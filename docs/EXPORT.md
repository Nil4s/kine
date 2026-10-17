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

## Blender (and FBX for any engine)

1. Set the scene frame rate to the animation's (Poser's default is **30**) **before** importing, because the importer turns seconds into frames at the scene's rate. Then File → Import → **glTF 2.0** and pick the `.glb`. You get one armature with an action named after the scene.
2. **FBX**: File → Export → FBX, with these settings, or some frames are lost:
   - **Bake Animation** on, **Simplify 0** (`bake_anim_simplify_factor=0.0`). The default simplify kept 32 of 74 keys in our test.
   - **All Actions** off and **NLA Strips** off, so the bake covers the scene's frame range.
   - The scene's **End** frame rounded UP to cover the last key. A scene's length need not be whole frames: `combo3` ends at frame 140.1, so the end must be 141.
   - **Add Leaf Bones** off.

   `tools/blender_check.py` is the exact script that does this and checks it (`blender -b --factory-startup --python tools/blender_check.py`, after `tools/blender_expect.gd`).
3. BVH: File → Import → Motion Capture (.bvh), scale 1.0.

## Any other tool

Anything that reads glTF 2.0 or BVH: three.js, Babylon.js, Cascadeur, MotionBuilder, Maya (BVH, or the FBX above), Rokoko, Mixamo-style retargeters.

---

## NOT TESTED (said plainly)

- **Unreal Engine 5**: not opened. The bone names were checked against UE5's Mannequin list, which is typed into `tests/engine_names_test.gd`. The import and IK Retargeter steps above follow Epic's documented workflow but were not run here.
- **Unity**: not opened. The glTFast and Humanoid steps are the documented workflow, not run here.
- **Godot**: the import was run (every scene, every frame). The BoneMap retarget onto another character was not.
- **Blender 4.5**: run (glTF import, FBX export and re-import, every scene).

If you try one of these, the result (it worked, or what broke) is worth adding here.
