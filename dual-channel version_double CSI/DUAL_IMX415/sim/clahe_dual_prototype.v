`timescale 1ns/1ps
// Experimental harness only: not connected to the project top or a delivery bitstream.
// Two independent legacy cores are used to test isolation and mode invalidation.
module clahe_dual_prototype #(parameter WIDTH=64, HEIGHT=32)(
 input wire clk,rst_n,camera,input wire [2:0] mode,strength,
 input wire [31:0] gray,input wire valid,sof,eol,
 output wire [31:0] out,output wire out_valid,out_sof,out_eol,
 output wire [31:0] frames_a,frames_b,errors_a,errors_b
);
 reg [5:0] signature[0:1]; reg [1:0] known, accept_frame;
 reg [1:0] reset_core;
 wire enabled=(mode==2 || mode==3);
 wire [5:0] key={mode,(mode==3 ? strength : 3'd0)};
 wire changed=!known[camera] || signature[camera]!=key;
 wire [1:0] input_ready;
 wire accept = enabled && (sof ? (!changed && input_ready[camera]) : accept_frame[camera]);
 always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin known<=0;accept_frame<=0;reset_core<=0;signature[0]<=0;signature[1]<=0;end
   else begin
     reset_core<=0;
     if(valid && sof) begin
       signature[camera]<=key;known[camera]<=1;
       accept_frame[camera]<=enabled && !changed && input_ready[camera];
       if(changed) reset_core[camera]<=1;
     end
   end
 end
 wire [31:0] eq[0:1]; wire [1:0] ev,es,ee,ready;
 wire [31:0] counts[0:1], errs[0:1];
 assign frames_a=counts[0];assign frames_b=counts[1];
 assign errors_a=errs[0];assign errors_b=errs[1];
 genvar c;
 generate for(c=0;c<2;c=c+1) begin:g
   gray_clahe4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) core(
    .clk(clk),.rst_n(rst_n && !reset_core[c]),.s_gray(gray),
    .s_valid(valid && camera==c && accept),.s_sof(sof),.s_eol(eol),.enable(1'b1),
    .m_gray(eq[c]),.m_valid(ev[c]),.m_sof(es[c]),.m_eol(ee[c]),.lut_active(ready[c]),
    .hist_frames(counts[c]),.hist_errors(errs[c]),.input_ready(input_ready[c]));
 end endgenerate
 reg [31:0] raw0,raw1,raw2;
 reg [2:0] vpipe,spipe,epipe,cam_pipe,accepted_pipe;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin vpipe<=0;spipe<=0;epipe<=0;cam_pipe<=0;accepted_pipe<=0;raw0<=0;raw1<=0;raw2<=0;end
  else begin
   raw0<=gray;raw1<=raw0;raw2<=raw1;
   vpipe<={vpipe[1:0],valid};spipe<={spipe[1:0],valid&&sof};epipe<={epipe[1:0],valid&&eol};
   cam_pipe<={cam_pipe[1:0],camera};accepted_pipe<={accepted_pipe[1:0],accept};
  end
 end
 assign out_valid=vpipe[2];assign out_sof=spipe[2];assign out_eol=epipe[2];
 assign out=accepted_pipe[2] ? eq[cam_pipe[2]] : raw2;
endmodule
