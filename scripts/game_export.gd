class_name GameExport
## EXPORT TO THE GAME (round 31, GATES LL, UPGRADES_200 #101-105).
##
## The ARPG (Unity 6) plays no clips. A move is a PoseTable in C# (D:/arpg/unity/Assets/Scripts/View/PoseTable.cs):
## per slot, keys (t 0..1 of the move, pitch, yaw, roll) in degrees from the GAME's rest, in the character's own frame,
## composed pitch * yaw * roll * rest (LimbRig.Joint.Set), each segment eased with smoothstep (PoseTrack.Sample).
##
## THE FOLD. Poser has ~60 joints, the game 13 slots (11 on a human: no hocks). A game bone's world rotation is the
## Poser rotation of the joint that ends its chain, so the joints in between fold in for free (spine_01..03 -> Chest,
## clavicle -> Arm, neck -> Head); hands, feet and fingers do not reach the game. Poser's G[j] is each joint's world
## rotation AWAY FROM ITS REST, so a slot's angles are its delta relative to its parent's delta:  D = Dp^-1 * Dg.
##
## THE ARMS. Poser's rest holds the arms OUT (T-pose); the game's hang DOWN (SKELETON.md). So an arm's delta carries the
## rotation between the two rests (C, the shortest turn from straight down to Poser's rest direction): Dg = G * C. At
## Poser's rest the game's arms are therefore raised ~90 degrees, which is what Poser shows. The spine, head and legs
## stand the same way in both rests, so C is the identity there (Poser's pelvis bone leans 14 degrees by anatomy, not pose).
##
## SIGNS, as PoseTable.cs states them: +pitch swings a limb FORWARD, +yaw turns the body to its LEFT, +roll drops the
## RIGHT shoulder. Poser's character: left = +x, up = +y, forward = +z. NOT YET CHECKED IN THE GAME (UPGRADES #105):
## SIGN flips one axis everywhere if the capture says so.

const RIGHT := Vector3(-1, 0, 0)
const UP := Vector3(0, 1, 0)
const FWD := Vector3(0, 0, 1)
const SIGN := Vector3(1, 1, 1)   # pitch, yaw, roll: -1 flips that axis for the game

## game slot -> [its index in LimbRig.Bone, the Poser joint that ends its chain, the parent slot ("" = the root)]
const SLOTS := {
	"Hips": [0, "pelvis", ""],
	"Head": [1, "head", "Chest"],
	"ArmL": [2, "upperarm_l", "Chest"],
	"ArmR": [3, "upperarm_r", "Chest"],
	"ThighL": [4, "thigh_l", "Hips"],
	"ThighR": [5, "thigh_r", "Hips"],
	"ShinL": [6, "calf_l", "ThighL"],
	"ShinR": [7, "calf_r", "ThighR"],
	"ForeL": [8, "lowerarm_l", "ArmL"],
	"ForeR": [9, "lowerarm_r", "ArmR"],
	"Chest": [10, "spine_03", "Hips"],
}
## parents before children
const ORDER := ["Hips", "Chest", "Head", "ArmL", "ArmR", "ForeL", "ForeR", "ThighL", "ThighR", "ShinL", "ShinR"]
const ARMS := ["ArmL", "ArmR", "ForeL", "ForeR"]
const FPS := 60.0
const TOL := 1.0   # degrees: the game's sampler must stay this close to Poser on every frame


## the rotation between the game's rest and Poser's for a slot (identity but on the arms)
static func rest_turn(B: Body, slot: String) -> Quaternion:
	if not slot in ARMS:
		return Quaternion.IDENTITY
	var j: String = SLOTS[slot][1]
	var d: Vector3 = (B.e0[j] - B.p0[j]).normalized()
	return Quaternion(Vector3.DOWN, d)


## the game's composition: pitch about the character's right, then yaw about up, then roll about forward
static func compose(a: Vector3) -> Quaternion:
	var s := a * SIGN
	return Quaternion(RIGHT, deg_to_rad(s.x)) * Quaternion(UP, deg_to_rad(s.y)) * Quaternion(FWD, deg_to_rad(s.z))


