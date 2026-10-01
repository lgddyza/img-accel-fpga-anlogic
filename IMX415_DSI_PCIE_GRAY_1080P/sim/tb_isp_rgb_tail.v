`timescale 1ns/1ps
module tb_isp_rgb_tail;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg valid = 0, user = 0, last = 0;
    reg [95:0] rgb = 0;
    wire [95:0] adjusted;
    wire [127:0] rgb32;
    wire out_valid, out_user, out_last;

    ui_Brightness_adj #(.BRIGHTNESS_ADD(5), .BRIGHTNESS_MINUS(0)) brightness (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tlast(last), .I_tuser(user), .I_tdata(rgb), .I_tvalid(valid),
        .I_tready(), .O_tlast(out_last), .O_tuser(out_user),
        .O_tdata(adjusted), .O_tvalid(out_valid), .O_tready(1'b1)
    );
    ui_data96_128 pack (.I_tdata(adjusted), .O_tdata(rgb32));

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        valid = 1;
        user = 1;
        last = 1;
        rgb = {24'h0a283c, 24'h5a1e0a, 24'h146450, 24'h782814};
        @(posedge clk); #1;
        if (!out_valid || !out_user || !out_last)
            $fatal(1, "RGB stream control lost");
        if (rgb32 !== {32'h000f2d41, 32'h005f230f,
                        32'h00196955, 32'h007d2d19})
            $fatal(1, "RGB channels changed or collapsed: %h", rgb32);
        $display("PASS ISP RGB tail preserves distinct colour channels");
        $finish;
    end
endmodule
