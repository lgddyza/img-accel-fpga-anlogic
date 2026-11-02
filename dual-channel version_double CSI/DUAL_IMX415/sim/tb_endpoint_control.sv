`timescale 1ns/1ps
// Production AXI-Lite body and real mailboxes; inert JPEG interface stub.
module tb_endpoint_control;
    reg user_clk=0,pipe_clk=0,user_rst_n=0,run_pipe=1,hold_pipe_reset=0;
    always #4 user_clk=~user_clk;always #3.75 if(run_pipe) pipe_clk=~pipe_clk;
    wire stream_reset_n;wire pipe_rst_n=stream_reset_n && !hold_pipe_reset;
    wire link_up=1'b1,msi_enable=1'b1,jpeg_enc_clk=pipe_clk,jpeg_pll_lock=1'b1;
    reg [31:0] awaddr=0,wdata=0,araddr=0;reg [3:0] wstrb=0;
    reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
    wire awready,wready,arready;reg bvalid,rvalid;reg [31:0] rdata;
    wire [127:0] metadata=128'd0,processed_rgb=128'd0;
    wire metadata_valid=1'b0;wire metadata_ready;
    wire processed_valid=1'b0,processed_sof=1'b0,processed_eol=1'b0;
    wire [671:0] statistics={32'h12345678,32'd91,32'd79,32'd63,32'h00000009,512'd0};
    wire [511:0] pipeline_statistics={16{32'habcdef01}};
    reg [1535:0] store_diagnostics={48{32'h44353031}};
    reg [511:0] feature_result=0;
    reg feature_valid=0;
    wire feature_ready;
    wire [35:0] jpeg_input_levels;
    wire diag_clk=user_clk;
    reg [575:0] diagnostics={32'h0000c010,32'h0000510d,{16{32'h1234abcd}}};
    wire capture_enable;wire [2:0] mode_a,mode_b;
    wire [2:0] strength_a,strength_b;
    wire [6:0] quality_pipe,quality_b_pipe,quality_applied_pipe;wire independent_qf_pipe;wire [31:0] config_epoch;
    wire jpeg_armed,jpeg_done,jpeg_fault_pipe,jpeg_input_ready;
    wire [127:0] jpeg_a_data,jpeg_b_data,jpeg_c_data;
    wire [15:0] jpeg_a_keep,jpeg_b_keep,jpeg_c_keep;
    wire jpeg_a_valid,jpeg_b_valid,jpeg_c_valid,jpeg_a_last,jpeg_b_last,jpeg_c_last;
    wire jpeg_a_ready=1'b1,jpeg_b_ready=1'b1,jpeg_c_ready=1'b1;
`include "rtl/v2_endpoint_body.vh"
    task write_reg(input [31:0] addr,value,input [3:0] strobes,input integer skew);
        begin
            fork
                begin
                    @(negedge user_clk);awaddr=addr;awvalid=1;
                    do @(posedge user_clk);while(!awready);
                    @(negedge user_clk);awvalid=0;
                end
                begin
                    repeat(skew) @(negedge user_clk);
                    @(negedge user_clk);wdata=value;wstrb=strobes;wvalid=1;
                    do @(posedge user_clk);while(!wready);
                    @(negedge user_clk);wvalid=0;
                end
            join
            wait(bvalid);repeat(3) @(negedge user_clk);bready=1;
            @(negedge user_clk);bready=0;
        end
    endtask
    task read_check(input [31:0] addr,expected);
        begin
            @(negedge user_clk);araddr=addr;arvalid=1;
            do @(posedge user_clk);while(!arready);
            @(negedge user_clk);arvalid=0;wait(rvalid);
            if(rdata!==expected) $fatal(1,"BAR[%h] expected=%h got=%h",addr,expected,rdata);
            repeat(3) @(negedge user_clk);
            if(rdata!==expected || !rvalid) $fatal(1,"read response changed during stall");
            rready=1;@(negedge user_clk);rready=0;
        end
    endtask
    integer pulses=0;reg prev_reset=0;
    always @(posedge user_clk) begin
        if(user_rst_n && prev_reset && !stream_reset_n) pulses=pulses+1;
        prev_reset=stream_reset_n;
    end
    initial begin
        repeat(5) @(negedge user_clk);user_rst_n=1;
        wait(stream_reset_n);repeat(40) @(negedge user_clk);
        read_check('h284,'h20261024);read_check('h288,'h444c5931);
        read_check('h28c,'h434c4139);read_check('h290,0);read_check('h294,0);read_check('h298,16384);
        read_check('h22c,'h44);
        read_check('h6f0,'h3153424f);
        read_check('h700,0);read_check('h740,0);
        @(negedge pipe_clk);feature_result={16{32'h22222222}};feature_result[28]=0;feature_valid=1;
        do @(posedge pipe_clk);while(!feature_ready);
        @(negedge pipe_clk);feature_valid=0;
        repeat(40) @(negedge user_clk);
        read_check('h700,'h22222222);read_check('h704,'h22222222);
        @(negedge pipe_clk);feature_result={16{32'h44444444}};feature_result[28]=1;feature_valid=1;
        do @(posedge pipe_clk);while(!feature_ready);
        @(negedge pipe_clk);feature_valid=0;
        repeat(40) @(negedge user_clk);
        read_check('h73c,'h22222222);read_check('h740,'h54444444);
        read_check('h744,'h44444444);read_check('h77c,'h44444444);
        read_check('h700,'h22222222);read_check('h704,'h22222222);
        read_check('h500,'h44353031);
        store_diagnostics={48{32'hdeadbeef}};repeat(40) @(negedge user_clk);
        read_check('h504,'h44353031);read_check('h5bc,'h44353031);
        read_check('h500,'hdeadbeef);read_check('h504,'hdeadbeef);read_check('h5bc,'hdeadbeef);
        read_check('h600,0);read_check('h620,0);
        @(negedge user_clk);
        force jpeg_a_valid=1;force jpeg_a_keep=16'hffff;force jpeg_a_last=0;
        force jpeg_a_ready=0;
        repeat(5) @(negedge user_clk);
        force jpeg_a_ready=1;
        repeat(4) @(negedge user_clk);
        force jpeg_a_keep=16'h0003;force jpeg_a_last=1;
        @(negedge user_clk);force jpeg_a_valid=0;
        read_check('h600,66);read_check('h604,0);read_check('h608,1);
        read_check('h60c,0);read_check('h618,0);
        release jpeg_a_valid;release jpeg_a_keep;release jpeg_a_last;release jpeg_a_ready;
        read_check('h400,'habcdef01);read_check('h43c,'habcdef01);read_check('h480,0);
        read_check('h348,9);read_check('h34c,63);read_check('h350,79);read_check('h354,91);
        read_check('h358,'h12345678);
        read_check('h300,'h1234abcd);read_check('h33c,'h1234abcd);
        read_check('h340,'h510d);read_check('h344,'hc010);
        read_check('h200,'h32435644);read_check('h280,'h3f);
        write_reg('h218,'h7fff407f,4'hf,3);read_check('h218,'h4081);
        repeat(40) @(negedge user_clk);
        if(mode_a!==0 || mode_b!==0 || quality_pipe!==1) $fatal(1,"illegal config reached pipeline");
        write_reg('h218,(100<<7)|(3<<4)|(2<<1)|1,4'h3,0);
        write_reg('h218,(85<<7)|(1<<4)|(3<<1)|1,4'h3,1);
        repeat(80) @(negedge user_clk);
        if(mode_a!==3 || mode_b!==1 || quality_pipe!==85) $fatal(1,"latest CLA1 CDC tuple lost");
        write_reg('h218,'h00000081,4'h1,2);read_check('h218,(85<<7)|1);
        write_reg('h218,(127<<7)|(2<<1)|1,4'h3,0);read_check('h218,(100<<7)|(2<<1)|1);
        write_reg('h218,'h80000000,4'h8,0);
        wait(stream_reset_n);repeat(80) @(negedge user_clk);
        read_check('h218,(100<<7)|(2<<1)|1);
        if(pulses!=1 || mode_a!==2 || quality_pipe!==100) $fatal(1,"reset restore failed");
        read_check('h21c,5);
        write_reg('h22c,'h71,4'h1,2);read_check('h22c,'h41);
        repeat(40) @(negedge user_clk);
        if(strength_a!==1 || strength_b!==4) $fatal(1,"strength normalization/CDC failed");
        write_reg('h218,(85<<7)|(5<<4)|(1<<1)|1,4'h3,1);
        repeat(40) @(negedge user_clk);
        if(mode_a!==1 || mode_b!==5 || strength_a!==1 || strength_b!==4)
            $fatal(1,"mode write destroyed strength tuple");
        read_check('h218,(85<<7)|(5<<4)|(1<<1)|1);
        write_reg('h22c,'h13,4'h2,0);read_check('h22c,'h41);read_check('h21c,7);
        read_check('h2a4,'h32465144);read_check('h2a0,(85<<8)|85);
        write_reg('h2a0,(1<<16)|(30<<8)|95,4'h7,2);
        read_check('h2a0,(1<<16)|(30<<8)|95);
        repeat(50) @(negedge user_clk);
        if(quality_pipe!==95 || quality_b_pipe!==30 || !independent_qf_pipe)
            $fatal(1,"independent QF tuple did not cross clock domain");
        write_reg('h2a0,(127<<8),4'h2,1);
        read_check('h2a0,(1<<16)|(100<<8)|95);
        write_reg('h2a0,0,4'h1,0);
        read_check('h2a0,(1<<16)|(100<<8)|1);
        write_reg('h2a0,0,4'h4,0);
        read_check('h2a0,(100<<8)|1);
        repeat(50) @(negedge user_clk);
        if(quality_pipe!==1 || quality_b_pipe!==100 || independent_qf_pipe)
            $fatal(1,"QF normalization or shared fallback failed");
        write_reg('h218,(85<<7)|(4<<4)|(4<<1)|1,4'h3,1);
        repeat(50) @(negedge user_clk);
        if(mode_a!==4 || mode_b!==4) $fatal(1,"Sobel mode did not cross clock domain");
        hold_pipe_reset=1;run_pipe=0;diagnostics={18{32'h98765432}};
        repeat(80) @(negedge user_clk);
        read_check('h300,'h98765432);read_check('h33c,'h98765432);
        read_check('h340,'h98765432);read_check('h344,'h98765432);
        $display("PASS diagnostics remain live with DDR/pipeline clock stopped and pipeline held reset");
        $display("PASS AXI-Lite AW/W stalls, WSTRB/QF bounds, PRF1 modes/strength, latest CDC and stream reset");$finish;
    end
    initial begin #100000;$fatal(1,"endpoint control timeout");end
endmodule
