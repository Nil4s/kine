## blend_matrix.gd - BLEND MATRIX (docs/INNOVATIONS.md N084). For a moveset of N clips, every clip-to-clip crossfade (the end of A into the start of B over the
## blend time) is checked at its blend time for limit breaks, self-clash and foot skate, with the pose distance at the seam; an NxN matrix of cells with a verdict
## each, and a ranked list of the bad pairs. Read only: no scene, pose or file is written.
##
## THE BLEND (tests/n084_test.gd states the same and recomputes it with Body directly):
##   dt = 1/60 s, m = max(2, round(blend_s x 60)) steps, T = m dt, LA = (nA-1)/fpsA, LB = (nB-1)/fpsB, t0A = max(LA - T, 0).
##   sample k = 0..m: tA = min(t0A + k dt, LA), tB = min(k dt, LB), w = smoothstep(k / m). A and B are read at those times (the two nearest frames, linearly; the
##   pelvis twist by the shorter way round); the joint angles are a + (b - a) w, UNCLAMPED (the engine clamps afterwards: this reports what it would have to clamp);
##   the hips are lerp(offsetA(tA), offsetB'(tB), w), B moved on the floor so its hips at t = 0 sit at A's hips at t0A (x, z); the height is each clip's own.
## METRICS per cell (units in the names):
##   limit_deg  the most any joint axis (bend / side / twist) is past its range in data/body_limits.json over the m + 1 samples, with the joint and the axis
##   clash_mm   the deepest capsule pair past its allowance by more than 1 mm (Body.pairs, the touching-parts test; weapons and skin points are left out)
##   skate_mm   a foot planted at the start of the blend (sole under MocapMetrics.SOLE_H, ball under SOLE_V in A's own motion) slides over the floor while it stays
##              down; the same backwards from the end (planted in B); planted at BOTH ends: the distance between the two ends' ball positions
##   seam       PoseMatch's distance between A's last pose and B's first: mass-weighted mean joint difference (deg) + 100 deg per metre of hips height
## BARS: limit 1 deg, clash 10 mm, skate 25 mm = bad; half a bar, or a seam over 25 = warn; else ok. score = the worst of the three over its bar (+ a tenth of the seam's).
## HEAVY LOOP: scripts/blend_matrix.gd _cells_gd is the GDScript twin; native/src/kine_blend_native.cpp is the same arithmetic in C++ (KineBlendNative.matrix).
## The twin is used when the native class is not there. tests/n084_test.gd bars the two against each other and against its own recompute (0.1 mm / 0.1 deg).
class_name BlendMatrix
extends RefCounted

const DT := 1.0 / 60.0
const BAR_LIMIT_DEG := 1.0
const BAR_CLASH_MM := 10.0
const BAR_SKATE_MM := 25.0
const BAR_SEAM := 25.0
const CLASH_MIN := 0.001   # m: Body's "touching" threshold
const AXES := ["bend", "side", "twist"]

static var _rig_cache: Dictionary = {}


static func native_ok() -> bool:
	return NativeExt.ensure("kine_native", "KineBlendNative")


static func bars() -> Dictionary:
	return {"limit_deg": BAR_LIMIT_DEG, "clash_mm": BAR_CLASH_MM, "skate_mm": BAR_SKATE_MM, "seam": BAR_SEAM}


static func new_body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


# ------------------------------------------------------------------ clips

## a clip from per-frame joint dictionaries (missing joints rest) and hips offsets: {name, fps, n, ang (n x J), off (n)}
static func make_clip(cname: String, fps: float, angs: Array, offs: Array) -> Dictionary:
	var ang := PackedVector3Array()
	for a in angs:
		for j in Body.ORDER:
			ang.append((a as Dictionary).get(j, Vector3.ZERO))
	var off := PackedVector3Array()
	for o in offs:
		off.append(o)
	while off.size() < angs.size():
		off.append(Vector3.ZERO)
	return {"name": cname, "fps": fps, "n": angs.size(), "ang": ang, "off": off}


