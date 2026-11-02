module dsi_gamma_resource_top (
    input clk, rst_n, valid,
    input [7:0] data,
    output [7:0] result,
    output result_valid
);
    wire [95:0] rgb;
    ui_dsi_gamma22 dut(.I_clk(clk), .I_rst_n(rst_n), .I_tdata({12{data}}),
        .I_tvalid(valid), .I_tuser(1'b0), .I_tlast(1'b0), .I_tready(),
        .O_tdata(rgb), .O_tvalid(result_valid), .O_tuser(), .O_tlast(), .O_tready(1'b1));
    assign result=rgb[7:0];
endmodule
