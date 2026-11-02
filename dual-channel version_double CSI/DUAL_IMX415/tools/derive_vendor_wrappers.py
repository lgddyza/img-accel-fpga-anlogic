"""Preserve vendor PCIe/DDR connection code; only write isolated V2 wrappers."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
src=(ROOT/'docs/v1_system_top_reference.v.txt').read_text(encoding='utf-8-sig')
ep=src[src.index('module pcie_gray_endpoint ('):]
core=ep[ep.index('    wire core_clk'):ep.index('    reg enable,soft_reset;')]
core=core.replace('    wire [127:0] c2h_data;',"    wire [127:0] c2h_data=128'd0;")
core=core.replace('    wire c2h_valid,c2h_ready,c2h_last;',"    wire c2h_valid,c2h_ready,c2h_last;\n    assign c2h_valid=1'b0;assign c2h_last=1'b0;")
ports='''`timescale 1ns/1ps
module v2_pcie_endpoint (
    input wire diag_clk,input wire [575:0] diagnostics,
    input wire sys_clk,jpeg_refclk,refclk_p,refclk_n,rxp,rxn,pcie_mperst,
    output wire txp,txn,stream_reset_n,
    input wire pipe_clk,pipe_rst_n,
    input wire [127:0] metadata,input wire metadata_valid,output wire metadata_ready,
    input wire [127:0] processed_rgb,input wire processed_valid,processed_sof,processed_eol,
    input wire [671:0] statistics,
    output wire capture_enable,output wire [2:0] mode_a,mode_b,
    output wire [6:0] quality_pipe,output wire [31:0] config_epoch,
    output wire jpeg_armed,jpeg_done,jpeg_fault_pipe,jpeg_input_ready
);
'''
(ROOT/'rtl/v2_pcie_endpoint.v').write_text(ports+core+'\n`include "rtl/v2_endpoint_body.vh"\nendmodule\n',encoding='utf-8')
# DDR wrapper retains the exact V1 IP pin connection stanza. No DSI/FDMA code.
axi=src[src.index('// AXI Write Addr'):src.index('//MLK_FDMA')]
ddr=src[src.index('ui_ddr X_ui_ddr ('):src.index('  reset_gen u_reset_gen')]
ports='''`timescale 1ns/1ps
module v2_ddr_wrapper (
    input wire I_ddr_clk,S_pll_lock,
    output wire [13:0] ddr_addr,output wire [2:0] ddr_ba,
    output wire ddr_cke,ddr_odt,ddr_cs_n,ddr_ras_n,ddr_cas_n,ddr_we_n,
    output wire ddr_ck_p,ddr_ck_n,ddr_reset_n,
    inout wire [1:0] ddr_dm,inout wire [15:0] ddr_dq,
    inout wire [1:0] ddr_dqs_n,ddr_dqs_p,
    output wire S_dfi_clk,S_ddr_init_cal_done,output wire [7:0] S_ddr_init_cal_err,
    input wire [27:0] awaddr,input wire [7:0] awlen,input wire awvalid,output wire awready,
    input wire [127:0] wdata,input wire wlast,wvalid,output wire wready,
    output wire [1:0] bresp,output wire bvalid,input wire bready,
    input wire [27:0] araddr,input wire [7:0] arlen,input wire arvalid,output wire arready,
    output wire [127:0] rdata,output wire [1:0] rresp,output wire rlast,rvalid,input wire rready
);
localparam AXI_ADDR_WIDTH=28,AXI_ID_WIDTH=4,APP_DATA_WIDTH=128,APP_MASK_WIDTH=16;
'''
ties=''
for ch in ('aw','ar'):
 for suffix,value in [('id',"4'd0"),('addr',ch+'addr'),('len',ch+'len'),('size',"3'd4"),('burst',"2'b01"),('lock',"1'b0"),('cache',"4'd0"),('prot',"3'd0"),('qos',"4'd0"),('valid',ch+'valid')]:
  ties+=f'assign S_axi_{ch}{suffix}={value};\n'
 ties+=f'assign {ch}ready=S_axi_{ch}ready;\n'
for name,value in [('wdata','wdata'),('wstrb',"16'hffff"),('wlast','wlast'),('wvalid','wvalid'),('bready','bready'),('rready','rready')]:
 ties+=f'assign S_axi_{name}={value};\n'
for name in ('wready','bresp','bvalid','rdata','rresp','rlast','rvalid'):
 ties+=f'assign {name}=S_axi_{name};\n'
(ROOT/'rtl/v2_ddr_wrapper.v').write_text(ports+axi+ties+ddr+'\nendmodule\n',encoding='utf-8')
print('Generated vendor connection wrappers under', ROOT/'rtl')
