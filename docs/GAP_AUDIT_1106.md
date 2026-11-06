# What we lack: audit of 2026-11-06 (lane L7)

Method and honesty. Kine side: a grep and file listing of `scripts/`, `tests/`, `native/src/`, `tools/` and `docs/` on base 6254e061
(a feature counts as present when a script and a suite exist; I did not run them). Blender / Maya / Fusion side: from what I know of
those products, not from a fresh read of their manuals, so treat the "they have it" half as a recollection and the "Kine lacks it" half
as "not found by grep". Rank = user value per cost, best first. Owners: L1 AI digest + MCP, L2 Expert UI + icons, L3 Easy UI,
L4 CH15/CH17 eng layouts, L5 liquids + water, L6 materials + skin. "none" = no lane tonight.

## Top 10 for the next round

| # | item | area | value / cost | owner tonight |
|---|---|---|---|---|
| 1 | Windows installer shipped end to end: signed exe, opt-in update check, crash report upload path (kine.iss, build_installer.sh and crash_report.gd exist as pieces) | packaging | M3 gate; $$ | none |
| 2 | Import a full rigged character (FBX / glb with skin, not only animation) and retarget the mesh onto the body | IO + rig | every outside user arrives with a character; $$ | none |
| 3 | A "final render" button: SSAO / SSR / SDFGI preset, soft shadows, denoise, PNG sequence + mp4 from the shot camera | rendering | client-ready output; $ (render_queue.gd, shot_render.gd exist) | L6 touches materials only |
| 4 | Workspace layouts the user can save, rename and reset; per-page panel docking; full key remap | UI | what Maya and Blender users expect on day one; $$ | L2 (expert), L3 (easy), neither names layouts |
| 5 | Face as geometry, first slice: eyelids + jaw + 6 AUs as blendshapes (ROADMAP_400 I01-I04) | animation | the painted face is the most visible weakness in a close shot; $$$ | none |
| 6 | N040 throw truth (the one star-star-star item not started) | animation | the fight-choreography headline claim; $$$ (2-body pair judge) | none |
| 7 | Wire N082 reactable into `serve`, the CLI and the frame-data panel (module + strip are done, unwired) | agent | closes N082 for agents; $ | L1 owns agent_tools.gd, so after L1 merges |
| 8 | 60 fps playback with two fighters + a cloth item on a mid-range GPU: a measured frame budget and the top 3 hot loops | performance | M3 gate; $$ | none |
| 9 | Soft-body / muscle jiggle beyond secondary_motion: a native mass-spring or XPBD volume for flesh and cloth-on-body | physics | looks heavy; $$$ | none |
| 10 | USD export with skin + blendshapes (current USD is skeletal animation and layers) and Alembic-free point cache | IO | pipelines into Unreal / Houdini; $$ | none |

## Animation and rig

Have: cards, curves, dope sheet, NLA clips, IK with poles, constraints, drivers, layers, retarget, video to motion, 14 of 15 star-star-star judges.
1. Face as geometry (ROADMAP_400 I01-I12): lids, lips, jaw, AU blendshapes, ARKit 52 export. Maya and Blender both have shape-key faces. $$$. none.
2. Own skeleton: one fixed skeleton (UE5 Manny names); there is a bone editor and rig_precheck but no autorig for a user-built creature (Maya Quick Rig, Rigify). $$. none.
3. N040 throw truth and N041 lock truth (partner joint limits): the two-body judges are what a fight tool is for. $$$. none.
4. Motion matching beyond the preview (N084 blend matrix, N081 cancel windows): game-ready moveset checks. $$. none.
5. Spline IK and stretchy limbs for non-human rigs (Blender has both). $$. none.

## Sculpt, retopo and surface

Have: sculpt brushes, symmetry, masks, quad retopo (native), UV editor + pack, boolean, decimate, LOD, shape keys, vertex and weight paint.
1. Multires / dynamic topology (Blender Dyntopo, Maya none): sculpt at a resolution that changes with the stroke. $$$. none.
2. Remesh and quad-dominant auto-retopo quality bar against a hand retopo: a measured edge-flow score. $$. none (G16 retopo work is in flight on other branches).
3. UV: seam suggestion from curvature + live distortion heat map exists; missing UDIM tiles (Maya, Blender). $$. L6 may touch.
4. Curves and surfaces: NURBS patches for hard-surface cleanup (Maya), beyond the CAD kernel's B-rep. $$$. L4 (CAD side only).
5. Texture paint across seams with projection (Blender, Substance-style): `kmesh_vpaint` is vertex paint only. $$. L6.

## Rendering and materials

Have: Godot Forward+ viewport, shot camera, playblast, turntable, PBR material library, photo material, material words.
1. Final-quality offline render with GI, DOF, motion blur, denoise (Cycles, Arnold). A preset on Godot's own pipeline is the cheap path. $-$$. none.
2. Skin subsurface scattering and eye caustics for a believable face. $$. L6 (skin).
3. Node-based material graph (Blender shader nodes, Maya Hypershade); Kine has words and a library, not a graph. $$$. L6 is not building a graph.
4. Light rig presets and an HDRI picker with a light-linking toggle. $. none.
5. Hair cards / strand render (hair.gd exists as a prop; Blender hair curves, Maya XGen). $$$. none.

