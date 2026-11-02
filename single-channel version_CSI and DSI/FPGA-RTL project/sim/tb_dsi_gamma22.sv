`timescale 1ns/1ps
module tb_dsi_gamma22;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, valid=0, user=0, last=0, ready=1;
    reg [95:0] data={96{1'b1}};
    wire [95:0] expected, actual;
    wire ev, eu, el, er, av, au, al, ar;
    ui_gamma #(.GAMMA_10x(22)) reference_gamma (
        .I_clk(clk), .I_rst_n(rst_n), .I_tdata(data),
        .I_tvalid(valid), .I_tuser(user), .I_tlast(last), .I_tready(er),
        .O_tdata(expected), .O_tvalid(ev), .O_tuser(eu), .O_tlast(el), .O_tready(ready));
    ui_dsi_gamma22 dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_tdata(data),
        .I_tvalid(valid), .I_tuser(user), .I_tlast(last), .I_tready(ar),
        .O_tdata(actual), .O_tvalid(av), .O_tuser(au), .O_tlast(al), .O_tready(ready));
    integer checked=0;
    always @(posedge clk) begin
        #1;
        if (rst_n) begin
            if ({av,au,al,ar} !== {ev,eu,el,er}) $fatal(1,"gamma flags mismatch");
            if (actual !== expected) $fatal(1,"gamma data mismatch: %h != %h",actual,expected);
            if (av) checked=checked+12;
        end
    end
    integer i,c,phase;
    initial begin
        repeat(4) @(negedge clk);
        for(phase=0;phase<2;phase=phase+1) begin
            rst_n=1;
            for(i=0;i<1024;i=i+1) begin
                @(negedge clk);
                valid=(phase==0) || (i%5!=3);
                user=(i%257==0); last=(i%31==30); ready=(i%7!=4);
                for(c=0;c<12;c=c+1) data[8*c +: 8]=(i+19*c)&255;
            end
            @(negedge clk); valid=0; user=0; last=0;
            repeat(8) @(negedge clk);
            rst_n=0;
            repeat(4) @(negedge clk);
        end
        $display("DSI_GAMMA22_EQUIVALENCE_PASS: %0d channel values, all 256 inputs/channel, bubbles/reset",checked);
        $finish;
    end
endmodule
