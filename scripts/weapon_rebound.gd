## weapon_rebound.gd - PARRY REBOUND (ROADMAP I40). When two fighters' weapons meet (WeaponClash: CLASH or PARRY), the momentum they exchange
## at the contact, each weapon's change of angular velocity, and the deflection of both weapons and their wrists keyed over the next WINDOW
## seconds, decaying back to the authored motion. Static, no UI (weapon_rebound_ui.gd shows it; main.gd owns undo).
##
## THE BODIES  Each weapon is a rigid body that turns about its GRIP (WeightFeel.GRIP_U from the butt), with the inertia of I30
##   (WeaponTorque.profile: I_grip = m d^2 + m (k L)^2, the profile's own mass, centre of mass and radius of gyration). The wrist holds it
##   with an effective stiffness K_WRIST; the impact lasts a few ms, far shorter than the wrist's reaction (tens of ms), so DURING the impact
##   the grip is a pivot and the only impulses are the contact's J n and the grip's reaction.
## THE IMPACT  at the first touch: P_i = the weapon's closest point, r_i = P_i - grip_i, v_i = the clip's own velocity of P_i (240 Hz difference,
##   as WeaponClash measures it), n = the contact normal from A's closest point to B's (the weapons' surfaces' common normal). Closing speed
##   v_c = (v_A - v_B) . n. A pivoted body is pushed at P as a point of effective mass m_i = I_i / |r_i x n|^2, so with Newton's restitution
##   law (separation = e x approach)
##        J = (1 + e) v_c / (1/m_A + 1/m_B)         the impulse (N s): A gets -J n, B gets +J n
##        d_omega_A = -J (r_A x n) / I_A            d_omega_B = +J (r_B x n) / I_B        (rad/s, in the hero's space)
##   so for equal levers the two weapons' changes of angular velocity are in the INVERSE ratio of their inertias about the grips.
##   RESTITUTION E_REST = 0.5: a heuristic. Hard rods striking each other rebound with e of the order of 0.4-0.7 (steel on steel, wood on wood
##   are in that range; a baseball on a bat is about 0.5 at game speeds, Nathan 2000, Am. J. Phys. 68:979) and the arms' give in the first
##   milliseconds lowers it a little: one constant, stated, not fitted.
##   The grip's reaction impulse is J_g = m dv_com + (impulse on the weapon) with dv_com = d_omega x (com - grip); the ARM gets -J_g and its
##   velocity jumps by -J_g / M, M = the weapon + the forearm + the hand (Winter 2009 table 4.1: 1.6 % + 0.6 % of 75 kg body mass).
## THE WRIST  After the impact the wrist pulls the weapon back to the authored motion like a damped spring about the grip:
##        I theta'' + c theta' + K theta = 0,  theta(0) = 0, theta'(0) = d_omega,  K = K_WRIST,  c = 2 sqrt(K I)   (critical damping)
##   so theta(tau) = d_omega tau exp(-w_n tau), w_n = sqrt(K / I): a light weapon (small I) rebounds quickly and far, a heavy one slowly and
##   little (peak angle d_omega / (e w_n) goes as I^-1/2). The WRIST TORQUE of the parry is the angular impulse the wrist has to take, I |d_omega|,
##   over the time the wrist takes to give, the rise 1/w_n to the peak of the deflection: M = I w_n |d_omega| = sqrt(K I) |d_omega| (the mean
##   torque over the rise; the damper's instantaneous peak, 2 sqrt(K I) |d_omega|, is higher but lasts milliseconds and is carried by the
##   passive tissue, so it is not what the isometric maximum limits).
##   K_WRIST = 10 N m/rad is a HEURISTIC: voluntary wrist stiffness is of the order of 2-6 N m/rad (Charles & Hogan 2011; Formica 2012: recalled,
##   not re-read) and the forearm and the second hand add to it when the grip is braced.
## STOPPED DEAD  The parry took at least STOP_FRAC (half) of the weapon's angular speed (|d_omega| >= STOP_FRAC |omega|, the weapon was swinging:
##   its contact point faster than WeaponClash.STATIC) AND the wrist torque M is over WeaponTorque.WRIST_MAX (I30's isometric maximum): the arm
##   cannot give, it is a stop with no give.
## THE KEYS  Deflection d(tau) = (rotation d_omega g(tau) about the wrist, wrist shift dv g(tau)), g(tau) = tau exp(-w_n tau) x a cosine taper
##   over the last half of the WINDOW (the reflex returns the authored motion by then). Written as IK keys on the holding hand (Scene.ik,
##   LimbIK: target = the authored wrist + the shift, rot = the turn x the authored hand turn, weight 1 for the window, 0 either side), one key
##   every 1/KEY_HZ s, so the forearm and the arm follow by IK and the weapon (locked to the hand) turns with it.
class_name WeaponRebound
extends RefCounted

