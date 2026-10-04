"""Package the RK JPEG receiver sources for offline serial deployment."""

from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import hashlib

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "deploy" / "jpeg_rk_bundle.zip"
SOURCES = [
    "deploy/v4l2_drv/milianke_jpeg_v4l2.c",
    "deploy/v4l2_drv/milianke_jpeg_a.c",
    "deploy/v4l2_drv/milianke_jpeg_b.c",
    "deploy/v4l2_drv/milianke_jpeg_c.c",
    "deploy/preproc_mode.py",
    "deploy/jpeg_control.py",
    "deploy/capture_jpeg_tiles.py",
    "deploy/show_jpeg_hdmi.py",
    "deploy/rk_temporal_gray.c",
    "deploy/build_rk_temporal_gray.sh",
    "deploy/summarize_jpeg_hdmi.py",
    "deploy/probe_jpeg_busy.py",
    "deploy/stress_jpeg_tiles.py",
    "deploy/measure_transport_streams.py",
    "deploy/check_jpeg_weave.py",
    "deploy/capture_jpeg.sh",
]
MAKEFILE = """KDIR ?= /lib/modules/$(shell uname -r)/build
SGDMA_DIR ?= /root/pcie_smoke_demo/vendor_deploy/sgdma_drv
obj-m := milianke_jpeg_a.o milianke_jpeg_b.o milianke_jpeg_c.o
all:
\t$(MAKE) -C $(KDIR) M=$(CURDIR) KBUILD_EXTRA_SYMBOLS=$(SGDMA_DIR)/Module.symvers modules
clean:
\t$(MAKE) -C $(KDIR) M=$(CURDIR) clean
"""


def main():
    with ZipFile(OUT, "w", ZIP_DEFLATED, compresslevel=9) as archive:
        archive.writestr("jpeg_rk/Makefile", MAKEFILE)
        for relative in SOURCES:
            source = ROOT / relative
            archive.write(source, f"jpeg_rk/{source.name}")
    data = OUT.read_bytes()
    print(f"{OUT} {len(data)} bytes sha256={hashlib.sha256(data).hexdigest()}")


if __name__ == "__main__":
    main()
