## frame_advantage.gd - HITSTUN, BLOCKSTUN AND FRAME ADVANTAGE (INNOVATIONS N080). FrameData (frame_data.gd) measures one
## fighter's startup / active / recovery; this measures the EXCHANGE: how long the defender's reaction keeps him from acting,
## and who acts first afterwards. Terms and sources: docs/research/FRAME_DATA.md ("Hitstun and frame advantage").
##
## FRAMES: the attacker's FrameData frames (60 per second by default, the fighting-game clock); frame f = the pose at f / fps.
##   CONTACT frame c: the first frame the attacker's part is in the defender (Dummy.fighter_hits, the onset rounded UP to a frame:
##     the first frame whose pose has the contact), else, with no defender geometry (a reaction CLIP), the first active frame
##     (a frame-data chart assumes the move connects on its first active frame: the same convention).
##   RECOVERY END R = the first frame the attacker can act = last active + recovery + 1 = FrameData's n (the scene's end).
##   STUN END E = the first frame the defender can act: the first frame after his reaction's PEAK at which his pose is back
##     within TOL_M of the pose he was hit in (every joint and end point, relative to his pelvis, in his own space) and stays
##     there SETTLE frames (or to the clip's end).
##   HITSTUN / BLOCKSTUN = E - c - 1: the frames AFTER the contact frame during which he cannot act (the contact frame itself
##     is the attacker's active frame). With this count the community's formula holds exactly:
##       advantage = stun - (active frames left after the contact frame + recovery)  =  E - R
##   ADVANTAGE (on hit, on block) = E - R. + = the attacker acts first by that many frames; - = the defender does.
##   PUNISHABLE (on block): the defender's fastest move, input on E, is first active on E + startup (Kine's startup = the
##     frames BEFORE the first active frame). It lands before the attacker can act (guard) when E + startup < R, i.e.
##     -advantage > startup: "the disadvantage exceeds the fastest startup".
##
## TOL_M = 2 cm, HEURISTIC (no paper sets it): "back in guard" must ignore the 1-2 mm a played blend leaves (the card maker's
## 1 deg replay tolerance is ~1 cm at a hand 0.6 m from the shoulder: REPLAY_DEG in hit_reaction.gd) and catch a guard still
## visibly open; human_limits.gd TOUCH (2 cm) is the same size of "there". The test prints how the measure moves at 1 and 5 cm.
## SETTLE = 3 frames, HEURISTIC: a damped spring crossing the guard once (HitReaction's zeta 0.5 overshoots) is not "back".
## LIMITS: the pose he was hit in is the reference, so a defender whose own animation walks on after the hit is never "back";
## knockback distance is not stun (the pelvis's travel is removed). Nothing here is a game's state machine: it is what the
## animation shows.
class_name FrameAdvantage
extends RefCounted

const TOL_M := 0.02
const SETTLE := 3


## the body's shape now: every joint and end point minus the pelvis (m, its own space)
static func shape(B: Body) -> Array:
	var root: Vector3 = B.P["pelvis"]
	var out := []
	for j in B.P:
		out.append((B.P[j] as Vector3) - root)
	for j in B.E:
		out.append((B.E[j] as Vector3) - root)
	return out


## the largest distance between two shapes (m)
static func dev(a: Array, b: Array) -> float:
	var d := 0.0
	for i in mini(a.size(), b.size()):
		d = maxf(d, (a[i] as Vector3).distance_to(b[i]))
	return d


