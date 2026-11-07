# Kine innovations: 100 new ones, only what a body-aware tool can do (2026-10-23)

Nick 10-23: "this body aware makes it easier to make real animations, at least human possible... this is handy asf" -
and: it's perfect for vibe coders, because most AI agents are blind.

## The idea in one line

Other 3D tools are built for eyes: you look at the viewport to see if a pose is wrong. Kine's mesh and rig **know they
are a human body** (every vertex knows its bone, region and muscle; Kine knows joint limits, de Leva masses, ANSUR
proportions, balance, the physics judges and cited human numbers), so Kine can **say in numbers and words what is wrong
and how to fix it**. That makes it the first animation tool a blind AI agent can use for real, and a tool that teaches
beginners while they work.

**Already there to build on:** one agent code path for MCP, `poser_cli serve` and the local API
(`scripts/agent_tools.gd`, `local_api.gd`: describe / run / check / shot, plus serve's state / measure / ask / diff /
validate / pose); R10 "what would this angle do" (`what_if.gd`); every command is a script line (O15); Check's rulebook
with fixes; `human_limits.gd`, `balance.gd`, `fatigue.gd`, `feasible.gd`, `stunt_load.gd`; the I16 realism score with
the I45 judge suite; the body-aware mesh A18 (`kmesh_body.gd`) and anatomy tags A19 (`kmesh_anatomy.gd`); frame data
and hit boxes; the 2-fighter judges (I3, I11, I18, I31, I33, I37, I39, I44).

**What stays where it is:** the ROADMAP.md I-items (I1-I50) and R-items, and the 119 ★ items in ROADMAP_400.md, stay
planned in those files. This list is only what is NOT in them. Where an item grows from one of them, "builds on" says
which, and the row says what is different.

Cost as ROADMAP_400 defines it: **$** one agent hour, no new core; **$$** one wave, needs its track's core; **$$$**
several waves. **★★★** = the 15 I judge most valuable. **(research)** = the item needs a number from published data that
is not in `docs/physics_constants.md` yet; the row names the kind of source, never a made-up citation.

### Dropped from the first draft (29 items: X01-X13, Y01-Y12, Z01-Z04)

| draft | why it was dropped |
|---|---|
| X01 possible-or-not | is `feasible.gd` (PASS / FIX / IMPOSSIBLE per clip) + ROADMAP 10 human check |
| X02 make it possible | is I1 make it physical (physical version, accept per span) |
| X04 body landmarks as targets | one body: is I5 say it, see it ("hand over the right shoulder"); the two-body case is now N050 |
| X05 one score to optimise | is I16 realism score + I45 all judges |
| X08 diff in words | is ROADMAP 98 scene diff report + `poser_cli diff` |
| X09 captioned contact sheet | is K26 silhouette sheet + K23 render the judge |
| X11 pose search by words | is R21 |
| Y01 kinetic chain | is I8 power chain (hip -> trunk -> shoulder order) |
| Y02 injury flags | is ROADMAP 24 stunt load (landing BW, knee valgus, NIOSH spine, neck speed) |
| Y03 possible for THIS body | is G19 + G20 ★ |
| Y04 energy budget | is I34 fatigue (work budget) |
| Y05 gait from the body | is ROADMAP 92 walk / run along a path from gait data |
| Y07 balance recovery | is I39 recovery step (capture point) |
| Y08 ground forces | is I8 step 2 (ground force, NEEDS OUTSIDE FORCE badge) |
| Y09 retarget keeps the truth | is G08 + G21 ★ |
| Y11 self-collision over the clip | is `feasible.gd` SELF-PENETRATION + B24 |
| Z01 hit truth | is I21 sell the hit + I18 distance keeper + frame data ACTIVE |
| Z02 reaction from the hit | is I2 |
| Z03 fair choreography | is I11 + I18 + I31 |
| Z04 opponent-aware gaze | is I41 gaze director + I16 ★ (ROADMAP_400) |

Kept and rewritten: X03 -> N001, X06 -> N002, X07 -> N003, X10 -> N004, X12 -> N009, X13 -> N010, Y06 -> N033,
Y10 -> N091, Y12 -> N026.

---

## 1. Agent-first: the blind agent's eyes and hands (25)

