"""TEST FIXTURE ONLY (tests/anim_import_test.gd): a Mixamo-named skeleton with a DIFFERENT rest pose, animated, as .fbx.
Run by Blender, never by the app:
    blender -b --factory-startup --python tests/fixtures/make_mixamo_fbx.py -- data/skeleton.json out.fbx out_ref.json

THE RIG: Kine's joints (data/skeleton.json, read only) scaled by S = 1.2, the bones named as Mixamo names them
("mixamorig:Hips", "mixamorig:LeftArm" ...), plus a "mixamorig:HeadTop_End" leaf. The REST POSE differs from Kine's
T-pose: the arms hang 40 deg down (an A-pose) and the legs are spread 4 deg each. Blender's own bone axes (Y along the
bone, roll 0) differ from Kine's too.

THE MOTION (61 frames, 30 fps): the hips travel 0.4 m (x S) forward, bob and turn; the spine bends; the neck turns; the
left arm swings forward and its elbow bends; the right arm rises to the side and its elbow bends; the left hip flexes
with the knee; the right leg extends. Each rotation is written as a turn about an axis of Kine's REST frame (y up,
+z his front, +x his left) applied as a local turn A (world delta G = G_parent * A, Kine's own convention), then turned
into the source's world delta D = G * Roff^-1, Roff being the rest difference of the bone's chain (the A-pose turn for
an arm, the spread for a leg). So a correct retarget brings back joint positions exactly S x Kine's.

THE REFERENCE (out_ref.json): every bone's head, in Blender's world coordinates, as BLENDER evaluates the posed rig
after keying (not my formula), per frame; plus S and the axis map Kine -> Blender (x, y, z) = (kx, -kz, ky).
"""
import json
import math
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SKEL, OUT_FBX, OUT_REF = argv[0], argv[1], argv[2]
S = 1.2
FPS = 30
N = 61
PRE = "mixamorig:"

# Kine joint -> Mixamo name
MAP = {"pelvis": "Hips", "spine_01": "Spine", "spine_02": "Spine1", "spine_03": "Spine2", "neck_01": "Neck",
       "head": "Head", "clavicle_l": "LeftShoulder", "upperarm_l": "LeftArm", "lowerarm_l": "LeftForeArm",
       "hand_l": "LeftHand", "clavicle_r": "RightShoulder", "upperarm_r": "RightArm", "lowerarm_r": "RightForeArm",
       "hand_r": "RightHand", "thigh_l": "LeftUpLeg", "calf_l": "LeftLeg", "foot_l": "LeftFoot", "ball_l": "LeftToeBase",
       "thigh_r": "RightUpLeg", "calf_r": "RightLeg", "foot_r": "RightFoot", "ball_r": "RightToeBase"}
ORDER = list(MAP.keys())   # parents before children
CHILD = {"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01", "neck_01": "head",
         "clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l", "clavicle_r": "upperarm_r",
         "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r", "thigh_l": "calf_l", "calf_l": "foot_l", "foot_l": "ball_l",
         "thigh_r": "calf_r", "calf_r": "foot_r", "foot_r": "ball_r"}

sk = json.load(open(SKEL))["joints"]
p0 = {j: Vector(sk[j]["pos"]) for j in ORDER}
par = {j: (sk[j]["parent"] or "") for j in ORDER}
end0 = {}
for j in ORDER:
    if j in CHILD:
        end0[j] = p0[CHILD[j]]
    elif j == "hand_l":
        end0[j] = Vector(sk["middle_01_l"]["pos"])
    elif j == "hand_r":
        end0[j] = Vector(sk["middle_01_r"]["pos"])
    else:
        end0[j] = Vector(sk[j]["end"])


def rot(axis, deg):
    return Quaternion(Vector(axis).normalized(), math.radians(deg))


X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
# the rest difference per chain (Kine frame): A-pose arms, spread legs
ROFF = {j: Quaternion() for j in ORDER}
PIVOT = {}
for j in ["upperarm_l", "lowerarm_l", "hand_l"]:
    ROFF[j] = rot(Z, -40.0)
    PIVOT[j] = "upperarm_l"
for j in ["upperarm_r", "lowerarm_r", "hand_r"]:
    ROFF[j] = rot(Z, 40.0)
    PIVOT[j] = "upperarm_r"
for j in ["thigh_l", "calf_l", "foot_l", "ball_l"]:
    ROFF[j] = rot(Z, 4.0)
    PIVOT[j] = "thigh_l"
for j in ["thigh_r", "calf_r", "foot_r", "ball_r"]:
    ROFF[j] = rot(Z, -4.0)
    PIVOT[j] = "thigh_r"


def src_point(j, p):
    """a Kine rest point on joint j's chain -> the source's rest point (Kine frame, x S)"""
    if j in PIVOT:
        pv = p0[PIVOT[j]]
        return S * (pv + ROFF[j] @ (p - pv))
    return S * p


rest_head = {j: src_point(j, p0[j]) for j in ORDER}
rest_tail = {j: src_point(j, end0[j]) for j in ORDER}


def w(t, ph=0.0):
    return 0.5 - 0.5 * math.cos(2.0 * math.pi * (t / ((N - 1) / FPS)) + ph)


