## game_clip.gd - GAME DELIVERY PER CLIP (INNOVATIONS N083, N086, N087, N090; N081/N082 ride in the same sidecar).
##  N083 rate_range: the play-rate range where the move stays human and the planted feet do not slide against the root.
##   Engine model: the engine moves the root at the clip authored speed, the clip plays at rate r; a planted foot that travels L (m) relative to the root
##   during its plant then slides L*|1-r|/r. Edges: lo = L/(L+SLIDE_BAR), hi = L/(L-SLIDE_BAR). Human side: the fastest shoulder / knee / trunk joint speed times r
##   stays under HumanLimits.SPEED (group means and one pitching peak: a LOW bar for peaks, see human_limits.gd).
##  N086 contacts: per-frame foot and hand contact weights 0..1. A foot with plants reads FootPlant.weight_at (the max over its plants); a foot without
##   plants is derived from the motion (ankle within 2-6 cm of the clip lowest ankle and slower than 0.15-0.4 m/s). A hand is 1 while it holds the weapon or is within 3 cm of the floor.
##  N087 compress: key reduction with the error budget in metres at the hands, feet and weapon tip (not degrees per curve). Each joint tolerance is the tip
##   budget divided by its reach to the tips it moves; the budget scale is bisected until the measured worst tip error (240 Hz) meets the bar.
##  Sidecar <name>.clip.json: contacts + rate + cancel windows (N081) + reactable (N082). write_addon copies addons/kine_body_check (N090) next to an export.
class_name GameClip
extends RefCounted

const SLIDE_BAR := 0.025   # m: the rulebook FOOT SLIDE bar
const RATE_MIN := 0.25
const RATE_MAX := 8.0
const SPEED_CLASS := {"upperarm_l": "shoulder", "upperarm_r": "shoulder", "calf_l": "knee", "calf_r": "knee", "spine_01": "trunk", "spine_02": "trunk", "spine_03": "trunk"}
const TIP_JOINTS := ["hand_l", "hand_r", "foot_l", "foot_r"]
const ADDON := "res://addons/kine_body_check"
const ADDON_FILES := ["body_check.gd", "limits.json"]


static func slide_at(L: float, r: float) -> float:
	return L * absf(1.0 - r) / maxf(r, 1e-6)


static func nframes(S: Scene, fps: int) -> int:
	return int(round(S.length() * float(fps))) + 1