const E_REST := 0.5        # Newton's restitution coefficient (heuristic, see above)
const K_WRIST := 10.0      # N m/rad, effective stiffness of the wrist (+ forearm) holding the weapon (heuristic)
const WINDOW := 0.2        # s: the deflection lasts this long, then the authored motion is back
const TAPER_AT := 0.5      # fraction of the WINDOW at which the cosine taper to zero begins
const KEY_HZ := 60.0       # IK keys a second
const STOP_FRAC := 0.5     # the share of the weapon's angular speed a parry takes to count as a stop
const ARM_KG := (0.016 + 0.006) * 75.0   # forearm + hand (Winter 2009, 75 kg body)
const MIN_CLOSE := 0.05    # m/s: a contact that is not closing faster than this is a graze, nothing is exchanged


## the response of the wrist to an initial rate of 1 (rad/s or m/s), tau seconds after the impact: g(tau) with the taper
static func shape(tau: float, wn: float) -> float:
	if tau <= 0.0 or tau >= WINDOW:
		return 0.0
	var u := tau / WINDOW
	var tp := 1.0 if u <= TAPER_AT else 0.5 * (1.0 + cos(PI * (u - TAPER_AT) / (1.0 - TAPER_AT)))
	return tau * exp(-wn * tau) * tp


## the largest value of shape() over the window (per unit initial rate)
static func shape_peak(wn: float) -> float:
	var best := 0.0
	var n := 100
	for k in range(1, n):
		best = maxf(best, shape(WINDOW * float(k) / float(n), wn))
	return best


static func _tip(B: Body, name: String) -> Vector3:
	return B.wep_point(B.wep_len) if name == "weapon" else B.wep2_point(B.wep2_len())


static func _hand_of(B: Body, name: String) -> String:
	return B.wep_hand if name == "weapon" else B.wep2_hand


static func _kind_of(B: Body, name: String) -> String:
	return B.wep_kind if name == "weapon" else B.wep2_kind


## one weapon's side of the exchange. w: the weapon at the impact ({"a" knob, "b" tip, ...}), w0 / w1: the same half a sample before / after
static func _side(k: int, B: Body, name: String, w: Dictionary, w0: Dictionary, w1: Dictionary, pt: Vector3, vpt: Vector3, over: Dictionary) -> Dictionary:
	var kind := _kind_of(B, name)
	var prof := WeaponTorque.profile(kind, over.get("%d:%s" % [k, name], {}))
	if prof.is_empty():
		prof = WeaponTorque.profile(WeightFeel.REF_KIND, over.get("%d:%s" % [k, name], {}))
	var a: Vector3 = w["a"]
	var u := ((w["b"] as Vector3) - a).normalized()
	var grip := a + u * float(prof["grip"])
	var h := 1.0 / WeaponClash.SUB_HZ
	var u0 := ((w0["b"] as Vector3) - (w0["a"] as Vector3)).normalized()
	var u1 := ((w1["b"] as Vector3) - (w1["a"] as Vector3)).normalized()
	var omega := u.cross((u1 - u0) / h)   # the angular velocity perpendicular to the axis (the spin about the axis is ignored)
	return {"fighter": k, "weapon": name, "hand": _hand_of(B, name), "kind": kind, "prof": prof, "i": float(prof["i_grip"]), "mass": float(prof["mass"]),
		"grip": grip, "r": pt - grip, "v": vpt, "omega": omega, "u": u, "com": a + u * (float(prof["com"]) * a.distance_to(w["b"]))}


