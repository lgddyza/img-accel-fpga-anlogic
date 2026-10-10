#!/bin/sh
set -eu

governor=${1:-performance}
case "$governor" in
    performance|ondemand) ;;
    *)
        echo 'Usage: set_video_governor.sh [performance|ondemand]' >&2
        exit 2
        ;;
esac

found=0
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -e "$policy/scaling_governor" ] || continue
    found=1
    available=$(cat "$policy/scaling_available_governors")
    case " $available " in
        *" $governor "*) ;;
        *)
            echo "$governor is unavailable for $policy (available: $available)" >&2
            exit 1
            ;;
    esac
    printf '%s\n' "$governor" > "$policy/scaling_governor"
done

if [ "$found" -eq 0 ]; then
    echo 'No CPU frequency policies were found.' >&2
    exit 1
fi

for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -r "$policy/scaling_governor" ] || continue
    printf '%s: governor=%s current=%s kHz max=%s kHz\n' \
        "${policy##*/}" \
        "$(cat "$policy/scaling_governor")" \
        "$(cat "$policy/scaling_cur_freq")" \
        "$(cat "$policy/scaling_max_freq")"
done
