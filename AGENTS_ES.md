# AGENTS_ES.md — Notas para agentes de IA

**[Español](AGENTS_ES.md) | [English](AGENTS.md)**

Contexto operativo del proyecto `fan_control`. Léelo antes de tocar nada.

---

## Regla principal

**No borres ni modifiques archivos sin aprobación explícita del usuario.** Este proyecto escribe en `sysfs` y controla hardware real: un valor equivocado puede dejar el ventilador parado o al máximo.

Antes de cambiar algo, revisa el estado actual:

```bash
cat /sys/devices/platform/applesmc.768/fan2_manual
cat /sys/devices/platform/applesmc.768/fan2_output
cat /sys/devices/platform/applesmc.768/fan2_input
sudo crontab -l | tail -5
```

Si el cron está activo (`*/2 * * * * control_fan.sh`), **cualquier cambio manual de RPM será sobrescrito en ≤ 2 minutos**. Tenlo en cuenta al validar pruebas.

---

## Entorno

| Dato | Valor |
|---|---|
| Host | `imac` (el equipo de referencia) |
| SO | Linux Mint 22.3 (Zena), kernel 6.8.0-147 |
| Driver | `applesmc`, dispositivo `applesmc.768` |
| Ruta sysfs | `/sys/devices/platform/applesmc.768/` |
| Usuario | el usuario de la instalación (`$USER`); necesita poder usar `sudo` |
| Directorio | `$INSTALL_DIR` — el que elija el usuario (p. ej. `$HOME/fan_control`) |
| Proyecto | `$INSTALL_DIR/` — sin rutas absolutas en el código (ver `SCRIPT_DIR`) |
| Log de control | `$INSTALL_DIR/control_fan.log` (máx. 100 líneas) |
| Cron | **root**, `*/2 * * * * /ruta/absoluta/control_fan.sh` |

Requisitos externos: `lm-sensors` (`/usr/bin/sensors`), `awk`, `bc`, `grep`, `sed`, `bash` ≥ 4. Conky para la monitorización.

### Compatibilidad (importante al proponer cambios)

Estos scripts son **específicos de Linux sobre hardware Apple Intel con `applesmc`**. NO son portables:

- **macOS / Windows**: no existe `sysfs`.
- **Apple Silicon (M1+)**: no existe `applesmc` ni `coretemp`; no hay `fanN_manual`.
- **PC no-Apple**: no hay `/sys/devices/platform/applesmc.*` (habría que usar `hwmon` + `pwm1_enable`).

Portar a otro Mac exige revisar dos cosas: el ID del dispositivo (`applesmc.768` es propio de este equipo; `ls -d /sys/devices/platform/applesmc.*`) y el índice del ventilador (`cat .../fan*_label`: aquí `ODD`=fan1, `HDD`=fan2, `CPU`=fan3). Los nombres de chip de `sensors` (`coretemp-isa-0000`, `applesmc-isa-0300`) y el sensor `TG0H` también son específicos del modelo. No des por hecho que funcionarán en otro hardware: compruébalo antes.

---

## Mapa de ventiladores (verificado)

Correspondencia deducida cruzando `fanN_max` con los máximos que publica `sensors`:

| sysfs | `sensors` | Mín | Máx | Controlado por el proyecto |
|---|---|---|---|---|
| `fan1` | `ODD` | 1000 | 4350 | No |
| `fan2` | `HDD` | 1100 | 6300 | **Sí** |
| `fan3` | `CPU` | 1200 | 2600 | No |

Escribir en `fanN_output` sin `fanN_manual = 1` no tiene efecto. Siempre: `echo 1 > fan2_manual` **antes** de `echo <rpm> > fan2_output`.

---

## Contrato de salida de los scripts de temperatura

`cpu.sh` y `gpu.sh` devuelven **un único número, con un decimal, sin unidades ni signo y sin salto de línea**, con separador decimal `.` (por eso `LC_ALL=C`):

```
$ ./cpu.sh   ->  41.5
$ ./gpu.sh   ->  52.8
```

En caso de fallo devuelven `100` (entero, sin decimal).

`control_fan.sh` los consume a través de `parse_temp()`, que **tolera** enteros, coma decimal, signo `+`, sufijo de unidad (`°C`, `C`, `°`) y espacios. Verificado:

```
47.0 -> 47.0    45 -> 45      52,8 -> 52.8    +52.8°C -> 52.8
" 41.5" -> 41.5   N/D -> (vacío)   -127.0 -> (vacío)   12abc -> (vacío)
```

