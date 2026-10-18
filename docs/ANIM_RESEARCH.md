# Maya/Blender character animation -> what Poser should take, and what to add

Poser coverage was read from README_AI.md (rounds 10-42) and docs/COMPLAINTS.md. "Not found" means I did not find it there; I did not read scripts/.
Web sources are forum threads and docs from search results (snippets, not full pages). Where a claim is mine, it is marked (mine).

## 1. How it is done, and what Poser already has

Workflow: BLOCK in stepped keys (key poses, spacing, no timing polish; a key every 3-4 frames before splining) -> add breakdowns while still stepped -> SPLINE (switch tangents, fix bumps in the graph editor) -> POLISH (arcs, overlap, moving holds). Pose-to-pose = block then refine; straight-ahead = key frame after frame, more fluid but harder to retime. Sources: https://blog.animschool.edu/tag/animation-blocking-tips/ , https://animation.binus.ac.id/?p=5046 , https://forum.reallusion.com/424001/Group1.aspx

| Concept | What it is | Poser equivalent |
|---|---|---|
| Stepped blocking | Each key holds until the next | YES: Stepped preview (Scene.stepped), COMPLAINTS #6 |
| Splining | Smooth interpolation between keys | YES: scene "spline" flag (GATES A), per-card eases (Scene.EASES) |
| Breakdown / inbetween | Key between extremes for arc/overlap | YES: breakdowner.gd (Shift+E, push/relax), card ktype key/breakdown/moving_hold/extreme |
| Dope sheet | Keys as diamonds per channel group, retime by dragging | YES: dope_sheet.gd (8 part groups) |
| Graph editor | Per-channel curves with tangents | PARTLY: curve_editor.gd (X/Y/Z), speed graph, curves.gd filters (Butterworth, decimate, unwrap) |
| Euler filter / gimbal | Fix flipping Euler curves | YES by construction: swing/twist joints, flip_survey (COMPLAINTS #1) |
| Motion trails | Path of a point over time | YES: trail coloured by speed (GATES D); NOT editable (Maya's editable trail lets you drag path points) |
| Ghosting / onion skin | Poses before/after the playhead | YES: onion (O), spacing ghosts (Shift+O) |
| FK/IK switch | Pose a limb by joints or by end effector | PARTLY: IK drags exist; pin/step/free anchors; no explicit FK<->IK blend with snap |
| Space switching | Re-parent a control (hand to world / body / prop) | NOT found as a user feature (grip/carry/throw exist per prop) |
| Constraints (parent/aim/point) | Drive an object from another | LOOK-AT only (look_at.gd); no general constraints |
| Animation layers (Maya) / NLA tracks (Blender) | Additive tweak on top of a base without destroying it | NOT found. Closest: part_keys.gd, moving holds |
| Time Editor / Trax / NLA clips | Reusable clips, blend, retime, loop | PARTLY: scene Loop, preview range, markers (markers.gd), card copy/paste; no clip library/blend |
| Blender Action | Keys container reusable across objects | PARTLY: scene JSON files, versions |
| Retargeting / HumanIK | Map motion onto a different skeleton with IK correction | PARTLY: BVH import (bvh_import.gd) + mocap_clean (foot lock, pop finder); no proportion-aware retarget |
| Pose mirror / paste flipped | Left-right swap | YES: Shift+M, pose_paste(mirrored) |
| Playblast | Fast preview render | YES: --playblast AVI with burn-in |
| Markers | Named cues on timeline | YES: markers.gd |

## 2. Pain points for human animation (with sources)

1. IK/FK switch pops, snap fails. Maya arm jumps at the wrist on switch: https://forums.autodesk.com/t5/maya-animation-and-rigging-forum/ik-to-fk-switch-snapping-issue/m-p/13231913 . FK and IK are separate rigs, switching gives a different pose: https://courses.cs.washington.edu/courses/cse459/18au/tutorials/productionrig/ . Blender Rigify snap bugs (pole target jumps, inconsistent result): https://projects.blender.org/blender/blender-addons/issues/86792 , https://projects.blender.org/blender/blender-addons/issues/105309 . IK->FK is a copy of rotations; FK->IK needs the pole placed on the joint plane: https://blenderartists.org/t/ik-fk-snap-switch-how/697177
2. IK knee popping near straight legs; foot slide from parenting/switch mistakes: https://polycount.com/discussion/comment/1799011
3. Gimbal lock / flipping. Maya's own docs: Euler = gimbal/flip risk; quaternion = no flips but poor to edit in the graph editor, no tangents: https://help.autodesk.com/cloudhelp/2023/ENU/Maya-Animation/files/GUID-CBD30A0A-1166-4076-A564-1ADC946A15F3.htm
4. Retargeting breaks contact. HumanIK does not compensate foot proportions; matching feet exactly over-exaggerates stride; hand penetration needs per-effector IK Blend: https://help.autodesk.com/cloudhelp/2020/ENU/Maya-GettingStarted/files/GUID-9F8D22A6-94BA-4E53-A3D2-6DB745741131.htm . Hip/limb proportion mismatch makes feet slide or bounce: https://80.lv/articles/try-this-new-mocap-retargeting-tool-for-blender/ . Pelvis motion scaled by height, contact-aware correction: https://mocaponline.com/blogs/news/animation-retargeting-guide
5. Rig setup cost and layers. Maya layers are true non-destructive stacking; Blender NLA doubled transforms when keying on a new layer, add-ons fill the gap: https://archive.blender.org/lists/bf-committers/2016-May/047355.html , https://blenderartists.org/t/animation-layer-like-maya-without-nla-editor/1216870
6. Stepped -> spline surprises (flat tangents wreck a block-out; add breakdowns while stepped): https://forum.reallusion.com/PrintTopic424001.aspx
7. No physical-plausibility feedback during authoring. Shapiro & Lee show projected COM/COP vs the support polygon plus ballistic and angular-momentum checks for animators, evaluated only subjectively; PhysIK adds COM/inertia handles to keyframing: https://ict.usc.edu/pubs/Practical%20Character%20Physics%20For%20Animators.pdf , https://www.cs.mcgill.ca/~kry/pubs/physik/PhysIK.pdf . Neither Maya nor Blender ships this (mine: neither shows it in their stock UI).
8. Foot-skate cleanup relies on threshold heuristics or manual labels; contact labels then drive IK pinning: https://arxiv.org/pdf/2208.04598 (UnderPressure; the learned model is out for us, the heuristic baseline is the usable part).
9. Steep UI / hard-to-diagnose rigs: forum helpers keep asking for the .blend because users cannot describe the problem (https://blenderartists.org/t/ik-fk-switch-animation-issue/1121173). Not a survey; Reddit threads were not retrievable via search, so "steep UI" is weakly sourced.

Poser already answers: gimbal (#3), foot slide check (FOOT SLIDE + Fixer._plant), balance finding (scripts/balance.gd, de Leva 1996, WARN > 3 cm for 0.1 s), gait check vs real walkers (PEOPLE.md), "why + source" per finding.

## 3. Ranked features (new work only)

1. **Live COM / support-polygon overlay in the viewport.** User sees: a dot on the floor under the body (COM projection), the foot polygon shaded, green inside / amber near edge / red out, updating while dragging. Why: balance.gd already computes it but only as a CHECK finding after the fact; Shapiro & Lee make exactly this the animator-facing tool. Size S-M. Test: headless `measure` at a posed frame returns com/balance; assert the overlay builder's polygon points == Balance hull and the colour class flips at the 3 cm bar (anti-vacuity: lean past toes).
2. **Auto-contact detection -> "Plant feet for me".** User sees: one button proposes pin/step/free ranges per foot from the pose motion (height + speed thresholds), previewed as the blue fix ghost, then applied as one undo step. Why: replaces manual contact labelling, the step all foot-skate fixes need (UnderPressure paper baseline; Maya FK/IK parenting mistakes). Size M (reuse Fixer.propose, mocap_clean). Test: on walk_bat and an imported BVH, detected contact ranges vs known planted frames; after the fix, FOOT SLIDE findings = 0 and creep < 2.5 cm.
3. **Real-human reference curves behind the graph.** User sees: a faint band on the curve editor for hip/knee/ankle (and arm swing) over a gait cycle from published normative data; their curve drawn inside/outside it. Why: Maya/Blender have no "compare to a real human"; Poser's house rule is REAL HUMANS FIRST. Size M. Data: put numbers + links in docs/PEOPLE.md first. Test: scene resampled to 0-100 % cycle; assert deviation metric (RMS deg) on a cooked walk below a bar and on a deliberately stiff walk above it.
4. **Animation layers (additive offset).** User sees: "Add layer", sculpt a tweak (e.g. lean the torso through a whole walk) without touching base cards, a weight slider, delete = original returns. Why: Maya's best-loved non-destructive feature; Blender's NLA double-applies (source above). Size L (scene schema + undo + export bake). Test: base samples byte-identical with layer weight 0; weight 1 = base + delta per joint; schema validate; undo audit.
5. **Pose-to-pose "block from beats".** User sees: type/place 4-6 key poses on the timeline, press "Block", get stepped cards with spacing guides and a Check pass; "Spline it" converts. Why: codifies the block->spline->polish pipeline in one guided path, hiding graph editor. Poser has the parts (stepped preview, spline, breakdowner) but not the sequence. Size S-M. Test: cli `run` steps produce stepped scene, spline flag only after the step, Check findings listed per stage.
6. **Editable motion trail.** User sees: drag a dot on the wrist/foot trail; the nearest card's IK target moves; arcs get smoother. Why: Maya's editable motion trail is a standard polish tool; Blender motion paths are read-only. Size M. Test: scripted drag -> card changed, trail point within 1 mm of target, bar of undo steps = 1.
7. **Joint effort / strength warning.** User sees: per-joint static torque heat (shoulder holding a held pose, lumbar in a stoop) with "a real person can hold this N s" markers. Why: nothing in Maya/Blender; extends LIFT FORM (Storari 2025, Shu 2007) beyond the stoop. Torque from de Leva masses already in balance.gd (mine: needs published strength or L4/L5 compression limits, e.g. NIOSH 3400 N, before shipping). Size M. Test: hand calc of arm-extended shoulder torque vs `measure`; rule fires on straight-arm box at shoulder height (the round 39 failure).
8. **Proportion-aware BVH retarget with contact-aware pelvis.** User sees: drop a BVH, pick the poser body, get motion scaled by leg length with feet planted, plus a stride warning if it over-reaches. Why: documented HumanIK and Blender retarget pain (sources 4). Size L. Test: round trip on same-size body = 0.00004 deg (existing bar); on a 0.8x body, FOOT SLIDE = 0 and stride ratio ~ leg-length ratio.
9. **Space switch for hand/prop (world / body / hand).** User sees: a dropdown on a held prop or planted hand to change what it follows, from a chosen frame, without a pop (auto-matched). Why: space switching is the daily Maya tool; pops are the top forum complaint. Size M-L. Test: world position at the switch frame unchanged within 0.01 mm.
10. **FK<->IK snap on a limb with no pop.** User sees: toggle that matches the other mode's pose first (pole placed on the joint plane). Size M. Test: end effector and elbow positions equal before/after toggle. Lower rank because Poser's joints are swing/twist and pins already cover most uses.
11. **Dynamic plausibility for moves: angular momentum + airborne parabola in the timeline strip.** User sees: a ribbon marking frames where the body would not be able to produce the motion (jump launch speed vs leg strength, ballistic mismatch). Why: Shapiro & Lee / PhysIK ideas; Poser has a jump rule (WW10) but no in-timeline ribbon. Size M.

## Honest gaps in this research
- Reddit and GDC talks were not directly retrievable; "steep UI" and many sentiments rest on forum/doc results above.
- Normative gait numbers and strength limits for features 3 and 7 still need to be looked up and written to PEOPLE.md before any bar is set.
- Pose-from-photo excluded (needs pretrained model).
