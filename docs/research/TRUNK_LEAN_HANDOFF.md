# TRUNK LEAN: handoff (stopped by the budget rule, 10-23)

Nick's report: "the whole body moves, sometimes the back plus torso bend too much back or too much forward... you can see it on kicks".
Branch `w4-trunk` (from `w4-integ`), commit "WIP trunk lean". Nothing here is verified by a passing suite yet.

## Measured (before any fix)
The trunk is the line pelvis -> neck_01 against vertical, in the hips' frame (pitch: + forward; roll: + his left).
The rest pose reads pitch +4.0 because the skeleton's neck sits ahead of the pelvis. `TrunkLean.rest_pitch` takes this off.
Tool: `tools/trunk_measure.gd` (per-frame table to a file). Raw pitch below, rest offset not taken off.

| clip | recognised | max back | max fwd | max |roll| | spine bend summed |
|---|---|---|---|---|---|
| typed front kick | front kick | -13.4 | 3.1 | 4.9 | -7..0 |
| typed roundhouse | roundhouse | -20.2 | 3.1 | 33.7 | 0 |
| typed side kick | side kick | -16.0 | 10.5 | 34.5 | 0 |
| typed jab | jab | (1.9) | 3.7 | 7.6 | 0 |
| typed cross | cross | (2.1) | 4.0 | 7.2 | 0 |
| typed hook | hook | -4.4 | 3.9 | 13.1 | 0 |
| templates/jump | - | (4.0) | 30.4 | 0 | 0..27 |
| templates/punch | cross | (15.6) | 16.6 | 5.4 | 16 |
| templates/run | - | (11.0) | 11.0 | 0 | 8 |
| templates/sword_swing | swing | (8.1) | 14.1 | 8.7 | 4..12 |
| templates/walk, walk_bat | - | (6.2) | 8.5 | 1.7 | 4..5 |
| scenes/combo3 | swing | -2.6 | 40.7 | 11.6 | -12..31 |

A value in parentheses means the trunk never went behind vertical.

**Limb drag:** `tools/trunk_drag_measure.gd` uses main's real input path, as `drag_any_test` does, from the right side view with 24 moves. Numbers are the trunk change from the press.

| drag | smart off, balance off | smart on | balance on only | both on (app default) |
|---|---|---|---|---|
| foot_r to kick height | 0.0 / 0.0 | pitch +13.5, roll +11.3, spine +8.5; pelvis (-5.1, 21.2, 45.0) | roll 0.9, spine side 1.6 | same as smart on |
| hand_r to full reach | 0 | pitch +1.3, roll +1.2; pelvis twist 9.9 | 0 | same as smart on |

A first run from the left view (yaw +90) gave a foot drag of pitch +20.5 and spine bend +22.8. In the same drag the arms moved about 47 deg and the support leg 30-40 deg.

## Cause
SMART DRAG (`scripts/smart_drag.gd`) is ON by default in the app (`scripts/main.gd:488`). In a test it is OFF (`main.gd:2653`), which is why no drag test saw this.

`SmartDrag.begin` (`smart_drag.gd:~328`) makes every non-limb joint a follower, including the pelvis and spine_01..03. `SmartDrag.apply` (`smart_drag.gd:~362`) moves each follower by up to MAX_FOLLOW = 45 deg along the library's co-variation. Kicks in the library lean back, so a foot drag tilts the pelvis and bends the spine.

These do not move the trunk:
- `Body.reach`: two joints only.
- LiveBalance (keep balance): its counter-lean is capped at 8 deg and measured 0.9 deg.

## Sources (opened)
- **Kim, Yenuga & Kwon 2008**, ISBS, roundhouse, n=12 black belts. https://ojs.ub.uni-konstanz.de/cpa/article/view/2005
  - Ranges, Normal distance: pelvis-to-global mediolateral 60.2±7.6, AP 30.5±8.1; trunk-to-pelvis flex/ext 21.7±7.4, lateral 16.8±4.2, axial 52.8±11.0.
  - These are ROM figures, not absolute lean.
- **Gavagan & Sayers 2017**, PLoS ONE, doi:10.1371/journal.pone.0182645. Pelvis posterior tilt ROM: Muay Thai 71±9, Karate 77±9, Taekwondo 75±8. It gives no trunk angles.
- **Blaszczyszyn et al. 2019**, IJERPH, doi:10.3390/ijerph16173155. Mae-geri torso flexion (Plug-in Gait, probably relative to the pelvis):
  - advanced 14.8-21.6, beginners 25-29.6;
  - frontal toward the kicking leg 7.7-18.7;
  - no SD.
  - These values came through a summariser: check the tables.
