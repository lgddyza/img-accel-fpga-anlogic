`timescale 1ns/1ps
module tb_jpeg_bridge_encoder;
    reg cam_clk=0, enc_clk=0, rst_n=0;
    always #20 cam_clk=~cam_clk;
    always #5 enc_clk=~enc_clk;
    reg [63:0] pixels=0;
    reg valid=0, sof=0, eol=0;
    wire [15:0] vid_data;
    wire vid_valid,vid_ready,vid_sof,vid_eol,bridge_fault;
    wire [7:0] jpg_data;
    wire jpg_valid,jpg_last;
    wire [31:0] selected,completed;
    wire cam_fault;
    reg [4:0] awaddr=0,araddr=0;
    reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
    reg [31:0] wdata=0;
    reg [3:0] wstrb=0;
    wire awready,wready,bvalid,arready,rvalid;
    wire [1:0] bresp,rresp;
    wire [31:0] rdata;
    integer outfile, byte_count=0, x,y,k;
    reg finished=0;
    reg [7:0] prev=0;
    reg saw_soi=0,saw_eoi=0;

    jpeg_gray4_axis_cdc #(.IMG_WIDTH(64),.IMG_HEIGHT(8),
        .FIFO_ADDR_WIDTH(6)) bridge (
        .cam_clk(cam_clk),.enc_clk(enc_clk),.rst_n(rst_n),
        .s_yuyv4(pixels),.s_valid(valid),.s_sof(sof),.s_eol(eol),
        .s_take_frame(1'b1),.s_fault(cam_fault),
        .s_selected_frames(selected),.s_completed_frames(completed),
        .m_tdata(vid_data),.m_tvalid(vid_valid),.m_tready(vid_ready),
        .m_tuser(vid_sof),.m_tlast(vid_eol),.m_fault(bridge_fault)
    );

    mjpegzero_enc_top #(.IMG_WIDTH(64),.IMG_HEIGHT(8),.LITE_MODE(0)) enc (
        .clk(enc_clk),.rst_n(rst_n),
        .s_axis_vid_tdata(vid_data),.s_axis_vid_tvalid(vid_valid),
        .s_axis_vid_tready(vid_ready),.s_axis_vid_tuser(vid_sof),
        .s_axis_vid_tlast(vid_eol),
        .m_axis_jpg_tvalid(jpg_valid),.m_axis_jpg_tdata(jpg_data),
        .m_axis_jpg_tlast(jpg_last),
        .s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),
        .s_axi_awready(awready),.s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),
        .s_axi_wready(wready),.s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid),.s_axi_bready(bready),
        .s_axi_araddr(araddr),.s_axi_arvalid(arvalid),
        .s_axi_arready(arready),.s_axi_rdata(rdata),
        .s_axi_rresp(rresp),.s_axi_rvalid(rvalid),
        .s_axi_rready(rready)
    );

    task axi_write(input [4:0] addr,input [31:0] data);
        begin
            @(posedge enc_clk);
            awaddr=addr; awvalid=1;
            wdata=data; wstrb=4'hf; wvalid=1; bready=1;
            fork
                begin wait(awready); @(posedge enc_clk); awvalid=0; end
                begin wait(wready); @(posedge enc_clk); wvalid=0; end
            join
            wait(bvalid);
            @(posedge enc_clk); bready=0;
        end
    endtask

    initial outfile=$fopen("bridge_encoder_64x8.jpg","wb");
    always @(posedge enc_clk) begin
        if (jpg_valid) begin
            $fwrite(outfile,"%c",jpg_data);
            if (prev==8'hff && jpg_data==8'hd8) saw_soi=1;
            if (prev==8'hff && jpg_data==8'hd9) saw_eoi=1;
            prev=jpg_data;
            byte_count=byte_count+1;
            if (jpg_last) begin
                $fclose(outfile);
                finished=1;
            end
        end
    end

    initial begin
        repeat(10) @(negedge enc_clk);
        rst_n=1;
        repeat(5) @(negedge enc_clk);
        axi_write(5'h00,32'h1);
        axi_write(5'h0c,32'd85);
        repeat(600) @(negedge enc_clk);
        for(y=0;y<8;y=y+1) begin
            for(x=0;x<16;x=x+1) begin
                @(negedge cam_clk);
                valid=1; sof=(x==0 && y==0); eol=(x==15);
                for(k=0;k<4;k=k+1)
                    pixels[k*16 +: 16]=16'h8000 | ((y*64+x*4+k) & 16'hff);
            end
            @(negedge cam_clk);
            valid=0; sof=0; eol=0;
            repeat(10) @(negedge cam_clk);
        end
        wait(finished);
        repeat(10) @(negedge enc_clk);
        if (cam_fault || bridge_fault || selected!=1 || completed!=1 ||
            !saw_soi || !saw_eoi || byte_count<100)
            $fatal(1,"bridge-encoder failed: fault=%b/%b frame=%0d/%0d bytes=%0d SOI=%b EOI=%b",
                cam_fault,bridge_fault,selected,completed,byte_count,saw_soi,saw_eoi);
        $display("JPEG_BRIDGE_ENCODER_PASS bytes=%0d",byte_count);
        $finish;
    end
    initial begin #10000000; $fatal(1,"bridge-encoder timeout"); end
endmodule
