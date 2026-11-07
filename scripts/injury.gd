## injury.gd - INJURY PROFILE (N036). A fighter's per-joint losses: {"calf_r": {"rom": 0.30, "strength": 0.40}} = the range of motion is 30 %
## smaller on every axis (both ends scaled about the rest angle 0) and the strength 40 % smaller. Names knee / shoulder / hip / elbow / ankle
## (+ _l / _r) are accepted for calf / upperarm / thigh / lowerarm / foot. The judges use the reduced values: INJURY ROM (the played motion
## goes past the reduced stop; healthy limits still play it, so the failing moves can be listed), and the JOINT TORQUE / JOINT SPEED bars
## scaled by (1 - strength) (HumanLimits). Saved in the scene file as "injury" only when any. Agent tool `injury` (MCP):
## {action: read | set (joint, rom?, strength?) | clear (joint?) | moves}; set and clear are ONE undo step each.
## apply(B, prof) / clear(B) put the reduced limits on a Body (clamp_ang then holds them) and take them off byte for byte.
class_name Injury
extends RefCounted

const FPS := 60.0
const ALIAS := {"knee": "calf", "shoulder": "upperarm", "hip": "thigh", "elbow": "lowerarm", "ankle": "foot"}
const AXES := ["bend", "side", "twist"]


## "knee_r" -> "calf_r"; "" when the name is no joint of the body
static func joint_name(n: String) -> String:
	var base := n
	var sd := ""
	if n.ends_with("_l") or n.ends_with("_r"):
		base = n.substr(0, n.length() - 2)
		sd = n.substr(n.length() - 2)
	if ALIAS.has(base):
		base = ALIAS[base]
	var j := base + sd
	return j if j in Body.ORDER else ""


static func clean(d: Variant) -> Dictionary:
	var out := {}
	if d is Dictionary:
		for k in d:
			var j := joint_name(String(k))
			if j != "" and d[k] is Dictionary:
				var e := {"rom": clampf(float(d[k].get("rom", 0.0)), 0.0, 0.9), "strength": clampf(float(d[k].get("strength", 0.0)), 0.0, 0.9)}
				if e["rom"] > 0.0 or e["strength"] > 0.0:
					out[j] = e
	return out


static func mirror_file(d: Dictionary) -> Dictionary:
	var out := {}
	for j in d:
		var s := String(j)
		var t := s
		if s.ends_with("_l"):
			t = s.substr(0, s.length() - 2) + "_r"
		elif s.ends_with("_r"):
			t = s.substr(0, s.length() - 2) + "_l"
		out[t] = (d[j] as Dictionary).duplicate()
	return out


static func rom_loss(prof: Dictionary, j: String) -> float:
	return float(prof[j].get("rom", 0.0)) if prof.has(j) else 0.0


static func strength_loss(prof: Dictionary, j: String) -> float:
	return float(prof[j].get("strength", 0.0)) if prof.has(j) else 0.0


## the torque / speed cap of joint j: the healthy cap x (1 - strength loss)
static func torque_cap(prof: Dictionary, j: String, base: float) -> float:
	return base * (1.0 - strength_loss(prof, j))


## the healthy limits of joint j (the stored copy while apply() is on)
static func healthy(B: Body, j: String) -> Dictionary:
	if B.has_meta("inj_lim") and (B.get_meta("inj_lim") as Dictionary).has(j):
		return B.get_meta("inj_lim")[j]
	return B.lim[j]


## the profile's reduced limits for joint j: {"bend": Vector2, ...}
static func reduced(B: Body, prof: Dictionary, j: String) -> Dictionary:
	var src := healthy(B, j)
	var f := 1.0 - rom_loss(prof, j)
	var out := {}
	for ax in AXES:
		out[ax] = (src[ax] as Vector2) * f
	return out


static func apply(B: Body, prof: Dictionary) -> void:
	clear(B)
	var keep := {}
	for j in prof:
		if rom_loss(prof, j) > 0.0 and B.lim.has(j):
			keep[j] = B.lim[j].duplicate()
			var r := reduced(B, prof, j)
			for ax in AXES:
				B.lim[j][ax] = r[ax]
	B.set_meta("inj_lim", keep)


static func clear(B: Body) -> void:
	if B.has_meta("inj_lim"):
		var keep: Dictionary = B.get_meta("inj_lim")
		for j in keep:
			B.lim[j] = keep[j]
		B.remove_meta("inj_lim")


static func _words(j: String) -> String:
	var sd := ""
	var base := j
	if j.ends_with("_l") or j.ends_with("_r"):
		sd = " (left)" if j.ends_with("_l") else " (right)"
		base = j.substr(0, j.length() - 2)
	for k in ALIAS:
		if ALIAS[k] == base:
			base = k
	return base + sd


