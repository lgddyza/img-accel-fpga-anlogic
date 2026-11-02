"""Reproduce CLA1 isolation, mode-change and full-geometry core simulations."""
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
binary = root.parent / '.tools/iverilog/bin'
for case in ('tb_clahe_dual_prototype', 'tb_clahe_1080'):
    output = root / 'build' / (case + '.vvp')
    log = root / 'build' / (case + '.log')
    subprocess.run([str(binary / 'iverilog.exe'), '-g2012', '-s', case,
                    '-o', str(output), 'sim/' + case + '.sv',
                    'rtl/v2_dual_preprocess.v', 'uisrc/01_rtl/gray_preprocess4.v'],
                   cwd=root, check=True)
    with log.open('w', encoding='utf-8') as sink:
        run = subprocess.run([str(binary / 'vvp.exe'), '-i', str(output)],
                             cwd=root, stdout=sink, stderr=subprocess.STDOUT)
    print(log.read_text(encoding='utf-8'), flush=True)
    if run.returncode:
        raise SystemExit(run.returncode)
