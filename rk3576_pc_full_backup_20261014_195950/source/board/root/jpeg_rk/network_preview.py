"""MJPEG preview sampled from final HDMI sink buffers, with independent encoding."""
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
    return ''


class Preview:
    def __init__(self, pipeline, Gst):
        self.Gst = Gst
        self.pipeline = pipeline
        self.condition = threading.Condition()
        self.clients = 0
        self.sequence = 0
        self.latest = None
        self.raw = None
        self.hdmi_frames = self.selected_frames = self.raw_sequence = 0
        self.feed_sequence = 0
        self.pending_metadata = {}
        self.error = None
        self.encoder = None
        self.server_started = False
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
                    if owner.error:
                        self.send_error(503, 'HDMI preview encoder unavailable')
                        return
                    if owner.clients >= 2:
                        self.send_error(503, 'Preview client limit reached')
                        return
                    owner.clients += 1
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
                        stamp, data, hdmi_frame, source_pts = packet
                        header = (f'--rkframe\r\nContent-Type: image/jpeg\r\n'
                                  f'Content-Length: {len(data)}\r\n'
                                  f'X-Sequence: {sequence}\r\nX-RK-Time: {stamp:.6f}\r\n'
                                  f'X-HDMI-Frame: {hdmi_frame}\r\nX-Source-PTS: {source_pts}\r\n\r\n')
                        self.wfile.write(header.encode()+data+b'\r\n')
                        self.wfile.flush()
                except (OSError, ValueError):
                    pass
                finally:
                    with owner.condition:
                        owner.clients -= 1
                        if not owner.clients:
                            owner.latest = None
                            owner.raw = None

        try:
            self.server = ThreadingHTTPServer(('0.0.0.0', 8766), Handler)
        except OSError as exc:
            self.running = False
            print('Network preview unavailable: '+str(exc), flush=True)
            return
        self.server.daemon_threads = True
        try:
            self.encoder = Gst.parse_launch(
                'appsrc name=preview_input is-live=true format=time block=false '
                'max-buffers=1 max-bytes=0 leaky-type=downstream do-timestamp=true '
                '! queue max-size-buffers=1 max-size-bytes=0 max-size-time=0 leaky=downstream '
                '! videoscale method=0 ! video/x-raw,width=960,height=540 '
                '! videoconvert ! video/x-raw,format=GRAY8 '
                '! jpegenc quality=80 ! appsink name=preview_jpeg sync=false async=false '
                'max-buffers=1 drop=true enable-last-sample=false')
            self.source = self.encoder.get_by_name('preview_input')
            self.sink = self.encoder.get_by_name('preview_jpeg')
            display_sink = pipeline.get_by_name('fps').get_property('video-sink')
            self.hdmi_pad = display_sink.get_static_pad('sink')
            self.probe = self.hdmi_pad.add_probe(Gst.PadProbeType.BUFFER, self.hdmi_frame)
            if self.encoder.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
                raise RuntimeError('Preview encoder could not start')
        except Exception as exc:
            self.error = str(exc)
            self.running = False
            self.server.server_close()
            print('HDMI network preview unavailable: '+str(exc), flush=True)
            return
        self.write_state()
        self.server_started = True
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        threading.Thread(target=self.feed, daemon=True).start()
        threading.Thread(target=self.collect, daemon=True).start()
        print('Network preview ready: final HDMI sink RGBx frames -> MJPEG 960x540 @ 15 fps', flush=True)

    def hdmi_frame(self, pad, info):
        self.hdmi_frames += 1
        if not self.running or not self.clients or self.error:
            return self.Gst.PadProbeReturn.OK
        try:
            caps = pad.get_current_caps()
            valid, numerator, denominator = caps.get_structure(0).get_fraction('framerate')
            stride = max(1, (numerator+15*denominator-1)//(15*denominator)) if valid else 4
            if self.hdmi_frames % stride:
                return self.Gst.PadProbeReturn.OK
            buffer = info.get_buffer()
            # Shallow buffer copy retains owned pixel memory. Only preview metadata
            # changes; encoding and network writes never run on the HDMI thread.
            flags = (self.Gst.BufferCopyFlags.FLAGS | self.Gst.BufferCopyFlags.TIMESTAMPS |
                     self.Gst.BufferCopyFlags.META | self.Gst.BufferCopyFlags.MEMORY)
            snapshot = (buffer.copy_region(flags, 0, buffer.get_size()),
                        caps.copy(), self.hdmi_frames, buffer.pts)
            with self.condition:
                self.raw = snapshot
                self.raw_sequence += 1
                self.selected_frames += 1
                self.condition.notify_all()
        except Exception as exc:
            self.error = str(exc)
        return self.Gst.PadProbeReturn.OK

    def feed(self):
        configured = None
        while self.running:
            with self.condition:
                changed = self.condition.wait_for(lambda: self.raw_sequence != self.feed_sequence
                                                  or not self.running, timeout=.5)
                if not self.running:
                    return
                if not changed:
                    continue
                snapshot = self.raw
                self.feed_sequence = self.raw_sequence
            if snapshot is None:
                continue
            buffer, caps, hdmi_frame, source_pts = snapshot
            try:
                description = caps.to_string()
                if description != configured:
                    self.source.set_property('caps', caps)
                    configured = description
                buffer.pts = self.encoder.get_clock().get_time()-self.encoder.get_base_time()
                buffer.dts = self.Gst.CLOCK_TIME_NONE
                with self.condition:
                    self.pending_metadata[buffer.pts] = (hdmi_frame, source_pts)
                    while len(self.pending_metadata) > 16:
                        self.pending_metadata.pop(next(iter(self.pending_metadata)))
                result = self.source.emit('push-buffer', buffer)
                if result != self.Gst.FlowReturn.OK:
                    raise RuntimeError('Preview input failed: '+str(result))
            except Exception as exc:
                self.error = str(exc)
                return

    def write_state(self):
        temporary = STATE.with_suffix('.tmp')
        temporary.write_text(json.dumps({'pid': os.getpid(), 'token': self.token,
            'port': 8766, 'width': 960, 'height': 540, 'fps_limit': 15,
            'source': 'final_hdmi_sink', 'hdmi_frames': self.hdmi_frames,
            'selected_frames': self.selected_frames, 'error': self.error,
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
                    hdmi_frame, source_pts = self.pending_metadata.pop(buffer.pts, (None, None))
                    self.latest = (time.monotonic(), packet, hdmi_frame, source_pts)
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
        if hasattr(self, 'hdmi_pad'):
            self.hdmi_pad.remove_probe(self.probe)
        with self.condition:
            self.condition.notify_all()
        if hasattr(self, 'server'):
            if self.server_started:
                self.server.shutdown()
            self.server.server_close()
        if self.encoder:
            self.encoder.set_state(self.Gst.State.NULL)
        try:
            if json.loads(STATE.read_text()).get('pid') == os.getpid():
                STATE.unlink()
        except (OSError, ValueError):
            pass
