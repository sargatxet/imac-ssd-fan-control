# fan_control

Control de la velocidad del ventilador **fan2 (HDD)** de un iMac, ajustándola de forma proporcional a la temperatura de CPU y GPU.

- **Hardware**: Apple iMac (Linux Mint 22.3 "Zena", kernel 6.8.0, hostname `imac`)
- **Sistema operativo**: **solo Linux** sobre Mac con Intel (driver `applesmc`). No funciona en macOS, Windows, Apple Silicon ni PC → ver [Sistemas operativos y hardware compatibles](#sistemas-operativos-y-hardware-compatibles)
- **Driver**: `applesmc` → `/sys/devices/platform/applesmc.768/`
- **Ventilador gestionado**: `fan2` (etiqueta `HDD`)
- **Herramienta de lectura**: `lm-sensors` (`sensors`)

---

## Motivación: por qué existe este proyecto

A este iMac **se le ha sustituido el disco duro original (HDD) por un SSD**. Ese cambio afecta al control automático del ventilador que refrigera el disco (`fan2`, etiqueta `HDD`): el SMC de Apple regula esa velocidad a partir de la **temperatura del disco**, y al cambiar el disco por un SSD ese sensor deja de dar una lectura utilizable por el firmware. Sin esa realimentación, el control automático pierde la referencia y el ventilador **queda fijo a tope** (ruido y desgaste innecesarios) en lugar de regularse según la carga real.

Este proyecto corrige ese problema en dos pasos:

1. **Tomar el control del ventilador**: se activa el modo manual del SMC (`fan2_manual = 1`) para que el firmware deje de gobernar `fan2` a partir del sensor del disco.
2. **Sustituir la realimentación perdida**: como el sensor del HDD ya no es fiable, se usan las temperaturas que **sí** funcionan y son una buena aproximación térmica del interior del chasis:
   - **CPU**: media de los cores vía `coretemp` (`cpu.sh`)
   - **GPU**: sensor `TG0H` de `applesmc` (`gpu.sh`)

El RPM se calcula de forma proporcional a la **mayor** de esas dos temperaturas, respetando los límites reales del ventilador (1100–6300 RPM), de modo que el ventilador sigue regulándose automáticamente y en silencio cuando el equipo está frío, en vez de estar siempre al máximo.

> Nota: el ventilador `fan2` ya no refrigera un disco mecánico, pero sigue siendo el extractor del chasis, así que las temperaturas de CPU/GPU son una referencia válida para decidir cuánto aire mover.

---

## Estado actual

| Elemento | Valor |
|---|---|
| Ventilador controlado | `fan2` (`HDD`) |
| RPM mínimo (hardware) | 1100 |
| RPM máximo (hardware) | 6300 |
| Modo manual | `fan2_manual = 1` |
| Programación | `crontab` de **root**, cada **2 minutos** |
| Comando programado | `*/2 * * * * /home/sargatxet/fan_control/control_fan.sh` |
| Monitorización | Conky (`~/.conkyrc`) |

---

## Estructura

```
/home/sargatxet/fan_control/
├── cpu.sh          # Temperatura media de los cores de CPU -> "41.5"
├── gpu.sh          # Temperatura del sensor TG0H (GPU)   -> "52.8"
├── control_fan.sh  # Control por temperatura + modo manual opcional (cron)
├── control_fan.log # Registro de cambios de RPM (máx. 100 líneas)
├── LICENSE         # MIT © 2026 Toni Ramiro
├── README.md       # Este documento
└── AGENTS.md       # Notas para agentes de IA / mantenimiento
```

Todos los scripts deben tener permiso de ejecución (`chmod +x *.sh`).

---

## Límites del ventilador

Obtenidos directamente de `sysfs` (valores que expone el SMC de Apple):

| Fan | Etiqueta (`sensors`) | Mín. RPM | Máx. RPM |
|---|---|---|---|
| `fan1` | `ODD`  | 1000 | 4350 |
| **`fan2`** | **`HDD`** | **1100** | **6300** |
| `fan3` | `CPU`  | 1200 | 2600 |

La correspondencia se verificó cruzando los máximos de `fanN_max` con los publicados por `sensors applesmc-isa-0300`.

Ficheros relevantes en `/sys/devices/platform/applesmc.768/`:

| Fichero | Permiso | Descripción |
|---|---|---|
| `fan2_min` | `r--` | RPM mínimo soportado |
| `fan2_max` | `r--` | RPM máximo soportado |
| `fan2_input` | `r--` | RPM reales medidos |
| `fan2_output` | `rw-` | RPM objetivo (requiere root) |
| `fan2_manual` | `rw-` | `1` = control manual, `0` = control del SMC |
| `fan2_safe` | `r--` | Valor de referencia del SMC |

> El límite de 6300 RPM fue verificado empíricamente: se fijó `fan2_output = 6300` y el ventilador respondió alcanzando ese valor, sin errores; después se restauró.

---

## Sistemas operativos y hardware compatibles

### Resumen

| Plataforma | ¿Funciona? | Motivo |
|---|---|---|
| **Linux en Mac con Intel** (iMac/MacBook/Mac mini con `applesmc`) | ✅ **Sí** — es el objetivo del proyecto | Driver `applesmc` en el kernel + `coretemp` |
| Linux en Mac con **Apple Silicon** (M1/M2/M3…) | ❌ No | No existe `applesmc` ni `coretemp`; el control de ventiladores es otro (`macsmc-*`, sin `fanN_manual` equivalente) |
| Linux en **PC/no-Apple** | ❌ No | No hay dispositivo `applesmc.*`; habría que reescribir las rutas (`hwmon`, `pwm1_enable`…) |
| **macOS** | ❌ No | `sysfs` no existe; en macOS se usan `smc`/`smcFanControl` y APIs IOKit |
| **Windows** | ❌ No | Sin `sysfs`, sin `applesmc`, sin `sensors` |
| **FreeBSD/OpenBSD** | ⚠️ No probado | Existen drivers tipo `asmc`, pero ni las rutas ni `sensors` coinciden |

**En una frase:** los scripts son **específicos de Linux ejecutándose sobre hardware Apple Intel**. Están escritos para un **iMac** concreto y no son portables tal cual a otro sistema operativo.

### Entorno exacto en el que está probado

| Componente | Versión / valor |
|---|---|
| Distribución | Linux Mint 22.3 "Zena" (base Ubuntu 24.04) |
| Kernel | `6.8.0-147-generic` |
| Arquitectura | `x86_64` (Intel) |
| Driver SMC | `applesmc` (módulo del kernel) |
| Driver CPU | `coretemp` |
| Dispositivo | `/sys/devices/platform/applesmc.768` |
| `lm-sensors` | 3.6.0 (libsensors 3.6.0) |
| `bash` | 5.2.21 |
| Monitorización | Conky (opcional) |

### Dependencias de software (Linux)

| Dependencia | Uso | Paquete típico (Debian/Ubuntu/Mint) |
|---|---|---|
| `applesmc` | Acceso al SMC (ventiladores y sensores) | incluido en el kernel |
| `coretemp` | Temperatura de los cores Intel | incluido en el kernel |
| `sensors` | Lectura de temperaturas y RPM | `lm-sensors` |
| `bash` ≥ 4 | Intérprete (usa `=~`, `$((10#…))`, arrays) | `bash` |
| `awk` | Parseo de `sensors` en `cpu.sh`/`gpu.sh` | `mawk`/`gawk` |
| `bc` | Cálculo del RPM objetivo | `bc` |
| `sed`, `grep`, `tr`, `wc`, `date` | Utilidades básicas | `coreutils`, `sed`, `grep` |
| `cron` | Ejecución periódica (o un timer de systemd) | `cron` |
| `conky` | Panel opcional | `conky-all` |
| `sudo` | Escritura en `sysfs` | `sudo` |

Instalación mínima en Debian/Ubuntu/Mint:

```bash
sudo apt install lm-sensors bc
sudo sensors-detect --auto    # habilita applesmc/coretemp si no están cargados
```

### Si lo portas a otro Mac: dos cosas que cambian

1. **La ruta del dispositivo**: `applesmc.768` es el ID de plataforma de *este* equipo. En otro Mac puede ser `applesmc.0`, `applesmc.256`… Compruébalo con:
   ```bash
   ls -d /sys/devices/platform/applesmc.*
   ```
2. **El índice del ventilador**: aquí `fan2` es el del HDD (`ODD`=fan1, `HDD`=fan2, `CPU`=fan3), pero el orden **no tiene por qué coincidir** en otro modelo. Verifícalo con:
   ```bash
   cat /sys/devices/platform/applesmc.*/fan*_label
   ```
   y ajusta `SMC=` en `control_fan.sh` y los nombres de script en `cpu.sh`/`gpu.sh` (`coretemp-isa-0000`, `applesmc-isa-0300` también varían).

Los nombres de chip de `sensors` (`coretemp-isa-0000`, `applesmc-isa-0300`) y los sensores concretos usados (`TG0H` para GPU) **son propios del modelo**; en otro iMac pueden cambiar de nombre o no existir.

---

## Uso

### Control automático (recomendado)

```bash
sudo /home/sargatxet/fan_control/control_fan.sh
```

Requiere `root` porque escribe en `fan2_manual` y `fan2_output`.
Cron ya lo ejecuta como root cada 2 minutos, por lo que **no** hay que añadir `sudo` dentro de la línea de crontab.

### Control manual a RPM fijo

```bash
sudo /home/sargatxet/fan_control/control_fan.sh 4000    # fuerza 4000 RPM (se recorta a 1100..6300)
sudo /home/sargatxet/fan_control/control_fan.sh         # sin argumento -> modo automático
sudo /home/sargatxet/fan_control/control_fan.sh -h      # ayuda
```

En modo manual **no se leen los sensores**. Si el valor pedido cae fuera de `fan2_min`..`fan2_max` se avisa por `stderr` y se recorta al límite correspondiente. Un argumento no numérico devuelve código de salida `2` sin tocar el ventilador. El log registra `(manual)` en lugar de las temperaturas.

> El cron ejecuta el script **sin argumentos**, así que cualquier valor forzado a mano se sustituye por el automático en ≤ 2 minutos.

### Devolver el control al SMC (automático de Apple)

```bash
echo 0 | sudo tee /sys/devices/platform/applesmc.768/fan2_manual
```

Esto desactiva el modo manual y el ventilador vuelve a la curva gestionada por el firmware.
Nota: el cron de 2 minutos volverá a activar el modo manual en la siguiente pasada; descoméntalo o desactívalo si quieres ceder el control de forma permanente.

### Lectura de temperaturas

```bash
/home/sargatxet/fan_control/cpu.sh   # -> 41.5   (media de todos los cores, 1 decimal)
/home/sargatxet/fan_control/gpu.sh   # -> 52.8   (sensor TG0H, 1 decimal)
```

Ambos scripts devuelven un número con **un decimal, sin unidades y sin signo**, listo para ser consumido por `awk`/`bc`. En caso de fallo devuelven `100`.

---

## Lógica de `control_fan.sh`

### Argumentos

| Invocación | Modo | Descripción |
|---|---|---|
| `control_fan.sh` | auto | RPM proporcional a `max(CPU, GPU)` (lo que ejecuta el cron) |
| `control_fan.sh <RPM>` | manual | Fuerza ese RPM, recortado a `fan2_min`..`fan2_max`; no lee sensores |
| `control_fan.sh -h` | — | Ayuda |

Salida: `0` si todo va bien, `2` si el argumento no es un entero no negativo (no toca el hardware).

### Algoritmo (modo automático)

1. Lee `cpu.sh` y `gpu.sh`.
2. Extrae la parte numérica y toma el **máximo** de ambas temperaturas (`MAX_TEMP`).
3. Lee `fan2_min` y `fan2_max` de `sysfs` (no están hardcodeados; se adaptan al hardware).
4. Calcula el RPM objetivo:

```
si MAX_TEMP < 30 °C   -> RPM = fan2_min        (1100)
si MAX_TEMP > 80 °C   -> RPM = fan2_max        (6300)
si no                 -> interpolación lineal entre (30 °C -> 1100) y (80 °C -> 6300)
```

Fórmula de la zona lineal:

```
RPM = 1100 + ((MAX_TEMP - 30) / (80 - 30)) * (6300 - 1100)
RPM = 1100 + (MAX_TEMP - 30) * 104
```

Ejemplos: 40 °C → 2140 · 50 °C → 3180 · 60 °C → 4220 · 70 °C → 5260.

5. Trunca a entero (`bc scale=0`, trunca hacia cero; no redondea).
6. Si el objetivo difiere de `fan2_output`, activa `fan2_manual = 1`, escribe el nuevo `fan2_output` y registra la línea en `control_fan.log`.

### Formato de `control_fan.log`

El log está **acotado a 100 líneas**: en cada ejecución, si el fichero supera ese tamaño se eliminan las líneas más antiguas (`sed -i "1,Nd"`, que conserva inodo, propietario y permisos). Crece por abajo y se recorta por arriba.

```

2026-10-29 07:44:01 - 3471 -> 3492 (CPU: 44.5°C, GPU: 53.0°C, MAX: 53.0°C)
```

Primera línea histórica (`2547 -> 3600`) proviene del antiguo `set_fan.sh`, ya eliminado, y no sigue el formato con fecha.

Las entradas en modo manual no llevan temperaturas:

```
2026-10-29 08:05:01 - 3720 -> 6300 (manual)
2026-10-29 08:05:01 - 6300 -> 3720 (CPU: 51.0°C, GPU: 55.2°C, MAX: 55.2°C)
```

Parámetros en `control_fan.sh`:

```bash
LOG_FILE=/home/sargatxet/fan_control/control_fan.log
LOG_MAX_LINES=100
```

El recorte se aplica **siempre**, incluso si no ha habido cambio de RPM en esa ejecución, de modo que el límite se restablece aunque el fichero se haya desbordado por otra vía.

---

## Programación (cron)

`sudo crontab -e`:

```cron
*/2 * * * * /home/sargatxet/fan_control/control_fan.sh
```

Razonamiento del intervalo:

| Intervalo | Valoración |
|---|---|
| 30 s | Reacción más rápida; útil en cargas muy variables (compilación, renderizado) |
| **2 min** | **Elegido**: compromiso entre reactividad y carga del sistema; fan2 es un ventilador de chasis/HDD con inercia térmica alta |
| 5 min | Demasiado lento ante subidas sostenidas de temperatura |

No se ha implementado **histéresis**: el script solo actúa si el RPM objetivo difiere del actual. Como el objetivo se trunca a entero, pequeños cambios de temperatura producen cambios de ~104 RPM, lo que unido al intervalo de 2 minutos evita oscilaciones rápidas.

---

## Monitorización con Conky

En `~/.conkyrc` (`conky.text`):

```
CPU (promedio):    ${execi 120 sensors coretemp-isa-0000 | LC_ALL=C awk '/^Core [0-9]+:/ { value=$3; gsub(/[^0-9.+-]/, "", value); sum += value; n++ } END { if (n) printf "%.1f °C", sum/n; else printf "N/D" }'}
GPU (sensor TG0H): ${execi 120 sensors applesmc-isa-0300 | LC_ALL=C awk '$1 == "TG0H:" { value=$2; gsub(/[^0-9.+-]/, "", value); printf "%.1f °C", value; found=1 } END { if (!found) printf "N/D" }'}
FAN (HDD, fan2):   ${execi 120 sensors applesmc-isa-0300 | awk '$1 == "HDD" { printf "%s RPM", $3; found=1 } END { if (!found) printf "N/D" }'}
```

Detalles:

- CPU y GPU se muestran con **el mismo formato**: `%.1f °C`.
- `LC_ALL=C` es imprescindible para que el separador decimal sea `.` y coincida con lo que esperan `grep`/`bc` (con locale `es_ES` `printf` emite `,`).
- En el caso de `HDD` el campo es `$3`, porque `sensors` imprime `HDD :   3440 RPM` (hay un espacio antes de los `:`), mientras que `TG0H:` no lo tiene y su valor está en `$2`.
- Se muestra el RPM **real** (`fan2_input`, redondeado a la baja por `sensors`), no el objetivo (`fan2_output`), por lo que puede diferir ligeramente del valor escrito por el script.
- `execi 120` y `update_interval = 120` son coherentes entre sí.

Recargar Conky tras editar la configuración:

```bash
killall conky; nohup conky >/dev/null 2>&1 &
```

---

## Diagnóstico rápido

```bash
# Temperaturas y RPM actuales
sensors coretemp-isa-0000
sensors applesmc-isa-0300

# Estado del control
cat /sys/devices/platform/applesmc.768/fan2_manual    # 1 = manual
cat /sys/devices/platform/applesmc.768/fan2_output    # objetivo
cat /sys/devices/platform/applesmc.768/fan2_input     # real

# ¿Está corriendo el cron?
sudo crontab -l
grep CRON /var/log/syslog | tail -20
```

### Prueba manual de límites

```bash
sudo /home/sargatxet/fan_control/control_fan.sh 6300   # máximo
sudo /home/sargatxet/fan_control/control_fan.sh 1100   # mínimo
# (el cron restaurará un valor proporcional a la temperatura en <= 2 min)
```

---

## Limitaciones conocidas

1. **Sin histéresis ni rampa suavizada**: los cambios son escalonados de ~104 RPM.
2. **Ajustes manuales efímeros**: `control_fan.sh <RPM>` fuerza una velocidad, pero el cron la sobrescribe en ≤ 2 minutos. Para mantener un valor fijo hay que comentar la línea del crontab.
3. **`fan2_manual` no se restaura nunca a `0`** automáticamente: el control manual persiste incluso si se desinstala el cron.
4. **Colisión potencial**: la antigua línea de cron `*/1 * * * * /root/fan_control/set_fan.sh 3600` del `crontab` de root sigue **comentada**; si se reactivara, competiría con `control_fan.sh`.
5. **Fallo de sensores = máxima ventilación**: si `cpu.sh`/`gpu.sh` devuelven algo no numérico, el script asume 100 °C y lleva el ventilador a `fan2_max`. Es la opción segura frente al sobrecalentamiento, pero implica ruido máximo en lugar de un aviso de error.

### Parsing de temperaturas (resuelto el 2026-10-29)

`parse_temp()` acepta todas estas formas y devuelve un número con `.` como separador:

| Entrada | Resultado |
|---|---|
| `47.0`, `45`, `0`, `105.0` | `47.0`, `45`, `0`, `105.0` |
| `52,8` (coma decimal) | `52.8` |
| `+52.8`, `52.8 °C`, `+52.8°C`, `52.8°`, ` 41.5` | `52.8`, `52.8`, `52.8`, `52.8`, `41.5` |
| `N/D`, `` (vacío), `-127.0`, `abc`, `12abc` | vacío → fallback 100 °C → `fan2_max` |

---

## Historial de cambios

- **2026-10-29**
  - Investigados los límites de `fan2` vía `sysfs` (1100–6300 RPM); verificado el máximo empíricamente.
  - `gpu.sh` normalizado al mismo formato de salida que `cpu.sh` (`%.1f`, sin unidades, `LC_ALL=C`).
  - Añadido `control_fan.sh` con control proporcional CPU/GPU.
  - Permisos de ejecución aplicados a todos los scripts.
  - Programado en cron de root cada 2 minutos.
  - Conky: añadida línea de RPM de `fan2` y unificado el formato de GPU con CPU.
  - `control_fan.sh`: parsing de temperaturas robusto (`parse_temp`, acepta enteros, coma decimal, signo `+` y sufijo de unidad); el fallback por fallo de sensores pasa de 39.5/47.8 °C fijos a **100 °C → `fan2_max`** (fallo seguro).
  - `done.log` renombrado a **`control_fan.log`**; `set_fan.sh` pasa a escribir en la misma ruta (`/home/sargatxet/fan_control/control_fan.log`) en lugar de `/root/fan_control/`.
  - `control_fan.log` acotado a **100 líneas**: al añadir una nueva se descarta la más antigua.
  - **`set_fan.sh` eliminado**; su función la asume `control_fan.sh <RPM>` (parámetro opcional, con validación y recorte a los límites del hardware).
  - `README.md`: añadida la sección **Motivación** (sustitución del HDD por SSD y pérdida del sensor que regulaba `fan2`).
  - `README.md`: añadida la sección **Sistemas operativos y hardware compatibles** (Linux + Apple Intel + `applesmc`; no válido para macOS, Windows, Apple Silicon ni PC).
