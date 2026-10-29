#!/bin/bash

# Control fan2 (HDD) speed of the iMac via applesmc.
#
#   control_fan.sh [RPM]      no args  -> automatic: RPM proportional to max(CPU, GPU)
#                             RPM      -> force that speed (clamped to fan2_min/fan2_max)
#                             -h|--help
#
# Requires root (writes to fan2_manual / fan2_output).
# Scheduled by root's crontab every 2 minutes without arguments.

# Directory where this script lives: cpu.sh and gpu.sh are resolved relative to
# it, so the project can be installed anywhere without editing any path.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Override with LOG_FILE=/path/to/log if you want the log somewhere else.
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/control_fan.log}"
LOG_MAX_LINES=100

SMC=/sys/devices/platform/applesmc.768

# Temperature-to-RPM mapping parameters (automatic mode)
TEMP_MIN=30.0    # Below this temp, use the minimum RPM
TEMP_MAX=80.0    # Above this temp, use the maximum RPM

usage() {
    cat <<EOF
Usage: $(basename "$0") [RPM]

  (sin argumentos)  Control automático: RPM proporcional a max(CPU, GPU).
  RPM               Fija el ventilador a ese valor (se recorta a fan2_min..fan2_max).
  -h, --help        Muestra esta ayuda.

Ejemplos:
  sudo $(basename "$0")         # automático
  sudo $(basename "$0") 4000    # forzar 4000 RPM
EOF
}

# Parse a temperature value into a plain number.
# Accepts an optional leading '+', '.' or ',' as decimal separator, an optional
# unit suffix (°C, C, °) and stray spaces: "52.8", "45", "52,8", "+52.8°C".
# Returns an empty string if the value is not a valid non-negative number
# (e.g. "N/D", "", "-127.0"), which the caller treats as a sensor failure.
parse_temp() {
    printf '%s' "$1" \
        | tr ',' '.' \
        | tr -d ' ' \
        | LC_ALL=C sed -nE 's/^\+?([0-9]+(\.[0-9]+)?)(°C|°|C)?$/\1/p'
}

# ---------------------------------------------------------------- arguments
MANUAL_RPM=""
case "$1" in
    -h|--help)
        usage
        exit 0
        ;;
    "")
        ;;
    *)
        if [[ ! "$1" =~ ^[0-9]+$ ]]; then
            echo "ERROR: '$1' no es un RPM válido (se espera un entero no negativo)." >&2
            usage >&2
            exit 2
        fi
        MANUAL_RPM=$((10#$1))    # 10# evita que 0800 se interprete como octal
        ;;
esac

# ------------------------------------------------------------ fan hardware
FAN2_MIN=$(cat "$SMC/fan2_min")
FAN2_MAX=$(cat "$SMC/fan2_max")

# ------------------------------------------------------------------ target
if [[ -n "$MANUAL_RPM" ]]; then
    # Manual mode: no need to read the sensors at all.
    MODE="manual"
    TARGET_RPM=$MANUAL_RPM

    if (( TARGET_RPM < FAN2_MIN )); then
        echo "Aviso: ${TARGET_RPM} RPM está por debajo del mínimo; se usa ${FAN2_MIN}." >&2
        TARGET_RPM=$FAN2_MIN
    elif (( TARGET_RPM > FAN2_MAX )); then
        echo "Aviso: ${TARGET_RPM} RPM supera el máximo; se usa ${FAN2_MAX}." >&2
        TARGET_RPM=$FAN2_MAX
    fi

    LOG_DETAIL="manual"
else
    MODE="auto"

    # Load temperature values
    CPU_TEMP=$("$SCRIPT_DIR/cpu.sh")
    GPU_TEMP=$("$SCRIPT_DIR/gpu.sh")

    CPU_TEMP_NUM=$(parse_temp "$CPU_TEMP")
    GPU_TEMP_NUM=$(parse_temp "$GPU_TEMP")

    # Fallback if parsing fails: sensors are unavailable.
    # Use 100 so the fan is driven to max instead of guessing a cool temperature.
    if [[ -z "$CPU_TEMP_NUM" ]]; then
        CPU_TEMP_NUM="100"
    fi
    if [[ -z "$GPU_TEMP_NUM" ]]; then
        GPU_TEMP_NUM="100"
    fi

    # Get the maximum temperature
    MAX_TEMP=${CPU_TEMP_NUM}
    if (( $(echo "$GPU_TEMP_NUM > $MAX_TEMP" | bc -l) )); then
        MAX_TEMP=${GPU_TEMP_NUM}
    fi

    # Calculate target RPM based on temperature
    if (( $(echo "$MAX_TEMP < $TEMP_MIN" | bc -l) )); then
        TARGET_RPM=$FAN2_MIN
    elif (( $(echo "$MAX_TEMP > $TEMP_MAX" | bc -l) )); then
        TARGET_RPM=$FAN2_MAX
    else
        # Linear interpolation between FAN2_MIN and FAN2_MAX
        RANGE_TEMP=$(echo "$TEMP_MAX - $TEMP_MIN" | bc -l)
        RANGE_RPM=$(echo "$FAN2_MAX - $FAN2_MIN" | bc -l)
        RATIO=$(echo "($MAX_TEMP - $TEMP_MIN) / $RANGE_TEMP" | bc -l)
        TARGET_RPM=$(echo "$FAN2_MIN + ($RATIO * $RANGE_RPM)" | bc -l)
    fi

    # Truncate to integer
    TARGET_RPM=$(echo "scale=0; $TARGET_RPM / 1" | bc -l)
    TARGET_RPM=$(echo "$TARGET_RPM" | sed 's/^\./0./; s/^-\./-0./')

    LOG_DETAIL="CPU: ${CPU_TEMP_NUM}°C, GPU: ${GPU_TEMP_NUM}°C, MAX: ${MAX_TEMP}°C"
fi

# ------------------------------------------------------------------- apply
CURRENT_RPM=$(cat "$SMC/fan2_output")

if [[ "$CURRENT_RPM" != "$TARGET_RPM" ]]; then
    echo "Activating manual mode..."
    echo 1 > "$SMC/fan2_manual"

    echo "Setting fan2 speed: ${CURRENT_RPM} -> ${TARGET_RPM} RPM (${MODE})"
    echo "$TARGET_RPM" > "$SMC/fan2_output"

    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${TIMESTAMP} - ${CURRENT_RPM} -> ${TARGET_RPM} (${LOG_DETAIL})" >> "$LOG_FILE"
else
    echo "Fan speed already at target: ${TARGET_RPM} RPM (${MODE})"
fi

# Keep the log bounded: drop the oldest lines so it never exceeds LOG_MAX_LINES.
# 'sed -i' is used so the file keeps its inode, owner and permissions.
if [[ -f "$LOG_FILE" ]]; then
    LOG_LINES=$(wc -l < "$LOG_FILE")
    if (( LOG_LINES > LOG_MAX_LINES )); then
        sed -i "1,$((LOG_LINES - LOG_MAX_LINES))d" "$LOG_FILE"
    fi
fi

exit 0
