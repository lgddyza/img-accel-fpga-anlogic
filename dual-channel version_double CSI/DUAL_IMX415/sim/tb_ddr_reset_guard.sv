`timescale 1ns/1ps
module tb_ddr_reset_guard;
    reg clk=0,rst_n=0,run=0;always #3.75 clk=~clk;
    wire released;wire [31:0] debug;
    reg [27:0] s_awaddr=0,s_araddr=0;reg [7:0] s_awlen=15,s_arlen=15;
    reg s_awvalid=0,s_wvalid=0,s_wlast=0,s_bready=1,s_arvalid=0,s_rready=0;
    reg [127:0] s_wdata=0;
    wire s_awready,s_wready,s_bvalid,s_arready,s_rlast,s_rvalid;
    wire [1:0] s_bresp,s_rresp;wire [127:0] s_rdata;
    wire [27:0] m_awaddr,m_araddr;wire [7:0] m_awlen,m_arlen;
    wire m_awvalid,m_wvalid,m_wlast,m_bready,m_arvalid,m_rready;
    wire [127:0] m_wdata;
    wire m_awready,m_wready,m_arready;
    reg m_bvalid=0,m_rvalid=0,m_rlast=0;
    reg [127:0] m_rdata=0;
    wire [1:0] m_bresp=0,m_rresp=0;
`ifdef BYPASS_DDR_GUARD
    // Negative control reproduces the original direct master-to-DDR wiring.
    assign released=run;assign debug={28'd0,reading,2'd0,writing};
    assign m_awaddr=s_awaddr;assign m_awlen=s_awlen;assign m_awvalid=s_awvalid;assign s_awready=m_awready;
    assign m_wdata=s_wdata;assign m_wlast=s_wlast;assign m_wvalid=s_wvalid;assign s_wready=m_wready;
    assign s_bresp=m_bresp;assign s_bvalid=m_bvalid;assign m_bready=s_bready;
    assign m_araddr=s_araddr;assign m_arlen=s_arlen;assign m_arvalid=s_arvalid;assign s_arready=m_arready;
    assign s_rdata=m_rdata;assign s_rresp=m_rresp;assign s_rlast=m_rlast;
    assign s_rvalid=m_rvalid;assign m_rready=s_rready;
`else
    v2_ddr_reset_guard dut(.*);
`endif
    reg address_gate=1,data_gate=1,abort_expected=0;
    reg writing=0,reading=0;
    reg [31:0] random_bits=32'h95b873da;
    integer wb=0,rn=0,read_address=0,write_address=0,completed_w=0,completed_r=0;
    assign m_awready=address_gate && !writing && !m_bvalid && random_bits[0];
    assign m_arready=address_gate && !reading && !m_rvalid && random_bits[1];
    assign m_wready=data_gate && writing && random_bits[2];
    function [127:0] pattern(input integer address,beat);
        pattern={32'hcafe0123,32'(address),32'hdef04567,32'(beat)};
    endfunction
    always @(posedge clk) begin
        random_bits<={random_bits[30:0],random_bits[31]^random_bits[21]^random_bits[1]^random_bits[0]};
        if(m_awvalid && m_awready) begin
            if(writing || m_awlen!=15) $fatal(1,"overlapped/invalid DDR write");
            writing<=1;wb<=0;write_address<=m_awaddr;
        end
        if(m_wvalid && m_wready) begin
            if(!writing || m_wlast!=(wb==15)) $fatal(1,"bad DDR WLAST beat=%0d",wb);
            if(!abort_expected && m_wdata!==pattern(write_address,wb)) $fatal(1,"corrupt normal write");
            wb<=wb+1;
            if(m_wlast) begin writing<=0;m_bvalid<=1;end
        end
        if(m_bvalid && m_bready) begin m_bvalid<=0;completed_w<=completed_w+1;end
        if(m_arvalid && m_arready) begin
            if(reading || m_arlen!=15) $fatal(1,"overlapped/invalid DDR read");
            reading<=1;read_address<=m_araddr;rn<=0;
        end
        if(!m_rvalid || m_rready) begin
            m_rvalid<=0;
            if(reading && rn<16 && data_gate && random_bits[3]) begin
                m_rdata<=pattern(read_address,rn);m_rlast<=rn==15;m_rvalid<=1;rn<=rn+1;
            end else if(reading && rn==16) reading<=0;
        end
        if(m_rvalid && m_rready && m_rlast) completed_r<=completed_r+1;
