"""Stage-1 bars, written BEFORE the numbers were read, and the measurement. Run: python tools/physics/measure.py

BARS (reference: real human push recovery)
 B1  unaided stance 5 s: not fallen, COM drift < 5 cm.                          (the controller works at all)
 B2  small forward chest push, 0.4 x J_hof: recovers IN PLACE (0 steps, no fall), peak trunk-lean excursion <= 20 deg.
     Horak & Nashner 1986 (J Neurophysiol 55:1369): small perturbations are recovered by the ankle strategy with little
     trunk motion; 20 deg is a loose ceiling, not a measured human mean (I did not re-fetch their numbers).
 B3  the largest forward push recovered with stepping DISABLED (in-place limit, bisection, 3 s) lies between 0.3 and 1.0 x
     J_hof (cannot beat the ideal ankle-strategy limit by much; delay + torque limits keep it below) and within a factor 2
     of the Pai & Patton limit.
       J_hof   = M w0 (x_toe - x_com0)   Hof, Gazendam & Sinke 2005, J Biomech 38:1-8: stable while XCoM = x + v/w0 stays
                 inside the base of support, w0 = sqrt(g/l), l = COM height; a push J gives dv = J / M.  (backward: heel)
       J_pp    = M * 0.45 * H * (1 - d/L)   Pai & Patton 1997, J Biomech 30:347-354: the feasible-stability boundary runs
                 from 0.45 /s (normalised to body height H) with the COM over the heel to 0 over the toe, linear in between;
                 d = COM distance from the heel, L = foot length.  (boundary values as returned by the search abstract.)
 B4  strong forward push, 1.6 x J_hof: the controller TAKES A STEP (step_count >= 1); whether it then recovers is reported.
"""
import json
import sys

import numpy as np

import sim

M_HIT_BODY = "spine_03"


def run_hit(body, J, dr, stepping, secs=2.0, settle=1.0, record=None):
    h = sim.make(stepping=stepping)
    for _ in range(int(settle / h.dt)):
        h.step()
    c0 = h.com()
    h.hit(body, J, dr)
    l0 = h.trunk_lean_deg()
    mx = 0.0
    fell = False
    nrec = 0
    for i in range(int(secs / h.dt)):
        h.step()
        mx = max(mx, abs(h.trunk_lean_deg() - l0))
        if record is not None and i % int(round(1 / 60 / h.dt)) == 0:
            record(h)
        if h.fallen():
            fell = True
            break
    moved = float(np.linalg.norm(h.com()[[0, 2]] - c0[[0, 2]]))
    return dict(fell=fell, steps=h.step_count, lean=mx, moved=moved, t_first_step=h.first_step_t)


def inplace_limit(dr, lo=5.0, hi=80.0, n=7):
    def ok(J):
        r = run_hit(M_HIT_BODY, J, dr, stepping=False, secs=3.0)
        return (not r["fell"]) and r["moved"] < 0.10
    for _ in range(n):
        mid = 0.5 * (lo + hi)
        if ok(mid):
            lo = mid
        else:
            hi = mid
    return lo, hi


def main():
    h = sim.make()
    M = h.M
    com0 = h.com()
    H = 1.829
    box = h.foot_box("l"), h.foot_box("r")
    toe = max(b[3] for b in box)
    heel = min(b[2] for b in box)
    # use ONE foot's length/COM offset for Pai & Patton (feet are side by side)
    fl = h.foot_box("l")
    L = fl[3] - fl[2]
    w0 = np.sqrt(sim.G / com0[1])
    x_com = com0[2]
    J_hof_f = M * w0 * (toe - x_com)
    J_hof_b = M * w0 * (x_com - heel)
    d = x_com - fl[2]
    J_pp_f = M * 0.45 * H * max(0.0, 1 - d / L)
    print(f"M {M:.1f} kg, COM height {com0[1]:.3f} m, w0 {w0:.2f} /s, COM z {x_com:+.3f}, toe {toe:+.3f}, heel {heel:+.3f}, foot L {L:.3f}")
    print(f"J_hof fwd {J_hof_f:.1f} N s (dv {J_hof_f/M:.2f} m/s), back {J_hof_b:.1f} N s;  J_pp fwd {J_pp_f:.1f} N s (dv {J_pp_f/M:.2f} m/s)")
    out = {}
    ok, t, drift, *_ = sim.stand_test(5.0)
    out["B1"] = (ok, drift)
    print(f"B1 stand 5 s: ok={ok}, COM drift {100*drift:.1f} cm -> {'PASS' if ok and drift < 0.05 else 'FAIL'}")
    r = run_hit(M_HIT_BODY, 0.4 * J_hof_f, 0, stepping=True)
    p = (not r["fell"]) and r["steps"] == 0 and r["lean"] <= 20
    print(f"B2 small push {0.4*J_hof_f:.1f} N s: {r} -> {'PASS' if p else 'FAIL'}")
    out["B2"] = r
    lo, hi = inplace_limit(0)
    lb, hb = inplace_limit(180, lo=3.0, hi=60.0)
    print(f"B3 in-place limit forward {lo:.1f}..{hi:.1f} N s (dv {lo/M:.2f}..{hi/M:.2f} m/s) = {lo/J_hof_f:.2f}-{hi/J_hof_f:.2f} x J_hof, {lo/J_pp_f:.2f}-{hi/J_pp_f:.2f} x J_pp; backward {lb:.1f}..{hb:.1f} N s = {lb/J_hof_b:.2f}-{hb/J_hof_b:.2f} x J_hof")
    p3 = 0.3 * J_hof_f <= lo <= 1.0 * J_hof_f and 0.5 <= lo / J_pp_f <= 2.0
    print(f"   -> {'PASS' if p3 else 'FAIL'}")
    out["B3"] = (lo, hi, lb, hb)
    # step onset: first impulse (stepping enabled) at which a step is taken
    Jstep = None
    for J in np.arange(0.5, 2.01, 0.25) * J_hof_f:
        r = run_hit(M_HIT_BODY, J, 0, stepping=True, secs=3.0)
        print(f"   step sweep J={J:.1f} ({J/J_hof_f:.2f} x J_hof): {r}")
        if r["steps"] >= 1 and Jstep is None:
            Jstep = J
    print(f"B4 first impulse with a step: {Jstep}")
    r = run_hit(M_HIT_BODY, 1.6 * J_hof_f, 0, stepping=True, secs=3.0)
    print(f"   1.6 x J_hof = {1.6*J_hof_f:.1f} N s: {r} -> {'PASS (stepped)' if r['steps'] >= 1 else 'FAIL'}; recovered={not r['fell']}")
    json.dump({k: str(v) for k, v in out.items()}, open("measure_last.json", "w"))


if __name__ == "__main__":
    main()
