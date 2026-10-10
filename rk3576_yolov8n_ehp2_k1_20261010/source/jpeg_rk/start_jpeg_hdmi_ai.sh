#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
connector=${1:-188}
sink=${JPEG_HDMI_SINK:-kms}
decoder=${JPEG_DECODER:-software}
temporal_method=${JPEG_TEMPORAL_METHOD:-affine}
kms_sync_mode=${JPEG_KMS_SYNC_MODE:-auto}
output_format=${JPEG_OUTPUT_FORMAT:-RGBx}
ai_interval=${JPEG_AI_INTERVAL:-2}
ai_confidence=${JPEG_AI_CONFIDENCE:-0.10}
seconds=${JPEG_AI_SECONDS:-0}
status_mode=${JPEG_STATUS_MODE:-plane}
ai_model=${JPEG_AI_MODEL:-/root/road_damage_yolov8n/road_damage_yolov8n_gray640_int8_rk3576.rknn}
case "$connector" in
    *[!0-9]*|'') echo 'Connector must be numeric.' >&2; exit 2 ;;
esac
case "$sink" in
    kms) sink_options='--skip-vsync' ;;
    xv) sink_options='' ; export DISPLAY=:0 XAUTHORITY=/home/linaro/.Xauthority ;;
    *) echo 'JPEG_HDMI_SINK must be kms or xv.' >&2; exit 2 ;;
esac
case "$decoder" in
    software|mpp) ;;
    *) echo 'JPEG_DECODER must be software or mpp.' >&2; exit 2 ;;
esac
case "$status_mode" in
    plane|inframe|off) ;;
    *) echo 'JPEG_STATUS_MODE must be plane, inframe or off.' >&2; exit 2 ;;
esac
case "$temporal_method" in
    blend|affine|tone) ;;
    *) echo 'JPEG_TEMPORAL_METHOD must be blend, affine or tone.' >&2; exit 2 ;;
esac
case "$kms_sync_mode" in
    auto|none) ;;
    *) echo 'JPEG_KMS_SYNC_MODE must be auto or none.' >&2; exit 2 ;;
esac
case "$output_format" in
    RGBx) ;;
    *) echo 'AI overlay requires JPEG_OUTPUT_FORMAT=RGBx.' >&2; exit 2 ;;
esac
case "$ai_interval:$seconds" in
    *[!0-9:]*|'') echo 'JPEG_AI_INTERVAL and JPEG_AI_SECONDS must be numeric.' >&2; exit 2 ;;
esac
osd_options=''
if [ "$status_mode" != inframe ] || [ "${JPEG_NO_OSD:-0}" = 1 ]; then
    osd_options='--no-osd'
fi
pair_options=''
if [ "${JPEG_PAIR_DIAG:-0}" = 1 ]; then
    pair_options='--diagnose-pairing'
    export JPEG_PAIR_TRACE=1
fi

sh "$script_dir/set_video_governor.sh" performance
export GST_REGISTRY=${GST_REGISTRY:-/run/jpeg-rk-gst-registry.bin}

# Xfwm's compositor competes with the KMS video plane on HDMI-A-1.
# Keep the user's X11 desktop available, but stop it from recomposing HDMI.
if [ -S /tmp/.X11-unix/X0 ] && command -v xfconf-query >/dev/null 2>&1; then
    sudo -u linaro env DISPLAY=:0 XAUTHORITY=/home/linaro/.Xauthority \
        xfconf-query -c xfwm4 -p /general/use_compositing -s false
fi

temporal_source_sha=$(sha256sum "$script_dir/rk_temporal_gray.c" | cut -d ' ' -f 1)
temporal_build_stamp="$script_dir/.rk_temporal_gray_source.sha256"
if [ ! -f "$script_dir/libgstrktemporalgray.so" ] || \
   [ "$(cat "$temporal_build_stamp" 2>/dev/null || true)" != "$temporal_source_sha" ]; then
    sh "$script_dir/build_rk_temporal_gray.sh"
    printf '%s\n' "$temporal_source_sha" > "$temporal_build_stamp"
fi
if [ ! -f "$script_dir/libgstrkfastosd.so" ]; then
    sh "$script_dir/build_rk_fast_osd.sh"
