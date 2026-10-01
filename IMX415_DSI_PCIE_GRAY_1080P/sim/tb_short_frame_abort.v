`timescale 1ns/1ps
module tb_short_frame_abort;
    reg cam_clk=0,user_clk=0;
    always #4 cam_clk=~cam_clk;
    always #3.5 user_clk=~user_clk;
    reg rst_n=0,valid=0,sof=0,eol=0;
    reg [127:0] rgb=0;
    wire [127:0] data;
    wire out_valid,out_last;
    wire [31:0] frames,errors,pass,drop,delivered;
    integer x,y,beats=0,last_count=0;
    isp_gray_1080p_cdc dut (
        .cam_clk(cam_clk),.cam_rst_n(rst_n),
        .s_tdata(rgb),.s_tvalid(valid),.s_tuser(sof),.s_tlast(eol),
        .user_clk(user_clk),.user_rst_n(rst_n),.enable(1'b1),
        .dma_ready(1'b1),.m_tdata(data),.m_tvalid(out_valid),
        .m_tready(1'b1),.m_tlast(out_last),.pixel_valid(),
        .frame_count(frames),.error_count(errors),
        .pass_count(pass),.drop_count(drop),.delivered_count(delivered)
    );
    always @(posedge user_clk) if(rst_n && out_valid) begin
        beats=beats+1;
        if(out_last) begin
            last_count=last_count+1;
            if(beats!=1066*120+1 || data!==0)
                $fatal(1,"short packet has wrong length or abort beat");
        end
    end
    initial begin
        repeat(10) @(negedge cam_clk);
        rst_n=1;
        repeat(10) @(negedge cam_clk);
        for(y=0;y<1066;y=y+1) begin
            for(x=0;x<480;x=x+1) begin
                valid=1;sof=(x==0 && y==0);eol=(x==479);
                rgb={4{32'h00101010}};
                @(negedge cam_clk);
            end
            valid=0;sof=0;eol=0;
            repeat(8) @(negedge cam_clk);
        end
        repeat(40) @(negedge cam_clk);
        valid=1;sof=1;eol=0;
        @(negedge cam_clk);
        valid=0;sof=0;
        repeat(200) @(negedge cam_clk);
        if(last_count!=1 || frames!=0 || errors!=1 || pass!=0 ||
           drop!=1 || delivered!=1)
            $fatal(1,"abort counters last=%0d frames=%0d errors=%0d pass=%0d drop=%0d delivered=%0d",
                   last_count,frames,errors,pass,drop,delivered);
        $display("PASS short 1066-row frame rejected: %0d data beats + abort",beats-1);
        $finish;
    end
    initial begin #100000000; $fatal(1,"TIMEOUT"); end
endmodule
