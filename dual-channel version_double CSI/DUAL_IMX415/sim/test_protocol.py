"""Check wire format against RTL output and reject cross-camera pairing."""
from pathlib import Path
import sys,struct,unittest
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'rk'))
from dual_csi_protocol import HEADER,parse_packet,Assembler

def packet(cam=0,frame=1,tile=0,epoch=5):
    return HEADER.pack(b'DJP2',2,32,frame,cam,tile,3,85,1920,1080,360,8,1,epoch,123)+b'\xff\xd8payload\xff\xd9'

class ProtocolTests(unittest.TestCase):
    def test_rtl_header(self):
        t=parse_packet((ROOT/'build/header_packet.djp').read_bytes(),3)
        self.assertEqual((t.camera,t.frame_id,t.tile,t.mode,t.quality,t.epoch,t.timestamp),(1,42,2,3,85,77,123))
    def test_asynchronous_two_cameras(self):
        a=Assembler();done=[]
        for cam,tile in [(1,2),(0,1),(0,0),(1,0),(0,2),(1,1)]:
            group=a.push(parse_packet(packet(cam=cam,tile=tile)))
            if group:done.append(group)
        self.assertEqual([g[0].camera for g in done],[0,1])
        for group in done:self.assertEqual(len({t.group for t in group}),1)
        self.assertFalse(a.pending)
    def test_epoch_mismatch(self):
        a=Assembler();a.push(parse_packet(packet(tile=0)))
        with self.assertRaises(ValueError):a.push(parse_packet(packet(tile=1,epoch=6)))
    def test_corrupt_incompatible(self):
        for data in (b'\xff\xd8oldjpg',packet()[:-1],b'JPG3'+packet()[4:]):
            with self.assertRaises(ValueError):parse_packet(data)
        with self.assertRaises(ValueError):parse_packet(packet(tile=2),1)
    def test_pending_bounded(self):
        a=Assembler(max_pending=2)
        for frame in range(10):a.push(parse_packet(packet(frame=frame)))
        self.assertEqual(len(a.pending),2);self.assertEqual(a.incomplete_drops,8)
    def test_counter_wrap(self):
        a=Assembler()
        for frame in (0xfffffff,0):
            group=None
            for tile in range(3):group=a.push(parse_packet(packet(frame=frame,tile=tile)))
            self.assertIsNotNone(group)
if __name__=='__main__':unittest.main()
