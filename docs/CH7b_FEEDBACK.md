# CH7b feedback: the 8 s parkour run, planned contacts first

Lane CH7b (branch w4-ch7b, off the parked w4-ch7). Task: an 8 s Vector-style run with a vault, a wall run or climb, a drop and a roll,
with trajectories pinned to their contacts. The plan is `scripts/parkour_plan.gd`, the engine `scripts/parkour.gd`, the bars
`tests/ch7_test.gd` (not changed). **Status: PARKED, 21 ok / 1 fail.** Last commit: see the end of this file.

## 1. Result

`WT_MAX=8 wtest.sh ch7 easypart peasy3 freestart`, run 3 (the last fix pass): ch7 21 ok / 1 fail, easypart 73/0, peasy3 23/0, freestart 14/0.
At the start of CH7b the same suite read ch7 10 ok / 12 fail.

| bar | reads (run 3) | bar | before CH7b | |
|---|---|---|---|---|
| 1 speed vault palm (right) | 0.4 cm from the edge, slides 0.8 cm | 2 cm / 1 cm | 29.1 / 30.7 cm | ok |
| 1 kong palms L, R | 1.0 cm, slides 0.1 cm | 2 / 1 | 26.8 / 31.7 | ok |
| 1 cat catch palms L, R | 0.5 cm, slides 0.0 cm | 2 / 1 | 8.7 / 5.9 | ok |
| 1 mantle palms L, R | 0.5 cm, slides 0.1 cm | 2 / 1 | 58.3 / 43.0 | ok |
| 2 speed drop at move boundaries | worst 12.9 % (cat leap 3.43 to roll 2.99 m/s) | 15 % | 18.1 % | ok |
| 3 landing knee flex vs drop (0.25 s max) | 69 / 79 / 93 / 107 deg at drops 0.61 / 0.72 / 1.57 / 1.84 m, monotone, **26.3 deg/m** | 30.8 +- 20 % (24.6 to 37.0) | -1.6, not monotone | ok |
| 3b absorption peak (first local max) | the same four numbers, 26.3 deg/m | same | -20.7 | ok |
| 4 foot skate, 18 stance contacts | worst 0.8 mm | 10 mm, >= 15 contacts | 216.6 mm | ok |
| **5 penetration** | **80.0 mm, thigh_l in the kong box, frame 79** | 10 mm | 56 mm (335 in the roll) | **FAIL** |
| 6 length, playback, C++ == GDScript | 8.0 s / 241 cards, 0.0 mm, agree at 7 frames with **native true** | | native false | ok |
| 7a-7g planted controls | all fail their bar as they must (7e: a box through the pelvis reads 353 mm) | | | ok |

Bars 3 and 3b, as asked, once the landings existed: they now read the same, because each landing stance lasts the whole 0.25 s window,
so the window's maximum IS the absorption peak. Read this honestly: the plan sets each landing's absorption depth so the knee peak is
50 + 30.8 deg per m of the feet's drop (the published knee-dominant slope, Zhang et al. 2025, docs/CH7_REFERENCE.md), with the
engine's own stance solve in the loop (`ParkourPlan.knee_solved`). So bar 3 passing is designed in, not emergent. The run reads 26.3,
not 30.8, because the kong landing (drop 1.57 m) can only sink 93 deg instead of the planned 98.7 within its stance (the
deceleration needs more time than the 0.23 s stance has).

Bar 5's remaining offenders (probe of the same commit, every frame over 10 mm):
- kong (frames 76 to 79): thigh_l up to 80 mm. The legs tuck through the box top while the pelvis is at most about 1.38 m (the
  arms hold it there).
- speed vault palm hand_r (frames 33 to 37): 24 to 54 mm. The wrist sits at its 70 deg extension stop and the single hand capsule
  tips into the top.
