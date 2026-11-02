"""Publish STR4 only from current managed builds and completed regressions."""
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
SYN = ROOT/'dual_imx415_gray_demo_Runs/syn_1'
PHY = ROOT/'dual_imx415_gray_demo_Runs/phy_1'
OUT = ROOT/'build/str4_validation'
RELEASE = ROOT/'release/STR4_20261025'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stages(folder, names):
    result = {}
    for name in names:
        begin, end = [folder/f'.{name}.{suffix}.f' for suffix in ('begin', 'end')]
        if (folder/f'.{name}.error.f').exists() or not begin.is_file() or not end.is_file():
            raise SystemExit(f'Incomplete managed stage: {folder.name}/{name}')
        if end.stat().st_mtime < begin.stat().st_mtime:
            raise SystemExit('Stale managed stage: '+name)
        result[name] = dict(begin=begin.stat().st_mtime, end=end.stat().st_mtime)
    return result


def resources(path):
    text = path.read_text()
    result = {}
    for key in ('slice', 'eram', 'dsp'):
        match = re.search(r'^#'+key+r'\*?\s+(\d+)\s+out of\s+(\d+)\s+([\d.]+)%', text, re.M)
        if not match:
            raise SystemExit('Missing resource: '+key)
        result[key] = dict(used=int(match[1]), capacity=int(match[2]), percent=float(match[3]))
    return result


