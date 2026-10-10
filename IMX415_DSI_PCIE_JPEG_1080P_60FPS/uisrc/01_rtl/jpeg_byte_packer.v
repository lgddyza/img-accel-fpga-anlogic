`timescale 1ns/1ps

// Converts the encoder's unstallable byte stream into one EOP-delimited
// 128-bit SGDMA packet per JPEG. A full FIFO is fatal for the current frame:
// output stops without EOP, and the RK receiver must time out and reset the
// JPEG branch. It must never publish a truncated JPEG as a valid frame.
module jpeg_byte_packer #(
    parameter integer FIFO_ADDR_WIDTH=9
) (
    input wire enc_clk,user_clk,rst_n,
    input wire [7:0] s_byte,
    input wire s_valid,s_last,
    output reg fault,
    output wire [127:0] m_data,
    output wire [15:0] m_keep,
    output wire m_valid,m_last,
    input wire m_ready,
    output wire frame_sent,
    output reg [31:0] last_frame_bytes
);
    reg [127:0] word_buf;
    reg [3:0] byte_index;
    reg [31:0] byte_count;
    reg [127:0] next_word;
    always @* begin
        next_word=word_buf;
        next_word[byte_index*8 +: 8]=s_byte;
    end
    wire flush=s_valid && (byte_index==4'd15 || s_last) && !fault;
    wire [15:0] next_keep=16'hffff >> (4'd15-byte_index);
    wire [144:0] fifo_in={s_last,next_keep,next_word};
    wire [144:0] fifo_out;
    wire fifo_full,fifo_empty;
    wire fifo_write=flush && !fifo_full;
    reg primed;
    (* ASYNC_REG="TRUE" *) reg [1:0] fault_sync;
    assign m_last=fifo_out[144];
    assign m_keep=fifo_out[143:128];
    assign m_data=fifo_out[127:0];
    assign m_valid=!fifo_empty && primed && !fault_sync[1];
    wire fifo_read=m_valid && m_ready;
    assign frame_sent=fifo_read && m_last;

    always @(posedge enc_clk or negedge rst_n) begin
        if(!rst_n) begin
            fault<=0;word_buf<=0;byte_index<=0;
            byte_count<=0;last_frame_bytes<=0;
        end else begin
            if(flush && fifo_full) fault<=1;
            if(s_valid && !fault && !(flush && fifo_full)) begin
                if(s_last) begin
                    last_frame_bytes<=byte_count+1'b1;
                    byte_count<=0;
                end else byte_count<=byte_count+1'b1;
                if(flush) begin
                    byte_index<=0;
                    word_buf<=0;
                end else begin
                    byte_index<=byte_index+1'b1;
                    word_buf<=next_word;
                end
            end
        end
    end
    always @(posedge user_clk or negedge rst_n) begin
        if(!rst_n) begin
            primed<=0;
            fault_sync<=0;
        end else begin
            primed<=!fifo_empty;
            fault_sync<={fault_sync[0],fault};
        end
    end
    demo_async_sfifo #(
        .DATA_WIDTH_W(145),.DATA_WIDTH_R(145),
        .ADDR_WIDTH_W(FIFO_ADDR_WIDTH),.ADDR_WIDTH_R(FIFO_ADDR_WIDTH),
        .AL_FULL_NUM(16),.AL_EMPTY_NUM(4),
        .SHOW_AHEAD_EN(1'b1),.OUTREG_EN("NOREG")
    ) u_packet_fifo (
        .rst(~rst_n),.clkw(enc_clk),.clkr(user_clk),
        .we(fifo_write),.di(fifo_in),
        .re(fifo_read),.dout(fifo_out),.valid(),
        .full_flag(fifo_full),.empty_flag(fifo_empty),
        .afull(),.aempty(),.wrusedw(),.rdusedw()
    );
endmodule
