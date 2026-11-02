`timescale 1ns/1ps
// V2: two complete 1080p60 inputs -> RAW DDR -> shared ISP/JPEG -> RK.
// No DSI transmitter, reduced-rate background channel, or display-source mux.
// Bring-up demo: the FMC board remains in its factory 37.125 MHz clock
// assembly, matching the official dual-camera example.  The 24 MHz profile
// remains available only when the FMC clock-source resistors are changed.
module dual_imx415_top #(parameter CAMERA_INCK_HZ=37125000)(
    input wire I_sysclk_25m,I_ddr_clk,
    output wire [13:0] ddr_addr,output wire [2:0] ddr_ba,
    output wire ddr_cke,ddr_odt,ddr_cs_n,ddr_ras_n,ddr_cas_n,ddr_we_n,
    output wire ddr_ck_p,ddr_ck_n,ddr_reset_n,
    inout wire [1:0] ddr_dm,inout wire [15:0] ddr_dq,
    inout wire [1:0] ddr_dqs_n,ddr_dqs_p,
    output wire O_cam_a_scl,O_cam_b_scl,inout wire IO_cam_a_sda,IO_cam_b_sda,
    output wire O_cam_a_pwdnb,O_cam_b_pwdnb,
    output wire O_cam_refclk,
    input wire I_cam_a_clk_hs,I_cam_b_clk_hs,
    input wire [3:0] I_cam_a_data_hs,I_cam_b_data_hs,
    input wire refclk_p,refclk_n,rxp,rxn,pcie_mperst,output wire txp,txn
);
    wire lp_clk,cfg_clk,pll_lock;
    ui_pll X_ui_pll (.refclk(I_sysclk_25m),.reset(1'b0),.lock(pll_lock),
        .clk0_out(lp_clk),.clk1_out(cfg_clk),.clk2_out(),.clk3_out(),
        .clk4_out(),.clk5_out(),.clk6_out());
    // The factory 37.125 MHz assembly drives the cameras, so K16 remains
    // high-Z.  The 24 MHz branch is for a separately modified FMC assembly.
    assign O_cam_refclk=CAMERA_INCK_HZ==24000000 ? cfg_clk : 1'bz;
    wire mem_clk,ddr_ready;wire [7:0] ddr_error;
    wire [27:0] awaddr,araddr;
    wire [7:0] awlen,arlen;
    wire awvalid,awready,wvalid,wready,wlast,bvalid,bready,arvalid,arready,rvalid,rready,rlast;
    wire [127:0] wdata,rdata;wire [1:0] bresp,rresp;
    wire [27:0] d_awaddr,d_araddr;wire [7:0] d_awlen,d_arlen;
    wire d_awvalid,d_awready,d_wvalid,d_wready,d_wlast,d_bvalid,d_bready;
    wire d_arvalid,d_arready,d_rvalid,d_rready,d_rlast;
    wire [127:0] d_wdata,d_rdata;wire [1:0] d_bresp,d_rresp;
    wire stream_reset_n,ddr_guard_released,ddr_guard_rst_n;
    wire [31:0] ddr_guard_debug;
    v2_reset_sync u_guard_reset(mem_clk,pll_lock && ddr_ready,ddr_guard_rst_n);
    v2_ddr_reset_guard u_ddr_guard (
        .clk(mem_clk),.rst_n(ddr_guard_rst_n),.run(stream_reset_n),
        .released(ddr_guard_released),.debug(ddr_guard_debug),
        .s_awaddr(awaddr),.s_awlen(awlen),.s_awvalid(awvalid),.s_awready(awready),
        .s_wdata(wdata),.s_wlast(wlast),.s_wvalid(wvalid),.s_wready(wready),
        .s_bresp(bresp),.s_bvalid(bvalid),.s_bready(bready),
        .s_araddr(araddr),.s_arlen(arlen),.s_arvalid(arvalid),.s_arready(arready),
        .s_rdata(rdata),.s_rresp(rresp),.s_rlast(rlast),.s_rvalid(rvalid),.s_rready(rready),
        .m_awaddr(d_awaddr),.m_awlen(d_awlen),.m_awvalid(d_awvalid),.m_awready(d_awready),
        .m_wdata(d_wdata),.m_wlast(d_wlast),.m_wvalid(d_wvalid),.m_wready(d_wready),
        .m_bresp(d_bresp),.m_bvalid(d_bvalid),.m_bready(d_bready),
        .m_araddr(d_araddr),.m_arlen(d_arlen),.m_arvalid(d_arvalid),.m_arready(d_arready),
        .m_rdata(d_rdata),.m_rresp(d_rresp),.m_rlast(d_rlast),.m_rvalid(d_rvalid),.m_rready(d_rready));
    v2_ddr_wrapper u_ddr (
        .I_ddr_clk(I_ddr_clk),.S_pll_lock(pll_lock),
        .ddr_addr(ddr_addr),.ddr_ba(ddr_ba),.ddr_cke(ddr_cke),.ddr_odt(ddr_odt),
        .ddr_cs_n(ddr_cs_n),.ddr_ras_n(ddr_ras_n),.ddr_cas_n(ddr_cas_n),.ddr_we_n(ddr_we_n),
        .ddr_ck_p(ddr_ck_p),.ddr_ck_n(ddr_ck_n),.ddr_reset_n(ddr_reset_n),
        .ddr_dm(ddr_dm),.ddr_dq(ddr_dq),.ddr_dqs_n(ddr_dqs_n),.ddr_dqs_p(ddr_dqs_p),
        .S_dfi_clk(mem_clk),.S_ddr_init_cal_done(ddr_ready),.S_ddr_init_cal_err(ddr_error),
        .awaddr(d_awaddr),.awlen(d_awlen),.awvalid(d_awvalid),.awready(d_awready),
        .wdata(d_wdata),.wlast(d_wlast),.wvalid(d_wvalid),.wready(d_wready),
        .bresp(d_bresp),.bvalid(d_bvalid),.bready(d_bready),
        .araddr(d_araddr),.arlen(d_arlen),.arvalid(d_arvalid),.arready(d_arready),
        .rdata(d_rdata),.rresp(d_rresp),.rlast(d_rlast),.rvalid(d_rvalid),.rready(d_rready));
    wire async_reset_n=pll_lock && ddr_ready && stream_reset_n && ddr_guard_released;
    (* ASYNC_REG="TRUE" *) reg [2:0] reset_pipe;
    always @(posedge mem_clk or negedge async_reset_n)
        if(!async_reset_n) reset_pipe<=0;else reset_pipe<={reset_pipe[1:0],1'b1};
    wire pipe_rst_n=reset_pipe[2];
    wire [1:0] cam_clk,cam_valid,cam_sof,cam_eol,cam_odd,cfg_done,iic_error;
    wire [39:0] cam_raw [0:1];wire [223:0] camera_diag [0:1];
    wire [31:0] camera_calibration [0:1];
    v2_camera_frontend #(.INCK_HZ(CAMERA_INCK_HZ)) u_camera_a (
        .cfg_clk(cfg_clk),.lp_clk(lp_clk),.pll_lock(pll_lock),.stream_rst_n(pipe_rst_n),
        .clk_hs(I_cam_a_clk_hs),.data_hs(I_cam_a_data_hs),
        .scl(O_cam_a_scl),.sda(IO_cam_a_sda),.pwdnb(O_cam_a_pwdnb),.cam_clk(cam_clk[0]),
        .raw(cam_raw[0]),.valid(cam_valid[0]),.sof(cam_sof[0]),.eol(cam_eol[0]),.row_odd(cam_odd[0]),
        .cfg_done(cfg_done[0]),.iic_error(iic_error[0]),.diagnostics(camera_diag[0]),.calibration(camera_calibration[0]));
    v2_camera_frontend #(.INCK_HZ(CAMERA_INCK_HZ)) u_camera_b (
        .cfg_clk(cfg_clk),.lp_clk(lp_clk),.pll_lock(pll_lock),.stream_rst_n(pipe_rst_n),
        .clk_hs(I_cam_b_clk_hs),.data_hs(I_cam_b_data_hs),
        .scl(O_cam_b_scl),.sda(IO_cam_b_sda),.pwdnb(O_cam_b_pwdnb),.cam_clk(cam_clk[1]),
        .raw(cam_raw[1]),.valid(cam_valid[1]),.sof(cam_sof[1]),.eol(cam_eol[1]),.row_odd(cam_odd[1]),
        .cfg_done(cfg_done[1]),.iic_error(iic_error[1]),.diagnostics(camera_diag[1]),.calibration(camera_calibration[1]));
    wire [127:0] capture_data [0:1];wire [1:0] capture_valid,capture_ready;
    wire [31:0] source_frames [0:1],overflows [0:1],format_errors [0:1];
    wire [15:0] capture_level [0:1];
    generate for(genvar c=0;c<2;c=c+1) begin:g_capture
        v2_raw_capture u_capture (
            .rst_n(pipe_rst_n),.cam_clk(cam_clk[c]),.raw(cam_raw[c]),
            .valid(cam_valid[c]),.sof(cam_sof[c]),.eol(cam_eol[c]),.row_odd(cam_odd[c]),
            .mem_clk(mem_clk),.data(capture_data[c]),.data_valid(capture_valid[c]),.data_ready(capture_ready[c]),
            .source_frames(source_frames[c]),.overflow_frames(overflows[c]),.format_errors(format_errors[c]),
            .queued_words(capture_level[c]));
    end endgenerate
    // Source counters are observed using coherent mailboxes, never sampled as
    // unrelated binary bits. These snapshots are diagnostic, not flow control.
    wire [95:0] cap_snapshot [0:1];wire [1:0] cap_snap_valid;
    reg [95:0] cap_stats [0:1];
    generate for(genvar c=0;c<2;c=c+1) begin:g_cap_stats
        v2_mailbox #(.WIDTH(96)) u_mail (
            .rst_n(pipe_rst_n),.s_clk(cam_clk[c]),
            .s_data({format_errors[c],overflows[c],source_frames[c]}),.s_valid(1'b1),.s_ready(),
            .m_clk(mem_clk),.m_data(cap_snapshot[c]),.m_valid(cap_snap_valid[c]),.m_ready(1'b1));
        always @(posedge mem_clk or negedge pipe_rst_n)
            if(!pipe_rst_n) cap_stats[c]<=0;else if(cap_snap_valid[c]) cap_stats[c]<=cap_snapshot[c];
    end endgenerate
    wire capture_enable,jpeg_armed,jpeg_done,jpeg_fault,metadata_ready,metadata_valid;
    wire line_fault,preproc_error;
    wire [2:0] mode_a,mode_b,frame_mode;wire [6:0] quality,quality_b,quality_applied;
    wire independent_qf;wire [31:0] config_epoch;
    wire [2:0] strength_a,strength_b;
    wire [127:0] metadata;wire camera;
    wire [39:0] replay_raw;wire replay_valid,replay_sof,replay_eol,replay_odd;
    wire [31:0] captured_a,captured_b,dropped_a,dropped_b,delivered_a,delivered_b,axi_errors;
    wire [11:0] slot_debug;wire read_fault;
    wire [127:0] first_fault;
    wire [1535:0] store_diagnostics;
    wire replay_ready,jpeg_input_ready;
    wire [35:0] jpeg_input_levels,isp_reserved,isp_peak;
    wire row_ready,row_started,row_waiting,credit_fault;
    v2_frame_store #(.RAW_IDLE_CYCLES(1)) u_store (
        .clk(mem_clk),.rst_n(pipe_rst_n),
        .a_data(capture_data[0]),.b_data(capture_data[1]),.a_valid(capture_valid[0]),.b_valid(capture_valid[1]),
        .a_ready(capture_ready[0]),.b_ready(capture_ready[1]),.a_level(capture_level[0]),.b_level(capture_level[1]),
        .awaddr(awaddr),.awlen(awlen),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wlast(wlast),.wvalid(wvalid),.wready(wready),.bresp(bresp),.bvalid(bvalid),.bready(bready),
        .araddr(araddr),.arlen(arlen),.arvalid(arvalid),.arready(arready),
        .rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),
        .enable(capture_enable),.mode_a(mode_a),.mode_b(mode_b),
        .strength_a(strength_a),.strength_b(strength_b),.quality(quality),.quality_b(quality_b),
        .independent_qf(independent_qf),.jpeg_quality(quality_applied),.config_epoch(config_epoch),
        .jpeg_armed(jpeg_armed),.jpeg_done(jpeg_done),.jpeg_fault(jpeg_fault || line_fault || preproc_error || credit_fault),
        .metadata(metadata),.metadata_valid(metadata_valid),.metadata_ready(metadata_ready),
        .camera(camera),.frame_mode(frame_mode),.raw(replay_raw),.raw_valid(replay_valid),
        .raw_sof(replay_sof),.raw_eol(replay_eol),.raw_first_row_odd(replay_odd),
        .raw_ready(replay_ready),
        .captured_a(captured_a),.captured_b(captured_b),.dropped_a(dropped_a),.dropped_b(dropped_b),
        .delivered_a(delivered_a),.delivered_b(delivered_b),.axi_errors(axi_errors),.slot_debug(slot_debug),
        .read_fault(read_fault),.first_fault(first_fault),.diagnostics(store_diagnostics));
    wire [127:0] isp_rgb;wire isp_valid,isp_sof,isp_eol;
    wire [39:0] isp_raw;
    wire isp_input_valid,isp_input_sof,isp_input_eol;
    // ui_zhenghe reads a row with a 50-cycle offset. Keep its tail and
    // registered row-reset stages clear even when DDR catches up in bursts.
    v2_line_replay #(.BACKPRESSURE(1),.MIN_LINE_GAP(64)) u_line_replay (
        .clk(mem_clk),.rst_n(pipe_rst_n),.s_data(replay_raw),
        .s_valid(replay_valid),.s_sof(replay_sof),.s_eol(replay_eol),
        .m_data(isp_raw),.m_valid(isp_input_valid),.m_sof(isp_input_sof),.m_eol(isp_input_eol),.fault(line_fault),
        .s_ready(replay_ready),.m_start_ready(row_ready),
        .line_started(row_started),.line_waiting(row_waiting));
    ui_isp_top #(.ENABLE_DSI_BRANCH(0),.COMPACT_FIXED_ISP(1)) u_isp (
        .I_clk(mem_clk),.I_rst_n(pipe_rst_n),.I_tdata(isp_raw),.I_tvalid(isp_input_valid),
        .I_tuser(isp_input_sof),.I_tlast(isp_input_eol),.I_tdest(10'd0),.O_tready(1'b1),
        .O_tdata(isp_rgb),.O_tvalid(isp_valid),.O_tuser(isp_sof),.O_tlast(isp_eol),.I_tready(),
        .I_first_row_odd(replay_odd),.I_dsi_control(4'd0),
        .O_dsi_tdata(),.O_dsi_tvalid(),.O_dsi_tuser(),.O_dsi_tlast(),.O_dsi_phase());
    wire [127:0] processed;wire pv,ps,pe;
    wire [127:0] observer_rgb;wire ov,os,oe;
    wire [31:0] hist_frames [0:1],hist_errors [0:1];
    v2_dual_preprocess u_preproc (
        .camera(camera),.clk(mem_clk),.rst_n(pipe_rst_n),.s_rgb(isp_rgb),
        .s_valid(isp_valid),.s_sof(isp_sof),.s_eol(isp_eol),.mode(frame_mode),.strength(metadata[58:56]),
        .m_rgb_gray(processed),.m_valid(pv),.m_sof(ps),.m_eol(pe),
        .gauss_overrun(preproc_error),.applied_mode(),
        .hist_frames_a(hist_frames[0]),.hist_frames_b(hist_frames[1]),
        .hist_errors_a(hist_errors[0]),.hist_errors_b(hist_errors[1]),
        .observer_rgb(observer_rgb),.observer_valid(ov),.observer_sof(os),.observer_eol(oe));
    wire [511:0] feature_result;
    wire feature_valid,feature_ready;
    v2_feature_observer u_feature_observer (
        .clk(mem_clk),.rst_n(pipe_rst_n),.rgb(observer_rgb),.metadata(metadata),
        .valid(ov),.sof(os),.eol(oe),.result(feature_result),
        .result_valid(feature_valid),.result_ready(feature_ready));
    v2_isp_row_credit #(.FIFO_GROUPS(4096)) u_row_credit (
        .clk(mem_clk),.rst_n(pipe_rst_n),.line_started(row_started),
        .processed_valid(pv),.processed_sof(ps),.processed_eol(pe),
        .queued_groups(jpeg_input_levels),.line_ready(row_ready),.fault(credit_fault),
        .reserved_groups(isp_reserved),.peak_groups(isp_peak));
    reg [31:0] perf_tick,perf_raw,perf_input,perf_isp,perf_processed;
    reg [31:0] perf_line_wait,perf_raw_wait,perf_ar_wait,perf_r_blocked;
    reg [31:0] perf_aw_wait,perf_w_wait,perf_b_wait;
    always @(posedge mem_clk or negedge pipe_rst_n)
        if(!pipe_rst_n) begin
            perf_tick<=0;perf_raw<=0;perf_input<=0;perf_isp<=0;perf_processed<=0;
            perf_line_wait<=0;perf_raw_wait<=0;perf_ar_wait<=0;perf_r_blocked<=0;
            perf_aw_wait<=0;perf_w_wait<=0;perf_b_wait<=0;
        end else begin
            perf_tick<=perf_tick+1'b1;
            if(replay_valid) perf_raw<=perf_raw+1'b1;
            if(isp_input_valid) perf_input<=perf_input+1'b1;
            if(isp_valid) perf_isp<=perf_isp+1'b1;
            if(pv) perf_processed<=perf_processed+1'b1;
            if(row_waiting && !row_ready) perf_line_wait<=perf_line_wait+1'b1;
            if(!replay_ready && capture_enable) perf_raw_wait<=perf_raw_wait+1'b1;
            if(arvalid && !arready) perf_ar_wait<=perf_ar_wait+1'b1;
            if(rvalid && !rready) perf_r_blocked<=perf_r_blocked+1'b1;
            if(awvalid && !awready) perf_aw_wait<=perf_aw_wait+1'b1;
            if(wvalid && !wready) perf_w_wait<=perf_w_wait+1'b1;
            if(bready && !bvalid) perf_b_wait<=perf_b_wait+1'b1;
        end
    wire [511:0] pipeline_statistics={
        26'd0,credit_fault,line_fault,isp_peak[35:24],isp_peak[23:12],isp_peak[11:0],
        28'd0,isp_reserved[35:32],isp_reserved[31:0],
        perf_b_wait,perf_w_wait,perf_aw_wait,perf_r_blocked,perf_ar_wait,
        perf_raw_wait,perf_line_wait,perf_processed,perf_isp,perf_input,perf_raw,perf_tick};
    (* ASYNC_REG="TRUE" *) reg [3:0] cfg_status_meta,cfg_status;
    always @(posedge mem_clk or negedge pipe_rst_n)
        if(!pipe_rst_n) begin cfg_status_meta<=0;cfg_status<=0;end
        else begin cfg_status_meta<={iic_error,cfg_done};cfg_status<=cfg_status_meta;end
    wire [671:0] statistics={ddr_guard_debug,first_fault,
        hist_errors[1],hist_errors[0],
        cap_stats[1][95:64],cap_stats[0][95:64],
        cap_stats[1][63:32],cap_stats[0][63:32],
        cap_stats[1][31:0],cap_stats[0][31:0],
        4'd0,line_fault,cfg_status,(CAMERA_INCK_HZ==24000000 || CAMERA_INCK_HZ==37125000),preproc_error,read_fault,ddr_error,slot_debug,
        axi_errors,delivered_b,delivered_a,dropped_b,dropped_a,captured_b,captured_a};
    // Independent configuration-clock snapshot remains readable if DDR
    // initialization fails. Level inputs get two-stage synchronization here.
    (* ASYNC_REG="TRUE" *) reg [11:0] diag_meta,diag_sync;
    reg [31:0] diag_heartbeat;
    always @(posedge cfg_clk or negedge pll_lock) begin
        if(!pll_lock) begin diag_meta<=0;diag_sync<=0;diag_heartbeat<=0;end
        else begin
            diag_meta<={ddr_error,stream_reset_n,pipe_rst_n,ddr_ready,pll_lock};
            diag_sync<=diag_meta;diag_heartbeat<=diag_heartbeat+1'b1;
        end
    end
    wire [575:0] diagnostics={camera_calibration[1],camera_calibration[0],
        diag_heartbeat,camera_diag[1],camera_diag[0],20'd0,diag_sync};
    v2_pcie_endpoint u_pcie (
        .sys_clk(I_sysclk_25m),.jpeg_refclk(I_ddr_clk),.refclk_p(refclk_p),.refclk_n(refclk_n),
        .rxp(rxp),.rxn(rxn),.pcie_mperst(pcie_mperst),.txp(txp),.txn(txn),.stream_reset_n(stream_reset_n),
        .diag_clk(cfg_clk),.diagnostics(diagnostics),
        .pipe_clk(mem_clk),.pipe_rst_n(pipe_rst_n),.metadata(metadata),.metadata_valid(metadata_valid),.metadata_ready(metadata_ready),
        .processed_rgb(processed),.processed_valid(pv),.processed_sof(ps),.processed_eol(pe),
        .statistics(statistics),.pipeline_statistics(pipeline_statistics),.store_diagnostics(store_diagnostics),
        .feature_result(feature_result),.feature_valid(feature_valid),.feature_ready(feature_ready),
        .capture_enable(capture_enable),.mode_a(mode_a),.mode_b(mode_b),
        .strength_a(strength_a),.strength_b(strength_b),
        .quality_pipe(quality),.quality_b_pipe(quality_b),.independent_qf_pipe(independent_qf),
        .quality_applied_pipe(quality_applied),.config_epoch(config_epoch),.jpeg_armed(jpeg_armed),.jpeg_done(jpeg_done),
        .jpeg_fault_pipe(jpeg_fault),.jpeg_input_ready(jpeg_input_ready),.jpeg_input_levels(jpeg_input_levels));
endmodule
