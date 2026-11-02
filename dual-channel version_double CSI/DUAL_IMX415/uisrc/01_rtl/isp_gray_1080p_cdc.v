`timescale 1ns/1ps

// Read-only 1920x1080 ISP tap. Four RGB888 pixels arrive per camera clock.
// Four camera beats become one 128-bit GREY DMA beat. The asynchronous FIFO
// absorbs clock phase and short PCIe stalls without ever stalling the ISP.
module isp_gray_1080p_cdc (
    input wire cam_clk, cam_rst_n,
    input wire [127:0] s_tdata,
    input wire s_tvalid, s_tuser, s_tlast,
    input wire user_clk, user_rst_n, enable, dma_ready,
    output wire [127:0] m_tdata,
    output wire m_tvalid, m_tlast,
    input wire m_tready,
    output wire pixel_valid,
    output wire [31:0] frame_count, error_count,
    output reg [31:0] pass_count, drop_count, delivered_count
);
    localparam integer BEATS_PER_LINE=480;
    localparam integer LINES_PER_FRAME=1080;
    wire async_rst_n=cam_rst_n & user_rst_n;
    (* ASYNC_REG="TRUE" *) reg [2:0] cam_reset_sync, user_reset_sync;
    always @(posedge cam_clk or negedge async_rst_n)
        if(!async_rst_n) cam_reset_sync<=0;
        else cam_reset_sync<={cam_reset_sync[1:0],1'b1};
    always @(posedge user_clk or negedge async_rst_n)
        if(!async_rst_n) user_reset_sync<=0;
        else user_reset_sync<={user_reset_sync[1:0],1'b1};

    function [7:0] luma;
        input [31:0] rgb;
        reg [15:0] weighted;
        begin
            weighted=rgb[23:16]*16'd77 + rgb[15:8]*16'd150 +
                     rgb[7:0]*16'd29;
            luma=weighted[15:8];
        end
    endfunction
    reg [31:0] gray4;
    reg valid_d,sof_d,eol_d;
    always @(posedge cam_clk or negedge async_rst_n) begin
        if(!async_rst_n) begin
            gray4<=0;valid_d<=0;sof_d<=0;eol_d<=0;
        end else begin
            gray4<={luma(s_tdata[127:96]),luma(s_tdata[95:64]),
                    luma(s_tdata[63:32]),luma(s_tdata[31:0])};
            valid_d<=s_tvalid;sof_d<=s_tuser;eol_d<=s_tlast;
        end
    end

    reg [8:0] beat_x;
    reg [10:0] line_y;
    reg active,bad,abort_pending;
    reg [1:0] group;
    reg [95:0] partial;
    reg [31:0] frames_cam,errors_cam,frames_gray,errors_gray;
    wire first=sof_d;
    wire [8:0] cur_x=first ? 9'd0 : beat_x;
    wire [10:0] cur_y=first ? 11'd0 : line_y;
    wire taking=valid_d && (active || first) && (!bad || first) &&
                !abort_pending && !(first && active);
    wire malformed=taking && (eol_d != (cur_x==BEATS_PER_LINE-1) ||
                              cur_y>=LINES_PER_FRAME ||
                              group!=cur_x[1:0]);
    wire final_beat=taking && !malformed &&
                    cur_x==BEATS_PER_LINE-1 && cur_y==LINES_PER_FRAME-1;
    wire word_ready=taking && !malformed && group==2'd3;
    wire [127:0] gray16={gray4,partial};
    wire fifo_full,fifo_empty;
    wire [130:0] fifo_out;
    wire write_abort=abort_pending && !fifo_full;
    wire write_word=word_ready && !abort_pending && !fifo_full;
    wire [130:0] fifo_in=write_abort ? {1'b1,130'd0} :
                           {1'b0,final_beat,(cur_x==9'd3 && cur_y==0),gray16};
    wire fifo_pop;

    always @(posedge cam_clk or negedge async_rst_n) begin
        if(!async_rst_n) begin
            beat_x<=0;line_y<=0;active<=0;bad<=0;abort_pending<=0;
            group<=0;partial<=0;frames_cam<=0;errors_cam<=0;
            frames_gray<=0;errors_gray<=0;
        end else begin
            frames_gray<=(frames_cam>>1)^frames_cam;
            errors_gray<=(errors_cam>>1)^errors_cam;
            if(write_abort) abort_pending<=0;
            if(!cam_reset_sync[2]) begin
                beat_x<=0;line_y<=0;active<=0;bad<=0;
                abort_pending<=0;group<=0;
            end else begin
                if(first) begin
                    beat_x<=0;line_y<=0;group<=0;
                    active<=1;bad<=abort_pending || active;
                    if(active) begin
                        abort_pending<=1;
                        errors_cam<=errors_cam+1'b1;
                    end
                end
                if(taking) begin
                    if(malformed || (word_ready && fifo_full)) begin
                        active<=0;bad<=1;abort_pending<=1;
                        errors_cam<=errors_cam+1'b1;
                    end else begin
                        if(group==0) partial[31:0]<=gray4;
                        if(group==1) partial[63:32]<=gray4;
                        if(group==2) partial[95:64]<=gray4;
                        group<=group+1'b1;
                        if(eol_d) begin
                            beat_x<=0;line_y<=cur_y+1'b1;
                        end else beat_x<=cur_x+1'b1;
                        if(final_beat) begin
                            active<=0;frames_cam<=frames_cam+1'b1;
                        end
                    end
                end
            end
        end
    end

    demo_async_sfifo #(
        .DATA_WIDTH_W(131),.DATA_WIDTH_R(131),
        .ADDR_WIDTH_W(9),.ADDR_WIDTH_R(9),
        .AL_FULL_NUM(16),.AL_EMPTY_NUM(4),
        .SHOW_AHEAD_EN(1'b1),.OUTREG_EN("NOREG")
    ) u_gray_fifo (
        .rst(~async_rst_n),.clkw(cam_clk),.clkr(user_clk),
        .we((write_word||write_abort)&&cam_reset_sync[2]),.di(fifo_in),
        .re(fifo_pop),.dout(fifo_out),.valid(),
        .full_flag(fifo_full),.empty_flag(fifo_empty),
        .afull(),.aempty(),.wrusedw(),.rdusedw()
    );

    (* ASYNC_REG="TRUE" *) reg [31:0] frames_sync1,frames_sync2;
    (* ASYNC_REG="TRUE" *) reg [31:0] errors_sync1,errors_sync2;
    genvar bit_index;
    generate for(bit_index=0;bit_index<32;bit_index=bit_index+1) begin:g_decode
        assign frame_count[bit_index]=^(frames_sync2>>bit_index);
        assign error_count[bit_index]=^(errors_sync2>>bit_index);
    end endgenerate

    localparam [1:0] WAIT_SOF=0,STREAM=1,DROP=2;
    reg [1:0] state;
    wire is_abort=fifo_out[130];
    wire is_eof=fifo_out[129];
    wire is_sof=fifo_out[128];
    wire choose_frame=enable && dma_ready && is_sof && !is_abort;
    assign m_tdata=is_abort ? 128'd0 : fifo_out[127:0];
    assign m_tlast=is_abort || is_eof;
    assign m_tvalid=!fifo_empty && user_reset_sync[2] &&
                    (state==STREAM || (state!=STREAM && choose_frame));
    assign fifo_pop=!fifo_empty && user_reset_sync[2] &&
                    (state==STREAM ? m_tready :
                     choose_frame ? m_tready : 1'b1);
    assign pixel_valid=!fifo_empty;

    always @(posedge user_clk or negedge async_rst_n) begin
        if(!async_rst_n) begin
            state<=WAIT_SOF;pass_count<=0;drop_count<=0;delivered_count<=0;
            frames_sync1<=0;frames_sync2<=0;
            errors_sync1<=0;errors_sync2<=0;
        end else begin
            frames_sync1<=frames_gray;frames_sync2<=frames_sync1;
            errors_sync1<=errors_gray;errors_sync2<=errors_sync1;
            if(!user_reset_sync[2]) state<=WAIT_SOF;
            else if(fifo_pop) begin
                if(state==STREAM) begin
                    if(is_abort) begin
                        state<=WAIT_SOF;
                        drop_count<=drop_count+1'b1;
                        delivered_count<=delivered_count+1'b1;
                    end else if(is_eof) begin
                        state<=WAIT_SOF;
                        pass_count<=pass_count+1'b1;
                        delivered_count<=delivered_count+1'b1;
                    end
                end else if(is_sof && !is_abort) begin
                    if(choose_frame) begin
                        if(is_eof) begin
                            state<=WAIT_SOF;
                            pass_count<=pass_count+1'b1;
                            delivered_count<=delivered_count+1'b1;
                        end else state<=STREAM;
                    end else begin
                        state<=DROP;
                        drop_count<=drop_count+1'b1;
                    end
                end else if(is_eof || is_abort) state<=WAIT_SOF;
            end
        end
    end
endmodule
