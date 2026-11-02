module tb_dct_equivalence;
    reg clk=0, rst_n=0, in_valid=0, in_last=0;
    reg signed [11:0] in_data=0;
    wire va,vb,la,lb;
    wire signed [15:0] da,db;
    integer cycle, samples=0, outputs=0;
    reg [31:0] rng=32'h4d317ac9;
    always #5 clk=~clk;
    dct_1d old_dct(clk,rst_n,in_valid,in_data,in_last,va,da,la);
    dct_1d_optimized new_dct(clk,rst_n,in_valid,in_data,in_last,vb,db,lb);
    initial begin
        repeat(4) @(negedge clk);
        rst_n=1;
        for (cycle=0;cycle<12000;cycle=cycle+1) begin
            @(negedge clk);
            rst_n = !((cycle>=3000 && cycle<3003) ||
                      (cycle>=7001 && cycle<7004));
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            in_valid=rst_n && (cycle<11800) && (rng[2:0]!=0);
            in_data=rng[15:4];
            in_last=in_valid && (samples%8==7);
            if(in_valid) samples=samples+1;
            @(posedge clk); #1;
            if(va!==vb || la!==lb || (va && da!==db)) begin
                $display("FAIL cycle=%0d valid=%b/%b last=%b/%b data=%d/%d",cycle,va,vb,la,lb,da,db);
                $fatal;
            end
            if(va) outputs=outputs+1;
        end
        if(outputs<9000) $fatal(1,"insufficient coverage %0d",outputs);
        $display("PASS DCT equivalence samples=%0d outputs=%0d",samples,outputs);
        $finish;
    end
endmodule
