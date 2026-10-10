"""Exercise the CLI with an in-memory BAR; never opens a PCIe device."""
import contextlib
import importlib.util
import io
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location(
    "preproc_mode", Path(__file__).resolve().parents[1] / "deploy/preproc_mode.py")
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)


class Bar(bytearray):
    def close(self):
        pass


def invoke(tag, mode, reject=False):
    bar = Bar(control.REGION_SIZE)
    control.write32(bar, control.REG_ALGORITHM, tag)
    control.write32(bar, control.REG_MODE, 3)
    control.write32(bar, control.REG_APPLIED_MODE, 3)
    control.user_bar = lambda: (bar, "mock BAR")
    sys.argv = ["preproc_mode.py", mode]
    try:
        with contextlib.redirect_stdout(io.StringIO()) as output:
            control.main()
    except RuntimeError:
        assert reject, (tag, mode)
        assert control.read32(bar, control.REG_MODE) == 3
    else:
        assert not reject, (tag, mode)
        expected = 3 if mode == "status" else control.MODES[mode]
        assert control.read32(bar, control.REG_MODE) == expected
        assert "mode requested:" in output.getvalue()


for mode in ("gray", "gauss", "clahe", "gauss-clahe", "sobel", "blackhat", "status"):
    invoke(control.ENHANCE_TAG, mode)
    invoke(control.ENHANCE2_TAG, mode)
for mode in ("sobel-clahe", "blackhat-clahe"):
    invoke(control.ENHANCE2_TAG, mode)
    for tag in (control.ENHANCE_TAG, control.CLAHE_TAG, 0):
        invoke(tag, mode, reject=True)
for mode in ("sobel", "blackhat"):
    invoke(control.CLAHE_TAG, mode, reject=True)
    invoke(0, mode, reject=True)
invoke(control.CLAHE_TAG, "clahe")
invoke(0, "gauss")
print("PASS EHP2 combinations, EHP1/CLH1 compatibility, unsupported modes rejected before write")
