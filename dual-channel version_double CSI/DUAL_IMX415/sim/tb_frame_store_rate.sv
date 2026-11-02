`timescale 1ns/1ps
// Full geometry capture/cache scheduling under aligned 60fps source bursts.
// Ideal independent AXI channels; a fixed JPEG tail models measured pipeline
// latency only, not JPEG content, PCIe backpressure or vendor DDR arbitration.
module tb_frame_store_rate;
    tb_frame_store #(.W(1920),.H(1080),.STRIDE(4194304),.CAP_FIFO_ADDR(9),
                     .BURST(2),.TIMEOUT_NS(120000000)) run();
endmodule
