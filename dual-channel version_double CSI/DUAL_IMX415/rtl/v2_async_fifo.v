`timescale 1ns/1ps
// Single producer/consumer. Storage has a synchronous read port so TD can
// infer ERAM. The output register owns a popped entry during backpressure.
module v2_async_fifo #(parameter WIDTH=128, parameter ADDR=9, parameter READ_INCREMENT_LOOKAHEAD=0, parameter READ_REFILL_ON_POP=1, parameter WRITE_INCREMENT_LOOKAHEAD=0)(
    input wire rst_n, input wire wclk, input wire [WIDTH-1:0] s_data,
    input wire s_valid, output wire s_ready,
    input wire rclk, output reg [WIDTH-1:0] m_data,
    output reg m_valid, input wire m_ready,
    output wire [ADDR:0] m_level,
    output wire [ADDR:0] s_level
);
    reg [WIDTH-1:0] mem [0:(1<<ADDR)-1];
    reg [ADDR:0] wp,wg,rp,rg;
    (* ASYNC_REG="TRUE" *) reg [ADDR:0] rg1,rg2,wg1,wg2;
    (* ASYNC_REG="TRUE" *) reg [1:0] wrst,rrst;
    wire push=s_valid && s_ready;
    // Optional isolation for consumers slower than one word per two clocks:
    // no same-cycle refill means downstream ready cannot reach ERAM enable.
    wire pop=(!m_valid || (READ_REFILL_ON_POP && m_ready)) && (rg!=wg2) && rrst[1];
    wire [ADDR:0] wn;
    generate if(WRITE_INCREMENT_LOOKAHEAD) begin:g_write_increment
        reg [ADDR:0] wp_next;
        always @(posedge wclk or negedge wrst[1]) begin
            if(!wrst[1]) wp_next<=1;
            else if(push) wp_next<=wp_next+1'b1;
        end
        assign wn=push ? wp_next : wp;
    end else begin:g_write_increment_default
        assign wn=wp+push;
    end endgenerate
    wire [ADDR:0] rn;
    generate if(READ_INCREMENT_LOOKAHEAD) begin:g_read_increment
        // Keep a one-ahead pointer so pop does not drive the carry chain.
        reg [ADDR:0] rp_next;
        always @(posedge rclk or negedge rrst[1]) begin
            if(!rrst[1]) rp_next<=1;
            else if(pop) rp_next<=rp_next+1'b1;
        end
        assign rn=pop ? rp_next : rp;
    end else begin:g_read_increment_default
        assign rn=rp+pop;
    end endgenerate
    wire [ADDR:0] wgn=(wn>>1)^wn, rgn=(rn>>1)^rn;
    reg full;
    function [ADDR:0] from_gray(input [ADDR:0] value);
        integer n;
        begin
            from_gray[ADDR]=value[ADDR];
            for(n=ADDR-1;n>=0;n=n-1) from_gray[n]=from_gray[n+1]^value[n];
        end
    endfunction
    // Reader-domain estimate from synchronized Gray write pointer, including
    // the prefetched output entry. Never synchronize a binary occupancy bus.
    assign m_level=(from_gray(wg2)-rp)+m_valid;
    // Conservative writer-domain occupancy, including synchronization lag.
    assign s_level=wp-from_gray(rg2);
    assign s_ready=wrst[1] && !full;
    always @(posedge wclk or negedge rst_n)
        if(!rst_n) wrst<=0; else wrst<={wrst[0],1'b1};
    always @(posedge rclk or negedge rst_n)
        if(!rst_n) rrst<=0; else rrst<={rrst[0],1'b1};
    always @(posedge wclk or negedge wrst[1]) begin
        if(!wrst[1]) begin wp<=0;wg<=0;rg1<=0;rg2<=0;full<=0;end
        else begin
            rg1<=rg;rg2<=rg1;wp<=wn;wg<=wgn;
            full<=wgn=={~rg2[ADDR:ADDR-1],rg2[ADDR-2:0]};
        end
    end
    always @(posedge wclk) if(push) mem[wp[ADDR-1:0]]<=s_data;
    always @(posedge rclk or negedge rrst[1]) begin
        if(!rrst[1]) begin rp<=0;rg<=0;wg1<=0;wg2<=0;m_valid<=0;end
        else begin
            wg1<=wg;wg2<=wg1;rp<=rn;rg<=rgn;
            if(!m_valid || m_ready) m_valid<=pop;
        end
    end
    always @(posedge rclk) if(pop) m_data<=mem[rp[ADDR-1:0]];
endmodule