## a scene played through Scene.apply at fps (the clip as it plays: cards, plants and all)
static func clip_of_scene(S: Scene, B: Body, cname: String, fps := 30.0) -> Dictionary:
	var L := S.length()
	var n := int(floorf(L * fps)) + 1
	var angs := []
	var offs := []
	var keep := B.state()
	for f in n:
		S.apply(B, minf(float(f) / fps, L))
		B.fk()
		angs.append(B.ang.duplicate())
		offs.append(B.offset)
	B.set_state(keep)
	return make_clip(cname, fps, angs, offs)


## the scene files of these folders with some motion in them, as clips (names = file names without .json); `only` = the names wanted ([] = all)
static func clips_of_dirs(dirs: Array, only := []) -> Array:
	var B := new_body()
	var out := []
	for dir in dirs:
		for fn in DirAccess.get_files_at(dir):
			if not fn.ends_with(".json"):
				continue
			var nm := fn.get_basename()
			if not only.is_empty() and not (nm in only):
				continue
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + fn))
			if not (d is Dictionary) or (d.get("cards", []) as Array).size() < 2:
				continue
			var S := Scene.new()
			S.from_dict(d)
			if S.length() <= 0.0:
				continue
			out.append(clip_of_scene(S, B, nm))
	return out


static func clips_of_files(paths: Array) -> Array:
	var B := new_body()
	var out := []
	for p in paths:
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(p)))
		if not (d is Dictionary):
			continue
		var S := Scene.new()
		S.from_dict(d)
		out.append(clip_of_scene(S, B, String(p).get_file().get_basename()))
	return out


# ------------------------------------------------------------------ the rig for the native twin

static func rig(B: Body) -> Dictionary:
	var J: int = Body.ORDER.size()
	var idx := {}
	for i in J:
		idx[Body.ORDER[i]] = i
	var par := PackedInt32Array()
	var p0 := PackedFloat64Array()
	var e0 := PackedFloat64Array()
	var bax := PackedFloat64Array()
	var aax := PackedFloat64Array()
	var wax := PackedFloat64Array()
	var lim := PackedFloat64Array()
	var st := PackedFloat64Array()
	var mass := PackedFloat64Array()
	for j in Body.ORDER:
		par.append(int(idx.get(B.parent[j], -1)))
		_push3(p0, B.p0[j])
		_push3(e0, B.e0[j])
		_push3(bax, B.b_ax[j])
		_push3(aax, B.a_ax[j])
		_push3(wax, B.w_ax[j])
		st.append(float(B.stretch.get(j, 1.0)) if B._has_stretch else 1.0)
		for ax in AXES:
			var r: Vector2 = B.lim[j][ax]
			lim.append(r.x)
			lim.append(r.y)
		mass.append(PoseMatch.weight(j))
	return {"J": J, "parent": par, "p0": p0, "e0": e0, "bax": bax, "aax": aax, "wax": wax, "lim": lim, "stretch": st, "mass": mass}


static func _push3(arr: PackedFloat64Array, v: Vector3) -> void:
	arr.append(v.x)
	arr.append(v.y)
	arr.append(v.z)


## the capsule pairs as tables (parts: joint, rest end points, radius; pairs: two part indices and the allowance)
static func caps(B: Body) -> Dictionary:
	var idx := {}
	for i in Body.ORDER.size():
		idx[Body.ORDER[i]] = i
	var pnames := []
	var pidx := {}
	var pj := PackedInt32Array()
	var c0 := PackedFloat64Array()
	var c1 := PackedFloat64Array()
	var rj := PackedFloat64Array()
	var rad := PackedFloat64Array()
	var pr := PackedInt32Array()
	var al := PackedFloat64Array()
	for p in B.pairs:
		var x: String = p[0]
		var y: String = p[1]
		if x in Body.WEAPON or y in Body.WEAPON or x in Body.WEAPON2 or y in Body.WEAPON2:
			continue
		for nm in [x, y]:
			if pidx.has(nm):
				continue
			pidx[nm] = pnames.size()
			pnames.append(nm)
			var jn: String = Body.WIDE[nm][0] if Body.WIDE.has(nm) else nm
			var c: Array = B.cap0[nm]
			pj.append(int(idx[jn]))
			_push3(c0, c[0])
			_push3(c1, c[1])
			_push3(rj, B.p0[jn])
			rad.append(float(B.rad[nm]))
		pr.append(int(pidx[x]))
		pr.append(int(pidx[y]))
		al.append(float(B.allow.get(x + "|" + y, 0.0)))
	var fi := PackedInt32Array([int(idx["foot_l"]), int(idx["ball_l"]), int(idx["foot_r"]), int(idx["ball_r"])])
	var rest := PackedFloat64Array()
	for sd in ["_l", "_r"]:
		rest.append((B.p0["foot" + sd] as Vector3).y)
		rest.append((B.p0["ball" + sd] as Vector3).y)
		rest.append((B.e0["ball" + sd] as Vector3).y)
	return {"names": pnames, "joint": pj, "c0": c0, "c1": c1, "rj": rj, "rad": rad, "pairs": pr, "allow": al, "feet": fi, "rest": rest}


