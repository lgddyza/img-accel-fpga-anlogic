`timescale 1ns/1ps

// Hold one full word until its successor arrives. On an input error the
// held word closes a SHORT packet; no synthetic padding can turn a damaged
// frame into a correctly sized frame.
module gray_frame_packer #(
    parameter integer FRAME_PIXELS=1280*720,
    parameter integer TIMEOUT_CYCLES=125000,
    parameter integer FIFO_ADDR_BITS=7
)(
    input wire clk, rst_n, enable,
    input wire [7:0] s_gray,
    input wire s_valid, s_sof, s_eof, s_abort,
    input wire dma_ready,
    output wire [127:0] m_tdata,
    output wire m_tvalid,
    input wire m_tready,
    output wire m_tlast,
    output reg [31:0] pass_count, drop_count,
    output reg [31:0] delivered_count
);
    reg [127:0] pack, pending;
    reg [19:0] pixel_index;
    reg active, pending_valid, closing, good_close;
    reg [19:0] idle_count;
    wire [FIFO_ADDR_BITS:0] fifo_fill;
    wire fifo_ready;
    wire select_frame = enable && dma_ready && fifo_fill==0 && !m_tvalid &&
                        !active && !pending_valid && !closing;
    wire input_error = s_abort || (s_valid && active &&
                       (s_sof || (s_eof != (pixel_index==FRAME_PIXELS-1)))) ||
                       (active && idle_count==TIMEOUT_CYCLES-1);
    wire complete_word = s_valid && active && !input_error &&
                         pixel_index[3:0]==15;
    wire [127:0] packed_word = {s_gray,pack[127:8]};
    wire fifo_valid = pending_valid && (closing || complete_word);
    wire [127:0] fifo_data = pending;
    wire fifo_last = closing;

    axis_stream_fifo #(.DATA_WIDTH(128),.DEPTH(1<<FIFO_ADDR_BITS),.DISTRIBUTED_RAM(1),
                      .ADDR_BITS(FIFO_ADDR_BITS)) u_dma_fifo (
        .clk(clk),.rst_n(rst_n),.s_tdata(fifo_data),.s_tvalid(fifo_valid),
        .s_tready(fifo_ready),.s_tlast(fifo_last),.m_tdata(m_tdata),
        .m_tvalid(m_tvalid),.m_tready(m_tready),.m_tlast(m_tlast),
        .fill_level(fifo_fill)
    );
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pack<=0;pending<=0;pixel_index<=0;active<=0;pending_valid<=0;
            closing<=0;good_close<=0;idle_count<=0;
            pass_count<=0;drop_count<=0;delivered_count<=0;
        end else begin
            if(m_tvalid && m_tready && m_tlast) delivered_count<=delivered_count+1'b1;
            if(active && !s_valid) begin
                if(idle_count<TIMEOUT_CYCLES-1) idle_count<=idle_count+1'b1;
            end else idle_count<=0;
            if(closing && pending_valid && fifo_ready) begin
                pending_valid<=0;closing<=0;
                if(good_close) pass_count<=pass_count+1'b1;
            end
            if(s_valid && s_sof && !active) begin
                active<=select_frame;
                if(select_frame) begin pixel_index<=1;pack<={s_gray,120'd0};end
                else drop_count<=drop_count+1'b1;
            end else if(s_valid && active && !input_error) begin
                pixel_index<=pixel_index+1'b1;
                pack<=packed_word;
                if(complete_word) begin
                    if(!pending_valid || fifo_ready) begin
                        pending<=packed_word;pending_valid<=1;
                        if(s_eof) begin active<=0;closing<=1;good_close<=1;end
                    end else begin
                        active<=0;closing<=1;good_close<=0;
                        drop_count<=drop_count+1'b1;
                    end
                end
            end
            if(input_error && active) begin
                active<=0;closing<=pending_valid;good_close<=0;
                drop_count<=drop_count+1'b1;
            end
        end
    end
endmodule
