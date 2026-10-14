#!/bin/sh
set -eu
test "$(id -u)" = 0 || { echo 'Run as root' >&2; exit 1; }
test "$(uname -r)" = 6.1.99 || { echo 'Matching kernel 6.1.99 required' >&2; exit 1; }
if pgrep -f '(^|/| )(show_jpeg_hdmi[^ ]*\.py|start_jpeg_hdmi[^ ]*\.sh|jpeg_qf_button\.py)( |$)' >/dev/null; then
    echo 'Stop the current viewer and K1 helper before restoring or starting.' >&2
    exit 1
fi
sh /usr/local/sbin/pcie1-recover.sh
modprobe anlogic_pci
for lane in a b c; do
    name="milianke_jpeg_$lane"
    if [ ! -d "/sys/module/$name" ]; then insmod "/root/jpeg_rk/$name.ko"; fi
done
python3 -c 'import sys; sys.path.insert(0,"/root/jpeg_rk"); from preproc_mode import user_bar,read32; r,p=user_bar(); tag=read32(r,0xac); modes=read32(r,0x104); r.close(); assert tag==0x45485032 and modes==0xff, "EHP2 FPGA with eight modes required"'
python3 /root/jpeg_rk/preproc_mode.py "${PREPROC_MODE:-gray}" --wait-applied
python3 /root/jpeg_rk/jpeg_control.py --quality "${JPEG_QUALITY:-80}" --rate 60
export JPEG_HDMI_SINK=kms JPEG_DECODER=software JPEG_TEMPORAL_METHOD=normalize
export JPEG_AI_INTERVAL="${JPEG_AI_INTERVAL:-1}" JPEG_AI_CONFIDENCE="${JPEG_AI_CONFIDENCE:-0.5}" JPEG_AI_SECONDS=0
export JPEG_STATUS_MODE=inframe JPEG_OUTPUT_FORMAT=RGBx JPEG_KMS_SYNC_MODE=auto
export JPEG_AI_MODEL=/root/road_damage_yolov8n/road_damage_yolov8n_gray640_int8_rk3576.rknn JPEG_PAIR_DIAG=0
exec sh /root/jpeg_rk/start_jpeg_hdmi_ai_fallback.sh "${1:-188}"
