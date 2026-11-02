
/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2024/10/23
*Module Name:
*File Name:
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.0
*Signal description
*1) I_ input
*2) O_ output
*3) IO_ input output
*4) S_ system internal signal
*5) _n activ low
*6) _dg debug signal 
*7) _r delay or register
*8) _s state mechine
*********************************************************************/
/*********ui_isp_top ********************************************
--米联客ISP图像算法包含有黑电平矫正(BLC),去噪(Denoising),去马赛克(Demosaicing),白平衡(wab),
伽马矫正(Gamma),对比度调节(Contrast),亮度调节(Brightness),饱和度调节(Saturation)锐化(Sharpening)
--版本号1.0  
*****************************************************************/
module ui_isp_top #(parameter ENABLE_DSI_BRANCH = 0) (
    input 			I_clk,
    input 			I_rst_n			,
    input 			I_tlast			,
    input 			I_tuser			,
    input [39:0] 	I_tdata			,
    input 			I_tvalid		,
    input [9:0] 	I_tdest			,
    input 			O_tready		,
    output [127:0] 	O_tdata			,
    output 			O_tlast			,
    output 			O_tuser			,
    output 			O_tvalid		,
    output 			I_tready,
    input           I_first_row_odd,
    // bit0 manual phase, bit1 phase flip, bit2 swap R/B, bit3 filter bypass.
    input [3:0]     I_dsi_control,
    output [127:0]  O_dsi_tdata,
    output          O_dsi_tlast, O_dsi_tuser, O_dsi_tvalid,
    output [1:0]    O_dsi_phase
);

    wire         	BLC_O_tlast;  
    wire         	BLC_O_tuser;  
    wire [39:0] 	BLC_O_tdata;  
    wire         	BLC_O_tvalid;  
    wire [9:0] 		BLC_O_tdest;  
    wire         	BLC_O_tready;  
    
    wire [9:0] 		black_level_offset_r0;
    wire [9:0] 		black_level_offset_r1;
    wire [9:0] 		black_level_offset_r2;
    wire [9:0] 		black_level_offset_r3;
    
    
    wire         	m_aixs_tvalid;  
    wire [127:0] 	m_aixs_tdata;  
    wire         	m_aixs_tuser;  
    wire         	m_aixs_tlast;  
    wire         	m_aixs_tready;  
    wire [ 95:0] 	m_aixs_tdata_96;
    
    wire         	awb_O_tlast;  
    wire         	awb_O_tuser;  
    wire [ 95:0] 	awb_O_tdata;  
    wire         	awb_O_tvalid; 
    wire         	awb_O_tready; 
	  
    wire         	gamma_O_tlast;  
    wire         	gamma_O_tuser;  
    wire [ 95:0] 	gamma_O_tdata;  
    wire         	gamma_O_tvalid;  
    wire         	gamma_O_tready;  
	  
    wire         	cut_O_tlast;
    wire         	cut_O_tuser;
    wire [ 95:0] 	cut_O_tdata;	
    wire         	cut_O_tvalid;
    wire         	cut_O_tready;
	  
    wire         	contrast_O_tlast;
    wire         	contrast_O_tuser;
    wire [ 95:0] 	contrast_O_tdata;
    wire         	contrast_O_tvalid;
    wire         	contrast_O_tready;
	  
    wire         	Brightness_O_tlast;
    wire         	Brightness_O_tuser;
    wire [ 95:0] 	Brightness_O_tdata;
    wire         	Brightness_O_tvalid;
    wire         	Brightness_O_tready;
	  
    wire [127:0] Color_O_tdata_128;
    wire [127:0] dsi_raw_rgb;
    wire dsi_raw_last, dsi_raw_user, dsi_raw_valid;
    reg dsi_phase_flip, dsi_swap_rb, dsi_filter_bypass;
    // Native IMX415 GBRG, crop advances by multiples of four columns:
    // retained sensor row 0 -> GBRG (flip); retained row 1 -> RGGB.
    // Metadata is captured one clock after I_tuser, before window output.
    reg dsi_sof_d;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            dsi_sof_d <= 0; dsi_phase_flip <= 0; dsi_swap_rb <= 0;
            dsi_filter_bypass <= 0;
        end else begin
            dsi_sof_d <= I_tuser && I_tvalid;
            if (dsi_sof_d) begin
                dsi_phase_flip <= I_dsi_control[0] ? I_dsi_control[1] : !I_first_row_odd;
                dsi_swap_rb <= I_dsi_control[2];
                dsi_filter_bypass <= I_dsi_control[3];
            end
        end
    end
    assign O_dsi_phase = {dsi_swap_rb, dsi_phase_flip};

	//assign m_aixs_tready = O_tready;
	//assign O_tdata  = m_aixs_tdata;
	//assign O_tlast  = m_aixs_tlast    ;
	//assign O_tuser  = m_aixs_tuser    ;
	//assign O_tvalid = m_aixs_tvalid   ;
 
	// The DSI/DDR path receives RGB; only the PCIe tap computes grayscale.
	assign Brightness_O_tready = O_tready;
	assign O_tdata  = Color_O_tdata_128;
	assign O_tlast  = Brightness_O_tlast;
	assign O_tuser  = Brightness_O_tuser;
	assign O_tvalid = Brightness_O_tvalid;