## the exchange at one WeaponClash event (CLASH or PARRY) of `fighters` ([{"name", "S", "xf"}]). `over`: {"<fighter>:<weapon>": profile override}
## ("what if this were 5 kg"). Returns {"ok", "why", "ev", "t", "n", "close" (m/s), "j" (N s), "e", "sides": [A, B]}; each side:
## {"fighter", "weapon", "hand", "kind", "prof", "i" (kg m2), "r" (m, the lever), "domega" (Vector3 rad/s), "omega" (rad/s before), "wn" (rad/s),
##  "dv" (Vector3 m/s, the wrist's jump), "angle" (deg, the largest deflection of the weapon), "shift" (m, the largest wrist shift),
##  "torque" (N m), "lost" (share of the angular speed taken), "swinging", "dead" (stopped dead)}
static func analyze(fighters: Array, ev: Dictionary, over := {}) -> Dictionary:
	var res := {"ok": false, "why": "", "ev": ev, "t": float(ev["t"]), "e": E_REST}
	var i := int(ev["a"])
	var j := int(ev["b"])
	var na: String = ev["wa"]
	var nb: String = ev["wb"]
	var t := float(ev["t"])
	var h := 1.0 / WeaponClash.SUB_HZ
	var bodies := []
	for f in fighters:
		bodies.append(Choreo._body())
	var p0 := WeaponClash._poses_pair(fighters, bodies, i, j, t - 0.5 * h)
	var p1 := WeaponClash._poses_pair(fighters, bodies, i, j, t + 0.5 * h)
	var pm := WeaponClash._poses_pair(fighters, bodies, i, j, t)
	var wa := WeaponClash.named(pm[0], na)
	var wb := WeaponClash.named(pm[1], nb)
	if wa.is_empty() or wb.is_empty():
		res["why"] = "the weapons are not there at this time: run 'Parry rebound' again"
		return res
	var c := WeaponClash._contact(fighters, bodies, i, j, na, nb, t)
	var sp := WeaponClash._speeds(fighters, bodies, i, j, na, nb, t)
	if not bool(c["ok"]) or not sp.has("vav"):
		res["why"] = "no contact at this time"
		return res
	var pa: Vector3 = c["pa"]
	var pb: Vector3 = c["pb"]
	var n := pb - pa
	if n.length() < 1e-5:
		n = ((wa["b"] as Vector3) - (wa["a"] as Vector3)).cross((wb["b"] as Vector3) - (wb["a"] as Vector3))
		if n.dot((sp["vav"] as Vector3) - (sp["vbv"] as Vector3)) < 0.0:
			n = -n
	n = n.normalized()
	var close := ((sp["vav"] as Vector3) - (sp["vbv"] as Vector3)).dot(n)
	res["n"] = n
	res["close"] = close
	if close < MIN_CLOSE:
		res["why"] = "the weapons are not closing at the contact (%.2f m/s): a graze, nothing is exchanged" % close
		return res
	var A := _side(i, bodies[i], na, wa, WeaponClash.named(p0[0], na), WeaponClash.named(p1[0], na), pa, sp["vav"], over)
	var B := _side(j, bodies[j], nb, wb, WeaponClash.named(p0[1], nb), WeaponClash.named(p1[1], nb), pb, sp["vbv"], over)
	var ra: Vector3 = A["r"]
	var rb: Vector3 = B["r"]
	var ka := (ra.cross(n)).length_squared() / float(A["i"])   # 1 / the effective mass at the contact
	var kb := (rb.cross(n)).length_squared() / float(B["i"])
	if ka + kb < 1e-9:
		res["why"] = "the contact is at the grip: it cannot turn the weapon"
		return res
	var J := (1.0 + E_REST) * close / (ka + kb)
	A["domega"] = -J * ra.cross(n) / float(A["i"])
	B["domega"] = J * rb.cross(n) / float(B["i"])
	for s in [A, B]:
		var d: Vector3 = s["domega"]
		var com_v := d.cross((s["com"] as Vector3) - (s["grip"] as Vector3))   # the centre of mass's jump
		var imp: Vector3 = (-J * n) if s == A else (J * n)
		var jg: Vector3 = float(s["mass"]) * com_v - imp   # the grip's reaction on the weapon; the arm gets the opposite
		s["dv"] = -jg / (float(s["mass"]) + ARM_KG)
		s["wn"] = sqrt(K_WRIST / float(s["i"]))
		var gp := shape_peak(float(s["wn"]))
		s["angle"] = rad_to_deg(d.length() * gp)
		s["shift"] = (s["dv"] as Vector3).length() * gp
		s["torque"] = sqrt(K_WRIST * float(s["i"])) * d.length()
		var om: float = (s["omega"] as Vector3).length()
		s["swinging"] = om * (s["r"] as Vector3).length() >= WeaponClash.STATIC
		s["lost"] = d.length() / maxf(om, 1e-6)
		s["dead"] = bool(s["swinging"]) and float(s["lost"]) >= STOP_FRAC and float(s["torque"]) > WeaponTorque.WRIST_MAX
		s["omega_after"] = ((s["omega"] as Vector3) + d).length()
	res["j"] = J
	res["sides"] = [A, B]
	res["ok"] = true
	return res


