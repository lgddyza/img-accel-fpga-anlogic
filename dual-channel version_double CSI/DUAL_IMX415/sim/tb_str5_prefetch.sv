`timescale 1ns/1ps
// Actual store + reset guard, ordered queued DDR model. Every RAW group is
// checked. The artificial 64-cycle latency is a comparison, not board FPS.
module tb_str5_prefetch;
    parameter LIMIT=2,STALL=1,ERROR_KIND=0;
    localparam W=128,H=64,N=W*H/8,STRIDE=16384;
    reg clk=0,rst_n=0,run=1;always #3.75 clk=~clk;
    wire released;wire [31:0] debug;
    wire srst=rst_n && released;
    reg [127:0] a_data=0,b_data=0;
    reg a_valid=0,b_valid=0;
    wire a_ready,b_ready;
    wire [27:0] s_awaddr,s_araddr,m_awaddr,m_araddr;
    wire [7:0] s_awlen,s_arlen,m_awlen,m_arlen;
    wire s_awvalid,s_awready,s_wlast,s_wvalid,s_wready,s_bvalid,s_bready;
    wire s_arvalid,s_arready,s_rlast,s_rvalid,s_rready;
    wire [127:0] s_wdata,s_rdata,m_wdata;
    wire [1:0] s_bresp,s_rresp;
    wire m_awvalid,m_wvalid,m_wlast,m_bready,m_arvalid,m_rready;
    wire m_awready,m_wready,m_arready;
    reg m_bvalid=0,m_rvalid=0,m_rlast=0;
    reg [127:0] m_rdata=0;reg [1:0] m_rresp=0;
    wire [1:0] m_bresp=0;
    wire [127:0] metadata,first_fault;
    wire metadata_valid,camera,raw_valid,raw_sof,raw_eol,raw_first_row_odd;
    wire [2:0] frame_mode;wire [39:0] raw;
    wire [31:0] captured_a,captured_b,dropped_a,dropped_b,delivered_a,delivered_b,axi_errors;
    wire [11:0] slot_debug;wire read_fault;wire [1535:0] diagnostics;
    reg jpeg_done=0;
    integer cycle=0,tail=0,groups=0,completed=0,begin_cycle=0;
    reg raw_gate=1;
    wire raw_ready=raw_gate && (!STALL || cycle%113>31);
    v2_frame_store #(.WIDTH(W),.HEIGHT(H),.SLOT_STRIDE(STRIDE),
        .RAW_IDLE_CYCLES(1),.READ_OUTSTANDING(LIMIT)) dut (
        .clk(clk),.rst_n(srst),.a_data(a_data),.b_data(b_data),.a_valid(a_valid),.b_valid(b_valid),
        .a_ready(a_ready),.b_ready(b_ready),.a_level(16'd64),.b_level(16'd64),
        .awaddr(s_awaddr),.awlen(s_awlen),.awvalid(s_awvalid),.awready(s_awready),
        .wdata(s_wdata),.wlast(s_wlast),.wvalid(s_wvalid),.wready(s_wready),
        .bresp(s_bresp),.bvalid(s_bvalid),.bready(s_bready),
        .araddr(s_araddr),.arlen(s_arlen),.arvalid(s_arvalid),.arready(s_arready),
        .rdata(s_rdata),.rresp(s_rresp),.rlast(s_rlast),.rvalid(s_rvalid),.rready(s_rready),
        .enable(1'b1),.mode_a(3'd0),.mode_b(3'd0),.quality(7'd85),.quality_b(7'd85),
        .jpeg_quality(7'd85),.independent_qf(1'b0),.config_epoch(32'd19),
        .jpeg_armed(1'b1),.jpeg_done(jpeg_done),.jpeg_fault(1'b0),.metadata(metadata),
        .metadata_valid(metadata_valid),.metadata_ready(1'b1),.camera(camera),.frame_mode(frame_mode),
        .raw(raw),.raw_valid(raw_valid),.raw_sof(raw_sof),.raw_eol(raw_eol),
        .raw_first_row_odd(raw_first_row_odd),.raw_ready(raw_ready),
        .captured_a(captured_a),.captured_b(captured_b),.dropped_a(dropped_a),.dropped_b(dropped_b),
        .delivered_a(delivered_a),.delivered_b(delivered_b),.axi_errors(axi_errors),
        .slot_debug(slot_debug),.read_fault(read_fault),.first_fault(first_fault),.diagnostics(diagnostics));
    v2_ddr_reset_guard guard(.*);
    reg [127:0] mem[0:6*STRIDE/16-1];
    integer wa=0,wb=0;
    reg writing=0;
    integer qaddr[0:7],due[0:7];
    integer qwrite=0,qread=0,qcount=0,rbeat=0,peak=0,total_ar=0;
    reg [31:0] rng=32'hc541d839;
    assign m_awready=!writing && !m_bvalid && (!STALL || rng[0]);
    assign m_wready=writing && (!STALL || rng[1]);
    assign m_arready=qcount<2 && (!STALL || rng[2]);
    wire take_ar=m_arvalid && m_arready;
    wire take_last=m_rvalid && m_rready && m_rlast;
    always @(posedge clk) begin
        cycle<=cycle+1;rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        if(m_awvalid && m_awready) begin
            wa=m_awaddr/16;wb=0;writing<=1;
            if(m_awlen!=15) $fatal(1,"AW length");
        end
        if(m_wvalid && m_wready) begin
            if(m_wlast!=(wb==15)) $fatal(1,"W last");
            mem[wa+wb]=m_wdata;wb=wb+1;
            if(m_wlast) begin writing<=0;m_bvalid<=1;end
        end
        if(m_bvalid && m_bready) m_bvalid<=0;
        if(take_ar) begin
            if(m_arlen!=15 || m_araddr[7:0]!=0 || m_araddr[11:0]>3840) $fatal(1,"AR boundary/length");
            qaddr[qwrite]=m_araddr/16;due[qwrite]=cycle+64;
            qwrite=(qwrite+1)%8;total_ar=total_ar+1;
        end
        if(!m_rvalid || m_rready) begin
            m_rvalid<=0;
            if(take_last) begin qread=(qread+1)%8;rbeat=0;end
            else if(m_rvalid && m_rready) rbeat=rbeat+1;
            if(qcount!=0 && !take_last && cycle>=due[qread] && (!STALL || rng[3])) begin
                m_rdata<=mem[qaddr[qread]+rbeat];m_rlast<=rbeat==15;m_rvalid<=1;
                m_rresp<=(ERROR_KIND==1 && total_ar==2 && rbeat==5) ? 2'b10 : 0;
                if(ERROR_KIND==2 && total_ar==2 && rbeat==5) m_rlast<=1;
            end
        end
        case({take_ar,take_last})
            2'b10: qcount<=qcount+1;
            2'b01: qcount<=qcount-1;
        endcase
        if(qcount>peak) peak=qcount;
    end
    function [39:0] pixels(input integer cam,frame,group_id);
        pixels={10'(cam*401+frame*53+group_id*4+3),10'(cam*401+frame*53+group_id*4+2),
                10'(cam*401+frame*53+group_id*4+1),10'(cam*401+frame*53+group_id*4)};
    endfunction
    task automatic send(input integer cam,frame);
        reg [127:0] word;
        begin
            for(integer i=0;i<N;i=i+1) begin
                word={1'b0,1'(cam),28'(frame),18'(i),pixels(cam,frame,2*i+1),pixels(cam,frame,2*i)};
                @(negedge clk);
                if(cam) begin b_data=word;b_valid=1;end else begin a_data=word;a_valid=1;end
                do @(posedge clk);while(!(cam?b_ready:a_ready));
            end
            @(negedge clk);if(cam) b_valid=0;else a_valid=0;
        end
    endtask
    reg ar_stall=0;reg [35:0] held_ar;
    integer frame_cam=0,frame_id=0;
    reg [31:0] pixel_hash=32'h811c9dc5;
    always @(posedge clk) if(srst) begin
        if(ar_stall && (!s_arvalid || held_ar!=={s_araddr,s_arlen})) $fatal(1,"unstable AR");
        ar_stall=s_arvalid&&!s_arready;held_ar={s_araddr,s_arlen};
        if(dut.read_buffered+dut.read_reserved>240 || dut.read_outstanding>LIMIT)
            $fatal(1,"reservation/occupancy overflow");
        if(dut.rf_push && !dut.rf_ready) $fatal(1,"FIFO overflow");
        if(dut.rf_take && dut.read_buffered==0) $fatal(1,"FIFO ownership underflow");
        if(!ERROR_KIND && read_fault) $fatal(1,"unexpected fault");
        jpeg_done<=0;
        if(tail>0) begin tail<=tail-1;if(tail==1) jpeg_done<=1;end
        if(raw_valid) begin
            if(raw_sof) begin
                groups=0;frame_cam=metadata[39:32];frame_id=metadata[31:0];
                if(completed==0) begin_cycle=cycle;
                if(metadata[95:64]!=19 || metadata[54:48]!=85) $fatal(1,"metadata");
            end
            if(raw!==pixels(frame_cam,frame_id,groups) || raw_first_row_odd!=frame_cam ||
               raw_eol!=(groups%(W/4)==W/4-1)) $fatal(1,"RAW mismatch group %0d",groups);
            pixel_hash=(pixel_hash^raw[31:0])*32'h01000193 ^ raw[39:32];
            groups=groups+1;
            if(groups==2*N) begin completed=completed+1;tail<=100;end
        end
    end
    initial begin
        repeat(10) @(negedge clk);rst_n=1;wait(srst);
        if(STALL) begin
            raw_gate=0;
            fork
                begin wait(dut.read_buffered>=200);repeat(100) @(negedge clk);raw_gate=1;end
                begin send(0,1);end
                begin send(1,1);end
            join
        end else fork send(0,1);send(1,1);join
        if(ERROR_KIND==3) begin
            wait(qcount==2 && m_rvalid);@(negedge clk);run=0;
            repeat(5) @(negedge clk);run=1;wait(released);@(negedge clk);
            if(qcount || m_rvalid || s_rvalid || dut.read_outstanding || dut.read_buffered)
                $fatal(1,"old responses survived stream reset");
            fork send(0,2);send(1,2);join
            wait(delivered_a==1 && delivered_b==1);
            if(read_fault || dropped_a || dropped_b) $fatal(1,"reset recovery damaged fresh frames");
            $display("PASS STR5 two DDR-accepted reads drained on video reset, fresh A/B RAW exact");$finish;
        end
        if(ERROR_KIND) begin
            wait(read_fault);repeat(300) @(negedge clk);
            if(axi_errors==0 || !first_fault[0] || delivered_a || delivered_b || raw_valid)
                $fatal(1,"read error not stopped");
            if(first_fault[49:32]!==18'd0 || first_fault[16:13]!==4'd5)
                $fatal(1,"fault index points to issued AR rather than response burst");
            $display("PASS STR5 injected read error kind=%0d, no corrupt frame published",ERROR_KIND);$finish;
        end
        wait(delivered_a==1 && delivered_b==1);
        for(integer f=2;f<=3;f=f+1) begin
            fork send(0,f);send(1,f);join
            wait(delivered_a==f && delivered_b==f);
        end
        if(dropped_a || dropped_b || captured_a!=3 || captured_b!=3 || completed!=6 || peak!=LIMIT)
            $fatal(1,"lost frames / did not exercise outstanding limit peak=%0d",peak);
        if(diagnostics[17*32+:32]!=6*N/16 || diagnostics[18*32+:32]!=6*N)
            $fatal(1,"diagnostic accounting");
        $display("PASS STR5 limit=%0d stall=%0d frames=6 hash=%h cycles=%0d outstanding_peak=%0d fifo_peak=%0d AR=%0d R=%0d",
            LIMIT,STALL,pixel_hash,cycle-begin_cycle,peak,diagnostics[23*32+:32],total_ar,diagnostics[18*32+:32]);
        $finish;
    end
    initial begin #2000000;$fatal(1,"timeout ws=%0d tx=%0d caps=%0d/%0d rs=%0d qcount=%0d outstanding=%0d completed=%0d",dut.ws,dut.tx_state,captured_a,captured_b,dut.rs,qcount,dut.read_outstanding,completed);end
endmodule
