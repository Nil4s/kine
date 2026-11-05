# CH6b feedback: a two-hand bowline on a simulated rope (PARKED, red)

Branch `w4-ch6b`. Pass 1 `d36e14f4`, pass 2 `93cbc67f` (the parked state). A pass 3 (a different regrip route) was tried in a probe, made things worse, and was reverted before it was committed or run against the bars.

## 1. Result

Suites on the parked commit: ch6b 11/16, ch6 10/16, easypart 73/0, peasy3 23/0, freestart 14/0.

| bar | baseline (577217a5 + merge) | pass 1 | pass 2 (parked) |
|---|---|---|---|
| K1 kinematic grip exact | ok 0.00000 mm | ok | ok |
| S2 C++ = GDScript (kin + adapt) | ok 0.001 mm | ok | ok |
| S3 adaptive substeps ran | ok (7) | ok | ok |
| N1 no self pass, end driven over rope | ok 0.000 r | ok | ok |
| N2 CONTROL contact off | ok 0.315 r | ok | ok |
| P5 expected codes = reference polyline | ok | ok | ok |
| P0 hole | ok | ok | ok |
| P1 UP `1U 2O 1O 2U` | ok | ok | ok |
| P2 DOWN `1U 2O 3U 1O 2U 3O` | FAIL (empty) | FAIL (clasp only) | **ok** |
| P3 ROUND `1U 2O 3U 4O 2U 3O 4U 1O` | FAIL (empty) | FAIL (16 symbols) | FAIL (16 symbols) |
| P4 BACK = bowline | FAIL (empty) | FAIL (22 symbols) | FAIL (18 symbols) |
| PS0 UP self-pen | ok 0.000 r | ok 0.007 r | ok 0.007 r |
| PS1 / PS2 / PS3 self-pen | 0.39 / 0.75 / 0.66 r | 0.32 / 1.53 / 0.77 r | 0.62 / 0.93 / **0.103** r |
| C3 CONTROL tie, contact off | ok 2.0 r | ok | ok 1.98 r |
| ch6 A1-A4 capstan, S1 | ok | ok | ok |
| ch6 T0 pinch on its target | ok 0.30 mm | FAIL 3.97 mm | FAIL 7.22 mm |
| ch6 T1 self-pen whole run | FAIL 0.750 r | FAIL 1.527 r | FAIL 0.930 r |
| ch6 T2 hand-rope pen | FAIL 3.475 r | FAIL 0.341 r | FAIL 0.129 r |
| ch6 T3 code = bowline | FAIL (empty) | FAIL | FAIL |
| ch6 T4 peg winding 1 | FAIL -0.38 | FAIL 0.61 | FAIL 0.61 |
| ch6 H1 no slip | ok 0.40 cm | ok 0.85 cm | ok 1.03 cm (it holds, but it is a tangle, not a bowline) |
| ch6 H2 loop | ok | ok | ok 4.2 % |
| ch6 H3 tightens | ok | FAIL 0.160 -> 0.352 m | FAIL 0.200 -> 0.312 m |
| ch6 H4 tension readout | FAIL 11064 N | **ok 117.3 N** | ok 117.3 N |
| ch6 C1 mu = 0 control | ok 111.6 cm | ok 82.2 cm | ok 82.3 cm |
| ch6 C2 slip-knot control | ok | ok | ok |

