"""Generate the stable V2 demo preprocessing pipeline.

The demo deliberately keeps only grayscale, Gaussian and CLAHE. Sobel and
black-hat remain available in the frozen V1 reference but are not instantiated
in the demo, so they cannot consume FPGA resources or create another failure
mode while the dual-camera transport is being brought up.
"""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'uisrc/01_rtl/gray_preprocess4.v').read_text(encoding='utf-8-sig').split('endmodule',1)[0]+'endmodule\n'
s=s.replace('module gray_preprocess4 #(','module v2_dual_preprocess #(',1)
s=s.replace('// Four pixels per camera clock. Modes 0..3 retain Gaussian/CLAHE selection;\n// Modes 4/5 bypass CLAHE; 6/7 apply CLAHE after Sobel/blackhat.', '// V2 stable demo: modes 0..3 are gray, Gaussian, gray+CLAHE, Gaussian+CLAHE.')
s=s.replace('            if (s_valid && s_sof) frame_mode<=mode;','            if (s_valid && s_sof) frame_mode<={1\'b0,mode[1:0]};',1)
s=s.replace('    input  wire         clk,','    input  wire         camera,\n    input  wire         clk,',1)
s=s.replace('    output wire [31:0] hist_frames,\n    output wire [31:0] hist_errors',
'''    output wire [31:0] hist_frames_a,hist_frames_b,
    output wire [31:0] hist_errors_a,hist_errors_b''',1)
start=s.index('    // 2x2 tiled CLAHE')
# The frozen source declares the optional Sobel/black-hat wires between the
# Gaussian stage and CLAHE. Remove that whole optional branch and rebuild the
# output path below; only center/gaussian -> CLAHE remains in V2 demo.
prefix=s[:start]
optional=prefix.find('    wire [31:0] sobel4,blackhat4;')
if optional >= 0:
    prefix=prefix[:optional]
hist='''    // The scheduler holds camera until all three JPEG packets complete.
    // Spatial windows reset/flush at frame boundaries. Histogram/LUT history
    // must persist independently for each physical camera.
    wire [31:0] eq_a,eq_b;
    wire va,vb_hist,sa,sb_hist,ea,eb,la,lb;
    assign equalized4=camera ? eq_b : eq_a;
    assign legacy_valid=camera ? vb_hist : va;
    assign legacy_sof=camera ? sb_hist : sa;
    assign legacy_eol=camera ? eb : ea;
'''
for cam,idx in [('a',0),('b',1)]:
 v,sof,eol,lut=('va','sa','ea','la') if idx==0 else ('vb_hist','sb_hist','eb','lb')
 hist+=f'''    gray_clahe4 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.LUT_IIR_SHIFT(2)) u_hist_{cam} (
        .clk(clk),.rst_n(rst_n),.s_gray(selected4),
        .s_valid(selected_valid && camera==1'b{idx}),
        .s_sof(selected_sof && camera==1'b{idx}),.s_eol(selected_eol && camera==1'b{idx}),
        .enable(frame_mode[1]),.m_gray(eq_{cam}),.m_valid({v}),.m_sof({sof}),.m_eol({eol}),
        .lut_active({lut}),.hist_frames(hist_frames_{cam}),.hist_errors(hist_errors_{cam}));
'''
tail='''    // Demo modes: 0=gray, 1=Gaussian, 2=gray+CLAHE, 3=Gaussian+CLAHE.
    wire [31:0] selected4 = frame_mode[0] ? gauss4 : center4;
    wire selected_valid=gauss_valid;
    wire selected_sof=gauss_sof;
    wire selected_eol=gauss_eol;
    wire [31:0] equalized4;
    wire legacy_valid,legacy_sof,legacy_eol;
'''
tail+=hist
tail+='''    assign m_valid=legacy_valid;
    assign m_sof=legacy_sof;
    assign m_eol=legacy_eol;
    assign gauss_overrun=gauss_fault;
    genvar lane;
    generate for (lane=0;lane<4;lane=lane+1) begin : g_rgb
        wire [7:0] y = equalized4[lane*8 +: 8];
        assign m_rgb_gray[lane*32 +: 32] = {8'd0,y,y,y};
    end endgenerate
endmodule
'''
prefix=prefix.replace('// Four pixels per camera clock.', '// V2 stable demo: one shared grayscale/Gaussian stage and two independent CLAHE histories.\n// Four pixels per processing clock.',1)
(ROOT/'rtl/v2_dual_preprocess.v').write_text(prefix+tail,encoding='utf-8')
print('Generated stable demo preprocessing: gray/Gaussian/CLAHE only')
