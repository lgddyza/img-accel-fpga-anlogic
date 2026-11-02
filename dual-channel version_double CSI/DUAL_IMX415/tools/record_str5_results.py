"""Release only the current managed STR5 build; never infer board success."""
import difflib
import json
from pathlib import Path
import re
import shutil

from record_str4_results import digest, resources, stages

ROOT = Path(__file__).resolve().parents[1]
SYN = ROOT/'dual_imx415_gray_demo_Runs/syn_1'
PHY = ROOT/'dual_imx415_gray_demo_Runs/phy_1'
OUT = ROOT/'build/str5_validation'
RELEASE = ROOT/'release/STR5_20261025'


def main():
    inputs = json.loads((ROOT/'build/resource_inputs.json').read_text())
    for entry in inputs:
        if digest(ROOT/entry['path']) != entry['sha256']:
            raise SystemExit('Build input changed: '+entry['path'])
    integrity = json.loads((ROOT/'build/source_integrity.json').read_text())
    if integrity['errors'] or integrity.get('synthesis_project_check', {}).get('errors', ['missing']):
        raise SystemExit('Effective project source verification failed')
    if "rdata<=32'h53545235" not in (ROOT/'rtl/v2_endpoint_body.vh').read_text():
        raise SystemExit('Not STR5')
    result = dict(stream_build='0x53545235', board_tested=False,
                  synthesis=stages(SYN, ('read_design', 'opt_rtl', 'opt_gate')),
                  physical=stages(PHY, ('opt_place', 'opt_route', 'bitgen')),
                  synthesis_resources=resources(SYN/'dual_imx415_gray_demo_gate.area'),
                  physical_resources=resources(PHY/'dual_imx415_gray_demo_phy.area'))
    if result['synthesis']['read_design']['begin'] < max((ROOT/x['path']).stat().st_mtime for x in inputs):
        raise SystemExit('Synthesis predates current inputs')
    if result['physical']['opt_place']['begin'] < result['synthesis']['opt_gate']['end']:
        raise SystemExit('Physical build predates current synthesis')
    if result['physical_resources']['eram']['used'] > 216 or result['physical_resources']['slice']['percent'] >= 80:
        raise SystemExit('STR5 resource review required')
    syn_text = (SYN/'run.log').read_text()
    if 'identifier' in syn_text and re.search(r'HDL-5373.*../../rtl/(v2_frame_store|v2_ddr_reset_guard)', syn_text):
        raise SystemExit('New declaration-order warning remains')
    for module in ('v2_frame_store', 'v2_ddr_reset_guard', 'v2_pcie_endpoint'):
        if 'elaborate module '+module not in syn_text:
            raise SystemExit('Missing managed elaboration: '+module)
    timing_path = PHY/'dual_imx415_gray_demo_pr.timing'
    timing = timing_path.read_text()
    result['timing'] = {key: float(re.search(r'\b'+key+r':\s*([-\d.]+)ns', timing)[1])
                        for key in ('SWNS', 'STNS', 'HWNS', 'HTNS')}
    result['timing']['coverage_percent'] = float(re.search(r'STA coverage\s*:\s*([\d.]+)%', timing)[1])
    if 'Confidence          : Routed' not in timing or any(result['timing'][key] < 0 for key in ('SWNS', 'STNS', 'HWNS', 'HTNS')):
        raise SystemExit('Routed timing has not passed; do not release this bitstream')
    required = dict(frame_store='PASS stopped camera', ddr_reset_guard='16 dual read cuts',
                    frame_store_burst='8 complete frames', frame_store_rate='PASS full 1080p',
                    endpoint_control='PASS AXI-Lite', header='PASS DJP2',
                    jpeg_packer_stall='PASS 16 KiB JPEG', line_replay='PASS ping-pong',
                    dual_preproc='PASS gray-only demo', str5_python_tests='OK')
    result['tests'] = {}
    for name, marker in required.items():
        path = ROOT/'build'/f'{name}.log'
        contents = path.read_text()
        if marker not in contents or 'FATAL:' in contents or 'FAILED (' in contents:
            raise SystemExit('Failed or missing simulation: '+name)
        result['tests'][name] = digest(path)
        shutil.copy2(path, OUT/path.name)
    for name in ('prefetch_1_0_0', 'prefetch_2_0_0', 'prefetch_2_1_0',
                 'prefetch_2_0_1', 'prefetch_2_0_2', 'prefetch_2_0_3'):
        path = OUT/(name+'.log')
        if 'PASS STR5' not in path.read_text() or 'FATAL:' in path.read_text():
            raise SystemExit('Failed STR5 focused simulation: '+name)
        result['tests'][name] = digest(path)
    result['modeled_comparison'] = {}
    hashes = set()
    for name in ('prefetch_1_0_0', 'prefetch_2_0_0', 'prefetch_2_1_0'):
        match = re.search(r'hash=(\w+) cycles=(\d+)', (OUT/(name+'.log')).read_text())
        hashes.add(match[1])
        result['modeled_comparison'][name] = dict(hash=match[1], cycles=int(match[2]))
    if len(hashes) != 1:
        raise SystemExit('RAW hashes differ')
    bit = PHY/'dual_imx415_gray_demo_compress.bit'
    if bit.stat().st_mtime < result['physical']['bitgen']['begin']:
        raise SystemExit('Stale bitstream')
    RELEASE.mkdir(parents=True, exist_ok=True)
    target = RELEASE/'dual_imx415_gray_demo_STR5_20261025_compress.bit'
    shutil.copy2(bit, target)
    result['bitstream'] = dict(path=target.relative_to(ROOT).as_posix(), bytes=target.stat().st_size,
                              sha256=digest(target))
    for label, directory, files in (
        ('synthesis', SYN, ('run.log', 'dual_imx415_gray_demo_gate.area', 'dual_imx415_gray_demo.prj')),
        ('physical', PHY, ('run.log', 'dual_imx415_gray_demo_phy.area', timing_path.name, 'dual_imx415_gray_demo_phy.ts'))):
        dest = OUT/label
        dest.mkdir(exist_ok=True)
        for name in files:
            shutil.copy2(directory/name, dest/name)
    for name in ('resource_inputs.json', 'source_integrity.json'):
        shutil.copy2(ROOT/'build'/name, OUT/name)
        shutil.copy2(ROOT/'build'/name, RELEASE/name)
    patch = []
    for old in sorted((ROOT/'build/str5_before/rtl').glob('*')):
        new = ROOT/'rtl'/old.name
        if new.is_file() and digest(old) != digest(new):
            patch.extend(difflib.unified_diff(old.read_text().splitlines(True), new.read_text().splitlines(True),
                         fromfile='STR4/rtl/'+old.name, tofile='STR5/rtl/'+old.name))
    (OUT/'rtl_changes.patch').write_text(''.join(patch))
    (OUT/'summary.json').write_text(json.dumps(result, indent=2)+'\n')
    for path in (OUT/'summary.json', OUT/'rtl_changes.patch', ROOT/'RTL_STR5_20261025.md'):
        shutil.copy2(path, RELEASE/path.name)
    software = RELEASE/'rk'
    software.mkdir(exist_ok=True)
    for path in (ROOT/'rk').glob('*'):
        if path.suffix in ('.py', '.c'):
            shutil.copy2(path, software/path.name)
    shutil.copy2(ROOT/'release/STR4_20261025/rk/libjpeg_str4.so', software/'libjpeg_str4.so')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
