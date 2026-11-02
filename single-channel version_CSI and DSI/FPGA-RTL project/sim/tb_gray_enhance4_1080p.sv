`timescale 1ns/1ps
module tb_gray_enhance4_1080p;
    localparam W=1920,H=1080,B=W/4,N=B*H;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,valid=0,sof=0,eol=0;
    reg [2:0] mode=4;
    reg [127:0] rgb={4{32'h00505050}};
    wire [127:0] result;
    wire ov,os,oe,fault;
    wire [2:0] applied;
    wire [31:0] hist_frames,hist_errors;
    integer tx,ty,frame,seen=0,cycle=0,first_in=0,first_out=0;
    gray_preprocess4 dut (
        .clk(clk),.rst_n(rst_n),.s_rgb(rgb),.s_valid(valid),
        .s_sof(sof),.s_eol(eol),.mode(mode),.applied_mode(applied),
        .m_rgb_gray(result),.m_valid(ov),.m_sof(os),.m_eol(oe),
        .gauss_overrun(fault),.hist_frames(hist_frames),.hist_errors(hist_errors)
    );
    always @(negedge clk) begin
        cycle=cycle+1;
        if(rst_n && ov) begin
            if(result !== {4{32'h00505050}} || os !== (seen%N==0) || oe !== (seen%B==B-1))
                $fatal(1,"bad beat %0d data=%h sof=%b eol=%b",seen,result,os,oe);
            if(seen%N==0) begin
                first_out=cycle;
                $display("mode %0d first pixel latency=%0d clocks",mode,first_out-first_in);
            end
            seen=seen+1;
        end
        if(rst_n && fault) $fatal(1,"alignment/padding fault at cycle %0d",cycle);
    end
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        repeat(1100) @(negedge clk);
        for(frame=0;frame<2;frame=frame+1) begin
            mode=frame==0 ? 4 : 5;
            first_in=cycle;
            for(ty=0;ty<H;ty=ty+1)
                for(tx=0;tx<B;tx=tx+1) begin
                    valid=1;sof=tx==0 && ty==0;eol=tx==B-1;
                    @(negedge clk);
                end
            valid=0;sof=0;eol=0;
            repeat(12000) @(negedge clk);
            if(seen!=(frame+1)*N) $fatal(1,"missing pixels frame=%0d count=%0d",frame,seen);
            $display("1080p frame %0d mode %0d complete, %0d beats",frame,mode,seen);
        end
        if(hist_frames!=2 || hist_errors!=0 || fault)
            $fatal(1,"hist frames=%0d errors=%0d fault=%b",hist_frames,hist_errors,fault);
        $display("PASS 1080p continuous input, Sobel/blackhat, no lost pixels");
        $finish;
    end
endmodule
