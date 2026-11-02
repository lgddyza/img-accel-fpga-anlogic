`timescale 1ns/1ps
// Observe a divided toggle instead of asynchronously sampling the raw clock
// or a binary counter. Loss asserts reset; recovery releases on byte clocks.
module v2rx_csi_rx_clock_det(input wire I_ref_clock,I_ext_clock,I_enable,I_reset_in,
 output wire O_reset_out);
 reg [3:0] divider;
 always @(posedge I_ext_clock or negedge I_reset_in)
  if(!I_reset_in) divider<=0;else divider<=divider+1'b1;
 (* ASYNC_REG="TRUE" *) reg [2:0] seen;
 reg last_seen,alive;reg [7:0] timeout_count;
 always @(posedge I_ref_clock or negedge I_reset_in) begin
  if(!I_reset_in) begin seen<=0;last_seen<=0;alive<=0;timeout_count<=0;end
  else begin
   seen<={seen[1:0],divider[3]};last_seen<=seen[2];
   if(!I_enable) begin alive<=0;timeout_count<=0;end
   else if(seen[2]!=last_seen) begin alive<=1;timeout_count<=0;end
   else if(timeout_count==255) alive<=0;
   else timeout_count<=timeout_count+1'b1;
  end
 end
 v2_reset_sync u_recovered_reset(I_ext_clock,I_reset_in && I_enable && alive,O_reset_out);
endmodule
