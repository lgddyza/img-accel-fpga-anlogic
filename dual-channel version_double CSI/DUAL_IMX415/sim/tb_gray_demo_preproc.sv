`timescale 1ns/1ps
// This project intentionally omits enhancement modes. Check its actual
// two-stage luma arithmetic and markers, including ignored mode requests.
module tb_dual_preproc;
    reg clk=0,rst_n=0,camera=0;always #3.75 clk=~clk;
    reg [127:0] s_rgb=0;reg s_valid=0,s_sof=0,s_eol=0;reg [2:0] mode=0;
    wire [127:0] m_rgb_gray;wire m_valid,m_sof,m_eol,gauss_overrun;
    wire [2:0] applied_mode;
    wire [31:0] hist_frames_a,hist_frames_b,hist_errors_a,hist_errors_b;
    v2_dual_preprocess dut(.*);
    reg [127:0] expected0=0,expected1=0;
    reg [2:0] marker0=0,marker1=0;
    integer checked=0;
    function [127:0] luma(input [127:0] rgb);
        integer y;
        for(integer lane=0;lane<4;lane=lane+1) begin
            y=(77*integer'(rgb[lane*32+16+:8])+150*integer'(rgb[lane*32+8+:8])+
                29*integer'(rgb[lane*32+:8])+128)>>8;
            luma[lane*32+:32]={8'd0,8'(y),8'(y),8'(y)};
        end
    endfunction
    always @(posedge clk) begin
        if(!rst_n) begin marker0<=0;marker1<=0;expected0<=0;expected1<=0;end
        else begin
            expected0<=luma(s_rgb);expected1<=expected0;
            marker0<={s_valid && s_eol,s_valid && s_sof,s_valid};marker1<=marker0;
        end
    end
    always @(negedge clk) if(rst_n) begin
        if({m_eol,m_sof,m_valid}!==marker1) $fatal(1,"gray demo marker latency");
        if(m_valid) begin
            if(m_rgb_gray!==expected1) $fatal(1,"gray demo luma arithmetic");
            checked=checked+1;
        end
        if(applied_mode || gauss_overrun || hist_frames_a || hist_frames_b || hist_errors_a || hist_errors_b)
            $fatal(1,"unsupported enhancement unexpectedly active");
    end
    integer n;
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        for(n=0;n<4096;n=n+1) begin
            @(negedge clk);#1;
            s_valid=n%7!=3;s_sof=n%64==0;s_eol=n%16==15;camera=n/64%2;mode=n%8;
            for(integer lane=0;lane<4;lane=lane+1) s_rgb[lane*32+:32]=$random;
        end
        @(negedge clk);#1;s_valid=0;s_sof=0;s_eol=0;
        repeat(5) @(negedge clk);
        if(checked<3000) $fatal(1,"missing gray output");
        $display("PASS gray-only demo: %0d exact four-pixel outputs, A/B and ignored modes, two-stage markers",checked);$finish;
    end
endmodule
