## shot_fx.gd - CAMERA SHAKE and RACK FOCUS on the shot camera (ROADMAP 76). The keys' maths lives in shot_camera.gd;
## this file holds the two things a shot can add on top of it. Each SHOT (ShotCam, shot_camera.gd) carries its own fx next to
## its camera keys, so every shot has its own shake and rack focus (ROADMAP 75):
##   shot.fx = {"shake": [impact events], "focus": [focus keys]}
##
## SHAKE: an event {"t" (start s), "dur" (s), "cm" Vector3 (x right, y up, z forward of the camera, cm), "deg" Vector3
## (pitch, yaw, roll of the camera, deg), "hz" (the base frequency), "decay" (e-folds over the event), "seed", "name"}.
## Each of the six channels is   amp * S(s) * env(u),   u = s / dur,   env(u) = exp(-decay u) (1 - u)
## S(s) = sum over 3 components of w_k cos(2 pi f_k s), the weights w_k (sum 1) and the frequency spread f_k = hz * r_k
## (r_k = 1, 1.7, 2.6, each jittered by the seed) drawn from the seed, so the same seed is the same shake, always.
## The components start on their crest, so S(0) = 1 and |S| <= 1 everywhere: the peak of a channel is its amplitude
## exactly, at the start of the event, and env(1) = 0 with decay 3 the event is below 5 % of its peak at its end.
## Outside every event the offset is zero and the camera is untouched (shaken() returns the same transform).
##
## FOCUS (rack focus): keys {"t", "dist" (m)} or {"t", "part": joint}. Between two keys the focus distance is
##   - a rack: a smoothstep from the first key's distance to the second's (a "part" key's distance is live, from the
##     camera to the part at each frame, so a rack can start or end on a tracked part),
##   - both "part": the part is tracked (the distance is camera-to-part at every frame),
##   - before the first key and after the last: the nearest key's own distance.
## The distance is measured from the keyed camera (the lens, not the shake), in the hero's space (the same as the render
## space: the stage moves rigidly). The part's position is the joint's point at time t, posed on a scratch body
## (the same pattern as gait_band.gd and clips.gd), so it is the part the pose puts there, not a guess.
## LENS: the DOF is Godot's CameraAttributesPractical (main.gd: _shot_dof): sharp at the distance, blurred on both sides.
class_name ShotFx
extends RefCounted

const HZ_RATIOS := [1.0, 1.7, 2.6]          # the three components' frequency ratios (seed jitters them by +-5 %)
const DIST_MIN := 0.05                       # m: the focus never goes closer than this
const FSTOPS := [1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0, 22.0]   # the full-stop series (ISO 517); the shot's "fstop" is one of these or between
const F_MIN := 1.4
const F_MAX := 22.0
const F_DEFAULT := 2.8
const COC_MM := 0.024   # circle of confusion on the 36 mm sensor: d / 1500 (the usual 35 mm figure is d / 1500 to d / 1730, 0.02-0.03 mm)
const PRESET_IMPACT := {"dur": 0.6, "cm": Vector3(1.5, 2.0, 1.0), "deg": Vector3(1.0, 0.6, 1.5), "hz": 9.0, "decay": 3.0}

static var _scratch: Body
static var _scratch_prop := ""


## the Impact preset at time t0: a hit's jolt (about 2 cm and 1 deg on the camera, 0.6 s)
static func impact(t0: float, seed_n := 1) -> Dictionary:
	return {"t": t0, "dur": PRESET_IMPACT["dur"], "cm": PRESET_IMPACT["cm"], "deg": PRESET_IMPACT["deg"],
		"hz": PRESET_IMPACT["hz"], "decay": PRESET_IMPACT["decay"], "seed": seed_n, "name": "Impact"}


## THE LENS'S DEPTH OF FIELD (thin lens, Kingslake / Ray "Applied Photographic Optics"): focal length f (mm), f-number N,
## focus distance S (m). Hyperfocal H = f^2 / (N c) + f; the sharp zone runs from near = S (H - f) / (H + S - 2 f) to
## far = S (H - f) / (H - S) (infinite from S >= H). Beyond it the blur circle grows to at most  c_inf = f^2 / (N (S - f))
## (the disc a point at infinity makes), here as a share of the frame's height. Returns what Godot's CameraAttributesPractical
## needs: "near", "far" (m, where blur begins), "near_tr", "far_tr" (m, the ramp to full blur), "amount" (blur strength), "coc" (share of frame height at infinity)
static func dof(f_mm: float, fstop: float, focus_m: float) -> Dictionary:
	var f := f_mm
	var n := clampf(fstop, F_MIN, F_MAX)
	var s_mm := maxf(focus_m * 1000.0, f * 1.05)
	var h := f * f / (n * COC_MM) + f
	var near_mm := s_mm * (h - f) / (h + s_mm - 2.0 * f)
	var far_mm := 1.0e9 if s_mm >= h else s_mm * (h - f) / (h - s_mm)
	var coc := f * f / (n * (s_mm - f)) / ShotCam.sensor_h()
	return {"near": near_mm / 1000.0, "far": minf(far_mm / 1000.0, 1000.0), "near_tr": clampf(focus_m * 0.3, 0.1, 5.0),
		"far_tr": clampf(focus_m * 0.3, 0.1, 5.0), "amount": clampf(coc * 6.0, 0.0, 0.6), "coc": coc}