static func _rig_for(B: Body) -> Dictionary:
	var key := str(B.p0.hash()) + str(B.pairs.size()) + str(B._has_stretch)
	if _rig_cache.has(key):
		return _rig_cache[key]
	var r := rig(B)
	r["caps"] = caps(B)
	_rig_cache.clear()
	_rig_cache[key] = r
	return r


# ------------------------------------------------------------------ the blend

static func plan(ca: Dictionary, cb: Dictionary, blend_s: float) -> Dictionary:
	var m := maxi(2, int(round(blend_s * 60.0)))
	var T := float(m) * DT
	var LA := float(int(ca["n"]) - 1) / float(ca["fps"])
	var LB := float(int(cb["n"]) - 1) / float(cb["fps"])
	var t0A := maxf(LA - T, 0.0)
	var oa := sample(ca, t0A)["off"] as Vector3
	var ob := sample(cb, 0.0)["off"] as Vector3
	return {"m": m, "T": T, "LA": LA, "LB": LB, "t0A": t0A, "shift": Vector2(oa.x - ob.x, oa.z - ob.z)}


## a clip at time t: {"ang": joint -> Vector3, "off": Vector3}
static func sample(c: Dictionary, t: float) -> Dictionary:
	var n: int = c["n"]
	var f := clampf(t * float(c["fps"]), 0.0, float(n - 1))
	var i0 := int(floor(f))
	var i1 := mini(i0 + 1, n - 1)
	var u := f - float(i0)
	var J: int = Body.ORDER.size()
	var A: PackedVector3Array = c["ang"]
	var a := {}
	for ji in J:
		var j: String = Body.ORDER[ji]
		var va: Vector3 = A[i0 * J + ji]
		var vb: Vector3 = A[i1 * J + ji]
		a[j] = va + Scene._d(va, vb, j) * u
	var O: PackedVector3Array = c["off"]
	var oa: Vector3 = O[i0]
	var ob: Vector3 = O[i1]
	return {"ang": a, "off": oa + (ob - oa) * u}


## the blended pose of step k: {"ang", "offset", "w"}
static func pose_at(ca: Dictionary, cb: Dictionary, P: Dictionary, k: int) -> Dictionary:
	var m: int = P["m"]
	var tA := minf(float(P["t0A"]) + float(k) * DT, float(P["LA"]))
	var tB := minf(float(k) * DT, float(P["LB"]))
	var w := smoothstep(0.0, 1.0, float(k) / float(m))
	var sa := sample(ca, tA)
	var sb := sample(cb, tB)
	var ang := {}
	for j in Body.ORDER:
		var va: Vector3 = sa["ang"][j]
		var vb: Vector3 = sb["ang"][j]
		var r := va + Scene._d(va, vb, j) * w
		if j == "pelvis":
			r.z = wrapf(r.z, -180.0, 180.0)
		ang[j] = r
	var oa: Vector3 = sa["off"]
	var ob: Vector3 = sb["off"]
	var sh: Vector2 = P["shift"]
	var obx := Vector3(ob.x + sh.x, ob.y, ob.z + sh.y)
	return {"ang": ang, "offset": oa.lerp(obx, w), "w": w}


