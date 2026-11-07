## body_limits.gd - N030 JUMP BUDGET and N032 GRIP HOLD CHECK. Both are READ-ONLY: they play the clip (scene and body restored), change nothing, add no undo step.
##
## JUMP BUDGET  What the legs must give to start a jump. From the COM at 60 Hz: the FLIGHT is a run of >= FLIGHT_MIN frames whose vertical
##   acceleration (second difference) is -g within 20 %; the TAKE-OFF is the frame before it, and only counts as a jump if the COM is going UP
##   there (> UP_MIN m/s; a drop is not a jump). The PUSH starts at the COM's lowest point in the second before take-off. With the apex rise h
##   above the take-off height, the rise d during the push and its time t:   work = m g h (kinetic energy at take-off) + m g d (height gained
##   while pushing),   mean push power = m g (h + d) / t   (d = 0 gives the plain m g h / t).
##   NORM: Lin, Goldstein & Schroeder 2025, Sports 13(9):292 (doi 10.3390/sports13090292), Table 2, 38 NCAA Division I men, CMJ force plate:
##   relative concentric MEAN power 29.72 +- 4.00 W/kg. ratio = need / 29.72 ("x an elite vertical jump"); FLAGGED above mean + 2 SD = 37.72 W/kg.
##   (A mean over the push, not the instantaneous peak, because the COM track gives work over time.) Body mass defaults to 75 kg (WeaponTorque.BODY_KG).
## GRIP HOLD  The force a swing puts on the hand is that of the weapon's centre of mass: F = m |a_com| (the centripetal m w^2 r plus the tangential
##   m alpha r as vectors; gravity left out like I30). A hand holds a handle by friction, so the squeeze needed is F / MU (MU = DisarmTruth.MU 0.8).
##   NORM: Dodds et al. 2014, PLoS ONE 9(12):e113637 (doi 10.1371/journal.pone.0113637), peak median grip: men 51 kg = 500.2 N, women 31 kg = 304.0 N.
##   The first frame where the squeeze needed passes the norm is the SLIP frame.
class_name BodyLimits
extends RefCounted

const FPS := 60.0
const G := 9.81
const FLIGHT_TOL := 0.20      # |a + g| under this x g counts as free flight (HEURISTIC)
const FLIGHT_MIN := 6         # frames (0.1 s) of free flight before it is a jump
const UP_MIN := 0.5           # m/s upward at take-off
const BACK_S := 1.0           # s before take-off in which the lowest point is looked for
const ELITE_MEAN := 29.72     # W/kg, Lin 2025 Table 2, men, relative concentric mean power
const ELITE_SD := 4.00
const ELITE_HI := ELITE_MEAN + 2.0 * ELITE_SD   # 37.72
const GRIP_N := {"male": 51.0 * 9.80665, "female": 31.0 * 9.80665}   # Dodds 2014 peak medians
const MU := 0.8               # = DisarmTruth.MU


## jump_budget over a COM track (Array of Vector3 at 60 Hz)
static func jump_budget(com: Array, mass := WeaponTorque.BODY_KG) -> Dictionary:
	var n := com.size()
	var res := {"ok": true, "jump": false, "flag": false, "mass": mass, "msg": "no jump (the COM never leaves the ground in free flight)"}
	if n < 3 * FLIGHT_MIN:
		return res
	var flag := []
	flag.resize(n)
	flag.fill(false)
	for q in range(1, n - 1):
		var a := ((com[q + 1] as Vector3).y - 2.0 * (com[q] as Vector3).y + (com[q - 1] as Vector3).y) * FPS * FPS
		flag[q] = absf(a + G) < FLIGHT_TOL * G
	var i := 1
	while i < n - 1:
		if not flag[i]:
			i += 1
			continue
		var j := i
		while j + 1 < n - 1 and flag[j + 1]:
			j += 1
		if j - i + 1 >= FLIGHT_MIN:
			var take := i - 1
			var vy := ((com[mini(take + 1, n - 1)] as Vector3).y - (com[maxi(take - 1, 0)] as Vector3).y) * 0.5 * FPS
			if vy > UP_MIN and take >= 1:
				return _jump(com, mass, take, j + 1)
		i = j + 1
	return res