## the inverse of compose. With RIGHT = -x it is Rx(-p) Ry(y) Rz(r); for M = Rx(a) Ry(b) Rz(c):
## M02 = sin b, M12 = -sin a cos b, M22 = cos a cos b, M01 = -cos b sin c, M00 = cos b cos c (M_ij = basis[j][i])
static func decompose(q: Quaternion) -> Vector3:
	var m := Basis(q)
	var b := asin(clampf(m.z.x, -1.0, 1.0))
	var a := atan2(-m.z.y, m.z.z)
	var c := atan2(-m.y.x, m.x.x)
	return Vector3(rad_to_deg(-a), rad_to_deg(b), rad_to_deg(c)) * SIGN


## each slot's world delta as the game would hold it (Poser's G, times the rest turn on the arms)
static func deltas(B: Body) -> Dictionary:
	var out := {}
	for s in ORDER:
		out[s] = (B.G[SLOTS[s][1]] as Quaternion) * rest_turn(B, s)
	return out


## THE FOLD: the body's pose now -> {slot: Vector3(pitch, yaw, roll) degrees}
static func slot_angles(B: Body) -> Dictionary:
	var dg := deltas(B)
	var out := {}
	for s in ORDER:
		var p: String = SLOTS[s][2]
		var dp: Quaternion = dg[p] if p != "" else Quaternion.IDENTITY
		out[s] = decompose(dp.inverse() * dg[s])
	return out


## a slot's angles brought next to the previous frame's (no jump of 360 between frames)
static func _unwrap(a: Vector3, prev: Vector3) -> Vector3:
	var o := a
	for k in 3:
		while o[k] - prev[k] > 180.0:
			o[k] -= 360.0
		while o[k] - prev[k] < -180.0:
			o[k] += 360.0
	return o


## PoseTrack.Sample, re-implemented: smoothstep between the bracketing keys. keys = [[t, Vector3], ...], t ascending
static func sample_keys(keys: Array, t: float) -> Vector3:
	if keys.is_empty():
		return Vector3.ZERO
	if t <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if t > keys[i][0]:
			continue
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		var span: float = b[0] - a[0]
		var u: float = 1.0 if span <= 1e-6 else (t - a[0]) / span
		u = u * u * (3.0 - 2.0 * u)
		return (a[1] as Vector3).lerp(b[1], u)
	return keys[-1][1]


## the angle between two rotations, degrees
static func gap(a: Quaternion, b: Quaternion) -> float:
	return rad_to_deg(2.0 * acos(clampf(absf(a.dot(b)), 0.0, 1.0)))


## every 60 fps frame of the scene: [times, {slot: [Vector3 per frame]}] (Euler unwrapped frame to frame)
static func frames(S: Scene, B: Body) -> Array:
	var L := S.length()
	var n := maxi(2, int(ceil(L * FPS)) + 1)
	var ts := []
	var per := {}
	for s in ORDER:
		per[s] = []
	for k in n:
		var t := minf(k / FPS, L)
		ts.append(t)
		S.apply(B, t)
		var a := slot_angles(B)
		for s in ORDER:
			var v: Vector3 = a[s]
			if k > 0:
				v = _unwrap(v, per[s][-1])
			per[s].append(v)
	return [ts, per]


## THE TABLE: per slot, keys at the start, the end and every card's arrive and leave; then (refine) the worst frame
## added as a key until the game's sampler is within TOL of Poser on every frame. -> {"length", "frames", "tracks":
## {slot: [[t 0..1, Vector3], ...]}, "worst": {slot: degrees}}
static func table(S: Scene, B: Body, refine := true, tol := TOL) -> Dictionary:
	var fr := frames(S, B)
	var ts: Array = fr[0]
	var per: Dictionary = fr[1]
	var L := maxf(S.length(), 1e-6)
	var n := ts.size()
	var base := {0: true, n - 1: true}
	for c in S.times():
		for tt in [c[1], c[2]]:
			base[clampi(int(round(float(tt) * FPS)), 0, n - 1)] = true
	var tracks := {}
	var worst := {}
	for s in ORDER:
		var idx: Array = base.keys()
		var vals: Array = per[s]
		var exact := []
		for v in vals:
			exact.append(compose(v))
		while true:
			idx.sort()
			var keys := []
			for i in idx:
				keys.append([ts[i] / L, vals[i]])
			var w := 0.0
			var wi := -1
			for k in n:
				var g := gap(compose(sample_keys(keys, ts[k] / L)), exact[k])
				if g > w:
					w = g
					wi = k
			if not refine or w <= tol or idx.has(wi):
				tracks[s] = keys
				worst[s] = w
				break
			idx.append(wi)
	var out := {"length": S.length(), "frames": n, "tracks": tracks, "worst": worst}
	if not S.markers.is_empty():
		out["events"] = Markers.events(S.markers, S.length())   # WW5: only when the scene has markers (old exports are byte-identical)
	return out


