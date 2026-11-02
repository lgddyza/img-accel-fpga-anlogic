"""Run a read-only old-versus-current preprocessing RTL comparison."""
from pathlib import Path
import sys
import re
import subprocess

root = Path(__file__).resolve().parents[1]
old = root.parent/'IMX415_DSI_PCIE_JPEG_EHP2_DSI_FIX_20261016'/'uisrc'/'01_rtl'
source = '\n'.join((old/name).read_text(encoding='utf-8') for name in ('gray_gauss4.v','gray_preprocess4.v'))
names = re.findall(r'^\s*module\s+(\w+)', source, flags=re.M)
source = re.sub(r'\b('+'|'.join(map(re.escape,names))+r')\b', lambda m:'old_'+m.group(), source)
dest = root/'build'/'audit_old_single_namespaced_20261029.v'
dest.write_text(source,encoding='utf-8')
bindir = root.parent/'.tools'/'iverilog'/'bin'
exe = root/'build'/'audit_single_dual_20261029.vvp'
files = ['sim/tb_single_dual_compare_20261029.sv', str(dest), 'rtl/v2_dual_preprocess.v',
         'rtl/v2_async_fifo.v', 'uisrc/01_rtl/gray_gauss4.v', 'uisrc/01_rtl/gray_preprocess4.v']
subprocess.run([str(bindir/'iverilog.exe'),'-g2012','-s','tb_single_dual_compare','-o',str(exe),*files],cwd=root,check=True)
arguments=[str(bindir/'vvp.exe'),'-i',str(exe)]
if len(sys.argv)>1: arguments.append('+input='+Path(sys.argv[1]).resolve().as_posix())
subprocess.run(arguments,cwd=root,check=True,timeout=180)
