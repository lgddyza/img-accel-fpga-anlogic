`timescale 1ns/1ps
module tb_jpeg_packer_stall;
`ifdef SMALL_JPEG_FIFO
    localparam DEPTH=7;
`else
    localparam DEPTH=10;
`endif
    reg enc_clk=0,user_clk=0,rst_n=0;
    always #2.5 enc_clk=~enc_clk;always #4 user_clk=~user_clk;
    reg [7:0] s_byte=0;reg s_valid=0,s_last=0,m_ready=0;
    wire fault,m_valid,m_last,frame_sent,s_ready;
    wire [127:0] m_data;wire [15:0] m_keep;wire [31:0] last_frame_bytes;
    jpeg_byte_packer #(.FIFO_ADDR_WIDTH(DEPTH)) dut(.*);
    integer received=0,frames=0,cycles=0;reg check_data=0,stalled=0;
    reg [144:0] held;
    function [7:0] pattern(input integer byte_number);
        pattern=(byte_number*37+byte_number/17+91)&255;
    endfunction
    always @(negedge user_clk) if(check_data) begin
        cycles=cycles+1;m_ready=cycles%13>3;
    end
    always @(posedge user_clk) if(rst_n) begin
        if(stalled && !fault && (!m_valid || {m_last,m_keep,m_data}!==held)) $fatal(1,"JPEG changed under DMA stall");
        stalled=m_valid && !m_ready;held={m_last,m_keep,m_data};
        if(m_valid && m_ready) begin
            for(integer b=0;b<16;b=b+1) if(m_keep[b]) begin
                if(m_data[b*8+:8]!==pattern(received)) $fatal(1,"bad JPEG byte %0d",received);
                received=received+1;
            end
            if(m_last) begin
                if(received!=10007) $fatal(1,"bad final keep/EOP received=%0d",received);
                received=0;frames=frames+1;
            end
        end
    end
    task send_frame;
        for(integer b=0;b<10007;b=b+1) begin
            @(negedge enc_clk);s_valid=1;s_byte=pattern(b);s_last=b==10006;
        end
        @(negedge enc_clk);s_valid=0;s_last=0;
    endtask
    initial begin
        repeat(10) @(negedge enc_clk);rst_n=1;repeat(10) @(negedge enc_clk);
        // Linux/DMA is paused for the entire 10 KB burst, then resumes with
        // stalls. The old 2 KB capacity must fail; 16 KB must preserve all bytes.
        send_frame();repeat(20) @(negedge user_clk);
`ifdef SMALL_JPEG_FIFO
        if(!fault) $fatal(1,"small-buffer overflow was not detected");
        repeat(10) @(negedge user_clk);
        if(m_valid) $fatal(1,"overflow published a truncated packet");
        $display("PASS negative control: 2 KiB JPEG output FIFO overflows during host pause");$finish;
`else
        if(fault || last_frame_bytes!=10007) $fatal(1,"16 KiB FIFO failed paused host");
        check_data=1;wait(frames==1);
        send_frame();wait(frames==2);
        repeat(12) @(negedge user_clk);
        if(fault || m_valid) $fatal(1,"packer did not drain cleanly");
        $display("PASS 16 KiB JPEG output: paused host, 2 x 10007 exact bytes, final keep/EOP, pointer wrap, random stalls");$finish;
`endif
    end
    initial begin #1000000;$fatal(1,"packer timeout");end
endmodule
