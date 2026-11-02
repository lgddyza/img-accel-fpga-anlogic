"""Archive completed managed TD evidence and measured STR1 software results."""
import hashlib
import json
from pathlib import Path
import re
import shutil

root = Path(__file__).resolve().parents[1]
run = root / 'dual_imx415_gray_demo_Runs/syn_1'
out = root / 'build/str2_validation'
inputs = json.loads((root / 'build/resource_inputs.json').read_text())
for item in inputs:
    if hashlib.sha256((root / item['path']).read_bytes()).hexdigest() != item['sha256']:
        raise SystemExit('Build input changed: ' + item['path'])
integrity = json.loads((root / 'build/source_integrity.json').read_text())
if integrity['errors']:
    raise SystemExit('Source registration/integrity check failed')
log = (run / 'run.log').read_text(errors='replace')
stages = {}
for stage in ('read_design', 'opt_rtl', 'opt_gate'):
    begin, end = (run / f'.{stage}.{suffix}.f' for suffix in ('begin', 'end'))
    if not begin.exists() or not end.exists() or end.stat().st_mtime < begin.stat().st_mtime:
        raise SystemExit('Managed stage not complete: ' + stage)
    stages[stage] = dict(begin_mtime=begin.stat().st_mtime, end_mtime=end.stat().st_mtime)
if 'finish command "optimize_gate ' not in log or re.search(r'\bERROR\s*:', log):
    raise SystemExit('Native run log does not confirm successful gate mapping')
area = (run / 'dual_imx415_gray_demo_gate.area').read_text()
resources = {}
for key in ('slice*', 'eram', 'dsp'):
    match = re.search(r'^#' + re.escape(key) + r'\s+(\d+)\s+out of\s+(\d+)\s+([\d.]+)%', area, re.M)
    if not match:
        raise SystemExit('Missing native area field: ' + key)
    resources[key] = dict(used=int(match[1]), available=int(match[2]), percent=float(match[3]))
out.mkdir(exist_ok=True)
for name in ('run.log', 'dual_imx415_gray_demo_gate.area', 'dual_imx415_gray_demo.prj'):
    shutil.copy2(run / name, out / name)
for name in ('resource_inputs.json', 'source_integrity.json'):
    shutil.copy2(root / 'build' / name, out / name)
software = []
for name in ('threaded_60', 'threaded_1m_60'):
    data = json.loads((root / 'build/board_test_str1_20261025' / name / 'result.json').read_text())
    software.append(dict(run=name, board_build='STR1', elapsed=data['elapsed'],
        decoded_frames=data['decoded_frames'],
        decoded_fps=[n / data['elapsed'] for n in data['decoded_frames']],
        bad_packets=data['bad_packets'], queue_drops=data['queue_drops'],
        decode_queue_drops=data['decode_queue_drops'], display_queue_drops=data['display_queue_drops']))
rate_log = (root / 'build/jpeg_dual_rate.log').read_text()
service = [dict(camera=int(c), service_ns=float(ns), aggregate_fps=float(fps))
           for c, ns, fps in re.findall(r'SERVICE camera=(\d+) ns=([\d.]+) rate_fps=([\d.]+)', rate_log)]
if len(service) != 2 or 'COMPLETE 2 frames 1920x1080' not in rate_log:
    raise SystemExit('Full-resolution JPEG test has not completed both frames')
result = dict(stream_build='0x53545232', managed_synthesis_and_mapping_complete=True,
    stages=stages, resources=resources, input_hashes_checked=len(inputs),
    combinational_loop_warning_found='combinational loop' in log.lower(),
    timing_closure_verified=False, str2_bitstream_generated=False, str2_board_tested=False,
    str1_software_tests=software, jpeg_service_measurements=service,
    jpeg_dual60_budget_passed='PASS full source geometry and dual-60 service budget' in rate_log,
    jpeg_budget_failure='shared JPEG exceeded dual-60 budget' in rate_log)
(out / 'summary.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
print(json.dumps(result, indent=2))
