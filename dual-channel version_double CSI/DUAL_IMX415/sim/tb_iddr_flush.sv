`timescale 1ps/1ps
module tb_iddr_flush;
    reg bitclk=0,nibbleclk=0,byteclk=0,runclock=1;
    always #1122 if(runclock) bitclk=~bitclk;
    always #2244 if(runclock) nibbleclk=~nibbleclk;
    always #4488 if(runclock) byteclk=~byteclk;
    reg rst_n=1,serial_data=0;
    reg [15:0] lfsr=16'hac73;
    // Change at the middle of each DDR unit interval, away from sampling edges.
    always @(bitclk) begin
        #561;
        lfsr={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
        serial_data=lfsr[0];
    end
    wire [7:0] data;
    v2rx_csi_rx_hs_data_phy #(.DEVICE("PH1A")) dut(
        .I_rxclk(byteclk),.I_rxclk_div_x2(nibbleclk),.I_rxclk_div_x4(bitclk),
        .I_reset_n(rst_n),.I_hs_data_p(serial_data),.I_delay_value(6'd16),
        .I_delay_vaild(1'b0),.O_rx_data(data),.O_delay_data_val());
    // Reference uses the vendor's resettable sampler. After a bounded flush,
    // the free-running implementation must produce identical stream bytes.
    wire [3:0] ref_nibble;
    PH1_LOGIC_IDDRx2 ref_iddr(.pclk(nibbleclk),.sclk(bitclk),.d(serial_data),
        .rst(!rst_n),.q3(ref_nibble[3]),.q2(ref_nibble[2]),.q1(ref_nibble[1]),.q0(ref_nibble[0]));
    reg [3:0] ref_previous;
    reg [7:0] ref_byte;
    always @(posedge nibbleclk) ref_previous<=ref_nibble;
    always @(posedge byteclk) ref_byte<={ref_nibble,ref_previous};
    integer age=0,compared=0;
    always @(negedge rst_n) age=0;
    always @(posedge byteclk) begin
        if(rst_n) age=age+1;else age=0;
        #1;
        if(age<8) begin
            if(data!==8'd0) $fatal(1,"unsettled byte escaped age=%0d",age);
        end else begin
            if((^data)===1'bx || data!==ref_byte)
                $fatal(1,"IDDR stream mismatch after flush age=%0d got=%h ref=%h",age,data,ref_byte);
            compared=compared+1;
        end
    end
    initial begin
        // Exercise initial unknown pipeline contents and reset at varied phases.
        #100 rst_n=0;
        #17000 rst_n=1;
        repeat(100) @(negedge byteclk);
        for(integer k=0;k<8;k=k+1) begin
            #(117+k*83) rst_n=0;
            #(15631+k*101) rst_n=1;
            repeat(40) @(negedge byteclk);
        end
        #731 rst_n=0;
        #21001 runclock=0;
        #100000;
        if(data!==0) $fatal(1,"clock-stop reset did not mask data");
        runclock=1;
        #371 rst_n=1;
        repeat(100) @(negedge byteclk);
        if(compared<400) $fatal(1,"not enough checked bytes");
        $display("PASS vendor-visible IDDR model: startup unknowns, 8 phase-varied resets, clock stop/restart, eight-byte flush; %0d bytes matched",compared);
        $finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
