`timescale 1ns/1ps
module tb_jpeg_triple_tile_branch;
`ifdef FULL_TEST
    localparam integer TEST_WIDTH=1920;
    localparam integer TEST_HEIGHT=1080;
`ifdef REAL_CAM_TIMING
    localparam integer LINE_BLANK=909;
`else
    localparam integer LINE_BLANK=675;
`endif
`elsif MID_TEST
    localparam integer TEST_WIDTH=1920;
    localparam integer TEST_HEIGHT=240;
    localparam integer LINE_BLANK=675;
`elsif LARGE_TEST
    localparam integer TEST_WIDTH=1920;
    localparam integer TEST_HEIGHT=24;
    localparam integer LINE_BLANK=675;
`else
    localparam integer TEST_WIDTH=64;
    localparam integer TEST_HEIGHT=24;
    localparam integer LINE_BLANK=16;
`endif
`ifdef NOISE_Q50
    localparam [6:0] TEST_QUALITY=7'd50;
`elsif NOISE_Q30
    localparam [6:0] TEST_QUALITY=7'd30;
`else
    localparam [6:0] TEST_QUALITY=7'd85;
`endif
    reg cam_clk=0,enc_clk=0,user_clk=0,rst_n=0;
`ifdef FULL_TEST
`ifdef REAL_CAM_TIMING
    always #5.554 cam_clk=~cam_clk;
`else
    always #6.667 cam_clk=~cam_clk;
`endif
`elsif MID_TEST
    always #6.667 cam_clk=~cam_clk;
`elsif LARGE_TEST
    always #6.667 cam_clk=~cam_clk;
`else
    always #20 cam_clk=~cam_clk;
`endif
`ifdef FAST_ENC
    always #2.5 enc_clk=~enc_clk;
`else
    always #3.333 enc_clk=~enc_clk;
`endif
    always #4 user_clk=~user_clk;
    reg [127:0] rgb=0;
    reg valid=0,sof=0,eol=0;
    wire [127:0] a_data,b_data,c_data;
    wire [15:0] a_keep,b_keep,c_keep;
    wire a_valid,b_valid,c_valid,a_last,b_last,c_last,configured,busy,fault;
    wire [6:0] applied_quality;
    wire [31:0] sent_a,sent_b,sent_c,fault_count,bytes_a,bytes_b,bytes_c;
    reg [7:0] prev_a=0,prev_b=0,prev_c=0;
    reg soi_a=0,soi_b=0,soi_c=0,eoi_a=0,eoi_b=0,eoi_c=0;
    reg done_a=0,done_b=0,done_c=0;
    integer fa,fb,fc,x,y,k,i,count_a=0,count_b=0,count_c=0;
    function [7:0] test_pixel(input integer xx,input integer yy);
        reg [31:0] h;
        begin
`ifdef NOISE_TEST
            h=(xx*32'd3266489917)^(yy*32'd2246822519);
            h=h^(h>>15);
            h=h*32'd2246822519;
            test_pixel=h[23:16];
`else
            test_pixel=(yy*7+xx)&255;
`endif
        end
    endfunction
    jpeg_triple_tile_branch #(.IMG_WIDTH(TEST_WIDTH),.IMG_HEIGHT(TEST_HEIGHT)) dut (
        .cam_clk(cam_clk),.cam_rst_n(rst_n),
        .user_clk(user_clk),.user_rst_n(rst_n),
        .enc_clk(enc_clk),.enc_pll_lock(1'b1),
        .s_rgb4(rgb),.s_valid(valid),.s_sof(sof),.s_eol(eol),
        .enable(1'b1),.reset_pulse(1'b0),.link_up(1'b1),
        .full_rate(1'b0),
        .quality(TEST_QUALITY),.a_ready(1'b1),.b_ready(1'b1),.c_ready(1'b1),
        .a_data(a_data),.a_keep(a_keep),.a_valid(a_valid),
        .a_last(a_last),.b_data(b_data),.b_keep(b_keep),
        .b_valid(b_valid),.b_last(b_last),.c_data(c_data),
        .c_keep(c_keep),.c_valid(c_valid),.c_last(c_last),
        .status_configured(configured),.status_busy(busy),
        .status_fault(fault),.status_quality(applied_quality),
        .sent_a(sent_a),.sent_b(sent_b),.sent_c(sent_c),
        .fault_count(fault_count),.bytes_a(bytes_a),.bytes_b(bytes_b),.bytes_c(bytes_c)
    );
    initial begin
`ifdef FULL_TEST
        fa=$fopen("jpeg_triple_a_1920x360.jpg","wb");
        fb=$fopen("jpeg_triple_b_1920x360.jpg","wb");
        fc=$fopen("jpeg_triple_c_1920x360.jpg","wb");
`elsif MID_TEST
        fa=$fopen("jpeg_triple_a_1920x80.jpg","wb");
        fb=$fopen("jpeg_triple_b_1920x80.jpg","wb");
        fc=$fopen("jpeg_triple_c_1920x80.jpg","wb");
`elsif LARGE_TEST
        fa=$fopen("jpeg_triple_a_1920x8.jpg","wb");
        fb=$fopen("jpeg_triple_b_1920x8.jpg","wb");
        fc=$fopen("jpeg_triple_c_1920x8.jpg","wb");
