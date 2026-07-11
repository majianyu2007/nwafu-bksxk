import os, string, numpy as np, torch, torch.nn as nn
torch.set_num_threads(8)
from torch.utils.data import TensorDataset, DataLoader
CHARS=string.digits+string.ascii_uppercase; NC=len(CHARS); NCHAR=4; IMG_W,IMG_H=128,48
d=np.load('/tmp/captcha_data.npz')
Xtr=torch.from_numpy(d['Xtr']).unsqueeze(1); Ytr=torch.from_numpy(d['Ytr'])
Xva=torch.from_numpy(d['Xva']).unsqueeze(1); Yva=torch.from_numpy(d['Yva'])
tr=DataLoader(TensorDataset(Xtr,Ytr),batch_size=256,shuffle=True,num_workers=0)
va=DataLoader(TensorDataset(Xva,Yva),batch_size=500,num_workers=0)
class Net(nn.Module):
    def __init__(s):
        super().__init__()
        def blk(i,o): return nn.Sequential(nn.Conv2d(i,o,3,1,1),nn.BatchNorm2d(o),nn.ReLU(),nn.Conv2d(o,o,3,1,1),nn.BatchNorm2d(o),nn.ReLU(),nn.MaxPool2d(2))
        s.cnn=nn.Sequential(blk(1,64),blk(64,128),blk(128,256)); s.pool=nn.AdaptiveAvgPool2d((3,8))
        s.heads=nn.ModuleList([nn.Linear(256*3*8,NC) for _ in range(NCHAR)]); s.drop=nn.Dropout(0.3)
    def forward(s,x):
        f=s.cnn(x);f=s.pool(f);f=s.drop(f.flatten(1)); return torch.stack([h(f) for h in s.heads],1)
m=Net();opt=torch.optim.Adam(m.parameters(),lr=1.5e-3);ce=nn.CrossEntropyLoss()
sched=torch.optim.lr_scheduler.CosineAnnealingLR(opt,T_max=int(os.environ.get('EPOCHS','40')))
EP=int(os.environ.get('EPOCHS','40'))
best=0
for ep in range(EP):
    m.train()
    for im,lb in tr:
        out=m(im);loss=sum(ce(out[:,k,:],lb[:,k]) for k in range(NCHAR))/NCHAR
        opt.zero_grad();loss.backward();opt.step()
    sched.step()
    m.eval();cor=0;tot=0;cc=0;ct=0
    with torch.no_grad():
        for im,lb in va:
            pr=m(im).argmax(2);cor+=(pr==lb).all(1).sum().item();tot+=lb.size(0);cc+=(pr==lb).sum().item();ct+=lb.numel()
    wacc=cor/tot
    print(f"ep{ep} loss {loss.item():.3f} word {wacc:.3f} char {cc/ct:.3f}",flush=True)
    if wacc>best:
        best=wacc; torch.save(m.state_dict(),'/tmp/captcha_net.pt')
print("best word-acc",best,flush=True)
# export best
m.load_state_dict(torch.load('/tmp/captcha_net.pt'));m.eval()
torch.onnx.export(m,torch.randn(1,1,IMG_H,IMG_W),'/tmp/captcha.onnx',input_names=['image'],output_names=['logits'],
    dynamic_axes={'image':{0:'batch'},'logits':{0:'batch'}},opset_version=17)
import onnx as _onnx
_mm=_onnx.load('/tmp/captcha.onnx'); _mm.ir_version=9; _onnx.save(_mm,'/tmp/captcha.onnx')
open('/tmp/captcha_charset.txt','w').write(CHARS)
print(f"exported best model, charset={NC} img={IMG_W}x{IMG_H} nchar={NCHAR}",flush=True)