## the table as JSON-ready data (Vector3 -> [pitch, yaw, roll], 2 decimals; t 4 decimals)
static func to_json(name: String, T: Dictionary) -> Dictionary:
	var tr := {}
	for s in ORDER:
		var ks := []
		for k in T["tracks"][s]:
			var v: Vector3 = k[1]
			ks.append([snappedf(k[0], 0.0001), snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)])
		tr[s] = ks
	var out := {"name": name, "seconds": snappedf(T["length"], 0.001), "bone_index": _indices(), "tracks": tr,
		"format": "PoseTable: t is a fraction of the move; pitch, yaw, roll in degrees from the game's rest (+pitch forward, +yaw left, +roll right shoulder down); smoothstep between keys"}
	if T.has("events"):
		out["events"] = T["events"]   # WW5: [{"t_frac", "name", "kind"}], the markers; absent without any
	return out


static func _indices() -> Dictionary:
	var o := {}
	for s in ORDER:
		o[s] = SLOTS[s][0]
	return o


## JSON data -> the same table shape (tracks of [t, Vector3])
static func from_json(d: Dictionary) -> Dictionary:
	var tr := {}
	for s in d["tracks"]:
		var ks := []
		for k in d["tracks"][s]:
			ks.append([float(k[0]), Vector3(k[1], k[2], k[3])])
		tr[s] = ks
	return {"length": float(d["seconds"]), "tracks": tr}


## the table in PoseTable.cs's own syntax, ready to paste into `Skills`
static func to_csharp(name: String, T: Dictionary) -> String:
	var J := to_json(name, T)
	var id := _ident(name)
	var lines := ["        /// <summary>%s: exported from Kine (%.3f s, %d keys). Paste into Skills.</summary>" % [name, J["seconds"], _count(J)],
		"        public static readonly PoseTable %s = new PoseTable(" % id]
	var blocks := []
	for s in ORDER:
		var b := ["            new PoseTrack(Bone.%s" % s]
		for k in J["tracks"][s]:
			b.append("                new PoseKey(%sf, pitch: %sf, yaw: %sf, roll: %sf)" % [_num(k[0], 4), _num(k[1], 2), _num(k[2], 2), _num(k[3], 2)])
		blocks.append(",\n".join(b) + ")")
	lines.append(",\n\n".join(blocks))
	lines.append("        );")
	return "\n".join(lines) + "\n"


static func _count(J: Dictionary) -> int:
	var n := 0
	for s in J["tracks"]:
		n += (J["tracks"][s] as Array).size()
	return n


static func _num(x: float, d: int) -> String:
	var s := String.num(x, d)
	return s if s.contains(".") else s + ".0"


static func _ident(name: String) -> String:
	var out := ""
	for part in name.replace("-", "_").replace(" ", "_").split("_", false):
		out += part.substr(0, 1).to_upper() + part.substr(1)
	if out.is_empty() or out[0].is_valid_int():
		out = "Clip" + out
	return out


## writes exports/<name>.json and exports/<name>.cs; -> [json path, cs path, the table]
static func write(S: Scene, B: Body, dir := "res://exports") -> Array:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var T := table(S, B)
	var jp := "%s/%s.json" % [dir, S.name]
	var cp := "%s/%s.cs" % [dir, S.name]
	var f := FileAccess.open(jp, FileAccess.WRITE)
	f.store_string(JSON.stringify(to_json(S.name, T), "\t"))
	f.close()
	f = FileAccess.open(cp, FileAccess.WRITE)
	f.store_string(to_csharp(S.name, T))
	f.close()
	return [jp, cp, T]
