`timescale 1ns/1ps
// Match the official HS-only receiver's IMX415 active rectangle: skip 20
// packet lines and the first four pixels, then retain exactly 1920x1080.
// Count explicit packet EOL markers, never infer a line from idle-cycle gaps.
module v2_axis_crop #(parameter WIDTH=1920,HEIGHT=1080,TOP=20,LEFT_BEATS=1)(
    input wire clk,rst_n,input wire [39:0] s_data,
    input wire s_valid,s_sof,s_eol,
    output reg [39:0] m_data,output reg m_valid,m_sof,m_eol,row_odd,
    output reg [31:0] format_errors
);
    reg [12:0] x,y;
    wire [12:0] cx=s_sof ? 13'd0 : x;
    wire [12:0] cy=s_sof ? 13'd0 : y;
    wire active=cy>=TOP && cy<TOP+HEIGHT && cx>=LEFT_BEATS && cx<LEFT_BEATS+WIDTH/4;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x<=0;y<=0;m_data<=0;m_valid<=0;m_sof<=0;m_eol<=0;row_odd<=TOP%2;format_errors<=0;
        end else begin
            m_valid<=0;m_sof<=0;m_eol<=0;
            // The core can assert frame start in a blank cycle.
            if(s_sof) begin x<=0;y<=0;end
            if(s_valid) begin
                if(active) begin
                    m_data<=s_data;m_valid<=1;
                    m_sof<=cy==TOP && cx==LEFT_BEATS;
                    m_eol<=cx==LEFT_BEATS+WIDTH/4-1;
                    if(cy==TOP && cx==LEFT_BEATS) row_odd<=cy[0];
                end
                if(s_eol) begin
                    x<=0;if(cy!=13'h1fff) y<=cy+1'b1;
                    if(cy>=TOP && cy<TOP+HEIGHT && cx<LEFT_BEATS+WIDTH/4-1)
                        format_errors<=format_errors+1'b1;
                end else if(cx!=13'h1fff) x<=cx+1'b1;
            end else if(s_eol) begin
                x<=0;if(cy!=13'h1fff) y<=cy+1'b1;
                if(cy>=TOP && cy<TOP+HEIGHT && cx<LEFT_BEATS+WIDTH/4)
                    format_errors<=format_errors+1'b1;
            end
        end
    end
endmodule
