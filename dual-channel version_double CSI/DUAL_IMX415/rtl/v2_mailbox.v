`timescale 1ns/1ps
// Bundled data is held from request until destination acknowledgement returns.
// Destination waits an extra clock after synchronized request detection.
module v2_mailbox #(parameter WIDTH=64)(
    input wire rst_n, input wire s_clk, input wire [WIDTH-1:0] s_data,
    input wire s_valid, output wire s_ready,
    input wire m_clk, output reg [WIDTH-1:0] m_data,
    output reg m_valid, input wire m_ready
);
    wire s_rst_n,m_rst_n;
    v2_reset_sync u_s_reset(s_clk,rst_n,s_rst_n);
    v2_reset_sync u_m_reset(m_clk,rst_n,m_rst_n);
    reg [WIDTH-1:0] hold_data;
    reg req,ack,settle;
    (* ASYNC_REG="TRUE" *) reg [1:0] req_sync,ack_sync;
    assign s_ready=s_rst_n && req==ack_sync[1];
    always @(posedge s_clk or negedge s_rst_n) begin
        if(!s_rst_n) begin req<=0;hold_data<=0;ack_sync<=0;end
        else begin
            ack_sync<={ack_sync[0],ack};
            if(s_valid && s_ready) begin hold_data<=s_data;req<=~req;end
        end
    end
    always @(posedge m_clk or negedge m_rst_n) begin
        if(!m_rst_n) begin req_sync<=0;ack<=0;settle<=0;m_data<=0;m_valid<=0;end
        else begin
            req_sync<={req_sync[0],req};
            if(!m_valid && req_sync[1]!=ack) begin
                if(settle) begin m_data<=hold_data;m_valid<=1;settle<=0;end
                else settle<=1;
            end
            if(m_valid && m_ready) begin m_valid<=0;ack<=req_sync[1];end
        end
    end
endmodule
