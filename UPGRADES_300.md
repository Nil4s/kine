# Poser: the next 100 upgrades (238–337), on the same footing as Maya and Blender

Drafted 2026-10-17 after round 40 (Nick: "lets plan the next 100 ones to be in same foot as maya/blender").
Built from two surveys made that day:
- Maya 2025/2026 and Blender 4.x/5.x manuals, area by area: keys, curves, dope sheet/NLA/Time Editor, rigging,
  posing, skin, face, mocap, physics, review, pipeline. The sources are listed per section below.
- What Poser can do today. Poser already has things those two don't: a Check rulebook that names the cause and the
  number, flights and gravity checked against physics, real-people bars, an agent and CLI that drive every command,
  and a first-timer path.

THE GAP, in one line each:
- No curves. Every key is a whole-body card with one of 5 eases. Maya and Blender key every channel and shape it
  with tangents.
- No layers. Maya has additive/override animation layers and the Time Editor; Blender has NLA strips.
- No rig controls. Poser has no constraints, space switching, FK/IK switching, drivers, or a custom rig (section J of
  UPGRADES_200 is the skeleton-as-data part).
- No skin, shape keys, or correctives.
- No mocap in. BVH and .glb are export-only.
- No secondary motion or physics beyond the gravity of a dropped prop.
- No playblast to video, no camera animation, no 2D notes over the view.
- No FBX, no USD, no referencing.

THE RULE FOR THIS LIST: match what an animator DOES in Maya or Blender, not the menu. Each item keeps Poser's edge:
it is checked by a number, it has a reason a first-timer can read, it can be driven by the agent, and wherever a
body moves it is compared with REAL PEOPLE first (README_AI house rule, 2026-10-17).

Same rules as before:
- Gates go in GATES.md first. Each item gets a real test, with an anti-vacuity stub, and is ticked only with
  evidence.
- Never write scenes/, poses/ or data/.
- Run all suites after each round.
- Older items still open are referenced by number, not repeated. UPGRADES_100: #52 curve editor, #55 pose library,
  #56 clip blend. UPGRADES_200: #139 additive layers, #145 head look-at, #146 foot roll, #209 animation import, the
  J section (any skeleton) and the L section (the face).

Tags:
- [CRV] curves
- [LYR] layers and clips
- [RIG] controls
- [POSE] posing
- [SKIN] deformation
- [MOCAP] capture in
- [SIM] secondary and physics
- [REV] viewport and review
- [PIPE] files and pipeline
- [REAL] the people library

**DECIDED** marks a design call I made (Nick 10-17: "u can tell me what u gonna do"). It is written down so it
can be argued with.

---

## M. KEYS BY THE PART, AND CURVES (238–251)
Sources:
- https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/editors/graph_editor/fcurves/editing.rst
- https://help.autodesk.com/cloudhelp/2023/ENU/Maya-Animation/files/GUID-6D38EAEA-6032-471E-BD0E-54A74D4443C0.htm

**DECIDED: the data model.** Cards stay the main key, a whole-body pose, because a first-timer thinks in poses.
On top of them, a scene can hold PART KEYS: one joint, one axis, a time, a value, and two tangent handles. A part
key overrides the card blend for that channel only. A scene with no part keys plays byte for byte as today, which
is the guard for every item in this section.

238. [CRV] Part keys in the scene file (schema, validator, save/load, mirror, undo). The empty case must stay
     identical to the byte.
239. [CRV] Key one part (K on a selected part): its 3 angles at the playhead. The card strip shows a small tick
     where it is keyed.
