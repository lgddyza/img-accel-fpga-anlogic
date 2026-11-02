`timescale 1ns/1ps
module tb_huffman_amplitude;
    reg [10:0] magnitude;
    integer n,category,expected;
    huffman_encoder dut(.clk(1'b0),.rst_n(1'b0),.comp_id(2'd0),
        .restart(1'b0),.in_valid(1'b0),.in_data(16'd0),.in_sob(1'b0),
        .out_ready(1'b0));
    initial begin
        force dut.cur_abs=magnitude;
        for(n=0;n<2048;n=n+1) begin
            magnitude=n;category=0;
            while((1<<category)<=n) category=category+1;
            expected=-n+(1<<category)-1;
            #1;
            if(dut.negative_amplitude!==expected[10:0])
                $fatal(1,"amplitude mismatch magnitude=%0d got=%0d expected=%0d",
                    n,dut.negative_amplitude,expected);
        end
        release dut.cur_abs;
        $display("PASS exhaustive JPEG negative amplitude magnitudes 0..2047");
        $finish;
    end
endmodule
