`timescale 1ns/1ps
module tb_gray_hist4_1080p;
    localparam W=1920,H=1080,B=W/4;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,valid=0,sof=0,eol=0;
    reg [31:0] data={8'd192,8'd128,8'd64,8'd16};
    wire [31:0] result;
    wire ov,os,oe,lut_active;
    wire [31:0] frames,errors;
    integer tx,ty,frame,seen=0;
    gray_hist4 #(.LUT_IIR_SHIFT(2)) dut (
        .clk(clk),.rst_n(rst_n),.s_gray(data),.s_valid(valid),
        .s_sof(sof),.s_eol(eol),.enable(1'b1),
        .m_gray(result),.m_valid(ov),.m_sof(os),.m_eol(oe),
        .lut_active(lut_active),.hist_frames(frames),.hist_errors(errors)
    );
    always @(negedge clk) if (rst_n && ov) begin
        if (os !== (seen%(B*H)==0) || oe !== (seen%B==B-1))
            $fatal(1,"marker at beat %0d",seen);
        if (seen < B*H) begin
            if (result !== {8'd192,8'd128,8'd64,8'd16})
                $fatal(1,"first frame beat %0d got %h",seen,result);
        end else if (result !== {8'd208,8'd139,8'd69,8'd12})
            $fatal(1,"equalized beat %0d got %h",seen,result);
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
        if (seen!=2*B*H || frames!=2 || errors!=0)
            $fatal(1,"counts seen=%0d hist=%0d errors=%0d",seen,frames,errors);
        $display("PASS 1080p four-level equalization with LUT IIR, two complete frames");
        $finish;
    end
endmodule
