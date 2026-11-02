`timescale 1ns/1ps
module tb_jfif_backpressure;
    reg clk=0,rst_n=0,start=0;
    always #2.5 clk=~clk;
    reg [31:0] rng=32'h912367ab;
    integer cycles=0;
    always @(negedge clk) begin
        cycles=cycles+1;
        rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
    end
    wire [3:0] ready={rng[0] && cycles%101>40,1'b1,rng[1] && cycles%89>20,1'b1};
    wire [3:0] valid,last;
    wire [7:0] data[0:3];
    integer scan_index[0:3],count[0:3];
    reg [7:0] received[0:3][0:2047];
    reg [3:0] finished=0;
    generate for(genvar g=0;g<4;g=g+1) begin:gen_writer
        wire scan_ready;
        wire [5:0] qt_addr;
        wire qt_chroma;
        reg [7:0] qt_data;
        always @(posedge clk) qt_data<=qt_addr*37+(qt_chroma?19:7);
        wire [7:0] scan_data=scan_index[g]*13+23;
        jfif_writer #(.IMG_WIDTH(1920),.IMG_HEIGHT(360),.LITE_MODE(g/2),
            .MONO(g<2),.OUTPUT_BACKPRESSURE(1)) dut (
            .clk(clk),.rst_n(rst_n),.frame_start(start),.frame_done(1'b0),.restart_interval(16'd0),
            .qt_rd_addr(qt_addr),.qt_rd_is_chroma(qt_chroma),.qt_rd_data(qt_data),
            .scan_valid(scan_index[g]<=128),.scan_data(scan_data),.scan_last(scan_index[g]==128),
            .scan_ready(scan_ready),.m_axis_tvalid(valid[g]),.m_axis_tdata(data[g]),
            .m_axis_tlast(last[g]),.m_axis_tready(ready[g]),.headers_done());
        reg stalled=0;
        reg [8:0] held;
        always @(posedge clk) if(rst_n) begin
            if(scan_ready && scan_index[g]<=128) scan_index[g]<=scan_index[g]+1;
            if(stalled && (!valid[g] || {last[g],data[g]}!==held))
                $fatal(1,"JFIF changed under backpressure mode=%0d",g/2);
            stalled=valid[g] && !ready[g];held={last[g],data[g]};
            if(valid[g] && ready[g]) begin
                received[g][count[g]]=data[g];count[g]=count[g]+1;
                if(last[g]) finished[g]=1;
            end
        end
    end endgenerate
    initial begin
        for(integer g=0;g<4;g=g+1) begin scan_index[g]=0;count[g]=0;end
        repeat(10) @(negedge clk);rst_n=1;
        @(negedge clk);start=1;@(negedge clk);start=0;
        wait(&finished);repeat(5) @(negedge clk);
        for(integer g=0;g<4;g=g+2) begin
            if(count[g]!=count[g+1]) $fatal(1,"JFIF length mismatch");
            for(integer b=0;b<count[g];b=b+1)
                if(received[g][b]!==received[g+1][b])
                    $fatal(1,"JFIF byte mismatch mode=%0d byte=%0d",g/2,b);
        end
        $display("PASS full/lite JFIF: stalled headers/DQT/scan/EOI match unstalled output byte-for-byte");
        $finish;
    end
    initial begin #1000000;$fatal(1,"JFIF timeout");end
endmodule
