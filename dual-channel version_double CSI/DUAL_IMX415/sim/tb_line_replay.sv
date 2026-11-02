`timescale 1ns/1ps
module tb_line_replay;
    localparam W=64,B=W/4,H=12,F=3;
    reg clk=0,rst_n=0;always #3.75 clk=~clk;
    reg [39:0] data=0;reg valid=0,sof=0,eol=0;
    wire [39:0] result;wire rv,rs,re,fault;
    integer frame,y,x,gap,n=0,contiguous=0,seed=107;
    v2_line_replay #(.WIDTH(W)) dut(
        .clk(clk),.rst_n(rst_n),.s_data(data),.s_valid(valid),.s_sof(sof),.s_eol(eol),
        .m_data(result),.m_valid(rv),.m_sof(rs),.m_eol(re),.fault(fault),
        .s_ready(),.m_start_ready(1'b1),.line_started(),.line_waiting());
    always @(posedge clk) if(rst_n) begin
        if(rv) begin
            if(result!==n) $fatal(1,"pixel order n=%0d got=%0d",n,result);
            if(rs!==(n%(B*H)==0) || re!==(n%B==B-1)) $fatal(1,"bad raster marker");
            contiguous=contiguous+1;n=n+1;
            if(re) begin
                if(contiguous!=B) $fatal(1,"short active row");
                contiguous=0;
            end
        end else if(contiguous!=0) $fatal(1,"gap inside active row");
    end
    initial begin
        repeat(5) @(negedge clk);rst_n=1;
        for(frame=0;frame<F;frame=frame+1) begin
            for(y=0;y<H;y=y+1) begin
                for(x=0;x<B;x=x+1) begin
                    @(negedge clk);valid=1;sof=(x==0 && y==0);eol=(x==B-1);
                    data=frame*B*H+y*B+x;
                    @(negedge clk);valid=0;sof=0;eol=0;
                    gap=$unsigned($random(seed))%5;
                    repeat(gap) @(negedge clk);
                end
            end
            repeat(B*3) @(negedge clk);
        end
        if(n!=B*H*F || fault) $fatal(1,"missing pixels/fault %0d",n);
        // Malformed line must stop the stream and set the sticky diagnostic.
        @(negedge clk);valid=1;sof=1;eol=1;
        @(negedge clk);valid=0;sof=0;eol=0;
        repeat(3) @(negedge clk);
        if(!fault) $fatal(1,"bad EOL was accepted");
        $display("PASS ping-pong line replay: random DDR gaps, contiguous rows, exact pixels/markers, malformed-line detection");
        $finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
