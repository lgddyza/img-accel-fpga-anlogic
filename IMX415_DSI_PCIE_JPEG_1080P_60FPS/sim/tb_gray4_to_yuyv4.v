`timescale 1ns/1ps

module tb_gray4_to_yuyv4;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [127:0] s_rgb = 0;
    reg s_valid = 0, s_sof = 0, s_eol = 0;
    wire [63:0] m_yuyv;
    wire m_valid, m_sof, m_eol;

    gray4_to_yuyv4 dut (
        .clk(clk), .rst_n(rst_n), .s_rgb(s_rgb),
        .s_valid(s_valid), .s_sof(s_sof), .s_eol(s_eol),
        .m_yuyv(m_yuyv), .m_valid(m_valid),
        .m_sof(m_sof), .m_eol(m_eol)
    );

    initial begin
        @(negedge clk);
        rst_n = 1;
        s_rgb = {32'h00404040, 32'h00303030,
                 32'h00202020, 32'h00101010};
        s_valid = 1; s_sof = 1; s_eol = 0;
        @(posedge clk); #1;
        if (m_yuyv !== 64'h8040_8030_8020_8010 ||
            {m_valid,m_sof,m_eol} !== 3'b110)
            $fatal(1, "first four pixels or SOF incorrect");

        @(negedge clk);
        s_rgb = {32'h00808080, 32'h00707070,
                 32'h00606060, 32'h00505050};
        s_valid = 1; s_sof = 0; s_eol = 1;
        @(posedge clk); #1;
        if (m_yuyv !== 64'h8080_8070_8060_8050 ||
            {m_valid,m_sof,m_eol} !== 3'b101)
            $fatal(1, "second four pixels or EOL incorrect");

        @(negedge clk);
        s_valid = 0; s_sof = 1; s_eol = 1;
        @(posedge clk); #1;
        if ({m_valid,m_sof,m_eol} !== 3'b000)
            $fatal(1, "invalid cycle emitted a marker");
        $display("GRAY4_TO_YUYV4_PASS");
        $finish;
    end
endmodule
