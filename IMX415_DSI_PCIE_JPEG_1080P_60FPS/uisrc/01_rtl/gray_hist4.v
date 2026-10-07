`timescale 1ns/1ps

// Four histogram banks accept one pixel per lane on every clock. Their counts
// are merged during vertical blanking to build one shared CDF-min LUT. Four
// copies of each LUT provide four simultaneous pixel reads. Frame N uses the
// complete LUT from frame N-1; a partial frame never publishes a LUT.
module gray_hist4 #(
    parameter integer WIDTH = 1920,
    parameter integer HEIGHT = 1080,
    // 0 preserves the original mapping; 2 follows each new LUT by 1/4.
    parameter integer LUT_IIR_SHIFT = 0
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] s_gray,
    input  wire        s_valid,
    input  wire        s_sof,
    input  wire        s_eol,
    input  wire        enable,
    output reg  [31:0] m_gray,
    output reg         m_valid,
    output reg         m_sof,
    output reg         m_eol,
    output reg         lut_active,
    output reg  [31:0] hist_frames,
    output reg  [31:0] hist_errors
);
    localparam integer FRAME_BEATS = (WIDTH/4)*HEIGHT;
    localparam integer FRAME_PIXELS = WIDTH*HEIGHT;
    localparam integer CW = $clog2(FRAME_BEATS+1);
    localparam integer FW = $clog2(FRAME_PIXELS+1);
    localparam integer XB = $clog2(WIDTH/4);
    localparam [3:0] CLEAR=0, WAIT_SOF=1, CAPTURE=2, DRAIN=3,
                     DRAIN2=4, READ_BIN=5, CALC=6, ADVANCE=7,
                     WRITE_BIN=8, UNIFORM=9, CLEAR_BIN=10;

    reg [3:0] state;
    reg [7:0] index;
    reg [CW-1:0] beat_count;
    reg [XB-1:0] line_x;
    reg [CW-1:0] hist0 [0:255];
    reg [CW-1:0] hist1 [0:255];
    reg [CW-1:0] hist2 [0:255];
    reg [CW-1:0] hist3 [0:255];
    reg [CW-1:0] q0,q1,q2,q3;
    reg [CW-1:0] read0,read1,read2,read3;
    reg [7:0] pend0,pend1,pend2,pend3;
    reg pend_valid;
    reg [7:0] last0,last1,last2,last3;
    reg [CW-1:0] value0,value1,value2,value3;
    reg last_write;
    wire [CW-1:0] next0 = ((last_write && last0==pend0) ? value0 : read0) + 1'b1;
    wire [CW-1:0] next1 = ((last_write && last1==pend1) ? value1 : read1) + 1'b1;
    wire [CW-1:0] next2 = ((last_write && last2==pend2) ? value2 : read2) + 1'b1;
    wire [CW-1:0] next3 = ((last_write && last3==pend3) ? value3 : read3) + 1'b1;

    reg [7:0] lut_a0 [0:255],lut_a1 [0:255],lut_a2 [0:255],lut_a3 [0:255];
    reg [7:0] lut_b0 [0:255],lut_b1 [0:255],lut_b2 [0:255],lut_b3 [0:255];
    // One extra 256-byte state table avoids adding a read port to the four
    // LUTs used by the live four-pixel-per-clock path.
    reg [7:0] previous_lut [0:255];
    reg active_bank, next_ready, eq_enabled, initial_clear;
    wire select_bank = (s_sof && next_ready && state==WAIT_SOF) ?
                       !active_bank : active_bank;
    wire select_eq = s_sof ? enable : eq_enabled;
    wire [31:0] lookup_a = {lut_a3[s_gray[31:24]],lut_a2[s_gray[23:16]],
                            lut_a1[s_gray[15:8]],lut_a0[s_gray[7:0]]};
    wire [31:0] lookup_b = {lut_b3[s_gray[31:24]],lut_b2[s_gray[23:16]],
                            lut_b1[s_gray[15:8]],lut_b0[s_gray[7:0]]};

    reg [FW-1:0] cdf,cdf_min,denominator;
    reg found;
    reg [FW+7:0] target,threshold;
    reg [7:0] level,bin_value,old_bin_value;
    localparam integer IIR_ROUND = LUT_IIR_SHIFT > 0 ?
                                   (1 << (LUT_IIR_SHIFT-1)) : 0;
    function [7:0] filter_bin;
        input [7:0] old_value,new_value;
        reg [8:0] difference,step;
        begin
            if (LUT_IIR_SHIFT == 0) filter_bin = new_value;
            else if (new_value >= old_value) begin
                difference = {1'b0,new_value} - {1'b0,old_value};
                step = (difference + IIR_ROUND) >> LUT_IIR_SHIFT;
                filter_bin = old_value + step[7:0];
            end else begin
                difference = {1'b0,old_value} - {1'b0,new_value};
                step = (difference + IIR_ROUND) >> LUT_IIR_SHIFT;
                filter_bin = old_value - step[7:0];
            end
        end
    endfunction
    wire [7:0] filtered_bin = filter_bin(old_bin_value,bin_value);
    wire [FW-1:0] bin_sum = {{(FW-CW){1'b0}},q0}+
                             {{(FW-CW){1'b0}},q1}+
                             {{(FW-CW){1'b0}},q2}+
                             {{(FW-CW){1'b0}},q3};
    wire [FW-1:0] cdf_next = cdf + bin_sum;
    wire [FW-1:0] delta = cdf_next - cdf_min;
    wire capture = s_valid && (state==CAPTURE ||
                               (state==WAIT_SOF && s_sof));

    // One synchronous read and one write per histogram bank and clock.
    // The most recently written value bypasses read-during-write ambiguity.
    always @(posedge clk) begin
        if (capture) begin
            read0 <= hist0[s_gray[7:0]];
            read1 <= hist1[s_gray[15:8]];
            read2 <= hist2[s_gray[23:16]];
            read3 <= hist3[s_gray[31:24]];
        end else if (state==READ_BIN) begin
            q0 <= hist0[index]; q1 <= hist1[index];
            q2 <= hist2[index]; q3 <= hist3[index];
            old_bin_value <= previous_lut[index];
        end
        // Keep the histogram read and clear on separate clocks. TD's ERAM
        // read-during-write result is not guaranteed to be the old count.
        if (state==CLEAR || state==CLEAR_BIN) begin
            hist0[index] <= 0; hist1[index] <= 0;
            hist2[index] <= 0; hist3[index] <= 0;
        end else if (pend_valid) begin
            hist0[pend0] <= next0; hist1[pend1] <= next1;
            hist2[pend2] <= next2; hist3[pend3] <= next3;
        end
        if (state==CLEAR && initial_clear) begin
            previous_lut[index] <= index;
            lut_a0[index] <= index; lut_a1[index] <= index;
            lut_a2[index] <= index; lut_a3[index] <= index;
            lut_b0[index] <= index; lut_b1[index] <= index;
            lut_b2[index] <= index; lut_b3[index] <= index;
        end else if (state==WRITE_BIN || state==UNIFORM) begin
            previous_lut[index] <= state==UNIFORM ? index : filtered_bin;
            if (active_bank) begin
                lut_a0[index] <= state==UNIFORM ? index : filtered_bin;
                lut_a1[index] <= state==UNIFORM ? index : filtered_bin;
                lut_a2[index] <= state==UNIFORM ? index : filtered_bin;
                lut_a3[index] <= state==UNIFORM ? index : filtered_bin;
            end else begin
                lut_b0[index] <= state==UNIFORM ? index : filtered_bin;
                lut_b1[index] <= state==UNIFORM ? index : filtered_bin;
                lut_b2[index] <= state==UNIFORM ? index : filtered_bin;
                lut_b3[index] <= state==UNIFORM ? index : filtered_bin;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=CLEAR; index<=0; beat_count<=0; line_x<=0;
            pend0<=0; pend1<=0; pend2<=0; pend3<=0; pend_valid<=0;
            last0<=0; last1<=0; last2<=0; last3<=0;
            value0<=0; value1<=0; value2<=0; value3<=0;
            last_write<=0; active_bank<=0; next_ready<=0;
            initial_clear<=1;
            eq_enabled<=0; lut_active<=0;
            cdf<=0; cdf_min<=0; denominator<=0; found<=0;
            target<=0; threshold<=0; level<=0; bin_value<=0;
            m_gray<=0; m_valid<=0; m_sof<=0; m_eol<=0;
            hist_frames<=0; hist_errors<=0;
        end else begin
            m_valid <= s_valid;
            m_sof <= s_valid && s_sof;
            m_eol <= s_valid && s_eol;
            if (s_valid) begin
                m_gray <= select_eq && (lut_active ||
                          (s_sof && next_ready && state==WAIT_SOF)) ?
                          (select_bank ? lookup_b : lookup_a) : s_gray;
            end
            if (s_valid && s_sof) eq_enabled <= enable;
            if (capture) begin
                pend0<=s_gray[7:0]; pend1<=s_gray[15:8];
                pend2<=s_gray[23:16]; pend3<=s_gray[31:24];
            end
            pend_valid<=capture;
            last_write<=pend_valid && state!=CLEAR && state!=CLEAR_BIN;
            if (pend_valid && state!=CLEAR && state!=CLEAR_BIN) begin
                last0<=pend0; last1<=pend1; last2<=pend2; last3<=pend3;
                value0<=next0; value1<=next1;
                value2<=next2; value3<=next3;
            end

            case (state)
                CLEAR: begin
                    if (index==255) begin
                        index<=0; state<=WAIT_SOF; initial_clear<=0;
                    end
                    else index<=index+1'b1;
                end
                WAIT_SOF: if (s_valid && s_sof) begin
                    state<=CAPTURE; beat_count<=1; line_x<=1;
                    if (next_ready) begin
                        active_bank<=!active_bank; next_ready<=0;
                        lut_active<=1;
                    end
                end
                CAPTURE: if (s_valid) begin
                    if (s_sof || (s_eol != (line_x==(WIDTH/4)-1))) begin
                        state<=CLEAR; index<=0; hist_errors<=hist_errors+1'b1;
                    end else if (beat_count==FRAME_BEATS-1) begin
                        state<=DRAIN; beat_count<=0;
                    end else begin
                        beat_count<=beat_count+1'b1;
                        line_x<=s_eol ? {XB{1'b0}} : line_x+1'b1;
                    end
                end
                DRAIN: state<=DRAIN2;
                DRAIN2: begin
                    hist_frames<=hist_frames+1'b1;
                    index<=0; cdf<=0; cdf_min<=0; denominator<=0;
                    found<=0; level<=0; threshold<=0;
                    state<=READ_BIN;
                end
                READ_BIN: state<=CLEAR_BIN;
                CLEAR_BIN: state<=CALC;
                CALC: begin
                    cdf<=cdf_next;
                    if (!found) begin
                        bin_value<=0;
                        if (bin_sum!=0) begin
                            found<=1; cdf_min<=cdf_next;
                            denominator<=FRAME_PIXELS-cdf_next;
                            threshold<=FRAME_PIXELS-cdf_next;
                            if (cdf_next==FRAME_PIXELS) begin
                                index<=0; state<=UNIFORM;
                            end else state<=WRITE_BIN;
                        end else state<=WRITE_BIN;
                    end else begin
                        target<=({8'd0,delta}<<8)-{8'd0,delta};
                        state<=ADVANCE;
                    end
                end
                ADVANCE: begin
                    if (level!=255 && target>=threshold) begin
                        level<=level+1'b1;
                        threshold<=threshold+denominator;
                    end else begin
                        bin_value<=level; state<=WRITE_BIN;
                    end
                end
                WRITE_BIN: begin
                    if (index==255) begin next_ready<=1; state<=WAIT_SOF; end
                    else begin index<=index+1'b1; state<=READ_BIN; end
                end
                UNIFORM: begin
                    if (index==255) begin next_ready<=1; state<=WAIT_SOF; end
                    else index<=index+1'b1;
                end
                default: begin state<=CLEAR; index<=0; end
            endcase
            if (s_valid && s_sof && state!=WAIT_SOF && state!=CAPTURE) begin
                hist_errors<=hist_errors+1'b1;
            end
        end
    end
endmodule
