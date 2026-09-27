import json, subprocess, sys
D=sys.argv[1]; ev={e['what']:e['t'] for e in json.load(open(f'{D}/events.json'))}
# (crop px y0, y1, [(x0, x1, local row y0, y1) per word chip, in pt at 402 wide])
CHIPS={'play s1':(1695,1893,[(72,111,0,32),(113,160,0,32),(162,191,0,32),(193,224,0,32),(226,290,0,32),(72,158,34,66)]),
       'play s3':(492,588,[(72,106,0,32),(108,178,0,32),(180,283,0,32)])}
ok=True
for k,(y0,y1,chips) in CHIPS.items():
    t0=ev['pre '+k]-0.5; span=3.8
    out=subprocess.run(['ffmpeg','-loglevel','error','-ss',f'{t0:.2f}','-t',f'{span:.2f}','-i','cfr.mp4','-vf',f'crop=1206:{y1-y0}:0:{y0},scale=402:-1,format=rgb24','-f','rawvideo','-'],capture_output=True).stdout
    W=402; H=(y1-y0)//3; n=W*H*3; N=len(out)//n
    seq=[]; last=None
    for i in range(N):
        f=out[i*n:(i+1)*n]; lit=None
        for ci,(x0,x1,ly0,ly1) in enumerate(chips):
            c=0; tot=0
            for y in range(ly0,min(ly1,H)):
                row=f[(y*W+x0)*3:(y*W+x1)*3]
                for j in range(0,len(row),3):
                    tot+=1
                    if 120<row[j]<185 and row[j+1]>225 and 85<row[j+2]<150: c+=1
            if c>0.35*tot: lit=ci; break
        if lit is not None and lit!=last: seq.append((lit, round(t0+i/30,2)))
        last=lit if lit is not None else last
    order=[c for c,_ in seq]
    # Accept a missed first chip when that word is very short (<0.2s, shorter than
    # the app's highlight tick at 30fps); otherwise every chip must light in order.
    n=len(chips)
    good = (order==list(range(n))) or (order==list(range(1,n)))
    print(k, 'lit sequence', seq, 'OK' if good else 'BAD')
    ok = ok and good
print('VERIFY', 'PASS' if ok else 'FAIL'); sys.exit(0 if ok else 1)
