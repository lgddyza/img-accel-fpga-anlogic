`timescale 1ns/1ps

// Complete spatial split before two baseline JPEG encoders. Alternate eight
// source rows between A (544 rows) and B (536 rows). Each encoder therefore
// receives 62.2 Mpixel/s at 1080p60, within its 1080p30 input budget, while
// the existing GREY and DSI paths see the original 60 FPS stream unchanged.
// The RK reconstructs a 1080p image by weaving eight-row bands from the two
// JPEGs. A and B are separate SGDMA C2H channels (1 and 2).
module jpeg_dual_tile_branch #(
    parameter integer IMG_WIDTH=1920,
    parameter integer IMG_HEIGHT=1080,
    parameter integer INPUT_FIFO_ADDR_WIDTH=10
) (
    input wire cam_clk,cam_rst_n,
    input wire user_clk,user_rst_n,
    input wire enc_clk,enc_pll_lock,
    input wire [127:0] s_rgb4,
    input wire s_valid,s_sof,s_eol,
    input wire enable,reset_pulse,link_up,
    input wire [6:0] quality,
    input wire a_ready,b_ready,
    output wire [127:0] a_data,b_data,
    output wire [15:0] a_keep,b_keep,
    output wire a_valid,a_last,b_valid,b_last,
    output wire status_configured,status_busy,status_fault,
    output reg [31:0] sent_a,sent_b,fault_count,
    output wire [31:0] bytes_a,bytes_b
);
    reg [5:0] reset_count;
    always @(posedge user_clk or negedge user_rst_n)
        if(!user_rst_n) reset_count<=6'd32;
        else if(reset_pulse) reset_count<=6'd32;
        else if(reset_count!=0) reset_count<=reset_count-1'b1;
    wire branch_rst_n=user_rst_n && reset_count==0;
    wire enc_async_rst_n=branch_rst_n && enc_pll_lock;
    reg [1:0] enc_reset_sync;
    always @(posedge enc_clk or negedge enc_async_rst_n)
        if(!enc_async_rst_n) enc_reset_sync<=0;
        else enc_reset_sync<={enc_reset_sync[0],1'b1};
    wire enc_rst_n=enc_reset_sync[1];
    reg [1:0] cam_reset_sync;
    always @(posedge cam_clk or negedge enc_rst_n)
        if(!enc_rst_n) cam_reset_sync<=0;
        else cam_reset_sync<={cam_reset_sync[0],1'b1};
    wire cam_branch_rst_n=cam_rst_n && cam_reset_sync[1];

    wire [63:0] yuyv4;
    wire gray_valid,gray_sof,gray_eol;
    gray4_to_yuyv4 u_format (
        .clk(cam_clk),.rst_n(cam_branch_rst_n),
        .s_rgb(s_rgb4),.s_valid(s_valid),.s_sof(s_sof),.s_eol(s_eol),
        .m_yuyv(yuyv4),.m_valid(gray_valid),
        .m_sof(gray_sof),.m_eol(gray_eol)
    );

    (* ASYNC_REG="TRUE" *) reg [1:0] enable_enc,link_enc,
                                  dma_a_enc,dma_b_enc;
    (* ASYNC_REG="TRUE" *) reg [6:0] quality_meta,quality_enc;
    always @(posedge enc_clk or negedge enc_rst_n)
        if(!enc_rst_n) begin
            enable_enc<=0;link_enc<=0;dma_a_enc<=0;dma_b_enc<=0;
            quality_meta<=7'd85;quality_enc<=7'd85;
        end else begin
            enable_enc<={enable_enc[0],enable};
            link_enc<={link_enc[0],link_up};
            dma_a_enc<={dma_a_enc[0],a_ready};
            dma_b_enc<={dma_b_enc[0],b_ready};
            quality_meta<=quality;quality_enc<=quality_meta;
        end

    wire [1:0] cfg_ready,bridge_fault,packer_fault;
    wire [1:0] vid_valid,vid_ready,vid_sof,vid_eol;
    wire [1:0] packet_sent;
    wire [15:0] vid_data [0:1];
    wire [31:0] last_bytes [0:1];
    reg [1:0] busy;
    wire fault_enc=(|bridge_fault) || (|packer_fault);
    wire configured_enc=&cfg_ready;
    wire arm_enc=enable_enc[1] && link_enc[1] &&
                 dma_a_enc[1] && dma_b_enc[1] &&
                 configured_enc && !(|busy) && !fault_enc;
    (* ASYNC_REG="TRUE" *) reg [1:0] arm_cam;
    reg frame_phase,source_start,frame_selected;
    reg [10:0] source_y;
    wire [10:0] cur_y=gray_sof ? 11'd0 : source_y;
    wire stripe_a=!cur_y[3];
    wire stripe_b=cur_y[3];
    wire b_sof=gray_valid && cur_y==11'd8 && source_start;
    wire a_take=arm_cam[1] && !frame_phase;
    wire b_take=frame_selected;
    always @(posedge cam_clk or negedge cam_branch_rst_n) begin
        if(!cam_branch_rst_n) begin
            arm_cam<=0;frame_phase<=0;source_y<=0;
            source_start<=1;frame_selected<=0;
        end else begin
            arm_cam<={arm_cam[0],arm_enc};
            if(gray_valid) begin
                if(gray_sof) begin
                    source_y<=0;source_start<=0;
                    frame_selected<=a_take;
                    frame_phase<=~frame_phase;
                end else if(gray_eol) begin
                    source_y<=source_y+1'b1;
                    source_start<=1;
                end else source_start<=0;
            end
        end
    end

    reg [1:0] sent_toggle;
    reg [1:0] sent_meta,sent_sync,sent_seen;
    always @(posedge user_clk or negedge branch_rst_n)
        if(!branch_rst_n) sent_toggle<=0;
        else sent_toggle<=sent_toggle ^ packet_sent;
    always @(posedge enc_clk or negedge enc_rst_n) begin
        if(!enc_rst_n) begin
            sent_meta<=0;sent_sync<=0;sent_seen<=0;busy<=0;
        end else begin
            sent_meta<=sent_toggle;
            sent_sync<=sent_meta;
            if(vid_valid[0] && vid_ready[0] && vid_sof[0]) busy[0]<=1;
            if(vid_valid[1] && vid_ready[1] && vid_sof[1]) busy[1]<=1;
            if(sent_sync[0]!=sent_seen[0]) begin
                sent_seen[0]<=sent_sync[0];busy[0]<=0;
            end
            if(sent_sync[1]!=sent_seen[1]) begin
                sent_seen[1]<=sent_sync[1];busy[1]<=0;
            end
        end
    end

    wire [127:0] c2h_data [0:1];
    wire [15:0] c2h_keep [0:1];
    wire [1:0] c2h_valid,c2h_last;
    wire [1:0] c2h_ready={b_ready,a_ready};
    genvar lane;
    generate for(lane=0;lane<2;lane=lane+1) begin:g_tile
        localparam integer A_HEIGHT=((IMG_HEIGHT+15)/16)*8;
        localparam integer TILE_HEIGHT=lane==0 ? A_HEIGHT : IMG_HEIGHT-A_HEIGHT;
        wire tile_valid=gray_valid && (lane==0 ? stripe_a : stripe_b);
        wire tile_sof=lane==0 ? gray_sof : b_sof;
        wire tile_take=lane==0 ? a_take : b_take;
        jpeg_gray4_axis_cdc #(
            .IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(TILE_HEIGHT),
            .FIFO_ADDR_WIDTH(INPUT_FIFO_ADDR_WIDTH)
        ) u_input (
            .cam_clk(cam_clk),.enc_clk(enc_clk),.rst_n(cam_branch_rst_n),
            .s_yuyv4(yuyv4),.s_valid(tile_valid),
            .s_sof(tile_sof),.s_eol(gray_eol),
            .s_take_frame(tile_take),.s_fault(),
            .s_selected_frames(),.s_completed_frames(),
            .m_tdata(vid_data[lane]),.m_tvalid(vid_valid[lane]),
            .m_tready(vid_ready[lane]),.m_tuser(vid_sof[lane]),
            .m_tlast(vid_eol[lane]),.m_fault(bridge_fault[lane])
        );
        wire [4:0] ax_awaddr;
        wire ax_awvalid,ax_awready,ax_wvalid,ax_wready;
        wire [31:0] ax_wdata;
        wire [3:0] ax_wstrb;
        wire ax_bvalid,ax_bready;
        jpeg_axil_config u_config (
            .clk(enc_clk),.rst_n(enc_rst_n),
            .quality(quality_enc),.frame_busy(busy[lane]),
            .ready(cfg_ready[lane]),
            .awaddr(ax_awaddr),.awvalid(ax_awvalid),.awready(ax_awready),
            .wdata(ax_wdata),.wstrb(ax_wstrb),
            .wvalid(ax_wvalid),.wready(ax_wready),
            .bvalid(ax_bvalid),.bready(ax_bready)
        );
        wire jpg_valid,jpg_last;
        wire [7:0] jpg_byte;
        mjpegzero_enc_top #(
            .LITE_MODE(0),.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(TILE_HEIGHT),
            .RGB_INPUT(0),.MONO(1)
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
            .s_axi_awaddr(ax_awaddr),.s_axi_awvalid(ax_awvalid),
            .s_axi_awready(ax_awready),.s_axi_wdata(ax_wdata),
            .s_axi_wstrb(ax_wstrb),.s_axi_wvalid(ax_wvalid),
            .s_axi_wready(ax_wready),.s_axi_bresp(),
            .s_axi_bvalid(ax_bvalid),.s_axi_bready(ax_bready),
            .s_axi_araddr(5'd0),.s_axi_arvalid(1'b0),
            .s_axi_arready(),.s_axi_rdata(),.s_axi_rresp(),
            .s_axi_rvalid(),.s_axi_rready(1'b0)
        );
        jpeg_byte_packer u_packer (
            .enc_clk(enc_clk),.user_clk(user_clk),.rst_n(enc_rst_n),
            .s_byte(jpg_byte),.s_valid(jpg_valid),.s_last(jpg_last),
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

    (* ASYNC_REG="TRUE" *) reg [1:0] fault_user,cfg_user,busy_user;
    (* ASYNC_REG="TRUE" *) reg [31:0] bytes_a_meta,bytes_b_meta,
                                  bytes_a_sync,bytes_b_sync;
    reg fault_seen;
    always @(posedge user_clk or negedge branch_rst_n) begin
        if(!branch_rst_n) begin
            fault_user<=0;cfg_user<=0;busy_user<=0;
            bytes_a_meta<=0;bytes_b_meta<=0;
            bytes_a_sync<=0;bytes_b_sync<=0;
            sent_a<=0;sent_b<=0;fault_count<=0;fault_seen<=0;
        end else begin
            fault_user<={fault_user[0],fault_enc};
            cfg_user<={cfg_user[0],configured_enc};
            busy_user<={busy_user[0],(|busy)};
            bytes_a_meta<=last_bytes[0];bytes_b_meta<=last_bytes[1];
            bytes_a_sync<=bytes_a_meta;bytes_b_sync<=bytes_b_meta;
            if(packet_sent[0]) sent_a<=sent_a+1'b1;
            if(packet_sent[1]) sent_b<=sent_b+1'b1;
            fault_seen<=fault_user[1];
            if(fault_user[1] && !fault_seen)
                fault_count<=fault_count+1'b1;
        end
    end
    assign status_configured=cfg_user[1];
    assign status_busy=busy_user[1];
    assign status_fault=fault_user[1];
    assign bytes_a=bytes_a_sync;
    assign bytes_b=bytes_b_sync;
endmodule