## the blend as poses, for the preview: [{"ang", "offset", "w"}] (m + 1 of them)
static func frames(ca: Dictionary, cb: Dictionary, blend_s: float) -> Array:
	var P := plan(ca, cb, blend_s)
	var out := []
	for k in int(P["m"]) + 1:
		out.append(pose_at(ca, cb, P, k))
	return out


# ------------------------------------------------------------------ the GDScript twin

static func _put(b: Body, ang: Dictionary, off: Vector3) -> void:
	for j in Body.ORDER:
		b.ang[j] = ang[j]
	b.offset = off
	b.fk()


static func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _speeds(b: Body, c: Dictionary, t: float, t2: float, shift: Vector2) -> Array:
	var pos := []
	for tt in [t, t2]:
		var s := sample(c, tt)
		var o: Vector3 = s["off"]
		_put(b, s["ang"], Vector3(o.x + shift.x, o.y, o.z + shift.y))
		pos.append([_xz(b.P["ball_l"]), _xz(b.P["ball_r"])])
	var moved := absf(t - t2) > 1e-9
	return [(pos[0][0] as Vector2).distance_to(pos[1][0]) / DT if moved else 0.0, (pos[0][1] as Vector2).distance_to(pos[1][1]) / DT if moved else 0.0]


## one cell by the Body's own FK (the twin of the native cell)
static func _cell_gd(b: Body, ca: Dictionary, cb: Dictionary, blend_s: float) -> Dictionary:
	var P := plan(ca, cb, blend_s)
	var m: int = P["m"]
	var lim_x := 0.0
	var lim_j := ""
	var lim_ax := ""
	var clash := 0.0
	var cl_a := ""
	var cl_b := ""
	var low := [[], []]
	var ball := [[], []]
	var prs := []
	for pr in b.pairs:
		if pr[0] in Body.WEAPON or pr[1] in Body.WEAPON or pr[0] in Body.WEAPON2 or pr[1] in Body.WEAPON2:
			continue
		prs.append([pr[0], pr[1], float(b.allow.get(pr[0] + "|" + pr[1], 0.0))])
	for k in m + 1:
		var ps := pose_at(ca, cb, P, k)
		_put(b, ps["ang"], ps["offset"])
		for j in Body.ORDER:
			var v: Vector3 = ps["ang"][j]
			for ai in 3:
				var rg: Vector2 = b.lim[j][AXES[ai]]
				var x := maxf(maxf(rg.x - v[ai], v[ai] - rg.y), 0.0)
				if x > lim_x:
					lim_x = x
					lim_j = j
					lim_ax = AXES[ai]
		for pr in prs:
			var d: float = b.depth(pr[0], pr[1]) - float(pr[2])
			if d > CLASH_MIN and d > clash:
				clash = d
				cl_a = pr[0]
				cl_b = pr[1]
		for s in 2:
			var sd: String = "_l" if s == 0 else "_r"
			(low[s] as Array).append(b.foot_sole_low(sd))
			(ball[s] as Array).append(_xz(b.P["ball" + sd]))
	var tA0: float = P["t0A"]
	var LA: float = P["LA"]
	var LB: float = P["LB"]
	var tAo := tA0 + DT if tA0 + DT <= LA else tA0 - DT
	var tBm := minf(float(P["T"]), LB)
	var tBo := tBm + DT if tBm + DT <= LB else tBm - DT
	var spa := _speeds(b, ca, tA0, tAo, Vector2.ZERO)
	var spb := _speeds(b, cb, tBm, tBo, P["shift"])
	var skate := 0.0
	var sk_foot := ""
	for s in 2:
		var lw: Array = low[s]
		var bl: Array = ball[s]
		var sp: bool = float(spa[s]) < MocapMetrics.SOLE_V and float(lw[0]) < MocapMetrics.SOLE_H
		var ep: bool = float(spb[s]) < MocapMetrics.SOLE_V and float(lw[m]) < MocapMetrics.SOLE_H
		var sl := 0.0
		if sp:
			for k in range(1, m + 1):
				if float(lw[k]) >= MocapMetrics.SOLE_H:
					break
				sl = maxf(sl, (bl[k] as Vector2).distance_to(bl[0]))
		if ep:
			for k in range(m - 1, -1, -1):
				if float(lw[k]) >= MocapMetrics.SOLE_H:
					break
				sl = maxf(sl, (bl[k] as Vector2).distance_to(bl[m]))
		if sp and ep:
			sl = maxf(sl, (bl[m] as Vector2).distance_to(bl[0]))
		if sl > skate:
			skate = sl
			sk_foot = "foot_l" if s == 0 else "foot_r"
	var qa := sample(ca, float(P["LA"]))
	var qb := sample(cb, 0.0)
	var tot := 0.0
	var sm := 0.0
	for j in Body.ORDER:
		var d3: Vector3 = Scene._d(qa["ang"][j], qb["ang"][j], j)
		if j == "pelvis":
			d3.z = 0.0
		var mm := PoseMatch.weight(j)
		sm += mm * d3.length()
		tot += mm
	var seam := sm / tot + PoseMatch.HEIGHT_W * absf((qb["off"] as Vector3).y - (qa["off"] as Vector3).y)
	return {"limit_deg": lim_x, "limit_joint": lim_j, "limit_axis": lim_ax, "clash_mm": clash * 1000.0, "clash_a": cl_a, "clash_b": cl_b,
		"skate_mm": skate * 1000.0, "skate_foot": sk_foot, "seam": seam}


