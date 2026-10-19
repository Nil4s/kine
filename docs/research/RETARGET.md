# Retargeting an animation from another skeleton onto Kine (GAP_ANALYSIS row 26)

Code: `scripts/anim_import.gd` (`AnimImport`). Test: `tests/anim_import_test.gd`. Command: "Import animation (fbx / glb / gltf / bvh)...", or drop a .fbx (or a rigged, animated .glb / .gltf, or a .bvh) on the window. The result is always a NEW scene in `scenes/_wip/`; nothing of Nick's is overwritten.

## 1. Reading the file (no external converters)
- **.fbx**: Godot 4.7's own `FBXDocument` / `FBXState` (ufbx inside the engine), at run time, the same calls as glTF.
- **.glb / .gltf**: `GLTFDocument` / `GLTFState`.
- **.bvh**: `BvhImport.parse`. A .bvh whose root is Kine's `pelvis` (our own export) goes through `BvhImport.to_scene`, which is exact. Any other .bvh goes through the retarget below. The rest pose is all rotations zero (the OFFSETs), and End Sites become `<joint>_end` bones so the last bones have a direction.
- The skeleton with the most bones is used, with its longest animation. Each track is sampled at the file's own frame rate (taken from its key spacing, 10 to 120 fps) into GLOBAL transforms in the file's scene space. The parent nodes are included, so the 100x scale and Z-up turn on an FBX "Armature" node cancel out.
- **Found while building the fixture**: Godot's FBX reader takes bone rest ROTATIONS from the skin's bind pose, but the root bone's rest TRANSLATION from the pose the file was saved in. An armature with no mesh gets its whole rest from the saved pose. So root motion is never measured against the rest hips (see section 4), and a file exported without its mesh (Mixamo: "Without Skin") may have the wrong rest.

## 2. Matching bones by name (`AnimImport.classify`, `map_bones`)
Prefixes are stripped (`mixamorig:`, `mixamorig_` (Godot turns `:` into `_`), `mixamorig1_`, `Bip01`, `DEF-`, `Armature|` ...). Then a SIDE (left/right, `.L`/`_r` tokens, DAZ `lShldr`, Biped `L`) and a PART are read:

| Kine | Mixamo | UE4 / UE5 | Godot humanoid | Blender (metarig-like) | DAZ |
|---|---|---|---|---|---|
| pelvis | Hips | pelvis | Hips | hips / pelvis | hip |
| spine_01..03 | Spine, Spine1, Spine2 | spine_01..03 (UE5: 01..05) | Spine, Chest, UpperChest | spine, chest | abdomenLower/Upper, chestLower/Upper |
| neck_01, head | Neck, Head | neck_01, head | Neck, Head | neck, head | neckLower, head |
| clavicle_l | LeftShoulder | clavicle_l | LeftShoulder | shoulder.L | lCollar |
| upperarm_l | LeftArm | upperarm_l | LeftUpperArm | upper_arm.L | lShldrBend |
| lowerarm_l | LeftForeArm | lowerarm_l | LeftLowerArm | forearm.L | lForearmBend |
| hand_l | LeftHand | hand_l | LeftHand | hand.L | lHand |
| thigh_l | LeftUpLeg | thigh_l | LeftUpperLeg | thigh.L | lThighBend |
| calf_l | LeftLeg | calf_l | LeftLowerLeg | shin.L | lShin |
| foot_l / ball_l | LeftFoot / LeftToeBase | foot_l / ball_l | LeftFoot / LeftToes | foot.L / toe.L | lFoot / lToe |
| index_01..03_l | LeftHandIndex1..3 | index_01..03_l | LeftIndexProximal/Intermediate/Distal | | |
| thumb_01..03_l | LeftHandThumb1..3 | thumb_01..03_l | LeftThumbMetacarpal/Proximal/Distal | | |

