## REAL-MOCAP POSE CHECK (ROADMAP I48). How typical is each card's pose of what people actually do? The reference is a small
## statistic built OFFLINE (tools/i48_dump.gd + tools/i48_build.py) from the CMU Graphics Lab Motion Capture Database
## (mocap.cs.cmu.edu, "free for all uses"; terms quoted in docs/physics_constants_i48.md). Nothing of the raw data ships: res://data_gen/mocap_stat.json
## holds (a) per joint group a smoothed occupancy table of 20-degree cells over the group's Kine angles and the quantiles of the
## density the real frames themselves have there, and (b) a few hundred real poses (k-means medoids, angles rounded to 2 deg).
## Groups (the angles are Kine's own, after the app's retarget path):
##   arm   shoulder + elbow : upperarm bend, side, twist + lowerarm bend   (right side mirrored onto the left: twist negated, as Body.mirror_side)
##   leg   hip + knee       : thigh bend, side, twist + calf bend          (same)
##   spine spine chain      : sum of the three spine bends, sides, twists + neck and head bend together
## A pose's score per group = the PERCENT of real frames whose density in that group is at or below this pose's (0 = never seen
## near it). The card's score is its lowest group; below FLAG_PCT it is flagged, with the nearest real pose and the joints that differ most.
## analyze() poses the body and puts it back (B.state() / B.set_state()); it writes nothing.
class_name MocapCheck
extends RefCounted

const PATH := "res://data_gen/mocap_stat.json"
## a card is flagged when fewer than this percent of real mocap frames sit in a less-visited place (measured on frames of
## clips the statistic never saw: docs/physics_constants_i48.md)
const FLAG_PCT := 1.0
## the joints compared for the nearest real pose (the pelvis is left out: its angles carry which way the clip faced)
const JOINTS := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
	"thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
## left out of the nearest-pose search and the ghost (the ghost wears the card's own): the pelvis carries which way the clip faced, and the
## retargeted feet came out with side/twist near +-170 deg on the CMU skeleton (their foot axes are not Kine's), so they carry no signal
const NEAR_SKIP := ["pelvis", "foot_l", "foot_r"]
const GROUP_NAMES := {"arm": "shoulder + elbow", "leg": "hip + knee", "spine": "spine chain"}

static var _stat: Dictionary = {}
static var _loaded := false


static func stat() -> Dictionary:
	if not _loaded:
		_loaded = true
		var s: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_stat = s if s is Dictionary else {}
	return _stat


## the group's feature vector (cell coordinates are floor(angle / bin)) from a pose {joint: Vector3(bend, side, twist)}
static func feats(group: String, side: String, ang: Dictionary) -> Array:
	var f: Array = []
	if group == "spine":
		var sb := 0.0
		var ss := 0.0
		var st := 0.0
		for j in ["spine_01", "spine_02", "spine_03"]:
			var v: Vector3 = ang.get(j, Vector3.ZERO)
			sb += v.x
			ss += v.y
			st += v.z
		var n: Vector3 = ang.get("neck_01", Vector3.ZERO)
		var h: Vector3 = ang.get("head", Vector3.ZERO)
		return [sb, ss, st, n.x + h.x]
	var top := "upperarm" if group == "arm" else "thigh"
	var low := "lowerarm" if group == "arm" else "calf"
	var a: Vector3 = ang.get(top + side, Vector3.ZERO)
	var b: Vector3 = ang.get(low + side, Vector3.ZERO)
	var sg := -1.0 if side == "_r" else 1.0
	return [a.x, a.y, a.z * sg, b.x]


static func _key(f: Array, bin: float) -> String:
	return "%d,%d,%d,%d" % [floori(float(f[0]) / bin), floori(float(f[1]) / bin), floori(float(f[2]) / bin), floori(float(f[3]) / bin)]


## percent of real frames at or below density d (a sorted quantile list q of 0..100 percent)
static func _pct(q: Array, d: float) -> float:
	if d <= 0.0 or q.is_empty():
		return 0.0
	var lo := 0
	var hi := q.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if float(q[mid]) <= d:
			lo = mid + 1
		else:
			hi = mid
	return 100.0 * float(lo) / float(q.size())


## {"pct": lowest group score, "rows": [{"group","side","label","pct","feat": Array}], "worst": the lowest row}
static func score(ang: Dictionary) -> Dictionary:
	var st := stat()
	var rows: Array = []
	if st.is_empty():
		return {"pct": 100.0, "rows": rows, "worst": {}}
	var bin: float = st["bin"]
	for g in ["arm", "leg", "spine"]:
		var G: Dictionary = st["groups"][g]
		for side in (["_l", "_r"] if g != "spine" else [""]):
			var f := feats(g, side, ang)
			var d: float = float((G["cells"] as Dictionary).get(_key(f, bin), 0.0))
			rows.append({"group": g, "side": side, "label": "%s%s" % [GROUP_NAMES[g], (" (left)" if side == "_l" else " (right)") if side != "" else ""],
				"pct": _pct(G["q"], d), "feat": f})
	var worst: Dictionary = rows[0]
	for r in rows:
		if float(r["pct"]) < float(worst["pct"]):
			worst = r
	return {"pct": float(worst["pct"]), "rows": rows, "worst": worst}


