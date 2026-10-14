"""Build a portable, checksummed release; do not include local login credentials."""
import hashlib
import argparse
import json
from pathlib import Path
import zipfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dashboard', action='store_true')
    parser.add_argument('--video', action='store_true')
    parser.add_argument('--h264', action='store_true')
    parser.add_argument('--mjpeg', action='store_true')
    parser.add_argument('--stable', action='store_true')
    parser.add_argument('--hdmi-preview', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    distribution = root/('dist_hdmi_preview' if args.hdmi_preview else 'dist_preview_v3' if args.stable else 'dist_mjpeg' if args.mjpeg else 'dist_h264' if args.h264 else 'dist_video' if args.video else 'dist_dashboard' if args.dashboard else 'dist')/'RKVisionHost'
    assert (distribution/'RKVisionHost.exe').is_file(), 'Build the executable first'
    files = [(path, 'RKVisionHost/'+path.relative_to(distribution).as_posix())
             for path in distribution.rglob('*') if path.is_file()]
    files.append((root/'README.md', 'README.md'))
    for name in ('app.py', 'transport.py', 'board_agent.py', 'dashboard.py', 'telemetry.py', 'video_preview.py',
                 'requirements.txt', 'build.ps1', 'build_dashboard.ps1', 'test_telemetry.py', 'verify_dashboard_ui.py',
                 'test_host.py', 'verify_board.py', 'verify_ui.py', 'verify_live_ui.py'):
        files.append((root/name, 'source/'+name))
    evidence = root/'verification'/('preview_cadence_20261014' if args.hdmi_preview else 'pc_preview_stable_20261014' if args.stable else 'pc_mjpeg_20261014' if args.mjpeg else 'pc_h264_20261014' if args.h264 else 'pc_video_20261014' if args.video else 'dashboard' if args.dashboard else '')
    files += [(path, 'verification/'+path.relative_to(evidence).as_posix())
              for path in evidence.rglob('*') if path.is_file() and path.suffix in ('.json', '.png', '.md')]
    if args.dashboard:
        run = root.parent/'road_damage_yolov8n/runs/pc_dashboard_20261013'
        for name in ('board/capture_jpeg_tiles.py', 'before_telemetry.tar.gz', 'deployment.json'):
            files.append((run/name, 'rk_telemetry/'+name))
        files.append((root/'VIDEO_FEASIBILITY_20261013.md', 'VIDEO_FEASIBILITY_20261013.md'))
        files.append((root/'verification/deploy_dashboard.py', 'source/verification/deploy_dashboard.py'))
        files.append((root/'verification/rk_work.py', 'source/verification/rk_work.py'))
    if args.video:
        run = root.parent/'road_damage_yolov8n/runs/pc_video_20261014'
        for name in ('network_preview.py', 'show_jpeg_hdmi.py', 'show_jpeg_hdmi_overlay.py', 'capture_jpeg_tiles.py'):
            files.append((run/'board'/name, 'rk_video/'+name))
        files.append((root/'build_video.ps1', 'source/build_video.ps1'))
        for name in ('rk_work.py', 'verify_network_preview.py', 'verify_video_ui.py', 'record_video_deployment.py'):
            files.append((root/'verification'/name, 'source/verification/'+name))
        files.append((run/'before_video.tar.gz', 'rk_video/before_video.tar.gz'))
    if args.h264:
        run = root.parent/'road_damage_yolov8n/runs/pc_h264_20261014'
        for name in ('network_preview.py', 'show_jpeg_hdmi.py', 'show_jpeg_hdmi_overlay.py', 'capture_jpeg_tiles.py'):
            files.append((run/'board'/name, 'rk_video/'+name))
        files.append((root/'build_h264.ps1', 'source/build_h264.ps1'))
        files.append((root/'test_h264_preview.py', 'source/test_h264_preview.py'))
        for name in ('rk_work.py', 'verify_h264_performance.py', 'verify_video_ui.py', 'record_h264_deployment.py'):
            files.append((root/'verification'/name, 'source/verification/'+name))
        files.append((run/'before_h264.tar.gz', 'rk_video/before_h264.tar.gz'))
    if args.mjpeg or args.stable:
        run = root.parent/'road_damage_yolov8n/runs/pc_mjpeg_20261014'
        for name in ('network_preview.py', 'show_jpeg_hdmi.py', 'show_jpeg_hdmi_overlay.py', 'capture_jpeg_tiles.py'):
            files.append((run/'board'/name, 'rk_video/'+name))
        files.append((root/'build_mjpeg.ps1', 'source/build_mjpeg.ps1'))
        files.append((root/'test_mjpeg_preview.py', 'source/test_mjpeg_preview.py'))
        for name in ('rk_work.py', 'deploy_mjpeg_preview.py', 'verify_mjpeg_performance.py', 'verify_video_ui.py', 'record_mjpeg_deployment.py'):
            files.append((root/'verification'/name, 'source/verification/'+name))
        files.append((run/'before_mjpeg.tar.gz', 'rk_video/before_mjpeg.tar.gz'))
    if args.stable:
        for name in ('build_preview_stable.ps1', 'test_preview_render.py', 'test_preview_luma.py', 'preview_luma.py'):
            files.append((root/name, 'source/'+name))
        for name in ('diagnose_preview_flicker.py', 'verify_preview_rk_unchanged.py'):
            files.append((root/'verification'/name, 'source/verification/'+name))
    if args.hdmi_preview:
        run = root.parent/'road_damage_yolov8n/runs/pc_hdmi_preview_20261014'
        original = root.parent/'road_damage_yolov8n/runs/pc_video_20261014/board'
        files.append((run/'board/network_preview.py', 'rk_video/network_preview.py'))
        for name in ('show_jpeg_hdmi.py', 'show_jpeg_hdmi_overlay.py', 'capture_jpeg_tiles.py'):
            files.append((original/name, 'rk_video/'+name))
        files.append((root/'build_hdmi_preview.ps1', 'source/build_hdmi_preview.ps1'))
        files.append((evidence/'before_network_preview.py', 'rk_video/before_network_preview.py'))
        for name in ('rk_work.py', 'deploy_hdmi_sink_preview.py', 'test_hdmi_preview_pipeline.py',
                     'capture_preview_analysis.py', 'analyze_preview_background.py'):
            files.append((root/'verification'/name, 'source/verification/'+name))
    manifest = {'date': '2026-10-14' if args.video or args.h264 or args.mjpeg or args.stable or args.hdmi_preview else '2026-10-13', 'name': 'RKVisionHost', 'files': [
        {'path': name, 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        for path, name in files]}
    releases = root/'releases'
    releases.mkdir(exist_ok=True)
    release_name = 'RKVisionHost_20261014_hdmi_source_mjpeg' if args.hdmi_preview else 'RKVisionHost_20261014_mjpeg_stable_v3' if args.stable else 'RKVisionHost_20261014_mjpeg' if args.mjpeg else 'RKVisionHost_20261014_h264' if args.h264 else 'RKVisionHost_20261014_video' if args.video else 'RKVisionHost_20261013_dashboard' if args.dashboard else 'RKVisionHost_20261013'
    destination = releases/(release_name+'.zip')
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path, name in files:
            archive.write(path, name)
        archive.writestr('manifest.json', json.dumps(manifest, indent=2))
        archive.writestr('CHECKSUMS.sha256', '\n'.join(entry['sha256']+'  '+entry['path']
                                                      for entry in manifest['files'])+'\n')
    with zipfile.ZipFile(destination) as archive:
        for entry in manifest['files']:
            assert hashlib.sha256(archive.read(entry['path'])).hexdigest() == entry['sha256']
    sha = hashlib.sha256(destination.read_bytes()).hexdigest()
    (releases/(release_name+'.sha256')).write_text(sha+'  '+destination.name+'\n', encoding='ascii')
    print(f'PACKAGED {len(files)} files; {destination.stat().st_size} bytes; SHA256 {sha}')


if __name__ == '__main__':
    main()
