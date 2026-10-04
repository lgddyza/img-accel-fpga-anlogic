`timescale 1ns/1ps

// 1920x1080, four RGB888 pixels per camera clock. All three stages remain
// active in hardware. mode[0] bypasses Gaussian; mode[1] bypasses HE.
// HE always learns the selected input stream and publishes only complete LUTs.
module gray_preprocess4 #(
    parameter integer WIDTH = 1920,
    parameter integer HEIGHT = 1080
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire [127:0] s_rgb,
    input  wire         s_valid,
    input  wire         s_sof,
    input  wire         s_eol,
    input  wire [1:0]   mode,
    output wire [127:0] m_rgb_gray,
    output wire         m_valid,
    output wire         m_sof,
    output wire         m_eol,
    output wire         gauss_overrun,
    output wire [31:0] hist_frames,
    output wire [31:0] hist_errors
);
    function [7:0] luma;
        input [31:0] rgb;
        reg [15:0] sum_y;
        begin
            sum_y = 16'd77*rgb[23:16] + 16'd150*rgb[15:8] +
                    16'd29*rgb[7:0] + 16'd128;
            luma = sum_y[15:8];
        end
    endfunction
    reg [31:0] gray4;
    reg gray_valid,gray_sof,gray_eol;
    reg [1:0] frame_mode;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gray4<=0; gray_valid<=0; gray_sof<=0; gray_eol<=0;
            frame_mode<=2'b11;
        end else begin
            gray4 <= {luma(s_rgb[127:96]),luma(s_rgb[95:64]),
                      luma(s_rgb[63:32]),luma(s_rgb[31:0])};
            gray_valid<=s_valid;
            gray_sof<=s_valid && s_sof;
            gray_eol<=s_valid && s_eol;
            if (s_valid && s_sof) frame_mode<=mode;
        end
    end

    wire [31:0] center4,gauss4;
    wire gauss_valid,gauss_sof,gauss_eol;
    gray_gauss4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_gauss (
        .clk(clk),.rst_n(rst_n),.s_gray(gray4),
        .s_valid(gray_valid),.s_sof(gray_sof),.s_eol(gray_eol),
        .m_center(center4),.m_gauss(gauss4),
        .m_valid(gauss_valid),.m_sof(gauss_sof),.m_eol(gauss_eol),
        .m_overrun(gauss_overrun)
    );
    wire [31:0] selected4 = frame_mode[0] ? gauss4 : center4;
    wire [31:0] equalized4;
    wire lut_active;
    gray_hist4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_hist (
        .clk(clk),.rst_n(rst_n),.s_gray(selected4),
        .s_valid(gauss_valid),.s_sof(gauss_sof),.s_eol(gauss_eol),
        .enable(frame_mode[1]),
        .m_gray(equalized4),.m_valid(m_valid),
        .m_sof(m_sof),.m_eol(m_eol),
        .lut_active(lut_active),.hist_frames(hist_frames),
        .hist_errors(hist_errors)
    );
    genvar lane;
    generate for (lane=0;lane<4;lane=lane+1) begin : g_rgb
        wire [7:0] y = equalized4[lane*8 +: 8];
        assign m_rgb_gray[lane*32 +: 32] = {8'd0,y,y,y};
    end endgenerate
endmodule
