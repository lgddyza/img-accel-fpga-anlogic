`timescale 1ns/1ps
// Decode actual SCL/SDA transactions. A NACK must not restart camera B.
module tb_camera_profiles;
 reg clk=0,rst=0;always #5 clk=~clk;
 tri1 [2:0] sda;wire [2:0] scl,pwd,done,error;
 wire [31:0] progress[0:2],nacks[0:2],failure[0:2];
 genvar c;
 generate for(c=0;c<3;c=c+1) begin:g
  v2_imx415_config #(.INCK_HZ(c==0?37125000:c==1?24000000:27000000),
   .I2C_QUARTER(4),.RESET_CYCLES(5),.BOOT_CYCLES(20),.START_CYCLES(200)) dut(
   .clk(clk),.rst_n(rst),.scl(scl[c]),.sda(sda[c]),.pwdnb(pwd[c]),
   .cfg_done(done[c]),.error_pulse(error[c]),.progress(progress[c]),.nack_count(nacks[c]),.last_failure(failure[c]));
  if(c<2) begin:slave
   reg drive=0,active=0;integer bits=0,bytes=0,transactions=0,accepted=-1;
   initial begin #1;accepted=0;end
   reg [31:0] word=0,completed_word=0;time standby_time=0;
   wire [31:0] expected;wire [7:0] size;wire [8:0] index=accepted;
   if(c==0) ui_imx415reg_37125 reference_rom(index,expected,size);
   else ui_imx415reg reference_rom(index,expected,size);
   assign sda[c]=drive ? 1'b0 : 1'bz;
   always @(negedge sda[c]) if(scl[c] && rst) begin active=1;bits=0;bytes=0;word=0;end
   always @(posedge scl[c]) if(active && bytes<4) begin
    if(bits<8) begin word={word[30:0],sda[c]};bits=bits+1;end
    else begin bits=0;bytes=bytes+1;if(bytes==4) completed_word=word;end
   end
   always @(negedge scl[c]) drive=active && bits==8 && bytes<4 && !(c==0 && transactions==0 && bytes==3);
   always @(posedge sda[c]) if(scl[c] && active) begin
    active=0;drive=0;
    if(bytes!=4) $fatal(1,"truncated transaction camera=%0d bytes=%0d",c,bytes);
    if(!(c==0 && transactions==0)) begin
     if(accepted<201 && completed_word!=={8'h34,expected[23:0]})
      $fatal(1,"camera=%0d index=%0d sent=%h expected=%h",c,accepted,completed_word,expected);
     if(accepted==201) begin
      if(completed_word!==32'h34300000) $fatal(1,"missing standby release");
      standby_time=$time;
     end
     if(accepted==202) begin
      if(completed_word!==32'h34300200 || $time-standby_time<2000) $fatal(1,"master start/delay");
     end
     accepted=accepted+1;
    end
    transactions=transactions+1;
   end
  end
 end endgenerate
 initial begin
  repeat(3) @(negedge clk);rst=1;
  wait(done[1]);if(nacks[1]!=0) $fatal(1,"A NACK disturbed B");
  wait(done[0]);repeat(20) @(negedge clk);
  if(nacks[0]!=1 || nacks[1]!=0 || done[2] || pwd[2]) $fatal(1,"retry/profile behavior");
  if(g[0].slave.accepted!=203 || g[1].slave.accepted!=203) $fatal(1,"missing table/start writes");
  if(failure[0][25:24]!=3) $fatal(1,"NACK byte diagnostic");
  if(!scl[0] || !scl[1] || sda[0]!==1'b1 || sda[1]!==1'b1) $fatal(1,"bus not idle");
  rst=0;#1;if(pwd!==0) $fatal(1,"PWDNB reset");
  $display("PASS both 201-entry profiles over I2C, isolated NACK retry, start delay, unsupported profile");$finish;
 end
 initial begin #5000000;$fatal(1,"configuration timeout");end
endmodule
