`timescale 1ns/1ps
module v2_pcie_endpoint (
    input wire diag_clk,input wire [575:0] diagnostics,
    input wire sys_clk,jpeg_refclk,refclk_p,refclk_n,rxp,rxn,pcie_mperst,
    output wire txp,txn,stream_reset_n,
    input wire pipe_clk,pipe_rst_n,
    input wire [127:0] metadata,input wire metadata_valid,output wire metadata_ready,
    input wire [127:0] processed_rgb,input wire processed_valid,processed_sof,processed_eol,
    input wire [671:0] statistics,
    input wire [511:0] pipeline_statistics,
    input wire [1535:0] store_diagnostics,
    input wire [511:0] feature_result,input wire feature_valid,output wire feature_ready,
    output wire capture_enable,output wire [2:0] mode_a,mode_b,
    output wire [2:0] strength_a,strength_b,
    output wire [6:0] quality_pipe,quality_b_pipe,quality_applied_pipe,
    output wire independent_qf_pipe,output wire [31:0] config_epoch,
    output wire jpeg_armed,jpeg_done,jpeg_fault_pipe,jpeg_input_ready,
    output wire [35:0] jpeg_input_levels
);
    wire core_clk, app_auxclk, pll_lock;
    wire jpeg_enc_clk,jpeg_pll_lock;
    wire user_clk, user_rst_n, link_up;
    wire sys_clk_g;
    PH1_LOGIC_BUFG u_sys_clk_bufg (.i(sys_clk),.o(sys_clk_g));
    reg [9:0] por_count=0;
    always @(posedge sys_clk_g) if(!(&por_count)) por_count<=por_count+1'b1;
    sgdma_pll u_sgdma_pll (.refclk(sys_clk_g),.reset(!(&por_count)),
        .lock(pll_lock),.clk0_out(core_clk),.clk1_out(app_auxclk));
    jpeg_clk_pll u_jpeg_clk_pll (
        .refclk(jpeg_refclk),.reset(1'b0),.lock(jpeg_pll_lock),
        .clk0_out(jpeg_enc_clk),.clk1_out(),.clk2_out()
    );
    reg [21:0] lock_count;
    always @(posedge core_clk or negedge pll_lock)
        if(!pll_lock) lock_count<=0;
        else if(!(&lock_count)) lock_count<=lock_count+1'b1;
    wire power_reset_n = pcie_mperst && (&lock_count);

    wire [127:0] c2h_data=128'd0;
    wire c2h_valid,c2h_ready,c2h_last;
    assign c2h_valid=1'b0;assign c2h_last=1'b0;
    wire [127:0] jpeg_a_data,jpeg_b_data,jpeg_c_data;
    wire [15:0] jpeg_a_keep,jpeg_b_keep,jpeg_c_keep;
    wire jpeg_a_valid,jpeg_a_ready,jpeg_a_last;
    wire jpeg_b_valid,jpeg_b_ready,jpeg_b_last;
    wire jpeg_c_valid,jpeg_c_ready,jpeg_c_last;
    wire [31:0] awaddr,wdata,araddr;
    wire [3:0] wstrb;
    wire [2:0] awprot,arprot;
    wire awvalid,awready,wvalid,wready,bready,arvalid,arready,rready;
    reg bvalid,rvalid;
    reg [31:0] rdata;
    wire [15:0] irq_ack;
    wire msi_enable;
    wire [4:0] msi_vector_width;
    sgdma_subsys #(
        .DEVICE_FAMILY("PH1A"),.USER_CLK_FREQ(125),.LINK_WIDTH(1),
        .DATA_WIDTH(128),.H2C_CHNL_NUM(1),.C2H_CHNL_NUM(4),.USR_IRQ_NUM(16),
        .LGCY_EN(0),.MSI_EN(1),.MSIX_EN(0),.AXI4MM_BUS_EN(0),.AXI4ST_BUS_EN(1),
        .H2C_DSC_BYP_MAP(0),.C2H_DSC_BYP_MAP(0)
    ) u_sgdma_subsys (
        .app_auxclk(app_auxclk),.tl_power_on_rstn(power_reset_n),
        .tl_clk_user(core_clk),.pll_lock(pll_lock),
        .ref_pad_clk_p(refclk_p),.ref_pad_clk_n(refclk_n),
        .pcie_tx_p(txp),.pcie_tx_n(txn),.pcie_rx_p(rxp),.pcie_rx_n(rxn),
        .c2h_sts_0(),.h2c_sts_0(),.c2h_sts_1(),.h2c_sts_1(),
        .c2h_sts_2(),.h2c_sts_2(),.c2h_sts_3(),.h2c_sts_3(),
        .s0_axis_c2h_tdata({jpeg_c_data,jpeg_b_data,jpeg_a_data,c2h_data}),
        .s0_axis_c2h_tkeep({jpeg_c_keep,jpeg_b_keep,jpeg_a_keep,16'hffff}),
        .s0_axis_c2h_tuser({jpeg_c_keep,jpeg_b_keep,jpeg_a_keep,16'hffff}),
        .s0_axis_c2h_tvalid({jpeg_c_valid,jpeg_b_valid,jpeg_a_valid,c2h_valid}),
        .s0_axis_c2h_tready({jpeg_c_ready,jpeg_b_ready,jpeg_a_ready,c2h_ready}),
        .s0_axis_c2h_tlast({jpeg_c_last,jpeg_b_last,jpeg_a_last,c2h_last}),
        .m0_axis_h2c_tready(1'b1),.m0_axis_h2c_tdata(),.m0_axis_h2c_tkeep(),
        .m0_axis_h2c_tuser(),.m0_axis_h2c_tlast(),.m0_axis_h2c_tvalid(),
        .m_axil_awaddr(awaddr),.m_axil_awprot(awprot),
        .m_axil_awvalid(awvalid),.m_axil_awready(awready),
        .m_axil_wdata(wdata),.m_axil_wstrb(wstrb),
        .m_axil_wvalid(wvalid),.m_axil_wready(wready),
        .m_axil_bvalid(bvalid),.m_axil_bresp(2'b00),.m_axil_bready(bready),
        .m_axil_araddr(araddr),.m_axil_arprot(arprot),
        .m_axil_arvalid(arvalid),.m_axil_arready(arready),
        .m_axil_rdata(rdata),.m_axil_rresp(2'b00),
        .m_axil_rvalid(rvalid),.m_axil_rready(rready),
        .usr_irq_req(16'd0),.usr_irq_ack(irq_ack),
        .msi_enable(msi_enable),.msi_vector_width(msi_vector_width),
        .user_link_up(link_up),.user_clk(user_clk),.user_rst_n(user_rst_n)
    );


`include "rtl/v2_endpoint_body.vh"
endmodule
