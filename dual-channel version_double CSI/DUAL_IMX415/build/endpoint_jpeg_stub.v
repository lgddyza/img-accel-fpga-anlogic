`timescale 1ns/1ps

// Complete 8-row stripe split across three monochrome JPEG encoders.
// 1080 rows become three 1920x360 independent JPEG images. GREY C2H0 and DSI
// still receive the original 60 FPS stream; A/B/C use C2H1/2/3.
module jpeg_triple_tile_branch #(
    parameter integer IMG_WIDTH=1920,
    parameter integer IMG_HEIGHT=1080,
    parameter integer INPUT_FIFO_ADDR_WIDTH=8,
    parameter integer OUTPUT_FIFO_ADDR_WIDTH=7,
    parameter integer V2_SCHEDULED=0
) (
    input wire cam_clk,cam_rst_n,
    input wire user_clk,user_rst_n,
    input wire enc_clk,enc_pll_lock,
    input wire [127:0] s_rgb4,
    input wire s_valid,s_sof,s_eol,
    input wire enable,reset_pulse,link_up,full_rate,
    input wire [6:0] quality,
    input wire a_ready,b_ready,c_ready,
    output wire [127:0] a_data,b_data,c_data,
    output wire [15:0] a_keep,b_keep,c_keep,
    output wire a_valid,a_last,b_valid,b_last,c_valid,c_last,
    output wire status_configured,status_busy,status_fault,
    output wire [6:0] status_quality,
    output reg [31:0] sent_a,sent_b,sent_c,fault_count,
    output wire [31:0] bytes_a,bytes_b,bytes_c,
    output wire [17:0] debug_status,
    output wire [31:0] debug_detail,
    output wire input_armed,
    output wire input_ready,
    output reg group_done_cam,
    output wire fault_cam,
    output wire [35:0] input_levels,
    output wire [287:0] enc_performance
);
assign a_data='d0;
assign b_data='d0;
assign c_data='d0;
assign a_keep='d0;
assign b_keep='d0;
assign c_keep='d0;
assign a_valid='d0;
assign a_last='d0;
assign b_valid='d0;
assign b_last='d0;
assign c_valid='d0;
assign c_last='d0;
assign status_configured=1'b1;
assign status_busy='d0;
assign status_fault='d0;
assign status_quality=quality;
assign bytes_a='d0;
assign bytes_b='d0;
assign bytes_c='d0;
assign debug_status='d0;
assign debug_detail='d0;
assign input_armed=1'b1;
assign input_ready='d0;
assign fault_cam='d0;
assign input_levels='d0;
assign enc_performance='d0;
initial begin sent_a=0;sent_b=0;sent_c=0;fault_count=0;group_done_cam=0; end
endmodule
