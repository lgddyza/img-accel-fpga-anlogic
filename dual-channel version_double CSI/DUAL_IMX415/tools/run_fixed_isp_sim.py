"""Compare legacy unity AWB pixels and legacy/compact Gamma in simulation."""
import subprocess
from run_isp_sim import ROOT, BIN, files

exe = ROOT / 'build/fixed_isp.vvp'
subprocess.run([str(BIN/'iverilog.exe'), '-g2012', '-s', 'tb_fixed_isp',
                '-o', str(exe), 'sim/tb_fixed_isp.sv', *map(str, files)],
               cwd=ROOT, check=True)
with (ROOT/'build/fixed_isp.log').open('w', encoding='utf-8') as log:
    result = subprocess.run([str(BIN/'vvp.exe'), '-i', str(exe)], cwd=ROOT,
                            stdout=log, stderr=subprocess.STDOUT)
print((ROOT/'build/fixed_isp.log').read_text())
raise SystemExit(result.returncode)
