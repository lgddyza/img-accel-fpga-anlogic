`timescale 1ns/1ps

// Independent JPEG tap after gray4_to_yuyv4. The live display path has no
// backpressure, so the caller selects a whole frame at SOF. On a malformed
// frame or FIFO overflow this bridge latches a fault and stops the AXI output;
// the JPEG controller must discard its current output and reset this bridge
// and encoder together before selecting another frame.
module jpeg_gray4_axis_cdc #(
    parameter integer IMG_WIDTH = 1920,
    parameter integer IMG_HEIGHT = 1080,
    parameter integer FIFO_ADDR_WIDTH = 9
) (
    input  wire        cam_clk,
    input  wire        enc_clk,
    input  wire        rst_n,
    input  wire [63:0] s_yuyv4,
    input  wire        s_valid,
    input  wire        s_sof,
    input  wire        s_eol,
    input  wire        s_take_frame,
    output reg         s_fault,
    output reg  [3:0]  s_fault_cause,
    output reg  [9:0]  s_fault_line,
    output reg  [9:0]  s_fault_beat,
    output reg  [31:0] s_selected_frames,
    output reg  [31:0] s_completed_frames,
    output wire [15:0] m_tdata,
    output wire        m_tvalid,
    input  wire        m_tready,
    output wire        m_tuser,
    output wire        m_tlast,
    output wire        m_fault
);
    localparam integer BEATS_PER_LINE = IMG_WIDTH / 4;
    localparam integer XW = $clog2(BEATS_PER_LINE + 1);
    localparam integer YW = $clog2(IMG_HEIGHT + 1);

    initial begin
        if (IMG_WIDTH < 4 || IMG_WIDTH % 4 != 0 || IMG_HEIGHT < 1)
            $error("jpeg_gray4_axis_cdc: invalid frame dimensions");
    end

    reg frame_active;
    reg [XW-1:0] beat_x;
    reg [YW-1:0] line_y;
    wire first = s_valid && s_sof;
    wire taking = s_valid && (frame_active || (first && s_take_frame));
    wire [XW-1:0] cur_x = first ? {XW{1'b0}} : beat_x;
    wire [YW-1:0] cur_y = first ? {YW{1'b0}} : line_y;
    wire malformed = taking &&
        ((first && frame_active) ||
         (s_eol != (cur_x == BEATS_PER_LINE-1)) ||
         (cur_y >= IMG_HEIGHT));
    wire final_beat = taking && s_eol && (cur_y == IMG_HEIGHT-1);

    wire fifo_full, fifo_empty;
    wire [17:0] fifo_out;
    wire fifo_write = taking && !malformed && !fifo_full && !s_fault;
    wire fifo_overflow = taking && fifo_full;
    // Each 18-bit lane is {SOF,EOL,{chroma,Y}}; pixel zero is in low bits.
    wire [71:0] fifo_in = {
        {1'b0,s_eol,s_yuyv4[63:48]},
        {1'b0,1'b0,s_yuyv4[47:32]},
        {1'b0,1'b0,s_yuyv4[31:16]},
        {s_sof,1'b0,s_yuyv4[15:0]}
    };

    always @(posedge cam_clk or negedge rst_n) begin
        if (!rst_n) begin
            s_fault <= 1'b0;
            s_fault_cause <= 4'b0;
            s_fault_line <= 10'd0;
            s_fault_beat <= 10'd0;
            frame_active <= 1'b0;
            beat_x <= 0;
            line_y <= 0;
            s_selected_frames <= 0;
            s_completed_frames <= 0;
        end else if (!s_fault) begin
            if (malformed || fifo_overflow) begin
                s_fault <= 1'b1;
                // Latch the first fault: bit0=unexpected SOF, bit1=bad EOL,
                // bit2=too many lines, bit3=input FIFO full.
                s_fault_cause <= {fifo_overflow,
                    taking && (cur_y >= IMG_HEIGHT),
                    taking && (s_eol != (cur_x == BEATS_PER_LINE-1)),
                    taking && first && frame_active};
                s_fault_line <= line_y;
                s_fault_beat <= beat_x;
                frame_active <= 1'b0;
            end else if (first) begin
                frame_active <= s_take_frame;
                beat_x <= 0;
                line_y <= 0;
                if (s_take_frame)
                    s_selected_frames <= s_selected_frames + 1'b1;
            end
            if (fifo_write) begin
                if (s_eol) begin
                    beat_x <= 0;
                    line_y <= cur_y + 1'b1;
                end else begin
                    beat_x <= cur_x + 1'b1;
                    line_y <= cur_y;
                end
                if (final_beat) begin
                    frame_active <= 1'b0;
                    s_completed_frames <= s_completed_frames + 1'b1;
                end
            end
        end
    end

    (* ASYNC_REG = "TRUE" *) reg [1:0] fault_sync;
    // The project's show-ahead RAM is synchronous. The FIFO's empty flag can
    // deassert one read clock before dout contains its first word.
    reg read_primed;
    always @(posedge enc_clk or negedge rst_n) begin
        if (!rst_n) begin
            fault_sync <= 2'b00;
            read_primed <= 1'b0;
        end else begin
            fault_sync <= {fault_sync[0],s_fault};
            read_primed <= !fifo_empty;
        end
    end
    assign m_fault = fault_sync[1];
    // Elastic output stage isolates the FIFO occupancy/empty arithmetic from
    // the encoder's write-address controls, while sustaining one pixel/clock.
    reg [17:0] output_word;
    reg output_valid;
    wire output_ready = !output_valid || m_tready;
    wire fifo_read = !fifo_empty && read_primed && !m_fault && output_ready;
    always @(posedge enc_clk or negedge rst_n) begin
        if (!rst_n) begin
            output_word <= 18'd0;
            output_valid <= 1'b0;
        end else if (m_fault) begin
            output_valid <= 1'b0;
        end else if (output_ready) begin
            output_valid <= fifo_read;
            if (fifo_read) output_word <= fifo_out;
        end
    end
    assign m_tdata = output_word[15:0];
    assign m_tlast = output_word[16];
    assign m_tuser = output_word[17];
    assign m_tvalid = output_valid && !m_fault;

    demo_async_sfifo #(
        .DATA_WIDTH_W(72), .DATA_WIDTH_R(18),
        .ADDR_WIDTH_W(FIFO_ADDR_WIDTH),
        .ADDR_WIDTH_R(FIFO_ADDR_WIDTH+2),
        .AL_FULL_NUM(16), .AL_EMPTY_NUM(4),
        .SHOW_AHEAD_EN(1'b1), .OUTREG_EN("NOREG")
    ) u_fifo (
        .rst(~rst_n), .clkw(cam_clk), .clkr(enc_clk),
        .we(fifo_write), .di(fifo_in),
        .re(fifo_read), .dout(fifo_out), .valid(),
        .full_flag(fifo_full), .empty_flag(fifo_empty),
        .afull(), .aempty(), .wrusedw(), .rdusedw()
    );
endmodule
