`timescale 1ns/1ps

// Read-only tap of the demo's four grayscale RGB pixels/beat. Include a
// halo for a centred 5x5 filter: x=316..1603, y=178..901 (1288x724).
module isp_gray_crop_cdc (
    input wire cam_clk, cam_rst_n,
    input wire [127:0] s_tdata,
    input wire s_tvalid, s_tuser, s_tlast,
    input wire user_clk, user_rst_n,
    output reg [7:0] m_gray,
    output reg m_valid, m_sof, m_eof, m_abort,
    output wire [31:0] error_count
);
    wire async_rst_n = cam_rst_n & user_rst_n;
    (* ASYNC_REG = "TRUE" *) reg [2:0] cam_reset_sync, user_reset_sync;
    always @(posedge cam_clk or negedge async_rst_n)
        if (!async_rst_n) cam_reset_sync <= 0;
        else cam_reset_sync <= {cam_reset_sync[1:0],1'b1};
    always @(posedge user_clk or negedge async_rst_n)
        if (!async_rst_n) user_reset_sync <= 0;
        else user_reset_sync <= {user_reset_sync[1:0],1'b1};

    reg [9:0] bx;
    reg [10:0] ly;
    reg have_frame, frame_bad, abort_pending, crop_open;
    reg [31:0] errors, errors_gray;
    wire [9:0] cx = s_tuser ? 10'd0 : bx;
    wire [10:0] cy = s_tuser ? 11'd0 : ly;
    wire selected = s_tvalid && have_frame && !frame_bad &&
                    cx >= 79 && cx < 401 && cy >= 178 && cy < 902;
    wire sof = cx == 79 && cy == 178;
    wire eof = cx == 400 && cy == 901;
    wire bad_line = s_tvalid && have_frame && !s_tuser &&
                    ((s_tlast && cx != 479) || (!s_tlast && cx >= 479));
    wire full_flag, empty_flag, pop;
    wire write_abort = abort_pending && !full_flag;
    wire write_pixel = selected && !abort_pending && !full_flag && !bad_line;
    wire [35:0] fifo_in = write_abort ? {1'b1,35'd0} :
        {1'b0,1'b0,eof,sof,s_tdata[111:104],s_tdata[79:72],
                            s_tdata[47:40],s_tdata[15:8]};
    wire [35:0] fifo_out;

    always @(posedge cam_clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            bx <= 0; ly <= 0; have_frame <= 0; frame_bad <= 0;
            abort_pending <= 0; crop_open <= 0; errors <= 0; errors_gray <= 0;
        end else if (!cam_reset_sync[2]) begin
            bx <= 0; ly <= 0; have_frame <= 0; frame_bad <= 0;
            abort_pending <= 0; crop_open <= 0; errors <= 0; errors_gray <= 0;
        end else begin
            errors_gray <= (errors >> 1) ^ errors;
            if (write_abort) abort_pending <= 0;
            if (write_pixel && sof) crop_open <= 1;
            if (write_pixel && eof) crop_open <= 0;
            // Handle SOF independently of valid, and saturate on bad timing.
            if (s_tuser) begin
                bx <= s_tvalid ? 10'd1 : 10'd0;
                ly <= 0; have_frame <= 1;
                frame_bad <= abort_pending || crop_open;
                if (crop_open) begin
                    abort_pending <= 1; crop_open <= 0; errors <= errors + 1'b1;
                end
            end else if (s_tvalid && have_frame) begin
                if (s_tlast) begin
                    bx <= 0;
                    if (ly != 11'h7ff) ly <= ly + 1'b1;
                end else if (bx != 10'h3ff) bx <= bx + 1'b1;
            end
            if (!frame_bad && (bad_line || (selected && full_flag))) begin
                frame_bad <= 1; errors <= errors + 1'b1;
                if (crop_open) begin abort_pending <= 1; crop_open <= 0; end
            end
        end
    end

    demo_async_sfifo #(.DATA_WIDTH_W(36), .DATA_WIDTH_R(36),
        .ADDR_WIDTH_W(9), .ADDR_WIDTH_R(9),
        .AL_FULL_NUM(16), .AL_EMPTY_NUM(4),
        .SHOW_AHEAD_EN(1'b1), .OUTREG_EN("NOREG")) u_crop_fifo (
        .rst(~async_rst_n), .clkw(cam_clk), .clkr(user_clk),
        .we((write_pixel || write_abort) && cam_reset_sync[2]), .di(fifo_in),
        .re(pop), .dout(fifo_out), .valid(), .full_flag(full_flag),
        .empty_flag(empty_flag), .afull(), .aempty(), .wrusedw(), .rdusedw()
    );
    (* ASYNC_REG = "TRUE" *) reg [31:0] err_sync1, err_sync2;
    genvar bit_index;
    generate for (bit_index=0; bit_index<32; bit_index=bit_index+1) begin : g_decode
        assign error_count[bit_index] = ^(err_sync2 >> bit_index);
    end endgenerate
    reg [35:0] word_hold;
    reg [1:0] lane;
    reg busy;
    assign pop = !busy && !empty_flag && user_reset_sync[2];
    always @(posedge user_clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            word_hold <= 0; lane <= 0; busy <= 0;
            m_gray <= 0; m_valid <= 0; m_sof <= 0; m_eof <= 0; m_abort <= 0;
            err_sync1 <= 0; err_sync2 <= 0;
        end else begin
            err_sync1 <= errors_gray; err_sync2 <= err_sync1;
            m_valid <= 0; m_sof <= 0; m_eof <= 0; m_abort <= 0;
            if (!user_reset_sync[2]) busy <= 0;
            else if (pop) begin
                if (fifo_out[35]) m_abort <= 1;
                else begin word_hold <= fifo_out; lane <= 0; busy <= 1; end
            end else if (busy) begin
                m_gray <= word_hold[7:0];
                word_hold[31:0] <= {8'd0,word_hold[31:8]};
                m_valid <= 1;
                m_sof <= word_hold[32] && lane == 0;
                m_eof <= word_hold[33] && lane == 3;
                if (lane == 3) busy <= 0;
                else lane <= lane + 1'b1;
            end
        end
    end
endmodule
