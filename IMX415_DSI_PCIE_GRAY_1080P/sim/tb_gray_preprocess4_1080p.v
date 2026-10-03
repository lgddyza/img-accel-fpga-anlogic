`timescale 1ns/1ps
module tb_gray_preprocess4_1080p;
    localparam W=1920,H=1080,B=W/4;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,valid=0,sof=0,eol=0;
    reg [127:0] rgb={4{32'h00505050}};
    wire [127:0] result;
    wire ov,os,oe,overrun;
    wire [31:0] hist_frames,hist_errors;
    integer tx,ty,frame,seen=0;
    gray_preprocess4 dut (
        .clk(clk),.rst_n(rst_n),.s_rgb(rgb),.s_valid(valid),
        .s_sof(sof),.s_eol(eol),.mode(2'b11),
        .m_rgb_gray(result),.m_valid(ov),.m_sof(os),.m_eol(oe),
        .gauss_overrun(overrun),.hist_frames(hist_frames),
        .hist_errors(hist_errors)
    );
    always @(negedge clk) if (rst_n && ov) begin
        if (result !== {4{32'h00505050}} ||
            os !== (seen%(B*H)==0) || oe !== (seen%B==B-1))
            $fatal(1,"bad output beat %0d data=%h sof=%b eol=%b",
                   seen,result,os,oe);
        seen=seen+1;
    end
    initial begin
        repeat (4) @(negedge clk);rst_n=1;
        repeat (260) @(negedge clk);
        for (frame=0;frame<2;frame=frame+1) begin
            for (ty=0;ty<H;ty=ty+1) begin
                for (tx=0;tx<B;tx=tx+1) begin
                    valid=1;sof=(tx==0 && ty==0);eol=(tx==B-1);
                    @(negedge clk);
                end
                valid=0;sof=0;eol=0;
                repeat (3) @(negedge clk);
            end
            repeat (8000) @(negedge clk);
        end
        if (seen!=2*B*H || hist_frames!=2 || hist_errors!=0 || overrun)
            $fatal(1,"counts seen=%0d hist=%0d err=%0d overrun=%b",
                   seen,hist_frames,hist_errors,overrun);
        $display("PASS full 1920x1080 two-frame gray/Gaussian/HE stream");
        $finish;
    end
endmodule
