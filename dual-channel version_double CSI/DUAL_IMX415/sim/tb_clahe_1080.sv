`timescale 1ns/1ps
module tb_clahe_1080;
 localparam W=1920,H=1080,N=W*H/4;
 reg clk=0,rst_n=0,camera=0,valid=0,sof=0,eol=0;
 reg [31:0] gray=0;
 wire [31:0] out,fa,fb,ea,eb; wire ov,os,oe;
 integer i,f,ic=0,oc=0,sc=0,ec=0,changed=0;
 always #4 clk=~clk;
 clahe_dual_prototype #(.WIDTH(W),.HEIGHT(H)) dut(.clk(clk),.rst_n(rst_n),.camera(camera),
   .mode(3'd2),.strength(3'd4),.gray(gray),.valid(valid),.sof(sof),.eol(eol),
   .out(out),.out_valid(ov),.out_sof(os),.out_eol(oe),.frames_a(fa),.frames_b(fb),.errors_a(ea),.errors_b(eb));
 always @(posedge clk) begin
  if(valid) ic<=ic+1;
  if(ov) begin
   if(os!==((oc%N)==0) || oe!==((oc%(W/4))==(W/4)-1)) $fatal(1,"geometry at %0d",oc);
   if(dut.accepted_pipe[2] && !dut.ev[dut.cam_pipe[2]]) $fatal(1,"CLAHE valid misaligned");
   if(oc>=4*N && out!==(dut.cam_pipe[2] ? 32'hb4b4b4b4 : 32'h14141414)) changed<=changed+1;
   oc<=oc+1;if(os)sc<=sc+1;if(oe)ec<=ec+1;
  end
 end
 initial begin
  repeat(3) @(negedge clk);rst_n=1;repeat(1100) @(negedge clk);
  for(f=0;f<6;f=f+1) begin
   camera=f%2;gray=camera ? 32'hb4b4b4b4 : 32'h14141414;
   for(i=0;i<N;i=i+1) begin
    @(negedge clk);valid=1;sof=(i==0);eol=(i%(W/4)==W/4-1);
   end
   @(negedge clk);valid=0;sof=0;eol=0;repeat(12) @(negedge clk);
   $display("1080 frame %0d accepted=%b completed=%0d/%0d",f,dut.accept_frame[camera],fa,fb);
  end
  repeat(20000) @(negedge clk);
  if(ic!=6*N || oc!=ic || sc!=6 || ec!=6*H || ea!=0 || eb!=0 || fa<2 || fb<2 || changed==0)
   $fatal(1,"FAIL counts %0d %0d %0d %0d hist=%0d/%0d errors=%0d/%0d changed=%0d",ic,oc,sc,ec,fa,fb,ea,eb,changed);
  $display("PASS full 1080p dual CLAHE input=%0d output=%0d changed=%0d hist=%0d/%0d errors=%0d/%0d",ic,oc,changed,fa,fb,ea,eb);$finish;
 end
endmodule
