# Innovations status (2026-11-06, lane L7, base 6254e061)

How read: **done** = the ROADMAP box is ticked AND a test file and a merge commit exist; **partial** = code and test are merged but the
roadmap names an open bar or a missing hook; **not started** = no script, no test, no commit. I did not re-run the old suites for this
table: "done" is box + file + commit, not a fresh PASS. Only `reactable` (N082) was run by this lane.

## Counts

| set | done | partial | not started |
|---|---|---|---|
| The 15 star-star-star items (INNOVATIONS.md) | 14 (with N082 built tonight) | 0 | 1 (N040) |
| All 100 N items (INNOVATIONS.md N001-N100), by merge-log grep | 30 | 0 | 70 |
| ROADMAP.md I1-I50 | 41 | 9 | 0 |
| ROADMAP_400 track I (face, I01-I20; the "I1..I10" are I01-I10) | 2 (I08, I20) | 0 | 18 |

N items built (30): N001 N002 N003 N004 N005 N006 N007 N008 N011 N013 N015 N016 N017 N018 N019 N020 N022 N024 N025 N027 N028 N029 N031
N064 N065 N066 N074 N080 N082 N091. The Build order's waves 1-3 are all built except N014 (noticeable or not: no script, no test,
needs a research number for perception thresholds). What is left is the 70 N items outside the waves, mostly the two-body and
game-delivery sections (N040-N051, N079-N090) and the sculpt and teaching sections.

## The 15 star-star-star items

| id | name | status | evidence | missing |
|---|---|---|---|---|
| N001 | text view of a pose | done | scripts/text_view.gd:31, tests/textview_test.gd, 31b2a3b4 | |
| N002 | body assertions | done | scripts/body_assert.gd:42, tests/asserts_test.gd, a6d90dd3 + 3c9d4744 | |
| N004 | spec to motion | done | scripts/spec_motion.gd:48, tests/spec_test.gd, 8c124365 | |
| N006 | conflict explainer | done | scripts/conflict_explain.gd:43, tests/conflict_test.gd, db4c14fa | |
| N015 | pose from supports | done | scripts/support_pose.gd:62, tests/supports_test.gd, 7b7ca5b1 | |
| N017 | event query | done | scripts/event_query.gd:43, tests/events_test.gd, 27c6977b | |
| N018 | lint any clip | done | scripts/clip_lint.gd:20, tests/lint_test.gd, 042de827 | runs serial, 600 s budget |
| N027 | who could do this | done | scripts/who_could.gd:32, tests/whocould_test.gd, acadfe10 | |
| N028 | coupled limits | done | scripts/coupled_limits.gd:21, tests/coupled_test.gd, d8e37645 | |
| N040 | throw truth | **done** | tests/n040_test.gd; scripts/throw_truth.gd (+ throw_fixtures, throw_truth_strip, throw_truth_pair). Pair judge per frame: partner extrapolated COM outside his feet + thrower COM margin + contact/grip points; verdict throw works / no kuzushi / thrower falls / no contact. Wired (L34): Throw check panel (CHECK ribbon, clickable frame cells), agent tool + CLI `throw_check` (scripts/throw_panel.gd, throw_serve.gd; tests/throwui_test.gd) |
| N041 | lock truth | **done** | tests/n041_test.gd; scripts/lock_truth.gd (+ lock_fixtures, lock_panel, lock_serve). Per frame the partner's elbow / wrist / shoulder angles the clip asks, against body_limits.json, on the arm the locker touches: lock not on / at limit (5 deg) / past limit: injury (joint, degrees) / no contact. Wired: Lock check panel (CHECK ribbon), agent tool + CLI `lock_check` |
| N065 | hit harder | done | scripts/hit_harder.gd:57, tests/hitharder_test.gd, a772a8b0 | |
| N066 | never falls while posing | done | scripts/live_balance.gd:29, tests/livebal_test.gd, daa042ec | |
| N080 | hitstun and frame advantage | done | scripts/frame_advantage.gd:28, tests/frameadv_test.gd, 374d0c4f | |
| N082 | reactable or not | **done tonight** | scripts/reactable.gd:10, scripts/reactable_strip.gd, tests/reactable_test.gd (suite `reactable`, run_all.sh), commit on branch w4-innov | not wired into main.gd / serve / CLI (kept off agent_tools.gd, L1 is in it); tell rule uses one striking tip, so weapon clips use FrameData's weapon-tip speed only |
| N091 | explain this motion | done | scripts/explain_motion.gd:32, tests/explain_test.gd, a2889258 | |

