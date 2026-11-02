"""Validate production control/CDC logic with an inert JPEG interface."""
from pathlib import Path
import re,subprocess
ROOT=Path(__file__).resolve().parents[1];BIN=ROOT.parent/'.tools/iverilog/bin'
source=(ROOT/'uisrc/01_rtl/jpeg_triple_tile_branch.v').read_text(encoding='utf-8-sig')
header=source[:source.index(');')+2]
wire_outputs=[];reg_outputs=[]
for kind,names in re.findall(r'output (wire|reg) (?:\[[^]]+\] )?([^\n]+)',header):
    for name in names.strip().rstrip(',').split(','):
        (wire_outputs if kind=='wire' else reg_outputs).append(name.strip())
stub=ROOT/'build/endpoint_jpeg_stub.v'
body=[]
for name in wire_outputs:
    value='quality' if name=='status_quality' else "1'b1" if name in ('status_configured','input_armed') else "'d0"
    body.append(f'assign {name}={value};')
body.append('initial begin '+''.join(name+'=0;' for name in reg_outputs)+' end')
stub.write_text(header+'\n'+'\n'.join(body)+'\nendmodule\n',encoding='utf-8')
exe=ROOT/'build/endpoint_control.vvp'
subprocess.run([str(BIN/'iverilog.exe'),'-g2012','-s','tb_endpoint_control','-o',str(exe),'sim/tb_endpoint_control.sv','rtl/v2_mailbox.v','rtl/v2_reset_sync.v','rtl/v2_jpeg_header.v',str(stub)],cwd=ROOT,check=True)
with (ROOT/'build/endpoint_control.log').open('w',encoding='utf-8') as log:
    result=subprocess.run([str(BIN/'vvp.exe'),'-i',str(exe)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
print((ROOT/'build/endpoint_control.log').read_text())
raise SystemExit(result.returncode)
