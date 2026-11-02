`timescale 1ns/1ps

// PREF1: one luma conversion and shared K3 window for both camera frames.
// The observer tap precedes enhancement; no duplicated conversion or frame RAM.
module v2_dual_preprocess #(
    parameter integer WIDTH = 1920,
    parameter integer HEIGHT = 1080
)(
    input  wire         camera,
    input  wire         clk,
    input  wire         rst_n,
    input  wire [127:0] s_rgb,
    input  wire         s_valid,
    input  wire         s_sof,
    input  wire         s_eol,
    input  wire [2:0]   mode,
    input  wire [2:0]   strength,
    output wire [127:0] m_rgb_gray,
    output wire         m_valid,
    output wire         m_sof,
    output wire         m_eol,
    output wire         gauss_overrun,
    output wire [2:0]   applied_mode,
    output wire [31:0] hist_frames_a,hist_frames_b,
    output wire [31:0] hist_errors_a,hist_errors_b,
    output wire [127:0] observer_rgb,
    output wire observer_valid,observer_sof,observer_eol
);
    // Four pixels per clock, with multiplication separated from summation.
    // Arithmetic: (77R + 150G + 29B + 128) >> 8.
    reg [15:0] product_r[0:3],product_g[0:3],product_b[0:3];
    reg product_valid,product_sof,product_eol;
    reg [31:0] gray4;
    reg gray_valid,gray_sof,gray_eol;
    reg [2:0] frame_mode,frame_strength;
    reg frame_busy,overlap;
    wire [2:0] normalized_mode=(mode==1 || mode==2 || mode==3 || mode==4 || mode==5) ? mode : 3'd0;
    assign applied_mode=frame_mode;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin frame_mode<=0;frame_strength<=4;frame_busy<=0;overlap<=0;end
        else begin
            if(m_valid && m_eol && output_row==HEIGHT-1) frame_busy<=0;
            if(s_valid && s_sof) begin
                if(frame_busy) overlap<=1;
                frame_mode<=normalized_mode;
                frame_strength<=strength>4 ? 3'd4 : strength;
                frame_busy<=1;
            end
        end
    end
    genvar color_lane;
    generate for(color_lane=0;color_lane<4;color_lane=color_lane+1) begin:g_luma
        wire [15:0] sum_y=product_r[color_lane]+product_g[color_lane]+
                         product_b[color_lane]+16'd128;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                product_r[color_lane]<=0;product_g[color_lane]<=0;product_b[color_lane]<=0;
                gray4[color_lane*8+:8]<=0;
            end else begin
                product_r[color_lane]<=16'd77*s_rgb[color_lane*32+16+:8];
                product_g[color_lane]<=16'd150*s_rgb[color_lane*32+8+:8];
                product_b[color_lane]<=16'd29*s_rgb[color_lane*32+:8];
                gray4[color_lane*8+:8]<=sum_y[15:8];
            end
        end
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_valid<=0;product_sof<=0;product_eol<=0;
            gray_valid<=0; gray_sof<=0; gray_eol<=0;
        end else begin
            product_valid<=s_valid;
            product_sof<=s_valid && s_sof;
            product_eol<=s_valid && s_eol;
            gray_valid<=product_valid;
            gray_sof<=product_sof;
            gray_eol<=product_eol;
        end
    end
    assign observer_valid=gray_valid;
    assign observer_sof=gray_sof;
    assign observer_eol=gray_eol;
    wire [31:0] center4,gauss4,blackhat4,sobel4;
    wire [287:0] window4;
    wire gv,gs,ge,bv,bs,be,sv,ss,se,gfault,bfault;
    gray_gauss4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_window (
        .clk(clk),.rst_n(rst_n),.s_gray(gray4),
        .s_valid(gray_valid && (frame_mode==1 || frame_mode==3 || frame_mode==4 || frame_mode==5)),
        .s_sof(gray_sof && (frame_mode==1 || frame_mode==3 || frame_mode==4 || frame_mode==5)),
        .s_eol(gray_eol && (frame_mode==1 || frame_mode==3 || frame_mode==4 || frame_mode==5)),.m_center(center4),.m_gauss(gauss4),
        .m_window(window4),.m_valid(gv),.m_sof(gs),.m_eol(ge),.m_overrun(gfault));
    gray_sobel_guided4 u_sobel (
        .clk(clk),.rst_n(rst_n),.s_window(window4),
        .s_valid(gv && frame_mode==4),.s_sof(gs && frame_mode==4),.s_eol(ge && frame_mode==4),
        .m_gray(sobel4),.m_valid(sv),.m_sof(ss),.m_eol(se));
    gray_blackhat4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_blackhat (
        .clk(clk),.rst_n(rst_n),.s_window(window4),.s_gray(center4),
        .s_valid(gv && frame_mode==5),.s_sof(gs && frame_mode==5),
        .s_eol(ge && frame_mode==5),.m_gray(blackhat4),
        .m_valid(bv),.m_sof(bs),.m_eol(be),.fault(bfault));
    reg [31:0] mixed4;
    reg mv,ms,me;
    genvar mix_lane;
    generate for(mix_lane=0;mix_lane<4;mix_lane=mix_lane+1) begin:g_mix
        wire [9:0] raw={2'd0,center4[mix_lane*8+:8]};
        wire [9:0] filtered={2'd0,gauss4[mix_lane*8+:8]};
        reg [9:0] total;
        always @* case(frame_strength)
            0:total=raw<<2;
            1:total=(raw<<1)+raw+filtered;
            2:total=(raw+filtered)<<1;
            3:total=raw+(filtered<<1)+filtered;
            default:total=filtered<<2;
        endcase
        // Round to nearest, ties to even, matching the software alpha blend.
        wire [7:0] rounded=total[9:2]+(total[1] && (total[0] || total[2]));
        always @(posedge clk) mixed4[mix_lane*8+:8]<=rounded;
    end endgenerate
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin mv<=0;ms<=0;me<=0;end
        else begin mv<=gv;ms<=gs;me<=ge;end
    wire use_gauss=frame_mode==1 || frame_mode==3;
    wire [31:0] selected=frame_mode==5 ? blackhat4 : frame_mode==4 ? sobel4 : use_gauss ? mixed4 : gray4;
    wire selected_valid=frame_mode==5 ? bv : frame_mode==4 ? sv : use_gauss ? mv : gray_valid;
    wire selected_sof=frame_mode==5 ? bs : frame_mode==4 ? ss : use_gauss ? ms : gray_sof;
    wire selected_eol=frame_mode==5 ? be : frame_mode==4 ? se : use_gauss ? me : gray_eol;
    // Bound the enhancement mux before histogram RAM address/enable logic.
    reg [31:0] selected_q;
    reg selected_vq,selected_sq,selected_eq;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin selected_vq<=0;selected_sq<=0;selected_eq<=0;end
        else begin selected_vq<=selected_valid;selected_sq<=selected_sof;selected_eq<=selected_eol;end
    always @(posedge clk) selected_q<=selected;
    wire [31:0] mapped;
    wire mapped_valid,mapped_sof,mapped_eol;
    clahe_dual_prototype #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_clahe(
        .clk(clk),.rst_n(rst_n),.camera(camera),.mode(frame_mode),.strength(frame_strength),
        .gray(selected_q),.valid(selected_vq),.sof(selected_sq),.eol(selected_eq),
        .out(mapped),.out_valid(mapped_valid),.out_sof(mapped_sof),.out_eol(mapped_eol),
        .frames_a(hist_frames_a),.frames_b(hist_frames_b),.errors_a(hist_errors_a),.errors_b(hist_errors_b));
    reg [31:0] mapped_q;
    reg output_vq,output_sq,output_eq;
    always @(posedge clk) mapped_q<=mapped;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin output_vq<=0;output_sq<=0;output_eq<=0;end
        else begin output_vq<=mapped_valid;output_sq<=mapped_sof;output_eq<=mapped_eol;end
    assign m_valid=output_vq;assign m_sof=output_sq;assign m_eol=output_eq;
    reg [$clog2(HEIGHT+1)-1:0] output_row;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) output_row<=0;
        else if(m_valid && m_eol) output_row<=output_row==HEIGHT-1 ? 0 : output_row+1'b1;
    assign gauss_overrun=gfault|bfault|overlap;
    genvar lane;
    generate for (lane=0;lane<4;lane=lane+1) begin : g_rgb
        wire [7:0] y = mapped_q[lane*8 +: 8];
        wire [7:0] original=gray4[lane*8+:8];
        assign m_rgb_gray[lane*32 +: 32] = {8'd0,y,y,y};
        assign observer_rgb[lane*32+:32]={8'd0,original,original,original};
    end endgenerate
endmodule
`timescale 1ns/1ps
// Two independent cores keep each camera's histogram and mapping isolated.
module clahe_dual_prototype #(parameter WIDTH=64, HEIGHT=32)(
 input wire clk,rst_n,camera,input wire [2:0] mode,strength,
 input wire [31:0] gray,input wire valid,sof,eol,
 output wire [31:0] out,output wire out_valid,out_sof,out_eol,
 output wire [31:0] frames_a,frames_b,errors_a,errors_b
);
 reg [5:0] signature[0:1]; reg [1:0] known, accept_frame;
 reg [1:0] reset_core;
 wire enabled=(mode==2 || mode==3);
 wire [5:0] key={mode,(mode==3 ? strength : 3'd0)};
 wire changed=!known[camera] || signature[camera]!=key;
 wire [1:0] input_ready;
 wire accept = enabled && (sof ? (!changed && input_ready[camera]) : accept_frame[camera]);
 always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin known<=0;accept_frame<=0;reset_core<=0;signature[0]<=0;signature[1]<=0;end
   else begin
     reset_core<=0;
     if(valid && sof) begin
       signature[camera]<=key;known[camera]<=1;
       accept_frame[camera]<=enabled && !changed && input_ready[camera];
       if(changed) reset_core[camera]<=1;
     end
   end
 end
 wire [31:0] eq[0:1]; wire [1:0] ev,es,ee,ready;
 wire [31:0] counts[0:1], errs[0:1];
 assign frames_a=counts[0];assign frames_b=counts[1];
 assign errors_a=errs[0];assign errors_b=errs[1];
 genvar c;
 generate for(c=0;c<2;c=c+1) begin:g
   gray_clahe4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) core(
    .clk(clk),.rst_n(rst_n && !reset_core[c]),.s_gray(gray),
    .s_valid(valid && camera==c && accept),.s_sof(sof),.s_eol(eol),.enable(1'b1),
    .m_gray(eq[c]),.m_valid(ev[c]),.m_sof(es[c]),.m_eol(ee[c]),.lut_active(ready[c]),
    .hist_frames(counts[c]),.hist_errors(errs[c]),.input_ready(input_ready[c]));
 end endgenerate
 reg [31:0] raw0,raw1,raw2;
 reg [2:0] vpipe,spipe,epipe,cam_pipe,accepted_pipe;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin vpipe<=0;spipe<=0;epipe<=0;cam_pipe<=0;accepted_pipe<=0;raw0<=0;raw1<=0;raw2<=0;end
  else begin
   raw0<=gray;raw1<=raw0;raw2<=raw1;
   vpipe<={vpipe[1:0],valid};spipe<={spipe[1:0],valid&&sof};epipe<={epipe[1:0],valid&&eol};
   cam_pipe<={cam_pipe[1:0],camera};accepted_pipe<={accepted_pipe[1:0],accept};
  end
 end
 assign out_valid=vpipe[2];assign out_sof=spipe[2];assign out_eol=epipe[2];
 assign out=accepted_pipe[2] ? eq[cam_pipe[2]] : raw2;
endmodule