Un resultado vacío se interpreta como **fallo de sensor** y se sustituye por `100` °C, lo que lleva el ventilador a `fan2_max` (fallo seguro: mejor ruido que sobrecalentamiento).

**Cualquier cambio en estos scripts debe preservar ese contrato**, porque Conky también lo consume directamente.

### Trampas de `sensors` ya resueltas

- **Locale**: sin `LC_ALL=C`, `printf "%.1f"` emite `52,8` en locale español y rompe el parseo posterior.
- **Campo del valor**: `TG0H:  +52.8°C` → el valor está en `$2` (no hay espacio antes de `:`). En cambio `HDD :  3440 RPM` → el valor está en `$3`, porque el espacio antes de `:` desplaza las columnas. Este fallo se detectó en producción (`awk '$1=="HDD:"'` no coincide nunca; hay que comparar con `$1=="HDD"`).
- **Limpieza numérica**: `gsub(/[^0-9.+-]/, "", value)` elimina el `+` inicial y la `C` final.
- **Sensores ausentes**: `TG0D` y `TG0p` devuelven `-127.0` en este equipo. No usarlos.

---

## Lógica de `control_fan.sh` (resumen)

Modos (parseo de `$1` al principio, antes de tocar hardware):

| Invocación | Modo | Log |
|---|---|---|
| sin argumentos | auto por temperatura | `(CPU: .., GPU: .., MAX: ..)` |
| `<RPM>` entero ≥ 0 | manual, recortado a `fan2_min`..`fan2_max` | `(manual)` |
| otro valor | error, `exit 2`, sin tocar el ventilador | — |
| `-h` / `--help` | ayuda | — |

```
MAX_TEMP = max(parse_temp(cpu.sh), parse_temp(gpu.sh))   # vacío -> 100
RPM = 1100                        si MAX_TEMP < 30
RPM = 6300                        si MAX_TEMP > 80
RPM = 1100 + (MAX_TEMP-30)*104    en otro caso
```

Casos verificados: `53.5 -> 3544`, `52.8 -> 3471`, `79.9 -> 6289`, `0 -> 1100`, `200 -> 6300`, fallo de sensores -> `6300`.

Los límites **no están hardcodeados**: se leen de `fan2_min` y `fan2_max` en cada ejecución (las constantes 1100/6300 solo aparecen en la fórmula como resultado de esa lectura). El truncado es a la baja (`bc scale=0`), no redondeo.

Solo escribe si `TARGET_RPM != fan2_output`, y registra en `control_fan.log`. Si no hay cambio, imprime `Fan speed already at target: N RPM`.

---

## Errores ya cometidos (no repetirlos)

1. **Llamar a `cpu.sh`/`gpu.sh` sin permiso de ejecución** → `Permiso denegado` silencioso y caída a los valores por defecto. Todos los `.sh` deben ser `chmod +x`.
2. **`printf "%.0f"` sobre la salida de `bc -l`** → error `número no válido` porque `bc` devuelve `2951.20000000000000000000`; con `printf` hay que usar `%.0f` y un argumento válido, o truncar con `bc scale=0`. Actualmente se usa `bc`.
3. **Usar `2>/dev/null || reintento`** en lugar de corregir la causa raíz → el fallo se enmascara.
4. **Ejecutar `control_fan.sh` sin `sudo`** → `fan2_manual: Permiso denegado` y el RPM no cambia.
5. **Editar `.conkyrc` sin reiniciar Conky** → los cambios no se ven. `killall conky; nohup conky >/dev/null 2>&1 &`.
6. **Validar `control_fan.sh` ejecutándolo contra el hardware real** → el cron sobrescribe el resultado en ≤ 2 min y se ensucia `control_fan.log`. Para probar la lógica, sustituir las rutas de `cpu.sh`/`gpu.sh`, de `/sys/devices/platform/applesmc.768/` y del log por stubs en un directorio temporal (ver más abajo).
7. **Pasar un RPM con cero inicial sin `10#`** → `config 0800` se interpretaría como octal (`0`). El script usa `MANUAL_RPM=$((10#$1))`.
8. **Escribir a mano en `fan2_output` en lugar de usar `control_fan.sh <RPM>`** → se salta la validación de rango y el registro en el log.

---

## Deuda técnica / mejoras pendientes

Priorizadas, ninguna aplicada todavía:

1. **Histéresis** para evitar micro-ajustes por ruido de ±1 °C.
2. **Restaurar `fan2_manual = 0`** en una salida limpia (trap EXIT o script `stop_fan_control.sh`).
3. **Aviso visible ante fallo de sensores**: hoy el fallo se traduce silenciosamente en `fan2_max`; convendría loguear una línea de error diferenciada en `control_fan.log`.
4. **Modo manual no persistente**: `control_fan.sh <RPM>` se revierte en ≤ 2 min por el cron. Si se quiere fijar una velocidad de forma estable hay que comentar la línea del crontab o añadir un fichero de estado con el modo deseado.

