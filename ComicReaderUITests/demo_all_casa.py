# Cut for the "play every bubble" flow: events start, tap bubble 1, play s1, step k / play bk..., close card 2, next page, end.
import json, subprocess, sys
D=sys.argv[1]; OUT=sys.argv[2] if len(sys.argv)>2 else 'demo-all.mp4'
ev={e['what']:e['t'] for e in json.load(open(f'{D}/events.json'))}
import os
CFR=f'{D}/cfr.mp4' if os.path.exists(f'{D}/cfr.mp4') else 'cfr.mp4'
E='/private/tmp/comigo-demo/casa/comic-la_casa_en_la_colina/audio'
BOT=(1797,1893); TOP=(492,588); TOP2=(492,690)
PLAYS={'play s1':(f'{E}/el_superviviente_p3_s1_b1_t1.mp3',1.52,BOT,[(72,128,0,32,0),(130,201,0,32,600),(203,250,0,32,929),(252,302,0,32,1148)]),
       'play b2':(f'{E}/el_superviviente_p3_s1_b2_t1.mp3',2.96,TOP,[(72,148,0,32,0)]),
       'play b3':(f'{E}/el_superviviente_p3_s1_b3_t1.mp3',4.96,TOP2,[(72,106,0,32,0),(108,144,0,32,320),(146,209,0,32,520),(211,280,0,32,880),(282,321,0,32,2361),(72,141,34,66,2574)]),
       'play b4':(f'{E}/el_superviviente_p3_s1_b4_t1.mp3',4.48,TOP,[(72,154,0,32,0),(156,247,0,32,1198),(249,290,0,32,2211)])}
