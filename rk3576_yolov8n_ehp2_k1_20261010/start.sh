#!/bin/sh
# Run after restoring board.tar.gz on the matching RK3576 root filesystem.
set -eu
test "$(id -u)" = 0 || { echo 'Run as root' >&2; exit 1; }
test "$(uname -r)" = 6.1.99 || { echo 'This snapshot requires kernel 6.1.99' >&2; exit 1; }
if pgrep -f '^python3 /root/jpeg_rk/show_jpeg_hdmi' >/dev/null ||
   pgrep -f '^sh /root/jpeg_rk/start_jpeg_hdmi' >/dev/null; then
    echo 'An HDMI viewer/launcher is already running; stop it and its children first.' >&2
    exit 1
fi
model=/root/road_damage_yolov8n/road_damage_yolov8n_gray640_int8_rk3576.rknn
printf '%s  %s\n' ecdc6accd6558c3394d4a73eeb03b876f09d9e82ba11c2754869d8bb9add55ae "$model" | sha256sum -c -
sh /usr/local/sbin/pcie1-recover.sh
modprobe anlogic_pci
for lane in a b c; do
    name="milianke_jpeg_$lane"
    if [ ! -d "/sys/module/$name" ]; then
        insmod "/root/jpeg_rk/$name.ko"
    fi
done
python3 -c 'import sys; sys.path.insert(0,"/root/jpeg_rk"); from preproc_mode import user_bar,read32; r,p=user_bar(); tag=read32(r,0xac); modes=read32(r,0x104); r.close(); assert tag==0x45485032 and modes==0xff, "EHP2 FPGA image with eight modes required"'
python3 /root/jpeg_rk/preproc_mode.py gauss-clahe --wait-applied
python3 /root/jpeg_rk/jpeg_control.py --quality 90 --rate 60
export JPEG_HDMI_SINK=kms JPEG_DECODER=software JPEG_TEMPORAL_METHOD=affine
export JPEG_AI_INTERVAL=2 JPEG_AI_CONFIDENCE=0.10 JPEG_AI_SECONDS=0
export JPEG_STATUS_MODE=plane JPEG_OUTPUT_FORMAT=RGBx JPEG_KMS_SYNC_MODE=auto
export JPEG_AI_MODEL="$model"
export JPEG_PAIR_DIAG="${JPEG_PAIR_DIAG:-0}"
exec sh /root/jpeg_rk/start_jpeg_hdmi_ai_fallback.sh 188
