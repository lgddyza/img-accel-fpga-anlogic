`timescale 1ns/1ps
module tb_header;
    reg clk=0,rst=0;always #4 clk=~clk;
    reg [127:0] metadata={32'd123,32'd77,8'd0,8'd85,8'd3,8'd1,32'd42};
    reg [127:0] sd=0;reg [15:0] sk=0;reg sv=0,sl=0,mr=0;
    wire sr,mv,ml;wire [127:0] md;wire [15:0] mk;
    v2_jpeg_header #(.TILE(2)) dut (.clk(clk),.rst_n(rst),.metadata(metadata),
        .s_data(sd),.s_keep(sk),.s_valid(sv),.s_last(sl),.s_ready(sr),
        .m_data(md),.m_keep(mk),.m_valid(mv),.m_last(ml),.m_ready(mr));
    reg [31:0] rng=32'h873a191a;integer got=0;
    reg stalled=0;reg [144:0] held;
    integer f;
    initial f=$fopen("build/header_packet.djp","wb");
    always @(posedge clk) if(rst) begin
        rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        mr<=rng[0] && rng[3];
        if(stalled && (!mv || {md,mk,ml}!==held)) $fatal(1,"AXIS changed during stall");
        stalled=mv && !mr;held={md,mk,ml};
        if(mv && mr) begin
            if(got<2 && (mk!=16'hffff || ml)) $fatal(1,"bad header sideband");
            if(got==0 && md!=={8'd85,8'd3,8'd2,8'd1,32'd42,16'd32,16'd2,32'h32504a44}) $fatal(1,"bad header0");
            if(got==1 && md!=={32'd123,32'd77,8'd1,8'd8,16'd360,16'd1080,16'd1920}) $fatal(1,"bad header1");
            if(got==2 && (md[15:0]!=16'hd8ff || mk!=16'hffff || ml)) $fatal(1,"payload corruption");
            if(got==3 && (md[15:0]!=16'hd9ff || mk!=16'h0003 || !ml)) $fatal(1,"bad payload tail");
            for(integer i=0;i<16;i=i+1) if(mk[i]) $fwrite(f,"%c",md[i*8+:8]);
            got=got+1;
        end
    end
    task send(input [127:0] d,input [15:0] k,input l);
        begin
            @(negedge clk);sd=d;sk=k;sl=l;sv=1;
            do @(posedge clk);while(!sr);
            @(negedge clk);sv=0;
        end
    endtask
    initial begin
        repeat(10) @(negedge clk);rst=1;
        send(128'h102030405060708090a0b0c0d0e0d8ff,16'hffff,0);
        send(128'hd9ff,16'h0003,1);
        repeat(5) @(negedge clk);
        if(got!=4) $fatal(1,"lost transfer");
        $fclose(f);$display("PASS DJP2 headers, byte order, TKEEP/TLAST and randomized backpressure");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