static func _vec(ang: Dictionary) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	for j in JOINTS:
		if j == "pelvis":
			continue
		var a: Vector3 = ang.get(j, Vector3.ZERO)
		v.append_array([a.x, a.y, a.z])
	return v


## the nearest real pose by the root-mean-square angle difference over the 19 joints (not the pelvis and feet: NEAR_SKIP):
## {"i", "rms", "top": [[joint, deg]] largest first (the angle difference of the joint as a 3D vector, degrees), "ang": {joint: Vector3}}
static func nearest(ang: Dictionary) -> Dictionary:
	var st := stat()
	if st.is_empty():
		return {}
	var P: Dictionary = st["poses"]
	var step: float = P["step"]
	var js: Array = P["joints"]
	var q := _vec(ang)
	var used: Array = []
	for k in js.size():
		used.append(not NEAR_SKIP.has(js[k]))
	var best := -1
	var bd := INF
	var rows: Array = P["rows"]
	for i in rows.size():
		var r: Array = rows[i]
		var s := 0.0
		for k in r.size():
			if not used[k / 3]:
				continue
			var d := q[k] - float(r[k]) * step
			s += d * d
		if s < bd:
			bd = s
			best = i
	var row: Array = rows[best]
	var A := {}
	var diffs: Array = []
	var nused := 0
	for k in js.size():
		var v := Vector3(float(row[3 * k]), float(row[3 * k + 1]), float(row[3 * k + 2])) * step
		if not used[k]:
			continue
		nused += 1
		A[js[k]] = v
		var mine: Vector3 = ang.get(js[k], Vector3.ZERO)
		diffs.append([js[k], (mine - v).length()])
	diffs.sort_custom(func(a, b): return a[1] > b[1])
	return {"i": best, "rms": sqrt(bd / float(3 * nused)), "top": diffs.slice(0, 4), "ang": A}


## the same measure between two poses (RMS angle difference over the joints nearest() compares)
static func rms(a: Dictionary, b: Dictionary) -> float:
	var s := 0.0
	var n := 0
	for j in JOINTS:
		if NEAR_SKIP.has(j):
			continue
		var d: Vector3 = (a.get(j, Vector3.ZERO) as Vector3) - (b.get(j, Vector3.ZERO) as Vector3)
		s += d.length_squared()
		n += 3
	return sqrt(s / float(n))


## a one-card scene holding the real pose (for the ghost)
static func pose_scene(real: Dictionary) -> Scene:
	var S := Scene.new()
	var jd := {}
	for j in real:
		var v: Vector3 = real[j]
		jd[j] = {"bend": v.x, "side": v.y, "twist": v.z}
	S.add("real", {"joints": jd})
	return S


## every card: {"i","name","t","pct","label","flag","near": nearest(), "rows"}. B is put back exactly.
static func analyze(S: Scene, B: Body) -> Dictionary:
	var out := {"ok": false, "cards": [], "flagged": 0, "msg": ""}
	if stat().is_empty():
		out["msg"] = "the real-mocap statistic (data_gen/mocap_stat.json) is missing: run tools/i48_build.py"
		return out
	if S.cards.is_empty():
		out["msg"] = "no cards"
		return out
	var keep: Dictionary = B.state()
	var tm := S.times()
	for i in S.cards.size():
		S.apply(B, float(tm[i][1]))
		var ang := {}
		for j in JOINTS:
			ang[j] = B.ang[j]
		var sc := score(ang)
		var flag: bool = float(sc["pct"]) < FLAG_PCT
		var row := {"i": i, "name": String(S.cards[i]["name"]), "t": float(tm[i][1]), "pct": sc["pct"], "label": sc["worst"].get("label", ""), "flag": flag, "rows": sc["rows"], "ang": ang}
		if flag:
			row["near"] = nearest(ang)
			out["flagged"] = int(out["flagged"]) + 1
		out["cards"].append(row)
	B.set_state(keep)
	B.fk()
	out["ok"] = true
	out["msg"] = "%d of %d cards sit where fewer than %.0f%% of real mocap frames are" % [out["flagged"], S.cards.size(), FLAG_PCT] if int(out["flagged"]) > 0 else "every card is a pose people really make (none below the %.0f%% line)" % FLAG_PCT
	return out
