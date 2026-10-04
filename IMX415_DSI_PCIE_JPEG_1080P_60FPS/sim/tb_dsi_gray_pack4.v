`timescale 1ns/1ps
module tb_dsi_gray_pack4;
    reg [127:0] input_pixels;
    wire [127:0] output_pixels;
    dsi_gray_pack4 dut (.I_tdata(input_pixels), .O_tdata(output_pixels));
    initial begin
        input_pixels = {32'h00ffffff,32'h000000ff,
                        32'h0000ff00,32'h00ff0000};
        #1;
        if(output_pixels !== {32'h00ffffff,32'h001d1d1d,
                              32'h00959595,32'h004d4d4d}) begin
            $display("FAIL grayscale packing: %h", output_pixels);
            $fatal;
        end
        input_pixels = {4{32'h00000000}};
        #1;
        if(output_pixels !== 128'd0) begin
            $display("FAIL black pixel: %h", output_pixels);
            $fatal;
        end
        $display("PASS DSI gray pack4: RGB channel equality and lane order");
        $finish;
    end
endmodule
