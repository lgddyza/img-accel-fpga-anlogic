# mjpegZero source snapshot

Local derivative (2026-10-09): `mjpegzero_enc_top.v` registers the JFIF header-complete flag before gating input-buffer reads. The Huffman block-capacity check remains immediate. Timing-repair evidence and byte-identical JPEG regressions are documented in the project's `TIMING_FIX_20261009.md`.

- Upstream: https://github.com/lcapossio/mjpegZero (`main` archive downloaded 2026-10-03).
- Archive SHA-256: `B27744BFBCC35ED9020675D0D30EEAF58402753A74F64E60AC19ED7FDFC7C3D1`.
- Copied here: twelve top-level `rtl/*.v` files, upstream README, and full LICENSE.
- License: Apache-2.0 with Commons Clause v1.0. The license explicitly permits non-commercial student/research use and requires written permission for commercial integration. Keep the license and source notices with derivatives.
- The project source manifest now includes this candidate. The user has not yet run the full project synthesis or programmed its new bitstream.

Local derivative (2026-10-04): `input_buffer.v`, `mjpegzero_enc_top.v`, and `jfif_writer.v` add `MONO=1` to encode the existing grayscale camera data as a single-component JPEG. It emits only luminance blocks and changes the SOF0/SOS headers accordingly. `MONO=0` retains upstream color behavior. The 1080p/Q85 combined source in `E:/FPGA/workspace/jpeg_rtl_evaluation/` predates this modification; project simulations compile the twelve source files here directly.
