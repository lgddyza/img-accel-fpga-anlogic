"""Check production store/guard with queued DDR, FIFO pressure and faults."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT.parent / '.tools/iverilog/bin'
OUT = ROOT / 'build/str5_validation'
OUT.mkdir(exist_ok=True)
results = {}
for limit, stall, fault in ((1, 0, 0), (2, 0, 0), (2, 1, 0), (2, 0, 1), (2, 0, 2), (2, 0, 3)):
    name = f'prefetch_{limit}_{stall}_{fault}'
    exe = OUT / (name + '.vvp')
    subprocess.run([str(BIN/'iverilog.exe'), '-g2012', '-s', 'tb_str5_prefetch',
                    f'-Ptb_str5_prefetch.LIMIT={limit}', f'-Ptb_str5_prefetch.STALL={stall}',
                    f'-Ptb_str5_prefetch.ERROR_KIND={fault}', '-o', str(exe),
                    'sim/tb_str5_prefetch.sv', 'rtl/v2_frame_store.v',
                    'rtl/v2_ddr_reset_guard.v', 'rtl/v2_async_fifo.v'], cwd=ROOT, check=True)
    with (OUT/(name+'.log')).open('w') as log:
        result = subprocess.run([str(BIN/'vvp.exe'), '-i', str(exe)], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    text = (OUT/(name+'.log')).read_text()
    print(text, flush=True)
    if result.returncode or 'PASS STR5' not in text:
        raise SystemExit('FAIL '+name)
    if not fault:
        results[limit, stall] = re.search(r'hash=(\w+) cycles=(\d+)', text).groups()
if len({value[0] for value in results.values()}) != 1:
    raise SystemExit('RAW hash differs across scheduling variants')
if int(results[2, 0][1]) >= int(results[1, 0][1]):
    raise SystemExit('Queued latency model did not benefit from two reads')
print('PASS identical full RAW content, bounded reservations, modeled latency improvement')
