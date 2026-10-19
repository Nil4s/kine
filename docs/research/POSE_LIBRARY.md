# Pose library: what Blender and Maya do, and what Kine matches

For docs/GAP_ANALYSIS.md row 8 ("Save pose plus a Poses list; no thumbnails, no blend-in-a-pose slider").
No code was copied. Code: `scripts/pose_library.gd`; test: `tests/pose_library_test.gd`.

## What the references do

**Blender** (manual, *Animation & Rigging > Armatures > Posing > Editing > Pose Library*,
docs.blender.org/manual/en/latest/animation/armatures/posing/editing/pose_library.html, read 2026-10-18):
- A pose is an asset (a one-frame action). It stores each bone's location, rotation, scale. Made with *Create Pose
  Asset* from the selected bones.
- Previews: rendered "through the active Scene camera" with Workbench; *Generate Preview* renders it again.
- *Apply Pose*: "If bones are selected, only those bones change." Double-click also applies.
- *Apply Pose Flipped*: "mirror the pose from left to right and vice versa".
- *Select / Deselect Pose Bones*: selects the bones the pose uses.
- *Blend Pose*: move the mouse left/right to set the amount; left subtracts, E extrapolates past 100 %, Tab toggles
  original / blended. Confirm with LMB or Return, cancel with RMB or Esc.
- Asset shelf in the viewport: click applies; "dragging a thumbnail left to right blends it, and releasing the mouse
  confirms. Holding Ctrl while blending applies the flipped pose."
- Updating a pose: Adjust / Replace / Add / Remove from its right-click menu.

**Maya, Studio Library** (Kurt Rathjen's free tool; from memory, the site was not read for this round, so unverified):
- A library of folders with a thumbnail per item, captured from the viewport when the pose is saved.
- A pose item has *Apply*, a *Mirror* option (with a mirror table for left/right names), and a *Blend* slider; dragging
  over the thumbnail with the middle mouse blends. Apply can be limited to the selected controls.
- Undo: a blend is one undo chunk when the slider is released.

## What Kine matches (and what it does not)

| Reference | Kine | Notes |
|---|---|---|
| Thumbnail per pose | Yes | Rendered off screen on a clean mannequin (no weapon, no props), one fixed orthographic camera (front 3/4, 2.35 m tall frame), 160 x 200 px, saved as `<pose>.png` next to the `.json` |
| Generate Preview again | Yes, automatic + menu | Remade when the pose file's md5 changes or the `.json` is newer than the `.png`; right-click > *Remake the thumbnail* |
| Grid / asset browser | Yes | *Pose library* (POSE tab, LIBRARY group; also the command search and the browser's Poses right-click menu): every pose in poses/lib, poses, moves |
| Click = apply | Yes | One undo step |
| Apply flipped | Yes | Right-click > *Apply flipped*, the *Flipped* box, or Ctrl held; the same reflection as Mirror pose (test: equal within 0.01 deg) |
| Drag on thumbnail = blend, release confirms | Yes | Drag right: 160 px = 100 %, live; release = one undo step; RMB while dragging cancels; Ctrl = flipped |
| Blend slider | Yes | *Blend* slider on the picked pose; release = one undo step, the slider goes back to 0 (each blend starts from the body as it is) |
| Apply to selected bones only | Yes, by a box | One part is always picked in Kine, so "selected only" is the *Only the selected parts* box (Ctrl+click more parts) |
| Select the pose's bones | Yes | Right-click > *Select the parts it moves* (every joint turned over 0.5 deg), and turns on *Only the selected parts* |
| Blend left subtracts / E extrapolates / Tab toggle | No | The blend is 0..100 % only |
| Pose stores location / scale | Partly | Joint rotations and the hips' offset; the weapon stays in the hand it is in (as Blender: bone transforms only) |
| Adjust / Add / Remove bones of a saved pose | No | Save pose again under the same name replaces it (it asks) |
| Folders / tags / search in the library | No | The three folders are listed in order: library, starter poses, yours |

## The maths

Blend at factor f, for each joint j in scope: `ang[j] = clamp(decompose(slerp(compose(start), compose(target), f)))`
(the same slerp as the Breakdowner). f = 1 sets the target exactly. A whole-body blend lerps the hips' offset too; a
selected-parts blend leaves the hips and every other joint bit for bit. Flipped target:
`q = compose(twin(j), pose[twin(j)])`, reflected `(x, -y, -z, w)`, decomposed on j and clamped (Body.pose_paste's rule).
