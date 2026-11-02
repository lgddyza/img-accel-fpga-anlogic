`timescale 1ns/1ps

// Four pixels per camera clock. Modes 0..3 retain Gaussian/CLAHE selection;
// Modes 4/5 bypass CLAHE; 6/7 apply CLAHE after Sobel/blackhat.
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
    input  wire [2:0]   mode,
    output wire [127:0] m_rgb_gray,
    output wire         m_valid,
    output wire         m_sof,
    output wire         m_eol,
    output wire         gauss_overrun,
    output wire [2:0]   applied_mode,
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
    reg [2:0] frame_mode;
    assign applied_mode = frame_mode;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gray4<=0; gray_valid<=0; gray_sof<=0; gray_eol<=0;
            frame_mode<=3'd3;
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
    wire [287:0] neighborhood;
    wire gauss_fault;
    gray_gauss4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_gauss (
        .clk(clk),.rst_n(rst_n),.s_gray(gray4),
        .s_valid(gray_valid),.s_sof(gray_sof),.s_eol(gray_eol),
        .m_center(center4),.m_gauss(gauss4),
        .m_window(neighborhood),
        .m_valid(gauss_valid),.m_sof(gauss_sof),.m_eol(gauss_eol),
        .m_overrun(gauss_fault)
    );
    wire [31:0] sobel4,blackhat4;
    wire sv,ss,se,bv,bs,be,blackhat_fault;
    wire choose_sobel=frame_mode==4 || frame_mode==6;
    wire choose_blackhat=frame_mode==5 || frame_mode==7;
    wire [31:0] selected4 = choose_blackhat ? blackhat4 : choose_sobel ? sobel4 :
        (frame_mode[0] ? gauss4 : center4);
    wire selected_valid=choose_blackhat ? bv : choose_sobel ? sv : gauss_valid;
    wire selected_sof=choose_blackhat ? bs : choose_sobel ? ss : gauss_sof;
    wire selected_eol=choose_blackhat ? be : choose_sobel ? se : gauss_eol;
    wire [31:0] equalized4;
    wire lut_active;
    wire legacy_valid,legacy_sof,legacy_eol;
    // 2x2 tiled CLAHE with clipping, bilinear interpolation and temporal LUT IIR.
    gray_clahe4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.LUT_IIR_SHIFT(2)) u_hist (
        .clk(clk),.rst_n(rst_n),.s_gray(selected4),
        .s_valid(selected_valid),.s_sof(selected_sof),.s_eol(selected_eol),
        .enable(frame_mode[1]),
        .m_gray(equalized4),.m_valid(legacy_valid),
        .m_sof(legacy_sof),.m_eol(legacy_eol),
        .lut_active(lut_active),.hist_frames(hist_frames),
        .hist_errors(hist_errors)
    );
    gray_sobel_guided4 u_sobel(.clk(clk),.rst_n(rst_n),.s_window(neighborhood),
        .s_valid(gauss_valid),.s_sof(gauss_sof),.s_eol(gauss_eol),
        .m_gray(sobel4),.m_valid(sv),.m_sof(ss),.m_eol(se));
    gray_blackhat4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_blackhat(
        .clk(clk),.rst_n(rst_n),.s_window(neighborhood),.s_gray(center4),
        .s_valid(gauss_valid),.s_sof(gauss_sof),.s_eol(gauss_eol),.m_gray(blackhat4),
        .m_valid(bv),.m_sof(bs),.m_eol(be),.fault(blackhat_fault));
    // Frame blanking drains all branches before the next SOF changes mode.
    // Select markers with pixels; legacy modes keep their original latency.
    wire [31:0] output4=equalized4;
    assign m_valid=legacy_valid;
    assign m_sof=legacy_sof;
    assign m_eol=legacy_eol;
    localparam FRAME_BEATS=(WIDTH/4)*HEIGHT;
    reg [$clog2(FRAME_BEATS)-1:0] blackhat_count;
    reg branches_busy,frame_overlap;
    wire branches_done=bv && blackhat_count==FRAME_BEATS-1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin blackhat_count<=0;branches_busy<=0;frame_overlap<=0;end
        else begin
            if(bv) blackhat_count<=branches_done ? 0 : blackhat_count+1'b1;
            if(s_valid && s_sof) begin
                if(branches_busy && !branches_done) frame_overlap<=1;
                branches_busy<=1;
            end else if(branches_done) branches_busy<=0;
        end
    end
    assign gauss_overrun=gauss_fault|blackhat_fault|frame_overlap;
    genvar lane;
    generate for (lane=0;lane<4;lane=lane+1) begin : g_rgb
        wire [7:0] y = output4[lane*8 +: 8];
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

// Enhancement definitions live in this registered TD source so GUI source-list
// saves cannot drop them. The standalone enhancement paths are compatibility stubs.
`timescale 1ns/1ps