STEP_ROW={'step 2':None,'step 3':TOP,'step 4':TOP}
order=['start','tap bubble 1','play s1','step 2','play b2','step 3','play b3','step 4','play b4','close card 2','next page','end']
dur=float(subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',CFR],capture_output=True,text=True).stdout)
def frames(t0,t1,crop,w=40):
    vf=(f'crop=1206:{crop[1]-crop[0]}:0:{crop[0]},' if crop else '')+f'scale={w}:-1'
    out=subprocess.run(['ffmpeg','-loglevel','error','-ss',f'{t0:.2f}','-t',f'{t1-t0:.2f}','-i',CFR,'-vf',vf+',format=rgb24','-f','rawvideo','-'],capture_output=True).stdout
    h=round(w*((crop[1]-crop[0]) if crop else 2622)/1206); n=w*h*3
    return [out[i*n:(i+1)*n] for i in range(len(out)//n)], w, h
def visual_onset(t0,t1,crop=None,thresh=4.0):
    fr,w,h=frames(t0,t1,crop)
    for i in range(1,len(fr)):
        d=sum(abs(a-b) for a,b in zip(fr[i],fr[i-1]))/(w*h*3)
        if d>thresh: return t0+i/30
    return None
def chip_onset(k):
    f,l,crop,chips=PLAYS[k]; t0=ev.get('pre '+k, ev[k]-1.5)-0.3; t1=ev[k]+2.5
    fr,w,h=frames(t0,t1,crop,w=402)
    for i,f_ in enumerate(fr):
        for x0,x1,ly0,ly1,ms in chips:
            c=tot=0
            for y in range(ly0,min(ly1,h)):
                row=f_[(y*w+x0)*3:(y*w+x1)*3]
                for j in range(0,len(row),3):
                    tot+=1
                    if 120<row[j]<185 and row[j+1]>225 and 85<row[j+2]<150: c+=1
            if c>0.35*tot: return t0+i/30, ms
    return None
# Where each line's speech really ends: trailing silence (or a stray tail after a
# long gap) shouldn't hold the clip. Audio is trimmed there too.
def speech_end(f, total):
    out=subprocess.run(['ffmpeg','-i',f,'-af','silencedetect=n=-36dB:d=0.25','-f','null','-'],capture_output=True,text=True).stderr
    import re
    starts=[float(x) for x in re.findall(r'silence_start: ([0-9.]+)',out)]; ends=[float(x) for x in re.findall(r'silence_end: ([0-9.]+)',out)]
    end=total
    for st,en in zip(starts,ends):
        if en-st>=1.5: end=st; break
    if starts and (len(starts)>len(ends) or starts[-1]>=end-0.01) and total-starts[-1]>=0.25: end=min(end,starts[-1])
    return end
SPEECH={k:speech_end(v[0],v[1]) for k,v in PLAYS.items()}
for k,v in SPEECH.items(): print('%-8s speech ends %.2fs of %.2fs'%(k,v,PLAYS[k][1]))
start={}
for k in PLAYS:
    r=chip_onset(k)
    if r: start[k]=r[0]-r[1]/1000; print('%-8s first lit chip %.2f (word @%dms) -> start %.2f'%(k,r[0],r[1],start[k]))
    else: start[k]=ev.get('pre '+k, ev[k]-0.3)+0.12; print(k,'no chip seen; using tap stamp')
for k,row in STEP_ROW.items():
    v=visual_onset(ev[k]-0.3, ev[k]+1.8, crop=row, thresh=(6.0 if row is None else 1.5))
    print('%-7s mark %.2f -> seen %s'%(k,ev[k],('%.2f'%v) if v else 'none')); ev[k]=v or ev[k]
HOLD=0.55
cuts=[]
for a,b in zip(order,order[1:]):
    ta,tb=ev[a],ev[b]
    if a in PLAYS: ta=start[a]
    if b in PLAYS: tb=start[b]
    if a=='start': need=0.5
    elif a in PLAYS: need=SPEECH[a]+0.45                   # move on soon after the spoken part
    elif a.startswith('step'): need=0.6+HOLD
    elif a=='close card 2': need=HOLD
    elif a=='next page': need=99
    else: need=0.45+HOLD
    if tb-ta > need+0.15: cuts.append((ta+need, tb-0.12))
slide=visual_onset(ev['next page']+0.3, ev['next page']+6.0, thresh=6.0)
cuts.append((ev['next page']+0.15, (slide-0.15) if slide else ev['next page']+0.82)); cuts.sort()
keep=[]; pos=max(0.0, ev['tap bubble 1']-0.55)
for c0,c1 in cuts:
    if c0>pos: keep.append((pos,c0))
    pos=max(pos,c1)
if slide and slide>pos:
    keep.append((pos,slide-0.02)); keep.append((slide-0.02,slide+0.45,2.6)); keep.append((slide+0.45,min(dur,slide+1.05)))
    print('page slide seen at %.2f -> slowed 2.6x'%slide)
else: keep.append((pos,dur))
def newt(t):
    out=0.0
    for seg in keep:
        k0,k1=seg[0],seg[1]; f=seg[2] if len(seg)>2 else 1.0
        if t<k0: break
        out+=(min(t,k1)-k0)*f
    return out
total=sum((k[1]-k[0])*(k[2] if len(k)>2 else 1.0) for k in keep); print('kept %.1fs of %.1fs'%(total,dur))
vparts=''.join(f'[0:v]trim=start={k[0]:.3f}:end={k[1]:.3f},setpts={(k[2] if len(k)>2 else 1.0):.2f}*(PTS-STARTPTS)[v{i}];' for i,k in enumerate(keep))
vcat=''.join(f'[v{i}]' for i in range(len(keep)))+f'concat=n={len(keep)}:v=1:a=0,tpad=stop_mode=clone:stop_duration=1.1[vout];'
inputs=['-i',CFR]; aparts=''; amix=''
for i,(k,(f,l,_,_)) in enumerate(PLAYS.items()):
    inputs+=['-i',f]; t=newt(start[k]); print('%-8s audio at %.2fs'%(k,t))
    aparts+=f'[{i+1}:a]atrim=0:{SPEECH[k]+0.15:.2f},aformat=sample_rates=44100:channel_layouts=stereo,adelay={int(t*1000)}|{int(t*1000)}[a{i}];'; amix+=f'[a{i}]'
n=len(PLAYS)
open('filter_casa.txt','w').write(vparts+vcat+aparts+f'anullsrc=r=44100:cl=stereo,atrim=0:{total+1.1:.2f}[sil];'+amix+f'[sil]amix=inputs={n+1}:normalize=0[aout]')
subprocess.run(['ffmpeg','-y','-loglevel','error',*inputs,'-filter_complex_script','filter_casa.txt','-map','[vout]','-map','[aout]','-c:v','libx264','-preset','medium','-crf','17','-pix_fmt','yuv420p','-r','30','-c:a','aac','-b:a','160k','-shortest','-movflags','+faststart',OUT],check=True); print('written',OUT)
