## cancel_windows.gd - CANCEL WINDOWS FROM THE BODY (INNOVATIONS N081). The frames where the body is balanced and slow enough to start another move.
## A frame is CANCELABLE when all three hold:
##   1. balanced: Balance.read margin >= MARGIN_MIN (the COM's floor point inside the feet's support);
##   2. slow: |COM velocity| <= V_MAX and whole-body angular momentum about the COM (per unit mass) <= H_MAX;
##   3. no foot mid-swing: neither foot is off the floor (both are in Balance.read's "down" list, by Balance.footprint's own touch rule).
## A WINDOW is a maximal run of cancelable frames at least MIN_RUN long: {"f0", "f1"} (f1 one past the last frame, like FrameData.spans).
## Thresholds were registered in tests/n081_test.gd before any measuring (sources there). Angular momentum: sum m_i (r_i - c) x (v_i - vbar) over the
## 17 Balance.MASS parts at their capsule midpoints, masses as fractions of the body (de Leva 1996); each part's own spin is left out. Velocities are forward
## differences at fps (the last frame backward), as FrameData's tip speed is. The COM used for velocity is the same midpoint sum.
class_name CancelWindows
extends RefCounted

const V_MAX := 0.25         # m/s
const H_MAX := 0.045        # m^2/s per unit mass
const MARGIN_MIN := 0.0     # m
const MIN_RUN := 3          # frames
const COL_BAND := Color(0.05, 0.05, 0.07)   # the band on the frame-data strip (POL1106b: near-black, was teal 2fbf9b: 1.07:1 on the dark startup green)


## one frame's measurements of the body as posed now: {"margin", "com", "pos" (Array of Vector3, Balance.MASS order), "swing" (a foot is off the floor)}
static func measure(B: Body) -> Dictionary:
	var pos := []
	var com := Vector3.ZERO
	var w := 0.0
	for j in Balance.MASS:
		var c: Array = B.cap(j)
		var mid: Vector3 = ((c[0] as Vector3) + (c[1] as Vector3)) * 0.5
		var m: float = Balance.MASS[j]
		pos.append(mid)
		com += mid * m
		w += m
	var r := Balance.read(B)
	return {"margin": float(r["margin"]), "com": com / w, "pos": pos, "swing": (r["down"] as Array).size() < 2}


## {x: |COM velocity| m/s, y: angular momentum m^2/s per unit mass} between two measurements one frame apart
static func motion(a: Dictionary, b: Dictionary, fps: int) -> Vector2:
	var vc := ((b["com"] as Vector3) - (a["com"] as Vector3)) * float(fps)
	var vbar := Vector3.ZERO
	var w := 0.0
	var vel := []
	var i := 0
	for j in Balance.MASS:
		var m: float = Balance.MASS[j]
		var v: Vector3 = ((b["pos"][i] as Vector3) - (a["pos"][i] as Vector3)) * float(fps)
		vel.append(v)
		vbar += v * m
		w += m
		i += 1
	vbar /= w
	var h := Vector3.ZERO
	i = 0
	for j in Balance.MASS:
		h += ((a["pos"][i] as Vector3) - (a["com"] as Vector3)).cross((vel[i] as Vector3) - vbar) * (float(Balance.MASS[j]) / w)
		i += 1
	return Vector2(vc.length(), h.length())


## maximal runs of true in flags, at least min_run long: [{"f0", "f1"}]
static func runs(flags: Array, min_run: int) -> Array:
	var out := []
	var i := 0
	var n := flags.size()
	while i < n:
		if flags[i]:
			var j := i
			while j < n and flags[j]:
				j += 1
			if j - i >= min_run:
				out.append({"f0": i, "f1": j})
			i = j
		else:
			i += 1
	return out


## th: {v_max, h_max, margin_min, min_run, feet (false = ignore the feet rule)}. Leaves B posed at the scene's last frame. {} for an empty scene.
static func analyze(S: Scene, B: Body, fps := FrameData.FPS, th := {}) -> Dictionary:
	var N := int(round(S.length() * float(fps)))
	if N < 1 or S.cards.is_empty():
		return {}
	var s := []
	for f in N:
		S.apply(B, float(f) / float(fps))
		s.append(measure(B))
	return of_samples(s, fps, th)