> Nota: existe un directorio residual `/root/fan_control/` (copia antigua de `set_fan.sh` y su `done.log`) que ya no usa nada. **No tocar sin aprobación del usuario**; el usuario gestiona el `crontab` de root a mano.

### Resuelto el 2026-10-29

- ~~Parsing frágil de temperaturas~~ → `parse_temp()` acepta enteros, coma decimal, `+` y unidades.
- ~~Fallback inseguro ante fallo de sensores~~ → ahora 100 °C → `fan2_max`.
- ~~Rotación de `control_fan.log`~~ → acotado a `LOG_MAX_LINES=100` con `sed -i` (conserva owner/permisos).
- ~~Ruta del log partida en `/root/fan_control/`~~ → unificada en `$INSTALL_DIR/`.
- ~~`set_fan.sh` truncaba el log~~ → **`set_fan.sh` eliminado**; su función la cubre `control_fan.sh <RPM>` (append + recorte de 100 líneas).

Si implementas alguna, actualiza `README_ES.md` y `README.md` (secciones "Limitaciones conocidas" / "Known limitations" e historial) en el mismo cambio.

---

## Comandos de verificación

`$INSTALL_DIR` = directorio del proyecto (no hay rutas absolutas en el código).

```bash
# Sintaxis de todos los scripts
for f in "$INSTALL_DIR"/*.sh; do bash -n "$f" || echo "FALLO: $f"; done

# Contrato de salida (debe imprimir un número con un decimal)
"$INSTALL_DIR/cpu.sh"; echo
"$INSTALL_DIR/gpu.sh"; echo

# Traza del cálculo (usa el hardware real)
sudo bash -x "$INSTALL_DIR/control_fan.sh" 2>&1 | grep -E 'MAX_TEMP|TARGET_RPM'

# Banco de pruebas: copia el proyecto a /tmp y sustituye cpu.sh/gpu.sh por stubs.
# El script resuelve SCRIPT_DIR desde su propia ruta, así que usa los stubs y su
# propio control_fan.log. OJO: sysfs sigue siendo el real (el ventilador se mueve,
# acotado a 1100..6300).
T=$(mktemp -d)
cp "$INSTALL_DIR"/{cpu.sh,gpu.sh,control_fan.sh} "$T"/
printf '#!/bin/bash\necho 53.5\n' > "$T/cpu.sh"
printf '#!/bin/bash\necho 40.0\n' > "$T/gpu.sh"
sudo "$T/control_fan.sh"        # esperado: 1100 + (53.5-30)*104 = 3544
rm -rf "$T"

# Prueba real (sobrescribe el valor; el cron lo corregirá)
sudo "$INSTALL_DIR/control_fan.sh"

# Comprobar que el cron se ejecuta
sudo crontab -l | tail -3
grep CRON /var/log/syslog | grep control_fan | tail -5
```

---

## Portabilidad de rutas (`SCRIPT_DIR`)

`control_fan.sh` **no contiene rutas absolutas**: al arrancar hace

```bash
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/control_fan.log}"
```

y llama a `"$SCRIPT_DIR/cpu.sh"` y `"$SCRIPT_DIR/gpu.sh"`. Consecuencias:

- El proyecto se puede mover/clonar en **cualquier** directorio sin editar nada.
- Funciona invocado por ruta absoluta, relativa o vía symlink desde otro `cwd`.
- `LOG_FILE` se puede redirigir con una variable de entorno (`LOG_FILE=/var/log/x.log sudo -E ...`).
- **No** volver a introducir `/home/algo/...` en el código; si hace falta una ruta, derivarla de `$SCRIPT_DIR`.

---

## Convenciones

- Idioma de la documentación: **español** en `*_ES.md`, **inglés** en `README.md`/`AGENTS.md`. Comentarios de código: inglés.
- **Nunca hardcodear** el directorio del proyecto en los scripts; usar `$SCRIPT_DIR`.
- En la **línea de cron** sí va la ruta **absoluta** real (`cron` no expande `~` ni variables, y su `PATH`/`HOME` no son los del usuario).
- Citar rutas de fichero como `` `ruta/absoluta` `` en las respuestas.
- Antes de proponer un cambio destructivo (borrar scripts, vaciar `control_fan.log`, desactivar el cron), pedir aprobación.
