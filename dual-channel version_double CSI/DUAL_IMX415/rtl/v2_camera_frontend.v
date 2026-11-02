`timescale 1ns/1ps
// New FMC board uses an HS-only CSI receiver adapted to PH1A. LP pins are not
// involved. Camera initialization/RX diagnostics run independently of DDR.
module v2_camera_frontend #(parameter INCK_HZ=37125000)(
    input wire cfg_clk,lp_clk,pll_lock,stream_rst_n,
    input wire clk_hs,input wire [3:0] data_hs,
    output wire scl,inout wire sda,output wire pwdnb,
    output wire cam_clk,output wire [39:0] raw,
    output wire valid,sof,eol,row_odd,
    output wire cfg_done,iic_error,output wire [223:0] diagnostics,
    output wire [31:0] calibration
);
    wire cfg_reset_n;
    v2_reset_sync u_cfg_reset(cfg_clk,pll_lock,cfg_reset_n);
    wire [31:0] progress,nacks,last_failure;
    v2_imx415_config #(.INCK_HZ(INCK_HZ)) u_cfg(
        .clk(cfg_clk),.rst_n(cfg_reset_n),.scl(scl),.sda(sda),.pwdnb(pwdnb),
        .cfg_done(cfg_done),.error_pulse(iic_error),.progress(progress),
        .nack_count(nacks),.last_failure(last_failure));
    // Keep clock recovery alive even when DDR/PCIe is not yet ready. Its
    // AXIS and crop reset releases synchronously to the recovered byte clock.
    wire rx_ref_reset_n,rx_axis_reset_n;
    // Start PHY training only after the final XMSTA write was ACKed. The
    // 201-register I2C sequence is longer than the PHY scan's no-data timeout;
    // releasing at PWDNB would finish training before the sensor starts.
    wire rx_async_n=pll_lock && pwdnb && cfg_done;
    v2_reset_sync u_ref_reset(lp_clk,rx_async_n,rx_ref_reset_n);
    v2_reset_sync u_axis_reset(cam_clk,rx_async_n,rx_axis_reset_n);
    wire rv,rs,re;wire [39:0] rd;wire [7:0] phy_debug,phy_delay;
    wire auto_done;wire [5:0] best_len;
    // PH1_PHY_LCLK is unavailable in the PH1A90SEG324 package. Keep the
    // package-supported PH1A clock/IDDR path; its delay/alignment behavior
    // is handled in the V2 PHY implementation below.
    v2rx_mipi_csi_rx #(.MIPI_LAN(4),.DEVICE("PH1A")) u_rx(
        .I_debug_button(1'b1),.I_ref_clock(lp_clk),.I_clk_hs_rx_p(clk_hs),
        .I_reset_n(rx_ref_reset_n),.I_hs_data_p(data_hs),.I_enable(1'b1),
        .O_hs_div_clk(cam_clk),.m_axis_video_aclk(cam_clk),
        .m_axis_video_aresetn(rx_axis_reset_n),.m_axis_video_tready(1'b1),
        .m_axis_video_tuser(rs),.m_axis_video_tlast(re),
        .m_axis_video_tvalid(rv),.m_axis_video_tdata(rd),
        .O_auto_delay_done(auto_done),.O_dbg_mipi(phy_debug),.O_dbg_delay(phy_delay),.O_dbg_best_len(best_len));
    wire [31:0] crop_errors;
    v2_axis_crop u_crop(
        .clk(cam_clk),.rst_n(rx_axis_reset_n),.s_data(rd),.s_valid(rv),.s_sof(rs),.s_eol(re),
        .m_data(raw),.m_valid(valid),.m_sof(sof),.m_eol(eol),.row_odd(row_odd),
        .format_errors(crop_errors));
    reg [31:0] rx_words,rx_frames,crop_frames;
    always @(posedge cam_clk or negedge rx_axis_reset_n) begin
        if(!rx_axis_reset_n) begin rx_words<=0;rx_frames<=0;crop_frames<=0;end
        else begin
            if(rv) rx_words<=rx_words+1'b1;
            if(rs) rx_frames<=rx_frames+1'b1;
            if(valid && sof) crop_frames<=crop_frames+1'b1;
        end
    end
    // A continuously exchanged snapshot proves byte-clock activity even
    // while no packet has been decoded. A separate flag is exposed in bit19.
    wire [159:0] rx_snapshot;wire rx_snapshot_valid;
    reg [159:0] rx_debug;
    reg [19:0] snapshot_age;
    v2_mailbox #(.WIDTH(160)) u_rx_stats(
        .rst_n(rx_async_n),.s_clk(cam_clk),.s_data({9'd0,best_len,phy_delay,auto_done,phy_debug,crop_errors,crop_frames,rx_frames,rx_words}),
        .s_valid(1'b1),.s_ready(),.m_clk(cfg_clk),.m_data(rx_snapshot),
        .m_valid(rx_snapshot_valid),.m_ready(1'b1));
    always @(posedge cfg_clk or negedge cfg_reset_n) begin
        if(!cfg_reset_n) begin rx_debug<=0;snapshot_age<=20'hfffff;end
        else if(!pwdnb) begin rx_debug<=0;snapshot_age<=20'hfffff;end
        else if(rx_snapshot_valid) begin rx_debug<=rx_snapshot;snapshot_age<=0;end
        else if(snapshot_age!=20'hfffff) snapshot_age<=snapshot_age+1'b1;
    end
    assign diagnostics={rx_debug[127:0],last_failure,nacks,(progress | {rx_debug[135:128],3'd0,rx_debug[136],(snapshot_age<240000),19'd0})};
    // [15] no-eye fallback, [14] done, [13:8] eye width,
    // [7] load pulse, [6] manual mode, [5:0] selected tap.
    assign calibration={16'd0,
        (rx_debug[136] && rx_debug[150:145]==0 && !rx_debug[143]),
        rx_debug[136],rx_debug[150:145],rx_debug[144:137]};
endmodule
