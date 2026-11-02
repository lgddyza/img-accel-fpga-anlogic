`timescale 1ns/1ps

// Registered-output FIFO, adapted from the PCIe project's axis_stream_fifo.
// fill_level counts memory words; m_tvalid accounts for the extra output word.
module axis_stream_fifo #(
    parameter DATA_WIDTH=128,
    parameter DEPTH=128,
    parameter ADDR_BITS=7,
    parameter DISTRIBUTED_RAM=0
)(
    input wire clk,rst_n,
    input wire [DATA_WIDTH-1:0] s_tdata,
    input wire s_tvalid,s_tlast,
    output wire s_tready,
    output wire [DATA_WIDTH-1:0] m_tdata,
    output wire m_tvalid,m_tlast,
    input wire m_tready,
    output wire [ADDR_BITS:0] fill_level
);
    localparam MEM_WIDTH=DATA_WIDTH+1;
    reg [ADDR_BITS:0] wr_ptr,rd_ptr;
    reg [MEM_WIDTH-1:0] out_reg;
    reg out_valid;
    wire [ADDR_BITS-1:0] wr_addr=wr_ptr[ADDR_BITS-1:0];
    wire [ADDR_BITS-1:0] rd_addr=rd_ptr[ADDR_BITS-1:0];
    wire empty=wr_ptr==rd_ptr;
    wire full=(wr_addr==rd_addr) && (wr_ptr[ADDR_BITS]!=rd_ptr[ADDR_BITS]);
    wire wr_en=s_tvalid && s_tready;
    wire fetch=(!out_valid || m_tready) && !empty;
    wire [MEM_WIDTH-1:0] memory_word;
    assign fill_level=wr_ptr-rd_ptr;
    assign s_tready=!full;
    assign m_tdata=out_reg[DATA_WIDTH-1:0];
    assign m_tlast=out_reg[DATA_WIDTH];
    assign m_tvalid=out_valid;

    generate if(DISTRIBUTED_RAM) begin : g_distributed
        // Port contract checked against TD arch/ph1_macro.v. This small FIFO
        // uses spare LUT RAM instead of ERAM needed by the DSI/camera paths.
        PH1_LOGIC_DRAM #(
            .DATA_WIDTH_W(MEM_WIDTH),.DATA_WIDTH_R(MEM_WIDTH),
            .ADDR_WIDTH_W(ADDR_BITS),.ADDR_WIDTH_R(ADDR_BITS),
            .DATA_DEPTH_W(DEPTH),.DATA_DEPTH_R(DEPTH),.READREG("DISABLE")
        ) u_ram (
            .di({s_tlast,s_tdata}),.waddr(wr_addr),.we(wr_en),.wclk(clk),
            .raddr(rd_addr),.rdo(memory_word),.rdoq(),
            .rclk(clk),.rrst(1'b0),.rce(1'b1)
        );
    end else begin : g_inferred
        reg [MEM_WIDTH-1:0] mem[0:DEPTH-1];
        always @(posedge clk) if(wr_en) mem[wr_addr]<={s_tlast,s_tdata};
        assign memory_word=mem[rd_addr];
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin wr_ptr<=0;rd_ptr<=0;out_reg<=0;out_valid<=0;end
        else begin
            if(wr_en) wr_ptr<=wr_ptr+1'b1;
            if(fetch) begin
                out_reg<=memory_word;out_valid<=1;rd_ptr<=rd_ptr+1'b1;
            end else if(out_valid && m_tready) out_valid<=0;
        end
    end
endmodule
