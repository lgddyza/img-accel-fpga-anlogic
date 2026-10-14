"""Bounded MJPEG branch from the existing HDMI pipeline, enabled by a client."""
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import threading
import time

STATE = Path('/run/rk-network-preview.json')


def branch():
    return (' preview_tee. ! queue max-size-buffers=1 max-size-bytes=0 '
            'max-size-time=0 leaky=downstream ! valve name=preview_gate drop=true '
            '! identity sleep-time=66667 ! videoscale method=0 '
            '! video/x-raw,format=GRAY8,width=960,height=540 '
            '! jpegenc quality=80 ! appsink name=preview_jpeg sync=false async=false '
            'max-buffers=1 drop=true enable-last-sample=false')


class Preview:
    def __init__(self, pipeline, Gst):
        self.Gst = Gst
        self.gate = pipeline.get_by_name('preview_gate')
        self.sink = pipeline.get_by_name('preview_jpeg')
        self.condition = threading.Condition()
        self.clients = 0
        self.sequence = 0
        self.latest = None
        self.running = True
        self.token = secrets.token_urlsafe(32)
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = 'HTTP/1.1'

            def log_message(self, *_):
                pass

            def do_GET(self):
                if self.path != '/stream' or not hmac.compare_digest(
                        self.headers.get('Authorization', ''), 'Bearer '+owner.token):
                    self.send_error(403)
                    return
                self.connection.settimeout(3)
                with owner.condition:
                    if owner.clients >= 2:
                        self.send_error(503, 'Preview client limit reached')
                        return
                    owner.clients += 1
                    owner.gate.set_property('drop', False)
                try:
                    self.send_response(200)
                    self.send_header('Content-Type', 'multipart/x-mixed-replace; boundary=rkframe')
                    self.send_header('Cache-Control', 'no-store')
                    self.send_header('Connection', 'close')
                    self.end_headers()
                    sequence = -1
                    while owner.running:
                        with owner.condition:
                            changed = owner.condition.wait_for(lambda: owner.sequence != sequence
                                                               or not owner.running, timeout=2)
                            sequence = owner.sequence
                            packet = owner.latest if changed else None
                        if packet is None:
                            self.wfile.write(b'\r\n')
                            self.wfile.flush()
                            continue
                        stamp, data = packet
                        header = (f'--rkframe\r\nContent-Type: image/jpeg\r\n'
                                  f'Content-Length: {len(data)}\r\n'
                                  f'X-Sequence: {sequence}\r\nX-RK-Time: {stamp:.6f}\r\n\r\n')
                        self.wfile.write(header.encode()+data+b'\r\n')
                        self.wfile.flush()
                except (OSError, ValueError):
                    pass
                finally:
                    with owner.condition:
                        owner.clients -= 1
                        if not owner.clients:
                            owner.gate.set_property('drop', True)
                            owner.latest = None

        try:
            self.server = ThreadingHTTPServer(('0.0.0.0', 8766), Handler)
        except OSError as exc:
            self.running = False
            print('Network preview unavailable: '+str(exc), flush=True)
            return
        self.server.daemon_threads = True
        self.write_state()
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        threading.Thread(target=self.collect, daemon=True).start()
        print('Network preview ready: MJPEG 960x540 @ 15 fps, port 8766', flush=True)

    def write_state(self):
        temporary = STATE.with_suffix('.tmp')
        temporary.write_text(json.dumps({'pid': os.getpid(), 'token': self.token,
            'port': 8766, 'width': 960, 'height': 540, 'fps_limit': 15,
            'clients': self.clients, 'frames': self.sequence, 'sample_s': time.monotonic()}))
        temporary.replace(STATE)

    def collect(self):
        next_state = 0
        while self.running:
            sample = self.sink.emit('try-pull-sample', 100_000_000)
            if sample is not None:
                buffer = sample.get_buffer()
                packet = buffer.extract_dup(0, buffer.get_size())
                with self.condition:
                    self.latest = (time.monotonic(), packet)
                    self.sequence += 1
                    self.condition.notify_all()
            if time.monotonic() > next_state:
                try:
                    self.write_state()
                except OSError as exc:
                    print('Preview telemetry: '+str(exc), flush=True)
                next_state = time.monotonic()+1

    def close(self):
        self.running = False
        with self.condition:
            self.condition.notify_all()
        if hasattr(self, 'server'):
            self.server.shutdown()
            self.server.server_close()
        try:
            if json.loads(STATE.read_text()).get('pid') == os.getpid():
                STATE.unlink()
        except (OSError, ValueError):
            pass
