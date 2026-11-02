`timescale 1ns/1ps
// Real header/ECC, RAW10 unpack, packet-to-stream and crop. Electrical PHY
// is outside this test. Feed 1100 packet lines, verify every retained pixel.
module tb_csi_packets;
 reg clk=0,rst=0;always #4.488 clk=~clk;
 reg [31:0] data=0;reg valid=0;
 wire done,wait_sync,in_frame,in_line;wire [31:0] payload;wire pv;
 v2rx_csi_rx_packet_handler parser(clk,rst,1'b1,data,valid,done,wait_sync,payload,pv,,in_frame,in_line);
 wire [39:0] raw,axis,out;wire rv,av,as,ae,ov,os,oe,odd;wire [31:0] errors;
 v2rx_csi_rx_10bit_unpack unpack(clk,rst,1'b1,in_line,payload,pv,raw,rv);
 v2rx_csi_rx_vid2stream bridge(clk,rst,done,in_line,in_frame,raw,rv,clk,rst,1'b1,as,ae,av,axis);
 v2_axis_crop crop(clk,rst,axis,av,as,ae,out,ov,os,oe,odd,errors);
 reg [23:0] header;wire [7:0] ecc;
 v2rx_csi_rx_hdr_ecc checksum(header,ecc);
 integer count=0,starts=0,ends=0,lines=0;
 integer j,expected;
 always @(negedge clk) begin
  if(av && ae) lines=lines+1;
  if(ov) begin
   for(j=0;j<4;j=j+1) begin
    expected=((count/480+20)*3+(count%480+1)*4+j)%1024;
    if(out[j*10+:10]!==expected) $fatal(1,"RAW pixel mismatch beat=%0d pixel=%0d actual=%0d expected=%0d",count,j,out[j*10+:10],expected);
   end
   if(os!==(count==0) || oe!==(count%480==479) || odd!==0) $fatal(1,"wrong RAW markers");
   count=count+1;if(os) starts=starts+1;if(oe) ends=ends+1;
  end
 end
 task hdr(input [7:0] typ,input [15:0] n);
  begin
   header={n,typ};#1;
   @(negedge clk);data={ecc,header};valid=1;
   @(negedge clk);valid=0;
  end
 endtask
 reg [7:0] bytes[0:2415];integer row,x,k,l,v;
 initial begin
  repeat(4) @(negedge clk);rst=1;repeat(20) @(negedge clk);
  hdr(0,1);repeat(20) @(negedge clk);
  for(row=0;row<1100;row=row+1) begin
   for(x=0;x<482;x=x+1) begin
    bytes[x*5+4]=0;
    for(k=0;k<4;k=k+1) begin
     v=(row*3+x*4+k)%1024;bytes[x*5+k]=v>>2;bytes[x*5+4][k*2+:2]=v&3;
    end
   end
   for(l=2410;l<2416;l=l+1) bytes[l]=0;
   hdr(8'h2b,2410);
   // hdr returns at a falling edge immediately after the header; first data
   // now arrives on the next rising edge with no extra blank cycle.
   for(l=0;l<2416;l=l+4) begin
    data={bytes[l+3],bytes[l+2],bytes[l+1],bytes[l]};valid=1;
    @(negedge clk);
   end
   valid=0;repeat(32) @(negedge clk);
  end
  hdr(1,1);repeat(40) @(negedge clk);
  if(count!=518400 || starts!=1 || ends!=1080 || errors!=0 || lines!=1100)
   $fatal(1,"geometry beats=%0d starts=%0d ends=%0d source_lines=%0d errors=%0d",count,starts,ends,lines,errors);
  $display("PASS CSI RAW10 full geometry 1928x1100 -> exact 1920x1080 pixels and frame/line markers");$finish;
 end
endmodule