## the CLASH / PARRY events of the fighters' scenes, each analysed: [analysis]; PASS-THROUGH events are not an impact (they are a mistake to fix first)
static func scan(fighters: Array, over := {}) -> Array:
	var out := []
	if fighters.size() < 2:
		return out
	var fps := float((fighters[0]["S"] as Scene).fps)
	for ev in WeaponClash.scan(fighters, fps):
		if String(ev["kind"]) == "PASS-THROUGH":
			continue
		var r := analyze(fighters, ev, over)
		if bool(r["ok"]):
			out.append(r)
	return out


## the IK keys that carry the deflection of one side: {"fighter", "hand", "keys": [LimbIK key], "clash": bool} or {} when the side cannot be keyed.
## Fills side["why"] (a reason) when it is skipped
static func keys_of(fighters: Array, an: Dictionary, side: int) -> Dictionary:
	var s: Dictionary = an["sides"][side]
	var k: int = s["fighter"]
	var hand: String = s["hand"]
	if hand == "":
		s["why"] = "its weapon is not in a hand (free): there is no wrist to deflect"
		return {}
	var S: Scene = fighters[k]["S"]
	var xf: Transform3D = fighters[k]["xf"]
	var inv := xf.basis.inverse()
	var t0 := float(an["t"])
	for q in S.ik.get(hand, []):
		if float(q["t"]) > t0 - 0.5 and float(q["t"]) < t0 + WINDOW + 0.5:
			s["why"] = "its %s already has IK keys here (%.2f s): release them first, or the rebound would fight them" % [hand, float(q["t"])]
			return {}
	var B := Choreo._body()
	var dw: Vector3 = inv * (s["domega"] as Vector3)
	var dv: Vector3 = inv * (s["dv"] as Vector3)
	var wn: float = s["wn"]
	var keys := []
	var n := int(round(WINDOW * KEY_HZ))
	for q in range(-1, n + 2):
		var tt := t0 + float(q) / KEY_HZ
		S.apply(B, maxf(0.0, tt))
		var on := q >= 0 and q <= n
		var g := shape(float(q) / KEY_HZ, wn) if on else 0.0
		var rotv := dw * g
		var rq := Quaternion.IDENTITY
		if rotv.length() > 1e-9:
			rq = Quaternion(rotv.normalized(), rotv.length())
		keys.append({"t": snappedf(tt, 0.0001), "target": (B.P[hand] as Vector3) + dv * g, "pole": LimbIK.pole_from_pose(B, hand),
			"w": 1.0 if on else 0.0, "rot": (rq * (B.G[hand] as Quaternion)).normalized()})
	return {"fighter": k, "hand": hand, "keys": keys}


## the keys of both sides of an analysis: [{"fighter", "hand", "keys"}] (a side that cannot be keyed is left out, with its "why")
static func plan(fighters: Array, an: Dictionary) -> Array:
	var out := []
	for side in 2:
		var kk := keys_of(fighters, an, side)
		if not kk.is_empty():
			out.append(kk)
	return out