## Physics: rigid, cloth, liquids, soft

Have: MuJoCo humanoid (I1), rigid drop, ragdoll, native cloth + self-collision, hit physics.
1. Liquids and water: absent. L5 owns it.
2. Soft body / flesh jiggle volume (Blender soft body, Maya nCloth + nucleus): none; secondary_motion is spring chains only. $$$. none.
3. Cloth pinned to an animated body with a measured penetration and stretch bar in the delivery gate (exists in tests; not a user-facing "bake cloth" with a cache). $$. none.
4. Rigid destruction / fracture (Blender Cell Fracture, Maya Bullet): none. $$$. none.
5. Cache and scrub: bake any sim to a point cache file the timeline scrubs (Blender point cache, Maya cache). $$. none.

## CAD and engineering (Fusion 360 comparison)

Have: native B-rep kernel (OpenCascade), STEP import/export, features, ISO 286 fits, BOM, assembly checks, fasteners,.
1. Parametric history tree with edit-in-the-middle and rollback (Fusion timeline). Partially in features; no visible timeline. $$$. L4 (layouts only).
2. Constraints / joints between assembly parts with motion study (Fusion joints, motion link). $$$. none.
3. Sketch with dimensional constraints solved live (Fusion sketch). No dimensional sketch solver found by grep of scripts/ (easy_part_sketch.gd is a 2D sketch to part, not a constraint solver). $$$. none.
4. Simulation: static stress FEA or at least beam checks (Fusion simulation). $$$. none.
5. CAM toolpath output (Fusion manufacture): a G-code preview (kine_wood_native.cpp exists, so a CNC lane is plausible; not verified). $$. none.
6. Drawing sheets with title blocks and GD&T symbols. $$. L4.

## UI and UX

Have: pages, command search, hover hints, easy mode, themes, ui scale, undo history, keyboard hints.
1. Saved workspaces (see top 10 #4). L2 / L3 partial.
2. Full key remap UI (Blender keymap editor, Maya hotkey editor). `hotkeys` suite exists for viewing. $. L2.
3. Outliner tree with filters, search and drag to reparent (Blender outliner, Maya outliner). Browser tree exists; no drag reparent. $$. L2.
4. Multi-window / second-monitor detach for timeline and viewport (Maya, Blender). $$. none.
5. Tooltips with a short looping clip (Blender 4.x). $$. L3 may touch.

## IO: FBX, GLB, STEP, USD

Have: FBX export (with camera + material), GLB export, USD export + layers (pxr reference check), BVH, OBJ, STL / 3MF, STEP in/out, anim import from fbx / glb / bvh.
1. Full character import (mesh + skin + blendshapes) from FBX / glb. See top 10 #2.
2. FBX export of blendshapes and custom attributes round-tripped through Blender (checked headless); `fbx_export` suite checks structure only. $$.
3. USD with skin, blendshapes and variants. $$.
4. Alembic and a point cache for sims. $$.
5. Round-trip regression against real DCC output: import a Maya-exported FBX in a test fixture (licence-clean). $.

## The agent / MCP route

Have: one agent path for MCP, CLI `serve` and the local API; 14 star-star-star judges as calls; trust labels; dry run; try N ways; Kine-Bench (`bench`).
1. N082 and N014 not callable by agents yet (N082 built tonight, unwired). $. L1 after merge.
2. Event stream (N023 findings stream): not built; an agent cannot coach live beside a person. $$. L1.
3. Guardrails (N021): owner-set limits enforced by Kine, not by the prompt. $$. L1.
4. Replay proof (N010) and a signed command log. $. L1.
5. A remote MCP transport with auth, so a cloud agent (the paid tier idea) can drive a local Kine. $$$. L1.

## Performance

1. A frame budget with a profile per page (`perf4`, `play_perf` suites exist, no single budget table). $.
2. GPU skinning for crowds and two fighters (dq_skin_native is CPU native). $$. none.
3. Background thread for judges so the realism score (I16) stops blocking: re-score is 644-982 ms vs the 400 ms bar. $$. none.
4. Mesh ops on 1M+ vertices: sculpt and boolean timing table against Blender's. $$. none.
5. Startup: `boot` suite and BOOT_TIME.md exist; a cold-start bar on the installed build is missing. $. none.

## Installer and packaging

Have: `tools/build_installer.sh`, `tools/installer/kine.iss`, `stage_dist.py`, `make_notices.py`, C78 plan, a G45 dist lane.
1. Code signing and a clean-machine install test (a VM or Windows Sandbox script). $$.
2. Opt-in update check and a release feed. $$.
3. Crash report upload path the user opts into (crash_report.gd writes locally). $.
4. Linux and macOS builds (M4). $$$.
5. Third-party notices regenerated in CI so the shipped notices match the shipped DLLs (OpenCascade libs). $.
