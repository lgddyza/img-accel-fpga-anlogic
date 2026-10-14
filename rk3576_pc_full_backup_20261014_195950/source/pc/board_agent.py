"""Small, stateless RK control RPC; uses existing production scripts and BAR API."""
import base64
import fcntl
import json
import math
import os
from pathlib import Path
import re
import signal
import struct
import subprocess
import sys
import time

ROOT = Path('/root/jpeg_rk')
MODEL = '/root/road_damage_yolov8n/road_damage_yolov8n_gray640_int8_rk3576.rknn'
LOG = ROOT / 'pc_host_viewer.log'
MODES = ('GRAY', 'GAUSS', 'CLAHE', 'GAUSS+CLAHE', 'SOBEL', 'BLACKHAT',
         'SOBEL+CLAHE', 'BLACKHAT+CLAHE')
LABELS = ('Alligator crack', 'Longitudinal crack', 'Oblique crack',
          'Pothole', 'Repair', 'Transverse crack')
NAMES = {'start_jpeg_hdmi_ai_fallback.sh', 'start_jpeg_hdmi_ai.sh',
         'start_jpeg_hdmi_60.sh', 'show_jpeg_hdmi_overlay.py',
         'show_jpeg_hdmi.py', 'jpeg_qf_button.py', 'rk_hdmi_status_plane'}
sys.path.insert(0, str(ROOT))


def processes():
    found = []
    for path in Path('/proc').glob('[0-9]*'):
        try:
            args = (path / 'cmdline').read_bytes().decode(errors='replace').split('\0')
            matched = next((Path(a).name for a in args if a.startswith(str(ROOT) + '/')
                            and Path(a).name in NAMES), None)
            if matched:
                stat = (path / 'stat').read_text().rsplit(')', 1)[1].split()
                found.append({'pid': int(path.name), 'ppid': int(stat[1]),
                              'start_ticks': stat[19], 'name': matched, 'args': args})
        except (OSError, ValueError, IndexError):
            pass
    return found


def alive(proc):
    try:
        stat = Path(f"/proc/{proc['pid']}/stat").read_text().rsplit(')', 1)[1].split()
        return stat[0] != 'Z' and stat[19] == proc['start_ticks']
    except (OSError, IndexError):
        return False


def stop_viewers():
    found = processes()
    # Stop fallback launchers before their children can exit and trigger a restart.
    roots = [p for p in found if p['name'].startswith('start_')]
    children = [p for p in found if p not in roots]
    for group in (roots, children):
        for proc in group:
            if alive(proc):
                try:
                    os.kill(proc['pid'], signal.SIGSTOP if proc in roots else signal.SIGTERM)
                except ProcessLookupError:
                    pass
    deadline = time.monotonic() + 3
    while any(alive(p) for p in children) and time.monotonic() < deadline:
        time.sleep(.05)
    for proc in children + roots:
        if alive(proc):
            try:
                os.kill(proc['pid'], signal.SIGKILL)
            except ProcessLookupError:
                pass
    deadline = time.monotonic() + 2
    while processes() and time.monotonic() < deadline:
        time.sleep(.05)
    if any(alive(p) for p in processes()):
        raise RuntimeError('Existing viewer did not stop; refusing a second capture process')


def read_fpga():
    from preproc_mode import user_bar, read32
    region, path = user_bar()
    try:
        tag = read32(region, 0xAC)
        if tag not in (0x45485032, 0x45485031, 0x434C4831):
            raise RuntimeError(f'Unknown preprocessing ABI 0x{tag:08x}')
        bitmap = read32(region, 0x104) & 255 if tag == 0x45485032 else (
            0x3f if tag == 0x45485031 else 0xf)
        quality = read32(region, 0xF8)
        jct = read32(region, 0xFC) == 0x4A435431
        return {'bar': str(path), 'tag': f'{tag:08x}', 'bitmap': bitmap,
                'mode_requested': read32(region, 0xA4), 'mode_applied': read32(region, 0x100),
                'preproc_fault': read32(region, 0xA8) & 1,
                'qf_requested': read32(region, 0xB8),
                'qf_applied': quality & 127 if jct and quality & 128 else None,
                'input_fps': 60 if read32(region, 0xF0) == 1 else 30,
                'jpeg_faults': read32(region, 0xCC), 'jpeg_status': read32(region, 0xB4),
                'tiles': [{'sent': read32(region, a), 'bytes': read32(region, b)}
                          for a, b in ((0xBC, 0xC4), (0xC0, 0xC8), (0xDC, 0xE0))]}
    finally:
        region.close()


