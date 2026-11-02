"""Focused PRF1 transport and lookahead safety regression."""
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
BIN=ROOT.parent/'.tools/iverilog/bin'
tests={
    'compact_cdc':(['-Ptb_jpeg_cdc.COMPACT_MONO=1'],'tb_jpeg_cdc',
        ['sim/tb_jpeg_cdc.sv','uisrc/01_rtl/jpeg_gray4_axis_cdc.v','rtl/v2_async_fifo.v','rtl/v2_reset_sync.v']),
    'preproc_credit':([], 'tb_preproc_credit', ['sim/tb_preproc_credit.sv','rtl/v2_dual_preprocess.v',
        'rtl/v2_line_replay.v','rtl/v2_async_fifo.v','uisrc/01_rtl/gray_gauss4.v','uisrc/01_rtl/gray_preprocess4.v']),
}
for name,(options,top,files) in tests.items():
    exe=ROOT/'build'/f'{name}.vvp'
    subprocess.run([str(BIN/'iverilog.exe'),'-g2012',*options,'-s',top,'-o',str(exe),*files],cwd=ROOT,check=True)
    run=subprocess.run([str(BIN/'vvp.exe'),'-i',str(exe)],cwd=ROOT,capture_output=True,text=True,timeout=120)
    (ROOT/'build'/f'{name}.log').write_text(run.stdout+run.stderr,encoding='utf-8')
    print(run.stdout+run.stderr,flush=True)
    if run.returncode: raise SystemExit(run.returncode)
