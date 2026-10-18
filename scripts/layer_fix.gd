## FIX ON A LAYER (round 49, GATES NA2, UPGRADES_300 #255; Maya's practice of tweaking on an additive layer so the
## base animation stays as it was). A Check fix (scripts/fixer.gd) is run on a COPY of the scene; what it changed in the
## card POSES becomes additive layers, one a changed card, and the scene's own cards are not touched:
##   each layer's angles = what the FIXED scene plays at the card's arrival - what the scene plays there, on the joints
##   whose CARD angles the fix changed (> 0.01 deg; the head fix edits the trunk only: the legs that move with it are the
##   floor re-planting them under the moved hips, and an additive leg offset would fight the plant). Played, not the card's own angles: with natural overlap the trunk is still on
##   its way at the arrival (a card-angle difference overshot by 2.8 deg on combo3_detail card 24);
##   its weight is KEYED on every frame from the card before's arrival to the next card's arrival: at each frame the
##   least-squares scale of the arrival change that best matches the fix's played change there (sum over the layer's
##   joints of D(t).V / V.V), so the in-between follows the fix, not a guessed fade; 1 at the arrival by construction,
##   0 at the ends. Its "w" (1) scales that curve: 0 = none of the fix, 1 = all of it.
##   The hips' POSITION the fix also eases goes on the layer as "offset" (Scene.add_layers re-plants the feet after it).
## A fix that changes anything else on a card (a move's time, flow, a planted foot) cannot be a layer (a layer holds
## angles, not time): it is refused with that reason, and the plain Fix still works.
class_name LayerFix
extends RefCounted

## the floor plants these (Scene._ground after the fix puts the card), so their change is a consequence, not the fix
const LEGS := ["thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]


## {"ok": bool, "msg": String, "layers": [layer dicts for Scene.layers]}; S is not changed
static func make(f: Dictionary, S: Scene, B: Body, sm0 := {}) -> Dictionary:
	if Fixer.label(f, S) == "":
		return {"ok": false, "msg": "%s has no automatic fix to put on a layer" % f["rule"], "layers": []}
	var C := S.clone()
	C.cards = S.cards.duplicate(true)
	var keep := B.state()
	var r: Dictionary = Fixer.apply(f, C, B, sm0)
	B.set_state(keep)
	if not r["kept"]:
		return {"ok": false, "msg": "the fix was not kept, so there is nothing to layer: " + String(r["msg"]), "layers": []}
	var changed := []
	for i in S.cards.size():
		var a: Dictionary = (S.cards[i] as Dictionary).duplicate(true)
		var b: Dictionary = (C.cards[i] as Dictionary).duplicate(true)
		var pa: Dictionary = a["pose"]
		var pb: Dictionary = b["pose"]
		a.erase("pose")
		b.erase("pose")
		if JSON.stringify(a) != JSON.stringify(b):
			return {"ok": false, "msg": "this fix changes card %d's timing or contacts, not only its pose; a layer holds angles only, so use the plain Fix" % (i + 1), "layers": []}
		if JSON.stringify(pa) != JSON.stringify(pb):
			changed.append(i)
	var ts := S.times()
	var PA := Body.new()
	PA.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var PB := Body.new()
	PB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var out := []
	for i in changed:
		PA.from_dict(S.cards[i]["pose"])
		PB.from_dict(C.cards[i]["pose"])
		var js := []
		for j in PA.ang:
			if ((PB.ang[j] as Vector3) - (PA.ang[j] as Vector3)).length() > 0.01 and not LEGS.has(j):
				js.append(j)
		S.apply(PA, float(ts[i][1]))
		C.apply(PB, float(ts[i][1]))
		var v := {}
		for j in js:
			var d: Vector3 = (PB.ang[j] as Vector3) - (PA.ang[j] as Vector3)
			if d.length() > 0.01:
				v[j] = d
		if (PB.offset - PA.offset).length() > 0.0005:
			v["offset"] = PB.offset - PA.offset   # the hips' position (metres; 1 cm counts as 1 deg in the fit below)
		if v.is_empty():
			continue
		var t0 := float(ts[i - 1][1]) if i > 0 else float(ts[i][1])
		var t1 := float(ts[i + 1][1]) if i < S.cards.size() - 1 else float(ts[i][1])
		var fps := float(maxi(S.fps, 1))
		var vv := 0.0
		for j in v:
			vv += (v[j] as Vector3).length_squared() * (1e4 if j == "offset" else 1.0)
		var wk := []
		var n := int(round((t1 - t0) * fps))
		for k in n + 1:
			var t := minf(t0 + k / fps, t1)
			if absf(t - float(ts[i][1])) < 0.5 / fps:
				t = float(ts[i][1])
			S.apply(PA, t)
			C.apply(PB, t)
			var dv := 0.0
			for j in v:
				if j == "offset":
					dv += (PB.offset - PA.offset).dot(v[j]) * 1e4
				else:
					dv += ((PB.ang[j] as Vector3) - (PA.ang[j] as Vector3)).dot(v[j])
			wk.append([t, clampf(dv / vv, 0.0, 1.0)])
		if absf(float(wk[-1][0]) - t1) > 1e-6:
			wk.append([t1, 0.0])
		out.append({"name": "Fix %s c%d" % [String(f["rule"]).to_lower(), i + 1], "mode": "add", "w": 1.0, "wk": wk,
			"mute": false, "solo": false, "lock": false, "v": v})
	if out.is_empty():
		return {"ok": false, "msg": "the fix changed no angle, so there is nothing to layer", "layers": []}
	return {"ok": true, "msg": "%s on %d layer%s (cards untouched): %s" % [r["msg"], out.size(), "" if out.size() == 1 else "s", ", ".join(out.map(func(L): return L["name"]))], "layers": out}