def set_fpga(request):
    from preproc_mode import user_bar, read32, write32
    from jpeg_control import wait_for_quality
    current = read_fpga()
    mode, qf = request.get('mode'), request.get('qf')
    if mode is not None and (type(mode) is not int or not 0 <= mode <= 7
                             or not current['bitmap'] & (1 << mode)):
        raise ValueError('Unsupported preprocessing mode')
    if qf is not None and (type(qf) is not int or not 1 <= qf <= 100):
        raise ValueError('QF must be an integer in 1..100')
    region, _ = user_bar()
    try:
        if mode is not None:
            write32(region, 0xA4, mode)
            if read32(region, 0xA4) != mode:
                raise RuntimeError('FPGA mode request did not latch')
            deadline = time.monotonic() + 2
            while read32(region, 0x100) != mode:
                if time.monotonic() >= deadline:
                    raise RuntimeError('Mode requested but not applied: no camera SOF or K1 conflict')
                time.sleep(.01)
        if qf is not None:
            if read32(region, 0xFC) != 0x4A435431:
                raise RuntimeError('Verified live QF control needs JCT1')
            write32(region, 0xB8, qf)
            wait_for_quality(region, qf, True, 2)
    finally:
        region.close()
    result = read_fpga()
    if mode is not None and result['mode_applied'] != mode:
        raise RuntimeError('Preprocessing changed during control; possible simultaneous K1 press')
    if qf is not None and result['qf_applied'] != qf:
        raise RuntimeError('QF changed during control; possible simultaneous K1 press')
    if result['preproc_fault'] or result['jpeg_faults']:
        raise RuntimeError('FPGA reports a fault after applying parameters')
    return result


def boxes_snapshot():
    try:
        with open('/run/road_ai_boxes.bin', 'rb', buffering=0) as handle:
            for _ in range(4):
                handle.seek(0)
                data = handle.read(1560)
                magic, seq, stamp, count, _ = struct.unpack_from('<IIQII', data)
                handle.seek(4)
                end_seq = struct.unpack('<I', handle.read(4))[0]
                if magic == 0x52414942 and seq == end_seq and seq % 2 == 0 and count <= 64:
                    boxes = []
                    for i in range(count):
                        x1, y1, x2, y2, confidence, cls = struct.unpack_from('<fffffI', data, 24+i*24)
                        if not all(math.isfinite(x) for x in (x1, y1, x2, y2, confidence)):
                            continue
                        boxes.append({'label': LABELS[cls] if cls < 6 else str(cls), 'class': cls,
                                      'confidence': confidence, 'xyxy': [x1, y1, x2, y2]})
                    return {'seq': seq, 'updated_us': stamp,
                            'age_ms': max(0, time.monotonic_ns()/1000-stamp)/1000, 'boxes': boxes}
    except (OSError, struct.error):
        pass
    return None


def tail(path, size=20000):
    try:
        with path.open('rb') as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell()-size))
            return f.read().decode('utf-8', errors='replace')
    except OSError:
        return ''


def log_stats(found):
    viewer = next((p for p in found if p['name'].startswith('show_')), None)
    if not viewer:
        return {}, ''
    try:
        path = Path(os.readlink(f"/proc/{viewer['pid']}/fd/1"))
        if not path.is_file():
            return {}, ''
        text = tail(path)
        stats = {'log_path': str(path), 'log_age_s': max(0, time.time()-path.stat().st_mtime)}
    except OSError:
        return {}, ''
    patterns = {
        'hdmi_fps': r'HDMI JPEG sink FPS=([\d.]+)',
        'hdmi_dropped_rate': r'HDMI JPEG sink FPS=[\d.]+ dropped=([\d.]+)',
        'reconstructed_avg_fps': r'distinct=\d+ rate=([\d.]+) fps',
        'unpaired': r'reconstructed=\d+ unpaired=(\d+)',
        'queue_overruns': r'HDMI queue overruns=(\d+)',
        'present_queue_overruns': r'HDMI present overruns=(\d+)',
        'ai_avg_ms': r'AI submitted=\d+ completed=\d+ rate=[\d.]+ fps mean_ms=([\d.]+)',
        'ai_avg_fps': r'AI submitted=\d+ completed=\d+ rate=([\d.]+) fps',
    }
    for name, pattern in patterns.items():
        values = re.findall(pattern, text)
        if values:
            stats[name] = float(values[-1])
    if 'present_queue_overruns' in stats:
        stats['processing_queue_overruns'] = stats.get('queue_overruns', 0)
        stats['queue_overruns'] = stats['processing_queue_overruns'] + stats['present_queue_overruns']
    return stats, '\n'.join(text.splitlines()[-22:])


