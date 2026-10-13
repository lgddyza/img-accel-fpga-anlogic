"""Generate deterministic OpenCV reference pixels for RTL stream verification."""
import json
from pathlib import Path

import cv2
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
from enhancement_reference import line_filter


def sobel_exact(image):
    raw=image.astype(np.int32)
    gx=cv2.Sobel(image,cv2.CV_16S,1,0,ksize=3,borderType=cv2.BORDER_REPLICATE).astype(np.int32)
    gy=cv2.Sobel(image,cv2.CV_16S,0,1,ksize=3,borderType=cv2.BORDER_REPLICATE).astype(np.int32)
    total=cv2.boxFilter(image,cv2.CV_32F,(3,3),normalize=False,borderType=cv2.BORDER_REPLICATE).astype(np.int32)
    detail=np.clip(9*raw-total,-288,288)
    gate=np.clip(np.abs(gx)+np.abs(gy)-8,0,96)
    numerator=raw*1728+detail*gate
    quotient=numerator//1728
    remainder=numerator%1728
    rounded=quotient+((remainder>864)|((remainder==864)&((quotient&1)!=0)))
    return np.clip(rounded,0,255).astype(np.uint8)


def main():
    output=ROOT/'sim/enhance_vectors'
    output.mkdir(exist_ok=True)
    w,h=32,16
    modes=[0,1,2,3,4,5,6,7,4,5,0,3,1,6,7,2,3]
    rng=np.random.default_rng(20261009)
    images=[]
    for frame,mode in enumerate(modes):
        if frame%4==0:
            yy,xx=np.indices((h,w));image=((xx*13+yy*27+frame*9)%256).astype(np.uint8)
        elif frame%4==1:
            image=rng.integers(0,256,(h,w),dtype=np.uint8)
        elif frame%4==2:
            image=np.full((h,w),100,np.uint8);image[:,w//2]=60;image[h//2,:]=65
            image[0,0]=0;image[-1,-1]=255
        else:
            image=np.full((h,w),80,np.uint8);image[1:-1,3]=78;image[h//2,1:-1]=79
        images.append(image)
    inputs=[];expected=[]
    for image,mode in zip(images,modes):
        inputs.extend(image.reshape(-1).tolist())
        if mode in (4,6):
            result=sobel_exact(image)
        elif mode in (5,7):
            response=cv2.morphologyEx(image,cv2.MORPH_BLACKHAT,np.ones((3,3),np.uint8),
                                      borderType=cv2.BORDER_REPLICATE)
            response=line_filter(response,5)
            result=np.clip(image.astype(np.int16)-response,0,255).astype(np.uint8)
        else:
            result=image
        expected.extend(result.reshape(-1).tolist())
    (output/'input.hex').write_text('\n'.join(f'{v:02x}' for v in inputs)+'\n',encoding='ascii')
    (output/'expected.hex').write_text('\n'.join(f'{v:02x}' for v in expected)+'\n',encoding='ascii')
    (output/'modes.hex').write_text('\n'.join(f'{v:x}' for v in modes)+'\n',encoding='ascii')
    (output/'manifest.json').write_text(json.dumps({'width':w,'height':h,'modes':modes,
        'pixels':len(inputs),'opencv':cv2.__version__,'blackhat_kernel':3,'blackhat_gain':1,
        'reference':'OpenCV enhancement pixels followed by independent Gaussian/CLAHE RTL'},indent=2))
    print('Prepared',len(images),'frames,',len(inputs),'pixels')


if __name__=='__main__':main()
