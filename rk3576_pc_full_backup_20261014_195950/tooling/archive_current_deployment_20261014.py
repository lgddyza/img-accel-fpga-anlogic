"""Read the deployed RK files over SFTP and make a verified local backup."""
import base64
import hashlib
import io
import json
from pathlib import Path
import shlex
import shutil
import sys
import tarfile
from datetime import datetime
import zipfile

PROJECT = Path(__file__).resolve().parent
HOST = PROJECT.parent / 'rk_serial_host'
sys.path.insert(0, str(HOST / 'verification'))
from rk_work import connect
from capture_rk_release_20261013 import FILES

FILES = [path.as_posix() for path in FILES] + ['/root/jpeg_rk/network_preview.py']
PC_RELEASE = HOST / 'releases/RKVisionHost_20261014_hdmi_source_mjpeg.zip'
PC_SHA = 'd246240a7e6d7716f18cc3eab1d60668e31c6bcce46ab7e141946a5a24330cef'
PC_SOURCE = ('app.py', 'transport.py', 'board_agent.py', 'dashboard.py',
             'telemetry.py', 'video_preview.py', 'requirements.txt',
             'build_hdmi_preview.ps1', 'RKVisionHost.spec', 'package_release.py')


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def clean(value):
    if isinstance(value, dict):
        return {key: clean(item) for key, item in value.items()
                if not any(word in key.lower() for word in
                           ('token', 'password', 'secret', 'private_key'))}
    if isinstance(value, list):
        return [clean(item) for item in value]
    return value


