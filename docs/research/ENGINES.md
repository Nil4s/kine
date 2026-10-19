# Engine delivery: what each engine needs, and where each fact came from

The three presets in `scripts/engine_export.gd` (EngineExport) and the menu commands "Export for Unreal 5...",
"Export for Unity...", "Export for Godot..." (main.gd `_export_engine`). Each run prints the pre-flight report
(OK or WRONG per check) before the file is written.

## The file (all presets)

- glTF 2.0 binary (.glb) written by Godot's GLTFDocument (`scripts/gltf_export.gd`).
- **Units: metres.** Source: glTF 2.0 spec, "Coordinate System and Units" (fetched from the Khronos repo):
  "The units for all linear distances are meters."
- **Axes: right-handed, +Y up, the front of the asset faces +Z, the left side faces +X.** Same source, quoted:
  "glTF uses a right-handed coordinate system." and "glTF defines +Y as up; the front side of a glTF asset faces +Z".
- The animation is named after the scene (letters, digits and `_`, 63 characters at most), one key per frame at the
  scene's fps, so the engine plays exactly the frames Poser shows.
- The skeleton carries UE5's Mannequin bone names (`pelvis`, `spine_01`..., `head`); the leaf bones (`*_leaf_*`) carry no
  motion. `root` is the glTF root bone above `pelvis` (the mannequin's own, `assets/mannequin.glb`).

## Unreal Engine 5 (preset `ue5`, suffix `_ue5`)

| Setting | Value | Source |
|---|---|---|
| Units | glTF metres to UE centimetres: **Import Uniform Scale = 100** (the default for glTF) | UE 5.2 Python API, `GLTFImportOptions.import_scale`, default 100 "for conversion from meters(glTF) to centimeters(Unreal default)". Found by search; the page itself returned HTTP 403 to WebFetch. |
| Unreal unit | 1 UU = 1 cm | Epic, "Importing and Converting Assets" (migration guide, found by search) |
| Up axis | UE is Z up; the importer converts the glTF Y-up | Not confirmed in an Epic page. Checked in Blender 4.5 only (see below). |
| Import | Skeletal Mesh, Import Animations on | Epic glTF import workflow (see EXPORT.md), not run in UE |
| Root motion | The pelvis's horizontal travel is moved onto the `root` bone; the pelvis keeps its horizontal place | Engine need (UE's root motion bone, Manny's `root`). Implemented in `GltfExport._animate` (`root_motion`). |
| Bones | The 23 UE5 core names are checked (root, pelvis, spine_01..03, neck_01, head, clavicle/upperarm/lowerarm/hand, thigh/calf/foot/ball, both sides) | `tests/engine_names_test.gd` list (typed from UE5's Mannequin) |

## Unity (preset `unity`, suffix `_unity`)

| Setting | Value | Source |
|---|---|---|
| Units | 1 unit = 1 m; the file is metres: no scale | glTF spec (above); Unity's own unit is the metre (not re-checked in Unity's docs) |
| Import | glTFast package (`com.unity.cloud.gltfast`). Humanoid avatars need the FBX route (docs/EXPORT.md). | Unity glTFast manual (overview fetched) |
| Facing | glTFast 4.x and later: the upgrade guide says models imported before 4.x appear rotated 180 degrees about Y; a parent rotated 180 about Y restores the old look | glTFast upgrade guide (found by search, not fetched in full) |
| Root motion | None from the file: the clip moves the hips; Unity does not move the object | Engine behaviour, not re-checked in Unity |

## Godot 4 (preset `godot`, suffix `_godot`)

| Setting | Value | Source |
|---|---|---|
| Units | 1 unit = 1 m; the file is metres: no scale | glTF spec (above); Godot's unit convention not found in the fetched docs page |
| Import dock | **Root Scale** (default 1), applied to the meshes with **Apply Root Scale** | Godot 4 docs, import configuration (fetched) |
| Root motion | None: the clip moves the hips | Engine behaviour |

## Weapon trail sidecar (all presets, ROADMAP 35)
Written next to the .glb when the scene holds a weapon: `<name>_<engine>_weapon_trail.json`, per frame the bat's knob end (`base`)
and tip, in metres, Y up, the .glb's space, plus the tip speed. The format and the game's use are in `docs/EXPORT.md`.
`tests/weapon_trail_test.gd` reads the file back and checks each point against the body within 0.1 mm.

## Pre-flight checks (all presets)

- units: mannequin height from the file's mesh, 1.5 to 2.0 m (WRONG otherwise)
- up: the rest pose stands (head above pelvis above foot; WRONG if not)
- facing: the toes point to +Z, the glTF front (WRONG if turned)
- root motion: the pelvis's horizontal travel; UE5 needs a root bone (WRONG if none); Unity and Godot print WRONG when the
  clip travels more than 5 cm, since the travel stays on the hips
- frame rate: integer 1 to 120 fps, a key on every frame
- animation name, bone count (leaf bones named), and for UE5 the core-name list

## Blender 4.5 check (once, on the UE5 preset file `combo3_ue5.glb`, 12 cards, 30 fps)

Imported with Blender's glTF importer, factory settings, metres:
- Mannequin height 1.829 m, feet on the floor at z = 0.0005 m, head at z = 1.569 m (Blender is Z up): upright, right size.
- Toes point to -Y in Blender (`ball_l - foot_l` = (0, -0.149, -0.089)), the glTF +Z front: facing as the file says.
- The pelvis's horizontal place stays at (0, 0.050) m through the clip (no drift); its height changes with the clip.
- **Finding: Blender 4.5's importer dropped the root bone's translation.** The file holds the root track (x 0.00..0.03 m,
  z 0.00..0.17 m, read back by Godot's GLTFDocument within 0.000 mm), but Blender's `root` location fcurves are all 0.
  This is Blender's importer, not the file: the travel is in the glb. Blender is not the UE5 importer, so UE5's root
  motion is NOT confirmed by this check; it needs a UE5 import (not done here).

## Not tested

- Unreal Engine 5: not opened. Its import scale and axis handling are from the sources above, not from a UE run.
- Unity: not opened. The glTFast steps are the documented workflow.
- Godot: the .glb reads back with GLTFDocument (tests/engine_export_test.gd); the import dock was not run on it.