static func _cells_gd(clips: Array, blend_s: float) -> Array:
	var b := new_body()
	var n := clips.size()
	var out := []
	for i in n:
		var row := []
		for j in n:
			row.append(_cell_gd(b, clips[i], clips[j], blend_s))
		out.append(row)
	return out


static func _cells_native(clips: Array, blend_s: float) -> Array:
	var b := new_body()
	var R := _rig_for(b)
	var cc: Dictionary = R["caps"]
	var raw: Array = (load("res://scripts/blend_native.gd") as GDScript).call("run", R, cc, clips, blend_s)
	var pn: Array = cc["names"]
	var n := clips.size()
	var out := []
	for i in n:
		var row := []
		for j in n:
			var r: Dictionary = raw[i * n + j]
			var ji := int(r["limit_j"])
			var pi := int(r["clash_p"])
			row.append({"limit_deg": float(r["limit_deg"]), "limit_joint": Body.ORDER[ji] if ji >= 0 else "", "limit_axis": AXES[int(r["limit_ax"])] if ji >= 0 else "",
				"clash_mm": float(r["clash_mm"]), "clash_a": pn[int((cc["pairs"] as PackedInt32Array)[2 * pi])] if pi >= 0 else "",
				"clash_b": pn[int((cc["pairs"] as PackedInt32Array)[2 * pi + 1])] if pi >= 0 else "",
				"skate_mm": float(r["skate_mm"]), "skate_foot": ["", "foot_l", "foot_r"][int(r["skate_foot"])], "seam": float(r["seam"])})
		out.append(row)
	return out


# ------------------------------------------------------------------ verdicts and the matrix

static func judge(c: Dictionary) -> void:
	var lr := float(c["limit_deg"]) / BAR_LIMIT_DEG
	var cr := float(c["clash_mm"]) / BAR_CLASH_MM
	var sr := float(c["skate_mm"]) / BAR_SKATE_MM
	var worst := maxf(lr, maxf(cr, sr))
	var why := PackedStringArray()
	if sr > 1.0:
		why.append("skate %.0f mm (%s)" % [c["skate_mm"], c["skate_foot"]])
	if lr > 1.0:
		why.append("limit %.1f deg past %s %s" % [c["limit_deg"], c["limit_joint"], c["limit_axis"]])
	if cr > 1.0:
		why.append("clash %.0f mm (%s into %s)" % [c["clash_mm"], c["clash_a"], c["clash_b"]])
	var verdict := "ok"
	if worst > 1.0:
		verdict = "bad"
	elif worst > 0.5 or float(c["seam"]) > BAR_SEAM:
		verdict = "warn"
		if worst > 0.5:
			if sr > 0.5:
				why.append("skate %.0f mm" % c["skate_mm"])
			if lr > 0.5:
				why.append("limit %.1f deg" % c["limit_deg"])
			if cr > 0.5:
				why.append("clash %.0f mm" % c["clash_mm"])
		if float(c["seam"]) > BAR_SEAM:
			why.append("seam %.0f deg apart" % c["seam"])
	c["verdict"] = verdict
	c["why"] = ", ".join(why) if not why.is_empty() else "clean"
	c["score"] = worst + 0.1 * float(c["seam"]) / BAR_SEAM