`else
        fa=$fopen("jpeg_triple_a_64x8.jpg","wb");
        fb=$fopen("jpeg_triple_b_64x8.jpg","wb");
        fc=$fopen("jpeg_triple_c_64x8.jpg","wb");
`endif
    end
    always @(posedge user_clk) begin
        if(fault) $fatal(1,"triple fault y=%0d bridge=%b packer=%b A_full=%b A_malformed=%b A_active=%b A_line=%0d A_x=%0d C_full=%b C_malformed=%b C_active=%b C_line=%0d C_x=%0d C_ready=%b counts=%0d/%0d/%0d",
            dut.source_y,dut.bridge_fault,dut.packer_fault,
            dut.g_tile[0].u_input.fifo_full,dut.g_tile[0].u_input.malformed,
            dut.g_tile[0].u_input.frame_active,dut.g_tile[0].u_input.line_y,
            dut.g_tile[0].u_input.beat_x,
            dut.g_tile[2].u_input.fifo_full,dut.g_tile[2].u_input.malformed,
            dut.g_tile[2].u_input.frame_active,dut.g_tile[2].u_input.line_y,
            dut.g_tile[2].u_input.beat_x,dut.vid_ready[2],count_a,count_b,count_c);
        if(a_valid) begin
            for(i=0;i<16;i=i+1) if(a_keep[i]) begin
                $fwrite(fa,"%c",a_data[i*8 +: 8]);
                if(prev_a==8'hff && a_data[i*8 +: 8]==8'hd8) soi_a=1;
                if(prev_a==8'hff && a_data[i*8 +: 8]==8'hd9) eoi_a=1;
                prev_a=a_data[i*8 +: 8];count_a=count_a+1;
            end
            if(a_last) begin $fclose(fa);done_a=1; end
        end
        if(b_valid) begin
            for(i=0;i<16;i=i+1) if(b_keep[i]) begin
                $fwrite(fb,"%c",b_data[i*8 +: 8]);
                if(prev_b==8'hff && b_data[i*8 +: 8]==8'hd8) soi_b=1;
                if(prev_b==8'hff && b_data[i*8 +: 8]==8'hd9) eoi_b=1;
                prev_b=b_data[i*8 +: 8];count_b=count_b+1;
            end
            if(b_last) begin $fclose(fb);done_b=1; end
        end
        if(c_valid) begin
            for(i=0;i<16;i=i+1) if(c_keep[i]) begin
                $fwrite(fc,"%c",c_data[i*8 +: 8]);
                if(prev_c==8'hff && c_data[i*8 +: 8]==8'hd8) soi_c=1;
                if(prev_c==8'hff && c_data[i*8 +: 8]==8'hd9) eoi_c=1;
                prev_c=c_data[i*8 +: 8];count_c=count_c+1;
            end
            if(c_last) begin $fclose(fc);done_c=1; end
        end
    end
    initial begin
        repeat(10) @(negedge user_clk);
        rst_n=1;
        wait(configured);
        if(applied_quality!=TEST_QUALITY)
            $fatal(1,"unexpected applied quality %0d",applied_quality);
        repeat(20) @(negedge cam_clk);
        for(y=0;y<TEST_HEIGHT;y=y+1) begin
            for(x=0;x<TEST_WIDTH/4;x=x+1) begin
                @(negedge cam_clk);
                valid=1;sof=(y==0 && x==0);eol=(x==TEST_WIDTH/4-1);
                for(k=0;k<4;k=k+1)
                    rgb[k*32 +: 32]={24'd0,test_pixel(x*4+k,y)};
            end
            @(negedge cam_clk);
            valid=0;sof=0;eol=0;
            repeat(LINE_BLANK) @(negedge cam_clk);
        end
        wait(done_a && done_b && done_c);
        repeat(10) @(negedge user_clk);
        if(fault || fault_count || sent_a!=1 || sent_b!=1 || sent_c!=1 ||
           bytes_a!=count_a || bytes_b!=count_b || bytes_c!=count_c ||
           !soi_a || !soi_b || !soi_c || !eoi_a || !eoi_b || !eoi_c)
            $fatal(1,"triple tiles failed: fault=%b/%d sent=%d/%d/%d bytes=%d/%d,%d/%d,%d/%d markers=%b%b%b%b%b%b",
                fault,fault_count,sent_a,sent_b,sent_c,bytes_a,count_a,
                bytes_b,count_b,bytes_c,count_c,soi_a,soi_b,soi_c,eoi_a,eoi_b,eoi_c);
        $display("JPEG_TRIPLE_TILE_PASS A=%0d B=%0d C=%0d",count_a,count_b,count_c);
        $finish;
    end
    initial begin #50000000; $fatal(1,"triple tile timeout counts=%0d/%0d/%0d fault=%b busy=%b sent=%0d/%0d/%0d",
        count_a,count_b,count_c,fault,busy,sent_a,sent_b,sent_c); end
endmodule
