"""Run meaningful transport checks and optionally the full-resolution JPEG load."""
from pathlib import Path
import argparse,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
BIN=ROOT.parent/'.tools/iverilog/bin'
ap=argparse.ArgumentParser();ap.add_argument('--jpeg',action='store_true');ap.add_argument('--rate',action='store_true');ap.add_argument('--only');args=ap.parse_args()
tests={
 'jfif_backpressure':['sim/tb_jfif_backpressure.sv','third_party/mjpegZero/rtl/jfif_writer.v'],
 'ddr_reset_guard':['sim/tb_ddr_reset_guard.sv','rtl/v2_ddr_reset_guard.v'],
 'jpeg_packer_stall':['sim/tb_jpeg_packer_stall.sv','uisrc/01_rtl/jpeg_byte_packer.v'],
 'camera_profiles':['sim/tb_camera_profiles.sv','rtl/v2_imx415_config.v','rtl/v2_i2c_write.v','uisrc/03_ip/ui_imx415_cfg/ui_imx415_reg.v','uisrc/03_ip/ui_imx415_cfg/ui_imx415_reg_37125.v'],
 'csi_packets':['sim/tb_csi_packets.sv','rtl/v2_axis_crop.v']+['uisrc/03_ip/mipi_csi_2/'+x+'.v' for x in ('csi_rx_packet_handler','csi_rx_hdr_ecc','csi_rx_10bit_unpack','csi_rx_vid2stream')],
 'rx_recovery':['sim/tb_rx_recovery.sv','uisrc/03_ip/mipi_csi_2/csi_rx_clock_det.v','uisrc/03_ip/mipi_csi_2/auto_delay_ctl.v'],
 'axis_crop':['sim/tb_axis_crop.sv','rtl/v2_axis_crop.v'],
 'jpeg_cdc':['sim/tb_jpeg_cdc.sv','uisrc/01_rtl/jpeg_gray4_axis_cdc.v','rtl/v2_async_fifo.v'],
 'frame_store':['sim/tb_frame_store.sv','rtl/v2_async_fifo.v','rtl/v2_raw_capture.v','rtl/v2_frame_store.v','rtl/v2_mailbox.v'],
 'frame_store_burst':['sim/tb_frame_store_burst.sv','sim/tb_frame_store.sv','rtl/v2_async_fifo.v','rtl/v2_raw_capture.v','rtl/v2_frame_store.v','rtl/v2_mailbox.v'],
 'header':['sim/tb_header.sv','rtl/v2_jpeg_header.v'],
 'line_replay':['sim/tb_line_replay.sv','rtl/v2_line_replay.v'],
}
if (ROOT/'sim/tb_preproc_replay.sv').exists():
 tests['preproc_replay']=['sim/tb_preproc_replay.sv']+[str(p.relative_to(ROOT)) for p in sorted((ROOT/'uisrc/01_rtl').glob('gray*.v'))]
if (ROOT/'rtl/v2_dual_preprocess.v').exists():
 tests['dual_preproc']=[]
if args.jpeg:
 tests['jpeg_dual_rate']=['sim/tb_jpeg_dual_rate.sv','uisrc/01_rtl/jpeg_triple_tile_branch.v','uisrc/01_rtl/jpeg_gray4_axis_cdc.v','uisrc/01_rtl/jpeg_byte_packer.v','uisrc/01_rtl/gray4_to_yuyv4.v','uisrc/01_rtl/jpeg_axil_config.v','uisrc/03_ip/ui_dbuf/sfifo/sfifo.v']+[str(p.relative_to(ROOT)) for p in sorted((ROOT/'third_party/mjpegZero/rtl').glob('*.v'))]
 tests['jpeg_stream_stall']=['sim/tb_jpeg_stream_stall.sv']+tests['jpeg_dual_rate']
 tests['jpeg_backpressure']=['sim/tb_jpeg_backpressure.sv','rtl/v2_line_replay.v']+tests['jpeg_dual_rate'][1:]
 (ROOT/'build/str2_backpressure').mkdir(exist_ok=True)
if args.rate:
 tests['frame_store_rate']=['sim/tb_frame_store_rate.sv','sim/tb_frame_store.sv','rtl/v2_async_fifo.v','rtl/v2_raw_capture.v','rtl/v2_frame_store.v','rtl/v2_mailbox.v']
if args.only and args.only not in tests:ap.error('unknown test: '+args.only)
for name,files in tests.items():
 if args.only and args.only!=name:continue
 if name=='dual_preproc':
  subprocess.run([sys.executable,str(ROOT/'tools/run_preproc_lite.py')],cwd=ROOT,check=True)
  continue
 files=list(dict.fromkeys(files+['rtl/v2_reset_sync.v','rtl/v2_async_fifo.v']))
 exe=ROOT/'build'/f'{name}.vvp'
 print('RUN',name,flush=True)
 subprocess.run([str(BIN/'iverilog.exe'),'-g2012','-s','tb_'+name,'-o',str(exe),*files],cwd=ROOT,check=True)
 with (ROOT/'build'/f'{name}.log').open('w',encoding='utf-8') as log:
  result=subprocess.run([str(BIN/'vvp.exe'),'-i',str(exe)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
 print((ROOT/'build'/f'{name}.log').read_text(),flush=True)
 if result.returncode: raise SystemExit(result.returncode)
