import json, subprocess, sys
D=sys.argv[1]; ev={e['what']:e['t'] for e in json.load(open(f'{D}/events.json'))}
CHIPS={'play s1':(1797,1893,[(72,111),(113,147),(149,178),(180,256)]),
       'play s3':(492,588,[(72,141),(143,184),(186,232),(234,298)])}
ok=True
for k,(y0,y1,chips) in CHIPS.items():
    t0=ev['pre '+k]-0.5; span=3.8
    out=subprocess.run(['ffmpeg','-loglevel','error','-ss',f'{t0:.2f}','-t',f'{span:.2f}','-i','cfr.mp4','-vf',f'crop=1206:{y1-y0}:0:{y0},scale=402:-1,format=rgb24','-f','rawvideo','-'],capture_output=True).stdout
    W=402; H=(y1-y0)//3; n=W*H*3; N=len(out)//n
    seq=[]; last=None
    for i in range(N):
        f=out[i*n:(i+1)*n]; lit=None
        for ci,(x0,x1) in enumerate(chips):
            c=0; tot=0
            for y in range(H):
                row=f[(y*W+x0)*3:(y*W+x1)*3]
                for j in range(0,len(row),3):
                    tot+=1
                    if 120<row[j]<185 and row[j+1]>225 and 85<row[j+2]<150: c+=1
            if c>0.35*tot: lit=ci; break
        if lit is not None and lit!=last: seq.append((lit, round(t0+i/30,2)))
        last=lit if lit is not None else last
    order=[c for c,_ in seq]
    good = order[:4]==[0,1,2,3]
    print(k, 'lit sequence', seq, 'OK' if good else 'BAD')
    ok = ok and good
print('VERIFY', 'PASS' if ok else 'FAIL'); sys.exit(0 if ok else 1)