// Small alignment queues use LUT RAM to preserve scarce ERAM for line stores.
module gray_align_queue #(
    parameter integer BITS=32, DEPTH=2048
)(
    input wire clk,rst_n,push,pop,
    input wire [BITS-1:0] s_data,
    output wire [BITS-1:0] head,
    output reg fault
);
    localparam AW=$clog2(DEPTH), CW=$clog2(DEPTH+1);
    reg [BITS-1:0] memory[0:DEPTH-1]; /* fehdl force_ram=1, ram_style="dram" */
    reg [AW-1:0] wr,rd;
    reg [CW-1:0] count;
    assign head=memory[rd];
    wire take=pop && count!=0;
    wire put=push && (count<DEPTH || take);
    always @(posedge clk) if(put) memory[wr]<=s_data;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin wr<=0;rd<=0;count<=0;fault<=0;end
        else begin
            if((push && !put)||(pop && !take)) fault<=1;
            if(put) wr<=(wr==DEPTH-1)?0:wr+1'b1;
            if(take) rd<=(rd==DEPTH-1)?0:rd+1'b1;
            case({put,take})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:count<=count;
            endcase
        end
    end
endmodule

// Centered KxK neighborhoods, four pixels/clock, replicated image borders.
// Each byte plane has independent RAM style; no frame buffer or ready signal.
module gray_window4 #(
    parameter integer WIDTH=1920,HEIGHT=1080,K=7,PIX_BITS=8,
    parameter integer DRAM_MASK=0
)(
    input wire clk,rst_n,
    input wire [4*PIX_BITS-1:0] s_data,
    input wire s_valid,s_sof,s_eol,
    output reg [4*K*K*PIX_BITS-1:0] m_window,
    output reg m_valid,m_sof,m_eol,
    output reg fault
);
    localparam B=WIDTH/4,R=K/2,XW=$clog2(B),YW=$clog2(HEIGHT+K+1);
    reg [XW-1:0] input_x,pad_x,q_x,prev_x;
    reg [YW-1:0] input_y,pad_y,q_y,prev_y;
    reg padding,q_valid,q_padding,prev_valid;
    reg [15:0] gap_count,line_gap,pad_wait;
    wire [XW-1:0] x=s_sof ? {XW{1'b0}} : input_x;
    wire [YW-1:0] y=s_sof ? {YW{1'b0}} : input_y;
    wire [XW-1:0] addr=padding ? pad_x : x;
    wire step=padding ? pad_wait==0 : s_valid;
    wire [4*PIX_BITS-1:0] rows[0:K-1];
    genvar p,l;
    generate for(p=0;p<PIX_BITS/8;p=p+1) begin:g_plane
        wire [31:0] delayed[0:K-2];
        wire [31:0] packed_input={s_data[3*PIX_BITS+p*8+:8],s_data[2*PIX_BITS+p*8+:8],
                                 s_data[PIX_BITS+p*8+:8],s_data[p*8+:8]};
        reg [31:0] input_delayed;
        wire [31:0] newest=q_padding ? delayed[0] : input_delayed;
        for(l=0;l<K-1;l=l+1) begin:g_line
            wire [31:0] store_data;
            if(l==0) begin:g_first
                assign store_data=input_delayed;
            end else begin:g_later
                assign store_data=delayed[l-1];
            end
            if((DRAM_MASK>>p)&1) begin:g_dram
                reg [31:0] mem[0:B-1]; /* fehdl force_ram=1, ram_style="dram" */
                reg [31:0] q;
                assign delayed[l]=q;
                always @(posedge clk) begin
                    if(step) q<=mem[addr];
                    if(q_valid && (!q_padding || l!=0)) mem[q_x]<=store_data;
                end
            end else begin:g_bram
                reg [31:0] mem[0:B-1]; /* fehdl force_ram=1, ram_style="bram" */
                reg [31:0] q;
                assign delayed[l]=q;
                // Registered read data also feeds the following line's write
                // on the next cycle, preserving synchronous ERAM inference.
                always @(posedge clk) begin
                    if(step) q<=mem[addr];
                    if(q_valid && (!q_padding || l!=0)) mem[q_x]<=store_data;
                end
            end
        end
        always @(posedge clk) if(step) begin
            input_delayed<=packed_input;
        end
        for(l=0;l<4;l=l+1) begin:g_row_unpack
            assign rows[K-1][l*PIX_BITS+p*8+:8]=newest[l*8+:8];
            genvar r;
            for(r=0;r<K-1;r=r+1) begin:g_old_row
                assign rows[r][l*PIX_BITS+p*8+:8]=delayed[K-2-r][l*8+:8];
            end
        end
    end endgenerate
    reg [4*PIX_BITS-1:0] prev[0:K-1],left[0:K-1];
    wire same_row=q_valid && prev_valid && q_y==prev_y && q_x==prev_x+1'b1;
    wire emit=prev_valid && prev_y>=R && prev_y<HEIGHT+R &&
              (q_valid || prev_x==B-1);
    integer rr,cc,lane,col,norm;
    reg [PIX_BITS-1:0] sample;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            input_x<=0;input_y<=0;pad_x<=0;pad_y<=HEIGHT;padding<=0;
            q_x<=0;q_y<=0;q_valid<=0;q_padding<=0;prev_x<=0;prev_y<=0;prev_valid<=0;
            m_window<=0;m_valid<=0;m_sof<=0;m_eol<=0;fault<=0;
            gap_count<=0;line_gap<=0;pad_wait<=0;
            for(rr=0;rr<K;rr=rr+1) begin prev[rr]<=0;left[rr]<=0;end
        end else begin
            q_valid<=step;
            if(step) q_padding<=padding;
            // Upstream horizontal lookahead can move row blanking before EOL.
            // Measure all within-frame gaps, not only the EOL-to-next-row gap.
            if(s_valid && s_sof) begin line_gap<=0;gap_count<=0;end
            else if(s_valid) begin
                if(gap_count>line_gap) line_gap<=gap_count;
                gap_count<=0;
            end
            else if(gap_count!=16'hffff)
                gap_count<=gap_count+1'b1;
            if(padding) begin
                if(s_valid) fault<=1;
                if(pad_wait!=0) pad_wait<=pad_wait-1'b1;
                else begin
                    q_x<=pad_x;q_y<=pad_y;
                    if(pad_x==B-1) begin
                        pad_x<=0;
                        if(pad_y==HEIGHT+R-1) padding<=0;
                        else begin pad_y<=pad_y+1'b1;pad_wait<=line_gap;end
                    end else pad_x<=pad_x+1'b1;
                end
            end else if(s_valid) begin
                q_x<=x;q_y<=y;input_y<=y;
                if(s_eol != (x==B-1)) fault<=1;
                if(s_eol) begin
                    input_x<=0;input_y<=y+1'b1;
                    if(y==HEIGHT-1) begin
                        padding<=1;pad_x<=0;pad_y<=HEIGHT;pad_wait<=line_gap;
                    end
                end else input_x<=x+1'b1;
            end
            m_valid<=emit;m_sof<=emit && prev_y==R && prev_x==0;
            m_eol<=emit && prev_x==B-1;
            if(emit) begin
                for(lane=0;lane<4;lane=lane+1)
                    for(rr=0;rr<K;rr=rr+1)
                        for(cc=0;cc<K;cc=cc+1) begin
                            col=lane+cc-R;
                            if(col<0) sample=(prev_x==0) ? prev[rr][0+:PIX_BITS] :
                                                          left[rr][(4+col)*PIX_BITS+:PIX_BITS];
                            else if(col>=4) begin
                                norm=(q_y<K-1 && rr<K-1-q_y) ? K-1-q_y : rr;
                                sample=same_row ? rows[norm][(col-4)*PIX_BITS+:PIX_BITS] :
                                                  prev[rr][3*PIX_BITS+:PIX_BITS];
                            end else sample=prev[rr][col*PIX_BITS+:PIX_BITS];
                            m_window[((lane*K*K+rr*K+cc)*PIX_BITS)+:PIX_BITS]<=sample;
                        end
            end
            if(q_valid) begin
                for(rr=0;rr<K;rr=rr+1) begin
                    left[rr]<=prev[rr];
                    norm=(q_y<K-1 && rr<K-1-q_y) ? K-1-q_y : rr;
                    prev[rr]<=rows[norm];
                end
                prev_x<=q_x;prev_y<=q_y;prev_valid<=1;
            end else if(emit) prev_valid<=0;
        end
    end
endmodule

// Balanced comparisons keep every reduction at ceil(log2(K)) levels.
module gray_extreme #(
    parameter integer K=7,MAXIMUM=1
)(input wire [K*8-1:0] s_data,output wire [7:0] m_data);
    localparam N=2**$clog2(K);
    wire [7:0] tree[0:2*N-2];
    genvar j;
    generate
        for(j=0;j<N;j=j+1) begin:g_leaf
            assign tree[N-1+j]=s_data[((j<K)?j:K-1)*8+:8];
        end
        for(j=0;j<N-1;j=j+1) begin:g_node
            assign tree[j]=MAXIMUM ?
                ((tree[2*j+1]>tree[2*j+2])?tree[2*j+1]:tree[2*j+2]) :
                ((tree[2*j+1]<tree[2*j+2])?tree[2*j+1]:tree[2*j+2]);
        end
    endgenerate
    assign m_data=tree[0];
endmodule

// Horizontal morphology is performed before the vertical line buffers.
module gray_horizontal4 #(
    parameter integer WIDTH=1920,K=7,MAXIMUM=1
)(
    input wire clk,rst_n,
    input wire [31:0] s_data,
    input wire s_valid,s_sof,s_eol,
    output reg [31:0] m_data,
    output reg m_valid,m_sof,m_eol
);
    reg [31:0] prev,left;
    reg prev_valid,prev_sof,prev_eol,first;
    wire emit=prev_valid && (s_valid || prev_eol);
    wire [31:0] reduced;
    genvar lane,j;
    generate for(lane=0;lane<4;lane=lane+1) begin:g_reduce
        wire [K*8-1:0] samples;
        for(j=0;j<K;j=j+1) begin:g_sample
            localparam C=lane+j-K/2;
            if(C<0) assign samples[j*8+:8]=first ? prev[7:0] : left[(4+C)*8+:8];
            else if(C>=4) assign samples[j*8+:8]=prev_eol ? prev[31:24] : s_data[(C-4)*8+:8];
            else assign samples[j*8+:8]=prev[C*8+:8];
        end
        gray_extreme #(.K(K),.MAXIMUM(MAXIMUM)) u_reduce(
            .s_data(samples),.m_data(reduced[lane*8+:8]));
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            prev<=0;left<=0;prev_valid<=0;prev_sof<=0;prev_eol<=0;first<=1;
            m_data<=0;m_valid<=0;m_sof<=0;m_eol<=0;
        end else begin
            m_valid<=emit;m_sof<=emit && prev_sof;m_eol<=emit && prev_eol;
            if(emit) m_data<=reduced;
            if(s_valid) begin
                left<=prev;prev<=s_data;prev_valid<=1;
                prev_sof<=s_sof;prev_eol<=s_eol;
                first<=s_sof || !prev_valid || prev_eol;
            end else if(emit) prev_valid<=0;
        end
    end
endmodule

module gray_rect_morph4 #(
    parameter integer WIDTH=1920,HEIGHT=1080,K=7,MAXIMUM=1
)(
    input wire clk,rst_n,
    input wire [31:0] s_data,
    input wire s_valid,s_sof,s_eol,
    output reg [31:0] m_data,
    output reg m_valid,m_sof,m_eol,
    output wire fault
);
    wire [31:0] horizontal;
    wire hv,hs,he,wv,ws,we;
    wire [4*K*K*8-1:0] window;
    gray_horizontal4 #(.WIDTH(WIDTH),.K(K),.MAXIMUM(MAXIMUM)) u_horizontal(
        .clk(clk),.rst_n(rst_n),.s_data(s_data),.s_valid(s_valid),.s_sof(s_sof),.s_eol(s_eol),
        .m_data(horizontal),.m_valid(hv),.m_sof(hs),.m_eol(he));
    gray_window4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.K(K)) u_vertical(
        .clk(clk),.rst_n(rst_n),.s_data(horizontal),.s_valid(hv),.s_sof(hs),.s_eol(he),
        .m_window(window),.m_valid(wv),.m_sof(ws),.m_eol(we),.fault(fault));
    wire [31:0] reduced;
    genvar lane,r;
    generate for(lane=0;lane<4;lane=lane+1) begin:g_reduce
        wire [K*8-1:0] samples;
        for(r=0;r<K;r=r+1) begin:g_sample
            assign samples[r*8+:8]=window[(lane*K*K+r*K+K/2)*8+:8];
        end
        gray_extreme #(.K(K),.MAXIMUM(MAXIMUM)) u_reduce(
            .s_data(samples),.m_data(reduced[lane*8+:8]));
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin m_data<=0;m_valid<=0;m_sof<=0;m_eol<=0;end
        else begin
            m_valid<=wv;m_sof<=ws;m_eol<=we;
            m_data<=reduced;
        end
    end
