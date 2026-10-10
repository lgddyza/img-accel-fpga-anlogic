`timescale 1ns/1ps
module tb_jpeg_gray4_axis_backpressure;
    localparam W=32,H=16,N=5;
    reg cam_clk=0,enc_clk=0,rst_n=0;
    always #6 cam_clk=~cam_clk;
    always #2.5 enc_clk=~enc_clk;
    reg [63:0] pixels=0;
    reg valid=0,sof=0,eol=0,ready=0;
    wire [15:0] data;
    wire ov,os,oe,cf,ef;
    wire [31:0] selected,completed;
    integer received=0,frame,x,y,k,cycles=0,run_length=0,longest_run=0;
    reg [31:0] random_state=32'h63a78f15;
    reg stalled=0;
    reg [17:0] held;
    jpeg_gray4_axis_cdc #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.FIFO_ADDR_WIDTH(8)) dut(
        .cam_clk(cam_clk),.enc_clk(enc_clk),.rst_n(rst_n),
        .s_yuyv4(pixels),.s_valid(valid),.s_sof(sof),.s_eol(eol),
        .s_take_frame(1'b1),.s_fault(cf),.s_fault_cause(),
        .s_fault_line(),.s_fault_beat(),.s_selected_frames(selected),
        .s_completed_frames(completed),.m_tdata(data),.m_tvalid(ov),
        .m_tready(ready),.m_tuser(os),.m_tlast(oe),.m_fault(ef));
    always @(negedge enc_clk) if(rst_n) begin
        cycles=cycles+1;
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        if(cycles<160) ready=0;
        else if(cycles<500) ready=1;
        else ready=random_state[0] || random_state[3];
    end
    always @(posedge enc_clk) if(rst_n) begin
        if(cf || ef) $fatal(1,"unexpected bridge fault");
        if(stalled && (!ov || {os,oe,data} !== held))
            $fatal(1,"output changed while stalled");
        stalled=ov && !ready;
        held={os,oe,data};
        if(ov && ready) begin
            if(received>=N*W*H || data !== {8'h80,8'((received*13+received/(W*H)*29)&255)})
                $fatal(1,"pixel %0d: %h",received,data);
            if(os !== (received%(W*H)==0) || oe !== (received%W==W-1))
                $fatal(1,"marker mismatch at %0d",received);
            received=received+1;
            run_length=run_length+1;
            if(run_length>longest_run) longest_run=run_length;
        end else run_length=0;
    end
    initial begin
        repeat(8) @(negedge cam_clk);
        rst_n=1;
        // Vendor FIFO releases each clock-domain reset through two registers.
        repeat(8) @(negedge cam_clk);
        for(frame=0;frame<N;frame=frame+1) begin
            for(y=0;y<H;y=y+1) begin
                for(x=0;x<W/4;x=x+1) begin
                    @(negedge cam_clk);
                    valid=1;sof=(x==0 && y==0);eol=(x==W/4-1);
                    for(k=0;k<4;k=k+1)
                        pixels[k*16+:16]={8'h80,8'(((frame*W*H+y*W+x*4+k)*13+frame*29)&255)};
                end
                @(negedge cam_clk);valid=0;sof=0;eol=0;
                repeat(8+y%5) @(negedge cam_clk);
            end
            repeat(13) @(negedge cam_clk);
        end
        wait(received==N*W*H);
        repeat(100) @(negedge enc_clk);
        if(selected!=N || completed!=N || longest_run<32)
            $fatal(1,"counts=%0d/%0d longest_run=%0d",selected,completed,longest_run);
        $display("JPEG_CDC_BACKPRESSURE_PASS pixels=%0d consecutive_beats=%0d",received,longest_run);
        $finish;
    end
    initial begin #1000000; $fatal(1,"timeout pixels=%0d",received); end
endmodule