def write_json(path, value):
    path.write_text(json.dumps(clean(value), indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


def remote_python(client, code):
    encoded = base64.b64encode(code.encode()).decode()
    command = 'python3 -c ' + shlex.quote('import base64;exec(base64.b64decode(' + repr(encoded) + '))')
    _, stdout, stderr = client.exec_command(command, timeout=120)
    data = stdout.read().decode()
    error = stderr.read().decode()
    if stdout.channel.recv_exit_status():
        raise RuntimeError(error)
    return json.loads(data)


def snapshot(client):
    return remote_python(client, '''
import base64,hashlib,json,os,subprocess
from pathlib import Path
files = ''' + repr(FILES) + '''
def command(args):
    p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=30)
    return {'exit_code':p.returncode,'output':p.stdout}
payload=[]
for name in files:
    path=Path(name); st=path.stat()
    with path.open('rb') as f: digest=hashlib.file_digest(f,'sha256').hexdigest()
    payload.append({'path':name,'archive_path':name.lstrip('/'),'bytes':st.st_size,
                    'mode':oct(st.st_mode & 0o7777),'uid':st.st_uid,'gid':st.st_gid,
                    'mtime':st.st_mtime,'sha256':digest})
reply=command(['python3','/root/jpeg_rk/pc_host_agent_v1.py','inspect','eyJhY3Rpb24iOiJzdGF0dXMifQ=='])
assert reply['exit_code']==0,reply
status=json.loads(reply['output'].split('RKRPC_inspect:',1)[1])
assert status['ok'],status
processes=[]
for proc in Path('/proc').iterdir():
    if not proc.name.isdigit(): continue
    try:
        argv=(proc/'cmdline').read_bytes().split(b'\\0')
        if not any(b'/root/jpeg_rk/' in a for a in argv): continue
        args=[a.decode(errors='replace') for a in argv if a]
        allowed=[e.decode(errors='replace') for e in (proc/'environ').read_bytes().split(b'\\0')
                 if e.startswith((b'JPEG_',b'RK_STATUS_',b'GST_PLUGIN_PATH=',b'GST_REGISTRY='))
                 and not any(k in e.upper() for k in (b'TOKEN',b'PASSWORD',b'SECRET'))]
        libraries=sorted(set(line.split()[-1] for line in (proc/'maps').read_text().splitlines()
                             if '/root/jpeg_rk/' in line and '.so' in line))
        processes.append({'pid':int(proc.name),'args':args,'environment':allowed,'project_libraries':libraries})
    except OSError: pass
environment={'uname':command(['uname','-a']),'os_release':Path('/etc/os-release').read_text(),
             'packages':command(['dpkg-query','-W']),'modules':command(['lsmod']),
             'services':command(['systemctl','show','pcie1-recover.service','anlogic-sgdma.service',
                                 '-p','ActiveState','-p','UnitFileState']),
             'network':command(['ip','-br','addr']),
             'kernel_module_vermagic':command(['modinfo','-F','vermagic','/root/jpeg_rk/milianke_jpeg_a.ko']),
             'processes':processes,'dependencies':{}}
for name in files:
    if name.endswith('.so') and '/active_ai_plugins/' not in name:
        environment['dependencies'][name]=command(['ldd',name])
try: preview=json.loads(Path('/run/rk-network-preview.json').read_text())
except OSError: preview={}
print(json.dumps({'files':payload,'status':status['data'],'preview':preview,'environment':environment}))
''')


def main():
    assert sha(PC_RELEASE) == PC_SHA, 'PC release differs from verified version'
    name = 'rk3576_pc_full_backup_' + datetime.now().strftime('%Y%m%d_%H%M%S')
    root = PROJECT / 'releases' / name
    root.mkdir(exist_ok=False)
    client = connect()
    try:
        before = snapshot(client)
        write_json(root / 'environment.json', before['environment'])
        write_json(root / 'runtime_before.json', {'status': before['status'], 'preview': before['preview']})
        write_json(root / 'manifest.json', {'captured_pc_time': datetime.now().isoformat(),
                                          'timezone': 'Asia/Shanghai', 'files': before['files']})
        print(f"Capturing {len(before['files'])} deployed files", flush=True)
        with client.open_sftp() as sftp, tarfile.open(root / 'board.tar.gz', 'w:gz') as archive:
            for entry in before['files']:
                with sftp.open(entry['path'], 'rb') as remote:
                    remote.prefetch(entry['bytes'], max_concurrent_requests=8)
                    data = remote.read()
                assert len(data) == entry['bytes'], entry['path']
                assert hashlib.sha256(data).hexdigest() == entry['sha256'], entry['path']
                info = tarfile.TarInfo(entry['archive_path'])
                info.size, info.mode, info.mtime = len(data), int(entry['mode'], 8), entry['mtime']
                info.uid, info.gid = entry['uid'], entry['gid']
                archive.addfile(info, io.BytesIO(data))
        after = snapshot(client)
    finally:
        client.close()
    assert {e['path']: e['sha256'] for e in before['files']} == {
        e['path']: e['sha256'] for e in after['files']}, 'Deployment changed during capture'
    write_json(root / 'runtime_after.json', {'status': after['status'], 'preview': after['preview']})
    expected = {e['archive_path']: e for e in before['files']}
    source = root / 'source' / 'board'
    contents = {}
    with tarfile.open(root / 'board.tar.gz') as archive:
        assert set(archive.getnames()) == set(expected)
        for member in archive:
            entry = expected[member.name]
            data = archive.extractfile(member).read()
            assert len(data) == entry['bytes'] and hashlib.sha256(data).hexdigest() == entry['sha256']
            assert member.mode == int(entry['mode'], 8)
            contents[member.name] = data
            path = Path(member.name)
            if path.suffix in ('.py', '.sh', '.c', '.cpp', '.h', '.conf', '.service') or path.name == 'Makefile':
                target = source / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
    mapped = {library for p in before['environment']['processes'] for library in p['project_libraries']}
    assert mapped.issubset(set(FILES)), f'Missing mapped project libraries: {mapped-set(FILES)}'
    (root / 'PAYLOAD_SHA256SUMS').write_text(''.join(
        f"{e['sha256']}  {e['archive_path']}\n" for e in before['files']), encoding='ascii')
    print('Board payload verified; collecting PC distribution', flush=True)
    with zipfile.ZipFile(PC_RELEASE) as archive:
        manifest = json.loads(archive.read('manifest.json'))
        assert archive.testzip() is None
        for entry in manifest['files']:
            data = archive.read(entry['path'])
            assert len(data) == entry['bytes'] and hashlib.sha256(data).hexdigest() == entry['sha256']
            path = Path(entry['path'])
            assert not path.is_absolute() and '..' not in path.parts
            if entry['path'].startswith('RKVisionHost/'):
                current = HOST / 'dist_hdmi_preview' / path
                assert current.is_file() and sha(current) == entry['sha256'], str(current)
                target = root / 'pc' / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
        for filename in PC_SOURCE:
            current = HOST / filename
            if 'source/' + filename in archive.namelist():
                assert current.read_bytes() == archive.read('source/' + filename), filename
            target = root / 'source' / 'pc' / filename
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(current, target)
        write_json(root / 'pc' / 'release_manifest.json', manifest)
    assert (root / 'pc/RKVisionHost/_internal/board_agent.py').read_bytes() == contents['root/jpeg_rk/pc_host_agent_v1.py']
    assert (root / 'source/pc/board_agent.py').read_bytes() == contents['root/jpeg_rk/pc_host_agent_v1.py']
    (root / 'pc/launch.cmd').write_bytes(b'@echo off\r\nstart "" "%~dp0RKVisionHost\\RKVisionHost.exe"\r\n')
    shutil.copy2(HOST / 'README.md', root / 'pc/README_HISTORY.md')
    evidence = root / 'evidence'
    evidence.mkdir()
    for filename in ('REPORT.md', 'background_comparison.json', 'deployment.json'):
        original = HOST / 'verification/preview_cadence_20261014' / filename
        if original.suffix == '.json':
            write_json(evidence / filename, json.loads(original.read_text(encoding='utf-8')))
        else:
            shutil.copy2(original, evidence / filename)
    rollback = root / 'rollback'
    rollback.mkdir()
    shutil.copy2(HOST / 'verification/preview_cadence_20261014/before_network_preview.py', rollback / 'before_network_preview.py')
    shutil.copy2(PROJECT / 'release_docs_20261013/build_runtime.sh', root / 'build_runtime.sh')
    tooling = root / 'tooling'
    tooling.mkdir()
    shutil.copy2(Path(__file__), tooling / Path(__file__).name)
    write_docs(root, before)
    same_process = before['status']['viewer_pid'] == after['status']['viewer_pid']
    stable_settings = all(before['status'].get(k) == after['status'].get(k)
                          for k in ('runtime', 'interval', 'confidence', 'connector')) and all(
        before['status']['fpga'][k] == after['status']['fpga'][k]
        for k in ('mode_requested', 'mode_applied', 'qf_requested', 'qf_applied', 'input_fps'))
    verification = {'payload_files': len(expected), 'source_hashes_unchanged': True,
                    'tar_hash_size_mode_verified': True, 'mapped_project_libraries_included': True,
                    'pc_release_sha256': PC_SHA, 'pc_archive_manifest_verified': True,
                    'pc_matches_current_distribution': True, 'pc_board_agent_identical': True,
                    'viewer_pid_unchanged': same_process, 'runtime_settings_unchanged': stable_settings,
                    'board_archive_sha256': sha(root / 'board.tar.gz'),
                    'restore_on_fresh_system_tested': False,
                    'credentials_included': False}
    write_json(root / 'verification.json', verification)
    files = sorted(p for p in root.rglob('*') if p.is_file())
    (root / 'SHA256SUMS').write_text(''.join(
        f'{sha(p)}  {p.relative_to(root).as_posix()}\n' for p in files), encoding='utf-8')
    zip_path = root.with_suffix('.zip')
    assert not zip_path.exists()
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(p for p in root.rglob('*') if p.is_file()):
            archive.write(path, name + '/' + path.relative_to(root).as_posix(),
                          compress_type=zipfile.ZIP_STORED if path.suffix == '.gz' else zipfile.ZIP_DEFLATED)
    with zipfile.ZipFile(zip_path) as archive:
        assert archive.testzip() is None
        assert len(archive.namelist()) == len(files) + 1
        for path in root.rglob('*'):
            if path.is_file():
                assert hashlib.sha256(archive.read(name + '/' + path.relative_to(root).as_posix())).hexdigest() == sha(path)
    digest = sha(zip_path)
    zip_path.with_suffix('.zip.sha256').write_text(f'{digest}  {zip_path.name}\n', encoding='ascii')
    print(json.dumps({'zip': str(zip_path), 'bytes': zip_path.stat().st_size,
                      'sha256': digest, 'verification': verification}, indent=2), flush=True)


def write_docs(root, capture):
    status = capture['status']
    mode_names = ['gray', 'gauss', 'he', 'all', 'sobel', 'blackhat', 'sobel-clahe', 'blackhat-clahe']
    fpga = status['fpga']
    settings = {'ai_interval': status['interval'], 'confidence': status['confidence'],
                'connector': status['connector'], 'mode': fpga['mode_applied'],
                'qf': fpga['qf_applied'], 'input_fps': fpga['input_fps'],
                'preview': clean(capture['preview'])}
    write_json(root / 'RESTORE_SETTINGS.json', settings)
    start = '''#!/bin/sh
set -eu
test "$(id -u)" = 0 || { echo 'Run as root' >&2; exit 1; }
test "$(uname -r)" = 6.1.99 || { echo 'Matching kernel 6.1.99 required' >&2; exit 1; }
if pgrep -f '(^|/| )(show_jpeg_hdmi[^ ]*\\.py|start_jpeg_hdmi[^ ]*\\.sh|jpeg_qf_button\\.py)( |$)' >/dev/null; then
    echo 'Stop the current viewer and K1 helper before restoring or starting.' >&2
    exit 1
fi
sh /usr/local/sbin/pcie1-recover.sh
modprobe anlogic_pci
for lane in a b c; do
    name="milianke_jpeg_$lane"
    if [ ! -d "/sys/module/$name" ]; then insmod "/root/jpeg_rk/$name.ko"; fi
done
python3 -c 'import sys; sys.path.insert(0,"/root/jpeg_rk"); from preproc_mode import user_bar,read32; r,p=user_bar(); tag=read32(r,0xac); modes=read32(r,0x104); r.close(); assert tag==0x45485032 and modes==0xff, "EHP2 FPGA with eight modes required"'
python3 /root/jpeg_rk/preproc_mode.py "${PREPROC_MODE:-MODE}" --wait-applied
python3 /root/jpeg_rk/jpeg_control.py --quality "${JPEG_QUALITY:-QUALITY}" --rate 60
export JPEG_HDMI_SINK=kms JPEG_DECODER=software JPEG_TEMPORAL_METHOD=normalize
export JPEG_AI_INTERVAL="${JPEG_AI_INTERVAL:-INTERVAL}" JPEG_AI_CONFIDENCE="${JPEG_AI_CONFIDENCE:-CONFIDENCE}" JPEG_AI_SECONDS=0
export JPEG_STATUS_MODE=inframe JPEG_OUTPUT_FORMAT=RGBx JPEG_KMS_SYNC_MODE=auto
export JPEG_AI_MODEL=/root/road_damage_yolov8n/road_damage_yolov8n_gray640_int8_rk3576.rknn JPEG_PAIR_DIAG=0
exec sh /root/jpeg_rk/start_jpeg_hdmi_ai_fallback.sh "${1:-CONNECTOR}"
'''
    for key, value in {'MODE': mode_names[settings['mode']], 'QUALITY': settings['qf'],
                       'INTERVAL': settings['ai_interval'], 'CONFIDENCE': settings['confidence'],
                       'CONNECTOR': settings['connector']}.items():
        start = start.replace(':-' + key + '}', ':-' + str(value) + '}')
    (root / 'start.sh').write_text(start, encoding='utf-8', newline='\n')
    readme = f'''# RK3576 与 PC 上位机完整部署存档

存档时间：{datetime.now().isoformat(timespec='seconds')}，Asia/Shanghai。
版本：HDMI 同源 MJPEG 预览；YOLOv8n 灰度 640×640 INT8；RK3576 / 2GB。

## 内容与打开方式

- `board.tar.gz`：从板端实际文件只读取回，包含模型、HDMI/YOLO/K1/预处理控制、PCIe/JPEG 驱动、RKNN运行库、GStreamer插件、预览模块及原路径/权限/时间戳。
- `pc/RKVisionHost/`：当前完整 Windows 可执行程序及依赖。双击 `pc/launch.cmd` 或其中的 `RKVisionHost.exe`；须保留整个目录。
- `source/board/`、`source/pc/`：板端与上位机源码；PC源码构建用 `build_hdmi_preview.ps1`，需先建立 `.venv` 并安装requirements及PyInstaller。
- `environment.json`：内核、系统包、依赖、服务、运行进程与项目库清单。`runtime_before.json`/`runtime_after.json`为此次只读归档的实机快照。
- `manifest.json` / `PAYLOAD_SHA256SUMS` / `SHA256SUMS` / `verification.json`：文件校验及验证记录。
- `evidence/`：之前预览修复测试记录；其中参数和网速是历史数据，当前参数以 `RESTORE_SETTINGS.json` 为准。
- `rollback/before_network_preview.py`：预览修改前文件；不会自动回退。

本包不包含SSH私钥、登录密码、WiFi配置、系统镜像、训练数据或FPGA工程/bit。
运行库和驱动匹配当前aarch64 Debian12 / Linux6.1.99环境；系统动态依赖由原系统提供，并在环境清单中记录。

## 此次实机参数

| 项目 | 存档值 |
| --- | --- |
| HDMI connector | {settings['connector']} |
| 视频输入标称FPS | {settings['input_fps']} |
| YOLO输入 | 640×640，当前部署模型未变化 |
| 每N帧推理 | {settings['ai_interval']} |
| 置信度阈值 | {settings['confidence']} |
| 预处理模式 | {settings['mode']} / {mode_names[settings['mode']]} |
| JPEG QF | {settings['qf']} |
| HDMI | KMS，RGBx，软件解码3线程，normalize，实测FPS文字 |
| 网口预览 | HDMI最终sink输入帧，960×540，MJPEG quality80，约15 FPS上限 |
| RK地址 / PC地址 | 169.254.53.76 / 169.254.53.75，掩码255.255.0.0 |
| SSH / 备用串口 | root:22 / COM12:1500000 |

存档瞬时HDMI FPS：{status['stats'].get('hdmi_fps')}；运行以来YOLO平均FPS：{status['stats'].get('ai_avg_fps')}。
当前协商网速实测记录：{json.dumps(status.get('network_links', []), ensure_ascii=False)}。历史曾到千兆，不将历史网速当作当前网速。
上位机界面默认值可能不同，复现时按上表设置。`start.sh`默认值已按本次实机参数生成。
灰度模式0表示不启用高斯、CLAHE、Sobel、黑帽；原灰度通路及RK normalize仍保留。
该预览读取HDMI显示器输入端同一份像素，再缩放编码；不是物理屏幕截图。
历史静止场景测试背景明暗跳变明显降低；尚未收到用户对所有场景闪烁消失的最终确认。

## 恢复到同一板卡或同版本系统

当前正在运行，无需执行恢复。下列步骤仅供未来主动恢复使用，会覆盖包中同名部署文件。
先确认FPGA已加载八种模式EHP2位流，系统内核为6.1.99；先备份目标板上现有部署。
通过上位机“停止输出”停止查看器/K1，关闭预览。已加载的驱动如需替换，须在无采集进程时卸载，或恢复文件后重启板卡。
将存档目录传到板卡并进入该目录，以root执行：

```sh
sha256sum -c SHA256SUMS
tar -tzf board.tar.gz
tar -xzpf board.tar.gz -C /
cd /
sha256sum -c /path/to/backup/PAYLOAD_SHA256SUMS
depmod -a
systemctl daemon-reload
```

把 `/path/to/backup` 换成板卡实际存档目录。包保留两个PCIe服务的unit文件，原启用状态见environment.json；不会自动替换整套开机配置。
恢复驱动后重启可确保加载的模块和磁盘文件一致。确认PC与RK的直连IP后，可从存档目录运行：

```sh
nohup sh ./start.sh > /root/road_damage_yolov8n/hdmi_ai_ui_fixed.log 2>&1 < /dev/null &
```

也可通过PC上位机初始化PCIe，按上表设置模式/QF/interval/confidence再启动“显示 + YOLO”。
新电脑需自行配置登录：可通过已进入root shell的串口使用上位机“串口配置SSH密钥”，或使用已有合法登录方式。
预览令牌由运行进程生成，上位机连接后获取，不在存档中保存。
`build_runtime.sh`仅供有匹配开发依赖的SDK重编译用户态组件；驱动重编译另需匹配内核构建环境。

本次已核对板端文件读取前后SHA256、tar内文件大小/权限/内容、PC发布清单及整包ZIP内容。
没有停止或重新配置生产程序；是否有用户操作改变参数见verification.json。
没有在新系统上执行覆盖恢复测试，本包是部署备份，不能替代完整系统镜像。
'''
    (root / 'README.md').write_text(readme, encoding='utf-8')


if __name__ == '__main__':
    main()
