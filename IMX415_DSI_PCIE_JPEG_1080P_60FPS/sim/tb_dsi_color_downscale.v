`timescale 1ns/1ps
module tb_dsi_color_downscale;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [127:0] input_data = 0;
    reg input_valid = 0;
    reg input_user = 0;
    reg input_last = 0;
    wire [127:0] output_data;
    wire output_valid, output_user, output_last;

    dsi_color_downscale dut (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_tdata(input_data), .I_tvalid(input_valid),
        .I_tuser(input_user), .I_tlast(input_last),
        .O_tdata(output_data), .O_tvalid(output_valid),
        .O_tuser(output_user), .O_tlast(output_last)
    );

    function [31:0] color;
        input integer x, y;
        begin
            color = {8'd0, x[7:0], y[7:0], x[7:0] ^ y[7:0]};
        end
    endfunction

    integer output_x = 0;
    integer output_y = 0;
    integer word_count = 0;
    integer user_count = 0;
    integer pixel;
    integer source_x;
    integer source_y;
    always @(posedge clk) begin
        #1;
        if (rst_n && output_valid) begin
            if (output_user !== (word_count == 0))
                $fatal(1, "frame start at wrong word %0d", word_count);
            if (output_user)
                user_count = user_count + 1;
            if (output_last !== (output_x == 255))
                $fatal(1, "line end at output (%0d,%0d)", output_x, output_y);
            for (pixel = 0; pixel < 4; pixel = pixel + 1) begin
                source_x = ((2 * (output_x * 4 + pixel) + 1) * 15) / 16;
                source_y = ((2 * output_y + 1) * 15) / 16;
                if (output_data[pixel*32 +: 32] !== color(source_x, source_y))
                    $fatal(1, "wrong RGB pixel at (%0d,%0d): got %h, want %h",
                           output_x * 4 + pixel, output_y,
                           output_data[pixel*32 +: 32], color(source_x, source_y));
            end
            word_count = word_count + 1;
            if (output_last) begin
                output_x = 0;
                output_y = output_y + 1;
            end else
                output_x = output_x + 1;
        end
    end

    integer y, beat, lane;
    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        for (y = 0; y < 1080; y = y + 1) begin
            for (beat = 0; beat < 480; beat = beat + 1) begin
                @(negedge clk);
                input_valid = 1;
                input_user = (y == 0 && beat == 0);
                input_last = (beat == 479);
                for (lane = 0; lane < 4; lane = lane + 1)
                    input_data[lane*32 +: 32] = color(beat*4 + lane, y);
            end
        end
        @(negedge clk);
        input_valid = 0;
        input_user = 0;
        input_last = 0;
        repeat (8) @(negedge clk);
        if (word_count != 256*576 || output_y != 576 || output_x != 0 ||
            user_count != 1)
            $fatal(1, "shape mismatch: %0d words, %0d rows, %0d x, %0d SOF",
                   word_count, output_y, output_x, user_count);
        $display("PASS DSI full-frame color: 1920x1080 -> 1024x576, 256 words/line");
        $finish;
    end
endmodule
