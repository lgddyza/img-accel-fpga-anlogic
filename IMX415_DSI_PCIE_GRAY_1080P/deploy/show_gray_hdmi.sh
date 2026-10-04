#!/bin/sh
set -eu

# The gray driver must already be built/loaded for the GR ABI bitstream.
# This script neither changes PCIe bindings nor terminates an existing viewer.
video_device=${1:-}
connector=${2:-188}
if [ -z "$video_device" ]; then
    for node in /sys/class/video4linux/video*; do
        [ -r "$node/name" ] || continue
        if [ "$(cat "$node/name")" = 'Milianke PCIe GREY' ]; then
            video_device=/dev/${node##*/}
            break
        fi
    done
fi
if [ -z "$video_device" ]; then
    echo 'No Milianke PCIe GREY capture device. Load the matching gray driver first.' >&2
    exit 1
fi
case "$connector" in *[!0-9]*|'') echo 'Connector must be numeric.' >&2; exit 1;; esac
details=$(v4l2-ctl -d "$video_device" --all)
printf '%s\n' "$details" | grep -q 'milianke-gray' || {
    echo 'Refusing to use a non-gray capture driver.' >&2; exit 1;
}
v4l2-ctl -d "$video_device" --set-fmt-video=width=1920,height=1080,pixelformat=GREY
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ ! -f "$script_dir/libgstrkfastosd.so" ] && command -v cc >/dev/null 2>&1; then
    sh "$script_dir/build_rk_fast_osd.sh" || \
        echo 'Fast status overlay unavailable; using the standard text overlay.' >&2
fi
if [ "${HDMI_TEMPORAL:-1}" != 0 ] &&
   [ ! -f "$script_dir/libgstrktemporalgray.so" ]; then
    sh "$script_dir/build_rk_temporal_gray.sh" || {
        echo 'Temporal GREY stabilizer could not be built; set HDMI_TEMPORAL=0 to bypass it.' >&2
        exit 1
    }
fi
exec python3 "$script_dir/show_gray_hdmi.py" "$video_device" "$connector"
