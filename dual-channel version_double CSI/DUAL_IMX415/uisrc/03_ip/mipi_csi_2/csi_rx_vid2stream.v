`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/07/18 17:00:36
// Design Name: 
// Module Name: v2rx_csi_rx_vid2stream
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module v2rx_csi_rx_vid2stream(

    input wire           I_data_clk,    
    input wire           I_reset_n,    
    input wire           I_packet_done,
    input wire           I_packet_line,        
    input wire           I_packet_frame,    
    input wire [39:0]    I_data_unpack,  
    input wire           I_dout_unpack_valid,
    //stream锟斤拷锟斤拷锟斤拷
    input  wire         m_axis_video_aclk,
    input  wire         m_axis_video_aresetn,
	  input  wire         m_axis_video_tready,
    output wire         m_axis_video_tuser,
    output wire         m_axis_video_tlast,
    output wire         m_axis_video_tvalid,
    output wire[39:0]   m_axis_video_tdata
    );

wire [41:0] w_rdata;      //锟斤拷锟斤拷锟斤拷
wire        w_wdata_first_valid; //写锟斤拷锟斤拷每帧锟斤拷一锟斤拷锟斤拷锟斤拷vaild
wire        w_packet_frame_down; //frame锟铰斤拷锟斤拷
wire        w_vid_last;
wire empty;
reg        r_dout_unpack_valid_d0;
reg        r_packet_frame_start;
reg        r_packet_frame;
reg        r_last_data_valid;
reg [39:0] r_data_unpack;
reg        r_packet_done_vaild; //约锟斤拷packet_done锟斤拷效锟斤拷锟斤拷止锟斤拷锟襟发筹拷packet_done

assign w_wdata_first_valid = r_packet_frame_start & r_dout_unpack_valid_d0;
assign w_packet_frame_down = !I_packet_frame & r_packet_frame; 

assign w_valid_down = !I_dout_unpack_valid & r_dout_unpack_valid_d0; //vaild锟铰斤拷锟截诧拷锟斤拷
assign w_vid_last = r_last_data_valid & w_valid_down;

assign m_axis_video_tuser =  m_axis_video_tvalid? w_rdata[0] : 1'b0;
assign m_axis_video_tlast =  m_axis_video_tvalid? w_rdata[1] : 1'b0;
assign m_axis_video_tdata =  m_axis_video_tvalid? w_rdata[41:2]: 40'b0;
assign m_axis_video_tvalid = ~empty;

//-------------------------------------
// 状态锟斤拷锟藉（锟斤拷一锟轿ｏ拷状态锟斤拷锟斤拷锟斤拷
//-------------------------------------
// 使锟斤拷localparam锟斤拷确锟斤拷锟斤拷锟斤拷锟斤拷状态
localparam [1:0] 
    STATE_IDLE      = 2'b00,   // 锟斤拷锟斤拷状态锟斤拷锟斤拷位锟斤拷锟斤拷
    STATE_WAIT_FRAM = 2'b01,  // 锟饺达拷帧锟斤拷效
    STATE_WAIT_DONE = 2'b10;    // 锟饺达拷帧锟斤拷效

reg [1:0] R_MS;  // 锟斤拷前状态锟侥达拷锟斤拷
reg [1:0] R_MS_NEXT;      // 锟斤拷一状态锟侥达拷锟斤拷

always @(posedge I_data_clk or negedge I_reset_n) begin
    if (!I_reset_n) 
        R_MS <= STATE_IDLE;  // 锟斤拷位状态
    else 
        R_MS <= R_MS_NEXT;  // 状态转锟斤拷
end

//-------------------------------------
// 锟节讹拷锟轿ｏ拷锟斤拷一状态锟竭硷拷锟斤拷锟斤拷锟斤拷锟竭硷拷锟斤拷
//-------------------------------------
always @(*) begin
    // 默锟较憋拷锟街碉拷前状态
    R_MS_NEXT = R_MS;
    // 状态转锟斤拷锟斤拷锟斤拷锟叫讹拷
    case (R_MS)
        STATE_IDLE       : R_MS_NEXT = STATE_WAIT_FRAM;   // 锟斤拷锟斤拷状态 -> 锟饺达拷锟斤拷头
        STATE_WAIT_FRAM  : R_MS_NEXT = (r_dout_unpack_valid_d0 & r_packet_frame_start == 1'b1)? STATE_WAIT_DONE : STATE_WAIT_FRAM;
        STATE_WAIT_DONE  : R_MS_NEXT = w_packet_frame_down? STATE_WAIT_FRAM : STATE_WAIT_DONE; // 锟斤拷锟斤拷锟斤拷锟缴伙拷锟斤拷锟斤拷时锟斤拷锟斤拷       
        default: R_MS_NEXT = STATE_IDLE;  // 锟届常锟斤拷锟斤拷
    endcase
end

always @(posedge I_data_clk or negedge I_reset_n) begin
  if (!I_reset_n) 
    r_packet_frame <=  1'b0;
  else 
    r_packet_frame <=  I_packet_frame;
end

//帧锟斤拷始锟脚猴拷
always @(posedge I_data_clk or negedge I_reset_n) begin
  if (!I_reset_n) 
    r_packet_frame_start <=  1'b0;
  else if (R_MS == STATE_WAIT_FRAM) begin
      if (I_packet_frame & r_packet_frame_start == 1'b0) 
        r_packet_frame_start <=  1'b1;
      else if (r_dout_unpack_valid_d0 & r_packet_frame_start == 1'b1)
        r_packet_frame_start <=  1'b0;
      else 
        r_packet_frame_start <=  r_packet_frame_start;
      end
    else r_packet_frame_start <=  1'b0;
  end 


//vaild锟斤拷锟斤拷
always @(posedge I_data_clk or negedge I_reset_n) begin
  if (!I_reset_n) 
      r_dout_unpack_valid_d0 <=  1'b0;
  else  
      r_dout_unpack_valid_d0 <=  I_dout_unpack_valid;
end

always @(posedge I_data_clk or negedge I_reset_n) begin
  if (!I_reset_n) 
    r_data_unpack <=  40'b0;
  else  
    r_data_unpack <=  I_data_unpack;
  
end

//锟斤拷锟斤拷一锟斤拷vaild锟斤拷锟斤拷
always @(posedge I_data_clk or negedge I_reset_n) begin
  if (!I_reset_n) 
    r_last_data_valid <=  1'b0;
  else if (I_packet_done & r_packet_done_vaild) 
    r_last_data_valid <=  1'b1;    
  else if (w_valid_down)  
    r_last_data_valid <=  1'b0;  
  else  
    r_last_data_valid <=  r_last_data_valid;
end

always @(posedge I_data_clk or negedge I_reset_n) begin
  if (!I_reset_n) 
    r_packet_done_vaild <=  1'b0;
  else if (I_packet_line) 
    r_packet_done_vaild <=  1'b1;    
  else if (I_packet_done) 
    r_packet_done_vaild <=  1'b0;      
  else 
    r_packet_done_vaild <=  r_packet_done_vaild; 
end

  // Same recovered clock, continuously ready downstream. RAW DDR supplies
// complete frame storage; a 64-word elastic buffer avoids two extra frame FIFOs.
wire fifo_ready,fifo_valid;
wire [41:0] fifo_data;
v2_async_fifo #(.WIDTH(42),.ADDR(6)) u_stream_fifo(
 .rst_n(I_reset_n && m_axis_video_aresetn),.wclk(I_data_clk),
 .s_data({r_data_unpack,w_vid_last,w_wdata_first_valid}),.s_valid(r_dout_unpack_valid_d0),.s_ready(fifo_ready),
 .rclk(m_axis_video_aclk),.m_data(fifo_data),.m_valid(fifo_valid),.m_ready(m_axis_video_tready),.m_level());
assign w_rdata=fifo_data;
assign empty=!fifo_valid;
  
    // ChipWatcher_vid ChipWatcher_vid
    //(
 	//.clk     (I_data_clk),      
 	//.probe0  (I_packet_done),        
 	//.probe1  (I_packet_line),  
 	//.probe2  (I_packet_frame), 
 	//.probe3  (I_data_unpack), 
 	//.probe4  (I_dout_unpack_valid), 
 	//.probe5  (m_axis_video_tready), 
 	//.probe6  (m_axis_video_tuser), 
 	//.probe7  (m_axis_video_tlast), 
 	//.probe8  (m_axis_video_tvalid), 
 	//.probe9  (m_axis_video_tdata), 
 	//.probe10 (w_rdata),
 	//.probe11 (w_wdata_first_valid),
 	//.probe12 (w_packet_frame_down),
 	//.probe13 (w_vid_last),
 	//.probe14 (empty),
 	//.probe15 (r_dout_unpack_valid_d0),
 	//.probe16 (r_packet_frame_start),
 	//.probe17 (r_packet_frame),
 	//.probe18 (r_last_data_valid),
 	//.probe19 (r_data_unpack),
 	//.probe20 (r_packet_done_vaild)
    //);

//xpm_fifo_async # (
//  .FIFO_MEMORY_TYPE          ("auto"),           //string; "auto", "block", or "distributed";
//  .ECC_MODE                  ("no_ecc"),         //string; "no_ecc" or "en_ecc";
//  .RELATED_CLOCKS            (0),                //positive integer; 0 or 1
//  .FIFO_WRITE_DEPTH          (4096),             //positive integer
//  .WRITE_DATA_WIDTH          (42),               //positive integer
//  .WR_DATA_COUNT_WIDTH       (13),               //positive integer
//  .PROG_FULL_THRESH          (10),               //positive integer
//  .FULL_RESET_VALUE          (0),                //positive integer; 0 or 1
//  .USE_ADV_FEATURES          ("0707"),           //string; "0000" to "1F1F"; 
//  .READ_MODE                 ("fwft"),           //string; "std" or "fwft";
//  .FIFO_READ_LATENCY         (0),                //positive integer;
//  .READ_DATA_WIDTH           (42),               //positive integer
//  .RD_DATA_COUNT_WIDTH       (13),               //positive integer
//  .PROG_EMPTY_THRESH         (10),               //positive integer
//  .DOUT_RESET_VALUE          ("0"),              //string
//  .CDC_SYNC_STAGES           (2),                //positive integer
//  .WAKEUP_TIME               (0)                 //positive integer; 0 or 2;

//) xpm_fifo_async_inst (

//      .rst              (~I_reset_n),
//      .wr_clk           (I_data_clk),
//      .wr_en            (r_dout_unpack_valid_d0),
//      .din              ({r_data_unpack,w_vid_last,w_wdata_first_valid}),
//      .full             (full),
//      .overflow         (),
//      .prog_full        (),
//      .wr_data_count    (),
//      .almost_full      (),
//      .wr_ack           (),
//      .wr_rst_busy      (),
//      .rd_clk           (m_axis_video_aclk),
//      .rd_en            (m_axis_video_tready & ~empty),
//      .dout             (w_rdata),
//      .empty            (empty),
//      .underflow        (),
//      .rd_rst_busy      (),
//      .prog_empty       (),
//      .rd_data_count    (),
//      .almost_empty     (),
//      .data_valid       (),
//      .sleep            (1'b0),
//      .injectsbiterr    (1'b0),
//      .injectdbiterr    (1'b0),
//      .sbiterr          (),
//      .dbiterr          ()

//);
    


endmodule
