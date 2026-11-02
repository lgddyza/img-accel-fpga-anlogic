"""Create a small grayscale crack crop as RGB simulation input, preserving frame geometry."""
from pathlib import Path
from PIL import Image

root=Path(__file__).resolve().parents[1]
src=root.parent/'RK_DUAL_YOLO_CLA9_20261028/verification/live_fixed_20261029/hdmi_1080/mode_0.pgm'
image=Image.open(src).convert('L').crop((480,150,544,174))
if image.size != (64,24): raise RuntimeError('Unexpected crop geometry')
image.save(root/'build/audit_crack_input_20261029.png')
pixels=list(image.getdata())
lines=[]
for i in range(0,len(pixels),4):
    packed=sum((int(pixels[i+j])*0x010101) << (32*j) for j in range(4))
    lines.append(f'{packed:032x}\n')
(root/'build/audit_crack_rgb_20261029.hex').write_text(''.join(lines)*9,encoding='ascii')
print('Generated 64x24 crop',src,flush=True)
