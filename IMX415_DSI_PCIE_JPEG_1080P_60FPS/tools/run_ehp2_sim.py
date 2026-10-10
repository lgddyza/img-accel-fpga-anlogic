"""Compile and run isolated full-resolution xsim regressions."""
import argparse
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
BIN=Path("F:/FPGA/Vivado18.3/Vivado/2018.3/bin")


def run(args, directory, log):
    result=subprocess.run(args,cwd=directory,text=True,capture_output=True,timeout=1200)
    (directory/log).write_text(result.stdout+result.stderr,encoding="utf-8")
    if result.returncode or "FATAL" in result.stdout or "Fatal" in result.stdout:
        raise RuntimeError(result.stdout[-3000:]+result.stderr[-1000:])
    print(result.stdout[-1600:],flush=True)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("case",choices=("pixels","jpeg"))
    case=parser.parse_args().case
    directory=ROOT/"tools/ehp2_sim"/case
    directory.mkdir(parents=True,exist_ok=True)
    files=[ROOT/"uisrc/01_rtl"/n for n in ("gray_gauss4.v","gray_preprocess4.v")]
    top="tb_gray_enhance4_1080p" if case=="pixels" else "tb_ehp2_jpeg_1080p"
    if case=="jpeg":
        files+=[ROOT/"uisrc/03_ip/ui_dbuf/sfifo/sfifo.v"]
        files += [ROOT/"uisrc/01_rtl"/n for n in (
            "gray4_to_yuyv4.v","jpeg_gray4_axis_cdc.v","jpeg_axil_config.v",
            "jpeg_byte_packer.v","jpeg_triple_tile_branch.v")]
        files+=sorted((ROOT/"third_party/mjpegZero/rtl").glob("*.v"))
        # xsim rejects this forward declaration; keep the synthesis source intact.
        original=ROOT/"third_party/mjpegZero/rtl/mjpegzero_enc_top.v"
        source=original.read_text(encoding="utf-8")
        declaration="    reg         frame_start_pulse;"
        if source.count(declaration)!=1:
            raise RuntimeError("Unexpected frame_start_pulse declaration")
        source=source.replace(declaration+"\n", "", 1)
        anchor="    wire        jfif_headers_done;"
        if source.count(anchor)!=1:
            raise RuntimeError("Unexpected JFIF declaration anchor")
        source=source.replace(anchor, declaration+"\n"+anchor, 1)
        compatible=directory/original.name
        compatible.write_text(source,encoding="utf-8")
        files=[compatible if f==original else f for f in files]
    run([str(BIN/"xvlog.bat"),"-sv",*[str(f) for f in files[:2]]],directory,"compile_preproc.log")
    if files[2:]:
        run([str(BIN/"xvlog.bat"),*[str(f) for f in files[2:]]],directory,"compile.log")
    run([str(BIN/"xvlog.bat"),"-sv",str(ROOT/"sim"/(top+".sv"))],directory,"compile_tb.log")
    run([str(BIN/"xelab.bat"),top,"-s","ehp2_"+case,"-mt","2"],directory,"elaborate.log")
    run([str(BIN/"xsim.bat"),"ehp2_"+case,"-runall"],directory,"simulate.log")
    print("EHP2_SIM_PASS",case,flush=True)


if __name__=="__main__":main()
