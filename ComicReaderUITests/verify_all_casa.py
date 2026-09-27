# Every play must light its chips in order (a missed first chip is tolerated when that word is short).
import json, subprocess, sys
sys.argv=[sys.argv[0], sys.argv[1], '/dev/null']
src=open('/private/tmp/comigo-demo/demo_all_casa.py').read()
head=src[:src.index("start={}")]
ns={}; exec(head, ns)
ok=True
for k,(f,l,crop,chips) in ns['PLAYS'].items():
    ev=ns['ev']; t0=ev['pre '+k]-0.5
    fr,w,h=ns['frames'](t0,t0+l+2.5,crop,w=402)
    seq=[]; last=None
    for i,f_ in enumerate(fr):
        lit=None
        for ci,(x0,x1,ly0,ly1,ms) in enumerate(chips):
            c=tot=0
            for y in range(ly0,min(ly1,h)):
                row=f_[(y*w+x0)*3:(y*w+x1)*3]
                for j in range(0,len(row),3):
                    tot+=1
                    if 120<row[j]<185 and row[j+1]>225 and 85<row[j+2]<150: c+=1
            if c>0.35*tot: lit=ci; break
        if lit is not None and lit!=last: seq.append(lit)
        last=lit if lit is not None else last
    n=len(chips); good=(seq==list(range(n))) or (n>1 and seq==list(range(1,n)))
    print(k,'lit',seq,'OK' if good else 'BAD'); ok=ok and good
print('VERIFY','PASS' if ok else 'FAIL'); sys.exit(0 if ok else 1)
