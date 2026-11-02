`timescale 1ns/1ps

// Dynamic AWB is disabled in the design, so divider outputs are unused.
module divider(input clk, rst, start, input [31:0] denominator,
    input [47:0] numerator, output done, output [47:0] quotient,
    output [31:0] remainder);
    assign done = 1'b0;
    assign quotient = 48'd0;
    assign remainder = 32'd0;
endmodule

// RAM read latency matches the ISP IP's NOREG synchronous read ports.
module ui_ram_zhenghe(input clka, wea, input [10:0] addra,
    input [31:0] dia, input clkb, input [10:0] addrb,
    output reg [31:0] dob);
    reg [31:0] mem [0:2047];
    always @(posedge clka) if (wea) mem[addra] <= dia;
    always @(posedge clkb) dob <= mem[addrb];
endmodule

module ui_ram_demosaic(input clka, wea, input [10:0] addra,
    input [32:0] dia, input clkb, input [10:0] addrb,
    output reg [32:0] dob);
    reg [32:0] mem [0:2047];
    always @(posedge clka) if (wea) mem[addra] <= dia;
    always @(posedge clkb) dob <= mem[addrb];
endmodule

module ui_ram_awb_delay_signal(input clka, wea, input [10:0] addra,
    input [95:0] dia, input clkb, input [10:0] addrb,
    output reg [95:0] dob);
    reg [95:0] mem [0:2047];
    always @(posedge clka) if (wea) mem[addra] <= dia;
    always @(posedge clkb) dob <= mem[addrb];
endmodule

module tb_dsi_color_diagnosis;
    reg clk = 0;
    always #5 clk = !clk;
    reg rst_n = 0;
    reg [39:0] raw = 0;
    reg valid = 0, user = 0, last = 0;
    reg csi_mode = 0;
    reg csi_valid = 0, csi_start = 0;
    reg [31:0] csi_data = 0;
    wire [39:0] decoded_raw, corrected_raw;
    wire decoded_valid, decoded_start;
    wire corrected_valid, corrected_user, corrected_last, first_row_odd;
    ui_raw10_unpacket_4lane unpack(.I_clk(clk), .I_rst_n(rst_n),
        .I_csi_frame_start(csi_start), .I_csi_frame_end(1'b0),
        .I_csi_valid(csi_valid), .I_csi_data(csi_data),
        .O_raw10_frame_start(decoded_start), .O_raw10_frame_end(),
        .O_raw10_valid(decoded_valid), .O_raw10_data(decoded_raw));
    ui_image_correction correction(.I_clk(clk), .I_rst_n(rst_n),
        .I_raw_data(decoded_raw), .I_raw_valid(decoded_valid),
        .I_raw_frame_start(decoded_start), .I_raw_frame_end(1'b0),
        .O_raw_tdata(corrected_raw), .O_raw_tlast(corrected_last),
        .O_raw_tdest(), .O_raw_tvalid(corrected_valid),
        .O_raw_tuser(corrected_user), .O_raw_tready(1'b1),
        .O_raw_first_row_odd(first_row_odd));
    wire [127:0] rgb, scaled, dsi_rgb;
    wire [127:0] legacy_rgb;
    wire legacy_valid, legacy_user, legacy_last;
    wire [39:0] legacy_raw;
    wire legacy_raw_valid, legacy_raw_user, legacy_raw_last;
    integer legacy_compares = 0;
    legacy_ui_image_correction old_crop(.I_clk(clk), .I_rst_n(rst_n),
        .I_raw_data(decoded_raw), .I_raw_valid(decoded_valid),
        .I_raw_frame_start(decoded_start), .I_raw_frame_end(1'b0),
        .O_raw_tdata(legacy_raw), .O_raw_tlast(legacy_raw_last),
        .O_raw_tdest(), .O_raw_tvalid(legacy_raw_valid),
        .O_raw_tuser(legacy_raw_user), .O_raw_tready(1'b1));
    legacy_ui_isp_top old_isp(.I_clk(clk), .I_rst_n(rst_n),
        .I_tdata(csi_mode ? legacy_raw : raw),
        .I_tvalid(csi_mode ? legacy_raw_valid : valid),
        .I_tuser(csi_mode ? legacy_raw_user : user),
        .I_tlast(csi_mode ? legacy_raw_last : last),
        .I_tdest(10'd0), .O_tready(1'b1), .I_tready(),
        .O_tdata(legacy_rgb), .O_tvalid(legacy_valid),
        .O_tuser(legacy_user), .O_tlast(legacy_last));
    wire dsi_valid, dsi_user, dsi_last;
    wire rgb_valid, rgb_user, rgb_last, scale_valid;
    ui_isp_top #(.ENABLE_DSI_BRANCH(1)) isp(.I_clk(clk), .I_rst_n(rst_n),
        .I_tdata(csi_mode ? corrected_raw : raw),
        .I_tvalid(csi_mode ? corrected_valid : valid),
        .I_tuser(csi_mode ? corrected_user : user),
        .I_tlast(csi_mode ? corrected_last : last),
        .I_tdest(10'd0), .O_tready(1'b1), .I_tready(),
        .O_tdata(rgb), .O_tvalid(rgb_valid), .O_tuser(rgb_user),
        .O_tlast(rgb_last), .I_first_row_odd(csi_mode ? first_row_odd : 1'b1),
        .I_dsi_control(4'd0), .O_dsi_tdata(dsi_rgb), .O_dsi_tvalid(dsi_valid),
        .O_dsi_tuser(dsi_user), .O_dsi_tlast(dsi_last), .O_dsi_phase());
    dsi_color_downscale scale(.I_clk(clk), .I_rst_n(rst_n),
        .I_tdata(dsi_rgb), .I_tvalid(dsi_valid), .I_tuser(dsi_user),
        .I_tlast(dsi_last), .O_tdata(scaled), .O_tvalid(scale_valid),
        .O_tuser(), .O_tlast());

    integer counts [0:2];
    integer chroma [0:2];
    integer unknowns [0:2];
    integer mismatches [0:2];
    integer columns [0:2];
    integer rows [0:2];
    reg [23:0] sample [0:2];
    integer mode, frame, y, w, p, s, k;
    integer first_mode=0, end_mode=4, row_limit=20;
    integer rr, gg, bb, value, pack_index;
    reg [23:0] expected_interior;
    reg [7:0] payload [0:2439];
    reg [9:0] bayer_pixel [0:3];
    reg [127:0] stages [0:2];
    reg [2:0] stage_valid, stage_last;
    always @(negedge clk) if (rst_n) begin
        if ({legacy_raw_valid,legacy_raw_user,legacy_raw_last,legacy_raw} !==
            {corrected_valid,corrected_user,corrected_last,corrected_raw})
            $fatal(1, "Legacy crop output changed");
        if ({legacy_valid,legacy_user,legacy_last} !== {rgb_valid,rgb_user,rgb_last})
            $fatal(1, "Legacy ISP timing changed");
        if (rgb_valid) begin
            if (legacy_rgb !== rgb) $fatal(1, "Legacy ISP pixel changed");
            legacy_compares=legacy_compares+4;
        end
        if (csi_mode && frame == 1 &&
            isp.X_ui_top_demosaic.X_ui_raw_matrix_3x3_buffer.ch_valid &&
            isp.X_ui_top_demosaic.X_ui_raw_matrix_3x3_buffer.v_cnt == 6 &&
            isp.X_ui_top_demosaic.X_ui_raw_matrix_3x3_buffer.h_cnt == 100)
            $display("MATRIX mode=%0d row=%0d phase=%b prev=%h cur=%h next=%h",
                mode, isp.X_ui_top_demosaic.X_ui_raw_matrix_3x3_buffer.v_cnt,
                isp.X_ui_top_demosaic.bayer_ypos,
                isp.X_ui_top_demosaic.matrix_last_line[71:24],
                isp.X_ui_top_demosaic.matrix_cur_line[71:24],
                isp.X_ui_top_demosaic.matrix_next_line[71:24]);
        stages[0] = isp.dsi_raw_rgb;
        stages[1] = dsi_rgb;
        stages[2] = scaled;
        stage_valid = {scale_valid, dsi_valid, isp.dsi_raw_valid};
        stage_last = {scale.O_tlast, dsi_last, isp.dsi_raw_last};
        for (s = 0; s < 3; s = s + 1) begin
            if (stage_valid[s]) begin
                if (rows[s] >= 4 && columns[s] >= 8 && columns[s] < (s == 2 ? 248 : 472) &&
                    (!csi_mode || frame == 1)) begin
                    if (s == 0) expected_interior = {rr[7:0], gg[7:0], bb[7:0]};
                    else case (mode)
                        0: expected_interior = 24'hf26262;
                        1: expected_interior = 24'h62f262;
                        2: expected_interior = 24'h6262f2;
                        3: expected_interior = 24'haeaeae;
                    endcase
                    for (k = 0; k < 4; k = k + 1)
                        if (stages[s][k*32 +: 24] !== expected_interior) begin
                            if (mismatches[s] < 8) $display("PIXEL_MISMATCH stage=%0d row=%0d word=%0d lane=%0d got=%h expected=%h",
                                s, rows[s], columns[s], k, stages[s][k*32 +: 24], expected_interior);
                            mismatches[s] = mismatches[s] + 1;
                        end
                end
                if (rows[s] >= 4) begin
                    for (k = 0; k < 4; k = k + 1) begin
                        counts[s] = counts[s] + 1;
                        if (counts[s] == 1000) begin
                            $display("interior mode=%0d stage=%0d rgb=%06h", mode, s,
                                stages[s][k*32 +: 24]);
                            if (!csi_mode || frame == 1) begin
                                if (s == 0) expected_interior = {rr[7:0], gg[7:0], bb[7:0]};
                                else case (mode)
                                    0: expected_interior = 24'hf26262;
                                    1: expected_interior = 24'h62f262;
                                    2: expected_interior = 24'h6262f2;
                                    3: expected_interior = 24'haeaeae;
                                endcase
                                if (stages[s][k*32 +: 24] !== expected_interior)
                                    $fatal(1, "Interior stage %0d: got %06h expected %06h", s,
                                        stages[s][k*32 +: 24], expected_interior);
                            end
                        end
                        if ((^stages[s][k*32 +: 24]) === 1'bx)
                            unknowns[s] = unknowns[s] + 1;
                        else begin
                            if (stages[s][k*32+16 +: 8] != stages[s][k*32+8 +: 8] ||
                                stages[s][k*32+8 +: 8] != stages[s][k*32 +: 8])
                                chroma[s] = chroma[s] + 1;
                            sample[s] = stages[s][k*32 +: 24];
                        end
                    end
                end
                if (stage_last[s]) begin rows[s] = rows[s] + 1; columns[s] = 0; end
                else columns[s] = columns[s] + 1;
            end
        end
    end

    initial begin
        csi_mode = $test$plusargs("CSI");
        if ($test$plusargs("FULL")) begin
            first_mode=2; end_mode=3; row_limit=csi_mode ? 1097 : 1080;
        end
        for (mode = first_mode; mode < end_mode; mode = mode + 1) begin
            @(posedge clk); #1;
            rst_n = 0;
            valid = 0; user = 0; last = 0;
            csi_valid = 0; csi_start = 0;
            for (p = 0; p < 3; p = p + 1) begin
                counts[p] = 0; chroma[p] = 0; unknowns[p] = 0;
                rows[p] = 0; sample[p] = 0;
                mismatches[p] = 0; columns[p] = 0;
            end
            repeat (8) @(posedge clk);
            #1 rst_n = 1;
            rr = mode == 0 ? 200 : 30;
            gg = mode == 1 ? 200 : 30;
            bb = mode == 2 ? 200 : 30;
            if (mode == 3) begin rr = 100; gg = 100; bb = 100; end
            // The original row compactor learns CSI line length for the next frame.
            for (frame = 0; frame < (csi_mode ? 2 : 1); frame = frame + 1) begin
            if (frame != 0) begin
                for (p = 0; p < 3; p = p + 1) begin
                    counts[p] = 0; chroma[p] = 0; unknowns[p] = 0;
                    rows[p] = 0; sample[p] = 0;
                    mismatches[p] = 0; columns[p] = 0;
                end
            end
            if (csi_mode) begin
                // Change only the phase of the free-running idle counter at FS.
                // No DUT signal is forced. This represents a longer vertical blank.
                if ($test$plusargs("FS_WRAP") && frame == 1)
                    while (correction.cnt != 17'd5) begin @(posedge clk); #1; end
                @(posedge clk); #1 csi_start = 1;
                @(posedge clk); #1 csi_start = 0;
                repeat (32) @(posedge clk);
            end
            for (y = 0; y < row_limit; y = y + 1) begin
                if (csi_mode) begin
                    for (w = 0; w < 488; w = w + 1) begin
                        for (p = 0; p < 4; p = p + 1) begin
                            // IMX415 sensor GBRG; the steady-state crop drops its first row.
                            value = y % 2 == 0 ? (p % 2 == 0 ? gg : bb) :
                                                             (p % 2 == 0 ? rr : gg);
                            bayer_pixel[p] = value*4 + 50;
                            payload[w*5+p] = bayer_pixel[p][9:2];
                        end
                        payload[w*5+4] = {bayer_pixel[3][1:0], bayer_pixel[2][1:0],
                                          bayer_pixel[1][1:0], bayer_pixel[0][1:0]};
                    end
                    for (pack_index = 0; pack_index < 610; pack_index = pack_index + 1) begin
                        @(posedge clk); #1;
                        csi_valid = 1;
                        csi_data = {payload[pack_index*4], payload[pack_index*4+1],
                                    payload[pack_index*4+2], payload[pack_index*4+3]};
                    end
                    @(posedge clk); #1 csi_valid = 0;
                end else for (w = 0; w < 480; w = w + 1) begin
                    @(posedge clk); #1;
                    valid = 1; user = (y == 0 && w == 0);
                    last = (w == 479);
                    for (p = 0; p < 4; p = p + 1) begin
                        value = y % 2 == 0 ? (p % 2 == 0 ? rr : gg) :
                                                         (p % 2 == 0 ? gg : bb);
                        raw[p*10 +: 10] = value*4 + 50;
                    end
                end
                @(posedge clk); #1;
                valid = 0; user = 0; last = 0;
                repeat (240) @(posedge clk);
            end
            repeat (1500) @(posedge clk);
            if (csi_mode) $display("CSI frame=%0d compactor_width=%0d first_line_cycles=%0d ram0=%h ram400=%h",
                frame, isp.X_ui_top_demosaic.X_ui_raw_matrix_3x3_buffer.X_ui_zhenghe.valid_width,
                isp.X_ui_top_demosaic.X_ui_raw_matrix_3x3_buffer.X_ui_zhenghe.cnt_first,
                isp.X_ui_top_demosaic.X_ui_raw_matrix_3x3_buffer.X_ui_zhenghe.X_ui_ram_zhenghe.mem[0],
                isp.X_ui_top_demosaic.X_ui_raw_matrix_3x3_buffer.X_ui_zhenghe.X_ui_ram_zhenghe.mem[400]);
            end
            #1;
            if ($test$plusargs("FULL")) begin
                if (rows[0] != 1080 || rows[1] != 1080 || rows[2] != 576)
                    $fatal(1,"Full frame geometry changed: %0d/%0d/%0d", rows[0],rows[1],rows[2]);
            end
            for (p = 0; p < 3; p = p + 1) begin
                $display("STRICT stage=%0d mismatches=%0d", p, mismatches[p]);
                if (mismatches[p] != 0) $fatal(1, "Uniform color is not uniform");
                $display("mode=%0d stage=%0d pixels=%0d non_gray=%0d unknown=%0d rows=%0d sample=%06h",
                    mode, p, counts[p], chroma[p], unknowns[p], rows[p], sample[p]);
                if (counts[p] == 0 || unknowns[p] != 0)
                    $fatal(1, "Missing or unknown pixels at stage %0d", p);
                if (mode != 3 && chroma[p] < counts[p]*95/100)
                    $fatal(1, "Color collapsed at stage %0d", p);
                if (mode == 3 && chroma[p] != 0)
                    $fatal(1, "False color in grayscale control at stage %0d", p);
            end
        end
        $display("DSI_COLOR_DIAGNOSIS_PASS legacy_pixels_bit_exact=%0d", legacy_compares);
        $finish;
    end
endmodule