## the shot's f-number (F_DEFAULT when none is set)
static func fstop_of(fx: Dictionary) -> float:
	return clampf(float(fx.get("fstop", F_DEFAULT)), F_MIN, F_MAX)


## the list inside fx ("shake" or "focus"), made if absent (fx is a Dictionary, so the caller's copy shares it)
static func list(fx: Dictionary, kind: String) -> Array:
	if not fx.has(kind):
		fx[kind] = []
	return fx[kind]


## the seeded draw in [0, 1) (integer hash, the same on every machine)
static func _h01(n: int) -> float:
	var x := (n * 2654435761) & 0x7fffffff
	x = (x ^ (x >> 13)) * 1274126177 & 0x7fffffff
	return float((x ^ (x >> 16)) & 0xffff) / 65536.0


## the component weights (sum 1) and frequencies (Hz) of one channel c (0..5) of an event
static func _comp(e: Dictionary, c: int) -> Array:
	var w := []
	var sum := 0.0
	var sd := int(e.get("seed", 1))
	for k in 3:
		var v := 0.3 + 0.7 * _h01(sd * 97 + c * 13 + k * 5 + 1)
		w.append(v)
		sum += v
	var out := []
	for k in 3:
		var jit := 1.0 + 0.1 * (_h01(sd * 131 + c * 17 + k * 7 + 3) - 0.5)
		out.append([float(w[k]) / sum, float(e.get("hz", 9.0)) * HZ_RATIOS[k] * jit])
	return out


## one channel's offset at s seconds into the event (channels 0-2: metres, 3-5: radians)
static func _chan(e: Dictionary, c: int, s: float) -> float:
	var dur := maxf(float(e.get("dur", 0.6)), 0.001)
	var u := s / dur
	var env := exp(-float(e.get("decay", 3.0)) * u) * (1.0 - u)
	var S := 0.0
	for p in _comp(e, c):
		S += float(p[0]) * cos(TAU * float(p[1]) * s)
	var amp: float
	if c < 3:
		amp = (e["cm"] as Vector3)[c] / 100.0
	else:
		amp = deg_to_rad((e["deg"] as Vector3)[c - 3])
	return amp * S * env


## the shake at time t: {"pos": Vector3 (m, camera axes), "rot": Vector3 (rad, pitch yaw roll)} summed over the events
## active at t; {} = none active (the camera is then exactly as it is)
static func shake_at(shakes: Array, t: float) -> Dictionary:
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	var any := false
	for e in shakes:
		var s := t - float(e["t"])
		if s < 0.0 or s >= float(e["dur"]):
			continue
		any = true
		for c in 3:
			pos[c] += _chan(e, c, s)
		for c in 3:
			rot[c] += _chan(e, c + 3, s)
	return {} if not any else {"pos": pos, "rot": rot}


## the camera transform with the shake at t applied in the camera's own axes; xf unchanged when no event is active
static func shaken(xf: Transform3D, shakes: Array, t: float) -> Transform3D:
	var off := shake_at(shakes, t)
	if off.is_empty():
		return xf
	return xf * Transform3D(Basis.from_euler(off["rot"]), off["pos"])


## the joint's point at time t in the hero's space: the scene posed at t on a scratch body (the trail's point: the
## joint's end, the pelvis' centre). NAN when the joint does not exist.
static func part_at(S: Scene, joint: String, t: float) -> Vector3:
	var prop := JSON.stringify(S.body)
	if _scratch == null:
		_scratch = Body.new()
		_scratch.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	if prop != _scratch_prop:
		_scratch.set_proportions(S.body)
		_scratch_prop = prop
	S.apply(_scratch, t)
	if not _scratch.E.has(joint) and joint != "pelvis":
		return Vector3(NAN, NAN, NAN)
	return _scratch.P[joint] if joint == "pelvis" else _scratch.E[joint]


## the focus distance at time t (m). cam_at(t) -> the keyed camera's position, part_at(joint, t) -> the joint's point
## (both in the hero's space). NAN when there are no keys.
static func focus_at(keys: Array, t: float, cam_at: Callable, part_at_fn: Callable) -> float:
	if keys.is_empty():
		return NAN
	var first: Dictionary = keys[0]
	if t <= float(first["t"]):
		return _dist(first, t, cam_at, part_at_fn)   # a part key tracks its part before and after its own time too
	var last: Dictionary = keys[-1]
	if t >= float(last["t"]):
		return _dist(last, t, cam_at, part_at_fn)
	var p: Dictionary = first
	var n: Dictionary = last
	for i in range(keys.size() - 1):
		if t >= float(keys[i]["t"]) and t < float(keys[i + 1]["t"]):
			p = keys[i]
			n = keys[i + 1]
			break
	var tp: float = p["t"]
	var tn: float = n["t"]
	if p.has("part") and n.has("part"):
		return _dist(p, t, cam_at, part_at_fn)   # tracking a part between two part keys
	var a := _dist(p, t, cam_at, part_at_fn)
	var b := _dist(n, tn, cam_at, part_at_fn)
	var u := clampf((t - tp) / maxf(tn - tp, 1e-6), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)   # smoothstep: the rack eases in and out
	return lerpf(a, b, u)


