`timescale 1ns/1ps
module tb_jpeg_gray4_axis_cdc;
    reg cam_clk = 0, enc_clk = 0;
    always #6 cam_clk = ~cam_clk;
    // Source: four pixels / 12 ns during a line; encoder: one pixel / 6 ns.
    // Four source blank clocks let the encoder drain each 16-pixel line.
    always #3 enc_clk = ~enc_clk;
    reg rst_n = 0;
    reg [63:0] s_yuyv4 = 0;
    reg s_valid = 0, s_sof = 0, s_eol = 0, s_take_frame = 0;
    reg m_tready = 1;
    wire s_fault, m_fault;
    wire [31:0] s_selected_frames, s_completed_frames;
    wire [15:0] m_tdata;
    wire m_tvalid, m_tuser, m_tlast;
    integer received = 0;
    integer y, x, k;

    jpeg_gray4_axis_cdc #(.IMG_WIDTH(16), .IMG_HEIGHT(8),
        .FIFO_ADDR_WIDTH(4)) dut (
        .cam_clk(cam_clk), .enc_clk(enc_clk), .rst_n(rst_n),
        .s_yuyv4(s_yuyv4), .s_valid(s_valid), .s_sof(s_sof),
        .s_eol(s_eol), .s_take_frame(s_take_frame),
        .s_fault(s_fault), .s_selected_frames(s_selected_frames),
        .s_completed_frames(s_completed_frames),
        .m_tdata(m_tdata), .m_tvalid(m_tvalid),
        .m_tready(m_tready), .m_tuser(m_tuser),
        .m_tlast(m_tlast), .m_fault(m_fault)
    );

    always @(posedge enc_clk) begin
        if (rst_n && m_tvalid && m_tready) begin
            if (m_tdata !== {8'h80,received[7:0]})
                $fatal(1,"pixel %0d got %h",received,m_tdata);
            if (m_tuser !== (received == 0))
                $fatal(1,"SOF at pixel %0d",received);
            if (m_tlast !== ((received % 16) == 15))
                $fatal(1,"EOL at pixel %0d",received);
            received = received + 1;
        end
    end

    task send_frame;
        input take;
        begin
            for (y=0;y<8;y=y+1) begin
                for (x=0;x<4;x=x+1) begin
                    @(negedge cam_clk);
                    s_valid = 1;
                    s_sof = (x==0 && y==0);
                    s_eol = (x==3);
                    s_take_frame = take;
                    for (k=0;k<4;k=k+1)
                        s_yuyv4[k*16 +: 16] = 16'h8000 | ((y*16+x*4+k) & 16'hff);
                end
                @(negedge cam_clk);
                s_valid = 0; s_sof = 0; s_eol = 0;
                repeat(4) @(negedge cam_clk);
            end
        end
    endtask

    initial begin
        repeat(8) @(negedge cam_clk);
        rst_n = 1;
        send_frame(0);
        if (received != 0) $fatal(1,"skipped frame emitted data");
        send_frame(1);
        repeat(200) @(negedge enc_clk);
        if (received != 128 || s_selected_frames != 1 ||
            s_completed_frames != 1 || s_fault || m_fault)
            $fatal(1,"normal frame: pixels=%0d selected=%0d complete=%0d fault=%b",
                received,s_selected_frames,s_completed_frames,s_fault);
        $display("JPEG_GRAY4_CDC_FRAME_PASS");

        @(negedge cam_clk); rst_n = 0; m_tready = 0;
        repeat(8) @(negedge cam_clk); rst_n = 1;
        send_frame(1);
        repeat(8) @(negedge enc_clk);
        if (!s_fault || !m_fault || m_tvalid)
            $fatal(1,"overflow did not stop frame safely");
        $display("JPEG_GRAY4_CDC_OVERFLOW_PASS");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1,"timeout");
    end
endmodule
