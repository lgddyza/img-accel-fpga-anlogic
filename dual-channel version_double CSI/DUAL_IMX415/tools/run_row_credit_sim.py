"""Focused safety checks for nonelastic ISP row admission."""
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
bin_dir = root.parent / '.tools/iverilog/bin'
exe = root / 'build/row_credit.vvp'
subprocess.run([str(bin_dir/'iverilog.exe'), '-g2012', '-s', 'tb_isp_row_credit',
                '-o', str(exe), 'sim/tb_isp_row_credit.sv', 'rtl/v2_line_replay.v'],
               cwd=root, check=True)
result = subprocess.run([str(bin_dir/'vvp.exe'), '-i', str(exe)], cwd=root,
                        capture_output=True, text=True)
(root/'build/row_credit.log').write_text(result.stdout+result.stderr, encoding='utf-8')
print(result.stdout+result.stderr)
raise SystemExit(result.returncode)
