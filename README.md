# fan_control

**[Español](README_ES.md) | [English](README.md)**

Controls the speed of the **fan2 (HDD)** fan on an iMac, scaling it proportionally to the CPU and GPU temperatures.

- **Hardware**: Apple iMac (Linux Mint 22.3 "Zena", kernel 6.8.0, hostname `imac`)
- **Operating system**: **Linux only**, running on an Intel Mac (driver `applesmc`). Does not work on macOS, Windows, Apple Silicon or generic PCs → see [Supported operating systems and hardware](#supported-operating-systems-and-hardware)
- **Driver**: `applesmc` → `/sys/devices/platform/applesmc.768/`
- **Managed fan**: `fan2` (label `HDD`)
- **Reading tool**: `lm-sensors` (`sensors`)

> **Path convention**: throughout this document, `$INSTALL_DIR` is **the directory where you install the project** (for example `$HOME/fan_control`). The scripts contain **no absolute paths**: `control_fan.sh` resolves `cpu.sh`, `gpu.sh` and the log file relative to its own location, so it can be installed anywhere without editing anything. See [Installation](#installation).

---

## Motivation: why this project exists

**The original hard disk drive (HDD) in this iMac has been replaced with an SSD.** That change breaks the automatic control of the fan that cools the drive (`fan2`, label `HDD`): Apple's SMC regulates that fan based on the **drive temperature**, and once the HDD is replaced by an SSD that sensor no longer provides a usable reading to the firmware. Without that feedback, automatic control loses its reference and the fan **sticks at full speed** (needless noise and wear) instead of regulating itself according to the actual load.

This project fixes that problem in two steps:

1. **Take over the fan**: manual mode on the SMC is enabled (`fan2_manual = 1`) so the firmware stops driving `fan2` from the drive sensor.
2. **Replace the lost feedback**: since the HDD sensor is no longer reliable, the project uses temperatures that **do** work and are a good thermal proxy for the inside of the chassis:
   - **CPU**: average of the cores through `coretemp` (`cpu.sh`)
   - **GPU**: `TG0H` sensor from `applesmc` (`gpu.sh`)

The RPM is computed proportionally to the **higher** of those two temperatures, respecting the fan's real limits (1100–6300 RPM), so the fan still regulates itself automatically and quietly when the machine is cool, instead of always running at maximum.

> Note: `fan2` no longer cools a mechanical drive, but it is still the case exhaust fan, so CPU/GPU temperatures are a valid reference for deciding how much air to move.

---

## Current status

| Item | Value |
|---|---|
| Managed fan | `fan2` (`HDD`) |
| Minimum RPM (hardware) | 1100 |
| Maximum RPM (hardware) | 6300 |
| Manual mode | `fan2_manual = 1` |
| Scheduling | **root** `crontab`, every **2 minutes** |
| Scheduled command | `*/2 * * * * /home/YOUR_USER/fan_control/control_fan.sh` (real absolute path) |
| Monitoring | Conky (`~/.conkyrc`) |

---

## Layout

```
$INSTALL_DIR/
├── cpu.sh          # Average CPU core temperature -> "41.5"
├── gpu.sh          # GPU sensor TG0H temperature   -> "52.8"
├── control_fan.sh  # Temperature control + optional manual mode (cron)
├── control_fan.log # Log of RPM changes (max. 100 lines, created at runtime)
├── LICENSE         # MIT © 2026 Toni Ramiro
├── README.md       # This document (English)
├── README_ES.md    # Spanish translation
├── AGENTS.md       # Notes for AI agents (English)
└── AGENTS_ES.md    # Notes for AI agents (Spanish)
```

All scripts must be executable (`chmod +x *.sh`).

---

## Fan limits

Read directly from `sysfs` (the values exposed by Apple's SMC):

| Fan | `sensors` label | Min RPM | Max RPM |
|---|---|---|---|
| `fan1` | `ODD`  | 1000 | 4350 |
| **`fan2`** | **`HDD`** | **1100** | **6300** |
| `fan3` | `CPU`  | 1200 | 2600 |

The mapping was verified by cross-checking each `fanN_max` with the maximums published by `sensors applesmc-isa-0300`.

Relevant files under `/sys/devices/platform/applesmc.768/`:

| File | Mode | Description |
|---|---|---|
| `fan2_min` | `r--` | Minimum supported RPM |
| `fan2_max` | `r--` | Maximum supported RPM |
| `fan2_input` | `r--` | Measured RPM |
| `fan2_output` | `rw-` | Target RPM (requires root) |
| `fan2_manual` | `rw-` | `1` = manual control, `0` = SMC control |
| `fan2_safe` | `r--` | SMC reference value |

> The 6300 RPM limit was verified empirically: `fan2_output` was set to `6300`, the fan reached that value without errors, and it was then restored.

---

## Supported operating systems and hardware

### Summary

| Platform | Works? | Reason |
|---|---|---|
| **Linux on an Intel Mac** (iMac/MacBook/Mac mini with `applesmc`) | ✅ **Yes** — this is the target | `applesmc` kernel driver + `coretemp` |
| Linux on **Apple Silicon** (M1/M2/M3…) | ❌ No | No `applesmc` or `coretemp`; fan control is different (`macsmc-*`, no `fanN_manual` equivalent) |
| Linux on **non-Apple PC** | ❌ No | No `applesmc.*` device; paths would have to be rewritten (`hwmon`, `pwm1_enable`…) |
| **macOS** | ❌ No | No `sysfs`; macOS uses `smc`/`smcFanControl` and IOKit APIs |
| **Windows** | ❌ No | No `sysfs`, no `applesmc`, no `sensors` |
| **FreeBSD/OpenBSD** | ⚠️ Untested | `asmc`-style drivers exist, but neither the paths nor `sensors` match |

**In one sentence:** these scripts are **specific to Linux running on Intel Apple hardware**. They were written for one particular **iMac** and are not portable as-is to another operating system.

### Exact environment it was tested on

| Component | Version / value |
|---|---|
| Distribution | Linux Mint 22.3 "Zena" (Ubuntu 24.04 base) |
| Kernel | `6.8.0-147-generic` |
| Architecture | `x86_64` (Intel) |
| SMC driver | `applesmc` (kernel module) |
| CPU driver | `coretemp` |
| Device | `/sys/devices/platform/applesmc.768` |
| `lm-sensors` | 3.6.0 (libsensors 3.6.0) |
| `bash` | 5.2.21 |
| Monitoring | Conky (optional) |

### Software dependencies (Linux)

| Dependency | Purpose | Typical package (Debian/Ubuntu/Mint) |
|---|---|---|
| `applesmc` | SMC access (fans and sensors) | kernel built-in |
| `coretemp` | Intel core temperatures | kernel built-in |
| `sensors` | Read temperatures and RPM | `lm-sensors` |
| `bash` ≥ 4 | Interpreter (uses `=~`, `$((10#…))`, arrays) | `bash` |
| `awk` | Parse `sensors` output in `cpu.sh`/`gpu.sh` | `mawk`/`gawk` |
| `bc` | Compute the target RPM | `bc` |
| `sed`, `grep`, `tr`, `wc`, `date` | Basic utilities | `coreutils`, `sed`, `grep` |
| `cron` | Periodic execution (or a systemd timer) | `cron` |
| `conky` | Optional panel | `conky-all` |
| `sudo` | Write to `sysfs` | `sudo` |

Minimal install on Debian/Ubuntu/Mint (details in [Installation](#installation)):

```bash
sudo apt install lm-sensors bc
sudo sensors-detect --auto    # enables applesmc/coretemp if they are not loaded
```

### Porting to another Mac: two things that change

1. **The device path**: `applesmc.768` is the platform ID of *this* machine. On another Mac it may be `applesmc.0`, `applesmc.256`… Check with:
   ```bash
   ls -d /sys/devices/platform/applesmc.*
   ```
2. **The fan index**: here `fan2` is the HDD fan (`ODD`=fan1, `HDD`=fan2, `CPU`=fan3), but the order **does not have to match** on another model. Verify with:
   ```bash
   cat /sys/devices/platform/applesmc.*/fan*_label
   ```
   and adjust `SMC=` in `control_fan.sh` and the chip names in `cpu.sh`/`gpu.sh` (`coretemp-isa-0000`, `applesmc-isa-0300` also vary).

The `sensors` chip names (`coretemp-isa-0000`, `applesmc-isa-0300`) and the specific sensors used (`TG0H` for GPU) **are model-specific**; on another iMac they may be named differently or not exist at all.

---

## Installation

Guide to installing the project on **your** machine. The examples use `$HOME/fan_control` as the destination; change it to whatever you prefer (`/opt/fan_control`, `~/scripts/fan`, …).

### Step 0 — Prerequisites

You need **Linux on an Intel Mac** with the `applesmc` driver (see [compatibility](#supported-operating-systems-and-hardware)). First of all, check that the hardware exposes the fans:

```bash
ls -d /sys/devices/platform/applesmc.*      # must exist
ls /sys/devices/platform/applesmc.*/fan*_label   # must list labels
```

If nothing appears, the driver is not loaded or the hardware is not supported:

```bash
sudo modprobe applesmc
lsmod | grep -E 'applesmc|coretemp'
```

### Step 1 — Install the required programs

| Program | Package (Debian/Ubuntu/Mint) | What for? |
|---|---|---|
| `sensors` | `lm-sensors` | Read temperatures and RPM |
| `bc` | `bc` | Compute the target RPM |
| `awk`, `sed`, `grep`, `tr`, `wc`, `date` | `mawk`, `sed`, `grep`, `coreutils` | Parsing and utilities |
| `bash` ≥ 4 | `bash` | Interpreter |
| `cron` | `cron` | Periodic execution |
| `git` | `git` | Only to clone the repository |
| `sudo` | `sudo` | Write to `sysfs` |

```bash
sudo apt update
sudo apt install -y lm-sensors bc git cron
```

On most installations `bash`, `awk`, `sed`, `grep` and `coreutils` are already present. Detect and load the sensor modules:

```bash
sudo sensors-detect --auto
sensors            # must show coretemp-isa-0000 and applesmc-isa-0300
```

If `sensors` does not show `applesmc-isa-0300`, go back to [Step 0](#step-0--prerequisites).

**Optional — Conky panel**:

```bash
sudo apt install -y conky-all
```

### Step 2 — Download the project

With git:

```bash
INSTALL_DIR="$HOME/fan_control"
git clone https://github.com/sargatxet/imac-ssd-fan-control.git "$INSTALL_DIR"
```

Or by copying the files (`cpu.sh`, `gpu.sh`, `control_fan.sh`) into `$INSTALL_DIR` with `scp`, a USB stick, etc.

### Step 3 — Execution permissions

```bash
cd "$INSTALL_DIR"
chmod +x cpu.sh gpu.sh control_fan.sh
```

### Step 4 — Verify without touching the fan

```bash
"$INSTALL_DIR/cpu.sh"; echo      # -> 41.5   (a number with one decimal)
"$INSTALL_DIR/gpu.sh"; echo      # -> 52.8
cat /sys/devices/platform/applesmc.768/fan2_min   # -> 1100
cat /sys/devices/platform/applesmc.768/fan2_max   # -> 6300
```

If the first two do not return a number, review the `sensors` chip names in `cpu.sh`/`gpu.sh` (they vary by model).

### Step 5 — First run

```bash
sudo "$INSTALL_DIR/control_fan.sh"
```

Expected output: `Setting fan2 speed: 3600 -> 3180 RPM (auto)` or `Fan speed already at target: N RPM (auto)`.

If it fails with `Permission denied`, it was run without `sudo`. The script **creates the log next to itself** (`$INSTALL_DIR/control_fan.log`); if it does not appear, check the write permissions of the directory. When created by cron (which runs as root) the file will be `root:root` with mode `644`: it can be read without problems, and the 100-line trimming still works because that also runs as root.

> From this point on the fan is in **manual mode**. To return control to the firmware: `echo 0 | sudo tee /sys/devices/platform/applesmc.768/fan2_manual`.

### Step 6 — Automate with cron

```bash
sudo crontab -e
```

Add **one** line, with the **real absolute path** (cron expands neither `~` nor `$VARIABLES`):

```cron
*/2 * * * * /home/YOUR_USER/fan_control/control_fan.sh
```

Get the path you must paste with:

```bash
cd "$INSTALL_DIR" && pwd -P
```

Verify that it was registered:

```bash
sudo crontab -l | grep control_fan
```

### Step 7 — Post-install diagnostics

```bash
sensors applesmc-isa-0300 | head -4            # ODD/HDD/CPU RPM
cat /sys/devices/platform/applesmc.768/fan2_manual   # 1 = manual control enabled
cat /sys/devices/platform/applesmc.768/fan2_output   # target RPM
cat /sys/devices/platform/applesmc.768/fan2_input    # measured RPM
tail -5 "$INSTALL_DIR/control_fan.log"         # history of changes
```

Two to four minutes after enabling cron, `control_fan.log` should contain new lines.

### Optional — Conky panel

Copy the `${execi …}` block from the [Conky monitoring](#conky-monitoring) section into `~/.conkyrc` and restart Conky:

```bash
killall conky; nohup conky >/dev/null 2>&1 &
```

### Uninstall

```bash
# 1. Remove the cron entry (sudo crontab -e and delete the line), then:
# 2. Give fan control back to the firmware
 echo 0 | sudo tee /sys/devices/platform/applesmc.768/fan2_manual
# 3. Delete the project
rm -rf "$INSTALL_DIR"
```

**Step 2 matters**: while `fan2_manual` is `1`, the SMC will not regulate the fan on its own.

---

## Usage

### Automatic control (recommended)

```bash
sudo $INSTALL_DIR/control_fan.sh
```

Requires `root` because it writes to `fan2_manual` and `fan2_output`.
Cron already runs it as root every 2 minutes, so **do not** add `sudo` inside the crontab line.

### Manual control at a fixed RPM

```bash
sudo $INSTALL_DIR/control_fan.sh 4000    # force 4000 RPM (clamped to 1100..6300)
sudo $INSTALL_DIR/control_fan.sh         # no argument -> automatic mode
sudo $INSTALL_DIR/control_fan.sh -h      # help
```

In manual mode **the sensors are not read at all**. If the requested value falls outside `fan2_min`..`fan2_max`, a warning is printed to `stderr` and the value is clamped to the corresponding limit. A non-numeric argument returns exit code `2` without touching the fan. The log records `(manual)` instead of the temperatures.

> Cron runs the script **without arguments**, so any value forced by hand is replaced by the automatic one within ≤ 2 minutes.

### Give control back to the SMC (Apple's automatic mode)

```bash
echo 0 | sudo tee /sys/devices/platform/applesmc.768/fan2_manual
```

This disables manual mode and the fan returns to the curve managed by the firmware.
Note: the 2-minute cron job will re-enable manual mode on its next run; disable it if you want to hand over control permanently.

### Reading temperatures

```bash
$INSTALL_DIR/cpu.sh   # -> 41.5   (average of all cores, 1 decimal)
$INSTALL_DIR/gpu.sh   # -> 52.8   (TG0H sensor, 1 decimal)
```

Both scripts return a number with **one decimal, no units and no sign**, ready to be consumed by `awk`/`bc`. On failure they return `100`.

---

## How `control_fan.sh` works

### Arguments

| Invocation | Mode | Description |
|---|---|---|
| `control_fan.sh` | auto | RPM proportional to `max(CPU, GPU)` (what cron runs) |
| `control_fan.sh <RPM>` | manual | Forces that RPM, clamped to `fan2_min`..`fan2_max`; does not read sensors |
| `control_fan.sh -h` | — | Help |

Exit status: `0` on success, `2` if the argument is not a non-negative integer (hardware untouched).

### Algorithm (automatic mode)

1. Reads `cpu.sh` and `gpu.sh`.
2. Extracts the numeric part and takes the **maximum** of both temperatures (`MAX_TEMP`).
3. Reads `fan2_min` and `fan2_max` from `sysfs` (they are not hardcoded; they adapt to the hardware).
4. Computes the target RPM:

```
if MAX_TEMP < 30 °C   -> RPM = fan2_min        (1100)
if MAX_TEMP > 80 °C   -> RPM = fan2_max        (6300)
otherwise             -> linear interpolation between (30 °C -> 1100) and (80 °C -> 6300)
```

Formula for the linear range:

```
RPM = 1100 + ((MAX_TEMP - 30) / (80 - 30)) * (6300 - 1100)
RPM = 1100 + (MAX_TEMP - 30) * 104
```

Examples: 40 °C → 2140 · 50 °C → 3180 · 60 °C → 4220 · 70 °C → 5260.

5. Truncates to an integer (`bc scale=0`, truncates towards zero; it does not round).
6. If the target differs from `fan2_output`, it enables `fan2_manual = 1`, writes the new `fan2_output` and appends the line to `control_fan.log`.

### `control_fan.log` format

The log is **capped at 100 lines**: on every run, if the file exceeds that size the oldest lines are removed (`sed -i "1,Nd"`, which preserves inode, owner and permissions). It grows at the bottom and is trimmed at the top.

```
2026-10-29 07:44:01 - 3471 -> 3492 (CPU: 44.5°C, GPU: 53.0°C, MAX: 53.0°C)
```

The first historical line (`2547 -> 3600`) comes from the old `set_fan.sh`, now removed, and does not follow the timestamped format.

Manual-mode entries carry no temperatures:

```
2026-10-29 08:05:01 - 3720 -> 6300 (manual)
2026-10-29 08:05:01 - 6300 -> 3720 (CPU: 51.0°C, GPU: 55.2°C, MAX: 55.2°C)
```

Parameters in `control_fan.sh`:

```bash
LOG_FILE=$INSTALL_DIR/control_fan.log
LOG_MAX_LINES=100
```

Trimming is applied **always**, even when there was no RPM change on that run, so the limit is restored even if the file was overflowed by other means.

---

## Scheduling (cron)

`sudo crontab -e`:

```cron
*/2 * * * * /home/YOUR_USER/fan_control/control_fan.sh
```

**Cron expands neither variables nor `~`**, so the **real absolute path** must be used here, not `$INSTALL_DIR`. Check it with `echo "$INSTALL_DIR/control_fan.sh"` before pasting. The **root** crontab is used because the script writes to `sysfs`.

Why this interval:

| Interval | Assessment |
|---|---|
| 30 s | Faster reaction; useful under highly variable load (compiling, rendering) |
| **2 min** | **Chosen**: a compromise between responsiveness and system load; fan2 is a chassis/HDD fan with high thermal inertia |
| 5 min | Too slow for sustained temperature rises |

**Hysteresis** is not implemented: the script only acts if the target RPM differs from the current one. Because the target is truncated to an integer, small temperature changes produce ~104 RPM steps, which together with the 2-minute interval avoids rapid oscillation.

---

## Conky monitoring

In `~/.conkyrc` (`conky.text`):

```
CPU (promedio):    ${execi 120 sensors coretemp-isa-0000 | LC_ALL=C awk '/^Core [0-9]+:/ { value=$3; gsub(/[^0-9.+-]/, "", value); sum += value; n++ } END { if (n) printf "%.1f °C", sum/n; else printf "N/D" }'}
GPU (sensor TG0H): ${execi 120 sensors applesmc-isa-0300 | LC_ALL=C awk '$1 == "TG0H:" { value=$2; gsub(/[^0-9.+-]/, "", value); printf "%.1f °C", value; found=1 } END { if (!found) printf "N/D" }'}
FAN (HDD, fan2):   ${execi 120 sensors applesmc-isa-0300 | awk '$1 == "HDD" { printf "%s RPM", $3; found=1 } END { if (!found) printf "N/D" }'}
```

Details:

- CPU and GPU are displayed in **the same format**: `%.1f °C`.
- `LC_ALL=C` is essential so the decimal separator is `.` and matches what `grep`/`bc` expect (with an `es_ES` locale `printf` emits `,`).
- For `HDD` the value is field `$3`, because `sensors` prints `HDD :   3440 RPM` (there is a space before the `:`), whereas `TG0H:` has none and its value is in `$2`.
- The value shown is the **actual** RPM (`fan2_input`, rounded down by `sensors`), not the target (`fan2_output`), so it may differ slightly from the value written by the script.
- `execi 120` and `update_interval = 120` are consistent with each other.

Reload Conky after editing the configuration:

```bash
killall conky; nohup conky >/dev/null 2>&1 &
```

---

## Quick diagnostics

```bash
# Current temperatures and RPM
sensors coretemp-isa-0000
sensors applesmc-isa-0300

# Control state
cat /sys/devices/platform/applesmc.768/fan2_manual    # 1 = manual
cat /sys/devices/platform/applesmc.768/fan2_output    # target
cat /sys/devices/platform/applesmc.768/fan2_input     # actual

# Is cron running?
sudo crontab -l
grep CRON /var/log/syslog | tail -20
```

### Manual limits test

```bash
sudo $INSTALL_DIR/control_fan.sh 6300   # maximum
sudo $INSTALL_DIR/control_fan.sh 1100   # minimum
# (cron will restore a temperature-proportional value within <= 2 min)
```

---

## Known limitations

1. **No hysteresis and no smooth ramp**: changes are stepped at ~104 RPM.
2. **Manual adjustments are short-lived**: `control_fan.sh <RPM>` forces a speed, but cron overwrites it within ≤ 2 minutes. To keep a fixed value you must comment out the crontab line.
3. **`fan2_manual` is never restored to `0`** automatically: manual control persists even if the cron job is removed.
4. **Potential conflict**: the old cron line `*/1 * * * * /root/fan_control/set_fan.sh 3600` in root's `crontab` is still **commented out**; if it were re-enabled it would fight with `control_fan.sh`.
5. **Sensor failure = maximum ventilation**: if `cpu.sh`/`gpu.sh` return something non-numeric, the script assumes 100 °C and drives the fan to `fan2_max`. This is the safe choice against overheating, but it means maximum noise instead of an error notification.

### Temperature parsing (fixed on 2026-10-29)

`parse_temp()` accepts all of these forms and returns a number with `.` as the separator:

| Input | Result |
|---|---|
| `47.0`, `45`, `0`, `105.0` | `47.0`, `45`, `0`, `105.0` |
| `52,8` (decimal comma) | `52.8` |
| `+52.8`, `52.8 °C`, `+52.8°C`, `52.8°`, ` 41.5` | `52.8`, `52.8`, `52.8`, `52.8`, `41.5` |
| `N/D`, `` (empty), `-127.0`, `abc`, `12abc` | empty → fallback 100 °C → `fan2_max` |

---

## Change history

- **2026-10-29**
  - Investigated the `fan2` limits through `sysfs` (1100–6300 RPM); the maximum was verified empirically.
  - `gpu.sh` normalised to the same output format as `cpu.sh` (`%.1f`, no units, `LC_ALL=C`).
  - Added `control_fan.sh` with proportional CPU/GPU control.
  - Execution permissions applied to all scripts.
  - Scheduled in root's cron every 2 minutes.
  - Conky: added the `fan2` RPM line and unified the GPU format with the CPU one.
  - `control_fan.sh`: robust temperature parsing (`parse_temp`, accepts integers, decimal comma, `+` sign and unit suffix); the sensor-failure fallback changed from fixed 39.5/47.8 °C to **100 °C → `fan2_max`** (fail-safe).
  - `done.log` renamed to **`control_fan.log`**; `set_fan.sh` now writes to the same path (`$INSTALL_DIR/control_fan.log`) instead of `/root/fan_control/`.
  - `control_fan.log` capped at **100 lines**: a new line evicts the oldest one.
  - **`set_fan.sh` removed**; its role is covered by `control_fan.sh <RPM>` (optional parameter, with validation and clamping to the hardware limits).
  - `README.md`: added the **Motivation** section (HDD replaced by SSD and loss of the sensor that used to regulate `fan2`).
  - `README.md`: added the **Supported operating systems and hardware** section (Linux + Intel Apple + `applesmc`; not valid for macOS, Windows, Apple Silicon or PCs).
  - `control_fan.sh` no longer contains absolute paths: it resolves `cpu.sh`, `gpu.sh` and `control_fan.log` from its own directory (`SCRIPT_DIR`), so it can be installed in any folder. `LOG_FILE` can be overridden through an environment variable.
  - `README_ES.md` / `README.md`: added the **Installation** section (requirements, dependencies, steps 0–7, Conky, uninstall) and all paths now use `$INSTALL_DIR`.
  - Documentation split by language: `README_ES.md` / `AGENTS_ES.md` (Spanish) and `README.md` / `AGENTS.md` (English).
