`timescale 1ns/1ps
// Worst aligned active burst at the supported 720Mbps/lane RAW10 cadence:
// four 4-pixel beats then one bubble at ~90MHz, production 512-word FIFOs.
// 64 consecutive full-width rows bound the burst response, not a 60fps proof.
// Ideal AXI responses deliberately isolate local writer throughput.
module tb_frame_store_burst;
    tb_frame_store #(.W(1920),.H(64),.STRIDE(262144),.CAP_FIFO_ADDR(9),.BURST(1)) run();
endmodule
