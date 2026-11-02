"""Publish PRF1 only after current managed implementation and simulations pass."""
from pathlib import Path
import hashlib
import json
import re
import shutil

from record_str4_results import stages, resources

ROOT = Path(__file__).resolve().parents[1]
SYN = ROOT / 'dual_imx415_gray_demo_Runs/syn_1'
PHY = ROOT / 'dual_imx415_gray_demo_Runs/phy_1'
RELEASE = ROOT / 'release/PRF1_20261027'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    inputs = json.loads((ROOT / 'build/resource_inputs.json').read_text())
    for item in inputs:
        if digest(ROOT / item['path']) != item['sha256']:
            raise SystemExit('Changed build input: ' + item['path'])
    integrity = json.loads((ROOT / 'build/source_integrity.json').read_text())
    if integrity['errors'] or integrity.get('synthesis_project_check', {}).get('errors', ['missing']):
        raise SystemExit('Managed project source verification missing/failed')
    if "rdata<=32'h50524631" not in (ROOT / 'rtl/v2_endpoint_body.vh').read_text():
        raise SystemExit('Not PRF1 source')
    result = dict(
        stream_build='0x50524631', capability_mask='0x23', board_tested=False,
        project='dual_imx415_gray_demo.al', top='dual_imx415_top', device='PH1A90SEG324-2',
        input_hashes_checked=len(inputs),
        synthesis_stages=stages(SYN, ('read_design', 'opt_rtl', 'opt_gate')),
        physical_stages=stages(PHY, ('opt_place', 'opt_route', 'bitgen')),
        synthesis_resources=resources(SYN / 'dual_imx415_gray_demo_gate.area'),
        physical_resources=resources(PHY / 'dual_imx415_gray_demo_phy.area'))
    # TD may rewrite the project entry without changing its content on open.
    # Its digest is checked above; other inputs and the manifest must predate
    # the managed Read Design run.
    latest = max((ROOT / item['path']).stat().st_mtime for item in inputs
                 if item['path'] != 'dual_imx415_gray_demo.al')
    latest = max(latest, (ROOT / 'build/resource_inputs.json').stat().st_mtime)
    if result['synthesis_stages']['read_design']['begin'] < latest:
        raise SystemExit('Synthesis predates current inputs')
    if result['physical_stages']['opt_place']['begin'] < result['synthesis_stages']['opt_gate']['end']:
        raise SystemExit('Physical build predates synthesis')
    timing_path = PHY / 'dual_imx415_gray_demo_pr.timing'
    timing = timing_path.read_text()
    result['timing'] = {key: float(re.search(r'\b' + key + r':\s*([-\d.]+)ns', timing)[1])
                        for key in ('SWNS', 'STNS', 'HWNS', 'HTNS')}
    result['timing']['sta_coverage_percent'] = float(
        re.search(r'STA coverage\s*:\s*([\d.]+)%', timing)[1])
    if 'Confidence          : Routed' not in timing or any(
            result['timing'][key] < 0 for key in ('SWNS', 'STNS', 'HWNS', 'HTNS')):
        raise SystemExit('Routed setup/hold did not pass')
    logs = {
        'preproc_full': 'PASS PRF1 1920x1080 cases=2 groups=1036800',
        'preproc_small_paused': 'PASS PRF1 64x24 cases=9',
        'compact_cdc': 'PASS', 'preproc_credit': 'PASS',
        'endpoint_control': 'PASS AXI-Lite', 'frame_store': 'PASS',
        'header': 'PASS', 'row_credit': 'PASS row credits',
        'prf1_host_tests': 'Ran 16 tests', 'prf1_protocol_tests': 'Ran 6 tests',
        'prf1_final_pipeline_rate': 'PASS full source geometry and dual-60 service budget',
    }
    result['simulation_logs'] = {}
    # The final window implementation must be covered by the full-size pixel
    # comparison and real JPEG integration test, rather than older executables.
    window_time = (ROOT / 'uisrc/01_rtl/gray_gauss4.v').stat().st_mtime
    for name, marker in logs.items():
        path = ROOT / 'build' / (name + '.log')
        contents = path.read_text(encoding='utf-8')
        if marker not in contents or 'FATAL:' in contents or 'FAILED (' in contents:
            raise SystemExit('Regression incomplete/failed: ' + name)
        if name.endswith('_tests') and not re.search(r'^OK\s*$', contents, re.M):
            raise SystemExit('Python tests did not complete successfully: ' + name)
        if name in ('preproc_full', 'prf1_final_pipeline_rate'):
            if (ROOT / 'build' / (name + '.vvp')).stat().st_mtime < window_time:
                raise SystemExit('Simulation predates final window: ' + name)
        result['simulation_logs'][name] = digest(path)
    pipeline = (ROOT / 'build/prf1_final_pipeline_rate.log').read_text()
    result['nominal_service_ns'] = [float(ns) for ns in re.findall(
        r'SERVICE camera=\d+ ns=([\d.]+)', pipeline)]
    if len(result['nominal_service_ns']) != 2 or max(result['nominal_service_ns']) > 8333333.33:
        raise SystemExit('Dual-60 simulation budget missing/failed')
    image_checks = json.loads((ROOT / 'build/prf1_final_pipeline_rate/image_checks.json').read_text())
    if len(image_checks) != 2 or min(item['psnr_db'] for item in image_checks) < 32:
        raise SystemExit('Final JPEG image comparison missing/failed')
    result['image_checks'] = image_checks
    result['limitations'] = [
        'Simulation is not a board throughput or HDMI measurement.',
        'CLAHE and automatic feature-to-mode selection are not implemented.',
        'Older noisy-input/backpressure JPEG tests cover the preceding window implementation; '
        'final window has exact-pixel, long-pause and row-credit regressions.',
    ]
    bit = PHY / 'dual_imx415_gray_demo.bit'
    if bit.stat().st_mtime < result['physical_stages']['bitgen']['begin']:
        raise SystemExit('Stale bitstream')
    RELEASE.mkdir(parents=True, exist_ok=True)
    destination = RELEASE / 'dual_imx415_PRF1_20261027.bit'
    shutil.copy2(bit, destination)
    result['bitstream'] = dict(path=destination.relative_to(ROOT).as_posix(),
                              size=destination.stat().st_size, sha256=digest(destination))
    evidence = RELEASE / 'evidence'
    evidence.mkdir(exist_ok=True)
    for prefix, folder, names in (
            ('syn', SYN, ('run.log', 'dual_imx415_gray_demo_gate.area', 'dual_imx415_gray_demo.prj')),
            ('phy', PHY, ('run.log', 'dual_imx415_gray_demo_phy.area', timing_path.name))):
        for name in names:
            shutil.copy2(folder / name, evidence / (prefix + '_' + name))
    for name in logs:
        shutil.copy2(ROOT / 'build' / (name + '.log'), evidence / (name + '.log'))
    for name in ('resource_inputs.json', 'source_integrity.json'):
        shutil.copy2(ROOT / 'build' / name, evidence / name)
    shutil.copy2(ROOT / 'build/prf1_final_pipeline_rate/image_checks.json', evidence / 'image_checks.json')
    shutil.copy2(ROOT / 'PRF1_README.md', RELEASE / 'PRF1_README.md')
    shutil.copy2(ROOT / 'host_compat/rk_payload.zip', RELEASE / 'rk_payload.zip')
    result['rk_payload_sha256'] = digest(RELEASE / 'rk_payload.zip')
    (RELEASE / 'validation.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
