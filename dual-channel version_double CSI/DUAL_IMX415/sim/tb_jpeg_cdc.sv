`timescale 1ns/1ps
module tb_jpeg_cdc;
 parameter COMPACT_MONO=0;
 reg wclk=0,rclk=0,rst=0;always #7 wclk=~wclk;always #2.5 rclk=~rclk;
 reg [63:0] data=0;reg valid=0,sof=0,eol=0,take=1,ready=0;
 wire [15:0] q;wire qv,qs,qe,fault,sfault;
 jpeg_gray4_axis_cdc #(.IMG_WIDTH(32),.IMG_HEIGHT(4),.FIFO_ADDR_WIDTH(5),.COMPACT_MONO(COMPACT_MONO)) dut(
  .cam_clk(wclk),.enc_clk(rclk),.rst_n(rst),.s_yuyv4(data),.s_valid(valid),.s_sof(sof),.s_eol(eol),
  .s_take_frame(take),.s_fault(sfault),.m_tdata(q),.m_tvalid(qv),.m_tready(ready),
  .m_tuser(qs),.m_tlast(qe),.m_fault(fault));
 integer received=0,cycle=0,ready_mode=0;reg stalled=0;reg [17:0] held;
 reg continuous_check=0,stream_started=0;
 always @(negedge rclk) begin
  cycle=cycle+1;
  ready=ready_mode==2 ? 1'b1 : ready_mode==1 ? 1'b0 : cycle%11>2;
 end
 always @(posedge rclk or negedge rst) if(!rst) begin
  received=0;stalled=0;stream_started=0;
 end else begin
  if(stalled && (!qv || {qs,qe,q}!==held)) $fatal(1,"payload/valid changed under stall");
  if(continuous_check && stream_started && received<128 && !qv)
   $fatal(1,"bubble in prefilled continuous output at pixel %0d",received);
  stalled=qv&&!ready;held={qs,qe,q};
  if(qv && ready) begin
   if(q!==(COMPACT_MONO ? (16'h8000|received) : received) || qs!==(received==0) || qe!==(received%32==31))
    $fatal(1,"bad serialized pixel %0d data=%0d sof=%b eol=%b",received,q,qs,qe);
   received=received+1;
   stream_started=1;
  end
 end
 integer i,j;
 task send_frame(input integer bubbles);
  begin
   for(i=0;i<32;i=i+1) begin
    for(j=0;j<4;j=j+1) data[j*16+:16]=i*4+j;
    valid=1;sof=i==0;eol=i%8==7;
    @(negedge wclk);valid=0;sof=0;eol=0;
    repeat(bubbles) @(negedge wclk);
   end
  end
 endtask
 task reset_stream;
  begin
   valid=0;sof=0;eol=0;continuous_check=0;
   #1 rst=0;#1;if(qv) $fatal(1,"reset did not flush output");
   repeat(4) @(negedge wclk);rst=1;repeat(10) @(negedge wclk);
  end
 endtask
 initial begin
  repeat(4) @(negedge wclk);rst=1;repeat(10) @(negedge wclk);
  send_frame(3);
  wait(received==128);repeat(8) @(negedge wclk);
  if(fault || sfault) $fatal(1,"unexpected CDC fault");
  ready_mode=1;reset_stream();send_frame(0);
  repeat(8) @(negedge wclk);
  continuous_check=1;ready_mode=2;
  wait(received==128);repeat(8) @(negedge wclk);
  if(fault || sfault) $fatal(1,"prefill caused CDC fault");
  ready_mode=1;reset_stream();send_frame(0);
  repeat(8) @(negedge wclk);
  if(!qv || received!=0) $fatal(1,"expected pending stalled frame before reset");
  reset_stream();ready_mode=0;send_frame(2);
  wait(received==128);repeat(8) @(negedge wclk);
  if(fault || sfault) $fatal(1,"restart caused CDC fault");
  $display("PASS asynchronous 4:1 pixels, SOF/EOL, backpressure, 128 pixels without bubbles, occupied reset/restart");$finish;
 end
 initial begin #100000;$fatal(1,"CDC timeout");end
endmodule
