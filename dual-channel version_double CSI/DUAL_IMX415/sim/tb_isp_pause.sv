`timescale 1ns/1ps
module tb_isp_pause #(parameter LONG_IDLE_CYCLES=0, ROWS=96, FRAMES=2);
    localparam B=480,TOTAL=B*ROWS*FRAMES;
    reg clk=0,rst_n=0;
    always #3.75 clk=~clk;
    wire [127:0] pixels[0:1];
    wire [1:0] valid,sof,eol,source_done;
    reg [127:0] reference[0:TOTAL-1],paused[0:TOTAL-1];
    integer count[0:1];
    generate for(genvar c=0;c<2;c=c+1) begin:g_source
        reg [39:0] raw=0;
        reg sv=0,ss=0,se=0;
        wire sr,lv,ls,le,fault;
        wire [39:0] data;
        integer cycles=0;
        reg finished=0;
        always @(posedge clk) cycles<=cycles+1;
        wire admit=c==0 || cycles%10000>2500;
        assign source_done[c]=finished;
        v2_line_replay #(.BACKPRESSURE(1),.MIN_LINE_GAP(64)) replay(
            .clk(clk),.rst_n(rst_n),.s_data(raw),.s_valid(sv),.s_sof(ss),.s_eol(se),
            .m_data(data),.m_valid(lv),.m_sof(ls),.m_eol(le),.fault(fault),
            .s_ready(sr),.m_start_ready(admit),.line_started(),.line_waiting());
        ui_isp_top #(.ENABLE_DSI_BRANCH(0),.COMPACT_FIXED_ISP(1)) isp(
            .I_clk(clk),.I_rst_n(rst_n),.I_tdata(data),.I_tvalid(lv),.I_tuser(ls),.I_tlast(le),
            .I_tdest(10'd0),.O_tready(1'b1),.O_tdata(pixels[c]),.O_tvalid(valid[c]),
            .O_tuser(sof[c]),.O_tlast(eol[c]),.I_tready(),.I_first_row_odd(1'b0),
            .I_dsi_control(4'd0),.O_dsi_tdata(),.O_dsi_tvalid(),.O_dsi_tuser(),.O_dsi_tlast(),.O_dsi_phase());
        always @(posedge clk) if(rst_n) begin
            if(fault) $fatal(1,"replay fault source=%0d",c);
            if(valid[c]) begin
                if(count[c]>=TOTAL || sof[c]!=(count[c]%(B*ROWS)==0) || eol[c]!=(count[c]%B==B-1))
                    $fatal(1,"ISP geometry source=%0d group=%0d sof=%b eol=%b",c,count[c],sof[c],eol[c]);
                if(c==0) reference[count[c]]=pixels[c];else paused[count[c]]=pixels[c];
                count[c]=count[c]+1;
            end
        end
        initial begin
            wait(rst_n);
            for(integer f=0;f<FRAMES;f=f+1) begin
            for(integer y=0;y<ROWS;y=y+1) begin
                if(c==1 && y==ROWS/2 && f==0) begin
                    @(negedge clk);sv=0;ss=0;se=0;
                    repeat(LONG_IDLE_CYCLES) @(negedge clk);
                end
                for(integer x=0;x<B;x=x+1) begin
                    @(negedge clk);
                    while(!sr) begin sv=0;ss=0;se=0;@(negedge clk);end
                    sv=1;ss=y==0 && x==0;se=x==B-1;
                    for(integer p=0;p<4;p=p+1) raw[p*10+:10]=((x*13+y*29+p*31)%896)+64;
                    if(c==0 && x%2==1) begin @(negedge clk);sv=0;ss=0;se=0;end
                end
            end
            @(negedge clk);sv=0;ss=0;se=0;
            // Drain the old frame before SOF; compare both continuous and
            // long-idle restart against the exact same production ISP.
            wait(count[c]==(f+1)*B*ROWS);
            repeat(c==1 ? LONG_IDLE_CYCLES+100 : 100) @(negedge clk);
            end
            @(negedge clk);sv=0;ss=0;se=0;finished=1;
        end
    end endgenerate
    initial begin
        count[0]=0;count[1]=0;
        repeat(10) @(negedge clk);rst_n=1;
        wait(&source_done);wait(count[0]==TOTAL && count[1]==TOTAL);
        for(integer n=0;n<TOTAL;n=n+1)
            if(reference[n]!==paused[n]) $fatal(1,"pause changed ISP pixels group=%0d",n);
        $display("PASS legacy ISP row-gap contract: %0d frames x %0d rows, idle=%0d clocks, exact pixels and markers",FRAMES,ROWS,LONG_IDLE_CYCLES);
        $finish;
    end
    initial begin #200000000;$fatal(1,"timeout counts=%0d/%0d",count[0],count[1]);end
endmodule
