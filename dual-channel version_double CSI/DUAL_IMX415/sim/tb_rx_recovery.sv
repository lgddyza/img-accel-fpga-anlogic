`timescale 1ns/1ps
module tb_rx_recovery;
 reg refclk=0,rxclk=0,rst=0,run=1;
 always #7 refclk=~refclk;
 always #4.5 if(run) rxclk=~rxclk;
 wire rx_reset;
 v2rx_csi_rx_clock_det detector(refclk,rxclk,1'b1,rst,rx_reset);
 wire [5:0] tap0,tap1,best0,best1;wire load0,load1,done0,done1;
 wire [3:0] aligned0=(tap0>=5 && tap0<=21)?4'hf:4'h0;
 v2rx_auto_delay_ctl eye0(rxclk,rst,aligned0,tap0,load0,done0,best0);
 v2rx_auto_delay_ctl eye1(rxclk,rst,4'hf,tap1,load1,done1,best1);
 always @(posedge rxclk) if(rst && (tap0>31 || tap1>31)) $fatal(1,"PH1A tap overflow");
 reg recovered=0;
 initial begin
  #25;rst=1;wait(rx_reset);repeat(10) @(negedge refclk);run=0;
  repeat(300) @(negedge refclk);if(rx_reset) $fatal(1,"clock stop did not assert reset");
  run=1;wait(rx_reset);recovered=1;
 end
 initial begin
  wait(done0 && done1 && recovered);
  if(tap0!=13 || best0!=17 || tap1!=16 || best1!=32) $fatal(1,"eye center/all-pass window incorrect");
  $display("PASS stopped/restarted RX clock, synchronous reset recovery, 32-tap windows including all-pass");$finish;
 end
 initial begin #12000000;$fatal(1,"RX recovery timeout");end
endmodule
