`timescale 1ns/1ps
module tb_gray_gauss4;
    localparam W=16,H=4,B=W/4;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,valid=0,sof=0,eol=0;
    reg [31:0] data=0;
    wire [31:0] center,gauss;
    wire ov,os,oe,overrun;
    reg [7:0] image [0:W*H-1];
    integer x,y,mx,my,lane,k,xi,yi,dy,dx,sum,weight,expect_gray;
    integer output_beats=0;
    gray_gauss4 #(.WIDTH(W),.HEIGHT(H)) dut (
        .clk(clk),.rst_n(rst_n),.s_gray(data),.s_valid(valid),
        .s_sof(sof),.s_eol(eol),.m_center(center),.m_gauss(gauss),
        .m_valid(ov),.m_sof(os),.m_eol(oe),.m_overrun(overrun)
    );
    always @(negedge clk) if (rst_n && ov) begin
        if (output_beats >= B*H) $fatal(1,"extra beat");
        if (os !== (output_beats==0) || oe !== (output_beats%B==B-1))
            $fatal(1,"markers beat=%0d sof=%b eol=%b",output_beats,os,oe);
        for (lane=0;lane<4;lane=lane+1) begin
            mx=(output_beats%B)*4+lane;
            my=output_beats/B;
            if (center[lane*8+:8] !== image[my*W+mx])
                $fatal(1,"center (%0d,%0d) got=%0d want=%0d",
                       mx,my,center[lane*8+:8],image[my*W+mx]);
            sum=0;
            for (dy=-1;dy<=1;dy=dy+1)
                for (dx=-1;dx<=1;dx=dx+1) begin
                    xi=mx+dx; yi=my+dy;
                    if (xi<0) xi=0;
                    if (xi>=W) xi=W-1;
                    if (yi<0) yi=0;
                    if (yi>=H) yi=H-1;
                    weight=(dx==0 ? 2 : 1)*(dy==0 ? 2 : 1);
                    sum=sum+weight*image[yi*W+xi];
                end
            expect_gray=(sum+8)/16;
            if (gauss[lane*8+:8] !== expect_gray[7:0]) begin
                $fatal(1,"gauss (%0d,%0d) got=%0d want=%0d",
                       mx,my,gauss[lane*8+:8],expect_gray);
            end
        end
        output_beats=output_beats+1;
    end
    initial begin
        for (y=0;y<H;y=y+1)
            for (x=0;x<W;x=x+1) image[y*W+x]=(x*13+y*27)%256;
        repeat (4) @(negedge clk);
        rst_n=1;
        for (y=0;y<H;y=y+1) begin
            for (x=0;x<B;x=x+1) begin
                valid=1; sof=(x==0 && y==0); eol=(x==B-1);
                data={image[y*W+x*4+3],image[y*W+x*4+2],
                      image[y*W+x*4+1],image[y*W+x*4]};
                @(negedge clk);
            end
            valid=0; sof=0; eol=0;
            repeat (2) @(negedge clk);
        end
        repeat (B+10) @(negedge clk);
        if (output_beats!=B*H || overrun)
            $fatal(1,"count=%0d expected=%0d overrun=%b",output_beats,B*H,overrun);
        $display("PASS gray_gauss4 %0d pixels",W*H);
        $finish;
    end
endmodule
