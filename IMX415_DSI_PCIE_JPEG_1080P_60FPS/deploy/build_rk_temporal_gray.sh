#!/bin/sh
set -eu
cd "$(dirname "$0")"
cc -O3 -march=armv8-a+simd -std=gnu11 -fPIC -shared -Wall -Wextra \
    -o libgstrktemporalgray.so rk_temporal_gray.c \
    $(pkg-config --cflags --libs gstreamer-video-1.0 gstreamer-base-1.0)
