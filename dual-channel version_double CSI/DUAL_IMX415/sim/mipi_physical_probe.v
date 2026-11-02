`timescale 1ns/1ps
// Non-programmable physical connectivity probe, NOT the camera application.
// Production 37.125MHz profile enables both receivers. K16 is not INCK.
module mipi_physical_probe (
    input wire I_sysclk_25m,
    output wire O_cam_a_scl,O_cam_b_scl,
    inout wire IO_cam_a_sda,IO_cam_b_sda,
    output wire O_cam_a_pwdnb,O_cam_b_pwdnb,O_cam_refclk,
    input wire I_cam_a_clk_hs,I_cam_b_clk_hs,
    input wire [3:0] I_cam_a_data_hs,I_cam_b_data_hs
);
    wire cfg_clk,lp_clk,lock;
    ui_pll X_ui_pll (.refclk(I_sysclk_25m),.reset(1'b0),.lock(lock),
        .clk0_out(lp_clk),.clk1_out(cfg_clk),.clk2_out(),.clk3_out(),
        .clk4_out(),.clk5_out(),.clk6_out());
    wire [1:0] cam_clk,valid,sof,eol,odd,cfg_done,iic_error;
    wire [39:0] raw [0:1];wire [223:0] errors [0:1];
    v2_camera_frontend #(.INCK_HZ(37125000)) u_camera_a (
        .cfg_clk(cfg_clk),.lp_clk(lp_clk),.pll_lock(lock),.stream_rst_n(lock),
        .clk_hs(I_cam_a_clk_hs),.data_hs(I_cam_a_data_hs),
        .scl(O_cam_a_scl),.sda(IO_cam_a_sda),.pwdnb(O_cam_a_pwdnb),.cam_clk(cam_clk[0]),
        .raw(raw[0]),.valid(valid[0]),.sof(sof[0]),.eol(eol[0]),.row_odd(odd[0]),
        .cfg_done(cfg_done[0]),.iic_error(iic_error[0]),.diagnostics(errors[0]));
    v2_camera_frontend #(.INCK_HZ(37125000)) u_camera_b (
        .cfg_clk(cfg_clk),.lp_clk(lp_clk),.pll_lock(lock),.stream_rst_n(lock),
        .clk_hs(I_cam_b_clk_hs),.data_hs(I_cam_b_data_hs),
        .scl(O_cam_b_scl),.sda(IO_cam_b_sda),.pwdnb(O_cam_b_pwdnb),.cam_clk(cam_clk[1]),
        .raw(raw[1]),.valid(valid[1]),.sof(sof[1]),.eol(eol[1]),.row_odd(odd[1]),
        .cfg_done(cfg_done[1]),.iic_error(iic_error[1]),.diagnostics(errors[1]));
    reg [1:0] checksum;
    generate for(genvar c=0;c<2;c=c+1) begin: g_signature
        always @(posedge cam_clk[c] or negedge lock)
            if(!lock) checksum[c]<=0;
            else checksum[c]<=checksum[c] ^ ^{raw[c],valid[c],sof[c],eol[c],odd[c],errors[c]};
    end endgenerate
    assign O_cam_refclk=^{checksum,cfg_done,iic_error};
endmodule