ui_BLC #(
    .Black_level_offset_r0	(50),
    .Black_level_offset_r1	(50),
    .Black_level_offset_r2	(50),
    .Black_level_offset_r3	(50)
) X_ui_BLC (
    .I_clk   		(I_clk				),
    .I_rst_n 		(I_rst_n 			),
    .I_tlast 		(I_tlast 			),
    .I_tuser 		(I_tuser 			),
    .I_tdata 		(I_tdata 			),
    .I_tvalid		(I_tvalid			),
    .I_tdest 		(I_tdest 			),
    .I_tready		(					),
	
    .O_tlast 		(BLC_O_tlast		),
    .O_tuser 		(BLC_O_tuser		),
    .O_tdata 		(BLC_O_tdata		),
    .O_tvalid		(BLC_O_tvalid		),
    .O_tdest 		(BLC_O_tdest		),
    .O_tready		(BLC_O_tready		)
);

ui_top_demosaic #(
    .IMG_HEIGHT          (1080			),  // 图像高度
    .IMG_WIDTH           (1920			),   // 图像宽度
    .data_complete_delay (50  			),
    .BAYER_MODE          ("RGGB"		),
    .ENABLE_DSI_BRANCH   (ENABLE_DSI_BRANCH)
)
X_ui_top_demosaic
(
    .I_clk   		(I_clk				),  // 时钟信号
    .I_rst_n 		(I_rst_n			),  // 复位信号，低有效
    .I_axi4s_tdata 	(BLC_O_tdata		),  // AXI4-Stream视频数据
    .I_axi4s_tdest 	(BLC_O_tdest		),
    .I_axi4s_tlast 	(BLC_O_tlast		),  // 行结束信号
    .I_axi4s_tvalid	(BLC_O_tvalid		),  // 数据有效信号
    .I_axi4s_tuser 	(BLC_O_tuser		),  // 帧开始信号
    .I_axi4s_tready	(BLC_O_tready		),  // 从模块准备好接受数据
    .O_tlast  		(m_aixs_tlast		),  // 输出行结束信号
    .O_tuser  		(m_aixs_tuser		),  // 输出帧开始信号
    .O_tdata  		(m_aixs_tdata		),  // 输出数据
    .O_tvalid 		(m_aixs_tvalid		),  // 输出数据有效信号
	.O_tready   	(m_aixs_tready		),
    .I_dsi_phase_flip(dsi_phase_flip),
    .O_dsi_tdata(dsi_raw_rgb), .O_dsi_tvalid(dsi_raw_valid),
    .O_dsi_tuser(dsi_raw_user), .O_dsi_tlast(dsi_raw_last)
);

ui_data128_96 X_ui_data128_96(
    .I_tdata		(m_aixs_tdata		),
    .O_tdata		(m_aixs_tdata_96	)
);

ui_awb #(
    .IMG_HEIGHT		(1080				),
    .IMG_WIDTH		(1920				),
    .DYNAMIC_ENABLE	(0					)
) X_ui_awb (	
    .I_clk   		(I_clk				),
    .I_rst_n 		(I_rst_n			),
    .I_tlast 		(m_aixs_tlast		),
    .I_tuser 		(m_aixs_tuser		),
    .I_tdata 		(m_aixs_tdata_96	),
    .I_tvalid		(m_aixs_tvalid		),
    .I_tready		(m_aixs_tready		),
    .O_tlast 		(awb_O_tlast 		),
    .O_tuser 		(awb_O_tuser 		),
    .O_tdata 		(awb_O_tdata 		),
    .O_tvalid		(awb_O_tvalid		),
    .O_tready		(awb_O_tready		)
);