static func _ss(a: float, b: float, x: float) -> float:
	var u := clampf((x - a) / (b - a), 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## {"fps", "n", "foot_l", "foot_r", "hand_l", "hand_r"}: Array of float per frame (frame k = t k/fps). Leaves B posed at the end.
static func contacts(S: Scene, B: Body, fps := 60) -> Dictionary:
	var n := nframes(S, fps)
	var out := {"fps": fps, "n": n, "foot_l": [], "foot_r": [], "hand_l": [], "hand_r": []}
	var ank := {"foot_l": [], "foot_r": []}
	var hy := {"hand_l": [], "hand_r": []}
	var holds := []
	for k in n:
		S.apply(B, minf(float(k) / float(fps), S.length()))
		for f in ank:
			ank[f].append(B.P[f])
		for h in hy:
			hy[h].append((B.E[h] as Vector3).y)
		holds.append((B.wep_hand if B.wep_hand != "" else "hand_r") if B.wep_on else "")
	var floor_y := 1e9
	for f in ank:
		for p in ank[f]:
			floor_y = minf(floor_y, (p as Vector3).y)
	for f in ["foot_l", "foot_r"]:
		var idx := []
		for i in S.plants.size():
			if String(S.plants[i]["foot"]) == f:
				idx.append(i)
		for k in n:
			var w := 0.0
			if not idx.is_empty():
				for i in idx:
					w = maxf(w, FootPlant.weight_at(S.plants, i, float(k) / float(fps), fps))
			else:
				var a: Array = ank[f]
				var ka := maxi(k - 1, 0)
				var kb := mini(k + 1, n - 1)
				var v := 0.0
				if kb > ka:
					v = ((a[kb] as Vector3) - (a[ka] as Vector3)).length() * float(fps) / float(kb - ka)
				w = (1.0 - _ss(0.02, 0.06, (a[k] as Vector3).y - floor_y)) * (1.0 - _ss(0.15, 0.4, v))
			out[f].append(w)
	for h in ["hand_l", "hand_r"]:
		for k in n:
			out[h].append(1.0 if (holds[k] == h or float(hy[h][k]) <= 0.03) else 0.0)
	return out


## {"lo", "hi", "hi_slide", "hi_human", "stride_m", "peak_deg_s": {class: deg/s}}
static func rate_range(S: Scene, B: Body, fps := 60) -> Dictionary:
	var C := contacts(S, B, fps)
	var n := int(C["n"])
	var rel := {"foot_l": [], "foot_r": []}
	var peak := {"shoulder": 0.0, "knee": 0.0, "trunk": 0.0}
	var prev := {}
	for k in n:
		S.apply(B, minf(float(k) / float(fps), S.length()))
		for f in rel:
			var r: Vector3 = (B.P[f] as Vector3) - (B.P["pelvis"] as Vector3)
			r.y = 0.0
			rel[f].append(r)
		for j in SPEED_CLASS:
			var v: Vector3 = B.ang[j]
			if prev.has(j):
				var c: String = SPEED_CLASS[j]
				peak[c] = maxf(float(peak[c]), (v - (prev[j] as Vector3)).length() * float(fps))
			prev[j] = v
	var L := 0.0
	for f in rel:
		var k := 0
		while k < n:
			if float(C[f][k]) >= 0.999:
				var a0: Vector3 = rel[f][k]
				while k < n and float(C[f][k]) >= 0.999:
					L = maxf(L, ((rel[f][k] as Vector3) - a0).length())
					k += 1
			else:
				k += 1
	var lo := RATE_MIN
	var hi_s := RATE_MAX
	if L > SLIDE_BAR:
		lo = maxf(L / (L + SLIDE_BAR), RATE_MIN)
		hi_s = minf(L / (L - SLIDE_BAR), RATE_MAX)
	var hi_h := RATE_MAX
	for c in peak:
		if float(peak[c]) > 1e-6:
			hi_h = minf(hi_h, float(HumanLimits.SPEED[c]) / float(peak[c]))
	return {"lo": lo, "hi": minf(hi_s, hi_h), "hi_slide": hi_s, "hi_human": hi_h, "stride_m": L, "peak_deg_s": peak}


static func _tips(B: Body) -> Array:
	var o := []
	for n in TIP_JOINTS:
		o.append(B.E[n])
	o.append(B.wep_point(B.wep_len) if B.wep_on else B.E["hand_r"])
	return o


## worst tip distance (m) over hands, feet, weapon tip: the scene own keys against pk, on a hz grid. ref = cached original tips (or [])
static func tip_error(S: Scene, B: Body, pk: Dictionary, hz := 240, ref: Array = []) -> float:
	var C := S.clone()
	C.part_keys = pk.duplicate(true)
	var n := int(round(S.length() * float(hz)))
	var worst := 0.0
	for k in n + 1:
		var t := minf(float(k) / float(hz), S.length())
		var a: Array
		if ref.is_empty():
			S.apply(B, t)
			a = _tips(B)
		else:
			a = ref[k]
		C.apply(B, t)
		var b := _tips(B)
		for i in a.size():
			worst = maxf(worst, ((a[i] as Vector3) - (b[i] as Vector3)).length())
	return worst


static func _ref_tips(S: Scene, B: Body, hz: int) -> Array:
	var ref := []
	var n := int(round(S.length() * float(hz)))
	for k in n + 1:
		S.apply(B, minf(float(k) / float(hz), S.length()))
		ref.append(_tips(B))
	return ref


## each keyed joint reach (m) to the tips it moves (a joint above the tip in the chain), at the scene first frame
static func reach(S: Scene, B: Body) -> Dictionary:
	S.apply(B, 0.0)
	var wj: String = B.wep_hand if B.wep_hand != "" else "hand_r"
	var out := {}
	for j in S.part_keys:
		var r := 0.0
		var tips := TIP_JOINTS.duplicate()
		if B.wep_on:
			tips.append("bat")
		for tp in tips:
			var anchor: String = wj if tp == "bat" else String(tp)
			var q := anchor
			var below := false
			while q != "":
				if q == j:
					below = true
					break
				q = String(B.parent.get(q, ""))
			if below:
				var pos: Vector3 = B.wep_point(B.wep_len) if tp == "bat" else B.E[tp]
				r = maxf(r, (pos - (B.P[j] as Vector3)).length())
		out[j] = r if r > 0.0 else 0.3
	return out


static func _count(pk: Dictionary) -> int:
	var c := 0
	for j in pk:
		c += (pk[j] as Array).size()
	return c


static func _reduce_with(pk: Dictionary, tols: Dictionary) -> Dictionary:
	var out := {}
	for j in pk:
		out[j] = KeyReduce.reduce({j: pk[j]}, float(tols[j]))["pk"][j]
	return out


static func _search(S: Scene, B: Body, bar: float, hi0: float, tol_of: Callable) -> Dictionary:
	var ref := _ref_tips(S, B, 240)
	var lo := 0.0
	var hi := hi0
	var best := S.part_keys.duplicate(true)
	var worst := 0.0
	for it in 10:
		var k := 0.5 * (lo + hi)
		var pk := _reduce_with(S.part_keys, tol_of.call(k))
		var e := tip_error(S, B, pk, 240, ref)
		if e <= bar:
			lo = k
			best = pk
			worst = e
		else:
			hi = k
	return {"pk": best, "before": _count(S.part_keys), "after": _count(best), "worst_m": worst, "k": lo}


## body-aware: tol_j (deg) = degrees of k metres of tip travel at the joint reach. Bisects k so the measured worst tip error <= bar_m.
static func compress(S: Scene, B: Body, bar_m := 0.005) -> Dictionary:
	var R := reach(S, B)
	return _search(S, B, bar_m, 6.0 * bar_m, func(k: float) -> Dictionary:
		var t := {}
		for j in R:
			t[j] = rad_to_deg(k / maxf(float(R[j]), 0.05))
		return t)


## the same search with ONE tolerance in degrees for every joint (what a per-curve reducer does); "k" is that tolerance
static func compress_uniform(S: Scene, B: Body, bar_m := 0.005) -> Dictionary:
	return _search(S, B, bar_m, 6.0, func(k: float) -> Dictionary:
		var t := {}
		for j in S.part_keys:
			t[j] = k
		return t)


static func _round(a: Array) -> Array:
	var o := []
	for x in a:
		o.append(snappedf(float(x), 0.001))
	return o


static func sidecar(S: Scene, B: Body, name: String, fps := 60, latency_ms := 0.0) -> Dictionary:
	var C := contacts(S, B, fps)
	var cj := {"fps": fps, "n": C["n"]}
	for k in ["foot_l", "foot_r", "hand_l", "hand_r"]:
		cj[k] = _round(C[k])
	var R := rate_range(S, B, fps)
	var rj := {}
	for k in ["lo", "hi", "hi_slide", "hi_human", "stride_m"]:
		rj[k] = snappedf(float(R[k]), 0.0001)
	return {"name": name, "fps": fps, "contacts": cj, "rate": rj,
		"cancel": CancelWindows.to_json(CancelWindows.analyze(S, B, fps)),
		"reactable": Reactable.to_json(Reactable.of_scene(S, B, fps, latency_ms))}


## writes <dir>/<name>.clip.json; returns its path
static func write_sidecar(S: Scene, B: Body, dir: String, name: String, fps := 60) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var p := "%s/%s.clip.json" % [dir, name]
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(sidecar(S, B, name, fps)))
	f.close()
	return p


