`timescale 1ps/1ps
// Synthetic eye feedback isolates control/primitive coupling. This does not
// simulate a camera or establish a board-level electrical sampling window.
module tb_phy_delay_scan;
    reg bitclk=0,nibbleclk=0,byteclk=0,rst_n=1,serial_data=0;
    always #1122 bitclk=~bitclk;
    always #2244 nibbleclk=~nibbleclk;
    always #4488 byteclk=~byteclk;
    wire [5:0] tap,best;
    wire load,done;
    wire [3:0] aligned=(dut.gen_ph1a.u_idelay.indly_en &&
        dut.gen_ph1a.u_idelay.in_dly>=5 && dut.gen_ph1a.u_idelay.in_dly<=21)?4'hf:4'h0;
    v2rx_auto_delay_ctl scan(byteclk,rst_n,aligned,tap,load,done,best);
    v2rx_csi_rx_hs_data_phy #(.DEVICE("PH1A")) dut(
        .I_rxclk(byteclk),.I_rxclk_div_x2(nibbleclk),.I_rxclk_div_x4(bitclk),
        .I_reset_n(rst_n),.I_hs_data_p(serial_data),.I_delay_value(tap),
        .I_delay_vaild(load),.O_rx_data(),.O_delay_data_val());
    wire [5:0] fallback_tap,fallback_best;
    wire fallback_load,fallback_done;
    // One alignment event begins a scan, followed by no usable eye.
    wire [3:0] no_eye=(fallback_scan.state==4'd1)?4'h1:4'h0;
    v2rx_auto_delay_ctl fallback_scan(byteclk,rst_n,no_eye,
        fallback_tap,fallback_load,fallback_done,fallback_best);
    v2rx_csi_rx_hs_data_phy #(.DEVICE("PH1A")) fallback_phy(
        .I_rxclk(byteclk),.I_rxclk_div_x2(nibbleclk),.I_rxclk_div_x4(bitclk),
        .I_reset_n(rst_n),.I_hs_data_p(serial_data),.I_delay_value(fallback_tap),
        .I_delay_vaild(fallback_load),.O_rx_data(),.O_delay_data_val());
    integer observations=0;
    always @(negedge byteclk) if(rst_n && scan.state==4'd4) begin
        if(dut.gen_ph1a.u_idelay.indly_en!==1 || dut.gen_ph1a.u_idelay.in_dly!==tap[4:0])
            $fatal(1,"scan is observing bypassed or unapplied delay");
        observations=observations+1;
    end
    initial begin
        #100;rst_n=0;#17000;rst_n=1;
        wait(done && fallback_done);
        repeat(3) @(negedge byteclk);
        if(tap!==13 || best!==17 || dut.gen_ph1a.u_idelay.in_dly!==13 || load!==0)
            $fatal(1,"eye midpoint was not retained in physical delay primitive");
        if(fallback_best!==0 || fallback_tap!==16 || fallback_phy.gen_ph1a.u_idelay.in_dly!==16 ||
           fallback_phy.gen_ph1a.u_idelay.indly_en!==1)
            $fatal(1,"no-eye fallback delay was not retained");
        // Explicit transitions initialize the vendor delay model's history.
        serial_data=1;#1000;serial_data=0;#1000;serial_data=1;#100;
        if(dut.w_hs_data_dalay!==0) $fatal(1,"delay bypassed after DONE");
        #500;
        if(dut.w_hs_data_dalay!==1) $fatal(1,"DONE delay did not settle");
        if(observations!=1048576) $fatal(1,"incomplete scan coverage");
        $display("PASS production scanner + PH1A model: %0d observation cycles enabled, eye5..21 -> retained tap13, no-eye -> retained tap16, DONE delay stays active",observations);
        $finish;
    end
    initial begin #12000000000;$fatal(1,"delay scan timeout");end
endmodule
