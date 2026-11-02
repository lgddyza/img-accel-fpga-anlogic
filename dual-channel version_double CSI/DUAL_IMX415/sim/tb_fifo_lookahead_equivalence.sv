`timescale 1ns/1ps
module tb_fifo_lookahead_equivalence;
  reg rst_n=0,wclk=0,rclk=0,s_valid=0,m_ready=0;
  reg [31:0] s_data=0,wrng=32'h4c312db7,rrng=32'ha4e5173b;
  wire s_ready0,s_ready1,m_valid0,m_valid1;
  wire [31:0] m_data0,m_data1;
  wire [5:0] m_level0,m_level1,s_level0,s_level1;
  v2_async_fifo #(.WIDTH(32),.ADDR(5),.READ_INCREMENT_LOOKAHEAD(0)) ref_fifo
    (.rst_n(rst_n),.wclk(wclk),.s_data(s_data),.s_valid(s_valid),.s_ready(s_ready0),
     .rclk(rclk),.m_data(m_data0),.m_valid(m_valid0),.m_ready(m_ready),.m_level(m_level0),.s_level(s_level0));
  v2_async_fifo #(.WIDTH(32),.ADDR(5),.READ_INCREMENT_LOOKAHEAD(1)) new_fifo
    (.rst_n(rst_n),.wclk(wclk),.s_data(s_data),.s_valid(s_valid),.s_ready(s_ready1),
     .rclk(rclk),.m_data(m_data1),.m_valid(m_valid1),.m_ready(m_ready),.m_level(m_level1),.s_level(s_level1));
  always #3.75 wclk=~wclk;
  always #2.5 rclk=~rclk;
  integer wc=0,rc=0,compared=0;
  always @(negedge wclk) begin
    wrng={wrng[30:0],wrng[31]^wrng[21]^wrng[1]^wrng[0]};wc=wc+1;
    s_valid=(wc%600<200) ? 1 : (wc%600<300 ? 0 : wrng[0]);
    s_data=wrng;
  end
  always @(negedge rclk) begin
    rrng={rrng[30:0],rrng[31]^rrng[21]^rrng[1]^rrng[0]};rc=rc+1;
    m_ready=(rc%900<250) ? 0 : (rc%900<550 ? 1 : rrng[3]);
  end
  always @(posedge wclk) begin #0.1;
    if(rst_n && (s_ready0!==s_ready1 || s_level0!==s_level1))
      $fatal(1,"write-side mismatch at %0d",wc);
  end
  always @(posedge rclk) begin #0.1;
    if(rst_n) begin
      if(m_valid0!==m_valid1 || m_level0!==m_level1 || (m_valid0 && m_data0!==m_data1))
        $fatal(1,"read-side mismatch at %0d",rc);
      if(new_fifo.rp!==ref_fifo.rp || new_fifo.rg!==ref_fifo.rg) $fatal(1,"pointer mismatch");
      if(m_valid0 && m_ready) compared=compared+1;
    end
  end
  initial begin
    #31 rst_n=1;#190000;rst_n=0;#19 rst_n=1;#190000;
    if(compared<2000) $fatal(1,"insufficient transfer coverage %0d",compared);
    $display("PASS lookahead FIFO equivalence: %0d transferred words, async clocks, full/empty, wrap, stalls and reset",compared);$finish;
  end
endmodule