ui_image_cut #(
    .IMG_WIDTH		(1920				),
    .IMG_HEIGHT		(1080				),
    .DATA_WIDTH		(96					),
    .SKIP_ROWS_top	(0					),
    .SKIP_ROWS_bottom(0					),
    .SKIP_COLS_left	(1					),
    .SKIP_COLS_right(0					)
) X_ui_image_cut 	
(	
    .I_clk   		(I_clk				),
    .I_rst_n 		(I_rst_n			),
    .I_tlast 		(awb_O_tlast		),
    .I_tuser 		(awb_O_tuser		),
    .I_tdata 		(awb_O_tdata		),
    .I_tvalid		(awb_O_tvalid		),
    .I_tready		(awb_O_tready		),
    .O_tlast 		(cut_O_tlast		),
    .O_tuser 		(cut_O_tuser		),
    .O_tdata 		(cut_O_tdata		),
    .O_tvalid		(cut_O_tvalid		),
    .O_tready		(cut_O_tready		)
);

ui_gamma #(
    .GAMMA_10x		(22					)
) X_ui_gamma 	
(	
    .I_clk   		(I_clk				),
    .I_rst_n 		(I_rst_n			),
    .I_tlast 		(cut_O_tlast		),
    .I_tuser 		(cut_O_tuser		),
    .I_tdata 		(cut_O_tdata		),
    .I_tvalid		(cut_O_tvalid		),
    .I_tready		(cut_O_tready		),
    .O_tlast 		(gamma_O_tlast		),
    .O_tuser 		(gamma_O_tuser		),
    .O_tdata 		(gamma_O_tdata		),
    .O_tvalid		(gamma_O_tvalid		),
    .O_tready		(gamma_O_tready		)
);

ui_Contrast_adj #(
    .contrast_level	(140				) 
) X_ui_Contrast_adj (
    .I_clk   		(I_clk				),
    .I_rst_n 		(I_rst_n			),
    .I_tlast 		(gamma_O_tlast		),
    .I_tuser 		(gamma_O_tuser		),
    .I_tdata 		(gamma_O_tdata		),
    .I_tvalid		(gamma_O_tvalid		),
    .I_tready		(gamma_O_tready		),
    .O_tlast 		(contrast_O_tlast	),
    .O_tuser 		(contrast_O_tuser	),
    .O_tdata 		(contrast_O_tdata	),
    .O_tvalid		(contrast_O_tvalid	),
    .O_tready		(contrast_O_tready	)
);

ui_Brightness_adj #(
    .BRIGHTNESS_ADD  (5					),
    .BRIGHTNESS_MINUS(0					)
) X_ui_Brightness_adjustment 
(
    .I_clk   		(I_clk				),
    .I_rst_n 		(I_rst_n			),
    .I_tlast 		(contrast_O_tlast	),
    .I_tuser 		(contrast_O_tuser	),
    .I_tdata 		(contrast_O_tdata	),
    .I_tvalid		(contrast_O_tvalid	),
    .I_tready		(contrast_O_tready	),
    .O_tlast 		(Brightness_O_tlast	),
    .O_tuser 		(Brightness_O_tuser	),
    .O_tdata 		(Brightness_O_tdata	),
    .O_tvalid		(Brightness_O_tvalid),
    .O_tready		(Brightness_O_tready)
);

ui_data96_128 X_ui_data96_128 (
    .I_tdata		(Brightness_O_tdata),
    .O_tdata		(Color_O_tdata_128)
);

