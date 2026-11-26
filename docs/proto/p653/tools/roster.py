import re, glob, json, os
ROOT='/tmp/p653/'
def arr(t,key):
    m=re.search(r'^%s = Packed\w+Array\((.*)\)$'%key,t,re.M)
    return [float(x) for x in m.group(1).split(',')] if m and m.group(1).strip() else []
def s(t,key):
    m=re.search(r'^%s = &?"?([^"\n]*)"?$'%key,t,re.M); return m.group(1) if m else ''
rows=[]
for f in sorted(glob.glob(ROOT+'assets/art/iso/*/*/*_sheet.tres')):
    t=open(f).read()
    parts=re.search(r'^parts = PackedStringArray\((.*)\)$',t,re.M).group(1).replace('"','').split(', ')
    counts=[int(x) for x in arr(t,'counts')]; sizes=[int(x) for x in arr(t,'sizes')]; boxes=[int(x) for x in arr(t,'boxes')]
    fp=int(s(t,'footprint') or 0)
    # texels: frames with a tight box use it, others the whole canvas
    bi=0; tex=0; sh=0; frames=0
    for k,p in enumerate(parts):
        w,h=sizes[2*k],sizes[2*k+1]
        for c in range(counts[k]):
            frames+=1
            if boxes and p in ('hull','turret','head') and fp==0:
                bw,bh=boxes[bi*4+2],boxes[bi*4+3]; bi+=1; a=bw*bh
            else: a=w*h
            if p=='shadow': sh+=a
            else: tex+=a
    rows.append(dict(id=s(t,'art_id'),faction=s(t,'faction'),cat=s(t,'category'),fp=fp,parts=parts,counts=counts,frames=frames,tex=tex,shadow_tex=sh,files=len(os.listdir(os.path.dirname(f)))))
J=json.load(open(ROOT+'docs/art/treadline-batches.json'))
ids=[i for b in J['batches'] for i in b['ids']]
print('art ids in batches:',len(ids),'sheets',len(rows))
units=[r for r in rows if r['cat'] in ('veh','sq','air','inf','unit') or r['fp']==0]
blds=[r for r in rows if r['fp']>0]
from collections import Counter
print(Counter((r['cat'],r['fp']) for r in rows))
tot=sum(r['tex']+r['shadow_tex'] for r in rows)
print('today texels (all sheets, one colour slot): %.2f M => %.1f MB RGBA8'%(tot/1e6,tot*4/1e6))
for r in rows:
    if r['id'] in ('heavy_tank','vehicle_factory','light_tank','rifle_squad','headquarters','fossil_fighter'):
        print(r['id'],r['cat'],r['fp'],r['parts'],r['counts'],'frames',r['frames'],'tex %d + shadow %d => %.2f MB (1x) %.2f MB (2x)'%(r['tex'],r['shadow_tex'],(r['tex']+r['shadow_tex'])*4/1e6,(r['tex']+r['shadow_tex'])*16/1e6))
print('units',len(units),'frames',sum(r['frames'] for r in units),'; buildings',len(blds),'frames',sum(r['frames'] for r in blds))
print('units tex MB 1x %.1f ; buildings tex MB 1x %.1f'%(sum(r['tex']+r['shadow_tex'] for r in units)*4/1e6,sum(r['tex']+r['shadow_tex'] for r in blds)*4/1e6))
json.dump(rows,open('/tmp/claude-0/-home-user-rts-mobile/f4088c2f-7ea6-5710-9456-77d97126fbd5/scratchpad/p653/roster.json','w'))
