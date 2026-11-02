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
/*********legacy_ui_awb***********
在原基础上删去了一些赘余的代码，并且优化了时序，加入BRAM IP核，
让从除法器出来的每一个数据都可以对上相应的像素数据进行增益，使
得它的适用行更加广泛了。
*********************************************************************/

module legacy_ui_awb  #(   
    parameter IMG_HEIGHT = 1080,   // 图像高度参数，默认值为1080
    parameter IMG_WIDTH  = 1920,   // 图像宽度参数，默认值为1920
    parameter DYNAMIC_ENABLE = 1   // 1: dynamic AWB, 0: fixed unity gain
) 
(
    input                   I_clk  ,    // 输入时钟信号
    input                   I_rst_n,    // 输入复位信号，低电平有效

    input                   I_tlast  ,  // 行结束信号
    input                   I_tuser  ,  // 帧开始信号
    input [95:0]            I_tdata  ,  // 输入数据，总共包含4个像素的RGB值，每个像素24位，4*24=96位
    input                   I_tvalid ,  // 输入数据有效信号
    output                  I_tready ,  // 输入数据准备好信号

    output                  O_tlast  ,  // 输出行结束信号
    output                  O_tuser  ,  // 输出帧开始信号
    output [95:0]           O_tdata  ,  // 输出数据
    output                  O_tvalid ,  // 输出数据有效信号
    input                   O_tready    // 输出数据准备好信号
);

/*****************************************************************
                          RGB565转RGB888（未使用部分）                                        
*****************************************************************/

// //RGB565转RGB888的代码（此部分代码被注释掉，未使用）
// wire [4:0]  rgb565_r   = I_st_data[11+:5];
// wire [5:0]  rgb565_g   = I_st_data[5+:6];
// wire [4:0]  rgb565_b   = I_st_data[0+:5];

// wire [23:0] rgb888     = {{rgb565_r[4:0],rgb565_r[2:0]},{rgb565_g[5:0],rgb565_g[1:0]},{rgb565_b[4:0],rgb565_b[2:0]}};

// wire [7:0]  rgb888_r   = rgb888[16+:8];
// wire [7:0]  rgb888_g   = rgb888[8+:8] ;
// wire [7:0]  rgb888_b   = rgb888[0+:8] ;

/*****************************************************************
                          中间信号                                        
*****************************************************************/

  reg         I_tvalid_r0,I_tvalid_r1;			// 输入有效信号的寄存
  reg  [95:0] I_tdata_d0,I_tdata_d1,I_tdata_d2; // 输入数据的寄存


  // 累加RGB通道的数值，用于计算平均值
  reg  [31:0]         sum_r[0:3];
  reg  [31:0]         sum_g[0:3];
  reg  [31:0]         sum_b[0:3];

  
  wire  [95:0]        data_d0 ;		// 延时后的数据
  wire                valid_d0;     // 延时后的有效信号
  wire                I_tuser_r0;   // 延时后的帧开始信号 
                                    
  reg                 I_tuser_r1;   // 帧开始信号的寄存
                                    
  reg   [95:0]        data_d1 ;     // 再次延时后的数据
  reg                 valid_d1;     // 再次延时后的有效信号

  /*****************************************************************
                            平均值计算                                      
*****************************************************************/

	// 对输入数据和有效信号进行寄存，形成流水线
  always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        I_tdata_d0  <= 0;
        I_tdata_d1  <= 0;
        I_tdata_d2  <= 0;
        {I_tvalid_r0,I_tvalid_r1} <= 0;
    end else begin
        I_tdata_d0  <= I_tdata   ;
        I_tdata_d1  <= I_tdata_d0;
        I_tdata_d2  <= I_tdata_d1;
        I_tvalid_r0 <= I_tvalid;
        I_tvalid_r1 <= I_tvalid_r0;
    end
  end
  
  // 将输入数据拆分为4个像素的RGB分量
    wire [7:0] rgb888_r_d0[0:3];
    wire [7:0] rgb888_g_d0[0:3];
    wire [7:0] rgb888_b_d0[0:3];

    assign  rgb888_r_d0[0] = I_tdata_d0[16+:8];
    assign  rgb888_g_d0[0] = I_tdata_d0[8+:8];
    assign  rgb888_b_d0[0] = I_tdata_d0[0+:8];
  
    assign  rgb888_r_d0[1] = I_tdata_d0[40+:8];
    assign  rgb888_g_d0[1] = I_tdata_d0[32+:8];
    assign  rgb888_b_d0[1] = I_tdata_d0[24+:8];
  
    assign  rgb888_r_d0[2] = I_tdata_d0[64+:8];
    assign  rgb888_g_d0[2] = I_tdata_d0[56+:8];
    assign  rgb888_b_d0[2] = I_tdata_d0[48+:8];
  
    assign  rgb888_r_d0[3] = I_tdata_d0[88+:8];
    assign  rgb888_g_d0[3] = I_tdata_d0[80+:8];
    assign  rgb888_b_d0[3] = I_tdata_d0[72+:8];

// 对每个通道的值进行累加，用于计算平均值
  always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n || I_tuser) begin
	  // 复位或行开始信号有效时，清零累加器
      sum_r[0] <= 0;
      sum_g[0] <= 0;
      sum_b[0] <= 0;

      sum_r[1] <= 0;
      sum_g[1] <= 0;
      sum_b[1] <= 0;

      sum_r[2] <= 0;
      sum_g[2] <= 0;
      sum_b[2] <= 0;

      sum_r[3] <= 0;
      sum_g[3] <= 0;
      sum_b[3] <= 0;
    end else if (I_tvalid_r0) begin
	  // 当输入有效时，累加RGB分量的值
      sum_r[0] <= sum_r[0] + rgb888_r_d0[0];
      sum_g[0] <= sum_g[0] + rgb888_g_d0[0];
      sum_b[0] <= sum_b[0] + rgb888_b_d0[0];

      sum_r[1] <= sum_r[1] + rgb888_r_d0[1];
      sum_g[1] <= sum_g[1] + rgb888_g_d0[1];
      sum_b[1] <= sum_b[1] + rgb888_b_d0[1];

      sum_r[2] <= sum_r[2] + rgb888_r_d0[2];
      sum_g[2] <= sum_g[2] + rgb888_g_d0[2];
      sum_b[2] <= sum_b[2] + rgb888_b_d0[2];

      sum_r[3] <= sum_r[3] + rgb888_r_d0[3];
      sum_g[3] <= sum_g[3] + rgb888_g_d0[3];
      sum_b[3] <= sum_b[3] + rgb888_b_d0[3];
    end
  end



  /*****************************************************************
                           除法运算                                        
*****************************************************************/
  // 定义除法器的输出信号
  wire [47:0] dout_R[3:0];
  wire [47:0] dout_B[3:0];

  wire done[3:0];
  // 提取除法器的输出数据，用于后续增益计算
  wire [47:0] in_r_x1;
  wire [47:0] in_b_x1;
  assign in_r_x1 = dout_R[0][47:0];
  assign in_b_x1 = dout_B[0][47:0];


  wire [47:0] in_r_x2;
  wire [47:0] in_b_x2;
  assign in_r_x2 = dout_R[1][47:0];
  assign in_b_x2 = dout_B[1][47:0];


  wire [47:0] in_r_x3;
  wire [47:0] in_b_x3;
  assign in_r_x3 = dout_R[2][47:0];
  assign in_b_x3 = dout_B[2][47:0];


  wire [47:0] in_r_x4;
  wire [47:0] in_b_x4;
  assign in_r_x4 = dout_R[3][47:0];
  assign in_b_x4 = dout_B[3][47:0];
    

/*****************************************************************
                   IP 调用                                    
*****************************************************************/
    //为了保证合理的延迟，这里使用了除法器

  genvar i;
  generate
    for (i = 0; i < 4; i = i + 1) begin : div_gen
	 divider X_div_gen_G_R (
         .clk(I_clk),  					// input wire aclk
         .rst(!I_rst_n),                    
         .start(I_tvalid_r1),              // 输入除数有效信号
         .denominator(sum_r[i]),  			// 输入除数数据，R通道的累加值
         .numerator({sum_g[i],16'd0}),  	// 输入被除数数据，G通道的累加值，扩展16位
         .quotient(dout_R[i]),  			// 输出数据，G/R的比值
         .done(done[i])                    // 输出数据有效信号
     );
	
     divider X_div_gen_G_B (
         .clk(I_clk),  					// input wire aclk
         .rst(!I_rst_n),                    
         .start(I_tvalid_r1),              // 输入除数有效信号
         .denominator(sum_b[i]),  			// 输入除数数据，R通道的累加值
         .numerator({sum_g[i],16'd0}),  	// 输入被除数数据，G通道的累加值，扩展16位
         .quotient(dout_B[i]),  			// 输出数据，G/R的比值
         .done()                           // 输出数据有效信号
     );
	
	
	
    //ui_divider X_ui_div_gen_G_R (
    //    .aclk						(I_clk),  				// input wire aclk
    //    .aresetn					(!I_rst_n),                    
	//    .s_axis_divisor_tdata		(sum_r[i]),  			// 输入除数数据，R通道的累加值
    //    .s_axis_divisor_tvalid	(I_tvalid_r1),          // 输入除数有效信号
    //    .s_axis_dividend_tdata	({sum_g[i],16'd0}),  	// 输入被除数数据，G通道的累加值，扩展16位
    //    .s_axis_dividend_tvalid	(I_tvalid_r1),  	    // 输入被除数有效信号
    //    .m_axis_dout_tdata		(dout_R[i]),  			// 输出数据，G/R的比值
    //    .m_axis_dout_tvalid		(done[i])               // 输出数据有效信号
    //);
	//
    //ui_divider X_ui_divide_G_B_ (
    //    .aclk						(I_clk),  				// input wire aclk	
    //    .aresetn					(!I_rst_n),                           
    //    .s_axis_divisor_tdata		(sum_b[i]),             // 输入除数数据，R通道的累加值
    //    .s_axis_divisor_tvalid	(I_tvalid_r1),          // 输入除数有效信号
    //    .s_axis_dividend_tdata	({sum_g[i],16'd0}),  	// 输入被除数数据，G通道的累加值，扩展16位
    //    .s_axis_dividend_tvalid	(I_tvalid_r1),  	    // 输入被除数有效信号
    //    .m_axis_dout_tdata		(dout_B[i]),  			// 输出数据，G/R的比值
    //    .m_axis_dout_tvalid()                             // 输出数据有效信号
    // );
    end
  endgenerate
     
	// 信号延迟模块，用于同步信号，延迟50个时钟周期
legacy_ui_signal_delay #(
    .IMG_HEIGHT (IMG_HEIGHT	),
    .IMG_WIDTH  (IMG_WIDTH 	),
    .DATA_WIDTH (96  		),	// 数据位宽为96位
    .DELAY_CYCLE(50		 	)   // 延迟50个时钟周期
)X_ui_signal_delay (           
    .I_clk  	(I_clk  	), // 输入时钟信号
    .I_rst_n	(I_rst_n	), // 输入复位信号
    .I_tuser	(I_tuser	), // 输入帧开始信号
    .I_valid	(I_tvalid_r1), // 输入数据有效信号
    .I_data 	(I_tdata_d1 ), // 输入数据
    .O_valid	(valid_d0   ), // 输出数据有效信号
    .O_data 	(data_d0    ), // 输出数据
    .O_tuser	(I_tuser_r0 )  // 输出帧开始信号
);

/*****************************************************************
                            增益计算                                      
*****************************************************************/

    reg  [19:0]   in_r_r1;
    reg  [19:0]   in_b_r1;

    reg  [19:0]   in_r_r2;
    reg  [19:0]   in_b_r2;

    reg  [19:0]   in_r_r3;
    reg  [19:0]   in_b_r3;

    reg  [19:0]   in_r_r4;
    reg  [19:0]   in_b_r4;
	
	// 计算增益，防止增益过大溢出，限制在0xFFFFF
    always @(posedge I_clk or negedge I_rst_n)begin 
        if(!I_rst_n || I_tuser)begin
            in_r_r1 <= 20'h10000;
            in_b_r1 <= 20'h10000;
        end
        else if(done[0] && DYNAMIC_ENABLE)begin
            if(|in_r_x1[47:20])    // 判断高位是否有1，防止溢出
                in_r_r1 <= 20'hfffff;
            else 
                in_r_r1 <= in_r_x1[19:0];
            if(|in_b_x1[47:20])
                in_b_r1 <= 20'hfffff;
            else 
                in_b_r1 <= in_b_x1[19:0];
        end
    end

    always @(posedge I_clk or negedge I_rst_n)begin 
        if(!I_rst_n|| I_tuser)begin
            in_r_r2 <= 20'h10000;
            in_b_r2 <= 20'h10000;
        end
        else if(done[1] && DYNAMIC_ENABLE)begin
            if(|in_r_x2[47:20])
                in_r_r2 <= 20'hfffff;
            else 
                in_r_r2 <= in_r_x2[19:0];
            if(|in_b_x2[47:20])
                in_b_r2 <= 20'hfffff;
            else 
                in_b_r2 <= in_b_x2[19:0];
        end
    end



    always @(posedge I_clk or negedge I_rst_n)begin 
        if(!I_rst_n || I_tuser)begin
            in_r_r3 <= 20'h10000;
            in_b_r3 <= 20'h10000;
        end
        else if(done[2] && DYNAMIC_ENABLE)begin
            if(|in_r_x3[47:20])
                in_r_r3 <= 20'hfffff;
            else 
                in_r_r3 <= in_r_x3[19:0];
            if(|in_b_x3[47:20])
                in_b_r3 <= 20'hfffff;
            else 
                in_b_r3 <= in_b_x3[19:0];
        end
    end




    always @(posedge I_clk or negedge I_rst_n)begin 
        if(!I_rst_n || I_tuser)begin
            in_r_r4 <= 20'h10000;
            in_b_r4 <= 20'h10000;
        end
        else if(done[3] && DYNAMIC_ENABLE)begin
            if(|in_r_x4[47:20])
                in_r_r4 <= 20'hfffff;
            else 
                in_r_r4 <= in_r_x4[19:0];
            if(|in_b_x4[47:20])
                in_b_r4 <= 20'hfffff;
            else 
                in_b_r4 <= in_b_x4[19:0];
        end
    end
    // 信号同步，延迟一级
    always @(posedge I_clk or negedge I_rst_n) begin
      if (!I_rst_n) begin
          valid_d1 <= 0;
          data_d1  <= 0;
          I_tuser_r1 <= 0;
      end else begin
          valid_d1 <= valid_d0;
          data_d1  <= data_d0 ;
          I_tuser_r1 <= I_tuser_r0;
      end
    end
/*****************************************************************
                           像素值计算                                       
*****************************************************************/

    reg [27:0] R_new_r1;
    reg [27:0] G_new_r1;
    reg [27:0] B_new_r1;

    reg [27:0] R_new_r2;
    reg [27:0] G_new_r2;
    reg [27:0] B_new_r2;

    reg [27:0] R_new_r3;
    reg [27:0] G_new_r3;
    reg [27:0] B_new_r3;

    reg [27:0] R_new_r4;
    reg [27:0] G_new_r4;
    reg [27:0] B_new_r4;


    wire   [7:0] rgb888_r_d1[0:3];
    wire   [7:0] rgb888_g_d1[0:3];
    wire   [7:0] rgb888_b_d1[0:3];

    assign  rgb888_r_d1[0] = data_d1[16+:8];
    assign  rgb888_g_d1[0] = data_d1[8+:8];
    assign  rgb888_b_d1[0] = data_d1[0+:8];

    assign  rgb888_r_d1[1] = data_d1[40+:8];
    assign  rgb888_g_d1[1] = data_d1[32+:8];
    assign  rgb888_b_d1[1] = data_d1[24+:8];

    assign  rgb888_r_d1[2] = data_d1[64+:8];
    assign  rgb888_g_d1[2] = data_d1[56+:8];
    assign  rgb888_b_d1[2] = data_d1[48+:8];

    assign  rgb888_r_d1[3] = data_d1[88+:8];
    assign  rgb888_g_d1[3] = data_d1[80+:8];
    assign  rgb888_b_d1[3] = data_d1[72+:8];
	
	// 计算新的RGB值，应用增益
    always @(posedge I_clk or negedge I_rst_n)begin 
        if(!I_rst_n)begin
            R_new_r1 <= 0;
            G_new_r1 <= 0;
            B_new_r1 <= 0;

            R_new_r2 <= 0;
            G_new_r2 <= 0;
            B_new_r2 <= 0;

            R_new_r3 <= 0;
            G_new_r3 <= 0;
            B_new_r3 <= 0;

            R_new_r4 <= 0;
            G_new_r4 <= 0;
            B_new_r4 <= 0;
        end
        else if(valid_d1) begin
            R_new_r1 <= in_r_r1 * rgb888_r_d1[0];
            G_new_r1 <=           rgb888_g_d1[0];
            B_new_r1 <= in_b_r1 * rgb888_b_d1[0];

            R_new_r2 <= in_r_r2 * rgb888_r_d1[1];
            G_new_r2 <=           rgb888_g_d1[1];
            B_new_r2 <= in_b_r2 * rgb888_b_d1[1];

            R_new_r3 <= in_r_r3 * rgb888_r_d1[2];
            G_new_r3 <=           rgb888_g_d1[2];
            B_new_r3 <= in_b_r3 * rgb888_b_d1[2];

            R_new_r4 <= in_r_r4 * rgb888_r_d1[3];
            G_new_r4 <=           rgb888_g_d1[3];
            B_new_r4 <= in_b_r4 * rgb888_b_d1[3];
        end
    end

/*****************************************************************
                            像素值截断                                      
*****************************************************************/

    wire [7:0] R_new_x1;
    wire [7:0] G_new_x1;
    wire [7:0] B_new_x1;

    wire [7:0] R_new_x2;
    wire [7:0] G_new_x2;
    wire [7:0] B_new_x2;

    wire [7:0] R_new_x3;
    wire [7:0] G_new_x3;
    wire [7:0] B_new_x3;

    wire [7:0] R_new_x4;
    wire [7:0] G_new_x4;
    wire [7:0] B_new_x4;
	
	// 对新的像素值进行截断，防止溢出
    assign R_new_x1 = (R_new_r1[27:24])?255:R_new_r1[23:16];
    assign G_new_x1 =  G_new_r1;
    assign B_new_x1 = (B_new_r1[27:24])?255:B_new_r1[23:16];

    assign R_new_x2 = (R_new_r2[27:24])?255:R_new_r2[23:16];
    assign G_new_x2 =  G_new_r2;
    assign B_new_x2 = (B_new_r2[27:24])?255:B_new_r2[23:16];

    assign R_new_x3 = (R_new_r3[27:24])?255:R_new_r3[23:16];
    assign G_new_x3 =  G_new_r3;
    assign B_new_x3 = (B_new_r3[27:24])?255:B_new_r3[23:16];

    assign R_new_x4 = (R_new_r4[27:24])?255:R_new_r4[23:16];
    assign G_new_x4 =  G_new_r4;
    assign B_new_x4 = (B_new_r4[27:24])?255:B_new_r4[23:16];
/*****************************************************************
                           ͬ同步信号                                      
*****************************************************************/

    reg valid_d2,I_tuser_r2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin
            valid_d2 <= 0;
            I_tuser_r2 <= 0;
        end
        else begin
            valid_d2 <= valid_d1;
            I_tuser_r2 <= I_tuser_r1;
        end
    end

	// 输出信号的生成
    assign  O_tlast  = (valid_d1 == 0) && (valid_d2 == 1);   // 行结束信号
    assign  O_tuser  = I_tuser_r2 ;                          // 帧开始信号
    assign  O_tvalid = valid_d2;                             // 输出有效信号
	
	// 输出数据，由四个像素的数据拼接而成
    assign  O_tdata = O_tvalid?{R_new_x4,G_new_x4,B_new_x4,
                       R_new_x3,G_new_x3,B_new_x3,
                       R_new_x2,G_new_x2,B_new_x2,
                       R_new_x1,G_new_x1,B_new_x1}:0;
    // assign O_t_data = {R_new[7-:5],G_new[7-:6],B_new[7-:5]};
	// 输入准备好信号，直接连接到输出准备好信号
    assign  I_tready = O_tready;
 
endmodule




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
/*********legacy_ui_signal_delay***********
*********************************************************************/
module legacy_ui_signal_delay #(
    parameter IMG_HEIGHT = 1080,
    parameter IMG_WIDTH  = 1920,
    parameter DATA_WIDTH = 96,
    parameter DELAY_CYCLE = 50
) (
    input                        I_clk,	   // 输入时钟信号
    input                        I_rst_n,  // 输入复位信号，低电平有效
    input                        I_tuser,  // 输入tuser信号，帧起始标志 
    input  wire                  I_valid,  // 输入数据有效信号          
    input  wire [DATA_WIDTH-1:0] I_data,   // 输入数据总线，宽度为33位  
    output wire                  O_valid,  // 输出数据有效信号          
    output wire [DATA_WIDTH-1:0] O_data ,  // 输出数据总线，宽度为33位  
    output wire                  O_tuser   // 输出tuser信号，帧起始标志  
);

    wire        rd_en; 

    reg  [10:0] addra; 
    reg  [10:0] addrb; 


    reg  [13:0] h_cnt;
    reg  [13:0] v_cnt;
    reg  [13:0] rd_cnt;
    
    reg  [DATA_WIDTH-1:0] I_data_r;
    reg         rd_valid,I_valid_r;

    localparam IMG_WIDTH_4x = (IMG_WIDTH >> 2);
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n ) begin
            I_valid_r <= 0;
            I_data_r  <= 0;
        end
        else begin
            I_valid_r <= I_valid;
            I_data_r  <= I_data;
        end
    end
	
	//行列计数器
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n || I_tuser) begin
            h_cnt <= 0;
            v_cnt <= 0;
        end
        else begin
            h_cnt <= I_valid_r ? ((h_cnt == IMG_WIDTH_4x-1) ? 0 : h_cnt + 1) : h_cnt;
            v_cnt <= I_valid_r &&(h_cnt == IMG_WIDTH_4x-1) ? ((v_cnt == IMG_HEIGHT - 1) ? 0 : v_cnt + 1) : v_cnt;
        end
    end
    
	//读有效信号
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n || I_tuser) begin
            rd_valid <= 0;
        end
        else if(h_cnt == DELAY_CYCLE - 3)begin
            rd_valid <= 1;
        end
        else if(rd_cnt == IMG_WIDTH_4x - 1) //一次都有效开始之后，读IMG_WIDTH_4x个数据即可
            rd_valid <= 0;
    end
	
	 //读数据计数
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n || I_tuser) begin
            rd_cnt <= 0;
        end
        else if(rd_cnt == IMG_WIDTH_4x )
            rd_cnt <= 0;
        else if(rd_valid)begin
            rd_cnt <= rd_cnt + 1;
        end
    end
	
	//写地址
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n || I_tuser) begin
            addra <= 0;
        end else if (I_valid_r) begin
            addra <= (addra == IMG_WIDTH_4x - 1) ? 'b0 : addra + 1'b1;
        end
    end

	//读地址
    always @(posedge I_clk or negedge I_rst_n) begin
      if (!I_rst_n || I_tuser) begin
        addrb <= 0;
      end else begin
        addrb <= rd_valid ? (addrb == IMG_WIDTH_4x - 1) ? 'b0 : addrb + 1'b1 : addrb;
      end
    end
    
	//为了和输出的数据O_data同步，进行打拍处理
    reg rd_valid_d;
    always @(posedge I_clk or negedge I_rst_n) begin
      if (!I_rst_n) begin
        rd_valid_d <= 0;
      end else begin
        rd_valid_d <= rd_valid;
      end
    end
    assign O_valid = rd_valid_d;
    assign O_tuser = (v_cnt == 0) && (rd_cnt == 1);

    ui_ram_awb_delay_signal X_ui_ram_awb_delay_signal (
      .clka (I_clk   ),  // input wire clka
      .wea  (I_valid_r),  // input wire [0 : 0] wea
      .addra(addra   ),  // input wire [10 : 0] addra
      .dia  (I_data_r ),  // input wire [95 : 0] dina
      .clkb (I_clk   ),  // input wire clkb
      .addrb(addrb   ),  // input wire [10 : 0] addrb
      .dob  (O_data  )   // output wire [95 : 0] doutb
    );


endmodule

