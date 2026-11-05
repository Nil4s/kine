# CH6b feedback: a two-hand bowline on a simulated rope (PARKED, red)

Branch `w4-ch6b`. The shared `HandShape` collision model is active. After three measured fix passes, the scripts were restored to the best HandShape run (`9108457a`, restored at `b19040b5`); no bar was edited.

## 1. Result

Best HandShape run: **ch6b 11/16, ch6 12/16**, hand 15/0, easypart 73/0, peasy3 23/0, freestart 14/0. The other suites stayed green in all three passes. Native rope was rebuilt after merging `origin/poser-ui-rounds`; the #209 KCad DLL was also present.

| measure | parked before HandShape (`93cbc67f`) | HandShape, restored best |
|---|---:|---:|
| T0 pinch target | FAIL 7.22 mm | **ok 0.38 mm** |
| T1 / PS0 UP self-penetration | 0.930 / 0.007 r | FAIL 1.516 / **ok 0.000 r** |
| PS1 DOWN | 0.620 r | **FAIL 1.516 r** |
| PS2 ROUND | 0.930 r | **FAIL 1.285 r** |
| PS3 BACK | 0.103 r | **ok 0.014 r** |
| T2 hand-rope | FAIL 0.129 r | **FAIL 3.160 r** |
| T4 peg winding | FAIL 0.61 turns | **FAIL 0.48 turns** |
| H1 judged slip | ok 1.03 cm | ok 1.38 cm |
| H2 loop change | ok 4.2 % | ok 1.2 % |
| H3 seating | FAIL 0.200 -> 0.312 m | **ok 0.216 -> 0.136 m** |
| H4 tension | ok 117.3 N | ok 117.4 N |

The planted controls remain valid: N2 and C3 penetrate with self-contact off; ch6 C1 slips with mu = 0 and C2 rejects the slip knot. K1, S2, S3, N1, P0, P1 and P5 pass.

### Codes at the measured phases (restored best)

| phase | reduced code | verdict |
|---|---|---|
| hole | empty | ok |
| UP f43 | `1U 2O 1O 2U` | ok |
| DOWN f189 | empty | FAIL; expected `1U 2O 3U 1O 2U 3O` |
| ROUND f441 | empty | FAIL; expected `1U 2O 3U 4O 2U 3O 4U 1O` |
| BACK f630 | `1O 2U 3U 2O 4U 1U 4O 3O` | FAIL, 4 crossings |
| end of tie (ch6 T3) | `1O 2U 3U 4O 2O 5U 1U 5O 3O 4U` | FAIL, 5 crossings |
| Ashley #1010 reference | `1U 2O 3O 4U 5O 6O 3U 4O 5U 1O 2U 6U` | 6 crossings |

The front-view contact sheet still has the correct ROUND code at f360 and its mirror at f400. It is lost later in regrip 3, before the measured ROUND endpoint. Thus the final rope is not a bowline even though the loaded loop holds.

## 2. Engineering level

- **Rope and contact mechanics: L3.** C++ and GDScript agree to 0.001 mm; kinematic grips are exact, adaptive substeps are measured, capstan friction agrees with exp(mu theta), and planted controls fail as intended. Assumed quasi-static mass and friction, and the remaining contact penetration, prevent a higher grade.
- **Knot topology: L2-L3.** Every phase is checked against Ashley #1010. `best_code` is only greedy Reidemeister I/II reduction over 46 views, not an open-curve knot invariant.
- **Hand manipulation: L1-L2.** The real shared palm slab, posed finger capsules and slim wrist now collide with rope, and the pinch is accurate to 0.38 mm. There is still no contact-aware grasp/transit planner and the off hand is represented by kinematic rope grips, not a second rig hand.

## 3. What Kine lacked

| needed | exists today | workaround / measured gap | proposed feature |
|---|---|---|---|
| a slim posed hand | `HandShape.caps`, `forearm_caps`, `palm_flat`, `close_on` (#200) | CH6b now uses the shared shape directly; the old path drives that palm through rope | collision-aware reach and grasp planning using `HandShape` |
| release, transit, re-grasp | keyed `Ch6Knot.tie_plan` plus local wrist search | three routes were measured; all lost topology or exceed reach | sampled transit planner with capsule-rope clearance and arm-reach cost |
| a real second hand | off-hand kinematic grips on 84 rope particles | hand contact with driven held rope is not a complete two-hand simulation | two rig hands with rope grips and collision |
| keep the peg loop wound | rope/peg contact and friction | T4 is 0.48 turns after the transit drags the loop | a second-hand peg-loop hold or contact-aware loop anchor |
| a topological invariant | view-minimised Gauss code | phase codes can change with view and transient penetration | an open-knot / knotoid canonical form |

## 4. What looks wrong

The restored contact sheet (`C:/Users/Nick/tools/kine_workers/out/ch6b/tie_sheet_handshape_baseline.png`) shows UP, DOWN and the collar forming; at f360-f400 the collar is right. During regrip 3 the working hand returns through the standing-part/hole region, folds the peg loop across the hole and leaves a wad rather than the bowline's open peg loop and collar. The HandShape palm is visibly involved in the DOWN and ROUND contacts, consistent with T2 = 3.160 r and the PS1/PS2 spikes. The final peg loop has slipped to 0.48 turns.

The pass-1 sheet (`C:/Temp/opencode/ch6b_sheet_fix1_view.png`) was also inspected: the wider wrist search reduced hand penetration but unthreaded DOWN and no collar formed. It was not kept.

## 5. What changed after seeing results

- **HandShape baseline (w24):** replaced the four local metacarpal capsules and old forearm with `HandShape.caps` + `forearm_caps`. T0 and H3 improved; T2, DOWN and ROUND penetration got worse. ch6b stayed 11/16 and ch6 improved from 10/16 to 12/16.
- **Fix pass 1 (`17b2c2c4`, w25):** front-side regrip 3 and a wider wrist search. T2 improved to 0.461 r and T4 to 0.86 turns, but DOWN unthreaded, PS2 reached 1.710 r, P4 reduced to 2 crossings and H1 slipped 1.75 cm. ch6b 10/16, ch6 12/16.
- **Fix pass 2 (`38af8dd1`, w26):** right-side high-clearance transit and 48 solver iterations. The right route was beyond arm reach (T0 175.83 mm); ch6 fell to 10/16 and H4 read 222.5 N. ch6b exited 127 before producing bars, so no ch6b result is claimed.
- **Fix pass 3 (`5999e16a`, w27):** reachable left transit, 14 cm z-clearance and a 24-frame pre-DOWN dwell. T0 still missed by 59.38 mm; ch6b 10/16, ch6 10/16, and the loaded rope slipped 82.31 cm with no knot found.
- **Restore (`b19040b5`):** returned both tie scripts to the exact best HandShape state (empty diff against `9108457a`). This is the parked code; w24 is its measured suite result. No thresholds, expected codes, or controls were amended.

## Park note

Three fix passes are exhausted. The best HandShape state is clean and committed, but red. The next implementation must plan the hand's whole capsule chain around held rope, with a reachable transit that stays on the front side at regrip 3, and must hold the peg loop with a real second hand. More solver iterations and a wider wrist search alone were measured not to solve the topology.