endmodule

module gray_direction_open4 #(
    parameter integer WIDTH=1920,HEIGHT=1080
)(
    input wire clk,rst_n,
    input wire [31:0] s_data,
    input wire s_valid,s_sof,s_eol,
    output reg [31:0] m_data,
    output reg m_valid,m_sof,m_eol,
    output wire fault
);
    wire [799:0] w0;
    wire v0,s0,e0,f0;
    gray_window4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.K(5)) u_erode_window(
        .clk(clk),.rst_n(rst_n),.s_data(s_data),.s_valid(s_valid),.s_sof(s_sof),.s_eol(s_eol),
        .m_window(w0),.m_valid(v0),.m_sof(s0),.m_eol(e0),.fault(f0));
    reg [127:0] eroded;
    reg ev,es,ee;
    wire [3199:0] w1;
    wire v1,s1,e1,f1;
    wire [127:0] erode_values,dilate_values;
    wire [31:0] merged_values;
    reg [127:0] dilated;
    reg dv,ds,de;
    genvar lane,d,j;
    generate for(lane=0;lane<4;lane=lane+1) begin:g_lane
        for(d=0;d<4;d=d+1) begin:g_direction
            wire [39:0] esamples,dsamples;
            for(j=0;j<5;j=j+1) begin:g_sample
                localparam R=(d==0)?2:j;
                localparam C=(d==1)?2:((d==3)?4-j:j);
                assign esamples[j*8+:8]=w0[(lane*25+R*5+C)*8+:8];
                assign dsamples[j*8+:8]=w1[(lane*25+R*5+C)*32+d*8+:8];
            end
            gray_extreme #(.K(5),.MAXIMUM(0)) u_erode(
                .s_data(esamples),.m_data(erode_values[lane*32+d*8+:8]));
            gray_extreme #(.K(5),.MAXIMUM(1)) u_dilate(
                .s_data(dsamples),.m_data(dilate_values[lane*32+d*8+:8]));
        end
        gray_extreme #(.K(4),.MAXIMUM(1)) u_merge(
            .s_data(dilated[lane*32+:32]),.m_data(merged_values[lane*8+:8]));
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin eroded<=0;ev<=0;es<=0;ee<=0;end
        else begin
            ev<=v0;es<=s0;ee<=e0;
            eroded<=erode_values;
        end
    end
    // Horizontal/vertical planes use LUT RAM; diagonal planes use ERAM.
    gray_window4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.K(5),.PIX_BITS(32),.DRAM_MASK(3)) u_dilate_window(
        .clk(clk),.rst_n(rst_n),.s_data(eroded),.s_valid(ev),.s_sof(es),.s_eol(ee),
        .m_window(w1),.m_valid(v1),.m_sof(s1),.m_eol(e1),.fault(f1));
    // Direction dilation and four-way merge occupy separate clock stages.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            dilated<=0;dv<=0;ds<=0;de<=0;
            m_data<=0;m_valid<=0;m_sof<=0;m_eol<=0;
        end
        else begin
            dilated<=dilate_values;dv<=v1;ds<=s1;de<=e1;
            m_valid<=dv;m_sof<=ds;m_eol<=de;
            m_data<=merged_values;
        end
    end
    assign fault=f0|f1;
