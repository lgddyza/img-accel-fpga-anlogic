`timescale 1ns/1ps

// 1920x1080, four RGB888 pixels per camera clock. All three stages remain
// active in hardware. mode[0] enables Gaussian; mode[1] enables CLAHE.
// CLAHE learns the selected input stream and publishes only complete LUTs.
module gray_preprocess4 #(
    parameter integer WIDTH = 1920,
    parameter integer HEIGHT = 1080
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire [127:0] s_rgb,
    input  wire         s_valid,
    input  wire         s_sof,
    input  wire         s_eol,
    input  wire [1:0]   mode,
    output wire [127:0] m_rgb_gray,
    output wire         m_valid,
    output wire         m_sof,
    output wire         m_eol,
    output wire         gauss_overrun,
    output wire [31:0] hist_frames,
    output wire [31:0] hist_errors
);
    function [7:0] luma;
        input [31:0] rgb;
        reg [15:0] sum_y;
        begin
            sum_y = 16'd77*rgb[23:16] + 16'd150*rgb[15:8] +
                    16'd29*rgb[7:0] + 16'd128;
            luma = sum_y[15:8];
        end
    endfunction
    reg [31:0] gray4;
    reg gray_valid,gray_sof,gray_eol;
    reg [1:0] frame_mode;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gray4<=0; gray_valid<=0; gray_sof<=0; gray_eol<=0;
            frame_mode<=2'b11;
        end else begin
            gray4 <= {luma(s_rgb[127:96]),luma(s_rgb[95:64]),
                      luma(s_rgb[63:32]),luma(s_rgb[31:0])};
            gray_valid<=s_valid;
            gray_sof<=s_valid && s_sof;
            gray_eol<=s_valid && s_eol;
            if (s_valid && s_sof) frame_mode<=mode;
        end
    end

    wire [31:0] center4,gauss4;
    wire gauss_valid,gauss_sof,gauss_eol;
    gray_gauss4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_gauss (
        .clk(clk),.rst_n(rst_n),.s_gray(gray4),
        .s_valid(gray_valid),.s_sof(gray_sof),.s_eol(gray_eol),
        .m_center(center4),.m_gauss(gauss4),
        .m_valid(gauss_valid),.m_sof(gauss_sof),.m_eol(gauss_eol),
        .m_overrun(gauss_overrun)
    );
    wire [31:0] selected4 = frame_mode[0] ? gauss4 : center4;
    wire [31:0] equalized4;
    wire lut_active;
    // 2x2 tiled CLAHE with clipping, bilinear interpolation and temporal LUT IIR.
    gray_clahe4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.LUT_IIR_SHIFT(2)) u_hist (
        .clk(clk),.rst_n(rst_n),.s_gray(selected4),
        .s_valid(gauss_valid),.s_sof(gauss_sof),.s_eol(gauss_eol),
        .enable(frame_mode[1]),
        .m_gray(equalized4),.m_valid(m_valid),
        .m_sof(m_sof),.m_eol(m_eol),
        .lut_active(lut_active),.hist_frames(hist_frames),
        .hist_errors(hist_errors)
    );
    genvar lane;
    generate for (lane=0;lane<4;lane=lane+1) begin : g_rgb
        wire [7:0] y = equalized4[lane*8 +: 8];
        assign m_rgb_gray[lane*32 +: 32] = {8'd0,y,y,y};
    end endgenerate
endmodule

`timescale 1ns/1ps

