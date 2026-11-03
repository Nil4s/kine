## HAND BEND CHECK (C08, complaint #543: a mocap file's hand / finger bend values arriving wrong). Reads a scene's finger joints
## against Kine's limits (Body.lim) and says in one line how many leave their range. Words only; the scene is unchanged.
class_name HandCheck

const TOL := 1.0   # degrees past a limit before it counts


## {"joints": distinct finger joints out of range, "cards_out": cards with any, "cards", "worst": {joint, axis, deg, over_deg, lo, hi}, "text"}
static func check(S: Scene, B: Body) -> Dictionary:
	var bad := {}
	var cards_out := 0
	var worst := {"joint": "", "axis": "", "deg": 0.0, "over_deg": 0.0, "lo": 0.0, "hi": 0.0}
	for c in S.cards:
		var jd: Dictionary = (c["pose"] as Dictionary).get("joints", {})
		var hit := false
		for f in Body.FINGERS:
			if not (jd.has(f) and B.lim.has(f)):
				continue
			for ax in ["bend", "side", "twist"]:
				var r: Vector2 = B.lim[f][ax]
				var v := float(jd[f].get(ax, 0.0))
				var over := maxf(v - r.y, r.x - v)
				if over > TOL:
					hit = true
					bad[f] = true
					if over > float(worst["over_deg"]):
						worst = {"joint": f, "axis": ax, "deg": v, "over_deg": over, "lo": r.x, "hi": r.y}
		if hit:
			cards_out += 1
	var text := ""
	if not bad.is_empty():
		text = "hands: %d finger joint%s %s outside Kine's range on %d of %d cards (worst %s %s %.0f deg, Kine allows %.0f..%.0f); the bend values may have come in wrong, so play the hands before using them" % [
			bad.size(), "" if bad.size() == 1 else "s", "is" if bad.size() == 1 else "are", cards_out, S.cards.size(), worst["joint"], worst["axis"], worst["deg"], worst["lo"], worst["hi"]]
	return {"joints": bad.size(), "cards_out": cards_out, "cards": S.cards.size(), "worst": worst, "text": text}