/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
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
/*********legacy_ui_BLC 黑电平矫正********************************************
--版本号1.0  
*****************************************************************/
`timescale 1ns / 1ps

module legacy_ui_BLC #(
    parameter [9:0]  Black_level_offset_r0 = 15,
    parameter [9:0]  Black_level_offset_r1 = 15,
    parameter [9:0]  Black_level_offset_r2 = 15,
    parameter [9:0]  Black_level_offset_r3 = 15
)
(
    input                   I_clk  	  ,
    input                   I_rst_n	  ,

    input                   I_tlast   ,
    input                   I_tuser   ,
    input  [39:0]           I_tdata   ,
    input                   I_tvalid  , 
    input  [9:0]            I_tdest   ,
    output                  I_tready  ,

    output                  O_tlast   ,
    output                  O_tuser   ,
    output [39:0]           O_tdata   ,
    output                  O_tvalid  ,
    output [9:0]            O_tdest   ,
    input                   O_tready  

);


    reg                   I_tlast_r    ;
    reg                   I_tuser_r    ;
    reg                   I_tvalid_r   ;
	
    reg  [9:0]  		  data_out[3:0];

    wire [9:0]  I_blc_data[3:0];
    wire [9:0]  black_level_offset[3:0] ;
	
	
    assign black_level_offset[0] = Black_level_offset_r0;
    assign black_level_offset[1] = Black_level_offset_r1;
    assign black_level_offset[2] = Black_level_offset_r2;
    assign black_level_offset[3] = Black_level_offset_r3;


    assign I_blc_data[0] = I_tdata[9:0]  ;
    assign I_blc_data[1] = I_tdata[19:10];
    assign I_blc_data[2] = I_tdata[29:20];
    assign I_blc_data[3] = I_tdata[39:30];
	
    assign  O_tlast      = I_tlast_r;   
    assign  O_tuser      = I_tuser_r;   
    assign  O_tvalid     = I_tvalid_r;

    assign  O_tdata      = {data_out[3],data_out[2],data_out[1],data_out[0]};
    assign  I_tready     = O_tready;

    
    genvar i;
    generate for(i=0;i<4;i=i+1)
        begin:
        BLACK_LEVEL_OFFSET
        always @(posedge I_clk)begin 
            if (I_tvalid) begin
                // 执行黑电平矫正，防止出现负数
                if (I_blc_data[i] > black_level_offset[i]) begin
                    data_out[i] <= I_blc_data[i] - black_level_offset[i];
                end 
                else begin
                    data_out[i] <= 10'd0; // 将结果裁剪为0，防止负数
                end
            end
        end
        end
    endgenerate


    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            {I_tlast_r,I_tuser_r,I_tvalid_r} <= 0;
        else begin
            I_tlast_r <= I_tlast;
            I_tuser_r <= I_tuser;
            I_tvalid_r <= I_tvalid;
        end
    end



endmodule

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
/*********legacy_ui_Brightness_adj ********************************************
--亮度调节(Brightness)
--版本号1.0  
*****************************************************************/
module legacy_ui_Brightness_adj #(
    parameter  BRIGHTNESS_ADD   = 20,
    parameter  BRIGHTNESS_MINUS = 0
)
(
    input                   I_clk    ,
    input                   I_rst_n  ,

    input                   I_tlast  ,
    input                   I_tuser  ,
    input  [95:0]           I_tdata  ,
    input                   I_tvalid , 
    output                  I_tready ,

    output                  O_tlast  ,
    output                  O_tuser  ,
    output [95:0]           O_tdata  ,
    output                  O_tvalid ,
    input                   O_tready
);

/*****************************************************************
                        24deta to RGB888                                        
*****************************************************************/
    reg             I_tlast_r    ;
    reg             I_tuser_r    ;
    reg             I_tvalid_r   ;

    wire [23:0] I_tdata_r1 = I_tdata[23:0] ;
    wire [23:0] I_tdata_r2 = I_tdata[47:24];
    wire [23:0] I_tdata_r3 = I_tdata[71:48];
    wire [23:0] I_tdata_r4 = I_tdata[95:72];

    wire [7:0]  rgb888_r[3:0];
    wire [7:0]  rgb888_g[3:0];
    wire [7:0]  rgb888_b[3:0];

    reg  [9:0]  R_d[3:0];
    reg  [9:0]  G_d[3:0];
    reg  [9:0]  B_d[3:0];

    wire  [7:0]  R[3:0];
    wire  [7:0]  G[3:0];
    wire  [7:0]  B[3:0];

    assign   rgb888_r[0] = I_tdata_r1[16+:8];
    assign   rgb888_g[0] = I_tdata_r1[8+:8] ;
    assign   rgb888_b[0] = I_tdata_r1[0+:8] ;

    assign   rgb888_r[1] = I_tdata_r2[16+:8];
    assign   rgb888_g[1] = I_tdata_r2[8+:8] ;
    assign   rgb888_b[1] = I_tdata_r2[0+:8] ;

    assign   rgb888_r[2] = I_tdata_r3[16+:8];
    assign   rgb888_g[2] = I_tdata_r3[8+:8] ;
    assign   rgb888_b[2] = I_tdata_r3[0+:8] ;

    assign   rgb888_r[3] = I_tdata_r4[16+:8];
    assign   rgb888_g[3] = I_tdata_r4[8+:8] ;
    assign   rgb888_b[3] = I_tdata_r4[0+:8] ;

/*****************************************************************
                           数据计算                                          
*****************************************************************/
    
    generate  
	genvar i ;
			for (i = 0;i<4 ;i=i+1 ) begin :top
        
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
           {R_d[i],G_d[i],B_d[i]} <= 0;
        end
        else if(I_tvalid)begin
            R_d[i] <= rgb888_r[i] + BRIGHTNESS_ADD - BRIGHTNESS_MINUS;
            G_d[i] <= rgb888_g[i] + BRIGHTNESS_ADD - BRIGHTNESS_MINUS;
            B_d[i] <= rgb888_b[i] + BRIGHTNESS_ADD - BRIGHTNESS_MINUS;
        end
    end

    assign R[i] = (R_d[i][9])?0:(R_d[i][8])?255:R_d[i][7:0];
    assign G[i] = (G_d[i][9])?0:(G_d[i][8])?255:G_d[i][7:0];
    assign B[i] = (B_d[i][9])?0:(B_d[i][8])?255:B_d[i][7:0];
       end
    endgenerate

/*****************************************************************
                          同步信号                                          
*****************************************************************/


    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            {I_tlast_r,I_tuser_r,I_tvalid_r} <= 0;
        else begin
            I_tlast_r <= {I_tlast_r,I_tlast};
            I_tuser_r <= {I_tuser_r,I_tuser};
            I_tvalid_r <= {I_tvalid_r,I_tvalid};
        end
    end


    assign  O_tlast  = I_tlast_r;   
    assign  O_tuser  = I_tuser_r;   
    assign  O_tvalid = I_tvalid_r;

    assign O_tdata = {R[3],G[3],B[3],
                      R[2],G[2],B[2],
                      R[1],G[1],B[1],
                      R[0],G[0],B[0]};

    assign I_tready = O_tready;

endmodule



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
/*********legacy_ui_Contrast_adj ********************************************
--对比度调节(Contrast)
--版本号1.0   
*****************************************************************/

module legacy_ui_Contrast_adj #(
    parameter  contrast_level   = 160 //对比度调节因子，定点数表示，128对应1.0
)
(
    input                   I_clk  	 ,
    input                   I_rst_n	 ,

    input                   I_tlast  ,
    input                   I_tuser  ,
    input  [95:0]           I_tdata  ,
    input                   I_tvalid , 
    output                  I_tready ,

    output                  O_tlast  ,
    output                  O_tuser  ,
    output [95:0]           O_tdata  ,
    output                  O_tvalid ,
    input                   O_tready
);

/*****************************************************************
                        24deta to RGB888                                        
*****************************************************************/
    reg  [2:0]          I_tlast_r ;
    reg  [2:0]          I_tuser_r ;
    reg  [2:0]          I_tvalid_r;

    wire [23:0] I_tdata_r1 = I_tdata[23:0] ;
    wire [23:0] I_tdata_r2 = I_tdata[47:24];
    wire [23:0] I_tdata_r3 = I_tdata[71:48];
    wire [23:0] I_tdata_r4 = I_tdata[95:72];

    wire [7:0]  rgb888_r[3:0];
    wire [7:0]  rgb888_g[3:0];
    wire [7:0]  rgb888_b[3:0];

    reg  [9:0]  R_d[3:0];
    reg  [9:0]  G_d[3:0];
    reg  [9:0]  B_d[3:0];

    wire  [7:0]  R[3:0];
    wire  [7:0]  G[3:0];
    wire  [7:0]  B[3:0];

    reg  [15:0] pixel_shifted_R[3:0];
    reg  [15:0] pixel_shifted_G[3:0];
    reg  [15:0] pixel_shifted_B[3:0];

    reg  [15:0] temp_value_R[3:0];
    reg  [15:0] temp_value_G[3:0];
    reg  [15:0] temp_value_B[3:0];


    assign   rgb888_r[0] = I_tdata_r1[16+:8];
    assign   rgb888_g[0] = I_tdata_r1[8+:8] ;
    assign   rgb888_b[0] = I_tdata_r1[0+:8] ;

    assign   rgb888_r[1] = I_tdata_r2[16+:8];
    assign   rgb888_g[1] = I_tdata_r2[8+:8] ;
    assign   rgb888_b[1] = I_tdata_r2[0+:8] ;

    assign   rgb888_r[2] = I_tdata_r3[16+:8];
    assign   rgb888_g[2] = I_tdata_r3[8+:8] ;
    assign   rgb888_b[2] = I_tdata_r3[0+:8] ;

    assign   rgb888_r[3] = I_tdata_r4[16+:8];
    assign   rgb888_g[3] = I_tdata_r4[8+:8] ;
    assign   rgb888_b[3] = I_tdata_r4[0+:8] ;


/*****************************************************************
                      数据计算                                         
*****************************************************************/
    
    
    generate  
	genvar i ;
			for (i = 0;i<4 ;i=i+1 ) begin : top
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            pixel_shifted_R[i] <= 0;
            pixel_shifted_G[i] <= 0;
            pixel_shifted_B[i] <= 0;
        end
        else if(I_tvalid)begin
            pixel_shifted_R[i] <= {8'd0, rgb888_r[i]} - 16'd128;
            pixel_shifted_G[i] <= {8'd0, rgb888_g[i]} - 16'd128;
            pixel_shifted_B[i] <= {8'd0, rgb888_b[i]} - 16'd128;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            temp_value_R[i] <= 0;
            temp_value_G[i] <= 0;
            temp_value_B[i] <= 0;
        end
        else if(I_tvalid_r[0])begin
            temp_value_R[i] <= (pixel_shifted_R[i] * contrast_level)>>7;// 由于 contrast_level 是定点数（Q0.7 格式），需要右移7位
            temp_value_G[i] <= (pixel_shifted_G[i] * contrast_level)>>7;
            temp_value_B[i] <= (pixel_shifted_B[i] * contrast_level)>>7;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            R_d[i] <= 0;
            G_d[i] <= 0;
            B_d[i] <= 0;
        end
        else if(I_tvalid_r[1])begin
            R_d[i] <= temp_value_R[i] + 16'd128;// 由于 contrast_level 是定点数（Q0.7 格式），需要右移7位
            G_d[i] <= temp_value_G[i] + 16'd128;
            B_d[i] <= temp_value_B[i] + 16'd128;
        end
    end

    assign  R[i] = (R_d[i][9])?0:(R_d[i][8])?255:R_d[i][7:0];
    assign  G[i] = (G_d[i][9])?0:(G_d[i][8])?255:G_d[i][7:0];
    assign  B[i] = (B_d[i][9])?0:(B_d[i][8])?255:B_d[i][7:0];

       end
    endgenerate
/*****************************************************************
                             信号同步                                         
*****************************************************************/


    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            {I_tlast_r,I_tuser_r,I_tvalid_r} <= 0;
        else begin
            I_tlast_r <= {I_tlast_r[1:0],I_tlast};
            I_tuser_r <= {I_tuser_r[1:0],I_tuser};
            I_tvalid_r <= {I_tvalid_r[1:0],I_tvalid};
        end
    end


    assign  O_tlast  = I_tlast_r[2];   
    assign  O_tuser  = I_tuser_r[2];   
    assign  O_tvalid = I_tvalid_r[2];

    assign O_tdata = {R[3],G[3],B[3],
                      R[2],G[2],B[2],
                      R[1],G[1],B[1],
                      R[0],G[0],B[0]};

    assign I_tready = O_tready;
endmodule




/*****************************************************************
Company : Nanjing Weiku Robot Technology Co., Ltd.
Brand   : VLKUS
Technical forum:www.uisrc.com
@Author      :   XiaoQingquan 
@Time        :   2024/09/18 
@Description :   
*****************************************************************/

module legacy_ui_data128_96 (

    input  wire [127:0] I_tdata,
    output wire [ 95:0] O_tdata
);

  assign O_tdata = {I_tdata[119:96], I_tdata[87:64], I_tdata[55:32], I_tdata[23:0]};

endmodule

/*****************************************************************
Company : Nanjing Weiku Robot Technology Co., Ltd.
Brand   : VLKUS
Technical forum:www.uisrc.com
@Author      :   XiaoQingquan 
@Time        :   2024/09/18 
@Description :   
*****************************************************************/

module legacy_ui_data96_128 (

    input wire [95:0] I_tdata,

    output wire [127:0] O_tdata

);

  assign O_tdata = {
    {8'd0}, I_tdata[95:72], {8'd0}, I_tdata[71:48], {8'd0}, I_tdata[47:24], {8'd0}, I_tdata[23:0]
  };
endmodule


/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
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
/*********legacy_ui_bilinear_interpolation ******************************
由于RGGB和GBRG的Bayer格式中的三元操作符的条件判断分支是颠倒的，
                 导致在需要插值的地方使用了原始值，在有原始值的地方进行了错误的
                 平均，现在重写修改了此处，让其正确的去进行平均。
--版本号1.0  
*****************************************************************/

module legacy_ui_bilinear_interpolation #(
    parameter BAYER_MODE = "BGGR"
)(
    input             I_clk            ,
    input             I_rst_n          ,

    //input
    input             I_tlast          ,
    input             I_tuser          ,
    input             I_tvalid         ,
    output            I_tready         ,
  
    input             bayer_ypos       ,
    input   [95:0]    matrix_last_line ,
    input   [95:0]    matrix_cur_line  ,
    input   [95:0]    matrix_next_line ,
  
    //output
    output            O_tlast         ,
    output            O_tuser         ,
    output [127 : 0]  O_tdata         ,
    output            O_tvalid        ,
    input             O_tready

);

/*********************************************************
                  function 声明
*********************************************************/
// calculate the data's bit width
function integer clog2b(
    input integer depth
);
    begin
        for(clog2b=0; depth>0; clog2b=clog2b+1)begin
            depth = depth >> 1;
        end
    end    
endfunction

/*********************************************************
                      RAW格式
*********************************************************/
// bayer mode 
////bayer格式
localparam RGGB = "RGGB";
localparam BGGR = "BGGR";
localparam GBRG = "GBRG";
localparam GRBG = "GRBG";



/*********************************************************
                       reg 信号声明
*********************************************************/
reg         bayer_ypos_r0,  bayer_ypos_r1;

reg [9:0]   r0_matrix_plus, g0_matrix_plus, b0_matrix_plus ;
reg [9:0]   r1_matrix_plus, g1_matrix_plus, b1_matrix_plus ;
reg [9:0]   r2_matrix_plus, g2_matrix_plus, b2_matrix_plus ;
reg [9:0]   r3_matrix_plus, g3_matrix_plus, b3_matrix_plus ;
// -----------------------------------------------------------------

reg [8:0]   r0_sum_part0, r0_sum_part1 ;
reg [8:0]   r1_sum_part0, r1_sum_part1 ;
reg [8:0]   r2_sum_part0, r2_sum_part1 ;
reg [8:0]   r3_sum_part0, r3_sum_part1 ;

reg [8:0]   g0_sum_part0, g0_sum_part1 ;
reg [8:0]   g1_sum_part0, g1_sum_part1 ;
reg [8:0]   g2_sum_part0, g2_sum_part1 ;
reg [8:0]   g3_sum_part0, g3_sum_part1 ;

reg [8:0]   b0_sum_part0, b0_sum_part1 ;
reg [8:0]   b1_sum_part0, b1_sum_part1 ;
reg [8:0]   b2_sum_part0, b2_sum_part1 ;
reg [8:0]   b3_sum_part0, b3_sum_part1 ;

// -----------------------------------------------------------------
reg [8:0]   r0_mean, g0_mean, b0_mean ;
reg [8:0]   r1_mean, g1_mean, b1_mean ;
reg [8:0]   r2_mean, g2_mean, b2_mean ;
reg [8:0]   r3_mean, g3_mean, b3_mean ;
// -----------------------------------------------------------------
reg [31:0] rgb_data0 ;
reg [31:0] rgb_data1 ;
reg [31:0] rgb_data2 ;
reg [31:0] rgb_data3 ;

reg   [4:0]   I_tlast_r ;
reg   [4:0]   I_tuser_r ;
reg   [4:0]   I_tvalid_r;
/*********************************************************
                    wire 信号声明
*********************************************************/

// bayer format BGGR 
wire    [7:0]   matrix03, matrix04, matrix05, matrix06, matrix07, matrix08 ;
wire    [7:0]   matrix13, matrix14, matrix15, matrix16, matrix17, matrix18 ;
wire    [7:0]   matrix23, matrix24, matrix25, matrix26, matrix27, matrix28 ;


wire    [127:0] rgb_data;
wire            rgb_data_valid ;
/*********************************************************
                        信号描述
*********************************************************/
assign {matrix03, matrix04, matrix05, matrix06, matrix07, matrix08} = matrix_last_line[71:24];
assign {matrix13, matrix14, matrix15, matrix16, matrix17, matrix18} = matrix_cur_line[71:24];
assign {matrix23, matrix24, matrix25, matrix26, matrix27, matrix28} = matrix_next_line[71:24];



/*********************************************************
                        信号延迟
*********************************************************/
// pipleline 0
always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin 
        bayer_ypos_r0 <= 'b0 ;
        bayer_ypos_r1 <= 'b0 ;
    end
    else begin
        bayer_ypos_r0 <= bayer_ypos ;
        bayer_ypos_r1 <= bayer_ypos_r0 ;
    end
end

/*****************************************************************
                        BAYER_MODE_BGGR                                        
*****************************************************************/

////////////////////////////////////////////
//
//              双线性插值算法
//
////////////////////////////////////////////
// mipi ov5640 raw
generate if(BAYER_MODE == BGGR) begin : BAYER_MODE_BGGR
    // R Channel
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {r0_sum_part0, r0_sum_part1} <= 'd0 ; 
            r1_sum_part0  <= 'd0 ; 
            {r2_sum_part0, r2_sum_part1}  <= 'd0 ; 
            r3_sum_part0  <= 'd0 ; 
        end
        else if(I_tvalid)begin
            if(bayer_ypos) begin
                r0_sum_part0 <= matrix13 + matrix15 ;
                r0_sum_part1 <= 'd0 ;
        
                r1_sum_part0 <= matrix15 ;
        
                r2_sum_part0 <= matrix15 + matrix17 ;
                r2_sum_part1 <= 'd0 ;
        
                r3_sum_part0 <= matrix17 ;
            end
            else begin
                r0_sum_part0 <= matrix03 + matrix05 ;
                r0_sum_part1 <= matrix23 + matrix25 ;

                r1_sum_part0 <= matrix05 + matrix25 ;

                r2_sum_part0 <= matrix05 + matrix07 ;
                r2_sum_part1 <= matrix25 + matrix27 ;

                r3_sum_part0 <= matrix07 + matrix27 ;
            end
        end
    end

// G Channel
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {g0_sum_part0, g0_sum_part1} <= 'b0 ;
            {g1_sum_part0, g1_sum_part1} <= 'b0 ;
            {g2_sum_part0, g2_sum_part1} <= 'b0 ;
            {g3_sum_part0, g3_sum_part1} <= 'b0 ;
        end
        else if(I_tvalid)begin
            if(bayer_ypos) begin
                g0_sum_part0 <= matrix14 ;
                g0_sum_part1 <= 'd0 ;

                g1_sum_part0 <= matrix05 + matrix25 ;
                g1_sum_part1 <= matrix14 + matrix16 ;

                g2_sum_part0 <= matrix16;
                g2_sum_part1 <= 'd0 ;

                g3_sum_part0 <= matrix07 + matrix27 ; 
                g3_sum_part1 <= matrix16 + matrix18 ;
            end
            else begin
                g0_sum_part0 <= matrix04 + matrix24 ;
                g0_sum_part1 <= matrix13 + matrix15 ;

                g1_sum_part0 <= matrix15 ;
                g1_sum_part1 <= 'd0 ;

                g2_sum_part0 <= matrix06 + matrix26 ;
                g2_sum_part1 <= matrix15 + matrix17 ;

                g3_sum_part0 <= matrix17 ; 
                g3_sum_part1 <= 'd0 ;
            end
        end
    end
//B Channel
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            b0_sum_part0 <= 'd0 ;
            {b1_sum_part0, b1_sum_part1} <= 'd0 ;
            b2_sum_part0 <= 'd0 ;
            {b3_sum_part0, b3_sum_part1} <= 'd0 ;
        end
        else if(I_tvalid)begin
            if(bayer_ypos) begin
                b0_sum_part0 <= matrix04 + matrix24 ;

                b1_sum_part0 <= matrix04 + matrix06 ;
                b1_sum_part1 <= matrix24 + matrix26 ;

                b2_sum_part0 <= matrix06 + matrix26 ;

                b3_sum_part0 <= matrix06 + matrix08 ;
                b3_sum_part1 <= matrix26 + matrix28 ;
            end
            else begin
                b0_sum_part0 <= matrix14 ;

                b1_sum_part0 <= matrix14 + matrix16 ;
                b1_sum_part1 <= 'd0 ;

                b2_sum_part0 <= matrix16 ;

                b3_sum_part0 <= matrix16 + matrix18 ;
                b3_sum_part1 <= 'd0 ;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {r0_matrix_plus, g0_matrix_plus, b0_matrix_plus} <= 'd0 ;
            {r1_matrix_plus, g1_matrix_plus, b1_matrix_plus} <= 'd0 ;
            {r2_matrix_plus, g2_matrix_plus, b2_matrix_plus} <= 'd0 ;
            {r3_matrix_plus, g3_matrix_plus, b3_matrix_plus} <= 'd0 ;
        end
        else if(I_tvalid_r[0])begin
            r0_matrix_plus <= r0_sum_part0 + r0_sum_part1 ;
            r1_matrix_plus <= r1_sum_part0 ;
            r2_matrix_plus <= r2_sum_part0 + r2_sum_part1 ;
            r3_matrix_plus <= r3_sum_part0 ;

            g0_matrix_plus <= g0_sum_part0 + g0_sum_part1 ;
            g1_matrix_plus <= g1_sum_part0 + g1_sum_part1 ;
            g2_matrix_plus <= g2_sum_part0 + g2_sum_part1 ;
            g3_matrix_plus <= g3_sum_part0 + g3_sum_part1 ;

            b0_matrix_plus <= b0_sum_part0 ;
            b1_matrix_plus <= b1_sum_part0 + b1_sum_part1 ;
            b2_matrix_plus <= b2_sum_part0 ;
            b3_matrix_plus <= b3_sum_part0 + b3_sum_part1 ;
        end
    end


    // pipleline 1
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {r0_mean, g0_mean, b0_mean} <= 'd0 ;
            {r1_mean, g1_mean, b1_mean} <= 'd0 ;
            {r2_mean, g2_mean, b2_mean} <= 'd0 ;
            {r3_mean, g3_mean, b3_mean} <= 'd0 ;
        end
        else if(I_tvalid_r[1]) begin
            r0_mean <= bayer_ypos_r1 ? r0_matrix_plus >> 1 : r0_matrix_plus >> 2 ;
            g0_mean <= bayer_ypos_r1 ? g0_matrix_plus      : g0_matrix_plus >> 2 ;
            b0_mean <= bayer_ypos_r1 ? b0_matrix_plus >> 1 : b0_matrix_plus      ;

            r1_mean <= bayer_ypos_r1 ? r1_matrix_plus      : r1_matrix_plus >> 1 ;
            g1_mean <= bayer_ypos_r1 ? g1_matrix_plus >> 2 : g1_matrix_plus ;
            b1_mean <= bayer_ypos_r1 ? b1_matrix_plus >> 2 : b1_matrix_plus >> 1 ;

            r2_mean <= bayer_ypos_r1 ? r2_matrix_plus >> 1 : r2_matrix_plus >> 2;
            g2_mean <= bayer_ypos_r1 ? g2_matrix_plus      : g2_matrix_plus >> 2;   
            b2_mean <= bayer_ypos_r1 ? b2_matrix_plus >> 1 : b2_matrix_plus ;

            r3_mean <= bayer_ypos_r1 ? r3_matrix_plus      : r3_matrix_plus >> 1 ;
            g3_mean <= bayer_ypos_r1 ? g3_matrix_plus >> 2 : g3_matrix_plus ;
            b3_mean <= bayer_ypos_r1 ? b3_matrix_plus >> 2 : b3_matrix_plus >> 1 ;
        end
    end
end


/*****************************************************************
                        BAYER_MODE_GBRG                                             
*****************************************************************/



    else if(BAYER_MODE == GBRG)
    begin:BAYER_MODE_GBRG

    // R Channel
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {r0_sum_part0, r0_sum_part1} <= 'd0 ; 
            {r1_sum_part0, r1_sum_part1}  <= 'd0 ; 
            r2_sum_part0  <= 'd0 ; 
            {r3_sum_part0, r3_sum_part1}  <= 'd0 ; 
        end
        else if(I_tvalid)begin
            if(bayer_ypos) begin
                r0_sum_part0 <= matrix14 ;
                r0_sum_part1 <= 'd0;

                r1_sum_part0 <= matrix14 + matrix16;
                r1_sum_part1 <= 'd0;

                r2_sum_part0 <= matrix16;

                r3_sum_part0 <= matrix16 + matrix18 ;
                r3_sum_part1 <= 'd0;
            end
            else begin
                r0_sum_part0 <= 'd0;
                r0_sum_part1 <= matrix04 + matrix24;

                r1_sum_part0 <= matrix04 + matrix06 ;
                r1_sum_part1 <= matrix24 + matrix26 ;

                r2_sum_part0 <= matrix06 + matrix26 ;

                r3_sum_part0 <= matrix06 + matrix26 ;
                r3_sum_part1 <= matrix08 + matrix28 ;
            end
        end
    end
// G Channel
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {g0_sum_part0, g0_sum_part1} <= 'b0 ;
            {g1_sum_part0, g1_sum_part1} <= 'b0 ;
            {g2_sum_part0, g2_sum_part1} <= 'b0 ;
            {g3_sum_part0, g3_sum_part1} <= 'b0 ;
        end
        else if(I_tvalid)begin
            if(bayer_ypos) begin
                g0_sum_part0 <= matrix04 + matrix24;
                g0_sum_part1 <= matrix13 + matrix15;

                g1_sum_part0 <= matrix15;
                g1_sum_part1 <= 'd0 ;

                g2_sum_part0 <= matrix06 + matrix26 ;
                g2_sum_part1 <= matrix15 + matrix17 ;

                g3_sum_part0 <= matrix17  ; 
                g3_sum_part1 <= 'd0 ;
            end
            else begin
                g0_sum_part0 <= matrix14 ;
                g0_sum_part1 <= 'd0;

                g1_sum_part0 <= matrix05 + matrix25;
                g1_sum_part1 <= matrix14 + matrix16;

                g2_sum_part0 <= matrix16 ;
                g2_sum_part1 <= 'd0;

                g3_sum_part0 <= matrix07 + matrix27; 
                g3_sum_part1 <= matrix16 + matrix18;
            end
        end
    end
//B Channel
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {b0_sum_part0, b0_sum_part1} <= 'd0 ;
            {b1_sum_part0, b1_sum_part1} <= 'd0 ;
            {b2_sum_part0, b2_sum_part1} <= 'd0 ;
            {b3_sum_part0, b3_sum_part1} <= 'd0 ;
        end
        else if(I_tvalid)begin
            if(bayer_ypos) begin
                b0_sum_part0 <= matrix03 + matrix23 ;//????
                b0_sum_part1 <= matrix05 + matrix25 ;//????

                b1_sum_part0 <= 'd0;//????
                b1_sum_part1 <= matrix05 + matrix25 ;

                b2_sum_part0 <= matrix05 + matrix25 ;
                b2_sum_part1 <= matrix07 + matrix27 ;

                b3_sum_part0 <= 'd0 ;//????
                b3_sum_part1 <= matrix07 + matrix27 ;
            end
            else begin
                b0_sum_part0 <= matrix13 + matrix15 ;
                b0_sum_part1 <= 'd0;

                b1_sum_part0 <= matrix15 ;
                b1_sum_part1 <= 'd0 ;

                b2_sum_part0 <= matrix15 +  matrix17;
                b2_sum_part1 <= 'd0;

                b3_sum_part0 <= matrix17 ;
                b3_sum_part1 <= 'd0 ;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {r0_matrix_plus, g0_matrix_plus, b0_matrix_plus} <= 'd0 ;
            {r1_matrix_plus, g1_matrix_plus, b1_matrix_plus} <= 'd0 ;
            {r2_matrix_plus, g2_matrix_plus, b2_matrix_plus} <= 'd0 ;
            {r3_matrix_plus, g3_matrix_plus, b3_matrix_plus} <= 'd0 ;
        end
        else if(I_tvalid_r[0])begin
            r0_matrix_plus <= r0_sum_part0 + r0_sum_part1 ;
            r1_matrix_plus <= r1_sum_part0 + r1_sum_part1 ;
            r2_matrix_plus <= r2_sum_part0   ;
            r3_matrix_plus <= r3_sum_part0 + r3_sum_part1 ;

            g0_matrix_plus <= g0_sum_part0 + g0_sum_part1 ;
            g1_matrix_plus <= g1_sum_part0 + g1_sum_part1 ;
            g2_matrix_plus <= g2_sum_part0 + g2_sum_part1 ;
            g3_matrix_plus <= g3_sum_part0 + g3_sum_part1 ;

            b0_matrix_plus <= b0_sum_part0 + b0_sum_part1 ;
            b1_matrix_plus <= b1_sum_part0 + b1_sum_part1 ;
            b2_matrix_plus <= b2_sum_part0 + b2_sum_part1 ;
            b3_matrix_plus <= b3_sum_part0 + b3_sum_part1 ;
        end
    end


    // pipleline 1
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {r0_mean, g0_mean, b0_mean} <= 'd0 ;
            {r1_mean, g1_mean, b1_mean} <= 'd0 ;
            {r2_mean, g2_mean, b2_mean} <= 'd0 ;
            {r3_mean, g3_mean, b3_mean} <= 'd0 ;
        end
        else if(I_tvalid_r[1])begin
            r0_mean <= bayer_ypos_r1    ? r0_matrix_plus      : r0_matrix_plus >> 1 ;
            g0_mean <= (!bayer_ypos_r1) ? g0_matrix_plus      : g0_matrix_plus >> 2 ;
            b0_mean <= bayer_ypos_r1    ? b0_matrix_plus >> 2 : b0_matrix_plus >> 1 ;

            r1_mean <= bayer_ypos_r1    ? r1_matrix_plus >> 1 : r1_matrix_plus >> 2 ;
            g1_mean <= (!bayer_ypos_r1) ? g1_matrix_plus >> 2 : g1_matrix_plus      ;
            b1_mean <= bayer_ypos_r1 ? b1_matrix_plus >> 1 : b1_matrix_plus      ;

            r2_mean <= bayer_ypos_r1    ? r2_matrix_plus      : r2_matrix_plus >> 1 ;
            g2_mean <= (!bayer_ypos_r1) ? g2_matrix_plus      : g2_matrix_plus >> 2 ;   
            b2_mean <= bayer_ypos_r1    ? b2_matrix_plus >> 2 : b2_matrix_plus >> 1 ;

            r3_mean <= bayer_ypos_r1    ? r3_matrix_plus >> 1 : r3_matrix_plus >> 2 ;
            g3_mean <= (!bayer_ypos_r1) ? g3_matrix_plus >> 2 : g3_matrix_plus      ;
            b3_mean <= bayer_ypos_r1    ? b3_matrix_plus >> 1 : b3_matrix_plus      ;
        end
    end
end

/*****************************************************************
                       BAYER_MODE_RGGB                             
*****************************************************************/

    else if(BAYER_MODE == RGGB)
    begin:BAYER_MODE_RGGB

    // R Channel
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {r0_sum_part0, r0_sum_part1} <= 'd0 ; 
            {r1_sum_part0, r1_sum_part1}  <= 'd0 ; 
            r2_sum_part0  <= 'd0 ; 
            {r3_sum_part0, r3_sum_part1}  <= 'd0 ; 
        end
        else if(I_tvalid)begin
            if(bayer_ypos) begin
                r0_sum_part0 <= matrix04 + matrix24;//
                r0_sum_part1 <= 'd0;

                r1_sum_part0 <= matrix04 + matrix24;
                r1_sum_part1 <= matrix06 + matrix26;

                r2_sum_part0 <= matrix06 + matrix26;

                r3_sum_part0 <= matrix06 + matrix26;
                r3_sum_part1 <= matrix08 + matrix28;
            end
            else begin
                r0_sum_part0 <= matrix14;
                r0_sum_part1 <= 'd0;

                r1_sum_part0 <= matrix14 + matrix16;
                r1_sum_part1 <= 'd0;

                r2_sum_part0 <= matrix16  ;

                r3_sum_part0 <= matrix16 + matrix18 ;
                r3_sum_part1 <= 'd0 ;
            end
        end
    end
// G Channel
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {g0_sum_part0, g0_sum_part1} <= 'b0 ;
            {g1_sum_part0, g1_sum_part1} <= 'b0 ;
            {g2_sum_part0, g2_sum_part1} <= 'b0 ;
            {g3_sum_part0, g3_sum_part1} <= 'b0 ;
        end
        else if(I_tvalid)begin
            if(bayer_ypos) begin
                g0_sum_part0 <= matrix14 ;
                g0_sum_part1 <= 'd0;

                g1_sum_part0 <= matrix05 + matrix25;
                g1_sum_part1 <= matrix14 + matrix16;

                g2_sum_part0 <= matrix16 ;
                g2_sum_part1 <= 'd0;

                g3_sum_part0 <= matrix07 + matrix27; 
                g3_sum_part1 <= matrix16 + matrix18;
            end
            else begin
                g0_sum_part0 <= matrix04 + matrix24;
                g0_sum_part1 <= matrix13 + matrix15;

                g1_sum_part0 <= matrix15;
                g1_sum_part1 <= 'd0 ;

                g2_sum_part0 <= matrix06 + matrix26 ;
                g2_sum_part1 <= matrix15 + matrix17 ;

                g3_sum_part0 <= matrix17  ; 
                g3_sum_part1 <= 'd0 ;
            end
        end
    end
//B Channel
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {b0_sum_part0, b0_sum_part1} <= 'd0 ;
            {b1_sum_part0, b1_sum_part1} <= 'd0 ;
            {b2_sum_part0, b2_sum_part1} <= 'd0 ;
            {b3_sum_part0, b3_sum_part1} <= 'd0 ;
        end
        else if(I_tvalid)begin
            if(bayer_ypos) begin
                b0_sum_part0 <= matrix13 + matrix15 ;
                b0_sum_part1 <= 'd0;

                b1_sum_part0 <= matrix15 ;
                b1_sum_part1 <= 'd0 ;

                b2_sum_part0 <= matrix15 +  matrix17;
                b2_sum_part1 <= 'd0;

                b3_sum_part0 <= matrix17 ;
                b3_sum_part1 <= 'd0 ;
            end
            else begin
                b0_sum_part0 <= matrix03 + matrix23 ;//????
                b0_sum_part1 <= matrix05 + matrix25 ;//????

                b1_sum_part0 <= 'd0;//????
                b1_sum_part1 <= matrix05 + matrix25 ;

                b2_sum_part0 <= matrix05 + matrix25 ;
                b2_sum_part1 <= matrix07 + matrix27 ;

                b3_sum_part0 <= 'd0 ;//????
                b3_sum_part1 <= matrix07 + matrix27 ;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {r0_matrix_plus, g0_matrix_plus, b0_matrix_plus} <= 'd0 ;
            {r1_matrix_plus, g1_matrix_plus, b1_matrix_plus} <= 'd0 ;
            {r2_matrix_plus, g2_matrix_plus, b2_matrix_plus} <= 'd0 ;
            {r3_matrix_plus, g3_matrix_plus, b3_matrix_plus} <= 'd0 ;
        end
        else if(I_tvalid_r[0])begin
            r0_matrix_plus <= r0_sum_part0 + r0_sum_part1 ;
            r1_matrix_plus <= r1_sum_part0 + r1_sum_part1 ;
            r2_matrix_plus <= r2_sum_part0   ;
            r3_matrix_plus <= r3_sum_part0 + r3_sum_part1 ;

            g0_matrix_plus <= g0_sum_part0 + g0_sum_part1 ;
            g1_matrix_plus <= g1_sum_part0 + g1_sum_part1 ;
            g2_matrix_plus <= g2_sum_part0 + g2_sum_part1 ;
            g3_matrix_plus <= g3_sum_part0 + g3_sum_part1 ;

            b0_matrix_plus <= b0_sum_part0 + b0_sum_part1 ;
            b1_matrix_plus <= b1_sum_part0 + b1_sum_part1 ;
            b2_matrix_plus <= b2_sum_part0 + b2_sum_part1 ;
            b3_matrix_plus <= b3_sum_part0 + b3_sum_part1 ;
        end
    end


    // pipleline 1
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {r0_mean, g0_mean, b0_mean} <= 'd0 ;
            {r1_mean, g1_mean, b1_mean} <= 'd0 ;
            {r2_mean, g2_mean, b2_mean} <= 'd0 ;
            {r3_mean, g3_mean, b3_mean} <= 'd0 ;
        end
        else if(I_tvalid_r[1])begin
            r0_mean <= (!bayer_ypos_r1) ? r0_matrix_plus      : r0_matrix_plus >> 1 ;
            g0_mean <= bayer_ypos_r1    ? g0_matrix_plus      : g0_matrix_plus >> 2 ;
            b0_mean <= (!bayer_ypos_r1) ? b0_matrix_plus >> 2 : b0_matrix_plus >> 1 ;

            r1_mean <= (!bayer_ypos_r1) ? r1_matrix_plus >> 1 : r1_matrix_plus >> 2 ;
            g1_mean <= bayer_ypos_r1    ? g1_matrix_plus >> 2 : g1_matrix_plus      ;
            b1_mean <= (!bayer_ypos_r1) ? b1_matrix_plus >> 1 : b1_matrix_plus      ;

            r2_mean <= (!bayer_ypos_r1) ? r2_matrix_plus      : r2_matrix_plus >> 1 ;
            g2_mean <= bayer_ypos_r1    ? g2_matrix_plus      : g2_matrix_plus >> 2 ;   
            b2_mean <= (!bayer_ypos_r1) ? b2_matrix_plus >> 2 : b2_matrix_plus >> 1 ;

            r3_mean <= (!bayer_ypos_r1) ? r3_matrix_plus >> 1 : r3_matrix_plus >> 2 ;
            g3_mean <= bayer_ypos_r1    ? g3_matrix_plus >> 2 : g3_matrix_plus      ;
            b3_mean <= (!bayer_ypos_r1) ? b3_matrix_plus >> 1 : b3_matrix_plus      ;
        end
    end
end


/*****************************************************************
                       BAYER_MODE_GRBG                             
*****************************************************************/


    else if(BAYER_MODE == GRBG)
    begin:BAYER_MODE_GRBG

    // R Channel
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {r0_sum_part0, r0_sum_part1} <= 'd0 ; 
            {r1_sum_part0, r1_sum_part1}  <= 'd0 ; 
            {r2_sum_part0, r2_sum_part1} <= 'd0 ; 
            {r3_sum_part0, r3_sum_part1}  <= 'd0 ; 
        end
        else if(I_tvalid)begin
            if(bayer_ypos) begin
                r0_sum_part0 <= matrix03 + matrix05 ;
                r0_sum_part1 <= matrix23 + matrix25 ;

                r1_sum_part0 <= matrix05 + matrix25 ;
                r1_sum_part1 <= 'd0;

                r2_sum_part0 <= matrix05 + matrix07 ;
                r2_sum_part1 <= matrix25 + matrix27 ;

                r3_sum_part0 <= matrix07 + matrix27 ;       
                r3_sum_part1 <= 'd0 ;                                                                 
            end
            else begin
                r0_sum_part0 <= matrix13 + matrix15 ;
                r0_sum_part1 <= 'd0 ;

                r1_sum_part0 <= matrix15 ;
                r1_sum_part1 <= 'd0;

                r2_sum_part0 <= matrix15 + matrix17 ;
                r2_sum_part1 <= 'd0 ;

                r3_sum_part0 <= matrix17 ;
                r3_sum_part1 <= 'd0 ;  
            end
        end
    end
// G Channel
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {g0_sum_part0, g0_sum_part1} <= 'b0 ;
            {g1_sum_part0, g1_sum_part1} <= 'b0 ;
            {g2_sum_part0, g2_sum_part1} <= 'b0 ;
            {g3_sum_part0, g3_sum_part1} <= 'b0 ;
        end
        else if(I_tvalid)begin
            if(bayer_ypos) begin
                g0_sum_part0 <= matrix04 + matrix24;
                g0_sum_part1 <= matrix13 + matrix15;

                g1_sum_part0 <= matrix15;
                g1_sum_part1 <= 'd0 ;

                g2_sum_part0 <= matrix06 + matrix26 ;
                g2_sum_part1 <= matrix15 + matrix17 ;

                g3_sum_part0 <= matrix17  ; 
                g3_sum_part1 <= 'd0 ;
            end
            else begin
                g0_sum_part0 <= matrix14 ;
                g0_sum_part1 <= 'd0;

                g1_sum_part0 <= matrix05 + matrix25;
                g1_sum_part1 <= matrix14 + matrix16;

                g2_sum_part0 <= matrix16 ;
                g2_sum_part1 <= 'd0;

                g3_sum_part0 <= matrix07 + matrix27; 
                g3_sum_part1 <= matrix16 + matrix18;
            end
        end
    end
//B Channel
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {b0_sum_part0, b0_sum_part1} <= 'd0 ;
            {b1_sum_part0, b1_sum_part1} <= 'd0 ;
            {b2_sum_part0, b2_sum_part1} <= 'd0 ;
            {b3_sum_part0, b3_sum_part1} <= 'd0 ;
        end
        else if(I_tvalid)begin
            if(bayer_ypos) begin
                b0_sum_part0 <= matrix14 ;
                b0_sum_part1 <= 'd0;

                b1_sum_part0 <= matrix14 + matrix16 ;
                b1_sum_part1 <= 'd0 ;

                b2_sum_part0 <= matrix16 ;
                b2_sum_part1 <= 'd0;

                b3_sum_part0 <= matrix16 + matrix18 ;
                b3_sum_part1 <= 'd0 ;
            end
            else begin
                b0_sum_part0 <= matrix04 + matrix24 ;
                b0_sum_part1 <= 'd0;

                b1_sum_part0 <= matrix04 + matrix06 ;
                b1_sum_part1 <= matrix24 + matrix26 ;

                b2_sum_part0 <= matrix06 + matrix26 ;
                b2_sum_part1 <= 'd0;

                b3_sum_part0 <= matrix06 + matrix08 ;
                b3_sum_part1 <= matrix26 + matrix28 ;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {r0_matrix_plus, g0_matrix_plus, b0_matrix_plus} <= 'd0 ;
            {r1_matrix_plus, g1_matrix_plus, b1_matrix_plus} <= 'd0 ;
            {r2_matrix_plus, g2_matrix_plus, b2_matrix_plus} <= 'd0 ;
            {r3_matrix_plus, g3_matrix_plus, b3_matrix_plus} <= 'd0 ;
        end
        else if(I_tvalid_r[0])begin
            r0_matrix_plus <= r0_sum_part0 + r0_sum_part1 ;
            r1_matrix_plus <= r1_sum_part0 + r1_sum_part1 ;
            r2_matrix_plus <= r2_sum_part0 + r2_sum_part1 ;
            r3_matrix_plus <= r3_sum_part0 + r3_sum_part1 ;

            g0_matrix_plus <= g0_sum_part0 + g0_sum_part1 ;
            g1_matrix_plus <= g1_sum_part0 + g1_sum_part1 ;
            g2_matrix_plus <= g2_sum_part0 + g2_sum_part1 ;
            g3_matrix_plus <= g3_sum_part0 + g3_sum_part1 ;

            b0_matrix_plus <= b0_sum_part0 + b0_sum_part1 ;
            b1_matrix_plus <= b1_sum_part0 + b1_sum_part1 ;
            b2_matrix_plus <= b2_sum_part0 + b2_sum_part1 ;
            b3_matrix_plus <= b3_sum_part0 + b3_sum_part1 ;
        end
    end


    // pipleline 1
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {r0_mean, g0_mean, b0_mean} <= 'd0 ;
            {r1_mean, g1_mean, b1_mean} <= 'd0 ;
            {r2_mean, g2_mean, b2_mean} <= 'd0 ;
            {r3_mean, g3_mean, b3_mean} <= 'd0 ;
        end
        else if(I_tvalid_r[1])begin
            r0_mean <= (!bayer_ypos_r1) ? r0_matrix_plus >> 1 : r0_matrix_plus >> 2 ;
            g0_mean <= (!bayer_ypos_r1) ? g0_matrix_plus      : g0_matrix_plus >> 2 ;
            b0_mean <= (!bayer_ypos_r1) ? b0_matrix_plus >> 1 : b0_matrix_plus      ;

            r1_mean <= (!bayer_ypos_r1) ? r1_matrix_plus      : r1_matrix_plus >> 1 ;
            g1_mean <= (!bayer_ypos_r1) ? g1_matrix_plus >> 2 : g1_matrix_plus      ;
            b1_mean <= (!bayer_ypos_r1) ? b1_matrix_plus >> 2 : b1_matrix_plus >> 1 ;

            r2_mean <= (!bayer_ypos_r1) ? r2_matrix_plus >> 1 : r2_matrix_plus >> 2 ;
            g2_mean <= (!bayer_ypos_r1) ? g2_matrix_plus      : g2_matrix_plus >> 2 ;      
            b2_mean <= (!bayer_ypos_r1) ? b2_matrix_plus >> 1 : b2_matrix_plus      ;

            r3_mean <= (!bayer_ypos_r1) ? r3_matrix_plus      : r3_matrix_plus >> 1 ;
            g3_mean <= (!bayer_ypos_r1) ? g3_matrix_plus >> 2 : g3_matrix_plus      ;
            b3_mean <= (!bayer_ypos_r1) ? b3_matrix_plus >> 2 : b3_matrix_plus >> 1 ;
        end
    end
end

endgenerate 
    


    reg [7:0] r0_mean_d,r1_mean_d,r2_mean_d,r3_mean_d;
    reg [7:0] g0_mean_d,g1_mean_d,g2_mean_d,g3_mean_d;
    reg [7:0] b0_mean_d,b1_mean_d,b2_mean_d,b3_mean_d;
    // pipleline 2
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            {r0_mean_d,r1_mean_d,r2_mean_d,r3_mean_d} <= 'd0 ;
            {g0_mean_d,g1_mean_d,g2_mean_d,g3_mean_d} <= 'd0 ;
            {b0_mean_d,b1_mean_d,b2_mean_d,b3_mean_d} <= 'd0 ;
        end
        else if(I_tvalid_r[2])begin
            r0_mean_d <= r0_mean[8]?255:r0_mean[7:0];
            g0_mean_d <= g0_mean[8]?255:g0_mean[7:0];
            b0_mean_d <= b0_mean[8]?255:b0_mean[7:0];

            r1_mean_d <= r1_mean[8]?255:r1_mean[7:0];
            g1_mean_d <= g1_mean[8]?255:g1_mean[7:0];
            b1_mean_d <= b1_mean[8]?255:b1_mean[7:0];

            r2_mean_d <= r2_mean[8]?255:r2_mean[7:0];
            g2_mean_d <= g2_mean[8]?255:g2_mean[7:0];
            b2_mean_d <= b2_mean[8]?255:b2_mean[7:0];

            r3_mean_d <= r3_mean[8]?255:r3_mean[7:0];
            g3_mean_d <= g3_mean[8]?255:g3_mean[7:0];
            b3_mean_d <= b3_mean[8]?255:b3_mean[7:0];
        end
    end

    // pipleline 3
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            rgb_data0 <= 'd0 ;
            rgb_data1 <= 'd0 ;
            rgb_data2 <= 'd0 ;
            rgb_data3 <= 'd0 ;
        end
        else if(I_tvalid_r[3])begin
            rgb_data0 <= {8'b0, r0_mean_d, g0_mean_d, b0_mean_d};
            rgb_data1 <= {8'b0, r1_mean_d, g1_mean_d, b1_mean_d};
            rgb_data2 <= {8'b0, r2_mean_d, g2_mean_d, b2_mean_d};
            rgb_data3 <= {8'b0, r3_mean_d, g3_mean_d, b3_mean_d};
        end
    end

    assign rgb_data = {rgb_data3, rgb_data2, rgb_data1, rgb_data0};
/*****************************************************************
                          信号同步                                        
*****************************************************************/

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            {I_tlast_r,I_tuser_r,I_tvalid_r} <= 0;
        else begin
            I_tlast_r  <= {I_tlast_r[3:0],I_tlast};
            I_tuser_r  <= {I_tuser_r[3:0],I_tuser};
            I_tvalid_r <= {I_tvalid_r[3:0],I_tvalid};
        end
    end

    assign  O_tlast  = I_tlast_r[4];   
    assign  O_tuser  = I_tuser_r[4];   
    assign  O_tvalid = I_tvalid_r[4];

    
    assign O_tdata  = rgb_data;
    assign I_tready = O_tready;

endmodule
/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
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
/*********legacy_ui_line_buffer_demosaic ******************************
--版本号1.0  
*****************************************************************/

module legacy_ui_line_buffer_demosaic #(
    parameter 		IMG_HEIGHT = 1080,   // 图像高度参数，默认值为1080
    parameter 		IMG_WIDTH  = 1920    // 图像宽度参数，默认值为1920
) (
    input           I_clk	,    // 输入时钟信号
    input           I_rst_n	,    // 输入复位信号，低电平有效
    input           I_tuser	,    // 输入tuser信号，帧起始标志 
    input           I_valid	,    // 输入数据有效信号          
    input   [32:0]  I_data	,    // 输入数据总线，宽度为33位  
    output          O_valid	,    // 输出数据有效信号          
    output  [32:0]  O_data       // 输出数据总线，宽度为33位  
);

    // 定义局部参数，计算图像宽度的四分之一，用于地址计数
    localparam IMG_WIDTH_4x = (IMG_WIDTH >> 2);

    // 定义读使能信号
    wire        rd_en;  // synthesis keep 

    // 定义地址计数器寄存器和数据寄存器
    reg  [10:0] addra;     // 写地址计数器               
    reg  [10:0] addrb;     // 读地址计数器               
    reg  [32:0] data_d0;   // 延时一个时钟的数据         
    reg         valid_d0;  // 延时一个时钟的数据有效信号  
	
	reg 		tlast_lock_d0;
	
	
	// 读使能信号rd_en的生成
    assign rd_en = (I_valid && tlast_lock_d0) ? 1'b1 : 1'b0;
    // 只有当I_valid有效且tlast_lock_d0置位后，才产生读使能信号
	
	// 输出有效信号O_valid的生成
    assign O_valid = (valid_d0 && tlast_lock_d0) ? 1'b1 : 1'b0;
    // 只有当valid_d0有效且tlast_lock_d0置位后，才输出有效数据

    // 数据和有效信号的寄存，延时一个时钟
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            data_d0  <= 0;            // 复位时将data_d0清零
            valid_d0 <= 0;            // 复位时将valid_d0清零
        end else begin
            data_d0  <= I_data;       // 正常工作时，data_d0跟随I_data
            valid_d0 <= I_valid;      // 正常工作时，valid_d0跟随I_valid
        end
    end

    // 写地址计数器addra的更新
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n || I_tuser) begin
            addra <= 0;    // 复位或者I_tuser有效时，将addra清零
        end else if (valid_d0) begin
            // 当valid_d0有效时，更新addra
            addra <= (addra == IMG_WIDTH_4x - 1) ? 0 : addra + 1'b1;
            // 如果addra达到最大值（IMG_WIDTH_4x - 1），则清零，否则加1
        end
    end

    // 行结束标志tlast_lock_d0的更新

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n || I_tuser) begin
            tlast_lock_d0 <= 1'b0;  // 复位或者I_tuser有效时，将tlast_lock_d0清零
        end else if ((tlast_lock_d0 == 1'b0) & (addra == IMG_WIDTH_4x - 1)) begin
            tlast_lock_d0 <= 1'b1;  // 当第一次addra达到最大值时，置位tlast_lock_d0
        end
    end

    // 读地址计数器addrb的更新
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n || I_tuser) begin
            addrb <= 0;    // 复位或者I_tuser有效时，将addrb清零
        end else begin
            // 当rd_en有效时，更新addrb
            addrb <= rd_en ? ((addrb == IMG_WIDTH_4x - 1) ? 0 : addrb + 1'b1) : addrb;
            // 如果addrb达到最大值（IMG_WIDTH_4x - 1），则清零，否则加1
            // 如果rd_en无效，addrb保持不变
        end
    end

    // 实例化块存储器，用于数据的存储和读取
    ui_ram_demosaic X_ui_ram_demosaic_demosaic (
        .clka 	(I_clk  )	,	// 写端口时钟信号
        .wea  	(valid_d0)	,  	// 写使能信号
        .addra	(addra  )	,  	// 写地址
        .dia 	(data_d0)	,   // 写数据
        .clkb 	(I_clk  )	,   // 读端口时钟信号
        .addrb	(addrb  )	,   // 读地址
        .dob	(O_data )    	// 读数据输出
    );

endmodule


/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
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
/*********legacy_ui_mipi_to_raw_converter ******************************
该模块主要是用于3x3矩阵的形成，以及对图像边界像素的处理
在原基础上优化了时序，把原来的一些未完全对齐的信号进行对齐。
--版本号1.0  
*****************************************************************/

module legacy_ui_mipi_to_raw_converter 
(
    input           	I_clk   	,
    input           	I_rst_n 	,
	
    input   [39:0]  	I_raw_tdata ,
    input   [ 9:0]  	I_raw_tdest ,
    input           	I_raw_tlast ,
    input           	I_raw_tvalid,
    input           	I_raw_tuser ,
    output          	I_raw_tready,
		
    // 输出RAW10数据	
    output  [31:0]  	O_raw_tdata ,
    output          	O_raw_tlast ,
    output          	O_raw_tvalid,
    output          	O_raw_tuser ,
    input           	O_raw_tready
);
    reg            			I_tlast_r0;
    reg            			I_tuser_r0;
			
    reg            			I_tvalid_r0;
    reg    [31:0]  			raw_data_r0;
	
	assign  O_raw_tlast  = 	I_tlast_r0;   
    assign  O_raw_tuser  = 	I_tuser_r0;   
    assign  O_raw_tvalid = 	I_tvalid_r0;
	
    assign  O_raw_tdata  = 	raw_data_r0;
		
    assign  I_raw_tready = 	O_raw_tready;

    ///此处对于每个RAW10取高8位是因为高位所包含的颜色数据更多。
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            raw_data_r0 <= 0;
        else if(I_raw_tvalid)begin
            raw_data_r0 <= {I_raw_tdata[9:2], I_raw_tdata[19:12], I_raw_tdata[29:22], I_raw_tdata[39:32]};
        end 
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin
            {I_tlast_r0,I_tuser_r0,I_tvalid_r0} <= 0;
        end
        else begin
            I_tlast_r0  <= I_raw_tlast;
            I_tuser_r0  <= I_raw_tuser;
            I_tvalid_r0 <= I_raw_tvalid;
        end
    end
    

endmodule




/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
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
/*********legacy_ui_raw_matrix_3x3_buffer ******************************
该模块主要是用于3x3矩阵的形成，以及对图像边界像素的处理
在原基础上优化了时序，把原来的一些未完全对齐的信号进行对齐。
--版本号1.0  
*****************************************************************/

module legacy_ui_raw_matrix_3x3_buffer #(
    parameter 			IMG_HEIGHT 			= 1080,  // 图像高度
    parameter 			IMG_WIDTH  			= 1920,   // 图像宽度
    parameter 			data_complete_delay = 50
)
(
    input           	I_clk   			,  // 时钟信号
    input           	I_rst_n 			,  // 复位信号，低有效

    input [39:0]  		I_axi4s_video_tdata ,  // AXI4-Stream视频数据
    input [9:0]   		I_axi4s_video_tdest ,
    input         		I_axi4s_video_tlast ,  // 行结束信号
    input         		I_axi4s_video_tvalid,  // 数据有效信号
    input         		I_axi4s_video_tuser ,  // 帧开始信号
    output        		I_axi4s_video_tready,  // 从模块准备好接受数据
		
    output        		O_tlast         	,   // 行结束信号输出
    output        		O_tuser         	,   // 帧开始信号输出
    output        		O_tvalid        	,   // 数据有效信号输出
    input         		O_tready        	,   // 上一级模块准备好接受数据
			
    output        		bayer_ypos      	,   // Bayer滤波器行位置
    output  [95:0]		matrix_last_line	,   // 上一行3x3矩阵数据
    output  [95:0]		matrix_cur_line 	,   // 当前行3x3矩阵数据
    output  [95:0]		matrix_next_line        // 下一行3x3矩阵数据
);


/*********************************************************
******************1.功能声明*******************************
*********************************************************/
// 计算数据的位宽
function integer clog2b(
    input integer depth
);
    begin
        for(clog2b=0; depth>0; clog2b=clog2b+1)begin
            depth = depth >> 1;
        end
    end    
endfunction

/*********************************************************
******************2.常数声明*******************************
*********************************************************/
localparam N = 3;  // 矩阵大小为3x3

localparam DATA_WIDTH   = 32;  // 数据位宽

localparam IMG_WIDTH_4x = (IMG_WIDTH >> 2);  // 图像宽度除以4，得到每个数据块的数量

/*********************************************************
******************3.信号声明*******************************
*********************************************************/
// 定义线网信号
wire                        zhenghe_tlast 	;    // 合并后的行结束信号
wire                        zhenghe_tuser 	;    // 合并后的帧开始信号
wire  [31:0]                zhenghe_tdata 	;    // 合并后的数据
wire                        zhenghe_tvalid	;    // 合并后的数据有效信号

wire  [DATA_WIDTH-1:0]      raw_data        ;    // 原始数据
wire                        raw_data_valid  ;    // 原始数据有效信号

wire                		valid   [0:N-1] ;    // 有效信号数组
wire [DATA_WIDTH:0] 		data    [0:N-1] ;    // 数据数组（包含tuser位）

wire                		O_raw_tlast_d0	;    // 行结束信号，延迟0周期
wire                		O_raw_tuser_d0	;    // 帧开始信号，延迟0周期
wire                		I_raw_tready	;    // 模块准备好接受原始数据
wire [32:0]         		next_line_data	;    // 下一行数据
wire [32:0]         		data_d2			;    // 数据延迟2个周期
wire                		next_line_start	;    // 下一行的开始信号
wire                		bayer_ypos_d0	;    // Bayer位置，延迟0周期

/*********************************************************
******************4.寄存器信号声明*************************
*********************************************************/
// 定义寄存器信号
reg [95:0]      matrix_cur_line_buffer       ; // 当前行的3x3矩阵缓冲
reg [95:0]      matrix_last_line_buffer      ; // 上一行的3x3矩阵缓冲
reg [95:0]      matrix_next_line_buffer      ; // 下一行的3x3矩阵缓冲
reg             tlast_d0,tlast_d1,tlast_d2;     // 行结束信号延迟寄存器
reg             tuser_d0,tuser_d1,tuser_d2;     // 帧开始信号延迟寄存器
reg             ch_valid;                       // 数据通道有效信号
reg [13:0]      h_cnt;                          // 水平像素计数器
reg [13:0]      v_cnt,v_cnt_d;                  // 垂直像素计数器及其延迟
reg             next_line_data_valid;           // 下一行数据有效信号
reg             valid_d0,valid_d1;              // 有效信号延迟寄存器
reg             bayer_ypos_d;                   // Bayer位置延迟寄存器
reg  [32:0]     data_d0_d,data_d0;              // 数据延迟寄存器
reg  [32:0]     data_d1;

/*********************************************************
******************5.组合逻辑******************************
*********************************************************/
// 将数据和有效信号进行连接
assign data[0]  = {zhenghe_tuser, zhenghe_tdata};  // 将tuser和数据拼接
assign valid[0] = zhenghe_tvalid;                  // 第一个有效信号

// 将准备信号连接到上级模块
assign axi4s_video_tready = O_tready;

/*********************************************************/
// 将矩阵缓冲输出
assign matrix_last_line = matrix_last_line_buffer;
assign matrix_cur_line  = matrix_cur_line_buffer ;
assign matrix_next_line = matrix_next_line_buffer;

// 计算Bayer滤波器的行位置
assign bayer_ypos_d0 = !v_cnt_d[0] & ch_valid;

/*********************************************************
******************6.模块实例化*****************************
*********************************************************/
// 实例化mipi_to_raw_converter模块，将MIPI协议的数据转换为RAW数据
legacy_ui_mipi_to_raw_converter X_ui_mipi_to_raw_converter(
    .I_clk       (I_clk  ),              // 时钟信号
    .I_rst_n     (I_rst_n),              // 复位信号，低有效
    .I_raw_tdata (I_axi4s_video_tdata ),   // 输入原始数据
    .I_raw_tdest (I_axi4s_video_tdest ),   // 输入目的地地址
    .I_raw_tlast (I_axi4s_video_tlast ),   // 输入行结束信号
    .I_raw_tvalid(I_axi4s_video_tvalid),   // 输入数据有效信号
    .I_raw_tuser (I_axi4s_video_tuser),    // 输入帧开始信号
    .I_raw_tready(I_raw_tready  ),       // 输出准备好信号
    .O_raw_tdata (raw_data      ),       // 输出原始数据
    .O_raw_tlast (O_raw_tlast_d0),       // 输出行结束信号
    .O_raw_tvalid(raw_data_valid),       // 输出数据有效信号
    .O_raw_tuser (O_raw_tuser_d0),       // 输出帧开始信号
    .O_raw_tready(1)                     // 模块始终准备好接受数据
);

// 实例化“zhenghe”模块，将数据进行合并处理
legacy_ui_zhenghe#(
    .IMG_WIDTH ( IMG_WIDTH ),
    .IMG_HEIGHT( IMG_HEIGHT),
    .DATA_WIDTH( 32),
    .data_complete_delay (data_complete_delay)
) 
X_ui_zhenghe(
    .I_clk    (I_clk   ),               // 时钟信号
    .I_rst_n  (I_rst_n ),               // 复位信号，低有效

    .I_tlast  (O_raw_tlast_d0 ),        // 输入行结束信号
    .I_tuser  (O_raw_tuser_d0 ),        // 输入帧开始信号
    .I_tdata  (raw_data ),              // 输入原始数据
    .I_tvalid (raw_data_valid),         // 输入数据有效信号

    .O_tlast  (zhenghe_tlast ),         // 输出合并后的行结束信号
    .O_tuser  (zhenghe_tuser ),         // 输出合并后的帧开始信号
    .O_tdata  (zhenghe_tdata ),         // 输出合并后的数据
    .O_tvalid (zhenghe_tvalid)          // 输出合并后的数据有效信号
);

// 生成两行缓冲区，使用线性缓冲区实现3x3矩阵的行数据缓存
genvar i;
generate
    for(i=1; i<3; i=i+1)
    begin: two_line_buffer  // 模块命名为two_line_buffer
        legacy_ui_line_buffer_demosaic #(
            .IMG_HEIGHT (IMG_HEIGHT),
            .IMG_WIDTH  (IMG_WIDTH )
        ) X_ui_line_buffer_demosaic (
            .I_clk     ( I_clk      ),    // 时钟信号
            .I_rst_n   ( I_rst_n    ),    // 复位信号，低有效
            .I_tuser   ( data[i-1][32] & valid[i-1]), // 输入帧开始信号
            .I_valid   ( valid[i-1] ),    // 输入有效信号
            .I_data    ( data[i-1]  ),    // 输入数据
            .O_valid   ( valid[i]   ),    // 输出有效信号
            .O_data    ( data[i]    )     // 输出数据
        );           
    end        
endgenerate

// 由于在BRAM中每次输出数据都会延迟一个周期，所以要使这些数据对齐，需要对这些数据进行延迟处理，其中data[0]延迟2个周期，data[1]延迟一个周期
always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        data_d0_d <= 0;
        data_d0   <= 0;
        data_d1   <= 0;
        valid_d0  <= 0;
        valid_d1  <= 0;
    end
    else begin
        valid_d0  <= valid[0];
        valid_d1  <= valid_d0;
        data_d0_d <= data[0];
        data_d0   <= data_d0_d;
        data_d1   <= data[1];
    end
end

assign data_d2 = data[2];
/*********************************************************
***********3x3矩阵的形成，以及对边界元素的补充处理***********
*********************************************************/

always @(posedge I_clk or negedge I_rst_n) begin 
    if(!I_rst_n) begin
        matrix_last_line_buffer <= 'b0 ;
        matrix_cur_line_buffer  <= 'b0 ;
        matrix_next_line_buffer <= 'b0 ;
    end else if(valid_d1) begin
        if(v_cnt == 0) begin  // 第一行
            if(h_cnt == 0) begin  // 第一行的第一个像素
                matrix_last_line_buffer <= {{24{1'b0}}, data_d0[31:24], data_d0[31:0], data_d0[31:0]} ;
                matrix_cur_line_buffer  <= {{24{1'b0}}, data_d0[31:24], data_d0[31:0], data_d0[31:0]} ;
                matrix_next_line_buffer <= {{24{1'b0}}, data_d0[31:24], data_d0[31:0], data_d0[31:0]} ;
            end else if(h_cnt == (IMG_WIDTH_4x - 1)) begin  // 第一行的最后一个像素
                matrix_last_line_buffer <= {matrix_next_line_buffer [63:0], matrix_next_line_buffer[7:0], {24{1'b0}}} ;
                matrix_cur_line_buffer  <= {matrix_next_line_buffer [63:0], matrix_next_line_buffer[7:0], {24{1'b0}}} ;
                matrix_next_line_buffer <= {matrix_next_line_buffer [63:0], matrix_next_line_buffer[7:0], {24{1'b0}}} ;
            end else begin  // 第一行的中间像素
                matrix_last_line_buffer <= {matrix_next_line_buffer[63:0], data_d0[31:0]} ;
                matrix_cur_line_buffer  <= {matrix_next_line_buffer[63:0], data_d0[31:0]} ;
                matrix_next_line_buffer <= {matrix_next_line_buffer[63:0], data_d0[31:0]} ;
            end
        end
        else if(v_cnt == 1) begin  // 第二行
            if(h_cnt == 0) begin  // 第二行的第一个像素
                matrix_last_line_buffer <= {{24{1'b0}}, data_d1[31:24], data_d1[31:0], data_d1[31:0]} ;
                matrix_cur_line_buffer  <= {{24{1'b0}}, data_d1[31:24], data_d1[31:0], data_d1[31:0]} ;
                matrix_next_line_buffer <= {{24{1'b0}}, data_d0[31:24], data_d0[31:0], data_d0[31:0]} ;
            end else if(h_cnt == (IMG_WIDTH_4x - 1)) begin  // 第二行的最后一个像素
                matrix_last_line_buffer <= {matrix_cur_line_buffer [63:0], matrix_cur_line_buffer[7:0], {24{1'b0}}} ;
                matrix_cur_line_buffer  <= {matrix_cur_line_buffer [63:0], matrix_cur_line_buffer[7:0], {24{1'b0}}} ;
                matrix_next_line_buffer <= {matrix_next_line_buffer [63:0], matrix_next_line_buffer[7:0], {24{1'b0}}} ;
            end else begin  // 第二行的中间像素
                matrix_last_line_buffer <= {matrix_cur_line_buffer[63:0],  data_d1[31:0]} ;
                matrix_cur_line_buffer  <= {matrix_cur_line_buffer[63:0],  data_d1[31:0]} ;
                matrix_next_line_buffer <= {matrix_next_line_buffer[63:0], data_d0[31:0]} ;
            end
        end
        else begin  // 第三行及以后
            if(h_cnt == 0) begin  // 第一个像素
                matrix_last_line_buffer <= {{24{1'b0}}, data_d2[31:24], data_d2[31:0], data_d2[31:0]} ;
                matrix_cur_line_buffer  <= {{24{1'b0}}, data_d1[31:24], data_d1[31:0], data_d1[31:0]} ;
                matrix_next_line_buffer <= {{24{1'b0}}, data_d0[31:24], data_d0[31:0], data_d0[31:0]} ;
            end else if(h_cnt == (IMG_WIDTH_4x - 1)) begin  // 最后一个像素
                matrix_last_line_buffer <= {matrix_last_line_buffer[63:0], matrix_last_line_buffer[7:0], {24{1'b0}}} ;
                matrix_cur_line_buffer  <= {matrix_cur_line_buffer [63:0], matrix_cur_line_buffer [7:0], {24{1'b0}}} ;
                matrix_next_line_buffer <= {matrix_next_line_buffer[63:0], matrix_next_line_buffer[7:0], {24{1'b0}}} ;
            end else begin  // 中间像素
                matrix_last_line_buffer <= {matrix_last_line_buffer[63:0], data_d2[31:0]} ;
                matrix_cur_line_buffer  <= {matrix_cur_line_buffer [63:0], data_d1[31:0]} ;
                matrix_next_line_buffer <= {matrix_next_line_buffer[63:0], data_d0[31:0]} ;
            end  
        end
    end
    else begin
        matrix_last_line_buffer <= 'b0 ;
        matrix_cur_line_buffer  <= 'b0 ;
        matrix_next_line_buffer <= 'b0 ;
    end 
end

// 计算水平和垂直计数器
always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n || zhenghe_tuser) begin
        h_cnt <= 0;
        v_cnt <= 0;
    end else begin
        h_cnt    <= valid_d1 ? ((h_cnt == IMG_WIDTH_4x - 1) ? 0 : h_cnt + 1) : h_cnt;
        v_cnt    <= valid_d1 && (h_cnt == IMG_WIDTH_4x - 1) ? ((v_cnt == IMG_HEIGHT - 1) ? 0 : v_cnt + 1) : v_cnt;
    end
end

// 数据有效信号的延迟处理
always @(posedge I_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
        ch_valid <= 0;
        v_cnt_d <= 0;
    end else begin
        ch_valid <= valid_d1 ;
        v_cnt_d  <= v_cnt;
    end
end

assign bayer_ypos = bayer_ypos_d0 ;

// 对tuser和tlast信号进行同步处理，此时数据和流控制信号已经同步
always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        tlast_d0 <= 0;
        tlast_d1 <= 0;
        tlast_d2 <= 0;
        tuser_d0 <= 0;
        tuser_d1 <= 0;
        tuser_d2 <= 0;
    end
    else begin
        tlast_d0 <= zhenghe_tlast;
        tlast_d1 <= tlast_d0;
        tlast_d2 <= tlast_d1;
        tuser_d0 <= zhenghe_tuser;
        tuser_d1 <= tuser_d0;
        tuser_d2 <= tuser_d1;
    end
end

// 将同步后的信号输出
assign O_tuser  = tuser_d2;
assign O_tlast  = tlast_d2;
assign O_tvalid = ch_valid;


endmodule




/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
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
/**********************legacy_ui_top_demosaic ******************************
该模块主要是用于3x3矩阵的形成，以及对图像边界像素的处理
在原基础上优化了时序，把原来的一些未完全对齐的信号进行对齐。
--版本号1.0  
*****************************************************************/

module legacy_ui_top_demosaic #(
    parameter IMG_HEIGHT          = 1080,  // 图像高度
    parameter IMG_WIDTH           = 1920,  // 图像宽度
    parameter data_complete_delay = 50  ,
    parameter BAYER_MODE          = "BGGR"
)
(
    input           I_clk   		,  // 时钟信号
    input           I_rst_n 		,  // 复位信号，低有效

    input [39:0]    I_axi4s_tdata 	,  // AXI4-Stream视频数据
    input [9:0]     I_axi4s_tdest 	,
    input           I_axi4s_tlast 	,  // 行结束信号
    input           I_axi4s_tvalid	,  // 数据有效信号
    input           I_axi4s_tuser 	,  // 帧开始信号
    output          I_axi4s_tready	,  // 从模块准备好接受数据

    output          O_tlast  		,  // 输出行结束信号
    output          O_tuser  		,  // 输出帧开始信号
    output [127:0]  O_tdata  		,  // 输出数据
    output          O_tvalid 		,  // 输出数据有效信号
    input           O_tready 		   // 输出数据准备好信号
);


wire 		demosaic_tlast ; 
wire 		demosaic_tuser ; 
wire 		demosaic_tvalid; 
wire 		demosaic_tready; 

wire        bayer_ypos      ;
wire [95:0] matrix_last_line;
wire [95:0] matrix_cur_line ;
wire [95:0] matrix_next_line;

legacy_ui_raw_matrix_3x3_buffer #(
    .IMG_HEIGHT         (IMG_HEIGHT         )	,  // 图像高度
    .IMG_WIDTH          (IMG_WIDTH          )	,  // 图像宽度
    .data_complete_delay(data_complete_delay)
)X_ui_raw_matrix_3x3_buffer 
(
   .I_clk    				(I_clk   )				,  // 时钟信号
   .I_rst_n  				(I_rst_n )				,  // 复位信号，低有效

   .I_axi4s_video_tdata 	(I_axi4s_tdata )	,  // AXI4-Stream视频数据
   .I_axi4s_video_tdest 	(I_axi4s_tdest )	,
   .I_axi4s_video_tlast 	(I_axi4s_tlast )	,  // 行结束信号
   .I_axi4s_video_tvalid	(I_axi4s_tvalid)	,  // 数据有效信号
   .I_axi4s_video_tuser 	(I_axi4s_tuser )	,  // 帧开始信号
   .I_axi4s_video_tready	(I_axi4s_tready)	,  // 从模块准备好接受数据

   .O_tlast         		(demosaic_tlast )		,   // 行结束信号输出
   .O_tuser         		(demosaic_tuser )		,   // 帧开始信号输出
   .O_tvalid        		(demosaic_tvalid)		,   // 数据有效信号输出
   .O_tready        		(demosaic_tready)		,   // 上一级模块准备好接受数据
	
   .bayer_ypos      		(bayer_ypos      )		,   // Bayer滤波器行位置
   .matrix_last_line		(matrix_last_line)		,   // 上一行3x3矩阵数据
   .matrix_cur_line 		(matrix_cur_line )		,   // 当前行3x3矩阵数据
   .matrix_next_line		(matrix_next_line)		    // 下一行3x3矩阵数据
);

legacy_ui_bilinear_interpolation #(
    .BAYER_MODE 		(BAYER_MODE)
	)
X_ui_bilinear_interpolation(
	.I_clk            	(I_clk   )			,
	.I_rst_n          	(I_rst_n )			,
	
	.I_tlast      		(demosaic_tlast )  	,
	.I_tuser      		(demosaic_tuser )  	,
	.I_tvalid     		(demosaic_tvalid)  	,
	.I_tready     		(demosaic_tready)  	,
	
	.bayer_ypos       	(bayer_ypos       )	,
	.matrix_last_line 	(matrix_last_line )	,
	.matrix_cur_line  	(matrix_cur_line  )	,
	.matrix_next_line 	(matrix_next_line )	,
	
	.O_tlast 			(O_tlast )			,
	.O_tuser 			(O_tuser )			,
	.O_tdata 			(O_tdata )			,
	.O_tvalid			(O_tvalid)			,
	.O_tready			(O_tready)			

);



endmodule

/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
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
/*********legacy_ui_zhenghe ******************************
使用BRAM进行FIFO整合，并且不影响下一帧的数据传输
--版本号1.0  
*****************************************************************/

module legacy_ui_zhenghe#(
    parameter [12:0] 		IMG_WIDTH  = 640,
    parameter [12:0] 		IMG_HEIGHT = 480,
    parameter [8:0]  		DATA_WIDTH = 96 ,
    parameter [8:0]  		data_complete_delay = 50 //每行BRAM完成数据传输后与这行最后一个数据的距离
) 
(
    input                   I_clk  ,
    input                   I_rst_n,

    input                   I_tlast  ,
    input                   I_tuser  ,
    input [DATA_WIDTH-1:0]  I_tdata  ,
    input                   I_tvalid , 

    output reg              O_tlast  ,
    output reg              O_tuser  ,
    output [DATA_WIDTH-1:0] O_tdata  ,
    output reg              O_tvalid 
);

    localparam   IMG_WIDTH_4x = (IMG_WIDTH>>2);

    reg  [10:0]             addra			 ;
    reg  [10:0]             addrb			 ;
    reg                     valid_r0		 ;
    reg                     valid_r1		 ;
    reg                     I_tlast_d0		 ;
    reg                     I_tlast_d1		 ;
    reg                     I_tuser_d0		 ;
    reg                     I_tuser_d1		 ;
    reg  [13:0]             y_cnt			 ;
    reg  [20:0]             x_cnt			 ;
    reg  [DATA_WIDTH-1:0]   data_d0			 ;
    wire [DATA_WIDTH-1:0]   data_d			 ;


    wire         			flag_valid       ;
    wire [15:0]  			rd_valid_width_d0;
    wire [15:0]  			rd_valid_width_d1;
    reg          			flag_valid_d0    ;
    reg          			flag_valid_d1    ;
    reg          			flag_valid_first ;
    reg  [15:0]  			cnt_first		 ;
    reg  [15:0]  			valid_width	 	 ;
	
	wire   O_tuser_d,O_tvalid_d,O_tlast_d;
    assign O_tuser_d  = (x_cnt == rd_valid_width_d0 + 1) && (y_cnt == 0);
    assign O_tvalid_d = rd_valid;
    assign O_tdata    = data_d;
    assign O_tlast_d  = (x_cnt == rd_valid_width_d1 - 1) ;
	
    ////为了方便对后续的信号进行合理的处理，在此对部分信号进行打拍操作
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            valid_r0   <= 0;
            valid_r1   <= 0;
            I_tlast_d0 <= 0;
            I_tlast_d1 <= 0;
            data_d0    <= 0;
            I_tuser_d0 <= 0;
            I_tuser_d1 <= 0;
        end else begin
            valid_r0   <= I_tvalid;
            valid_r1   <= valid_r0;
            I_tlast_d0 <= I_tlast;
            I_tlast_d1 <= I_tlast_d0;
            data_d0    <= I_tdata;
            I_tuser_d0 <= I_tuser;
            I_tuser_d1 <= I_tuser_d0;
        end
    end  
    
    ////以每帧的第一行的数据长度作为VALID_WIDTH，为了防止可能的错误，每一帧都更新一次。
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) 
            flag_valid_first <= 0;
        else if(I_tuser )
            flag_valid_first <= 1;
        else if(I_tlast_d0)
            flag_valid_first <= 0;
    end
    
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n || I_tuser_d1) 
            cnt_first <= 0;
        else if(flag_valid_first )
            cnt_first <= cnt_first + 1;
    end

    
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n ) 
            valid_width <= IMG_WIDTH_4x;
        else if(I_tuser && (cnt_first > IMG_WIDTH_4x))
            valid_width <= cnt_first;
    end

    ////计数行数
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n || I_tuser) 
            y_cnt <= 0;
        else if(I_tlast_d0)
            y_cnt <= y_cnt + 1;
    end
    
    //从每行的第一个数据到这行的最后一个数据，flag_valid_d0处于高电平
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) 
            flag_valid_d0 <= 0;
        else if(I_tuser || I_tlast_d1)
            flag_valid_d0 <= 0;
        else if(valid_r1)
            flag_valid_d0 <= 1;
    end
    
    //从每行的最后一个数据到下一行的第一个数据，flag_valid_d1处于高电平
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n || I_tuser ) 
            flag_valid_d1 <= 0;
        else if(I_tlast)
            flag_valid_d1 <= 1;
        else if(I_tvalid)
            flag_valid_d1 <= 0;    
    end

    assign flag_valid        = flag_valid_d0 || flag_valid_d1 ;
    assign rd_valid_width_d0 = valid_width - IMG_WIDTH_4x + data_complete_delay;
    assign rd_valid_width_d1 = valid_width + data_complete_delay + 1;
    
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n || I_tuser) 
            x_cnt <= 0;
        else if(flag_valid)
            x_cnt <= x_cnt + 1;
        else 
            x_cnt <= 0;
    end
    
    assign rd_valid = (x_cnt < rd_valid_width_d1) && (x_cnt > rd_valid_width_d0);
    
    //////A端口
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n || I_tuser) begin
            addra <= 0;
        end 
        else if(valid_r0)begin
            addra <= (addra == IMG_WIDTH_4x -1) ? 'b0 : addra + 1'b1;
        end
    end

    //////B端口
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n || I_tuser) begin
            addrb <= 0;
        end 
        else if(rd_valid)begin
            addrb <= (addrb == IMG_WIDTH_4x -1) ? 'b0 : addrb + 1'b1;
        end
    end
    ui_ram_zhenghe X_ui_ram_zhenghe (
      .clka (I_clk   ),  // input wire clka
      .wea  (valid_r0),  // input wire [0 : 0] wea
      .addra(addra   ),  // input wire [10 : 0] addra
      .dia (data_d0 ),  // input wire [95 : 0] dina
      .clkb (I_clk   ),  // input wire clkb
      .addrb(addrb   ),  // input wire [10 : 0] addrb
      .dob(data_d  )   // output wire [95 : 0] doutb
    );

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            O_tuser  <= 0;
            O_tvalid <= 0;
            O_tlast  <= 0;
        end else begin
            O_tuser  <= O_tuser_d;
            O_tvalid <= O_tvalid_d;
            O_tlast  <= O_tlast_d;
        end
    end  
    
endmodule

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
/*********legacy_ui_gamma ********************************************
伽马矫正(Gamma)
--版本号1.0
*****************************************************************/
module legacy_ui_gamma #(
    parameter [4:0] GAMMA_10x = 22 // 伽玛值的十倍，默认值为22，即伽玛值为2.2
)
(
    input                   I_clk  		, // 时钟信号
    input                   I_rst_n		, // 复位信号，低电平有效

    input                   I_tlast     , // 输入数据通道的最后一个有效信号
    input                   I_tuser     , // 输入数据通道的第一个有效信号
    input [95:0]            I_tdata     , // 输入数据，总共96位，每24位表示一个像素的RGB数据
    input                   I_tvalid    , // 输入数据有效信号
    output                  I_tready    , // 输入数据准备好信号

    output                  O_tlast     , // 输出数据通道的最后一个有效信号
    output                  O_tuser     , // 输出数据通道的第一个有效信号
    output [95:0]           O_tdata     , // 输出数据，总共96位，每24位表示一个像素的RGB数据
    output                  O_tvalid    , // 输出数据有效信号
    input                   O_tready      // 输出数据准备好信号
);

/*****************************************************************
                        将输入的96位数据分解为4个像素的RGB888格式                                        
*****************************************************************/

    wire [23:0] I_tdata_r1 = I_tdata[23:0] ;     // 第1个像素的数据
    wire [23:0] I_tdata_r2 = I_tdata[47:24];     // 第2个像素的数据
    wire [23:0] I_tdata_r3 = I_tdata[71:48];     // 第3个像素的数据
    wire [23:0] I_tdata_r4 = I_tdata[95:72];     // 第4个像素的数据

    wire [7:0]  rgb888_r[3:0];                   // 定义数组，存储4个像素的R分量
    wire [7:0]  rgb888_g[3:0];                   // 定义数组，存储4个像素的G分量
    wire [7:0]  rgb888_b[3:0];                   // 定义数组，存储4个像素的B分量

    // 提取第1个像素的RGB分量
    assign   rgb888_r[0] = I_tdata_r1[16+:8];    // R分量，高8位
    assign   rgb888_g[0] = I_tdata_r1[8+:8] ;    // G分量，中8位
    assign   rgb888_b[0] = I_tdata_r1[0+:8] ;    // B分量，低8位

    // 提取第2个像素的RGB分量
    assign   rgb888_r[1] = I_tdata_r2[16+:8];
    assign   rgb888_g[1] = I_tdata_r2[8+:8] ;
    assign   rgb888_b[1] = I_tdata_r2[0+:8] ;

    // 提取第3个像素的RGB分量
    assign   rgb888_r[2] = I_tdata_r3[16+:8];
    assign   rgb888_g[2] = I_tdata_r3[8+:8] ;
    assign   rgb888_b[2] = I_tdata_r3[0+:8] ;

    // 提取第4个像素的RGB分量
    assign   rgb888_r[3] = I_tdata_r4[16+:8];
    assign   rgb888_g[3] = I_tdata_r4[8+:8] ;
    assign   rgb888_b[3] = I_tdata_r4[0+:8] ;

/*****************************************************************
                        定义中间信号                     
*****************************************************************/

    // 定义用于存储查找表(LUT)输出的信号，针对不同的伽玛值
    wire [11:0] O_LUT_2_6_data_r[3:0];
    wire [11:0] O_LUT_2_6_data_g[3:0];
    wire [11:0] O_LUT_2_6_data_b[3:0];
    
    wire [11:0] O_LUT_2_4_data_r[3:0];
    wire [11:0] O_LUT_2_4_data_g[3:0];
    wire [11:0] O_LUT_2_4_data_b[3:0];

    wire [11:0] O_LUT_2_2_data_r[3:0];
    wire [11:0] O_LUT_2_2_data_g[3:0];
    wire [11:0] O_LUT_2_2_data_b[3:0];

    wire [11:0] O_LUT_2_0_data_r[3:0];
    wire [11:0] O_LUT_2_0_data_g[3:0];
    wire [11:0] O_LUT_2_0_data_b[3:0];

    wire [11:0] O_LUT_1_8_data_r[3:0];
    wire [11:0] O_LUT_1_8_data_g[3:0];
    wire [11:0] O_LUT_1_8_data_b[3:0];

    wire [11:0] O_LUT_1_6_data_r[3:0];
    wire [11:0] O_LUT_1_6_data_g[3:0];
    wire [11:0] O_LUT_1_6_data_b[3:0];
    
    wire [11:0] O_LUT_1_4_data_r[3:0];
    wire [11:0] O_LUT_1_4_data_g[3:0];
    wire [11:0] O_LUT_1_4_data_b[3:0];
    
    wire [11:0] O_LUT_1_2_data_r[3:0];
    wire [11:0] O_LUT_1_2_data_g[3:0];
    wire [11:0] O_LUT_1_2_data_b[3:0];

    wire [11:0] O_LUT_0_8_data_r[3:0];
    wire [11:0] O_LUT_0_8_data_g[3:0];
    wire [11:0] O_LUT_0_8_data_b[3:0];

    // 定义新的RGB值
    wire  [7:0]  R_new [3:0];
    wire  [7:0]  G_new [3:0];
    wire  [7:0]  B_new [3:0];

/*****************************************************************
                        定义寄存器信号                     
*****************************************************************/

    // 用于存储选择后的LUT输出数据
    reg   [11:0]  acc_rgb888_r[3:0];
    reg   [11:0]  acc_rgb888_g[3:0];
    reg   [11:0]  acc_rgb888_b[3:0];

    // 用于同步输入的tlast、tuser和tvalid信号
    reg   [3:0]   I_tlast_r ;
    reg   [3:0]   I_tuser_r ;
    reg   [3:0]   I_tvalid_r;

    // 用于反归一化的中间变量
    reg   [20:0] acc_rgb888_r_x0[3:0];
    reg   [20:0] acc_rgb888_g_x0[3:0];
    reg   [20:0] acc_rgb888_b_x0[3:0];

    reg   [20:0] acc_rgb888_r_x1[3:0];
    reg   [20:0] acc_rgb888_g_x1[3:0];
    reg   [20:0] acc_rgb888_b_x1[3:0];

    reg   [7:0]  acc_rgb888_r_x2[3:0];
    reg   [7:0]  acc_rgb888_g_x2[3:0];
    reg   [7:0]  acc_rgb888_b_x2[3:0];

/*****************************************************************
                           伽玛查找表模块实例化                                        
*****************************************************************/
    genvar i;
    generate
        for(i = 0; i < 4; i = i + 1)
        begin: LUT
            // 针对不同的伽玛值，实例化对应的LUT模块

            // 伽玛值为2.6的LUT
            legacy_ui_lut_2_6 X_ui_lut_2_6_R(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_2_6_data(rgb888_r[i]),
                .O_LUT_2_6_data(O_LUT_2_6_data_r[i])
            );

            legacy_ui_lut_2_6 X_ui_lut_2_6_G(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_2_6_data(rgb888_g[i]),
                .O_LUT_2_6_data(O_LUT_2_6_data_g[i])
            );

            legacy_ui_lut_2_6 X_ui_lut_2_6_B(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_2_6_data(rgb888_b[i]),
                .O_LUT_2_6_data(O_LUT_2_6_data_b[i])
            );

            // 伽玛值为2.4的LUT
            legacy_ui_lut_2_4 X_ui_lut_2_4_R(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_2_4_data(rgb888_r[i]),
                .O_LUT_2_4_data(O_LUT_2_4_data_r[i])
            );

            legacy_ui_lut_2_4 X_ui_lut_2_4_G(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_2_4_data(rgb888_g[i]),
                .O_LUT_2_4_data(O_LUT_2_4_data_g[i])
            );

            legacy_ui_lut_2_4 X_ui_lut_2_4_B(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_2_4_data(rgb888_b[i]),
                .O_LUT_2_4_data(O_LUT_2_4_data_b[i])
            );

            // 伽玛值为2.2的LUT
            legacy_ui_lut_2_2 X_ui_lut_2_2_R(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_2_2_data(rgb888_r[i]),
                .O_LUT_2_2_data(O_LUT_2_2_data_r[i])
            );

            legacy_ui_lut_2_2 X_ui_lut_2_2_G(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_2_2_data(rgb888_g[i]),
                .O_LUT_2_2_data(O_LUT_2_2_data_g[i])
            );

            legacy_ui_lut_2_2 X_ui_lut_2_2_B(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_2_2_data(rgb888_b[i]),
                .O_LUT_2_2_data(O_LUT_2_2_data_b[i])
            );

            // 伽玛值为2.0的LUT
            legacy_ui_lut_2_0 X_ui_lut_2_0_R(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_2_0_data(rgb888_r[i]),
                .O_LUT_2_0_data(O_LUT_2_0_data_r[i])
            );

            legacy_ui_lut_2_0 X_ui_lut_2_0_G(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_2_0_data(rgb888_g[i]),
                .O_LUT_2_0_data(O_LUT_2_0_data_g[i])
            );

            legacy_ui_lut_2_0 X_ui_lut_2_0_B(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_2_0_data(rgb888_b[i]),
                .O_LUT_2_0_data(O_LUT_2_0_data_b[i])
            );

            // 伽玛值为1.8的LUT
            legacy_ui_lut_1_8 X_ui_lut_1_8_R(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_1_8_data(rgb888_r[i]),
                .O_LUT_1_8_data(O_LUT_1_8_data_r[i])
            );

            legacy_ui_lut_1_8 X_ui_lut_1_8_G(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_1_8_data(rgb888_g[i]),
                .O_LUT_1_8_data(O_LUT_1_8_data_g[i])
            );

            legacy_ui_lut_1_8 X_ui_lut_1_8_B(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_1_8_data(rgb888_b[i]),
                .O_LUT_1_8_data(O_LUT_1_8_data_b[i])
            );

            // 伽玛值为1.6的LUT
            legacy_ui_lut_1_6 X_ui_lut_1_6_R(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_1_6_data(rgb888_r[i]),
                .O_LUT_1_6_data(O_LUT_1_6_data_r[i])
            );

            legacy_ui_lut_1_6 X_ui_lut_1_6_G(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_1_6_data(rgb888_g[i]),
                .O_LUT_1_6_data(O_LUT_1_6_data_g[i])
            );

            legacy_ui_lut_1_6 X_ui_lut_1_6_B(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_1_6_data(rgb888_b[i]),
                .O_LUT_1_6_data(O_LUT_1_6_data_b[i])
            );

            // 伽玛值为1.4的LUT
            legacy_ui_lut_1_4 X_ui_lut_1_4_R(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_1_4_data(rgb888_r[i]),
                .O_LUT_1_4_data(O_LUT_1_4_data_r[i])
            );

            legacy_ui_lut_1_4 X_ui_lut_1_4_G(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_1_4_data(rgb888_g[i]),
                .O_LUT_1_4_data(O_LUT_1_4_data_g[i])
            );

            legacy_ui_lut_1_4 X_ui_lut_1_4_B(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_1_4_data(rgb888_b[i]),
                .O_LUT_1_4_data(O_LUT_1_4_data_b[i])
            );

            // 伽玛值为1.2的LUT
            legacy_ui_lut_1_2 X_ui_lut_1_2_R(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_1_2_data(rgb888_r[i]),
                .O_LUT_1_2_data(O_LUT_1_2_data_r[i])
            );

            legacy_ui_lut_1_2 X_ui_lut_1_2_G(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_1_2_data(rgb888_g[i]),
                .O_LUT_1_2_data(O_LUT_1_2_data_g[i])
            );

            legacy_ui_lut_1_2 X_ui_lut_1_2_B(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_1_2_data(rgb888_b[i]),
                .O_LUT_1_2_data(O_LUT_1_2_data_b[i])
            );

            // 伽玛值为0.8的LUT
            legacy_ui_lut_0_8 X_ui_lut_0_8_R(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_0_8_data(rgb888_r[i]),
                .O_LUT_0_8_data(O_LUT_0_8_data_r[i])
            );

            legacy_ui_lut_0_8 X_ui_lut_0_8_G(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_0_8_data(rgb888_g[i]),
                .O_LUT_0_8_data(O_LUT_0_8_data_g[i])
            );

            legacy_ui_lut_0_8 X_ui_lut_0_8_B(
                .I_clk         (I_clk     ),
                .I_rst_n       (I_rst_n   ),
                .I_LUT_0_8_data(rgb888_b[i]),
                .O_LUT_0_8_data(O_LUT_0_8_data_b[i])
            );

/*****************************************************************
                           选择对应的伽玛校正值                                      
*****************************************************************/

            // 根据参数GAMMA_10x选择对应的伽玛LUT输出
            always @(posedge I_clk or negedge I_rst_n)begin 
                if(!I_rst_n)begin
                    acc_rgb888_r[i] <= 12'd0;
                    acc_rgb888_g[i] <= 12'd0;
                    acc_rgb888_b[i] <= 12'd0;
                end
                else begin
                    case (GAMMA_10x)
                        5'd26:begin 
                           acc_rgb888_r[i] <= O_LUT_2_6_data_r[i];
                           acc_rgb888_g[i] <= O_LUT_2_6_data_g[i];
                           acc_rgb888_b[i] <= O_LUT_2_6_data_b[i];
                        end
                        5'd24:begin 
                           acc_rgb888_r[i] <= O_LUT_2_4_data_r[i];
                           acc_rgb888_g[i] <= O_LUT_2_4_data_g[i];
                           acc_rgb888_b[i] <= O_LUT_2_4_data_b[i];
                        end
                        5'd22:begin 
                           acc_rgb888_r[i] <= O_LUT_2_2_data_r[i];
                           acc_rgb888_g[i] <= O_LUT_2_2_data_g[i];
                           acc_rgb888_b[i] <= O_LUT_2_2_data_b[i];
                        end
                        5'd20:begin
                           acc_rgb888_r[i] <= O_LUT_2_0_data_r[i];
                           acc_rgb888_g[i] <= O_LUT_2_0_data_g[i];
                           acc_rgb888_b[i] <= O_LUT_2_0_data_b[i];
                        end
                        5'd18:begin
                           acc_rgb888_r[i] <= O_LUT_1_8_data_r[i];
                           acc_rgb888_g[i] <= O_LUT_1_8_data_g[i];
                           acc_rgb888_b[i] <= O_LUT_1_8_data_b[i];
                        end
                        5'd16:begin
                           acc_rgb888_r[i] <= O_LUT_1_6_data_r[i];
                           acc_rgb888_g[i] <= O_LUT_1_6_data_g[i];
                           acc_rgb888_b[i] <= O_LUT_1_6_data_b[i];
                        end
                        5'd14:begin
                           acc_rgb888_r[i] <= O_LUT_1_4_data_r[i];
                           acc_rgb888_g[i] <= O_LUT_1_4_data_g[i];
                           acc_rgb888_b[i] <= O_LUT_1_4_data_b[i];
                        end
                        5'd12:begin
                           acc_rgb888_r[i] <= O_LUT_1_2_data_r[i];
                           acc_rgb888_g[i] <= O_LUT_1_2_data_g[i];
                           acc_rgb888_b[i] <= O_LUT_1_2_data_b[i];
                        end
                        5'd8 :begin
                           acc_rgb888_r[i] <= O_LUT_0_8_data_r[i];
                           acc_rgb888_g[i] <= O_LUT_0_8_data_g[i];
                           acc_rgb888_b[i] <= O_LUT_0_8_data_b[i];
                        end
                        default:begin 
                           acc_rgb888_r[i] <= O_LUT_2_2_data_r[i];
                           acc_rgb888_g[i] <= O_LUT_2_2_data_g[i];
                           acc_rgb888_b[i] <= O_LUT_2_2_data_b[i];
                        end
                    endcase
                end
            end

/*****************************************************************
                           反归一化处理                                      
*****************************************************************/

            // 第一级流水线，将数据左移8位
            always @(posedge I_clk or negedge I_rst_n)begin 
                if(!I_rst_n)begin
                    acc_rgb888_r_x0[i] <= 0;
                    acc_rgb888_g_x0[i] <= 0;
                    acc_rgb888_b_x0[i] <= 0;
                end
                else if(I_tvalid_r[0])begin
                    acc_rgb888_r_x0[i] <= acc_rgb888_r[i] << 8;
                    acc_rgb888_g_x0[i] <= acc_rgb888_g[i] << 8;
                    acc_rgb888_b_x0[i] <= acc_rgb888_b[i] << 8;
                end
                else begin
                    acc_rgb888_r_x0[i] <= acc_rgb888_r_x0[i] ;
                    acc_rgb888_g_x0[i] <= acc_rgb888_g_x0[i] ;
                    acc_rgb888_b_x0[i] <= acc_rgb888_b_x0[i] ;
                end
            end
        
            // 第二级流水线，减去2048，实现反归一化
            always @(posedge I_clk or negedge I_rst_n)begin 
                if(!I_rst_n)begin
                    acc_rgb888_r_x1[i] <= 0;
                    acc_rgb888_g_x1[i] <= 0;
                    acc_rgb888_b_x1[i] <= 0;
                end
                else if(I_tvalid_r[1])begin
                    acc_rgb888_r_x1[i] <= acc_rgb888_r_x0[i] - 2048;
                    acc_rgb888_g_x1[i] <= acc_rgb888_g_x0[i] - 2048;
                    acc_rgb888_b_x1[i] <= acc_rgb888_b_x0[i] - 2048;
                end
                else begin
                    acc_rgb888_r_x1[i] <= acc_rgb888_r_x1[i];
                    acc_rgb888_g_x1[i] <= acc_rgb888_g_x1[i];
                    acc_rgb888_b_x1[i] <= acc_rgb888_b_x1[i];
                end
            end
    
            // 第三级流水线，限制RGB值的范围，防止溢出
            always @(posedge I_clk or negedge I_rst_n)begin 
                if(!I_rst_n)begin
                    acc_rgb888_r_x2[i] <= 0;
                    acc_rgb888_g_x2[i] <= 0;
                    acc_rgb888_b_x2[i] <= 0;
                end
                else if(I_tvalid_r[2])begin
                    acc_rgb888_r_x2[i] <= (acc_rgb888_r_x1[i][20]) ? 8'd255 : (acc_rgb888_r_x1[i][19:12]);
                    acc_rgb888_g_x2[i] <= (acc_rgb888_g_x1[i][20]) ? 8'd255 : (acc_rgb888_g_x1[i][19:12]);
                    acc_rgb888_b_x2[i] <= (acc_rgb888_b_x1[i][20]) ? 8'd255 : (acc_rgb888_b_x1[i][19:12]);
                end
                else begin
                    acc_rgb888_r_x2[i] <= acc_rgb888_r_x2[i];
                    acc_rgb888_g_x2[i] <= acc_rgb888_g_x2[i];
                    acc_rgb888_b_x2[i] <= acc_rgb888_b_x2[i];
                end
            end

/*****************************************************************
                            获取新的RGB值                                      
*****************************************************************/

            // 将反归一化并限制后的值赋给新的RGB值
            assign R_new[i] = acc_rgb888_r_x2[i];
            assign G_new[i] = acc_rgb888_g_x2[i];
            assign B_new[i] = acc_rgb888_b_x2[i];

        end
    endgenerate

/*****************************************************************
                            同步信号处理                                      
*****************************************************************/

    // 对输入的控制信号进行同步，延迟4个时钟周期，与数据对齐
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            {I_tlast_r,I_tuser_r,I_tvalid_r} <= 0;
        else begin
            I_tlast_r <= {I_tlast_r[2:0],I_tlast};
            I_tuser_r <= {I_tuser_r[2:0],I_tuser};
            I_tvalid_r <= {I_tvalid_r[2:0],I_tvalid};
        end
    end

    // 将同步后的控制信号赋给输出
    assign  O_tlast  = I_tlast_r[3];   
    assign  O_tuser  = I_tuser_r[3];   
    assign  O_tvalid = I_tvalid_r[3];

    // 将新的RGB值组合成输出数据
    assign O_tdata = {R_new[3],G_new[3],B_new[3],
                      R_new[2],G_new[2],B_new[2],
                      R_new[1],G_new[1],B_new[1],
                      R_new[0],G_new[0],B_new[0]};

    // 将输入的准备好信号直接连接到输出的准备好信号
    assign  I_tready = O_tready;

endmodule

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
/*********legacy_ui_lut_0_8 ********************************************
@Description :   gamma=0.8
*****************************************************************/
module legacy_ui_lut_0_8 (
    input                          I_clk  ,
    input                          I_rst_n,

    input      [7:0]               I_LUT_0_8_data,
    output reg [11:0]              O_LUT_0_8_data  
);

    always @(*)begin 
        case (I_LUT_0_8_data)
                0:   O_LUT_0_8_data = 12'd1; 
                1:   O_LUT_0_8_data = 12'd6;
                2:   O_LUT_0_8_data = 12'd12;
                3:   O_LUT_0_8_data = 12'd19;
                4:   O_LUT_0_8_data = 12'd26;
                5:   O_LUT_0_8_data = 12'd33;
                6:   O_LUT_0_8_data = 12'd41;
                7:   O_LUT_0_8_data = 12'd49;
                8:   O_LUT_0_8_data = 12'd58;
                9:   O_LUT_0_8_data = 12'd66;
                10:  O_LUT_0_8_data = 12'd75;
                11:  O_LUT_0_8_data = 12'd84;
                12:  O_LUT_0_8_data = 12'd94;
                13:  O_LUT_0_8_data = 12'd103;
                14:  O_LUT_0_8_data = 12'd113;
                15:  O_LUT_0_8_data = 12'd123;
                16:  O_LUT_0_8_data = 12'd133;
                17:  O_LUT_0_8_data = 12'd143;
                18:  O_LUT_0_8_data = 12'd153;
                19:  O_LUT_0_8_data = 12'd163;
                20:  O_LUT_0_8_data = 12'd174;
                21:  O_LUT_0_8_data = 12'd185;
                22:  O_LUT_0_8_data = 12'd196;
                23:  O_LUT_0_8_data = 12'd206;
                24:  O_LUT_0_8_data = 12'd218;
                25:  O_LUT_0_8_data = 12'd229;
                26:  O_LUT_0_8_data = 12'd240;
                27:  O_LUT_0_8_data = 12'd251;
                28:  O_LUT_0_8_data = 12'd263;
                29:  O_LUT_0_8_data = 12'd275;
                30:  O_LUT_0_8_data = 12'd286;
                31:  O_LUT_0_8_data = 12'd298;
                32:  O_LUT_0_8_data = 12'd310;
                33:  O_LUT_0_8_data = 12'd322;
                34:  O_LUT_0_8_data = 12'd334;
                35:  O_LUT_0_8_data = 12'd346;
                36:  O_LUT_0_8_data = 12'd358;
                37:  O_LUT_0_8_data = 12'd371;
                38:  O_LUT_0_8_data = 12'd383;
                39:  O_LUT_0_8_data = 12'd396;
                40:  O_LUT_0_8_data = 12'd408;
                41:  O_LUT_0_8_data = 12'd421;
                42:  O_LUT_0_8_data = 12'd434;
                43:  O_LUT_0_8_data = 12'd446;
                44:  O_LUT_0_8_data = 12'd459;
                45:  O_LUT_0_8_data = 12'd472;
                46:  O_LUT_0_8_data = 12'd485;
                47:  O_LUT_0_8_data = 12'd498;
                48:  O_LUT_0_8_data = 12'd511;
                49:  O_LUT_0_8_data = 12'd525;
                50:  O_LUT_0_8_data = 12'd538;
                51:  O_LUT_0_8_data = 12'd551;
                52:  O_LUT_0_8_data = 12'd565;
                53:  O_LUT_0_8_data = 12'd578;
                54:  O_LUT_0_8_data = 12'd592;
                55:  O_LUT_0_8_data = 12'd605;
                56:  O_LUT_0_8_data = 12'd619;
                57:  O_LUT_0_8_data = 12'd633;
                58:  O_LUT_0_8_data = 12'd647;
                59:  O_LUT_0_8_data = 12'd661;
                60:  O_LUT_0_8_data = 12'd674;
                61:  O_LUT_0_8_data = 12'd688;
                62:  O_LUT_0_8_data = 12'd702;
                63:  O_LUT_0_8_data = 12'd717;
                64:  O_LUT_0_8_data = 12'd731;
                65:  O_LUT_0_8_data = 12'd745;
                66:  O_LUT_0_8_data = 12'd759;
                67:  O_LUT_0_8_data = 12'd773;
                68:  O_LUT_0_8_data = 12'd788;
                69:  O_LUT_0_8_data = 12'd802;
                70:  O_LUT_0_8_data = 12'd817;
                71:  O_LUT_0_8_data = 12'd831;
                72:  O_LUT_0_8_data = 12'd846;
                73:  O_LUT_0_8_data = 12'd860;
                74:  O_LUT_0_8_data = 12'd875;
                75:  O_LUT_0_8_data = 12'd890;
                76:  O_LUT_0_8_data = 12'd904;
                77:  O_LUT_0_8_data = 12'd919;
                78:  O_LUT_0_8_data = 12'd934;
                79:  O_LUT_0_8_data = 12'd949;
                80:  O_LUT_0_8_data = 12'd964;
                81:  O_LUT_0_8_data = 12'd979;
                82:  O_LUT_0_8_data = 12'd994;
                83:  O_LUT_0_8_data = 12'd1009;
                84:  O_LUT_0_8_data = 12'd1024;
                85:  O_LUT_0_8_data = 12'd1039;
                86:  O_LUT_0_8_data = 12'd1055;
                87:  O_LUT_0_8_data = 12'd1070;
                88:  O_LUT_0_8_data = 12'd1085;
                89:  O_LUT_0_8_data = 12'd1101;
                90:  O_LUT_0_8_data = 12'd1116;
                91:  O_LUT_0_8_data = 12'd1131;
                92:  O_LUT_0_8_data = 12'd1147;
                93:  O_LUT_0_8_data = 12'd1162;
                94:  O_LUT_0_8_data = 12'd1178;
                95:  O_LUT_0_8_data = 12'd1194;
                96:  O_LUT_0_8_data = 12'd1209;
                97:  O_LUT_0_8_data = 12'd1225;
                98:  O_LUT_0_8_data = 12'd1241;
                99:  O_LUT_0_8_data = 12'd1257;
                100: O_LUT_0_8_data = 12'd1272;
                101: O_LUT_0_8_data = 12'd1288;
                102: O_LUT_0_8_data = 12'd1304;
                103: O_LUT_0_8_data = 12'd1320;
                104: O_LUT_0_8_data = 12'd1336;
                105: O_LUT_0_8_data = 12'd1352;
                106: O_LUT_0_8_data = 12'd1368;
                107: O_LUT_0_8_data = 12'd1384;
                108: O_LUT_0_8_data = 12'd1400;
                109: O_LUT_0_8_data = 12'd1416;
                110: O_LUT_0_8_data = 12'd1433;
                111: O_LUT_0_8_data = 12'd1449;
                112: O_LUT_0_8_data = 12'd1465;
                113: O_LUT_0_8_data = 12'd1481;
                114: O_LUT_0_8_data = 12'd1498;
                115: O_LUT_0_8_data = 12'd1514;
                116: O_LUT_0_8_data = 12'd1530;
                117: O_LUT_0_8_data = 12'd1547;
                118: O_LUT_0_8_data = 12'd1563;
                119: O_LUT_0_8_data = 12'd1580;
                120: O_LUT_0_8_data = 12'd1596;
                121: O_LUT_0_8_data = 12'd1613;
                122: O_LUT_0_8_data = 12'd1630;
                123: O_LUT_0_8_data = 12'd1646;
                124: O_LUT_0_8_data = 12'd1663;
                125: O_LUT_0_8_data = 12'd1680;
                126: O_LUT_0_8_data = 12'd1696;
                127: O_LUT_0_8_data = 12'd1713;
                128: O_LUT_0_8_data = 12'd1730;
                129: O_LUT_0_8_data = 12'd1747;
                130: O_LUT_0_8_data = 12'd1764;
                131: O_LUT_0_8_data = 12'd1781;
                132: O_LUT_0_8_data = 12'd1798;
                133: O_LUT_0_8_data = 12'd1815;
                134: O_LUT_0_8_data = 12'd1832;
                135: O_LUT_0_8_data = 12'd1849;
                136: O_LUT_0_8_data = 12'd1866;
                137: O_LUT_0_8_data = 12'd1883;
                138: O_LUT_0_8_data = 12'd1900;
                139: O_LUT_0_8_data = 12'd1917;
                140: O_LUT_0_8_data = 12'd1934;
                141: O_LUT_0_8_data = 12'd1952;
                142: O_LUT_0_8_data = 12'd1969;
                143: O_LUT_0_8_data = 12'd1986;
                144: O_LUT_0_8_data = 12'd2003;
                145: O_LUT_0_8_data = 12'd2021;
                146: O_LUT_0_8_data = 12'd2038;
                147: O_LUT_0_8_data = 12'd2056;
                148: O_LUT_0_8_data = 12'd2073;
                149: O_LUT_0_8_data = 12'd2091;
                150: O_LUT_0_8_data = 12'd2108;
                151: O_LUT_0_8_data = 12'd2126;
                152: O_LUT_0_8_data = 12'd2143;
                153: O_LUT_0_8_data = 12'd2161;
                154: O_LUT_0_8_data = 12'd2178;
                155: O_LUT_0_8_data = 12'd2196;
                156: O_LUT_0_8_data = 12'd2214;
                157: O_LUT_0_8_data = 12'd2231;
                158: O_LUT_0_8_data = 12'd2249;
                159: O_LUT_0_8_data = 12'd2267;
                160: O_LUT_0_8_data = 12'd2285;
                161: O_LUT_0_8_data = 12'd2302;
                162: O_LUT_0_8_data = 12'd2320;
                163: O_LUT_0_8_data = 12'd2338;
                164: O_LUT_0_8_data = 12'd2356;
                165: O_LUT_0_8_data = 12'd2374;
                166: O_LUT_0_8_data = 12'd2392;
                167: O_LUT_0_8_data = 12'd2410;
                168: O_LUT_0_8_data = 12'd2428;
                169: O_LUT_0_8_data = 12'd2446;
                170: O_LUT_0_8_data = 12'd2464;
                171: O_LUT_0_8_data = 12'd2482;
                172: O_LUT_0_8_data = 12'd2500;
                173: O_LUT_0_8_data = 12'd2518;
                174: O_LUT_0_8_data = 12'd2536;
                175: O_LUT_0_8_data = 12'd2555;
                176: O_LUT_0_8_data = 12'd2573;
                177: O_LUT_0_8_data = 12'd2591;
                178: O_LUT_0_8_data = 12'd2609;
                179: O_LUT_0_8_data = 12'd2628;
                180: O_LUT_0_8_data = 12'd2646;
                181: O_LUT_0_8_data = 12'd2664;
                182: O_LUT_0_8_data = 12'd2683;
                183: O_LUT_0_8_data = 12'd2701;
                184: O_LUT_0_8_data = 12'd2719;
                185: O_LUT_0_8_data = 12'd2738;
                186: O_LUT_0_8_data = 12'd2756;
                187: O_LUT_0_8_data = 12'd2775;
                188: O_LUT_0_8_data = 12'd2793;
                189: O_LUT_0_8_data = 12'd2812;
                190: O_LUT_0_8_data = 12'd2830;
                191: O_LUT_0_8_data = 12'd2849;
                192: O_LUT_0_8_data = 12'd2868;
                193: O_LUT_0_8_data = 12'd2886;
                194: O_LUT_0_8_data = 12'd2905;
                195: O_LUT_0_8_data = 12'd2924;
                196: O_LUT_0_8_data = 12'd2942;
                197: O_LUT_0_8_data = 12'd2961;
                198: O_LUT_0_8_data = 12'd2980;
                199: O_LUT_0_8_data = 12'd2999;
                200: O_LUT_0_8_data = 12'd3017;
                201: O_LUT_0_8_data = 12'd3036;
                202: O_LUT_0_8_data = 12'd3055;
                203: O_LUT_0_8_data = 12'd3074;
                204: O_LUT_0_8_data = 12'd3093;
                205: O_LUT_0_8_data = 12'd3112;
                206: O_LUT_0_8_data = 12'd3131;
                207: O_LUT_0_8_data = 12'd3150;
                208: O_LUT_0_8_data = 12'd3169;
                209: O_LUT_0_8_data = 12'd3188;
                210: O_LUT_0_8_data = 12'd3207;
                211: O_LUT_0_8_data = 12'd3226;
                212: O_LUT_0_8_data = 12'd3245;
                213: O_LUT_0_8_data = 12'd3264;
                214: O_LUT_0_8_data = 12'd3283;
                215: O_LUT_0_8_data = 12'd3302;
                216: O_LUT_0_8_data = 12'd3321;
                217: O_LUT_0_8_data = 12'd3341;
                218: O_LUT_0_8_data = 12'd3360;
                219: O_LUT_0_8_data = 12'd3379;
                220: O_LUT_0_8_data = 12'd3398;
                221: O_LUT_0_8_data = 12'd3418;
                222: O_LUT_0_8_data = 12'd3437;
                223: O_LUT_0_8_data = 12'd3456;
                224: O_LUT_0_8_data = 12'd3476;
                225: O_LUT_0_8_data = 12'd3495;
                226: O_LUT_0_8_data = 12'd3514;
                227: O_LUT_0_8_data = 12'd3534;
                228: O_LUT_0_8_data = 12'd3553;
                229: O_LUT_0_8_data = 12'd3573;
                230: O_LUT_0_8_data = 12'd3592;
                231: O_LUT_0_8_data = 12'd3612;
                232: O_LUT_0_8_data = 12'd3631;
                233: O_LUT_0_8_data = 12'd3651;
                234: O_LUT_0_8_data = 12'd3670;
                235: O_LUT_0_8_data = 12'd3690;
                236: O_LUT_0_8_data = 12'd3709;
                237: O_LUT_0_8_data = 12'd3729;
                238: O_LUT_0_8_data = 12'd3749;
                239: O_LUT_0_8_data = 12'd3768;
                240: O_LUT_0_8_data = 12'd3788;
                241: O_LUT_0_8_data = 12'd3808;
                242: O_LUT_0_8_data = 12'd3827;
                243: O_LUT_0_8_data = 12'd3847;
                244: O_LUT_0_8_data = 12'd3867;
                245: O_LUT_0_8_data = 12'd3887;
                246: O_LUT_0_8_data = 12'd3906;
                247: O_LUT_0_8_data = 12'd3926;
                248: O_LUT_0_8_data = 12'd3946;
                249: O_LUT_0_8_data = 12'd3966;
                250: O_LUT_0_8_data = 12'd3986;
                251: O_LUT_0_8_data = 12'd4006;
                252: O_LUT_0_8_data = 12'd4026;
                253: O_LUT_0_8_data = 12'd4046;
                254: O_LUT_0_8_data = 12'd4066;
                255: O_LUT_0_8_data = 12'd4086;
            default: O_LUT_0_8_data = 12'd4089;
        endcase
    end
    
endmodule
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
/*********legacy_ui_lut_1_2 ********************************************
@Description :   gamma=1.2
*****************************************************************/
module legacy_ui_lut_1_2 (
    input                    I_clk  ,
    input                    I_rst_n,

    input      [7:0]               I_LUT_1_2_data  ,
    output reg [11:0]              O_LUT_1_2_data  
);

    always @(*)begin 
        case (I_LUT_1_2_data)
                0:   O_LUT_1_2_data = 12'd23;
                1:   O_LUT_1_2_data = 12'd57;
                2:   O_LUT_1_2_data = 12'd87;
                3:   O_LUT_1_2_data = 12'd116;
                4:   O_LUT_1_2_data = 12'd143;
                5:   O_LUT_1_2_data = 12'd169;
                6:   O_LUT_1_2_data = 12'd194;
                7:   O_LUT_1_2_data = 12'd218;
                8:   O_LUT_1_2_data = 12'd242;
                9:   O_LUT_1_2_data = 12'd266;
                10:  O_LUT_1_2_data = 12'd289;
                11:  O_LUT_1_2_data = 12'd311;
                12:  O_LUT_1_2_data = 12'd334;
                13:  O_LUT_1_2_data = 12'd356;
                14:  O_LUT_1_2_data = 12'd377;
                15:  O_LUT_1_2_data = 12'd399;
                16:  O_LUT_1_2_data = 12'd420;
                17:  O_LUT_1_2_data = 12'd441;
                18:  O_LUT_1_2_data = 12'd462;
                19:  O_LUT_1_2_data = 12'd483;
                20:  O_LUT_1_2_data = 12'd503;
                21:  O_LUT_1_2_data = 12'd524;
                22:  O_LUT_1_2_data = 12'd544;
                23:  O_LUT_1_2_data = 12'd564;
                24:  O_LUT_1_2_data = 12'd584;
                25:  O_LUT_1_2_data = 12'd603;
                26:  O_LUT_1_2_data = 12'd623;
                27:  O_LUT_1_2_data = 12'd642;
                28:  O_LUT_1_2_data = 12'd662;
                29:  O_LUT_1_2_data = 12'd681;
                30:  O_LUT_1_2_data = 12'd700;
                31:  O_LUT_1_2_data = 12'd719;
                32:  O_LUT_1_2_data = 12'd738;
                33:  O_LUT_1_2_data = 12'd757;
                34:  O_LUT_1_2_data = 12'd776;
                35:  O_LUT_1_2_data = 12'd794;
                36:  O_LUT_1_2_data = 12'd813;
                37:  O_LUT_1_2_data = 12'd831;
                38:  O_LUT_1_2_data = 12'd850;
                39:  O_LUT_1_2_data = 12'd868;
                40:  O_LUT_1_2_data = 12'd886;
                41:  O_LUT_1_2_data = 12'd904;
                42:  O_LUT_1_2_data = 12'd922;
                43:  O_LUT_1_2_data = 12'd940;
                44:  O_LUT_1_2_data = 12'd958;
                45:  O_LUT_1_2_data = 12'd976;
                46:  O_LUT_1_2_data = 12'd994;
                47:  O_LUT_1_2_data = 12'd1011;
                48:  O_LUT_1_2_data = 12'd1029;
                49:  O_LUT_1_2_data = 12'd1047;
                50:  O_LUT_1_2_data = 12'd1064;
                51:  O_LUT_1_2_data = 12'd1082;
                52:  O_LUT_1_2_data = 12'd1099;
                53:  O_LUT_1_2_data = 12'd1117;
                54:  O_LUT_1_2_data = 12'd1134;
                55:  O_LUT_1_2_data = 12'd1151;
                56:  O_LUT_1_2_data = 12'd1168;
                57:  O_LUT_1_2_data = 12'd1185;
                58:  O_LUT_1_2_data = 12'd1202;
                59:  O_LUT_1_2_data = 12'd1220;
                60:  O_LUT_1_2_data = 12'd1237;
                61:  O_LUT_1_2_data = 12'd1253;
                62:  O_LUT_1_2_data = 12'd1270;
                63:  O_LUT_1_2_data = 12'd1287;
                64:  O_LUT_1_2_data = 12'd1304;
                65:  O_LUT_1_2_data = 12'd1321;
                66:  O_LUT_1_2_data = 12'd1338;
                67:  O_LUT_1_2_data = 12'd1354;
                68:  O_LUT_1_2_data = 12'd1371;
                69:  O_LUT_1_2_data = 12'd1387;
                70:  O_LUT_1_2_data = 12'd1404;
                71:  O_LUT_1_2_data = 12'd1421;
                72:  O_LUT_1_2_data = 12'd1437;
                73:  O_LUT_1_2_data = 12'd1453;
                74:  O_LUT_1_2_data = 12'd1470;
                75:  O_LUT_1_2_data = 12'd1486;
                76:  O_LUT_1_2_data = 12'd1503;
                77:  O_LUT_1_2_data = 12'd1519;
                78:  O_LUT_1_2_data = 12'd1535;
                79:  O_LUT_1_2_data = 12'd1551;
                80:  O_LUT_1_2_data = 12'd1567;
                81:  O_LUT_1_2_data = 12'd1584;
                82:  O_LUT_1_2_data = 12'd1600;
                83:  O_LUT_1_2_data = 12'd1616;
                84:  O_LUT_1_2_data = 12'd1632;
                85:  O_LUT_1_2_data = 12'd1648;
                86:  O_LUT_1_2_data = 12'd1664;
                87:  O_LUT_1_2_data = 12'd1680;
                88:  O_LUT_1_2_data = 12'd1696;
                89:  O_LUT_1_2_data = 12'd1712;
                90:  O_LUT_1_2_data = 12'd1727;
                91:  O_LUT_1_2_data = 12'd1743;
                92:  O_LUT_1_2_data = 12'd1759;
                93:  O_LUT_1_2_data = 12'd1775;
                94:  O_LUT_1_2_data = 12'd1791;
                95:  O_LUT_1_2_data = 12'd1806;
                96:  O_LUT_1_2_data = 12'd1822;
                97:  O_LUT_1_2_data = 12'd1838;
                98:  O_LUT_1_2_data = 12'd1853;
                99:  O_LUT_1_2_data = 12'd1869;
                100: O_LUT_1_2_data = 12'd1885;
                101: O_LUT_1_2_data = 12'd1900;
                102: O_LUT_1_2_data = 12'd1916;
                103: O_LUT_1_2_data = 12'd1931;
                104: O_LUT_1_2_data = 12'd1947;
                105: O_LUT_1_2_data = 12'd1962;
                106: O_LUT_1_2_data = 12'd1977;
                107: O_LUT_1_2_data = 12'd1993;
                108: O_LUT_1_2_data = 12'd2008;
                109: O_LUT_1_2_data = 12'd2024;
                110: O_LUT_1_2_data = 12'd2039;
                111: O_LUT_1_2_data = 12'd2054;
                112: O_LUT_1_2_data = 12'd2070;
                113: O_LUT_1_2_data = 12'd2085;
                114: O_LUT_1_2_data = 12'd2100;
                115: O_LUT_1_2_data = 12'd2115;
                116: O_LUT_1_2_data = 12'd2130;
                117: O_LUT_1_2_data = 12'd2146;
                118: O_LUT_1_2_data = 12'd2161;
                119: O_LUT_1_2_data = 12'd2176;
                120: O_LUT_1_2_data = 12'd2191;
                121: O_LUT_1_2_data = 12'd2206;
                122: O_LUT_1_2_data = 12'd2221;
                123: O_LUT_1_2_data = 12'd2236;
                124: O_LUT_1_2_data = 12'd2251;
                125: O_LUT_1_2_data = 12'd2266;
                126: O_LUT_1_2_data = 12'd2281;
                127: O_LUT_1_2_data = 12'd2296;
                128: O_LUT_1_2_data = 12'd2311;
                129: O_LUT_1_2_data = 12'd2326;
                130: O_LUT_1_2_data = 12'd2341;
                131: O_LUT_1_2_data = 12'd2356;
                132: O_LUT_1_2_data = 12'd2371;
                133: O_LUT_1_2_data = 12'd2385;
                134: O_LUT_1_2_data = 12'd2400;
                135: O_LUT_1_2_data = 12'd2415;
                136: O_LUT_1_2_data = 12'd2430;
                137: O_LUT_1_2_data = 12'd2445;
                138: O_LUT_1_2_data = 12'd2459;
                139: O_LUT_1_2_data = 12'd2474;
                140: O_LUT_1_2_data = 12'd2489;
                141: O_LUT_1_2_data = 12'd2504;
                142: O_LUT_1_2_data = 12'd2518;
                143: O_LUT_1_2_data = 12'd2533;
                144: O_LUT_1_2_data = 12'd2548;
                145: O_LUT_1_2_data = 12'd2562;
                146: O_LUT_1_2_data = 12'd2577;
                147: O_LUT_1_2_data = 12'd2591;
                148: O_LUT_1_2_data = 12'd2606;
                149: O_LUT_1_2_data = 12'd2621;
                150: O_LUT_1_2_data = 12'd2635;
                151: O_LUT_1_2_data = 12'd2650;
                152: O_LUT_1_2_data = 12'd2664;
                153: O_LUT_1_2_data = 12'd2679;
                154: O_LUT_1_2_data = 12'd2693;
                155: O_LUT_1_2_data = 12'd2708;
                156: O_LUT_1_2_data = 12'd2722;
                157: O_LUT_1_2_data = 12'd2736;
                158: O_LUT_1_2_data = 12'd2751;
                159: O_LUT_1_2_data = 12'd2765;
                160: O_LUT_1_2_data = 12'd2780;
                161: O_LUT_1_2_data = 12'd2794;
                162: O_LUT_1_2_data = 12'd2808;
                163: O_LUT_1_2_data = 12'd2823;
                164: O_LUT_1_2_data = 12'd2837;
                165: O_LUT_1_2_data = 12'd2851;
                166: O_LUT_1_2_data = 12'd2866;
                167: O_LUT_1_2_data = 12'd2880;
                168: O_LUT_1_2_data = 12'd2894;
                169: O_LUT_1_2_data = 12'd2908;
                170: O_LUT_1_2_data = 12'd2923;
                171: O_LUT_1_2_data = 12'd2937;
                172: O_LUT_1_2_data = 12'd2951;
                173: O_LUT_1_2_data = 12'd2965;
                174: O_LUT_1_2_data = 12'd2979;
                175: O_LUT_1_2_data = 12'd2994;
                176: O_LUT_1_2_data = 12'd3008;
                177: O_LUT_1_2_data = 12'd3022;
                178: O_LUT_1_2_data = 12'd3036;
                179: O_LUT_1_2_data = 12'd3050;
                180: O_LUT_1_2_data = 12'd3064;
                181: O_LUT_1_2_data = 12'd3078;
                182: O_LUT_1_2_data = 12'd3092;
                183: O_LUT_1_2_data = 12'd3106;
                184: O_LUT_1_2_data = 12'd3121;
                185: O_LUT_1_2_data = 12'd3135;
                186: O_LUT_1_2_data = 12'd3149;
                187: O_LUT_1_2_data = 12'd3163;
                188: O_LUT_1_2_data = 12'd3177;
                189: O_LUT_1_2_data = 12'd3191;
                190: O_LUT_1_2_data = 12'd3205;
                191: O_LUT_1_2_data = 12'd3218;
                192: O_LUT_1_2_data = 12'd3232;
                193: O_LUT_1_2_data = 12'd3246;
                194: O_LUT_1_2_data = 12'd3260;
                195: O_LUT_1_2_data = 12'd3274;
                196: O_LUT_1_2_data = 12'd3288;
                197: O_LUT_1_2_data = 12'd3302;
                198: O_LUT_1_2_data = 12'd3316;
                199: O_LUT_1_2_data = 12'd3330;
                200: O_LUT_1_2_data = 12'd3344;
                201: O_LUT_1_2_data = 12'd3357;
                202: O_LUT_1_2_data = 12'd3371;
                203: O_LUT_1_2_data = 12'd3385;
                204: O_LUT_1_2_data = 12'd3399;
                205: O_LUT_1_2_data = 12'd3413;
                206: O_LUT_1_2_data = 12'd3426;
                207: O_LUT_1_2_data = 12'd3440;
                208: O_LUT_1_2_data = 12'd3454;
                209: O_LUT_1_2_data = 12'd3468;
                210: O_LUT_1_2_data = 12'd3481;
                211: O_LUT_1_2_data = 12'd3495;
                212: O_LUT_1_2_data = 12'd3509;
                213: O_LUT_1_2_data = 12'd3523;
                214: O_LUT_1_2_data = 12'd3536;
                215: O_LUT_1_2_data = 12'd3550;
                216: O_LUT_1_2_data = 12'd3564;
                217: O_LUT_1_2_data = 12'd3577;
                218: O_LUT_1_2_data = 12'd3591;
                219: O_LUT_1_2_data = 12'd3605;
                220: O_LUT_1_2_data = 12'd3618;
                221: O_LUT_1_2_data = 12'd3632;
                222: O_LUT_1_2_data = 12'd3645;
                223: O_LUT_1_2_data = 12'd3659;
                224: O_LUT_1_2_data = 12'd3673;
                225: O_LUT_1_2_data = 12'd3686;
                226: O_LUT_1_2_data = 12'd3700;
                227: O_LUT_1_2_data = 12'd3713;
                228: O_LUT_1_2_data = 12'd3727;
                229: O_LUT_1_2_data = 12'd3740;
                230: O_LUT_1_2_data = 12'd3754;
                231: O_LUT_1_2_data = 12'd3767;
                232: O_LUT_1_2_data = 12'd3781;
                233: O_LUT_1_2_data = 12'd3794;
                234: O_LUT_1_2_data = 12'd3808;
                235: O_LUT_1_2_data = 12'd3821;
                236: O_LUT_1_2_data = 12'd3835;
                237: O_LUT_1_2_data = 12'd3848;
                238: O_LUT_1_2_data = 12'd3862;
                239: O_LUT_1_2_data = 12'd3875;
                240: O_LUT_1_2_data = 12'd3889;
                241: O_LUT_1_2_data = 12'd3902;
                242: O_LUT_1_2_data = 12'd3915;
                243: O_LUT_1_2_data = 12'd3929;
                244: O_LUT_1_2_data = 12'd3942;
                245: O_LUT_1_2_data = 12'd3956;
                246: O_LUT_1_2_data = 12'd3969;
                247: O_LUT_1_2_data = 12'd3982;
                248: O_LUT_1_2_data = 12'd3996;
                249: O_LUT_1_2_data = 12'd4009;
                250: O_LUT_1_2_data = 12'd4022;
                251: O_LUT_1_2_data = 12'd4036;
                252: O_LUT_1_2_data = 12'd4049;
                253: O_LUT_1_2_data = 12'd4062;
                254: O_LUT_1_2_data = 12'd4076;
                255: O_LUT_1_2_data = 12'd4089;
            default: O_LUT_1_2_data = 12'd4089;
        endcase
    end
    
endmodule
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
/*********legacy_ui_lut_1_4 ********************************************
@Description :   gamma=1.4
*****************************************************************/
module legacy_ui_lut_1_4 (
    input                    I_clk  ,
    input                    I_rst_n,

    input      [7:0]               I_LUT_1_4_data  ,
    output reg [11:0]              O_LUT_1_4_data  
);

    always @(*)begin 
        case (I_LUT_1_4_data)
                0:   O_LUT_1_4_data = 12'd48 ;
                1:   O_LUT_1_4_data = 12'd106;
                2:   O_LUT_1_4_data = 12'd153;
                3:   O_LUT_1_4_data = 12'd194;
                4:   O_LUT_1_4_data = 12'd232;
                5:   O_LUT_1_4_data = 12'd268;
                6:   O_LUT_1_4_data = 12'd301;
                7:   O_LUT_1_4_data = 12'd334;
                8:   O_LUT_1_4_data = 12'd365;
                9:   O_LUT_1_4_data = 12'd395;
                10:  O_LUT_1_4_data = 12'd424;
                11:  O_LUT_1_4_data = 12'd452;
                12:  O_LUT_1_4_data = 12'd480;
                13:  O_LUT_1_4_data = 12'd507;
                14:  O_LUT_1_4_data = 12'd533;
                15:  O_LUT_1_4_data = 12'd559;
                16:  O_LUT_1_4_data = 12'd584;
                17:  O_LUT_1_4_data = 12'd609;
                18:  O_LUT_1_4_data = 12'd634;
                19:  O_LUT_1_4_data = 12'd658;
                20:  O_LUT_1_4_data = 12'd682;
                21:  O_LUT_1_4_data = 12'd705;
                22:  O_LUT_1_4_data = 12'd728;
                23:  O_LUT_1_4_data = 12'd751;
                24:  O_LUT_1_4_data = 12'd774;
                25:  O_LUT_1_4_data = 12'd796;
                26:  O_LUT_1_4_data = 12'd818;
                27:  O_LUT_1_4_data = 12'd840;
                28:  O_LUT_1_4_data = 12'd861;
                29:  O_LUT_1_4_data = 12'd883;
                30:  O_LUT_1_4_data = 12'd904;
                31:  O_LUT_1_4_data = 12'd925;
                32:  O_LUT_1_4_data = 12'd946;
                33:  O_LUT_1_4_data = 12'd966;
                34:  O_LUT_1_4_data = 12'd987;
                35:  O_LUT_1_4_data = 12'd1007;
                36:  O_LUT_1_4_data = 12'd1027;
                37:  O_LUT_1_4_data = 12'd1047;
                38:  O_LUT_1_4_data = 12'd1067;
                39:  O_LUT_1_4_data = 12'd1086;
                40:  O_LUT_1_4_data = 12'd1106;
                41:  O_LUT_1_4_data = 12'd1125;
                42:  O_LUT_1_4_data = 12'd1144;
                43:  O_LUT_1_4_data = 12'd1163;
                44:  O_LUT_1_4_data = 12'd1182;
                45:  O_LUT_1_4_data = 12'd1201;
                46:  O_LUT_1_4_data = 12'd1220;
                47:  O_LUT_1_4_data = 12'd1238;
                48:  O_LUT_1_4_data = 12'd1257;
                49:  O_LUT_1_4_data = 12'd1275;
                50:  O_LUT_1_4_data = 12'd1293;
                51:  O_LUT_1_4_data = 12'd1311;
                52:  O_LUT_1_4_data = 12'd1329;
                53:  O_LUT_1_4_data = 12'd1347;
                54:  O_LUT_1_4_data = 12'd1365;
                55:  O_LUT_1_4_data = 12'd1383;
                56:  O_LUT_1_4_data = 12'd1401;
                57:  O_LUT_1_4_data = 12'd1418;
                58:  O_LUT_1_4_data = 12'd1436;
                59:  O_LUT_1_4_data = 12'd1453;
                60:  O_LUT_1_4_data = 12'd1470;
                61:  O_LUT_1_4_data = 12'd1488;
                62:  O_LUT_1_4_data = 12'd1505;
                63:  O_LUT_1_4_data = 12'd1522;
                64:  O_LUT_1_4_data = 12'd1539;
                65:  O_LUT_1_4_data = 12'd1556;
                66:  O_LUT_1_4_data = 12'd1572;
                67:  O_LUT_1_4_data = 12'd1589;
                68:  O_LUT_1_4_data = 12'd1606;
                69:  O_LUT_1_4_data = 12'd1623;
                70:  O_LUT_1_4_data = 12'd1639;
                71:  O_LUT_1_4_data = 12'd1656;
                72:  O_LUT_1_4_data = 12'd1672;
                73:  O_LUT_1_4_data = 12'd1688;
                74:  O_LUT_1_4_data = 12'd1705;
                75:  O_LUT_1_4_data = 12'd1721;
                76:  O_LUT_1_4_data = 12'd1737;
                77:  O_LUT_1_4_data = 12'd1753;
                78:  O_LUT_1_4_data = 12'd1769;
                79:  O_LUT_1_4_data = 12'd1785;
                80:  O_LUT_1_4_data = 12'd1801;
                81:  O_LUT_1_4_data = 12'd1817;
                82:  O_LUT_1_4_data = 12'd1833;
                83:  O_LUT_1_4_data = 12'd1848;
                84:  O_LUT_1_4_data = 12'd1864;
                85:  O_LUT_1_4_data = 12'd1880;
                86:  O_LUT_1_4_data = 12'd1895;
                87:  O_LUT_1_4_data = 12'd1911;
                88:  O_LUT_1_4_data = 12'd1926;
                89:  O_LUT_1_4_data = 12'd1942;
                90:  O_LUT_1_4_data = 12'd1957;
                91:  O_LUT_1_4_data = 12'd1972;
                92:  O_LUT_1_4_data = 12'd1988;
                93:  O_LUT_1_4_data = 12'd2003;
                94:  O_LUT_1_4_data = 12'd2018;
                95:  O_LUT_1_4_data = 12'd2033;
                96:  O_LUT_1_4_data = 12'd2048;
                97:  O_LUT_1_4_data = 12'd2063;
                98:  O_LUT_1_4_data = 12'd2078;
                99:  O_LUT_1_4_data = 12'd2093;
                100: O_LUT_1_4_data = 12'd2108;
                101: O_LUT_1_4_data = 12'd2123;
                102: O_LUT_1_4_data = 12'd2138;
                103: O_LUT_1_4_data = 12'd2153;
                104: O_LUT_1_4_data = 12'd2168;
                105: O_LUT_1_4_data = 12'd2182;
                106: O_LUT_1_4_data = 12'd2197;
                107: O_LUT_1_4_data = 12'd2212;
                108: O_LUT_1_4_data = 12'd2226;
                109: O_LUT_1_4_data = 12'd2241;
                110: O_LUT_1_4_data = 12'd2255;
                111: O_LUT_1_4_data = 12'd2270;
                112: O_LUT_1_4_data = 12'd2284;
                113: O_LUT_1_4_data = 12'd2299;
                114: O_LUT_1_4_data = 12'd2313;
                115: O_LUT_1_4_data = 12'd2327;
                116: O_LUT_1_4_data = 12'd2342;
                117: O_LUT_1_4_data = 12'd2356;
                118: O_LUT_1_4_data = 12'd2370;
                119: O_LUT_1_4_data = 12'd2384;
                120: O_LUT_1_4_data = 12'd2398;
                121: O_LUT_1_4_data = 12'd2413;
                122: O_LUT_1_4_data = 12'd2427;
                123: O_LUT_1_4_data = 12'd2441;
                124: O_LUT_1_4_data = 12'd2455;
                125: O_LUT_1_4_data = 12'd2469;
                126: O_LUT_1_4_data = 12'd2483;
                127: O_LUT_1_4_data = 12'd2497;
                128: O_LUT_1_4_data = 12'd2510;
                129: O_LUT_1_4_data = 12'd2524;
                130: O_LUT_1_4_data = 12'd2538;
                131: O_LUT_1_4_data = 12'd2552;
                132: O_LUT_1_4_data = 12'd2566;
                133: O_LUT_1_4_data = 12'd2579;
                134: O_LUT_1_4_data = 12'd2593;
                135: O_LUT_1_4_data = 12'd2607;
                136: O_LUT_1_4_data = 12'd2620;
                137: O_LUT_1_4_data = 12'd2634;
                138: O_LUT_1_4_data = 12'd2648;
                139: O_LUT_1_4_data = 12'd2661;
                140: O_LUT_1_4_data = 12'd2675;
                141: O_LUT_1_4_data = 12'd2688;
                142: O_LUT_1_4_data = 12'd2702;
                143: O_LUT_1_4_data = 12'd2715;
                144: O_LUT_1_4_data = 12'd2729;
                145: O_LUT_1_4_data = 12'd2742;
                146: O_LUT_1_4_data = 12'd2755;
                147: O_LUT_1_4_data = 12'd2769;
                148: O_LUT_1_4_data = 12'd2782;
                149: O_LUT_1_4_data = 12'd2795;
                150: O_LUT_1_4_data = 12'd2809;
                151: O_LUT_1_4_data = 12'd2822;
                152: O_LUT_1_4_data = 12'd2835;
                153: O_LUT_1_4_data = 12'd2848;
                154: O_LUT_1_4_data = 12'd2861;
                155: O_LUT_1_4_data = 12'd2875;
                156: O_LUT_1_4_data = 12'd2888;
                157: O_LUT_1_4_data = 12'd2901;
                158: O_LUT_1_4_data = 12'd2914;
                159: O_LUT_1_4_data = 12'd2927;
                160: O_LUT_1_4_data = 12'd2940;
                161: O_LUT_1_4_data = 12'd2953;
                162: O_LUT_1_4_data = 12'd2966;
                163: O_LUT_1_4_data = 12'd2979;
                164: O_LUT_1_4_data = 12'd2992;
                165: O_LUT_1_4_data = 12'd3005;
                166: O_LUT_1_4_data = 12'd3017;
                167: O_LUT_1_4_data = 12'd3030;
                168: O_LUT_1_4_data = 12'd3043;
                169: O_LUT_1_4_data = 12'd3056;
                170: O_LUT_1_4_data = 12'd3069;
                171: O_LUT_1_4_data = 12'd3082;
                172: O_LUT_1_4_data = 12'd3094;
                173: O_LUT_1_4_data = 12'd3107;
                174: O_LUT_1_4_data = 12'd3120;
                175: O_LUT_1_4_data = 12'd3132;
                176: O_LUT_1_4_data = 12'd3145;
                177: O_LUT_1_4_data = 12'd3158;
                178: O_LUT_1_4_data = 12'd3170;
                179: O_LUT_1_4_data = 12'd3183;
                180: O_LUT_1_4_data = 12'd3196;
                181: O_LUT_1_4_data = 12'd3208;
                182: O_LUT_1_4_data = 12'd3221;
                183: O_LUT_1_4_data = 12'd3233;
                184: O_LUT_1_4_data = 12'd3246;
                185: O_LUT_1_4_data = 12'd3258;
                186: O_LUT_1_4_data = 12'd3271;
                187: O_LUT_1_4_data = 12'd3283;
                188: O_LUT_1_4_data = 12'd3295;
                189: O_LUT_1_4_data = 12'd3308;
                190: O_LUT_1_4_data = 12'd3320;
                191: O_LUT_1_4_data = 12'd3333;
                192: O_LUT_1_4_data = 12'd3345;
                193: O_LUT_1_4_data = 12'd3357;
                194: O_LUT_1_4_data = 12'd3370;
                195: O_LUT_1_4_data = 12'd3382;
                196: O_LUT_1_4_data = 12'd3394;
                197: O_LUT_1_4_data = 12'd3406;
                198: O_LUT_1_4_data = 12'd3419;
                199: O_LUT_1_4_data = 12'd3431;
                200: O_LUT_1_4_data = 12'd3443;
                201: O_LUT_1_4_data = 12'd3455;
                202: O_LUT_1_4_data = 12'd3467;
                203: O_LUT_1_4_data = 12'd3480;
                204: O_LUT_1_4_data = 12'd3492;
                205: O_LUT_1_4_data = 12'd3504;
                206: O_LUT_1_4_data = 12'd3516;
                207: O_LUT_1_4_data = 12'd3528;
                208: O_LUT_1_4_data = 12'd3540;
                209: O_LUT_1_4_data = 12'd3552;
                210: O_LUT_1_4_data = 12'd3564;
                211: O_LUT_1_4_data = 12'd3576;
                212: O_LUT_1_4_data = 12'd3588;
                213: O_LUT_1_4_data = 12'd3600;
                214: O_LUT_1_4_data = 12'd3612;
                215: O_LUT_1_4_data = 12'd3624;
                216: O_LUT_1_4_data = 12'd3636;
                217: O_LUT_1_4_data = 12'd3648;
                218: O_LUT_1_4_data = 12'd3660;
                219: O_LUT_1_4_data = 12'd3672;
                220: O_LUT_1_4_data = 12'd3684;
                221: O_LUT_1_4_data = 12'd3695;
                222: O_LUT_1_4_data = 12'd3707;
                223: O_LUT_1_4_data = 12'd3719;
                224: O_LUT_1_4_data = 12'd3731;
                225: O_LUT_1_4_data = 12'd3743;
                226: O_LUT_1_4_data = 12'd3754;
                227: O_LUT_1_4_data = 12'd3766;
                228: O_LUT_1_4_data = 12'd3778;
                229: O_LUT_1_4_data = 12'd3790;
                230: O_LUT_1_4_data = 12'd3801;
                231: O_LUT_1_4_data = 12'd3813;
                232: O_LUT_1_4_data = 12'd3825;
                233: O_LUT_1_4_data = 12'd3837;
                234: O_LUT_1_4_data = 12'd3848;
                235: O_LUT_1_4_data = 12'd3860;
                236: O_LUT_1_4_data = 12'd3871;
                237: O_LUT_1_4_data = 12'd3883;
                238: O_LUT_1_4_data = 12'd3895;
                239: O_LUT_1_4_data = 12'd3906;
                240: O_LUT_1_4_data = 12'd3918;
                241: O_LUT_1_4_data = 12'd3929;
                242: O_LUT_1_4_data = 12'd3941;
                243: O_LUT_1_4_data = 12'd3952;
                244: O_LUT_1_4_data = 12'd3964;
                245: O_LUT_1_4_data = 12'd3975;
                246: O_LUT_1_4_data = 12'd3987;
                247: O_LUT_1_4_data = 12'd3998;
                248: O_LUT_1_4_data = 12'd4010;
                249: O_LUT_1_4_data = 12'd4021;
                250: O_LUT_1_4_data = 12'd4033;
                251: O_LUT_1_4_data = 12'd4044;
                252: O_LUT_1_4_data = 12'd4056;
                253: O_LUT_1_4_data = 12'd4067;
                254: O_LUT_1_4_data = 12'd4078;
                255: O_LUT_1_4_data = 12'd4090;
            default: O_LUT_1_4_data = 12'd4090;
        endcase
    end
    
endmodule
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
/*********legacy_ui_lut_1_6 ********************************************
@Description :   gamma=1.6
*****************************************************************/
module legacy_ui_lut_1_6 (
    input                    I_clk  ,
    input                    I_rst_n,

    input      [7:0]               I_LUT_1_6_data  ,
    output reg [11:0]              O_LUT_1_6_data  
);

    always @(*)begin 
        case (I_LUT_1_6_data)
                0:  O_LUT_1_6_data = 12'd82 ;
                1:  O_LUT_1_6_data = 12'd164;
                2:  O_LUT_1_6_data = 12'd226;
                3:  O_LUT_1_6_data = 12'd280;
                4:  O_LUT_1_6_data = 12'd327;
                5:  O_LUT_1_6_data = 12'd371;
                6:  O_LUT_1_6_data = 12'd412;
                7:  O_LUT_1_6_data = 12'd450;
                8:  O_LUT_1_6_data = 12'd487;
                9:  O_LUT_1_6_data = 12'd522;
                10: O_LUT_1_6_data = 12'd556;
                11: O_LUT_1_6_data = 12'd589;
                12: O_LUT_1_6_data = 12'd620;
                13: O_LUT_1_6_data = 12'd651;
                14: O_LUT_1_6_data = 12'd680;
                15: O_LUT_1_6_data = 12'd709;
                16: O_LUT_1_6_data = 12'd738;
                17: O_LUT_1_6_data = 12'd765;
                18: O_LUT_1_6_data = 12'd792;
                19: O_LUT_1_6_data = 12'd819;
                20: O_LUT_1_6_data = 12'd845;
                21: O_LUT_1_6_data = 12'd870;
                22: O_LUT_1_6_data = 12'd896;
                23: O_LUT_1_6_data = 12'd920;
                24: O_LUT_1_6_data = 12'd945;
                25: O_LUT_1_6_data = 12'd968;
                26: O_LUT_1_6_data = 12'd992;
                27: O_LUT_1_6_data = 12'd1015;
                28: O_LUT_1_6_data = 12'd1038;
                29: O_LUT_1_6_data = 12'd1061;
                30: O_LUT_1_6_data = 12'd1083;
                31: O_LUT_1_6_data = 12'd1105;
                32: O_LUT_1_6_data = 12'd1127;
                33: O_LUT_1_6_data = 12'd1149;
                34: O_LUT_1_6_data = 12'd1170;
                35: O_LUT_1_6_data = 12'd1191;
                36: O_LUT_1_6_data = 12'd1212;
                37: O_LUT_1_6_data = 12'd1233;
                38: O_LUT_1_6_data = 12'd1253;
                39: O_LUT_1_6_data = 12'd1273;
                40: O_LUT_1_6_data = 12'd1293;
                41: O_LUT_1_6_data = 12'd1313;
                42: O_LUT_1_6_data = 12'd1333;
                43: O_LUT_1_6_data = 12'd1352;
                44: O_LUT_1_6_data = 12'd1372;
                45: O_LUT_1_6_data = 12'd1391;
                46: O_LUT_1_6_data = 12'd1410;
                47: O_LUT_1_6_data = 12'd1429;
                48: O_LUT_1_6_data = 12'd1448;
                49: O_LUT_1_6_data = 12'd1466;
                50: O_LUT_1_6_data = 12'd1485;
                51: O_LUT_1_6_data = 12'd1503;
                52: O_LUT_1_6_data = 12'd1521;
                53: O_LUT_1_6_data = 12'd1539;
                54: O_LUT_1_6_data = 12'd1557;
                55: O_LUT_1_6_data = 12'd1575;
                56: O_LUT_1_6_data = 12'd1593;
                57: O_LUT_1_6_data = 12'd1610;
                58: O_LUT_1_6_data = 12'd1628;
                59: O_LUT_1_6_data = 12'd1645;
                60: O_LUT_1_6_data = 12'd1662;
                61: O_LUT_1_6_data = 12'd1679;
                62: O_LUT_1_6_data = 12'd1696;
                63: O_LUT_1_6_data = 12'd1713;
                64: O_LUT_1_6_data = 12'd1730;
                65: O_LUT_1_6_data = 12'd1747;
                66: O_LUT_1_6_data = 12'd1763;
                67: O_LUT_1_6_data = 12'd1780;
                68: O_LUT_1_6_data = 12'd1796;
                69: O_LUT_1_6_data = 12'd1813;
                70: O_LUT_1_6_data = 12'd1829;
                71: O_LUT_1_6_data = 12'd1845;
                72: O_LUT_1_6_data = 12'd1861;
                73: O_LUT_1_6_data = 12'd1877;
                74: O_LUT_1_6_data = 12'd1893;
                75: O_LUT_1_6_data = 12'd1909;
                76: O_LUT_1_6_data = 12'd1925;
                77: O_LUT_1_6_data = 12'd1940;
                78: O_LUT_1_6_data = 12'd1956;
                79: O_LUT_1_6_data = 12'd1972;
                80: O_LUT_1_6_data = 12'd1987;
                81: O_LUT_1_6_data = 12'd2003;
                82: O_LUT_1_6_data = 12'd2018;
                83: O_LUT_1_6_data = 12'd2033;
                84: O_LUT_1_6_data = 12'd2048;
                85: O_LUT_1_6_data = 12'd2063;
                86: O_LUT_1_6_data = 12'd2078;
                87: O_LUT_1_6_data = 12'd2093;
                88: O_LUT_1_6_data = 12'd2108;
                89: O_LUT_1_6_data = 12'd2123;
                90: O_LUT_1_6_data = 12'd2138;
                91: O_LUT_1_6_data = 12'd2153;
                92: O_LUT_1_6_data = 12'd2167;
                93: O_LUT_1_6_data = 12'd2182;
                94: O_LUT_1_6_data = 12'd2197;
                95: O_LUT_1_6_data = 12'd2211;
                96: O_LUT_1_6_data = 12'd2226;
                97: O_LUT_1_6_data = 12'd2240;
                98: O_LUT_1_6_data = 12'd2254;
                99: O_LUT_1_6_data = 12'd2269;
                100:O_LUT_1_6_data = 12'd2283;
                101:O_LUT_1_6_data = 12'd2297;
                102:O_LUT_1_6_data = 12'd2311;
                103:O_LUT_1_6_data = 12'd2325;
                104:O_LUT_1_6_data = 12'd2339;
                105:O_LUT_1_6_data = 12'd2353;
                106:O_LUT_1_6_data = 12'd2367;
                107:O_LUT_1_6_data = 12'd2381;
                108:O_LUT_1_6_data = 12'd2395;
                109:O_LUT_1_6_data = 12'd2409;
                110:O_LUT_1_6_data = 12'd2422;
                111:O_LUT_1_6_data = 12'd2436;
                112:O_LUT_1_6_data = 12'd2450;
                113:O_LUT_1_6_data = 12'd2463;
                114:O_LUT_1_6_data = 12'd2477;
                115:O_LUT_1_6_data = 12'd2490;
                116:O_LUT_1_6_data = 12'd2504;
                117:O_LUT_1_6_data = 12'd2517;
                118:O_LUT_1_6_data = 12'd2530;
                119:O_LUT_1_6_data = 12'd2544;
                120:O_LUT_1_6_data = 12'd2557;
                121:O_LUT_1_6_data = 12'd2570;
                122:O_LUT_1_6_data = 12'd2584;
                123:O_LUT_1_6_data = 12'd2597;
                124:O_LUT_1_6_data = 12'd2610;
                125:O_LUT_1_6_data = 12'd2623;
                126:O_LUT_1_6_data = 12'd2636;
                127:O_LUT_1_6_data = 12'd2649;
                128:O_LUT_1_6_data = 12'd2662;
                129:O_LUT_1_6_data = 12'd2675;
                130:O_LUT_1_6_data = 12'd2688;
                131:O_LUT_1_6_data = 12'd2701;
                132:O_LUT_1_6_data = 12'd2713;
                133:O_LUT_1_6_data = 12'd2726;
                134:O_LUT_1_6_data = 12'd2739;
                135:O_LUT_1_6_data = 12'd2752;
                136:O_LUT_1_6_data = 12'd2764;
                137:O_LUT_1_6_data = 12'd2777;
                138:O_LUT_1_6_data = 12'd2790;
                139:O_LUT_1_6_data = 12'd2802;
                140:O_LUT_1_6_data = 12'd2815;
                141:O_LUT_1_6_data = 12'd2827;
                142:O_LUT_1_6_data = 12'd2840;
                143:O_LUT_1_6_data = 12'd2852;
                144:O_LUT_1_6_data = 12'd2865;
                145:O_LUT_1_6_data = 12'd2877;
                146:O_LUT_1_6_data = 12'd2889;
                147:O_LUT_1_6_data = 12'd2902;
                148:O_LUT_1_6_data = 12'd2914;
                149:O_LUT_1_6_data = 12'd2926;
                150:O_LUT_1_6_data = 12'd2938;
                151:O_LUT_1_6_data = 12'd2950;
                152:O_LUT_1_6_data = 12'd2963;
                153:O_LUT_1_6_data = 12'd2975;
                154:O_LUT_1_6_data = 12'd2987;
                155:O_LUT_1_6_data = 12'd2999;
                156:O_LUT_1_6_data = 12'd3011;
                157:O_LUT_1_6_data = 12'd3023;
                158:O_LUT_1_6_data = 12'd3035;
                159:O_LUT_1_6_data = 12'd3047;
                160:O_LUT_1_6_data = 12'd3059;
                161:O_LUT_1_6_data = 12'd3071;
                162:O_LUT_1_6_data = 12'd3083;
                163:O_LUT_1_6_data = 12'd3094;
                164:O_LUT_1_6_data = 12'd3106;
                165:O_LUT_1_6_data = 12'd3118;
                166:O_LUT_1_6_data = 12'd3130;
                167:O_LUT_1_6_data = 12'd3142;
                168:O_LUT_1_6_data = 12'd3153;
                169:O_LUT_1_6_data = 12'd3165;
                170:O_LUT_1_6_data = 12'd3177;
                171:O_LUT_1_6_data = 12'd3188;
                172:O_LUT_1_6_data = 12'd3200;
                173:O_LUT_1_6_data = 12'd3211;
                174:O_LUT_1_6_data = 12'd3223;
                175:O_LUT_1_6_data = 12'd3235;
                176:O_LUT_1_6_data = 12'd3246;
                177:O_LUT_1_6_data = 12'd3258;
                178:O_LUT_1_6_data = 12'd3269;
                179:O_LUT_1_6_data = 12'd3280;
                180:O_LUT_1_6_data = 12'd3292;
                181:O_LUT_1_6_data = 12'd3303;
                182:O_LUT_1_6_data = 12'd3315;
                183:O_LUT_1_6_data = 12'd3326;
                184:O_LUT_1_6_data = 12'd3337;
                185:O_LUT_1_6_data = 12'd3349;
                186:O_LUT_1_6_data = 12'd3360;
                187:O_LUT_1_6_data = 12'd3371;
                188:O_LUT_1_6_data = 12'd3382;
                189:O_LUT_1_6_data = 12'd3394;
                190:O_LUT_1_6_data = 12'd3405;
                191:O_LUT_1_6_data = 12'd3416;
                192:O_LUT_1_6_data = 12'd3427;
                193:O_LUT_1_6_data = 12'd3438;
                194:O_LUT_1_6_data = 12'd3449;
                195:O_LUT_1_6_data = 12'd3460;
                196:O_LUT_1_6_data = 12'd3471;
                197:O_LUT_1_6_data = 12'd3482;
                198:O_LUT_1_6_data = 12'd3493;
                199:O_LUT_1_6_data = 12'd3504;
                200:O_LUT_1_6_data = 12'd3515;
                201:O_LUT_1_6_data = 12'd3526;
                202:O_LUT_1_6_data = 12'd3537;
                203:O_LUT_1_6_data = 12'd3548;
                204:O_LUT_1_6_data = 12'd3559;
                205:O_LUT_1_6_data = 12'd3570;
                206:O_LUT_1_6_data = 12'd3581;
                207:O_LUT_1_6_data = 12'd3592;
                208:O_LUT_1_6_data = 12'd3602;
                209:O_LUT_1_6_data = 12'd3613;
                210:O_LUT_1_6_data = 12'd3624;
                211:O_LUT_1_6_data = 12'd3635;
                212:O_LUT_1_6_data = 12'd3645;
                213:O_LUT_1_6_data = 12'd3656;
                214:O_LUT_1_6_data = 12'd3667;
                215:O_LUT_1_6_data = 12'd3678;
                216:O_LUT_1_6_data = 12'd3688;
                217:O_LUT_1_6_data = 12'd3699;
                218:O_LUT_1_6_data = 12'd3709;
                219:O_LUT_1_6_data = 12'd3720;
                220:O_LUT_1_6_data = 12'd3731;
                221:O_LUT_1_6_data = 12'd3741;
                222:O_LUT_1_6_data = 12'd3752;
                223:O_LUT_1_6_data = 12'd3762;
                224:O_LUT_1_6_data = 12'd3773;
                225:O_LUT_1_6_data = 12'd3783;
                226:O_LUT_1_6_data = 12'd3794;
                227:O_LUT_1_6_data = 12'd3804;
                228:O_LUT_1_6_data = 12'd3815;
                229:O_LUT_1_6_data = 12'd3825;
                230:O_LUT_1_6_data = 12'd3836;
                231:O_LUT_1_6_data = 12'd3846;
                232:O_LUT_1_6_data = 12'd3856;
                233:O_LUT_1_6_data = 12'd3867;
                234:O_LUT_1_6_data = 12'd3877;
                235:O_LUT_1_6_data = 12'd3887;
                236:O_LUT_1_6_data = 12'd3898;
                237:O_LUT_1_6_data = 12'd3908;
                238:O_LUT_1_6_data = 12'd3918;
                239:O_LUT_1_6_data = 12'd3928;
                240:O_LUT_1_6_data = 12'd3939;
                241:O_LUT_1_6_data = 12'd3949;
                242:O_LUT_1_6_data = 12'd3959;
                243:O_LUT_1_6_data = 12'd3969;
                244:O_LUT_1_6_data = 12'd3980;
                245:O_LUT_1_6_data = 12'd3990;
                246:O_LUT_1_6_data = 12'd4000;
                247:O_LUT_1_6_data = 12'd4010;
                248:O_LUT_1_6_data = 12'd4020;
                249:O_LUT_1_6_data = 12'd4030;
                250:O_LUT_1_6_data = 12'd4040;
                251:O_LUT_1_6_data = 12'd4050;
                252:O_LUT_1_6_data = 12'd4060;
                253:O_LUT_1_6_data = 12'd4070;
                254:O_LUT_1_6_data = 12'd4080;
                255:O_LUT_1_6_data = 12'd4090;
            default:O_LUT_1_6_data = 12'd4092;
        endcase
    end
    
endmodule
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
/*********legacy_ui_lut_1_8 ********************************************
@Description :   gamma=1.8
*****************************************************************/
module legacy_ui_lut_1_8 (
    input                                I_clk  ,
    input                                I_rst_n,

    input      [7:0]               I_LUT_1_8_data,
    output reg [11:0]              O_LUT_1_8_data  
);
    always @(*)begin 
        case (I_LUT_1_8_data)
                0:   O_LUT_1_8_data = 12'd124;
                1:   O_LUT_1_8_data = 12'd230;
                2:   O_LUT_1_8_data = 12'd306;
                3:   O_LUT_1_8_data = 12'd370;
                4:   O_LUT_1_8_data = 12'd426;
                5:   O_LUT_1_8_data = 12'd476;
                6:   O_LUT_1_8_data = 12'd523;
                7:   O_LUT_1_8_data = 12'd567;
                8:   O_LUT_1_8_data = 12'd608;
                9:   O_LUT_1_8_data = 12'd647;
                10:  O_LUT_1_8_data = 12'd684;
                11:  O_LUT_1_8_data = 12'd720;
                12:  O_LUT_1_8_data = 12'd755;
                13:  O_LUT_1_8_data = 12'd788;
                14:  O_LUT_1_8_data = 12'd820;
                15:  O_LUT_1_8_data = 12'd851;
                16:  O_LUT_1_8_data = 12'd882;
                17:  O_LUT_1_8_data = 12'd911;
                18:  O_LUT_1_8_data = 12'd940;
                19:  O_LUT_1_8_data = 12'd968;
                20:  O_LUT_1_8_data = 12'd996;
                21:  O_LUT_1_8_data = 12'd1023;
                22:  O_LUT_1_8_data = 12'd1049;
                23:  O_LUT_1_8_data = 12'd1075;
                24:  O_LUT_1_8_data = 12'd1100;
                25:  O_LUT_1_8_data = 12'd1125;
                26:  O_LUT_1_8_data = 12'd1150;
                27:  O_LUT_1_8_data = 12'd1174;
                28:  O_LUT_1_8_data = 12'd1198;
                29:  O_LUT_1_8_data = 12'd1221;
                30:  O_LUT_1_8_data = 12'd1244;
                31:  O_LUT_1_8_data = 12'd1267;
                32:  O_LUT_1_8_data = 12'd1289;
                33:  O_LUT_1_8_data = 12'd1311;
                34:  O_LUT_1_8_data = 12'd1333;
                35:  O_LUT_1_8_data = 12'd1354;
                36:  O_LUT_1_8_data = 12'd1376;
                37:  O_LUT_1_8_data = 12'd1397;
                38:  O_LUT_1_8_data = 12'd1417;
                39:  O_LUT_1_8_data = 12'd1438;
                40:  O_LUT_1_8_data = 12'd1458;
                41:  O_LUT_1_8_data = 12'd1478;
                42:  O_LUT_1_8_data = 12'd1498;
                43:  O_LUT_1_8_data = 12'd1518;
                44:  O_LUT_1_8_data = 12'd1537;
                45:  O_LUT_1_8_data = 12'd1556;
                46:  O_LUT_1_8_data = 12'd1575;
                47:  O_LUT_1_8_data = 12'd1594;
                48:  O_LUT_1_8_data = 12'd1613;
                49:  O_LUT_1_8_data = 12'd1632;
                50:  O_LUT_1_8_data = 12'd1650;
                51:  O_LUT_1_8_data = 12'd1668;
                52:  O_LUT_1_8_data = 12'd1686;
                53:  O_LUT_1_8_data = 12'd1704;
                54:  O_LUT_1_8_data = 12'd1722;
                55:  O_LUT_1_8_data = 12'd1740;
                56:  O_LUT_1_8_data = 12'd1757;
                57:  O_LUT_1_8_data = 12'd1774;
                58:  O_LUT_1_8_data = 12'd1792;
                59:  O_LUT_1_8_data = 12'd1809;
                60:  O_LUT_1_8_data = 12'd1826;
                61:  O_LUT_1_8_data = 12'd1842;
                62:  O_LUT_1_8_data = 12'd1859;
                63:  O_LUT_1_8_data = 12'd1876;
                64:  O_LUT_1_8_data = 12'd1892;
                65:  O_LUT_1_8_data = 12'd1909;
                66:  O_LUT_1_8_data = 12'd1925;
                67:  O_LUT_1_8_data = 12'd1941;
                68:  O_LUT_1_8_data = 12'd1957;
                69:  O_LUT_1_8_data = 12'd1973;
                70:  O_LUT_1_8_data = 12'd1989;
                71:  O_LUT_1_8_data = 12'd2005;
                72:  O_LUT_1_8_data = 12'd2020;
                73:  O_LUT_1_8_data = 12'd2036;
                74:  O_LUT_1_8_data = 12'd2051;
                75:  O_LUT_1_8_data = 12'd2067;
                76:  O_LUT_1_8_data = 12'd2082;
                77:  O_LUT_1_8_data = 12'd2097;
                78:  O_LUT_1_8_data = 12'd2112;
                79:  O_LUT_1_8_data = 12'd2127;
                80:  O_LUT_1_8_data = 12'd2142;
                81:  O_LUT_1_8_data = 12'd2157;
                82:  O_LUT_1_8_data = 12'd2172;
                83:  O_LUT_1_8_data = 12'd2187;
                84:  O_LUT_1_8_data = 12'd2201;
                85:  O_LUT_1_8_data = 12'd2216;
                86:  O_LUT_1_8_data = 12'd2230;
                87:  O_LUT_1_8_data = 12'd2245;
                88:  O_LUT_1_8_data = 12'd2259;
                89:  O_LUT_1_8_data = 12'd2273;
                90:  O_LUT_1_8_data = 12'd2288;
                91:  O_LUT_1_8_data = 12'd2302;
                92:  O_LUT_1_8_data = 12'd2316;
                93:  O_LUT_1_8_data = 12'd2330;
                94:  O_LUT_1_8_data = 12'd2344;
                95:  O_LUT_1_8_data = 12'd2358;
                96:  O_LUT_1_8_data = 12'd2371;
                97:  O_LUT_1_8_data = 12'd2385;
                98:  O_LUT_1_8_data = 12'd2399;
                99:  O_LUT_1_8_data = 12'd2412;
                100: O_LUT_1_8_data = 12'd2426;
                101: O_LUT_1_8_data = 12'd2439;
                102: O_LUT_1_8_data = 12'd2453;
                103: O_LUT_1_8_data = 12'd2466;
                104: O_LUT_1_8_data = 12'd2479;
                105: O_LUT_1_8_data = 12'd2493;
                106: O_LUT_1_8_data = 12'd2506;
                107: O_LUT_1_8_data = 12'd2519;
                108: O_LUT_1_8_data = 12'd2532;
                109: O_LUT_1_8_data = 12'd2545;
                110: O_LUT_1_8_data = 12'd2558;
                111: O_LUT_1_8_data = 12'd2571;
                112: O_LUT_1_8_data = 12'd2584;
                113: O_LUT_1_8_data = 12'd2597;
                114: O_LUT_1_8_data = 12'd2610;
                115: O_LUT_1_8_data = 12'd2622;
                116: O_LUT_1_8_data = 12'd2635;
                117: O_LUT_1_8_data = 12'd2648;
                118: O_LUT_1_8_data = 12'd2660;
                119: O_LUT_1_8_data = 12'd2673;
                120: O_LUT_1_8_data = 12'd2685;
                121: O_LUT_1_8_data = 12'd2698;
                122: O_LUT_1_8_data = 12'd2710;
                123: O_LUT_1_8_data = 12'd2723;
                124: O_LUT_1_8_data = 12'd2735;
                125: O_LUT_1_8_data = 12'd2747;
                126: O_LUT_1_8_data = 12'd2760;
                127: O_LUT_1_8_data = 12'd2772;
                128: O_LUT_1_8_data = 12'd2784;
                129: O_LUT_1_8_data = 12'd2796;
                130: O_LUT_1_8_data = 12'd2808;
                131: O_LUT_1_8_data = 12'd2820;
                132: O_LUT_1_8_data = 12'd2832;
                133: O_LUT_1_8_data = 12'd2844;
                134: O_LUT_1_8_data = 12'd2856;
                135: O_LUT_1_8_data = 12'd2868;
                136: O_LUT_1_8_data = 12'd2880;
                137: O_LUT_1_8_data = 12'd2891;
                138: O_LUT_1_8_data = 12'd2903;
                139: O_LUT_1_8_data = 12'd2915;
                140: O_LUT_1_8_data = 12'd2927;
                141: O_LUT_1_8_data = 12'd2938;
                142: O_LUT_1_8_data = 12'd2950;
                143: O_LUT_1_8_data = 12'd2961;
                144: O_LUT_1_8_data = 12'd2973;
                145: O_LUT_1_8_data = 12'd2985;
                146: O_LUT_1_8_data = 12'd2996;
                147: O_LUT_1_8_data = 12'd3007;
                148: O_LUT_1_8_data = 12'd3019;
                149: O_LUT_1_8_data = 12'd3030;
                150: O_LUT_1_8_data = 12'd3042;
                151: O_LUT_1_8_data = 12'd3053;
                152: O_LUT_1_8_data = 12'd3064;
                153: O_LUT_1_8_data = 12'd3075;
                154: O_LUT_1_8_data = 12'd3087;
                155: O_LUT_1_8_data = 12'd3098;
                156: O_LUT_1_8_data = 12'd3109;
                157: O_LUT_1_8_data = 12'd3120;
                158: O_LUT_1_8_data = 12'd3131;
                159: O_LUT_1_8_data = 12'd3142;
                160: O_LUT_1_8_data = 12'd3153;
                161: O_LUT_1_8_data = 12'd3164;
                162: O_LUT_1_8_data = 12'd3175;
                163: O_LUT_1_8_data = 12'd3186;
                164: O_LUT_1_8_data = 12'd3197;
                165: O_LUT_1_8_data = 12'd3208;
                166: O_LUT_1_8_data = 12'd3219;
                167: O_LUT_1_8_data = 12'd3229;
                168: O_LUT_1_8_data = 12'd3240;
                169: O_LUT_1_8_data = 12'd3251;
                170: O_LUT_1_8_data = 12'd3262;
                171: O_LUT_1_8_data = 12'd3272;
                172: O_LUT_1_8_data = 12'd3283;
                173: O_LUT_1_8_data = 12'd3294;
                174: O_LUT_1_8_data = 12'd3304;
                175: O_LUT_1_8_data = 12'd3315;
                176: O_LUT_1_8_data = 12'd3326;
                177: O_LUT_1_8_data = 12'd3336;
                178: O_LUT_1_8_data = 12'd3347;
                179: O_LUT_1_8_data = 12'd3357;
                180: O_LUT_1_8_data = 12'd3368;
                181: O_LUT_1_8_data = 12'd3378;
                182: O_LUT_1_8_data = 12'd3388;
                183: O_LUT_1_8_data = 12'd3399;
                184: O_LUT_1_8_data = 12'd3409;
                185: O_LUT_1_8_data = 12'd3419;
                186: O_LUT_1_8_data = 12'd3430;
                187: O_LUT_1_8_data = 12'd3440;
                188: O_LUT_1_8_data = 12'd3450;
                189: O_LUT_1_8_data = 12'd3461;
                190: O_LUT_1_8_data = 12'd3471;
                191: O_LUT_1_8_data = 12'd3481;
                192: O_LUT_1_8_data = 12'd3491;
                193: O_LUT_1_8_data = 12'd3501;
                194: O_LUT_1_8_data = 12'd3511;
                195: O_LUT_1_8_data = 12'd3521;
                196: O_LUT_1_8_data = 12'd3532;
                197: O_LUT_1_8_data = 12'd3542;
                198: O_LUT_1_8_data = 12'd3552;
                199: O_LUT_1_8_data = 12'd3562;
                200: O_LUT_1_8_data = 12'd3572;
                201: O_LUT_1_8_data = 12'd3582;
                202: O_LUT_1_8_data = 12'd3592;
                203: O_LUT_1_8_data = 12'd3601;
                204: O_LUT_1_8_data = 12'd3611;
                205: O_LUT_1_8_data = 12'd3621;
                206: O_LUT_1_8_data = 12'd3631;
                207: O_LUT_1_8_data = 12'd3641;
                208: O_LUT_1_8_data = 12'd3651;
                209: O_LUT_1_8_data = 12'd3661;
                210: O_LUT_1_8_data = 12'd3670;
                211: O_LUT_1_8_data = 12'd3680;
                212: O_LUT_1_8_data = 12'd3690;
                213: O_LUT_1_8_data = 12'd3700;
                214: O_LUT_1_8_data = 12'd3709;
                215: O_LUT_1_8_data = 12'd3719;
                216: O_LUT_1_8_data = 12'd3729;
                217: O_LUT_1_8_data = 12'd3738;
                218: O_LUT_1_8_data = 12'd3748;
                219: O_LUT_1_8_data = 12'd3757;
                220: O_LUT_1_8_data = 12'd3767;
                221: O_LUT_1_8_data = 12'd3777;
                222: O_LUT_1_8_data = 12'd3786;
                223: O_LUT_1_8_data = 12'd3796;
                224: O_LUT_1_8_data = 12'd3805;
                225: O_LUT_1_8_data = 12'd3815;
                226: O_LUT_1_8_data = 12'd3824;
                227: O_LUT_1_8_data = 12'd3834;
                228: O_LUT_1_8_data = 12'd3843;
                229: O_LUT_1_8_data = 12'd3852;
                230: O_LUT_1_8_data = 12'd3862;
                231: O_LUT_1_8_data = 12'd3871;
                232: O_LUT_1_8_data = 12'd3880;
                233: O_LUT_1_8_data = 12'd3890;
                234: O_LUT_1_8_data = 12'd3899;
                235: O_LUT_1_8_data = 12'd3908;
                236: O_LUT_1_8_data = 12'd3918;
                237: O_LUT_1_8_data = 12'd3927;
                238: O_LUT_1_8_data = 12'd3936;
                239: O_LUT_1_8_data = 12'd3945;
                240: O_LUT_1_8_data = 12'd3955;
                241: O_LUT_1_8_data = 12'd3964;
                242: O_LUT_1_8_data = 12'd3973;
                243: O_LUT_1_8_data = 12'd3982;
                244: O_LUT_1_8_data = 12'd3991;
                245: O_LUT_1_8_data = 12'd4001;
                246: O_LUT_1_8_data = 12'd4010;
                247: O_LUT_1_8_data = 12'd4019;
                248: O_LUT_1_8_data = 12'd4028;
                249: O_LUT_1_8_data = 12'd4037;
                250: O_LUT_1_8_data = 12'd4046;
                251: O_LUT_1_8_data = 12'd4055;
                252: O_LUT_1_8_data = 12'd4064;
                253: O_LUT_1_8_data = 12'd4073;
                254: O_LUT_1_8_data = 12'd4082;
                255: O_LUT_1_8_data = 12'd4091;
            default: O_LUT_1_8_data = 12'd4092;
        endcase
    end
endmodule
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
/*********legacy_ui_lut_2_0 ********************************************
@Description :   gamma=2.0
*****************************************************************/
module legacy_ui_lut_2_0 (
    input                    I_clk  ,
    input                    I_rst_n,

    input      [7:0]               I_LUT_2_0_data  ,
    output reg [11:0]              O_LUT_2_0_data  
);

    always @(*)begin 
        case (I_LUT_2_0_data)
                0:   O_LUT_2_0_data = 12'd181;
                1:   O_LUT_2_0_data = 12'd313;
                2:   O_LUT_2_0_data = 12'd404;
                3:   O_LUT_2_0_data = 12'd478;
                4:   O_LUT_2_0_data = 12'd543;
                5:   O_LUT_2_0_data = 12'd600;
                6:   O_LUT_2_0_data = 12'd652;
                7:   O_LUT_2_0_data = 12'd701;
                8:   O_LUT_2_0_data = 12'd746;
                9:   O_LUT_2_0_data = 12'd789;
                10:  O_LUT_2_0_data = 12'd829;
                11:  O_LUT_2_0_data = 12'd868;
                12:  O_LUT_2_0_data = 12'd905;
                13:  O_LUT_2_0_data = 12'd940;
                14:  O_LUT_2_0_data = 12'd974;
                15:  O_LUT_2_0_data = 12'd1007;
                16:  O_LUT_2_0_data = 12'd1039;
                17:  O_LUT_2_0_data = 12'd1070;
                18:  O_LUT_2_0_data = 12'd1101;
                19:  O_LUT_2_0_data = 12'd1130;
                20:  O_LUT_2_0_data = 12'd1159;
                21:  O_LUT_2_0_data = 12'd1187;
                22:  O_LUT_2_0_data = 12'd1214;
                23:  O_LUT_2_0_data = 12'd1241;
                24:  O_LUT_2_0_data = 12'd1267;
                25:  O_LUT_2_0_data = 12'd1292;
                26:  O_LUT_2_0_data = 12'd1317;
                27:  O_LUT_2_0_data = 12'd1342;
                28:  O_LUT_2_0_data = 12'd1366;
                29:  O_LUT_2_0_data = 12'd1390;
                30:  O_LUT_2_0_data = 12'd1413;
                31:  O_LUT_2_0_data = 12'd1436;
                32:  O_LUT_2_0_data = 12'd1459;
                33:  O_LUT_2_0_data = 12'd1481;
                34:  O_LUT_2_0_data = 12'd1503;
                35:  O_LUT_2_0_data = 12'd1525;
                36:  O_LUT_2_0_data = 12'd1546;
                37:  O_LUT_2_0_data = 12'd1567;
                38:  O_LUT_2_0_data = 12'd1588;
                39:  O_LUT_2_0_data = 12'd1608;
                40:  O_LUT_2_0_data = 12'd1629;
                41:  O_LUT_2_0_data = 12'd1649;
                42:  O_LUT_2_0_data = 12'd1668;
                43:  O_LUT_2_0_data = 12'd1688;
                44:  O_LUT_2_0_data = 12'd1707;
                45:  O_LUT_2_0_data = 12'd1726;
                46:  O_LUT_2_0_data = 12'd1745;
                47:  O_LUT_2_0_data = 12'd1764;
                48:  O_LUT_2_0_data = 12'd1782;
                49:  O_LUT_2_0_data = 12'd1801;
                50:  O_LUT_2_0_data = 12'd1819;
                51:  O_LUT_2_0_data = 12'd1837;
                52:  O_LUT_2_0_data = 12'd1854;
                53:  O_LUT_2_0_data = 12'd1872;
                54:  O_LUT_2_0_data = 12'd1889;
                55:  O_LUT_2_0_data = 12'd1907;
                56:  O_LUT_2_0_data = 12'd1924;
                57:  O_LUT_2_0_data = 12'd1941;
                58:  O_LUT_2_0_data = 12'd1958;
                59:  O_LUT_2_0_data = 12'd1974;
                60:  O_LUT_2_0_data = 12'd1991;
                61:  O_LUT_2_0_data = 12'd2007;
                62:  O_LUT_2_0_data = 12'd2023;
                63:  O_LUT_2_0_data = 12'd2039;
                64:  O_LUT_2_0_data = 12'd2055;
                65:  O_LUT_2_0_data = 12'd2071;
                66:  O_LUT_2_0_data = 12'd2087;
                67:  O_LUT_2_0_data = 12'd2103;
                68:  O_LUT_2_0_data = 12'd2118;
                69:  O_LUT_2_0_data = 12'd2134;
                70:  O_LUT_2_0_data = 12'd2149;
                71:  O_LUT_2_0_data = 12'd2164;
                72:  O_LUT_2_0_data = 12'd2179;
                73:  O_LUT_2_0_data = 12'd2194;
                74:  O_LUT_2_0_data = 12'd2209;
                75:  O_LUT_2_0_data = 12'd2224;
                76:  O_LUT_2_0_data = 12'd2239;
                77:  O_LUT_2_0_data = 12'd2253;
                78:  O_LUT_2_0_data = 12'd2268;
                79:  O_LUT_2_0_data = 12'd2282;
                80:  O_LUT_2_0_data = 12'd2296;
                81:  O_LUT_2_0_data = 12'd2311;
                82:  O_LUT_2_0_data = 12'd2325;
                83:  O_LUT_2_0_data = 12'd2339;
                84:  O_LUT_2_0_data = 12'd2353;
                85:  O_LUT_2_0_data = 12'd2367;
                86:  O_LUT_2_0_data = 12'd2380;
                87:  O_LUT_2_0_data = 12'd2394;
                88:  O_LUT_2_0_data = 12'd2408;
                89:  O_LUT_2_0_data = 12'd2421;
                90:  O_LUT_2_0_data = 12'd2435;
                91:  O_LUT_2_0_data = 12'd2448;
                92:  O_LUT_2_0_data = 12'd2462;
                93:  O_LUT_2_0_data = 12'd2475;
                94:  O_LUT_2_0_data = 12'd2488;
                95:  O_LUT_2_0_data = 12'd2501;
                96:  O_LUT_2_0_data = 12'd2514;
                97:  O_LUT_2_0_data = 12'd2527;
                98:  O_LUT_2_0_data = 12'd2540;
                99:  O_LUT_2_0_data = 12'd2553;
                100: O_LUT_2_0_data = 12'd2566;
                101: O_LUT_2_0_data = 12'd2579;
                102: O_LUT_2_0_data = 12'd2591;
                103: O_LUT_2_0_data = 12'd2604;
                104: O_LUT_2_0_data = 12'd2616;
                105: O_LUT_2_0_data = 12'd2629;
                106: O_LUT_2_0_data = 12'd2641;
                107: O_LUT_2_0_data = 12'd2654;
                108: O_LUT_2_0_data = 12'd2666;
                109: O_LUT_2_0_data = 12'd2678;
                110: O_LUT_2_0_data = 12'd2691;
                111: O_LUT_2_0_data = 12'd2703;
                112: O_LUT_2_0_data = 12'd2715;
                113: O_LUT_2_0_data = 12'd2727;
                114: O_LUT_2_0_data = 12'd2739;
                115: O_LUT_2_0_data = 12'd2751;
                116: O_LUT_2_0_data = 12'd2763;
                117: O_LUT_2_0_data = 12'd2774;
                118: O_LUT_2_0_data = 12'd2786;
                119: O_LUT_2_0_data = 12'd2798;
                120: O_LUT_2_0_data = 12'd2810;
                121: O_LUT_2_0_data = 12'd2821;
                122: O_LUT_2_0_data = 12'd2833;
                123: O_LUT_2_0_data = 12'd2844;
                124: O_LUT_2_0_data = 12'd2856;
                125: O_LUT_2_0_data = 12'd2867;
                126: O_LUT_2_0_data = 12'd2879;
                127: O_LUT_2_0_data = 12'd2890;
                128: O_LUT_2_0_data = 12'd2901;
                129: O_LUT_2_0_data = 12'd2913;
                130: O_LUT_2_0_data = 12'd2924;
                131: O_LUT_2_0_data = 12'd2935;
                132: O_LUT_2_0_data = 12'd2946;
                133: O_LUT_2_0_data = 12'd2957;
                134: O_LUT_2_0_data = 12'd2968;
                135: O_LUT_2_0_data = 12'd2979;
                136: O_LUT_2_0_data = 12'd2990;
                137: O_LUT_2_0_data = 12'd3001;
                138: O_LUT_2_0_data = 12'd3012;
                139: O_LUT_2_0_data = 12'd3023;
                140: O_LUT_2_0_data = 12'd3034;
                141: O_LUT_2_0_data = 12'd3045;
                142: O_LUT_2_0_data = 12'd3055;
                143: O_LUT_2_0_data = 12'd3066;
                144: O_LUT_2_0_data = 12'd3077;
                145: O_LUT_2_0_data = 12'd3087;
                146: O_LUT_2_0_data = 12'd3098;
                147: O_LUT_2_0_data = 12'd3109;
                148: O_LUT_2_0_data = 12'd3119;
                149: O_LUT_2_0_data = 12'd3130;
                150: O_LUT_2_0_data = 12'd3140;
                151: O_LUT_2_0_data = 12'd3150;
                152: O_LUT_2_0_data = 12'd3161;
                153: O_LUT_2_0_data = 12'd3171;
                154: O_LUT_2_0_data = 12'd3182;
                155: O_LUT_2_0_data = 12'd3192;
                156: O_LUT_2_0_data = 12'd3202;
                157: O_LUT_2_0_data = 12'd3212;
                158: O_LUT_2_0_data = 12'd3222;
                159: O_LUT_2_0_data = 12'd3233;
                160: O_LUT_2_0_data = 12'd3243;
                161: O_LUT_2_0_data = 12'd3253;
                162: O_LUT_2_0_data = 12'd3263;
                163: O_LUT_2_0_data = 12'd3273;
                164: O_LUT_2_0_data = 12'd3283;
                165: O_LUT_2_0_data = 12'd3293;
                166: O_LUT_2_0_data = 12'd3303;
                167: O_LUT_2_0_data = 12'd3313;
                168: O_LUT_2_0_data = 12'd3323;
                169: O_LUT_2_0_data = 12'd3332;
                170: O_LUT_2_0_data = 12'd3342;
                171: O_LUT_2_0_data = 12'd3352;
                172: O_LUT_2_0_data = 12'd3362;
                173: O_LUT_2_0_data = 12'd3372;
                174: O_LUT_2_0_data = 12'd3381;
                175: O_LUT_2_0_data = 12'd3391;
                176: O_LUT_2_0_data = 12'd3401;
                177: O_LUT_2_0_data = 12'd3410;
                178: O_LUT_2_0_data = 12'd3420;
                179: O_LUT_2_0_data = 12'd3429;
                180: O_LUT_2_0_data = 12'd3439;
                181: O_LUT_2_0_data = 12'd3448;
                182: O_LUT_2_0_data = 12'd3458;
                183: O_LUT_2_0_data = 12'd3467;
                184: O_LUT_2_0_data = 12'd3477;
                185: O_LUT_2_0_data = 12'd3486;
                186: O_LUT_2_0_data = 12'd3496;
                187: O_LUT_2_0_data = 12'd3505;
                188: O_LUT_2_0_data = 12'd3514;
                189: O_LUT_2_0_data = 12'd3524;
                190: O_LUT_2_0_data = 12'd3533;
                191: O_LUT_2_0_data = 12'd3542;
                192: O_LUT_2_0_data = 12'd3551;
                193: O_LUT_2_0_data = 12'd3561;
                194: O_LUT_2_0_data = 12'd3570;
                195: O_LUT_2_0_data = 12'd3579;
                196: O_LUT_2_0_data = 12'd3588;
                197: O_LUT_2_0_data = 12'd3597;
                198: O_LUT_2_0_data = 12'd3606;
                199: O_LUT_2_0_data = 12'd3615;
                200: O_LUT_2_0_data = 12'd3624;
                201: O_LUT_2_0_data = 12'd3633;
                202: O_LUT_2_0_data = 12'd3642;
                203: O_LUT_2_0_data = 12'd3651;
                204: O_LUT_2_0_data = 12'd3660;
                205: O_LUT_2_0_data = 12'd3669;
                206: O_LUT_2_0_data = 12'd3678;
                207: O_LUT_2_0_data = 12'd3687;
                208: O_LUT_2_0_data = 12'd3696;
                209: O_LUT_2_0_data = 12'd3705;
                210: O_LUT_2_0_data = 12'd3714;
                211: O_LUT_2_0_data = 12'd3723;
                212: O_LUT_2_0_data = 12'd3731;
                213: O_LUT_2_0_data = 12'd3740;
                214: O_LUT_2_0_data = 12'd3749;
                215: O_LUT_2_0_data = 12'd3758;
                216: O_LUT_2_0_data = 12'd3766;
                217: O_LUT_2_0_data = 12'd3775;
                218: O_LUT_2_0_data = 12'd3784;
                219: O_LUT_2_0_data = 12'd3792;
                220: O_LUT_2_0_data = 12'd3801;
                221: O_LUT_2_0_data = 12'd3810;
                222: O_LUT_2_0_data = 12'd3818;
                223: O_LUT_2_0_data = 12'd3827;
                224: O_LUT_2_0_data = 12'd3835;
                225: O_LUT_2_0_data = 12'd3844;
                226: O_LUT_2_0_data = 12'd3852;
                227: O_LUT_2_0_data = 12'd3861;
                228: O_LUT_2_0_data = 12'd3869;
                229: O_LUT_2_0_data = 12'd3878;
                230: O_LUT_2_0_data = 12'd3886;
                231: O_LUT_2_0_data = 12'd3895;
                232: O_LUT_2_0_data = 12'd3903;
                233: O_LUT_2_0_data = 12'd3911;
                234: O_LUT_2_0_data = 12'd3920;
                235: O_LUT_2_0_data = 12'd3928;
                236: O_LUT_2_0_data = 12'd3936;
                237: O_LUT_2_0_data = 12'd3945;
                238: O_LUT_2_0_data = 12'd3953;
                239: O_LUT_2_0_data = 12'd3961;
                240: O_LUT_2_0_data = 12'd3970;
                241: O_LUT_2_0_data = 12'd3978;
                242: O_LUT_2_0_data = 12'd3986;
                243: O_LUT_2_0_data = 12'd3994;
                244: O_LUT_2_0_data = 12'd4002;
                245: O_LUT_2_0_data = 12'd4011;
                246: O_LUT_2_0_data = 12'd4019;
                247: O_LUT_2_0_data = 12'd4027;
                248: O_LUT_2_0_data = 12'd4035;
                249: O_LUT_2_0_data = 12'd4043;
                250: O_LUT_2_0_data = 12'd4051;
                251: O_LUT_2_0_data = 12'd4059;
                252: O_LUT_2_0_data = 12'd4067;
                253: O_LUT_2_0_data = 12'd4075;
                254: O_LUT_2_0_data = 12'd4083;
                255: O_LUT_2_0_data = 12'd4091;
            default: O_LUT_2_0_data = 12'd4091;
        endcase
    end

endmodule
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
/*********legacy_ui_lut_2_2 ********************************************
@Description :   GAMMA=2.2
*****************************************************************/
module legacy_ui_lut_2_2 (
    input                    I_clk  ,
    input                    I_rst_n,

    input      [7:0]              I_LUT_2_2_data  ,
    output reg [11:0]              O_LUT_2_2_data  
);
    
    always @(*)begin 
        case (I_LUT_2_2_data)
                0:   O_LUT_2_2_data = 12'd240; 
                1:   O_LUT_2_2_data = 12'd396; 
                2:   O_LUT_2_2_data = 12'd499; 
                3:   O_LUT_2_2_data = 12'd582; 
                4:   O_LUT_2_2_data = 12'd652; 
                5:   O_LUT_2_2_data = 12'd715; 
                6:   O_LUT_2_2_data = 12'd771; 
                7:   O_LUT_2_2_data = 12'd823; 
                8:   O_LUT_2_2_data = 12'd871; 
                9:   O_LUT_2_2_data = 12'd916; 
                10:  O_LUT_2_2_data = 12'd959; 
                11:  O_LUT_2_2_data = 12'd999; 
                12:  O_LUT_2_2_data = 12'd1038;
                13:  O_LUT_2_2_data = 12'd1075;
                14:  O_LUT_2_2_data = 12'd1110;
                15:  O_LUT_2_2_data = 12'd1145;
                16:  O_LUT_2_2_data = 12'd1178;
                17:  O_LUT_2_2_data = 12'd1209;
                18:  O_LUT_2_2_data = 12'd1240;
                19:  O_LUT_2_2_data = 12'd1270;
                20:  O_LUT_2_2_data = 12'd1300;
                21:  O_LUT_2_2_data = 12'd1328;
                22:  O_LUT_2_2_data = 12'd1356;
                23:  O_LUT_2_2_data = 12'd1383;
                24:  O_LUT_2_2_data = 12'd1409;
                25:  O_LUT_2_2_data = 12'd1435;
                26:  O_LUT_2_2_data = 12'd1461;
                27:  O_LUT_2_2_data = 12'd1485;
                28:  O_LUT_2_2_data = 12'd1510;
                29:  O_LUT_2_2_data = 12'd1534;
                30:  O_LUT_2_2_data = 12'd1557;
                31:  O_LUT_2_2_data = 12'd1580;
                32:  O_LUT_2_2_data = 12'd1603;
                33:  O_LUT_2_2_data = 12'd1625;
                34:  O_LUT_2_2_data = 12'd1647;
                35:  O_LUT_2_2_data = 12'd1668;
                36:  O_LUT_2_2_data = 12'd1689;
                37:  O_LUT_2_2_data = 12'd1710;
                38:  O_LUT_2_2_data = 12'd1731;
                39:  O_LUT_2_2_data = 12'd1751;
                40:  O_LUT_2_2_data = 12'd1771;
                41:  O_LUT_2_2_data = 12'd1791;
                42:  O_LUT_2_2_data = 12'd1810;
                43:  O_LUT_2_2_data = 12'd1830;
                44:  O_LUT_2_2_data = 12'd1849;
                45:  O_LUT_2_2_data = 12'd1868;
                46:  O_LUT_2_2_data = 12'd1886;
                47:  O_LUT_2_2_data = 12'd1904;
                48:  O_LUT_2_2_data = 12'd1923;
                49:  O_LUT_2_2_data = 12'd1940;
                50:  O_LUT_2_2_data = 12'd1958;
                51:  O_LUT_2_2_data = 12'd1976;
                52:  O_LUT_2_2_data = 12'd1993;
                53:  O_LUT_2_2_data = 12'd2010;
                54:  O_LUT_2_2_data = 12'd2027;
                55:  O_LUT_2_2_data = 12'd2044;
                56:  O_LUT_2_2_data = 12'd2061;
                57:  O_LUT_2_2_data = 12'd2077;
                58:  O_LUT_2_2_data = 12'd2094;
                59:  O_LUT_2_2_data = 12'd2110;
                60:  O_LUT_2_2_data = 12'd2126;
                61:  O_LUT_2_2_data = 12'd2142;
                62:  O_LUT_2_2_data = 12'd2157;
                63:  O_LUT_2_2_data = 12'd2173;
                64:  O_LUT_2_2_data = 12'd2189;
                65:  O_LUT_2_2_data = 12'd2204;
                66:  O_LUT_2_2_data = 12'd2219;
                67:  O_LUT_2_2_data = 12'd2234;
                68:  O_LUT_2_2_data = 12'd2249;
                69:  O_LUT_2_2_data = 12'd2264;
                70:  O_LUT_2_2_data = 12'd2279;
                71:  O_LUT_2_2_data = 12'd2294;
                72:  O_LUT_2_2_data = 12'd2308;
                73:  O_LUT_2_2_data = 12'd2322;
                74:  O_LUT_2_2_data = 12'd2337;
                75:  O_LUT_2_2_data = 12'd2351;
                76:  O_LUT_2_2_data = 12'd2365;
                77:  O_LUT_2_2_data = 12'd2379;
                78:  O_LUT_2_2_data = 12'd2393;
                79:  O_LUT_2_2_data = 12'd2407;
                80:  O_LUT_2_2_data = 12'd2421;
                81:  O_LUT_2_2_data = 12'd2434;
                82:  O_LUT_2_2_data = 12'd2448;
                83:  O_LUT_2_2_data = 12'd2461;
                84:  O_LUT_2_2_data = 12'd2474;
                85:  O_LUT_2_2_data = 12'd2488;
                86:  O_LUT_2_2_data = 12'd2501;
                87:  O_LUT_2_2_data = 12'd2514;
                88:  O_LUT_2_2_data = 12'd2527;
                89:  O_LUT_2_2_data = 12'd2540;
                90:  O_LUT_2_2_data = 12'd2553;
                91:  O_LUT_2_2_data = 12'd2566;
                92:  O_LUT_2_2_data = 12'd2578;
                93:  O_LUT_2_2_data = 12'd2591;
                94:  O_LUT_2_2_data = 12'd2604;
                95:  O_LUT_2_2_data = 12'd2616;
                96:  O_LUT_2_2_data = 12'd2628;
                97:  O_LUT_2_2_data = 12'd2641;
                98:  O_LUT_2_2_data = 12'd2653;
                99:  O_LUT_2_2_data = 12'd2665;
                100: O_LUT_2_2_data = 12'd2677;
                101: O_LUT_2_2_data = 12'd2690;
                102: O_LUT_2_2_data = 12'd2702;
                103: O_LUT_2_2_data = 12'd2713;
                104: O_LUT_2_2_data = 12'd2725;
                105: O_LUT_2_2_data = 12'd2737;
                106: O_LUT_2_2_data = 12'd2749;
                107: O_LUT_2_2_data = 12'd2761;
                108: O_LUT_2_2_data = 12'd2772;
                109: O_LUT_2_2_data = 12'd2784;
                110: O_LUT_2_2_data = 12'd2795;
                111: O_LUT_2_2_data = 12'd2807;
                112: O_LUT_2_2_data = 12'd2818;
                113: O_LUT_2_2_data = 12'd2830;
                114: O_LUT_2_2_data = 12'd2841;
                115: O_LUT_2_2_data = 12'd2852;
                116: O_LUT_2_2_data = 12'd2863;
                117: O_LUT_2_2_data = 12'd2875;
                118: O_LUT_2_2_data = 12'd2886;
                119: O_LUT_2_2_data = 12'd2897;
                120: O_LUT_2_2_data = 12'd2908;
                121: O_LUT_2_2_data = 12'd2919;
                122: O_LUT_2_2_data = 12'd2930;
                123: O_LUT_2_2_data = 12'd2940;
                124: O_LUT_2_2_data = 12'd2951;
                125: O_LUT_2_2_data = 12'd2962;
                126: O_LUT_2_2_data = 12'd2973;
                127: O_LUT_2_2_data = 12'd2983;
                128: O_LUT_2_2_data = 12'd2994;
                129: O_LUT_2_2_data = 12'd3004;
                130: O_LUT_2_2_data = 12'd3015;
                131: O_LUT_2_2_data = 12'd3025;
                132: O_LUT_2_2_data = 12'd3036;
                133: O_LUT_2_2_data = 12'd3046;
                134: O_LUT_2_2_data = 12'd3057;
                135: O_LUT_2_2_data = 12'd3067;
                136: O_LUT_2_2_data = 12'd3077;
                137: O_LUT_2_2_data = 12'd3087;
                138: O_LUT_2_2_data = 12'd3098;
                139: O_LUT_2_2_data = 12'd3108;
                140: O_LUT_2_2_data = 12'd3118;
                141: O_LUT_2_2_data = 12'd3128;
                142: O_LUT_2_2_data = 12'd3138;
                143: O_LUT_2_2_data = 12'd3148;
                144: O_LUT_2_2_data = 12'd3158;
                145: O_LUT_2_2_data = 12'd3168;
                146: O_LUT_2_2_data = 12'd3178;
                147: O_LUT_2_2_data = 12'd3188;
                148: O_LUT_2_2_data = 12'd3197;
                149: O_LUT_2_2_data = 12'd3207;
                150: O_LUT_2_2_data = 12'd3217;
                151: O_LUT_2_2_data = 12'd3227;
                152: O_LUT_2_2_data = 12'd3236;
                153: O_LUT_2_2_data = 12'd3246;
                154: O_LUT_2_2_data = 12'd3255;
                155: O_LUT_2_2_data = 12'd3265;
                156: O_LUT_2_2_data = 12'd3275;
                157: O_LUT_2_2_data = 12'd3284;
                158: O_LUT_2_2_data = 12'd3294;
                159: O_LUT_2_2_data = 12'd3303;
                160: O_LUT_2_2_data = 12'd3312;
                161: O_LUT_2_2_data = 12'd3322;
                162: O_LUT_2_2_data = 12'd3331;
                163: O_LUT_2_2_data = 12'd3340;
                164: O_LUT_2_2_data = 12'd3350;
                165: O_LUT_2_2_data = 12'd3359;
                166: O_LUT_2_2_data = 12'd3368;
                167: O_LUT_2_2_data = 12'd3377;
                168: O_LUT_2_2_data = 12'd3386;
                169: O_LUT_2_2_data = 12'd3396;
                170: O_LUT_2_2_data = 12'd3405;
                171: O_LUT_2_2_data = 12'd3414;
                172: O_LUT_2_2_data = 12'd3423;
                173: O_LUT_2_2_data = 12'd3432;
                174: O_LUT_2_2_data = 12'd3441;
                175: O_LUT_2_2_data = 12'd3450;
                176: O_LUT_2_2_data = 12'd3459;
                177: O_LUT_2_2_data = 12'd3467;
                178: O_LUT_2_2_data = 12'd3476;
                179: O_LUT_2_2_data = 12'd3485;
                180: O_LUT_2_2_data = 12'd3494;
                181: O_LUT_2_2_data = 12'd3503;
                182: O_LUT_2_2_data = 12'd3512;
                183: O_LUT_2_2_data = 12'd3520;
                184: O_LUT_2_2_data = 12'd3529;
                185: O_LUT_2_2_data = 12'd3538;
                186: O_LUT_2_2_data = 12'd3546;
                187: O_LUT_2_2_data = 12'd3555;
                188: O_LUT_2_2_data = 12'd3564;
                189: O_LUT_2_2_data = 12'd3572;
                190: O_LUT_2_2_data = 12'd3581;
                191: O_LUT_2_2_data = 12'd3589;
                192: O_LUT_2_2_data = 12'd3598;
                193: O_LUT_2_2_data = 12'd3606;
                194: O_LUT_2_2_data = 12'd3615;
                195: O_LUT_2_2_data = 12'd3623;
                196: O_LUT_2_2_data = 12'd3632;
                197: O_LUT_2_2_data = 12'd3640;
                198: O_LUT_2_2_data = 12'd3648;
                199: O_LUT_2_2_data = 12'd3657;
                200: O_LUT_2_2_data = 12'd3665;
                201: O_LUT_2_2_data = 12'd3673;
                202: O_LUT_2_2_data = 12'd3682;
                203: O_LUT_2_2_data = 12'd3690;
                204: O_LUT_2_2_data = 12'd3698;
                205: O_LUT_2_2_data = 12'd3706;
                206: O_LUT_2_2_data = 12'd3714;
                207: O_LUT_2_2_data = 12'd3723;
                208: O_LUT_2_2_data = 12'd3731;
                209: O_LUT_2_2_data = 12'd3739;
                210: O_LUT_2_2_data = 12'd3747;
                211: O_LUT_2_2_data = 12'd3755;
                212: O_LUT_2_2_data = 12'd3763;
                213: O_LUT_2_2_data = 12'd3771;
                214: O_LUT_2_2_data = 12'd3779;
                215: O_LUT_2_2_data = 12'd3787;
                216: O_LUT_2_2_data = 12'd3795;
                217: O_LUT_2_2_data = 12'd3803;
                218: O_LUT_2_2_data = 12'd3811;
                219: O_LUT_2_2_data = 12'd3819;
                220: O_LUT_2_2_data = 12'd3827;
                221: O_LUT_2_2_data = 12'd3835;
                222: O_LUT_2_2_data = 12'd3843;
                223: O_LUT_2_2_data = 12'd3850;
                224: O_LUT_2_2_data = 12'd3858;
                225: O_LUT_2_2_data = 12'd3866;
                226: O_LUT_2_2_data = 12'd3874;
                227: O_LUT_2_2_data = 12'd3882;
                228: O_LUT_2_2_data = 12'd3889;
                229: O_LUT_2_2_data = 12'd3897;
                230: O_LUT_2_2_data = 12'd3905;
                231: O_LUT_2_2_data = 12'd3912;
                232: O_LUT_2_2_data = 12'd3920;
                233: O_LUT_2_2_data = 12'd3928;
                234: O_LUT_2_2_data = 12'd3935;
                235: O_LUT_2_2_data = 12'd3943;
                236: O_LUT_2_2_data = 12'd3951;
                237: O_LUT_2_2_data = 12'd3958;
                238: O_LUT_2_2_data = 12'd3966;
                239: O_LUT_2_2_data = 12'd3973;
                240: O_LUT_2_2_data = 12'd3981;
                241: O_LUT_2_2_data = 12'd3988;
                242: O_LUT_2_2_data = 12'd3996;
                243: O_LUT_2_2_data = 12'd4003;
                244: O_LUT_2_2_data = 12'd4011;
                245: O_LUT_2_2_data = 12'd4018;
                246: O_LUT_2_2_data = 12'd4026;
                247: O_LUT_2_2_data = 12'd4033;
                248: O_LUT_2_2_data = 12'd4041;
                249: O_LUT_2_2_data = 12'd4048;
                250: O_LUT_2_2_data = 12'd4055;
                251: O_LUT_2_2_data = 12'd4063;
                252: O_LUT_2_2_data = 12'd4070;
                253: O_LUT_2_2_data = 12'd4077;
                254: O_LUT_2_2_data = 12'd4085;
                255: O_LUT_2_2_data = 12'd4092;
            default: O_LUT_2_2_data = 12'd4092;
        endcase
    end




endmodule
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
/*********legacy_ui_lut_2_4 ********************************************
@Description :   GAMMA=2.4
*****************************************************************/
module legacy_ui_lut_2_4 (
    input                    I_clk  ,
    input                    I_rst_n,
    input      [7:0]         I_LUT_2_4_data  ,
    output reg [11:0]        O_LUT_2_4_data  
);
    
    always @(*)begin 
        case (I_LUT_2_4_data)
                0:   O_LUT_2_4_data = 12'd317;
                1:   O_LUT_2_4_data = 12'd497;
                2:   O_LUT_2_4_data = 12'd613;
                3:   O_LUT_2_4_data = 12'd704;
                4:   O_LUT_2_4_data = 12'd781;
                5:   O_LUT_2_4_data = 12'd848;
                6:   O_LUT_2_4_data = 12'd908;
                7:   O_LUT_2_4_data = 12'd963;
                8:   O_LUT_2_4_data = 12'd1014;
                9:   O_LUT_2_4_data = 12'd1061;
                10:  O_LUT_2_4_data = 12'd1105;
                11:  O_LUT_2_4_data = 12'd1147;
                12:  O_LUT_2_4_data = 12'd1187;
                13:  O_LUT_2_4_data = 12'd1225;
                14:  O_LUT_2_4_data = 12'd1262;
                15:  O_LUT_2_4_data = 12'd1297;
                16:  O_LUT_2_4_data = 12'd1330;
                17:  O_LUT_2_4_data = 12'd1363;
                18:  O_LUT_2_4_data = 12'd1394;
                19:  O_LUT_2_4_data = 12'd1425;
                20:  O_LUT_2_4_data = 12'd1454;
                21:  O_LUT_2_4_data = 12'd1483;
                22:  O_LUT_2_4_data = 12'd1511;
                23:  O_LUT_2_4_data = 12'd1538;
                24:  O_LUT_2_4_data = 12'd1565;
                25:  O_LUT_2_4_data = 12'd1590;
                26:  O_LUT_2_4_data = 12'd1616;
                27:  O_LUT_2_4_data = 12'd1640;
                28:  O_LUT_2_4_data = 12'd1665;
                29:  O_LUT_2_4_data = 12'd1688;
                30:  O_LUT_2_4_data = 12'd1712;
                31:  O_LUT_2_4_data = 12'd1734;
                32:  O_LUT_2_4_data = 12'd1757;
                33:  O_LUT_2_4_data = 12'd1779;
                34:  O_LUT_2_4_data = 12'd1800;
                35:  O_LUT_2_4_data = 12'd1822;
                36:  O_LUT_2_4_data = 12'd1842;
                37:  O_LUT_2_4_data = 12'd1863;
                38:  O_LUT_2_4_data = 12'd1883;
                39:  O_LUT_2_4_data = 12'd1903;
                40:  O_LUT_2_4_data = 12'd1923;
                41:  O_LUT_2_4_data = 12'd1942;
                42:  O_LUT_2_4_data = 12'd1961;
                43:  O_LUT_2_4_data = 12'd1980;
                44:  O_LUT_2_4_data = 12'd1998;
                45:  O_LUT_2_4_data = 12'd2017;
                46:  O_LUT_2_4_data = 12'd2035;
                47:  O_LUT_2_4_data = 12'd2053;
                48:  O_LUT_2_4_data = 12'd2070;
                49:  O_LUT_2_4_data = 12'd2088;
                50:  O_LUT_2_4_data = 12'd2105;
                51:  O_LUT_2_4_data = 12'd2122;
                52:  O_LUT_2_4_data = 12'd2139;
                53:  O_LUT_2_4_data = 12'd2155;
                54:  O_LUT_2_4_data = 12'd2172;
                55:  O_LUT_2_4_data = 12'd2188;
                56:  O_LUT_2_4_data = 12'd2204;
                57:  O_LUT_2_4_data = 12'd2220;
                58:  O_LUT_2_4_data = 12'd2236;
                59:  O_LUT_2_4_data = 12'd2251;
                60:  O_LUT_2_4_data = 12'd2267;
                61:  O_LUT_2_4_data = 12'd2282;
                62:  O_LUT_2_4_data = 12'd2297;
                63:  O_LUT_2_4_data = 12'd2312;
                64:  O_LUT_2_4_data = 12'd2327;
                65:  O_LUT_2_4_data = 12'd2342;
                66:  O_LUT_2_4_data = 12'd2356;
                67:  O_LUT_2_4_data = 12'd2371;
                68:  O_LUT_2_4_data = 12'd2385;
                69:  O_LUT_2_4_data = 12'd2399;
                70:  O_LUT_2_4_data = 12'd2414;
                71:  O_LUT_2_4_data = 12'd2427;
                72:  O_LUT_2_4_data = 12'd2441;
                73:  O_LUT_2_4_data = 12'd2455;
                74:  O_LUT_2_4_data = 12'd2469;
                75:  O_LUT_2_4_data = 12'd2482;
                76:  O_LUT_2_4_data = 12'd2496;
                77:  O_LUT_2_4_data = 12'd2509;
                78:  O_LUT_2_4_data = 12'd2522;
                79:  O_LUT_2_4_data = 12'd2535;
                80:  O_LUT_2_4_data = 12'd2548;
                81:  O_LUT_2_4_data = 12'd2561;
                82:  O_LUT_2_4_data = 12'd2574;
                83:  O_LUT_2_4_data = 12'd2587;
                84:  O_LUT_2_4_data = 12'd2600;
                85:  O_LUT_2_4_data = 12'd2612;
                86:  O_LUT_2_4_data = 12'd2625;
                87:  O_LUT_2_4_data = 12'd2637;
                88:  O_LUT_2_4_data = 12'd2649;
                89:  O_LUT_2_4_data = 12'd2662;
                90:  O_LUT_2_4_data = 12'd2674;
                91:  O_LUT_2_4_data = 12'd2686;
                92:  O_LUT_2_4_data = 12'd2698;
                93:  O_LUT_2_4_data = 12'd2710;
                94:  O_LUT_2_4_data = 12'd2722;
                95:  O_LUT_2_4_data = 12'd2733;
                96:  O_LUT_2_4_data = 12'd2745;
                97:  O_LUT_2_4_data = 12'd2757;
                98:  O_LUT_2_4_data = 12'd2768;
                99:  O_LUT_2_4_data = 12'd2780;
                100: O_LUT_2_4_data = 12'd2791;
                101: O_LUT_2_4_data = 12'd2803;
                102: O_LUT_2_4_data = 12'd2814;
                103: O_LUT_2_4_data = 12'd2825;
                104: O_LUT_2_4_data = 12'd2836;
                105: O_LUT_2_4_data = 12'd2847;
                106: O_LUT_2_4_data = 12'd2858;
                107: O_LUT_2_4_data = 12'd2869;
                108: O_LUT_2_4_data = 12'd2880;
                109: O_LUT_2_4_data = 12'd2891;
                110: O_LUT_2_4_data = 12'd2902;
                111: O_LUT_2_4_data = 12'd2913;
                112: O_LUT_2_4_data = 12'd2923;
                113: O_LUT_2_4_data = 12'd2934;
                114: O_LUT_2_4_data = 12'd2945;
                115: O_LUT_2_4_data = 12'd2955;
                116: O_LUT_2_4_data = 12'd2966;
                117: O_LUT_2_4_data = 12'd2976;
                118: O_LUT_2_4_data = 12'd2986;
                119: O_LUT_2_4_data = 12'd2997;
                120: O_LUT_2_4_data = 12'd3007;
                121: O_LUT_2_4_data = 12'd3017;
                122: O_LUT_2_4_data = 12'd3027;
                123: O_LUT_2_4_data = 12'd3037;
                124: O_LUT_2_4_data = 12'd3047;
                125: O_LUT_2_4_data = 12'd3057;
                126: O_LUT_2_4_data = 12'd3067;
                127: O_LUT_2_4_data = 12'd3077;
                128: O_LUT_2_4_data = 12'd3087;
                129: O_LUT_2_4_data = 12'd3097;
                130: O_LUT_2_4_data = 12'd3107;
                131: O_LUT_2_4_data = 12'd3117;
                132: O_LUT_2_4_data = 12'd3126;
                133: O_LUT_2_4_data = 12'd3136;
                134: O_LUT_2_4_data = 12'd3145;
                135: O_LUT_2_4_data = 12'd3155;
                136: O_LUT_2_4_data = 12'd3165;
                137: O_LUT_2_4_data = 12'd3174;
                138: O_LUT_2_4_data = 12'd3184;
                139: O_LUT_2_4_data = 12'd3193;
                140: O_LUT_2_4_data = 12'd3202;
                141: O_LUT_2_4_data = 12'd3212;
                142: O_LUT_2_4_data = 12'd3221;
                143: O_LUT_2_4_data = 12'd3230;
                144: O_LUT_2_4_data = 12'd3239;
                145: O_LUT_2_4_data = 12'd3249;
                146: O_LUT_2_4_data = 12'd3258;
                147: O_LUT_2_4_data = 12'd3267;
                148: O_LUT_2_4_data = 12'd3276;
                149: O_LUT_2_4_data = 12'd3285;
                150: O_LUT_2_4_data = 12'd3294;
                151: O_LUT_2_4_data = 12'd3303;
                152: O_LUT_2_4_data = 12'd3312;
                153: O_LUT_2_4_data = 12'd3321;
                154: O_LUT_2_4_data = 12'd3329;
                155: O_LUT_2_4_data = 12'd3338;
                156: O_LUT_2_4_data = 12'd3347;
                157: O_LUT_2_4_data = 12'd3356;
                158: O_LUT_2_4_data = 12'd3365;
                159: O_LUT_2_4_data = 12'd3373;
                160: O_LUT_2_4_data = 12'd3382;
                161: O_LUT_2_4_data = 12'd3391;
                162: O_LUT_2_4_data = 12'd3399;
                163: O_LUT_2_4_data = 12'd3408;
                164: O_LUT_2_4_data = 12'd3416;
                165: O_LUT_2_4_data = 12'd3425;
                166: O_LUT_2_4_data = 12'd3433;
                167: O_LUT_2_4_data = 12'd3442;
                168: O_LUT_2_4_data = 12'd3450;
                169: O_LUT_2_4_data = 12'd3458;
                170: O_LUT_2_4_data = 12'd3467;
                171: O_LUT_2_4_data = 12'd3475;
                172: O_LUT_2_4_data = 12'd3483;
                173: O_LUT_2_4_data = 12'd3492;
                174: O_LUT_2_4_data = 12'd3500;
                175: O_LUT_2_4_data = 12'd3508;
                176: O_LUT_2_4_data = 12'd3516;
                177: O_LUT_2_4_data = 12'd3524;
                178: O_LUT_2_4_data = 12'd3533;
                179: O_LUT_2_4_data = 12'd3541;
                180: O_LUT_2_4_data = 12'd3549;
                181: O_LUT_2_4_data = 12'd3557;
                182: O_LUT_2_4_data = 12'd3565;
                183: O_LUT_2_4_data = 12'd3573;
                184: O_LUT_2_4_data = 12'd3581;
                185: O_LUT_2_4_data = 12'd3589;
                186: O_LUT_2_4_data = 12'd3597;
                187: O_LUT_2_4_data = 12'd3605;
                188: O_LUT_2_4_data = 12'd3612;
                189: O_LUT_2_4_data = 12'd3620;
                190: O_LUT_2_4_data = 12'd3628;
                191: O_LUT_2_4_data = 12'd3636;
                192: O_LUT_2_4_data = 12'd3644;
                193: O_LUT_2_4_data = 12'd3651;
                194: O_LUT_2_4_data = 12'd3659;
                195: O_LUT_2_4_data = 12'd3667;
                196: O_LUT_2_4_data = 12'd3675;
                197: O_LUT_2_4_data = 12'd3682;
                198: O_LUT_2_4_data = 12'd3690;
                199: O_LUT_2_4_data = 12'd3697;
                200: O_LUT_2_4_data = 12'd3705;
                201: O_LUT_2_4_data = 12'd3713;
                202: O_LUT_2_4_data = 12'd3720;
                203: O_LUT_2_4_data = 12'd3728;
                204: O_LUT_2_4_data = 12'd3735;
                205: O_LUT_2_4_data = 12'd3743;
                206: O_LUT_2_4_data = 12'd3750;
                207: O_LUT_2_4_data = 12'd3758;
                208: O_LUT_2_4_data = 12'd3765;
                209: O_LUT_2_4_data = 12'd3772;
                210: O_LUT_2_4_data = 12'd3780;
                211: O_LUT_2_4_data = 12'd3787;
                212: O_LUT_2_4_data = 12'd3794;
                213: O_LUT_2_4_data = 12'd3802;
                214: O_LUT_2_4_data = 12'd3809;
                215: O_LUT_2_4_data = 12'd3816;
                216: O_LUT_2_4_data = 12'd3824;
                217: O_LUT_2_4_data = 12'd3831;
                218: O_LUT_2_4_data = 12'd3838;
                219: O_LUT_2_4_data = 12'd3845;
                220: O_LUT_2_4_data = 12'd3852;
                221: O_LUT_2_4_data = 12'd3859;
                222: O_LUT_2_4_data = 12'd3867;
                223: O_LUT_2_4_data = 12'd3874;
                224: O_LUT_2_4_data = 12'd3881;
                225: O_LUT_2_4_data = 12'd3888;
                226: O_LUT_2_4_data = 12'd3895;
                227: O_LUT_2_4_data = 12'd3902;
                228: O_LUT_2_4_data = 12'd3909;
                229: O_LUT_2_4_data = 12'd3916;
                230: O_LUT_2_4_data = 12'd3923;
                231: O_LUT_2_4_data = 12'd3930;
                232: O_LUT_2_4_data = 12'd3937;
                233: O_LUT_2_4_data = 12'd3944;
                234: O_LUT_2_4_data = 12'd3951;
                235: O_LUT_2_4_data = 12'd3958;
                236: O_LUT_2_4_data = 12'd3965;
                237: O_LUT_2_4_data = 12'd3971;
                238: O_LUT_2_4_data = 12'd3978;
                239: O_LUT_2_4_data = 12'd3985;
                240: O_LUT_2_4_data = 12'd3992;
                241: O_LUT_2_4_data = 12'd3999;
                242: O_LUT_2_4_data = 12'd4006;
                243: O_LUT_2_4_data = 12'd4012;
                244: O_LUT_2_4_data = 12'd4019;
                245: O_LUT_2_4_data = 12'd4026;
                246: O_LUT_2_4_data = 12'd4032;
                247: O_LUT_2_4_data = 12'd4039;
                248: O_LUT_2_4_data = 12'd4046;
                249: O_LUT_2_4_data = 12'd4053;
                250: O_LUT_2_4_data = 12'd4059;
                251: O_LUT_2_4_data = 12'd4066;
                252: O_LUT_2_4_data = 12'd4072;
                253: O_LUT_2_4_data = 12'd4079;
                254: O_LUT_2_4_data = 12'd4086;
                255: O_LUT_2_4_data = 12'd4092;
            default: O_LUT_2_4_data = 12'd4092;
        endcase
    end




endmodule
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
/*********legacy_ui_lut_2_6 ********************************************
@Description :   GAMMA=2.6
*****************************************************************/
module legacy_ui_lut_2_6 (
    input                    I_clk  ,
    input                    I_rst_n,

    input      [7:0]         I_LUT_2_6_data  ,
    output reg [11:0]        O_LUT_2_6_data  
);
    
    always @(*)begin 
        case (I_LUT_2_6_data)
                0:   O_LUT_2_6_data = 12'd373;
                1:   O_LUT_2_6_data = 12'd569;
                2:   O_LUT_2_6_data = 12'd692;
                3:   O_LUT_2_6_data = 12'd787;
                4:   O_LUT_2_6_data = 12'd867;
                5:   O_LUT_2_6_data = 12'd937;
                6:   O_LUT_2_6_data = 12'd999;
                7:   O_LUT_2_6_data = 12'd1055;
                8:   O_LUT_2_6_data = 12'd1107;
                9:   O_LUT_2_6_data = 12'd1156;
                10:  O_LUT_2_6_data = 12'd1201;
                11:  O_LUT_2_6_data = 12'd1244;
                12:  O_LUT_2_6_data = 12'd1284;
                13:  O_LUT_2_6_data = 12'd1323;
                14:  O_LUT_2_6_data = 12'd1360;
                15:  O_LUT_2_6_data = 12'd1395;
                16:  O_LUT_2_6_data = 12'd1429;
                17:  O_LUT_2_6_data = 12'd1461;
                18:  O_LUT_2_6_data = 12'd1493;
                19:  O_LUT_2_6_data = 12'd1523;
                20:  O_LUT_2_6_data = 12'd1553;
                21:  O_LUT_2_6_data = 12'd1582;
                22:  O_LUT_2_6_data = 12'd1610;
                23:  O_LUT_2_6_data = 12'd1637;
                24:  O_LUT_2_6_data = 12'd1663;
                25:  O_LUT_2_6_data = 12'd1689;
                26:  O_LUT_2_6_data = 12'd1714;
                27:  O_LUT_2_6_data = 12'd1738;
                28:  O_LUT_2_6_data = 12'd1763;
                29:  O_LUT_2_6_data = 12'd1786;
                30:  O_LUT_2_6_data = 12'd1809;
                31:  O_LUT_2_6_data = 12'd1832;
                32:  O_LUT_2_6_data = 12'd1854;
                33:  O_LUT_2_6_data = 12'd1875;
                34:  O_LUT_2_6_data = 12'd1897;
                35:  O_LUT_2_6_data = 12'd1918;
                36:  O_LUT_2_6_data = 12'd1938;
                37:  O_LUT_2_6_data = 12'd1958;
                38:  O_LUT_2_6_data = 12'd1978;
                39:  O_LUT_2_6_data = 12'd1998;
                40:  O_LUT_2_6_data = 12'd2017;
                41:  O_LUT_2_6_data = 12'd2036;
                42:  O_LUT_2_6_data = 12'd2055;
                43:  O_LUT_2_6_data = 12'd2073;
                44:  O_LUT_2_6_data = 12'd2092;
                45:  O_LUT_2_6_data = 12'd2109;
                46:  O_LUT_2_6_data = 12'd2127;
                47:  O_LUT_2_6_data = 12'd2145;
                48:  O_LUT_2_6_data = 12'd2162;
                49:  O_LUT_2_6_data = 12'd2179;
                50:  O_LUT_2_6_data = 12'd2196;
                51:  O_LUT_2_6_data = 12'd2212;
                52:  O_LUT_2_6_data = 12'd2229;
                53:  O_LUT_2_6_data = 12'd2245;
                54:  O_LUT_2_6_data = 12'd2261;
                55:  O_LUT_2_6_data = 12'd2277;
                56:  O_LUT_2_6_data = 12'd2292;
                57:  O_LUT_2_6_data = 12'd2308;
                58:  O_LUT_2_6_data = 12'd2323;
                59:  O_LUT_2_6_data = 12'd2338;
                60:  O_LUT_2_6_data = 12'd2353;
                61:  O_LUT_2_6_data = 12'd2368;
                62:  O_LUT_2_6_data = 12'd2383;
                63:  O_LUT_2_6_data = 12'd2398;
                64:  O_LUT_2_6_data = 12'd2412;
                65:  O_LUT_2_6_data = 12'd2426;
                66:  O_LUT_2_6_data = 12'd2440;
                67:  O_LUT_2_6_data = 12'd2454;
                68:  O_LUT_2_6_data = 12'd2468;
                69:  O_LUT_2_6_data = 12'd2482;
                70:  O_LUT_2_6_data = 12'd2496;
                71:  O_LUT_2_6_data = 12'd2509;
                72:  O_LUT_2_6_data = 12'd2523;
                73:  O_LUT_2_6_data = 12'd2536;
                74:  O_LUT_2_6_data = 12'd2549;
                75:  O_LUT_2_6_data = 12'd2562;
                76:  O_LUT_2_6_data = 12'd2575;
                77:  O_LUT_2_6_data = 12'd2588;
                78:  O_LUT_2_6_data = 12'd2601;
                79:  O_LUT_2_6_data = 12'd2614;
                80:  O_LUT_2_6_data = 12'd2626;
                81:  O_LUT_2_6_data = 12'd2639;
                82:  O_LUT_2_6_data = 12'd2651;
                83:  O_LUT_2_6_data = 12'd2663;
                84:  O_LUT_2_6_data = 12'd2676;
                85:  O_LUT_2_6_data = 12'd2688;
                86:  O_LUT_2_6_data = 12'd2700;
                87:  O_LUT_2_6_data = 12'd2712;
                88:  O_LUT_2_6_data = 12'd2724;
                89:  O_LUT_2_6_data = 12'd2735;
                90:  O_LUT_2_6_data = 12'd2747;
                91:  O_LUT_2_6_data = 12'd2759;
                92:  O_LUT_2_6_data = 12'd2770;
                93:  O_LUT_2_6_data = 12'd2782;
                94:  O_LUT_2_6_data = 12'd2793;
                95:  O_LUT_2_6_data = 12'd2804;
                96:  O_LUT_2_6_data = 12'd2816;
                97:  O_LUT_2_6_data = 12'd2827;
                98:  O_LUT_2_6_data = 12'd2838;
                99:  O_LUT_2_6_data = 12'd2849;
                100: O_LUT_2_6_data = 12'd2860;
                101: O_LUT_2_6_data = 12'd2871;
                102: O_LUT_2_6_data = 12'd2882;
                103: O_LUT_2_6_data = 12'd2892;
                104: O_LUT_2_6_data = 12'd2903;
                105: O_LUT_2_6_data = 12'd2914;
                106: O_LUT_2_6_data = 12'd2924;
                107: O_LUT_2_6_data = 12'd2935;
                108: O_LUT_2_6_data = 12'd2945;
                109: O_LUT_2_6_data = 12'd2956;
                110: O_LUT_2_6_data = 12'd2966;
                111: O_LUT_2_6_data = 12'd2976;
                112: O_LUT_2_6_data = 12'd2987;
                113: O_LUT_2_6_data = 12'd2997;
                114: O_LUT_2_6_data = 12'd3007;
                115: O_LUT_2_6_data = 12'd3017;
                116: O_LUT_2_6_data = 12'd3027;
                117: O_LUT_2_6_data = 12'd3037;
                118: O_LUT_2_6_data = 12'd3047;
                119: O_LUT_2_6_data = 12'd3057;
                120: O_LUT_2_6_data = 12'd3066;
                121: O_LUT_2_6_data = 12'd3076;
                122: O_LUT_2_6_data = 12'd3086;
                123: O_LUT_2_6_data = 12'd3095;
                124: O_LUT_2_6_data = 12'd3105;
                125: O_LUT_2_6_data = 12'd3115;
                126: O_LUT_2_6_data = 12'd3124;
                127: O_LUT_2_6_data = 12'd3134;
                128: O_LUT_2_6_data = 12'd3143;
                129: O_LUT_2_6_data = 12'd3152;
                130: O_LUT_2_6_data = 12'd3162;
                131: O_LUT_2_6_data = 12'd3171;
                132: O_LUT_2_6_data = 12'd3180;
                133: O_LUT_2_6_data = 12'd3189;
                134: O_LUT_2_6_data = 12'd3199;
                135: O_LUT_2_6_data = 12'd3208;
                136: O_LUT_2_6_data = 12'd3217;
                137: O_LUT_2_6_data = 12'd3226;
                138: O_LUT_2_6_data = 12'd3235;
                139: O_LUT_2_6_data = 12'd3244;
                140: O_LUT_2_6_data = 12'd3253;
                141: O_LUT_2_6_data = 12'd3262;
                142: O_LUT_2_6_data = 12'd3270;
                143: O_LUT_2_6_data = 12'd3279;
                144: O_LUT_2_6_data = 12'd3288;
                145: O_LUT_2_6_data = 12'd3297;
                146: O_LUT_2_6_data = 12'd3305;
                147: O_LUT_2_6_data = 12'd3314;
                148: O_LUT_2_6_data = 12'd3323;
                149: O_LUT_2_6_data = 12'd3331;
                150: O_LUT_2_6_data = 12'd3340;
                151: O_LUT_2_6_data = 12'd3348;
                152: O_LUT_2_6_data = 12'd3357;
                153: O_LUT_2_6_data = 12'd3365;
                154: O_LUT_2_6_data = 12'd3373;
                155: O_LUT_2_6_data = 12'd3382;
                156: O_LUT_2_6_data = 12'd3390;
                157: O_LUT_2_6_data = 12'd3399;
                158: O_LUT_2_6_data = 12'd3407;
                159: O_LUT_2_6_data = 12'd3415;
                160: O_LUT_2_6_data = 12'd3423;
                161: O_LUT_2_6_data = 12'd3431;
                162: O_LUT_2_6_data = 12'd3440;
                163: O_LUT_2_6_data = 12'd3448;
                164: O_LUT_2_6_data = 12'd3456;
                165: O_LUT_2_6_data = 12'd3464;
                166: O_LUT_2_6_data = 12'd3472;
                167: O_LUT_2_6_data = 12'd3480;
                168: O_LUT_2_6_data = 12'd3488;
                169: O_LUT_2_6_data = 12'd3496;
                170: O_LUT_2_6_data = 12'd3504;
                171: O_LUT_2_6_data = 12'd3511;
                172: O_LUT_2_6_data = 12'd3519;
                173: O_LUT_2_6_data = 12'd3527;
                174: O_LUT_2_6_data = 12'd3535;
                175: O_LUT_2_6_data = 12'd3543;
                176: O_LUT_2_6_data = 12'd3550;
                177: O_LUT_2_6_data = 12'd3558;
                178: O_LUT_2_6_data = 12'd3566;
                179: O_LUT_2_6_data = 12'd3574;
                180: O_LUT_2_6_data = 12'd3581;
                181: O_LUT_2_6_data = 12'd3589;
                182: O_LUT_2_6_data = 12'd3596;
                183: O_LUT_2_6_data = 12'd3604;
                184: O_LUT_2_6_data = 12'd3611;
                185: O_LUT_2_6_data = 12'd3619;
                186: O_LUT_2_6_data = 12'd3626;
                187: O_LUT_2_6_data = 12'd3634;
                188: O_LUT_2_6_data = 12'd3641;
                189: O_LUT_2_6_data = 12'd3649;
                190: O_LUT_2_6_data = 12'd3656;
                191: O_LUT_2_6_data = 12'd3663;
                192: O_LUT_2_6_data = 12'd3671;
                193: O_LUT_2_6_data = 12'd3678;
                194: O_LUT_2_6_data = 12'd3685;
                195: O_LUT_2_6_data = 12'd3693;
                196: O_LUT_2_6_data = 12'd3700;
                197: O_LUT_2_6_data = 12'd3707;
                198: O_LUT_2_6_data = 12'd3714;
                199: O_LUT_2_6_data = 12'd3721;
                200: O_LUT_2_6_data = 12'd3729;
                201: O_LUT_2_6_data = 12'd3736;
                202: O_LUT_2_6_data = 12'd3743;
                203: O_LUT_2_6_data = 12'd3750;
                204: O_LUT_2_6_data = 12'd3757;
                205: O_LUT_2_6_data = 12'd3764;
                206: O_LUT_2_6_data = 12'd3771;
                207: O_LUT_2_6_data = 12'd3778;
                208: O_LUT_2_6_data = 12'd3785;
                209: O_LUT_2_6_data = 12'd3792;
                210: O_LUT_2_6_data = 12'd3799;
                211: O_LUT_2_6_data = 12'd3806;
                212: O_LUT_2_6_data = 12'd3813;
                213: O_LUT_2_6_data = 12'd3820;
                214: O_LUT_2_6_data = 12'd3827;
                215: O_LUT_2_6_data = 12'd3833;
                216: O_LUT_2_6_data = 12'd3840;
                217: O_LUT_2_6_data = 12'd3847;
                218: O_LUT_2_6_data = 12'd3854;
                219: O_LUT_2_6_data = 12'd3861;
                220: O_LUT_2_6_data = 12'd3867;
                221: O_LUT_2_6_data = 12'd3874;
                222: O_LUT_2_6_data = 12'd3881;
                223: O_LUT_2_6_data = 12'd3887;
                224: O_LUT_2_6_data = 12'd3894;
                225: O_LUT_2_6_data = 12'd3901;
                226: O_LUT_2_6_data = 12'd3907;
                227: O_LUT_2_6_data = 12'd3914;
                228: O_LUT_2_6_data = 12'd3921;
                229: O_LUT_2_6_data = 12'd3927;
                230: O_LUT_2_6_data = 12'd3934;
                231: O_LUT_2_6_data = 12'd3940;
                232: O_LUT_2_6_data = 12'd3947;
                233: O_LUT_2_6_data = 12'd3953;
                234: O_LUT_2_6_data = 12'd3960;
                235: O_LUT_2_6_data = 12'd3966;
                236: O_LUT_2_6_data = 12'd3973;
                237: O_LUT_2_6_data = 12'd3979;
                238: O_LUT_2_6_data = 12'd3986;
                239: O_LUT_2_6_data = 12'd3992;
                240: O_LUT_2_6_data = 12'd3998;
                241: O_LUT_2_6_data = 12'd4005;
                242: O_LUT_2_6_data = 12'd4011;
                243: O_LUT_2_6_data = 12'd4018;
                244: O_LUT_2_6_data = 12'd4024;
                245: O_LUT_2_6_data = 12'd4030;
                246: O_LUT_2_6_data = 12'd4036;
                247: O_LUT_2_6_data = 12'd4043;
                248: O_LUT_2_6_data = 12'd4049;
                249: O_LUT_2_6_data = 12'd4055;
                250: O_LUT_2_6_data = 12'd4061;
                251: O_LUT_2_6_data = 12'd4068;
                252: O_LUT_2_6_data = 12'd4074;
                253: O_LUT_2_6_data = 12'd4080;
                254: O_LUT_2_6_data = 12'd4086;
                255: O_LUT_2_6_data = 12'd4092;
            default: O_LUT_2_6_data = 12'd4092;
        endcase
    end




endmodule

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
/*********legacy_ui_image_cut ********************************************
--版本号1.0  
*****************************************************************/

module legacy_ui_image_cut  #(   
    parameter [12:0] IMG_WIDTH  		= 640,
    parameter [12:0] IMG_HEIGHT 		= 480,
    parameter 	     DATA_WIDTH 		= 96,
	parameter	     SKIP_ROWS_top 		= 2, 
	parameter	     SKIP_ROWS_bottom 	= 2,
    parameter        SKIP_COLS_left  	= 2,
    parameter        SKIP_COLS_right 	= 2
) 
(
    input                       I_clk  ,
    input                       I_rst_n,

    input                       I_tlast  ,
    input                       I_tuser  ,
    input [DATA_WIDTH-1:0]      I_tdata  ,
    input                       I_tvalid , 
    output                      I_tready ,

    output                      O_tlast  ,
    output                      O_tuser  ,
    output reg [DATA_WIDTH-1:0] O_tdata  ,
    output                      O_tvalid ,
    input                       O_tready
);
reg 	[13:0]        h_cnt , v_cnt ; 

reg  [DATA_WIDTH-1:0] I_tdata_r;
reg                   I_tlast_r0 ,I_tuser_r0,I_tvalid_r0;
reg                   I_tlast_r1 ,I_tuser_r1,I_tvalid_r1;

localparam IMG_WIDTH_4x = (IMG_WIDTH >> 2);

wire  w_skip = (v_cnt < SKIP_ROWS_top) ||(h_cnt < SKIP_COLS_left) || (v_cnt >= IMG_HEIGHT - SKIP_ROWS_bottom) || (h_cnt >= IMG_WIDTH_4x - SKIP_COLS_right); 

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n ) begin
            O_tdata <= 0;
        end
        else begin
            O_tdata <= w_skip ? {DATA_WIDTH{1'b0}} : I_tdata_r; 
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n || I_tuser) begin
            h_cnt <= 0;
            v_cnt <= 0;
        end
        else begin
            h_cnt <= I_tvalid_r0 ? ((h_cnt == IMG_WIDTH_4x-1) ? 0 : h_cnt + 1) : h_cnt;
            v_cnt <= I_tvalid_r0 &&(h_cnt == IMG_WIDTH_4x-1) ? ((v_cnt == IMG_HEIGHT - 1) ? 0 : v_cnt + 1) : v_cnt;
        end
    end


    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n ) begin
            {I_tlast_r0 ,I_tlast_r1 } <= 0;
            {I_tuser_r0 ,I_tuser_r1 } <= 0;
            {I_tvalid_r0,I_tvalid_r1} <= 0;
            I_tdata_r  <= 0;
        end
        else begin
            I_tlast_r0  <= I_tlast ; 
            I_tuser_r0  <= I_tuser ;
            I_tvalid_r0 <= I_tvalid;
            I_tlast_r1  <= I_tlast_r0 ;
            I_tuser_r1  <= I_tuser_r0 ;
            I_tvalid_r1 <= I_tvalid_r0;
            I_tdata_r   <= I_tdata ;
        end
    end


    assign  O_tlast  = I_tlast_r1 ;   
    assign  O_tuser  = I_tuser_r1 ;   
    assign  O_tvalid = I_tvalid_r1;

    assign  I_tready = O_tready;

endmodule


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
/*********legacy_ui_isp_top ********************************************
--米联客ISP图像算法包含有黑电平矫正(BLC),去噪(Denoising),去马赛克(Demosaicing),白平衡(wab),
伽马矫正(Gamma),对比度调节(Contrast),亮度调节(Brightness),饱和度调节(Saturation)锐化(Sharpening)
--版本号1.0  
*****************************************************************/
module legacy_ui_isp_top (
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
    output 			I_tready
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


legacy_ui_BLC #(
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

legacy_ui_top_demosaic #(
    .IMG_HEIGHT          (1080			),  // 图像高度
    .IMG_WIDTH           (1920			),   // 图像宽度
    .data_complete_delay (50  			),
    .BAYER_MODE          ("RGGB"		)
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
    .O_tready   	(m_aixs_tready		)   // 输出数据准备好信号
);

legacy_ui_data128_96 X_ui_data128_96(
    .I_tdata		(m_aixs_tdata		),
    .O_tdata		(m_aixs_tdata_96	)
);

legacy_ui_awb #(
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

legacy_ui_image_cut #(
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

legacy_ui_gamma #(
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

legacy_ui_Contrast_adj #(
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

legacy_ui_Brightness_adj #(
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

legacy_ui_data96_128 X_ui_data96_128 (
    .I_tdata		(Brightness_O_tdata),
    .O_tdata		(Color_O_tdata_128)
);
	
endmodule


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
/*********legacy_ui_Saturation_adj ********************************************
--饱和度调节(Saturation)
    
    Y = 0.2989*R + 0.5870*G + 0.1140*B;
    R_new = -Y * value + R * (1+value);
    G_new = -Y * value + G * (1+value);
    B_new = -Y * value + B * (1+value);
    value = (-1~1) 
--版本号1.0  
*****************************************************************/


module legacy_ui_Saturation_adj#(
parameter [8:0]  ADJUST_VAL = 128, // 饱和度调节参数，9位，默认值为128
parameter        GRAYSCALE_ENABLE = 0
)  
(
    input                   I_clk    ,    // 输入时钟信号
    input                   I_rst_n  ,    // 输入复位信号，低电平有效

    input                   I_tlast  ,  // 行结束信号
    input                   I_tuser  ,  // 帧开始信号
    input [95:0]            I_tdata  ,  // 输入数据，总共包含4个像素的RGB值，每个像素24位，4*24=96位
    input                   I_tvalid ,  // 输入数据有效信号
    output                  I_tready ,  // 输入数据准备好信号

    output                  O_tlast  ,  // 输出行结束信号
    output                  O_tuser  ,  // 输出帧开始信号
    output [95:0]           O_tdata  ,  // 输出数据
    output                  O_tvalid ,  // 输出数据有效信号
    input                   O_tready    // 输出数据准备好信号
);

/*****************************************************************
                        将输入的96位数据切分为4个24位的像素，以便后续处理                                        
*****************************************************************/
    wire [23:0] I_tdata_r1 = I_tdata[23:0] ;    // 第1个像素数据
    wire [23:0] I_tdata_r2 = I_tdata[47:24];    // 第2个像素数据
    wire [23:0] I_tdata_r3 = I_tdata[71:48];    // 第3个像素数据
    wire [23:0] I_tdata_r4 = I_tdata[95:72];    // 第4个像素数据

    // 定义RGB888格式的数组，存储每个像素的R、G、B分量
    wire [7:0]  rgb888_r[3:0];
    wire [7:0]  rgb888_g[3:0];
    wire [7:0]  rgb888_b[3:0];

    // 从每个像素中提取R、G、B分量，注意位宽和位置
    assign   rgb888_r[0] = I_tdata_r1[16+:8];   // 第1个像素的R分量
    assign   rgb888_g[0] = I_tdata_r1[8+:8] ;   // 第1个像素的G分量
    assign   rgb888_b[0] = I_tdata_r1[0+:8] ;   // 第1个像素的B分量

    assign   rgb888_r[1] = I_tdata_r2[16+:8];   // 第2个像素的R分量
    assign   rgb888_g[1] = I_tdata_r2[8+:8] ;   // 第2个像素的G分量
    assign   rgb888_b[1] = I_tdata_r2[0+:8] ;   // 第2个像素的B分量

    assign   rgb888_r[2] = I_tdata_r3[16+:8];   // 第3个像素的R分量
    assign   rgb888_g[2] = I_tdata_r3[8+:8] ;   // 第3个像素的G分量
    assign   rgb888_b[2] = I_tdata_r3[0+:8] ;   // 第3个像素的B分量

    assign   rgb888_r[3] = I_tdata_r4[16+:8];   // 第4个像素的R分量
    assign   rgb888_g[3] = I_tdata_r4[8+:8] ;   // 第4个像素的G分量
    assign   rgb888_b[3] = I_tdata_r4[0+:8] ;   // 第4个像素的B分量

/*****************************************************************
                        信号声明部分                                         
*****************************************************************/
    // 定义调整值数组，每个像素一个调整值
    wire [8:0]   adjust_val[3:0];

    // 将参数ADJUST_VAL赋值给每个像素的调整值
    assign adjust_val[0] = ADJUST_VAL;
    assign adjust_val[1] = ADJUST_VAL;
    assign adjust_val[2] = ADJUST_VAL;
    assign adjust_val[3] = ADJUST_VAL;
    
    // 定义用于同步的寄存器，延迟输入的控制信号
    reg  [3:0]   I_tlast_r ;
    reg  [3:0]   I_tuser_r ;
    reg  [3:0]   I_tvalid_r;

    // 定义用于计算亮度Y的中间变量
    reg  [16:0]  Y_R_m[3:0];
    reg  [17:0]  Y_G_m[3:0];
    reg  [14:0]  Y_B_m[3:0];

    // 定义用于存储第一级流水线的RGB值
    reg  [7:0]   rgb888_r_r0[3:0];
    reg  [7:0]   rgb888_g_r0[3:0];
    reg  [7:0]   rgb888_b_r0[3:0];
    reg  [8:0]   RGB_C[3:0];
    
    // 定义Y的计算结果
    wire [17:0]  Y_w[3:0];
    reg  [7:0]   Y[3:0];

    // 定义用于存储第二级流水线的RGB值
    reg  [7:0]   rgb888_r_r1[3:0];
    reg  [7:0]   rgb888_g_r1[3:0];
    reg  [7:0]   rgb888_b_r1[3:0];

    // 定义Y_C的符号位和绝对值，用于判断调整值的正负
    reg          Y_C_sign[3:0];
    reg  [7:0]   Y_C_abs[3:0];

    // 定义用于存储第三级流水线的中间结果
    reg  [16:0]   Y_m[3:0];
    reg  [7:0]    Y_r2[3:0];

    reg  [16:0]   rgb888_r_r2[3:0];
    reg  [16:0]   rgb888_g_r2[3:0];
    reg  [16:0]   rgb888_b_r2[3:0];

    // 定义Y_m_s等用于符号扩展的变量
    wire [18:0] Y_m_s[3:0];
    wire [18:0] Y_R_m_s[3:0];
    wire [18:0] Y_G_m_s[3:0];
    wire [18:0] Y_B_m_s[3:0];

    // 定义最终新的RGB值
    reg  [7:0]  R_new[3:0];
    reg  [7:0]  G_new[3:0];
    reg  [7:0]  B_new[3:0];
    

    // 定义用于亮度计算的常数系数
    localparam C0 = 9'd306;  // 0.299*1024，用于R分量
    localparam C1 = 10'd601; // 0.587*1024，用于G分量
    localparam C2 = 7'd117;  // 0.114*1024，用于B分量

/*****************************************************************
                    计算部分，实现饱和度调整                                         
*****************************************************************/

    genvar i;
    generate
        for(i = 0; i < 4; i = i + 1)
        begin: computing
        // 第一级流水线，计算Y的各部分并保存RGB值
        // Y=0.299*R+0.587*G+0.114*B
        always @(posedge I_clk or negedge I_rst_n) begin
            if(!I_rst_n) begin
                {Y_R_m[i], Y_G_m[i], Y_B_m[i]} <= 0;
                {rgb888_r_r0[i], rgb888_g_r0[i], rgb888_b_r0[i]} <= 0;
                RGB_C[i] <= 0;
            end 
            else if(I_tvalid)begin
                Y_R_m[i] <= rgb888_r[i]*C0; // R分量乘以系数C0
                Y_G_m[i] <= rgb888_g[i]*C1; // G分量乘以系数C1
                Y_B_m[i] <= rgb888_b[i]*C2; // B分量乘以系数C2
                {rgb888_r_r0[i], rgb888_g_r0[i], rgb888_b_r0[i]} <= {rgb888_r[i], rgb888_g[i], rgb888_b[i]};
                RGB_C[i] <= 255 + adjust_val[i]; // 计算RGB_C，用于后续计算
            end
        end
        // 将Y_R_m、Y_G_m、Y_B_m相加，得到Y_w
        assign Y_w[i] = Y_R_m[i] + Y_G_m[i] + Y_B_m[i];
    
        // 第二级流水线，对Y进行截取，并同步RGB值和调整值的符号与绝对值
        always @(posedge I_clk or negedge I_rst_n) begin
            if(!I_rst_n) begin
                Y[i] <= 0;
                {rgb888_r_r1[i], rgb888_g_r1[i], rgb888_b_r1[i]} <= 0;
                {Y_C_sign[i], Y_C_abs[i]} <= 0;
            end 
            else if(I_tvalid_r[0])begin
                Y[i] <= Y_w[i][17:10]; // 截取Y_w的高位，得到Y
                {rgb888_r_r1[i], rgb888_g_r1[i], rgb888_b_r1[i]} <= {rgb888_r_r0[i], rgb888_g_r0[i], rgb888_b_r0[i]};
                Y_C_sign[i] <= adjust_val[i][8]; // 判断调整值的符号位，最高位为符号
                Y_C_abs[i] <= adjust_val[i][8] ? (~adjust_val[i][7:0] + 1) : adjust_val[i];// 如果为负数，取补码+1，否则直接取值
            end
        end   
    
        // 第三级流水线，计算Y_m和RGB的中间值
        always @(posedge I_clk or negedge I_rst_n) begin
            if(!I_rst_n) begin
                Y_m[i] <= 0;
                Y_r2[i] <= 0;
                {rgb888_r_r2[i], rgb888_g_r2[i], rgb888_b_r2[i]} <= 0;
            end 
            else if(I_tvalid_r[1])begin
                Y_m[i] <= Y[i]*Y_C_abs[i]; // Y乘以调整值的绝对值
                Y_r2[i] <= Y[i];
                rgb888_r_r2[i] <= rgb888_r_r1[i]*RGB_C[i]; // R分量乘以RGB_C
                rgb888_g_r2[i] <= rgb888_g_r1[i]*RGB_C[i]; // G分量乘以RGB_C
                rgb888_b_r2[i] <= rgb888_b_r1[i]*RGB_C[i]; // B分量乘以RGB_C
            end
        end
        
        // 根据调整值的符号位，对Y_m取反或保持不变
        assign Y_m_s[i] = (~Y_C_sign[i]) ? (~{2'b0, Y_m[i]} + 1) : {2'b0, Y_m[i]};
    
        // 计算新的RGB分量
        assign Y_R_m_s[i] = Y_m_s[i] + rgb888_r_r2[i];
        assign Y_G_m_s[i] = Y_m_s[i] + rgb888_g_r2[i];
        assign Y_B_m_s[i] = Y_m_s[i] + rgb888_b_r2[i];
    
        // 第四级流水线，对计算结果进行饱和处理，防止溢出，并得到最终的RGB值
        always @(posedge I_clk or negedge I_rst_n) begin
            if(!I_rst_n) begin
                {R_new[i], G_new[i], B_new[i]} <= 0;
            end 
            else if(I_tvalid_r[2])begin
                if(GRAYSCALE_ENABLE) begin
                    R_new[i] <= Y_r2[i];
                    G_new[i] <= Y_r2[i];
                    B_new[i] <= Y_r2[i];
                end
                else begin
                    // 判断结果是否为负数或溢出，进行裁剪
                    R_new[i] <= Y_R_m_s[i][18] ? 0 : Y_R_m_s[i][17:16] > 0 ? 255 : Y_R_m_s[i][15:8];
                    G_new[i] <= Y_G_m_s[i][18] ? 0 : Y_G_m_s[i][17:16] > 0 ? 255 : Y_G_m_s[i][15:8];
                    B_new[i] <= Y_B_m_s[i][18] ? 0 : Y_B_m_s[i][17:16] > 0 ? 255 : Y_B_m_s[i][15:8];
                end
            end
        end       
        end
    endgenerate
    
/*****************************************************************
                    同步输入的控制信号，使数据和控制信号对齐                                         
*****************************************************************/

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) 
            {I_tlast_r,I_tuser_r,I_tvalid_r} <= 0;
        else begin
            I_tlast_r <= {I_tlast_r[2:0],I_tlast};    // 同步I_tlast信号
            I_tuser_r <= {I_tuser_r[2:0],I_tuser};    // 同步I_tuser信号
            I_tvalid_r <= {I_tvalid_r[2:0],I_tvalid}; // 同步I_tvalid信号
        end
    end

    // 输出同步的控制信号
    assign  O_tlast  = I_tlast_r[3];   
    assign  O_tuser  = I_tuser_r[3];   
    assign  O_tvalid = I_tvalid_r[3];

    // 将新的RGB值组合成输出数据
    assign  O_tdata = {R_new[3],G_new[3],B_new[3],
                       R_new[2],G_new[2],B_new[2],
                       R_new[1],G_new[1],B_new[1],
                       R_new[0],G_new[0],B_new[0]};
    // 如果需要将RGB888转换为RGB565，可以使用以下代码进行转换
    // assign O_st_data = {R_new[7-:5],G_new[7-:6],B_new[7-:5]};
    // 输入就绪信号直接连接输出就绪信号
    assign  I_tready = O_tready;

endmodule


/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
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
/*********legacy_ui_image_correction 消减图像的多余的***********
--版本号1.0  
*****************************************************************/

module legacy_ui_image_correction #(
    parameter DATA_WIDTH   = 40,
    parameter TDEST_WIDTH  = 10
)(
    input                          		I_clk   			,
    input                          		I_rst_n 			,

    input    [DATA_WIDTH - 1:0]       	I_raw_data			,       
    input                             	I_raw_valid 		,     
    input                             	I_raw_frame_start	,
    input                             	I_raw_frame_end  	,
    // 输出RAW10数据	
    output     [DATA_WIDTH - 1:0]     	O_raw_tdata 		,
    output                            	O_raw_tlast 		,
    output reg [TDEST_WIDTH - 1:0]    	O_raw_tdest 		,
    output                            	O_raw_tvalid		,
    output                            	O_raw_tuser 		,
    input                             	O_raw_tready
);

    reg                        I_raw_tvalid_d; 
    reg    [DATA_WIDTH - 1:0]  I_raw_tdata_r;
    reg    [14:0]              h_cnt,v_cnt;
    wire                       V_valid,H_valid;
    wire                       tuser;
	
	assign H_valid 		= (h_cnt < 481) && (h_cnt > 0);
    
    assign tuser 		= (h_cnt == 1) && (v_cnt == 1) && I_raw_tvalid_d;
    
    assign O_raw_tdata  = V_valid && H_valid? I_raw_tdata_r:0;
    assign I_raw_tready = O_raw_tready;
    assign O_raw_tvalid = H_valid && V_valid && I_raw_tvalid_d;
    assign O_raw_tlast  = V_valid && (h_cnt == 480) && I_raw_tvalid_d;
    assign O_raw_tuser  = tuser;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n )begin
            I_raw_tvalid_d <= 0;
            I_raw_tdata_r  <= 0;
        end
        else begin
            I_raw_tvalid_d <= I_raw_valid;
            I_raw_tdata_r  <= I_raw_data;
        end
    end
    
    reg  [16:0] cnt;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n )begin
            cnt <= 0;
        end
        else if(I_raw_valid)
            cnt <= 0;
        else if(!I_raw_valid)begin
            cnt <= cnt + 1;
        end
    end

    wire last = (cnt == 10);
    // 计算行数
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n || I_raw_frame_start)
            v_cnt <= 0;
        else if(last)
            v_cnt  <=  v_cnt + 1;
    end

    assign V_valid = (v_cnt > 0) && (v_cnt < 1081);

    // 计算每行像素个数
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n || I_raw_frame_start) 
            h_cnt <= 0;
        else if(last)
            h_cnt <= 0;
        else if(I_raw_tvalid_d)
            h_cnt <=  h_cnt + 1;
    end


//    cwc2 cwc2_inst
//  (
//  .probe0  (v_cnt       ),
//  .probe1  (h_cnt      ),
//  .probe2  (tuser  ),
//  .probe3  (cnt    ),
//  .probe4  (O_raw_tlast        ),
//  .probe5  (O_raw_tvalid         ),
//  .probe6  (O_raw_tdata ),
//  .clk(I_clk)
//  );
endmodule