def resource_snapshot():
    ticks = {}
    for line in Path('/proc/stat').read_text().splitlines():
        fields = line.split()
        if fields and re.fullmatch(r'cpu\d*', fields[0]):
            values = [int(value) for value in fields[1:9]]
            ticks[fields[0]] = {'total': sum(values), 'idle': values[3]+values[4]}
    result = {'cpu': {'sample_s': time.monotonic(), 'ticks': ticks,
                      'boot_id': Path('/proc/sys/kernel/random/boot_id').read_text().strip()},
              'npu_load_percent': None, 'npu_core_load_percent': [], 'gpu_load_percent': None}
    try:
        text = Path('/sys/kernel/debug/rknpu/load').read_text()
        loads = [min(100, int(v)) for v in re.findall(r'Core\d+:\s*(\d+)%', text)]
        if loads:
            result['npu_core_load_percent'] = loads
            result['npu_load_percent'] = sum(loads)/len(loads)
    except (OSError, ValueError):
        pass
    for path in Path('/sys/class/devfreq').glob('*gpu*/load'):
        try:
            result['gpu_load_percent'] = min(100, int(path.read_text().split('@', 1)[0]))
        except (OSError, ValueError):
            pass
    interfaces = []
    for path in Path('/sys/class/net').glob('*'):
        if path.name == 'lo':
            continue
        try:
            if (path/'operstate').read_text().strip() == 'up':
                interfaces.append({'name': path.name, 'speed_mbps': int((path/'speed').read_text())})
        except (OSError, ValueError):
            pass
    result['network_links'] = interfaces
    return result


def capture_snapshot(viewer):
    snapshots = []
    if not viewer:
        return snapshots
    for tile in range(3):
        try:
            sample = json.loads(Path(f'/run/jpeg-rk-tile{tile}-telemetry.json').read_text())
            if (sample['pid'] == viewer['pid'] and sample['tile'] == tile and
                    0 <= time.monotonic()-sample['sample_s'] < 3):
                snapshots.append(sample)
        except (OSError, ValueError, KeyError, TypeError):
            pass
    return snapshots


def status():
    found = processes()
    ai = next((p for p in found if p['name'] == 'show_jpeg_hdmi_overlay.py'), None)
    video = next((p for p in found if p['name'] == 'show_jpeg_hdmi.py'), None)
    result = {'agent_version': 1, 'monotonic_s': time.monotonic(),
              'hostname': os.uname().nodename, 'runtime': 'ai' if ai else 'video' if video else 'stopped',
              'viewer_pid': (ai or video or {}).get('pid'), 'processes': found}
    if ai or video:
        for flag, name, convert in (('--ai-interval', 'interval', int),
                                    ('--ai-confidence', 'confidence', float),
                                    ('--connector', 'connector', int)):
            try:
                viewer_args = (ai or video)['args']
                result[name] = convert(viewer_args[viewer_args.index(flag)+1])
            except (ValueError, IndexError):
                pass
    result['ai'] = boxes_snapshot() if ai else None
    try:
        result['fpga'] = read_fpga()
    except Exception as exc:
        result['fpga_error'] = str(exc)
    result['stats'], result['log'] = log_stats(found)
    result.update(resource_snapshot())
    result['pcie_capture'] = capture_snapshot(ai or video)
    mem = dict(re.findall(r'^(\w+):\s+(\d+)', Path('/proc/meminfo').read_text(), re.M))
    result['memory_total_mb'] = int(mem['MemTotal'])/1024
    result['memory_used_mb'] = (int(mem['MemTotal'])-int(mem.get('MemAvailable', mem['MemFree'])))/1024
    result['load'] = os.getloadavg()[0]
    temps = []
    for zone in Path('/sys/class/thermal').glob('thermal_zone*'):
        try:
            temps.append({'name': (zone/'type').read_text().strip(),
                          'celsius': int((zone/'temp').read_text())/1000})
        except (OSError, ValueError):
            pass
    result['temperatures'] = temps
    result['npu_mhz'] = None
    for path in Path('/sys/class/devfreq').glob('*npu*/cur_freq'):
        try:
            result['npu_mhz'] = int(path.read_text())/1e6
        except (OSError, ValueError):
            pass
    result['monotonic_s'] = time.monotonic()
    return result