endmodule

module gray_blackhat4 #(
    parameter integer WIDTH=1920,HEIGHT=1080
)(
    input wire clk,rst_n,
    input wire [287:0] s_window,
    input wire [31:0] s_gray,
    input wire s_valid,s_sof,s_eol,
    output reg [31:0] m_gray,
    output reg m_valid,m_sof,m_eol,
    output wire fault
);
    wire [31:0] dilated,closed,raw_closed,raw_final,directional;
    wire dv,ds,de,cv,cs,ce,ov,os,oe,f0,f1,f2,f3,f4;
    wire [31:0] max_values;
    reg [31:0] dilated_reg;
    reg dilated_valid,dilated_sof,dilated_eol;
    genvar max_lane;
    generate for(max_lane=0;max_lane<4;max_lane=max_lane+1) begin:g_shared_max
        gray_extreme #(.K(9),.MAXIMUM(1)) u_max(
            .s_data(s_window[max_lane*72+:72]),.m_data(max_values[max_lane*8+:8]));
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin dilated_reg<=0;dilated_valid<=0;dilated_sof<=0;dilated_eol<=0;end
        else begin
            dilated_reg<=max_values;dilated_valid<=s_valid;
            dilated_sof<=s_sof;dilated_eol<=s_eol;
        end
    end
    assign dilated=dilated_reg;assign dv=dilated_valid;
    assign ds=dilated_sof;assign de=dilated_eol;assign f0=1'b0;
    gray_rect_morph4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.K(3),.MAXIMUM(0)) u_close_min(
        .clk(clk),.rst_n(rst_n),.s_data(dilated),.s_valid(dv),.s_sof(ds),.s_eol(de),
        .m_data(closed),.m_valid(cv),.m_sof(cs),.m_eol(ce),.fault(f1));
    gray_align_queue #(.DEPTH(2*(WIDTH/4)+64)) u_close_raw(
        .clk(clk),.rst_n(rst_n),.push(s_valid),.pop(cv),.s_data(s_gray),.head(raw_closed),.fault(f2));
    reg [31:0] response,original;
    reg bv,bs,be;
    integer lane;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin response<=0;original<=0;bv<=0;bs<=0;be<=0;end
        else begin
            bv<=cv;bs<=cs;be<=ce;original<=raw_closed;
            for(lane=0;lane<4;lane=lane+1)
                response[lane*8+:8]<=(closed[lane*8+:8]>raw_closed[lane*8+:8]) ?
                    closed[lane*8+:8]-raw_closed[lane*8+:8] : 0;
        end
    end
    gray_direction_open4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_direction(
        .clk(clk),.rst_n(rst_n),.s_data(response),.s_valid(bv),.s_sof(bs),.s_eol(be),
        .m_data(directional),.m_valid(ov),.m_sof(os),.m_eol(oe),.fault(f3));
    gray_align_queue #(.DEPTH(4*(WIDTH/4)+64)) u_final_raw(
        .clk(clk),.rst_n(rst_n),.push(bv),.pop(ov),.s_data(original),.head(raw_final),.fault(f4));
    function [7:0] full_subtract;
        input [7:0] raw,enhancement;
        begin
            full_subtract=(raw>enhancement)?raw-enhancement:0;
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin m_gray<=0;m_valid<=0;m_sof<=0;m_eol<=0;end
        else begin
            m_valid<=ov;m_sof<=os;m_eol<=oe;
            for(lane=0;lane<4;lane=lane+1)
                m_gray[lane*8+:8]<=full_subtract(raw_final[lane*8+:8],directional[lane*8+:8]);
        end
    end
    assign fault=f0|f1|f2|f3|f4;