def local_A(j, t):
    """Kine local turn (rest frame axes), inside Kine's limits"""
    a = w(t)
    b = w(t, 1.0)
    return {
        "pelvis": rot(Y, 20.0 * math.sin(2.0 * math.pi * t / 2.0)),
        "spine_01": rot(X, 12.0 * a),
        "spine_02": rot(X, 8.0 * b),
        "neck_01": rot(Y, 25.0 * math.sin(2.0 * math.pi * t / 2.0)),
        "head": rot(X, 10.0 * a),
        "upperarm_l": rot(Y, -55.0 * a) @ rot(Z, -20.0 * b),
        "lowerarm_l": rot((0, -1, 0), 70.0 * a),
        "hand_l": rot(Z, 15.0 * b),
        "upperarm_r": rot(Z, -35.0 * b),
        "lowerarm_r": rot(Y, 50.0 * b),
        "hand_r": rot(Z, -12.0 * a),
        "thigh_l": rot(X, -40.0 * a),
        "calf_l": rot(X, 55.0 * a),
        "foot_l": rot(X, 10.0 * b),
        "thigh_r": rot(X, 15.0 * b),
        "calf_r": rot(X, 25.0 * b),
        "foot_r": rot(X, -8.0 * a),
    }.get(j, Quaternion())


def offset(t):
    T = (N - 1) / FPS
    return Vector((0.1 * math.sin(2.0 * math.pi * t / T), -0.05 * w(t, 0.5), 0.4 * t / T))


# Kine frame -> Blender frame: (x, y, z) = (kx, -kz, ky)
MB = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))


def to_b(v):
    return MB @ v


bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
scn.render.fps = FPS
scn.frame_start = 0
scn.frame_end = N - 1
arm_data = bpy.data.armatures.new("Armature")
arm = bpy.data.objects.new("Armature", arm_data)
scn.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = {}
for j in ORDER:
    b = arm_data.edit_bones.new(PRE + MAP[j])
    b.head = to_b(rest_head[j])
    b.tail = to_b(rest_tail[j])
    b.roll = 0.0
    if par[j]:
        b.parent = eb[par[j]]
        b.use_connect = False
    eb[j] = b
top = arm_data.edit_bones.new(PRE + "HeadTop_End")
top.head = to_b(rest_tail["head"])
top.tail = top.head + Vector((0, 0, 0.05))
top.parent = eb["head"]
bpy.ops.object.mode_set(mode="POSE")

rest_m = {j: arm_data.bones[PRE + MAP[j]].matrix_local.copy() for j in ORDER}
for pb in arm.pose.bones:
    pb.rotation_mode = "QUATERNION"

for f in range(N):
    t = f / FPS
    G = {}
    P = {}
    posem = {}
    for j in ORDER:
        A = local_A(j, t)
        G[j] = G[par[j]] @ A if par[j] else A
    # the source's world delta and posed heads (Kine frame)
    D = {j: G[j] @ ROFF[j].inverted() for j in ORDER}
    for j in ORDER:
        if par[j]:
            P[j] = P[par[j]] + D[par[j]] @ (rest_head[j] - rest_head[par[j]])
        else:
            P[j] = rest_head[j] + S * offset(t)
    for j in ORDER:
        Db = (MB @ D[j].to_matrix() @ MB.transposed())
        R = rest_m[j]
        M = Matrix.Translation(to_b(P[j])) @ (Db @ R.to_3x3()).to_4x4()
        posem[j] = M
        if par[j]:
            Rp = rest_m[par[j]]
            basis = (Rp.inverted() @ R).inverted() @ posem[par[j]].inverted() @ M
        else:
            basis = R.inverted() @ M
        pb = arm.pose.bones[PRE + MAP[j]]
        loc, q, _sc = basis.decompose()
        pb.location = loc
        pb.rotation_quaternion = q
        pb.keyframe_insert("location", frame=f)
        pb.keyframe_insert("rotation_quaternion", frame=f)

ref = {"S": S, "fps": FPS, "frames": N, "axes": "blender = (kx, -kz, ky) of Kine's (y up, +z front, +x his left)",
       "map": MAP, "heads": []}
for f in range(N):
    scn.frame_set(f)
    row = {}
    for j in ORDER:
        h = arm.matrix_world @ arm.pose.bones[PRE + MAP[j]].head
        row[j] = [h.x, h.y, h.z]
    ref["heads"].append(row)
for row in ref["heads"]:
    for j in row:
        row[j] = [round(x, 6) for x in row[j]]
json.dump(ref, open(OUT_REF, "w"), separators=(",", ":"))

bpy.ops.object.mode_set(mode="OBJECT")
# a skinned mesh, as a Mixamo character has: its BIND POSE is what makes the FBX's rest the rig's rest (an armature alone
# is written in whatever pose it stands in). A small box per bone, weighted fully to it.
verts = []
faces = []
for j in ORDER:
    h = to_b(rest_head[j])
    t = to_b(rest_tail[j])
    k = len(verts)
    d = 0.02
    for v in [h + Vector((-d, -d, 0)), h + Vector((d, -d, 0)), h + Vector((d, d, 0)), h + Vector((-d, d, 0)), t]:
        verts.append(v)
    faces += [(k, k + 1, k + 4), (k + 1, k + 2, k + 4), (k + 2, k + 3, k + 4), (k + 3, k, k + 4), (k, k + 3, k + 2, k + 1)]
me = bpy.data.meshes.new("Body")
me.from_pydata([tuple(v) for v in verts], [], faces)
body = bpy.data.objects.new("Body", me)
scn.collection.objects.link(body)
body.parent = arm
for n, j in enumerate(ORDER):
    vg = body.vertex_groups.new(name=PRE + MAP[j])
    vg.add(list(range(n * 5, n * 5 + 5)), 1.0, "REPLACE")
mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = arm
scn.frame_set(0)
bpy.ops.export_scene.fbx(filepath=OUT_FBX, object_types={"ARMATURE", "MESH"}, add_leaf_bones=False, bake_anim=True,
                         bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False,
                         bake_anim_force_startend_keying=True, bake_anim_simplify_factor=0.0, bake_anim_step=1.0)
print("FIXTURE OK", OUT_FBX, OUT_REF)
