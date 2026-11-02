"""Archive public engineering references used by the STR5 proposal."""
import argparse
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import urllib.request

SOURCES = {
    'zipcpu_master': 'https://zipcpu.com/blog/2021/06/28/master-examples.html',
    'zipcpu_axi_limits': 'https://zipcpu.com/blog/2020/06/16/axiaddr-limits.html',
    'zipcpu_axiperf': 'https://zipcpu.com/blog/2021/08/14/axiperf.html',
    'handshake': 'https://fpgacpu.ca/fpga/handshake.html',
    'kernel_dmaengine': 'https://www.kernel.org/doc/html/latest/driver-api/dmaengine/client.html',
    'axi_vdma': 'https://docs.amd.com/r/en-US/pg020_axi_vdma/Triple-Buffering',
    'verilog_axi': 'https://github.com/alexforencich/verilog-axi',
    'projectf_framebuffer': 'https://projectf.io/posts/framebuffers/',
    'projectf_double_buffer': 'https://projectf.io/posts/animated-shapes/',
    'zipcpu_video': 'https://zipcpu.com/blog/2022/02/23/axis-video.html',
}


class Text(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.skip = 0
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'):
            self.skip += 1
        if tag in ('p', 'div', 'h1', 'h2', 'h3', 'li', 'pre', 'tr', 'br'):
            self.parts.append('\n')

    def handle_endtag(self, tag):
        if tag in ('script', 'style'):
            self.skip = max(0, self.skip-1)
        if tag in ('p', 'div', 'h1', 'h2', 'h3', 'li', 'pre', 'tr'):
            self.parts.append('\n')

    def handle_data(self, data):
        if not self.skip:
            self.parts.append(data)


parser = argparse.ArgumentParser()
parser.add_argument('source', choices=SOURCES)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]/'docs'/'STR5_RESEARCH_20261025'/'sources'
root.mkdir(parents=True, exist_ok=True)
url = SOURCES[args.source]
record = dict(url=url, accessed_utc=datetime.now(timezone.utc).isoformat())
try:
    request = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(request, timeout=22) as response:
        data = response.read()
        record.update(status=response.status, final_url=response.url,
                      content_type=response.headers.get('Content-Type'))
    record.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
    root.joinpath(args.source+'.html').write_bytes(data)
    parsed = Text()
    parsed.feed(data.decode('utf-8', errors='replace'))
    content = '\n'.join(line.strip() for line in ''.join(parsed.parts).splitlines() if line.strip())
    root.joinpath(args.source+'.txt').write_text(content, encoding='utf-8')
    record['text_chars'] = len(content)
    print(content[:1100])
except Exception as exc:
    record['error'] = str(exc)
finally:
    root.joinpath(args.source+'.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
    print(json.dumps(record))