def start(request):
    runtime = request.get('runtime')
    if runtime not in ('ai', 'video'):
        raise ValueError('Runtime must be ai or video')
    interval = request.get('interval', 2)
    confidence = request.get('confidence', .1)
    connector = request.get('connector', 188)
    if type(interval) is not int or not 1 <= interval <= 120:
        raise ValueError('Inference interval must be 1..120')
    if type(confidence) not in (int, float) or not math.isfinite(confidence) or not 0 <= confidence <= 1:
        raise ValueError('Confidence must be 0..1')
    if type(connector) is not int or not 0 < connector <= 10000:
        raise ValueError('Invalid HDMI connector')
    script = ROOT / ('start_jpeg_hdmi_ai_fallback.sh' if runtime == 'ai' else 'start_jpeg_hdmi_60.sh')
    if not script.is_file() or (runtime == 'ai' and not Path(MODEL).is_file()):
        raise RuntimeError('Production script/model not installed')
    read_fpga()
    initialize()
    old = status()
    if (not request.get('restart') and old['runtime'] == runtime and
            old.get('connector') == connector and
            (runtime == 'video' or (old.get('interval') == interval and
                                   old.get('confidence') == confidence))):
        return {'requested_runtime': runtime, 'status': old, 'already_running': True}
    stop_viewers()
    env = dict(os.environ, JPEG_AI_INTERVAL=str(interval), JPEG_AI_CONFIDENCE=str(confidence),
               JPEG_PAIR_DIAG='0', JPEG_AI_SECONDS='0', JPEG_STATUS_MODE='inframe', JPEG_NO_OSD='0')
    env.pop('RK_STATUS_SNAPSHOT', None)
    with LOG.open('wb') as log:
        child = subprocess.Popen(['sh', str(script), str(connector)], stdin=subprocess.DEVNULL,
                                 stdout=log, stderr=subprocess.STDOUT, env=env, start_new_session=True)
    desired = 'show_jpeg_hdmi_overlay.py' if runtime == 'ai' else 'show_jpeg_hdmi.py'
    deadline = time.monotonic()+15
    while time.monotonic() < deadline:
        if any(p['name'] == desired for p in processes()):
            current = status()
            fresh_video = (current['stats'].get('hdmi_fps') is not None and
                           current['stats'].get('log_age_s', 99) < 3 and
                           current.get('fpga', {}).get('jpeg_status', 0) & 1)
            ai = current.get('ai')
            fresh_ai = runtime == 'video' or (ai and ai['seq'] > 2 and ai['age_ms'] < 2000)
            if fresh_video and fresh_ai:
                return {'launched_pid': child.pid, 'requested_runtime': runtime, 'status': current}
        if child.poll() is not None:
            raise RuntimeError('Viewer exited: ' + tail(LOG, 3000))
        time.sleep(.2)
    detail = tail(Path('/root/road_damage_yolov8n/hdmi_ai_ui_fixed.log'), 2000) if runtime == 'ai' else ''
    raise RuntimeError('Viewer did not produce fresh frames within 15s: ' + tail(LOG, 1000)+detail)


def initialize():
    endpoint = any((p/'vendor').exists() and (p/'vendor').read_text().strip() == '0x1edb'
                   for p in Path('/sys/bus/pci/devices').glob('*'))
    if not endpoint:
        # A failed cold-boot probe leaves this controller unbound. Never unbind a live bus.
        controller = Path('/sys/bus/platform/devices/2a210000.pcie')
        if controller.exists() and not (controller/'driver').exists():
            Path('/sys/bus/platform/drivers/rk-pcie/bind').write_text('2a210000.pcie')
        Path('/sys/bus/pci/rescan').write_text('1')
        deadline = time.monotonic()+5
        while time.monotonic() < deadline:
            try:
                read_fpga()
                break
            except RuntimeError:
                time.sleep(.25)
    fpga = read_fpga()
    loaded = Path('/proc/modules').read_text()
    commands = [['modprobe', 'anlogic_pci']]
    commands += [['insmod', str(ROOT/(name+'.ko'))] for name in
                 ('milianke_jpeg_a', 'milianke_jpeg_b', 'milianke_jpeg_c')
                 if not re.search(r'^'+name+r' ', loaded, re.M)]
    for command in commands:
        done = subprocess.run(command, capture_output=True, text=True, timeout=10)
        if done.returncode:
            raise RuntimeError('Driver initialization failed: '+done.stderr.strip())
    return fpga


def dispatch(request):
    action = request.get('action')
    if action == 'preview':
        current = status()
        try:
            preview = json.loads(Path('/run/rk-network-preview.json').read_text())
        except (OSError, ValueError):
            raise RuntimeError('Network preview is not installed in the running viewer')
        if preview.get('pid') != current.get('viewer_pid') or time.monotonic()-preview['sample_s'] > 5:
            raise RuntimeError('Start HDMI output before starting network preview')
        return preview
    if action == 'status':
        return status()
    if action == 'logs':
        return {'log': status()['log']}
    with open('/run/pc_host_control.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if action == 'start':
            return start(request)
        if action == 'stop':
            stop_viewers()
            return status()
        if action == 'set_fpga':
            return set_fpga(request)
        if action == 'initialize':
            return initialize()
        raise ValueError('Unknown RPC action')


def main():
    token = sys.argv[1]
    try:
        request = json.loads(base64.b64decode(sys.argv[2]))
        response = {'ok': True, 'data': dispatch(request)}
    except Exception as exc:
        response = {'ok': False, 'error': f'{type(exc).__name__}: {exc}'}
    print('\nRKRPC_' + token + ':' + json.dumps(response, ensure_ascii=True, allow_nan=False), flush=True)


if __name__ == '__main__':
    main()
