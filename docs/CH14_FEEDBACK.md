# CH14 feedback: water-syringe arm builds a 3-2-1 pyramid of six cans (tests/ch14_test.gd, 60 ok, 0 fail)

Reference, sources and what is SEEN / MEMORY / ASSUMED: docs/CH14_REFERENCE.md. Code: scripts/build/ch14_arm.gd (physics), ch14_parts.gd (Kine Parts), ch14_anim.gd (build sequence), ch14_scene.gd (3D), ch14_bom.gd (cost). All GDScript: closed forms, no C++ twin warranted.

## Design
- **Arm:** upper arm 240 mm, forearm 220 mm, shoulder 250 mm over the table, can centre 95 mm under the wrist. Joint limits: shoulder 10..82, elbow -136..-60, wrist -5..100 deg (kept level), base -90..+90.
- **Syringes (10, master|slave):** base 20|20, shoulder 20|20, elbow 20|20, wrist 10|10, gripper 5|5.
- **Base:** a rack on the 20 mL slave drives a 20-tooth module-2 pinion (r 20 mm). 180 deg needs pi x 20 = 62.8 mm of the 69.6 mm stroke, and the stroke is monotone with no dead point. A lever-crank (planted control) has zero arm in the middle of its swing.
- **Shoulder, elbow, wrist:** lever horns. The smallest arms over the whole range are 43.1, 32.8 and 21.9 mm; strokes use 93, 92 and 94 pct of the slave.
- **Gripper:** two racked jaws with an idler pinion, so it centres itself. Jaw force 20.4 N against 7.1 N needed for a full can (mu 0.4).

## Bars (all pass; every planted control fails as it should)
1. **Reach:** all 7 poses plus hovers inside the limits; FK(IK) closes to 1e-13 mm.
2. **Base:** 180 deg from one stroke. 2b: the lever chains fit their syringes, smallest arm >= 20 mm.
3. **Count:** 10 syringes.
4. **Torque, empty can:** margin 2.30 at least (elbow at the top can).
5. **Grip:** friction 16.3 N vs 3.78 N full-can weight.
6. **Placement:** 7.10 mm in-plane, 5.21 mm sideways (x2 vs tau 16.9 / 37.9 mm).
7. **Stack:** stable in all 128 worst sign combinations (min margin 10.4 mm).
8. **Full-can stretch:** only plywood meets it (margin 1.52, tip 0.56 mm).
9. **Hand arithmetic:** every number matches to 1e-9.
10. **Parts:** 14 parts build; the 4.45 mm drawn pin hole prints 4.05 mm worst; 6 STLs.
11. **Build sequence:** 104 s, no lost IK, arm clearance >= 2.91 mm, carried can >= 1.71 mm. 11b: the drawn horns match the lever maths.
12. **Pictures:** the contact sheet and the pair section.
13. **Cost:** see docs/CH14_BOM.md. Current design 29.37 USD; cheapest working design 26.49 USD.

## Backlash: the real failure
Lost slave stroke per axis without air / with 0.5 mL air: shoulder 0.10 / 0.75 mm, elbow 0.14 / 0.83 mm, wrist 0.14 / 1.24 mm, base 0.05 / 0.31 mm.
- **Without air:** 2 x 7.10 = 14.2 mm in-plane, inside the 16.9 mm tolerance.
- **With 0.5 mL air per circuit:** 39.7 mm, OUTSIDE. The budget survives at most **0.053 mL of air per circuit**: bleed the lines under water, or the pyramid fails.
- **Soft PVC tube:** fails even without air (2 x 25.6 mm).

## Materials (full can, thumb 50 N)
| material | min margin | boom tip | verdict |
|---|---|---|---|
| cardboard | 1.59 | 3.99 mm | fails (deflection) |
| pine | 1.48 | 0.36 mm | fails (heavy solid section, shoulder margin) |
| plywood | 1.52 | 0.56 mm | **meets** |
| PLA+ | 1.51 | 3.56 mm | fails (deflection) |

## Things changed after seeing results (all in git)
- Wrist horn: the previous lane's 76/38 horn at a 90 deg phase kept only 16.2 mm of arm. A search over d, r and phase found phase 80 deg, d 126, r 36: 21.9 mm. The 95..153 mm pivot-to-pin length also fits a real 10 mL syringe, which the old one did not.
- Bar 11b tolerance 1e-9 -> 1e-4 mm: Vector2 is single precision (measured 2e-5 mm).
- Animation: the released can was not drawn while the jaws opened (between held and placed); the slave syringes were missing. Both fixed.

## Looking at the pictures (docs/ch14/sheet_build.png, frame_07.png, section_pair.png)
**What reads right:**
- The base swings the arm from the feeder (left) to the pyramid (right).
- The cans go up 3, 2, 1, and the last frame shows the finished pyramid.
- The three slave syringes ride on their pivots and push the horns; their rods extend and retract with the joints.
- The five master plungers on the console move with their axes.

**What still looks wrong:**
- **No hoses drawn:** the 10 circuits aren't shown.
- **Base drive hidden:** the base and gripper slaves (the rack under the turntable, the 5 mL on the gripper) aren't drawn.
- **Gripper looks heavy:** the body is a plain block, bigger than needed.
- **Section is plain:** the pair section is a flat ortho picture; the glass barrels barely show against white.
