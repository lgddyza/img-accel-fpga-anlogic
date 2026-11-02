`timescale 1ns/1ps
module tb_clahe_dual_prototype;
 localparam W=64,H=32,N=W*H/4;
 reg clk=0,rst_n=0,cam=0,valid=0,sof=0,eol=0;
 reg [2:0] mode=2,strength=4;reg [31:0] gray=0;
 wire [31:0] out,fa,fb,ea,eb;wire ov,os,oe;
 integer i,ins=0,outs=0,sofs=0,eols=0,enhanced=0;
 integer binidx,tile,base;
 reg [7:0] value_a,value_b;
 reg [31:0] expected_pixels[0:4095];reg expected_sof[0:4095],expected_eol[0:4095],expected_bypass[0:4095];
 always #5 clk=~clk;
 clahe_dual_prototype #(.WIDTH(W),.HEIGHT(H)) dut(clk,rst_n,cam,mode,strength,gray,valid,sof,eol,out,ov,os,oe,fa,fb,ea,eb);
 always @(posedge clk) begin
  if(valid) begin
   expected_pixels[ins]=gray;expected_sof[ins]=sof;expected_eol[ins]=eol;
   expected_bypass[ins]=!dut.accept;ins<=ins+1;
  end
  if(ov) begin
   if(os!==expected_sof[outs] || oe!==expected_eol[outs]) $fatal(1,"marker mismatch at %0d",outs);
   if(expected_bypass[outs] && out!==expected_pixels[outs]) $fatal(1,"bypass pixel mismatch at %0d",outs);
   if(!expected_bypass[outs]) begin
    if(!dut.ev[dut.cam_pipe[2]]) $fatal(1,"accepted sample lacks aligned core valid");
    if(dut.g[0].core.lut_active && out!==expected_pixels[outs]) enhanced=enhanced+1;
   end
   outs<=outs+1;if(os)sofs<=sofs+1;if(oe)eols<=eols+1;
  end
 end
 task frame(input c,input [2:0] m,input [7:0] value);
  begin
   for(i=0;i<N;i=i+1) begin
    @(negedge clk);cam=c;mode=m;gray={4{value}};valid=1;sof=(i==0);eol=(i%(W/4)==W/4-1);
   end
   @(negedge clk);valid=0;sof=0;eol=0;
  end
 endtask
 initial begin
  repeat(3) @(negedge clk);rst_n=1;repeat(1100) @(negedge clk);
  frame(0,2,20);frame(1,2,180);
  repeat(1200) @(negedge clk);
  frame(0,2,20);frame(1,2,180);
  frame(0,2,45);
  if(dut.accept_frame[0]) $fatal(1,"busy frame was accepted");
  repeat(10000) @(negedge clk);
  if(!dut.g[0].core.lut_active || !dut.g[1].core.lut_active) $fatal(1,"missing LUTs");
  for(tile=0;tile<4;tile=tile+1) begin
   for(binidx=0;binidx<256;binidx=binidx+1) begin
    case(tile)
     0:begin value_a=dut.g[0].core.lut00[binidx];value_b=dut.g[1].core.lut00[binidx];end
     1:begin value_a=dut.g[0].core.lut01[binidx];value_b=dut.g[1].core.lut01[binidx];end
     2:begin value_a=dut.g[0].core.lut10[binidx];value_b=dut.g[1].core.lut10[binidx];end
     3:begin value_a=dut.g[0].core.lut11[binidx];value_b=dut.g[1].core.lut11[binidx];end
    endcase
    base=tile*256+binidx;
    if(value_a !== dut.g[0].core.previous_map[base] || value_b !== dut.g[1].core.previous_map[base]) $fatal(1,"LUT mismatch tile=%0d bin=%0d",tile,binidx);
   end
  end
  $display("PASS both cameras: all full LUT entries match their history");
  if(dut.g[0].core.previous_map[20] == dut.g[1].core.previous_map[20]) $fatal(1,"expected independent maps");
  $display("separate LUTs valid A_bin20=%0d B_bin20=%0d",dut.g[0].core.previous_map[20],dut.g[1].core.previous_map[20]);
  frame(0,2,20); repeat(10000) @(negedge clk);
  if(enhanced==0) $fatal(1,"no pixels changed after LUT activation");
  frame(0,3,30); repeat(1100) @(negedge clk);
  if(dut.g[0].core.lut_active || !dut.g[1].core.lut_active) $fatal(1,"mode change isolation failed");
  repeat(10) @(negedge clk);
  if(ins!=outs || sofs!=7 || eols!=7*H || ea!=0 || eb!=0) $fatal(1,"output count, markers or errors mismatch %0d %0d %0d %0d %0d %0d",ins,outs,sofs,eols,ea,eb);
  $display("PASS input=%0d output=%0d SOF=%0d EOL=%0d errors=%0d/%0d",ins,outs,sofs,eols,ea,eb);$finish;
 end
endmodule