## ROADMAP.md I1-I50

Partial means the box is open in ROADMAP.md and the note names what fails. Every row has code and a suite; none is "not started".

| id | item | status | evidence | what is missing |
|---|---|---|---|---|
| I1 | Make it physical: one button sends the clip through the MuJoCo humanoi | done | tests/i1_test.gd, 235a78da |  |
| I2 | Reaction from the hit: when the attacker's weapon or fist touches the  | done | tests/i2_test.gd, 77f92cad |  |
| I3 | Counter suggestion: for the attacker's current card, suggest the defen | done | tests/i3_test.gd, eedfbfa5 |  |
| I4 | Timing coach: compare each move's timing to real-motion references (mo | done | tests/i4_test.gd, 4f79ee68 |  |
| I5 | Say it, see it: type "low guard, weight on back foot, bat cocked over  | done | tests/i5_test.gd, 1fef63fa |  |
| I6 | Style dial: "heavier / tired / angry / sneaky" sliders that change a w | done | tests/i6_test.gd, 263ccaec |  |
| I7 | Auto camera: for each beat (wind-up, contact, recover) suggest a shot  | done | tests/i7_test.gd, 1fef63fa |  |
| I8 | Force view: per card, the joint torques and ground forces from inverse | partial | tests/i8_test.gd, f32dae84 | torque colours, power chain, ground force done; bar 8c replaced, combo3 shows NEEDS OUTSIDE FORCE; Nick to judge the bar change |
| I9 | Sketch to pose: draw a stick figure over the viewport with the mouse;  | partial | tests/i9_test.gd, 66f38106 | strokes, depth prior, flip handles merged; 19 of 42 library fits still have a bone >10 deg off (single-view ambiguity) |
| I10 | Your moves learn you: the R27 habits index also learns your timing and | done | tests/i10_test.gd, 1fef63fa |  |
| I11 | Fight phrase builder: give it the attacker's combo and it builds the d | done | tests/i11_test.gd, 7b9f041f |  |
| I12 | Smart drag: dragging one joint moves the rest of the body the way YOUR | done | tests/i12_test.gd, 9e4e8548 |  |
| I13 | Impact frames from the hit: at each contact Kine adds hit-stop (a hold | done | tests/i13_test.gd, a48a3388 |  |
| I14 | Rehearse against yourself: record a short phone video of Nick doing th | done | tests/i14_test.gd, 70c78deb |  |
| I15 | Fight to the beat: with music loaded, Kine moves each contact onto the | done | tests/i15_test.gd, 263ccaec |  |
| I16 | Realism score: one number per clip, "how real is this", from the judge | partial | tests/i16_test.gd, 37096123 | score + fixes merged, incremental == cold; re-score 644-982 ms vs 400 ms bar (Body.apply_true ~2.8 ms/frame) |
| I17 | Learn my style: Kine reads every clip Nick made (scenes/, his poses) a | done | tests/i17_test.gd, f90bfc10 |  |
| I18 | Fight distance keeper: choreography help that keeps two fighters at a  | done | tests/i18_test.gd, c1978b4b |  |
| I19 | Fight rhythm: a tempo map of the exchange (who attacks, who defends, b | done | tests/i19_test.gd, 232ed8db |  |
| I20 | Feint maker: turn a strike card into a feint + real strike (the feint  | done | tests/i20_test.gd, a3bb4419 |  |
| I21 | Sell the hit: for the shot camera, check each strike as the camera see | done | tests/i21_test.gd, f32dae84 |  |
| I22 | Choreograph to the song: from a loaded track's beats and loudness, lay | done | tests/i22_test.gd, ee5bf6d9 |  |
| I23 | My combos: mine Nick's own scenes for card sequences he repeats (same  | done | tests/i23_test.gd, 64ecb7dc |  |
| I24 | Drag the balance: drag the centre-of-mass marker and the body rebalanc | done | tests/i24_test.gd, faa5aa99 |  |
| I25 | Breakfall check: on a fall or knockdown, judge the landing like a stun | partial | tests/i25_test.gd, 49cb30d4 | fall finder, verdicts, fixes merged; arm verdict too lenient on a clavicle-first landing; fall H still fails |
| I26 | Learn from my edits: record which suggestions Nick accepts, undoes or  | partial | tests/i26_test.gd, 2b04d599 | journal + kept-rate learning merged; Check and realism fixes not hooked, counter/rhythm edits not watched |
| I27 | Throw and catch: release a prop from one hand and the app solves the b | done | tests/i27_test.gd, 904f50cf |  |
| I28 | Safety sheet: one pre-shoot report for the stunt crew over the whole s | done | tests/i28_test.gd, b226a787 |  |
| I29 | Match the reference's timing: from a reference video (video import), f | done | tests/i29_test.gd, 878df241 |  |
| I30 | Weapon weight: from the prop's mass and length (inertia about the grip | partial | tests/i30_test.gd, 1ec51104 | torque, flags, fixes merged and bar/text now agree; box just left unticked in ROADMAP |
| I31 | Precog check: every defender reaction (block, slip, step-back, flinch) | done | tests/i31_test.gd, 545d2472 |  |
| I32 | My camera: learn Nick's shot habits from his own shot cameras (lens, h | done | tests/i32_test.gd, 1e19dd85 |  |
| I33 | Reaction direction: a struck body must move away along the blow's impu | done | tests/i33_test.gd, 4bd1244c |  |
| I34 | Fatigue: track each fighter's mechanical work over the fight (joint po | done | tests/i34_test.gd, 1ec51104 |  |
| I35 | Sound cues from physics: place whoosh markers at weapon/limb speed pea | done | tests/i35_test.gd, 7d56d758 |  |
| I36 | Momentum ledger: per card transition, the body's linear and angular mo | done | tests/i36_test.gd, c066e4b1 |  |
| I37 | Auto opponent: for a hero clip, generate fighter 2's whole reactive tr | done | tests/i37_test.gd, a8c98d01 |  |
| I38 | My best take: Nick stars a clip; Kine measures what the starred clip d | done | tests/i38_test.gd, 1ec51104 |  |
| I39 | Recovery step: after a hit reaction or shove, the capture point (Hof 2 | done | tests/i39_test.gd, b48e0a18 |  |
| I40 | Parry rebound: when weapons meet (weapon_clash), compute the exchange  | done | tests/i40_test.gd, 6db8ab3c |  |
| I41 | Gaze director: where each fighter looks, learned from Nick's clips (op | partial | tests/i41_test.gd, e6730c4f | gaze merged (6 of 7 bars): chest share 86 % vs 90 % bar on a dense clip |
| I42 | Floor plan: top-down rehearsal plan of the fight, every foot placement | done | tests/i42_test.gd, 6db8ab3c |  |
| I43 | Airborne spin check: in flight phases (jumps, flips, spinning kicks) t | partial | tests/i43_test.gd, 6c62aec9 | flights, judge, fix merged; 360 spin fix still over (228 vs 219 deg) |
| I44 | Next beat (two fighters): the Next-step suggestion grown to the exchan | done | tests/i44_test.gd, 4bf65340 |  |
| I45 | All judges in one score: the round-3/4 physics judges (weapon weight I | done | tests/i45_test.gd, 357d3e31 |  |
| I46 | My hit reactions: learn how Nick sizes and times hit reactions from hi | done | tests/i46_test.gd, 34f4e5e8 |  |
| I47 | Human speed envelope: every joint's peak angular speed and every hand/ | done | tests/i47_test.gd, d39475a6 |  |
| I48 | Real-mocap pose check: joint-angle combinations in Nick's poses are sc | partial | tests/i48_test.gd, 37096123 | CMU stats + ghost merged; corpus too narrow (flags guard_bat), nearest-pose bar failing |
| I49 | Live layer (Nick: "track moves while recording, so u got an partial mo | done | tests/live_layer_test.gd, 91662bc3 |  |
| I50 | GRIP BOOK** (Nick 10-20: "the weapons have a body for limits and parts | done | tests/grip_book_test.gd, - |  |

## ROADMAP_400 track I (face as geometry)

| id | item | status | evidence | missing |
|---|---|---|---|---|
| I01 | head mesh with lids, lips, jaw, brows | not started | scripts/face.gd is the painted face | the whole geometry head |
| I02 | jaw and eye bones | not started | | |
| I03 | FACS AUs as blendshapes | not started | | needs I01 |
| I04 | expression presets from AUs | not started | | needs I03 |
| I05 | on-surface face controls + slider panel | not started | | |
| I06 | visemes from AUs | not started | scripts/lip_sync (jaw only, test lip_sync) | geometry visemes |
| I07 | teeth and tongue | not started | | |
| I08 | eye look-at, saccades, blinks | done | scripts/eye_life.gd, tests/eyelife_test.gd, 644a8f6b | |
| I09 | wrinkle maps | not started | | |
| I10 | webcam face to AUs | not started | | MediaPipe is allowed already |
| I20 | face from words | done | scripts/face_words.gd, tests/faceword_test.gd, 8ffd6e94 | works on the painted face |

I11-I19 are all open (ARKit 52 export, retarget, effort / pain / breath face, face checks, kiai, micro-expressions). Gaze I16 is covered by ROADMAP I41.

## APP_ROADMAP milestones (from docs/APP_ROADMAP.md; gates are not met by ticking items)

| milestone | state | evidence / what is missing |
|---|---|---|
| M0 solid ground | partial | w2-integ is merged (222 merge commits on the branch); CI green twice and the skip list for failing suites are not shown anywhere I could verify; CLAUDE.md still lists `units` as failing on the base |
| M1 one fighter, start to finish | partial | mesh pages exist (kmesh, sculpt, uv, retopo suites); no outsider test has been run, so gate part 2 is open; P19 task coach not found |
| M2 agent-first | mostly done | INNOVATIONS waves 1-2 built (see above); MCP guide in README_AI.md and docs/API_FOR_AGENTS.md; the "3 of 3 with a score bar" gate run is not recorded |
| M3 public beta | not started | tools/build_installer.sh and docs/C78_INSTALLER.md exist; no auto-update, docs site, crash reporter; not public by Nick's decision |
| M4 1.0 | not started | star-star-star items 14 of 15; Linux and macOS untested; engine add-ons not started |

## All N001-N100 rows still missing above (lane L66, 2026-11-06)

Evidence rule: **done** = script + test + commit found; **partial** = a script or commit exists but the item's named bar or hook is missing (the text says which); **open** = grep found no script, test or commit. These rows were made by file-name and commit grep, not by re-running suites.

| id | name | status | evidence | missing |
|---|---|---|---|---|
| N003 | Dry run any command | partial | scripts/dry_run.gd, tests/dryrun_test.gd | not every command answers dry run |
| N005 | Fix until it passes | partial | scripts/fix_loop.gd, c070715d (serve fix_until, CLI fixuntil) | no test row checked; realism bar wiring unverified |
| N007 | Body-frame numbers | partial | scripts/body_frame.gd | agent-facing input in body frame not confirmed for every serve call |
| N008 | Path to a pose | partial | scripts/pose_path.gd | ordering that never breaks a limit on the way not verified |
| N009 | Screen-reader mode | open | no script, test or commit found by grep | the whole item |
| N010 | Replay proof | open | no script, test or commit found by grep | the whole item |
| N011 | Scene brief | partial | scripts/scene_brief.gd | token bound not checked |
| N012 | Ask why at a time | partial | scripts/why.gd, tests/why_test.gd | curves only; no joint-number cause chain in words |
| N013 | Safe range sweep | partial | scripts/range_sweep.gd | interval sweep exists; not wired to the balance and reach pair named in the item |
| N014 | Noticeable or not | open | no script, test or commit found by grep | the whole item |
| N016 | Move recognizer | partial | scripts/move_recognizer.gd | naming exists; distance from textbook form not verified |
| N019 | Try N ways | partial | scripts/try_n.gd | undo-tree branch scoring exists; not checked against the 5-variant call |
| N020 | Trust labels | partial | scripts/trust.gd | labels not on every API number |
| N021 | Guardrails | open | no script, test or commit found by grep | the whole item |
| N022 | Human facts API | partial | scripts/human_facts.gd | cited tables exist; not every fact asked for |
| N023 | Findings stream | open | no script, test or commit found by grep | the whole item |
| N024 | Kine-Bench | partial | scripts/kine_bench.gd | runner exists; graded task set not verified |
| N025 | Move knobs | partial | scripts/move_knobs.gd | knob set exists; re-solve with contacts kept not verified |
| N026 | How-human dial | open | no script, test or commit found by grep | the whole item |
| N029 | Weight-transfer check | partial | scripts/weight_xfer.gd, 81ce511c, c550e2f1 | test row not located; shift offer not verified |
| N030 | Jump budget | open | no script, test or commit found by grep | the whole item |
| N031 | Whole-body speed caps | partial | scripts/body_caps.gd, tests/bodycaps_test.gd | limb caps; whole-body start / stop caps not verified |
| N032 | Grip hold check | open | no script, test or commit found by grep | the whole item |
| N033 | Load posture | open | no script, test or commit found by grep | the whole item |
| N034 | Impact alignment | open | no script, test or commit found by grep | the whole item |
| N035 | Floor material | open | no script, test or commit found by grep | the whole item |
| N036 | Injury profile | open | no script, test or commit found by grep | the whole item |
| N037 | Real sway in holds | open | no script, test or commit found by grep | the whole item |
| N038 | Stance strength map | partial | scripts/push_limits.gd | one stance (R24); polar map not built |
| N039 | Strength curves | open | no script, test or commit found by grep | the whole item |
| N042 | Target anatomy | open | no script, test or commit found by grep | the whole item |
| N043 | Blind-side check | open | no script, test or commit found by grep | the whole item |
| N044 | Hurt memory | partial | scripts/hit_habits.gd (I46) | learned reaction sizes; no per-side hurt memory |
| N045 | Disarm truth | open | no script, test or commit found by grep | the whole item |
| N046 | Body collision | open | no script, test or commit found by grep | the whole item |
| N047 | Stance matchup | partial | scripts/range_rings.gd | rings exist; orthodox vs southpaw matchup not verified |
| N048 | One vs many | open | no script, test or commit found by grep | the whole item |
| N049 | Lift the opponent | open | no script, test or commit found by grep | the whole item |
| N050 | Two-body targets | open | no script, test or commit found by grep | the whole item |
| N051 | Grab contracts | open | no script, test or commit found by grep | the whole item |
| N052 | Landmark snap | open | no script, test or commit found by grep | the whole item |
| N053 | Draw-path check | open | no script, test or commit found by grep | the whole item |
| N054 | Armour limits the body | partial | scripts/rom_clash.gd, tests/romclash_test.gd | flags clash, does not change limits |
| N055 | Tailor's tape | open | no script, test or commit found by grep | the whole item |
| N056 | Stylised proportions, with consequences | open | no script, test or commit found by grep | the whole item |
| N057 | Fist test | open | no script, test or commit found by grep | the whole item |
| N058 | Can this body stand? | open | no script, test or commit found by grep | the whole item |
| N059 | Materials by anatomy | open | no script, test or commit found by grep | the whole item |
| N060 | Looks strong enough? | open | no script, test or commit found by grep | the whole item |
| N061 | Helmet vision check | open | no script, test or commit found by grep | the whole item |
| N062 | Brush in kilograms | open | no script, test or commit found by grep | the whole item |
| N063 | Reach envelope | open | no script, test or commit found by grep | the whole item |
| N064 | Ouch meter | partial | scripts/ouch_meter.gd:29, tests/ouch_test.gd | commit not located in log |
| N067 | Touch tool | open | no script, test or commit found by grep | the whole item |
| N068 | Part-first actions | open | no script, test or commit found by grep | the whole item |
| N069 | Weight split | open | no script, test or commit found by grep | the whole item |
| N070 | Stances that fit the body | open | no script, test or commit found by grep | the whole item |
| N071 | Best view for this joint | open | no script, test or commit found by grep | the whole item |
| N072 | Stop reason | open | no script, test or commit found by grep | the whole item |
| N073 | Difficulty stars | open | no script, test or commit found by grep | the whole item |
| N074 | Red spots on the body | partial | scripts/red_spots.gd, tests/redspots_test.gd, 417862c7 | click-to-fix not verified |
| N075 | What this body can do | open | no script, test or commit found by grep | the whole item |
| N076 | Phase-by-phase builder | open | no script, test or commit found by grep | the whole item |
| N077 | Into the band | partial | scripts/gait_band.gd | shows the band; does not pull curves into it |
| N078 | Say what looks wrong | done | scripts/whywrong.gd, tests/whywrong_test.gd, 0a25e758 (merge wt-whywrong) | none noted |
| N079 | Hurtboxes from the real mesh | partial | scripts/hit_boxes.gd, tests/hit_boxes_test.gd | mannequin capsules; not fitted to the mesh |
| N081 | Cancel windows from the body | done | scripts/cancel_windows.gd:10, tests/n081_test.gd, 79ca57d0 + 5865be68 | none noted |
| N083 | Play-rate safe range | partial | scripts/play_speed.gd | speed control exists; 0.8x-1.25x range report not verified |
| N084 | Blend matrix | done | scripts/blend_matrix.gd, tests/n084_test.gd + n084w_test.gd, 3e08bac5 + 2cdf0259 | none noted |
| N085 | Ragdoll export | open | no script, test or commit found by grep | the whole item |
| N086 | Contact curves | partial | scripts/foot_plant.gd | foot-plant detection exists; no per-clip curve export |
| N087 | Body-aware compression | partial | scripts/key_reduce.gd | reduction exists; error measured in degrees, not cm at hands and feet |
| N088 | LOD by body region | open | no script, test or commit found by grep | the whole item |
| N089 | Sockets from anatomy | open | no script, test or commit found by grep | the whole item |
| N090 | Runtime body check | open | no script, test or commit found by grep | the whole item |
| N092 | Which muscles fire | open | no script, test or commit found by grep | the whole item |
| N093 | What drives what | open | no script, test or commit found by grep | the whole item |
| N094 | Lesson from my mistake | open | no script, test or commit found by grep | the whole item |
| N095 | Drills | open | no script, test or commit found by grep | the whole item |
| N096 | Living glossary | open | no script, test or commit found by grep | the whole item |
| N097 | Pro comparison | open | no script, test or commit found by grep | the whole item |
| N098 | Before / after per fix | open | no script, test or commit found by grep | the whole item |
| N099 | My progress | open | no script, test or commit found by grep | the whole item |
| N100 | The 12 principles as physics | partial | scripts/critique.gd | critique exists; physical cause sentence per principle not verified |
