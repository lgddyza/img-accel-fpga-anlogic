`timescale 1ns/1ps
module tb_jpeg_gray4_axis_faults;
    reg cam_clk=0, enc_clk=0, rst_n=0;
    always #5 cam_clk=~cam_clk;
    always #2.5 enc_clk=~enc_clk;
    reg valid=0, sof=0, eol=0;
    wire fault;
    wire [3:0] cause;
    wire [9:0] line, beat;
    jpeg_gray4_axis_cdc #(.IMG_WIDTH(16),.IMG_HEIGHT(16),
                          .FIFO_ADDR_WIDTH(4)) dut (
        .cam_clk(cam_clk),.enc_clk(enc_clk),.rst_n(rst_n),
        .s_yuyv4(64'd0),.s_valid(valid),.s_sof(sof),.s_eol(eol),
        .s_take_frame(1'b1),.s_fault(fault),
        .s_fault_cause(cause),.s_fault_line(line),.s_fault_beat(beat),
        .s_selected_frames(),.s_completed_frames(),
        .m_tdata(),.m_tvalid(),.m_tready(1'b0),.m_tuser(),
        .m_tlast(),.m_fault()
    );
    task send_line(input bit first_line);
        integer x;
        begin
            for(x=0;x<4;x=x+1) begin
                @(negedge cam_clk);
                valid=1;sof=first_line && x==0;eol=x==3;
            end
            @(negedge cam_clk);
            valid=0;sof=0;eol=0;
        end
    endtask
    initial begin
        repeat(5) @(negedge cam_clk);
        rst_n=1;
        send_line(1);
        send_line(0);
        // Starting a new selected image before 16 lines must preserve the
        // first fault position, before the next SOF resets cur_y to zero.
        @(negedge cam_clk);
        valid=1;sof=1;eol=0;
        @(negedge cam_clk);
        valid=0;sof=0;
        if(!fault || cause!=4'b0001 || line!=2 || beat!=0)
            $fatal(1,"unexpected early SOF result %b/%b line=%d beat=%d",
                   fault,cause,line,beat);
        rst_n=0;
        repeat(5) @(negedge cam_clk);
        rst_n=1;
        // Stop the read side and exceed the 16-word input FIFO.
        repeat(6) send_line(0);
        if(fault) $fatal(1,"unselected input filled the FIFO");
        send_line(1);
        repeat(5) send_line(0);
        if(!fault || !cause[3])
            $fatal(1,"FIFO-full cause missing: fault=%b cause=%b line=%d beat=%d",
                   fault,cause,line,beat);
        $display("JPEG_INPUT_FAULT_DETAIL_PASS cause=%b line=%d beat=%d",
                 cause,line,beat);
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule
