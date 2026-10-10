"""Run on RK to snapshot immutable deployment files without stopping video."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import time

ROOT = Path("/root/road_damage_yolov8n/release_ehp2_k1_20261010")
NAMES = """start_jpeg_hdmi_ai.sh start_jpeg_hdmi_ai_fallback.sh
show_jpeg_hdmi_overlay.py rk_hdmi_status_plane.c rk_hdmi_status_plane
rk_temporal_ai.c rk_status_ai.c rk_font5x7.h libroad_infer.so
libgstrktemporalai.so libgstrkstatusai.so
active_ai_plugins/libgstrktemporalai.so active_ai_plugins/libgstrkstatusai.so
capture_jpeg_tiles.py jpeg_control.py preproc_mode.py jpeg_qf_button.py
set_video_governor.sh start_jpeg_hdmi_60.sh show_jpeg_hdmi.py
rk_temporal_gray.c rk_fast_osd.c libgstrktemporalgray.so libgstrkfastosd.so
build_rk_temporal_gray.sh build_rk_fast_osd.sh .rk_temporal_gray_source.sha256
milianke_jpeg_a.ko milianke_jpeg_b.ko milianke_jpeg_c.ko
milianke_jpeg_a.c milianke_jpeg_b.c milianke_jpeg_c.c milianke_jpeg_v4l2.c Makefile
limit_rk_logs.sh check_jpeg_weave.py""".split()
FILES = [Path("/root/jpeg_rk") / name for name in NAMES] + [Path(p) for p in """
/root/road_damage_yolov8n/road_damage_yolov8n_gray640_int8_rk3576.rknn
/root/road_damage_yolov8n/rk3576_infer.cpp
/root/road_damage_yolov8n/rk3576_benchmark.cpp
/root/road_damage_yolov8n/rknn_api.h
/lib/librknnrt.so
/lib/modules/6.1.99/extra/anlogic_pci.ko
/etc/modprobe.d/anlogic_pci.conf
/etc/systemd/system/anlogic-sgdma.service
/etc/systemd/system/pcie1-recover.service
/usr/local/sbin/pcie1-recover.sh
""".split()]


def command(args):
    proc = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, errors="replace", timeout=12)
    return {"exit_code": proc.returncode, "output": proc.stdout}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ROOT.mkdir(exist_ok=False)
    for path in FILES:
        if not path.is_file():
            raise RuntimeError(f"Required file missing: {path}")
    sys.path.insert(0, "/root/jpeg_rk")
    from preproc_mode import read32, user_bar
    region, bar = user_bar()
    try:
        registers = {name: read32(region, offset) for name, offset in {
            "algorithm": 0xac, "supported": 0x104, "requested_mode": 0xa4,
            "applied_mode": 0x100, "preproc_fault": 0xa8, "raw_fault": 0x94,
            "jpeg_fault": 0xcc, "qf_request": 0xb8, "qf_applied_raw": 0xf8,
            "input_rate": 0xf0}.items()}
    finally:
        region.close()
    manifest = {"host_date": "2026-10-10", "host_timezone": "Asia/Shanghai",
                "board_time_untrusted": time.time(), "bar": str(bar),
                "registers": registers, "files": []}
    model = FILES[len(NAMES)]
    if digest(model) != "ecdc6accd6558c3394d4a73eeb03b876f09d9e82ba11c2754869d8bb9add55ae":
        raise RuntimeError("Unexpected deployed model")
    for path in FILES:
        info = path.stat()
        manifest["files"].append({"path": str(path), "archive_path": str(path).lstrip("/"),
                                  "bytes": info.st_size, "mode": oct(info.st_mode & 0o7777),
                                  "sha256": digest(path)})

    metadata = {
        "uname": command(["uname", "-a"]),
        "os_release": Path("/etc/os-release").read_text(),
        "packages": command(["dpkg-query", "-W", "python3", "python3-gi", "python3-gst-1.0",
                             "libdrm2", "libdrm-dev", "libopencv-core406", "libopencv-imgproc406",
                             "libgstreamer1.0-0", "gstreamer1.0-plugins-good"]),
        "loaded_modules": command(["lsmod"]),
        "drm_state": command(["cat", "/sys/kernel/debug/dri/0/state"]),
        "infer_dependencies": command(["ldd", "/root/jpeg_rk/libroad_infer.so"]),
        "status_dependencies": command(["ldd", "/root/jpeg_rk/rk_hdmi_status_plane"]),
        "driver_vermagic": command(["modinfo", "-F", "vermagic", "/root/jpeg_rk/milianke_jpeg_a.ko"]),
        "service_state": command(["systemctl", "show", "pcie1-recover.service",
                                  "anlogic-sgdma.service", "-p", "ActiveState", "-p", "UnitFileState"]),
        "rc_local_reference": Path("/etc/rc.local").read_text(),
        "processes": [], "log_tails": {}}
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            argv = (proc/"cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
            if any(token in argv for token in ("show_jpeg_hdmi_overlay.py", "jpeg_qf_button.py",
                                                "rk_hdmi_status_plane", "start_jpeg_hdmi_ai")):
                env = (proc/"environ").read_bytes().split(b"\0")
                allowed = [item.decode(errors="replace") for item in env
                           if item.startswith((b"JPEG_", b"RK_STATUS_", b"GST_PLUGIN_PATH=", b"GST_REGISTRY="))]
                metadata["processes"].append({"pid": int(proc.name), "argv": argv,
                                              "relevant_environment": allowed})
        except (OSError, PermissionError):
            pass
    for name, path in {
        "button": "/root/jpeg_rk/qf_button.log",
        "status": "/root/road_damage_yolov8n/hdmi_status_plane.log",
        "viewer": "/root/road_damage_yolov8n/hdmi_ai_ui_fixed.log"}.items():
        with open(path, "rb") as stream:
            stream.seek(max(0, os.fstat(stream.fileno()).st_size-12000))
            metadata["log_tails"][name] = stream.read().decode(errors="replace")
    (ROOT/"manifest.json").write_text(json.dumps(manifest, indent=2))
    (ROOT/"environment.json").write_text(json.dumps(metadata, indent=2))
    (ROOT/"PAYLOAD_SHA256SUMS").write_text("".join(
        f"{item['sha256']}  {item['archive_path']}\n" for item in manifest["files"]))
    archive_path = ROOT/"board.tar.gz"
    with tarfile.open(archive_path, "w:gz") as archive:
        for item in manifest["files"]:
            archive.add(item["path"], arcname=item["archive_path"], recursive=False)
    for item in manifest["files"]:
        if digest(Path(item["path"])) != item["sha256"]:
            raise RuntimeError(f"Deployment file changed during capture: {item['path']}")
    archive_info = {"archive": str(archive_path), "bytes": archive_path.stat().st_size,
                    "sha256": digest(archive_path), "file_count": len(FILES)}
    (ROOT/"capture.json").write_text(json.dumps(archive_info, indent=2))
    print("RELEASE_CAPTURED", json.dumps(archive_info), flush=True)


if __name__ == "__main__":
    main()
