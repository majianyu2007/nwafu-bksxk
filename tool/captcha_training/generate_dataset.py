# Pre-generate a fixed dataset to disk (fast training afterwards).
import os, random, string, numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
CHARS=string.digits+string.ascii_uppercase; C2I={c:i for i,c in enumerate(CHARS)}
NCHAR=4; IMG_W,IMG_H=128,48
FD=['/System/Library/Fonts','/System/Library/Fonts/Supplemental','/Library/Fonts']
FONTS=[]
for d in FD:
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.lower().endswith(('.ttf','.ttc','.otf')): FONTS.append(os.path.join(d,f))
FONTS=FONTS[:30]
def rc(lo,hi): return tuple(random.randint(lo,hi) for _ in range(3))
def gen(text):
    im=Image.new('RGB',(IMG_W,IMG_H),rc(210,255));d=ImageDraw.Draw(im)
    for _ in range(random.randint(20,80)): d.point((random.randint(0,IMG_W),random.randint(0,IMG_H)),fill=rc(130,210))
    for _ in range(random.randint(1,4)): d.line([(random.randint(0,IMG_W),random.randint(0,IMG_H)) for _ in range(2)],fill=rc(120,200),width=1)
    cell=IMG_W//NCHAR
    for i,ch in enumerate(text):
        size=random.randint(26,34)
        try: font=ImageFont.truetype(random.choice(FONTS),size) if FONTS else ImageFont.load_default()
        except: font=ImageFont.load_default()
        ci=Image.new('RGBA',(size+8,size+12),(0,0,0,0));cd=ImageDraw.Draw(ci)
        cd.text((4,2),ch,font=font,fill=rc(0,90)+(255,)); ci=ci.rotate(random.uniform(-18,18),expand=1,resample=Image.BICUBIC)
        x=i*cell+random.randint(2,8);y=random.randint(2,8);im.paste(ci,(x,y),ci)
    if random.random()<0.3: im=im.filter(ImageFilter.GaussianBlur(random.uniform(0.3,0.8)))
    return im
def build(n):
    X=np.zeros((n,IMG_H,IMG_W),dtype=np.float32); Y=np.zeros((n,NCHAR),dtype=np.int64)
    for k in range(n):
        t=''.join(random.choice(CHARS) for _ in range(NCHAR))
        X[k]=(np.asarray(gen(t).convert('L'),dtype=np.float32)/255.0-0.5)/0.5
        Y[k]=[C2I[c] for c in t]
    return X,Y
random.seed(0)
import sys
ntr=int(sys.argv[1]) if len(sys.argv)>1 else 40000
Xtr,Ytr=build(ntr); Xva,Yva=build(2000)
np.savez_compressed('/tmp/captcha_data.npz',Xtr=Xtr,Ytr=Ytr,Xva=Xva,Yva=Yva)
print("saved",ntr,"train +2000 val")
