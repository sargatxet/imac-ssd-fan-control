# AGENTS.md — Notes for AI agents

**[Español](AGENTS_ES.md) | [English](AGENTS.md)**

Operational context for the `fan_control` project. Read this before touching anything.

---

## Main rule

**Do not delete or modify files without the user's explicit approval.** This project writes to `sysfs` and drives real hardware: a wrong value can leave the fan stopped or at full speed.

Before changing anything, check the current state:

```bash
cat /sys/devices/platform/applesmc.768/fan2_manual
cat /sys/devices/platform/applesmc.768/fan2_output
cat /sys/devices/platform/applesmc.768/fan2_input
sudo crontab -l | tail -5
```

If cron is active (`*/2 * * * * control_fan.sh`), **any manual RPM change will be overwritten within ≤ 2 minutes**. Keep that in mind when validating tests.

---

## Environment

| Item | Value |
|---|---|
| Host | `imac` (the reference machine) |
| OS | Linux Mint 22.3 (Zena), kernel 6.8.0-147 |
| Driver | `applesmc`, device `applesmc.768` |
| sysfs path | `/sys/devices/platform/applesmc.768/` |
| User | the installing user (`$USER`); must be able to use `sudo` |
| Directory | `$INSTALL_DIR` — whatever the user picks (e.g. `$HOME/fan_control`) |
| Project | `$INSTALL_DIR/` — no absolute paths in the code (see `SCRIPT_DIR`) |
| Control log | `$INSTALL_DIR/control_fan.log` (max. 100 lines) |
| Cron | **root**, `*/2 * * * * /absolute/path/control_fan.sh` |

External requirements: `lm-sensors` (`/usr/bin/sensors`), `awk`, `bc`, `grep`, `sed`, `bash` ≥ 4. Conky for monitoring.

### Compatibility (important when proposing changes)

These scripts are **specific to Linux on Intel Apple hardware with `applesmc`**. They are NOT portable:

- **macOS / Windows**: no `sysfs`.
- **Apple Silicon (M1+)**: no `applesmc` or `coretemp`; there is no `fanN_manual`.
- **Non-Apple PC**: no `/sys/devices/platform/applesmc.*` (you would need `hwmon` + `pwm1_enable`).

Porting to another Mac requires checking two things: the device ID (`applesmc.768` belongs to this machine; `ls -d /sys/devices/platform/applesmc.*`) and the fan index (`cat .../fan*_label`: here `ODD`=fan1, `HDD`=fan2, `CPU`=fan3). The `sensors` chip names (`coretemp-isa-0000`, `applesmc-isa-0300`) and the `TG0H` sensor are also model-specific. Do not assume they will work on other hardware: verify first.

---

## Fan map (verified)

Mapping deduced by cross-checking `fanN_max` with the maximums published by `sensors`:

| sysfs | `sensors` | Min | Max | Controlled by the project |
|---|---|---|---|---|
| `fan1` | `ODD` | 1000 | 4350 | No |
| `fan2` | `HDD` | 1100 | 6300 | **Yes** |
| `fan3` | `CPU` | 1200 | 2600 | No |

Writing to `fanN_output` without `fanN_manual = 1` has no effect. Always: `echo 1 > fan2_manual` **before** `echo <rpm> > fan2_output`.

---

## Output contract of the temperature scripts

`cpu.sh` and `gpu.sh` return **a single number, with one decimal, no units, no sign and no trailing newline**, using `.` as the decimal separator (hence `LC_ALL=C`):

```
$ ./cpu.sh   ->  41.5
$ ./gpu.sh   ->  52.8
```

On failure they return `100` (an integer, no decimal).

`control_fan.sh` consumes them through `parse_temp()`, which **tolerates** integers, decimal comma, `+` sign, unit suffix (`°C`, `C`, `°`) and spaces. Verified:

```
47.0 -> 47.0    45 -> 45      52,8 -> 52.8    +52.8°C -> 52.8
" 41.5" -> 41.5   N/D -> (empty)   -127.0 -> (empty)   12abc -> (empty)
```

