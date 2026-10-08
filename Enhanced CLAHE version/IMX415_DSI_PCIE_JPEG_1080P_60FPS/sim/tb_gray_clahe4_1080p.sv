`timescale 1ns/1ps
module tb_gray_clahe4_1080p;
    localparam W=1920,H=1080,B=W/4;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,s_valid=0,s_sof=0,s_eol=0;
    reg [31:0] s_gray=0;
    wire [31:0] m_gray;
    wire m_valid,m_sof,m_eol,lut_active;
    wire [31:0] hist_frames,hist_errors;
    integer x,y,seen=0,second_seen=0;
    reg second=0;
    gray_clahe4 dut(.*,.enable(1'b1));
    always @(negedge clk) if(rst_n && m_valid) begin
        if(!second) begin
            if(m_sof !== (seen==0) || m_eol !== (seen%B==B-1))
                $fatal(1,"frame1 marker %0d",seen);
            seen=seen+1;
        end else begin
            if(m_sof !== (second_seen==0) || m_eol !== (second_seen%B==B-1))
                $fatal(1,"frame2 marker %0d",second_seen);
            if(second_seen==0 && m_gray[7:0]==8'd32)
                $fatal(1,"CLAHE mapping did not activate");
            second_seen=second_seen+1;
        end
    end
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        repeat(1050)@(negedge clk);
        for(y=0;y<H;y=y+1)begin
            for(x=0;x<B;x=x+1)begin
                s_valid=1;s_sof=(x==0&&y==0);s_eol=(x==B-1);
                s_gray={4{(y>=H/2) ? ((x>=B/2)?8'd200:8'd128) : ((x>=B/2)?8'd64:8'd32)}};
                @(negedge clk);
            end
            s_valid=0;s_sof=0;s_eol=0;
            repeat(3)@(negedge clk);
        end
        repeat(12000)@(negedge clk);
        if(seen!=B*H || hist_frames!=1 || hist_errors!=0 || !lut_active)
            $fatal(1,"frame1 seen=%0d hist=%0d errors=%0d active=%0d",seen,hist_frames,hist_errors,lut_active);
        second=1;
        for(y=0;y<2;y=y+1)begin
            for(x=0;x<B;x=x+1)begin
                s_valid=1;s_sof=(x==0&&y==0);s_eol=(x==B-1);
                s_gray={4{8'd32}};
                @(negedge clk);
            end
            s_valid=0;s_sof=0;s_eol=0;
            repeat(3)@(negedge clk);
        end
        repeat(5)@(negedge clk);
        if(second_seen!=2*B || hist_errors!=0)
            $fatal(1,"frame2 seen=%0d errors=%0d",second_seen,hist_errors);
        $display("PASS CLAHE 1080p: %0d four-pixel beats and LUT ready in blank",seen);
        $finish;
    end
endmodule
