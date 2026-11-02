"""Compare paced and burst/pause traffic through the actual compact ISP."""
import argparse
import subprocess
from run_isp_sim import ROOT, BIN, files

parser = argparse.ArgumentParser()
parser.add_argument('--long-idle', action='store_true')
args = parser.parse_args()
name = 'isp_long_idle' if args.long_idle else 'isp_pause'
defines = ['-Ptb_isp_pause.LONG_IDLE_CYCLES=2105344', '-Ptb_isp_pause.ROWS=16'] if args.long_idle else []
exe = ROOT/'build'/f'{name}.vvp'
subprocess.run([str(BIN/'iverilog.exe'), '-g2012', '-s', 'tb_isp_pause', '-o', str(exe),
                *defines, 'sim/tb_isp_pause.sv', *map(str, files)], cwd=ROOT, check=True)
with (ROOT/'build'/f'{name}.log').open('w', encoding='utf-8') as log:
    result = subprocess.run([str(BIN/'vvp.exe'), '-i', str(exe)], cwd=ROOT,
                            stdout=log, stderr=subprocess.STDOUT, timeout=3600)
print((ROOT/'build'/f'{name}.log').read_text())
raise SystemExit(result.returncode)
