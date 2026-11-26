import numpy as np
from PIL import Image, ImageDraw
SC='/tmp/claude-0/-home-user-rts-mobile/f4088c2f-7ea6-5710-9456-77d97126fbd5/scratchpad/p653/'
im=np.asarray(Image.open(SC+'raw/grid_check.png').convert('RGBA')).astype(int)
H,W=im.shape[:2]; ax,ay=516,150; N=8
yy,xx=np.mgrid[0:H,0:W]
# expected label from IsoProjection: ground point of the pixel (art px, ground plane z=0)
u=((xx-ax)/64.0+(yy-ay)/32.0)/2.0; v=((yy-ay)/32.0-(xx-ax)/64.0)/2.0
inside=(u>=0)&(u<N)&(v>=0)&(v<N)
i=np.floor(u).astype(int); j=np.floor(v).astype(int)
exp_red=((i+j)%2==0)
isred=(im[...,0]>150)&(im[...,2]<100)&(im[...,3]>200)
isblue=(im[...,2]>150)&(im[...,0]<100)&(im[...,3]>200)
cube=(im[...,1]>150)&(im[...,0]<100)&(im[...,2]<100)
# the cube covers part of the diamond; compare outside it, and away from tile borders (+-1 px)
du=np.abs(u-np.round(u))*64; dv=np.abs(v-np.round(v))*64
away=(np.minimum(du,dv)>1.5)
m=inside&away&~cube&(isred|isblue)
ok=(isred==exp_red)&m
print('diamond px compared',m.sum(),'matching',ok.sum(),'rate %.5f'%(ok.sum()/m.sum()))
print('diamond px not covered by a colour (inside, away from cube/borders):',int((inside&away&~cube&~(isred|isblue)).sum()))
ys,xs=np.nonzero(cube)
top=ys.min()
print('cube top y',top,'expected', (3+3)*32+ay-78.38367,'; cube x range',xs.min(),xs.max(),'expected',ax+(3-4)*64,ax+(4-3)*64)
# overlay: expected tile outlines on the render for the committed PNG
base=Image.open(SC+'raw/grid_check.png').convert('RGBA')
bg=Image.new('RGBA',base.size,(20,24,30,255)); bg.alpha_composite(base)
d=ImageDraw.Draw(bg)
def P(gx,gy): return (ax+(gx-gy)*64, ay+(gx+gy)*32)
for k in range(N+1):
    d.line([P(k,0),P(k,N)],fill=(255,255,255,255),width=1)
    d.line([P(0,k),P(N,k)],fill=(255,255,255,255),width=1)
bg.crop((0,60,1032,60+N*64+150)).save(SC+'grid_overlay.png')