static func of_samples(s: Array, fps: int, th := {}) -> Dictionary:
	var vmax := float(th.get("v_max", V_MAX))
	var hmax := float(th.get("h_max", H_MAX))
	var mmin := float(th.get("margin_min", MARGIN_MIN))
	var mrun := int(th.get("min_run", MIN_RUN))
	var feet := bool(th.get("feet", true))
	var N := s.size()
	var frames := []
	var flags := []
	for f in N:
		var vh := Vector2.ZERO
		if N > 1:
			var a := f if f < N - 1 else f - 1
			vh = motion(s[a], s[a + 1], fps)
		var sw: bool = s[f]["swing"]
		var good: bool = float(s[f]["margin"]) >= mmin and vh.x <= vmax and vh.y <= hmax and not (feet and sw)
		flags.append(good)
		frames.append({"f": f, "margin": s[f]["margin"], "v": vh.x, "h": vh.y, "swing": sw, "ok": good})
	return {"fps": fps, "n": N, "thresholds": {"v_max": vmax, "h_max": hmax, "margin_min": mmin}, "min_run": mrun, "frames": frames, "windows": runs(flags, mrun)}


## the JSON-ready summary (no per-frame numbers): {fps, thresholds, min_run, windows: [{f0, f1}]}
static func to_json(c: Dictionary) -> Dictionary:
	if c.is_empty():
		return {"fps": 0, "thresholds": {}, "min_run": MIN_RUN, "windows": []}
	var t: Dictionary = c["thresholds"]
	var out := {"fps": c["fps"], "thresholds": {"v_max": t["v_max"], "h_max": t["h_max"], "margin_min": t["margin_min"]}, "min_run": c["min_run"], "windows": []}
	for w in c["windows"]:
		out["windows"].append({"f0": int(w["f0"]), "f1": int(w["f1"])})
	return out


## adds fd["cancel"] (to_json of the clip's windows at fd's fps) so the strip and FrameData.to_json carry it. No-op for empty frame data.
static func attach(fd: Dictionary, S: Scene, B: Body) -> void:
	if fd.is_empty() or S.cards.is_empty():
		return
	fd["cancel"] = to_json(analyze(S, B, int(fd["fps"])))


## "cancel windows: f 0-9, f 25-57" for words
static func words(c: Dictionary) -> String:
	var ws: Array = c.get("windows", [])
	if ws.is_empty():
		return "no cancel window: the body is never balanced and slow for %d frames in a row" % int(c.get("min_run", MIN_RUN))
	var parts := []
	for w in ws:
		parts.append("f %d-%d" % [int(w["f0"]), int(w["f1"]) - 1])
	return "cancel windows: " + ", ".join(parts)


## SERVE cancel_windows {clip?, frame?, fps?, v_max?, h_max?, margin_min?}: no clip = the live scene (not moved)
static func serve(m: Node, p: Dictionary) -> Dictionary:
	var fps := int(p.get("fps", FrameData.FPS))
	if fps < 1:
		return {"ok": false, "error": "fps must be a whole number of frames a second, e.g. 60"}
	var S: Scene = m.S
	if p.has("clip"):
		var path := AgentTools.res(String(p["clip"]))
		if not FileAccess.file_exists(path):
			return {"ok": false, "error": "cancel_windows: no such scene file '%s'" % p["clip"]}
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not d is Dictionary:
			return {"ok": false, "error": "cancel_windows: '%s' is not a scene file" % p["clip"]}
		S = Scene.new()
		S.from_dict(d)
	if S.cards.size() < 2:
		return {"ok": false, "error": "cancel_windows needs a scene of 2+ cards: open one or give {clip}"}
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	B.ground()
	var th := {}
	for k in ["v_max", "h_max", "margin_min", "min_run"]:
		if p.has(k):
			th[k] = p[k]
	var c := analyze(S, B, fps, th)
	var out := to_json(c)
	out["text"] = words(c)
	if p.has("frame"):
		var fr := int(p["frame"])
		var fl: Array = c["frames"]
		if fr < 0 or fr >= fl.size():
			out["at_frame"] = {"frame": fr, "state": "outside the clip"}
		else:
			var inw := false
			for w in c["windows"]:
				if fr >= int(w["f0"]) and fr < int(w["f1"]):
					inw = true
			out["at_frame"] = {"frame": fr, "cancelable": inw, "margin": fl[fr]["margin"], "v": fl[fr]["v"], "h": fl[fr]["h"], "foot_swinging": fl[fr]["swing"]}
	return {"ok": true, "result": out}
