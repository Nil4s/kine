## disarm_truth.gd - DISARM TRUTH (INNOVATIONS N045). A disarm works only when the lever on the wrist beats the grip.
##   T = force_n * lever_m           torque the strike puts on the weapon about the holding hand(s) (lever = palm to the point struck, from the grip book: tip distance).
##   hold = hands * MU * grip_n * r  what the grip resists: friction MU x grip force x the handle radius, per hand (r = Body.KINDS[kind].r_handle).
##   wrist = T / hands               what each wrist carries; WRIST_FAIL_NM is where it gives.
## Verdict: T <= hold -> "grip holds"; else wrist >= WRIST_FAIL_NM -> "wrist breaks first"; else "works". Monotone in the lever arm by construction.
## Approximations (stated): MU 0.8 leather on wood; WRIST_FAIL_NM 30 Nm is the order of the loaded-wrist injury range, not a measured tolerance;
## a static torque balance (no impulse, no wet grip, no thumb leverage). Grip force default 400 N = an adult male mean grip (Mathiowetz 1985).
class_name DisarmTruth
extends RefCounted

const MU := 0.8
const WRIST_FAIL_NM := 30.0
const GRIP_N := 400.0
const V_HOLD := "grip holds"
const V_WORKS := "works"
const V_BREAK := "wrist breaks first"


static func judge(p: Dictionary) -> Dictionary:
	var kind := String(p.get("kind", "katana"))
	var hands := int(p.get("hands", 1))
	var lever := float(p.get("lever_m", -1.0))
	if p.has("grip"):
		var g := GripBook.find(kind, String(p["grip"]))
		if g.is_empty():
			return {"ok": false, "msg": "no grip '%s' in the grip book for '%s'" % [p["grip"], kind]}
		hands = (g["hands"] as Array).size()
		if lever < 0.0 and Body.KINDS.has(kind):
			var u := float(g["hands"][0].get("u", 0.0))
			lever = maxf(0.0, float(Body.KINDS[kind]["len"]) - u)
	if lever < 0.0:
		return {"ok": false, "msg": "lever_m (palm to the point struck, m) or a book grip is needed"}
	var r := float(p.get("r_handle", float(Body.KINDS[kind]["r_handle"]) if Body.KINDS.has(kind) else 0.016))
	var force := float(p.get("force_n", 80.0))
	var gn := float(p.get("grip_n", GRIP_N))
	hands = maxi(1, hands)
	var t := force * lever
	var hold := hands * MU * gn * r
	var wrist := t / hands
	var v := V_HOLD if t <= hold else (V_BREAK if wrist >= WRIST_FAIL_NM else V_WORKS)
	return {"ok": true, "verdict": v, "torque_nm": t, "hold_nm": hold, "wrist_nm_per_hand": wrist, "wrist_fail_nm": WRIST_FAIL_NM, "hands": hands, "lever_m": lever, "force_n": force, "grip_n": gn,
		"say": "%s: %.1f Nm on the wrist lever vs the grip's %.1f Nm (%d hand%s), %.1f Nm per wrist" % [v, t, hold, hands, "" if hands == 1 else "s", wrist]}
