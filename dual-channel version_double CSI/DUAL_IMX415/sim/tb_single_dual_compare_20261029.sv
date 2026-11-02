`timescale 1ns/1ps
module tb_single_dual_compare;
    localparam W=64,H=24,N=W*H/4,CASES=9;
    reg clk=0,rst=0,v=0,s=0,e=0;
    always #3.75 clk=~clk;
    reg [127:0] rgb=0;
    reg [2:0] mode=0;
    wire [127:0] single,dual;
    wire sv,ss,se,sf,dv,ds,de,df;
    old_gray_preprocess4 #(.WIDTH(W),.HEIGHT(H)) old_dut(
        .clk(clk),.rst_n(rst),.s_rgb(rgb),.s_valid(v),.s_sof(s),.s_eol(e),.mode(mode),
        .m_rgb_gray(single),.m_valid(sv),.m_sof(ss),.m_eol(se),.gauss_overrun(sf),
        .applied_mode(),.hist_frames(),.hist_errors());
    v2_dual_preprocess #(.WIDTH(W),.HEIGHT(H)) new_dut(
        .clk(clk),.rst_n(rst),.camera(1'b0),.s_rgb(rgb),.s_valid(v),.s_sof(s),.s_eol(e),
        .mode(mode),.strength(3'd4),.m_rgb_gray(dual),.m_valid(dv),.m_sof(ds),.m_eol(de),
        .gauss_overrun(df),.applied_mode(),.hist_frames_a(),.hist_frames_b(),
        .hist_errors_a(),.hist_errors_b(),.observer_rgb(),.observer_valid(),.observer_sof(),.observer_eol());
    reg [127:0] pixels[0:CASES*N-1];
    reg [127:0] old_pixels[0:N-1],new_pixels[0:N-1];
    integer old_count=0,new_count=0,idx,chosen;
    string input_path;
    always @(negedge clk) if(rst) begin
        if(sf || df) $fatal(1,"fault single=%b dual=%b",sf,df);
        if(sv) begin
            if(old_count>=N || ss!==(old_count==0) || se!==(old_count%(W/4)==W/4-1)) $fatal(1,"single geometry");
            old_pixels[old_count]=single;old_count=old_count+1;
        end
        if(dv) begin
            if(new_count>=N || ds!==(new_count==0) || de!==(new_count%(W/4)==W/4-1)) $fatal(1,"dual geometry");
            new_pixels[new_count]=dual;new_count=new_count+1;
        end
    end
    initial begin
        if(!$value$plusargs("input=%s",input_path)) input_path="build/preproc_small_paused_rgb.hex";
        $readmemh(input_path,pixels);
        repeat(8) @(negedge clk);rst=1;
        repeat(20) @(negedge clk);
        for(integer test=0;test<4;test=test+1) begin
            case(test) 0:begin idx=0;mode=0;end 1:begin idx=5;mode=1;end
                2:begin idx=6;mode=5;end default:begin idx=8;mode=5;end endcase
            old_count=0;new_count=0;
            for(integer i=0;i<N;i=i+1) begin
                @(negedge clk);#1;v=1;s=i==0;e=i%(W/4)==W/4-1;rgb=pixels[idx*N+i];
                if((i%29==10) || i%(W/4)==W/4-1) begin
                    @(negedge clk);#1;v=0;s=0;e=0;repeat((i%7)+4) @(negedge clk);
                end
            end
            @(negedge clk);#1;v=0;s=0;e=0;
            wait(old_count==N && new_count==N);
            for(integer i=0;i<N;i=i+1)
                if(old_pixels[i]!==new_pixels[i]) $fatal(1,"test=%0d mode=%0d group=%0d single=%h dual=%h",test,mode,i,old_pixels[i],new_pixels[i]);
            $display("PASS single vs dual exact pixels mode=%0d input=%0d groups=%0d",mode,idx,N);
            repeat(2000) @(negedge clk);
        end
        $finish;
    end
    initial begin #300000000;$fatal(1,"timeout single=%0d dual=%0d",old_count,new_count);end
endmodule
