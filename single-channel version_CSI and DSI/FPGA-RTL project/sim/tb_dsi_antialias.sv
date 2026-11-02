`timescale 1ns/1ps
module tb_dsi_antialias;
    reg clk=0; always #5 clk=!clk;
    reg rst_n=0, bypass=0, valid=0, user=0, last=0;
    reg [127:0] data=0;
    wire [127:0] out_data;
    wire out_valid, out_user, out_last;
    ui_dsi_box2x2 dut(.clk(clk), .rst_n(rst_n), .bypass(bypass),
        .s_data(data), .s_valid(valid), .s_user(user), .s_last(last),
        .m_data(out_data), .m_valid(out_valid), .m_user(out_user), .m_last(out_last));
    integer frame, y, w, p, c, ox=0, oy=0, count=0, expected, actual;
    integer height=16;
    function integer channel(input integer yy, xx, cc);
        begin
            if(frame==0) begin
                case(cc)
                    0: channel=((xx+yy)%2)*255;
                    1: channel=(1-(xx+yy)%2)*255;
                    2: channel=32;
                endcase
            end else case(cc)
                0: channel=(xx+3*yy)%256;
                1: channel=(xx/8+7*yy)%256;
                2: channel=(xx*13+17*yy)%256;
            endcase
        end
    endfunction
    always @(negedge clk) if(rst_n && out_valid) begin
        if(out_user !== (ox==0 && oy==0)) $fatal(1,"SOF moved");
        if(out_last !== (ox==1916)) $fatal(1,"EOL moved");
        for(p=0;p<4;p=p+1) begin
            for(c=0;c<3;c=c+1) begin
                expected=channel(oy,ox+p,c);
                if(!bypass) expected=(expected+
                    channel(oy,ox+p==0 ? 0 : ox+p-1,c)+
                    channel(oy==0 ? 0 : oy-1,ox+p,c)+
                    channel(oy==0 ? 0 : oy-1,ox+p==0 ? 0 : ox+p-1,c))/4;
                actual=out_data[32*p+8*c +: 8];
                if(out_data[32*p+8*c +: 8] !== expected[7:0])
                    $fatal(1,"Box mismatch f=%0d y=%0d x=%0d c=%0d got=%0d expected=%0d",
                        frame,oy,ox+p,c,actual,expected);
            end
            if(out_data[32*p+24 +: 8] !== 0) $fatal(1,"Padding changed");
        end
        count=count+4;
        if(ox==1916) begin ox=0; oy=oy+1; end else ox=ox+4;
    end
    initial begin
        if($test$plusargs("FULL")) height=1080;
        repeat(4) @(posedge clk); #1 rst_n=1;
        for(frame=0;frame<3;frame=frame+1) begin
            bypass=frame==2; ox=0; oy=0;
            for(y=0;y<height;y=y+1) begin
                for(w=0;w<480;w=w+1) begin
                    @(posedge clk); #1;
                    valid=1;user=y==0 && w==0;last=w==479;
                    for(integer ip=0;ip<4;ip=ip+1) begin
                        data[32*ip+24 +: 8]=0;
                        for(integer ic=0;ic<3;ic=ic+1)
                            data[32*ip+8*ic +: 8]=channel(y,4*w+ip,ic);
                    end
                    if(w%7==6) begin
                        @(posedge clk); #1;valid=0;user=0;last=0;
                    end
                end
                @(posedge clk); #1;valid=0;user=0;last=0;
                repeat(12) @(posedge clk);
            end
            repeat(20) @(posedge clk); #1;
            if(oy!=height || ox!=0) $fatal(1,"Incomplete frame");
        end
        $display("DSI_ANTIALIAS_PASS pixels=%0d: checker, RGB ramp, bypass, bubbles, frame edges",count);
        $finish;
    end
endmodule