## copies the runtime add-on to <dir>/addons/kine_body_check/ (ship it with the export)
static func write_addon(dir: String) -> void:
	var to := dir + "/addons/kine_body_check"
	DirAccess.make_dir_recursive_absolute(to)
	for fn in ADDON_FILES:
		var f := FileAccess.open(to + "/" + fn, FileAccess.WRITE)
		f.store_buffer(FileAccess.get_file_as_bytes(ADDON + "/" + fn))
		f.close()


## SERVE game_clip {clip?, dir?, fps?}: writes the sidecar and the add-on; no clip = the live scene
static func serve(m: Node, p: Dictionary) -> Dictionary:
	var S: Scene = m.S
	if p.has("clip"):
		var path := AgentTools.res(String(p["clip"]))
		if not FileAccess.file_exists(path):
			return {"ok": false, "error": "game_clip: no such scene file '%s'" % p["clip"]}
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not d is Dictionary:
			return {"ok": false, "error": "game_clip: '%s' is not a scene file" % p["clip"]}
		S = Scene.new()
		S.from_dict(d)
	if S.cards.is_empty():
		return {"ok": false, "error": "game_clip needs a scene with cards"}
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	B.ground()
	var dir := String(p.get("dir", "user://exports"))
	var jp := write_sidecar(S, B, dir, S.name if S.name != "" else "clip", int(p.get("fps", 60)))
	write_addon(dir)
	return {"ok": true, "result": {"sidecar": jp, "addon": dir + "/addons/kine_body_check"}}
