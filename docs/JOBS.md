# Poser jobs benchmark (UPGRADES_200 #221)

Written 2026-10-17 from the docs and the code (README_AI.md, SPEC.md, docs/CLICKS.md, docs/MOTION_RULES.md,
docs/ATTACK_RULES.md, docs/EXPORT.md, UPGRADES_200.md, scripts/main.gd, scripts/scene.gd). Nothing here was run.
Where I could not confirm a feature, it says "not found".
Blender routes were re-checked on 2026-10-17 against the installed Blender 4.5.3 LTS (menu labels and the default keymap,
read from its own scripts) plus manual pages. The manual site pages could not be read in full by the fetch tool (it
returned only the navigation menu), so the manual lines below cite pages whose content was confirmed from search excerpts.

Nick: "i dont wanna make equal them... blender and maya dont explain why walking dont feel natural, or why an arm
inside a body feels weird, we do". So this is not a feature count. It is six real jobs a first-timer does. Each one
gets Blender's route, Poser's route, a score, and the "why" Poser gives (or should give).

Scores:
- CAN'T: Poser cannot do the job today.
- CAN: Poser does it, but Blender is as fast or faster.
- FASTER: fewer steps, or fewer wrong turns, for a first-timer.

HONEST NOTE ON "FASTER". A step count alone does not prove it. #222 says each score needs a test or a recorded run.
None of the scores below has a timed run behind it yet. The step counts are my reading of the docs. Where I say
FASTER, the claim is about steps AND about not getting lost; it still needs a timed first-timer run to be official.

What Poser has today, confirmed (the short list the jobs lean on):
- Cards (key poses) on a timeline; Enter adds the pose as a card; Play interpolates (Natural, Spline, Stepped).
- Drag a part (IK on hands and feet) or use sliders; joints stop at human limits; the body cannot go through itself
  (capsule collision); "Fix moves through the body" exists.
- Mirror: Shift+M mirrors the whole pose; Ctrl+Shift+V pastes mirrored; "Mirror the scene" makes a left-handed copy.
- Plant a foot on a card (it stays where it stood in the card before); pin is on by default, so feet that do not move
  between cards do not slide.
- Hips follow the floor (on_floor): the lowest sole is kept on the ground every frame, unless the scene turns it off.
- Loop checkbox; Check grades the LOOP SEAM (pose 3 deg, 2 cm, speed 0.5 m/s); "Loop: close the seam" copies the
  first card onto the last.
- Moving holds: a held pose keeps drifting a little (the "dead hold" fix). Saved with the scene.
- Check rules (docs/MOTION_RULES.md): SEQUENCE, HIPS TURN, HEAD QUIET, TIP SPEED, STRIKE FRAMES, FIST SPEED, HITCH,
  FOOT SLIDE, LOOP SEAM, BALANCE. Each finding says why, and a Fix button sits under it for some of them.
- Weapons in the hand: bat, staff, knife, hammer, spear, two daggers (one per hand). A sword: not found.
- Export .glb (UE5 mannequin bone names, one animation, a key per frame) and .bvh; "To game" writes the ARPG table.
- A dummy that measures the hit and a hit_react example.

