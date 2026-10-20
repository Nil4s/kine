"""Bars for swing.py, written BEFORE the numbers were read. Run: python tools/physics/measure_swing.py  (about 4 min)

Real references (cited from memory, NOT re-fetched this run; treat as order-of-magnitude):
  Walilko, Viano & Bir 2005, Br J Sports Med 39:710 (Olympic boxers, Hybrid III head): mean peak force ~3.4 kN, fist speed ~9 m/s,
      effective striking mass ~2.9 kg -> momentum ~26 N s.
  Smith, Dyson, Hale & Janaway 2000, J Sports Sci 18:445 (boxing dynamometer): punch peak forces of order 2-5 kN.
  strike contact durations 10-20 ms (the brief); a bat tip at the sweet spot swings at 30-35 m/s in baseball hitters (Nathan 2003).
BARS
 S1  fist (weapon off, hand+forearm strike) DOMINANT pulse: impulse 10-45 N s, FWHM 5-25 ms, peak 1-5 kN.
 S2  bat DOMINANT pulse: impulse <= m_eff v bound with m_eff <= 6 kg at the sim's barrel speed (reported, no human range exists); barrel speed
     at impact within 20-40 m/s.
 S3  tracking: sim barrel speed peak within 15 % of the clip's own peak.
 S4  location: the head-hit clip gives a larger peak head angular velocity than a trunk-hit clip, and the trunk-hit clip a larger trunk lean
     than the head-hit clip (head snaps vs body bends), same weapon.
 S5  timescale sensitivity: scaling the contact omega_n x0.5 / x2 moves the impulse by < 25 % (the impulse is momentum, not the solver)
     and moves peak force and duration by > 40 % (those are the solver's).
"""
import os
import sys

import numpy as np

import swing

CLIPS = ["swing_fore", "swing_back", "combo3", "strike_legs"]


def line(r):
    p = r["pulses"][r["dom"]]
    return (f"{r['clip']:11s} {'bat ' if r['weapon'] else 'fist'} n_pulses {r['n_pulses']} dom@{p['t0']:.3f}s {p['body']:11s} J {p['impulse_Ns']:5.1f} N s "
            f"peak {p['peak_N']:6.0f} N  FWHM {p['fwhm_ms']:5.1f} ms (base {p['base_ms']:5.1f})  v_at_hit {r['speed_at_hit']:4.1f} m/s  "
            f"head w {r['head_w_peak']:5.1f} rad/s  neck {r['neck_peak_deg']:4.1f} deg  trunk lean {r['lean_signed']:+5.1f} deg  head {r['head_acc_g']:4.1f} g  fell {r['fell']}")


def main():
    res = {}
    for c in CLIPS:
        for wp in (True, False):
            r = swing.run(c, weapon=wp, keep_states=False)
            if r["n_pulses"] == 0:
                print(c, "bat" if wp else "fist", "NO CONTACT")
                continue
            res[(c, wp)] = r
            print(line(r), flush=True)
    print("-- sensitivity of the contact timescale (swing_fore, bat)")
    for sc in (0.5, 1.0, 2.0):
        r = swing.run("swing_fore", True, tc=swing.TC / sc, dr=swing.DR, keep_states=False)
        p = r["pulses"][r["dom"]]
        print(f"  omega x{sc}: J {p['impulse_Ns']:.1f} N s  peak {p['peak_N']:.0f} N  FWHM {p['fwhm_ms']:.1f} ms")
    print("-- location (swing_fore, bat) by offset of the aim (dx, dz) m")
    for off in [(0.0, 0.0), (0.0, -0.15), (0.0, 0.15), (0.2, 0.0), (-0.2, 0.0)]:
        r = swing.run("swing_fore", True, offset=off, keep_states=False)
        if r["n_pulses"]:
            print(f"  offset {off}: " + line(r))
        else:
            print(f"  offset {off}: no contact")


if __name__ == "__main__":
    main()