- kong palms: 13 to 18 mm.
- wall-run stance calves: 27 to 52 mm (frames 105 to 124). With the ankle at its 25 deg inversion stop, the shank leans into the wall.
- the mantle hand at the press: 17 to 21 mm.
- frame 95, ball_l: 11 mm.

### The contact schedule (the plan's first stage; `ParkourPlan.schedule_text`)

| window (s) | limb | surface | contact |
|---|---|---|---|
| 0.00-0.18, 0.27-0.45, 0.53-0.70 | R, L, R sole | roof A | run stances (the hip passes over the pinned toe base; the heel lifts on the ankle's stop) |
| 0.80-0.97 | L sole | roof A | take-off |
| 1.10-1.24 | R palm (-0.35, 0.82, 5.00) | speed box, near edge | plant; the pelvis rides an inverted pendulum over it (`arm_y`) |
| 1.48-1.74 | R sole | roof A | landing; fall 0.15 m pelvis, feet drop 0.72 m, knee peak 79 deg |
| 1.78-1.95, 2.02-2.16 | L, R sole | roof A | run, take-off |
| 2.35-2.56 | L, R palms (+-0.20, 1.02, 9.99) | kong box, FAR edge | dive kong; the pelvis is held by both arms (shoulders over the wrists at 2.44) |
| 2.84-3.07 | L sole | roof A | landing; feet drop 1.57 m, knee 93 deg |
| 3.12-3.26 | R sole | roof A | run |
| 3.40-3.57, 3.70-3.85, 4.00-4.15 | L, R, L toe base | wall face (x 0.74) | wall run; the toe base is pinned, and the foot pivots on it |
| 4.30-4.56 | R sole | roof B | landing; feet drop 0.61 m, knee 69 deg |
| 4.62-4.76, 4.82-4.96 | L, R sole | roof B | run, take-off for the cat leap |
| 5.30-5.86 | L, R palms (+-0.20, 1.72, 21.195) | wall top, near edge | hooked over the edge (normal (0,1,-1)), turning flat for the press; the SHOULDER path about the palms is keyed and the pelvis follows through the trunk |
| 5.98-6.06 | R sole | wall top | the climb-up's step and take-off |
| 6.58-6.82 | L + R soles | roof B | drop landing (feet 1.84 m, knee 107 deg), legs extend 15 cm into the dive |
| 6.76-6.90 | L, R palms | roof B | the roll's hands |
| 6.84-7.20 | shoulder, back, hip | roof B | logged, NOT pinned: the engine rests the lowest capsule on the roof (snap) |

The roll's order (feet, then hands, then back) comes from Wang et al. 2020, "Kinematic analyses of Parkour landings from as high as
2.7 m", J Hum Kinet 72, doi 10.2478/hukin-2019-0123: "a rolling motion from the feet to the hands and to the back". The diagonal
(shoulder to the opposite side) is from Puddle & Maulder 2013, J Sports Sci Med, PMC3761764.

## 2. Engineering level reached

| discipline | level | evidence | why not higher |
|---|---|---|---|
| biomechanics: landings | L3 | the absorption is constant deceleration (closed form: a = v^2 / 2D); the knee peak comes from a cited slope (Zhang 2025, PeerJ 13:e19490, knee-dominant 30.8 deg/m) through the engine's own leg solve; monotone and slope bars carry planted controls | 1.84 m drops extrapolate a 0.3-0.6 m study; there are no ground reaction forces; the pelvis stands in for the centre of mass |
| animation physics: flight | L3 | every airborne phase is a g = 9.81 parabola of the pelvis between contacts (`YPath.par`); the support phases are geometric (arm-length pendulum, leg reach) | no momentum or angular momentum: the kong and the roll rotate at keyed rates with no conservation check; the COM is the pelvis, not Balance.com (de Leva masses) |
| joint ranges | L2 | data/body_limits.json is unchanged: knee 0-145, ankle -45/25 dorsiflexion, inversion 25, hip flexion 120; the hand's extension stop is 70 deg (AAOS) | the limits bind (wrist, ankle inversion, hip flexion) and the plan works round them instead of the body adapting; these cost the remaining bar 5 frames |
| timing vs footage | L2 | moves 0.62-1.23 s, vault and kong plants 0.14 and 0.21 s (footage says 0.15-0.25 s, docs/CH7_REFERENCE.md) | landings brake to about 2.1 m/s and re-accelerate to 3.5-4.1 m/s, which the footage does not show |

Next level (L4) would need: centre-of-mass ballistics from Balance.com; impulse-momentum at each plant and landing (GRF peaks
compared with Puddle & Maulder's force-plate numbers); angular momentum held in flight (the kong's pitch and the roll's rotation
derived, not keyed); a contact model for the hand (palm plus fingers); and a traced mocap reference to compare joint curves against.

## 3. What Kine lacked (searched before claiming)

| needed | exists in Kine today | workaround in this lane | cost | proposed feature |
|---|---|---|---|---|
| a contact schedule (limb, surface point, window) that pins contacts and solves the root from them | Body.plant (feet on a floor), ContactIK.reach (hands), Scene holds/pins (floor scenes only) | parkour_plan.gd + parkour.gd: YPath (ballistic / pendulum / absorb segments), `_land`, `arm_y`, shoulder-keyed mantle | the two files are 1430 lines; CH7b added about 520 of them | a Scene "contact track": pinned limb contacts on any prop surface, and a root solver (ballistic between contacts, reach-limited during them) |
| ballistic flight off the floor, from the centre of mass | Scene flights (VV1, scene.gd:1080: a parabola, on_floor scenes at y = 0 only); Balance.com (de Leva COM) | a pelvis parabola; Balance.com not used: a DISCOVERABILITY gap | the COM proxy is off by the limbs' swing | flights on any surface, from Balance.com, as a Scene option |
| a palm on a surface with the fingers along a chosen heading | ContactIK.reach turns the palm flat by the shortest arc; the fingers end wherever they end | `Parkour._palm_reach(..., fdir)`: the hand's rest frame carried onto (-n, fdir) | 30 lines | a fingers/heading option in ContactIK.reach |
| a foot pinned on a wall (non-horizontal face) at its toe base | Body.plant is for floors (flat sole); `_surface_foot` (CH7) asked for a rotation and let the ball drift 18-23 cm | `Parkour._wall_ball`: damped fixed point on the ankle target, best kept | 25 lines | Body.plant on any surface normal, pivoting about the toe base within the ankle's range |
| free limbs kept out of the set | Props.depth / deepest only CHECK | `_clear_free_legs` (legs and arms): the target moves out along the face normal, re-solved; contacts and pelvis untouched | 70 lines | an IK "keep clear of props" pass for free limbs |
| a hand that conforms to a surface | the hand is ONE capsule wrist to fingertip; nothing curls the fingers to a surface | could not do it: 2-5 cm of hand in the box top whenever the wrist is at its stop | bar 5 stays red | a palm capsule + finger capsules with a curl that wraps an edge (or a palm allowance like STAND_DEPTH for soles) |
| body-surface contacts (shoulder blade, back, hip) for a roll | nothing (the lane's snap rests the lowest capsule) | the roll is a pitch-only ball, not the diagonal shoulder-to-hip path | could not do it | rolling contact constraints for named body regions |
| a contact sheet of a scripted scene from a test or tool | silsheet.gd (K26) draws cards from the app's camera as silhouettes | tools/ch7_sheet.gd: capsules + boxes + contact dots, an orthographic camera that follows the run | 150 lines (G11 again) | the shared "render sequence" helper of G11 |
| the native penetration scan actually loaded | NativeExt.ensure (native_ext.gd) | Parkour.native_on() only asked ClassDB: ch7 had compared GDScript with itself (the CH7 lane's "C++ == GDScript" line read native false in this branch). Fixed | 1 line | none (a bug, fixed) |

## 4. What looks wrong (contact sheet C:/Temp/claude/ch7b/sheet_final.png, every 7th frame, side view)

- **Speed vault** (frame 35): the body sits sideways over the box with the legs forward. It reads as a lazy/speed vault hybrid, not
  a clean speed vault with the legs whipping over. The free arm is stiff.
- **Kong** (frames 70-77): the dive is good, horizontal over the box, but at frame 77 the tucked legs graze the box's top edge. This
  is the 80 mm bar 5 failure.
- **Wall run**: from the side the wall is behind him, so the feet on the wall cannot be judged in this view. The probe shows the toe
  bases pinned within 0.8 mm.
- **Cat leap and climb-up**: the catch and the hang read right (arms long, legs hanging). The climb-up leaves the top of the tiles,
  which is the sheet camera's fixed height, not the animation.
- **Drop and roll**: the landing and squat read well (107 deg at a 1.84 m drop). The roll is a tight forward ball about the side-to-
  side axis, a gymnastics roll, not the diagonal parkour roll the sources describe. He comes out sitting, then lies back for the slide.
- **Arms overall**: the free arms often sit stiff or crossed. Their IK misses reach 0.3 m, which no bar reads.
- **Speed**: every landing brakes hard (vault exit 2.16, kong exit 2.10, wall exit 2.03 m/s) and re-accelerates. Bar 2 only
  penalises a DROP at a boundary, so a surge passes. Footage runs about 4 m/s through.

## 5. What was changed after seeing results

- **No bar was amended or loosened.** tests/ch7_test.gd is unchanged.
- **The course** (plan data, read by the bars through P["obstacles"]):
  - the kong box moved 0.6 m nearer (z 9.4-10.0, was 10.0-10.6);
  - the kong palms plant on its far edge (a dive kong);
  - the ledge is a 0.6 m deep wall top (was 1.7 m), so the drop leaves its far edge.

  Both changes came from timing. With the bars' fixed touchdown times (2.84 s) the old layout needed the pelvis over the box and
  1.35 m up at 2.76 s, then down to 0.83 m by 2.84 s, which gravity cannot do. They change what bars 1 and 5 measure against, so
  they are stated here.
- **Bar 6** now really compares C++ with GDScript (native true): NativeExt loads the plug-in.
- **Engine changes (scripts/parkour.gd):**
  - a stance's heel-up pivot plus toes_flat;
  - a blend-in foot no longer moves the pelvis;
  - the pelvis lowering keeps its best height (it used to run the pelvis 0.72 m into the roof);
  - the wall toe-base pin;
  - palm normals and finger headings per contact;
  - free legs and hands swung out of solids.
- **Plan changes (scripts/parkour_plan.gd):**
  - contacts first;
  - the pendulum pelvis over palm plants;
  - the keyed shoulder path for the climb-up;
  - landing depth searched through the engine's leg solve;
  - a two-pass build (feet flights first, then each landing's depth from the feet's drop).

## Park note

Red: bar 5 only, 80 mm. To close it:
- (a) a conforming hand (palm + fingers, or a palm depth allowance argued from soft tissue like the soles' STAND_DEPTH), for the
  vault and kong palms (13-54 mm);
- (b) the kong needs the pelvis higher over the box than straight arms allow at pitch 90 (about 1.38 m). Either a real push-off
  impulse (the pelvis rises after the hands leave, ballistic from a vertical velocity the arms gave) or the knees tucked to the chest
  in FK;
- (c) the wall-run calves need the foot's sole turned more than the 25 deg inversion stop: pin the ball lower and the knee further
  from the wall, or let the hip turn out (thigh twist) in `_wall_ball`;
- (d) the mantle hand (about 20 mm) wants the palm point lifted to the hand capsule's radius while it turns from hooked to flat.

Each one is local to one move; none needs a bar change.

Last tested commit: 1cd99663 (run 3, logs C:/Temp/claude/w4-ch7b/w4). Commits after it change comments and this doc only.
