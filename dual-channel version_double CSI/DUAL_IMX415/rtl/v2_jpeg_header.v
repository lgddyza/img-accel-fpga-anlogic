`timescale 1ns/1ps
// DJP2 replaces JPG3: a 32-byte little-endian envelope precedes each JPEG.
// Payload length is the DMA completion byte count minus 32, never guessed.
module v2_jpeg_header #(parameter TILE=0,WIDTH=1920,HEIGHT=1080)(
    input wire clk,rst_n,input wire [127:0] metadata,
    input wire [127:0] s_data,input wire [15:0] s_keep,
    input wire s_valid,s_last,output wire s_ready,
    output wire [127:0] m_data,output wire [15:0] m_keep,
    output wire m_valid,m_last,input wire m_ready
);
    localparam [7:0] TILE_ID=TILE;
    localparam [15:0] W=WIDTH,H=HEIGHT,TH=HEIGHT/3;
    reg [1:0] state;
    reg [127:0] h0,h1;
    assign s_ready=state==3 && m_ready;
    assign m_valid=state==1 || state==2 || (state==3 && s_valid);
    assign m_data=state==1 ? h0 : state==2 ? h1 : s_data;
    assign m_keep=state==3 ? s_keep : 16'hffff;
    assign m_last=state==3 && s_last;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin state<=0;h0<=0;h1<=0;end
        else case(state)
            0: if(s_valid) begin
                h0<={metadata[55:48],metadata[47:40],TILE_ID,metadata[39:32],
                     metadata[31:0],16'd32,16'd2,32'h32504a44};
                h1<={metadata[127:64],8'd1,8'd8,TH,H,W};
                state<=1;
            end
            1: if(m_ready) state<=2;
            2: if(m_ready) state<=3;
            3: if(s_valid && m_ready && s_last) state<=0;
        endcase
    end
endmodule