static func _jump(com: Array, mass: float, take: int, end_f: int) -> Dictionary:
	var lo := maxi(0, take - int(BACK_S * FPS))
	var start := lo
	var ymin := 1e30
	for k in range(lo, take + 1):
		var y: float = (com[k] as Vector3).y
		if y <= ymin + 1e-6:
			start = k
			ymin = minf(ymin, y)
	var apex := -1e30
	for k in range(take, mini(end_f, com.size() - 1) + 1):
		apex = maxf(apex, (com[k] as Vector3).y)
	var y1: float = (com[take] as Vector3).y
	var h := apex - y1
	var d := y1 - ymin
	var t := float(take - start) / FPS
	var res := {"ok": true, "jump": false, "flag": false, "mass": mass, "msg": "no jump (no push before the flight)"}
	if t <= 0.0:
		return res
	var p := mass * G * (h + d) / t
	var wkg := p / mass
	var ratio := wkg / ELITE_MEAN
	res.merge({"jump": true, "apex_h": h, "rise_push": d, "t_push": t, "power_w": p, "w_per_kg": wkg, "ratio": ratio, "push_start": start, "takeoff": take,
		"flag": wkg > ELITE_HI, "elite_mean": ELITE_MEAN, "elite_hi": ELITE_HI}, true)
	res["msg"] = "this jump needs %.1fx an elite vertical jump (%.1f W/kg over the %.2f s push, elite mean %.1f, top of the range %.1f)%s; push frames %d..%d, apex %.2f m" % [
		ratio, wkg, t, ELITE_MEAN, ELITE_HI, " - FLAG: beyond what legs give" if res["flag"] else "", start, take, h]
	return res


## grip_hold over the weapon's COM track (Array of Vector3 at 60 Hz)
static func grip_hold(com: Array, mass: float, sex := "male") -> Dictionary:
	var norm: float = GRIP_N.get(sex, GRIP_N["male"])
	var peak := 0.0
	var pk := -1
	var slip := -1
	for i in range(1, com.size() - 1):
		var a: Vector3 = ((com[i + 1] as Vector3) - 2.0 * (com[i] as Vector3) + (com[i - 1] as Vector3)) * FPS * FPS
		var f := mass * a.length()
		if f > peak:
			peak = f
			pk = i
		if slip < 0 and f / MU > norm:
			slip = i
	var need := peak / MU
	var res := {"ok": true, "has_weapon": true, "mass": mass, "peak_n": peak, "peak_frame": pk, "grip_need_n": need, "norm_n": norm, "sex": sex,
		"ratio": need / norm, "slip": slip >= 0, "slip_frame": slip}
	res["msg"] = "the swing pulls %.0f N on the hand at frame %d: a squeeze of %.0f N is needed (friction %.1f), the %s grip norm is %.0f N (%.2fx)%s" % [
		peak, pk, need, MU, sex, norm, need / norm, ("; SLIPS at frame %d" % slip) if slip >= 0 else "; holds"]
	return res


## the COM and the held weapon's COM at 60 Hz (the clip is played and the body restored)
static func scene_series(S: Scene, B: Body) -> Dictionary:
	var keep: Dictionary = B.state()
	var was := S.stepped
	S.stepped = false
	var n := int(ceil(S.length() * FPS)) + 1
	var com := []
	var wc := []
	var mass := 0.0
	for i in n:
		S.apply_true(B, i / FPS)
		B.fk()
		com.append(Balance.com(B))
		if B.wep_on and Body.KINDS.has(B.wep_kind):
			var k: Dictionary = Body.KINDS[B.wep_kind]
			mass = float(k["mass"])
			wc.append(B.wep_point(0.0) + B.wep_axis() * (float(k["com"]) * B.wep_len))
		else:
			wc.append(null)
	S.stepped = was
	B.set_state(keep)
	return {"com": com, "wcom": wc, "wmass": mass}


static func serve(tool: String, m: Variant, p: Dictionary) -> Dictionary:
	var mass := float(p.get("mass", WeaponTorque.BODY_KG))
	if tool == "grip_hold" and p.has("omega") and p.has("radius"):
		var w := float(p["omega"])
		var r := float(p["radius"])
		var f := mass * w * w * r
		var norm: float = GRIP_N.get(String(p.get("sex", "male")), GRIP_N["male"])
		return {"ok": true, "result": {"force_n": f, "grip_need_n": f / MU, "norm_n": norm, "slip": f / MU > norm,
			"msg": "m w^2 r = %.1f N; squeeze needed %.0f N vs norm %.0f N" % [f, f / MU, norm]}}
	var S: Scene = m.S
	var B: Body = m.B
	var ser := scene_series(S, B)
	if tool == "jump_budget":
		return {"ok": true, "result": jump_budget(ser["com"], mass)}
	if tool == "grip_hold":
		var wc: Array = ser["wcom"]
		if float(ser["wmass"]) <= 0.0:
			return {"ok": true, "result": {"has_weapon": false, "slip": false, "msg": "no weapon held in this clip"}}
		var first: Vector3 = Vector3.ZERO
		for v in wc:
			if v != null:
				first = v
				break
		var track := []
		for v in wc:
			track.append(v if v != null else first)
		return {"ok": true, "result": grip_hold(track, float(ser["wmass"]), String(p.get("sex", "male")))}
	return {"ok": false, "error": "unknown tool"}
