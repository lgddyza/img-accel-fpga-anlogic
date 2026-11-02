`timescale 1ns/1ps
module tb_clahe_weight_equiv;
  parameter W=64,H=32,N=W*H/4;
  reg clk=0,rst_n=0,valid=0,sof=0,eol=0,enable=1;
  reg [31:0] gray=0;
  wire [31:0] a,b,fa,fb,ea,eb;
  wire av,asof,aeol,aa,ar,bv,bsof,beol,ba,br;
  integer i,f,checks=0;
  reg [31:0] rnd=32'h12345678;
  always #4 clk=~clk;
  gray_clahe4 #(.WIDTH(W),.HEIGHT(H)) dut(clk,rst_n,gray,valid,sof,eol,enable,a,av,asof,aeol,aa,fa,ea,ar);
  gray_clahe4_reference #(.WIDTH(W),.HEIGHT(H)) refdut(clk,rst_n,gray,valid,sof,eol,enable,b,bv,bsof,beol,ba,fb,eb,br);
  always @(negedge clk) if(rst_n) begin
    if ({av,asof,aeol,aa,ar,fa,ea} !== {bv,bsof,beol,ba,br,fb,eb})
      $fatal(1,"control mismatch frame %0d pixel %0d",f,i);
    if(av) begin
      if(a!==b) $fatal(1,"pixel mismatch frame %0d pixel %0d got %h expected %h",f,i,a,b);
      checks=checks+1;
    end
  end
  initial begin
    repeat(4) @(negedge clk); rst_n=1;
    for(f=0;f<5;f=f+1) begin
      wait(ar && br);
      for(i=0;i<N;i=i+1) begin
        @(negedge clk); #1;
        rnd={rnd[30:0],rnd[31]^rnd[21]^rnd[1]^rnd[0]};
        gray=rnd; valid=1; sof=i==0; eol=i%(W/4)==W/4-1;
        if(f%2 && i%31==7) begin
          @(negedge clk); #1; valid=0;sof=0;eol=0;
        end
      end
      @(negedge clk); #1; valid=0;sof=0;eol=0;
      repeat(10) @(negedge clk);
    end
    repeat(20) @(negedge clk);
    if(checks!=5*N || ea!=0 || eb!=0 || fa<4 || fb<4) $fatal(1,"bad count %0d hist %0d/%0d errors %0d/%0d",checks,fa,fb,ea,eb);
    $display("PASS CLAHE reference exact pixels=%0d frames=%0d/%0d",checks,fa,fb);
    $finish;
  end
  initial begin #20000000; $fatal(1,"timeout"); end
endmodule