## THE STUN of a reaction: RS played on RB, the contact at scene time t_hit (frame c = ceil(t_hit * fps)). Frames are RS's
## own at fps. Returns {"c", "end" (E), "stun" (E - c - 1), "peak_f", "peak_m", "back" (false: not back by the clip's end,
## E = the frame after it and stun is then a lower bound), "tol_m"}. RB is left at the clip's last frame.
static func stun(RS: Scene, RB: Body, t_hit: float, fps := FrameData.FPS, tol := TOL_M) -> Dictionary:
	var c := int(ceil(t_hit * float(fps) - 1e-6))
	var last := int(floor(RS.length() * float(fps) + 1e-6))
	RS.apply(RB, t_hit)
	var ref := shape(RB)
	var ds := []   # ds[k] = the deviation at frame c + k
	for f in range(c, last + 1):
		RS.apply(RB, float(f) / float(fps))
		ds.append(dev(shape(RB), ref))
	var pk := 0
	for k in ds.size():
		if float(ds[k]) > float(ds[pk]):
			pk = k
	var out := {"c": c, "peak_f": c + pk, "peak_m": snappedf(float(ds[pk]) if not ds.is_empty() else 0.0, 1e-4), "back": true, "tol_m": tol}
	if ds.is_empty() or float(ds[pk]) <= tol:
		out["end"] = c + 1   # he never left his guard: he may act on the very next frame
	else:
		var e := -1
		for k in range(pk + 1, ds.size()):
			var ok := true
			for s in range(k, mini(k + SETTLE, ds.size())):
				if float(ds[s]) > tol:
					ok = false
					break
			if ok:
				e = k
				break
		if e < 0:
			out["back"] = false
			e = ds.size()
		out["end"] = c + e
	out["stun"] = int(out["end"]) - c - 1
	return out


## the contact frame: the first attacker -> defender contact (Dummy.fighter_hits rows, by "hero") inside the active span,
## else the first active frame. {"c", "t" (s, the onset; -1 assumed), "from": "contact" / "first active", "part", "on"}
static func contact(fd: Dictionary, hits: Array) -> Dictionary:
	var fps := float(fd["fps"])
	for h in hits:
		if String(h.get("by", "")) != "hero":
			continue
		var c := int(ceil(float(h["t"]) * fps - 1e-6))
		if int(fd["first"]) >= 0 and c >= int(fd["first"]) and c <= int(fd["last"]):
			return {"c": c, "t": float(h["t"]), "from": "contact", "part": h.get("part", ""), "on": h.get("on", "")}
	return {"c": int(fd["first"]), "t": -1.0, "from": "first active", "part": "", "on": ""}


## the fastest startup among the defender's moves (FrameData of each scene, played on B; a scene with no active part is
## skipped). -1 = none known
static func fastest(moves: Array, B: Body, fps := FrameData.FPS) -> int:
	var best := -1
	for mv in moves:
		var fd := FrameData.analyze(mv, B, fps)
		if fd.is_empty() or int(fd["first"]) < 0:
			continue
		best = int(fd["startup"]) if best < 0 else mini(best, int(fd["startup"]))
	return best


## THE NUMBERS from the parts: fd = the attacker's FrameData, ct = contact(), hit / block = stun() results in the
## attacker's frames ({} = no such clip), quick = fastest() (-1 = unknown)
static func numbers(fd: Dictionary, ct: Dictionary, hit: Dictionary, block: Dictionary, quick: int) -> Dictionary:
	var R := int(fd["n"])   # = startup + active + recovery = last active + recovery + 1
	var out := {"fps": int(fd["fps"]), "contact_f": int(ct["c"]), "contact_from": ct["from"], "recovery_end": R,
		"hitstun": null, "hit_stun_end": null, "on_hit": null, "blockstun": null, "block_stun_end": null, "on_block": null,
		"defender_fastest_startup": quick if quick >= 0 else null, "punishable": null, "tol_m": TOL_M,
		"convention": "60 fps frames; stun = frames after the contact frame; advantage = stun end - recovery end (+ = attacker acts first)"}
	if int(ct["c"]) < 0:
		out["note"] = "the attacker has no active frame: nothing connects"
		return out
	for kv in [["hit", hit], ["block", block]]:
		var r: Dictionary = kv[1]
		if r.is_empty():
			continue
		var k: String = kv[0]
		out[k + "stun"] = int(r["stun"])
		out[k + "_stun_end"] = int(r["end"])
		out["on_" + k] = int(r["end"]) - R
		if not bool(r["back"]):
			out[k + "_note"] = "the defender is not back in guard by the clip's end: %sstun is at least this" % k
	if out["on_block"] != null and quick >= 0:
		out["punishable"] = int(out["on_block"]) < 0 and -int(out["on_block"]) > quick
	return out