## the keys written into the scenes of `scenes` (index = fighter number): LimbIK.put, so a key within a millisecond of another replaces it
static func write(scenes: Array, pl: Array) -> void:
	for p in pl:
		var S: Scene = scenes[int(p["fighter"])]
		for q in p["keys"]:
			LimbIK.put(S.ik, String(p["hand"]), (q as Dictionary).duplicate(true))


## the clones of the fighters with the plan written: [{"name", "S", "xf"}] (the scenes in `fighters` are not touched)
static func with_plan(fighters: Array, pl: Array) -> Array:
	var out := fighters.map(func(f): return {"name": f["name"], "S": (f["S"] as Scene).clone(), "xf": f["xf"]})
	write(out.map(func(f): return f["S"]), pl)
	return out


## the weapon tip's path (hero space) of one fighter's weapon from t0 to t1, at KEY_HZ
static func tip_path(fighters: Array, k: int, name: String, t0: float, t1: float) -> Array:
	var B := Choreo._body()
	var S: Scene = fighters[k]["S"]
	var xf: Transform3D = fighters[k]["xf"]
	var out := []
	var n := int(ceil((t1 - t0) * KEY_HZ))
	for q in n + 1:
		S.apply(B, maxf(0.0, t0 + float(q) / KEY_HZ))
		out.append(xf * _tip(B, name))
	return out


## the deflection arcs of an analysis: [{"fighter", "weapon", "authored": [Vector3], "deflected": [Vector3]}] over the window (+ a lead-in)
static func arcs(fighters: Array, an: Dictionary, pl: Array) -> Array:
	var after := with_plan(fighters, pl)
	var t0 := float(an["t"]) - 0.1
	var t1 := float(an["t"]) + WINDOW + 0.1
	var out := []
	for s in an["sides"]:
		out.append({"fighter": s["fighter"], "weapon": s["weapon"], "authored": tip_path(fighters, int(s["fighter"]), String(s["weapon"]), t0, t1),
			"deflected": tip_path(after, int(s["fighter"]), String(s["weapon"]), t0, t1)})
	return out


## the angle (deg) between the weapon's axis in the authored motion and with the plan, the largest over the window: the deflection as the IK plays it
static func measured_angle(fighters: Array, pl: Array, k: int, name: String, t0: float) -> Array:   # [deg, t, tip shift (m)]
	var after := with_plan(fighters, pl)
	var B0 := Choreo._body()
	var B1 := Choreo._body()
	var best := 0.0
	var tb := t0
	var sh := 0.0
	var n := int(round(WINDOW * KEY_HZ))
	for q in range(0, n + 1):
		var tt := t0 + float(q) / KEY_HZ
		(fighters[k]["S"] as Scene).apply(B0, tt)
		(after[k]["S"] as Scene).apply(B1, tt)
		var a0: Vector3 = (_tip(B0, name) - (B0.wep_point(0.0) if name == "weapon" else B0.wep2_point(0.0))).normalized()
		var a1: Vector3 = (_tip(B1, name) - (B1.wep_point(0.0) if name == "weapon" else B1.wep2_point(0.0))).normalized()
		var ang := rad_to_deg(a0.angle_to(a1))
		if ang > best:
			best = ang
			tb = tt
			sh = _tip(B0, name).distance_to(_tip(B1, name))
	return [best, tb, sh]


static func describe(an: Dictionary) -> String:
	var ev: Dictionary = an["ev"]
	var bits := []
	for si in 2:
		var s: Dictionary = an["sides"][si]
		var tag := "A" if si == 0 else "B"
		bits.append("%s: turns %.1f rad/s, deflects %.1f deg, wrist %.1f cm" % [tag, (s["domega"] as Vector3).length(), float(s["angle"]), 100.0 * float(s["shift"])])
	return "%s at %.2f s, closing %.1f m/s, impulse %.2f N s (e = %.1f).  %s" % [String(ev["kind"]), float(an["t"]), float(an["close"]), float(an["j"]), E_REST, "  |  ".join(bits)]
