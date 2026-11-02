"""Collect actual CLA9 simulation, source, JPEG and managed synthesis evidence."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

import cv2

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / 'DUAL_IMX415_RTL_OPT5_20261028'
BIN = ROOT.parent / '.tools/iverilog/bin'
RUN = ROOT / 'dual_imx415_gray_demo_Runs/syn_1'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def area(root):
    path = root / 'dual_imx415_gray_demo_Runs/syn_1/dual_imx415_gray_demo_gate.area'
    text = path.read_text()
    fields = {}
    for name in ('lut', 'reg', 'slice*', 'dram lut', 'eram', 'dsp'):
        fields[name] = int(re.search(r'^#?' + (r'\s*#' if name == 'dram lut' else '') +
                                    re.escape(name) + r'\s+(\d+)', text, re.M).group(1))
    return dict(path=str(path), sha256=digest(path), counts=fields)


checks = {}
for name, source in (
    ('huffman_amplitude', ['third_party/mjpegZero/rtl/huffman_encoder.v']),
    ('fifo_lookahead', ['rtl/v2_async_fifo.v']),
):
    executable = ROOT / f'build/{name}.vvp'
    subprocess.run([str(BIN/'iverilog.exe'), '-g2012', '-s', 'tb_' + name,
                    '-o', str(executable), f'sim/tb_{name}.sv', *source], cwd=ROOT, check=True)
    result = subprocess.run([str(BIN/'vvp.exe'), str(executable)], cwd=ROOT,
                            capture_output=True, text=True, check=True)
    log = ROOT / f'build/{name}.log'
    log.write_text(result.stdout + result.stderr, encoding='utf-8')
    assert 'PASS' in result.stdout
    checks[name] = dict(log=str(log), sha256=digest(log))

for name in ('endpoint_control', 'jpeg_cdc', 'jpeg_stream_stall', 'jpeg_dual_rate',
             'frame_store', 'frame_store_burst', 'frame_store_rate',
             'tb_clahe_dual_prototype', 'tb_clahe_1080',
             'preproc_small_paused', 'clahe_first_small_paused', 'row_credit'):
    log = ROOT / f'build/{name}.log'
    content = log.read_text(encoding='utf-8')
    assert 'PASS' in content and 'FATAL' not in content, name
    checks[name] = dict(log=str(log), sha256=digest(log))

jpegs = []
for cam in range(2):
    for tile in range(3):
        name = f'cam_{cam}_tile_{tile}.jpg'
        path = ROOT / 'build' / name
        reference = BASE / 'build' / name
        decoded = cv2.imread(str(path))
        assert decoded is not None and decoded.shape == (360, 1920, 3), name
        assert path.read_bytes() == reference.read_bytes(), name
        jpegs.append(dict(file=name, bytes=path.stat().st_size, sha256=digest(path),
                          decoded_shape=list(decoded.shape), identical_to_cla8=True))

stages = {}
for stage in ('read_design', 'opt_rtl', 'opt_gate'):
    end = RUN / f'.{stage}.end.f'
    assert end.exists() and not (RUN / f'.{stage}.error.f').exists(), stage
    stages[stage] = dict(completed=True, marker=str(end), mtime=end.stat().st_mtime)
assert (RUN / 'dual_imx415_gray_demo_gate.db').stat().st_size > 0
assert not list((ROOT / 'dual_imx415_gray_demo_Runs/phy_1').glob('.*.begin.f'))
assert not list(ROOT.rglob('*.bit'))

unchanged = ['uisrc/04_pin/fpga_pin.adc', 'uisrc/04_pin/timing.sdc']
for name in unchanged:
    assert digest(ROOT / name) == digest(BASE / name), name

expected = {'rtl/v2_async_fifo.v', 'rtl/v2_frame_store.v', 'rtl/v2_dual_preprocess.v',
            'rtl/v2_endpoint_body.vh', 'uisrc/01_rtl/gray_preprocess4.v',
            'uisrc/01_rtl/jpeg_gray4_axis_cdc.v', 'third_party/mjpegZero/rtl/huffman_encoder.v'}
inputs = json.loads((ROOT/'build/resource_inputs.json').read_text())
changed = []
for item in inputs:
    path = ROOT / item['path']
    assert digest(path) == item['sha256'], item['path']
    if path.suffix in ('.v', '.sv', '.vh', '.sdc', '.adc') and digest(path) != digest(BASE/item['path']):
        changed.append(item['path'])
assert set(changed) == expected, changed
integrity = json.loads((ROOT/'build/source_integrity.json').read_text(encoding='utf-8'))
assert integrity['errors'] == [] and integrity['synthesis_project_check']['errors'] == []
run_log = (RUN/'run.log').read_text(errors='replace')
assert 'Failed infer ram' not in run_log
result = dict(revision='CLA9', build_id='0x434c4139', top='dual_imx415_top',
              device='PH1A90SEG324-2', before=area(BASE), after=area(ROOT),
              stages=stages, checks=checks, jpeg=jpegs, changed_hdl=changed,
              unchanged_constraints=unchanged, input_hashes_verified=len(inputs),
              registered_sources=integrity['registered_project_files'],
              run_log_sha256=digest(RUN/'run.log'),
              physical_implementation_run=False, timing_closure_verified=False,
              new_bitstream_generated=False, board_verified=False)
out = ROOT / 'build/cla9_verification.json'
out.write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(dict(report=str(out), before=result['before']['counts'],
                      after=result['after']['counts'], tests='PASS', jpeg_identical=6), indent=2))
