`timescale 1ns/1ps
// Assert immediately; release only after three clocks of the receiving domain.
module v2_reset_sync(input wire clk,arst_n,output wire rst_n);
    (* ASYNC_REG="TRUE" *) reg [2:0] stages;
    always @(posedge clk or negedge arst_n)
        if(!arst_n) stages<=0; else stages<={stages[1:0],1'b1};
    assign rst_n=stages[2];
endmodule
