`timescale 1ns/1ps
module tb_jpeg_elastic;
  reg enc_clk=0,user_clk=0,rst_n=0;
  always #2.5 enc_clk=~enc_clk;
  always #4 user_clk=~user_clk;
  reg [7:0] s_byte=0;
  reg s_valid=0,s_last=0,m_ready=0;
  wire s_ready,fault,m_valid,m_last,frame_sent;
  wire [127:0] m_data;
  wire [15:0] m_keep;
  wire [31:0] last_frame_bytes;
  jpeg_byte_packer #(.FIFO_ADDR_WIDTH(2),.STALLABLE_INPUT(1)) dut(.*);
  function integer frame_len(input integer f);
    case(f%6)
      0:frame_len=1; 1:frame_len=15; 2:frame_len=16;
      3:frame_len=17; 4:frame_len=31; default:frame_len=48;
    endcase
  endfunction
  function [7:0] pattern(input integer n);
    pattern=(n*37+91)&255;
  endfunction
  integer sent=0,tx_frame=0,tx_pos=0,rx_byte=0,rx_frame=0,rx_pos=0,cycles=0;
  reg hold=0; reg [144:0] saved;
  always @(negedge enc_clk) if(rst_n && tx_frame<120) begin
    s_valid=1;s_byte=pattern(sent);s_last=(tx_pos==frame_len(tx_frame)-1);
  end else s_valid=0;
  always @(posedge enc_clk) if(rst_n && s_valid && s_ready) begin
    sent=sent+1;
    if(s_last) begin tx_frame=tx_frame+1;tx_pos=0;end
    else tx_pos=tx_pos+1;
  end
  always @(negedge user_clk) if(rst_n) begin
    cycles=cycles+1;
    m_ready=(cycles%47>=23) && (cycles%7!=0);
  end
  always @(posedge user_clk) if(rst_n) begin
    if(fault) $fatal(1,"stallable input should not overflow");
    if(hold && (!m_valid || {m_last,m_keep,m_data}!==saved))
      $fatal(1,"output changed under backpressure");
    hold=m_valid && !m_ready;saved={m_last,m_keep,m_data};
    if(m_valid && m_ready) begin
      if(m_keep==0 || (m_keep & (m_keep+16'd1))!=0)
        $fatal(1,"invalid keep mask %h",m_keep);
      for(integer b=0;b<16;b=b+1) if(m_keep[b]) begin
        if(m_data[b*8+:8]!==pattern(rx_byte)) $fatal(1,"byte mismatch %0d",rx_byte);
        rx_byte=rx_byte+1;rx_pos=rx_pos+1;
      end
      if(m_last) begin
        if(rx_pos!=frame_len(rx_frame)) $fatal(1,"bad frame %0d length %0d",rx_frame,rx_pos);
        rx_frame=rx_frame+1;rx_pos=0;
      end else if(rx_pos>=frame_len(rx_frame)) $fatal(1,"missing EOP");
    end
  end
  initial begin
    repeat(8) @(negedge enc_clk);rst_n=1;
    wait(rx_frame==120);repeat(10) @(posedge user_clk);
    if(rx_byte!=sent || fault) $fatal(1,"final count mismatch");
    $display("PASS 120 mixed-size JPEG packets, tiny FIFO, elastic-stage refill, sustained backpressure");$finish;
  end
  initial begin #500000;$fatal(1,"timeout");end
endmodule
