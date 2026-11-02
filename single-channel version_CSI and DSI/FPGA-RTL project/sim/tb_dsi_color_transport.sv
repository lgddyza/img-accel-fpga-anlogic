`timescale 1ns/1ps
module tb_dsi_color_transport;
    reg clk = 0;
    always #5 clk = !clk;
    reg reset = 1;
    reg we = 0, re = 0;
    reg [127:0] in_word = 0;
    wire [31:0] pixel;
    wire empty;
    wire [23:0] overlay_data;
    wire pack_de, pack_vsync, pack_hsync;
    wire [31:0] pack_data;
    wire packet_en, packet_last;
    wire [31:0] packet_data;
    wire pixel_de = re && !empty;

    demo_async_sfifo #(.DATA_WIDTH_W(128), .DATA_WIDTH_R(32),
        .ADDR_WIDTH_W(9), .ADDR_WIDTH_R(11), .SHOW_AHEAD_EN(1'b1))
    read_fifo(.rst(reset), .clkw(clk), .clkr(clk), .we(we),
        .di(in_word), .re(re), .dout(pixel), .empty_flag(empty),
        .full_flag(), .valid(), .afull(), .aempty(), .wrusedw(), .rdusedw());
    dsi_status_overlay overlay(.I_clk(clk), .I_rst(reset),
        .I_test_pattern(1'b0),
        .I_vsync(1'b0), .I_hsync(1'b0), .I_de(pixel_de), .I_data(pixel[23:0]),
        .O_vsync(), .O_hsync(), .O_de(), .O_data(overlay_data), .O_image_active());
    rgb_24b_to_32b #(.H_ACTIVE(1024)) pack(.I_clk(clk), .I_rst(reset),
        .I_vsync(1'b0), .I_hsync(1'b0), .I_de(pixel_de), .I_data(overlay_data),
        .O_vsync(pack_vsync), .O_hsync(pack_hsync), .O_de(pack_de), .O_data(pack_data));
    dsi_video_mode_packet #(.H_ACTIVE(1024)) packet(.I_clk(clk), .I_rst(reset),
        .I_vsync(pack_vsync), .I_hsync(pack_hsync), .I_de(pack_de), .I_data(pack_data),
        .O_hs_en(packet_en), .O_hs_data(packet_data), .O_hs_last(packet_last));

    function [23:0] expected_pixel(input integer index);
        reg [7:0] r, g, b;
        begin
            r = index % 251;
            g = (index*3+70) % 251;
            b = (index*7+130) % 251;
            expected_pixel = {r, g, b};
        end
    endfunction
    function [7:0] expected_byte(input integer index);
        reg [23:0] rgb;
        begin
            rgb = expected_pixel(index/3);
            case (index%3)
                0: expected_byte = rgb[23:16];
                1: expected_byte = rgb[15:8];
                2: expected_byte = rgb[7:0];
            endcase
        end
    endfunction

    integer fifo_pixels = 0, packed_bytes = 0, packet_bytes = 0;
    integer i, w, p;
    reg in_packet = 0;
    always @(posedge clk) if (!reset && pixel_de) begin
        if (pixel[23:0] !== expected_pixel(fifo_pixels))
            $fatal(1, "Read FIFO pixel %0d: got %06h expected %06h",
                fifo_pixels, pixel[23:0], expected_pixel(fifo_pixels));
        fifo_pixels = fifo_pixels + 1;
    end
    always @(negedge clk) if (!reset) begin
        if (pack_de) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (pack_data[i*8 +: 8] !== expected_byte(packed_bytes))
                    $fatal(1, "Pack byte %0d: got %02h expected %02h", packed_bytes,
                        pack_data[i*8 +: 8], expected_byte(packed_bytes));
                packed_bytes = packed_bytes + 1;
            end
        end
        if (packet_en) begin
            if (!in_packet) begin
                if (packet_data[23:0] !== 24'h0c003e)
                    $fatal(1, "Unexpected RGB888 packet header %08h", packet_data);
                in_packet = 1;
            end else if (!packet_last) begin
                for (i = 0; i < 4; i = i + 1) begin
                    if (packet_data[i*8 +: 8] !== expected_byte(packet_bytes))
                        $fatal(1, "DSI packet byte %0d mismatch", packet_bytes);
                    packet_bytes = packet_bytes + 1;
                end
            end
        end
    end
    initial begin
        force overlay.pixel_y = 11'd100;
        repeat (8) @(posedge clk);
        #1 reset = 0;
        repeat (8) @(posedge clk);
        for (w = 0; w < 256; w = w + 1) begin
            @(posedge clk); #1;
            we = 1;
            for (p = 0; p < 4; p = p + 1)
                in_word[p*32 +: 32] = {8'h00, expected_pixel(w*4+p)};
        end
        @(posedge clk); #1 we = 0;
        repeat (16) @(posedge clk);
        #1 re = 1;
        repeat (1024) @(posedge clk);
        #1 re = 0;
        repeat (1024) @(posedge clk);
        #1;
        if (fifo_pixels != 1024 || packed_bytes != 3072 || packet_bytes != 3072)
            $fatal(1, "Counts: pixels=%0d packed=%0d packet=%0d",
                fifo_pixels, packed_bytes, packet_bytes);
        $display("DSI_COLOR_TRANSPORT_PASS: FIFO 1024 RGB pixels, pack 3072 bytes, packet 3072 bytes exact");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "Transport timeout");
    end
endmodule