An empty result is treated as a **sensor failure** and replaced with `100` °C, which drives the fan to `fan2_max` (fail-safe: noise is better than overheating).

**Any change to these scripts must preserve that contract**, because Conky also consumes it directly.

### `sensors` pitfalls already solved

- **Locale**: without `LC_ALL=C`, `printf "%.1f"` emits `52,8` in a Spanish locale and breaks downstream parsing.
- **Value field**: `TG0H:  +52.8°C` → the value is in `$2` (no space before `:`). However `HDD :  3440 RPM` → the value is in `$3`, because the space before `:` shifts the columns. This bug was found in production (`awk '$1=="HDD:"'` never matches; you must compare `$1=="HDD"`).
- **Numeric cleanup**: `gsub(/[^0-9.+-]/, "", value)` removes the leading `+` and the trailing `C`.
- **Missing sensors**: `TG0D` and `TG0p` return `-127.0` on this machine. Do not use them.

---

## `control_fan.sh` logic (summary)

Modes (parsing `$1` up front, before touching hardware):

| Invocation | Mode | Log |
|---|---|---|
| no arguments | automatic by temperature | `(CPU: .., GPU: .., MAX: ..)` |
| `<RPM>` integer ≥ 0 | manual, clamped to `fan2_min`..`fan2_max` | `(manual)` |
| any other value | error, `exit 2`, hardware untouched | — |
| `-h` / `--help` | help | — |

```
MAX_TEMP = max(parse_temp(cpu.sh), parse_temp(gpu.sh))   # empty -> 100
RPM = 1100                        if MAX_TEMP < 30
RPM = 6300                        if MAX_TEMP > 80
RPM = 1100 + (MAX_TEMP-30)*104    otherwise
```

Verified cases: `53.5 -> 3544`, `52.8 -> 3471`, `79.9 -> 6289`, `0 -> 1100`, `200 -> 6300`, sensor failure -> `6300`.

The limits are **not hardcoded**: they are read from `fan2_min` and `fan2_max` on every run (the 1100/6300 constants only appear in the formula as a result of that read). Truncation is downwards (`bc scale=0`), not rounding.

It only writes if `TARGET_RPM != fan2_output`, and records the change in `control_fan.log`. With no change it prints `Fan speed already at target: N RPM`.

---

## Mistakes already made (do not repeat them)

1. **Calling `cpu.sh`/`gpu.sh` without the executable bit** → silent `Permission denied` and fallback to defaults. Every `.sh` must be `chmod +x`.
2. **`printf "%.0f"` over the output of `bc -l`** → `invalid number` error, because `bc` returns `2951.20000000000000000000`; either pass a valid argument to `printf` or truncate with `bc scale=0`. `bc` is what is used now.
3. **Using `2>/dev/null || retry`** instead of fixing the root cause → the failure is masked.
4. **Running `control_fan.sh` without `sudo`** → `fan2_manual: Permission denied` and the RPM does not change.
5. **Editing `.conkyrc` without restarting Conky** → changes are not visible. `killall conky; nohup conky >/dev/null 2>&1 &`.
6. **Validating `control_fan.sh` by running it against real hardware** → cron overwrites the result within ≤ 2 min and `control_fan.log` gets polluted. To test the logic, copy the project to a temp dir and stub `cpu.sh`/`gpu.sh` (see below).
7. **Passing an RPM with a leading zero without `10#`** → `0800` would be interpreted as octal (`0`). The script uses `MANUAL_RPM=$((10#$1))`.
8. **Writing to `fan2_output` by hand instead of using `control_fan.sh <RPM>`** → it skips range validation and the log entry.

---

## Technical debt / pending improvements

Prioritised, none applied yet:

1. **Hysteresis** to avoid micro-adjustments from ±1 °C noise.
2. **Restore `fan2_manual = 0`** on a clean exit (EXIT trap or a `stop_fan_control.sh` script).
3. **Visible warning on sensor failure**: today the failure silently becomes `fan2_max`; a distinct error line in `control_fan.log` would be better.
4. **Non-persistent manual mode**: `control_fan.sh <RPM>` is reverted within ≤ 2 min by cron. To pin a speed stably you must comment out the crontab line or add a state file holding the desired mode.

