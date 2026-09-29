`timescale 1ns/1ns
/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2025/12/10
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
*4) S_system internal signal
*5) n_ activ low
*6) dg_ debug signal
*7) r_ delay or register
*8) s_ state mechine
*********************************************************************/
/*********system_top***********
--本方案采用IMX415摄像头,将图像数据经米联客ISP图像算法处理后,
缓存至DDR中,最终通过HDMI输出1080P_60HZ的图像
*********************************************************************/

`define DRAM_BYTE_NUM 2   	   // 1 = x8, 2 = x16,4 = x32,8=x64
`define DRAM_SIZE    "2G"     // AP106,AP102=2G ,AP104=4G    1G , 2G , 4G = 256x16bit, 8G    ,ONE DDR particle capacity

//`define XLNX_NATIVE
//`define ALC_NATIVE  
`define MC_AXI  
 
//`define AXI_ATG  
//`define ATG   
//`define DFI
  
module system_top#(
parameter DRAM_TYPE       = "DDR3"  ,            //"DDR4" "DDR3"
parameter ECC             = "OFF",
parameter APP_ADDR_WIDTH  = (`DRAM_SIZE=="1G")?26:(`DRAM_SIZE=="2G")?27:(`DRAM_SIZE == "4G")?28:(`DRAM_SIZE == "8G")?29:28, //512Mx16bit=29 ,256Mx16bit=28 ,128Mx16bit=27,64Mx16bit = 26,
parameter AXI_ID_WIDTH    =  4,                                                                                   
parameter APP_DATA_WIDTH  = (ECC == "ON")? (`DRAM_BYTE_NUM-1)*8*8 : `DRAM_BYTE_NUM*8*8,
parameter APP_MASK_WIDTH  = (ECC == "ON")? (`DRAM_BYTE_NUM-1)*8   : `DRAM_BYTE_NUM*8,
parameter AXI_ADDR_WIDTH  = APP_ADDR_WIDTH+3,
parameter AXI_DATA_WIDTH  = APP_DATA_WIDTH,
parameter DQ_WIDTH        = `DRAM_BYTE_NUM * 8,
parameter DQS_WIDTH       = `DRAM_BYTE_NUM,
parameter DM_WIDTH        = `DRAM_BYTE_NUM,
parameter ADDR_WIDTH      = (DRAM_TYPE=="DDR4")?17:(`DRAM_SIZE=="1G")?13:(`DRAM_SIZE=="2G")?14:(`DRAM_SIZE == "4G")?15:(`DRAM_SIZE == "8G")?16:15, // 512Mx16bit=16 ,256Mx16bit=15,128Mx16bit=14,64Mx16bit=13
parameter ROW_WIDTH       = (`DRAM_SIZE=="1G")?13:(`DRAM_SIZE=="2G")?14:(`DRAM_SIZE == "4G")?15:(`DRAM_SIZE == "8G")?16:15,                        // 512Mx16bit=16 ,256Mx16bit=15,128Mx16bit=14,64Mx16bit=13
parameter COL_WIDTH       = 10,                  
parameter BA_WIDTH        = 3,                   
parameter BG_WIDTH        = 1,                   
parameter ODT_WIDTH       = 1,                   
parameter CKE_WIDTH       = 1,                   
parameter CS_WIDTH        = 1                    
)
(
    input                           I_sysclk_25m,	//系统时钟
    input                           I_ddr_clk   ,	//DDR参考时钟
	
	//DDR
    output    [ADDR_WIDTH-1:0]      ddr_addr    , 
    output    [  BA_WIDTH-1:0]      ddr_ba      ,
    output    [ CKE_WIDTH-1:0]      ddr_cke     ,
    output    [ ODT_WIDTH-1:0]      ddr_odt     ,
    output    [  CS_WIDTH-1:0]      ddr_cs_n    ,
    output                          ddr_ras_n   ,
    output                          ddr_cas_n   ,
    output                          ddr_we_n    ,
    output                          ddr_ck_p    ,
    output                          ddr_ck_n    ,
    output                          ddr_reset_n ,
    inout     [  DM_WIDTH-1:0]      ddr_dm  	,
    inout     [  DQ_WIDTH-1:0]      ddr_dq      ,
    inout     [ DQS_WIDTH-1:0]      ddr_dqs_n   ,
    inout     [ DQS_WIDTH-1:0]      ddr_dqs_p   ,

	//摄像头配置信号
	output wire 					S_clk_25m	,	//摄像头工作时钟，端口名保留，实际为24MHz
	output wire 					O_clk_rst	,	//摄像头复位信号,默认上拉
    output wire 					O_cam_scl	,   //I2C总线，SCL时钟
    inout  wire 					IO_cam_sda	,   //I2C总线，SDA数据
	
	//MIPI_RX
	input  wire		    			I_clk_hs_p  ,	
	input  wire	[3:0]				I_data_hs_p , 
	input  wire	[3:0]				I_data_lp_p ,
	input  wire	[3:0]				I_data_lp_n ,
	
	//MIPI_TX
	output 		 					O_clk_hs_p	,
	output 		 					O_clk_lp_p	,
	output 		 					O_clk_lp_n	,
	output 		 [3:0] 				O_data_hs_p	,
	output 		 [3:0] 				O_data_lp_p	,
	output 		 [3:0] 				O_data_lp_n


);                                      

//-------- User Clock --------//
wire                       		S_dfi_clk             ;
wire                       		S_ddr_init_cal_done   ;
wire [7:0]                          S_ddr_init_cal_err    ;

// AXI Write Addr
wire [AXI_ADDR_WIDTH-1:0]      	S_axi_awaddr  	;
wire                           	S_axi_awvalid 	;
wire                           	S_axi_awready 	;
wire   [AXI_ID_WIDTH-1:0]      	S_axi_awid    	;
wire                [7:0]      	S_axi_awlen   	; 
wire                [2:0]      	S_axi_awsize  	; 
wire                [1:0]      	S_axi_awburst 	; 
wire                [0:0]      	S_axi_awlock  	; 
wire                [3:0]      	S_axi_awcache 	; 
wire                [2:0]      	S_axi_awprot  	; 
wire                [3:0]      	S_axi_awqos   	;
// AXI Write Data              		
wire [APP_DATA_WIDTH-1:0]      	S_axi_wdata   	;
wire [APP_MASK_WIDTH-1:0]      	S_axi_wstrb   	;
wire                           	S_axi_wvalid  	;
wire                           	S_axi_wlast   	;
wire                           	S_axi_wready  	;
// Write Response Port         		
wire   [AXI_ID_WIDTH-1:0]      	S_axi_bid     	;    
wire                [1:0]      	S_axi_bresp   	;    
wire                           	S_axi_bvalid  	;    
wire                           	S_axi_bready  	;    
								
// AXI Read Addr               	
wire [AXI_ADDR_WIDTH-1:0]      	S_axi_araddr  	;
wire                           	S_axi_arvalid 	;
wire                           	S_axi_arready 	;
wire [  AXI_ID_WIDTH-1:0]      	S_axi_arid    	;
wire                [7:0]      	S_axi_arlen   	;
wire                [2:0]      	S_axi_arsize  	;
wire                [1:0]      	S_axi_arburst 	;
wire                [0:0]      	S_axi_arlock  	;
wire                [3:0]      	S_axi_arcache 	;
wire                [2:0]      	S_axi_arprot  	;
wire                [3:0]      	S_axi_arqos   	;
// AXI Read Data               		
wire [APP_DATA_WIDTH-1:0]      	S_axi_rdata   	;
wire                           	S_axi_rlast   	;
wire                           	S_axi_rvalid  	;
wire                           	S_axi_rready  	;
wire   [AXI_ID_WIDTH-1:0]      	S_axi_rid     	;
wire                [1:0]      	S_axi_rresp   	;

//MLK_FDMA
wire [AXI_ADDR_WIDTH-1:  0]    	S_fdma_waddr	;   //FDMA写通道地址
wire                           	S_fdma_wareq	;   //FDMA写通道请求
wire [15: 0]                   	S_fdma_wsize	;   //FDMA写通道一次FDMA的传输大小                                       
wire                           	S_fdma_wbusy	;   //FDMA处于BUSY状态，AXI总线正在写操作 		
wire [AXI_DATA_WIDTH-1 : 0]    	S_fdma_wdata	;   //FDMA写数据
wire                           	S_fdma_wvalid	;   //FDMA 写有效
wire                           	S_fdma_wready	;   //FDMA写准备好，用户可以写数据
wire                           	S_fdma_wirq	;   //一整帧已经完成DDR写入
								
wire [AXI_ADDR_WIDTH-1:  0]    	S_fdma_raddr	;   //FDMA读通道地址
wire                           	S_fdma_rareq	;   //FDMA读通道请求
wire [15: 0]                   	S_fdma_rsize	;   //FDMA读通道一次FDMA的传输大小                                       
wire                           	S_fdma_rbusy	;   //FDMA处于BUSY状态，AXI总线正在读操作 			
wire [AXI_DATA_WIDTH-1 : 0]    	S_fdma_rdata	;   //FDMA读数据
wire                           	S_fdma_rvalid	;   //FDMA 读有效
wire                           	S_fdma_rready	;   //FDMA读准备好，用户可以读数据	
wire                           	S_test_error	;   //测试是否有错误，1有错误，0没错误

//wire   							S_clk_25m		;
wire        					S_clk_70m		;
wire        					S_pll_lock		;

wire [7:0]						S_ae			;
wire 							S_cam_cfg_done	;
wire 							S_ae_cfg_done	;
wire 							S_ae_req		;
wire                            S_cam_iic_error;
wire                            S_cam_cfg_rst_n;
wire                            S_cam_rx_rst_n_70m;
wire                            S_cam_hs_rst_n;

wire          					S_hs_rx_clk		;  
wire          					S_hs_rx_valid	;  
wire [31 : 0] 					S_hs_rx_data	; 
wire [3:0]                      S_lane_error;

wire        					S_csi_frame_start;       
wire        					S_csi_frame_end	;         
wire        					S_csi_valid		;             
wire[31:0]  					S_csi_data		;  
	
wire          					S_raw10_frame_start;
wire          					S_raw10_frame_end;
wire          					S_raw10_valid	;
wire [39 : 0] 					S_raw10_data	;

wire [39:0]						S_axis_tdata	;
wire 							S_axis_tvalid	;
wire 							S_axis_tlast	; 
wire 							S_axis_tuser	; 

wire							S_ISP_O_tready 	;
wire [127:0]					S_ISP_O_tdata  	;
wire 							S_ISP_O_tlast  	;
wire 							S_ISP_O_tuser  	;
wire 							S_ISP_O_tvalid 	;

wire [7:0] 						S_wbuf_sync		;
wire [7:0] 						S_rbuf_sync		;
					
wire 							S_ud_wclk		;
wire 							S_ud_wtuser		; 
wire 							S_ud_wtvalid	; 
wire 							S_ud_wtlast		; 
wire 							S_ud_wtready	;  
wire [127:0] 					S_ud_wtdata		;
wire                            S_ud_woverflow  ;
wire                            S_ud_wsync_error;
wire                            S_capture_error_pulse;
wire                            S_capture_fifo_error;
wire                            S_capture_frame_ok;

wire [23:0] 					S_ud_rtdata		;  
wire                            S_ud_rtvalid      ;
					
wire        					S_R_vrst		;
wire [23:0] 					S_video_in_data	; 
					
assign S_ud_wclk 				= S_hs_rx_clk	;
assign S_ud_wtuser 				= S_ISP_O_tuser	;
assign S_ud_wtvalid 			= S_ISP_O_tvalid;
assign S_ud_wtlast 				= S_ISP_O_tlast	;
assign S_ud_wtdata 				= S_ISP_O_tdata	;
		
assign S_video_in_data 			= S_ud_rtdata;


wire        	S_clk;
wire        	S_clk_x2;
wire        	S_clk_x4;
wire        	S_clk_x4_90d;
wire        	S_lp_clk;
wire        	S_pll1_lock;

wire        	S_rst;  //synthesis keep
wire        	S_config_start;
wire        	S_config_done;
	
wire        	S_24b_vsync;  //synthesis keep
wire        	S_24b_hsync;  //synthesis keep
wire        	S_24b_de;  //synthesis keep
wire [23:0] 	S_24b_data;  //synthesis keep

wire        	S_osd_vsync;
wire        	S_osd_hsync;
wire        	S_osd_de;
wire [23:0] 	S_osd_data;
	
wire        	S_32b_vsync;  //synthesis keep
wire        	S_32b_hsync;  //synthesis keep
wire        	S_32b_de;  //synthesis keep
wire [31:0] 	S_32b_data;  //synthesis keep
	
wire        	S_hs_en;  //synthesis keep           
wire        	S_hs_last;  //synthesis keep	       
wire [31:0] 	S_hs_data;  //synthesis keep    
	
wire        	S_lp_tx_valid;
wire        	S_lp_tx_last;
wire [ 7:0] 	S_lp_tx_data;
wire        	S_lp_tx_ready;



//PLL时钟管理IP 
  ui_pll X_ui_pll (
    .refclk  	(I_sysclk_25m	),
    .reset		(1'b0			),

    .lock		(S_pll_lock		),

    .clk0_out	(S_clk_70m		),
    .clk1_out	(S_clk_25m		),
    .clk2_out	(S_clk			),
    .clk3_out	(S_clk_x2		),
    .clk4_out	(S_clk_x4		),
    .clk5_out	(S_clk_x4_90d	),
    .clk6_out	(S_lp_clk		)
  );

// A JTAG reconfiguration does not power-cycle the camera.  Force a real
// reset every time the FPGA/PLL restarts, then give IMX415 time to stabilize
// before the I2C table is sent.  Any I2C NACK restarts the whole sequence.
localparam [19:0] CAM_RESET_LOW_CYCLES = 20'd250000; // 10 ms at 25 MHz
localparam [19:0] CAM_CONFIG_CYCLES    = 20'd750000; // 30 ms total
reg [19:0] S_cam_startup_cnt;

always @(posedge S_clk_25m or negedge S_pll_lock) begin
    if(!S_pll_lock)
        S_cam_startup_cnt <= 20'd0;
    else if(S_cam_iic_error)
        S_cam_startup_cnt <= 20'd0;
    else if(S_cam_startup_cnt < CAM_CONFIG_CYCLES)
        S_cam_startup_cnt <= S_cam_startup_cnt + 1'b1;
end

assign O_clk_rst       = S_pll_lock &&
                         (S_cam_startup_cnt >= CAM_RESET_LOW_CYCLES);
assign S_cam_cfg_rst_n = S_pll_lock &&
                         (S_cam_startup_cnt >= CAM_CONFIG_CYCLES);

// Release receive logic synchronously in each of its clock domains.  This
// avoids a partial first frame when PLL lock or camera configuration changes.
reg [2:0] S_cam_rx_rst_sync_70m;
always @(posedge S_clk_70m or negedge S_cam_cfg_rst_n) begin
    if(!S_cam_cfg_rst_n)
        S_cam_rx_rst_sync_70m <= 3'b000;
    else
        S_cam_rx_rst_sync_70m <= {S_cam_rx_rst_sync_70m[1:0], 1'b1};
end
assign S_cam_rx_rst_n_70m = S_cam_rx_rst_sync_70m[2];

reg [2:0] S_cam_hs_rst_sync;
always @(posedge S_hs_rx_clk or negedge S_cam_cfg_done) begin
    if(!S_cam_cfg_done)
        S_cam_hs_rst_sync <= 3'b000;
    else
        S_cam_hs_rst_sync <= {S_cam_hs_rst_sync[1:0], 1'b1};
end
assign S_cam_hs_rst_n = S_cam_hs_rst_sync[2];

//PH1_LOGIC_ODDR X_cam_clk (
//    .q  		(O_clk_25m	), 
//    .clk		(S_clk_25m	),
//    .d0 		(1'b1		),
//    .d1 		(1'b0		),
//    .rst		(~S_pll_lock)
//  );
  

//手动配置相机AE
ui_ae_set X_ui_ae_set (
	.I_clk			(S_clk_25m		),
	.I_rst			(S_cam_cfg_rst_n), 
	.I_btn			( 2'b11			), // active-low keys: 11 means no key pressed
	.I_cam_cfg_done	(S_cam_cfg_done	),
	.I_ae_cfg_done	(S_ae_cfg_done	),
	.O_ae_req		(S_ae_req		),
	.O_ae			(S_ae			)
  );
  
//IIC协议配置摄像头寄存器
ui_cfg_imx415#(
	.CLK_DIV(24_000_000/100_000-1)
	)
X_ui_cfg_imx415(
	.I_clk			(S_clk_25m		),  
	.I_rst_n		(S_cam_cfg_rst_n),  
	.I_ae_req		(S_ae_req		),
	.I_ae_data		(S_ae			),
	.O_cam_scl		(O_cam_scl		), 
	.IO_cam_sda		(IO_cam_sda		), 
	.O_cfg_done		(S_cam_cfg_done	),
	.O_ae_cfg_done	(S_ae_cfg_done	),
	.O_iic_error   	(S_cam_iic_error)
  );

//mipi_rx
mipi_dphy_rx_over_lvds_wrapper#(
    .DEVICE           ( "PH1"		 ),
    .LANE_NUM         ( 4    		 )
)X_mipi_dphy_rx_over_lvds_wrapper(
    .I_lp_clk         ( S_clk_70m    ),
    .I_rst            ( ~S_cam_rx_rst_n_70m ),

    .I_mipi_clk_p     ( I_clk_hs_p   ),
    .I_mipi_data_hs_p ( I_data_hs_p  ),
    .I_mipi_data_lp_p ( I_data_lp_p  ),
    .I_mipi_data_lp_n ( I_data_lp_n  ),

    .I_lane_hs_invert ( 4'b0000      ),
    .I_lane_lp_invert ( 4'b0000      ),

    .O_hs_rx_clk      ( S_hs_rx_clk  ),
    .O_hs_rx_valid    ( S_hs_rx_valid),
    .O_hs_rx_data     ( S_hs_rx_data ),

    .O_lp_rx_lane0_p  (				 ),
    .O_lp_rx_lane0_n  (				 ),

    .O_lane_error     ( S_lane_error )
);

//csi解码模块
ui_csi_unpacket_4lane X_ui_csi_unpacket_4lane(
	.I_clk            ( S_hs_rx_clk       ),
	.I_rst_n          ( S_cam_hs_rst_n    ),
	.I_hs_valid       ( S_hs_rx_valid     ),
	.I_hs_data        ( S_hs_rx_data      ),
		
	.O_csi_frame_start( S_csi_frame_start ),
	.O_csi_frame_end  ( S_csi_frame_end   ),
	.O_csi_valid      ( S_csi_valid       ),
	.O_csi_data       ( S_csi_data        )
);

//转为RAW10数据格式
ui_raw10_unpacket_4lane X_ui_raw10_unpacket_4lane (
	.I_clk  			(S_hs_rx_clk		),
	.I_rst_n			(S_cam_hs_rst_n	),
		
	.I_csi_frame_start	(S_csi_frame_start	),
	.I_csi_frame_end  	(S_csi_frame_end	),
	.I_csi_valid      	(S_csi_valid		),
	.I_csi_data       	(S_csi_data			),
		
	.O_raw10_frame_start(S_raw10_frame_start),
	.O_raw10_frame_end  (S_raw10_frame_end  ),
	.O_raw10_valid      (S_raw10_valid      ),
	.O_raw10_data       (S_raw10_data       )
);

//图像大小裁剪模块
ui_image_correction #(
    .DATA_WIDTH  (40),
    .TDEST_WIDTH (10)
)X_ui_image_correction
(
    .I_clk            (S_hs_rx_clk		  ),
    .I_rst_n          (S_cam_hs_rst_n  ),
	
    .I_raw_data       (S_raw10_data       ),       
    .I_raw_valid      (S_raw10_valid      ),     
    .I_raw_frame_start(S_raw10_frame_start),
    .I_raw_frame_end  (S_raw10_frame_end  ),
    
    .O_raw_tdata 	  (S_axis_tdata 	  ),
    .O_raw_tlast 	  (S_axis_tlast 	  ),
    .O_raw_tvalid	  (S_axis_tvalid	  ),
    .O_raw_tuser 	  (S_axis_tuser 	  )

);



//米联客ISP图像处理模块
ui_isp_top X_ui_isp_top (
	.I_clk		     (S_hs_rx_clk		),
	.I_rst_n         (S_cam_hs_rst_n	),
	.I_tlast         (S_axis_tlast 		),
	.I_tuser         (S_axis_tuser 		),
	.I_tdata         (S_axis_tdata 		),
	.I_tvalid        (S_axis_tvalid		),
	.I_tdest         (					),
	.O_tready        (S_ISP_O_tready	),
	.O_tdata         (S_ISP_O_tdata 	),
	.O_tlast         (S_ISP_O_tlast 	),
	.O_tuser         (S_ISP_O_tuser 	),
	.O_tvalid        (S_ISP_O_tvalid	),
	.I_tready        (					)
  );


//设置3帧缓存，读延迟写1帧
ui_setvbuf#(
	.BUF_DELAY		(1			),
	.BUF_LENTH		(3			)
)
X_ui_setvbuf
(
	.I_bufn			(S_wbuf_sync),
	.O_bufn			(S_rbuf_sync)
);


//例化uidbuf 控制器
ui_dbuf# (  
	.AXI_DATA_WIDTH	(AXI_DATA_WIDTH		),//AXI总线数据位宽
	.AXI_ADDR_WIDTH	(AXI_ADDR_WIDTH		),//AXI总线地址位宽
	.ENABLE_VSYNC	(1					),
	.W_BUFDEPTH		(2048				),//写通道AXI设置FIFO缓存大小
	.W_DATAWIDTH	(128				),//写通道AXI设置数据位宽大小
	.W_BASEADDR		(0					),//写通道设置内存起始地址
	.W_DSIZEBITS	(25					),//写通道设置缓存数据的增量地址大小，用于FDMA DBUF 计算帧缓存起始地址
	.W_XSIZE		(480				),//写通道设置X方向的数据大小，代表了每次FDMA 传输的数据长度
	.W_XSTRIDE		(480				),//写通道设置X方向的Stride值，主要用于图形缓存应用
	.W_YSIZE		(1080				),//写通道设置Y方向值，代表了进行了多少次XSIZE传输
	.W_XDIV			(2					),//写通道对X方向数据拆分为XDIV次传输，减少FIFO的使用
	.W_BUFSIZE		(3					),//写通道设置帧缓存大小，目前最大支持128帧，可以修改参数支持更缓存数
		
	.R_BUFDEPTH		(2048				),//读通道AXI设置FIFO缓存大小
	.R_DATAWIDTH	(32					),//读通道AXI设置数据位宽大小
	.R_BASEADDR		(0					),//读通道设置内存起始地址
	.R_DSIZEBITS	(25					),//读通道设置缓存数据的增量地址大小，用于FDMA DBUF 计算帧缓存起始地址
	.R_XSIZE		(1024				),//读通道设置X方向的数据大小，代表了每次FDMA 传输的数据长度
	.R_XSTRIDE		(1920				),//读通道设置X方向的Stride值，主要用于图形缓存应用
	.R_YSIZE		(600				),//读通道设置Y方向值，代表了进行了多少次XSIZE传输
	.R_XDIV			(2					),//读通道对X方向数据拆分为XDIV次传输，减少FIFO的使用
	.R_BUFSIZE		(3					) //读通道设置帧缓存大小，目前最大支持128帧，可以修改参数支持更缓存数
)
X_ui_dbuf
(
	.I_ui_clk		(S_dfi_clk			),
	.I_ui_rstn		(S_ddr_init_cal_done),
		
	.I_W_en      	(1					),
	.I_W_wclk    	(S_ud_wclk			),
	.I_W_tuser   	(S_ud_wtuser		),
	.I_W_tvalid  	(S_ud_wtvalid		),
	.I_W_tdata   	(S_ud_wtdata		),
	.I_W_tlast   	(S_ud_wtlast		),
	.O_W_tready  	(					),
	.O_W_overflow 	(S_ud_woverflow		),
	.O_W_sync_error(S_ud_wsync_error	),
	.O_W_sync_cnt	(S_wbuf_sync		),
	.I_W_buf     	(S_wbuf_sync		),
	
	.I_R_en      	(S_24b_vsync		),
	.I_R_rclk    	(S_clk				),
	.I_R_tready  	(S_24b_de			),
	.O_R_tuser   	(					),
	.O_R_tvalid  	(S_ud_rtvalid		),
	.O_R_tdata   	(S_ud_rtdata		),
	.O_R_tlast   	(					),
	.O_R_sync_cnt	(					),
	.I_R_buf     	(S_rbuf_sync		),
	.O_R_vrst    	(S_R_vrst			),
	
	.O_fdma_waddr 	(S_fdma_waddr		),
	.O_fdma_wareq 	(S_fdma_wareq		),
	.O_fdma_wsize 	(S_fdma_wsize		),
	.I_fdma_wbusy 	(S_fdma_wbusy		),
	.O_fdma_wdata 	(S_fdma_wdata		),
	.I_fdma_wvalid	(S_fdma_wvalid		),
	.O_fdma_wready	(S_fdma_wready		),
	.O_fdma_raddr 	(S_fdma_raddr		),
	.O_fdma_rareq 	(S_fdma_rareq		),
	.O_fdma_rsize 	(S_fdma_rsize		),
	.I_fdma_rbusy 	(S_fdma_rbusy		),
	.I_fdma_rdata 	(S_fdma_rdata		),
	.I_fdma_rvalid	(S_fdma_rvalid		),
	.O_fdma_rready	(S_fdma_rready		),
	.O_fdma_wirq  	(S_fdma_wirq		)
	//.O_fmda_wbuf  	(fdma_wbuf			),	
	//.O_fmda_rbuf  	(fdma_rbuf			),	
	//.O_fdma_rirq  	(fdma_rirq			)
);

ui_capture_monitor #(
    .BEATS_PER_LINE(480),
    .LINES_PER_FRAME(1080)
) u_ui_capture_monitor (
    .I_clk                (S_ud_wclk),
    .I_rst_n              (S_ddr_init_cal_done),
    .I_tuser              (S_ud_wtuser),
    .I_tvalid             (S_ud_wtvalid),
    .I_tlast              (S_ud_wtlast),
    .I_fifo_overflow      (S_ud_woverflow),
    .I_fifo_sync_error    (S_ud_wsync_error),
    .O_complete_frame_pulse(S_capture_frame_ok),
    .O_error_pulse        (S_capture_error_pulse),
    .O_fifo_error_seen    (S_capture_fifo_error)
);

//例化米联客uiFDMA AXI 控制器 IP
ui_FDMA#
(
	.M_AXI_B2B_SET		(1				),
	.M_AXI_ID_WIDTH		(AXI_ID_WIDTH	),//ID位宽
	.M_AXI_ADDR_WIDTH	(AXI_ADDR_WIDTH	),//内存地址位宽
	.M_AXI_DATA_WIDTH	(AXI_DATA_WIDTH	),//AXI总线的数据位宽
	.M_AXI_MAX_BURST_LEN(16				) //AXI总线的burst 大小，对于AXI4，支持任意长度，对于AXI3以下最大16
)
X_ui_FDMA
(
	.I_fdma_waddr		(S_fdma_waddr	),//FDMA写通道地址
	.I_fdma_wareq		(S_fdma_wareq	),//FDMA写通道请求
	.I_fdma_wsize		(S_fdma_wsize	),//FDMA写通道一次FDMA的传输大小                                            
	.O_fdma_wbusy		(S_fdma_wbusy	),//FDMA处于BUSY状态，AXI总线正在写操作  
					
	.I_fdma_wdata		(S_fdma_wdata	),//FDMA写数据
	.O_fdma_wvalid		(S_fdma_wvalid	),//FDMA 写有效
	.I_fdma_wready		(1'b1			),//FDMA写准备好，用户可以写数据
	
	.I_fdma_raddr		(S_fdma_raddr	),// FDMA读通道地址
	.I_fdma_rareq		(S_fdma_rareq	),// FDMA读通道请求
	.I_fdma_rsize		(S_fdma_rsize	),// FDMA读通道一次FDMA的传输大小                                      
	.O_fdma_rbusy		(S_fdma_rbusy	),// FDMA处于BUSY状态，AXI总线正在读操作 
					
	.O_fdma_rdata		(S_fdma_rdata	),// FDMA读数据
	.O_fdma_rvalid		(S_fdma_rvalid	),// FDMA 读有效
	.I_fdma_rready		(1'b1			),// FDMA读准备好，用户可以读数据

//以下为AXI总线信号		
	.M_AXI_ACLK         (S_dfi_clk		),
	.M_AXI_ARESETN      (S_ddr_init_cal_done),
// Master Interface Write Address Ports
	.M_AXI_AWID         (S_axi_awid		),
	.M_AXI_AWADDR       (S_axi_awaddr	),
	.M_AXI_AWLEN        (S_axi_awlen	),
	.M_AXI_AWSIZE       (S_axi_awsize	),
	.M_AXI_AWBURST      (S_axi_awburst	),
	.M_AXI_AWLOCK       (				),
	.M_AXI_AWCACHE      (S_axi_awcache	),
	.M_AXI_AWPROT       (S_axi_awprot	),
	.M_AXI_AWQOS        (				),
	.M_AXI_AWVALID      (S_axi_awvalid	),
	.M_AXI_AWREADY      (S_axi_awready	),
// Master Interface Write Data Ports
	.M_AXI_WDATA        (S_axi_wdata	),
	.M_AXI_WSTRB        (S_axi_wstrb	),
	.M_AXI_WLAST        (S_axi_wlast	),
	.M_AXI_WVALID       (S_axi_wvalid	),
	.M_AXI_WREADY       (S_axi_wready	),
// Master Interface Write Response Ports
	.M_AXI_BID          (S_axi_bid		),
	.M_AXI_BRESP        (S_axi_bresp	),
	.M_AXI_BVALID       (S_axi_bvalid	),
	.M_AXI_BREADY       (S_axi_bready	),
// Master Interface Read Address Ports
	.M_AXI_ARID         (S_axi_arid		),
	.M_AXI_ARADDR       (S_axi_araddr	),
	.M_AXI_ARLEN        (S_axi_arlen	),
	.M_AXI_ARSIZE       (S_axi_arsize	),
	.M_AXI_ARBURST      (S_axi_arburst	),
	.M_AXI_ARLOCK       (				),
	.M_AXI_ARCACHE      (S_axi_arcache	),
	.M_AXI_ARPROT       (				),
	.M_AXI_ARQOS        (				),
	.M_AXI_ARVALID      (S_axi_arvalid	),
	.M_AXI_ARREADY      (S_axi_arready	),
// Master Interface Read Data Ports
	.M_AXI_RID          (S_axi_rid		),
	.M_AXI_RDATA        (S_axi_rdata	),
	.M_AXI_RRESP        (S_axi_rresp	),
	.M_AXI_RLAST        (S_axi_rlast	),
	.M_AXI_RVALID       (S_axi_rvalid	),
	.M_AXI_RREADY       (S_axi_rready	)		
);


//例化DDR IP
//===== DDR3 PHY INS =====//
ui_ddr X_ui_ddr (

	.sys_rst_n  		(S_pll_lock		),
    .sys_clk    		(I_ddr_clk		),

// DDRIO
`ifdef MC0_DRAM_DDR4
    .ddr_ck_t       	(				),
    .ddr_ck_c       	(				),
    .ddr_reset_n    	(				),
    .ddr_cke        	(				),
    .ddr_odt        	(				),
    .ddr_cs_n       	(				),
    .ddr_act_n      	(				),
    .ddr_bg         	(				),
    .ddr_ba         	(				),
    .ddr_addr       	(				),
    .ddr_dqs_t      	(				),
    .ddr_dqs_c      	(				),
    .ddr_dq         	(				),
    .ddr_dm_dbi     	(				),
`else
    .ddr_ck_p       	(ddr_ck_p		),    
    .ddr_ck_n       	(ddr_ck_n		),    
    .ddr_reset_n    	(ddr_reset_n	),   
    .ddr_cke        	(ddr_cke		),   
    .ddr_odt        	(ddr_odt		),    
    .ddr_cs_n       	(ddr_cs_n		),     
    .ddr_ras_n      	(ddr_ras_n		),    
    .ddr_cas_n      	(ddr_cas_n		), 		
    .ddr_we_n       	(ddr_we_n		),     
    .ddr_ba         	(ddr_ba			), 
    .ddr_addr       	(ddr_addr		),        
    .ddr_dqs_p      	(ddr_dqs_p		),   
    .ddr_dqs_n      	(ddr_dqs_n		),   
    .ddr_dq         	(ddr_dq			),
    .ddr_dm            	(ddr_dm			),
`endif

    .ctl_ram_rst_n     	(				),
    .ctl_ram_cke       	(				),

// user interface ports
    .dfi_clk           	(S_dfi_clk		),
    .pll_locked        	(				),
    .ddrphy_rst_n      	(				),
    .ddr_init_cal_done 	(S_ddr_init_cal_done),
    .ddr_init_cal_err  	(S_ddr_init_cal_err),
    .ddr_init_cal_step 	(				),

// mc user interface
`ifdef MC0_MIS_AXI
// AXI Interface
    .axi_aclk          	(				),
    .axi_aresetn       	(				),
// AXI Write Address Channel
    .axi_awid          (S_axi_awid   	),
    .axi_awaddr        (S_axi_awaddr 	),
    .axi_awlen         (S_axi_awlen  	),
    .axi_awsize        (S_axi_awsize 	),
    .axi_awburst       (S_axi_awburst	),
    .axi_awlock        (S_axi_awlock 	),
    .axi_awcache       (S_axi_awcache	),
    .axi_awprot        (S_axi_awprot 	),
    .axi_awqos         (S_axi_awqos  	),
    .axi_awvalid       (S_axi_awvalid	),
    .axi_awready       (S_axi_awready	),
// AXI Write Data Channel
    .axi_wdata         (S_axi_wdata 	),
    .axi_wstrb         (S_axi_wstrb 	),
    .axi_wlast         (S_axi_wlast 	),
    .axi_wvalid        (S_axi_wvalid	),
    .axi_wready        (S_axi_wready	),
// AXI Write Response Channel
    .axi_bid           (S_axi_bid   	),
    .axi_bresp         (S_axi_bresp 	),
    .axi_bvalid        (S_axi_bvalid	),
    .axi_bready        (S_axi_bready	),
// AXI Read Address Channel
    .axi_arid          (S_axi_arid   	),
    .axi_araddr        (S_axi_araddr 	),
    .axi_arlen         (S_axi_arlen  	),
    .axi_arsize        (S_axi_arsize 	),
    .axi_arburst       (S_axi_arburst	),
    .axi_arlock        (S_axi_arlock 	),
    .axi_arcache       (S_axi_arcache	),
    .axi_arprot        (S_axi_arprot 	),
    .axi_arqos         (S_axi_arqos  	),
    .axi_arvalid       (S_axi_arvalid	),
    .axi_arready       (S_axi_arready	),
// AXI Read Data Channel
    .axi_rid           (S_axi_rid   	),
    .axi_rdata         (S_axi_rdata 	),
    .axi_rresp         (S_axi_rresp 	),
    .axi_rlast         (S_axi_rlast 	),
    .axi_rvalid        (S_axi_rvalid	),
    .axi_rready        (S_axi_rready	),
`else  // PAXI
// Write Address Ports
    .paxi_awaddr       (				), 
    .paxi_awvalid      (				), 
    .paxi_awready      (				), 
// Write Data Ports    				
    .paxi_wdata        (				), 
    .paxi_wstrb        (				), 
    .paxi_wvalid       (				), 
    .paxi_wlast        (				), 
    .paxi_wready       (				), 
// Write Response Port 				
    .paxi_bresp        (				), 
    .paxi_bvalid       (				), 
    .paxi_bready       (				), 
// Read Address Ports  				
    .paxi_araddr       (				), 
    .paxi_arvalid      (				), 
    .paxi_arready      (				), 			 
// Read Data Ports     				
    .paxi_rdata        (				), 
    .paxi_rlast        (				), 
    .paxi_rvalid       (				), 
    .paxi_rready       (				), 
`endif
// PZQ Share
    .pzq_cal_done_i    (				),
    .pzq_cal_done_o    (				),
// DFX				
    .user_clk          (				), 
    .apb_clk           (				), 
    .mcu_busy          (				), 
    .user_update       (				), 
    .user_ram_addr     (				), 
    .user_ram_wr_en    (				), 
    .user_ram_rd_en    (				), 
    .user_ram_wr_data  (				), 
    .user_ram_rd_data  (				), 
				
    .uart_rxd          (				),
    .uart_txd          (				)
);


  reset_gen u_reset_gen (
      .I_clk     (S_clk),
      .I_pll_lock(S_pll_lock),
      .I_rst     (1'b0),

      .O_rst_n       (),
      .O_rst         (S_rst),
      .O_config_start(S_config_start)
  );

  video_source #(
        .HTOTAL ( 1344 ),
        .HSA    ( 24    ),
        .HBP    ( 136   ),
        .HFP    ( 160   ),
 
        .VTOTAL ( 635 ),
        .VSA    ( 2    ),
        .VBP    ( 21   ),
        .VFP    ( 12   )
  ) u_video_source (
      .I_clk(S_clk),
      .I_rst(S_rst),

      .I_config_done(S_config_done),

      .O_rgb24b_vsync(S_24b_vsync),
      .O_rgb24b_hsync(S_24b_hsync),
      .O_rgb24b_de   (S_24b_de),
      .O_rgb24b_data (S_24b_data)
  );


  // O_fdma_wirq stays high for multiple DDR clocks; count only its rising edge.
  reg S_fdma_wirq_d;
  always @(posedge S_dfi_clk or negedge S_ddr_init_cal_done) begin
      if(!S_ddr_init_cal_done)
          S_fdma_wirq_d <= 1'b0;
      else
          S_fdma_wirq_d <= S_fdma_wirq;
  end
  wire S_ddr_frame_pulse = S_fdma_wirq & ~S_fdma_wirq_d;

  // Start underflow monitoring only after DDR has completed its first frame.
  // Before that point an empty read FIFO is expected during normal startup.
  reg S_ddr_frame_seen;
  always @(posedge S_dfi_clk or negedge S_ddr_init_cal_done) begin
      if(!S_ddr_init_cal_done)
          S_ddr_frame_seen <= 1'b0;
      else if(S_ddr_frame_pulse)
          S_ddr_frame_seen <= 1'b1;
  end

  reg [1:0] S_ddr_frame_seen_sync;
  reg       S_ud_runderflow_seen;
  always @(posedge S_clk or posedge S_rst) begin
      if(S_rst) begin
          S_ddr_frame_seen_sync <= 2'b00;
          S_ud_runderflow_seen  <= 1'b0;
      end
      else begin
          S_ddr_frame_seen_sync <= {S_ddr_frame_seen_sync[0], S_ddr_frame_seen};
          if(S_ddr_frame_seen_sync[1] && S_24b_de && !S_ud_rtvalid)
              S_ud_runderflow_seen <= 1'b1;
      end
  end


  ui_video_osd #(
      .PIXEL_CLOCK_HZ(50000000),
      .H_ACTIVE      (1024),
      .V_ACTIVE      (600),
      .CAPTURE_WIDTH (1920),
      .CAPTURE_HEIGHT(1080)
  ) u_ui_video_osd (
      .I_pixel_clk  (S_clk),
      .I_pixel_rst  (S_rst),
      .I_frame_clk  (S_dfi_clk),
      .I_frame_rst_n(S_ddr_init_cal_done),
      .I_frame_pulse(S_ddr_frame_pulse),
      .I_error_clk  (S_ud_wclk),
      .I_error_rst_n(S_ddr_init_cal_done),
      .I_input_frame_pulse(S_axis_tuser & S_axis_tvalid),
      .I_error_pulse(S_capture_error_pulse),
      .I_fifo_error (S_capture_fifo_error | S_ud_runderflow_seen |
                     (|S_ddr_init_cal_err)),

      .I_vsync(S_24b_vsync),
      .I_hsync(S_24b_hsync),
      .I_de   (S_24b_de),
      .I_data (S_ud_rtvalid ? S_ud_rtdata : 24'h000000),

      .O_vsync(S_osd_vsync),
      .O_hsync(S_osd_hsync),
      .O_de   (S_osd_de),
      .O_data (S_osd_data)
  );


  rgb_24b_to_32b #(
      .H_ACTIVE(1024)
  ) u_rgb_24b_to_32b (
      .I_clk(S_clk),
      .I_rst(S_rst),

      .I_vsync(S_osd_vsync),
      .I_hsync(S_osd_hsync),
      .I_de   (S_osd_de),
      .I_data (S_osd_data),

      .O_vsync(S_32b_vsync),
      .O_hsync(S_32b_hsync),
      .O_de   (S_32b_de),
      .O_data (S_32b_data)
  );


  dsi_video_mode_packet #(
      .H_ACTIVE(1024)
  ) u_dsi_video_mode_packet (
      .I_clk(S_clk),
      .I_rst(S_rst),

      .I_vsync(S_32b_vsync),
      .I_hsync(S_32b_hsync),
      .I_de   (S_32b_de),
      .I_data (S_32b_data),

      .O_hs_en  (S_hs_en),
      .O_hs_data(S_hs_data),
      .O_hs_last(S_hs_last)
  );


  display_config_wrapper u_display_config_wrapper (
      .I_clk(S_lp_clk),
      .I_rst(S_rst),

      .I_config_start(S_config_start),
      .O_config_done (S_config_done),

      .O_lp_tx_valid(S_lp_tx_valid),
      .O_lp_tx_last (S_lp_tx_last),
      .O_lp_tx_data (S_lp_tx_data),
      .I_lp_tx_ready(S_lp_tx_ready)
  );

  mipi_dphy_tx_wrapper #(
      .LANE_NUM(4),

      .HS_TX_FIFO_TYPE      ("DRAM"),  ///"DRAM","BRAM"
      .LP_TX_FIFO_TYPE      ("DRAM"),  ///"DRAM","BRAM"
      .LP_TX_MAX_DATA_LENGTH(8),       ///1-240

      .CLK_LANE_MODE("CONTINUE"),  ///"INTERRUPT","CONTINUE"

      .T_DATA_LPX       (10),
      .T_DATA_HS_PREPARE(10),
      .T_DATA_HS_ZERO   (20),
      .T_DATA_HS_TRAIL  (20),
      .T_CLK_LPX        (10),
      .T_CLK_PREPARE    (10),
      .T_CLK_ZERO       (10),
      .T_CLK_PRE        (10),
      .T_CLK_POST       (10),
      .T_CLK_TRAIL      (10)
  ) u_mipi_dphy_tx_wrapper (
      .I_hs_clk       (S_clk),
      .I_hs_clk_x2    (S_clk_x2),
      .I_hs_clk_x4    (S_clk_x4),
      .I_hs_clk_x4_90d(S_clk_x4_90d),

      .I_rst(S_rst),

      .I_hs_tx_valid(S_hs_en),
      .I_hs_tx_data (S_hs_data),
      .I_hs_tx_last (S_hs_last),
      .O_hs_tx_ready(),

      .I_lpdt_clk   (S_lp_clk),
      .I_lp_tx_valid(S_lp_tx_valid),
      .I_lp_tx_data (S_lp_tx_data),
      .I_lp_tx_last (S_lp_tx_last),
      .O_lp_tx_ready(S_lp_tx_ready),

      .O_clk_hs_p (O_clk_hs_p),
      .O_data_hs_p(O_data_hs_p),
      .O_clk_lp_p (O_clk_lp_p),
      .O_clk_lp_n (O_clk_lp_n),
      .O_data_lp_p(O_data_lp_p),
      .O_data_lp_n(O_data_lp_n)
  );

  assign O_clk_lp_dir  = 1'b1;
  assign O_dsi_pwm     = 1'b1;
  assign O_data_lp_dir = 4'b1111;


endmodule


module ui_capture_monitor #(
    parameter integer BEATS_PER_LINE = 480,
    parameter integer LINES_PER_FRAME = 1080
) (
    input  wire I_clk,
    input  wire I_rst_n,
    input  wire I_tuser,
    input  wire I_tvalid,
    input  wire I_tlast,
    input  wire I_fifo_overflow,
    input  wire I_fifo_sync_error,
    output reg  O_complete_frame_pulse,
    output reg  O_error_pulse,
    output reg  O_fifo_error_seen
);

// Delay the stream markers by one clock so they are aligned with the write
// FIFO input register and its overflow indication inside ui_dbuf.
reg tuser_d;
reg tvalid_d;
reg tlast_d;
reg fifo_sync_error_d;

reg        have_frame;
reg        frame_bad;
reg [9:0]  beat_count;
reg [10:0] line_count;

always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        tuser_d                <= 1'b0;
        tvalid_d               <= 1'b0;
        tlast_d                <= 1'b0;
        fifo_sync_error_d      <= 1'b0;
        have_frame             <= 1'b0;
        frame_bad              <= 1'b0;
        beat_count             <= 10'd0;
        line_count             <= 11'd0;
        O_complete_frame_pulse <= 1'b0;
        O_error_pulse          <= 1'b0;
        O_fifo_error_seen      <= 1'b0;
    end
    else begin
        tuser_d           <= I_tuser;
        tvalid_d          <= I_tvalid;
        tlast_d           <= I_tlast;
        fifo_sync_error_d <= I_fifo_sync_error;

        O_complete_frame_pulse <= 1'b0;
        O_error_pulse          <= 1'b0;

        if(I_fifo_overflow || I_fifo_sync_error)
            O_fifo_error_seen <= 1'b1;

        if(tvalid_d) begin
            if(tuser_d) begin
                // A frame is accepted only when the next SOF proves that the
                // previous frame contained exactly 1080 complete 480-beat lines.
                if(have_frame) begin
                    if((line_count == LINES_PER_FRAME) &&
                       (beat_count == 0) && !frame_bad && !fifo_sync_error_d)
                        O_complete_frame_pulse <= 1'b1;
                    else
                        O_error_pulse <= 1'b1;
                end

                have_frame <= 1'b1;
                if(tlast_d) begin
                    beat_count <= 10'd0;
                    line_count <= 11'd1;
                    frame_bad  <= 1'b1;
                end
                else begin
                    beat_count <= 10'd1;
                    line_count <= 11'd0;
                    frame_bad  <= I_fifo_overflow | fifo_sync_error_d;
                end
            end
            else if(have_frame) begin
                if(I_fifo_overflow)
                    frame_bad <= 1'b1;

                if(tlast_d) begin
                    if(beat_count != BEATS_PER_LINE - 1)
                        frame_bad <= 1'b1;
                    beat_count <= 10'd0;
                    if(line_count < 11'h7ff)
                        line_count <= line_count + 1'b1;
                    else
                        frame_bad <= 1'b1;
                end
                else begin
                    if(beat_count >= BEATS_PER_LINE - 1)
                        frame_bad <= 1'b1;
                    if(beat_count < 10'h3ff)
                        beat_count <= beat_count + 1'b1;
                    else
                        frame_bad <= 1'b1;
                end
            end
        end
    end
end

endmodule


module ui_video_osd #(
    parameter integer PIXEL_CLOCK_HZ = 50000000,
    parameter integer H_ACTIVE       = 1024,
    parameter integer V_ACTIVE       = 600,
    parameter integer CAPTURE_WIDTH  = 1920,
    parameter integer CAPTURE_HEIGHT = 1080
) (
    input  wire        I_pixel_clk,
    input  wire        I_pixel_rst,
    input  wire        I_frame_clk,
    input  wire        I_frame_rst_n,
    input  wire        I_frame_pulse,
    input  wire        I_error_clk,
    input  wire        I_error_rst_n,
    input  wire        I_input_frame_pulse,
    input  wire        I_error_pulse,
    input  wire        I_fifo_error,
    input  wire        I_vsync,
    input  wire        I_hsync,
    input  wire        I_de,
    input  wire [23:0] I_data,
    output reg         O_vsync,
    output reg         O_hsync,
    output reg         O_de,
    output reg  [23:0] O_data
);

localparam integer TEXT_X       = 16;
localparam integer TEXT0_Y      = 16;
localparam integer TEXT1_Y      = 40;
localparam integer TEXT2_Y      = 64;
localparam integer TEXT0_CHARS  = 13;
localparam integer TEXT1_CHARS  = 13;
localparam integer TEXT2_CHARS  = 13;
localparam integer CHAR_WIDTH   = 16;
localparam integer CHAR_HEIGHT  = 16;
localparam integer BG_X_MIN     = 8;
localparam integer BG_X_MAX     = TEXT_X + TEXT0_CHARS * CHAR_WIDTH + 8;
localparam integer BG_Y_MIN     = 8;
localparam integer BG_Y_MAX     = TEXT2_Y + CHAR_HEIGHT + 8;
localparam integer PANE0_X       = 0;
localparam integer PANE1_X       = 341;
localparam integer PANE2_X       = 682;
localparam integer IMAGE_WIDTH   = 400;
localparam integer IMAGE_HEIGHT  = 234;
localparam integer IMAGE_PIXELS  = IMAGE_WIDTH * IMAGE_HEIGHT;
localparam [17:0]  IMAGE_PIXELS_18 = IMAGE_PIXELS;
localparam integer SOURCE_Y_CROP = 3;
localparam integer ROTATE_CLOCKWISE = 1;

localparam [3:0] CW_DIGIT_3 = (CAPTURE_WIDTH / 1000) % 10;
localparam [3:0] CW_DIGIT_2 = (CAPTURE_WIDTH / 100)  % 10;
localparam [3:0] CW_DIGIT_1 = (CAPTURE_WIDTH / 10)   % 10;
localparam [3:0] CW_DIGIT_0 =  CAPTURE_WIDTH         % 10;
localparam [3:0] CH_DIGIT_3 = (CAPTURE_HEIGHT / 1000) % 10;
localparam [3:0] CH_DIGIT_2 = (CAPTURE_HEIGHT / 100)  % 10;
localparam [3:0] CH_DIGIT_1 = (CAPTURE_HEIGHT / 10)   % 10;
localparam [3:0] CH_DIGIT_0 =  CAPTURE_HEIGHT         % 10;

reg frame_toggle_src;

always @(posedge I_frame_clk or negedge I_frame_rst_n) begin
    if(!I_frame_rst_n)
        frame_toggle_src <= 1'b0;
    else if(I_frame_pulse)
        frame_toggle_src <= ~frame_toggle_src;
end

reg input_frame_toggle_src;
reg error_toggle_src;
reg fifo_error_src;

always @(posedge I_error_clk or negedge I_error_rst_n) begin
    if(!I_error_rst_n) begin
        input_frame_toggle_src <= 1'b0;
        error_toggle_src <= 1'b0;
        fifo_error_src   <= 1'b0;
    end
    else begin
        if(I_input_frame_pulse)
            input_frame_toggle_src <= ~input_frame_toggle_src;
        if(I_error_pulse)
            error_toggle_src <= ~error_toggle_src;
        if(I_fifo_error)
            fifo_error_src <= 1'b1;
    end
end

reg        frame_toggle_meta;
reg        frame_toggle_sync;
reg        frame_toggle_sync_d;
reg        input_frame_toggle_meta;
reg        input_frame_toggle_sync;
reg        input_frame_toggle_sync_d;
reg        error_toggle_meta;
reg        error_toggle_sync;
reg        error_toggle_sync_d;
reg        fifo_error_meta;
reg        fifo_error_sync;
reg [25:0] second_counter;
reg [7:0]  frame_counter;
reg [7:0]  fps_value;
reg [7:0]  input_frame_counter;
reg [7:0]  input_fps_value;
reg [7:0]  error_count;

wire frame_event = frame_toggle_sync ^ frame_toggle_sync_d;
wire input_frame_event = input_frame_toggle_sync ^ input_frame_toggle_sync_d;
wire error_event = error_toggle_sync ^ error_toggle_sync_d;
wire [8:0] frame_count_next = {1'b0, frame_counter} + frame_event;
wire [8:0] input_frame_count_next = {1'b0, input_frame_counter} + input_frame_event;

always @(posedge I_pixel_clk or posedge I_pixel_rst) begin
    if(I_pixel_rst) begin
        frame_toggle_meta   <= 1'b0;
        frame_toggle_sync   <= 1'b0;
        frame_toggle_sync_d <= 1'b0;
        input_frame_toggle_meta   <= 1'b0;
        input_frame_toggle_sync   <= 1'b0;
        input_frame_toggle_sync_d <= 1'b0;
        error_toggle_meta   <= 1'b0;
        error_toggle_sync   <= 1'b0;
        error_toggle_sync_d <= 1'b0;
        fifo_error_meta     <= 1'b0;
        fifo_error_sync     <= 1'b0;
        second_counter      <= 26'd0;
        frame_counter       <= 8'd0;
        fps_value           <= 8'd0;
        input_frame_counter <= 8'd0;
        input_fps_value     <= 8'd0;
        error_count         <= 8'd0;
    end
    else begin
        frame_toggle_meta   <= frame_toggle_src;
        frame_toggle_sync   <= frame_toggle_meta;
        frame_toggle_sync_d <= frame_toggle_sync;
        input_frame_toggle_meta   <= input_frame_toggle_src;
        input_frame_toggle_sync   <= input_frame_toggle_meta;
        input_frame_toggle_sync_d <= input_frame_toggle_sync;
        error_toggle_meta   <= error_toggle_src;
        error_toggle_sync   <= error_toggle_meta;
        error_toggle_sync_d <= error_toggle_sync;
        fifo_error_meta     <= fifo_error_src;
        fifo_error_sync     <= fifo_error_meta;

        if(error_event && error_count < 8'd99)
            error_count <= error_count + 1'b1;

        if(second_counter == PIXEL_CLOCK_HZ - 1) begin
            second_counter <= 26'd0;
            frame_counter  <= 8'd0;
            fps_value      <= (frame_count_next > 9'd99) ? 8'd99 : frame_count_next[7:0];
            input_frame_counter <= 8'd0;
            input_fps_value <= (input_frame_count_next > 9'd99) ? 8'd99 : input_frame_count_next[7:0];
        end
        else begin
            second_counter <= second_counter + 1'b1;
            if(frame_event && frame_counter != 8'hff)
                frame_counter <= frame_counter + 1'b1;
            if(input_frame_event && input_frame_counter != 8'hff)
                input_frame_counter <= input_frame_counter + 1'b1;
        end
    end
end

reg [3:0] input_fps_tens;
always @* begin
    if(input_fps_value >= 90)      input_fps_tens = 9;
    else if(input_fps_value >= 80) input_fps_tens = 8;
    else if(input_fps_value >= 70) input_fps_tens = 7;
    else if(input_fps_value >= 60) input_fps_tens = 6;
    else if(input_fps_value >= 50) input_fps_tens = 5;
    else if(input_fps_value >= 40) input_fps_tens = 4;
    else if(input_fps_value >= 30) input_fps_tens = 3;
    else if(input_fps_value >= 20) input_fps_tens = 2;
    else if(input_fps_value >= 10) input_fps_tens = 1;
    else                           input_fps_tens = 0;
end

wire [3:0] input_fps_ones = input_fps_value - input_fps_tens * 10;

reg [3:0] fps_tens;
always @* begin
    if(fps_value >= 90)      fps_tens = 9;
    else if(fps_value >= 80) fps_tens = 8;
    else if(fps_value >= 70) fps_tens = 7;
    else if(fps_value >= 60) fps_tens = 6;
    else if(fps_value >= 50) fps_tens = 5;
    else if(fps_value >= 40) fps_tens = 4;
    else if(fps_value >= 30) fps_tens = 3;
    else if(fps_value >= 20) fps_tens = 2;
    else if(fps_value >= 10) fps_tens = 1;
    else                     fps_tens = 0;
end

wire [3:0] fps_ones = fps_value - fps_tens * 10;

reg [3:0] error_tens;
always @* begin
    if(error_count >= 90)      error_tens = 9;
    else if(error_count >= 80) error_tens = 8;
    else if(error_count >= 70) error_tens = 7;
    else if(error_count >= 60) error_tens = 6;
    else if(error_count >= 50) error_tens = 5;
    else if(error_count >= 40) error_tens = 4;
    else if(error_count >= 30) error_tens = 3;
    else if(error_count >= 20) error_tens = 2;
    else if(error_count >= 10) error_tens = 1;
    else                       error_tens = 0;
end

wire [3:0] error_ones = error_count - error_tens * 10;

reg        de_d;
reg        vsync_d;
reg [10:0] pixel_x;
reg [10:0] pixel_y;

wire pixel_frame_start = !vsync_d && I_vsync;

always @(posedge I_pixel_clk or posedge I_pixel_rst) begin
    if(I_pixel_rst) begin
        de_d    <= 1'b0;
        vsync_d <= 1'b0;
        pixel_x <= 11'd0;
        pixel_y <= 11'd0;
    end
    else begin
        de_d    <= I_de;
        vsync_d <= I_vsync;

        if(!vsync_d && I_vsync) begin
            pixel_x <= 11'd0;
            pixel_y <= 11'd0;
        end
        else begin
            if(I_de)
                pixel_x <= pixel_x + 1'b1;
            else
                pixel_x <= 11'd0;

            if(de_d && !I_de)
                pixel_y <= pixel_y + 1'b1;
        end
    end
end

// The panel is mounted in portrait orientation. Native X therefore becomes
// portrait Y, so the three physical windows occupy three native X bands.
// A 400x234 logical image is double-buffered to keep rotation tear-free.
reg [7:0] gauss_line_1  [0:IMAGE_WIDTH-1]; /* fehdl force_ram=1, ram_style="bram" */
reg [7:0] gauss_line_2  [0:IMAGE_WIDTH-1]; /* fehdl force_ram=1, ram_style="bram" */
reg [7:0] equalize_lut_0 [0:255];
reg [7:0] equalize_lut_1 [0:255];
reg       equalize_ready_0;
reg       equalize_ready_1;

reg [10:0] scale_x_acc;
reg [10:0] scale_y_acc;
reg [8:0]  capture_x;
reg [8:0]  capture_y;
reg [16:0] capture_addr;
reg        capture_bank;
reg        display_bank;
reg        capture_complete;
reg        frame_buffer_valid;

wire scale_x_take = (scale_x_acc + IMAGE_WIDTH) >= H_ACTIVE;
wire scale_y_take = (scale_y_acc + IMAGE_HEIGHT) >= V_ACTIVE;
wire capture_sample = I_de && scale_x_take && scale_y_take &&
                      (capture_addr < IMAGE_PIXELS);

always @(posedge I_pixel_clk or posedge I_pixel_rst) begin
    if(I_pixel_rst) begin
        scale_x_acc       <= 11'd0;
        scale_y_acc       <= 11'd0;
        capture_x         <= 9'd0;
        capture_y         <= 9'd0;
        capture_addr      <= 17'd0;
        capture_bank      <= 1'b0;
        display_bank      <= 1'b1;
        capture_complete  <= 1'b0;
        frame_buffer_valid <= 1'b0;
    end
    else begin
        if(pixel_frame_start) begin
            scale_x_acc  <= 11'd0;
            scale_y_acc  <= 11'd0;
            capture_x    <= 9'd0;
            capture_y    <= 9'd0;
            capture_addr <= 17'd0;

            if(capture_complete) begin
                display_bank       <= capture_bank;
                capture_bank       <= ~capture_bank;
                frame_buffer_valid <= 1'b1;
            end
            capture_complete <= 1'b0;
        end
        else begin
            if(I_de) begin
                if(scale_x_take)
                    scale_x_acc <= scale_x_acc + IMAGE_WIDTH - H_ACTIVE;
                else
                    scale_x_acc <= scale_x_acc + IMAGE_WIDTH;
            end
            else
                scale_x_acc <= 11'd0;

            if(de_d && !I_de) begin
                if(scale_y_take)
                    scale_y_acc <= scale_y_acc + IMAGE_HEIGHT - V_ACTIVE;
                else
                    scale_y_acc <= scale_y_acc + IMAGE_HEIGHT;
            end

            if(capture_sample) begin
                if(capture_addr == IMAGE_PIXELS - 1)
                    capture_complete <= 1'b1;
                else
                    capture_addr <= capture_addr + 1'b1;

                if(capture_x == IMAGE_WIDTH - 1) begin
                    capture_x <= 9'd0;
                    if(capture_y != IMAGE_HEIGHT - 1)
                        capture_y <= capture_y + 1'b1;
                end
                else
                    capture_x <= capture_x + 1'b1;
            end
        end
    end
end

// The ISP grayscale stage emits equal R/G/B channels.  Dynamic AWB is disabled
// in ui_isp_top so this luminance no longer changes gain during every frame.
wire [7:0] gray_value = I_data[15:8];

// Gaussian processing runs on the scaled 400x234 stream before rotation.
// Four line buffers and five horizontal taps implement the separable 5x5
// binomial kernel [1 4 6 4 1]^2 / 256.  This is visibly stronger than the
// previous 3x3 kernel while retaining an exact power-of-two normalization.
reg        gauss_filter_valid;
reg        gauss_filter_bank;
reg [8:0]  gauss_filter_x;
reg [8:0]  gauss_filter_y;
reg [16:0] gauss_filter_addr;
reg [7:0]  gauss_filter_gray;
reg [7:0]  gauss_line_1_data;
reg [7:0]  gauss_line_2_data;
reg [7:0]  gauss_line_3_data;
reg [7:0]  gauss_line_4_data;
reg [7:0]  gauss_row0_m4, gauss_row0_m3, gauss_row0_m2, gauss_row0_m1;
reg [7:0]  gauss_row1_m4, gauss_row1_m3, gauss_row1_m2, gauss_row1_m1;
reg [7:0]  gauss_row2_m4, gauss_row2_m3, gauss_row2_m2, gauss_row2_m1;
reg [7:0]  gauss_row3_m4, gauss_row3_m3, gauss_row3_m2, gauss_row3_m1;
reg [7:0]  gauss_row4_m4, gauss_row4_m3, gauss_row4_m2, gauss_row4_m1;
reg        gauss_kernel_valid;
reg        gauss_kernel_bank;
reg [16:0] gauss_kernel_addr;
reg [11:0] gauss_row_sum0;
reg [11:0] gauss_row_sum1;
reg [11:0] gauss_row_sum2;
reg [11:0] gauss_row_sum3;
reg [11:0] gauss_row_sum4;

reg [7:0] gauss_line_3 [0:IMAGE_WIDTH-1]; /* fehdl force_ram=1, ram_style="bram" */
reg [7:0] gauss_line_4 [0:IMAGE_WIDTH-1]; /* fehdl force_ram=1, ram_style="bram" */

always @(posedge I_pixel_clk or posedge I_pixel_rst) begin
    if(I_pixel_rst) begin
        gauss_filter_valid <= 1'b0;
        gauss_filter_bank  <= 1'b0;
        gauss_filter_x     <= 9'd0;
        gauss_filter_y     <= 9'd0;
        gauss_filter_addr  <= 17'd0;
        gauss_filter_gray  <= 8'd0;
        gauss_line_1_data  <= 8'd0;
        gauss_line_2_data  <= 8'd0;
        gauss_line_3_data  <= 8'd0;
        gauss_line_4_data  <= 8'd0;
    end
    else begin
        gauss_filter_valid <= capture_sample;
        if(capture_sample) begin
            gauss_filter_bank <= capture_bank;
            gauss_filter_x    <= capture_x;
            gauss_filter_y    <= capture_y;
            gauss_filter_addr <= capture_addr;
            gauss_filter_gray <= gray_value;
            gauss_line_1_data <= gauss_line_1[capture_x];
            gauss_line_2_data <= gauss_line_2[capture_x];
            gauss_line_3_data <= gauss_line_3[capture_x];
            gauss_line_4_data <= gauss_line_4[capture_x];
        end
    end
end

wire [11:0] gauss_horizontal0 =
    {4'd0, gauss_row0_m4} + ({4'd0, gauss_row0_m3} << 2) +
    ({4'd0, gauss_row0_m2} << 2) + ({4'd0, gauss_row0_m2} << 1) +
    ({4'd0, gauss_row0_m1} << 2) + {4'd0, gauss_line_4_data};
wire [11:0] gauss_horizontal1 =
    {4'd0, gauss_row1_m4} + ({4'd0, gauss_row1_m3} << 2) +
    ({4'd0, gauss_row1_m2} << 2) + ({4'd0, gauss_row1_m2} << 1) +
    ({4'd0, gauss_row1_m1} << 2) + {4'd0, gauss_line_3_data};
wire [11:0] gauss_horizontal2 =
    {4'd0, gauss_row2_m4} + ({4'd0, gauss_row2_m3} << 2) +
    ({4'd0, gauss_row2_m2} << 2) + ({4'd0, gauss_row2_m2} << 1) +
    ({4'd0, gauss_row2_m1} << 2) + {4'd0, gauss_line_2_data};
wire [11:0] gauss_horizontal3 =
    {4'd0, gauss_row3_m4} + ({4'd0, gauss_row3_m3} << 2) +
    ({4'd0, gauss_row3_m2} << 2) + ({4'd0, gauss_row3_m2} << 1) +
    ({4'd0, gauss_row3_m1} << 2) + {4'd0, gauss_line_1_data};
wire [11:0] gauss_horizontal4 =
    {4'd0, gauss_row4_m4} + ({4'd0, gauss_row4_m3} << 2) +
    ({4'd0, gauss_row4_m2} << 2) + ({4'd0, gauss_row4_m2} << 1) +
    ({4'd0, gauss_row4_m1} << 2) + {4'd0, gauss_filter_gray};

wire [15:0] gauss_sum =
    {4'd0, gauss_row_sum0} + ({4'd0, gauss_row_sum1} << 2) +
    ({4'd0, gauss_row_sum2} << 2) + ({4'd0, gauss_row_sum2} << 1) +
    ({4'd0, gauss_row_sum3} << 2) + {4'd0, gauss_row_sum4};
wire [16:0] gauss_write_addr = gauss_kernel_addr - (2 * IMAGE_WIDTH) - 2;

always @(posedge I_pixel_clk or posedge I_pixel_rst) begin
    if(I_pixel_rst) begin
        gauss_row0_m4 <= 8'd0; gauss_row0_m3 <= 8'd0;
        gauss_row0_m2 <= 8'd0; gauss_row0_m1 <= 8'd0;
        gauss_row1_m4 <= 8'd0; gauss_row1_m3 <= 8'd0;
        gauss_row1_m2 <= 8'd0; gauss_row1_m1 <= 8'd0;
        gauss_row2_m4 <= 8'd0; gauss_row2_m3 <= 8'd0;
        gauss_row2_m2 <= 8'd0; gauss_row2_m1 <= 8'd0;
        gauss_row3_m4 <= 8'd0; gauss_row3_m3 <= 8'd0;
        gauss_row3_m2 <= 8'd0; gauss_row3_m1 <= 8'd0;
        gauss_row4_m4 <= 8'd0; gauss_row4_m3 <= 8'd0;
        gauss_row4_m2 <= 8'd0; gauss_row4_m1 <= 8'd0;
    end
    else if(gauss_filter_valid) begin
        if(gauss_filter_x == 0) begin
            gauss_row0_m4 <= 8'd0; gauss_row0_m3 <= 8'd0;
            gauss_row0_m2 <= 8'd0; gauss_row0_m1 <= gauss_line_4_data;
            gauss_row1_m4 <= 8'd0; gauss_row1_m3 <= 8'd0;
            gauss_row1_m2 <= 8'd0; gauss_row1_m1 <= gauss_line_3_data;
            gauss_row2_m4 <= 8'd0; gauss_row2_m3 <= 8'd0;
            gauss_row2_m2 <= 8'd0; gauss_row2_m1 <= gauss_line_2_data;
            gauss_row3_m4 <= 8'd0; gauss_row3_m3 <= 8'd0;
            gauss_row3_m2 <= 8'd0; gauss_row3_m1 <= gauss_line_1_data;
            gauss_row4_m4 <= 8'd0; gauss_row4_m3 <= 8'd0;
            gauss_row4_m2 <= 8'd0; gauss_row4_m1 <= gauss_filter_gray;
        end
        else begin
            gauss_row0_m4 <= gauss_row0_m3; gauss_row0_m3 <= gauss_row0_m2;
            gauss_row0_m2 <= gauss_row0_m1; gauss_row0_m1 <= gauss_line_4_data;
            gauss_row1_m4 <= gauss_row1_m3; gauss_row1_m3 <= gauss_row1_m2;
            gauss_row1_m2 <= gauss_row1_m1; gauss_row1_m1 <= gauss_line_3_data;
            gauss_row2_m4 <= gauss_row2_m3; gauss_row2_m3 <= gauss_row2_m2;
            gauss_row2_m2 <= gauss_row2_m1; gauss_row2_m1 <= gauss_line_2_data;
            gauss_row3_m4 <= gauss_row3_m3; gauss_row3_m3 <= gauss_row3_m2;
            gauss_row3_m2 <= gauss_row3_m1; gauss_row3_m1 <= gauss_line_1_data;
            gauss_row4_m4 <= gauss_row4_m3; gauss_row4_m3 <= gauss_row4_m2;
            gauss_row4_m2 <= gauss_row4_m1; gauss_row4_m1 <= gauss_filter_gray;
        end
    end
end

always @(posedge I_pixel_clk) begin
    if(gauss_filter_valid) begin
        gauss_line_4[gauss_filter_x] <= gauss_line_3_data;
        gauss_line_3[gauss_filter_x] <= gauss_line_2_data;
        gauss_line_2[gauss_filter_x] <= gauss_line_1_data;
        gauss_line_1[gauss_filter_x] <= gauss_filter_gray;
    end
end

always @(posedge I_pixel_clk or posedge I_pixel_rst) begin
    if(I_pixel_rst) begin
        gauss_kernel_valid <= 1'b0;
        gauss_kernel_bank  <= 1'b0;
        gauss_kernel_addr  <= 17'd0;
        gauss_row_sum0     <= 12'd0;
        gauss_row_sum1     <= 12'd0;
        gauss_row_sum2     <= 12'd0;
        gauss_row_sum3     <= 12'd0;
        gauss_row_sum4     <= 12'd0;
    end
    else begin
        gauss_kernel_valid <= gauss_filter_valid &&
                              (gauss_filter_x >= 4) && (gauss_filter_y >= 4);
        if(gauss_filter_valid) begin
            gauss_kernel_bank <= gauss_filter_bank;
            gauss_kernel_addr <= gauss_filter_addr;
            gauss_row_sum0    <= gauss_horizontal0;
            gauss_row_sum1    <= gauss_horizontal1;
            gauss_row_sum2    <= gauss_horizontal2;
            gauss_row_sum3    <= gauss_horizontal3;
            gauss_row_sum4    <= gauss_horizontal4;
        end
    end
end

// Portrait coordinate mapping. For a clockwise-mounted panel, native Y is
// reversed to become the left-to-right axis of each physical window.
wire [10:0] portrait_x = ROTATE_CLOCKWISE ?
                         (V_ACTIVE - 1 - pixel_y) : pixel_y;
wire [10:0] portrait_y = ROTATE_CLOCKWISE ?
                         pixel_x : (H_ACTIVE - 1 - pixel_x);
wire [10:0] pane0_y = portrait_y - PANE0_X;
wire [10:0] pane1_y = portrait_y - PANE1_X;
wire [10:0] pane2_y = portrait_y - PANE2_X;
wire gray_image_area = I_de && (portrait_y < PANE1_X - 1);
wire gauss_image_area = I_de && (portrait_y >= PANE1_X) &&
                         (portrait_y < PANE2_X - 1);
wire equalized_image_area = I_de && (portrait_y >= PANE2_X);

// Enlarge 400x234 to the 600x340 pane using a 3:2 nearest-neighbor scale.
// Seven source rows are center-cropped so the aspect ratio stays unchanged.
wire [10:0] pane2_display_y = (pane2_y > 11'd339) ? 11'd339 : pane2_y;
wire [10:0] active_pane_y = (portrait_y < PANE1_X) ? pane0_y :
                            (portrait_y < PANE2_X) ? pane1_y : pane2_display_y;
wire [8:0] image_u = (portrait_x * 2) / 3;
wire [8:0] image_v = SOURCE_Y_CROP + ((active_pane_y * 2) / 3);
wire [8:0] gauss_image_u = (image_u < 2) ? 9'd2 :
                           (image_u >= IMAGE_WIDTH - 2) ? IMAGE_WIDTH - 3 : image_u;
wire [16:0] gray_read_addr = image_v * IMAGE_WIDTH + image_u;
wire [16:0] gauss_read_addr = image_v * IMAGE_WIDTH + gauss_image_u;
wire gray_frame_read_enable = gray_image_area | equalized_image_area;

wire gray_0_write = capture_sample && !capture_bank;
wire gray_1_write = capture_sample &&  capture_bank;
wire gauss_write_valid = gauss_kernel_valid;
wire gauss_0_write = gauss_write_valid && !gauss_kernel_bank;
wire gauss_1_write = gauss_write_valid &&  gauss_kernel_bank;
wire [7:0] gray_frame_0_q;
wire [7:0] gray_frame_1_q;
wire [7:0] gauss_frame_0_q;
wire [7:0] gauss_frame_1_q;

ram_infer_0322d65db018 #(
    .MODE("SDP"), .DATAWIDTH_A(8), .ADDRWIDTH_A(17),
    .DATADEPTH_A(IMAGE_PIXELS), .REGMODE_A("NOREG"),
    .DATAWIDTH_B(8), .ADDRWIDTH_B(17),
    .DATADEPTH_B(IMAGE_PIXELS), .REGMODE_B("NOREG")
) u_gray_frame_0 (
    .clka(I_pixel_clk), .rsta(I_pixel_rst), .cea(gray_0_write), .ocea(1'b1),
    .wea(gray_0_write), .dia(gray_value), .addra(capture_addr), .doa(),
    .clkb(I_pixel_clk), .rstb(I_pixel_rst), .ceb(gray_frame_read_enable), .oceb(1'b1),
    .web(1'b0), .dib(8'd0), .addrb(gray_read_addr), .dob(gray_frame_0_q)
);

ram_infer_0322d65db018 #(
    .MODE("SDP"), .DATAWIDTH_A(8), .ADDRWIDTH_A(17),
    .DATADEPTH_A(IMAGE_PIXELS), .REGMODE_A("NOREG"),
    .DATAWIDTH_B(8), .ADDRWIDTH_B(17),
    .DATADEPTH_B(IMAGE_PIXELS), .REGMODE_B("NOREG")
) u_gray_frame_1 (
    .clka(I_pixel_clk), .rsta(I_pixel_rst), .cea(gray_1_write), .ocea(1'b1),
    .wea(gray_1_write), .dia(gray_value), .addra(capture_addr), .doa(),
    .clkb(I_pixel_clk), .rstb(I_pixel_rst), .ceb(gray_frame_read_enable), .oceb(1'b1),
    .web(1'b0), .dib(8'd0), .addrb(gray_read_addr), .dob(gray_frame_1_q)
);

ram_infer_0322d65db018 #(
    .MODE("SDP"), .DATAWIDTH_A(8), .ADDRWIDTH_A(17),
    .DATADEPTH_A(IMAGE_PIXELS), .REGMODE_A("NOREG"),
    .DATAWIDTH_B(8), .ADDRWIDTH_B(17),
    .DATADEPTH_B(IMAGE_PIXELS), .REGMODE_B("NOREG")
) u_gauss_frame_0 (
    .clka(I_pixel_clk), .rsta(I_pixel_rst), .cea(gauss_0_write), .ocea(1'b1),
    .wea(gauss_0_write), .dia(gauss_sum[15:8]), .addra(gauss_write_addr), .doa(),
    .clkb(I_pixel_clk), .rstb(I_pixel_rst), .ceb(gauss_image_area), .oceb(1'b1),
    .web(1'b0), .dib(8'd0), .addrb(gauss_read_addr), .dob(gauss_frame_0_q)
);

ram_infer_0322d65db018 #(
    .MODE("SDP"), .DATAWIDTH_A(8), .ADDRWIDTH_A(17),
    .DATADEPTH_A(IMAGE_PIXELS), .REGMODE_A("NOREG"),
    .DATAWIDTH_B(8), .ADDRWIDTH_B(17),
    .DATADEPTH_B(IMAGE_PIXELS), .REGMODE_B("NOREG")
) u_gauss_frame_1 (
    .clka(I_pixel_clk), .rsta(I_pixel_rst), .cea(gauss_1_write), .ocea(1'b1),
    .wea(gauss_1_write), .dia(gauss_sum[15:8]), .addra(gauss_write_addr), .doa(),
    .clkb(I_pixel_clk), .rstb(I_pixel_rst), .ceb(gauss_image_area), .oceb(1'b1),
    .web(1'b0), .dib(8'd0), .addrb(gauss_read_addr), .dob(gauss_frame_1_q)
);

reg        video_de_1;
reg        video_vsync_1;
reg        video_hsync_1;
reg [10:0] video_x_1;
reg [10:0] video_y_1;
reg        gray_image_area_1;
reg        gauss_image_area_1;
reg        equalized_image_area_1;
wire [7:0] gray_read_data = display_bank ? gray_frame_1_q : gray_frame_0_q;
wire [7:0] gauss_read_data = display_bank ? gauss_frame_1_q : gauss_frame_0_q;
wire       equalize_display_ready = display_bank ? equalize_ready_1 : equalize_ready_0;
wire [7:0] equalized_read_data = display_bank ?
                                   equalize_lut_1[gray_read_data] :
                                   equalize_lut_0[gray_read_data];

always @(posedge I_pixel_clk or posedge I_pixel_rst) begin
    if(I_pixel_rst) begin
        video_de_1       <= 1'b0;
        video_vsync_1    <= 1'b0;
        video_hsync_1    <= 1'b0;
        video_x_1        <= 11'd0;
        video_y_1        <= 11'd0;
        gray_image_area_1 <= 1'b0;
        gauss_image_area_1 <= 1'b0;
        equalized_image_area_1 <= 1'b0;
    end
    else begin
        video_de_1       <= I_de;
        video_vsync_1    <= I_vsync;
        video_hsync_1    <= I_hsync;
        video_x_1        <= pixel_x;
        video_y_1        <= pixel_y;
        gray_image_area_1 <= gray_image_area;
        gauss_image_area_1 <= gauss_image_area;
        equalized_image_area_1 <= equalized_image_area;
    end
end

// Histogram banks follow the same capture/display bank ownership. After a
// frame completes, a small state machine converts its CDF into an 8-bit
// equalization LUT. It advances at most 255 extra cycles, avoiding a divider.
reg [17:0] histogram_0 [0:255];
reg [17:0] histogram_1 [0:255];
reg        histogram_clear_bank;
reg        histogram_clear_active;
reg [7:0]  histogram_clear_index;
reg        equalize_build_bank;
reg        equalize_build_active;
reg        equalize_build_advance;
reg        equalize_found_nonzero;
reg [7:0]  equalize_build_index;
reg [7:0]  equalize_level;
reg [17:0] equalize_cdf;
reg [17:0] equalize_cdf_min;
reg [17:0] equalize_denominator;
reg [25:0] equalize_target;
reg [25:0] equalize_threshold;

wire [17:0] equalize_histogram_value = equalize_build_bank ?
                                        histogram_1[equalize_build_index] :
                                        histogram_0[equalize_build_index];
wire [18:0] equalize_cdf_sum = {1'b0, equalize_cdf} +
                                {1'b0, equalize_histogram_value};
wire [17:0] equalize_cdf_next = equalize_cdf_sum[17:0];
wire [17:0] equalize_cdf_delta = equalize_cdf_next - equalize_cdf_min;
wire [25:0] equalize_target_next =
             ({8'd0, equalize_cdf_delta} << 8) -
              {8'd0, equalize_cdf_delta};
wire [17:0] equalize_first_denominator = IMAGE_PIXELS_18 - equalize_cdf_next;

always @(posedge I_pixel_clk or posedge I_pixel_rst) begin
    if(I_pixel_rst) begin
        histogram_clear_bank   <= 1'b0;
        histogram_clear_active <= 1'b1;
        histogram_clear_index  <= 8'd0;
    end
    else begin
        if(pixel_frame_start) begin
            histogram_clear_bank <= capture_complete ? ~capture_bank : capture_bank;
            histogram_clear_active <= 1'b1;
            histogram_clear_index <= 8'd0;

        end
        else begin
            if(histogram_clear_active) begin
                if(histogram_clear_bank)
                    histogram_1[histogram_clear_index] <= 18'd0;
                else
                    histogram_0[histogram_clear_index] <= 18'd0;

                if(histogram_clear_index == 8'hff)
                    histogram_clear_active <= 1'b0;
                else
                    histogram_clear_index <= histogram_clear_index + 1'b1;
            end
            else if(capture_sample) begin
                if(capture_bank)
                    histogram_1[gray_value] <= histogram_1[gray_value] + 1'b1;
                else
                    histogram_0[gray_value] <= histogram_0[gray_value] + 1'b1;
            end

        end
    end
end

always @(posedge I_pixel_clk or posedge I_pixel_rst) begin
    if(I_pixel_rst) begin
        equalize_build_bank      <= 1'b0;
        equalize_build_active    <= 1'b0;
        equalize_build_advance   <= 1'b0;
        equalize_found_nonzero   <= 1'b0;
        equalize_build_index     <= 8'd0;
        equalize_level           <= 8'd0;
        equalize_cdf             <= 18'd0;
        equalize_cdf_min         <= 18'd0;
        equalize_denominator     <= 18'd0;
        equalize_target          <= 26'd0;
        equalize_threshold       <= 26'd0;
        equalize_ready_0         <= 1'b0;
        equalize_ready_1         <= 1'b0;
    end
    else begin
        if(pixel_frame_start && capture_complete) begin
            equalize_build_bank    <= capture_bank;
            equalize_build_active  <= 1'b1;
            equalize_build_advance <= 1'b0;
            equalize_found_nonzero <= 1'b0;
            equalize_build_index   <= 8'd0;
            equalize_level         <= 8'd0;
            equalize_cdf           <= 18'd0;
            equalize_cdf_min       <= 18'd0;
            equalize_denominator   <= 18'd0;
            equalize_target        <= 26'd0;
            equalize_threshold     <= 26'd0;
            if(capture_bank)
                equalize_ready_1 <= 1'b0;
            else
                equalize_ready_0 <= 1'b0;
        end
        else if(equalize_build_active) begin
            if(equalize_build_advance) begin
                if((equalize_level != 8'hff) &&
                   (equalize_target >= equalize_threshold)) begin
                    equalize_level     <= equalize_level + 1'b1;
                    equalize_threshold <= equalize_threshold + equalize_denominator;
                end
                else begin
                    if(equalize_build_bank)
                        equalize_lut_1[equalize_build_index] <= equalize_level;
                    else
                        equalize_lut_0[equalize_build_index] <= equalize_level;
                    equalize_build_advance <= 1'b0;
                    if(equalize_build_index == 8'hff) begin
                        equalize_build_active <= 1'b0;
                        if(equalize_build_bank)
                            equalize_ready_1 <= 1'b1;
                        else
                            equalize_ready_0 <= 1'b1;
                    end
                    else
                        equalize_build_index <= equalize_build_index + 1'b1;
                end
            end
            else if(!equalize_found_nonzero) begin
                equalize_cdf <= equalize_cdf_next;
                if(equalize_histogram_value == 0) begin
                    if(equalize_build_bank)
                        equalize_lut_1[equalize_build_index] <= 8'd0;
                    else
                        equalize_lut_0[equalize_build_index] <= 8'd0;
                end
                else begin
                    equalize_found_nonzero <= 1'b1;
                    equalize_cdf_min       <= equalize_cdf_next;
                    equalize_denominator   <= equalize_first_denominator;
                    equalize_threshold     <= equalize_first_denominator;
                    if(equalize_build_bank)
                        equalize_lut_1[equalize_build_index] <=
                            (equalize_first_denominator == 0) ? equalize_build_index : 8'd0;
                    else
                        equalize_lut_0[equalize_build_index] <=
                            (equalize_first_denominator == 0) ? equalize_build_index : 8'd0;
                end

                if(equalize_build_index == 8'hff) begin
                    equalize_build_active <= 1'b0;
                    if(equalize_build_bank)
                        equalize_ready_1 <= 1'b1;
                    else
                        equalize_ready_0 <= 1'b1;
                end
                else
                    equalize_build_index <= equalize_build_index + 1'b1;
            end
            else if(equalize_denominator == 0) begin
                if(equalize_build_bank)
                    equalize_lut_1[equalize_build_index] <= equalize_build_index;
                else
                    equalize_lut_0[equalize_build_index] <= equalize_build_index;

                if(equalize_build_index == 8'hff) begin
                    equalize_build_active <= 1'b0;
                    if(equalize_build_bank)
                        equalize_ready_1 <= 1'b1;
                    else
                        equalize_ready_0 <= 1'b1;
                end
                else
                    equalize_build_index <= equalize_build_index + 1'b1;
            end
            else begin
                equalize_cdf           <= equalize_cdf_next;
                equalize_target        <= equalize_target_next;
                equalize_build_advance <= 1'b1;
            end
        end
    end
end

wire [10:0] portrait_x_1 = ROTATE_CLOCKWISE ?
                           (V_ACTIVE - 1 - video_y_1) : video_y_1;
wire [10:0] portrait_y_1 = ROTATE_CLOCKWISE ?
                           video_x_1 : (H_ACTIVE - 1 - video_x_1);

wire text0_area = video_de_1 &&
                  (portrait_x_1 >= TEXT_X) && (portrait_x_1 < TEXT_X + TEXT0_CHARS * CHAR_WIDTH) &&
                  (portrait_y_1 >= TEXT0_Y) && (portrait_y_1 < TEXT0_Y + CHAR_HEIGHT);
wire text1_area = video_de_1 &&
                  (portrait_x_1 >= TEXT_X) && (portrait_x_1 < TEXT_X + TEXT1_CHARS * CHAR_WIDTH) &&
                  (portrait_y_1 >= TEXT1_Y) && (portrait_y_1 < TEXT1_Y + CHAR_HEIGHT);
wire text2_area = video_de_1 &&
                  (portrait_x_1 >= TEXT_X) && (portrait_x_1 < TEXT_X + TEXT2_CHARS * CHAR_WIDTH) &&
                  (portrait_y_1 >= TEXT2_Y) && (portrait_y_1 < TEXT2_Y + CHAR_HEIGHT);
wire text_area = text0_area | text1_area | text2_area;
wire background_area = video_de_1 &&
                       (portrait_x_1 >= BG_X_MIN) && (portrait_x_1 < BG_X_MAX) &&
                       (portrait_y_1 >= BG_Y_MIN) && (portrait_y_1 < BG_Y_MAX);

wire [10:0] text_x_rel = portrait_x_1 - TEXT_X;
wire [10:0] text_y_rel = text2_area ? (portrait_y_1 - TEXT2_Y) :
                            text1_area ? (portrait_y_1 - TEXT1_Y) : (portrait_y_1 - TEXT0_Y);
wire [4:0]  char_index = text_x_rel[8:4];
wire [2:0]  glyph_x    = text_x_rel[3:1];
wire [2:0]  glyph_y    = text_y_rel[3:1];

reg [7:0] char_code;
always @* begin
    char_code = 8'h20;
    if(text0_area) begin
        case(char_index)
            5'd0:  char_code = 8'h43;
            5'd1:  char_code = 8'h41;
            5'd2:  char_code = 8'h4d;
            5'd3:  char_code = 8'h3a;
            5'd4:  char_code = 8'h30 + input_fps_tens;
            5'd5:  char_code = 8'h30 + input_fps_ones;
            5'd6:  char_code = 8'h20;
            5'd7:  char_code = 8'h44;
            5'd8:  char_code = 8'h44;
            5'd9:  char_code = 8'h52;
            5'd10: char_code = 8'h3a;
            5'd11: char_code = 8'h30 + fps_tens;
            5'd12: char_code = 8'h30 + fps_ones;
            default: char_code = 8'h20;
        endcase
    end
    else if(text1_area) begin
        case(char_index)
            5'd0:  char_code = 8'h52;
            5'd1:  char_code = 8'h45;
            5'd2:  char_code = 8'h53;
            5'd3:  char_code = 8'h3a;
            5'd4:  char_code = 8'h30 + CW_DIGIT_3;
            5'd5:  char_code = 8'h30 + CW_DIGIT_2;
            5'd6:  char_code = 8'h30 + CW_DIGIT_1;
            5'd7:  char_code = 8'h30 + CW_DIGIT_0;
            5'd8:  char_code = 8'h78;
            5'd9:  char_code = 8'h30 + CH_DIGIT_3;
            5'd10: char_code = 8'h30 + CH_DIGIT_2;
            5'd11: char_code = 8'h30 + CH_DIGIT_1;
            5'd12: char_code = 8'h30 + CH_DIGIT_0;
            default: char_code = 8'h20;
        endcase
    end
    else if(text2_area) begin
        case(char_index)
            5'd0:  char_code = 8'h45;
            5'd1:  char_code = 8'h52;
            5'd2:  char_code = 8'h52;
            5'd3:  char_code = 8'h3a;
            5'd4:  char_code = 8'h30 + error_tens;
            5'd5:  char_code = 8'h30 + error_ones;
            5'd6:  char_code = 8'h20;
            5'd7:  char_code = 8'h46;
            5'd8:  char_code = 8'h49;
            5'd9:  char_code = 8'h46;
            5'd10: char_code = 8'h4f;
            5'd11: char_code = 8'h3a;
            5'd12: char_code = fifo_error_sync ? 8'h31 : 8'h30;
            default: char_code = 8'h20;
        endcase
    end
end

function [4:0] font_row;
    input [7:0] character;
    input [2:0] row;
    begin
        font_row = 5'b00000;
        case(character)
            8'h30: case(row)
                0: font_row=5'b01110; 1: font_row=5'b10001; 2: font_row=5'b10011;
                3: font_row=5'b10101; 4: font_row=5'b11001; 5: font_row=5'b10001;
                6: font_row=5'b01110; default: font_row=5'b00000;
            endcase
            8'h31: case(row)
                0: font_row=5'b00100; 1: font_row=5'b01100; 2: font_row=5'b00100;
                3: font_row=5'b00100; 4: font_row=5'b00100; 5: font_row=5'b00100;
                6: font_row=5'b01110; default: font_row=5'b00000;
            endcase
            8'h32: case(row)
                0: font_row=5'b01110; 1: font_row=5'b10001; 2: font_row=5'b00001;
                3: font_row=5'b00010; 4: font_row=5'b00100; 5: font_row=5'b01000;
                6: font_row=5'b11111; default: font_row=5'b00000;
            endcase
            8'h33: case(row)
                0: font_row=5'b11110; 1: font_row=5'b00001; 2: font_row=5'b00001;
                3: font_row=5'b01110; 4: font_row=5'b00001; 5: font_row=5'b00001;
                6: font_row=5'b11110; default: font_row=5'b00000;
            endcase
            8'h34: case(row)
                0: font_row=5'b00010; 1: font_row=5'b00110; 2: font_row=5'b01010;
                3: font_row=5'b10010; 4: font_row=5'b11111; 5: font_row=5'b00010;
                6: font_row=5'b00010; default: font_row=5'b00000;
            endcase
            8'h35: case(row)
                0: font_row=5'b11111; 1: font_row=5'b10000; 2: font_row=5'b10000;
                3: font_row=5'b11110; 4: font_row=5'b00001; 5: font_row=5'b00001;
                6: font_row=5'b11110; default: font_row=5'b00000;
            endcase
            8'h36: case(row)
                0: font_row=5'b01110; 1: font_row=5'b10000; 2: font_row=5'b10000;
                3: font_row=5'b11110; 4: font_row=5'b10001; 5: font_row=5'b10001;
                6: font_row=5'b01110; default: font_row=5'b00000;
            endcase
            8'h37: case(row)
                0: font_row=5'b11111; 1: font_row=5'b00001; 2: font_row=5'b00010;
                3: font_row=5'b00100; 4: font_row=5'b01000; 5: font_row=5'b01000;
                6: font_row=5'b01000; default: font_row=5'b00000;
            endcase
            8'h38: case(row)
                0: font_row=5'b01110; 1: font_row=5'b10001; 2: font_row=5'b10001;
                3: font_row=5'b01110; 4: font_row=5'b10001; 5: font_row=5'b10001;
                6: font_row=5'b01110; default: font_row=5'b00000;
            endcase
            8'h39: case(row)
                0: font_row=5'b01110; 1: font_row=5'b10001; 2: font_row=5'b10001;
                3: font_row=5'b01111; 4: font_row=5'b00001; 5: font_row=5'b00001;
                6: font_row=5'b01110; default: font_row=5'b00000;
            endcase
            8'h3a: case(row)
                2: font_row=5'b00100; 4: font_row=5'b00100; default: font_row=5'b00000;
            endcase
            8'h41: case(row)
                0: font_row=5'b01110; 1: font_row=5'b10001; 2: font_row=5'b10001;
                3: font_row=5'b11111; 4: font_row=5'b10001; 5: font_row=5'b10001;
                6: font_row=5'b10001; default: font_row=5'b00000;
            endcase
            8'h43: case(row)
                0: font_row=5'b01111; 1: font_row=5'b10000; 2: font_row=5'b10000;
                3: font_row=5'b10000; 4: font_row=5'b10000; 5: font_row=5'b10000;
                6: font_row=5'b01111; default: font_row=5'b00000;
            endcase
            8'h44: case(row)
                0: font_row=5'b11110; 1: font_row=5'b10001; 2: font_row=5'b10001;
                3: font_row=5'b10001; 4: font_row=5'b10001; 5: font_row=5'b10001;
                6: font_row=5'b11110; default: font_row=5'b00000;
            endcase
            8'h45: case(row)
                0: font_row=5'b11111; 1: font_row=5'b10000; 2: font_row=5'b10000;
                3: font_row=5'b11110; 4: font_row=5'b10000; 5: font_row=5'b10000;
                6: font_row=5'b11111; default: font_row=5'b00000;
            endcase
            8'h46: case(row)
                0: font_row=5'b11111; 1: font_row=5'b10000; 2: font_row=5'b10000;
                3: font_row=5'b11110; 4: font_row=5'b10000; 5: font_row=5'b10000;
                6: font_row=5'b10000; default: font_row=5'b00000;
            endcase
            8'h49: case(row)
                0: font_row=5'b11111; 1: font_row=5'b00100; 2: font_row=5'b00100;
                3: font_row=5'b00100; 4: font_row=5'b00100; 5: font_row=5'b00100;
                6: font_row=5'b11111; default: font_row=5'b00000;
            endcase
            8'h4d: case(row)
                0: font_row=5'b10001; 1: font_row=5'b11011; 2: font_row=5'b10101;
                3: font_row=5'b10101; 4: font_row=5'b10001; 5: font_row=5'b10001;
                6: font_row=5'b10001; default: font_row=5'b00000;
            endcase
            8'h4e: case(row)
                0: font_row=5'b10001; 1: font_row=5'b11001; 2: font_row=5'b11001;
                3: font_row=5'b10101; 4: font_row=5'b10011; 5: font_row=5'b10011;
                6: font_row=5'b10001; default: font_row=5'b00000;
            endcase
            8'h4f: case(row)
                0: font_row=5'b01110; 1: font_row=5'b10001; 2: font_row=5'b10001;
                3: font_row=5'b10001; 4: font_row=5'b10001; 5: font_row=5'b10001;
                6: font_row=5'b01110; default: font_row=5'b00000;
            endcase
            8'h50: case(row)
                0: font_row=5'b11110; 1: font_row=5'b10001; 2: font_row=5'b10001;
                3: font_row=5'b11110; 4: font_row=5'b10000; 5: font_row=5'b10000;
                6: font_row=5'b10000; default: font_row=5'b00000;
            endcase
            8'h52: case(row)
                0: font_row=5'b11110; 1: font_row=5'b10001; 2: font_row=5'b10001;
                3: font_row=5'b11110; 4: font_row=5'b10100; 5: font_row=5'b10010;
                6: font_row=5'b10001; default: font_row=5'b00000;
            endcase
            8'h53: case(row)
                0: font_row=5'b01111; 1: font_row=5'b10000; 2: font_row=5'b10000;
                3: font_row=5'b01110; 4: font_row=5'b00001; 5: font_row=5'b00001;
                6: font_row=5'b11110; default: font_row=5'b00000;
            endcase
            8'h78: case(row)
                2: font_row=5'b10001; 3: font_row=5'b01010; 4: font_row=5'b00100;
                5: font_row=5'b01010; 6: font_row=5'b10001; default: font_row=5'b00000;
            endcase
            default: font_row=5'b00000;
        endcase
    end
endfunction

wire [4:0] glyph_row_bits = font_row(char_code, glyph_y);
reg glyph_pixel;
always @* begin
    case(glyph_x)
        3'd0: glyph_pixel = glyph_row_bits[4];
        3'd1: glyph_pixel = glyph_row_bits[3];
        3'd2: glyph_pixel = glyph_row_bits[2];
        3'd3: glyph_pixel = glyph_row_bits[1];
        3'd4: glyph_pixel = glyph_row_bits[0];
        default: glyph_pixel = 1'b0;
    endcase
end

always @(posedge I_pixel_clk or posedge I_pixel_rst) begin
    if(I_pixel_rst) begin
        O_vsync <= 1'b0;
        O_hsync <= 1'b0;
        O_de    <= 1'b0;
        O_data  <= 24'h000000;
    end
    else begin
        O_vsync <= video_vsync_1;
        O_hsync <= video_hsync_1;
        O_de    <= video_de_1;

        if(text_area && glyph_pixel)
            O_data <= 24'hffffff;
        else if(background_area)
            O_data <= 24'h000000;
        else if(!frame_buffer_valid)
            O_data <= 24'h000000;
        else if((portrait_y_1 == PANE1_X - 1) ||
                (portrait_y_1 == PANE2_X - 1))
            O_data <= 24'h00d8ff;
        else if(portrait_y_1 < PANE1_X) begin
            if(gray_image_area_1)
                O_data <= {gray_read_data, gray_read_data, gray_read_data};
            else
                O_data <= 24'h000000;
        end
        else if(portrait_y_1 < PANE2_X) begin
            if(gauss_image_area_1)
                O_data <= {gauss_read_data, gauss_read_data, gauss_read_data};
            else
                O_data <= 24'h000000;
        end
        else if(portrait_y_1 >= PANE2_X) begin
            if(equalized_image_area_1 && equalize_display_ready)
                O_data <= {equalized_read_data, equalized_read_data, equalized_read_data};
            else
                O_data <= 24'h000000;
        end
        else
            O_data <= 24'h000000;
    end
end

endmodule

