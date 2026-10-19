# Kine roadmap: toward Maya / Blender, and past them (2026-10-18)

Three lists feed this: what Maya / Blender have that Kine lacks (`GAP_ANALYSIS.md`, 32 rows), what animators
complain about in every tool (`COMPLAINTS.md` has the first 10), and what no tool does yet. The 400 upgrades are
planned as 16 areas; each area becomes a numbered list of gates before agents take it.

## The 400, by area

| area | count | examples |
|---|---|---|
| Rigging and IK | 30 | spline IK spine, IK/FK snap per frame, stretch, reverse foot, space switching |
| Graph editor and keys | 30 | tangent weights, euler filter, breakdowns, retime tool, key reduction slider |
| Dope sheet and timeline | 25 | summary rows, scale around playhead, markers, sub-frame keys, ripple edit |
| Layers / clips (NLA) | 20 | strip blending curves, clip warping, pose-matching on transitions |
| Viewport and display | 30 | motion trails editable, ghosts per part, isolate, xray, silhouette, safe frames |
| Deformation and mesh | 30 | skin weights paint, corrective shapes, muscle bulge, own characters (mesh engine) |
| Physics and secondary | 25 | cloth, hair, follow-through on props, ragdoll to keys, rigid props |
| Mocap and video | 25 | multi-camera video, hand capture, contact cleanup, live webcam puppet |
| Import / export / pipeline | 25 | fbx out, alembic, usd layers, per-engine presets, batch export |
| Camera and shot | 20 | rack focus, shake, multi-shot sequencer, storyboard panels |
| Audio | 15 | lip-sync visemes, beat markers, multi-track, scrub-to-hear |
| Faces and hands | 25 | face rig, viseme sets, finger poses library, grip auto-wrap for any prop |
| Combat-specific | 30 | frame data, hitboxes, choreography exchanges, hit reactions, weapon trails |
| Biomechanics truth | 25 | torque limits, balance, injury load, fatigue, real-human speed bars |
| Workflow and UX | 25 | undo tree, version branches, hotkey editor, command search, crash-proof saves |
| Collaboration and cloud | 20 | shared review links, frame comments, live co-editing, asset store |
| **total** | **400** | |

## What animators complain about (beyond the first 10 in COMPLAINTS.md)

Crashes and lost work; rigs that break on retarget; export scale / axis mix-ups between engines; viewport too slow to
play in real time; hotkey overload and a steep first week; Maya's price; Blender's NLA being clumsy; mocap that needs
hours of cleanup; no way to tell if a motion is physically possible; reviewing with a director by sending videos back
and forth.

## The top 25 (what nobody ships)

1. **"Could a human do this?"** Every frame graded against real joint torques, balance and speed from biomechanics papers, with the frame and the reason.
2. **Frame data for fighting games:** startup / active / recovery frames and hitboxes drawn from the animation itself, exported to the engine.
3. **Choreography for two or more fighters:** an exchange (attack, parry, counter) laid out as one timeline, spacing and reach kept honest between them.
4. **Automatic hit reactions:** a hit's momentum drives the victim's reaction, then it's baked as editable cards.
5. **Phone video to clean animation:** one video in, foot contacts locked, jitter removed, cards out.
6. **Live webcam puppeteering:** pose the mannequin with your own body in real time and record it.
7. **Critique that points at frames:** "floaty at 1.2 s", "no anticipation before the swing", "foot slides 3 cm", using the 12 principles plus the rulebook.
8. **Type a move, get blocking:** "overhead axe strike, step in" becomes the key poses from the motion rules, ready to polish.
9. **Sketch to pose:** draw a line of action or a stick figure and the body follows it.
10. **Grips for any prop:** the hand wraps any imported mesh, not only the 4 weapons.
11. **Injury and load check for stunt teams:** joint loads per frame, flagged above published limits.
12. **Style transfer:** make this walk heavier, older, tired, or angrier, with the timing and spacing changing as real data shows.
13. **Secondary motion baked to keys:** hair, cloth and weapon wobble, computed and then editable like your own keys.
14. **Ragdoll to keys:** drop the body, pin a hand, let physics pose it, keep the result.
15. **Undo as a tree:** go back and branch without losing the other version.
16. **Versions like git, visual:** compare two versions of a scene side by side or overlaid, pose by pose.
17. **Review links:** send a link, the director comments on frame 42, and the comment shows on your timeline.
18. **Live co-editing:** two animators in one scene, each on a fighter.
19. **One-click engine delivery:** UE5, Unity and Godot presets with scale, axes and root motion checked before writing.
20. **Spacing from real motion:** ease presets measured from mocap ("a punch accelerates like this"), not generic curves.
21. **Lip-sync from audio:** visemes keyed from the sound file.
22. **Beat-synced timing:** the music's beats as timeline markers; snap hits to them.
23. **Motion-matching preview:** see how your clips will blend in a game's locomotion system before exporting.
24. **Character mesh engine:** build your own characters with any proportions, and the rig follows.
25. **Crash-proof by design:** every edit journaled, so no work is ever lost.

## How to run it

Waves of 10 agents (one machine runs about 10 Godot tests at once; main.gd merges are the other bottleneck), one
area or a few top-25 items per wave, merged and tested in CI at the end of each day.