## a reaction clip (first card = the moment of impact, ReactionPicker's convention) put at contact frame c: its stun in the
## attacker's frames. {} for no clip
static func clip_stun(RS: Scene, RB: Body, c: int, fps := FrameData.FPS) -> Dictionary:
	if RS == null or RS.cards.is_empty():
		return {}
	var r := stun(RS, RB, 0.0, fps)
	r["c"] = c
	r["end"] = int(r["end"]) + c
	r["peak_f"] = int(r["peak_f"]) + c
	return r


## TWO FIGHTERS ON THE STAGE: attacker AS on AB, defender DS on DB placed by xf (his space -> the attacker's); DS is his track
## WITH the hit reaction in it (HitReaction / the picker put it at the contact). block_clip: a block reaction clip (or null);
## moves: the defender's moves as scenes (his own track counts as one when it has an active part). hits: the attacker's
## Dummy.fighter_hits rows when the caller already has them (null = found here). They are found at Dummy's own 30 Hz: it
## samples at 240 Hz wherever the bodies may touch and bisects the onset to 1/1024 of a frame, so the 60 fps contact frame
## is the same, at half the cost (combo3 vs a fighter: ~20 s at 60 Hz on a loaded machine is the run_par timeout's enemy).
static func of_actors(AS: Scene, AB: Body, DS: Scene, DB: Body, xf: Transform3D, fps := FrameData.FPS, block_clip: Scene = null, moves: Array = [], hits: Variant = null) -> Dictionary:
	var fd := FrameData.analyze(AS, AB, fps)
	if fd.is_empty():
		return {}
	var ct := contact(fd, hits if hits is Array else Dummy.fighter_hits(AS, AB, DS, DB, xf))
	var hit := {}
	if int(ct["c"]) >= 0:
		hit = stun(DS, DB, float(ct["t"]) if float(ct["t"]) >= 0.0 else float(ct["c"]) / float(fps), fps)
	var blk := clip_stun(block_clip, DB, int(ct["c"]), fps) if int(ct["c"]) >= 0 else {}
	var mv := moves.duplicate()
	mv.append(DS)
	var out := numbers(fd, ct, hit, blk, fastest(mv, DB, fps))
	out["fd"] = fd
	return out


## REACTION CLIPS only (no second fighter on the stage): the hit and block clips start at the attacker's first active frame
static func of_clips(AS: Scene, AB: Body, hit_clip: Scene, block_clip: Scene, DB: Body, fps := FrameData.FPS, moves: Array = []) -> Dictionary:
	var fd := FrameData.analyze(AS, AB, fps)
	if fd.is_empty():
		return {}
	var ct := contact(fd, [])
	var c := int(ct["c"])
	var hit := clip_stun(hit_clip, DB, c, fps) if c >= 0 else {}
	var blk := clip_stun(block_clip, DB, c, fps) if c >= 0 else {}
	var out := numbers(fd, ct, hit, blk, fastest(moves, DB, fps))
	out["fd"] = fd
	return out


## the exchange as the export and serve carry it (no FrameData inside: that is the file's top level)
static func to_json(ex: Dictionary) -> Dictionary:
	var out := ex.duplicate()
	out.erase("fd")
	return out


## one line for the strip / the status bar: "on hit +3, on block -5 (punishable by a 4 f move)"
static func words(ex: Dictionary) -> String:
	if ex.is_empty() or ex.get("on_hit") == null and ex.get("on_block") == null:
		return ""
	var bits := []
	if ex["on_hit"] != null:
		bits.append("on hit %+d (hitstun %d)" % [ex["on_hit"], ex["hitstun"]])
	if ex["on_block"] != null:
		var s := "on block %+d (blockstun %d)" % [ex["on_block"], ex["blockstun"]]
		if ex["punishable"] == true:
			s += " PUNISHABLE by his %d f startup" % ex["defender_fastest_startup"]
		bits.append(s)
	return ", ".join(bits)


static func _stand() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b


static func _scene(path: String) -> Scene:
	var r := AgentTools.res(path)
	if path == "" or not FileAccess.file_exists(r):
		return null
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(r))
	if not (d is Dictionary):
		return null
	var s := Scene.new()
	s.from_dict(d)
	return s


