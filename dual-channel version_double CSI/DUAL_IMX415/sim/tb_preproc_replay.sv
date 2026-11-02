`timescale 1ns/1ps
module tb_preproc_replay;
    localparam W=32,H=16,B=W/4,N=17,PIX=W*H;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,valid=0,sof=0,eol=0;
    reg [2:0] mode=0,ref_mode=0;
    reg [127:0] rgb=0;
    wire [127:0] result;
    wire ov,os,oe,fault;
    wire [2:0] applied;
    wire [31:0] hf,he;
    reg [7:0] input_pixels[0:N*PIX-1],golden[0:N*PIX-1];
    reg [2:0] modes[0:N-1];
    reg [7:0] legacy[0:N*PIX-1];
    integer seen=0,ref_seen=0,frame,tx,ty,j,idx,gap,cycle=0;
    gray_preprocess4 #(.WIDTH(W),.HEIGHT(H)) dut(
        .clk(clk),.rst_n(rst_n),.s_rgb(rgb),.s_valid(valid),.s_sof(sof),.s_eol(eol),.mode(mode),
        .m_rgb_gray(result),.m_valid(ov),.m_sof(os),.m_eol(oe),.gauss_overrun(fault),
        .applied_mode(applied),.hist_frames(hf),.hist_errors(he));
    wire [31:0] raw={rgb[103:96],rgb[71:64],rgb[39:32],rgb[7:0]};
    reg [31:0] ref_gray=0;
    reg rv=0,rs=0,re=0;
    always @(posedge clk) begin
        ref_gray<=raw;rv<=valid;rs<=valid&&sof;re<=valid&&eol;
        if(valid&&sof) ref_mode<=mode;
    end
    wire [31:0] rc,rg,ref_result;
    wire gv,gs,ge,gf,lv,ls,le,la;
    wire [31:0] lhf,lhe;
    gray_gauss4 #(.WIDTH(W),.HEIGHT(H)) reference_gaussian(
        .clk(clk),.rst_n(rst_n),.s_gray(ref_gray),.s_valid(rv),.s_sof(rs),.s_eol(re),
        .m_center(rc),.m_gauss(rg),.m_valid(gv),.m_sof(gs),.m_eol(ge),.m_overrun(gf));
    wire ref_sobel=ref_mode==4 || ref_mode==6;
    wire ref_blackhat=ref_mode==5 || ref_mode==7;
    wire ref_v=ref_blackhat ? dut.bv : ref_sobel ? dut.sv : gv;
    wire ref_s=ref_blackhat ? dut.bs : ref_sobel ? dut.ss : gs;
    wire ref_e=ref_blackhat ? dut.be : ref_sobel ? dut.se : ge;
    integer ref_input_seen=0;
    wire [31:0] expected_enhanced={golden[ref_input_seen*4+3],golden[ref_input_seen*4+2],
                                 golden[ref_input_seen*4+1],golden[ref_input_seen*4]};
    always @(posedge clk) if(rst_n && ref_v) ref_input_seen<=ref_input_seen+1;
    gray_clahe4 #(.WIDTH(W),.HEIGHT(H),.LUT_IIR_SHIFT(2)) reference_clahe(
        .clk(clk),.rst_n(rst_n),.s_gray(ref_mode>=4 ? expected_enhanced : (ref_mode[0]?rg:rc)),
        .s_valid(ref_v),.s_sof(ref_s),.s_eol(ref_e),.enable(ref_mode[1]),
        .m_gray(ref_result),.m_valid(lv),.m_sof(ls),.m_eol(le),.lut_active(la),
        .hist_frames(lhf),.hist_errors(lhe));
    integer lane,expected,current_frame,at;
    always @(negedge clk) if(rst_n) begin
        cycle=cycle+1;
        if(cycle>300000) $fatal(1,"timeout seen=%0d",seen);
        if(lv) begin
            for(lane=0;lane<4;lane=lane+1) legacy[ref_seen*4+lane]=ref_result[lane*8+:8];
            ref_seen=ref_seen+1;
        end
        if(ov) begin
            current_frame=seen/(B*H);at=seen%(B*H);
            if(current_frame>=N) $fatal(1,"extra output");
            if(os !== (at==0) || oe !== (at%B==B-1)) $fatal(1,"markers beat=%0d",seen);
            for(lane=0;lane<4;lane=lane+1) begin
                expected=legacy[seen*4+lane];
                if(result[lane*32+:8] !== expected[7:0])
                    $fatal(1,"mode=%0d beat=%0d lane=%0d got=%0d expected=%0d",modes[current_frame],seen,lane,result[lane*32+:8],expected);
                if(result[lane*32+24+:8]!==0 || result[lane*32+16+:8]!==result[lane*32+:8] ||
                   result[lane*32+8+:8]!==result[lane*32+:8]) $fatal(1,"RGB lane mismatch");
            end
            seen=seen+1;
        end
        if(fault) $fatal(1,"pipeline fault cycle=%0d seen=%0d",cycle,seen);
    end
    initial begin
        $readmemh("sim/reference_enhance_vectors/input.hex",input_pixels);
        $readmemh("sim/reference_enhance_vectors/expected.hex",golden);
        $readmemh("sim/reference_enhance_vectors/modes.hex",modes);
        repeat(4) @(negedge clk);rst_n=1;
        repeat(1100) @(negedge clk);
        for(frame=0;frame<N;frame=frame+1) begin
            mode=modes[frame];
            for(ty=0;ty<H;ty=ty+1) begin
                for(tx=0;tx<B;tx=tx+1) begin
                    valid=1;sof=(ty==0 && tx==0);eol=(tx==B-1);
                    for(j=0;j<4;j=j+1) begin
                        idx=frame*PIX+ty*W+tx*4+j;
                        rgb[j*32+:32]={8'd0,input_pixels[idx],input_pixels[idx],input_pixels[idx]};
                    end
                    @(negedge clk);
                    if(ty==H/2 && tx==0) mode=3'd5;
                    gap=(tx%2==1) ? 2 : 0;
                    if(gap!=0) begin valid=0;sof=0;eol=0;repeat(gap) @(negedge clk);end
                end
                valid=0;sof=0;eol=0;
            end
            repeat(12000) @(negedge clk);
            if(applied !== modes[frame]) $fatal(1,"midframe mode changed");
        end
        if(seen!=N*B*H || ref_seen!=seen || hf!=N || he!=0 || lhf!=N || lhe!=0)
            $fatal(1,"counts seen=%0d reference=%0d hist=%0d errors=%0d",seen,ref_seen,hf,he);
        $display("PASS V2 two-valid/two-idle replay, eight modes, exact OpenCV enhancement, post-CLAHE, gaps, borders and frame-latched mode");
        $finish;
    end
endmodule