> Note: a leftover `/root/fan_control/` directory exists (an old copy of `set_fan.sh` and its `done.log`) that nothing uses any more. **Do not touch it without the user's approval**; the user manages root's `crontab` by hand.

### Resolved on 2026-10-29

- ~~Fragile temperature parsing~~ → `parse_temp()` accepts integers, decimal comma, `+` and units.
- ~~Unsafe fallback on sensor failure~~ → now 100 °C → `fan2_max`.
- ~~`control_fan.log` rotation~~ → capped at `LOG_MAX_LINES=100` with `sed -i` (preserves owner/permissions).
- ~~Log path split under `/root/fan_control/`~~ → unified in `$INSTALL_DIR/`.
- ~~`set_fan.sh` truncated the log~~ → **`set_fan.sh` removed**; its role is covered by `control_fan.sh <RPM>` (append + 100-line trimming).

If you implement any of these, update `README.md` and `README_ES.md` (limitations and change history) in the same change.

---

## Verification commands

`$INSTALL_DIR` = the project directory (there are no absolute paths in the code).

```bash
# Syntax of every script
for f in "$INSTALL_DIR"/*.sh; do bash -n "$f" || echo "FAIL: $f"; done

# Output contract (must print a number with one decimal)
"$INSTALL_DIR/cpu.sh"; echo
"$INSTALL_DIR/gpu.sh"; echo

# Trace of the computation (uses real hardware)
sudo bash -x "$INSTALL_DIR/control_fan.sh" 2>&1 | grep -E 'MAX_TEMP|TARGET_RPM'

# Test bench: copy the project to /tmp and replace cpu.sh/gpu.sh with stubs.
# The script resolves SCRIPT_DIR from its own path, so it uses the stubs and its
# own control_fan.log. CAREFUL: sysfs is still the real one (the fan will move,
# clamped to 1100..6300).
T=$(mktemp -d)
cp "$INSTALL_DIR"/{cpu.sh,gpu.sh,control_fan.sh} "$T"/
printf '#!/bin/bash\necho 53.5\n' > "$T/cpu.sh"
printf '#!/bin/bash\necho 40.0\n' > "$T/gpu.sh"
sudo "$T/control_fan.sh"        # expected: 1100 + (53.5-30)*104 = 3544
rm -rf "$T"

# Real run (overwrites the value; cron will correct it)
sudo "$INSTALL_DIR/control_fan.sh"

# Check that cron runs
sudo crontab -l | tail -3
grep CRON /var/log/syslog | grep control_fan | tail -5
```

---

## Path portability (`SCRIPT_DIR`)

`control_fan.sh` **contains no absolute paths**: on startup it does

```bash
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/control_fan.log}"
```

and calls `"$SCRIPT_DIR/cpu.sh"` and `"$SCRIPT_DIR/gpu.sh"`. Consequences:

- The project can be moved/cloned into **any** directory without editing anything.
- It works when invoked by absolute path, relative path, or through a symlink from another `cwd`.
- `LOG_FILE` can be redirected through an environment variable (`LOG_FILE=/var/log/x.log sudo -E ...`).
- **Never** reintroduce `/home/something/...` in the code; if a path is needed, derive it from `$SCRIPT_DIR`.

---

## Conventions

- Documentation language: **Spanish** in `*_ES.md`, **English** in `README.md`/`AGENTS.md`. Code comments: English.
- **Never hardcode** the project directory in the scripts; use `$SCRIPT_DIR`.
- The **cron line** does need the **real absolute path** (cron expands neither `~` nor variables, and its `PATH`/`HOME` are not the user's).
- Cite file paths as `` `absolute/path` `` in replies.
- Before proposing a destructive change (deleting scripts, emptying `control_fan.log`, disabling cron), ask for approval.
