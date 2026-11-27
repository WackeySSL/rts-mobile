import sys, os, json, time
sys.path.insert(0,'/tmp/p655/docs/proto/p655/tools')
from build655 import *
OUTP=SC5+'final/'; os.makedirs(OUTP,exist_ok=True)
p653=json.load(open(pipeline.SC+'numbers.json'))
def bb(im):
    b=im.getchannel('A').point(lambda v:255 if v>8 else 0).getbbox(); return (b[2]-b[0]+2)*(b[3]-b[1]+2)
res={}
for dens,f in (('1x',8),('2x',4)):
    t0=time.time(); size=[]; area=0; 
    for d in range(16):
        for part in ('hull','turret'):
            im=frame(f'{RAW5}heavy_tank_{part}_d{d:02d}.png',f,SIG)
            fn=f'{OUTP}tank_{dens}_{part}_d{d:02d}.png'; im.save(fn,optimize=True)
            size.append(os.path.getsize(fn)); area+=bb(im)
    sh=p653[f'tank_{dens}']['shadow_texels']
    res[dens]=dict(png_kb_total_hull_turret=sum(size)/1024, png_kb_per_frame_mean=sum(size)/len(size)/1024, png_kb_per_frame_max=max(size)/1024,
        tight_texels_hull_turret=area, shadow_texels=sh, atlas_mb_with_shadow=(area+sh)*4/1e6, post_seconds=time.time()-t0)
res['p653_ref']=dict(atlas_1x=p653['tank_1x'], png_1x=p653['tank_1x']['png_bytes'])
print(json.dumps(res,indent=1))
json.dump(res,open(SC5+'numbers.json','w'),indent=1)