## SERVE `frame_data` (agent_tools.gd): the live scene's frame data on a fresh standing body (the live body is not moved).
## Default: FrameData.to_json without the per-frame boxes ({"frames": true} adds them). OPT-IN exchange: {"exchange": true}
## (the active fighter against the first other one on the stage), and/or {"hit_clip": path, "block_clip": path} (reaction
## clips, first card = the impact), {"moves": [paths]} (the defender's moves, for punishable), {"fps": 60}.
## Returns {"ok", "result"} or {"ok": false, "error"}.
static func serve(m: Node, p: Dictionary) -> Dictionary:
	if m.S.cards.size() < 2:
		return {"ok": false, "error": "frame_data needs a scene of 2+ cards: open one first"}
	var fps := int(p.get("fps", FrameData.FPS))
	if fps < 1:
		return {"ok": false, "error": "fps must be a whole number of frames a second, e.g. 60"}
	var want := bool(p.get("exchange", false)) or p.has("hit_clip") or p.has("block_clip")
	var AB := _stand()
	var fd := {}
	var ex := {}
	if want:
		var clips := {}
		for k in ["hit_clip", "block_clip"]:
			clips[k] = null
			if p.has(k):
				clips[k] = _scene(String(p[k]))
				if clips[k] == null:
					return {"ok": false, "error": "%s: no such scene file '%s' (a reaction clip: its first card is the moment of impact)" % [k, p[k]]}
		var moves := []
		for mp in p.get("moves", []):
			var ms := _scene(String(mp))
			if ms == null:
				return {"ok": false, "error": "moves: no such scene file '%s'" % mp}
			moves.append(ms)
		var DB := _stand()
		m._actors_sync()
		if m.actors_rt.size() >= 2 and clips["hit_clip"] == null:
			var a: Dictionary = m.actors_rt[m.actor_on]
			var d: Dictionary = m.actors_rt[1 if m.actor_on == 0 else 0]
			var xf: Transform3D = (a["xf"] as Transform3D).affine_inverse() * (d["xf"] as Transform3D)
			ex = of_actors(a["S"], AB, d["S"], DB, xf, fps, clips["block_clip"], moves)
		elif clips["hit_clip"] != null or clips["block_clip"] != null:
			ex = of_clips(m.S, AB, clips["hit_clip"], clips["block_clip"], DB, fps, moves)
		else:
			return {"ok": false, "error": "exchange needs a second fighter on the stage, or {\"hit_clip\": path} / {\"block_clip\": path} (reaction clips)"}
		if ex.is_empty():
			return {"ok": false, "error": "the scene has no frames to measure"}
		fd = ex["fd"]
	else:
		fd = FrameData.analyze(m.S, AB, fps)
	var out := FrameData.to_json(fd)
	if not bool(p.get("frames", false)):
		out.erase("frames")
	if want:
		out["exchange"] = to_json(ex)
	return {"ok": true, "result": out}


# ---------------------------------------------------------------- the app's frame strip / export (main.gd _fd_data)
static var _db: Body = null   # the defender's fresh body, read once


## what the exchange depends on besides the active fighter's cards: the other fighter's cards and placement ("" = one fighter)
static func app_key(m: Node) -> String:
	if m.actors_rt.size() < 2:
		return ""
	var d: Dictionary = m.actors_rt[1 if m.actor_on == 0 else 0]
	return var_to_str((d["S"] as Scene).cards) + var_to_str(d["xf"]) + var_to_str(m.actors_rt[m.actor_on]["xf"])


## two fighters on the stage: the active one's FrameData with "exchange" in it (the export carries it); {} = one fighter
static func app_fd(m: Node, Bc: Body, fps: int) -> Dictionary:
	if m.actors_rt.size() < 2 or m.actor_on >= m.actors_rt.size() or m.actors_rt[m.actor_on]["S"] != m.S:
		return {}
	if _db == null:
		_db = _stand()
	_db.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	_db.ground()
	var a: Dictionary = m.actors_rt[m.actor_on]
	var d: Dictionary = m.actors_rt[1 if m.actor_on == 0 else 0]
	var ex := of_actors(m.S, Bc, d["S"], _db, (a["xf"] as Transform3D).affine_inverse() * (d["xf"] as Transform3D), fps)
	if ex.is_empty():
		return {}
	var fd: Dictionary = ex["fd"]
	fd["exchange"] = to_json(ex)
	return fd
