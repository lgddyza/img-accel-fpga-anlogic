`timescale 1ns/1ps
module tb_frame_store #(
    parameter W=64,H=24,STRIDE=4096,CAP_FIFO_ADDR=10,BURST=0,DUAL_QF=0,
    parameter TIMEOUT_NS=10000000
);
    localparam N=W*H/8;
    reg clk=0,ca=0,cb=0,uc=0,rst=0;
    always #3.75 clk=~clk;
    always #5.55 ca=~ca;
    always #5.57 cb=~cb;
    always #4 uc=~uc;
    reg [39:0] ra=0,rb=0;
    reg va=0,sa=0,ea=0,vb=0,sb=0,eb=0;
    wire [127:0] ad,bd;wire av,bv,ard,brd;
    wire [31:0] srca,srcb,ova,ovb,fma,fmb;
    wire [15:0] a_level,b_level;
    v2_raw_capture #(.WIDTH(W),.HEIGHT(H),.FIFO_ADDR(CAP_FIFO_ADDR)) cap_a (
        .rst_n(rst),.cam_clk(ca),.raw(ra),.valid(va),.sof(sa),.eol(ea),.row_odd(1'b0),
        .mem_clk(clk),.data(ad),.data_valid(av),.data_ready(ard),.source_frames(srca),.overflow_frames(ova),.format_errors(fma),.queued_words(a_level));
    v2_raw_capture #(.WIDTH(W),.HEIGHT(H),.FIFO_ADDR(CAP_FIFO_ADDR)) cap_b (
        .rst_n(rst),.cam_clk(cb),.raw(rb),.valid(vb),.sof(sb),.eol(eb),.row_odd(1'b1),
        .mem_clk(clk),.data(bd),.data_valid(bv),.data_ready(brd),.source_frames(srcb),.overflow_frames(ovb),.format_errors(fmb),.queued_words(b_level));
    wire [27:0] aw,ar;wire [7:0] awlen,arlen;
    wire awv,wv,wl,bready,arv,rready;
    wire [127:0] wd;
    reg awready=0,wready=0,bvalid=0,arready=0,rvalid=0,rlast=0;
    reg [127:0] rd=0;
    reg [1:0] bresp=0,rresp=0;
    reg enable=1,jpeg_done=0;
    reg [6:0] jpeg_q=85,pending_q=85;
    integer qf_delay=0,qf_waits=0;
    integer raw_cycles=0;
    always @(posedge clk) raw_cycles<=raw_cycles+1;
    wire raw_ready=raw_cycles%113>47;
    wire [127:0] meta;wire mv,mready,camera;
    wire [2:0] mode;wire [39:0] raw;wire rawv,raws,rawe,odd;
    wire [31:0] caps_a,caps_b,drop_a,drop_b,del_a,del_b,errors;
    wire fault;wire [11:0] slotdbg;
    wire [127:0] first_fault;
    wire [1535:0] store_diagnostics;
    v2_frame_store #(.WIDTH(W),.HEIGHT(H),.SLOT_STRIDE(STRIDE),.RAW_IDLE_CYCLES(1)) dut (
        .clk(clk),.rst_n(rst),.a_data(ad),.b_data(bd),.a_valid(av),.b_valid(bv),.a_ready(ard),.b_ready(brd),
        .a_level(a_level),.b_level(b_level),
        .awaddr(aw),.awlen(awlen),.awvalid(awv),.awready(awready),.wdata(wd),.wlast(wl),.wvalid(wv),.wready(wready),
        .bresp(bresp),.bvalid(bvalid),.bready(bready),.araddr(ar),.arlen(arlen),.arvalid(arv),.arready(arready),
        .rdata(rd),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),
        .enable(enable),.mode_a(3'd1),.mode_b(3'd2),.strength_a(3'd1),.strength_b(3'd4),
        .quality(7'd85),.quality_b(7'd30),.jpeg_quality(jpeg_q),.independent_qf(DUAL_QF!=0),.config_epoch(32'd9),
        .jpeg_armed(1'b1),.jpeg_done(jpeg_done),.jpeg_fault(1'b0),.metadata(meta),.metadata_valid(mv),.metadata_ready(mready),
        .camera(camera),.frame_mode(mode),.raw(raw),.raw_valid(rawv),.raw_sof(raws),.raw_eol(rawe),.raw_first_row_odd(odd),
        .raw_ready(raw_ready),
        .captured_a(caps_a),.captured_b(caps_b),.dropped_a(drop_a),.dropped_b(drop_b),
        .delivered_a(del_a),.delivered_b(del_b),.axi_errors(errors),.slot_debug(slotdbg),.read_fault(fault),.first_fault(first_fault),.diagnostics(store_diagnostics));
    wire [127:0] um;wire umv;
    reg [127:0] current_meta=0;
    v2_mailbox #(.WIDTH(128)) mb (.rst_n(rst),.s_clk(clk),.s_data(meta),.s_valid(mv),.s_ready(mready),
        .m_clk(uc),.m_data(um),.m_valid(umv),.m_ready(1'b1));
    always @(posedge uc) if(umv) current_meta<=um;
    reg [127:0] mem[0:6*STRIDE/16-1];
    integer wa=0,wi=0,rraddr=0,rn=0;
    reg writing=0,reading=0;
    reg [31:0] random_state=32'h12345678;
    always @(posedge clk) begin
        random_state<={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        awready<=!writing && !bvalid && (BURST || random_state[0]);
        wready<=writing && (BURST || random_state[1]);
        arready<=!reading && (BURST || random_state[2]);
        if(awv && awready) begin
            if(writing || awlen!=15 || aw[7:0]!=0) $fatal(1,"bad AW");
            wa=aw/16;wi=0;writing=1;
        end
        if(wv && wready) begin
            if(!writing || wl!=(wi==15)) $fatal(1,"bad WLAST");
            mem[wa+wi]=wd;wi=wi+1;
            if(wl) begin writing=0;bvalid<=1;end
        end
        if(bvalid && bready) bvalid<=0;
        if(arv && arready) begin
            if(reading || arlen!=15) $fatal(1,"bad AR");
            reading=1;rraddr=ar/16;rn=0;
        end
        if(!rvalid || rready) begin
            rvalid<=0;
            if(reading && rn<16 && (BURST || random_state[3])) begin
                rd<=mem[rraddr+rn];rlast<=rn==15;rvalid<=1;rn=rn+1;
            end else if(reading && rn==16) reading=0;
        end
    end
    function [39:0] pattern(input integer cam,frame,beat);
        reg [9:0] p;begin p=(cam*512+frame*32+beat)%1024;pattern={p,p,p,p};end
    endfunction
    task send_a(input integer frame);
        begin
            for(integer i=0;i<W*H/4;i=i+1) begin
                @(negedge ca);va=1;sa=i==0;ea=i%(W/4)==W/4-1;ra=pattern(0,frame,i);
                if(!BURST || i%4==3) begin @(negedge ca);va=0;sa=0;ea=0;end
            end
        end
    endtask
    task send_b(input integer frame);
        begin
            for(integer i=0;i<W*H/4;i=i+1) begin
                @(negedge cb);vb=1;sb=i==0;eb=i%(W/4)==W/4-1;rb=pattern(1,frame,i);
                if(!BURST || i%4==3) begin @(negedge cb);vb=0;sb=0;eb=0;end
            end
        end
    endtask
    integer beats=0,frame_cam=0,frame_id=0,completed=0,tail=0;
    integer last_id[0:1];
    integer max_fifo_a=0,max_fifo_b=0;
    reg expect_write_error=0;
    initial begin last_id[0]=0;last_id[1]=0;end
    always @(posedge clk) if(rst) begin
        if(DUAL_QF && mv && mready && meta[54:48]!=jpeg_q) begin
            pending_q<=meta[54:48];qf_delay<=250;qf_waits<=qf_waits+1;
        end else if(qf_delay>0) begin
            qf_delay<=qf_delay-1;
            if(qf_delay==1) jpeg_q<=pending_q;
        end
        for(integer n=0;n<6;n=n+1) if(dut.pending[n]>2) $fatal(1,"queued write ownership counter overflow");
        if(dut.ws==1 && dut.bank_full[dut.write_bank]) $fatal(1,"capture overwrites AXI-owned burst bank");
        if(((cap_a.u_fifo.wp-cap_a.u_fifo.rp)&((1<<(CAP_FIFO_ADDR+1))-1))>max_fifo_a)
            max_fifo_a=(cap_a.u_fifo.wp-cap_a.u_fifo.rp)&((1<<(CAP_FIFO_ADDR+1))-1);
        if(((cap_b.u_fifo.wp-cap_b.u_fifo.rp)&((1<<(CAP_FIFO_ADDR+1))-1))>max_fifo_b)
            max_fifo_b=(cap_b.u_fifo.wp-cap_b.u_fifo.rp)&((1<<(CAP_FIFO_ADDR+1))-1);
        if(BURST && (ova || ovb)) $fatal(1,"aligned RAW10 burst overflow with production FIFO depth: A=%0d B=%0d",ova,ovb);
        jpeg_done<=0;
        if(tail>0) begin
            tail<=tail-1;if(tail==1) jpeg_done<=1;
        end
        if(rawv) begin
            if(raws) begin
                beats=0;frame_cam=current_meta[39:32];frame_id=current_meta[31:0];
                if(frame_id<=last_id[frame_cam]) $fatal(1,"reordered/duplicate frame");
                last_id[frame_cam]=frame_id;
                if(mode!=(frame_cam?2:1) || current_meta[95:64]!=9) $fatal(1,"metadata mismatch");
                if(current_meta[58:56]!=(frame_cam?4:1)) $fatal(1,"per-frame Gaussian strength snapshot mismatch");
                if(current_meta[54:48]!==((DUAL_QF && frame_cam) ? 7'd30 : 7'd85) ||
                   jpeg_q!==current_meta[54:48]) $fatal(1,"per-frame QF/encoder mismatch");
            end
            if(raw!==pattern(frame_cam,frame_id,beats))
                $fatal(1,"mixed/corrupt pixels cam=%0d frame=%0d beat=%0d got=%h expected=%h",frame_cam,frame_id,beats,raw,pattern(frame_cam,frame_id,beats));
            if(rawe!=(beats%(W/4)==W/4-1) || odd!=frame_cam) $fatal(1,"bad EOL/Bayer metadata");
            beats=beats+1;
            if(beats==W*H/4) begin completed=completed+1;tail<=BURST==2 ? 15000:150;end
        end
        if(!expect_write_error && (fault || errors)) $fatal(1,"unexpected AXI/read fault");
    end
    initial begin
        #100;rst=1;repeat(20) @(posedge ca);
        if(BURST==2) begin
            fork
                begin: rate_a
                    real began;
                    for(integer f=1;f<=4;f=f+1) begin
                        began=$realtime;send_a(f);
                        #(16666666.666-($realtime-began));
                    end
                end
                begin: rate_b
                    real began;
                    for(integer f=1;f<=4;f=f+1) begin
                        began=$realtime;send_b(f);
                        #(16666666.666-($realtime-began));
                    end
                end
            join
            wait(del_a==4 && del_b==4);
        end else begin
            for(integer f=1;f<=4;f=f+1) begin
                fork send_a(f);send_b(f);join
                wait(del_a==f && del_b==f);
            end
        end
        if(drop_a || drop_b || ova || ovb || fma || fmb || caps_a!=4 || caps_b!=4) $fatal(1,"normal phase lost frames");
        if(DUAL_QF && qf_waits<2) $fatal(1,"independent QF wait not exercised");
        if(BURST) begin
            $display("PASS aligned full-width RAW10 bursts, production FIFO depth, ideal AXI, 8 complete frames; FIFO peaks %0d/%0d",max_fifo_a,max_fifo_b);
            if(BURST==2) $display("PASS full 1080p sources independently scheduled every 16.667ms, modeled 112.5us JPEG tail; not real DDR/JPEG/PCIe");
            $finish;
        end
        $display("PASS dual capture/replay, asynchronous clocks, randomized AXI stalls, 8 complete frames");
        // Fill all slots with the reader stopped. Verify loss is explicit and
        // recovery produces complete, ordered frames without overwriting READING.
        @(negedge clk);enable=0;
        for(integer f=5;f<=10;f=f+1) begin fork send_a(f);send_b(f);join end
        repeat(5000) @(posedge clk);
        if(drop_a==0 || drop_b==0) $fatal(1,"pressure loss not counted");
        if(store_diagnostics[3*32+:32]!=3 || store_diagnostics[4*32+:32]!=3)
            $fatal(1,"no-free drop causes not split by camera");
        @(negedge clk);enable=1;
        wait(del_a==7 && del_b==7);
        fork send_a(11);send_b(11);join
        wait(del_a==8 && del_b==8);
        if(ova || ovb || fma || fmb) $fatal(1,"unexpected source FIFO/format errors");
        $display("PASS slot pressure and recovery: camera drops A=%0d B=%0d, delivered=%0d/%0d",drop_a,drop_b,del_a,del_b);
        // Camera A disappears inside a burst; B must not be starved forever.
        for(integer i=0;i<10;i=i+1) begin
            @(negedge ca);va=1;sa=i==0;ea=0;ra=pattern(0,12,i);
            @(negedge ca);va=0;sa=0;
        end
        send_b(12);wait(del_b==9);
        fork send_a(13);send_b(13);join
        wait(del_a==9 && del_b==10);
        if(fma!=1 || fmb || ova || ovb) $fatal(1,"camera partial-frame recovery failed");
        $display("PASS stopped camera cannot starve the other; recovery at next SOF");
        // A failed write must not publish its frame or reuse in-flight storage.
        @(negedge clk);expect_write_error=1;bresp=2;
        send_a(14);wait(fault);repeat(20) @(posedge clk);
        if(errors!=1 || caps_a!=9 || caps_b!=10 || awv || wv || ard || brd)
            $fatal(1,"AXI write error did not stop capture/publication");
        if(first_fault[3:0]!==4'b0011) $fatal(1,"missing first AXI write fault snapshot");
        if(store_diagnostics[15*32+:32]!=1 || store_diagnostics[16*32+:32]!=0)
            $fatal(1,"AXI drop diagnostic camera ownership");
        $display("PASS AXI write error fails closed, counted once, no incomplete frame published; system reset required");
        $finish;
    end
    initial begin #TIMEOUT_NS;$fatal(1,"timeout ws=%d rs=%d del=%d/%d cap=%d/%d",dut.ws,dut.rs,del_a,del_b,caps_a,caps_b);end
endmodule