## INJURY ROM findings: runs of frames where a profile joint's played angle is past its reduced range. Each: {sev FAIL, t, t1, frame (the
## scene's frames, first of the run), card, joint, axis, peak (deg), limit (deg), rule, msg}. Empty without a profile.
static func findings(S: Scene, B: Body) -> Array:
	var out := []
	if S.injury.is_empty() or S.cards.size() < 2:
		return out
	var n := int(ceil(S.length() * FPS)) + 1
	var was := S.stepped
	S.stepped = false
	var js := S.injury.keys().filter(func(j): return rom_loss(S.injury, j) > 0.0 and B.lim.has(j))
	js.sort()
	var mk := func(_i: int, t: float) -> Dictionary:
		FrameMemo.pose(S, B, t)
		var row := {}
		for j in js:
			row[j] = B.ang[j]
		return row
	var rows: Array = FrameMemo.frames("inj", S, B, n, FPS, mk)
	S.stepped = was
	for j in js:
		var lim := reduced(B, S.injury, j)
		var hl := healthy(B, j)
		for k in AXES.size():
			var ax: String = AXES[k]
			var r: Vector2 = lim[ax]
			if r.y - r.x <= 0.5:
				continue
			var i := 0
			while i < n:
				var v: float = (rows[i][j] as Vector3)[k]
				if v > r.y + 0.05 or v < r.x - 0.05:
					var i0 := i
					var pk := v
					while i < n and ((rows[i][j] as Vector3)[k] > r.y + 0.05 or (rows[i][j] as Vector3)[k] < r.x - 0.05):
						var w: float = (rows[i][j] as Vector3)[k]
						if absf(w) > absf(pk):
							pk = w
						i += 1
					var edge: float = r.y if pk > 0.0 else r.x
					var hedge: float = (hl[ax] as Vector2).y if pk > 0.0 else (hl[ax] as Vector2).x
					var t0 := float(i0) / FPS
					var t1 := float(i - 1) / FPS
					var fr := int(round(t0 * S.fps))
					out.append({"sev": "FAIL", "t": t0, "t1": t1, "frame": fr, "card": Rulebook.card_at(S, t0), "joint": j, "axis": ax, "peak": pk, "limit": edge, "rule": "INJURY ROM",
						"msg": "%.2f-%.2f s (from frame %d): %s %s goes to %.0f deg, past the injured range (%.1f deg; healthy %.0f, ROM -%.0f%%)." % [
							t0, t1, fr, _words(j), ax, pk, edge, hedge, rom_loss(S.injury, j) * 100.0]})
				else:
					i += 1
	out.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	return out


## the moves of the scene that now fail: one row per card + joint + axis: {card, name, frame, joint, axis, peak, limit, msg}
static func moves(S: Scene, B: Body) -> Array:
	var out := []
	var seen := {}
	for f in findings(S, B):
		var key := "%d %s %s" % [f["card"], f["joint"], f["axis"]]
		if seen.has(key):
			continue
		seen[key] = true
		var c := int(f["card"])
		out.append({"card": c, "name": String(S.cards[c]["name"]) if c >= 0 and c < S.cards.size() else "", "frame": f["frame"], "joint": f["joint"], "axis": f["axis"], "peak": f["peak"], "limit": f["limit"], "msg": f["msg"]})
	return out


static func serve(m: Node, p: Dictionary) -> Dictionary:
	var a := String(p.get("action", "read"))
	var S: Scene = m.S
	if a == "read":
		return {"ok": true, "result": {"injury": S.injury.duplicate(true)}}
	if a == "moves":
		return {"ok": true, "result": {"moves": moves(S, m.B)}}
	if a == "set":
		var j := joint_name(String(p.get("joint", "")))
		if j == "":
			return {"ok": false, "error": "joint needs a joint of the body such as knee_r, shoulder_l, calf_r (got '%s')" % String(p.get("joint", ""))}
		for k in ["rom", "strength"]:
			if p.has(k) and (float(p[k]) < 0.0 or float(p[k]) > 0.9):
				return {"ok": false, "error": "%s needs a loss between 0 and 0.9 (0.3 = 30 percent), got %s" % [k, str(p[k])]}
		var e: Dictionary = (S.injury[j] as Dictionary).duplicate() if S.injury.has(j) else {"rom": 0.0, "strength": 0.0}
		for k in ["rom", "strength"]:
			if p.has(k):
				e[k] = float(p[k])
		m._push_undo()
		S.injury[j] = e
		if float(e["rom"]) <= 0.0 and float(e["strength"]) <= 0.0:
			S.injury.erase(j)
	elif a == "clear":
		m._push_undo()
		if p.has("joint"):
			S.injury.erase(joint_name(String(p["joint"])))
		else:
			S.injury = {}
	else:
		return {"ok": false, "error": "action is one of read, set, clear, moves"}
	if m.has_method("_refresh"):
		m._refresh()
	return {"ok": true, "result": {"injury": S.injury.duplicate(true)}}
