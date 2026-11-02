`timescale 1ns/1ps
module tb_preproc_lite;
    parameter W=64,H=24,CASES=9,PAUSE=0;
    localparam N=W*H/4;
    reg clk=0,rst_n=0,camera=0;
    always #3.75 clk=~clk;
    reg [127:0] s_rgb=0,metadata=0;
    reg s_valid=0,s_sof=0,s_eol=0;
    reg [2:0] mode=0,strength=4;
    wire [127:0] m_rgb_gray,observer_rgb;
    wire m_valid,m_sof,m_eol,observer_valid,observer_sof,observer_eol,gauss_overrun;
    wire [2:0] applied_mode;
    wire [31:0] hist_frames_a,hist_frames_b,hist_errors_a,hist_errors_b;
    v2_dual_preprocess #(.WIDTH(W),.HEIGHT(H)) dut(.*);
    wire [511:0] result;wire result_valid;
    v2_feature_observer #(.WIDTH(W),.HEIGHT(H)) observer (
        .clk(clk),.rst_n(rst_n),.rgb(observer_rgb),.metadata(metadata),
        .valid(observer_valid),.sof(observer_sof),.eol(observer_eol),
        .result(result),.result_valid(result_valid),.result_ready(1'b1));
    reg [127:0] pixels[0:CASES*N-1];
    reg [31:0] expected[0:CASES*N-1],raw[0:CASES*N-1];
    reg [511:0] features[0:CASES-1];
    reg [7:0] settings[0:CASES-1];
    integer count=0,observed=0,feature_count=0;
    integer c,i,lane;
    string prefix;
    always @(negedge clk) if(rst_n) begin
        if(gauss_overrun) $fatal(1,"preprocessor fault at output %0d",count);
        if(m_valid) begin
            if(count>=CASES*N) $fatal(1,"extra output");
            if(m_sof!==(count%N==0) || m_eol!==(count%(W/4)==W/4-1))
                $fatal(1,"output geometry at %0d",count);
            for(integer p=0;p<4;p=p+1)
                if(m_rgb_gray[p*32+:32]!=={8'd0,{3{expected[count][p*8+:8]}}})
                    $fatal(1,"case=%0d group=%0d lane=%0d got=%h expected=%h",
                        count/N,count%N,p,m_rgb_gray[p*32+:32],expected[count][p*8+:8]);
            count=count+1;
        end
        if(observer_valid) begin
            if(observed>=CASES*N) $fatal(1,"extra observer sample");
            if(observer_sof!==(observed%N==0) || observer_eol!==(observed%(W/4)==W/4-1))
                $fatal(1,"observer geometry");
            for(integer p=0;p<4;p=p+1)
                if(observer_rgb[p*32+:32]!=={8'd0,{3{raw[observed][p*8+:8]}}})
                    $fatal(1,"observer did not retain original luma");
            observed=observed+1;
        end
        if(result_valid) begin
            if(feature_count>=CASES || result!==features[feature_count])
                $fatal(1,"original feature mismatch case=%0d got=%h expected=%h",
                    feature_count,result,features[feature_count]);
            feature_count=feature_count+1;
        end
    end
    initial begin
        if(!$value$plusargs("prefix=%s",prefix)) $fatal(1,"missing prefix");
        $readmemh({prefix,"_rgb.hex"},pixels);
        $readmemh({prefix,"_out.hex"},expected);
        $readmemh({prefix,"_raw.hex"},raw);
        $readmemh({prefix,"_features.hex"},features);
        $readmemh({prefix,"_settings.hex"},settings);
        repeat(6) @(negedge clk);rst_n=1;
        repeat(8) @(negedge clk);
        for(c=0;c<CASES;c=c+1) begin
            camera=c%2;metadata=0;metadata[27:0]=c+1;
            metadata[32]=camera;metadata[95:64]=c+100;
            mode=settings[c][2:0];strength=settings[c][6:4];
            for(i=0;i<N;i=i+1) begin
                @(negedge clk);#1;
                s_valid=1;s_sof=i==0;s_eol=i%(W/4)==W/4-1;s_rgb=pixels[c*N+i];
                // Controls are allowed to change only for the next frame.
                if(i==1) begin mode=7;strength=7;end
                if((i%29==10 && W<1920) || i%(W/4)==W/4-1) begin
                    @(negedge clk);#1;s_valid=0;s_sof=0;s_eol=0;
                    repeat((i%7)+2+PAUSE) @(negedge clk);
                end
            end
            @(negedge clk);#1;s_valid=0;s_sof=0;s_eol=0;
            wait(count==(c+1)*N && feature_count==c+1);
            repeat(20) @(negedge clk);
            $display("PASS exact pixels, original OBS1 features, SOF mode lock case=%0d",c);
        end
        if(observed!=CASES*N) $fatal(1,"missing observer samples");
        $display("PASS PRF1 %0dx%0d cases=%0d groups=%0d",W,H,CASES,count);
        $finish;
    end
    initial begin #300000000; $fatal(1,"preprocessor timeout count=%0d",count);end
endmodule
