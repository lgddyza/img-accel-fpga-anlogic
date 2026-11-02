"""Check the STR3 BAR packing independently of the HDL implementation."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'rk'))
from dual_control import decode_performance, read_performance
from analyze_performance import interval


class PerformanceTests(unittest.TestCase):
    def test_packed_lane_and_fault_bits(self):
        # Deliberately cross the 32-bit boundary with the third 12-bit lane.
        reserved = 13 | (480 << 12) | (1920 << 24)
        peak = 100 | (2000 << 12) | (2040 << 24)
        pipe = list(range(12)) + [reserved & 0xffffffff, reserved >> 32,
                                 peak & 0xffffffff, (peak >> 32) | 0x30]
        result = decode_performance(pipe, list(range(12)))
        self.assertEqual(result['reserved_groups'], [13, 480, 1920])
        self.assertEqual(result['peak_groups'], [100, 2000, 2040])
        self.assertTrue(result['line_fault'])
        self.assertTrue(result['credit_fault'])
        self.assertEqual(result['pipeline']['ddr_response_wait'], 11)
        self.assertEqual(result['jpeg'][2], dict(accepted_pixels=6, input_wait=7,
                                              output_wait=8, dma_wait=11))

    def test_address_map_and_old_revision(self):
        addresses = []
        def read(offset):
            addresses.append(offset)
            return 0
        self.assertIsNone(read_performance(read, 0x53545232))
        self.assertEqual(addresses, [])
        read_performance(read, 0x53545233)
        self.assertEqual(addresses, list(range(0x400, 0x440, 4)) +
                         list(range(0x480, 0x4b0, 4)))
        addresses.clear()
        read_performance(read, 0x53545234)
        self.assertEqual(addresses, list(range(0x400, 0x440, 4)) +
                         list(range(0x480, 0x4b0, 4)))

    def test_short_sample_rejected(self):
        with self.assertRaises(ValueError):
            decode_performance([0]*15, [0]*12)

    def test_counter_wrap_and_reset(self):
        before = decode_performance([0]*16, [0]*12)
        after = decode_performance([0]*16, [0]*12)
        before['pipeline']['tick'] = 0xffffffff-100
        after['pipeline']['tick'] = (before['pipeline']['tick']+133333333) & 0xffffffff
        after['pipeline']['processed_groups'] = 518400*120
        result = interval(dict(t=1, performance=before), dict(t=2, performance=after))
        self.assertAlmostEqual(result['pipeline_frame_equivalents_per_s']['processed_groups'], 120, places=5)
        after['pipeline']['tick'] = 0
        self.assertIsNone(interval(dict(t=1, performance=before), dict(t=2, performance=after)))


if __name__ == '__main__':
    unittest.main()
