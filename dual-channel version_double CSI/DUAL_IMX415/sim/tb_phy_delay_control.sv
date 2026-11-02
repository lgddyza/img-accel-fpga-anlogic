`timescale 1ps/1ps
module tb_phy_delay_control;
    reg bitclk=0,nibbleclk=0,byteclk=0,rst_n=1,serial_data=0;
    always #1122 bitclk=~bitclk;
    always #2244 nibbleclk=~nibbleclk;
    always #4488 byteclk=~byteclk;
    reg [5:0] tap=16;
    reg load=0;
    v2rx_csi_rx_hs_data_phy #(.DEVICE("PH1A")) dut(
        .I_rxclk(byteclk),.I_rxclk_div_x2(nibbleclk),.I_rxclk_div_x4(bitclk),
        .I_reset_n(rst_n),.I_hs_data_p(serial_data),.I_delay_value(tap),
        .I_delay_vaild(load),.O_rx_data(),.O_delay_data_val());
    integer checks=0;
    task check_edge(input integer delay_ps);
        reg previous;
        begin
            previous=serial_data;
            serial_data=~serial_data;
            #1;
            if(dut.w_hs_data_dalay!==previous) $fatal(1,"input delay bypassed");
            #(delay_ps-2);
            if(dut.w_hs_data_dalay!==previous) $fatal(1,"input delay shorter than selected tap");
            #2;
            if(dut.w_hs_data_dalay!==serial_data) $fatal(1,"input delay did not match selected tap");
            checks=checks+1;
            #1000;
        end
    endtask
    task apply_tap(input [5:0] code);
        begin
            @(negedge byteclk);tap=code;load=1;
            @(negedge byteclk);load=0;tap=63;
            repeat(3) @(negedge byteclk);
            // Change the input code without a load; the applied tap must hold.
            check_edge(170+code*23);
            check_edge(170+code*23);
        end
    endtask
    initial begin
        #100;rst_n=0;#17000;rst_n=1;
        // Give the visible delay model explicit input history before measuring.
        serial_data=1;#1000;serial_data=0;#1000;
        apply_tap(0);apply_tap(7);apply_tap(16);apply_tap(31);
        @(negedge byteclk);rst_n=0;load=0;tap=0;
        #17000;rst_n=1;
        repeat(3) @(negedge byteclk);
        check_edge(538);check_edge(538);
        $display("PASS PH1A persistent delay: %0d measured edges, taps 0/7/16/31, code hold without load, reset to tap16",checks);
        $finish;
    end
    initial begin #1000000;$fatal(1,"delay control timeout");end
endmodule
