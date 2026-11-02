    // Included only by the generated v2_pcie_endpoint wrapper.
    reg [63:0] cfg_request;
    reg cfg_dirty;
    reg [6:0] reset_count;
    assign stream_reset_n=user_rst_n && reset_count==0;
    wire cfg_tx_ready,cfg_rx_valid;
    wire [63:0] cfg_pipe;
    v2_mailbox #(.WIDTH(64)) u_config (
        .rst_n(user_rst_n),.s_clk(user_clk),.s_data(cfg_request),
        .s_valid(cfg_dirty),.s_ready(cfg_tx_ready),.m_clk(pipe_clk),
        .m_data(cfg_pipe),.m_valid(cfg_rx_valid),.m_ready(1'b1));
    reg [63:0] cfg_applied;
    always @(posedge pipe_clk or negedge user_rst_n)
        if(!user_rst_n) cfg_applied<={32'd0,3'd0,1'b0,7'd85,3'd4,3'd4,1'b0,7'd85,3'd0,3'd0,1'b0};
        else if(cfg_rx_valid) cfg_applied<=cfg_pipe;
    assign mode_a=cfg_applied[3:1];assign mode_b=cfg_applied[6:4];
    assign strength_a=cfg_applied[17:15];assign strength_b=cfg_applied[20:18];
    assign quality_pipe=cfg_applied[13:7];assign quality_b_pipe=cfg_applied[27:21];
    assign independent_qf_pipe=cfg_applied[28];assign config_epoch=cfg_applied[63:32];
    (* ASYNC_REG="TRUE" *) reg [1:0] host_ready_pipe;
    always @(posedge pipe_clk or negedge pipe_rst_n)
        if(!pipe_rst_n) host_ready_pipe<=0;
        else host_ready_pipe<={host_ready_pipe[0],link_up && jpeg_a_ready && jpeg_b_ready && jpeg_c_ready};
    assign capture_enable=cfg_applied[0] && host_ready_pipe[1];
    wire [127:0] metadata_user;
    wire metadata_user_valid;
    reg [127:0] current_metadata;
    reg [6:0] quality_user;
    v2_mailbox #(.WIDTH(128)) u_metadata (
        .rst_n(pipe_rst_n),.s_clk(pipe_clk),.s_data(metadata),
        .s_valid(metadata_valid),.s_ready(metadata_ready),.m_clk(user_clk),
        .m_data(metadata_user),.m_valid(metadata_user_valid),.m_ready(1'b1));
    always @(posedge user_clk or negedge pipe_rst_n)
        if(!pipe_rst_n) begin current_metadata<=0;quality_user<=85;end
        else if(metadata_user_valid) begin
            current_metadata<=metadata_user;
            quality_user<=metadata_user[55:48];
        end
    wire [671:0] snapshot_user;
    wire snapshot_valid,snapshot_ready;
    reg [671:0] snapshot;
    wire [575:0] diag_user;wire diag_valid;
    reg [575:0] diag_snapshot;
    v2_mailbox #(.WIDTH(576)) u_diag_snapshot(
        .rst_n(user_rst_n),.s_clk(diag_clk),.s_data(diagnostics),.s_valid(1'b1),.s_ready(),
        .m_clk(user_clk),.m_data(diag_user),.m_valid(diag_valid),.m_ready(1'b1));
    always @(posedge user_clk or negedge user_rst_n)
        if(!user_rst_n) diag_snapshot<=0;else if(diag_valid) diag_snapshot<=diag_user;
    v2_mailbox #(.WIDTH(672)) u_snapshot (
        .rst_n(pipe_rst_n),.s_clk(pipe_clk),.s_data(statistics),
        .s_valid(1'b1),.s_ready(snapshot_ready),.m_clk(user_clk),
        .m_data(snapshot_user),.m_valid(snapshot_valid),.m_ready(1'b1));
    always @(posedge user_clk or negedge pipe_rst_n)
        if(!pipe_rst_n) snapshot<=0;
        else if(snapshot_valid) snapshot<=snapshot_user;
    wire [511:0] performance_user;
    wire performance_valid;
    reg [511:0] performance_snapshot;
    v2_mailbox #(.WIDTH(512)) u_performance (
        .rst_n(pipe_rst_n),.s_clk(pipe_clk),.s_data(pipeline_statistics),
        .s_valid(1'b1),.s_ready(),.m_clk(user_clk),
        .m_data(performance_user),.m_valid(performance_valid),.m_ready(1'b1));
    always @(posedge user_clk or negedge pipe_rst_n)
        if(!pipe_rst_n) performance_snapshot<=0;
        else if(performance_valid) performance_snapshot<=performance_user;
    wire [1535:0] store_user;
    wire store_valid;
    reg [1535:0] store_latest,store_frozen;
    v2_mailbox #(.WIDTH(1536)) u_store_diagnostics (
        .rst_n(pipe_rst_n),.s_clk(pipe_clk),.s_data(store_diagnostics),
        .s_valid(1'b1),.s_ready(),.m_clk(user_clk),.m_data(store_user),
        .m_valid(store_valid),.m_ready(1'b1));
    // Read 0x500 first to freeze a coherent complete page for host MMIO.
    always @(posedge user_clk or negedge pipe_rst_n)
        if(!pipe_rst_n) begin store_latest<=0;store_frozen<=0;end
        else begin
            if(store_valid) store_latest<=store_user;
            if(arvalid && arready && araddr[15:0]==16'h0500) store_frozen<=store_latest;
        end
    wire [511:0] feature_user;
    wire feature_user_valid;
    reg [511:0] feature_a,feature_b,feature_frozen;
    v2_mailbox #(.WIDTH(512)) u_feature_mailbox (
        .rst_n(pipe_rst_n),.s_clk(pipe_clk),.s_data(feature_result),
        .s_valid(feature_valid),.s_ready(feature_ready),.m_clk(user_clk),
        .m_data(feature_user),.m_valid(feature_user_valid),.m_ready(1'b1));
    // Each camera's first word freezes its entire 64-byte page. The shared
    // frozen bank requires host readers to serialize complete page reads.
    always @(posedge user_clk or negedge pipe_rst_n)
        if(!pipe_rst_n) begin feature_a<=0;feature_b<=0;feature_frozen<=0;end
        else begin
            if(feature_user_valid) begin
                if(feature_user[28]) feature_b<=feature_user;else feature_a<=feature_user;
            end
            if(arvalid && arready) begin
                if(araddr[15:0]==16'h0700) feature_frozen<=feature_a;
                if(araddr[15:0]==16'h0740) feature_frozen<=feature_b;
            end
        end
    reg aw_pending,w_pending;
    reg [31:0] aw_hold,w_hold;
    reg [3:0] strb_hold;
    // Merge byte strobes before normalizing the complete tuple. A one-byte
    // QF update crosses bit7/bit8 and must not validate only one fragment.
    wire [31:0] cfg_write_mask={{8{strb_hold[3]}},{8{strb_hold[2]}},
                              {8{strb_hold[1]}},{8{strb_hold[0]}}};
    wire [31:0] cfg_merged=(cfg_request[31:0] & ~cfg_write_mask) |
                           (w_hold & cfg_write_mask);
    wire [6:0] cfg_qf=cfg_merged[13:7]<1 ? 7'd1 :
                      cfg_merged[13:7]>100 ? 7'd100 : cfg_merged[13:7];
    wire [2:0] cfg_mode_a=(cfg_merged[3:1]==1 || cfg_merged[3:1]==2 || cfg_merged[3:1]==3 || cfg_merged[3:1]==4 || cfg_merged[3:1]==5) ? cfg_merged[3:1] : 3'd0;
    wire [2:0] cfg_mode_b=(cfg_merged[6:4]==1 || cfg_merged[6:4]==2 || cfg_merged[6:4]==3 || cfg_merged[6:4]==4 || cfg_merged[6:4]==5) ? cfg_merged[6:4] : 3'd0;
    assign awready=!aw_pending && !bvalid;
    assign wready=!w_pending && !bvalid;
    reg read_pending;
    reg [3:0] read_page;
    reg [31:0] read_diag,read_stats,read_perf,read_jpeg;
    reg [31:0] read_store0,read_store1,read_store2,read_dma,read_feature,read_control;
    assign arready=!rvalid && !read_pending;
    always @(posedge user_clk or negedge user_rst_n) begin
        if(!user_rst_n) begin
            cfg_request<={32'd0,3'd0,1'b0,7'd85,3'd4,3'd4,1'b0,7'd85,3'd0,3'd0,1'b0};cfg_dirty<=1;
            reset_count<=127;aw_pending<=0;w_pending<=0;bvalid<=0;
            aw_hold<=0;w_hold<=0;strb_hold<=0;
        end else begin
            if(reset_count!=0) reset_count<=reset_count-1'b1;
            if(cfg_dirty && cfg_tx_ready) cfg_dirty<=0;
            if(awvalid && awready) begin aw_hold<=awaddr;aw_pending<=1;end
            if(wvalid && wready) begin w_hold<=wdata;strb_hold<=wstrb;w_pending<=1;end
            if(bvalid && bready) bvalid<=0;
            if(aw_pending && w_pending && !bvalid) begin
                aw_pending<=0;w_pending<=0;bvalid<=1;
                case(aw_hold[15:0])
                    16'h0218: begin
                        // Atomic parameter tuple. Bit31 requests a full pipeline reset.
                        if(|strb_hold[1:0]) begin
                            cfg_request[31:0]<={cfg_request[31:15],cfg_merged[14],cfg_qf,
                                               cfg_mode_b,cfg_mode_a,cfg_merged[0]};
                            cfg_request[63:32]<=cfg_request[63:32]+1'b1;cfg_dirty<=1;
                        end
                        if(strb_hold[3] && w_hold[31]) reset_count<=127;
                    end
                    16'h022c: if(strb_hold[0]) begin
                        cfg_request[17:15]<=w_hold[2:0]>4 ? 3'd4 : w_hold[2:0];
                        cfg_request[20:18]<=w_hold[6:4]>4 ? 3'd4 : w_hold[6:4];
                        cfg_request[63:32]<=cfg_request[63:32]+1'b1;cfg_dirty<=1;
                    end
                    16'h02a0: if(|strb_hold[2:0]) begin
                        if(strb_hold[0]) cfg_request[13:7]<=w_hold[6:0]<1 ? 7'd1 :
                            w_hold[6:0]>100 ? 7'd100 : w_hold[6:0];
                        if(strb_hold[1]) cfg_request[27:21]<=w_hold[14:8]<1 ? 7'd1 :
                            w_hold[14:8]>100 ? 7'd100 : w_hold[14:8];
                        if(strb_hold[2]) cfg_request[28]<=w_hold[16];
                        cfg_request[63:32]<=cfg_request[63:32]+1'b1;cfg_dirty<=1;
                    end
                endcase
            end
        end
    end
    wire jpeg_configured,jpeg_busy,jpeg_fault;
    wire [6:0] applied_quality;
    (* ASYNC_REG="TRUE" *) reg [6:0] applied_quality_meta,applied_quality_sync;
    always @(posedge pipe_clk or negedge pipe_rst_n)
        if(!pipe_rst_n) begin applied_quality_meta<=0;applied_quality_sync<=0;end
        else begin applied_quality_meta<=applied_quality;applied_quality_sync<=applied_quality_meta;end
    assign quality_applied_pipe=applied_quality_sync;
    wire [31:0] sent_a,sent_b,sent_c,faults;
    wire [17:0] jpeg_debug;wire [31:0] jpeg_detail;
    wire [127:0] ja,jb,jc;
    wire [15:0] ka,kb,kc;
    wire va,vb,vc,la,lb,lc,ra,rb,rc;
    wire [287:0] enc_performance,enc_performance_user;
    wire enc_performance_valid;
    reg [287:0] enc_performance_snapshot;
    v2_mailbox #(.WIDTH(288)) u_encoder_performance (
        .rst_n(pipe_rst_n),.s_clk(jpeg_enc_clk),.s_data(enc_performance),
        .s_valid(1'b1),.s_ready(),.m_clk(user_clk),
        .m_data(enc_performance_user),.m_valid(enc_performance_valid),.m_ready(1'b1));
    reg [31:0] dma_wait_a,dma_wait_b,dma_wait_c;
    always @(posedge user_clk or negedge pipe_rst_n)
        if(!pipe_rst_n) begin
            enc_performance_snapshot<=0;dma_wait_a<=0;dma_wait_b<=0;dma_wait_c<=0;
        end else begin
            if(enc_performance_valid) enc_performance_snapshot<=enc_performance_user;
            if(jpeg_a_valid && !jpeg_a_ready) dma_wait_a<=dma_wait_a+1'b1;
            if(jpeg_b_valid && !jpeg_b_ready) dma_wait_b<=dma_wait_b+1'b1;
            if(jpeg_c_valid && !jpeg_c_ready) dma_wait_c<=dma_wait_c+1'b1;
        end
    wire [383:0] jpeg_performance={dma_wait_c,dma_wait_b,dma_wait_a,enc_performance_snapshot};
    reg [63:0] dma_bytes [0:2];
    reg [31:0] dma_packets [0:2];
    reg [287:0] dma_frozen;
    wire [47:0] dma_keeps={jpeg_c_keep,jpeg_b_keep,jpeg_a_keep};
    wire [2:0] dma_takes={jpeg_c_valid && jpeg_c_ready,jpeg_b_valid && jpeg_b_ready,jpeg_a_valid && jpeg_a_ready};
    wire [2:0] dma_lasts={jpeg_c_last,jpeg_b_last,jpeg_a_last};
    function [4:0] keep_bytes(input [15:0] keep);
        integer n;
        begin keep_bytes=0;for(n=0;n<16;n=n+1) keep_bytes=keep_bytes+keep[n];end
    endfunction
    integer d;
    always @(posedge user_clk or negedge pipe_rst_n)
        if(!pipe_rst_n) begin
            for(d=0;d<3;d=d+1) begin dma_bytes[d]<=0;dma_packets[d]<=0;end
            dma_frozen<=0;
        end else begin
            for(d=0;d<3;d=d+1) if(dma_takes[d]) begin
                dma_bytes[d]<=dma_bytes[d]+keep_bytes(dma_keeps[d*16+:16]);
                if(dma_lasts[d]) dma_packets[d]<=dma_packets[d]+1'b1;
            end
            if(arvalid && arready && araddr[15:0]==16'h0600)
                dma_frozen<={dma_packets[2],dma_bytes[2],dma_packets[1],dma_bytes[1],dma_packets[0],dma_bytes[0]};
        end
    // 2048 four-pixel entries per encoder absorb 8-row bursts from the DDR
    // replay. Do not inherit V1's small real-time camera FIFO unchanged.
    // 16 KiB per lane absorbs scheduling gaps between host DMA requests.
    // Overflow remains explicit; this is not a whole-frame JPEG store.
    jpeg_triple_tile_branch #(.INPUT_FIFO_ADDR_WIDTH(12),.OUTPUT_FIFO_ADDR_WIDTH(10),.V2_SCHEDULED(1)) u_jpeg_tiles (
        .cam_clk(pipe_clk),.cam_rst_n(pipe_rst_n),.user_clk(user_clk),.user_rst_n(stream_reset_n),
        .enc_clk(jpeg_enc_clk),.enc_pll_lock(jpeg_pll_lock),
        .s_rgb4(processed_rgb),.s_valid(processed_valid),.s_sof(processed_sof),.s_eol(processed_eol),
        .enable(cfg_request[0]),.reset_pulse(1'b0),.link_up(link_up),.full_rate(1'b1),.quality(quality_user),
        .a_ready(ra),.b_ready(rb),.c_ready(rc),.a_data(ja),.b_data(jb),.c_data(jc),
        .a_keep(ka),.b_keep(kb),.c_keep(kc),.a_valid(va),.b_valid(vb),.c_valid(vc),
        .a_last(la),.b_last(lb),.c_last(lc),.status_configured(jpeg_configured),
        .status_busy(jpeg_busy),.status_fault(jpeg_fault),.status_quality(applied_quality),
        .sent_a(sent_a),.sent_b(sent_b),.sent_c(sent_c),.fault_count(faults),
        .bytes_a(),.bytes_b(),.bytes_c(),.debug_status(jpeg_debug),.debug_detail(jpeg_detail),
        .input_armed(jpeg_armed),.input_ready(jpeg_input_ready),
        .group_done_cam(jpeg_done),.fault_cam(jpeg_fault_pipe),
        .input_levels(jpeg_input_levels),.enc_performance(enc_performance));
    v2_jpeg_header #(.TILE(0)) u_header_a (
        .clk(user_clk),.rst_n(pipe_rst_n),.metadata(current_metadata),
        .s_data(ja),.s_keep(ka),.s_valid(va),.s_last(la),.s_ready(ra),
        .m_data(jpeg_a_data),.m_keep(jpeg_a_keep),.m_valid(jpeg_a_valid),.m_last(jpeg_a_last),.m_ready(jpeg_a_ready));
    v2_jpeg_header #(.TILE(1)) u_header_b (
        .clk(user_clk),.rst_n(pipe_rst_n),.metadata(current_metadata),
        .s_data(jb),.s_keep(kb),.s_valid(vb),.s_last(lb),.s_ready(rb),
        .m_data(jpeg_b_data),.m_keep(jpeg_b_keep),.m_valid(jpeg_b_valid),.m_last(jpeg_b_last),.m_ready(jpeg_b_ready));
    v2_jpeg_header #(.TILE(2)) u_header_c (
        .clk(user_clk),.rst_n(pipe_rst_n),.metadata(current_metadata),
        .s_data(jc),.s_keep(kc),.s_valid(vc),.s_last(lc),.s_ready(rc),
        .m_data(jpeg_c_data),.m_keep(jpeg_c_keep),.m_valid(jpeg_c_valid),.m_last(jpeg_c_last),.m_ready(jpeg_c_ready));
    always @(posedge user_clk or negedge user_rst_n) begin
        if(!user_rst_n) begin rvalid<=0;rdata<=0;read_pending<=0;read_page<=0;end
        else begin
            if(rvalid && rready) rvalid<=0;
            if(read_pending) begin
                read_pending<=0;rvalid<=1;
                case(read_page)
                    0:rdata<=read_diag;
                    1:rdata<=read_stats;
                    2:rdata<=read_perf;
                    3:rdata<=read_jpeg;
                    4:rdata<=read_store0;
                    5:rdata<=read_store1;
                    6:rdata<=read_store2;
                    7:rdata<=read_dma;
                    8:rdata<=read_feature;
                    default:rdata<=read_control;
                endcase
            end
            if(arvalid && arready) begin
                // Snapshot candidates at AR acceptance; select the response
                // one cycle later. Three 16-word banks bound the 48-word mux.
                read_pending<=1;
                read_diag<=diag_snapshot[araddr[5:2]*32+:32];
                read_stats<=snapshot[araddr[5:2]*32+:32];
                read_perf<=performance_snapshot[araddr[5:2]*32+:32];
                read_jpeg<=jpeg_performance[araddr[5:2]*32+:32];
                read_store0<=araddr[7:2]==0 ? store_latest[31:0] : store_frozen[araddr[5:2]*32+:32];
                read_store1<=store_frozen[512+araddr[5:2]*32+:32];
                read_store2<=store_frozen[1024+araddr[5:2]*32+:32];
                read_dma<=araddr[5:2]==0 ? dma_bytes[0][31:0] : dma_frozen[araddr[5:2]*32+:32];
                read_feature<=araddr[5:2]==0 ? (araddr[6] ? feature_b[31:0] : feature_a[31:0]) : feature_frozen[araddr[5:2]*32+:32];
                if(araddr[15:6]==10'h00c) read_page<=0;
                else if(araddr[15:6]==10'h009) read_page<=1;
                else if(araddr[15:6]==10'h010) read_page<=2;
                else if(araddr[15:6]==10'h012 && araddr[5:2]<12) read_page<=3;
                else if(araddr[15:8]==8'h05 && araddr[7:2]<48) read_page<=4+araddr[7:6];
                else if(araddr[15:6]==10'h018 && araddr[5:2]<9) read_page<=7;
                else if(araddr[15:7]==9'h00e) read_page<=8;
                else read_page<=9;
                case(araddr[15:0])
                    16'h004c,16'h0200: read_control<=32'h32435644; // DVC2 control
                    16'h005c,16'h0204: read_control<=2;
                    16'h00b0: read_control<=32'h32504a44; // DJP2 stream
                    16'h0208: read_control<=1920;
                    16'h020c: read_control<=1080;
                    16'h0210: read_control<=60;
                    16'h0214: read_control<=2;
                    16'h0284: read_control<=32'h20261024; // dual-camera gray-only bring-up
                    16'h0288: read_control<=32'h444c5931; // DLY1: persistent PH1A input delay
                    16'h028c: read_control<=32'h434c4139; // CLA9: memory mapping and control-path restructuring
                    16'h06f0: read_control<=32'h3153424f; // OBS1 page ABI v1
                    16'h06f4: read_control<=32'h20e01010; // dark<32, bright>224; sample stride16, bins16
                    16'h0290: read_control<={14'd0,jpeg_debug};
                    16'h0294: read_control<=jpeg_detail;
                    16'h0298: read_control<=16384; // JPEG payload buffer bytes per lane
                    16'h02a0: read_control<={15'd0,cfg_request[28],1'b0,cfg_request[27:21],1'b0,cfg_request[13:7]};
                    16'h02a4: read_control<=32'h32465144; // DQF2 capability
                    16'h0340: read_control<=diag_snapshot[543:512]; // camera A calibration
                    16'h0344: read_control<=diag_snapshot[575:544]; // camera B calibration
                    16'h0348: read_control<=snapshot[543:512]; // first fault flags/state
                    16'h034c: read_control<=snapshot[575:544]; // DDR read word index
                    16'h0350: read_control<=snapshot[607:576]; // replay output word index
                    16'h0354: read_control<=snapshot[639:608]; // failed source frame ID
                    16'h0358: read_control<=snapshot[671:640]; // reset-guard state/count
                    16'h0280: read_control<=32'h0000003f; // gray, Gaussian, CLAHE, Gaussian+CLAHE, Sobel, blackhat
                    16'h0218: read_control<={17'd0,cfg_request[14:0]};
                    16'h022c: read_control<={25'd0,cfg_request[20:18],1'b0,cfg_request[17:15]};
                    16'h021c: read_control<=cfg_request[63:32];
                    16'h0220: read_control<={25'd0,msi_enable,link_up,jpeg_fault,jpeg_busy,jpeg_configured,stream_reset_n,cfg_request[0]};
                    16'h0224: read_control<={25'd0,applied_quality};
                    16'h0228: read_control<=current_metadata[63:32];
                    16'h022c: read_control<=current_metadata[95:64];
                    16'h0230: read_control<=sent_a;
                    16'h0234: read_control<=sent_b;
                    16'h0238: read_control<=sent_c;
                    16'h023c: read_control<=faults;
                    default: read_control<=0;
                endcase
            end
        end
    end
