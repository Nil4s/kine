## group_fight.gd - ONE VS MANY (INNOVATIONS N048). Attackers around the hero (origin, facing +z; positions are (x, z) in metres) are scheduled so that
## no two attack at once from the same SIDE (front/right/back/left, 90 deg sectors), at most MAX_SIMUL at once, none attacks out of REACH, none attacks
## while another that blocks its line of sight to the hero is attacking, and every attacker gets ROUNDS windows.
##   WAIT POSITION: on the attacker bearing at 0.9 x reach (or where it stands if closer), nudged apart until neighbours are >= MIN_GAP (0.8 m) apart.
##   An attacker outside its reach first walks to the wait position (WALK m/s); its first window opens on arrival.
##   Output {attacks: [{id, t0, t1, side, from, round}], waits: [{id, pos, dist, side, arrive}]}. check() judges ANY schedule (including a hand-made one).
## Not modelled (stated): the hero turning, the attackers' footwork between windows, weapons longer than the reach given, dodging.
class_name GroupFight
extends RefCounted

const MIN_GAP := 0.8
const ATTACK_T := 0.8
const COOLDOWN := 1.0
const WALK := 1.5
const MAX_SIMUL := 2
const ROUNDS := 2
const STEP := 0.05
const LOS_R := 0.35
const SIDES := ["front", "right", "back", "left"]


static func side_of(p: Vector2) -> String:
	var k := int(floorf((atan2(p.x, p.y) + PI / 4.0) / (PI / 2.0)))
	return SIDES[((k % 4) + 4) % 4]


## does b stand on the line from a to the hero (origin), nearer to the hero?
static func blocks(b: Vector2, a: Vector2) -> bool:
	if b.length() >= a.length():
		return false
	var t := clampf(b.dot(a) / maxf(a.length_squared(), 1e-9), 0.0, 1.0)
	return (a * t - b).length() < LOS_R


static func _overlap(a: Dictionary, b: Dictionary) -> bool:
	return float(a["t0"]) < float(b["t1"]) - 1e-9 and float(b["t0"]) < float(a["t1"]) - 1e-9


static func _pt(ang: Array, rad: Array, i: int) -> Vector2:
	return Vector2(sin(ang[i]) * rad[i], cos(ang[i]) * rad[i])


static func plan(atk: Array) -> Dictionary:
	var n := atk.size()
	var ang: Array = []
	var rad: Array = []
	for a in atk:
		var p: Vector2 = a["pos"]
		ang.append(atan2(p.x, p.y))
		rad.append(minf(p.length(), 0.9 * float(a.get("reach", 1.0))))
	for _it in 400:
		var moved := false
		for i in n:
			for j in range(i + 1, n):
				if (_pt(ang, rad, i) - _pt(ang, rad, j)).length() < MIN_GAP:
					var d := wrapf(ang[j] - ang[i], -PI, PI)
					var s := 1.0 if d >= 0.0 else -1.0
					ang[i] -= s * 0.03
					ang[j] += s * 0.03
					moved = true
		if not moved:
			break
	var waits := []
	var arrive := []
	for i in n:
		var w := _pt(ang, rad, i)
		var d0: float = (atk[i]["pos"] as Vector2).length()
		var arr := maxf(0.0, d0 - float(rad[i])) / WALK
		arrive.append(arr)
		waits.append({"id": atk[i]["id"], "pos": w, "dist": w.length(), "side": side_of(w), "arrive": arr})
	var order := range(n)
	order.sort_custom(func(a, b): return arrive[a] < arrive[b] or (arrive[a] == arrive[b] and ang[a] < ang[b]))
	var attacks := []
	for rd in ROUNDS:
		for i in order:
			var w: Dictionary = waits[i]
			var ready: float = arrive[i]
			for e in attacks:
				if e["id"] == w["id"]:
					ready = maxf(ready, float(e["t1"]) + COOLDOWN)
			var t := ready
			while true:
				var cand := {"id": w["id"], "t0": t, "t1": t + ATTACK_T, "side": w["side"], "from": w["pos"], "round": rd}
				var bad := false
				var conc := 0
				for e in attacks:
					if not _overlap(cand, e):
						continue
					conc += 1
					if e["side"] == cand["side"] or blocks(e["from"], cand["from"]) or blocks(cand["from"], e["from"]):
						bad = true
				if not bad and conc < MAX_SIMUL:
					attacks.append(cand)
					break
				t += STEP
	attacks.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))
	return {"attacks": attacks, "waits": waits}


## judge any schedule against the attackers {id, pos, reach}
static func check(sch: Dictionary, atk: Array) -> Dictionary:
	var reach := {}
	for a in atk:
		reach[a["id"]] = float(a.get("reach", 1.0))
	var at: Array = sch["attacks"]
	var same := 0
	var los := 0
	var oor := 0
	var flags := []
	for i in at.size():
		var a: Dictionary = at[i]
		var fp: Vector2 = a["from"]
		if fp.length() > float(reach.get(a["id"], 1.0)) + 1e-6:
			oor += 1
			flags.append("%s starts %.2f m out (reach %.2f)" % [a["id"], fp.length(), reach.get(a["id"], 1.0)])
		for j in range(i + 1, at.size()):
			var b: Dictionary = at[j]
			if not _overlap(a, b):
				continue
			if side_of(fp) == side_of(b["from"]):
				same += 1
				flags.append("%s and %s attack together from the %s" % [a["id"], b["id"], side_of(fp)])
			if blocks(b["from"], fp) or blocks(fp, b["from"]):
				los += 1
				flags.append("%s and %s attack together with a blocked line of sight" % [a["id"], b["id"]])
	var cnt := {}
	for a in atk:
		cnt[a["id"]] = 0
	for e in at:
		if cnt.has(e["id"]):
			cnt[e["id"]] += 1
	var mw := 99
	for k in cnt:
		mw = mini(mw, int(cnt[k]))
		if cnt[k] == 0:
			flags.append("%s never gets a window" % k)
	var wg := 99.0
	var ws: Array = sch.get("waits", [])
	for i in ws.size():
		for j in range(i + 1, ws.size()):
			wg = minf(wg, ((ws[i]["pos"] as Vector2) - (ws[j]["pos"] as Vector2)).length())
	return {"same_side": same, "out_of_reach": oor, "los": los, "min_windows": mw, "min_wait_gap": wg, "flags": flags}


static func to_json(sch: Dictionary) -> Dictionary:
	var o := {"attacks": [], "waits": []}
	for e in sch["attacks"]:
		o["attacks"].append({"id": e["id"], "t0": snappedf(e["t0"], 0.001), "t1": snappedf(e["t1"], 0.001), "side": e["side"], "round": e.get("round", 0), "from": [snappedf(e["from"].x, 0.001), snappedf(e["from"].y, 0.001)]})
	for w in sch["waits"]:
		o["waits"].append({"id": w["id"], "pos": [snappedf(w["pos"].x, 0.001), snappedf(w["pos"].y, 0.001)], "dist": snappedf(w["dist"], 0.001), "side": w["side"], "arrive": snappedf(w["arrive"], 0.001)})
	return o
