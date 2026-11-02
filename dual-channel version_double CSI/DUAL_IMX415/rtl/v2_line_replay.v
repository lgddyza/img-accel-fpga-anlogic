`timescale 1ns/1ps
// V1 ISP expects complete, contiguous active lines. DDR AXI may pause inside
// a row: collect a whole row in ping-pong storage before presenting it to ISP.
// Four-pixel input average must be <= half the processing clock frequency.
module v2_line_replay #(parameter WIDTH=1920, BACKPRESSURE=0, MIN_LINE_GAP=0)(
    input wire clk,rst_n,input wire [39:0] s_data,
    input wire s_valid,s_sof,s_eol,
    output reg [39:0] m_data,output reg m_valid,m_sof,m_eol,
    output reg fault,
    output wire s_ready,input wire m_start_ready,
    output wire line_started,output wire line_waiting
);
    localparam BEATS=WIDTH/4,XB=$clog2(BEATS);
    reg [39:0] memory[0:(1<<(XB+1))-1];
    reg [XB-1:0] wx,rx;
    reg wb,rb,reading;
    localparam GAP_BITS=MIN_LINE_GAP>0 ? $clog2(MIN_LINE_GAP+1) : 1;
    reg [GAP_BITS-1:0] gap_left;
    reg [1:0] ready,line_sof;
    wire write_bank=s_sof ? 1'b0 : wb;
    wire [XB-1:0] write_x=s_sof ? {XB{1'b0}} : wx;
    wire collision=ready[write_bank] || (reading && rb==write_bank);
    // Ready must not depend on s_sof: the producer may gate its transfer
    // pulse with ready. Even-height frames naturally return wb to bank 0.
    assign s_ready=rst_n && !fault && !ready[wb] && !(reading && rb==wb);
    assign line_waiting=!reading && ready[rb] && !fault && gap_left==0;
    assign line_started=line_waiting && (!BACKPRESSURE || m_start_ready);
    always @(posedge clk) begin
        if(s_valid && !fault && !collision) memory[{write_bank,write_x}]<=s_data;
        if(reading && !fault) m_data<=memory[{rb,rx}];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wx<=0;rx<=0;wb<=0;rb<=0;reading<=0;ready<=0;line_sof<=0;
            gap_left<=0;
            m_valid<=0;m_sof<=0;m_eol<=0;fault<=0;
        end else begin
            if(gap_left!=0) gap_left<=gap_left-1'b1;
            m_valid<=reading && !fault;
            m_sof<=reading && !fault && rx==0 && line_sof[rb];
            m_eol<=reading && !fault && rx==BEATS-1;
            if(s_valid && !fault) begin
                if(collision || s_eol!=(write_x==BEATS-1)) fault<=1;
                else begin
                    if(write_x==0) line_sof[write_bank]<=s_sof;
                    if(s_eol) begin ready[write_bank]<=1;wb<=~write_bank;wx<=0;end
                    else begin wx<=write_x+1'b1;wb<=write_bank;end
                end
            end
            if(reading) begin
                if(rx==BEATS-1) begin
                    reading<=0;rx<=0;rb<=~rb;gap_left<=MIN_LINE_GAP;
                end
                else rx<=rx+1'b1;
            end else if(line_started) begin
                ready[rb]<=0;reading<=1;rx<=0;
            end
        end
    end
endmodule

// Reserve a destination row before the non-elastic legacy ISP starts it.
// A reservation is retired only when its corresponding output group exists.
module v2_isp_row_credit #(
    parameter WIDTH=1920,HEIGHT=1080,FIFO_GROUPS=2048,
    parameter FORMAT_FLIGHT=8
)(
    input wire clk,rst_n,line_started,
    input wire processed_valid,processed_sof,processed_eol,
    input wire [35:0] queued_groups,
    output wire line_ready,output reg fault,
    output wire [35:0] reserved_groups,output wire [35:0] peak_groups
);
    localparam BEATS=WIDTH/4;
    reg [11:0] pending[0:2],peak[0:2];
    reg [1:0] input_lane,output_lane;
    reg [2:0] input_row,output_row;
    reg [10:0] output_x,output_y,input_y;
    wire [1:0] out_lane=processed_sof ? 2'd0 : output_lane;
    wire [10:0] out_x=processed_sof ? 11'd0 : output_x;
    // Break FIFO pointer -> occupancy -> row reservation timing. A lane can
    // enqueue at most one group in the one-cycle observation delay, hence
    // reserve one additional group when making the admission decision.
    reg [35:0] queued_q;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) queued_q<=0; else queued_q<=queued_groups;
    wire [12:0] input_used={1'b0,queued_q[input_lane*12+:12]}+pending[input_lane];
    assign line_ready=rst_n && !fault && input_used+BEATS+FORMAT_FLIGHT+1<=FIFO_GROUPS;
    genvar lane;
    generate for(lane=0;lane<3;lane=lane+1) begin:g_credit
        wire reserve_row=line_started && input_lane==lane;
        wire retire_group=processed_valid && out_lane==lane;
        wire [12:0] used={1'b0,queued_groups[lane*12+:12]}+pending[lane];
        assign reserved_groups[lane*12+:12]=pending[lane];
        assign peak_groups[lane*12+:12]=peak[lane];
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin pending[lane]<=0;peak[lane]<=0;end
            else if(!fault) begin
                case({reserve_row,retire_group})
                    2'b10: pending[lane]<=pending[lane]+BEATS;
                    2'b01: if(pending[lane]!=0) pending[lane]<=pending[lane]-1'b1;
                    2'b11: pending[lane]<=pending[lane]+BEATS-1;
                endcase
                if(used>peak[lane]) peak[lane]<=used[11:0];
            end
        end
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            input_lane<=0;output_lane<=0;input_row<=0;output_row<=0;
            input_y<=0;output_y<=0;output_x<=0;fault<=0;
        end else if(!fault) begin
            if(line_started) begin
                if(!line_ready) fault<=1;
                if(input_y==HEIGHT-1) begin input_y<=0;input_lane<=0;input_row<=0;end
                else begin
                    input_y<=input_y+1'b1;input_row<=input_row+1'b1;
                    if(input_row==7) input_lane<=input_lane==2 ? 0 : input_lane+1'b1;
                end
            end
            if(processed_valid) begin
                if((pending[out_lane]==0 && !(line_started && input_lane==out_lane)) ||
                   processed_eol!=(out_x==BEATS-1) ||
                   processed_sof!=(output_x==0 && output_y==0)) fault<=1;
                if(processed_eol) begin
                    output_x<=0;
                    if(output_y==HEIGHT-1) begin output_y<=0;output_lane<=0;output_row<=0;end
                    else begin
                        output_y<=output_y+1'b1;output_row<=output_row+1'b1;
                        if(output_row==7) output_lane<=output_lane==2 ? 0 : output_lane+1'b1;
                    end
                end else output_x<=out_x+1'b1;
            end
        end
    end
endmodule