The final reduced Gauss code at the end of the tie was `1O 2O 3U 4U 5O 6U 7O 2U 8U 4O 9U 7U 6O 9O 3O 8O 1U 5U` (9 crossings). The bowline reference (Ashley #1010) is `1U 2O 3O 4U 5O 6O 3U 4O 5U 1O 2U 6U` (6 crossings). In the probe the correct ROUND code (the collar round the standing part) existed at frames 350-380 and was lost during regrip 3 (frames 390-430). At P3's own frame (441) it was already gone.

## 2. Engineering level

- **Rope and contact mechanics: L3.**
  - The PBD rope solver exists twice, in C++ and in GDScript, and the two agree to 0.001 mm.
  - Kinematic grips are exact to 0.00000 mm.
  - Adaptive substeps limit any particle's move to r/2 per substep.
  - The capstan law is checked against exp(mu theta) to within 1.5 %.
  - Planted controls (contact off, mu = 0, slip knot) all fail as they should.
  - Not higher: no torsion or twist in the rope, no bending stiffness from a rope datasheet, and the friction value is an assumed 0.4. The 0.3 kg particle mass is quasi-static, not real.
- **Knot topology: L2-L3.**
  - There are per-phase expected codes, checked against the reference polyline (P5), and every phase is measured.
  - Not higher: the "best code" is a greedy Reidemeister I/II reduction minimised over 46 views. It is not a knot invariant. It is view-dependent: P2 failed in pass 1 on a rope that was topologically the same as the reference, because some view reduced one extra crossing. A real invariant for open curves (knotoid or arc-presentation tools) would be needed.
- **Hand manipulation: L1-L2.** The regrip plan was keyed by hand, with no grasp planner. The off hand is not a rig hand (see the gaps).

## 3. What Kine lacked

| needed | exists today | workaround | cost | proposed feature |
|---|---|---|---|---|
| a hand collision shape that fits through a 9 cm hole | `Body.cap("hand_r")` is one capsule, r = 4.5 cm (9 cm thick); G23 says the same | `Ch6Tie.caps_now` uses 4 metacarpal capsules, r = 1.3 cm | 15 lines | a palm made of metacarpal capsules in Body, used by every contact test |
| control of wrist orientation for a grasp | `Body.reach` places only the wrist position; the wrist angles are left as they are | `reach_pinch_clear`: a per-frame search over wrist bend/side/twist for hand-rope clearance | 45 lines, about 7 IK solves per frame | a reach with an approach direction or a clearance cost |
| regrips: release, transit, re-grasp | `Scene.regrip_layered` is for a two-handed weapon grip, not rope (searched; it does not apply) | `Ch6Knot.tie_plan` (keyed legs), an escape search, slip-off on release | 120 lines | a grasp/regrasp planner for deformables (contact-aware transit) |
| a second hand that holds the rope | nothing: the off hand is a set of kinematic particles (crossing, standing part, and the end during a regrip) | kinematic `drive` of about 84 particles | the hand vs held rope is not measured (up to 4 r of the working hand goes through held rope; T2 skips driven segments) | an off-hand rig grip bound to rope particles, with its capsules colliding |
| a topological knot invariant | `Ch6Knot.best_code` (greedy R-I/II over views) | none | P2 false fail in pass 1 | a knotoid / Gauss-diagram canonical form with all moves |
| a rope-tie viewer that shows over and under | `tests/ch6_render_test.gd` (Godot spheres; still draws the old hand_r capsule) | a matplotlib sheet with z-sorted segments (C:/Users/Nick/tools/kine_workers/out/ch6b/tie_sheet.png) | 60 lines of Python | knot-diagram overlay in the rope view |
| robust PBD contact next to kinematic particles | the solver divided by W ~ s^2 | lever guard: skip a contact when W <= 0.01 x max w (C++ and GDScript) | it had made NaN and teleported particles through the held ring | keep the guard; add CCD for kinematic-kinematic pinches |

## 4. What looks wrong (sheet: C:/Users/Nick/tools/kine_workers/out/ch6b/tie_sheet.png, front view, z-sorted)

- **Frames 0-360 read right.**
  - The rabbit comes up through the hole (f60) and goes down in front of the bottom strand (f150-210).
  - It goes behind the standing part and comes back over it in front. The collar code is right at f360.
- **Regrip 3 (f390-480) ruins it.** The empty hand comes back round behind the standing part to the front and drags the leg to the peg and the peg loop up into the hole.
  - At f480-630 the green peg loop is folded across the hole.
  - The tail is doubled through it.
  - The loop no longer goes round the peg (T4 0.61 turns).
- **Compared with a real bowline:** the loop should stay open round the peg, with the collar hugging the standing part under the hole. Here the "knot" is a wad of five crossings more.
- **Regrip transits:** the hand sweeps wide arcs. In the planned transit the fingers still pass through held rope: the off hand is invisible.
- **The parts the bars don't watch:** T2 is green-ish (0.13 r) only because penetration of driven, held rope is not counted.

## 5. What changed (no bar edited; bars K1-PS3 and C3 were committed in 577217a5 before their first run)

- **Merge:** origin/poser-ui-rounds was merged (`tools/run_all.sh` kept both sides) and the native DLL rebuilt.
- **Pass 1:**
  - The palm became metacarpal capsules.
  - The free fingers are fisted (`Body.POSE_FIST`).
  - The standing part, the whole crossing and the bottom strand are held during the tie.
  - The wrist seeks clearance.
  - 4 regrips at waypoints 3, 7, 11 and 17. The tip dwells in `tip_path`, so the waypoint frames and the reference codes are unchanged (P5 ok).
  - The free-end coil is 0.45 m longer, because the tail ran out at frame 170.
  - Release is gentler.
  - The solver got the lever guard (C++ and GDScript).
- **Pass 2:** the empty hand searches its way out of the rope before each transit.
- **Behaviour-only changes:**
  - T0 now measures the pinch against its keyed target, which includes the post-regrip drift and the transit legs. It is no longer strictly the keyed tip path.
  - The layout's tail is longer.

## Park note

- Parked at `93cbc67f` after 2 committed passes. The third idea, routing regrip 3 down and right, was probed and reverted.
- **The blocker is regrip 3:** the hand has to get from behind to in front of the standing part without passing through the leg to the peg, the peg loop or the tail. With an invisible off hand, a one-capsule-chain arm and no grasp planner, every route tried drags one of them.
- **Next:**
  1. A real off-hand rig. It takes the end at regrips 3 and 4, as people actually tie: the hand holding the crossing also catches the end.
  2. A contact-aware transit planner (a sampled path that keeps hand-rope clearance).
  3. Hold the peg loop on the peg (it slides off a half wrap).