What Poser does not have today (all from UPGRADES_200 and not ticked): props and furniture (#201-213), held objects
other than weapons (#206), import of .glb/.bvh animation (#170, #209), a walk generator (#134), idle breathing
generator (#135), weight-shift drawing (#136), contact detection (#133), any skeleton but the human (#214-220), and
the "why" rules for walking (#224) and for weight and timing (#225).

---

## Job 1. A walk cycle that loops

DONE LOOKS LIKE: a character walks in place, two steps, and the last frame flows into the first with no pop. The feet
do not skate. It feels like a walk, not like a march.

BLENDER ROUTE (4.x, Rigify or Mixamo rig). About 22 steps:
1. Select the armature, press Ctrl+Tab (or the mode menu) for Pose Mode.
2. Set the timeline end to 25 (Timeline, End field). Frame 1.
3. Pose the contact pose: left leg forward, right back, opposite arms. Select bones one at a time, rotate with R or
   move the IK foot controls with G.
4. Select all (A), press I to insert a keyframe (4.x: I keys the channels ticked in Preferences > Animation > Default
   Key Channels, by default Location, Rotation, Scale and Custom Properties; K opens a Keying Set menu instead).
5. Still on frame 1, copy the pose: Pose > Copy Pose (Ctrl+C). Go to frame 13.
6. Pose > Paste Pose Flipped (Ctrl+Shift+V). It does not key by itself. Select all, I.
7. Go to frame 25. Paste frame-1 pose again (Paste Pose, not flipped). I. (Easy to forget: this is the loop.)
8. Go to frame 7. Pose the passing pose: the back leg comes through, the body at its HIGHEST point. Key it.
9. Frame 19: the mirror of that (paste flipped). Key it.
10. Add the down poses (low point) at frames 4 and 16 by hand. Key them. (A good walk needs these. Many first-timers
    skip them, and the walk floats.)
11. Open the Graph Editor (change an editor to Graph Editor, or Shift+F6).
12. Select all curves (A). Channel menu > Extrapolation Mode > Make Cyclic (F-Modifier) (Shift+E in the editor).
13. That adds the Cycles modifier so the clip repeats with no seam.
14. Play (Space). Look for foot sliding. Fix by hand: edit the root (hips) location keys in the Graph Editor or keep
    the IK feet pinned.
15. Make the character travel forward: key the root forward (and match the speed to the stride). (An NLA "root
    motion" setup: unverified, not described here.)
16. Stride and speed must match or the feet slide. No tool tells you. You scrub, watch, adjust, repeat.
17-22. Fix the pop at the seam: copy frame 1's keys to the end frame again if you forgot; check handles are
    auto-clamped; fix arms swinging out of phase; fix the shoulder gimbal flip on a long arm swing if it appears.
Verified against: https://docs.blender.org/manual/en/latest/animation/armatures/posing/editing/copy_paste.html , https://docs.blender.org/manual/en/latest/editors/graph_editor/fcurves/modifiers.html , https://docs.blender.org/manual/en/latest/editors/preferences/animation.html ; Blender 4.5.3 LTS bundled UI and keymap (Pose menu: Copy Pose, Paste Pose, Paste Pose Flipped; Ctrl+C / Ctrl+V / Ctrl+Shift+V in Pose Mode; Channel > Extrapolation Mode > Make Cyclic (F-Modifier), Shift+E; Shift+F6 = Graph Editor; Ctrl+Tab toggles Pose Mode; Timeline header Start/End fields).

WHAT A FIRST-TIMER GETS WRONG: forgetting the last key (the loop pops); feet sliding because stride and speed do not
match; no up/down of the hips so it looks like gliding; arms swinging the wrong way (same side as the leg); gimbal flips
from Euler rotation; Make Cyclic done on some curves but not all.

POSER ROUTE TODAY (confirmed in code and docs). About 14 steps:
1. Open the empty state, or open the walk_bat example (it opens as a copy).
2. Pose contact-left: drag the feet (IK) forward and back, set the arms opposite (drag or sliders). The body cannot
   break a limit.
3. Enter (adds the card).
4. Pose the passing pose, Enter.
5. On the contact card, Shift+M mirrors the pose. Enter adds it as the third card. (Or copy the first card and paste
   mirrored with Ctrl+Shift+V.)
6. Passing pose mirrored: Shift+M, Enter.
7. Tick Loop.
8. Run "Loop: close the seam" (press S, type "loop", Enter): the last card becomes a copy of the first.
9. Press Play.
10. Press Check. It grades the LOOP SEAM and FOOT SLIDE and BALANCE.
11. Read the findings; press Fix where there is a button.
12. Plant a foot on a card (S, "plant") if a foot should hold.
13. Slower / faster: click the card, Slower.
14. Export .glb or .bvh.
Walk generator: not found (#134 open). The hips go up and down on their own (on_floor keeps the lowest sole on the
ground), so the two dips per cycle come partly free. A forward-travel setting for the root across a loop: not found;
the walk is in place.

SCORE: CAN. Poser gives the loop seam as a number and a Fix, Mirror is one key, and the hips find the floor. But there
is no generator, and Check does not grade a walk as a walk (docs/MOTION_RULES.md: "Walk cadence has no walk scene with
steps to read"). Blender's Paste Flipped + Cycles modifier is about the same number of poses.

WHAT POSER EXPLAINS THAT BLENDER DOESN'T: today, "the loop jumps 7 deg / 4 cm at the seam" (LOOP SEAM), "the left foot
slides 3 cm while down" (FOOT SLIDE), "the centre of mass is 5 cm outside the feet" (BALANCE). It should also say why
the walk feels wrong as a walk: stride vs leg length, two hip dips per cycle, arms against legs, heel before toe
(#224). That is the edge no one else has.

UNLOCKED BY: #134 (walk generator, makes it FASTER), #224 (the walk "why", the edge), #133 (contact detection, makes
planting automatic), #146 (foot roll), #136 (weight-shift path), #139 (additive layers for a head turn over a walk).

---

## Job 2. A 3-hit sword combo with the feet planted

DONE LOOKS LIKE: three slashes in a row, each with a wind-up, a fast cut, and a recover. The feet stay where they
should. Nothing slides. The sword hits the same arc each time. It looks heavy, not floaty.

BLENDER ROUTE. About 30 steps:
1. Import or append the sword mesh. Parent it to the hand bone: select the sword, shift-select the armature (active),
   Ctrl+Tab for Pose Mode, select the hand bone, Ctrl+P > Bone (or add a Child Of constraint on the sword with
   target = the armature, Bone = the hand bone, then Set Inverse).
2. Move the sword in the hand until the grip is right (this takes time: the Child Of offset is easy to break).
3. Set the scene to 24 fps; end frame about 60.
4. Pose the guard stance at frame 1. Key it (I).
5. Pose the wind-up (frame 8). Key.
6. Pose the contact (frame 11). Key. The sword tip must travel in an arc: check by Pose > Motion Paths > Calculate
   for the hand bone (settings in Armature properties, Motion Paths panel).
7. Pose the follow-through (frame 15). Key.
8. Repeat for hits 2 and 3 (about 9 more key poses; the second and third hits go in opposite directions).
9. Open the Graph Editor. Select all; set Interpolation Mode (T) to Bezier (or another mode in that menu); fix the speed by editing handles:
   a fast cut needs a steep curve, a slow wind-up a flat one. (Many first-timers leave everything auto and the combo
   feels floaty.)
10. To plant the feet: set IK on legs (Rigify has IK foot controls). Keep the IK foot bone at the same place across
    all keys. Or lock with a Copy Location constraint to an empty. Or Child Of to a world empty.
11. If the feet slide anyway: add an Inverse Kinematics constraint (Pose > Inverse Kinematics > Add IK to Bone,
    Shift+I), keep the foot target fixed, key only the body.
12. Check the sword does not pass through the body (look from three views; no tool warns).
13. Check the weapon speed by eye. There is no number.
14-30. Re-time, re-key, re-check. A combo of 3 hits is usually a few hours the first time (unverified estimate).
Verified against: https://docs.blender.org/manual/en/latest/animation/constraints/relationship/child_of.html , https://docs.blender.org/manual/en/latest/animation/armatures/posing/visualization/motion_paths.html (page body not read) ; Blender 4.5.3 LTS bundled UI (Object > Parent > Bone; Pose > Motion Paths > Calculate; Pose > Inverse Kinematics > Add IK to Bone, Shift+I; T = Set Keyframe Interpolation in the Graph Editor).

WHAT A FIRST-TIMER GETS WRONG: feet sliding between hits (IK feet keyed loosely); a sword that jumps in the hand (Child
Of with no inverse); the blow too slow (floaty) or too fast (a pop); the hips not leading (arms swing alone); the hand
drifting through the chest; Euler gimbal on the shoulder.

POSER ROUTE TODAY. About 16 steps:
1. Pick a weapon (bat, staff, knife, hammer, spear). A sword: not found. A knife or bat stands in for it; its grip and
   length differ. (#154 would add a sword.)
2. Pose the guard, Enter. Pose the wind-up, Enter. Pose the cut, Enter. Pose the follow-through, Enter.
3. For hit 2: copy the cards of hit 1 and mirror them: Ctrl+C, Ctrl+Shift+V (pastes mirrored, weapon moves to the other
   hand; Nick asked for this, #155b/155c, so it is partly open: "the next hit, mirrored" is #155c).
4. Plant the feet: S, "plant", on each card that needs it. Pin is on by default, so feet that stay put do not slide.
5. Press Check.
6. Read the findings: SEQUENCE (hips, then chest, then weapon), HIPS TURN, HEAD QUIET, TIP SPEED, STRIKE FRAMES, HITCH,
   FOOT SLIDE. Press Fix where it offers one (TIP SPEED, STRIKE FRAMES, HITCH, HEAD QUIET, FOOT SLIDE). A Fix never
   adds or deletes a card, and Ctrl+Z undoes it.
7. Press Play, look at the trail (T).
8. Export.
Combo chaining of whole clips (light, light, heavy) as separate moves: not found (#116). Frame data
(startup/active/recovery) on the timeline: not found (#113). The combo3 example in scenes/ is a worked case (and
Nick's long-running one).

SCORE: FASTER. Reasons: the weapon is attached with no Child Of; planting is one command, not an IK setup; Check
grades the swing against recorded human numbers (docs/ATTACK_RULES.md, MOTION_RULES.md) and says what to change.
Caveat: only if a bat, knife or staff is acceptable. For a real sword, CAN'T cleanly (no sword). So: FASTER with the
weapons it has, CAN'T for a sword by name.

WHAT POSER EXPLAINS THAT BLENDER DOESN'T: this is where the edge is real today. "The bat tip reaches 41 m/s; a strong
human swing is about 35" (TIP SPEED). "The weapon turns before the hips: the chest should lead" (SEQUENCE).
"The head drops 56 cm in 130 ms" (HEAD QUIET). "The right foot creeps 5.4 cm into recover" (FOOT SLIDE).
Blender gives none of these.

UNLOCKED BY: #154 (a sword), #155c (mirror a combo), #116 (combo chains), #113 (frame data), #114 (hitbox ribbon),
#223 (every finding states the number and the cause in body terms, partly done already), #225 (weight and timing).

---

## Job 3. Idle breathing

DONE LOOKS LIKE: a character stands still but looks alive. The chest rises and falls, the shoulders move a little, the
head settles. It loops. It does not look like a statue and does not look like it is dancing.

BLENDER ROUTE. About 15 steps:
1. Pose Mode. Pose the standing rest pose. Key it at frame 1 (A, I).
2. Go to frame 36 (about 1.5 s at 24 fps). Rotate the chest bone (R X) a few degrees back and lift the shoulders a bit.
   Key (I).
3. Go back to frame 1, Pose > Copy Pose (Ctrl+C). Go to frame 73 and Pose > Paste Pose (Ctrl+V). I.
4. Add a small weight shift: key the hips sideways at frame 36 by 1 cm.
5. Add the head: offset the keys by 3-4 frames so the head lags the chest (overlap). Do it key by key in the Dope
   Sheet (select the head keys, G, type 3, Enter).
6. Graph Editor > Select all > Channel > Extrapolation Mode > Make Cyclic (F-Modifier) (Shift+E).
7. Slow the curves: set Interpolation (T) to Sinusoidal or Bezier with long handles.
8. Play. Check the breath is not too big. (Easy to overdo. The size of real quiet breathing, "a few mm and a couple of
   degrees": unverified.)
9-15. Retime, adjust, add the arms hanging a little, check the loop.
Verified against: https://docs.blender.org/manual/en/latest/animation/armatures/posing/editing/copy_paste.html , https://docs.blender.org/manual/en/latest/editors/graph_editor/fcurves/modifiers.html ; Blender 4.5.3 LTS bundled UI (Interpolation menu lists Sinusoidal, Bezier; Shift+E Extrapolation Mode). G then a typed number in the Dope Sheet is the standard time move; not looked up in the manual.

WHAT A FIRST-TIMER GETS WRONG: too much movement; all bones in sync (robotic, no overlap); the loop not cyclic; a dead
hold when they key the same pose twice (the pose freezes).

POSER ROUTE TODAY. About 9 steps:
1. Pose a stance. Enter. Add a second card with the chest up and shoulders raised a few degrees (drag the chest, or its
   sliders). Enter. Copy the first card to the end: Ctrl+C on it, then Ctrl+V on a new card. (Or use the idle_bat
   example as a base.)
2. Tick Loop. "Loop: close the seam".
3. Turn on "Moving holds" (ANIMATE tab): a held pose keeps drifting slightly, so it is not dead.
4. Slower on the cards (click the card, Slower) to get a long breath.
5. Check (LOOP SEAM grades the seam).
6. Play. Export.
The "breathing" pass (#135): not found. Moving holds helps but its drift is toward the next card, a fixed amount
(HOLD_DRIFT), not a breath with a slider. Stagger/overlap of the head behind the chest (#130): not found.

SCORE: CAN. About the same as Blender on steps. Moving holds is a real help against the dead hold. No breath tool and
no strength slider.

WHAT POSER EXPLAINS THAT BLENDER DOESN'T: today, the loop seam number. It should say "the chest moves 14 cm: real quiet
breathing is a few mm" and "everything moves on the same frame: real bodies lag" (not found today; this would be a
new rule).

UNLOCKED BY: #135 (breathing loop with a strength slider, makes it FASTER), #130 (overlap and follow-through), #225
(a rule for movement that is too big or has no lag).

---

## Job 4. A jump that lands

DONE LOOKS LIKE: crouch, push off, feet leave the ground, the body goes up and comes down on a bent landing, and the
body settles. The air time feels right. The landing has weight.

BLENDER ROUTE. About 25 steps:
1. Pose Mode. Frame 1: standing. Key.
2. Frame 6: the crouch (hips low, knees bent, arms back). Key.
3. Frame 10: push-off (legs straight, on toes, arms up). Key.
4. Frame 14: apex. The whole body must be above the floor. Move the ROOT/hips up in Z (G Z) and key it. With Rigify
   you move the torso/root controls (exact bone names: unverified). Key.
5. Frame 18: down again, legs reaching. Key.
6. Frame 20: landing contact. Hips low, knees bent. The feet MUST be at floor height here. Key.
7. Frame 24: settle. Key.
8. Graph Editor: check the hips' Z curve is a parabola in the air (gravity): steep at take-off, flat at the apex,
   steep at landing. First-timers leave the curve as a straight line (floaty). Edit the handles to get that shape.
9. Time the air: about 0.4-0.6 s for a small jump. Count the frames.
10. Anticipation (the crouch) and the follow-through (the knee bend on landing) are 3-4 more keys.
11. Plant the feet on the ground before and after: IK with the foot controls keyed to the floor, and not touched in the
    air. Easy to get sliding.
12-25. Adjust, re-key. Typical: an hour for the first (unverified estimate).
Verified against: Blender 4.5.3 LTS bundled UI and keymap (I = Insert Keyframe; Graph Editor T interpolation menu); https://docs.blender.org/manual/en/latest/editors/graph_editor/fcurves/properties.html (page body not read). Rigify torso/root bone names not confirmed (the Rigify rig_features page excerpt seen has no such section).

WHAT A FIRST-TIMER GETS WRONG: a floaty arc (linear instead of parabolic); no anticipation; no knee bend at landing
(stiff legs); the feet sinking through the floor or hovering; no overlap in the arms.

POSER ROUTE TODAY. About 12 steps:
1. Pose the crouch, Enter. The push-off, Enter. The air pose, Enter. The landing, Enter. The settle, Enter.
2. The "hips follow the floor" setting (on_floor) keeps the lowest sole on the floor every frame. For a jump that is
   the problem: in the air the body must leave the floor. A way to turn this off from the window: not found in main.gd
   (it is in the scene file as "on_floor"; set it by hand in the .json, or use the hips up/down slider on the card
   if on_floor allows it). I could not confirm this works in the window.
3. The example leap_slam (scenes/_wip/leap_slam.json) is a jump with a landing, and FOOT SLIDE was tuned on landings,
   and the rulebook knows a foot is "off the ground" at 5 cm (AIR in rulebook.gd; HEAD QUIET stands down in jumps).
   So the engine knows what a jump is. But it does not build one from a button.
4. Check: BALANCE, FOOT SLIDE and the rest. No rule says "the apex is too low" or "the landing is stiff": not found.
5. Play, Export.

SCORE: CAN, barely. The pieces exist (leap_slam, the AIR threshold, floor_body) and Check will not call a jump a
mistake. But I could not confirm a window control for a clean airborne pose, there is no gravity arc check, and no
landing rule. It could be CAN'T if on_floor cannot be turned off from the UI. I cannot say which without running it;
treat it as CAN'T-until-verified for a first-timer.

WHAT POSER EXPLAINS THAT BLENDER DOESN'T: should say "the hang time is 0.9 s: a jump of this height takes 0.5 s",
"the hips follow a straight line, not a parabola (floaty)", "the knees do not bend on landing (stiff)", "no crouch
before the push-off". None of these exists. (The hang-time-versus-height fact is physics, and is exactly the kind of
rule that fits docs/MOTION_RULES.md.)

UNLOCKED BY: a window switch for off-floor / airborne cards (no UPGRADES_200 number covers it exactly; closest are
#149, hips height on the ground, and #136, centre-of-mass path). #225 (weight and timing: anticipation, follow-through,
pops). A new item is needed: "Jump rule: hang time vs height, the arc as a parabola, landing absorbs" (suggest #228).
#133 (contact detection) would find take-off and landing frames automatically.

---

## Job 5. Sitting down on a chair

DONE LOOKS LIKE: a character walks up, turns, lowers, and sits on a chair. The hips are ON the seat, not through it
and not above it. The feet are flat on the floor. The back is supported. The body weight shifts back before it sits.

BLENDER ROUTE. About 24 steps:
1. Add the chair: Add > Mesh > Cube, scale it into a seat (S), or import one. Place it at the right height (45 cm).
2. Pose Mode on the character. Frame 1: standing next to the chair, facing away from it.
3. Frame 10: start to bend the knees and tilt the torso. Key.
4. Frame 20: the hips lowered about halfway. Key. The hips must not pass through the seat, and Blender does not stop
   you.
5. Frame 30: sat. Move the hips down (G Z) until they touch the seat top. This is by eye. Key.
6. Feet flat: move the IK foot controls so the soles are on the floor and do not slide while the hips go down. Key.
7. Rotate the thighs to be horizontal, the shins vertical, the torso upright.
8. Add hand positions: hands on knees. IK hand controls. Key.
9. Graph Editor: edit the hips' curve to slow into the seat (a soft landing).
10. Check the hips do not pass through the chair (switch to wireframe or X-ray, Alt+Z, to see).
11. Optional: Shrinkwrap or Copy Location constraint to hold the hips to the seat; Child Of to attach the hands.
12-24. Fix penetration, slide, and the "fall" at the end where the body drops the last cm.
Verified against: Blender 4.5.3 LTS bundled UI and keymap (Add > Mesh > Cube; Alt+Z = toggle X-ray; Shrinkwrap, Copy Location and Child Of exist as constraints); https://docs.blender.org/manual/en/latest/animation/constraints/relationship/child_of.html . Shrinkwrap to hold hips to a seat: unverified as a normal method.

WHAT A FIRST-TIMER GETS WRONG: hips through the seat or floating above it; feet sliding as the body lowers; the thighs
sinking into the chair; no weight shift (the body just falls down); the sit is a linear drop with no ease.

POSER ROUTE TODAY. Props: not found. There is no chair (#201 open). The mannequin cannot sit ON anything because
nothing is there. One could pose a seated body in the air (moves/seated_on_knee.json is a seated-on-a-knee pose in the
repo), but there is no surface to check the hips against and no way to show the chair.
1. Pose a seated pose, Enter, and with on_floor the hips fall to keep the sole on the floor (so the body cannot stay
   seated in the air unless floor_body or on_floor is changed).
SCORE: CAN'T. No chair, no support contact, no "the hips float above the seat".

WHAT POSER EXPLAINS THAT BLENDER DOESN'T: should say "the hips are 9 cm above the seat: the body is floating",
"the thighs sink 4 cm into the seat", "the weight has not moved over the feet before the hips leave: the body would
fall back" (BALANCE exists for standing; sitting needs support from the seat, #204).

UNLOCKED BY: #201 (props at real sizes: a chair), #202 (props in the scene file, snapped to the floor), #203 (solid
props: no passing through), #204 (support contact: hips on a seat count as allowed, floating is flagged), #205
(interaction snap: "sit" one click). With those four it is CAN, and with #205 it is FASTER (one click to sit, against
Blender's 24 steps). #207 (the chair in the .glb export).

---

## Job 6. Picking up a box

DONE LOOKS LIKE: the character walks to a box on the floor, bends (knees, back straight), takes it with both hands, and
stands with it at the chest. The box moves WITH the hands from the moment it is lifted. No box floating before the
hands touch it. The legs lift, not just the back.

BLENDER ROUTE. About 26 steps:
1. Add a cube (Add > Mesh > Cube), scale to 40 cm, rest it on the floor.
2. Frame 1: character beside the box. Key.
3. Frame 15: crouch with the knees bent, hands at the box sides (IK hand controls, G). Key.
4. At the moment of pickup: the box must switch from the world to the hands. This is the hard part for a first-timer:
   - Add a Child Of constraint on the box, target = the hand control (or a null/empty between the hands), Set Inverse
     at the exact frame.
   - Key the constraint's Influence: 0 before the pickup frame, 1 after (right-click the Influence slider > Insert
     Keyframe (or hover and press I), then set it constant interpolation in the Graph Editor (T > Constant) so there
     is no blend).
5. Frame 30: stand with the box. Key. The box follows through the constraint.
6. Both hands must stay on the box sides: IK controls with Copy Location to two empties on the box faces. Or key them.
7. Graph Editor: slow the lift, make the stand ease out.
8. Check the box does not pass through the body or the legs.
9. Check weight: the body should lean back a little when it holds a heavy box. By eye.
10-26. Fix the box's jump at the constraint switch (the usual bug), fix the hand slide, and fix the back bending
    instead of the knees.
Verified against: https://docs.blender.org/manual/en/latest/animation/constraints/relationship/child_of.html (Set Inverse; Influence can be keyed; the page says to click Set Inverse after assigning the parent, with other constraints at Influence 0 and before moving the target). The full pickup recipe (key Influence 0 -> 1, constant interpolation, Set Inverse at the pickup frame) is a synthesis, not written in the manual; Blender 4.5.3 LTS bundled UI (Set Inverse button exists).

WHAT A FIRST-TIMER GETS WRONG: the box jumps when Child Of switches on (no Set Inverse, or the wrong frame);
the influence is blended (it slides from the floor to the hand over frames); hands slide on the box; the back bends
instead of the knees; the box clips into the chest; no lean-back for weight.

POSER ROUTE TODAY. Held objects other than weapons: not found (#206 open). Only the weapon system (bat, staff, knife,
hammer, spear, two daggers) can be held. A "box" would have to be a weapon stand-in. No box, no put-down, no both-hands
on a box.
SCORE: CAN'T.

WHAT POSER EXPLAINS THAT BLENDER DOESN'T: should say "the hands touch the box at card 4 but the box does not move until
card 6", "the back bends 62 deg while the knees stay straight: the lift is on the spine", "the box is held 38 cm from
the chest: carrying it that far out is a heavy load; a body would lean back" (BALANCE would catch the lean).
The BALANCE rule exists and would read the extra mass only after the object has mass; it has none today.

UNLOCKED BY: #201 (a box prop at 40 cm), #206 (held objects: pick up in one or two hands, carry, put down at a
card), #203 (solid), #204/#205 (the box "step up" and the support), #207 (the box in the .glb). A new rule for lifting
form (back angle vs knee angle) fits #225 (suggest #229).

---

## Summary table

| # | job | score today | blocking upgrades |
|---|---|---|---|
| 1 | a walk cycle that loops | CAN | #134 walk generator, #224 walk "why", #133 contacts |
| 2 | a 3-hit sword combo, feet planted | FASTER (with bat/knife/staff); CAN'T for a named sword | #154 sword, #155c mirror a combo, #116 combo chains |
| 3 | idle breathing | CAN | #135 breathing loop, #130 overlap |
| 4 | a jump that lands | CAN'T until verified (pieces exist) | an off-floor switch in the window (new), #225, jump rule (new #228) |
| 5 | sitting down on a chair | CAN'T | #201, #202, #203, #204, #205 |
| 6 | picking up a box | CAN'T | #201, #206 (+ #203, #205) |

Count today: FASTER 1, CAN 2, CAN'T 3 (one of them, the jump, is a probable CAN once verified). Per #227, the honest
fundraiser line today is: "FASTER than Blender on 1 of 6 jobs for a first-timer, and the 'why' is the reason". Do not
write more than that until each score has a timed run (#222).

## What to build next, by jobs unlocked

Counting every job an upgrade helps move up a score (CAN'T to CAN, or CAN to FASTER):

| rank | upgrade | jobs it helps | which |
|---|---|---|---|
| 1 | #201 (the starter set of props) | 2 | sit on a chair, pick up a box |
| 1 | #206 (held objects) / #205 (interaction snaps) | 2 and 1 | box; chair (#205) and box step-up |
| 1 | #203 + #204 (solid props, support contact) | 2 | chair, box |
| 2 | #225 (weight and timing "why") | 3 | jump, idle breathing, sword combo (anticipation, follow-through) |
| 3 | #224 + #134 + #133 (walk "why", walk generator, contacts) | 1 to 2 | walk (all three), jump (#133 finds take-off and landing) |
| 4 | #135 / #130 (breathing, overlap) | 2 | idle breathing, walk arms |
| 5 | #154 + #155c + #116 (sword, mirror a combo, chains) | 1 | the sword combo |

The props block (#201-#205, #206) turns two CAN'T into CAN, and with #205 into FASTER, in one stretch of work. The
"why" block (#225, #224) lifts the most jobs at the lowest cost, because the rulebook, the numbers and the Check
button already exist: only new rules need writing. The sword combo is already the best job.

TOP 3 BY JOBS UNLOCKED: (1) #201 plus #203/#204 (props, solid, support): chair and box. (2) #206 held objects (box,
and later a cup) with #205 snaps. (3) #225 weight/timing rules (jump, breathing, combo, and it feeds the walk).

Items that do not exist in UPGRADES_200 but the jobs need: an off-floor/airborne switch in the window (jump); a jump
rule (hang time against height, the arc, a stiff landing); a lifting-form rule (back vs knees). Suggested as #228,
#229, and one for the switch. Needs Nick's call.
