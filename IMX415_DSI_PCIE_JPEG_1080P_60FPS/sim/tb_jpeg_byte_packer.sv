`timescale 1ns/1ps
module tb_jpeg_byte_packer;
    reg enc_clk=0,user_clk=0,rst_n=0;
    always #3 enc_clk=~enc_clk;
    always #5 user_clk=~user_clk;
    reg [7:0] s_byte=0;
    reg s_valid=0,s_last=0,m_ready=1;
    wire fault,m_valid,m_last,frame_sent;
    wire [127:0] m_data;
    wire [15:0] m_keep;
    wire [31:0] last_frame_bytes;
    integer n=0,i;
    jpeg_byte_packer #(.FIFO_ADDR_WIDTH(3)) dut (
        .enc_clk(enc_clk),.user_clk(user_clk),.rst_n(rst_n),
        .s_byte(s_byte),.s_valid(s_valid),.s_last(s_last),
        .fault(fault),.m_data(m_data),.m_keep(m_keep),
        .m_valid(m_valid),.m_last(m_last),.m_ready(m_ready),
        .frame_sent(frame_sent),.last_frame_bytes(last_frame_bytes)
    );
    always @(posedge user_clk) if(rst_n && m_valid && m_ready) begin
        if(n==0 && (m_keep!==16'hffff || m_last ||
                     m_data!==128'h0f0e0d0c0b0a09080706050403020100))
            $fatal(1,"first beat bad: %h %h %b",m_data,m_keep,m_last);
        if(n==1 && (m_keep!==16'h0001 || !m_last || m_data[7:0]!==8'h10))
            $fatal(1,"last beat bad: %h %h %b",m_data,m_keep,m_last);
        n=n+1;
    end
    initial begin
        repeat(8) @(negedge enc_clk); rst_n=1;
        for(i=0;i<17;i=i+1) begin
            @(negedge enc_clk);
            s_byte=i[7:0];s_valid=1;s_last=(i==16);
        end
        @(negedge enc_clk);s_valid=0;s_last=0;
        repeat(50) @(negedge user_clk);
        if(n!=2 || fault || last_frame_bytes!=17)
            $fatal(1,"packet count=%0d fault=%b bytes=%0d",n,fault,last_frame_bytes);
        $display("JPEG_BYTE_PACKER_PASS");
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule
