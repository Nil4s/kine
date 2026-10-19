# Shot camera: how Blender and Maya do it, and the numbers Kine uses

For docs/GAP_ANALYSIS.md row 21. No code was copied. Code: `scripts/shot_camera.gd`, `scripts/shot_frame.gd`, `main.gd` `_shot_*`.

## What the references do

**Blender** (manual, *Render > Cameras*, docs.blender.org/manual/en/latest/render/cameras.html, read 2026-10-18):
- A camera is an object: its transform (location, rotation) is keyed like any object. Aiming it at a point is
  usually done with a *Track To* constraint, the same thing as Kine's `aim` point.
- *Lens*: "The Focal Length controls the amount of zoom"; it "can be set either in terms of millimeters or the actual
  Field of View as an angle". The focal length is keyable.
- *Sensor Fit*: "Auto: calculates a square sensor size based on the larger of the Resolution dimensions";
  Horizontal / Vertical fix the width or the height and derive the other from the aspect ratio.
- *Passepartout*: "darkens the area outside of the camera's field of view", with an opacity slider.
- *Shift* moves the lens off-centre ("adjustment of vanishing points"). Kine has no user shift. It does use the same
  idea internally to put the frame where the panels leave room.
- Composition guides (thirds, centre, golden ratio) are overlays on the frame. Kine does not have them yet.
- Not on the parts of the page that were read, so these come from memory (unverified): the default focal length is
  **50 mm**, the default sensor is **36 mm**, the default passepartout alpha is **0.5**, the default render is
  **1920 x 1080 (16:9)**, and *View > Cameras > Active Camera* (Numpad 0) is "look through".

**Maya** (from memory; the help page could not be fetched): a camera has a *Focal Length* (35 mm default on the
persp camera) and a *Camera Aperture* (film back) of 1.417 x 0.945 in (36 x 24 mm, the 35 mm still gate).
*Panels > Look Through Selected* shows a camera's view, and the *Resolution Gate* draws the render's frame.
The Camera Sequencer (several shots cut together) is out of scope here.

## The numbers Kine uses

| Quantity | Value | Source |
|---|---|---|
| Sensor width | 36 mm | Blender default; 35 mm still film gate (36 x 24); Maya 1.417 in |
| Frame | 16:9 | Blender's default 1920 x 1080 |
| Sensor fit | width (Auto, since a 16:9 frame is wider than tall) | Blender *Sensor Fit: Auto* |
| Sensor height in the frame | 36 / (16/9) = 20.25 mm | from the two lines above |
| Vertical angle | fov_v = 2 atan(20.25 / 2 / f) | pinhole camera |
| Horizontal angle | fov_h = 2 atan(36 / 2 / f) | pinhole camera |
| Default lens | 50 mm, so fov_v = 22.895 deg and fov_h = 39.598 deg | Blender default |
| Lens presets | 18, 24, 35, 50, 85, 135 mm | common prime lenses |
| Passepartout | black at alpha 0.5 | Blender default |

Check of the formula: for 50 mm, 20.25 / 2 / 50 = 0.2025, and 2 atan(0.2025) = 22.8952 deg. For the horizontal angle,
2 atan(0.36) = 39.5978 deg. tests/shot_camera_test.gd checks both within 0.01 deg, and checks the rendered frame
against the same angle.

## How Kine maps it onto Godot

Godot's Camera3D keeps the vertical angle (KEEP_HEIGHT) over the whole viewport. The frame is a 16:9 rectangle inside
the viewport, so the viewport camera's frustum is set so that the frame's height spans exactly fov_v:

- frustum height at the near plane = viewport_h x (2 near tan(fov_v / 2) / frame_h)
- offset = the frame centre's distance from the viewport centre, in the same near-plane units.

When the frame is centred (a playblast or a clean view), this is a plain perspective camera with
fov = 2 atan(tan(fov_v / 2) x viewport_h / frame_h).