static func _dist(k: Dictionary, t: float, cam_at: Callable, part_at_fn: Callable) -> float:
	if k.has("part"):
		var q: Vector3 = part_at_fn.call(String(k["part"]), t)
		if is_nan(q.x):
			return NAN
		return maxf(DIST_MIN, cam_at.call(t).distance_to(q))
	return maxf(DIST_MIN, float(k["dist"]))


## the keys and shakes as the file holds them (the shot's "fx" in the scene file; only when either is not empty)
static func clean(fx: Dictionary) -> Dictionary:
	var out := {}
	if not (fx.get("shake", []) as Array).is_empty():
		out["shake"] = fx["shake"]
	if not (fx.get("focus", []) as Array).is_empty():
		out["focus"] = fx["focus"]
	if fx.has("fstop"):
		out["fstop"] = fx["fstop"]
	return out


static func to_file(fx: Dictionary) -> Dictionary:
	var out := {}
	var sh := []
	for e in fx.get("shake", []):
		var cm: Vector3 = e["cm"]
		var dg: Vector3 = e["deg"]
		sh.append({"t": snappedf(float(e["t"]), 0.0001), "dur": snappedf(float(e["dur"]), 0.0001),
			"cm": [snappedf(cm.x, 0.0001), snappedf(cm.y, 0.0001), snappedf(cm.z, 0.0001)],
			"deg": [snappedf(dg.x, 0.0001), snappedf(dg.y, 0.0001), snappedf(dg.z, 0.0001)],
			"hz": snappedf(float(e["hz"]), 0.001), "decay": snappedf(float(e["decay"]), 0.001),
			"seed": int(e["seed"]), "name": String(e.get("name", "Shake"))})
	if not sh.is_empty():
		out["shake"] = sh
	var fo := []
	for k in fx.get("focus", []):
		if k.has("part"):
			fo.append({"t": snappedf(float(k["t"]), 0.0001), "part": String(k["part"])})
		else:
			fo.append({"t": snappedf(float(k["t"]), 0.0001), "dist": snappedf(float(k["dist"]), 0.0001)})
	if not fo.is_empty():
		out["focus"] = fo
	if fx.has("fstop"):
		out["fstop"] = snappedf(clampf(float(fx["fstop"]), F_MIN, F_MAX), 0.01)
	return out


static func _v3(a: Variant) -> Vector3:
	var v: Array = a if a is Array else [0, 0, 0]
	return Vector3(float(v[0]), float(v[1]), float(v[2]))


static func from_file(d: Variant) -> Dictionary:
	var out := {"shake": [], "focus": []}
	if not d is Dictionary:
		return out
	for e in d.get("shake", []):
		if not e is Dictionary or not e.has("cm") or not e.has("deg"):
			continue
		out["shake"].append({"t": maxf(0.0, float(e.get("t", 0.0))), "dur": maxf(0.001, float(e.get("dur", 0.6))),
			"cm": _v3(e["cm"]), "deg": _v3(e["deg"]), "hz": maxf(0.1, float(e.get("hz", 9.0))),
			"decay": maxf(0.0, float(e.get("decay", 3.0))), "seed": int(e.get("seed", 1)), "name": String(e.get("name", "Shake"))})
	for k in d.get("focus", []):
		if not k is Dictionary or not k.has("t"):
			continue
		if k.has("part"):
			out["focus"].append({"t": maxf(0.0, float(k["t"])), "part": String(k["part"])})
		elif k.has("dist"):
			out["focus"].append({"t": maxf(0.0, float(k["t"])), "dist": maxf(DIST_MIN, float(k["dist"]))})
	if d.has("fstop"):
		out["fstop"] = clampf(float(d["fstop"]), F_MIN, F_MAX)
	out["shake"].sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
	out["focus"].sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
	return out


## MIRROR (ShotCam.mirror_shots_file, each shot's "fx" on the file form): the body mirrors across x = 0, so the shake's sideways
## offset (x), yaw and roll flip, and a part key moves to its twin (Body.twin: _l <-> _r). Times, sizes and seeds stay.
static func mirror_file(d: Dictionary) -> Dictionary:
	var out := {}
	if d.has("shake"):
		out["shake"] = (d["shake"] as Array).map(func(e):
			var cm: Array = e["cm"]
			var dg: Array = e["deg"]
			var n: Dictionary = e.duplicate(true)
			n["cm"] = [-float(cm[0]), cm[1], cm[2]]
			n["deg"] = [dg[0], -float(dg[1]), -float(dg[2])]
			return n)
	if d.has("focus"):
		out["focus"] = (d["focus"] as Array).map(func(k):
			var n: Dictionary = k.duplicate(true)
			if n.has("part"):
				n["part"] = Body.twin(String(n["part"]))
			return n)
	if d.has("fstop"):
		out["fstop"] = d["fstop"]
	return out
