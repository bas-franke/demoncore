"""Summarise Godot's local-debugger script profiler output (godot -d --profiling ...).

Usage: python tools/perf/profile_top.py <stdout capture> [N]
Averages the second half of the run (warm state) and lists the top N functions by self time, in ms
per rendered frame. "calls" is calls per frame (3 physics ticks per frame when the game is slow).
"""
import re,collections,sys
lines=open(sys.argv[1],encoding='utf-8',errors='replace').read().split('\n')
frames=[i for i,l in enumerate(lines) if l.startswith('FRAME:')]
if not frames:
    sys.exit('no FRAME lines: was the game started with -d --profiling?')
start=frames[len(frames)//2]
self_t=collections.Counter(); tot_t=collections.Counter(); calls=collections.Counter()
nf=0; cur=None; ftot=0; fscript=0
for l in lines[start:]:
    if l.startswith('FRAME:'):
        nf+=1
        m=re.search(r'total: ([\d.]+) script: ([\d.]+)',l)
        if m: ftot+=float(m.group(1)); fscript+=float(m.group(2))
        continue
    m=re.match(r'\d+:(.*)$',l)
    if m: cur=m.group(1); continue
    m=re.search(r'total: ([\d.]+)/.*self: ([\d.]+)/.*tcalls: (\d+)',l)
    if m and cur:
        tot_t[cur]+=float(m.group(1)); self_t[cur]+=float(m.group(2)); calls[cur]+=int(m.group(3))
print('frames %d  avg frame %.1f ms  script %.1f ms'%(nf,ftot/nf*1000,fscript/nf*1000))
N=int(sys.argv[2]) if len(sys.argv)>2 else 30
print('--- by self (ms/frame)')
for k,v in self_t.most_common(N): print('%7.2f self %7.2f tot %6d calls  %s'%(v/nf*1000,tot_t[k]/nf*1000,calls[k]//nf,k.replace('res://','')))
