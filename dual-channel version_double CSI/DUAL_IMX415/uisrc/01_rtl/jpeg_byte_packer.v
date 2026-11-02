`timescale 1ns/1ps

// Converts the encoder's unstallable byte stream into one EOP-delimited
// 128-bit SGDMA packet per JPEG. A full FIFO is fatal for the current frame:
// output stops without EOP, and the RK receiver must time out and reset the
// JPEG branch. It must never publish a truncated JPEG as a valid frame.
module jpeg_byte_packer #(
    parameter integer FIFO_ADDR_WIDTH=9,
    parameter integer STALLABLE_INPUT=0
) (
    input wire enc_clk,user_clk,rst_n,
    input wire [7:0] s_byte,
    input wire s_valid,s_last,
    output wire s_ready,
    output reg fault,
    output wire [127:0] m_data,
    output wire [15:0] m_keep,
    output wire m_valid,m_last,
    input wire m_ready,
    output wire frame_sent,
    output reg [31:0] last_frame_bytes
);
    wire enc_reset_n,user_reset_n;
    v2_reset_sync u_enc_reset(enc_clk,rst_n,enc_reset_n);
    v2_reset_sync u_user_reset(user_clk,rst_n,user_reset_n);
    reg [127:0] word_buf;
    reg [3:0] byte_index;
    reg [31:0] byte_count;
    reg [127:0] next_word;
    always @* begin
        next_word=word_buf;
        next_word[byte_index*8 +: 8]=s_byte;
    end
    wire accept=s_valid && (!STALLABLE_INPUT || s_ready);
    wire flush=accept && (byte_index==4'd15 || s_last) && !fault;
    wire [15:0] next_keep=16'hffff >> (4'd15-byte_index);
    wire [144:0] fifo_in={s_last,next_keep,next_word};
    wire [144:0] fifo_out;
    wire fifo_ready,fifo_valid;
    // One-word elastic stage separates byte packing from the asynchronous
    // FIFO pointer/full calculation. It can drain and refill in one cycle.
    reg [144:0] fifo_pending;
    reg fifo_pending_valid;
    wire pending_space=!fifo_pending_valid || fifo_ready;
    // Do not feed the asynchronous FIFO full signal back through the
    // encoder in the same cycle. A pending word occupies this single-entry
    // stage; pause the producer until the word has drained. This inserts at
    // most one bubble per completed 16-byte word in the normal case.
    assign s_ready=enc_reset_n && !fault && !fifo_pending_valid;
    (* ASYNC_REG="TRUE" *) reg [1:0] fault_sync;
    assign m_last=fifo_out[144];
    assign m_keep=fifo_out[143:128];
    assign m_data=fifo_out[127:0];
    assign m_valid=fifo_valid && user_reset_n && !fault_sync[1];
    wire fifo_read=m_valid && m_ready;
    assign frame_sent=fifo_read && m_last;

    always @(posedge enc_clk or negedge enc_reset_n) begin
        if(!enc_reset_n) begin
            fault<=0;word_buf<=0;byte_index<=0;
            byte_count<=0;last_frame_bytes<=0;fifo_pending<=0;fifo_pending_valid<=0;
        end else begin
            if(pending_space) begin
                fifo_pending_valid<=flush;
                if(flush) fifo_pending<=fifo_in;
            end
            if(flush && !pending_space) fault<=1;
            if(accept && !fault && !(flush && !pending_space)) begin
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
    always @(posedge user_clk or negedge user_reset_n) begin
        if(!user_reset_n) begin
            fault_sync<=0;
        end else begin
            fault_sync<={fault_sync[0],fault};
        end
    end
    v2_async_fifo #(.WIDTH(145),.ADDR(FIFO_ADDR_WIDTH)) u_packet_fifo (
        .rst_n(rst_n),.wclk(enc_clk),.s_data(fifo_pending),
        .s_valid(fifo_pending_valid),.s_ready(fifo_ready),
        .rclk(user_clk),.m_data(fifo_out),.m_valid(fifo_valid),.m_ready(fifo_read),.m_level());
endmodule
