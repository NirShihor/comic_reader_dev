import json, subprocess, sys
D=sys.argv[1]; ev={e['what']: e['t'] for e in json.load(open(f'{D}/events.json'))}
E='/Users/nirshihor/coding/comic-generator/server/projects/comic-9832e1ed/export/la_biblioteca/audio'
audio={'play s1':(f'{E}/el_préstamo_p7_s1_b2_t1.mp3',2.0),'play seguro':(f'{E}/words/seguro.mp3',1.44),
       'play s3':(f'{E}/el_préstamo_p7_s3_b4_t1.mp3',2.4),'play lugar':(f'{E}/words/lugar.mp3',1.04)}
dur=float(subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0','cfr.mp4'],capture_output=True,text=True).stdout)
HOLD=0.55; REACT={'more':0.85+0.5,'done sheet':0.6,'step bubble 2':0.35,'tap bubble 3':0.6,'close card 2':0.0,'next page':3.0}
order=['start','tap bubble 1','play s1','translation 1','tap seguro','play seguro','step bubble 2','tap bubble 3','play s3','translation 2','tap lugar','play lugar','more','done sheet','close card 2','next page','end']
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
cuts=[]
for a,b in zip(order,order[1:]):
    ta,tb=ev[a],ev[b]
    ta = start.get(a, ta) if a in audio else ta
    tb = start.get(b, tb) if b in audio else tb
    need = (audio[a][1]+0.35 if a in audio else REACT.get(a,0.45)) + HOLD
    if a=='start': need=0.5
    if tb-ta > need+0.15: cuts.append((ta+need, tb-0.12))
# The finger drag itself takes ~1s before the page slides: trim the static part of it.
cuts.append((ev['next page']+0.15, ev['next page']+0.82)); cuts.sort()
keep=[]; pos=max(0.0, ev['tap bubble 1']-0.55)
for c0,c1 in cuts:
    if c0>pos: keep.append((pos,c0))
    pos=max(pos,c1)
keep.append((pos,dur))
def newt(t):
    out=0.0
    for k0,k1 in keep:
        if t<k0: break
        out += min(t,k1)-k0
    return out
total=sum(k1-k0 for k0,k1 in keep); print('kept %.1fs of %.1fs'%(total,dur))
vparts=''.join(f'[0:v]trim=start={a:.3f}:end={b:.3f},setpts=PTS-STARTPTS[v{i}];' for i,(a,b) in enumerate(keep))
vcat=''.join(f'[v{i}]' for i in range(len(keep)))+f'concat=n={len(keep)}:v=1:a=0,tpad=stop_mode=clone:stop_duration=0.6[vout];'
inputs=['-i','cfr.mp4']; aparts=''; amix=''
for i,(k,(f,l)) in enumerate(audio.items()):
    inputs+=['-i',f]; t=newt(start[k]); print('%-12s %.2fs'%(k,t))
    aparts+=f'[{i+1}:a]aformat=sample_rates=44100:channel_layouts=stereo,adelay={int(t*1000)}|{int(t*1000)}[a{i}];'; amix+=f'[a{i}]'
n=len(audio)
open('filter.txt','w').write(vparts+vcat+aparts+f'anullsrc=r=44100:cl=stereo,atrim=0:{total+0.6:.2f}[sil];'+amix+f'[sil]amix=inputs={n+1}:normalize=0[aout]')
subprocess.run(['ffmpeg','-y','-loglevel','error',*inputs,'-filter_complex_script','filter.txt','-map','[vout]','-map','[aout]','-c:v','libx264','-preset','medium','-crf','17','-pix_fmt','yuv420p','-r','30','-c:a','aac','-b:a','160k','-shortest','-movflags','+faststart','demo.mp4'],check=True); print('written demo.mp4')
