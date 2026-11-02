"""Bit-exact shared preprocessing and raw OBS1 statistics against PC references."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

import cv2
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
BIN=ROOT.parent/'.tools/iverilog/bin'
sys.path.insert(0,str(ROOT.parent/'road_damage_yolov8n/preproc_selector_20261016'))
from reference import blackhat,luma


def write_hex(path,values,width):
    path.write_text(''.join(f'{int(v):0{width}x}\n' for v in values),encoding='ascii')


def packed(im):
    a=im.reshape(-1,4).astype(np.uint32)
    return a[:,0] | (a[:,1]<<8) | (a[:,2]<<16) | (a[:,3]<<24)


def feature_record(gray,case):
    a=gray[:,::16].astype(np.int64)
    b=gray[:,1::16].astype(np.int64)
    n=a.size
    record=(case+1)|((case%2)<<28)|(1<<29)|((case+100)<<32)
    record|=n<<64
    record|=int(a.sum())<<82
    record|=int((a<32).sum())<<107
    record|=int((a>224).sum())<<125
    record|=int(np.abs(a-b).sum())<<143
    for k,count in enumerate(np.bincount((a>>4).ravel(),minlength=16)):
        record|=int(count)<<(168+18*k)
    return record|((case+1)<<456)


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--full',action='store_true')
    p.add_argument('--pause',type=int,default=0)
    args=p.parse_args()
    w,h=(1920,1080) if args.full else (64,24)
    settings=[(2,4),(3,0),(2,4),(3,4),(2,4),(3,2)]
    if args.full: settings=[(1,1),(5,4)]
    prefix=ROOT/'build'/(('preproc_full' if args.full else 'clahe_first_small')+('_paused' if args.pause else ''))
    prefix.parent.mkdir(exist_ok=True)
    rng=np.random.default_rng(20261027)
    rgb_words=[];outputs=[];original=[];features=[]
    for case,(mode,k) in enumerate(settings):
        bgr=rng.integers(0,256,(h,w,3),dtype=np.uint8)
        if case==8:
            bgr[:]=180
            bgr[:,w//3:w//3+1]=25
            bgr[h//2,:]=12
            for t in range(min(h,w)): bgr[t,t]=30
            bgr[0,:]=0;bgr[-1,:]=255
        gray=luma(bgr)
        total=cv2.sepFilter2D(gray,cv2.CV_16U,np.array([1,2,1]),np.array([1,2,1]),borderType=cv2.BORDER_REPLICATE)
        gaussian=((total+8)//16).astype(np.uint8)
        result=(blackhat(gray) if mode==5 else
                np.rint((gray.astype(np.float32)*(4-k)+gaussian.astype(np.float32)*k)/4).astype(np.uint8) if mode in (1,3) else gray)
        words=(bgr[:,:,0].astype(np.uint32)|(bgr[:,:,1].astype(np.uint32)<<8)|
               (bgr[:,:,2].astype(np.uint32)<<16)).reshape(-1,4)
        rgb_words.extend(sum(int(v)<<(32*i) for i,v in enumerate(row)) for row in words)
        original.extend(packed(gray));outputs.extend(packed(result))
        features.append(feature_record(gray,case))
    for suffix,values,width in [('rgb',rgb_words,32),('raw',original,8),('out',outputs,8),
                                ('features',features,128),('settings',[(k<<4)|m for m,k in settings],2)]:
        write_hex(prefix.with_name(prefix.name+'_'+suffix+'.hex'),values,width)
    exe=prefix.with_suffix('.vvp')
    files=['sim/tb_preproc_lite.sv','rtl/v2_dual_preprocess.v','rtl/v2_feature_observer.v',
           'rtl/v2_async_fifo.v','uisrc/01_rtl/gray_gauss4.v','uisrc/01_rtl/gray_preprocess4.v']
    subprocess.run([str(BIN/'iverilog.exe'),'-g2012','-s','tb_preproc_lite',
        f'-Ptb_preproc_lite.W={w}',f'-Ptb_preproc_lite.H={h}',f'-Ptb_preproc_lite.CASES={len(settings)}',
        f'-Ptb_preproc_lite.PAUSE={args.pause}',
        '-o',str(exe),*files],cwd=ROOT,check=True)
    log=prefix.with_suffix('.log')
    with log.open('w',encoding='utf-8') as handle:
        run=subprocess.run([str(BIN/'vvp.exe'),'-i',str(exe),'+prefix='+prefix.as_posix()],
                           cwd=ROOT,stdout=handle,stderr=subprocess.STDOUT,timeout=1800)
    print(log.read_text())
    if run.returncode: raise SystemExit(run.returncode)
    prefix.with_suffix('.json').write_text(json.dumps(dict(width=w,height=h,settings=settings,
        pixel_exact=True,features_before_enhancement=True),indent=2),encoding='utf-8')


if __name__=='__main__': main()
