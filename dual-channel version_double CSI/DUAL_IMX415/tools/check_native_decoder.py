"""Run on RK: reject truncated scan data as well as fatal JPEG errors."""
import argparse
import ctypes
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('library', type=Path)
parser.add_argument('sample', type=Path)
args = parser.parse_args()
library = ctypes.CDLL(str(args.library.resolve()))
decode = library.jpeg_decode_gray
decode.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p,
                   ctypes.c_uint, ctypes.c_uint, ctypes.c_void_p, ctypes.c_size_t]
decode.restype = ctypes.c_int
pixels = ctypes.create_string_buffer(1920*360)
error = ctypes.create_string_buffer(256)
good = args.sample.read_bytes()
bad_scan = good[:min(1000, len(good)//2)]+b'\xff\xd9'
results = []
for name, data, width, expected in (
        ('valid', good, 1920, 0), ('truncated_scan', bad_scan, 1920, -2),
        ('malformed', b'not a JPEG', 1920, -1),
        ('wrong_dimensions', good, 1280, -1), ('valid_after_errors', good, 1920, 0)):
    result = decode(data, len(data), pixels, width, 360, error, len(error))
    results.append(dict(case=name, result=result, message=error.value.decode(errors='replace')))
    if result != expected:
        raise SystemExit(json.dumps(results, indent=2))
print(json.dumps(results, indent=2))
print('PASS strict native decoder rejects warning/fatal errors and recovers')
