`timescale 1ns/1ps
module tb_isp_replay;
    localparam W=1920,H=1080,B=W/4,BEATS=B*H;
    reg clk=0,rst=0,v=0,s=0,e=0;always #3.75 clk=~clk;
    reg [39:0] raw=0;
    wire [39:0] line_data;wire lv,ls,le,lf;
    v2_line_replay #(.MIN_LINE_GAP(64)) line_replay (.clk(clk),.rst_n(rst),.s_data(raw),.s_valid(v),.s_sof(s),.s_eol(e),
        .m_data(line_data),.m_valid(lv),.m_sof(ls),.m_eol(le),.fault(lf));
    wire [127:0] data;wire dv,ds,de;
    ui_isp_top #(.ENABLE_DSI_BRANCH(0),.COMPACT_FIXED_ISP(1)) dut (
        .I_clk(clk),.I_rst_n(rst),.I_tdata(line_data),.I_tvalid(lv),.I_tuser(ls),.I_tlast(le),
        .I_tdest(10'd0),.O_tready(1'b1),.O_tdata(data),.O_tvalid(dv),.O_tuser(ds),.O_tlast(de),.I_tready(),
        .I_first_row_odd(1'b0),.I_dsi_control(4'd0),.O_dsi_tdata(),.O_dsi_tvalid(),.O_dsi_tuser(),.O_dsi_tlast(),.O_dsi_phase());
    reg [127:0] reference[0:BEATS-1];
    integer seen=0,frame=0,at=0;
    always @(negedge clk) if(rst && dv) begin
        if(lf) $fatal(1,"line replay overrun");
        at=seen%BEATS;
        if(ds!==(at==0) || de!==(at%B==B-1)) $fatal(1,"ISP markers lost at beat=%0d",seen);
        if((^data)===1'bx) $fatal(1,"ISP output uninitialized beat=%0d data=%h",seen,data);
        if(seen<BEATS) reference[at]=data;
        if(seen>=2*BEATS && data!==reference[at])
            $fatal(1,"ISP retained other camera pixels beat=%0d got=%h expected=%h",at,data,reference[at]);
        seen=seen+1;
    end
    initial begin
        repeat(8) @(negedge clk);rst=1;repeat(100) @(negedge clk);
        for(frame=0;frame<3;frame=frame+1) begin
            for(integer y=0;y<H;y=y+1) for(integer x=0;x<B;x=x+1) begin
                v=1;s=y==0 && x==0;e=x==B-1;
                raw=frame==1 ? {4{10'd700}} : {4{10'd200}};
                @(negedge clk);
                if(x%2==1) begin v=0;s=0;e=0;repeat(2) @(negedge clk);end
            end
            v=0;s=0;e=0;repeat(16384) @(negedge clk);
            if(seen!=(frame+1)*BEATS) $fatal(1,"ISP frame count expected=%0d got=%0d",(frame+1)*BEATS,seen);
            $display("ISP replay full 1080p frame %0d passed",frame);
        end
        $display("PASS full 1080p shared ISP: A/B/A pixel comparison, DDR cadence, markers, no cross-camera state");$finish;
    end
    initial begin #30000000;$fatal(1,"ISP timeout");end
endmodule