- **The spine goes by STRUCTURE, not by name**: it is the bones strictly between the hips and the neck (or the clavicles' parent). Kine's spine_01 is the first of them, spine_03 is the last (the chest, which carries the clavicles and the neck), and spine_02 is the middle one. So UE5's five spine bones map to 01 / 03 / 05, and a two-bone spine leaves spine_02 at rest.
- These are never body joints: twist and roll correctives, IK targets (`ik_hand_r`), end and leaf bones (`HeadTop_End`, `LeftToe_End`, `*_leaf`), `root`, metacarpals, jaw, eyes, weapon and attach sockets.
- Where two bones match one joint, the one nearer the root wins. The REPORT lists every bone of the file that was not used, every main Kine joint left at rest, and how many finger joints stay at rest. It ends up in the status line and in the scene's `plan`. Fewer than 12 of the 22 main joints matched is refused, and so is a file with no hips.

## 3. Rotations: world deltas, corrected for the rest pose (`AnimImport.retarget`)
Kine's own model is `G[j] = G[parent] * A[j]` (world turn from rest), with `A` decomposed into bend / side / twist (`Body.decompose`). Retargeting is done in WORLD DELTAS, so neither skeleton's bone-axis convention matters (Blender's Y-along-the-bone and Kine's frames cancel out):
1. **Shared frame `C`**: left = left thigh minus right thigh (else the upper arms), up = pelvis to head (else neck, spine). Both are made square, and the frame is built the SAME way from Kine's rest and from the source's rest. `C = F_kine * F_src^-1` turns source space into Kine space, which handles Z-up versus Y-up and facing -Z versus +Z. Because the same rule is applied to both rests, Kine's 4.8 deg forward lean of pelvis-to-head is not taken as a tilt.
2. **Source world delta** per frame: `D = C * (Wsrc(t) * Wsrc_rest^-1) * C^-1`.
3. **Rest-pose difference** (Mixamo's A-pose against Kine's T-pose, spread legs ...), found by COMPARING REST ORIENTATIONS. For each mapped joint, `Roff` is the shortest turn from Kine's rest bone direction (joint to its child, or to its end point) to the source's (its mapped child, else its only child bone). A joint with no end to compare (a hand without fingers, a head without a top) inherits its parent's `Roff`. Then `G[j] = D * Roff[j]`: at the source's rest, Kine's bone points where the source's does. The test rig measures 40.0 deg on the arms and 4.0 deg on the legs, which are exactly the A-pose and spread it was built with.
4. `A[j] = G[parent]^-1 * G[j]`, then decompose and clamp to Kine's joint limits (a source that goes past a human limit is clamped, as any card is). A Kine joint with no source bone keeps its rest relation to its parent.
- The only approximation is that `Roff` is swing-only, because the twist about a bone cannot be read from joint positions. On the test rig the hinge elbows lose the tiny twist this leaves, and the hands land up to 3.2 mm off.

## 4. Root motion: scaled by the leg-length ratio
`ratio = leg_kine / leg_src`, where a leg is thigh to calf plus calf to foot at rest, both sides averaged. Without legs it falls back to the hips' height over the lowest bone. The hips go where the file has them, measured from the file's origin (its floor at height 0): `offset = C * hips_src(t) * ratio - pelvis_rest_kine`. The horizontal travel and the vertical bounce are both scaled, which is the same idea as UE's IK Retargeter, whose root / pelvis settings scale the translation between characters of different proportions so the feet do not float.

## 5. Cards (key reduction)
One card per frame is exact (the test checks it). The editable scene is made the way the video import makes it:
- `MocapClean.clean` (foot lock, pops mended), but only when Check finds a FOOT SLIDE. On a clean game clip (combo3 through .glb, which had no slide) the lock moved a pivoting foot 8.7 cm off the file's path and fixed nothing.
- `VideoImport.thin` (about 6 cards a second), REFINED by `AnimImport.refine`. Inside each gap, the frame the cards would blend worst is kept, until every joint's three angles are within 1 deg of the file and the hips within 5 mm. The scene blends cards linearly in bend/side/twist, so that blend is exactly what is measured. Without the refinement, even spacing blended combo3's bat swing 76.6 cm off its path. With it: 93 cards for 142 frames, worst 0.96 cm at every frame.

## Measured (tests/anim_import_test.gd)
- combo3, exported with our .glb exporter and imported back: all 52 joints within 0.000 cm at 10 times (one card per frame).
- The Mixamo-named FBX fixture (`tests/fixtures/make_mixamo_fbx.py` in Blender 4.5: an A-pose rest, legs spread 4 deg, 1.2x our size, Blender's own bone axes, a skinned mesh): 22 of 22 main bones mapped, only `HeadTop_End` reported unused, ratio 0.8333, and the hands and feet within 0.32 / 0.27 / 0.02 / 0.01 cm of Blender's own evaluated positions (/1.2) over 61 frames.
- Our .bvh with Mixamo joint names, through the retarget: 0.000 cm.

## Not done / limits
- Root motion carried on a parent NODE (some FBX files animate the Armature object, not the hips) is ignored.
- Only one clip per file (the longest; the report says how many there were).
- No IK pass after the retarget: on a very different proportion (long arms against short), hand contacts such as a two-handed grip are not kept, and feet are only kept when the foot lock runs.
- Swing-only rest comparison (section 3): the twist difference of rests about the bone itself is not corrected.
- Tested on a Blender-made Mixamo-named rig and our own exports, not yet on a real Mixamo or Unreal download.

## Sources (read 2026-10-18)
- Godot 4.7 classes `FBXDocument`, `FBXState`, `GLTFDocument`: checked in the engine with `ClassDB` (`FBXDocument` exists at run time, `append_from_file` + `generate_scene`).
- Epic, *Retargeting Bipeds with IK Rig*: "If these reference poses differ, such as if one character is T-posed and another is A-posed, then you will need to adjust one of their retarget poses so they match". Root translation is scaled and offset per character. https://dev.epicgames.com/documentation/en-us/unreal-engine/retargeting-bipeds-with-ik-rig-in-unreal-engine
- Epic, *Retargeting operation stack (UE 5.8)*: Pelvis Motion "ensures that translation data is scaled properly between characters of different proportions". https://dev.epicgames.com/documentation/en-us/unreal-engine/retargeting-operation-stack-in-unreal-engine-5-8
- Epic Python API, `TargetRootSettings` (scale horizontal / vertical of root motion): https://docs.unrealengine.com/PythonAPI/class/TargetRootSettings.html
- Mixamo leg chain Hips > LeftUpLeg > LeftLeg > LeftFoot > LeftToeBase > LeftToe_End (leaf), from Ready Player Me's Mixamo-compatible template: https://docs.readyplayer.me/asset-creation-guide/asset-creation/templates
- Godot `SkeletonProfileHumanoid` bone names: https://docs.godotengine.org/en/4.x/classes/class_skeletonprofilehumanoid.html
- Unity `HumanBodyBones` (the same humanoid set): https://docs.unity3d.com/ScriptReference/HumanBodyBones.html
