import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "rk"))
from dual_control import decode_stream_diagnostics


class StreamDiagnosticsTests(unittest.TestCase):
    def test_legacy_does_not_claim_new_diagnostics(self):
        self.assertIsNone(decode_stream_diagnostics(None))

    def test_bridge_lanes_and_first_fault_layout(self):
        flags = 1 | (3 << 1) | (4 << 4) | (1 << 9) | (5 << 10) | (15 << 13)
        detail = (8 << 28) | (2 << 24) | (479 << 14) | (359 << 4) | 1
        decoded = decode_stream_diagnostics([
            0x53545231, 0b010101, detail, 16384, flags, 258944, 258900, 123, 0
        ])
        self.assertEqual(decoded["bridge_fault_lanes"], 5)
        self.assertEqual(decoded["packer_fault_lanes"], 2)
        self.assertTrue(decoded["bridge_causes"][0]["fifo_full"])
        self.assertTrue(decoded["bridge_causes"][1]["bad_eol"])
        self.assertTrue(decoded["bridge_causes"][2]["unexpected_sof"])
        self.assertEqual(decoded["tile_c_fault_line"], 359)
        self.assertEqual(decoded["tile_c_fault_beat"], 479)
        self.assertEqual(decoded["first_fault"], {
            "cause": "axi_read_last", "read_state": 4, "write_state": 0,
            "camera": 1, "slot": 5, "read_beat": 15, "rresp": 0, "rlast": False,
            "bresp": 0, "read_word_index": 258944, "output_word_index": 258900,
            "frame_id": 123,
        })

    def test_reset_guard_and_invalid_first_fault(self):
        decoded = decode_stream_diagnostics([
            0x53545231, 0, 0, 16384, 0, 9, 7, 123, (35 << 16) | (7 << 8) | 0x7b
        ])
        self.assertIsNone(decoded["first_fault"])
        guard = decoded["ddr_guard"]
        self.assertTrue(guard["write_active"])
        self.assertTrue(guard["read_active"])
        self.assertTrue(guard["abort_write"])
        self.assertTrue(guard["abort_read"])
        self.assertFalse(guard["write_done"])
        self.assertEqual(guard["write_beat"], 7)
        self.assertEqual(guard["aborted_transactions"], 35)


if __name__ == "__main__":
    unittest.main()
