`timescale 1ns/1ps
module tb_jpeg_backpressure;
    localparam W=1920,H=96,F=2,B=W/4;
    reg cam_clk=0,enc_clk=0,user_clk=0,rst_n=0;
    always #3.75 cam_clk=~cam_clk;
    always #2.5 enc_clk=~enc_clk;
    always #4 user_clk=~user_clk;
    reg [39:0] raw=0;
    reg valid=0,sof=0,eol=0;
    wire source_ready,input_ready;
    wire [39:0] line_raw;
    wire lv,ls,le,line_fault;
    v2_line_replay #(.WIDTH(W),.BACKPRESSURE(1)) lines (
        .clk(cam_clk),.rst_n(rst_n),.s_data(raw),.s_valid(valid),.s_sof(sof),.s_eol(eol),
        .m_data(line_raw),.m_valid(lv),.m_sof(ls),.m_eol(le),.fault(line_fault),
        .s_ready(source_ready),.m_start_ready(input_ready));
    wire [127:0] rgb;
    generate for(genvar p=0;p<4;p=p+1) begin:g_rgb
        assign rgb[p*32+:32]={8'd0,{3{line_raw[p*10+:8]}}};
    end endgenerate
    integer cycles=0;
    always @(posedge user_clk) cycles<=cycles+1;
    // The first 0.8 ms without DMA is deliberately much longer than a 2 KiB
    // output FIFO can absorb. Each lane then has different long/short stalls.
    wire [2:0] ready=cycles<100000 ? 3'b000 :
        {cycles%113>37,cycles%127>67,cycles%139>89};
    wire [127:0] data[0:2];
    wire [15:0] keep[0:2];
    wire [2:0] v,last;
    wire configured,armed,done,fault;
    jpeg_triple_tile_branch #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.INPUT_FIFO_ADDR_WIDTH(11),
        .OUTPUT_FIFO_ADDR_WIDTH(7),.V2_SCHEDULED(1)) jpeg (
        .cam_clk(cam_clk),.cam_rst_n(rst_n),.enc_clk(enc_clk),.enc_pll_lock(1'b1),
        .user_clk(user_clk),.user_rst_n(rst_n),.s_rgb4(rgb),.s_valid(lv),.s_sof(ls),.s_eol(le),
        .enable(1'b1),.reset_pulse(1'b0),.link_up(1'b1),.full_rate(1'b1),.quality(7'd85),
        .a_ready(ready[0]),.b_ready(ready[1]),.c_ready(ready[2]),
        .a_data(data[0]),.b_data(data[1]),.c_data(data[2]),
        .a_keep(keep[0]),.b_keep(keep[1]),.c_keep(keep[2]),
        .a_valid(v[0]),.b_valid(v[1]),.c_valid(v[2]),
        .a_last(last[0]),.b_last(last[1]),.c_last(last[2]),
        .status_configured(configured),.status_busy(),.status_fault(fault),.status_quality(),
        .sent_a(),.sent_b(),.sent_c(),.fault_count(),.bytes_a(),.bytes_b(),.bytes_c(),
        .debug_status(),.debug_detail(),.input_armed(armed),.input_ready(input_ready),
        .group_done_cam(done),.fault_cam());
    integer packets[0:2],counts[0:2],encoded[0:2],consumed[0:2],paused[0:2],fd[0:2];
    reg [7:0] expected[0:2][0:500000];
    generate for(genvar g=0;g<3;g=g+1) begin:g_check
        reg stalled=0;
        reg [8:0] held;
        always @(posedge enc_clk) if(rst_n) begin
            if(stalled && (!jpeg.g_tile[g].jpg_valid ||
                {jpeg.g_tile[g].jpg_last,jpeg.g_tile[g].jpg_byte}!==held))
                $fatal(1,"encoder output changed while paused lane=%0d",g);
            stalled=jpeg.g_tile[g].jpg_valid && !jpeg.g_tile[g].jpg_ready;
            held={jpeg.g_tile[g].jpg_last,jpeg.g_tile[g].jpg_byte};
            if(stalled) paused[g]=paused[g]+1;
            if(jpeg.g_tile[g].jpg_valid && jpeg.g_tile[g].jpg_ready) begin
                expected[g][encoded[g]]=jpeg.g_tile[g].jpg_byte;
                encoded[g]=encoded[g]+1;
            end
        end
    end endgenerate
    always @(posedge user_clk) if(rst_n) begin
        if(fault || line_fault) $fatal(1,"flow control fault input=%b output=%b lines=%b",
            jpeg.bridge_fault,jpeg.packer_fault,line_fault);
        for(integer l=0;l<3;l=l+1) if(v[l] && ready[l]) begin
            if(counts[l]==0)
                fd[l]=$fopen($sformatf("build/str2_backpressure/frame_%0d_tile_%0d.jpg",packets[l],l),"wb");
            for(integer b=0;b<16;b=b+1) if(keep[l][b]) begin
                if(consumed[l]>=encoded[l] || data[l][b*8+:8]!==expected[l][consumed[l]])
                    $fatal(1,"byte loss/reorder lane=%0d byte=%0d",l,consumed[l]);
                consumed[l]=consumed[l]+1;counts[l]=counts[l]+1;
                $fwrite(fd[l],"%c",data[l][b*8+:8]);
            end
            if(last[l]) begin
                if(counts[l]<16384) $fatal(1,"stimulus did not exceed old FIFO capacity");
                $display("JPEG frame=%0d lane=%0d bytes=%0d paused_cycles=%0d",packets[l],l,counts[l],paused[l]);
                $fclose(fd[l]);packets[l]=packets[l]+1;counts[l]=0;
            end
        end
    end
    reg [31:0] rng=32'h84937251;
    integer blocked=0;
    initial begin
        for(integer l=0;l<3;l=l+1) begin
            packets[l]=0;counts[l]=0;encoded[l]=0;consumed[l]=0;paused[l]=0;
        end
        repeat(10) @(negedge user_clk);rst_n=1;
        wait(configured && armed);
        for(integer f=0;f<F;f=f+1) begin
            for(integer y=0;y<H;y=y+1) for(integer x=0;x<B;x=x+1) begin
                @(negedge cam_clk);
                while(!source_ready) begin
                    valid=0;sof=0;eol=0;blocked=blocked+1;@(negedge cam_clk);
                end
                valid=1;sof=(x==0 && y==0);eol=(x==B-1);
                for(integer p=0;p<4;p=p+1) begin
                    rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
                    raw[p*10+:10]={2'b0,rng[7:0]};
                end
                if(x%2==1) begin @(negedge cam_clk);valid=0;sof=0;eol=0;end
            end
            wait(done);wait(armed);repeat(20) @(negedge cam_clk);
        end
        repeat(20) @(negedge user_clk);
        for(integer l=0;l<3;l=l+1)
            if(packets[l]!=F || encoded[l]!=consumed[l] || paused[l]==0)
                $fatal(1,"missing data or untested backpressure lane=%0d",l);
        if(blocked==0) $fatal(1,"DDR replay never paused");
        $display("PASS end-to-end pause/resume: six noisy JPEGs >16KiB, 2KiB FIFOs, exact bytes, DDR pauses=%0d",blocked);
        $finish;
    end
    initial begin #20000000;$fatal(1,"backpressure timeout");end
endmodule
