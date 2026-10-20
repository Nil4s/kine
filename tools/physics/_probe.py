import numpy as np, sim
def run(body,J,dr,step,secs=2.0,settle=1.0):
    h=sim.make(stepping=step)
    for _ in range(int(settle/h.dt)): h.step()
    h.hit(body,J,dr)
    l0=h.trunk_lean_deg(); mx=0; c0=h.com()
    n=int(secs/h.dt); fell=False
    for i in range(n):
        h.step(); mx=max(mx,abs(h.trunk_lean_deg()-l0))
        if h.fallen(): fell=True;break
    return fell,h.step_count,mx,np.linalg.norm(h.com()[[0,2]]-c0[[0,2]])
import sys
for body,dr in [("spine_03",0),("spine_03",180)]:
  for J in [10,20,30,40,50,60,80]:
    for st in (False,True):
        r=run(body,J,dr,st); print(body,dr,J,"step" if st else "nostep",r,flush=True)
