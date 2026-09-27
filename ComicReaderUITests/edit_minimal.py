import json, subprocess, sys
D=sys.argv[1]; ev={e['what']: e['t'] for e in json.load(open(f'{D}/events.json'))}
E='/Users/nirshihor/coding/comic-generator/server/projects/comic-9832e1ed/export/la_biblioteca/audio'
audio={'play s1':(f'{E}/el_préstamo_p7_s1_b2_t1.mp3',2.0),'play s3':(f'{E}/el_préstamo_p7_s3_b4_t1.mp3',2.4)}
dur=float(subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0','cfr.mp4'],capture_output=True,text=True).stdout)
HOLD=0.55; REACT={'more':0.85+0.5,'done sheet':0.6,'step bubble 2':0.35,'tap bubble 3':0.6,'close card 2':0.0,'next page':99}
order=['start','tap bubble 1','play s1','step bubble 2','tap bubble 3','play s3','close card 2','next page','end']
# Where each sentence's audio really started: the first word chip that lights up
# green in the card, minus that word's startTimeMs. (Tap marks are unreliable:
# XCUITest delivers/returns taps up to ~1s late while the app animates.)
CHIPS={'play s1':(1797,1893,[(72,111,0),(113,147,827),(149,178,1174),(180,256,1360)]),
       'play s3':(492,588,[(72,141,0),(143,184,1059),(186,232,1423),(234,298,1746)])}
def chip_onset(k):
    y0,y1,chips=CHIPS[k]; t0=ev.get('pre '+k, ev[k]-1.5)-0.3; span=(ev[k]-t0)+2.5
    out=subprocess.run(['ffmpeg','-loglevel','error','-ss',f'{t0:.2f}','-t',f'{span:.2f}','-i','cfr.mp4','-vf',f'crop=1206:{y1-y0}:0:{y0},scale=402:-1,format=rgb24','-f','rawvideo','-'],capture_output=True).stdout
    W=402; H=(y1-y0)//3; n=W*H*3; N=len(out)//n
    for i in range(N):
        f=out[i*n:(i+1)*n]
        for x0,x1,ms in chips:
            c=0; tot=0
            for y in range(H):
                row=f[(y*W+x0)*3:(y*W+x1)*3]
                for j in range(0,len(row),3):
                    tot+=1
                    if 120<row[j]<185 and row[j+1]>225 and 85<row[j+2]<150: c+=1
            if c>0.35*tot: return t0+i/30, ms
    return None
start={}
for k in audio:
    t=ev.get('pre '+k, ev[k]-0.3)+0.12
    if k in CHIPS:
        r=chip_onset(k)
        if r: print('%-12s first lit chip at %.2f = word @%dms -> start %.2f'%(k,r[0],r[1],r[0]-r[1]/1000)); t=r[0]-r[1]/1000
        else: print(k,'no chip onset found; using tap stamp')
    start[k]=t
# Tap marks for the arrow steps are unreliable (the tap can land well after the
# stamp, or the stamp after the tap). Use the first visible change instead.
def visual_onset(t_from, t_to, crop=None, thresh=4.0):
    vf=(f'crop=1206:{crop[1]-crop[0]}:0:{crop[0]},' if crop else '')+'scale=40:-1,format=gray'
    out=subprocess.run(['ffmpeg','-loglevel','error','-ss',f'{t_from:.2f}','-t',f'{t_to-t_from:.2f}','-i','cfr.mp4','-vf',vf,'-f','rawvideo','-'],capture_output=True).stdout
    W=40; Hh=(len(out)//W)  # unknown height: derive per frame from crop
    h=round(40*((crop[1]-crop[0]) if crop else 2622)/1206); n=W*h; N=len(out)//n
    for i in range(1,N):
        d=sum(abs(a-b) for a,b in zip(out[i*n:(i+1)*n],out[(i-1)*n:i*n]))/n
        if d>thresh: return t_from+i/30
    return None
s2=visual_onset(ev['step bubble 2']-0.4, ev['step bubble 2']+1.6) or ev['step bubble 2']
b3=visual_onset(s2+0.7, ev['tap bubble 3']+1.6, crop=(492,588), thresh=1.5) or ev['tap bubble 3']
print('step bubble 2 mark %.2f -> seen %.2f | tap bubble 3 mark %.2f -> seen %.2f'%(ev['step bubble 2'],s2,ev['tap bubble 3'],b3))
ev['step bubble 2']=s2; ev['tap bubble 3']=b3
cuts=[]
for a,b in zip(order,order[1:]):
    ta,tb=ev[a],ev[b]
    ta = start.get(a, ta) if a in audio else ta
    tb = start.get(b, tb) if b in audio else tb
    need = (audio[a][1]+0.35 if a in audio else REACT.get(a,0.45)) + HOLD
    if a=='play s1': need = audio[a][1]+0.45          # move on to the last bubble quicker (half the gap)
    if a=='step bubble 2': need = 0.45
    if a=='start': need=0.5
    if tb-ta > need+0.15: cuts.append((ta+need, tb-0.12))
# The finger drag itself takes ~1s before the page slides: trim the static part of it.
_slide=visual_onset(ev['next page']+0.3, ev['next page']+6.0, thresh=6.0)
cuts.append((ev['next page']+0.15, (_slide-0.15) if _slide else ev['next page']+0.82)); cuts.sort()
keep=[]; pos=max(0.0, ev['tap bubble 1']-0.55)
for c0,c1 in cuts:
    if c0>pos: keep.append((pos,c0))
    pos=max(pos,c1)
# Page turn: slow the app's 0.35s push to half speed, and hold the new page longer.
slide=visual_onset(ev['next page']+0.3, ev['next page']+6.0, thresh=6.0)   # after the mark: the drag takes ~1-2s to land
if slide and slide>pos:
    # after the slide, keep 0.6s of the new page (tpad adds the rest of the hold)
    keep.append((pos,slide-0.02)); keep.append((slide-0.02,slide+0.45,2.6)); keep.append((slide+0.45,min(dur,slide+1.05)))
    print('page slide seen at %.2f -> slowed 2.6x'%slide)
else:
    keep.append((pos,dur))
def newt(t):
    out=0.0
    for seg in keep:
        k0,k1=seg[0],seg[1]; f=seg[2] if len(seg)>2 else 1.0
        if t<k0: break
        out += (min(t,k1)-k0)*f
    return out
total=sum((k[1]-k[0])*(k[2] if len(k)>2 else 1.0) for k in keep); print('kept %.1fs of %.1fs'%(total,dur))
vparts=''.join(f'[0:v]trim=start={k[0]:.3f}:end={k[1]:.3f},setpts={(k[2] if len(k)>2 else 1.0):.2f}*(PTS-STARTPTS)[v{i}];' for i,k in enumerate(keep))
vcat=''.join(f'[v{i}]' for i in range(len(keep)))+f'concat=n={len(keep)}:v=1:a=0,tpad=stop_mode=clone:stop_duration=1.1[vout];'
inputs=['-i','cfr.mp4']; aparts=''; amix=''
for i,(k,(f,l)) in enumerate(audio.items()):
    inputs+=['-i',f]; t=newt(start[k]); print('%-12s %.2fs'%(k,t))
    aparts+=f'[{i+1}:a]aformat=sample_rates=44100:channel_layouts=stereo,adelay={int(t*1000)}|{int(t*1000)}[a{i}];'; amix+=f'[a{i}]'
n=len(audio)
open('filter.txt','w').write(vparts+vcat+aparts+f'anullsrc=r=44100:cl=stereo,atrim=0:{total+1.1:.2f}[sil];'+amix+f'[sil]amix=inputs={n+1}:normalize=0[aout]')
subprocess.run(['ffmpeg','-y','-loglevel','error',*inputs,'-filter_complex_script','filter.txt','-map','[vout]','-map','[aout]','-c:v','libx264','-preset','medium','-crf','17','-pix_fmt','yuv420p','-r','30','-c:a','aac','-b:a','160k','-shortest','-movflags','+faststart','demo-minimal.mp4'],check=True); print('written demo-minimal.mp4')
