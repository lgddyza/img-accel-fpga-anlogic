`timescale 1ns/1ps
// Complete table -> standby release -> 20ms settle -> master start. NACK
// retries reset this camera only; progress and last failure survive retries.
module v2_imx415_config #(
    parameter INCK_HZ=37125000, I2C_QUARTER=60,
    parameter RESET_CYCLES=240000, BOOT_CYCLES=720000, START_CYCLES=480000
)(
    input wire clk,rst_n,output wire scl,inout wire sda,
    output wire pwdnb,output reg cfg_done,output reg error_pulse,
    output wire [31:0] progress,output reg [31:0] nack_count,
    output reg [31:0] last_failure
);
    localparam PROFILE_VALID=(INCK_HZ==24000000 || INCK_HZ==37125000);
    localparam BOOT=0,TABLE=1,SEND=2,WAIT_WRITE=3,STANDBY=4,SETTLE=5,MASTER=6,RUN=7;
    reg [3:0] state;
    reg [2:0] phase;
    reg [19:0] delay_count;
    reg [7:0] reg_index;
    wire [31:0] table_data;
    wire [7:0] table_size;
    generate if(INCK_HZ==37125000) begin:g_37
        ui_imx415reg_37125 rom({1'b0,reg_index},table_data,table_size);
    end else if(INCK_HZ==24000000) begin:g_24
        ui_imx415reg rom({1'b0,reg_index},table_data,table_size);
    end else begin:g_bad
        assign table_data=0;assign table_size=0;
    end endgenerate
    reg start;
    reg [31:0] write_data;
    wire busy,done,nack;
    wire [1:0] failed_byte;
    assign pwdnb=rst_n && PROFILE_VALID && (state!=BOOT || delay_count>=RESET_CYCLES);
    // [7:0] table index; [11:8] FSM; [12] busy; [13] pwdnb;
    // [14] done; [15] supported profile; [18:16] phase.
    assign progress={13'd0,phase,PROFILE_VALID,cfg_done,pwdnb,busy,state,reg_index};
    v2_i2c_write #(.QUARTER(I2C_QUARTER)) u_write(
        .clk(clk),.rst_n(rst_n),.start(start),.data(write_data),.scl(scl),.sda(sda),
        .busy(busy),.done(done),.nack(nack),.failed_byte(failed_byte));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=BOOT;phase<=0;delay_count<=0;reg_index<=0;start<=0;
            write_data<=0;cfg_done<=0;error_pulse<=0;nack_count<=0;last_failure<=0;
        end else begin
            start<=0;error_pulse<=0;
            case(state)
                BOOT: if(PROFILE_VALID) begin
                    if(delay_count==BOOT_CYCLES-1) begin state<=TABLE;delay_count<=0;end
                    else delay_count<=delay_count+1'b1;
                end
                TABLE: begin write_data<={8'h34,table_data[23:0]};phase<=0;state<=SEND;end
                STANDBY: begin write_data<=32'h34300000;phase<=1;state<=SEND;end
                MASTER: begin write_data<=32'h34300200;phase<=2;state<=SEND;end
                SEND: begin start<=1;state<=WAIT_WRITE;end
                WAIT_WRITE: if(done) begin
                    if(nack) begin
                        nack_count<=nack_count+1'b1;
                        last_failure<={6'd0,failed_byte,write_data[23:0]};
                        error_pulse<=1;cfg_done<=0;reg_index<=0;delay_count<=0;state<=BOOT;
                    end else if(phase==0) begin
                        if(reg_index==table_size-1'b1) state<=STANDBY;
                        else begin reg_index<=reg_index+1'b1;state<=TABLE;end
                    end else if(phase==1) begin delay_count<=0;state<=SETTLE;end
                    else begin cfg_done<=1;state<=RUN;end
                end
                SETTLE: if(delay_count==START_CYCLES-1) state<=MASTER;
                        else delay_count<=delay_count+1'b1;
                RUN: state<=RUN;
                default: begin state<=BOOT;delay_count<=0;cfg_done<=0;end
            endcase
        end
    end
endmodule