`ifndef BYPASS_DDR_GUARD
        if(!run && (s_bvalid || s_rvalid || s_awready || s_arready || s_wready))
            $fatal(1,"aborted response leaked to reset master");
`endif
    end
    reg aw_stall=0,ar_stall=0,w_stall=0,r_stall=0;
    reg [35:0] held_aw,held_ar;reg [128:0] held_w,held_r;
    always @(posedge clk) if(rst_n) begin
        if(aw_stall && (!m_awvalid || {m_awaddr,m_awlen}!==held_aw)) $fatal(1,"AW changed while stalled");
        if(ar_stall && (!m_arvalid || {m_araddr,m_arlen}!==held_ar)) $fatal(1,"AR changed while stalled");
        if(w_stall && (!m_wvalid || {m_wlast,m_wdata}!==held_w)) $fatal(1,"W changed while stalled/reset");
        if(r_stall && (!m_rvalid || {m_rlast,m_rdata}!==held_r)) $fatal(1,"DDR model violates R stall");
        aw_stall=m_awvalid&&!m_awready;held_aw={m_awaddr,m_awlen};
        ar_stall=m_arvalid&&!m_arready;held_ar={m_araddr,m_arlen};
        w_stall=m_wvalid&&!m_wready;held_w={m_wlast,m_wdata};
        r_stall=m_rvalid&&!m_rready;held_r={m_rlast,m_rdata};
    end
    task aw(input integer address);
        @(negedge clk);s_awaddr=address;s_awvalid=1;
        do @(posedge clk);while(!s_awready);
        @(negedge clk);s_awvalid=0;
    endtask
    task ar(input integer address);
        @(negedge clk);s_araddr=address;s_arvalid=1;
        do @(posedge clk);while(!s_arready);
        @(negedge clk);s_arvalid=0;
    endtask
    task word(input integer address,beat);
        @(negedge clk);s_wdata=pattern(address,beat);s_wvalid=1;s_wlast=beat==15;
        do @(posedge clk);while(!s_wready);
        @(negedge clk);s_wvalid=0;s_wlast=0;
    endtask
    task consume(input integer address,number);
        integer beat;
        begin
            for(beat=0;beat<number;beat=beat+1) begin
                @(negedge clk);s_rready=1;
                do @(posedge clk);while(!s_rvalid);
                if(s_rdata!==pattern(address,beat) || s_rlast!=(beat==15))
                    $fatal(1,"stale response address=%0d beat=%0d data=%h",address,beat,s_rdata);
                @(negedge clk);s_rready=0;
            end
        end
    endtask
    task video_reset;
        @(negedge clk);abort_expected=1;run=0;
        s_awvalid=0;s_wvalid=0;s_arvalid=0;s_rready=0;
        data_gate=0;
        repeat(4) @(negedge clk);
        run=1;
        repeat(4) @(negedge clk);
        if(released && (debug[0] || debug[3]))
            $fatal(1,"pipeline released before outstanding DDR transactions drained");
        address_gate=1;data_gate=1;
        wait(released);@(negedge clk);abort_expected=0;
        if(s_rvalid || s_bvalid || writing || m_bvalid || m_rvalid)
            $fatal(1,"old responses present at release");
    endtask
    integer cut,before_w,before_r;
    initial begin
        repeat(6) @(negedge clk);rst_n=1;run=1;wait(released);
        // Reset after every possible accepted write count, including pending
        // addresses and a final W beat that is still held downstream.
`ifdef BYPASS_DDR_GUARD
        for(cut=1;cut<=16;cut=cut+1) begin
`else
        for(cut=0;cut<=16;cut=cut+1) begin
`endif
            before_w=completed_w;address_gate=cut!=0;
            aw(256+cut*256);
            for(integer b=0;b<cut;b=b+1) word(256+cut*256,b);
            video_reset();
            if(completed_w!=before_w+1) $fatal(1,"aborted write not retired");
            aw(16384+cut*256);
            for(integer b=0;b<16;b=b+1) word(16384+cut*256,b);
            wait(completed_w==before_w+2);
        end
        // Reset before/inside the read burst. A fresh request must always
        // start at beat zero, never inherit the old RLAST or old slot data.
        for(cut=0;cut<16;cut=cut+1) begin
            before_r=completed_r;address_gate=cut!=0;
            ar(32768+cut*256);consume(32768+cut*256,cut);
            video_reset();
            if(completed_r!=before_r+1) $fatal(1,"aborted read not retired");
            ar(49152+cut*256);consume(49152+cut*256,16);
            wait(completed_r==before_r+2);
        end
        // Two upstream-owned requests: the second AR may still be stalled
        // at the single-request controller when video reset arrives.
        for(cut=0;cut<16;cut=cut+1) begin
            before_r=completed_r;address_gate=1;
            ar(73728+cut*512);
            wait(m_rvalid);@(negedge clk);address_gate=cut!=0;
            ar(73984+cut*512);
            consume(73728+cut*512,cut);video_reset();
            if(completed_r!=before_r+2) $fatal(1,"two old reads not fully drained");
            ar(90112+cut*256);consume(90112+cut*256,16);
            wait(completed_r==before_r+3);
        end
        before_w=completed_w;before_r=completed_r;
        fork
            begin aw(65536);for(integer b=0;b<7;b=b+1) word(65536,b);end
            begin ar(69632);consume(69632,5);end
        join
        video_reset();
        if(completed_w!=before_w+1 || completed_r!=before_r+1) $fatal(1,"simultaneous reset failed");
        $display("PASS DDR reset guard: 17 write cuts, 16 single and 16 dual read cuts, simultaneous read/write, random stalls, stable AXI and clean restart; aborted=%0d",debug[31:16]);
        $finish;
    end
    initial begin #1000000;$fatal(1,"guard timeout debug=%h",debug);end
endmodule
