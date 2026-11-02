"""Full geometry RAW replay -> line RAM -> ISP -> enhancement -> real JPEG.

Uses the explicitly documented behavioral ISP RAM model from run_isp_sim.
This is a simulation budget check, not a measurement of DDR or PCIe hardware.
"""
from pathlib import Path
import argparse,subprocess
from run_isp_sim import files as isp_files
ROOT=Path(__file__).resolve().parents[1]
BIN=ROOT.parent/'.tools/iverilog/bin'
files=[ROOT/'sim/tb_jpeg_dual_rate.sv',ROOT/'rtl/v2_dual_preprocess.v',*isp_files]
files+=sorted((ROOT/'uisrc/01_rtl').glob('gray*.v'))
files += [ROOT/'rtl/v2_reset_sync.v',ROOT/'rtl/v2_async_fifo.v']
files+=[ROOT/'uisrc/01_rtl'/n for n in ['jpeg_triple_tile_branch.v','jpeg_gray4_axis_cdc.v','jpeg_byte_packer.v','jpeg_axil_config.v']]
files+=[ROOT/'uisrc/03_ip/ui_dbuf/sfifo/sfifo.v']
files+=sorted((ROOT/'third_party/mjpegZero/rtl').glob('*.v'))
parser=argparse.ArgumentParser();parser.add_argument('--smoke-ns',type=int)
parser.add_argument('--backpressure',action='store_true')
parser.add_argument('--pause-ms',type=float,default=0)
parser.add_argument('--tag',default='str3')
parser.add_argument('--frames',type=int,default=2)
parser.add_argument('--qf-switch',action='store_true')
parser.add_argument('--wall-timeout',type=int,default=3600);args=parser.parse_args()
if args.pause_ms<0 or (args.pause_ms and not args.backpressure):
 parser.error('--pause-ms must be nonnegative and requires --backpressure')
name=args.tag+('_pipeline_smoke' if args.smoke_ns else '_pipeline_rate')
if args.backpressure:name+='_backpressure'
output_dir=ROOT/'build'/name
output_dir.mkdir(exist_ok=True)
exe=ROOT/'build'/f'{name}.vvp';defines=['-DPIPELINE_RATE_TEST',f'-Ptb_jpeg_dual_rate.FRAMES={args.frames}']
if args.qf_switch:defines.append('-Ptb_jpeg_dual_rate.QF_SWITCH=1')
if args.backpressure:defines.append('-DPIPELINE_BACKPRESSURE')
if args.pause_ms:defines.append(f'-Ptb_jpeg_dual_rate.PAUSE_CYCLES={int(args.pause_ms*125000)}')
if args.smoke_ns:defines.append(f'-DPIPELINE_SMOKE_NS={args.smoke_ns}')
subprocess.run([str(BIN/'iverilog.exe'),'-g2012',*defines,'-s','tb_jpeg_dual_rate','-o',str(exe),*[str(p) for p in dict.fromkeys(files)]],cwd=ROOT,check=True)
with (ROOT/'build'/f'{name}.log').open('w',encoding='utf-8') as log:
 try:
  result=subprocess.run([str(BIN/'vvp.exe'),'-i',str(exe),f'+output_dir={output_dir.as_posix()}'],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=args.wall_timeout)
 except subprocess.TimeoutExpired:
  log.write('\nINCOMPLETE: simulation wall-time limit, no throughput conclusion.\n');raise
print((ROOT/'build'/f'{name}.log').read_text())
raise SystemExit(result.returncode)
