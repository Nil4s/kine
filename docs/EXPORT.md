# Taking a Poser animation into any engine

Poser writes two open formats. Both come from the open scene, through the command box (type `export`):

| Command | File | What is in it |
|---|---|---|
| **Export animation (.glb)** | `exports/<scene>.glb` | glTF 2.0: the mannequin (mesh, skin, skeleton) and one animation named after the scene, a key on every frame. The weapons are animated nodes `weapon` / `weapon2` with a plain shaft. |
| **Export animation (.bvh)** | `exports/<scene>.bvh` | BVH motion capture: the skeleton and every frame. The weapons are joints under the hand that holds them. |
| Export to game | `exports/<scene>.json` + `.cs` | The ARPG's own PoseTable (round 31). |

Use **.glb** first: glTF is the Khronos open standard and Godot, Blender and Unreal 5 read it as it is. Use **.bvh** for retargeting tools (MotionBuilder, Cascadeur, Rokoko, Maya). For **FBX**, convert the .glb in Blender (see Blender below).

**The skeleton.** The bones carry the UE5 Mannequin names: `pelvis`, `spine_01`–`spine_03`, `neck_01`, `head`, `clavicle_l`, `upperarm_l`, `lowerarm_l`, `hand_l`, the fingers (`index_01_l` ...), `thigh_l`, `calf_l`, `foot_l`, `ball_l`, and the same on the right. `tests/engine_names_test.gd` checks every one of Poser's joints against UE5's list. The mannequin also has leaf bones (`index_04_leaf_l`, `ball_leaf_l` ...) that UE5 does not have. They carry no motion and every engine can ignore them.

**Units and axes.** The .glb is in metres, Y up, and the character faces +Z (glTF's own convention, so each importer converts it for you). The .bvh is in metres, Y up, rotation order Z X Y.

**How it was checked.** Every frame of every scene in `scenes/` was read back by Godot's own glTF importer: joints within 0.0000 m and bones within 0.000°. The same files were read by Blender 4.5's own importer: 65 bones, one key per frame, bone heads within 0.0000 m. Blender then wrote FBX and read it back with the same frame count. The BVH files were re-parsed by an independent reader: joints within 0.0000 m, weapons within 0.4 mm. See GATES.md OO1–OO3.

---

## Unreal Engine 5

1. Drag the `.glb` into the Content Browser (UE 5.2+ imports glTF natively; on older versions, use the FBX from Blender). Import it as a **Skeletal Mesh** with **Import Animations** on. You get a skeleton, a mesh and an Animation Sequence named after the scene.
2. Put it on Manny / Quinn (or your own UE5 character) with the **IK Retargeter**:
   - Create an **IK Rig** for the imported skeleton. Its chains are spine (`spine_01`→`spine_03`), neck/head, each arm (`clavicle`→`hand`), each leg (`thigh`→`ball`) and the fingers. Set the retarget root to `pelvis`.
   - Use Manny's own IK Rig (`IK_Mannequin`) as the target.
   - Create the IK Retargeter. The names already match UE5, so the chains pair up by name. UE5's spine has 5 bones and ours has 3; the Spine chain retargets 3 onto 5.
   - Export the retargeted animations.
3. The weapons are separate nodes in the file. To use them, attach a weapon mesh to the hand socket (`hand_r` / `hand_l`); Poser's grip puts the knob at the hand.

## Unity

Unity reads glTF through the free **glTFast** package (Package Manager → `com.unity.cloud.gltfast`). glTFast imports the animation as a **Legacy** or **Generic** clip, which plays on the exported mannequin itself.

To put the motion on *your* character (the **Humanoid** avatar, Mecanim retargeting), use the FBX route, because Unity's Humanoid setup is on its FBX importer:

1. Make the FBX in Blender (see Blender below).
2. Drop the FBX into Assets. In the Inspector, go to Rig → Animation Type **Humanoid** → Avatar Definition **Create From This Model** → **Configure**. The UE-style names (`pelvis`, `spine_01`, `upperarm_l` ...) map automatically; check that the hips are `pelvis` and the head is `head`.
3. On the Animation tab, the clip is the scene. Any Humanoid character can now play it.

## Godot 4

1. Copy the `.glb` into your project. Godot imports it as a scene with a `Skeleton3D` and an `AnimationPlayer` holding one animation named after the scene. It plays as it is.
2. To retarget it to another humanoid, open the Advanced Import Settings and select the `Skeleton3D`. Under Retarget, add a **BoneMap** with the profile **SkeletonProfileHumanoid**; the UE-style names fill it in automatically (check Hips → `pelvis`, Head → `head`). Do the same on your character, and the animation plays on both.
3. Poser's own test does exactly this read: `tests/glb_export_test.gd`.

## Weapon trail points (sidecar JSON, ROADMAP 35)

When the scene holds a weapon, every engine export (`Export for Unreal 5 / Unity / Godot`) also writes
`<name>_<engine>_weapon_trail.json` next to the `.glb`. It is not a mesh and not in the .glb: it is the two edge points of the bat
on every frame, so a game can draw its own sweep ribbon between them.

```json
{"format": "kine-weapon-trail-1", "scene": "combo3", "fps": 30, "units": "m", "up": "+Y",
 "frames": [{"t": 0.0, "held": true, "base": [x, y, z], "tip": [x, y, z], "speed": 0.0}, ...]}
```

- `base` is the knob end (the butt, the grip side), `tip` is the far end of the bat. Frame `i` is at `t = i / fps`.
- Metres, Y up, in the same space as the `.glb`'s root (the mannequin's own space; the weapon node in the file sits there too).
  The UE5 preset's root motion moves only the body, not the weapon, so these points match the file's `weapon` node in all presets.
