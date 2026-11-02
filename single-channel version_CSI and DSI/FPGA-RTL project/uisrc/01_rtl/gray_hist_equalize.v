`timescale 1ns/1ps

// Streaming HE: histogram of frame N maps frame N+1. CDF-min normalization;
// constant frames use identity. LUT switches only on an accepted SOF.
module gray_hist_equalize #(
    parameter integer FRAME_PIXELS = 1280*720
)(
    input wire clk, rst_n,
    input wire [7:0] s_gray,
    input wire s_valid, s_sof, s_eof, s_abort,
    output reg [7:0] m_gray,
    output reg m_valid, m_sof, m_eof, m_abort,
    output reg [31:0] frame_count,
    output reg lut_ready
);
    localparam CLEAR=0, WAIT_SOF=1, CAPTURE=2, DRAIN=3,
               READ_BIN=4, CALC=5, ADVANCE=6, WRITE_BIN=7;
    reg [2:0] state;
    reg [19:0] hist [0:255]; /* fehdl force_ram=1, ram_style="bram" */
    reg [7:0] lut0 [0:255];
    reg [7:0] lut1 [0:255];
    reg [19:0] hist_q;
    reg [7:0] index;
    reg initial_clear, active_bank, next_ready;
    reg [19:0] count, cdf, cdf_min, denominator;
    reg found, uniform_build;
    reg [27:0] target, threshold;
    reg [7:0] level, bin_value;
    reg update_valid, update_eof;
    reg [7:0] update_bin;
    reg last_write;
    reg [7:0] last_bin;
    reg [19:0] last_value;
    wire start = !s_abort && s_valid && s_sof && state==WAIT_SOF;
    wire accept = !s_abort && (start || (s_valid && !s_sof && state==CAPTURE));
    wire malformed = s_valid && state==CAPTURE &&
                     (s_sof || (s_eof != (count==FRAME_PIXELS-1)));
    wire update_fire = update_valid && state!=CLEAR;
    wire [19:0] incremented =
        ((last_write && last_bin==update_bin) ? last_value : hist_q) + 1'b1;
    wire [19:0] cdf_next = cdf + hist_q;
    wire [19:0] delta = cdf_next - cdf_min;
    wire use_bank = (start && next_ready) ? !active_bank : active_bank;

    always @(posedge clk) begin
        if (accept) hist_q <= hist[s_gray];
        else if (state==READ_BIN) hist_q <= hist[index];
        if (state==CLEAR || state==WRITE_BIN) hist[index] <= 0;
        else if (update_fire) hist[update_bin] <= incremented;
        if (state==CLEAR && initial_clear) begin
            lut0[index] <= index;
            lut1[index] <= index;
        end else if (state==WRITE_BIN) begin
            if (active_bank) lut0[index] <= bin_value;
            else lut1[index] <= bin_value;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=CLEAR; index<=0; initial_clear<=1;
            active_bank<=0; next_ready<=0; lut_ready<=0;
            count<=0; cdf<=0; cdf_min<=0; denominator<=0;
            found<=0; uniform_build<=0; target<=0; threshold<=0; level<=0; bin_value<=0;
            update_valid<=0; update_eof<=0; update_bin<=0;
            last_write<=0; last_bin<=0; last_value<=0;
            m_gray<=0; m_valid<=0; m_sof<=0; m_eof<=0; m_abort<=0;
            frame_count<=0;
        end else begin
            m_valid<=accept && !malformed;
            m_sof<=start;
            m_eof<=accept && s_eof && !malformed;
            m_abort<=s_abort || malformed;
            if (accept) m_gray<=use_bank ? lut1[s_gray] : lut0[s_gray];
            update_valid<=accept && !malformed;
            update_eof<=accept && s_eof && !malformed;
            update_bin<=s_gray;
            last_write<=update_fire;
            if (update_fire) begin last_bin<=update_bin; last_value<=incremented; end

            case(state)
                CLEAR: begin
                    if (index==255) begin
                        index<=0; initial_clear<=0; state<=WAIT_SOF;
                    end else index<=index+1'b1;
                end
                WAIT_SOF: if(start) begin
                    state<=CAPTURE; count<=1;
                    if(next_ready) begin
                        active_bank<=!active_bank; next_ready<=0; lut_ready<=1;
                    end
                end
                CAPTURE: if(accept) begin
                    count<=count+1'b1;
                    if(s_eof) state<=DRAIN;
                end
                DRAIN: if(update_eof) begin
                    frame_count<=frame_count+1'b1;
                    index<=0; cdf<=0; cdf_min<=0; found<=0; uniform_build<=0;
                    level<=0; threshold<=0; state<=READ_BIN;
                end
                READ_BIN: state<=CALC;
                CALC: begin
                    cdf<=cdf_next;
                    if(!found) begin
                        bin_value<=0;
                        if(hist_q!=0) begin
                            found<=1; cdf_min<=cdf_next;
                            denominator<=FRAME_PIXELS-cdf_next;
                            threshold<=FRAME_PIXELS-cdf_next;
                            if(cdf_next==FRAME_PIXELS) begin
                                // Revisit earlier zero bins as well, so the
                                // entire map is identity for a uniform frame.
                                uniform_build<=1; index<=0; bin_value<=0;
                            end
                        end
                        state<=WRITE_BIN;
                    end else if(denominator==0) begin
                        bin_value<=index; state<=WRITE_BIN;
                    end else begin
                        target<=({8'd0,delta}<<8)-{8'd0,delta}; state<=ADVANCE;
                    end
                end
                ADVANCE: begin
                    if(level!=255 && target>=threshold) begin
                        level<=level+1'b1; threshold<=threshold+denominator;
                    end else begin bin_value<=level; state<=WRITE_BIN; end
                end
                WRITE_BIN: begin
                    if(index==255) begin next_ready<=1; state<=WAIT_SOF; end
                    else begin
                        index<=index+1'b1;
                        if(uniform_build) begin bin_value<=index+1'b1; state<=WRITE_BIN; end
                        else state<=READ_BIN;
                    end
                end
                default: begin state<=CLEAR; index<=0; end
            endcase
            // Never publish a histogram from an incomplete frame. The last
            // complete LUT stays active through an input/CDC error.
            if ((s_abort || malformed) && (state==CAPTURE || state==DRAIN)) begin
                state<=CLEAR; index<=0; update_valid<=0; update_eof<=0;
                m_valid<=0; m_sof<=0; m_eof<=0;
            end
        end
    end
endmodule
