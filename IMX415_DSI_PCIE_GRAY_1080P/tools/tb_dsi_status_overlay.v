`timescale 1ns/1ps
module tb_dsi_status_overlay;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;
    reg vsync = 0;
    reg hsync = 0;
    reg de = 0;
    reg [23:0] data = 24'h63859a;
    wire out_vsync, out_hsync, out_de;
    wire image_active;
    wire [23:0] out_data;
    dsi_status_overlay #(.PIXEL_CLOCK_HZ(1000000)) dut (
        .I_clk(clk), .I_rst(rst), .I_vsync(vsync), .I_hsync(hsync),
        .I_de(de), .I_data(data), .O_vsync(out_vsync),
        .O_hsync(out_hsync), .O_de(out_de), .O_data(out_data),
        .O_image_active(image_active)
    );
    reg fps_rst = 1;
    reg fps_vsync = 0;
    reg fps_done = 0;
    dsi_status_overlay #(.PIXEL_CLOCK_HZ(100)) fps_dut (
        .I_clk(clk), .I_rst(fps_rst), .I_vsync(fps_vsync),
        .I_hsync(1'b0), .I_de(1'b0), .I_data(24'd0),
        .O_vsync(), .O_hsync(), .O_de(), .O_data(), .O_image_active()
    );

    task step;
        begin @(posedge clk); #1; end
    endtask
    task active_line;
        input integer row;
        integer x;
        begin
            @(negedge clk); de = 1;
            for (x = 0; x < 220; x = x + 1) begin
                #1;
                if (row == 16 && x == 10 && out_data !== 24'h102840)
                    $fatal(1, "panel background missing");
                if (row == 16 && x == 16 && out_data !== 24'hffffff)
                    $fatal(1, "letter D missing");
                if (row == 16 && x == 26 && out_data !== 24'h102840)
                    $fatal(1, "character spacing wrong");
                if (row == 16 && x == 216 && out_data !== data)
                    $fatal(1, "camera pixel changed outside panel");
                if ((row < 12 || row >= 588) && x == 216 && out_data !== 24'd0)
                    $fatal(1, "black letterbox row missing at %0d", row);
                if (x == 216 && image_active !== (row >= 12 && row < 588))
                    $fatal(1, "DDR read gate wrong at row %0d", row);
                step();
            end
            @(negedge clk); de = 0; step();
        end
    endtask

    integer y;
    integer n;
    initial begin
        repeat (3) step();
        @(negedge clk); fps_rst = 0;
        for (n = 0; n < 100; n = n + 1) begin
            fps_vsync = (n % 20 == 0);
            step();
            @(negedge clk);
        end
        if (fps_dut.fps_value !== 7'd5)
            $fatal(1, "FPS count wrong: %0d", fps_dut.fps_value);
        fps_done = 1;
    end
    initial begin
        repeat (3) step();
        @(negedge clk); rst = 0; vsync = 1; step();
        @(negedge clk); vsync = 0; step();
        if (out_vsync !== 0 || out_hsync !== hsync || out_de !== de)
            $fatal(1, "timing passthrough failed");
        for (y = 0; y <= 588; y = y + 1)
            active_line(y);
        if (dut.pixel_y !== 589)
            $fatal(1, "line count failed: %0d", dut.pixel_y);
        wait (fps_done);
        $display("PASS DSI pixels, text, passthrough, line tracking, and FPS count");
        $finish;
    end
endmodule
