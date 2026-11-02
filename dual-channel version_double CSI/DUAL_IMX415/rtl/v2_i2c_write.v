`timescale 1ns/1ps
// IMX415 four-byte write, entirely in clk. SDA is open drain. SCL runs at
// clk/(4*QUARTER); no fabric-generated clock or asynchronous busy handshake.
module v2_i2c_write #(parameter QUARTER=60)(
    input wire clk,rst_n,start,input wire [31:0] data,
    output reg scl,inout wire sda,
    output reg busy,done,nack,output reg [1:0] failed_byte
);
    localparam IDLE=0,START=1,LOW=2,HIGH=3,SAMPLE=4,FALL=5,
               ACK_LOW=6,ACK_HIGH=7,ACK_SAMPLE=8,ACK_FALL=9,
               STOP_LOW=10,STOP_HIGH=11,STOP_RELEASE=12,FINISH=13;
    reg [3:0] state;
    reg [$clog2(QUARTER+1)-1:0] divider;
    reg drive_low;
    reg [31:0] shift;
    reg [2:0] bit_index;
    reg [1:0] byte_index;
    (* ASYNC_REG="TRUE" *) reg [1:0] sda_sync;
    assign sda=drive_low ? 1'b0 : 1'bz;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) sda_sync<=2'b11;else sda_sync<={sda_sync[0],sda};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;divider<=0;scl<=1;drive_low<=0;
            busy<=0;done<=0;nack<=0;failed_byte<=0;
            shift<=0;bit_index<=7;byte_index<=0;
        end else begin
            done<=0;
            if(state==IDLE) begin
                divider<=0;scl<=1;drive_low<=0;
                if(start) begin
                    shift<=data;busy<=1;nack<=0;failed_byte<=0;
                    bit_index<=7;byte_index<=0;state<=START;
                end
            end else if(divider==QUARTER-1) begin
                divider<=0;
                case(state)
                    START: begin
                        // A bus stuck low must not look like 4 successful ACKs.
                        if(!sda_sync[1]) begin nack<=1;state<=STOP_LOW;end
                        else begin drive_low<=1;state<=LOW;end
                    end
                    LOW: begin scl<=0;drive_low<=!shift[31];state<=HIGH;end
                    HIGH: begin scl<=1;state<=SAMPLE;end
                    SAMPLE: state<=FALL;
                    FALL: begin
                        scl<=0;
                        if(bit_index==0) state<=ACK_LOW;
                        else begin shift<=shift<<1;bit_index<=bit_index-1'b1;state<=LOW;end
                    end
                    ACK_LOW: begin drive_low<=0;state<=ACK_HIGH;end
                    ACK_HIGH: begin scl<=1;state<=ACK_SAMPLE;end
                    ACK_SAMPLE: begin
                        if(sda_sync[1]) begin nack<=1;failed_byte<=byte_index;end
                        state<=ACK_FALL;
                    end
                    ACK_FALL: begin
                        scl<=0;
                        if(nack || byte_index==3) state<=STOP_LOW;
                        else begin
                            shift<=shift<<1;bit_index<=7;byte_index<=byte_index+1'b1;state<=LOW;
                        end
                    end
                    STOP_LOW: begin scl<=0;drive_low<=1;state<=STOP_HIGH;end
                    STOP_HIGH: begin scl<=1;state<=STOP_RELEASE;end
                    STOP_RELEASE: begin drive_low<=0;state<=FINISH;end
                    FINISH: begin busy<=0;done<=1;state<=IDLE;end
                    default: begin state<=IDLE;busy<=0;drive_low<=0;scl<=1;end
                endcase
            end else divider<=divider+1'b1;
        end
    end
endmodule
