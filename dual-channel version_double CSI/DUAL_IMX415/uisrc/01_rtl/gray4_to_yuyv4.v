`timescale 1ns/1ps

// One clock of format conversion for the independent JPEG capture branch.
// s_rgb is the existing gray_preprocess4 output: four {0,Y,Y,Y} pixels,
// pixel 0 in bits [31:0].  Each output word is {neutral chroma,Y}; pixel 0
// is in bits [15:0].  This matches mjpegZero's YUYV AXI pixel ordering.
// This module does not rate-match four pixels/clock to the encoder's
// one-pixel/clock input. jpeg_gray4_axis_cdc implements that next stage.
module gray4_to_yuyv4 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [127:0] s_rgb,
    input  wire         s_valid,
    input  wire         s_sof,
    input  wire         s_eol,
    output reg  [63:0]  m_yuyv,
    output reg          m_valid,
    output reg          m_sof,
    output reg          m_eol
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_yuyv  <= 64'd0;
            m_valid <= 1'b0;
            m_sof   <= 1'b0;
            m_eol   <= 1'b0;
        end else begin
            m_yuyv <= {8'h80, s_rgb[103:96],
                       8'h80, s_rgb[71:64],
                       8'h80, s_rgb[39:32],
                       8'h80, s_rgb[7:0]};
            m_valid <= s_valid;
            m_sof   <= s_valid && s_sof;
            m_eol   <= s_valid && s_eol;
        end
    end
endmodule
