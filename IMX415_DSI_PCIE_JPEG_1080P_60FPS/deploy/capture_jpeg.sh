#!/bin/sh
# Usage: sh capture_jpeg.sh [--count N] [--output DIR]
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$SCRIPT_DIR/capture_jpeg_tiles.py" "$@"
