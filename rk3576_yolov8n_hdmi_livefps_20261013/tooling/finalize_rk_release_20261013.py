"""Fetch and verify a complete board release, then assemble the PC archive."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tarfile
import zipfile

PROJECT = Path(__file__).resolve().parent
HOST = PROJECT.parent/'rk_serial_host'
sys.path.insert(0, str(HOST/'verification'))
from rk_work import connect

NAME = 'rk3576_yolov8n_hdmi_livefps_20261013'
ROOT = PROJECT/'releases'/NAME
FIX = PROJECT/'runs/rk_hdmi_fix_20261013'


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    ROOT.mkdir(exist_ok=False)
    client = connect()
    try:
        with client.open_sftp() as sftp:
            for name in ('board.tar.gz', 'manifest.json', 'environment.json',
                         'PAYLOAD_SHA256SUMS', 'capture.json'):
                sftp.get('/root/road_damage_yolov8n/release_hdmi_livefps_20261013/'+name,
                         str(ROOT/name))
    finally:
        client.close()
    manifest = json.loads((ROOT/'manifest.json').read_text())
    capture = json.loads((ROOT/'capture.json').read_text())
    assert sha(ROOT/'board.tar.gz') == capture['sha256']
    expected = {entry['archive_path']: entry for entry in manifest['files']}
    data_by_name = {}
    with tarfile.open(ROOT/'board.tar.gz') as archive:
        assert len(archive.getmembers()) == len(expected) == capture['file_count']
        assert set(archive.getnames()) == set(expected)
        for member in archive:
            assert member.isfile(), member.name
            assert not member.name.startswith('/') and '..' not in Path(member.name).parts
            data = archive.extractfile(member).read()
            entry = expected[member.name]
            assert len(data) == entry['bytes']
            assert hashlib.sha256(data).hexdigest() == entry['sha256']
            assert member.mode == int(entry['mode'], 8)
            data_by_name[member.name] = data
            path = Path(member.name)
            if path.suffix in ('.c', '.cpp', '.h', '.py', '.sh', '.conf', '.service') or path.name == 'Makefile':
                dest = ROOT/'source/board'/path
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(data)
    for name in ('show_jpeg_hdmi.py', 'show_jpeg_hdmi_overlay.py'):
        code = data_by_name['root/jpeg_rk/'+name].decode()
        assert 'display-fps' in code and 'fps-measurements' in code
        compile(code, name, 'exec')
    assert b'display-fps' in data_by_name['root/jpeg_rk/libgstrkstatusai.so']
    for name in ('temporalai', 'statusai'):
        assert data_by_name[f'root/jpeg_rk/libgstrk{name}.so'] == data_by_name[
            f'root/jpeg_rk/active_ai_plugins/libgstrk{name}.so']
    pc = ROOT/'pc'
    pc.mkdir()
    pc_zip = HOST/'releases/RKVisionHost_20261013_hdmi_fix.zip'
    assert sha(pc_zip) == 'fb6578237f8949196fa14e89aea47cbfea4fb3a60c007039d0dc31dfe5dd07dc'
    shutil.copy2(pc_zip, pc/pc_zip.name)
    with zipfile.ZipFile(pc_zip) as archive:
        agent = next(p for p in archive.namelist() if p.endswith('/_internal/board_agent.py'))
        assert archive.read(agent) == data_by_name['root/jpeg_rk/pc_host_agent_v1.py']
    pc_source = ROOT/'source/pc'
    pc_source.mkdir(parents=True)
    for name in ('app.py', 'transport.py', 'board_agent.py', 'requirements.txt',
                 'RKVisionHost.spec', 'build.ps1', 'launch.cmd'):
        shutil.copy2(HOST/name, pc_source/name)
    assert (pc_source/'board_agent.py').read_bytes() == data_by_name['root/jpeg_rk/pc_host_agent_v1.py']
    pc_readme = (HOST/'README.md').read_text(encoding='utf-8')
    pc_readme = ('> 2026-10-13修复版补充：默认状态栏改为灰度图内绘制，HDMI FPS已改为实测值。'
                 '当前常驻interval=1，PC界面启动默认仍为2；需要复现本次性能请设置1。'
                 '下文独立状态层及固定FPS:60的描述属于修复前行为，以总包README为准。\n\n'+pc_readme)
    (pc/'README.md').write_text(pc_readme, encoding='utf-8')
    evidence = ROOT/'evidence'
    evidence.mkdir()
    for name in ('REPORT.md', 'regression_summary.json', 'live_fps_verification.json',
                 'evidence.tar.gz', 'osd_23.4.png'):
        shutil.copy2(FIX/name, evidence/name)
    rollback = ROOT/'rollback'
    rollback.mkdir()
    shutil.copy2(FIX/'rollback.tar.gz', rollback/'before_hdmi_fix.tar.gz')
    tooling = ROOT/'tooling'
    tooling.mkdir()
    for name in ('capture_rk_release_20261013.py', 'finalize_rk_release_20261013.py'):
        shutil.copy2(PROJECT/name, tooling/name)
    shutil.copy2(HOST/'verification/rk_work.py', tooling/'rk_work.py')
    for name in ('README.md', 'start.sh', 'build_runtime.sh'):
        shutil.copy2(PROJECT/'release_docs_20261013'/name, ROOT/name)
    environment = json.loads((ROOT/'environment.json').read_text())
    verification = {'capture_date': '2026-10-13', 'payload_files': capture['file_count'],
                    'payload_hash_size_mode_verified': True, 'live_fps_sources_verified': True,
                    'live_fps_binary_property_verified': True, 'pc_board_agent_identical': True,
                    'board_archive_sha256': capture['sha256'],
                    'board_model_sha256': next(e['sha256'] for e in expected.values()
                                               if e['path'].endswith('.rknn')),
                    'viewer_running_at_capture': any('show_jpeg_hdmi_overlay.py' in p['argv']
                                                     for p in environment['processes']),
                    'restore_on_fresh_system_tested': False,
                    'temporalgray_builds_identical': data_by_name['root/jpeg_rk/libgstrktemporalgray.so'] ==
                        data_by_name['root/jpeg_rk/active_ai_plugins/libgstrktemporalgray.so']}
    assert verification['viewer_running_at_capture']
    (ROOT/'verification.json').write_text(json.dumps(verification, indent=2))
    files = sorted(p for p in ROOT.rglob('*') if p.is_file())
    checks = ''.join(f'{sha(path)}  {path.relative_to(ROOT).as_posix()}\n' for path in files)
    (ROOT/'SHA256SUMS').write_text(checks, encoding='ascii')
    zip_path = ROOT.with_suffix('.zip')
    assert not zip_path.exists(), 'Do not overwrite an existing release'
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(p for p in ROOT.rglob('*') if p.is_file()):
            relative = path.relative_to(ROOT).as_posix()
            archive.write(path, NAME+'/'+relative,
                          compress_type=zipfile.ZIP_STORED if path.suffix in ('.gz', '.zip', '.png') else zipfile.ZIP_DEFLATED)
    with zipfile.ZipFile(zip_path) as archive:
        assert archive.testzip() is None
        assert len(archive.namelist()) == len(files)+1
        for path in files:
            assert hashlib.sha256(archive.read(NAME+'/'+path.relative_to(ROOT).as_posix())).hexdigest() == sha(path)
    zip_sha = sha(zip_path)
    zip_path.with_suffix('.zip.sha256').write_text(f'{zip_sha}  {zip_path.name}\n', encoding='ascii')
    print(json.dumps({'zip': str(zip_path), 'bytes': zip_path.stat().st_size,
                      'sha256': zip_sha, 'payload_files': capture['file_count'],
                      'release_files': len(files)+1, 'verification': verification}, indent=2))


if __name__ == '__main__':
    main()