- **Chung et al. 2010**, J NeuroEng Rehabil, doi:10.1186/1743-0003-7-9. Walking trunk vs ground: tilt range 4.0±1.8, obliquity range 3.3±1.4, mean tilt -0.2±3.6.
- **Krebs et al. 1992**, Phys Ther, doi:10.1093/ptj/72.7.505. "Trunk ROM during gait was small (≤12 deg)". Abstract only.
- **Side kick and punches:** no measured trunk angle was found. Checked Hidayat 2026 doi:10.3389/fphys.2025.1708748, which defines the angle but reports no values, and Dinu & Louis 2020 doi:10.3389/fspor.2020.598861. These norms are HEURISTIC.

## Changed (WIP)
- **`scripts/smart_drag.gd` (the fix).** A limb drag (hand, foot, arm or leg part) no longer tilts the pelvis: its bend and side stay, and twist still follows, which keeps the I12 bars on pelvis twist. The spine's summed bend and side follow are capped at TRUNK_FOLLOW = 4 deg, spread over spine_01..03. 4 deg is Chung 2010's walking range, labelled HEURISTIC. Not yet measured.
- **`scripts/trunk_lean.gd` (new rule, TRUNK LEAN, WARN).**
  - Per card window, the recogniser's class picks NORMS (back, fwd, side); anything else gets GENERAL (25, 60, 30), all HEURISTIC.
  - Fix: on the card nearest the worst frame, spine_01..03 are turned in world space. A punching wrist is re-reached; legs and feet are untouched.
- **Wiring.** `rulebook.gd` (runs on every scene, plus WHY / plain / source entries), `fixer.gd` (label / propose / apply / _same_finding), and `trust.gd` (FILES, the TrunkLean.* and SmartDrag.TRUNK_FOLLOW rows, the rule map).
- **`tests/trunk_test.gd`.** Bars are in the header, written before measuring. `tools/trunk_measure.gd` and `tools/trunk_drag_measure.gd` are the dev tools.

## First test run: what failed and why (remaining steps)
1. **`kick_pose` bisection has the wrong sign.**
   - Pelvis bend -100 gave the trunk +81 FORWARD, so negative pelvis bend tilts forward.
   - Flip it: `if lean_now() > -back: lo = mid else: hi = mid`. Check that the printed trunk is -50 ±2 and -20 ±2.
   - Bars 2 and 3 failed only because of this.
2. **Fix aim.**
   - It turned the spine 190 deg because the acc accumulates and the spine limits (-7..20 per joint) stop it. Cap `acc` to what the spine can give (about -21..+60 bend summed).
   - When the spine is not enough, also tilt the pelvis and re-plant the feet with `WeightXfer.shift`-style `B.plant`.
   - Re-run bar 3.
3. **Lateral norms on kicks are too tight in the windows after the kick.** The typed roundhouse and side kick read roll 33-35 on their "knee" and general windows, flagged by 3-9 deg.
   - Either give the window after a kick the kick's norm, or widen GENERAL / knee side to 40.
   - Decide before listing flagged typed moves.
   - With the current norms the typed moves flagged are: roundhouse cards 3-5 (roll 33.7 vs 30/25) and side kick cards 2 and 4 (roll 34.3-34.5 vs 25). No back or forward flags.
4. **Bar 1 (the drag) did not run yet.** The run was stopped. Run `tests/trunk_test.gd` (window, off-screen).
5. **Add the suite.** Put `trunk:w` in `tools/run_all.sh`'s first EXTRA line. Then run alone with -j 1 and timeout 1200: trunk, drag_any, i12 (smart drag), livebal, templates, weightxfer, theme, people_doc, humanfacts, and the trust / knobs suites, since trust.gd changed.
6. **Write `docs/research/TRUNK_LEAN.md`** from the sources above. The rulebook and trust rows already point to it.
7. **Report to Nick.** On a foot drag smart drag also swings the arms about 47 deg and the support leg 30-40 deg. That is part of "the whole body moves" and was left unchanged (out of the trunk scope).

`scripts/strike_blocking.gd` and `scripts/text_blocking.gd` were not edited.
