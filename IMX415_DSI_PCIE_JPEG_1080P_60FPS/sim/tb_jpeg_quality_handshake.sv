`timescale 1ns/1ps

module tb_jpeg_quality_handshake;
    reg cam_clk=0,enc_clk=0,user_clk=0,rst_n=0;
    always #20 cam_clk=~cam_clk;
    always #2.5 enc_clk=~enc_clk;
    always #4 user_clk=~user_clk;

    reg [6:0] quality=7'd85;
    wire configured,busy,fault;
    wire [6:0] applied_quality;
    wire [31:0] sent_a,sent_b,sent_c,fault_count;
    wire [31:0] bytes_a,bytes_b,bytes_c;

    jpeg_triple_tile_branch #(.IMG_WIDTH(64),.IMG_HEIGHT(24)) dut (
        .cam_clk(cam_clk),.cam_rst_n(rst_n),
        .user_clk(user_clk),.user_rst_n(rst_n),
        .enc_clk(enc_clk),.enc_pll_lock(1'b1),
        .s_rgb4(128'd0),.s_valid(1'b0),.s_sof(1'b0),.s_eol(1'b0),
        .enable(1'b0),.reset_pulse(1'b0),.link_up(1'b1),
        .full_rate(1'b1),.quality(quality),
        .a_ready(1'b1),.b_ready(1'b1),.c_ready(1'b1),
        .a_data(),.a_keep(),.a_valid(),.a_last(),
        .b_data(),.b_keep(),.b_valid(),.b_last(),
        .c_data(),.c_keep(),.c_valid(),.c_last(),
        .status_configured(configured),.status_busy(busy),
        .status_fault(fault),.status_quality(applied_quality),
        .sent_a(sent_a),.sent_b(sent_b),.sent_c(sent_c),
        .fault_count(fault_count),.bytes_a(bytes_a),
        .bytes_b(bytes_b),.bytes_c(bytes_c),
        .debug_status(),.debug_detail()
    );

    task set_and_check(input [6:0] next_quality);
        begin
            @(negedge user_clk);
            quality=next_quality;
            wait(!configured);
            wait(configured);
            if(applied_quality!=next_quality)
                $fatal(1,"requested %0d but applied %0d",
                       next_quality,applied_quality);
        end
    endtask

    initial begin
        repeat(10) @(negedge user_clk);
        rst_n=1;
        wait(configured);
        if(applied_quality!=7'd85)
            $fatal(1,"initial applied quality %0d",applied_quality);
        set_and_check(7'd50);
        set_and_check(7'd90);
        if(busy || fault || fault_count || sent_a || sent_b || sent_c)
            $fatal(1,"unexpected data-path activity during control test");
        $display("JPEG_QUALITY_HANDSHAKE_PASS applied=%0d",applied_quality);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1,"quality handshake timeout requested=%0d applied=%0d ready=%b",
               quality,applied_quality,configured);
    end
endmodule