fi
if [ ! -f "$script_dir/libgstrktemporalai.so" ] ||
   [ "$script_dir/rk_temporal_ai.c" -nt "$script_dir/libgstrktemporalai.so" ] ||
   [ "$script_dir/rk_font5x7.h" -nt "$script_dir/libgstrktemporalai.so" ]; then
    cc -O3 -std=gnu11 -fPIC -shared -Wall -Wextra \
        -o "$script_dir/libgstrktemporalai.so" "$script_dir/rk_temporal_ai.c" \
        $(pkg-config --cflags --libs gstreamer-video-1.0 gstreamer-base-1.0) -lm
fi
if [ ! -f "$script_dir/libgstrkstatusai.so" ] ||
   [ "$script_dir/rk_status_ai.c" -nt "$script_dir/libgstrkstatusai.so" ] ||
   [ "$script_dir/rk_font5x7.h" -nt "$script_dir/libgstrkstatusai.so" ]; then
    cc -O3 -std=gnu11 -fPIC -shared -Wall -Wextra \
        -o "$script_dir/libgstrkstatusai.so" "$script_dir/rk_status_ai.c" \
        $(pkg-config --cflags --libs gstreamer-video-1.0 gstreamer-base-1.0)
fi
if [ ! -x "$script_dir/rk_hdmi_status_plane" ] ||
   [ "$script_dir/rk_hdmi_status_plane.c" -nt "$script_dir/rk_hdmi_status_plane" ] ||
   [ "$script_dir/rk_font5x7.h" -nt "$script_dir/rk_hdmi_status_plane" ]; then
    cc -O2 -std=gnu11 -Wall -Wextra \
        -o "$script_dir/rk_hdmi_status_plane" \
        "$script_dir/rk_hdmi_status_plane.c" \
        $(pkg-config --cflags --libs libdrm)
fi

# Keep the AI plugins in a directory with no rollback copies. GStreamer scans
# subdirectories of GST_PLUGIN_PATH and may otherwise register an older plugin
# with the same element name from rollback_ai_osd.
ai_plugin_dir="$script_dir/active_ai_plugins"
mkdir -p "$ai_plugin_dir"
cp -f "$script_dir/libgstrktemporalai.so" "$ai_plugin_dir/libgstrktemporalai.so"
cp -f "$script_dir/libgstrkstatusai.so" "$ai_plugin_dir/libgstrkstatusai.so"
export GST_PLUGIN_PATH="$ai_plugin_dir"
export GST_REGISTRY=/run/jpeg-rk-ai-gst-registry.bin

# The rate register must be changed while all JPEG V4L2 streams are stopped.
python3 "$script_dir/jpeg_control.py" --rate 60
python3 -u "$script_dir/jpeg_qf_button.py" \
    >> "$script_dir/qf_button.log" 2>&1 &
button_pid=$!
plane_pid=''
if [ "$status_mode" = plane ] && [ "${JPEG_NO_OSD:-0}" != 1 ]; then
    (
        sleep 3
        exec "$script_dir/rk_hdmi_status_plane" "$seconds"
    ) >> /root/road_damage_yolov8n/hdmi_status_plane.log 2>&1 &
    plane_pid=$!
fi
cleanup() {
    kill "$button_pid" 2>/dev/null || true
    wait "$button_pid" 2>/dev/null || true
    if [ -n "$plane_pid" ]; then
        kill "$plane_pid" 2>/dev/null || true
        wait "$plane_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
set -- python3 "$script_dir/show_jpeg_hdmi_overlay.py"
if [ "$(nproc)" -ge 8 ] && command -v taskset >/dev/null 2>&1; then
    # SGDMA workers are bound to cores 3-5; reserve the other cores for video.
    set -- taskset -c 0-2,6,7 "$@"
fi
"$@" \
    --connector "$connector" \
    --decoder "$decoder" \
    --decode-workers 3 \
    --fps 60 \
    --sink "$sink" \
    --kms-sync-mode "$kms_sync_mode" \
    --output-format "$output_format" \
    $osd_options \
    $sink_options \
    $pair_options \
    --temporal-method "$temporal_method" \
    --ai-model "$ai_model" \
    --ai-interval "$ai_interval" \
    --ai-confidence "$ai_confidence" \
    --seconds "$seconds"
