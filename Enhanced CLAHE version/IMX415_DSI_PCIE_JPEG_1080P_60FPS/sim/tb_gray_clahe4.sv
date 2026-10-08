`timescale 1ns/1ps
module tb_gray_clahe4;
    localparam W=64,H=32,TILE_PIXELS=(W/2)*(H/2),CLIP=(TILE_PIXELS*2)/256;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,s_valid=0,s_sof=0,s_eol=0,enable=1;
    reg [31:0] s_gray=0;
    wire [31:0] m_gray;
    wire m_valid,m_sof,m_eol,lut_active;
    wire [31:0] hist_frames,hist_errors;
    gray_clahe4 #(.WIDTH(W),.HEIGHT(H)) dut(.*);
    integer x,y,lane,beat,received=0,errors=0;
    reg checking=0;
    reg [7:0] stimulus;
    function integer gray_for_tile(input integer t);
        begin case(t)
            0:gray_for_tile=32;
            1:gray_for_tile=64;
            2:gray_for_tile=128;
            3:gray_for_tile=200;
        endcase end
    endfunction
    function integer ref_map(input integer t,input integer g,input integer offset);
        integer excess,q,rem,b,cdf,v;
        begin
            excess=TILE_PIXELS-CLIP;q=excess/256;rem=excess%256;cdf=0;
            for(b=0;b<=g;b=b+1) begin
                v=q+(b<rem);
                if(b==gray_for_tile(t)+offset) v=v+CLIP;
                cdf=cdf+v;
            end
            ref_map=(cdf*255)/TILE_PIXELS;
        end
    endfunction
    function integer ref_weight_x(input integer px);
        begin
            if(px<=W/4)ref_weight_x=0;
            else if(px>=3*W/4)ref_weight_x=256;
            else ref_weight_x=((px-W/4)*256)/(W/2);
        end
    endfunction
    function integer ref_weight_y(input integer py);
        begin
            if(py<=H/4)ref_weight_y=0;
            else if(py>=3*H/4)ref_weight_y=256;
            else ref_weight_y=((py-H/4)*256)/(H/2);
        end
    endfunction
    function integer ref_blend(input integer a,b,w);
        begin ref_blend=(a*(256-w)+b*w+128)/256;end
    endfunction
    function integer ref_iir(input integer old_value,new_value);
        begin
            if(new_value>=old_value)ref_iir=old_value+(new_value-old_value+2)/4;
            else ref_iir=old_value-(old_value-new_value+2)/4;
        end
    endfunction
    function integer expected(input integer px,py,g);
        integer top,bottom;
        begin
            top=ref_blend(ref_map(0,g,0),ref_map(1,g,0),ref_weight_x(px));
            bottom=ref_blend(ref_map(2,g,0),ref_map(3,g,0),ref_weight_x(px));
            expected=ref_blend(top,bottom,ref_weight_y(py));
        end
    endfunction
    task send_frame;
        input integer offset;
        begin
            for(y=0;y<H;y=y+1) for(x=0;x<W/4;x=x+1) begin
                @(negedge clk);
                s_valid=1;s_sof=(y==0 && x==0);s_eol=(x==W/4-1);
                for(lane=0;lane<4;lane=lane+1)
                    s_gray[lane*8 +:8]=gray_for_tile((y>=H/2)*2+(x>=W/8))+offset;
            end
            @(negedge clk);s_valid=0;s_sof=0;s_eol=0;
        end
    endtask
    always @(posedge clk) if(m_valid) begin
        if(m_sof && lut_active)begin checking=1;received=0;end
        if(checking) begin
            for(integer k=0;k<4;k=k+1) begin
                integer xx,yy,gg,ee;
                xx=(received%(W/4))*4+k; yy=received/(W/4);
                gg=gray_for_tile((yy>=H/2)*2+(xx>=W/2))+16;
                ee=expected(xx,yy,gg);
                if(m_gray[k*8 +:8]!==ee[7:0])begin
                    $display("MISMATCH beat=%0d x=%0d y=%0d got=%0d exp=%0d",received,xx,yy,m_gray[k*8 +:8],ee);
                    errors=errors+1;
                    if(errors>10)$fatal(1,"too many errors");
                end
            end
            if(m_eol !== (received%(W/4)==W/4-1))begin
                $display("EOL mismatch at %0d",received);errors=errors+1;
            end
            received=received+1;
            if(received==W*H/4)checking=0;
        end
    end
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        repeat(1100)@(negedge clk);
        send_frame(0);
        repeat(12000)@(negedge clk);
        if(!lut_active || hist_frames!=1 || hist_errors!=0)
            $fatal(1,"map not ready: active=%d frames=%d errors=%d",lut_active,hist_frames,hist_errors);
        send_frame(16);
        repeat(10)@(negedge clk);
        if(received!=W*H/4 || errors!=0)
            $fatal(1,"bad output: received=%d errors=%d",received,errors);
        repeat(12000)@(negedge clk);
        if(dut.lut00[32] !==
            ref_iir(ref_map(0,32,0),ref_map(0,32,16)))
            $fatal(1,"IIR LUT mismatch: got %0d",dut.lut00[32]);
        $display("PASS CLAHE: %0d beats, 4 lanes, clip=%0d, interpolation and LUT IIR verified",received,CLIP);
        $finish;
    end
endmodule
