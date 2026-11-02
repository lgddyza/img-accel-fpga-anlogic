`timescale 1ns/1ps
// Keep accepted DDR transactions alive across a video-only reset. Discard
// old read responses and finish an aborted write before releasing the pipeline.
module v2_ddr_reset_guard #(parameter ADDR_WIDTH=28)(
    input wire clk,rst_n,run,
    output wire released,output wire [31:0] debug,
    input wire [ADDR_WIDTH-1:0] s_awaddr,input wire [7:0] s_awlen,
    input wire s_awvalid,output wire s_awready,
    input wire [127:0] s_wdata,input wire s_wlast,s_wvalid,output wire s_wready,
    output wire [1:0] s_bresp,output wire s_bvalid,input wire s_bready,
    input wire [ADDR_WIDTH-1:0] s_araddr,input wire [7:0] s_arlen,
    input wire s_arvalid,output wire s_arready,
    output wire [127:0] s_rdata,output wire [1:0] s_rresp,
    output wire s_rlast,s_rvalid,input wire s_rready,
    output reg [ADDR_WIDTH-1:0] m_awaddr,output reg [7:0] m_awlen,
    output wire m_awvalid,input wire m_awready,
    output wire [127:0] m_wdata,output wire m_wlast,m_wvalid,input wire m_wready,
    input wire [1:0] m_bresp,input wire m_bvalid,output wire m_bready,
    output reg [ADDR_WIDTH-1:0] m_araddr,output reg [7:0] m_arlen,
    output wire m_arvalid,input wire m_arready,
    input wire [127:0] m_rdata,input wire [1:0] m_rresp,
    input wire m_rlast,m_rvalid,output wire m_rready
);
    reg write_active,write_address_sent,write_done;
    reg read_pending;
    reg [1:0] read_count,read_sent;
    wire read_active=read_count!=0;
    wire read_address_sent=read_sent!=0;
    reg abort_write,abort_read;
    reg [7:0] write_beat;
    reg [127:0] held_data;
    reg held_valid,held_last;
    reg [15:0] aborted_transactions;
    wire normal=run && !abort_write && !abort_read;
    wire drain_write=abort_write || !run;
    wire drain_read=abort_read || !run;
    assign released=rst_n && normal;
    assign debug={aborted_transactions,write_beat,1'b0,abort_read,abort_write,
                  read_address_sent,read_active,write_done,write_address_sent,write_active};
    assign s_awready=rst_n && normal && !write_active;
    // One elastic AR plus accepted DDR requests, bounded to two total. The
    // guard owns every upstream handshake until its RLAST, including reset.
    assign s_arready=rst_n && normal && !read_pending && read_count<2;
    assign m_awvalid=write_active && !write_address_sent;
    assign m_arvalid=read_pending;
    // Elastic write register preserves an already offered beat under stall,
    // even if run falls. Only subsequent, aborted beats are padded with zero.
    assign m_wdata=held_data;
    assign m_wlast=held_last;
    assign m_wvalid=write_active && write_address_sent && !write_done && held_valid;
    assign s_wready=rst_n && normal && write_active && !write_done &&
                    (!held_valid || (m_wvalid && m_wready && !m_wlast));
    assign s_bresp=m_bresp;
    assign s_bvalid=normal && write_active && write_done && m_bvalid;
    assign m_bready=write_active && write_done && (drain_write || s_bready);
    assign s_rdata=m_rdata;assign s_rresp=m_rresp;assign s_rlast=m_rlast;
    assign s_rvalid=normal && read_active && read_address_sent && m_rvalid;
    assign m_rready=read_active && read_address_sent && (drain_read || s_rready);
    wire write_take=m_wvalid && m_wready;
    wire write_finish=m_bvalid && m_bready;
    wire read_finish=m_rvalid && m_rready && m_rlast;
    wire read_accept=s_arvalid && s_arready;
    wire read_issue=m_arvalid && m_arready;
    wire abort_w_event=!run && write_active && !abort_write;
    wire abort_r_event=!run && read_active && !abort_read;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            write_active<=0;write_address_sent<=0;write_done<=0;
            read_pending<=0;read_count<=0;read_sent<=0;abort_write<=0;abort_read<=0;
            write_beat<=0;held_valid<=0;held_last<=0;held_data<=0;
            m_awaddr<=0;m_awlen<=0;m_araddr<=0;m_arlen<=0;aborted_transactions<=0;
        end else begin
            if(abort_w_event || abort_r_event)
                aborted_transactions<=aborted_transactions+{15'd0,abort_w_event}+{15'd0,abort_r_event};
            if(abort_w_event) abort_write<=1;
            if(abort_r_event) abort_read<=1;
            if(s_awvalid && s_awready) begin
                write_active<=1;write_address_sent<=0;write_done<=0;
                write_beat<=0;held_valid<=0;m_awaddr<=s_awaddr;m_awlen<=s_awlen;
            end
            if(m_awvalid && m_awready) write_address_sent<=1;
            if(read_accept) begin
                read_pending<=1;m_araddr<=s_araddr;m_arlen<=s_arlen;
            end
            if(read_issue) read_pending<=0;
            case({read_accept,read_finish})
                2'b10: read_count<=read_count+1'b1;
                2'b01: read_count<=read_count-1'b1;
            endcase
            case({read_issue,read_finish})
                2'b10: read_sent<=read_sent+1'b1;
                2'b01: read_sent<=read_sent-1'b1;
            endcase
            if(write_take) begin
                held_valid<=0;
                if(m_wlast) write_done<=1;else write_beat<=write_beat+1'b1;
            end
            if(s_wvalid && s_wready) begin
                held_data<=s_wdata;held_last<=s_wlast;held_valid<=1;
            end else if(drain_write && write_active && !write_done &&
                        (!held_valid || write_take) && !(write_take && m_wlast)) begin
                held_data<=0;held_valid<=1;
                held_last<=(write_beat+{7'd0,write_take}==m_awlen);
            end
            if(write_finish) begin
                write_active<=0;write_address_sent<=0;write_done<=0;
                held_valid<=0;abort_write<=0;
            end
            if(read_finish && read_count==1 && !read_accept) abort_read<=0;
        end
    end
endmodule
