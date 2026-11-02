`timescale 1ns/1ps

// Shared replicated-border K3 window with registered ERAM cascade writes.
// Gaussian horizontal and vertical sums occupy separate pipeline stages.
module gray_gauss4 #(
    parameter integer WIDTH=1920,HEIGHT=1080
)(
    input wire clk,rst_n,
    input wire [31:0] s_gray,
    input wire s_valid,s_sof,s_eol,
    output reg [31:0] m_center,m_gauss,
    output reg [287:0] m_window,
    output reg m_valid,m_sof,m_eol,
    output wire m_overrun
);
    wire [287:0] window;
    wire wv,ws,we;
    gray_window4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.K(3)) u_lines (
        .clk(clk),.rst_n(rst_n),.s_data(s_gray),.s_valid(s_valid),
        .s_sof(s_sof),.s_eol(s_eol),.m_window(window),
        .m_valid(wv),.m_sof(ws),.m_eol(we),.fault(m_overrun));
    reg [287:0] window0;
    reg v0,s0,e0;
    always @(posedge clk) begin
        if(wv) window0<=window;
        m_window<=window0;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin v0<=0;s0<=0;e0<=0;m_valid<=0;m_sof<=0;m_eol<=0;end
        else begin
            v0<=wv;s0<=ws;e0<=we;
            m_valid<=v0;m_sof<=s0;m_eol<=e0;
        end
    end
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1) begin:g_lane
        wire [71:0] p=window[lane*72+:72];
        reg [9:0] row0,row1,row2;
        reg [7:0] center0;
        wire [11:0] total={2'd0,row0}+{1'd0,row1,1'b0}+{2'd0,row2}+12'd8;
        always @(posedge clk) begin
            if(wv) begin
                row0<={2'd0,p[7:0]}+{1'd0,p[15:8],1'b0}+{2'd0,p[23:16]};
                row1<={2'd0,p[31:24]}+{1'd0,p[39:32],1'b0}+{2'd0,p[47:40]};
                row2<={2'd0,p[55:48]}+{1'd0,p[63:56],1'b0}+{2'd0,p[71:64]};
                center0<=p[39:32];
            end
            m_center[lane*8+:8]<=center0;
            m_gauss[lane*8+:8]<=total[11:4];
        end
    end endgenerate
endmodule