## the matrix of a moveset: {ok, names, n, blend_s, engine, ms, bars, cells [[cell]], bad [ranked], warn}. o: {"native": bool}
static func matrix(clips: Array, blend_s := 0.2, o := {}) -> Dictionary:
	if clips.is_empty():
		return {"ok": false, "error": "no clips: a blend matrix needs a moveset of 1 or more"}
	var want_native: bool = bool(o.get("native", true)) and native_ok()
	var t0 := Time.get_ticks_usec()
	var cells: Array = _cells_native(clips, blend_s) if want_native else _cells_gd(clips, blend_s)
	var names := []
	for c in clips:
		names.append(String(c["name"]))
	var bad := []
	var warn := 0
	for i in clips.size():
		for j in clips.size():
			var c: Dictionary = cells[i][j]
			c["a"] = names[i]
			c["b"] = names[j]
			c["i"] = i
			c["j"] = j
			judge(c)
			if c["verdict"] == "bad":
				bad.append({"a": names[i], "b": names[j], "i": i, "j": j, "score": c["score"], "why": c["why"], "verdict": "bad", "limit_deg": c["limit_deg"], "limit_joint": c["limit_joint"],
					"limit_axis": c["limit_axis"], "clash_mm": c["clash_mm"], "skate_mm": c["skate_mm"], "seam": c["seam"]})
			elif c["verdict"] == "warn":
				warn += 1
	bad.sort_custom(func(x, y): return float(x["score"]) > float(y["score"]) or (float(x["score"]) == float(y["score"]) and (int(x["i"]) < int(y["i"]) or (int(x["i"]) == int(y["i"]) and int(x["j"]) < int(y["j"])))))
	return {"ok": true, "names": names, "n": clips.size(), "blend_s": blend_s, "blend_frames": maxi(2, int(round(blend_s * 60.0))),
		"engine": "native" if want_native else "gd", "ms": float(Time.get_ticks_usec() - t0) / 1000.0, "bars": bars(), "cells": cells, "bad": bad, "warn": warn}


static func to_json(M: Dictionary) -> String:
	return JSON.stringify(M)


static func from_json(s: String) -> Dictionary:
	var d: Variant = JSON.parse_string(s)
	if not (d is Dictionary):
		return {}
	var M: Dictionary = d
	M["n"] = int(M.get("n", 0))
	M["warn"] = int(M.get("warn", 0))
	M["blend_frames"] = int(M.get("blend_frames", 0))
	for row in M.get("cells", []):
		for c in row:
			c["i"] = int(c["i"])
			c["j"] = int(c["j"])
	for e in M.get("bad", []):
		e["i"] = int(e["i"])
		e["j"] = int(e["j"])
	return M


## "a -> b: why" lines for the worst pairs
static func words(M: Dictionary, top := 10) -> String:
	if not bool(M.get("ok", false)):
		return String(M.get("error", "blend matrix: nothing to show"))
	var bad: Array = M["bad"]
	var lines := PackedStringArray()
	lines.append("BLEND MATRIX: %d clips, %d crossfades at %.2f s: %d bad, %d to watch (%s, %.0f ms)" % [M["n"], int(M["n"]) * int(M["n"]), M["blend_s"], bad.size(), M["warn"], M["engine"], M["ms"]])
	for e in bad.slice(0, top):
		lines.append("  %s -> %s: %s" % [e["a"], e["b"], e["why"]])
	if bad.size() > top:
		lines.append("  ... and %d more" % (bad.size() - top))
	return "\n".join(lines)