// Streaming 2x2 CLAHE for four grayscale pixels per clock.
// Frame N supplies four histograms; the complete maps are published in the
// vertical blank and applied to frame N+1. No stalls enter the video path.
// WIDTH must be a multiple of 8 and HEIGHT must be even.
module gray_clahe4 #(
    parameter integer WIDTH = 1920,
    parameter integer HEIGHT = 1080,
    parameter integer LUT_IIR_SHIFT = 2,
    parameter integer CLIP_FACTOR = 2
)(
    input wire clk, rst_n,
    input wire [31:0] s_gray,
    input wire s_valid, s_sof, s_eol, enable,
    output reg [31:0] m_gray,
    output reg m_valid, m_sof, m_eol, lut_active,
    output reg [31:0] hist_frames, hist_errors
);
    localparam integer FRAME_BEATS = (WIDTH/4)*HEIGHT;
    localparam integer TILE_PIXELS = (WIDTH/2)*(HEIGHT/2);
    localparam integer CLIP_LIMIT = ((TILE_PIXELS*CLIP_FACTOR)/256)<1 ?
                                    1 : (TILE_PIXELS*CLIP_FACTOR)/256;
    localparam integer HW = $clog2(TILE_PIXELS/4+1);
    localparam integer SW = $clog2(TILE_PIXELS+1);
    localparam integer BW = $clog2(FRAME_BEATS+1);
    localparam integer XW = $clog2(WIDTH/4);
    localparam integer YW = $clog2(HEIGHT+1);
    localparam integer XCW = $clog2(WIDTH+1);
    localparam [3:0] CLEAR=0, WAIT_SOF=1, CAPTURE=2, DRAIN=3,
      READ_HIST=4, CLEAR_HIST=5, CLIP_BIN=6, PREP_MAP=7,
      READ_CLIP=8, CALC_MAP=9, FIND_LEVEL=10, WRITE_MAP=11;
    reg [3:0] state;
    reg [9:0] clear_addr, hist_addr;
    reg [7:0] bin;
    reg [1:0] tile;
    reg [XW-1:0] beat_x;
    reg [YW-1:0] row_y;
    reg [BW-1:0] beat_count;
    reg [HW-1:0] hist0[0:1023],hist1[0:1023],hist2[0:1023],hist3[0:1023];
    reg [HW-1:0] read0,read1,read2,read3;
    reg [9:0] pending_addr0,pending_addr1,pending_addr2,pending_addr3;
    reg [9:0] last_addr0,last_addr1,last_addr2,last_addr3;
    reg [HW-1:0] last_value0,last_value1,last_value2,last_value3;
    reg pending_valid,last_write;
    wire [HW-1:0] next0 = ((last_write && last_addr0==pending_addr0) ? last_value0 : read0)+1'b1;
    wire [HW-1:0] next1 = ((last_write && last_addr1==pending_addr1) ? last_value1 : read1)+1'b1;
    wire [HW-1:0] next2 = ((last_write && last_addr2==pending_addr2) ? last_value2 : read2)+1'b1;
    wire [HW-1:0] next3 = ((last_write && last_addr3==pending_addr3) ? last_value3 : read3)+1'b1;
    wire [XW-1:0] pixel_beat_x = s_sof ? {XW{1'b0}} : beat_x;
    wire [YW-1:0] pixel_row_y = s_sof ? {YW{1'b0}} : row_y;
    wire [1:0] pixel_tile = {(pixel_row_y >= HEIGHT/2), (pixel_beat_x >= WIDTH/8)};
    wire [9:0] addr0={pixel_tile,s_gray[7:0]};
    wire [9:0] addr1={pixel_tile,s_gray[15:8]};
    wire [9:0] addr2={pixel_tile,s_gray[23:16]};
    wire [9:0] addr3={pixel_tile,s_gray[31:24]};
    wire capture = s_valid && (state==CAPTURE || (state==WAIT_SOF && s_sof));

    // One read and one write per lane bank; bypass consecutive identical bins.
    always @(posedge clk) begin
        if (capture) begin
            read0<=hist0[addr0]; read1<=hist1[addr1];
            read2<=hist2[addr2]; read3<=hist3[addr3];
        end else if (state==READ_HIST) begin
            read0<=hist0[hist_addr]; read1<=hist1[hist_addr];
            read2<=hist2[hist_addr]; read3<=hist3[hist_addr];
        end
        if (state==CLEAR) begin
            hist0[clear_addr]<=0; hist1[clear_addr]<=0;
            hist2[clear_addr]<=0; hist3[clear_addr]<=0;
        end else if (state==CLEAR_HIST) begin
            hist0[hist_addr]<=0; hist1[hist_addr]<=0;
            hist2[hist_addr]<=0; hist3[hist_addr]<=0;
        end else if (pending_valid) begin
            hist0[pending_addr0]<=next0; hist1[pending_addr1]<=next1;
            hist2[pending_addr2]<=next2; hist3[pending_addr3]<=next3;
        end
    end

    reg [SW-1:0] clipped[0:255];
    reg [SW-1:0] clipped_read;
    reg [SW-1:0] excess, cdf, extra_quotient;
    reg [7:0] extra_remainder;
    reg [SW-1:0] adjusted;
    reg [SW+7:0] target, threshold;
    reg [7:0] level, old_map;
    reg first_map, frame_use_lut;
    reg [7:0] previous_map[0:1023];
    reg [7:0] lut00[0:255],lut01[0:255],lut10[0:255],lut11[0:255];
    wire [SW-1:0] hist_sum = read0+read1+read2+read3;
    wire [SW-1:0] capped = hist_sum>CLIP_LIMIT ? CLIP_LIMIT : hist_sum;
    wire [SW-1:0] adjusted_next = clipped_read+extra_quotient+(bin<extra_remainder);
    wire [SW-1:0] cdf_next = cdf+adjusted_next;
    function [7:0] iir;
        input [7:0] old_value,new_value;
        reg [8:0] diff;
        begin
            if (LUT_IIR_SHIFT==0) iir=new_value;
            else if (new_value>=old_value) begin
                diff=new_value-old_value;
                iir=old_value+((diff+(1<<(LUT_IIR_SHIFT-1)))>>LUT_IIR_SHIFT);
            end else begin
                diff=old_value-new_value;
                iir=old_value-((diff+(1<<(LUT_IIR_SHIFT-1)))>>LUT_IIR_SHIFT);
            end
        end
    endfunction
    wire [7:0] new_map=first_map ? level : iir(old_map,level);

    // Four tile LUTs are used for bilinear interpolation. Each is read for
    // all four lanes; synthesis may replicate these small read-only-at-run
    // tables. Their only writes occur outside active video.
    function [8:0] xweight;
        input [XCW-1:0] x;
        reg [18:0] scaled;
        begin
            if (x<=WIDTH/4) xweight=0;
            else if (x>=3*WIDTH/4) xweight=256;
            // 273/1024 approximates 256/960 within 0.1 LSB at 1080p.
            else if (WIDTH==1920) begin
                scaled=(x-11'd480)*9'd273+19'd512;
                xweight=scaled[18:10];
            end
            else xweight=((x-WIDTH/4)*256)/(WIDTH/2);
        end
    endfunction
    function [8:0] yweight;
        input [YW-1:0] y;
        reg [18:0] scaled;
        begin
            if (y<=HEIGHT/4) yweight=0;
            else if (y>=3*HEIGHT/4) yweight=256;
            // 485/1024 approximates 256/540 within 0.3 LSB at 1080p.
            else if (HEIGHT==1080) begin
                scaled=(y-11'd270)*9'd485+19'd512;
                yweight=scaled[18:10];
            end
            else yweight=((y-HEIGHT/4)*256)/(HEIGHT/2);
        end
    endfunction
    function [7:0] blend;
        input [7:0] a,b;
        input [8:0] weight;
        reg signed [8:0] delta;
        reg signed [18:0] sum;
        begin
            // One signed multiply instead of two unsigned multiplies.
            delta=$signed({1'b0,b})-$signed({1'b0,a});
            sum=($signed({1'b0,a})<<<8)+delta*$signed({1'b0,weight})+19'sd128;
            blend=sum[15:8];
        end
    endfunction
    reg [7:0] p0_a[0:3],p0_b[0:3],p0_c[0:3],p0_d[0:3];
    reg [8:0] p0_wx[0:3],p0_wy;
    reg [31:0] p0_raw;
    reg p0_valid,p0_sof,p0_eol,p0_eq;
    reg [7:0] p1_top[0:3],p1_bottom[0:3];
    reg [8:0] p1_wy;
    reg [31:0] p1_raw;
    reg p1_valid,p1_sof,p1_eol,p1_eq;
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1) begin : g_lane
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                p0_a[lane]<=0;p0_b[lane]<=0;p0_c[lane]<=0;p0_d[lane]<=0;
                p0_wx[lane]<=0;p1_top[lane]<=0;p1_bottom[lane]<=0;
                m_gray[lane*8 +:8]<=0;
            end else begin
                p0_a[lane]<=lut00[s_gray[lane*8 +:8]];
                p0_b[lane]<=lut01[s_gray[lane*8 +:8]];
                p0_c[lane]<=lut10[s_gray[lane*8 +:8]];
                p0_d[lane]<=lut11[s_gray[lane*8 +:8]];
                p0_wx[lane]<=xweight(pixel_beat_x*4+lane);
                p1_top[lane]<=blend(p0_a[lane],p0_b[lane],p0_wx[lane]);
                p1_bottom[lane]<=blend(p0_c[lane],p0_d[lane],p0_wx[lane]);
                m_gray[lane*8 +:8]<=p1_eq ?
                    blend(p1_top[lane],p1_bottom[lane],p1_wy) :
                    p1_raw[lane*8 +:8];
            end
        end
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=CLEAR; clear_addr<=0; hist_addr<=0; bin<=0; tile<=0;
            beat_x<=0; row_y<=0; beat_count<=0;
            pending_valid<=0; last_write<=0;
            pending_addr0<=0;pending_addr1<=0;pending_addr2<=0;pending_addr3<=0;
            last_addr0<=0;last_addr1<=0;last_addr2<=0;last_addr3<=0;
            last_value0<=0;last_value1<=0;last_value2<=0;last_value3<=0;
            excess<=0;cdf<=0;extra_quotient<=0;extra_remainder<=0;
            adjusted<=0;target<=0;threshold<=0;level<=0;old_map<=0;
            first_map<=1;lut_active<=0;frame_use_lut<=0;
            hist_frames<=0;hist_errors<=0;
            p0_valid<=0;p0_sof<=0;p0_eol<=0;p0_eq<=0;p0_raw<=0;p0_wy<=0;
            p1_valid<=0;p1_sof<=0;p1_eol<=0;p1_eq<=0;p1_raw<=0;p1_wy<=0;
            m_valid<=0;m_sof<=0;m_eol<=0;
        end else begin
            p0_valid<=s_valid; p0_sof<=s_valid&&s_sof;
            p0_eol<=s_valid&&s_eol;
            p0_eq<=s_sof ? (enable && lut_active && state==WAIT_SOF) : frame_use_lut;
            p0_raw<=s_gray;
            p0_wy<=yweight(pixel_row_y);
            p1_valid<=p0_valid;p1_sof<=p0_sof;p1_eol<=p0_eol;
            p1_eq<=p0_eq;p1_raw<=p0_raw;p1_wy<=p0_wy;
            m_valid<=p1_valid;m_sof<=p1_sof;m_eol<=p1_eol;
            if (s_valid && s_sof) begin
                frame_use_lut<=enable && lut_active && state==WAIT_SOF;
            end
            if (s_valid) begin
                beat_x<=s_eol ? 0 : pixel_beat_x+1'b1;
                row_y<=s_sof ? 0 : (s_eol ? row_y+1'b1 : row_y);
            end
            if (capture) begin
                pending_addr0<=addr0;pending_addr1<=addr1;
                pending_addr2<=addr2;pending_addr3<=addr3;
            end
            pending_valid<=capture;
            last_write<=pending_valid && state!=CLEAR && state!=CLEAR_HIST;
            if (pending_valid && state!=CLEAR && state!=CLEAR_HIST) begin
                last_addr0<=pending_addr0;last_addr1<=pending_addr1;
                last_addr2<=pending_addr2;last_addr3<=pending_addr3;
                last_value0<=next0;last_value1<=next1;
                last_value2<=next2;last_value3<=next3;
            end
            case (state)
                CLEAR: if (clear_addr==1023) begin
                    clear_addr<=0;state<=WAIT_SOF;
                end else clear_addr<=clear_addr+1'b1;
                WAIT_SOF: if (s_valid && s_sof) begin
                    beat_count<=1;beat_x<=1;row_y<=0;state<=CAPTURE;
                end
                CAPTURE: if (s_valid) begin
                    if (s_sof || (s_eol != (beat_x==WIDTH/4-1))) begin
                        clear_addr<=0;state<=CLEAR;
                        hist_errors<=hist_errors+1'b1;
                    end else if (beat_count==FRAME_BEATS-1) begin
                        state<=DRAIN;beat_count<=0;
                    end else beat_count<=beat_count+1'b1;
                end
                DRAIN: begin
                    hist_frames<=hist_frames+1'b1;
                    tile<=0;bin<=0;excess<=0;
                    hist_addr<=0;state<=READ_HIST;
                end
                READ_HIST: state<=CLEAR_HIST;
                CLEAR_HIST: state<=CLIP_BIN;
                CLIP_BIN: begin
                    clipped[bin]<=capped;
                    excess<=excess+(hist_sum-capped);
                    if (bin==255) state<=PREP_MAP;
                    else begin
                        bin<=bin+1'b1;hist_addr<={tile,bin+1'b1};
                        state<=READ_HIST;
                    end
                end
                PREP_MAP: begin
                    extra_quotient<=excess>>8;
                    extra_remainder<=excess;
                    cdf<=0;threshold<=TILE_PIXELS;level<=0;
                    bin<=0;state<=READ_CLIP;
                end
                READ_CLIP: begin
                    clipped_read<=clipped[bin];
                    old_map<=previous_map[{tile,bin}];
                    state<=CALC_MAP;
                end
                CALC_MAP: begin
                    cdf<=cdf_next;
                    target<=({8'd0,cdf_next}<<8)-{8'd0,cdf_next};
                    state<=FIND_LEVEL;
                end
                FIND_LEVEL: begin
                    if (level!=255 && target>=threshold) begin
                        level<=level+1'b1;threshold<=threshold+TILE_PIXELS;
                    end else state<=WRITE_MAP;
                end
                WRITE_MAP: begin
                    previous_map[{tile,bin}]<=new_map;
                    case (tile)
                        0:lut00[bin]<=new_map;
                        1:lut01[bin]<=new_map;
                        2:lut10[bin]<=new_map;
                        3:lut11[bin]<=new_map;
                    endcase
                    if (bin==255) begin
                        if (tile==3) begin
                            first_map<=0;lut_active<=1;state<=WAIT_SOF;
                        end else begin
                            tile<=tile+1'b1;bin<=0;excess<=0;
                            hist_addr<={tile+1'b1,8'd0};state<=READ_HIST;
                        end
                    end else begin
                        bin<=bin+1'b1;state<=READ_CLIP;
                    end
                end
                default: begin state<=CLEAR;clear_addr<=0; end
            endcase
            if (s_valid && s_sof && state!=WAIT_SOF && state!=CAPTURE)
                hist_errors<=hist_errors+1'b1;
        end
    end
endmodule
