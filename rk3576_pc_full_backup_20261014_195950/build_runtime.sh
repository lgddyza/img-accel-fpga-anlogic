#!/bin/sh
# Optional: rebuild userspace on the same RK SDK, with video stopped.
set -eu
cd /root/jpeg_rk
cc -O3 -fPIC -shared -Wall -Wextra -o libjpeg_native.so jpeg_native.c -ljpeg
cc -O3 -fPIC -shared -Wall -Wextra -o libjpeg_weave.so jpeg_weave.c
sh ./build_rk_temporal_gray.sh
sha256sum rk_temporal_gray.c | cut -d ' ' -f 1 > .rk_temporal_gray_source.sha256
sh ./build_rk_fast_osd.sh
cc -O3 -std=gnu11 -fPIC -shared -Wall -Wextra -o libgstrktemporalai.so rk_temporal_ai.c \
    $(pkg-config --cflags --libs gstreamer-video-1.0 gstreamer-base-1.0) -lm
cc -O3 -std=gnu11 -fPIC -shared -Wall -Wextra -o libgstrkstatusai.so rk_status_ai.c \
    $(pkg-config --cflags --libs gstreamer-video-1.0 gstreamer-base-1.0)
cc -O2 -std=gnu11 -Wall -Wextra -o rk_hdmi_status_plane rk_hdmi_status_plane.c \
    $(pkg-config --cflags --libs libdrm)
g++ -O3 -std=c++17 -fPIC -shared /root/road_damage_yolov8n/rk3576_infer.cpp \
    -I/root/road_damage_yolov8n -o libroad_infer.so $(pkg-config --cflags --libs opencv4) -L/lib -lrknnrt
mkdir -p active_ai_plugins
cp libgstrktemporalgray.so libgstrktemporalai.so libgstrkstatusai.so active_ai_plugins/
echo 'Userspace build complete. Clear /run/jpeg-rk*gst-registry.bin with viewers stopped before starting.'