def main():
    inputs = json.loads((ROOT/'build/resource_inputs.json').read_text())
    for item in inputs:
        if digest(ROOT/item['path']) != item['sha256']:
            raise SystemExit('Changed build input: '+item['path'])
    integrity = json.loads((ROOT/'build/source_integrity.json').read_text())
    if integrity['errors'] or integrity.get('synthesis_project_check', {}).get('errors', ['missing']):
        raise SystemExit('Project source verification missing/failed')
    if "rdata<=32'h53545234" not in (ROOT/'rtl/v2_endpoint_body.vh').read_text():
        raise SystemExit('Not STR4 source')
    result = dict(stream_build='0x53545234', board_tested=False,
                  input_hashes_checked=len(inputs),
                  synthesis_stages=stages(SYN, ('read_design', 'opt_rtl', 'opt_gate')),
                  physical_stages=stages(PHY, ('opt_place', 'opt_route', 'bitgen')),
                  synthesis_resources=resources(SYN/'dual_imx415_gray_demo_gate.area'),
                  physical_resources=resources(PHY/'dual_imx415_gray_demo_phy.area'))
    latest = max((ROOT/item['path']).stat().st_mtime for item in inputs)
    if result['synthesis_stages']['read_design']['begin'] < latest:
        raise SystemExit('Synthesis predates current inputs')
    if result['physical_stages']['opt_place']['begin'] < result['synthesis_stages']['opt_gate']['end']:
        raise SystemExit('Physical build predates synthesis')
    timing_path = PHY/'dual_imx415_gray_demo_pr.timing'
    timing = timing_path.read_text()
    result['timing'] = {k: float(re.search(r'\b'+k+r':\s*([-\d.]+)ns', timing)[1])
                        for k in ('SWNS', 'STNS', 'HWNS', 'HTNS')}
    result['timing']['sta_coverage_percent'] = float(re.search(r'STA coverage\s*:\s*([\d.]+)%', timing)[1])
    if 'Confidence          : Routed' not in timing or any(result['timing'][k] < 0 for k in ('SWNS', 'STNS', 'HWNS', 'HTNS')):
        raise SystemExit('Routed setup/hold did not pass')
    if result['physical_resources']['eram']['used'] > 230:
        raise SystemExit('ERAM budget exceeded')
    logs = dict(row_credit='PASS row credits', isp_pause='PASS legacy ISP row-gap contract',
                isp_long_idle='idle=2105344 clocks, exact pixels and markers',
                isp_replay='PASS full 1080p shared ISP', endpoint_control='PASS AXI-Lite',
                str4_python_tests='OK',
                str4_final_pipeline_rate='PASS full source geometry and dual-60 service budget',
                str4_long_stress_pipeline_rate_backpressure='PASS full source geometry and backpressure recovery')
    result['simulation_logs'] = {}
    for name, marker in logs.items():
        path = ROOT/'build'/f'{name}.log'
        text = path.read_text(encoding='utf-8')
        if marker not in text or 'FATAL:' in text or 'FAILED (' in text:
            raise SystemExit('Regression incomplete/failed: '+name)
        result['simulation_logs'][name] = digest(path)
    result['image_checks'] = {}
    for name in ('str4_final_pipeline_rate', 'str4_long_stress_pipeline_rate_backpressure'):
        checks = json.loads((ROOT/'build'/name/'image_checks.json').read_text())
        if len(checks) != 2 or any(x['psnr_db'] < 32 for x in checks):
            raise SystemExit('JPEG image checks incomplete/failed: '+name)
        if 'stress' in name and checks[0]['jpeg_sha256'] != checks[1]['jpeg_sha256']:
            raise SystemExit('Pausing changed JPEG content')
        result['image_checks'][name] = checks
        text = (ROOT/'build'/f'{name}.log').read_text()
        result[name+'_service'] = [dict(frame=int(f), service_ns=float(ns))
            for f, ns in re.findall(r'SERVICE camera=(\d+) ns=([\d.]+)', text)]
    baseline = ROOT/'build/str3_validation/summary.json'
    if baseline.is_file():
        old = json.loads(baseline.read_text())['image_checks']
        for new_name, old_name in (
                ('str4_final_pipeline_rate', 'str3_final_pipeline_rate'),
                ('str4_long_stress_pipeline_rate_backpressure', 'str3_final_stress_pipeline_rate_backpressure')):
            if [x['jpeg_sha256'] for x in result['image_checks'][new_name]] != [x['jpeg_sha256'] for x in old[old_name]]:
                raise SystemExit('JPEG differs from the archived STR3 reference: '+new_name)
        result['jpeg_matches_archived_str3_reference'] = True
    bit = PHY/'dual_imx415_gray_demo_compress.bit'
    if bit.stat().st_mtime < result['physical_stages']['bitgen']['begin']:
        raise SystemExit('Stale bitstream')
    probe = ROOT/'build/str4_software_probe'
    native_check = probe/'native_check.txt'
    if 'PASS strict native decoder' not in native_check.read_text(encoding='utf-8'):
        raise SystemExit('Native strict decoder check missing/failed')
    native = probe/'rk_results/libjpeg_str4.so'
    source = probe/'rk_results/jpeg_native_strict.c'
    if digest(source) != digest(ROOT/'rk/jpeg_native_strict.c'):
        raise SystemExit('Native decoder tested source differs')
    strict = json.loads((probe/'rk_results/strict30/result.json').read_text())
    if strict['decoder_validation'] != 'strict' or strict['workers_still_alive']:
        raise SystemExit('RK strict software probe incomplete')
    result['rk_software_probe'] = dict(fpga_build=strict['bar_samples'][0]['stream_diagnostics']['build'],
        elapsed=strict['elapsed'], decoded_frames=strict['decoded_frames'],
        fps=[n/strict['elapsed'] for n in strict['decoded_frames']],
        rejected_frames=strict['decode_rejected_frames'], packet_streams=strict['packet_streams'],
        dma_errors=strict['dma_errors'], native_sha256=digest(native),
        note='STR4 software on existing STR3 hardware; not a STR4 board test')
    OUT.mkdir(exist_ok=True)
    RELEASE.mkdir(parents=True, exist_ok=True)
    destination = RELEASE/'dual_imx415_gray_demo_STR4_20261025_compress.bit'
    shutil.copy2(bit, destination)
    result['bitstream'] = dict(path=destination.relative_to(ROOT).as_posix(),
                               size=destination.stat().st_size, sha256=digest(destination))
    for label, folder, files in (
            ('synthesis', SYN, ('run.log', 'dual_imx415_gray_demo_gate.area', 'dual_imx415_gray_demo.prj')),
            ('physical', PHY, ('run.log', 'dual_imx415_gray_demo_phy.area', timing_path.name,
                              'dual_imx415_gray_demo_phy.ts'))):
        target = OUT/label
        target.mkdir(exist_ok=True)
        for name in files:
            shutil.copy2(folder/name, target/name)
    for name in logs:
        shutil.copy2(ROOT/'build'/f'{name}.log', OUT/f'{name}.log')
    for name in ('resource_inputs.json', 'source_integrity.json'):
        shutil.copy2(ROOT/'build'/name, OUT/name)
    shutil.copy2(native_check, OUT/native_check.name)
    (OUT/'summary.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    for path in (OUT/'summary.json', ROOT/'build/resource_inputs.json', ROOT/'RTL_STR4_20261025.md'):
        shutil.copy2(path, RELEASE/path.name)
    software = RELEASE/'rk'
    software.mkdir(exist_ok=True)
    for path in (ROOT/'rk').iterdir():
        if path.suffix in ('.py', '.c'):
            shutil.copy2(path, software/path.name)
    shutil.copy2(native, software/native.name)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
