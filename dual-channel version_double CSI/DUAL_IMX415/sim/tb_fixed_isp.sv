`timescale 1ns/1ps
module tb_fixed_isp;
    reg clk=0,rst=0,valid=0,sof=0,eol=0;
    always #3.75 clk=~clk;
    reg [95:0] data=0;
    wire [95:0] awb_data,gamma_old,gamma_new;
    wire av,asof,aeol,ov,os,oe,nv,ns,ne;
    ui_awb #(.IMG_WIDTH(1920),.IMG_HEIGHT(1080),.DYNAMIC_ENABLE(0)) awb (
        .I_clk(clk),.I_rst_n(rst),.I_tdata(data),.I_tvalid(valid),
        .I_tlast(eol),.I_tuser(sof),.I_tready(),.O_tready(1'b1),
        .O_tdata(awb_data),.O_tvalid(av),.O_tlast(aeol),.O_tuser(asof));
    ui_gamma #(.GAMMA_10x(22)) legacy (
        .I_clk(clk),.I_rst_n(rst),.I_tdata(data),.I_tvalid(valid),
        .I_tlast(eol),.I_tuser(sof),.I_tready(),.O_tready(1'b1),
        .O_tdata(gamma_old),.O_tvalid(ov),.O_tlast(oe),.O_tuser(os));
    ui_dsi_gamma22 compact (
        .I_clk(clk),.I_rst_n(rst),.I_tdata(data),.I_tvalid(valid),
        .I_tlast(eol),.I_tuser(sof),.I_tready(),.O_tready(1'b1),
        .O_tdata(gamma_new),.O_tvalid(nv),.O_tlast(ne),.O_tuser(ns));
    reg [95:0] expected[0:4799];
    integer written=0,read_count=0,gamma_count=0;
    always @(posedge clk) if(rst && valid) begin
        expected[written]=data;written=written+1;
    end
    always @(negedge clk) if(rst) begin
        if({ov,os,oe}!={nv,ns,ne}) $fatal(1,"gamma flags differ");
        if(ov) begin
            if(gamma_old!==gamma_new) $fatal(1,"gamma mismatch old=%h new=%h",gamma_old,gamma_new);
            gamma_count=gamma_count+1;
        end
        if(av) begin
            if(read_count>=written || awb_data!==expected[read_count])
                $fatal(1,"unity AWB changes data at %0d got=%h expected=%h",read_count,awb_data,expected[read_count]);
            if(asof!==(read_count==0) || aeol!==(read_count%480==479))
                $fatal(1,"AWB markers differ at %0d",read_count);
            read_count=read_count+1;
        end
    end
    integer row,x,c;
    initial begin
        repeat(8) @(negedge clk);data={12{8'hff}};
        @(negedge clk);rst=1;
        for(row=0;row<8;row=row+1) begin
            for(x=0;x<480;x=x+1) begin
                @(negedge clk);valid=1;sof=row==0 && x==0;eol=x==479;
                for(c=0;c<12;c=c+1) data[c*8+:8]=(row*31+x+c*17)%256;
            end
            @(negedge clk);valid=0;sof=0;eol=0;
            repeat(row%2 ? 4300 : 97) @(negedge clk);
        end
        repeat(1200) @(negedge clk);
        if(read_count!=3840 || gamma_count!=3840) $fatal(1,"counts AWB=%0d gamma=%0d",read_count,gamma_count);
        $display("PASS unity AWB pixel/marker identity and all 256 gamma inputs across 12 channels, including long row gaps");
        $finish;
    end
    initial begin #500000;$fatal(1,"fixed ISP timeout");end
endmodule
