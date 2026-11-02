`timescale 1ns/1ps

// Independent JPEG tap after gray4_to_yuyv4. The live display path has no
// backpressure, so the caller selects a whole frame at SOF. On a malformed
// frame or FIFO overflow this bridge latches a fault and stops the AXI output;
// the JPEG controller must discard its current output and reset this bridge
// and encoder together before selecting another frame.
module jpeg_gray4_axis_cdc #(
    parameter integer IMG_WIDTH = 1920,
    parameter integer IMG_HEIGHT = 1080,
    parameter integer FIFO_ADDR_WIDTH = 9,
    parameter integer COMPACT_MONO = 0
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
    output wire        m_fault,
    output wire [FIFO_ADDR_WIDTH:0] s_queued_groups
);
    localparam integer BEATS_PER_LINE = IMG_WIDTH / 4;
    localparam integer XW = $clog2(BEATS_PER_LINE + 1);
    localparam integer YW = $clog2(IMG_HEIGHT + 1);

    initial begin
        if (IMG_WIDTH < 4 || IMG_WIDTH % 4 != 0 || IMG_HEIGHT < 1)
            $error("jpeg_gray4_axis_cdc: invalid frame dimensions");
    end

    wire cam_reset_n,enc_reset_n;
    v2_reset_sync u_cam_reset(cam_clk,rst_n,cam_reset_n);
    v2_reset_sync u_enc_reset(enc_clk,rst_n,enc_reset_n);
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

    wire fifo_full;
    wire fifo_write = taking && !malformed && !fifo_full && !s_fault;
    wire fifo_overflow = taking && fifo_full;
    // Each 18-bit lane is {SOF,EOL,{chroma,Y}}; pixel zero is in low bits.
    wire [71:0] fifo_in = {
        {1'b0,s_eol,s_yuyv4[63:48]},
        {1'b0,1'b0,s_yuyv4[47:32]},
        {1'b0,1'b0,s_yuyv4[31:16]},
        {s_sof,1'b0,s_yuyv4[15:0]}
    };

    always @(posedge cam_clk or negedge cam_reset_n) begin
        if (!cam_reset_n) begin
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
    always @(posedge enc_clk or negedge enc_reset_n)
        if(!enc_reset_n) fault_sync<=0;else fault_sync<={fault_sync[0],s_fault};
    assign m_fault=fault_sync[1];
    // Equal-width ERAM FIFO, then a 4:1 serializer. This
    // removes the mixed-width FIFO read-address arithmetic from the 200MHz
    // RAM address path. An elastic register isolates the ERAM output from
    // the encoder control decode. Replace its word on the fourth accepted
    // pixel, allowing one pixel per clock without a bubble between groups.
    localparam integer GROUP_BITS=COMPACT_MONO ? 34 : 72;
    wire [GROUP_BITS-1:0] pixel_group;
    wire [GROUP_BITS-1:0] stored_group;
    generate if(COMPACT_MONO) begin:g_mono_pack
        assign stored_group={s_sof,s_eol,s_yuyv4[55:48],s_yuyv4[39:32],
                             s_yuyv4[23:16],s_yuyv4[7:0]};
    end else begin:g_color_pack
        assign stored_group=fifo_in;
    end endgenerate
    wire group_valid,group_ready,write_ready;
    reg [GROUP_BITS-1:0] held_group;
    reg held_valid;
    reg [1:0] pixel_index;
    always @(posedge enc_clk or negedge enc_reset_n) begin
        if(!enc_reset_n) begin pixel_index<=0;held_valid<=0;end
        else begin
            if(m_tvalid && m_tready) pixel_index<=pixel_index+1'b1;
            if(group_ready) held_valid<=group_valid;
        end
    end
    always @(posedge enc_clk)
        if(group_ready && group_valid) held_group<=pixel_group;
    generate if(COMPACT_MONO) begin:g_mono_unpack
        assign m_tdata={8'd128,held_group[pixel_index*8+:8]};
        assign m_tlast=held_group[32] && pixel_index==3;
        assign m_tuser=held_group[33] && pixel_index==0;
    end else begin:g_color_unpack
        wire [17:0] pixel=held_group[pixel_index*18+:18];
        assign m_tdata=pixel[15:0];assign m_tlast=pixel[16];assign m_tuser=pixel[17];
    end endgenerate
    assign m_tvalid=enc_reset_n && held_valid && !m_fault;
    assign group_ready=enc_reset_n && !m_fault &&
        (!held_valid || (m_tready && pixel_index==3));
    assign fifo_full=!write_ready;
    // One group per two clocks exceeds the serializer demand (one per four).
    // Isolate downstream ready from the RAM read enable and pointer control.
    v2_async_fifo #(.WIDTH(GROUP_BITS),.ADDR(FIFO_ADDR_WIDTH),.READ_INCREMENT_LOOKAHEAD(1),.READ_REFILL_ON_POP(0),.WRITE_INCREMENT_LOOKAHEAD(1)) u_fifo(
        .rst_n(rst_n),.wclk(cam_clk),.s_data(stored_group),.s_valid(fifo_write),.s_ready(write_ready),
        .rclk(enc_clk),.m_data(pixel_group),.m_valid(group_valid),.m_ready(group_ready),
        .m_level(),.s_level(s_queued_groups));
endmodule
