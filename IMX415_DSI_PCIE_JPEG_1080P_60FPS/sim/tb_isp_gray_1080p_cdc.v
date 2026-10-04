`timescale 1ns/1ps
module tb_isp_gray_1080p_cdc;
    reg cam_clk=0,user_clk=0;
    always #4 cam_clk=~cam_clk;
    always #3.5 user_clk=~user_clk;
    reg rst_n=0,valid=0,sof=0,eol=0,ready=1;
    reg [127:0] rgb=0;
    wire [127:0] data;
    wire out_valid,out_last,pixel_valid;
    wire [31:0] frames,errors,pass,drop,delivered;
    integer x,y,k,word_count=0,byte_count=0,cycle_count=0;
    reg [7:0] expected;
    reg [7:0] p;
    isp_gray_1080p_cdc dut (
        .cam_clk(cam_clk),.cam_rst_n(rst_n),
        .s_tdata(rgb),.s_tvalid(valid),.s_tuser(sof),.s_tlast(eol),
        .user_clk(user_clk),.user_rst_n(rst_n),.enable(1'b1),
        .dma_ready(ready),.m_tdata(data),.m_tvalid(out_valid),
        .m_tready(ready),.m_tlast(out_last),.pixel_valid(pixel_valid),
        .frame_count(frames),.error_count(errors),
        .pass_count(pass),.drop_count(drop),.delivered_count(delivered)
    );
    always @(posedge user_clk) begin
        cycle_count<=cycle_count+1;
        if(rst_n && out_valid && ready) begin
            for(k=0;k<16;k=k+1) begin
                expected=(byte_count+k) & 8'hff;
                if(data[k*8+:8] !== expected) begin
                    $display("BAD BYTE %0d got=%0h expected=%0h",byte_count+k,
                             data[k*8+:8],expected);
                    $fatal(1);
                end
            end
            byte_count=byte_count+16;
            word_count=word_count+1;
            if(out_last !== (word_count==129600))
                $fatal(1,"BAD LAST at word %0d",word_count);
        end
        if(cycle_count%37==0) ready<=0;
        else if(cycle_count%37==3) ready<=1;
    end
    initial begin
        repeat(10) @(negedge cam_clk);
        rst_n=1;
        repeat(10) @(negedge cam_clk);
        for(y=0;y<1080;y=y+1) begin
            for(x=0;x<480;x=x+1) begin
                valid=1;sof=(x==0 && y==0);eol=(x==479);
                p=((y*1920+x*4)&255);
                rgb={8'd0,p+8'd3,p+8'd3,p+8'd3,
                     8'd0,p+8'd2,p+8'd2,p+8'd2,
                     8'd0,p+8'd1,p+8'd1,p+8'd1,
                     8'd0,p,p,p};
                @(negedge cam_clk);
            end
            valid=0;sof=0;eol=0;
            repeat(8) @(negedge cam_clk);
        end
        valid=0;sof=0;eol=0;
        repeat(1000) @(negedge cam_clk);
        if(word_count!=129600 || byte_count!=2073600 || pass!=1 ||
           frames!=1 || errors!=0 || drop!=0 || delivered!=1)
            $fatal(1,"counts words=%0d bytes=%0d pass=%0d frames=%0d errors=%0d drop=%0d delivered=%0d",
                   word_count,byte_count,pass,frames,errors,drop,delivered);
        $display("PASS 1920x1080 GREY: %0d bytes, %0d DMA beats",byte_count,word_count);
        $finish;
    end
    initial begin #100000000; $fatal(1,"TIMEOUT"); end
endmodule
