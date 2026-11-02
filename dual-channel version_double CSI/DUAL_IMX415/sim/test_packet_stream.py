"""Exercise DMA boundaries, JPEG marker framing and captured STR3 fragments."""
from io import BytesIO
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'rk'))
from dual_csi_protocol import HEADER, PacketStream, parse_packet


def packet(frame=1, tile=0, jpeg=None):
    if jpeg is None:
        # APP data deliberately contains both an EOI and a valid DJP2 header.
        embedded = HEADER.pack(b'DJP2', 2, 32, 99, 1, tile, 0, 85,
                               1920, 1080, 360, 8, 1, 0, 0)
        app = b'x\xff\xd9'+embedded
        jpeg = (b'\xff\xd8\xff\xe1'+(len(app)+2).to_bytes(2, 'big')+app+
                b'\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00'+
                b'abc\xff\x00DJP2def\xff\xd0ghi\xff\xff\xd9')
    return HEADER.pack(b'DJP2', 2, 32, frame, 0, tile, 0, 85,
                       1920, 1080, 360, 8, 1, 0, frame)+jpeg


class PacketStreamTests(unittest.TestCase):
    def test_every_boundary_and_one_byte_reads(self):
        raw = packet()
        for split in range(len(raw)+1):
            stream = PacketStream(1)
            self.assertEqual(stream.feed(raw[:split])+stream.feed(raw[split:]), [raw])
            self.assertEqual(stream.invalid_packets, 0)
            self.assertEqual(stream.discarded_bytes, 0)
        stream = PacketStream(1)
        result = []
        for value in raw:
            result.extend(stream.feed(bytes([value])))
        self.assertEqual(result, [raw])
        self.assertEqual(stream.buffer, b'')

    def test_coalesced_and_headless_start(self):
        stream = PacketStream(1)
        expected = [packet(n) for n in range(5)]
        self.assertEqual(stream.feed(b'headless\xff\xd9'+b''.join(expected)), expected)
        self.assertEqual(stream.discarded_bytes, 10)
        self.assertEqual(stream.complete_packets, 5)

    def test_invalid_channel_header_and_missing_eoi(self):
        good = packet()
        for bad in (packet(tile=1), b'DJP2'+bytes(30),
                    packet(jpeg=b'\xff\xd8\xff\xe1\x00\x01'),
                    packet(jpeg=b'\xff\xd8\xff\xda\x00\x02abcdef')):
            stream = PacketStream(1)
            self.assertEqual(stream.feed(bad+good), [good])
            self.assertGreater(stream.invalid_packets, 0)
            self.assertGreater(stream.discarded_bytes, 0)

    def test_bound_and_resync(self):
        stream = PacketStream(1, max_jpeg_bytes=128)
        oversized = packet(jpeg=b'\xff\xd8\xff\xe1\x02\x00'+b'x'*300)
        good = packet()
        self.assertEqual(stream.feed(oversized+good*5), [good]*5)
        self.assertLessEqual(stream.max_buffered_bytes, 160)
        self.assertGreater(stream.invalid_packets, 0)
        self.assertEqual(stream.buffer, b'')

    def test_multiple_scans_and_segment_split(self):
        jpeg = (b'\xff\xd8\xff\xda\x00\x02a\xff\x00b'+
                b'\xff\xc4\x00\x05xyz\xff\xda\x00\x02c\xff\xd9')
        raw = packet(jpeg=jpeg)
        stream = PacketStream(1)
        result = []
        for offset in range(0, len(raw), 3):
            result.extend(stream.feed(raw[offset:offset+3]))
        self.assertEqual(result, [raw])

    def test_saved_board_fragments(self):
        folder = ROOT/'build/board_test_str3_20261025/rk_results/switch_retry_60'
        if not folder.exists():
            self.skipTest('STR3 raw board evidence not installed')
        from PIL import Image
        for head, tail, channel, camera, frame in (
                (5, 7, 1, 0, 1128), (6, 8, 2, 0, 1128),
                (10, 14, 2, 1, 1304), (11, 12, 1, 1, 1304)):
            first = (folder/f'bad_packet_{head:02d}_ch{channel}.bin').read_bytes()
            second = (folder/f'bad_packet_{tail:02d}_ch{channel}.bin').read_bytes()
            stream = PacketStream(channel)
            # Each pair contains a headless tail, one complete JPEG, then
            # another camera's JPEG split over the two reads. A JPEG decoder
            # alone would ignore the trailing packet and miss this distinction.
            packets = stream.feed(first)+stream.feed(second)
            self.assertEqual(len(packets), 2)
            tiles = [parse_packet(raw, channel) for raw in packets]
            self.assertEqual([(t.camera, t.frame_id) for t in tiles],
                             [(camera, frame), (1-camera, frame)])
            for tile in tiles:
                with Image.open(BytesIO(tile.jpeg)) as image:
                    image.load()
                    self.assertEqual(image.size, (1920, 360))
            self.assertGreater(stream.diagnostics()['discarded_bytes'], 0)
            self.assertEqual(stream.invalid_packets, 0)
            self.assertEqual(stream.buffer, b'')


if __name__ == '__main__':
    unittest.main()
