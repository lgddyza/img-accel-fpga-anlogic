`timescale 1ns/1ps
// Full row width and real encoder/packer; shortened frame height keeps this
// a bounded integrity regression, not a full-1080p throughput measurement.
module tb_jpeg_stream_stall;
    tb_jpeg_dual_rate #(.W(1920),.H(48),.FRAMES(4),.HOST_STALL(1)) run();
endmodule
