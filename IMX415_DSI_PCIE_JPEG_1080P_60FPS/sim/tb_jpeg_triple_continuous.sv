`timescale 1ns/1ps
// Three source frames in full-rate mode: encode every frame.
module tb_jpeg_triple_continuous;
    reg cam_clk=0,enc_clk=0,user_clk=0,rst_n=0;
    always #20 cam_clk=~cam_clk;
    always #2.5 enc_clk=~enc_clk;
    always #4 user_clk=~user_clk;
    reg [127:0] rgb=0;
    reg valid=0,sof=0,eol=0;
    wire [127:0] a_data,b_data,c_data;
    wire [15:0] a_keep,b_keep,c_keep;
    wire a_valid,a_last,b_valid,b_last,c_valid,c_last;
    wire configured,busy,fault;
    wire [31:0] sent_a,sent_b,sent_c,fault_count,bytes_a,bytes_b,bytes_c;
    jpeg_triple_tile_branch #(.IMG_WIDTH(64),.IMG_HEIGHT(24)) dut (
        .cam_clk(cam_clk),.cam_rst_n(rst_n),
        .user_clk(user_clk),.user_rst_n(rst_n),
        .enc_clk(enc_clk),.enc_pll_lock(1'b1),
        .s_rgb4(rgb),.s_valid(valid),.s_sof(sof),.s_eol(eol),
        .enable(1'b1),.reset_pulse(1'b0),.link_up(1'b1),
        .full_rate(1'b1),
        .quality(7'd85),.a_ready(1'b1),.b_ready(1'b1),.c_ready(1'b1),
        .a_data(a_data),.a_keep(a_keep),.a_valid(a_valid),.a_last(a_last),
        .b_data(b_data),.b_keep(b_keep),.b_valid(b_valid),.b_last(b_last),
        .c_data(c_data),.c_keep(c_keep),.c_valid(c_valid),.c_last(c_last),
        .status_configured(configured),.status_busy(busy),.status_fault(fault),
        .sent_a(sent_a),.sent_b(sent_b),.sent_c(sent_c),
        .fault_count(fault_count),.bytes_a(bytes_a),.bytes_b(bytes_b),
        .bytes_c(bytes_c)
    );
    task send_frame(input integer number);
        integer x,y,k;
        begin
            for(y=0;y<24;y=y+1) begin
                for(x=0;x<16;x=x+1) begin
                    @(negedge cam_clk);
                    valid=1;sof=(x==0 && y==0);eol=(x==15);
                    for(k=0;k<4;k=k+1)
                        rgb[k*32 +: 32]={24'd0,8'((x*4+k+y*7+number*31)&255)};
                end
                @(negedge cam_clk);
                valid=0;sof=0;eol=0;
                repeat(16) @(negedge cam_clk);
            end
        end
    endtask
    initial begin
        repeat(10) @(negedge user_clk);
        rst_n=1;
        wait(configured);
        repeat(20) @(negedge cam_clk);
        send_frame(0);
        send_frame(1);
        send_frame(2);
        wait(sent_a==3 && sent_b==3 && sent_c==3);
        repeat(10) @(negedge user_clk);
        if(fault || fault_count || !bytes_a || !bytes_b || !bytes_c)
            $fatal(1,"continuous JPEG failed");
        $display("JPEG_TRIPLE_CONTINUOUS_PASS sent=%0d/%0d/%0d",sent_a,sent_b,sent_c);
        $finish;
    end
    initial begin #5000000; $fatal(1,"continuous JPEG timeout sent=%0d/%0d/%0d fault=%b busy=%b",
        sent_a,sent_b,sent_c,fault,busy); end
endmodule
