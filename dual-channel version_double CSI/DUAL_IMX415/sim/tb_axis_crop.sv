`timescale 1ns/1ps
module tb_axis_crop;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg [39:0] data=0;reg valid=0,sof=0,eol=0;
 wire [39:0] q;wire v,s,e,odd;wire [31:0] errors;
 v2_axis_crop #(.WIDTH(16),.HEIGHT(3),.TOP(2)) dut(clk,rst,data,valid,sof,eol,q,v,s,e,odd,errors);
 integer count=0,starts=0,ends=0;
 always @(negedge clk) if(v) begin
  if(q!==((count/4+2)*100+count%4+1)) $fatal(1,"wrong crop pixel %0d=%0d",count,q);
  if(s!==(count==0) || e!==(count%4==3) || odd!==0) $fatal(1,"crop markers/parity");
  count=count+1;if(s) starts=starts+1;if(e) ends=ends+1;
 end
 integer y,x;
 initial begin
  repeat(3) @(negedge clk);rst=1;
  @(negedge clk);sof=1;@(negedge clk);sof=0;
  for(y=0;y<6;y=y+1) begin
   for(x=0;x<7;x=x+1) begin
    repeat(x==2?15:1) @(negedge clk);
    data=y*100+x;valid=1;eol=x==6;
    @(negedge clk);valid=0;eol=0;
   end
  end
  repeat(3) @(negedge clk);
  if(count!=12 || starts!=1 || ends!=3 || errors!=0) $fatal(1,"crop geometry");
  $display("PASS packet EOL crop with short/long bubbles and border rejection");$finish;
 end
endmodule
