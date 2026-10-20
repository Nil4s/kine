import numpy as np, sim, sys
J=float(sys.argv[1]); dr=float(sys.argv[2])
h=sim.make(stepping=True)
for _ in range(500): h.step()
h.hit("spine_03",J,dr)
for i in range(1000):
    h.step()
    if i%50==0:
        c=h.com();v=h.vcom();xc,w=h.xcom_of(c,v)
        print(f"t{h.d.time:.2f} {h.phase:5s} com {c[0]:+.3f} {c[2]:+.3f} xcom {xc[0]:+.3f} {xc[1]:+.3f} lean {h.trunk_lean_deg():+.1f} footL {h.d.xpos[h.bid['foot_l']].round(2)} footR {h.d.xpos[h.bid['foot_r']].round(2)} swing {h.swing} ref {h.ref_xz.round(3)}")
    if h.fallen(): print("fell");break