- `held` is false on frames with no bat in a hand; then `base` and `tip` are `null`.
- `speed` is the tip's speed in m/s (frame to frame), for the game to threshold a ribbon on, as the app does (8 m/s).
- Tested by `tests/weapon_trail_test.gd`: the points equal the body's own weapon points on every held frame within 0.1 mm.

This is not the motion trail (T) in the app, which draws the tip's path as dots. The app's ribbon ("Trail: weapon ribbon") and its
smear frames ("Trail: smear frames") are for the playblast and the view only; the game builds its own from this file.

## Blender (and FBX for any engine)

1. Set the scene frame rate to the animation's (Poser's default is **30**) **before** importing, because the importer turns seconds into frames at the scene's rate. Then File → Import → **glTF 2.0** and pick the `.glb`. You get one armature with an action named after the scene.
2. **FBX**: File → Export → FBX, with these settings, or some frames are lost:
   - **Bake Animation** on, **Simplify 0** (`bake_anim_simplify_factor=0.0`). The default simplify kept 32 of 74 keys in our test.
   - **All Actions** off and **NLA Strips** off, so the bake covers the scene's frame range.
   - The scene's **End** frame rounded UP to cover the last key. A scene's length need not be whole frames: `combo3` ends at frame 140.1, so the end must be 141.
   - **Add Leaf Bones** off.

   `tools/blender_check.py` is the exact script that does this and checks it (`blender -b --factory-startup --python tools/blender_check.py`, after `tools/blender_expect.gd`).
3. BVH: File → Import → Motion Capture (.bvh), scale 1.0.

## FBX straight from the app (Export... → Unreal Engine 5 / Unity / Maya)

Export... writes a **binary FBX 7.4** (`scripts/fbx_export.gd`, `FbxExport`): the same skeleton and keys as the `.glb`, the UE5 bone names, one take named after the scene, a rotation curve set (X, Y, Z in degrees, Euler XYZ) per animated bone, the pelvis's position curves, in **centimetres** (UnitScaleFactor 1.0), Y up. Every key is on a frame, as in the `.glb`. The weapons, props, sound and camera are not in it. The ASCII text of the same tree is a debug view: `FbxExport.write(..., ascii = true)`.

- **Unreal 5**: the root-motion preset writes `<scene>_ue5.fbx` with the travel on the root bone.
- **Unity**, **Maya** and **Blender 4.5** read it; each dialog line says what that engine needs. Blender reads the binary; it refuses ASCII FBX.

How it was checked: `tests/fbx_export_test.gd` writes the binary FBX and the `.glb` for `combo3`, and the ASCII debug view of the same scene. `tests/py/fbx_check.py` (a reader of its own, `python -I`) reads the ASCII back: the 65 bone names and their order are the `.glb`'s skin joints, the parents match, every curve has the `.glb`'s 142 keys, and 9 samples (3 bones at 3 frames) read back within 0.01° of the body's local rotation (worst 0.000010°). `tests/py/fbx_blender_check.py` then imports the app's own binary file in Blender 4.5 next to the `.glb`: every bone's head agrees to 0.00000 m and its direction to 0.0000°, at those frames, and the sampled bones move (0.135 m of head travel), so the check is not on a rest pose.

## Any other tool

Anything that reads glTF 2.0 or BVH: three.js, Babylon.js, Cascadeur, MotionBuilder, Maya (BVH, or the FBX above), Rokoko, Mixamo-style retargeters.

---

## NOT TESTED (said plainly)

- **Unreal Engine 5**: not opened. The bone names were checked against UE5's Mannequin list, which is typed into `tests/engine_names_test.gd`. The import and IK Retargeter steps above follow Epic's documented workflow but were not run here.
- **Unity**: not opened. The glTFast and Humanoid steps are the documented workflow, not run here.
- **Godot**: the import was run (every scene, every frame). The BoneMap retarget onto another character was not.
- **Blender 4.5**: run (glTF import, FBX export and re-import, every scene).

If you try one of these, the result (it worked, or what broke) is worth adding here.