endmodule

`timescale 1ns/1ps

// T=1, gain=0.5. Rational arithmetic retains the software formula's fractions.
// D9=clip(9*I-sum3x3,-288,288), W96=clip(|Gx|+|Gy|-8,0,96).
// Output=round_even(I+D9*W96/1728), saturated to eight bits.
module gray_sobel_guided4(
    input wire clk,rst_n,
    input wire [287:0] s_window,
    input wire s_valid,s_sof,s_eol,
    output wire [31:0] m_gray,
    output wire m_valid,m_sof,m_eol
);
    reg [4:0] valid_pipe,sof_pipe,eol_pipe;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin valid_pipe<=0;sof_pipe<=0;eol_pipe<=0;end
        else begin
            valid_pipe<={valid_pipe[3:0],s_valid};
            sof_pipe<={sof_pipe[3:0],s_valid && s_sof};
            eol_pipe<={eol_pipe[3:0],s_valid && s_eol};
        end
    end
    assign m_valid=valid_pipe[4];assign m_sof=sof_pipe[4];assign m_eol=eol_pipe[4];
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1) begin:g_lane
        wire [7:0] p[0:8];
        genvar j;
        for(j=0;j<9;j=j+1) begin:g_pixel
            assign p[j]=s_window[(lane*9+j)*8+:8];
        end
        reg signed [10:0] gx,gy;
        reg [11:0] sum;
        reg [7:0] raw0,raw1,raw2,raw3,result;
        reg signed [12:0] detail;
        reg [6:0] gate;
        reg signed [16:0] product;
        reg signed [19:0] numerator;
        wire [11:0] ax=gx<0 ? -gx : gx;
        wire [11:0] ay=gy<0 ? -gy : gy;
        wire [12:0] magnitude={1'b0,ax}+{1'b0,ay};
        wire signed [12:0] d9=$signed({1'b0,raw0})*13'sd9-$signed({1'b0,sum});
        function [7:0] quantize;
            input signed [19:0] n;
            reg [19:0] quotient,remainder;
            begin
                quotient=n/20'd1728;remainder=n%20'd1728;
                if(n<=0) quantize=0;
                else if(n>=20'sd440640) quantize=255;
                else quantize=quotient+((remainder>864 || (remainder==864 && quotient[0]))?1'b1:1'b0);
            end
        endfunction
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                gx<=0;gy<=0;sum<=0;raw0<=0;raw1<=0;raw2<=0;raw3<=0;
                detail<=0;gate<=0;product<=0;numerator<=0;result<=0;
            end else begin
                gx<=$signed({3'b0,p[2]})+($signed({3'b0,p[5]})<<<1)+$signed({3'b0,p[8]})-
                    $signed({3'b0,p[0]})-($signed({3'b0,p[3]})<<<1)-$signed({3'b0,p[6]});
                gy<=$signed({3'b0,p[6]})+($signed({3'b0,p[7]})<<<1)+$signed({3'b0,p[8]})-
                    $signed({3'b0,p[0]})-($signed({3'b0,p[1]})<<<1)-$signed({3'b0,p[2]});
                sum<={4'b0,p[0]}+{4'b0,p[1]}+{4'b0,p[2]}+{4'b0,p[3]}+{4'b0,p[4]}+
                     {4'b0,p[5]}+{4'b0,p[6]}+{4'b0,p[7]}+{4'b0,p[8]};
                raw0<=p[4];
                detail<=(d9>288)?13'sd288:((d9< -288)?-13'sd288:d9);
                gate<=(magnitude<=8)?0:((magnitude>=104)?96:magnitude-8);
                raw1<=raw0;
                product<=detail*$signed({1'b0,gate});raw2<=raw1;
                numerator<=$signed({1'b0,raw2})*20'sd1728+product;raw3<=raw2;
                result<=quantize(numerator);
            end
        end
        assign m_gray[lane*8+:8]=result;
    end endgenerate
endmodule
