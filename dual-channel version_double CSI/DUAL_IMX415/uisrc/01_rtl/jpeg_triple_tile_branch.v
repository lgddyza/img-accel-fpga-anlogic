`timescale 1ns/1ps

// Complete 8-row stripe split across three monochrome JPEG encoders.
// 1080 rows become three 1920x360 independent JPEG images. GREY C2H0 and DSI
// still receive the original 60 FPS stream; A/B/C use C2H1/2/3.
module jpeg_triple_tile_branch #(
    parameter integer IMG_WIDTH=1920,
    parameter integer IMG_HEIGHT=1080,
    parameter integer INPUT_FIFO_ADDR_WIDTH=8,
    parameter integer OUTPUT_FIFO_ADDR_WIDTH=7,
    parameter integer V2_SCHEDULED=0
) (
    input wire cam_clk,cam_rst_n,
    input wire user_clk,user_rst_n,
    input wire enc_clk,enc_pll_lock,
    input wire [127:0] s_rgb4,
    input wire s_valid,s_sof,s_eol,
    input wire enable,reset_pulse,link_up,full_rate,
    input wire [6:0] quality,
    input wire a_ready,b_ready,c_ready,
    output wire [127:0] a_data,b_data,c_data,
    output wire [15:0] a_keep,b_keep,c_keep,
    output wire a_valid,a_last,b_valid,b_last,c_valid,c_last,
    output wire status_configured,status_busy,status_fault,
    output wire [6:0] status_quality,
    output reg [31:0] sent_a,sent_b,sent_c,fault_count,
    output wire [31:0] bytes_a,bytes_b,bytes_c,
    output wire [17:0] debug_status,
    output wire [31:0] debug_detail,
    output wire input_armed,
    output wire input_ready,
    output reg group_done_cam,
    output wire fault_cam,
    output wire [35:0] input_levels,
    output wire [287:0] enc_performance
);
    initial if (IMG_HEIGHT % 24 != 0)
        $error("jpeg_triple_tile_branch requires a height divisible by 24");
    reg [5:0] reset_count;
    always @(posedge user_clk or negedge user_rst_n)
        if(!user_rst_n) reset_count<=6'd32;
        else if(reset_pulse) reset_count<=6'd32;
        else if(reset_count!=0) reset_count<=reset_count-1'b1;
    // One common asynchronous assertion, separate synchronous releases.
    // Avoid chaining enc->cam->user resets across unrelated PLL domains.
    wire common_rst_n=user_rst_n && cam_rst_n && enc_pll_lock && reset_count==0;
    wire branch_rst_n,enc_rst_n,cam_branch_rst_n;
    v2_reset_sync u_user_reset(user_clk,common_rst_n,branch_rst_n);
    v2_reset_sync u_enc_reset(enc_clk,common_rst_n,enc_rst_n);
    v2_reset_sync u_cam_reset(cam_clk,common_rst_n,cam_branch_rst_n);

    wire [63:0] yuyv4;
    wire gray_valid,gray_sof,gray_eol;
    gray4_to_yuyv4 u_format (
        .clk(cam_clk),.rst_n(cam_branch_rst_n),
        .s_rgb(s_rgb4),.s_valid(s_valid),.s_sof(s_sof),.s_eol(s_eol),
        .m_yuyv(yuyv4),.m_valid(gray_valid),
        .m_sof(gray_sof),.m_eol(gray_eol)
    );

    (* ASYNC_REG="TRUE" *) reg [1:0] enable_enc,link_enc,
                                  dma_a_enc,dma_b_enc,dma_c_enc;
    (* ASYNC_REG="TRUE" *) reg [6:0] quality_meta,quality_enc;
    always @(posedge enc_clk or negedge enc_rst_n)
        if(!enc_rst_n) begin
            enable_enc<=0;link_enc<=0;dma_a_enc<=0;dma_b_enc<=0;dma_c_enc<=0;
            quality_meta<=7'd85;quality_enc<=7'd85;
        end else begin
            enable_enc<={enable_enc[0],enable};
            link_enc<={link_enc[0],link_up};
            dma_a_enc<={dma_a_enc[0],a_ready};
            dma_b_enc<={dma_b_enc[0],b_ready};
            dma_c_enc<={dma_c_enc[0],c_ready};
            quality_meta<=quality;quality_enc<=quality_meta;
        end

    wire [2:0] cfg_ready,bridge_fault,packer_fault;
    wire [2:0] input_room;
    assign input_ready=cam_branch_rst_n && &input_room;
    wire [6:0] cfg_quality [0:2];
    wire [3:0] bridge_cause [0:2];
    wire [9:0] bridge_fault_line [0:2];
    wire [9:0] bridge_fault_beat [0:2];
    wire [2:0] vid_valid,vid_ready,vid_sof,vid_eol;
    wire [2:0] packet_sent;
    wire [2:0] jpg_valid_lane,jpg_last_lane;
    wire [15:0] vid_data [0:2];
    wire [31:0] last_bytes [0:2];
    reg [2:0] busy;
    wire fault_enc=(|bridge_fault) || (|packer_fault);
    wire configured_enc=&cfg_ready;
    wire arm_enc=enable_enc[1] && link_enc[1] &&
                 (V2_SCHEDULED || (dma_a_enc[1] && dma_b_enc[1] && dma_c_enc[1])) &&
                 configured_enc && cfg_quality[0]==quality_enc &&
                 cfg_quality[1]==quality_enc && cfg_quality[2]==quality_enc &&
                 !(|busy) && !fault_enc;
    (* ASYNC_REG="TRUE" *) reg [1:0] arm_cam,full_rate_cam;
    reg frame_phase,source_start,frame_selected;
    reg [1:0] stripe_index;
    reg [10:0] source_y;
    wire [10:0] cur_y=gray_sof ? 11'd0 : source_y;
    wire [1:0] cur_stripe=gray_sof ? 2'd0 : stripe_index;
    wire b_sof=gray_valid && cur_y==11'd8 && source_start;
    wire c_sof=gray_valid && cur_y==11'd16 && source_start;
    // Retain the verified 30 FPS selection as the reset/default mode. In
    // full-rate mode every camera SOF is eligible if all three encoders and
    // DMA lanes have finished the preceding frame.
    wire a_take=arm_cam[1] && (full_rate_cam[1] || !frame_phase);
    wire b_take=frame_selected;
    always @(posedge cam_clk or negedge cam_branch_rst_n) begin
        if(!cam_branch_rst_n) begin
            arm_cam<=0;full_rate_cam<=0;
            frame_phase<=0;source_y<=0;stripe_index<=0;
            source_start<=1;frame_selected<=0;
        end else begin
            arm_cam<={arm_cam[0],arm_enc};
            full_rate_cam<={full_rate_cam[0],full_rate};
            if(gray_valid) begin
                if(gray_sof) begin
                    source_y<=0;stripe_index<=0;source_start<=0;
                    frame_selected<=a_take;
                    frame_phase<=~frame_phase;
                end else if(gray_eol) begin
                    source_y<=source_y+1'b1;
                    if(source_y[2:0]==3'd7)
                        stripe_index<=stripe_index==2'd2 ? 2'd0 : stripe_index+1'b1;
                    source_start<=1;
                end else source_start<=0;
            end
        end
    end

    reg [2:0] sent_toggle;
    reg [2:0] sent_meta,sent_sync,sent_seen;
    always @(posedge user_clk or negedge branch_rst_n)
        if(!branch_rst_n) sent_toggle<=0;
        else sent_toggle<=sent_toggle ^ packet_sent;
    assign input_armed=arm_cam[1] && cam_branch_rst_n;
    (* ASYNC_REG="TRUE" *) reg [1:0] fault_cam_sync;
    always @(posedge cam_clk or negedge cam_branch_rst_n)
        if(!cam_branch_rst_n) fault_cam_sync<=0;
        else fault_cam_sync<={fault_cam_sync[0],fault_enc};
    assign fault_cam=fault_cam_sync[1];
    (* ASYNC_REG="TRUE" *) reg [2:0] sent_cam_meta,sent_cam_sync;
    reg [2:0] group_baseline,group_seen;
    reg group_active;
    wire [2:0] group_new=group_seen | (sent_cam_sync ^ group_baseline);
    always @(posedge cam_clk or negedge cam_branch_rst_n) begin
        if(!cam_branch_rst_n) begin
            sent_cam_meta<=0;sent_cam_sync<=0;group_baseline<=0;group_seen<=0;
            group_done_cam<=0;group_active<=0;
        end else begin
            sent_cam_meta<=sent_toggle;sent_cam_sync<=sent_cam_meta;
            group_done_cam<=0;
            if(s_valid && s_sof) begin
                group_baseline<=sent_cam_sync;group_seen<=0;group_active<=1;
            end else if(group_active) begin
                group_seen<=group_new;
                if(&group_new) begin group_done_cam<=1;group_active<=0;end
            end
        end
    end
    always @(posedge enc_clk or negedge enc_rst_n) begin
        if(!enc_rst_n) begin
            sent_meta<=0;sent_sync<=0;sent_seen<=0;busy<=0;
        end else begin
            sent_meta<=sent_toggle;
            sent_sync<=sent_meta;
            if(vid_valid[0] && vid_ready[0] && vid_sof[0]) busy[0]<=1;
            if(vid_valid[1] && vid_ready[1] && vid_sof[1]) busy[1]<=1;
            if(vid_valid[2] && vid_ready[2] && vid_sof[2]) busy[2]<=1;
            if(sent_sync[0]!=sent_seen[0]) begin
                sent_seen[0]<=sent_sync[0];busy[0]<=0;
            end
            if(sent_sync[1]!=sent_seen[1]) begin
                sent_seen[1]<=sent_sync[1];busy[1]<=0;
            end
            if(sent_sync[2]!=sent_seen[2]) begin
                sent_seen[2]<=sent_sync[2];busy[2]<=0;
            end
        end
    end

    wire [127:0] c2h_data [0:2];
    wire [15:0] c2h_keep [0:2];
    wire [2:0] c2h_valid,c2h_last;
    wire [2:0] c2h_ready={c_ready,b_ready,a_ready};
    genvar lane;
    generate for(lane=0;lane<3;lane=lane+1) begin:g_tile
        localparam integer TILE_HEIGHT=IMG_HEIGHT/3;
        localparam integer INPUT_ADDR=INPUT_FIFO_ADDR_WIDTH+(!V2_SCHEDULED && lane==2 ? 1 : 0);
        // Stop starting ISP rows early enough to drain its in-flight rows.
        // No extra line/frame memories are allocated for this flow control.
        localparam integer RESERVE=3*(IMG_WIDTH/4)+32;
        localparam integer LIMIT=(1<<INPUT_ADDR)>RESERVE ? (1<<INPUT_ADDR)-RESERVE : 1;
        wire [INPUT_ADDR:0] queued_groups;
        assign input_levels[lane*12+:12]=queued_groups>4095 ? 12'hfff : queued_groups;
        assign input_room[lane]=queued_groups<LIMIT;
        wire tile_valid=gray_valid && cur_stripe==lane;
        wire tile_sof=lane==0 ? gray_sof : lane==1 ? b_sof : c_sof;
        wire tile_take=lane==0 ? a_take : b_take;
        jpeg_gray4_axis_cdc #(
            .IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(TILE_HEIGHT),
            // C finishes closest to the source frame boundary. Give its
            // input one extra FIFO address bit to absorb longer stalls.
            .FIFO_ADDR_WIDTH(INPUT_FIFO_ADDR_WIDTH+(!V2_SCHEDULED && lane==2 ? 1 : 0)),
            .COMPACT_MONO(V2_SCHEDULED)
        ) u_input (
            .cam_clk(cam_clk),.enc_clk(enc_clk),.rst_n(common_rst_n),
            .s_yuyv4(yuyv4),.s_valid(tile_valid),
            .s_sof(tile_sof),.s_eol(gray_eol),
            .s_take_frame(tile_take),.s_fault(),
            .s_fault_cause(bridge_cause[lane]),
            .s_fault_line(bridge_fault_line[lane]),
            .s_fault_beat(bridge_fault_beat[lane]),
            .s_selected_frames(),.s_completed_frames(),
            .m_tdata(vid_data[lane]),.m_tvalid(vid_valid[lane]),
            .m_tready(vid_ready[lane]),.m_tuser(vid_sof[lane]),
            .m_tlast(vid_eol[lane]),.m_fault(bridge_fault[lane]),
            .s_queued_groups(queued_groups)
        );
        wire [4:0] ax_awaddr;
        wire ax_awvalid,ax_awready,ax_wvalid,ax_wready;
        wire [31:0] ax_wdata;
        wire [3:0] ax_wstrb;
        wire ax_bvalid,ax_bready;
        jpeg_axil_config u_config (
            .clk(enc_clk),.rst_n(enc_rst_n),
            .quality(quality_enc),.frame_busy(busy[lane]),
            .ready(cfg_ready[lane]),.applied_quality(cfg_quality[lane]),
            .awaddr(ax_awaddr),.awvalid(ax_awvalid),.awready(ax_awready),
            .wdata(ax_wdata),.wstrb(ax_wstrb),
            .wvalid(ax_wvalid),.wready(ax_wready),
            .bvalid(ax_bvalid),.bready(ax_bready)
        );
        wire jpg_valid,jpg_last,jpg_ready;
        wire [7:0] jpg_byte;
        reg [31:0] accepted_pixels,input_wait_cycles,output_wait_cycles;
        always @(posedge enc_clk or negedge enc_rst_n)
            if(!enc_rst_n) begin accepted_pixels<=0;input_wait_cycles<=0;output_wait_cycles<=0;end
            else begin
                if(vid_valid[lane] && vid_ready[lane]) accepted_pixels<=accepted_pixels+1'b1;
                if(vid_valid[lane] && !vid_ready[lane]) input_wait_cycles<=input_wait_cycles+1'b1;
                if(jpg_valid && !jpg_ready) output_wait_cycles<=output_wait_cycles+1'b1;
            end
        assign enc_performance[lane*96+:96]={output_wait_cycles,input_wait_cycles,accepted_pixels};
        assign jpg_valid_lane[lane]=jpg_valid && jpg_ready;
        assign jpg_last_lane[lane]=jpg_valid && jpg_ready && jpg_last;
        mjpegzero_enc_top #(
            .LITE_MODE(0),.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(TILE_HEIGHT),
            .RGB_INPUT(0),.MONO(1),.OUTPUT_BACKPRESSURE(V2_SCHEDULED)
        ) u_encoder (
            .clk(enc_clk),.rst_n(enc_rst_n),
            .s_axis_vid_tdata(vid_data[lane]),
            .s_axis_vid_tvalid(vid_valid[lane]),
            .s_axis_vid_tready(vid_ready[lane]),
            .s_axis_vid_tlast(vid_eol[lane]),
            .s_axis_vid_tuser(vid_sof[lane]),
            .m_axis_jpg_tvalid(jpg_valid),
            .m_axis_jpg_tdata(jpg_byte),
            .m_axis_jpg_tlast(jpg_last),
            .m_axis_jpg_tready(jpg_ready),
            .s_axi_awaddr(ax_awaddr),.s_axi_awvalid(ax_awvalid),
            .s_axi_awready(ax_awready),.s_axi_wdata(ax_wdata),
            .s_axi_wstrb(ax_wstrb),.s_axi_wvalid(ax_wvalid),
            .s_axi_wready(ax_wready),.s_axi_bresp(),
            .s_axi_bvalid(ax_bvalid),.s_axi_bready(ax_bready),
            .s_axi_araddr(5'd0),.s_axi_arvalid(1'b0),
            .s_axi_arready(),.s_axi_rdata(),.s_axi_rresp(),
            .s_axi_rvalid(),.s_axi_rready(1'b0)
        );
        jpeg_byte_packer #(.FIFO_ADDR_WIDTH(OUTPUT_FIFO_ADDR_WIDTH),.STALLABLE_INPUT(V2_SCHEDULED)) u_packer (
            .enc_clk(enc_clk),.user_clk(user_clk),.rst_n(common_rst_n),
            .s_byte(jpg_byte),.s_valid(jpg_valid),.s_last(jpg_last),
            .s_ready(jpg_ready),
            .fault(packer_fault[lane]),
            .m_data(c2h_data[lane]),.m_keep(c2h_keep[lane]),
            .m_valid(c2h_valid[lane]),.m_last(c2h_last[lane]),
            .m_ready(c2h_ready[lane]),.frame_sent(packet_sent[lane]),
            .last_frame_bytes(last_bytes[lane])
        );
    end endgenerate
    assign a_data=c2h_data[0];assign a_keep=c2h_keep[0];
    assign a_valid=c2h_valid[0];assign a_last=c2h_last[0];
    assign b_data=c2h_data[1];assign b_keep=c2h_keep[1];
    assign b_valid=c2h_valid[1];assign b_last=c2h_last[1];
    assign c_data=c2h_data[2];assign c_keep=c2h_keep[2];
    assign c_valid=c2h_valid[2];assign c_last=c2h_last[2];

    // Sticky per-lane milestones make an on-board failure diagnosable without
    // changing the live JPEG data path. Bit order within each group is A/B/C.
    reg [2:0] input_seen,jpg_byte_seen,jpg_eoi_seen;
    always @(posedge enc_clk or negedge enc_rst_n)
        if(!enc_rst_n) begin
            input_seen<=0;jpg_byte_seen<=0;jpg_eoi_seen<=0;
        end else begin
            input_seen<=input_seen | (vid_valid & vid_ready & vid_sof);
            jpg_byte_seen<=jpg_byte_seen | jpg_valid_lane;
            jpg_eoi_seen<=jpg_eoi_seen | jpg_last_lane;
        end
    wire [17:0] debug_enc={jpg_eoi_seen,jpg_byte_seen,input_seen,
                           cfg_ready,packer_fault,bridge_fault};
    (* ASYNC_REG="TRUE" *) reg [17:0] debug_meta,debug_sync;
    always @(posedge user_clk or negedge branch_rst_n)
        if(!branch_rst_n) begin
            debug_meta<=0;debug_sync<=0;
        end else begin
            debug_meta<=debug_enc;debug_sync<=debug_meta;
        end
    assign debug_status=debug_sync;

    // Publish a quality value only after all three encoders report the same
    // completed configuration. This is the applied value, not just the BAR
    // request, so RK can distinguish acceptance from actual table update.
    reg [6:0] applied_quality_enc;
    always @(posedge enc_clk or negedge enc_rst_n)
        if(!enc_rst_n) applied_quality_enc<=0;
        else if(configured_enc && cfg_quality[0]==cfg_quality[1] &&
                cfg_quality[1]==cfg_quality[2])
            applied_quality_enc<=cfg_quality[0];
    // First-error details: C cause[3:0], C line[13:4], C beat[23:14],
    // B cause[27:24], A cause[31:28]. Values remain fixed after a fault.
    wire [31:0] detail_cam={bridge_cause[0],bridge_cause[1],
                            bridge_fault_beat[2],bridge_fault_line[2],
                            bridge_cause[2]};
    (* ASYNC_REG="TRUE" *) reg [31:0] detail_meta,detail_sync;
    always @(posedge user_clk or negedge branch_rst_n)
        if(!branch_rst_n) begin
            detail_meta<=0;detail_sync<=0;
        end else begin
            detail_meta<=detail_cam;detail_sync<=detail_meta;
        end
    assign debug_detail=detail_sync;

    (* ASYNC_REG="TRUE" *) reg [1:0] fault_user,cfg_user,busy_user;
    (* ASYNC_REG="TRUE" *) reg [6:0] quality_user_meta,quality_user_sync;
    (* ASYNC_REG="TRUE" *) reg [31:0] bytes_a_meta,bytes_b_meta,bytes_c_meta,
                                  bytes_a_sync,bytes_b_sync,bytes_c_sync;
    reg fault_seen;
    always @(posedge user_clk or negedge branch_rst_n) begin
        if(!branch_rst_n) begin
            fault_user<=0;cfg_user<=0;busy_user<=0;
            quality_user_meta<=0;quality_user_sync<=0;
            bytes_a_meta<=0;bytes_b_meta<=0;bytes_c_meta<=0;
            bytes_a_sync<=0;bytes_b_sync<=0;bytes_c_sync<=0;
            sent_a<=0;sent_b<=0;sent_c<=0;fault_count<=0;fault_seen<=0;
        end else begin
            fault_user<={fault_user[0],fault_enc};
            cfg_user<={cfg_user[0],configured_enc};
            busy_user<={busy_user[0],(|busy)};
            quality_user_meta<=applied_quality_enc;
            quality_user_sync<=quality_user_meta;
            bytes_a_meta<=last_bytes[0];bytes_b_meta<=last_bytes[1];
            bytes_c_meta<=last_bytes[2];
            bytes_a_sync<=bytes_a_meta;bytes_b_sync<=bytes_b_meta;
            bytes_c_sync<=bytes_c_meta;
            if(packet_sent[0]) sent_a<=sent_a+1'b1;
            if(packet_sent[1]) sent_b<=sent_b+1'b1;
            if(packet_sent[2]) sent_c<=sent_c+1'b1;
            fault_seen<=fault_user[1];
            if(fault_user[1] && !fault_seen)
                fault_count<=fault_count+1'b1;
        end
    end
    // Gate ready with the synchronized value as well as the three ready bits.
    // The buses and flag cross independently, so this comparison prevents a
    // transient ready indication with the preceding quality value.
    assign status_configured=cfg_user[1] && quality_user_sync==quality;
    assign status_busy=busy_user[1];
    assign status_fault=fault_user[1];
    assign status_quality=quality_user_sync;
    assign bytes_a=bytes_a_sync;
    assign bytes_b=bytes_b_sync;
    assign bytes_c=bytes_c_sync;
endmodule
