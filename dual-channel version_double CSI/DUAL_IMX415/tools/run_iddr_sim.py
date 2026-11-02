"""Verify reset flushing using the vendor's publicly visible IDDR behavioral code.

The protected metadata block is not used or decrypted. Only the visible
functional model below it is compiled; this is not an electrical/timing model.
"""
from pathlib import Path
import argparse,hashlib,re,subprocess
root=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('--phy-source',type=Path,default=root/'uisrc/03_ip/mipi_csi_2/csi_rx_hs_data_phy.v')
ap.add_argument('--only',choices=('iddr_flush','phy_delay_control','phy_delay_scan'))
args=ap.parse_args()
vendor=Path('F:/FPGA/AnLu/sim_release/ph1')
source=vendor/'ph1_logic_io.v'
text=source.read_text()
model=re.search(r'module PH1_LOGIC_IDDRx2\s*\(.*?\nendmodule',text,re.S).group()
model=re.sub(r'`pragma protect begin_protected.*?`pragma protect end_protected','// Protected metadata omitted; visible model follows.',model,flags=re.S)
out=root/'build/iddr_visible_model.v'
delay_source=vendor/'ph1_logic_dynamic_idelay.v'
delay_model=re.search(r'module PH1_LOGIC_DYNAMIC_IDELAY\s*\(.*?\nendmodule',delay_source.read_text(),re.S).group()
out.write_text('// Anlogic functional model from '+str(source)+'\n// Copyright (c) Anlogic Inc.\n// Source SHA256 '+hashlib.sha256(source.read_bytes()).hexdigest()+'\n// IDELAY source SHA256 '+hashlib.sha256(delay_source.read_bytes()).hexdigest()+'\n`timescale 1ps/1ps\n'+model+'\n'+delay_model+'\n')
binpath=root.parent/'.tools/iverilog/bin'
for name in ('iddr_flush','phy_delay_control','phy_delay_scan'):
    if args.only and args.only!=name:continue
    exe=root/'build'/f'{name}.vvp'
    files=[root/'sim'/f'tb_{name}.sv',out,args.phy_source]
    if name=='phy_delay_scan':files.append(root/'uisrc/03_ip/mipi_csi_2/auto_delay_ctl.v')
    subprocess.run([str(binpath/'iverilog.exe'),'-g2012','-DFORMAL_VERIFICATION',
                    '-s','tb_'+name,'-o',str(exe),*[str(p) for p in files]],cwd=root,check=True)
    run=subprocess.run([str(binpath/'vvp.exe'),str(exe)],cwd=root,capture_output=True,text=True)
    (root/'build'/f'{name}.log').write_text(run.stdout+run.stderr,encoding='utf-8')
    print(run.stdout+run.stderr,flush=True)
    if run.returncode:raise SystemExit(run.returncode)
