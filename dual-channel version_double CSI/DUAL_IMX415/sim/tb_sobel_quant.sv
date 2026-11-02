`timescale 1ns/1ps
module tb_sobel_quant;
    reg clk=0, rst_n=0;
    reg signed [19:0] injected=0;
    wire [31:0] gray;
    integer i,n,q,r,expected[0:8],k;
    always #5 clk=~clk;
    gray_sobel_guided4 dut(.clk(clk),.rst_n(rst_n),.s_window(288'd0),
        .s_valid(1'b0),.s_sof(1'b0),.s_eol(1'b0),.m_gray(gray),
        .m_valid(),.m_sof(),.m_eol());
    initial begin
        force dut.g_lane[0].numerator=injected;
        for(k=0;k<9;k=k+1) expected[k]=0;
        repeat(2) @(negedge clk);
        rst_n=1;
        for(i=0;i<440680;i=i+1) begin
            n=i-20;
            injected=n;
            if(n<=0) q=0;
            else if(n>=440640) q=255;
            else begin
                q=n/1728;r=n%1728;
                if(r>864 || (r==864 && (q%2)==1)) q=q+1;
            end
            @(posedge clk); #1;
            for(k=8;k>0;k=k-1) expected[k]=expected[k-1];
            expected[0]=q;
            if(i>=8 && gray[7:0]!==expected[8]) begin
                $display("FAIL n=%0d got=%0d expected=%0d",i-28,gray[7:0],expected[8]);
                $fatal(1);
            end
            @(negedge clk);
        end
        $display("PASS exhaustive Sobel quantization, saturation and ties-to-even");
        $finish;
    end
endmodule
