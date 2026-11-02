"""Archive native managed-build evidence and completed STR3 simulations."""
import hashlib
import json
from pathlib import Path
import re
import shutil

root = Path(__file__).resolve().parents[1]
syn = root/'dual_imx415_gray_demo_Runs/syn_1'
phy = root/'dual_imx415_gray_demo_Runs/phy_1'
out = root/'build/str3_validation'
release = root/'release/STR3_20261025'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stages(run, names):
    result = {}
    for name in names:
        begin, end = (run/f'.{name}.{suffix}.f' for suffix in ('begin', 'end'))
        if (run/f'.{name}.error.f').exists() or not begin.exists() or not end.exists():
            raise SystemExit(f'Managed stage incomplete: {run.name}/{name}')
        if end.stat().st_mtime < begin.stat().st_mtime:
            raise SystemExit(f'Stale managed stage: {name}')
        result[name] = dict(begin=begin.stat().st_mtime, end=end.stat().st_mtime)
    return result


def resources(path):
    text = path.read_text()
    result = {}
    for key in ('slice', 'eram', 'dsp'):
        match = re.search(r'^#'+re.escape(key)+r'\*?\s+(\d+)\s+out of\s+(\d+)\s+([\d.]+)%', text, re.M)
        if not match:
            raise SystemExit('Missing native resource field: '+key)
        result[key] = dict(used=int(match[1]), capacity=int(match[2]), percent=float(match[3]))
    return result


def simulation(name, marker):
    path = root/'build'/name
    text = path.read_text()
    if marker not in text or 'FATAL:' in text:
        raise SystemExit('Simulation not confirmed: '+name)
    shutil.copy2(path, out/name)
    return digest(path)


inputs = json.loads((root/'build/resource_inputs.json').read_text())
for item in inputs:
    if digest(root/item['path']) != item['sha256']:
        raise SystemExit('Build input changed: '+item['path'])
integrity = json.loads((root/'build/source_integrity.json').read_text())
if integrity['errors'] or integrity['synthesis_project_check']['errors']:
    raise SystemExit('Source registration/integrity check failed')
result = dict(stream_build='0x53545233', board_tested=False,
              input_hashes_checked=len(inputs), synthesis_stages=stages(syn, ('read_design', 'opt_rtl', 'opt_gate')),
              physical_stages=stages(phy, ('opt_place', 'opt_route', 'bitgen')),
              synthesis_resources=resources(syn/'dual_imx415_gray_demo_gate.area'),
              physical_resources=resources(phy/'dual_imx415_gray_demo_phy.area'))
if result['physical_stages']['opt_place']['begin'] < result['synthesis_stages']['opt_gate']['end']:
    raise SystemExit('Physical build predates current synthesis')
timing_path = phy/'dual_imx415_gray_demo_pr.timing'
timing = timing_path.read_text()
result['timing'] = {name: float(re.search(r'\b'+name+r':\s*([-\d.]+)ns', timing)[1])
                    for name in ('SWNS', 'STNS', 'HWNS', 'HTNS')}
result['timing']['sta_coverage_percent'] = float(re.search(r'STA coverage\s*:\s*([\d.]+)%', timing)[1])
if 'Confidence          : Routed' not in timing or any(result['timing'][k] < 0 for k in ('SWNS', 'HWNS')):
    raise SystemExit('Current routed setup/hold checks did not pass')
if result['physical_resources']['eram']['used'] > 230:
    raise SystemExit('Resource budget was not met')
out.mkdir(exist_ok=True)
for label, run, names in (
        ('synthesis', syn, ('run.log', 'dual_imx415_gray_demo_gate.area', 'dual_imx415_gray_demo.prj')),
        ('physical', phy, ('run.log', 'dual_imx415_gray_demo_phy.area', timing_path.name,
                          'dual_imx415_gray_demo_phy.ts'))):
    folder = out/label
    folder.mkdir(exist_ok=True)
    for name in names:
        shutil.copy2(run/name, folder/name)
for name in ('resource_inputs.json', 'source_integrity.json'):
    shutil.copy2(root/'build'/name, out/name)
checks = dict(fixed_isp='PASS', row_credit='PASS row credits', isp_pause='PASS legacy ISP row-gap contract',
              isp_replay='PASS full 1080p shared ISP', endpoint_control='PASS AXI-Lite',
              frame_store='PASS stopped camera', jfif_backpressure='PASS full/lite JFIF',
              str3_final_pipeline_rate='PASS full source geometry and dual-60 service budget',
              str3_final_stress_pipeline_rate_backpressure='PASS full source geometry and backpressure recovery')
result['simulation_logs'] = {name: simulation(name+'.log', marker) for name, marker in checks.items()}
result['image_checks'] = {}
for name in ('str3_final_pipeline_rate', 'str3_final_stress_pipeline_rate_backpressure'):
    path = root/'build'/name/'image_checks.json'
    images = json.loads(path.read_text())
    if len(images) != 2 or any(x['psnr_db'] < 32 for x in images):
        raise SystemExit('Incomplete or failed JPEG image checks: '+name)
    result['image_checks'][name] = images
    text = (root/'build'/f'{name}.log').read_text()
    result[name+'_service'] = [dict(frame=int(frame), service_ns=float(ns))
        for frame, ns in re.findall(r'SERVICE camera=(\d+) ns=([\d.]+)', text)]
release.mkdir(parents=True, exist_ok=True)
bit = phy/'dual_imx415_gray_demo_compress.bit'
if bit.stat().st_mtime < result['physical_stages']['bitgen']['begin']:
    raise SystemExit('Bitstream predates current bitgen')
destination = release/'dual_imx415_gray_demo_STR3_20261025_compress.bit'
shutil.copy2(bit, destination)
result['bitstream'] = dict(path=destination.relative_to(root).as_posix(),
                           size=destination.stat().st_size, sha256=digest(destination))
(out/'summary.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
for path in (out/'summary.json', root/'build/resource_inputs.json'):
    shutil.copy2(path, release/path.name)
print(json.dumps(result, indent=2))
