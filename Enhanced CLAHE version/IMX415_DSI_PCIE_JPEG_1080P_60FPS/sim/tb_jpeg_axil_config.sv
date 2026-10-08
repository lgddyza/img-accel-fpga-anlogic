`timescale 1ns/1ps
module tb_jpeg_axil_config;
    reg clk=0,rst_n=0,frame_busy=0;
    always #5 clk=~clk;
    reg [6:0] quality=85;
    wire ready;
    wire [4:0] awaddr;
    wire awvalid,awready,wvalid,wready,bvalid,bready;
    wire [31:0] wdata;
    wire [3:0] wstrb;
    wire ctrl_enable,ctrl_soft_reset;
    wire [6:0] ctrl_quality;
    wire [6:0] applied_quality;
    wire [15:0] restart_interval;
    jpeg_axil_config dut (
        .clk(clk),.rst_n(rst_n),.quality(quality),.frame_busy(frame_busy),
        .ready(ready),.applied_quality(applied_quality),
        .awaddr(awaddr),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wvalid(wvalid),.wready(wready),
        .bvalid(bvalid),.bready(bready)
    );
    axi4_lite_regs #(.LITE_MODE(0)) regs (
        .clk(clk),.rst_n(rst_n),
        .s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
        .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid),.s_axi_wready(wready),
        .s_axi_bresp(),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
        .s_axi_araddr(5'd0),.s_axi_arvalid(1'b0),.s_axi_arready(),
        .s_axi_rdata(),.s_axi_rresp(),.s_axi_rvalid(),
        .s_axi_rready(1'b0),
        .ctrl_enable(ctrl_enable),.ctrl_soft_reset(ctrl_soft_reset),
        .ctrl_quality(ctrl_quality),.ctrl_restart_interval(restart_interval),
        .sts_busy(1'b0),.sts_frame_done_pulse(1'b0),
        .sts_frame_cnt(32'd0),.sts_frame_size(32'd0)
    );
    initial begin
        repeat(5) @(negedge clk); rst_n=1;
        wait(ready);
        @(negedge clk);
        if(!ctrl_enable || ctrl_quality!=85 || applied_quality!=85)
            $fatal(1,"initial config enable=%b q=%0d",ctrl_enable,ctrl_quality);
        frame_busy=1; quality=75;
        repeat(20) @(negedge clk);
        if(ready || ctrl_quality!=85 || applied_quality!=85)
            $fatal(1,"quality changed during active frame");
        frame_busy=0;
        wait(ready);
        @(negedge clk);
        if(!ctrl_enable || ctrl_quality!=75 || applied_quality!=75)
            $fatal(1,"quality update failed: q=%0d",ctrl_quality);
        $display("JPEG_AXIL_CONFIG_PASS");
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule
