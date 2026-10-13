"""Capture the running RK deployment without restarting or reconfiguring it."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import time

ROOT = Path('/root/road_damage_yolov8n/release_hdmi_livefps_20261013')
NAMES = '''start_jpeg_hdmi_ai.sh start_jpeg_hdmi_ai_fallback.sh
show_jpeg_hdmi_overlay.py rk_hdmi_status_plane.c rk_hdmi_status_plane
rk_temporal_ai.c rk_status_ai.c rk_font5x7.h libroad_infer.so
libgstrktemporalai.so libgstrkstatusai.so libgstrktemporalgray.so
active_ai_plugins/libgstrktemporalai.so active_ai_plugins/libgstrkstatusai.so
active_ai_plugins/libgstrktemporalgray.so
capture_jpeg_tiles.py jpeg_control.py preproc_mode.py jpeg_qf_button.py
set_video_governor.sh start_jpeg_hdmi_60.sh show_jpeg_hdmi.py
rk_temporal_gray.c rk_fast_osd.c libgstrkfastosd.so
build_rk_temporal_gray.sh build_rk_fast_osd.sh .rk_temporal_gray_source.sha256
rk_video_fast.py jpeg_native.c jpeg_weave.c libjpeg_native.so libjpeg_weave.so
pc_host_agent_v1.py
milianke_jpeg_a.ko milianke_jpeg_b.ko milianke_jpeg_c.ko
milianke_jpeg_a.c milianke_jpeg_b.c milianke_jpeg_c.c milianke_jpeg_v4l2.c Makefile
limit_rk_logs.sh check_jpeg_weave.py'''.split()
FILES = [Path('/root/jpeg_rk') / name for name in NAMES] + [Path(p) for p in '''
/root/road_damage_yolov8n/road_damage_yolov8n_gray640_int8_rk3576.rknn
/root/road_damage_yolov8n/rk3576_infer.cpp
/root/road_damage_yolov8n/rk3576_benchmark.cpp
/root/road_damage_yolov8n/rk3576_benchmark
/root/road_damage_yolov8n/rknn_api.h
/lib/librknnrt.so
/lib/modules/6.1.99/extra/anlogic_pci.ko
/etc/modprobe.d/anlogic_pci.conf
/etc/systemd/system/anlogic-sgdma.service
/etc/systemd/system/pcie1-recover.service
/usr/local/sbin/pcie1-recover.sh
'''.split()]
MODEL_SHA = 'ecdc6accd6558c3394d4a73eeb03b876f09d9e82ba11c2754869d8bb9add55ae'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, errors='replace', timeout=15)
    return {'exit_code': result.returncode, 'output': result.stdout}


def main():
    ROOT.mkdir(exist_ok=True)
    assert not any(ROOT.iterdir()), 'Release directory must be empty'
    for path in FILES:
        if not path.is_file():
            raise RuntimeError(f'Required deployment file missing: {path}')
    model = next(p for p in FILES if p.suffix == '.rknn')
    assert sha(model) == MODEL_SHA, 'Unexpected deployed model'
    for name in ('temporalai', 'statusai'):
        base = Path('/root/jpeg_rk') / f'libgstrk{name}.so'
        assert sha(base) == sha(base.parent/'active_ai_plugins'/base.name)
    assert 'display-fps' in Path('/root/jpeg_rk/rk_status_ai.c').read_text()
    sys.path.insert(0, '/root/jpeg_rk')
    from preproc_mode import read32, user_bar
    region, bar = user_bar()
    try:
        registers = {name: read32(region, offset) for name, offset in {
            'algorithm': 0xac, 'supported': 0x104, 'requested_mode': 0xa4,
            'applied_mode': 0x100, 'preproc_fault': 0xa8, 'raw_fault': 0x94,
            'jpeg_fault': 0xcc, 'qf_request': 0xb8, 'qf_applied_raw': 0xf8,
            'input_rate': 0xf0}.items()}
    finally:
        region.close()
    manifest = {'host_date': '2026-10-13', 'host_timezone': 'Asia/Shanghai',
                'board_time_untrusted': time.time(), 'monotonic_seconds': time.monotonic(),
                'bar': str(bar), 'registers': registers, 'files': []}
    for path in FILES:
        info = path.stat()
        manifest['files'].append({'path': str(path), 'archive_path': str(path).lstrip('/'),
                                  'bytes': info.st_size, 'mode': oct(info.st_mode & 0o7777),
                                  'sha256': sha(path)})
    metadata = {'uname': command(['uname', '-a']),
                'os_release': Path('/etc/os-release').read_text(),
                'packages': command(['dpkg-query', '-W']),
                'loaded_modules': command(['lsmod']),
                'drm_state': command(['cat', '/sys/kernel/debug/dri/0/state']),
                'driver_vermagic': command(['modinfo', '-F', 'vermagic', '/root/jpeg_rk/milianke_jpeg_a.ko']),
                'service_state': command(['systemctl', 'show', 'pcie1-recover.service',
                                          'anlogic-sgdma.service', '-p', 'ActiveState', '-p', 'UnitFileState']),
                'rc_local_reference': Path('/etc/rc.local').read_text(),
                'processes': [], 'dependencies': {}, 'log_tails': {}}
    for path in FILES:
        if path.suffix == '.so' and 'active_ai_plugins' not in str(path):
            metadata['dependencies'][str(path)] = command(['ldd', str(path)])
    metadata['dependencies']['status_plane'] = command(['ldd', '/root/jpeg_rk/rk_hdmi_status_plane'])
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            argv = (proc/'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
            if any(token in argv for token in ('show_jpeg_hdmi_overlay.py', 'jpeg_qf_button.py',
                                               'rk_hdmi_status_plane', 'start_jpeg_hdmi_ai')):
                env = (proc/'environ').read_bytes().split(b'\0')
                allowed = [item.decode(errors='replace') for item in env
                           if item.startswith((b'JPEG_', b'RK_STATUS_', b'GST_PLUGIN_PATH=', b'GST_REGISTRY='))]
                maps = (proc/'maps').read_text(errors='replace')
                libraries = sorted(set(line.split()[-1] for line in maps.splitlines()
                                       if '/root/jpeg_rk/' in line and '.so' in line))
                metadata['processes'].append({'pid': int(proc.name), 'argv': argv,
                                              'relevant_environment': allowed,
                                              'mapped_project_libraries': libraries})
        except (OSError, PermissionError):
            pass
    for name, path in {
        'button': '/root/jpeg_rk/qf_button.log',
        'viewer': '/root/road_damage_yolov8n/hdmi_ai_ui_fixed.log',
        'host_viewer': '/root/jpeg_rk/pc_host_viewer.log',
        'live_fps_viewer': '/root/jpeg_rk/hdmi_fix_20261013/live_fps/viewer.log'}.items():
        if Path(path).is_file():
            with open(path, 'rb') as stream:
                stream.seek(max(0, Path(path).stat().st_size-16000))
                metadata['log_tails'][name] = stream.read().decode(errors='replace')
    metadata['host_status'] = command(['python3', '/root/jpeg_rk/pc_host_agent_v1.py',
                                      'inspect', 'eyJhY3Rpb24iOiJzdGF0dXMifQ=='])
    (ROOT/'manifest.json').write_text(json.dumps(manifest, indent=2))
    (ROOT/'environment.json').write_text(json.dumps(metadata, indent=2))
    (ROOT/'PAYLOAD_SHA256SUMS').write_text(''.join(
        f"{item['sha256']}  {item['archive_path']}\n" for item in manifest['files']))
    archive_path = ROOT/'board.tar.gz'
    with tarfile.open(archive_path, 'w:gz', dereference=True) as archive:
        for item in manifest['files']:
            archive.add(item['path'], arcname=item['archive_path'], recursive=False)
    for item in manifest['files']:
        assert sha(Path(item['path'])) == item['sha256'], 'File changed during capture'
    capture = {'archive': str(archive_path), 'bytes': archive_path.stat().st_size,
               'sha256': sha(archive_path), 'file_count': len(FILES)}
    (ROOT/'capture.json').write_text(json.dumps(capture, indent=2))
    print('RELEASE_CAPTURED', json.dumps(capture), flush=True)


if __name__ == '__main__':
    main()
