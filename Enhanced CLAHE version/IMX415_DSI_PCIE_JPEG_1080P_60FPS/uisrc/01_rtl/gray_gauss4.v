`timescale 1ns/1ps

// Four 8-bit pixels per beat, low byte first. A complete 3x3 Gaussian is
// produced for every input pixel. Border samples are replicated. The output
// is delayed by one image row; the final row is generated during vertical
// blanking from the stored last row. No input backpressure is introduced.
module gray_gauss4 #(
    parameter integer WIDTH = 1920,
    parameter integer HEIGHT = 1080
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] s_gray,
    input  wire        s_valid,
    input  wire        s_sof,
    input  wire        s_eol,
    output reg  [31:0] m_center,
    output reg  [31:0] m_gauss,
    output reg         m_valid,
    output reg         m_sof,
    output reg         m_eol,
    output reg         m_overrun
);
    localparam integer BEATS = WIDTH / 4;
    localparam integer XB = $clog2(BEATS);
    localparam integer YB = $clog2(HEIGHT+1);

    reg [31:0] line1 [0:BEATS-1];
    reg [31:0] line2 [0:BEATS-1];
    reg [XB-1:0] input_x, pad_x;
    reg [YB-1:0] input_y;
    reg pad_active;

    // BRAM read outputs and the matching input beat.
    reg [31:0] q_top, q_mid, q_bot;
    reg [XB-1:0] q_x;
    reg [YB-1:0] q_y;
    reg q_valid;
    wire [XB-1:0] current_x = s_sof ? {XB{1'b0}} : input_x;
    wire [YB-1:0] current_y = s_sof ? {YB{1'b0}} : input_y;

    always @(posedge clk) begin
        if (pad_active) begin
            q_top <= line2[pad_x];
            q_mid <= line1[pad_x];
            q_bot <= line1[pad_x];
        end else if (s_valid) begin
            q_top <= line2[current_x];
            q_mid <= line1[current_x];
            q_bot <= s_gray;
            line2[current_x] <= line1[current_x];
            line1[current_x] <= s_gray;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_x <= 0;
            input_y <= 0;
            pad_x <= 0;
            pad_active <= 0;
            q_x <= 0;
            q_y <= 0;
            q_valid <= 0;
            m_overrun <= 0;
        end else begin
            q_valid <= pad_active || s_valid;
            if (pad_active) begin
                q_x <= pad_x;
                q_y <= HEIGHT;
                if (s_valid) m_overrun <= 1;
                if (pad_x == BEATS-1) begin
                    pad_x <= 0;
                    pad_active <= 0;
                end else pad_x <= pad_x + 1'b1;
            end else if (s_valid) begin
                q_x <= current_x;
                q_y <= current_y;
                input_y <= current_y;
                if (s_eol) begin
                    input_x <= 0;
                    input_y <= current_y + 1'b1;
                    if (current_y == HEIGHT-1) begin
                        pad_active <= 1;
                        pad_x <= 0;
                    end
                end else input_x <= current_x + 1'b1;
            end
            if (s_sof && !s_valid) m_overrun <= 1;
        end
    end

    reg [31:0] prev_top, prev_mid, prev_bot;
    reg [7:0] left_top, left_mid, left_bot;
    reg [XB-1:0] prev_x;
    reg [YB-1:0] prev_y;
    reg prev_valid;
    wire [31:0] now_top = (q_y == 1) ? q_mid : q_top;
    wire same_row = q_valid && prev_valid && q_y == prev_y &&
                    q_x == prev_x + 1'b1;
    wire emit = prev_valid && prev_y >= 1 && prev_y <= HEIGHT &&
                (q_valid || (prev_y == HEIGHT && prev_x == BEATS-1));

    genvar lane;
    wire [31:0] filtered;
    generate for (lane=0; lane<4; lane=lane+1) begin : g_filter
        wire [7:0] tl = (lane==0) ? ((prev_x==0) ? prev_top[7:0] : left_top)
                                  : prev_top[(lane-1)*8 +: 8];
        wire [7:0] ml = (lane==0) ? ((prev_x==0) ? prev_mid[7:0] : left_mid)
                                  : prev_mid[(lane-1)*8 +: 8];
        wire [7:0] bl = (lane==0) ? ((prev_x==0) ? prev_bot[7:0] : left_bot)
                                  : prev_bot[(lane-1)*8 +: 8];
        wire [7:0] tc = prev_top[lane*8 +: 8];
        wire [7:0] mc = prev_mid[lane*8 +: 8];
        wire [7:0] bc = prev_bot[lane*8 +: 8];
        wire [7:0] tr = (lane==3) ? (same_row ? now_top[7:0] : prev_top[31:24])
                                  : prev_top[(lane+1)*8 +: 8];
        wire [7:0] mr = (lane==3) ? (same_row ? q_mid[7:0] : prev_mid[31:24])
                                  : prev_mid[(lane+1)*8 +: 8];
        wire [7:0] br = (lane==3) ? (same_row ? q_bot[7:0] : prev_bot[31:24])
                                  : prev_bot[(lane+1)*8 +: 8];
        wire [9:0] top_sum = {2'b0,tl} + {1'b0,tc,1'b0} + {2'b0,tr};
        wire [9:0] mid_sum = {2'b0,ml} + {1'b0,mc,1'b0} + {2'b0,mr};
        wire [9:0] bot_sum = {2'b0,bl} + {1'b0,bc,1'b0} + {2'b0,br};
        wire [11:0] total = {2'b0,top_sum} + {1'b0,mid_sum,1'b0} +
                            {2'b0,bot_sum} + 12'd8;
        assign filtered[lane*8 +: 8] = total[11:4];
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_top <= 0; prev_mid <= 0; prev_bot <= 0;
            left_top <= 0; left_mid <= 0; left_bot <= 0;
            prev_x <= 0; prev_y <= 0; prev_valid <= 0;
            m_center <= 0; m_gauss <= 0;
            m_valid <= 0; m_sof <= 0; m_eol <= 0;
        end else begin
            m_valid <= emit;
            m_sof <= emit && prev_y == 1 && prev_x == 0;
            m_eol <= emit && prev_x == BEATS-1;
            if (emit) begin
                m_center <= prev_mid;
                m_gauss <= filtered;
            end
            if (q_valid) begin
                if (prev_valid) begin
                    left_top <= prev_top[31:24];
                    left_mid <= prev_mid[31:24];
                    left_bot <= prev_bot[31:24];
                end
                prev_top <= now_top;
                prev_mid <= q_mid;
                prev_bot <= q_bot;
                prev_x <= q_x;
                prev_y <= q_y;
                prev_valid <= 1;
            end else if (emit) prev_valid <= 0;
        end
    end
endmodule
