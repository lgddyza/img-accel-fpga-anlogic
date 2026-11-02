`timescale 1ns/1ps

// Programs mjpegZero Full after reset and between frames. Its AXI-Lite slave
// holds WDATA until both address and data have arrived, so this master holds
// the complete transaction through BVALID. A quality change pauses capture
// while the encoder rebuilds its quantization tables.
module jpeg_axil_config (
    input wire clk, rst_n,
    input wire [6:0] quality,
    input wire frame_busy,
    output wire ready,
    output wire [6:0] applied_quality,
    output wire [4:0] awaddr,
    output wire awvalid,
    input wire awready,
    output wire [31:0] wdata,
    output wire [3:0] wstrb,
    output wire wvalid,
    input wire wready,
    input wire bvalid,
    output wire bready
);
    localparam [2:0] Q_SEND=0,Q_RESP=1,Q_SETTLE=2,
                     CTRL_SEND=3,CTRL_RESP=4,READY=5;
    reg [2:0] state;
    reg aw_done,w_done;
    reg [6:0] programmed_quality, target_quality;
    reg [9:0] settle_count;
    wire sending = state==Q_SEND || state==CTRL_SEND;
    assign awaddr = (state==Q_SEND || state==Q_RESP) ? 5'h0c : 5'h00;
    assign wdata = (state==Q_SEND || state==Q_RESP) ?
                   {25'd0,target_quality} : 32'd1;
    assign wstrb = 4'hf;
    assign awvalid = sending && !aw_done;
    assign wvalid = sending && !w_done;
    assign bready = state==Q_RESP || state==CTRL_RESP;
    assign ready = state==READY && quality==programmed_quality;
    assign applied_quality = programmed_quality;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=Q_SEND;aw_done<=0;w_done<=0;
            programmed_quality<=0;target_quality<=7'd85;
            settle_count<=0;
        end else begin
            if (sending) begin
                if(awvalid && awready) aw_done<=1;
                if(wvalid && wready) w_done<=1;
                if((aw_done || (awvalid && awready)) &&
                   (w_done || (wvalid && wready))) begin
                    aw_done<=0;w_done<=0;
                    state <= state==Q_SEND ? Q_RESP : CTRL_RESP;
                end
            end else case(state)
                Q_RESP: if(bvalid) begin
                    state<=Q_SETTLE;
                    settle_count<=0;
                end
                Q_SETTLE: if(&settle_count) state<=CTRL_SEND;
                          else settle_count<=settle_count+1'b1;
                CTRL_RESP: if(bvalid) begin
                    programmed_quality<=target_quality;
                    state<=READY;
                end
                READY: if(!frame_busy && quality!=programmed_quality) begin
                    target_quality<=quality;
                    state<=Q_SEND;
                end
                default: state<=Q_SEND;
            endcase
        end
    end
endmodule