240. [CRV] The curve editor (builds #52): one curve per channel against time, colours X red / Y green / Z blue.
     Frame-all and frame-selected, zoom, pan, and click to scrub.
241. [CRV] Interpolation per key, using Blender's set: constant, linear, Bézier. The cards' 5 eases become presets
     that write handles.
242. [CRV] Handle types: auto-clamped (the default, never overshoots), auto, vector, aligned, free. Each is tested
     by numbers on the curve.
243. [CRV] Move, scale and drag keys in the editor, with snap to frame and to card, and box select. Every edit is
     one undo step.
244. [CRV] The Euler filter (Maya Curves > Euler Filter; Blender Discontinuity Filter): turns that jump 360 degrees
     between keys are unwrapped. Tested on a spin that crosses ±180.
245. [CRV] Smooth (Gaussian), Butterworth smooth, Decimate (by error) and Clean keyframes. Each reports how many keys
     it removed and the worst angle error.
246. [CRV] Shape tools from Blender's list: blend to neighbour, ease, push/pull, match slope, scale from neighbour.
     Each works on the selected keys.
247. [CRV] Cycles and infinity: hold, linear, cycle, cycle with offset. A walk loop then needs no copied cards, and
     LOOP SEAM reads the cycle.
248. [CRV] Curve modifiers: noise (for idle breathing and hands), stepped (for blocking on 2s), and limits.
     Non-destructive, each with a mix value.
249. [CRV] Normalized and stacked views (Maya Graph Editor): every channel fitted to −1..1, or one lane each.
250. [CRV] Bake: curves and part keys flattened into cards at a chosen rate, for export and for agents that read
     cards.
251. [CRV] The WHY of a curve: the editor colours a span red where the joint's speed breaks a Check rule (HITCH, TIP
     SPEED), naming the rule. No other curve editor tells you why a curve looks wrong.

## N. DOPE SHEET, LAYERS AND CLIPS (252–263)
Sources:
- https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/editors/nla/strips.rst
- Maya animation layers and Time Editor clips (help.autodesk.com MayaCRE-Animation GUID-63B2245A..., GUID-B3FFE1AA...)

252. [LYR] Dope sheet: one row per body part, keys as diamonds. Card keys (whole body) and part keys are both shown.
     Drag keys in time; Shift-drag copies.
253. [LYR] Key types, as Blender marks them: key, breakdown, moving hold, extreme. The type is shown in the dope
     sheet and the strip. Stepped view shows only keys and extremes.
