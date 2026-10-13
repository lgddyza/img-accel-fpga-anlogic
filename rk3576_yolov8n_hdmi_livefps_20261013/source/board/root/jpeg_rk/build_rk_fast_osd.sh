#!/bin/sh
set -eu
cd "$(dirname "$0")"
cc -O3 -std=gnu11 -fPIC -shared -Wall -Wextra \
    -o libgstrkfastosd.so rk_fast_osd.c \
    $(pkg-config --cflags --libs gstreamer-video-1.0 gstreamer-base-1.0)