An agent can't look at the viewport. These give it the body as text and numbers, a way to say what it wants, and a way
to know when it is done. Mixamo, Cascadeur, Blender's Python API and Unreal's Python all give an agent transforms
(xyz, quaternions); none of them answer "is this a human pose, and what do I change?".

| id | name | what the user or agent gets | builds on | cost | |
|---|---|---|---|---|---|
| N001 | **Text view of a pose** | A front + side stick figure in ASCII and one paragraph ("crouched, weight 70 % on the left foot, right fist at chin height, guard open on the right"), so a model that can't see images still sees the pose. | serve `state`, `balance.gd` | $ | ★★★ |
| N002 | **Body assertions** | The agent writes checks like tests ("left foot planted 0-0.4 s", "right fist touches his chin at 0.6 s +-1 f", "COM inside the feet all clip") and gets pass / fail with the miss in cm, deg or s. | foot plant (8), serve `measure` | $$ | ★★★ |
| N003 | **Dry run any command** | Every command can answer "what would this do?" (findings before / after, score change, parts moved) without changing the scene. | R10 `ask` (angles only), I16 predicted gains, JudgeSuite.fix on a clone | $ | |
| N004 | **Spec to motion** | Give a move as a spec (kind, target, timing, contacts, assertions) and get a clip that passes every assertion, or a list of the ones it could not meet and why. | ROADMAP 22 type a move, I5, N002 | $$$ | ★★★ |
| N005 | **Fix until it passes** | One call runs the fixes in order of gain until all assertions pass and the realism score is over a bar, then reports what it changed and what still fails. | I16 / I45 fixes, N002 | $$ | |
| N006 | **Conflict explainer** | When two wishes can't both hold, Kine names the smallest set that clash and the cost to free each ("fist needs 12 cm more reach: step 12 cm, or lean 9 deg, or drop 'both feet planted'"). | N002, `limb_ik.gd`, `balance.gd` | $$ | ★★★ |
| N007 | **Body-frame numbers** | Every answer and every input can be in the body's own frame ("15 cm in front of the sternum, at chin height, toward his left") so an agent never needs world axes. | `what_if.gd`, serve `measure` | $ | |
| N008 | **Path to a pose** | From the current pose to a named or described one, Kine returns the command lines that get there, in an order that never breaks a limit or a contact on the way. | `pose_words.gd`, R21 pose search | $$ | |
| N009 | **Screen-reader mode** | The same words (N001, findings, diffs) spoken or sent to a screen reader, so a blind PERSON can animate too; other tools have nothing to say. | N001, `whywrong.gd` | $$ | |
| N010 | **Replay proof** | A hash of the result plus the exact command log, so a human can check what an agent made and replay it byte for byte. | O15, macros (81) | $ | |
| N011 | **Scene brief** | One short summary per scene sized for a context window (who, moves, beats, contacts, top problems, under N tokens), so an agent picks up a scene without reading the file. | serve `describe`, `check` | $ | |
| N012 | **Ask why at a time** | "Why does the score drop at 1.2 s?" returns the cause chain in words with the joint numbers ("hips stop 2 frames before the fist: 38 kg m/s lost, MOMENTUM flag"). | `why.gd` (curves only), I16, I45 | $$ | |
| N013 | **Safe range sweep** | "What right-hip flexion keeps balance AND lets the fist reach?" returns the interval, not one test value, so the agent picks inside it. | R10 `ask` (one value) | $ | |
| N014 | **Noticeable or not** | Every number comes with a "would a viewer see this?" tag (a 3 mm foot creep: no; 2.5 cm: yes), so agents stop fixing what doesn't matter. (research: perception thresholds for animation errors) | Check bars, COMPLAINTS #2 | $ | |
| N015 | **Pose from supports** | Say what touches the floor ("kneeling on the right knee, left hand on the floor") and Kine solves a stable pose with the weight shared over those contacts. | I5 (feet only), `balance.gd`, `rise.gd` | $$ | ★★★ |
| N016 | **Move recognizer** | "Is this a hook?" Kine names the strike or move a clip shows (by its path, chain and speed) and says how far it is from the textbook form. | Rulebook.strikes, I47 | $$ | |
| N017 | **Event query** | Ask "when does the right foot leave the floor / when is the guard down / when is he off balance?" and get the times, from the body, not from keys. | `video_iq.gd` contacts, `critique.gd`, `balance.gd` | $ | ★★★ |
| N018 | **Lint any clip** | `kine lint clip.fbx|bvh|glb` judges animation made ANYWHERE (Blender, Mixamo, an agent's own code) and returns the findings as JSON: Kine as the body-truth checker in someone else's pipeline. | `anim_import.gd`, `check_all`, I45 | $$ | ★★★ |
| N019 | **Try N ways** | The agent asks for 5 variants of a change (in undo-tree branches), Kine scores each and returns the best with the diff, so trial and error is one call. | undo tree (15), I16 | $$ | |
| N020 | **Trust labels** | Every number the API gives says MEASURED (with source), HEURISTIC or UNVERIFIED, so the agent knows which bars it can argue with. | `docs/physics_constants.md` status column | $ | |
| N021 | **Guardrails** | The owner sets limits an agent can't cross ("never past human limits", "don't touch fighter 2", "max 50 edits", "never write scenes/"), enforced by Kine, not by the prompt. | CLI write rules, local API token | $ | |
| N022 | **Human facts API** | "How fast is a real jab? How long does a hook take? How far does a man step?" answered from Kine's cited tables with the source, so the agent plans with real numbers. | I47 limits, gait band, physics_constants | $ | |
| N023 | **Findings stream** | The agent subscribes and gets new body findings as the human edits (a foot starts sliding, the score drops 6), so an agent can coach live beside a person. | local API, O10 event hooks (generic) | $$ | |
| N024 | **Kine-Bench** | 20 graded tasks ("a jab that lands at 0.3 s, feet planted", "a fall that passes breakfall") scored by the judges, to compare agents and prompts on the same body. | R7 cold-start test (one task) | $$ | |
| N025 | **Move knobs** | Numeric handles on a finished move (strike height, reach %, stance width, guard height); the agent sets a number and Kine re-solves the rest, contacts kept. | I6 style dial (style, not geometry), I5 | $$ | |

## 2. Body truth: what a real body can and can't do (14)

The judges already check limits, balance, speed, torque, momentum, spin. These add the parts of being human they
don't cover yet. Cascadeur's AutoPhysics fixes the centre-of-mass path and spin of a clip, but it does not know human
strength, flexibility or who could do the move; that is where these sit.

| id | name | what the user or agent gets | builds on | cost | |
|---|---|---|---|---|---|
| N026 | **How-human dial** | One slider from real to anime / superhero: the checks loosen on purpose and Kine lists exactly which human rules the style is breaking and by how much. | I6 (heavier / tired / angry, a different axis), I16 | $$ | |
| N027 | **Who could do this?** | From the clip, the minimum body that could do it: "needs top-5 % hip flexibility, a pro boxer's hand speed, elite jump power", or "no human". (research: population ROM, strength and power norms) | I47, G20, G23 | $$ | ★★★ |
| N028 | **Coupled limits** | Limits that depend on two joints (a straight-knee high kick is limited by the hamstrings; bend the knee and the hip goes further), so a kick is judged as a real leg. (research: straight-leg-raise and two-joint muscle ROM studies) | `data/body_limits.json` (one joint at a time) | $$ | ★★★ |
| N029 | **Weight-transfer check** | In a combo, each strike needs the weight where it starts (a cross from the back foot); flags a strike that starts with the weight on the wrong foot and offers the shift. | I36 momentum, `balance.gd`, I44 | $$ | |
| N030 | **Jump budget** | The take-off power a jump needs vs what legs can give: "this jump needs 2x an elite vertical jump". Cascadeur gives the flight arc; Kine judges the push that starts it. (research: countermovement jump power norms) | I43 airborne spin, I8 ground force | $$ | |
| N031 | **Whole-body speed caps** | Caps on how fast the whole body can start, stop and change direction (0 to 8 m/s in 0.2 s is not human), beside I47's limb caps. (research: sprint start and cutting acceleration data) | I47 (limbs only), I36 | $ | |
| N032 | **Grip hold check** | Would the weapon fly out of his hand? Grip force the swing needs vs measured grip strength, with the frame where it slips. (research: grip strength norms) | I30 weapon weight (wrist and shoulder only), grip book | $$ | |
| N033 | **Load posture** | Holding or carrying a heavy prop changes the pose by itself: counter-lean, wider stance, slower turns, from the prop's mass and the body's. | weight feel (40), I30 | $$ | |
| N034 | **Impact alignment** | At the contact frame: wrist straight on a punch, elbow not snapping straight on a miss, knee not locked on a kick landing; flags the risky alignment with the angle. (research: hand and elbow injury mechanisms in striking sports) | frame data ACTIVE, `stunt_load.gd` (other loads) | $ | |
| N035 | **Floor material** | Mat, wood, sand, wet tile: the friction under the feet changes what pivots, stops and slides are possible. (research: shoe-floor friction coefficients) | I36 (friction 1.0 fixed), `balance.gd` | $ | |
| N036 | **Injury profile** | Give a fighter a bad left knee or a stiff shoulder: his limits and strength drop there, the judges use them, and Kine shows the moves that now fail (a real limp, not a keyed one). | G20, `data/body_limits.json` | $$ | |
| N037 | **Real sway in holds** | A still stance gets the small sway a real body has, sized from published postural sway, not the 8 % drift of moving holds (taste). (research: postural sway amplitude and frequency) | moving holds (COMPLAINTS #7) | $ | |
| N038 | **Stance strength map** | A polar picture of how hard a push this stance can take from each direction before stepping, worked out from THIS stance's feet. | R24 push limits (one stance), I39 capture point | $$ | |
| N039 | **Strength curves** | A joint's strength depends on its angle (a push is weak at full reach); torque bars follow the angle instead of one "strong human" number. (research: joint torque-angle curves) | I8 force view | $$ | |

## 3. Two or more bodies: fight choreography (12)

Kine already keeps range, timing, reads, counters and reactions between two fighters. These are the parts of a fight
where the two bodies touch, hold, see and remember each other.

| id | name | what the user or agent gets | builds on | cost | |
|---|---|---|---|---|---|
| N040 | **Throw truth** | A throw works only when the partner's centre of mass is pulled outside his feet (kuzushi) and the thrower's own balance holds; Kine judges both bodies as a pair and says which is missing. | `balance.gd`, I39, I36 | $$$ | ★★★ |
| N041 | **Lock truth** | An armbar or wristlock uses the PARTNER's joint limits: Kine says when the lock reaches his limit and flags going past it as an injury. | `data/body_limits.json`, A19 | $$ | |
| N042 | **Target anatomy** | Where the hit lands, by muscle and bone tag (liver, chin, thigh), picks the kind of reaction (fold, knees go, leg buckles), not only its direction. (research: sports-medicine knockout and body-shot mechanisms) | A19 anatomy tags, I2, I33 | $$ | |
| N043 | **Blind-side check** | Can the defender SEE the strike? Field of view from his head and eyes; a strike from outside it makes a fast block "precog" even if the timing is fine. (research: human visual field) | I31 precog (time only) | $ | |
| N044 | **Hurt memory** | After a hit to the ribs, the fighter guards that side, favours the hurt leg and slows on that side for the rest of the fight. | I33, I34, I37 | $$ | |
| N045 | **Disarm truth** (L74: scripts/disarm_truth.gd, tool disarm_check) | A disarm works only when the lever on the wrist beats the grip; Kine says why one works and another doesn't. | N032, grip book, I40 | $$ | |
| N046 | **Body collision** | A shoulder charge or tackle shares momentum between the two bodies by their masses; the lighter one moves more, and Kine keys both. | I36, I2 | $$ | |
| N047 | **Stance matchup** | Orthodox vs southpaw, open or closed: which lanes and targets each fighter's strikes can reach from where they stand. | I18 distance keeper, `range_rings.gd` | $ | |
| N048 | **One vs many** (L74: scripts/group_fight.gd, tool group_fight) | In a group fight, Kine schedules the attackers so only as many attack at once as can reach, with real spacing around the hero. | choreo (13), I18, I19 | $$ | |
| N049 | **Lift the opponent** | Picking up and slamming a body uses his real mass: posture, back load and how high he can be lifted. | de Leva masses, `stunt_load.gd` spine | $$ | |
| N050 | **Two-body targets** | "My right fist to HIS chin at 0.6 s": targets on the other fighter's moving body, solved for both, given by name. | I5 (one body), I3 | $$ | |
| N051 | **Grab contracts** | "Grab his wrist": the hand stays on the partner's moving limb, with a grip from the grip book, and breaks are reported in cm. | grip book (I50), contact IK (88) | $$ | |

## 4. Body-aware modeling, sculpt and surface (12)

The ★ items in ROADMAP_400 tracks B-H already cover armour from regions, ROM clash, sculpt in pose, muscle brushes and
deformation over the scene. These are the gaps between them.

| id | name | what the user or agent gets | builds on | cost | |
|---|---|---|---|---|---|
| N052 | **Landmark snap** | Snap points and straps to bony landmarks (shoulder tip, elbow knobs, hip bones, kneecap) by name; armour and straps sit where a tailor or armourer would put them. | A19, B08 snapping | $ | |
| N053 | **Draw-path check** | A sheath, holster or back sword: can the hand reach it and pull the weapon out in one motion? Kine tries the draw and says where it fails. | `limb_ik.gd`, grip book, B24 | $$ | |
| N054 | **Armour limits the body** | The armour's clash range becomes new joint limits for that fighter, so his animation is judged with the armour on. | B24 ROM clash (flags, does not change limits) | $$ | |
| N055 | **Tailor's tape** | Measure any sculpted mesh the ANSUR way (chest girth, sleeve, inseam) and see its percentile. | G16 (body page), B20 measure | $ | |
| N056 | **Stylised proportions, with consequences** | A heroic 9-head body or big chibi head: Kine says what the style breaks (can't touch his own face, jab reach -12 cm, guard can't cover the chin). | G03, `limb_ik.gd` | $ | |
| N057 | **Fist test** | A modeled hand or glove runs the grip book poses and a full fist: does it close, does it pass through itself, which finger fails. | grip book (I50), F14 | $ | |
| N058 | **Can this body stand?** | Square-cube check for creatures and stylised bodies: leg cross-section vs the weight on top; legs too thin to carry it are flagged. (research: muscle force per cross-section area) | G18, J22 | $$ | |
| N059 | **Materials by anatomy** | Skin, lips, nails and scalp get their materials from the anatomy tags in one click. | A19, E02 | $ | |
| N060 | **Looks strong enough?** | If the animation needs big torque at a joint, the sculpt's muscle there should look able to; skinny arms throwing a 200 N m punch are flagged. | I8 force view, H19, C22 | $$ | |
| N061 | **Helmet vision check** | A helmet's eye slots cut the field of view; Kine shows what he can't see, and N043 uses it. (research: human visual field) | N043, B23 | $ | |
| N062 | **Brush in kilograms** | "Add 2 kg of muscle to the thigh": the brush adds volume by tissue density and the mass tables update. | C22, G18 | $$ | |
| N063 | **Reach envelope** | A visible shell of where the hands and feet can reach for this body, to place shelves, weapon racks and props in a set. | `limb_ik.gd`, body limits | $ | |

## 5. Monkey-brain ease: beginners, only possible because Kine knows the body (15)

Easy mode, templates, drag any part and smart drag exist. These remove the next layer of thinking by letting the body
do it.

| id | name | what the user or agent gets | builds on | cost | |
|---|---|---|---|---|---|
| N064 | **Ouch meter** | While you drag, the joint goes green / yellow / red by comfortable vs maximum range, so you feel where a real body starts to hurt. (research: comfortable ROM from ergonomics studies) | body limits, `set_ang_safe` | $ | |
| N065 | **Hit harder** | One button: more hip turn, a longer chain, more follow-through, all within limits, and the fist speed or impulse goes up by a number Kine shows. | I8 power chain, I47 caps | $$ | ★★★ |
| N066 | **Never falls while posing** | Drag an arm far out and the hips shift to keep him over his feet, live; hold Alt to let him fall. Cascadeur fixes balance on the clip; Kine keeps it while you pose. | I24 drag balance (the reverse), `balance.gd` | $$ | ★★★ |
| N067 | **Touch tool** | Click a hand, then click any body part (his own or the opponent's): the hand goes there by IK. | contact IK (88), I5 | $ | |
| N068 | **Part-first actions** | Click a body part and get the moves it can do ("punch with this", "kick with this", "block with this"). | ROADMAP 22, templates (44) | $ | |
| N069 | **Weight split** | A big % under each foot (60 / 40), so beginners see weight without knowing what a centre of mass is. | `balance.gd`, balance view | $ | |
| N070 | **Stances that fit the body** | Boxer, karate, fencing stances sized to THIS body's legs and shoulders, not one size. (research: published stance width ratios) | G23 archetypes, templates (44) | $ | |
| N071 | **Best view for this joint** | The camera turns to the view where the picked joint's bend reads clearly, with no front / back confusion. | `view_cube.gd`, joint frames | $ | |
| N072 | **Stop reason** | When a drag stops, a label says what stopped it ("elbow can't straighten past 0 deg", "hand hits the thigh"). | `set_ang_safe` reached report | $ | |
| N073 | **Difficulty stars** | Each pose and move gets a label: anyone / athlete / elite / no human. | N027 | $ | |
| N074 | **Red spots on the body** | Problems glow ON the body part (a sliding foot, a bent wrist at impact); click the glow to fix it. | Check findings, I16 fixes | $ | |
| N075 | **What this body can do** | Pick a body and the move templates it can't do (splits for a stiff body, a jump too high for a heavy one) are greyed with the reason. | N027, G20 | $$ | |
| N076 | **Phase-by-phase builder** | Build a move one phase at a time (ready, wind-up, strike, follow-through, recover); each phase is checked before the next unlocks. | ROADMAP 22 phases, I4 | $$ | |
| N077 | **Into the band** | One slider pulls a hand-made walk's hip, knee and ankle curves into the real walkers' band. | gait band (shows the band, doesn't fix) | $ | |
| N078 | **Say what looks wrong** | Type "his arm looks weird": Kine matches the words to the findings on that body part near the playhead and offers their fixes. | `whywrong.gd`, Check | $ | |

## 6. Game delivery: engine-side truths (12)

Frame data, hitboxes, engine presets and LODs exist. These carry the body's truth into the game.

| id | name | what the user or agent gets | builds on | cost | |
|---|---|---|---|---|---|
| N079 | **Hurtboxes from the real mesh** | Hurtboxes fitted to the character's own mesh by region, with region multipliers (head, torso, limbs) for damage. | A18 regions, hit boxes (36) (mannequin capsules) | $$ | |
| N080 | **Hitstun and frame advantage** | Hitstun, blockstun and knockback from the hit's impulse and the recovery step, then frame advantage on hit / on block between two moves (FRAME_DATA.md: "not measured by Kine"). | I2 impulse, I39, frame data (12) | $$ | ★★★ |
| N081 | **Cancel windows from the body** | The frames where the body is balanced and its momentum low enough to start another move; exported as cancel windows. | I36, `balance.gd`, frame data | $$ | |
| N082 | **Reactable or not** | Frames from "readable" to "active" vs human reaction time: "this overhead is 9 frames from readable: not reactable online". Fairness from the body. | I31 read time, frame data | $ | ★★★ |
| N083 | **Play-rate safe range** | Engines speed clips up; Kine reports the range (0.8x-1.25x) where the move stays human and the feet don't slide against the root. | I47 caps, root motion (91) | $ | |
| N084 | **Blend matrix** | For a moveset, every clip-to-clip crossfade is checked at its blend time for limit breaks, self-clash and foot skate; bad pairs listed. | 84 pose matching, 33 motion-matching preview | $$ | |
| N085 | **Ragdoll export** | Joint cone limits and segment masses exported as Godot physical bones / UE physics asset / Unity joints, so the game's ragdoll is a human. | body limits, de Leva, N21 ★ | $$ | |
| N086 | **Contact curves** | Foot-planted and hand-contact weight curves exported with each clip, for the engine's foot IK. | foot plant (8), I49 | $ | |
| N087 | **Body-aware compression** | Key reduction with the error measured in cm at the hands, feet and weapon tip, not degrees per curve. | key reduction (68) | $ | |
| N088 | **LOD by body region** | LODs that keep loops at the joints and detail on the face and hands and cut elsewhere. | F04, A18 regions (F15 is by camera) | $$ | |
| N089 | **Sockets from anatomy** | Engine sockets (weapon_r, back_sheath, hip_holster, head_fx) placed on anatomical points and exported. | A19, N052 | $ | |
| N090 | **Runtime body check** | A small engine add-on that flags in play when blends or game IK push a joint past its human limit. | body limits, engine export (9) | $$ | |

## 7. Teaching and explaining (10)

Critique, timing coach and "what went wrong" point at problems. These teach WHY, through the user's own clip.

| id | name | what the user or agent gets | builds on | cost | |
|---|---|---|---|---|---|
| N091 | **Explain this motion** | A plain-words breakdown of a clip: phases, where the power comes from, what makes it read heavy or fast, with the numbers. | I8, I36, `critique.gd` | $$ | ★★★ |
| N092 | **Which muscles fire** | Per frame, the muscle groups that work (from the joint torque direction and the anatomy tags), drawn on the body. (research: muscle actions from anatomy texts) | I8 force view, A19 | $$ | |
| N093 | **What drives what** | Move one cause (hip turn, step length) and watch the effect (fist speed, reach) change live, so the kinetic chain is learned by playing. | I8, N013 | $$ | |
| N094 | **Lesson from my mistake** | When the same body mistake comes back 3 times, a 30-second lesson on it, using the user's own frames. | Check, I26 journal | $ | |
| N095 | **Drills** | Short tasks graded by the judges ("make a jab that lands in 0.3 s, feet planted"), the human side of N024. | N024, I16 | $ | |
| N096 | **Living glossary** | Hover a word (pronation, kuzushi, capture point, follow-through) and the mannequin shows it. | `pose_words.gd`, templates | $ | |
| N097 | **Pro comparison** | "Your hip leads your shoulder by 10 ms; trained boxers by about X ms": the user's mechanics beside published athlete numbers. (research: striking biomechanics studies) | I8, I47 | $$ | |
| N098 | **Before / after per fix** | Every fix plays as a short flip between the old and fixed frames with an arrow on what moved. | I16 fixes, version diff (28) | $ | |
| N099 | **My progress** | The user's realism score and most common body mistakes over weeks, so they see what they've learned. | I16, I26 journal | $ | |
| N100 | **The 12 principles as physics** | Each principle shown as its physical cause on the clip ("follow-through = momentum still in the arm: 4.1 kg m/s"). | `critique.gd`, I36 | $ | |

---

## The 15 ★★★

N001 text view, N002 body assertions, N004 spec to motion, N006 conflict explainer, N015 pose from supports, N017 event
query, N018 lint any clip, N027 who could do this, N028 coupled limits, N040 throw truth, N065 hit harder, N066 never
falls while posing, N080 hitstun and frame advantage, N082 reactable or not, N091 explain this motion.

## Build order

**Wave 1: the agent can see, measure and trust (all $ or small $$).** N001 text view, N007 body-frame numbers, N020
trust labels, N022 human facts API, N014 noticeable or not, N017 event query, N011 scene brief, N003 dry run, N002 body
assertions, N018 lint any clip.
Why: every later item is a call an agent makes, so first it must read the body in words, ask the right questions, and
state what "done" means; N018 also opens Kine to clips made in any other tool from day one.

**Wave 2: the agent can fix and create.** N013 safe range sweep, N006 conflict explainer, N005 fix until it passes,
N008 path to a pose, N015 pose from supports, N025 move knobs, N016 move recognizer, N019 try N ways, N004 spec to
motion, N024 Kine-Bench.
Why: with assertions and events in place, the solver side can promise a result or say exactly why not, and Kine-Bench
measures whether the agent loop really works before more is built on it.

**Wave 3: deeper body truth, shown to beginners too.** N027 who could do this, N028 coupled limits, N029 weight
transfer, N031 whole-body speed caps, N065 hit harder, N066 never falls while posing, N064 ouch meter, N074 red spots on
the body, N091 explain this motion, N080 hitstun and frame advantage.
Why: the new judges plug straight into the wave 1-2 agent calls, and the same numbers become the beginner's buttons,
glows and explanations, so one truth feeds both kinds of user.

Rules as in ROADMAP_400: one test per item with real numbers; human claims with an opened source (or marked UNVERIFIED);
Blender ideas only.