254. [LYR] Animation layers (builds #139). Additive or override, a weight per layer that can itself be keyed, mute,
     solo, and lock.
255. [LYR] "Fix it on a layer": a Check Fix can go onto a new layer instead of the base. The base stays untouched
     and the fix's weight can be dialled.
256. [LYR] Merge layers down. The merged scene samples identically to the layered one (tolerance printed).
257. [LYR] Clips: a scene, or a range of one, saved as a clip. Clips are placed on tracks in a sequence, which is
     NLA / Time Editor style.
258. [LYR] Clip blend (builds #56): a crossfade with its own length and ease. FOOT SLIDE is checked across the
     seam, with the feet matched.
259. [LYR] Clip scale, hold, loop count, and speed per clip. Retiming a clip keeps its contact frames on whole
     frames.
260. [LYR] Pose clips (Maya Time Editor): one pose held over a span, layered over a motion. Example: a fist held
     through a run.
261. [LYR] Markers: named, coloured, on the ruler. Jump with Ctrl-[ and ], and they export as events
     (UPGRADES_200 #106).
262. [LYR] The timeline in frames or seconds with a fps choice (24/30/60). A fps change keeps times; keys stay on
     whole frames.
263. [LYR] Preview range: play and loop only a span, without changing the scene.

## O. RIG CONTROLS AND CONSTRAINTS (264–277)
Sources:
- https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/animation/constraints/index.rst
- Maya HumanIK, IK spline and set driven key (help.autodesk.com MayaCRE-CharacterAnimation)

264. [RIG] Constraints, the first five: child-of/parent (hand to weapon, prop to hand), point, orient, aim, and
     limit rotation. Each has an influence that can be keyed.
265. [RIG] Space switching without a pop: a hand goes from world to hips to the other hand, and its world position
     is kept at the switch frame (to 0.1 mm).
266. [RIG] FK/IK switch per limb, plus match (Maya Set IK/FK Key). The limb looks the same before and after the
     switch (to 0.1 mm / 0.1 deg).
267. [RIG] Pole targets you can see and drag for elbows and knees. They are keyable and replace the swing-pole
     command.
268. [RIG] IK chain length and stretch off/on, with the limit printed when a target is out of reach (no silent
     snap).
269. [RIG] Spine IK (Maya IK spline / Blender Spline IK): drag the chest and the spine curves through its joints.
     Each joint stays under its limit.
270. [RIG] Foot roll (builds #146): heel, ball and toe pivots on one control. Compared with real gait: about 15 deg
     heel strike, about 50 deg toe-off at push.
271. [RIG] Head and eye look-at (builds #145): an aim target with a neck share, so the neck turns about 60 % and the
     eyes do the rest. The split is from real gaze-shift data; look it up first.
272. [RIG] Drivers (Blender) / set driven key (Maya): one part's angle drives another's. Example: the fingers curl
     as the wrist bends. A small rule editor.
273. [RIG] Custom control shapes: rings and boxes around joints, pickable in the view. Different sizes keep small
     parts easy to grab.
274. [RIG] Part groups like Blender bone collections: arms, legs, fingers, face. Show, hide, solo, and lock by
     group (builds on selection sets).
275. [RIG] Character picker panel: a flat body diagram you click to select. Maya and Blender rely on add-ons for
     this; ours is built in.
276. [RIG] Rig profiles (builds UPGRADES_200 J #214–220): the controls above read the profile, so a mech or a
     spider gets them too.
277. [RIG] A constraint health check: a cycle (A follows B follows A), zero influence everywhere, or a target
     missing after a delete. Each is named with a fix.

## P. POSING TOOLS (278–287)
Sources:
- https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/animation/in_betweens.rst
- https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/animation/armatures/posing/editing/pose_library.rst

278. [POSE] Breakdowner (Blender Shift-E): a slider between the card before and after (0..100 %). Values past the
     ends overshoot, which is how breakdowns are really made.
279. [POSE] Push and relax (Blender Ctrl-E / Alt-E): push the pose away from, or toward, the in-between of its
     neighbours.
280. [POSE] Blend to rest and blend to neighbour, for the selected parts only.
281. [POSE] Pose library (builds #55): thumbnails, catalogs, search, apply, apply flipped, blend by drag, and
     select the parts a pose touches.
282. [POSE] Paste flipped with "selected only" and a factor (Blender Paste Pose Flipped options).
283. [POSE] Motion trails you can edit (Maya editable motion trails): drag a dot on the trail and the key under it
     moves.
284. [POSE] Ghosts of any card, pinned (Maya Ghost Editor): choose which cards to show, not only the two
     neighbours.
285. [POSE] Selection masks (click only arms, only legs, or only weapon) and a mirror axis that follows a turned
     body. Mirror today assumes the body faces +Z.
286. [POSE] Pose from a photo, in two steps. First, a 2D reference image behind the body. Second, the joints'
     screen spots marked on it, and IK fits the body to them. Compared by the reprojection error in pixels.
287. [POSE] A "real people" pose check: the pose's joint angles against a reference pose of the same action. The
     differences are listed per joint, in degrees.

## Q. SKIN AND DEFORMATION (288–295)
Sources:
- https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/animation/armatures/skinning/parenting.rst
- Maya Paint Skin Weights, Pose Editor and Shape Editor (help.autodesk.com 2026 Maya-CharacterAnimation)

288. [SKIN] Bind an imported character mesh to the skeleton with automatic weights (heat, as Blender does). Every
     vertex's weights sum to 1.
289. [SKIN] Weight view: the colour per part as you hover, and the vertices a part moves.
290. [SKIN] Weight paint: add, subtract, smooth, and normalize. Locked parts stay as they are.
291. [SKIN] Volume check: elbows and knees lose volume when they bend (the candy-wrapper effect). The loss is
     measured per joint in % and flagged over a bar.
292. [SKIN] Corrective shapes: a shape fixes a pose and turns on as the joint reaches it (Maya Pose Editor /
     Blender drivers + shape keys).
293. [SKIN] Shape keys on any mesh: sliders and keys, and they export to .glb as morph targets.
294. [SKIN] Dual-quaternion skinning as an option. The volume check is compared both ways, with numbers.
295. [SKIN] Clothes and armour pieces that follow parts rigidly. Collision with the body is checked, as for props.

## R. MOCAP IN, RETARGET, CLEAN (296–305)
Sources:
- https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/files/import_export/bvh.rst
- Maya HumanIK retargeting (help.autodesk.com MayaCRE-CharacterAnimation GUID-B2E9F8B9...)

296. [MOCAP] BVH import (builds #209): axes, scale, fps, and rotation order. A BVH exported by Poser comes back
     identical (round trip, to 0.01 deg).
297. [MOCAP] Retarget onto Poser's body: a bone map, rest-pose matching, and a scale from leg length. The error is
     reported per joint.
298. [MOCAP] Retarget from rigged .glb and FBX (where FBX is supported; see 326).
299. [MOCAP] Foot lock on mocap: contacts are found by speed and height, then planted. FOOT SLIDE before and after
     is printed.
300. [MOCAP] Key reduction from mocap to animator keys: keys per second before and after, and the worst error.
301. [MOCAP] Mocap on a layer, with the animator's fixes on an override layer above it (Maya's HumanIK workflow).
302. [MOCAP] REAL MOTION LIBRARY: public CC0/CC-BY mocap (a walk, a run, a jump, a lift) loaded as reference
     ghosts beside the body. Sources and licences are checked before anything is downloaded.
303. [MOCAP] Compare to mocap: our clip against a real one, time-warped to match. The angle difference is given per
     joint, over time, as a strip.
304. [MOCAP] Video to clip (from UPGRADES_200 #191): pose estimation is a pretrained model, so it needs Nick's OK
     (house rule). **NICK?**
305. [MOCAP] Mocap cleanup report: joint pops, flips, and limbs through the body, each with the frame and a fix.

## S. SECONDARY MOTION AND PHYSICS (306–313)
Source: https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/physics/index.rst

306. [SIM] Spring bones (jiggle): a damped spring per chain (ponytail, cloth strip, antenna). Stiffness and damping
     settings, baked to keys.
307. [SIM] Overlap and follow-through on a chain: the delay per joint from the parent. Compared with filmed arm
     swing before it ships.
308. [SIM] Rigid props under gravity in motion, not only dropped: a thrown box flies a parabola and bounces with a
     set restitution. Checked against the formulas, as the drop is.
309. [SIM] Ragdoll to keys: the body falls from a pose under gravity, with joint limits and collisions, and is
     baked. Checked against fall time.
310. [SIM] Balance assist: a key that would tip the body over gets a suggested hip shift, the smallest one that
     brings the CoM over the feet.
311. [SIM] Momentum check: in a flight the CoM must follow the parabola. Arms flailing cannot change it. Flag
     clips where the CoM path is not ballistic (#228 extended to the CoM).
312. [SIM] Landing impact: the hip drop and knee bend after touchdown, against the flight height. A higher fall
     needs a deeper bend, from the real landing data.
313. [SIM] Cloth strip (cape, belt tail) as a chain of springs with body collision. Baked, and exported as bones.

## T. VIEWPORT AND REVIEW (314–323)
Sources:
- Maya playblast and Camera Sequencer (help.autodesk.com 2026 Maya-Animation GUID-F976E7C0...)
- https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/grease_pencil/index.rst

314. [REV] Playblast to video, using Godot's MovieWriter: MP4/AVI or PNG frames with a burn-in of the scene name,
     frame, time, and Check count.
315. [REV] Animated camera: camera keys, focal length, and the camera's own curves. The view through the camera
     shows a safe-frame overlay.
316. [REV] Camera sequencer: shots as camera plus range, played as one cut. The playblast exports the cut.
317. [REV] Draw over the view (Maya Grease Pencil / Blender annotations): 2D strokes tied to a frame, with ghosts
     of nearby strokes. For notes and for drawn arcs to match.
318. [REV] Shading modes: solid, matcap, silhouette (for #143 silhouette reading), and X-ray (#162).
319. [REV] Split view: two cameras side by side (builds UPGRADES_100 #31), for example the front and the game
     camera.
320. [REV] Isolate selected: only the picked parts and props are drawn (#163).
321. [REV] Review sheet: one page per scene with a frame strip, the Check findings, and notes (#174). Exported as
     HTML.
322. [REV] Compare two clips: ghosts of version A over version B, and the per-joint difference over time (#171).
323. [REV] Frame-rate truth: playback shows the real fps reached. A dropped frame is reported, not hidden.

## U. FILES AND PIPELINE (324–331)
Sources:
- https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/files/import_export/index.rst
- Maya Reference Editor and Game Exporter (help.autodesk.com MayaCRE-ManagingScenes)

324. [PIPE] .glb export with props and the set (#207), morph targets (293), and several clips as separate
     animations in one file.
325. [PIPE] Export straight to Unity, Unreal, and Godot presets: axes, scale, root motion on or off, and a re-import
     test for each.
326. [PIPE] FBX. There is no native writer in Godot. **DECIDED:** go through Blender headless with the user's own
     Blender install, never shipped. Checked by a round trip. If no Blender is found, say so plainly.
327. [PIPE] USD export (USDA text) of the skeleton animation, and a round-trip test for it.
328. [PIPE] Referencing: a scene can link a clip, a set, or a character from another file, and the change follows.
     Local overrides as in Blender library overrides.
329. [PIPE] Scripting: a GDScript/Python-like macro file of registry commands, run from the CLI and a panel, and
     recordable from what you do (Maya echo-all).
330. [PIPE] Plug-ins: a folder of add-on scripts that can add a command, a Check rule, or an exporter. Each is
     sandboxed to scenes/_wip and gets its own test.
331. [PIPE] Batch everything: check, bake, and export a folder of scenes with one command and a report (builds
     #107).

## V. THE PEOPLE LIBRARY: OUR EDGE (332–337)
Neither app tells you a pose is wrong for a human. We do, and every bar comes from a real measurement.

332. [REAL] docs/PEOPLE.md: every reference used (carry, jump, landing, lift, gait, gaze, reach). Each entry has the
     source, the numbers, and the test that uses it. It grows with every round.
333. [REAL] Gait bars from real walking data: step length against height, cadence, arm swing angle, and hip drop.
     A WALK FEEL rule (UPGRADES_200 #224).
334. [REAL] Lifting form (UPGRADES_200 #229) from NIOSH and lifting kinematics: back and knee angles at the floor.
335. [REAL] Reach and comfort zones from ergonomics data. A hand that works long above the shoulder or far out is
     named.
336. [REAL] Combat-specific references: punch and swing timing, and hip-shoulder separation from sports
     biomechanics papers. These sharpen SEQUENCE and HIPS TURN, whose bars came from coaching texts.
337. [REAL] A "show me a real one" button on any finding: the reference's numbers next to ours, and the link to
     the source.
338. [RIG][REAL] ONE GRIP STANDARD FOR EVERY HANDLE, AND A MAGNETIC HAND (Nick 10-18: "a standard method for hands
     and grips on weapons depending on how it's held, because the circumference of a grip is usually the same ...
     dagger, sword, hammer, staff, bo, bow, rifle ... so we never have this issue with hands again"; "a magnetic
     version for hands that could adapt within its limits to weapons and their limits of grip").
     - A HANDLE is described, not drawn: its cross-section (round / oval / flat, diameter in mm), its length, and
       which GRIP TYPES it takes (power grip round a shaft; the pistol-style grip of a rifle or bow; the light
       precision hold of a dagger flipped in the fingers; the sliding hand on a staff or axe haft).
     - A GRIP is solved from the hand and the handle: each finger closes round that diameter until it touches
       (joint limits from real hands), the thumb wraps or lies along it, by type. Ten weapons become ten numbers
       plus a type, not ten hand-posed files; a new weapon gets a hand that fits on day one.
     - THE MAGNET: near a handle, a hand snaps into the grip and can SLIDE along it (and roll round it) within the
       handle's grippable length and the arm's reach; pulled past its limits it lets go instead of breaking the arm.
       It replaces today's per-weapon G / grip_u / grip2 special cases with one rule.
     - SEEDED FROM NICK'S OWN FIXES, then checked against people: data/grips/metal_bat.json and staff.json (fitted
       by Nick 10-12/13) and his long-axe left hand (scenes/axe_strike_pose.json, cards v0-v20: the second hand high
       on the haft, 0.76-0.94 m of 1.2, the elbow opened). Each solved grip must reproduce his within a bar BEFORE it
       replaces them.
     - REAL HANDS FIRST (to read and cite before any number goes in): Napier's power vs precision grip
       classification; handle-diameter studies (grip force against diameter, the comfortable range as a share of
       hand length); hand anthropometry tables for finger lengths. Numbers only from the papers themselves.
     - TEST: for every weapon, the fingers touch the handle and do not go inside it, the palm is on it, the grip
       holds through a swing with no jump, and the magnet's slide stops at the handle's ends.

---

## ORDER I'LL BUILD THEM IN
1. M (curves and part keys). Everything else in Maya and Blender sits on per-channel keys.
2. N (layers and clips).
3. P (posing tools). They are cheap once part keys exist.
4. O (controls).
5. R (mocap).
6. T (review).
7. S (secondary motion).
8. U (pipeline).
9. Q (skin) last, because it needs an imported character first (UPGRADES_200 I/J).

V runs alongside every round: each new motion gets its people numbers before it is shown.
