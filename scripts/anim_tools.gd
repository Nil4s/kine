## anim_tools.gd - ANIMATION TOOLS (ROADMAP_400 L07, L09, L10, L11; lane L87).
## What already existed and is reused: the per-part onion (Overlays.onion_times, step = a ghost every N frames), the Breakdowner
## (card before / after slerp, overshoot, selected parts only), PartSets (named keying sets, saved with the scene) and Auto-key.
## New here:
##   RETIME (L10): move one card's arrival by whole frames. With RIPPLE the card's move grows by the delta, so every later card
##     (and every part key after it) shifts by exactly that delta; earlier cards are not touched. Without ripple every other key
##     stays where it is: the move trades with this card's hold and the next card's move, and a move that would leave either of
##     them under MIN_GAP seconds (i.e. cross a neighbour) is refused, nothing changes.
##   AUTO-KEY ON A SET (L11): see Main._autokey_set (with an active keying set auto-key keys that set's parts as part keys, no card).
##   serve(): the agent tool `animtools` {op: onion | breakdown | retime | keyset}.
class_name AnimTools
extends RefCounted

const MIN_GAP := 0.04   # s: no move shorter than this (Scene.MIN_MOVE of Scene.retime)


## "" if card i's arrival may move by df frames (ripple or not), else why not. Nothing is touched.
static func retime_refuse(S: Scene, i: int, df: int, ripple: bool) -> String:
	if i <= 0 or i >= S.cards.size():
		return "pick a card after the first one: the first card is the start of the clip"
	if df == 0:
		return "a move of 0 frames changes nothing"
	var d := float(df) / float(S.fps)
	var ts := S.times()
	var a := float(ts[i][1])
	var e_prev := float(ts[i - 1][2])
	if a + d - e_prev < MIN_GAP - 1e-9:
		return "that would put key %d on the key before it (a move needs %.2f s): move it less" % [i + 1, MIN_GAP]
	if not ripple and i + 1 < S.cards.size():
		var e_new := maxf(float(ts[i][2]), a + d)
		if float(ts[i + 1][1]) - e_new < MIN_GAP - 1e-9:
			return "that would cross key %d: use ripple to push the later keys along, or move it less" % [i + 2]
	return ""


## move card i's arrival by df frames. Returns {"ok", "why", "frames"}. Cards and part keys only (the caller follows markers).
static func retime_apply(S: Scene, i: int, df: int, ripple: bool) -> Dictionary:
	var why := retime_refuse(S, i, df, ripple)
	if why != "":
		return {"ok": false, "why": why, "frames": 0}
	var d := float(df) / float(S.fps)
	var ts: Array = S.times().duplicate(true)
	var a := float(ts[i][1])
	var e_prev := float(ts[i - 1][2])
	if ripple:
		S.cards[i]["move"] = snappedf(a + d - e_prev, 1e-9)
		for j in S.part_keys:
			for key in S.part_keys[j]:
				if float(key["t"]) > a + 1e-9:
					key["t"] = float(key["t"]) + d
	else:
		var e_new := maxf(float(ts[i][2]), a + d)
		S.cards[i]["move"] = snappedf(a + d - e_prev, 1e-9)
		S.cards[i]["hold"] = snappedf(e_new - (a + d), 1e-9)
		if i + 1 < S.cards.size():
			S.cards[i + 1]["move"] = snappedf(float(ts[i + 1][1]) - e_new, 1e-9)
	return {"ok": true, "why": "", "frames": df}


## the frames a per-part onion shows: [frame numbers] for the playhead frame, before / after counts and the step
static func onion_frames(frame: int, length: float, fps: float, before: int, after: int, step: int) -> Array:
	var out := []
	for f in Overlays.onion_times(float(frame) / fps, length, fps, before, after, step):
		out.append(int(round(float(f[0]) * fps)))
	out.sort()
	return out


## SERVE `animtools` (agent_tools.gd). {op: "onion", frame?, before?, after?, step?} -> {frames};
## {op: "breakdown", card, factor, parts?} -> {factor, moved, max_deg}; {op: "retime", card, frames, ripple?} -> {frames, ripple};
## {op: "keyset", name?, parts, active?} -> {name, parts, active}. Edits are one undo step each.
static func serve(m: Node, p: Dictionary) -> Dictionary:
	var op := String(p.get("op", ""))
	match op:
		"onion":
			var fr := int(p.get("frame", round(float(m.playhead) * float(m.S.fps))))
			var fl := onion_frames(fr, float(m.S.length()), float(m.S.fps), clampi(int(p.get("before", m.ov.onion_before)), 0, Overlays.ONION_MAX),
				clampi(int(p.get("after", m.ov.onion_after)), 0, Overlays.ONION_MAX), clampi(int(p.get("step", m.ov.onion_step)), 1, Overlays.ONION_STEP_MAX))
			return {"ok": true, "result": {"frames": fl, "parts": m.ov.onion_picks.duplicate(), "past": Tok.c("onion_past").to_html(false), "future": Tok.c("onion_future").to_html(false)}}
		"breakdown":
			var k := int(p.get("card", m.sel_card))
			var f := clampf(float(p.get("factor", 0.5)), Breakdowner.MIN_F, Breakdowner.MAX_F)
			var why := Breakdowner.refuse(m.S, k)
			if why != "":
				return {"ok": false, "error": why}
			var parts: Array = p.get("parts", [])
			m.sel_card = k
			if parts.size() > 1:
				m._select_set(parts)
			m._push_undo()
			var r := Breakdowner.run(m.B, m.S, k, f, Inbetween.joints_for(m.B, m.group()))
			if m.S.on_floor:
				m.S._ground(m.B)
			m.B.apply_grip()
			m._refresh()
			return {"ok": true, "result": {"factor": f, "moved": r["n"], "max_deg": r["max"], "stopped": r["stopped"].size()}}
		"retime":
			var r2: Dictionary = m._retime_key(int(p.get("card", -1)), int(p.get("frames", 0)), bool(p.get("ripple", true)))
			if not r2["ok"]:
				return {"ok": false, "error": String(r2["why"])}
			return {"ok": true, "result": {"frames": float(r2["frames"]), "ripple": bool(p.get("ripple", true))}}
		"keyset":
			var parts2: Array = p.get("parts", [])
			if parts2.is_empty():
				return {"ok": false, "error": "keyset needs parts: [\"upperarm_r\", ...]"}
			var ps := PartSets.of(m)
			var nm := String(p.get("name", "")).strip_edges()
			var keyable := PartSets.keyable(parts2)
			if keyable.is_empty():
				return {"ok": false, "error": "none of those is a body part"}
			if nm == "":
				nm = PartSets.auto_name(m.S.sets, "keying", keyable)
			var act := bool(p.get("active", true))
			ps._edit_sets(func(s):
				if not s.has("keying"):
					s["keying"] = {}
				s["keying"][nm] = keyable
				if act:
					s["active"] = nm)
			return {"ok": true, "result": {"name": nm, "parts": keyable, "active": ps.active() == nm}}
	return {"ok": false, "error": "op is onion, breakdown, retime or keyset"}
