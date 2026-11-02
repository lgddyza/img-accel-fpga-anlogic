import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'rk'))
from dual_control import decode_store_diagnostics, read_store_diagnostics


class DiagnosticsTests(unittest.TestCase):
    def test_address_order_and_legacy(self):
        addresses = []
        def read(offset):
            addresses.append(offset)
            return 0
        self.assertIsNone(read_store_diagnostics(read, 0x53545234))
        self.assertEqual(addresses, [])
        self.assertIsNone(read_store_diagnostics(read, 0x53545235))
        self.assertEqual(addresses, list(range(0x500, 0x5c0, 4)) + list(range(0x600, 0x624, 4)))

    def test_layout_and_64_bit_bytes(self):
        words = list(range(48))
        words[0] = 0x44353031
        words[37] = 1 | (1 << 1) | (1 << 6) | (1 << 9) | (4 << 10) | (2 << 13) | (1 << 15)
        words[41] = 235 | (5 << 10) | (2 << 20)
        words[43] = 2 | (3 << 16)
        result = decode_store_diagnostics(words, [0xfffffff0, 2, 123, 1, 0, 20, 2, 1, 30])
        self.assertEqual(result['drops']['new_sof_interrupt'], [13, 14])
        self.assertEqual(result['counters']['r_beats'], 18)
        self.assertEqual(result['first_drop']['causes'], ['no_free', 'new_sof_interrupt'])
        self.assertEqual(result['first_drop']['camera'], 1)
        self.assertEqual(result['first_drop']['slot'], 4)
        self.assertEqual(result['read_buffered'], 235)
        self.assertEqual(result['read_reserved'], 5)
        self.assertEqual(result['read_outstanding'], 2)
        self.assertEqual(result['ready_peaks'], [2, 3])
        self.assertEqual(result['dma'][0], dict(bytes=0x2fffffff0, packets=123))

    def test_invalid_schema_rejected(self):
        with self.assertRaises(ValueError):
            decode_store_diagnostics([1]*48, [0]*9)


if __name__ == '__main__':
    unittest.main()
