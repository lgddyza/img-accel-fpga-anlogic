`timescale 1ns/1ps
module tb_gray_preprocess4;
    localparam W=16,H=4,B=W/4;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,valid=0,sof=0,eol=0;
    reg [1:0] mode=0;
    reg [127:0] rgb=0;
    wire [127:0] result;
    wire ov,os,oe,overrun;
    wire [31:0] hist_frames,hist_errors;
    reg [7:0] image [0:W*H-1];
    reg [7:0] gaussian [0:W*H-1];
    integer hist [0:255];
    integer map [0:255];
    integer x,y,mx,my,lane,dx,dy,xi,yi,weight,sum,cdf,cdfmin,denom;
    integer out_frame=0,out_beat=0,expected;
    gray_preprocess4 #(.WIDTH(W),.HEIGHT(H)) dut (
        .clk(clk),.rst_n(rst_n),.s_rgb(rgb),.s_valid(valid),
        .s_sof(sof),.s_eol(eol),.mode(mode),
        .m_rgb_gray(result),.m_valid(ov),.m_sof(os),.m_eol(oe),
        .gauss_overrun(overrun),.hist_frames(hist_frames),
        .hist_errors(hist_errors)
    );
    always @(negedge clk) if (rst_n && ov) begin
        if (os !== (out_beat==0) || oe !== (out_beat%B==B-1))
            $fatal(1,"markers frame=%0d beat=%0d sof=%b eol=%b",
                   out_frame,out_beat,os,oe);
        for (lane=0;lane<4;lane=lane+1) begin
            mx=(out_beat%B)*4+lane;
            my=out_beat/B;
            if (out_frame==0) expected=image[my*W+mx];
            else if (out_frame==1) expected=gaussian[my*W+mx];
            else expected=map[gaussian[my*W+mx]];
            if (result[lane*32+:8] !== expected[7:0] ||
                result[lane*32+8+:8] !== expected[7:0] ||
                result[lane*32+16+:8] !== expected[7:0])
                $fatal(1,"pixel frame=%0d (%0d,%0d) got=%0d want=%0d",
                       out_frame,mx,my,result[lane*32+:8],expected);
        end
        out_beat=out_beat+1;
        if (out_beat==B*H) begin out_beat=0;out_frame=out_frame+1;end
    end
    task send_frame;
        input [1:0] selected;
        integer tx,ty,j;
        reg [7:0] p0,p1,p2,p3;
        begin
            mode=selected;
            for (ty=0;ty<H;ty=ty+1) begin
                for (tx=0;tx<B;tx=tx+1) begin
                    valid=1;sof=(tx==0 && ty==0);eol=(tx==B-1);
                    p0=image[ty*W+tx*4]; p1=image[ty*W+tx*4+1];
                    p2=image[ty*W+tx*4+2]; p3=image[ty*W+tx*4+3];
                    rgb={8'd0,p3,p3,p3,8'd0,p2,p2,p2,
                         8'd0,p1,p1,p1,8'd0,p0,p0,p0};
                    @(negedge clk);
                end
                valid=0;sof=0;eol=0;
                repeat (2) @(negedge clk);
            end
            repeat (1800) @(negedge clk);
        end
    endtask
    initial begin
        for (y=0;y<H;y=y+1)
            for (x=0;x<W;x=x+1) image[y*W+x]=(x*13+y*27)%256;
        for (y=0;y<H;y=y+1)
            for (x=0;x<W;x=x+1) begin
                sum=0;
                for (dy=-1;dy<=1;dy=dy+1)
                    for (dx=-1;dx<=1;dx=dx+1) begin
                        xi=x+dx; yi=y+dy;
                        if (xi<0) xi=0;
                        if (xi>=W) xi=W-1;
                        if (yi<0) yi=0;
                        if (yi>=H) yi=H-1;
                        weight=(dx==0 ? 2 : 1)*(dy==0 ? 2 : 1);
                        sum=sum+weight*image[yi*W+xi];
                    end
                gaussian[y*W+x]=(sum+8)/16;
            end
        for (x=0;x<256;x=x+1) hist[x]=0;
        for (x=0;x<W*H;x=x+1) hist[gaussian[x]]=hist[gaussian[x]]+1;
        cdf=0;cdfmin=-1;
        for (x=0;x<256;x=x+1) begin
            cdf=cdf+hist[x];
            if (cdfmin<0 && cdf!=0) cdfmin=cdf;
            denom=W*H-cdfmin;
            map[x]=(cdfmin<0 || denom==0) ? x :
                   (cdf<=cdfmin ? 0 : ((cdf-cdfmin)*255)/denom);
        end
        repeat (4) @(negedge clk);rst_n=1;
        repeat (260) @(negedge clk);
        send_frame(2'b00);
        send_frame(2'b01);
        send_frame(2'b11);
        if (out_frame!=3 || hist_frames!=3 || hist_errors!=0 || overrun)
            $fatal(1,"counts out=%0d hist=%0d errors=%0d overrun=%b",
                   out_frame,hist_frames,hist_errors,overrun);
        $display("PASS grayscale -> Gaussian -> HE, bypass modes and frame markers");
        $finish;
    end
endmodule
