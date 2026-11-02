`timescale 1ns/1ps
// Eight RAW10 pixels per DDR word. Every word carries its source frame and
// ordinal: FIFO loss or malformed rows cannot silently produce a valid frame.
// Layout: [79:0] RAW, [97:80] ordinal, [125:98] frame, [126] Bayer row, [127] bad.
module v2_raw_capture #(parameter WIDTH=1920,HEIGHT=1080,FIFO_ADDR=9)(
    input wire rst_n,cam_clk, input wire [39:0] raw,
    input wire valid,sof,eol,row_odd,
    input wire mem_clk,output wire [127:0] data,
    output wire data_valid,input wire data_ready,
    output reg [31:0] source_frames,overflow_frames,format_errors,
    output wire [15:0] queued_words
);
    localparam WORDS=WIDTH*HEIGHT/8, BEATS=WIDTH/4;
    reg [39:0] lo;
    reg half,active,bad,odd;
    reg [27:0] frame_id;
    reg [17:0] word_index;
    reg [10:0] x,y;
    reg [127:0] packed_data;
    reg packed_valid;
    wire fifo_ready;
    wire [FIFO_ADDR:0] fifo_level;
    assign queued_words=fifo_level;
    wire [10:0] cx=sof ? 11'd0:x, cy=sof ? 11'd0:y;
    wire taking=active || sof;
    wire malformed=eol!=(cx==BEATS-1) || cy>=HEIGHT;
    always @(posedge cam_clk or negedge rst_n) begin
        if(!rst_n) begin
            lo<=0;half<=0;active<=0;bad<=0;odd<=0;frame_id<=0;
            word_index<=0;x<=0;y<=0;packed_data<=0;packed_valid<=0;
            source_frames<=0;overflow_frames<=0;format_errors<=0;
        end else begin
            packed_valid<=0;
            if(packed_valid && !fifo_ready && !bad) begin
                bad<=1;overflow_frames<=overflow_frames+1'b1;
            end
            if(valid && taking) begin
                if(sof) begin
                    frame_id<=frame_id+1'b1;source_frames<=source_frames+1'b1;
                    half<=1;lo<=raw;word_index<=0;active<=1;bad<=0;odd<=row_odd;
                    if(active) format_errors<=format_errors+1'b1;
                end else if(!half) begin half<=1;lo<=raw;end
                else begin
                    half<=0;
                    packed_data<={bad || malformed || (packed_valid && !fifo_ready),
                                  (word_index==0 ? row_odd : odd),frame_id,word_index,raw,lo};
                    packed_valid<=1;word_index<=word_index+1'b1;
                    if(word_index==0) odd<=row_odd;
                end
                if(malformed) begin
                    bad<=1;if(!bad) format_errors<=format_errors+1'b1;
                end
                if(eol) begin x<=0;y<=cy+1'b1;end
                else begin x<=cx+1'b1;y<=cy;end
                if(eol && cy==HEIGHT-1) active<=0;
            end
        end
    end
    v2_async_fifo #(.WIDTH(128),.ADDR(FIFO_ADDR)) u_fifo (
        .rst_n(rst_n),.wclk(cam_clk),.s_data(packed_data),
        .s_valid(packed_valid),.s_ready(fifo_ready),.rclk(mem_clk),
        .m_data(data),.m_valid(data_valid),.m_ready(data_ready),.m_level(fifo_level));
endmodule
