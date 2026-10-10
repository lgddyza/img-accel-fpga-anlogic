`timescale 1ns/1ps
module tb_gray_hist4;
    localparam W=16,H=4,B=W/4;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,valid=0,sof=0,eol=0,enable=1;
    reg [31:0] data=0;
    wire [31:0] result;
    wire ov,os,oe,lut_active;
    wire [31:0] frames,errors;
    integer frame_idx=0,beats=0,x,y,lane,expected;
    gray_hist4 #(.WIDTH(W),.HEIGHT(H)) dut (
        .clk(clk),.rst_n(rst_n),.s_gray(data),.s_valid(valid),
        .s_sof(sof),.s_eol(eol),.enable(enable),
        .m_gray(result),.m_valid(ov),.m_sof(os),.m_eol(oe),
        .lut_active(lut_active),.hist_frames(frames),.hist_errors(errors)
    );
    always @(negedge clk) if (rst_n && ov) begin
        if (os !== (beats==0) || oe !== (beats%B==B-1))
            $fatal(1,"bad markers frame=%0d beat=%0d",frame_idx,beats);
        for (lane=0;lane<4;lane=lane+1) begin
            x=(beats%B)*4+lane;
            if (frame_idx==0) expected=x*16;
            else if (frame_idx==1) expected=x*17;
            else if (frame_idx==2) expected=34;
            else expected=42;
            if (result[lane*8+:8] !== expected[7:0])
                $fatal(1,"frame=%0d beat=%0d lane=%0d got=%0d want=%0d",
                       frame_idx,beats,lane,result[lane*8+:8],expected);
        end
        beats=beats+1;
        if (beats==B*H) begin beats=0;frame_idx=frame_idx+1;end
    end
    task send_frame;
        input integer uniform;
        integer tx,ty;
        reg [7:0] p0,p1,p2,p3;
        begin
            for (ty=0;ty<H;ty=ty+1) begin
                for (tx=0;tx<B;tx=tx+1) begin
                    valid=1;sof=(tx==0 && ty==0);eol=(tx==B-1);
                    p0=uniform ? 42 : tx*64;
                    p1=uniform ? 42 : tx*64+16;
                    p2=uniform ? 42 : tx*64+32;
                    p3=uniform ? 42 : tx*64+48;
                    data={p3,p2,p1,p0};
                    @(negedge clk);
                end
                valid=0;sof=0;eol=0;
                @(negedge clk);
            end
            repeat (1800) @(negedge clk);
        end
    endtask
    initial begin
        repeat (4) @(negedge clk);
        rst_n=1;
        repeat (260) @(negedge clk);
        send_frame(0);
        if (!lut_active && dut.next_ready!==1) $fatal(1,"first LUT not ready");
        send_frame(0);
        send_frame(1);
        send_frame(1);
        if (frame_idx!=4 || frames!=4 || errors!=0)
            $fatal(1,"counts out=%0d hist=%0d errors=%0d",frame_idx,frames,errors);
        $display("PASS gray_hist4 four frames, CDF-min and uniform fallback");
        $finish;
    end
endmodule