generate if (ENABLE_DSI_BRANCH) begin : dsi_post
    wire [127:0] filtered_rgb;
    wire f_last, f_user, f_valid;
    wire [95:0] rgb96, gamma_rgb, contrast_rgb, bright_rgb;
    wire g_last, g_user, g_valid, c_last, c_user, c_valid;
    wire [127:0] rgb128;
    ui_dsi_box2x2 u_antialias (
        .clk(I_clk), .rst_n(I_rst_n), .bypass(dsi_filter_bypass),
        .s_data(dsi_raw_rgb), .s_valid(dsi_raw_valid),
        .s_user(dsi_raw_user), .s_last(dsi_raw_last),
        .m_data(filtered_rgb), .m_valid(f_valid), .m_user(f_user), .m_last(f_last));
    ui_data128_96 u_unpack(.I_tdata(filtered_rgb), .O_tdata(rgb96));
    // Fixed unity AWB needs no duplicate delay RAM. Retain the existing
    // gamma/contrast/brightness transfer functions on the DSI branch.
    ui_dsi_gamma22 u_gamma (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tdata(rgb96),
        .I_tlast(f_last), .I_tuser(f_user), .I_tvalid(f_valid),
        .I_tready(), .O_tdata(gamma_rgb), .O_tlast(g_last),
        .O_tuser(g_user), .O_tvalid(g_valid), .O_tready(1'b1));
    ui_Contrast_adj #(.contrast_level(140)) u_contrast (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tdata(gamma_rgb),
        .I_tlast(g_last), .I_tuser(g_user), .I_tvalid(g_valid), .I_tready(),
        .O_tdata(contrast_rgb), .O_tlast(c_last), .O_tuser(c_user),
        .O_tvalid(c_valid), .O_tready(1'b1));
    ui_Brightness_adj #(.BRIGHTNESS_ADD(5), .BRIGHTNESS_MINUS(0)) u_bright (
        .I_clk(I_clk), .I_rst_n(I_rst_n), .I_tdata(contrast_rgb),
        .I_tlast(c_last), .I_tuser(c_user), .I_tvalid(c_valid), .I_tready(),
        .O_tdata(bright_rgb), .O_tlast(O_dsi_tlast), .O_tuser(O_dsi_tuser),
        .O_tvalid(O_dsi_tvalid), .O_tready(1'b1));
    ui_data96_128 u_pack(.I_tdata(bright_rgb), .O_tdata(rgb128));
    genvar dp;
    for (dp=0; dp<4; dp=dp+1) begin : pixels
        assign O_dsi_tdata[32*dp +: 32] = dsi_swap_rb ?
            {8'd0, rgb128[32*dp +: 8], rgb128[32*dp+8 +: 8], rgb128[32*dp+16 +: 8]} :
            rgb128[32*dp +: 32];
    end
end else begin : dsi_disabled
    assign O_dsi_tdata = O_tdata;
    assign O_dsi_tlast = O_tlast;
    assign O_dsi_tuser = O_tuser;
    assign O_dsi_tvalid = O_tvalid;
end endgenerate
	
endmodule

// Exact eight-bit transfer of ui_gamma(GAMMA_10x=22), including its
// quantization. Bit-plane constant multiplexers use logic instead of twelve
// mostly empty ERAMs. Four pipeline stages preserve data/flag latency.
module ui_dsi_gamma22 (
    input wire I_clk, I_rst_n,
    input wire [95:0] I_tdata,
    input wire I_tlast, I_tuser, I_tvalid,
    output wire I_tready,
    output wire [95:0] O_tdata,
    output wire O_tlast, O_tuser, O_tvalid,
    input wire O_tready
);
    localparam [255:0] B0 = 256'h98ccce666666666cccd99326c9b26db6db6d25a5ad6ad56aaaad5a5b33878d48;
    localparam [255:0] B1 = 256'he0f0f07878787870f0e1e3c70e3c71c71c71c639ce73198cccc9936da52aa4cd;
    localparam [255:0] B2 = 256'hff00ff807f807f80ff01fc07f03f81f81f81f83e0f83e1f0f0f1e38e39ccc965;
    localparam [255:0] B3 = 256'hffff00007fff8000fffe0007ffc001ffe001ffc00ffc01ff00fe03f03e0f0e77;
    localparam [255:0] B4 = 256'hffffffff80000000fffffff8000001fffffe00000ffffe0000fffc003ff00f86;
    localparam [255:0] B5 = 256'hffffffffffffffff00000000000001fffffffffff000000000ffffffc0000ff8;
    localparam [255:0] B6 = 256'hfffffffffffffffffffffffffffffe00000000000000000000fffffffffff000;
    localparam [255:0] B7 = 256'hffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000;
    // SWUG106 section 4.3.15: TD accepts "none" (not "distributed")
    // to prevent automatic ERAM inference. Keep the attribute on the array.
    (* rom_style = "none" *) reg [7:0] transfer [0:255];
    integer init_index;
    initial for (init_index=0;init_index<256;init_index=init_index+1)
        transfer[init_index]={B7[init_index],B6[init_index],B5[init_index],B4[init_index],
                              B3[init_index],B2[init_index],B1[init_index],B0[init_index]};
    reg [95:0] data0, data1, data2, data3;
    reg [3:0] valid_pipe, user_pipe, last_pipe;
    integer channel;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            data0<=0; data1<=0; data2<=0; data3<=0;
            valid_pipe<=0; user_pipe<=0; last_pipe<=0;
        end else begin
            for (channel=0; channel<12; channel=channel+1)
                data0[8*channel +: 8] <= transfer[I_tdata[8*channel +: 8]];
            if (valid_pipe[0]) data1<=data0;
            if (valid_pipe[1]) data2<=data1;
            if (valid_pipe[2]) data3<=data2;
            valid_pipe<={valid_pipe[2:0],I_tvalid};
            user_pipe<={user_pipe[2:0],I_tuser};
            last_pipe<={last_pipe[2:0],I_tlast};
        end
    end
    assign I_tready=O_tready;
    assign O_tdata=data3;
    assign O_tvalid=valid_pipe[3];
    assign O_tuser=user_pipe[3];
    assign O_tlast=last_pipe[3];
endmodule

// A trailing 2x2 RGB box before 8/15 decimation. Full throughput is four
// pixels/clock; one 512x96 line store (46,080 useful bits) is DSI-only.
// Read-before-write synchronous RAM, no bulk reset, no added backpressure.
module ui_dsi_box2x2 (
    input wire clk, rst_n, bypass,
    input wire [127:0] s_data,
    input wire s_valid, s_user, s_last,
    output reg [127:0] m_data,
    output reg m_valid, m_user, m_last
);
    reg [95:0] line_mem [0:511]; /* fehdl force_ram=1, ram_style="bram" */
    reg [8:0] column;
    reg first_row;
    wire [8:0] address = s_user ? 9'd0 : column;
    wire [95:0] packed_rgb = {s_data[119:96],s_data[87:64],s_data[55:32],s_data[23:0]};
    reg [95:0] previous_row, current_row;
    reg v1, u1, l1, first_row1, first_column1;
    // Separate memory process lets TD infer a block RAM with read-before-write.
    always @(posedge clk) if (s_valid) begin
        previous_row <= line_mem[address];
        line_mem[address] <= packed_rgb;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            column<=0; first_row<=1;
            current_row<=0; v1<=0; u1<=0; l1<=0;
            first_row1<=1; first_column1<=1;
        end else begin
            v1<=s_valid; u1<=s_user && s_valid; l1<=s_last && s_valid;
            if (s_user) begin column<=0; first_row<=1; end
            if (s_valid) begin
                current_row<=packed_rgb;
                first_row1<=s_user || first_row;
                first_column1<=address==0;
                if (s_last) begin column<=0; first_row<=0; end
                else column<=address+1'b1;
            end
        end
    end
    reg [8:0] vertical [0:11];
    reg [8:0] previous_column [0:2];
    reg [9:0] total;
    reg [127:0] filtered;
    integer p, c;
    always @* begin
        filtered=0;
        total=0;
        for(p=0;p<4;p=p+1)
            for(c=0;c<3;c=c+1)
                vertical[3*p+c] = {1'b0,current_row[24*p+8*c +: 8]} +
                    (first_row1 ? {1'b0,current_row[24*p+8*c +: 8]} :
                                  {1'b0,previous_row[24*p+8*c +: 8]});
        for(p=0;p<4;p=p+1)
            for(c=0;c<3;c=c+1) begin
                if(p==0)
                    total={1'b0,vertical[c]} +
                        (first_column1 ? {1'b0,vertical[c]} : {1'b0,previous_column[c]});
                else total={1'b0,vertical[3*p+c]} + {1'b0,vertical[3*(p-1)+c]};
                filtered[32*p+8*c +: 8] = total[9:2];
            end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_data<=0; m_valid<=0; m_user<=0; m_last<=0;
            previous_column[0]<=0; previous_column[1]<=0; previous_column[2]<=0;
        end else begin
            m_valid<=v1; m_user<=u1; m_last<=l1;
            if (v1) begin
                m_data<=bypass ? {8'd0,current_row[95:72],8'd0,current_row[71:48],
                                 8'd0,current_row[47:24],8'd0,current_row[23:0]} : filtered;
                previous_column[0]<=vertical[9];
                previous_column[1]<=vertical[10];
                previous_column[2]<=vertical[11];
            end
        end
    end
endmodule
