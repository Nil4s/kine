## force_view.gd - FORCE VIEW (docs/ROADMAP.md I8). Inverse dynamics of the played clip, read-only: nothing here edits the
## scene, the body or the undo history.
##
## SAMPLING: the clip is played with the app's own evaluation (Scene.apply_true) at HZ = 120 per second; the rigid pieces
## (HitReaction.pieces: de Leva 1996 masses, COM fractions and radii of gyration, the body's own mass, trunk in 5 pieces)
## give their centre c(t) and orientation G(t) at every sample.
## NEWTON-EULER, per joint j, over the pieces distal to j (those whose joint has j in its chain to the pelvis):
##     M_j = sum_p [ (c_p - P_j) x m_p (a_p - g) + I_p alpha_p ]  (- (x_cop - P_j) x F_foot   on the leg joints)
## a = second central difference of c, alpha = central difference of the angular velocity of G (spin included),
## I = m (k L)^2 about the piece's COM (isotropic: the gyroscopic term w x I w is dropped; stated). A held bat is one more
## piece shared between the hands that hold it (an equal split when two do, as HumanLimits.bat_share).
## GROUND (I8c, bottom-up): F = sum_all m (a - g), the whole body's momentum change, bat included. A foot can only push and
## not slide: F_y >= 0 and |F_h| <= MU F_y; what it cannot give is the OUTSIDE FORCE (resid = sum m (a - g) - F used, the force the
## pelvis would need from outside; zero for a real body, shown as a red "needs outside force" badge from NEED_BW body weights).
## The centre of pressure comes from the angular momentum rate about the COM, (x_cop - com) x F = sum (c - com) x m a + sum I alpha
## (horizontal parts), held inside the feet (the hull of the two footprints); what that cannot give is resid_tau. The force is
## split between the feet by the lever rule along the line joining their footprint centres. The leg joints (hip, knee, ankle)
## recurse bottom-up from the feet with this ground force; the spine, neck, arms recurse top-down from their free ends. The
## pelvis is where they meet, so resid is exactly the pelvis's unexplained force. (Before I8c the root was kinematic: F_y < 0
## zeroed the ground force, so combo3 3.05 s read lumbar 4122 Nm beside knee 31 Nm; the clip is a 0.16 s card move, 0.65 m of head
## travel, that no body can do without outside help.)
##
## LIMITS (colour = |M_j| / limit): green < 0.5, yellow < 1.0, red >= 1.0. LIMIT_NM is a STRONG young man's maximum
## voluntary joint torque, Nm at 75 kg, scaled linearly with body mass (mine). The order of magnitude follows Anderson,
## Madigan & Nussbaum 2007 (J Biomech 40:3105, maximum voluntary lower-limb torques by joint angle and velocity: hip
## extension, knee extension and ankle plantar flexion all of the order 100-250 Nm in young men) and NASA-STD-3000 vol. 1
## sec. 4 / Stobbe 1982 (NASA RP-1108, upper-body strength). THE ROUNDED VALUES BELOW ARE MINE: the tables were not
## opened (the Anderson PDF reachable here was another paper), so read the colours as "of the order of a strong person's
## best", not a clinical limit.
##
## POWER CHAIN: the angular speed of the pelvis (hip), spine_03 (trunk), upper arm (shoulder) and forearm (elbow) of the
## striking side; the textbook signature of a good strike is that their PEAKS come in that order, proximal to distal
## (Putnam 1993, J Biomech 26 Suppl 1:125, "Sequential motions of body segments in striking and throwing skills").
## The window is the 0.8 s up to the tip's peak speed (the swing); each peak is read on a 3-sample mean.
class_name ForceView
extends RefCounted

const HZ := 120.0
const GRAV := 9.81
const REF_MASS := 75.0
const TOUCH := 0.02
const WINDOW := 0.8      # s before the tip's peak speed in which the chain's peaks are looked for
const AFTER := 0.05      # s after it
const TIE := 1.0         # samples: peaks this close count as simultaneous (the order holds)
## Nm for a 75 kg strong young man, by joint kind (see the header: mine, order of magnitude from Anderson 2007 / NASA)
const LIMIT_NM := {"thigh": 250.0, "calf": 250.0, "foot": 150.0, "spine_01": 250.0, "spine_02": 200.0, "spine_03": 150.0,
	"neck_01": 50.0, "head": 40.0, "upperarm": 120.0, "lowerarm": 80.0, "hand": 25.0}
const GREEN_BELOW := 0.5
const YELLOW_BELOW := 1.0
const MU := 1.0          # friction cone: |F_horizontal| <= MU F_vertical (shoe on floor; mine, 0.6-1.0 is the usual range)
const NEED_BW := 0.15    # the outside force the motion needs, in body weights, from which the red "needs outside force" badge shows (mine)
const CHAIN := ["hip", "trunk", "shoulder", "elbow"]
const CHAIN_JOINT := {"hip": "pelvis", "trunk": "spine_03", "shoulder": "upperarm", "elbow": "lowerarm"}
const SPINE := ["spine_01", "spine_02", "spine_03", "neck_01", "head"]


static func kind_of(j: String) -> String:
	return j.trim_suffix("_l").trim_suffix("_r")


## the torque joints of a body: the spine, neck, head, and per side the arm and leg joints
static func joints() -> Array:
	var out: Array = SPINE.duplicate()
	for sd in ["_l", "_r"]:
		for k in ["upperarm", "lowerarm", "hand", "thigh", "calf", "foot"]:
			out.append(k + sd)
	return out


static func limit_nm(j: String, mass: float) -> float:
	return float(LIMIT_NM[kind_of(j)]) * mass / REF_MASS


## 0 green, 1 yellow, 2 red
static func band(ratio: float) -> int:
	return 0 if ratio < GREEN_BELOW else (1 if ratio < YELLOW_BELOW else 2)


static func band_col(ratio: float) -> Color:
	return Tok.c(["fv_ok", "fv_mid", "fv_hot"][band(ratio)])


# ---------------------------------------------------------------- numerics

## world angular velocity (rad/s) of a quaternion track, central difference
static func _omega(q: Array, n: int) -> Array:
	var w := []
	for i in n:
		var a: int = maxi(i - 1, 0)
		var b: int = mini(i + 1, n - 1)
		var dt := maxf(float(b - a) / HZ, 1e-9)
		var dq: Quaternion = (q[b] as Quaternion) * (q[a] as Quaternion).inverse()
		if dq.w < 0.0:
			dq = Quaternion(-dq.x, -dq.y, -dq.z, -dq.w)
		var v := Vector3(dq.x, dq.y, dq.z)
		var s := v.length()
		w.append(Vector3.ZERO if s < 1e-9 else v / s * (2.0 * atan2(s, dq.w)) / dt)
	return w


static func _ddt(v: Array, n: int) -> Array:
	var out := []
	for i in n:
		var a: int = maxi(i - 1, 0)
		var b: int = mini(i + 1, n - 1)
		out.append(((v[b] as Vector3) - (v[a] as Vector3)) / maxf(float(b - a) / HZ, 1e-9))
	return out


static func _accel(c: Array, n: int) -> Array:
	var a := []
	for i in n:
		var c0: Vector3 = c[maxi(i - 1, 0)]
		var c2: Vector3 = c[mini(i + 1, n - 1)]
		a.append((c2 - 2.0 * (c[i] as Vector3) + c0) * HZ * HZ)
	return a


## angular acceleration of the direction p -> d (a rod; its spin cannot be seen from its ends)
static func _alpha_dir(p: Array, d: Array, n: int) -> Array:
	var u := []
	for i in n:
		var v: Vector3 = (d[i] as Vector3) - (p[i] as Vector3)
		u.append(v.normalized() if v.length() > 1e-9 else Vector3.UP)
	var du := _ddt(u, n)
	var w := []
	for i in n:
		w.append((u[i] as Vector3).cross(du[i] as Vector3))
	return _ddt(w, n)


static func _smooth(s: Array) -> Array:
	var out := []
	for i in s.size():
		out.append((float(s[maxi(i - 1, 0)]) + float(s[i]) + float(s[mini(i + 1, s.size() - 1)])) / 3.0)
	return out


# ---------------------------------------------------------------- the clip

## the clip played at HZ with the app's evaluation: the pieces' centres and orientations, joint points, feet, bat, tips. Poses B
## at the clip's last sample. {} for fewer than 2 cards. THIS is the slow part (Scene.apply, milliseconds a call)
## the whole clip from its capture: {"hz", "n", "t", "mass", "tau": {joint: [Nm per sample]}, "ratio": {joint: [tau / limit]}, "grf": [Vector3],
## "down": [[sides]], "chain": the power chain (chain_of)}. Poses B at the clip's last sample. {} for fewer than 2 cards.
static func capture(S: Scene, B: Body) -> Dictionary:
	if S.cards.size() < 2:
		return {}
	var n := int(ceil(S.length() * HZ)) + 1
	var was := S.stepped
	S.stepped = false
	var mass := HumanLimits.mass_of(B)
	var cs := []     # per sample: the pieces' centres
	var gs := []     # per sample: the pieces' owner orientations
	var ps := []     # per sample: {joint: P}
	var feet := []   # per sample: {"_l": cop or null, "_r": ...}
	var fbox := []   # per sample: {"_l": Rect2 of the footprint (x, z) or null, ...}
	var bat := []    # per sample: null or {"c", "knob", "tip", "hand"}
	var tips := []   # per sample: {"_l": E hand, "_r": E hand}
	var pcs0: Array = []
	var jl := joints()
	var gj := {"pelvis": 1, "spine_03": 1, "upperarm_l": 1, "upperarm_r": 1, "lowerarm_l": 1, "lowerarm_r": 1}
	var gtrack := {}
	var us_all := []
	for k in gj:
		gtrack[k] = []
	var mk := func(_i: int, t: float) -> Dictionary:
		FrameMemo.pose(S, B, t)
		var pcs := HitReaction.pieces(B)
		var c := []
		var g := []
		var us := []
		for p in pcs:
			c.append(p["c"])
			g.append(B.G[p["j"]])
			us.append(p["u"])
		var pj := {}
		for j in jl:
			pj[j] = B.P[j]
		var fe := {}
		var fb := {}
		for sd in ["_l", "_r"]:
			fe[sd] = _cop(B, sd)
			fb[sd] = _fbox(B, sd)
		var bt = null
		if B.wep_on and B.wep_hand != "":
			bt = {"c": B.wep_point(HumanLimits.BAT_COM * B.wep_len), "knob": B.wep_point(0.0), "tip": B.wep_point(B.wep_len),
				"hand": B.wep_hand, "grip": B.grip, "m": float(HitReaction.WEAPON_KG.get(B.wep_kind, HumanLimits.BAT_KG)), "L": B.wep_len}
		var gt := {}
		for k in gtrack:
			gt[k] = B.G[k]
		return {"pcs": pcs, "c": c, "g": g, "us": us, "pj": pj, "fe": fe, "fb": fb, "bat": bt, "tip": {"_l": B.E["hand_l"], "_r": B.E["hand_r"]}, "gt": gt}
	var recs: Array = FrameMemo.frames("fv", S, B, n, HZ, mk)
	for i in n:
		var r: Dictionary = recs[i]
		if i == 0:
			pcs0 = r["pcs"]
		cs.append(r["c"])
		us_all.append(r["us"])
		gs.append(r["g"])
		ps.append(r["pj"])
		feet.append(r["fe"])
		fbox.append(r["fb"])
		bat.append(r["bat"])
		tips.append(r["tip"])
		for k in gtrack:
			gtrack[k].append(r["gt"][k])
	var chains := {}
	for p in pcs0:
		chains[p["j"]] = HitReaction.chain(B, String(p["j"]))
	for h in ["hand_l", "hand_r"]:
		chains[h] = HitReaction.chain(B, h)
	S.stepped = was
	var cap := {"n": n, "mass": mass, "cs": cs, "gs": gs, "ps": ps, "feet": feet, "fbox": fbox, "bat": bat, "tips": tips, "pcs0": pcs0, "us": us_all,
		"chains": chains, "gtrack": gtrack}
	return cap


## the clip from a capture(): the app's evaluation is paid once (capture), this is arithmetic on the samples
static func sample(S: Scene, B: Body) -> Dictionary:
	var tk := Time.get_ticks_usec()
	var cap := capture(S, B)
	FrameMemo.tick("fv capture total", tk)
	tk = Time.get_ticks_usec()
	var r := {} if cap.is_empty() else dynamics(cap)
	FrameMemo.tick("fv dynamics", tk)
	return r


static func dynamics(cap: Dictionary) -> Dictionary:
	var n: int = cap["n"]
	var mass: float = cap["mass"]
	var cs: Array = cap["cs"]
	var gs: Array = cap["gs"]
	var ps: Array = cap["ps"]
	var feet: Array = cap["feet"]
	var bat: Array = cap["bat"]
	var tips: Array = cap["tips"]
	var pcs0: Array = cap["pcs0"]
	var chains: Dictionary = cap["chains"]
	var gtrack: Dictionary = cap["gtrack"]
	var jl := joints()
	var np := pcs0.size()
	# per piece: acceleration and angular acceleration tracks
	var acc := []
	var alp := []
	for k in np:
		var ck := []
		var gk := []
		for i in n:
			ck.append(cs[i][k])
			gk.append(gs[i][k])
		acc.append(_accel(ck, n))
		alp.append(_ddt(_omega(gk, n), n))
	var bat_acc := []
	var bat_alp := []
	if bat.any(func(b): return b != null):
		# a weapon that is held on some samples only: the samples without it carry no load
		var bc := []
		var kn := []
		var tp := []
		for i in n:
			var b = bat[i]
			bc.append(b["c"] if b != null else Vector3.ZERO)
			kn.append(b["knob"] if b != null else Vector3.ZERO)
			tp.append(b["tip"] if b != null else Vector3.UP)
		bat_acc = _accel(bc, n)
		bat_alp = _alpha_dir(kn, tp, n)
	var out := {"hz": HZ, "n": n, "t": [], "mass": mass, "tau": {}, "ratio": {}, "grf": [], "down": []}
	for i in n:
		out["t"].append(i / HZ)
	var taus := {}
	var tauv := {}
	var pel_dyn := []
	var pel_f := []
	var fjoint := {}   # the force the joint carries (the same sum, force instead of moment)
	var members := {}   # joint -> the pieces distal to it
	var leg := {}       # leg joint -> its side
	for j in jl:
		var z := []
		z.resize(n)
		taus[j] = z
		tauv[j] = z.duplicate()
		fjoint[j] = z.duplicate()
		var mem := []
		for k in np:
			if (chains[pcs0[k]["j"]] as Array).has(j):
				mem.append(k)
		members[j] = mem
		var kd := kind_of(j)
		if kd == "thigh" or kd == "calf" or kd == "foot":
			leg[j] = String(j).substr(String(j).length() - 2)
	var gvec := Vector3(0.0, -GRAV, 0.0)
	var rod_k := 1.0 / sqrt(12.0)
	var fboxes: Array = cap["fbox"]
	var wbody := mass * GRAV
	out["cop"] = []
	out["resid"] = []        # the outside force the pelvis would need: sum m (a - g) - the ground force used (N, vector)
	out["resid_tau"] = []    # the outside horizontal torque about the COM that the centre of pressure cannot give (Nm)
	out["need"] = []         # max(|resid|, |resid_tau| / COM height) in body weights
	out["bw"] = wbody
	for i in n:
		# per piece: the force m (a - g), its moment about the origin c x f, and I alpha; a joint sums them over its distal pieces
		# and moves the origin to itself:  M_j = sum(c x f) - P_j x sum(f) + sum(I alpha)
		var fk := []
		var cfk := []
		var iak := []
		var ftot := Vector3.ZERO
		var com_sum := Vector3.ZERO
		var m_sum := 0.0
		for k in np:
			var m2: float = pcs0[k]["m"]
			var f: Vector3 = m2 * ((acc[k][i] as Vector3) - gvec)
			fk.append(f)
			cfk.append((cs[i][k] as Vector3).cross(f))
			var pk: Dictionary = pcs0[k].duplicate()   # I alpha with the piece's principal inertia (across kl, along kL) in its pose
			pk["u"] = (cap["us"] as Array)[i][k]
			iak.append(HitReaction.spin_h(pk, alp[k][i] as Vector3))
			ftot += f
			com_sum += m2 * (cs[i][k] as Vector3)
			m_sum += m2
		pel_dyn.append(cfk[0] + iak[0])   # pieces[0] is the pelvis: its c x f + I alpha (moment about the world origin)
		pel_f.append(fk[0])
		var bi = bat[i]
		var bf := Vector3.ZERO
		var bcf := Vector3.ZERO
		var bia := Vector3.ZERO
		var bhands := []
		if bi != null:
			var bm2: float = bi["m"]
			var bkl: float = rod_k * float(bi["L"])
			bf = bm2 * ((bat_acc[i] as Vector3) - gvec)
			bcf = (bi["c"] as Vector3).cross(bf)
			bia = (bat_alp[i] as Vector3) * (bm2 * bkl * bkl)
			bhands = ["hand_l", "hand_r"] if bool(bi["grip"]) else [String(bi["hand"])]
			ftot += bf
			com_sum += bm2 * (bi["c"] as Vector3)
			m_sum += bm2
		var com := com_sum / maxf(m_sum, 1e-9)
		# angular momentum rate about the COM: sum (c - com) x m a + sum I alpha (gravity has no moment about the COM)
		var ldot := Vector3.ZERO
		for k in np:
			ldot += ((cs[i][k] as Vector3) - com).cross((fk[k] as Vector3) + float(pcs0[k]["m"]) * gvec) + (iak[k] as Vector3)
		if bi != null:
			ldot += ((bi["c"] as Vector3) - com).cross(bf + float(bi["m"]) * gvec) + bia
		# THE GROUND REACTION (bottom-up): the whole body's momentum change is the ground force, but only what a foot can give:
		# it pushes (F_y >= 0) and does not slide (|F_h| <= MU F_y). The rest is the OUTSIDE force the motion needs (resid).
		var down := []
		for sd in ["_l", "_r"]:
			if feet[i][sd] != null and fboxes[i][sd] != null:
				down.append(sd)
		var fg := Vector3.ZERO
		var qf := {}
		var wts := {}
		var tau_res := Vector3(ldot.x, 0.0, ldot.z)
		if not down.is_empty() and ftot.y > 0.0:
			fg = ftot
			var fh := Vector2(fg.x, fg.z)
			if fh.length() > MU * fg.y:
				fh = fh.normalized() * MU * fg.y
				fg = Vector3(fh.x, fg.y, fh.y)
			# the net centre of pressure that gives the angular momentum rate:  (r x F) = Ldot (horizontal parts), r from the COM
			var y0 := 0.0
			for sd in down:
				y0 += (feet[i][sd] as Vector3).y / down.size()
			var ry := y0 - com.y
			var tgt := Vector2(com.x + (ldot.z + ry * fg.x) / fg.y, com.z + (ry * fg.z - ldot.x) / fg.y)
			# split between the feet by the lever rule along the line joining their footprint centres, then each foot's force point
			# moves by the same offset (inside its own footprint) so the pair's weighted point is the target wherever the hull allows
			var q2 := {}
			var cen := {}
			for sd in down:
				var bx: Rect2 = fboxes[i][sd]
				cen[sd] = bx.get_center()
			var off := Vector2.ZERO
			if down.size() == 1:
				wts[down[0]] = 1.0
				off = tgt - (cen[down[0]] as Vector2)
			else:
				var d12: Vector2 = (cen["_l"] as Vector2) - (cen["_r"] as Vector2)
				var wl := 0.5 if d12.length_squared() < 1e-8 else clampf((tgt - (cen["_r"] as Vector2)).dot(d12) / d12.length_squared(), 0.0, 1.0)
				wts["_l"] = wl
				wts["_r"] = 1.0 - wl
				off = tgt - ((cen["_l"] as Vector2) * wl + (cen["_r"] as Vector2) * (1.0 - wl))
			for sd in down:
				var bx2: Rect2 = fboxes[i][sd]
				var q: Vector2 = (cen[sd] as Vector2) + off
				q2[sd] = Vector2(clampf(q.x, bx2.position.x, bx2.end.x), clampf(q.y, bx2.position.y, bx2.end.y))
			var mom := Vector3.ZERO
			var cop_net := Vector3.ZERO
			for sd in down:
				qf[sd] = Vector3((q2[sd] as Vector2).x, (feet[i][sd] as Vector3).y, (q2[sd] as Vector2).y)
				mom += ((qf[sd] as Vector3) - com).cross(fg * float(wts[sd]))
				cop_net += (qf[sd] as Vector3) * float(wts[sd])
			tau_res = Vector3(ldot.x - mom.x, 0.0, ldot.z - mom.z)
			out["cop"].append(cop_net)
		else:
			out["cop"].append(Vector3(com.x, 0.0, com.z))
		var rv := ftot - fg
		out["grf"].append(fg)
		out["down"].append(down)
		out["resid"].append(rv)
		out["resid_tau"].append(tau_res)
		out["need"].append(maxf(rv.length(), tau_res.length() / maxf(com.y, 0.3)) / wbody)
		for j in jl:
			var pjv: Vector3 = ps[i][j]
			var sf := Vector3.ZERO
			var scf := Vector3.ZERO
			var sia := Vector3.ZERO
			for k in members[j]:
				sf += fk[k] as Vector3
				scf += cfk[k] as Vector3
				sia += iak[k] as Vector3
			if bi != null:
				var share := 0.0
				for h in bhands:
					if (chains[h] as Array).has(j):
						share += 1.0 / bhands.size()
				if share > 0.0:
					sf += share * bf
					scf += share * bcf
					sia += share * bia
			var tau := scf - pjv.cross(sf) + sia
			var fj := sf
			if leg.has(j):
				var sd2: String = leg[j]
				if wts.has(sd2) and fg != Vector3.ZERO:
					tau -= ((qf[sd2] as Vector3) - pjv).cross(fg * float(wts[sd2]))
					fj -= fg * float(wts[sd2])
			(taus[j] as Array)[i] = tau.length()
			(tauv[j] as Array)[i] = tau
			(fjoint[j] as Array)[i] = fj
	out["tau"] = taus
	out["tauv"] = tauv
	out["fjoint"] = fjoint
	out["pel_dyn"] = pel_dyn
	out["pel_f"] = pel_f
	for j in jl:
		var lim := limit_nm(j, mass)
		var r := []
		r.resize(n)
		for i in n:
			r[i] = float(out["tau"][j][i]) / lim
		out["ratio"][j] = r
	out["chain"] = chain_of(out, gtrack, tips, bat, n)
	return out


## THE LOAD PATH AT THE PELVIS, one number: the pelvis is where the top-down chain (lumbar) and the bottom-up chain (hips) meet.
## Moments about O = the midpoint of the hip joints, with F_u the force the lumbar carries and F_h the force each hip carries:
##     sum_h tau_h + tau_lumbar + (P_lumbar - O) x F_u + (pelvis piece: (c - O) x f + I alpha) + sum_h (P_h - O) x F_h = resid_tau
## so the hips equal the lumbar torque plus the LEVER of the trunk's force from the lumbar to the hips, plus the pelvis piece's
## own m a / I alpha, plus the torque the centre of pressure could not give (resid_tau, the pelvis's outside help). Returns the
## left side minus resid_tau (vector, Nm): ~0 at every sample when the arithmetic is consistent. {} parts: "lever", "pel", "resid".
static func pelvis_balance(cap: Dictionary, sm: Dictionary, i: int) -> Dictionary:
	var pl: Vector3 = cap["ps"][i]["spine_01"]
	var phl: Vector3 = cap["ps"][i]["thigh_l"]
	var phr: Vector3 = cap["ps"][i]["thigh_r"]
	var o := (phl + phr) * 0.5
	var lever := (pl - o).cross(sm["fjoint"]["spine_01"][i] as Vector3)
	var pel: Vector3 = (sm["pel_dyn"][i] as Vector3) - o.cross(sm["pel_f"][i] as Vector3)
	var hipf := (phl - o).cross(sm["fjoint"]["thigh_l"][i] as Vector3) + (phr - o).cross(sm["fjoint"]["thigh_r"][i] as Vector3)
	var hips: Vector3 = (sm["tauv"]["thigh_l"][i] as Vector3) + (sm["tauv"]["thigh_r"][i] as Vector3)
	var lum: Vector3 = sm["tauv"]["spine_01"][i]
	var rt: Vector3 = sm["resid_tau"][i]
	return {"gap": hips + lum + lever + pel + hipf - rt, "hips": hips, "lumbar": lum, "lever": lever, "pel": pel, "resid": rt}


## the bounding box (x, z) of a foot's footprint, or null when the foot is not on the floor
static func _fbox(B: Body, sd: String) -> Variant:
	var fp := Balance.footprint(B, sd)
	if fp.size() == 0:
		return null
	var lo := fp[0]
	var hi := fp[0]
	for q in fp:
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	return Rect2(lo, hi - lo)


## the middle of a foot's footprint (x, floor-ish y, z), or null when the foot is not on the floor
static func _cop(B: Body, sd: String) -> Variant:
	var fp := Balance.footprint(B, sd)
	if fp.size() == 0:
		return null
	var s := Vector2.ZERO
	for q in fp:
		s += q
	s /= float(fp.size())
	var y := 1e9
	for part in Balance.FEET[sd]:
		var c: Array = B.cap(part)
		var r: float = B.rad[part]
		y = minf(y, minf((c[0] as Vector3).y, (c[1] as Vector3).y) - r)
	return Vector3(s.x, maxf(y, 0.0), s.y)


## the POWER CHAIN: {"side", "t_star" (the tip's peak speed), "peak": {name: s}, "omega": {name: [rad/s, smoothed]},
## "a", "b" (window samples), "ok": the peaks come hip -> trunk -> shoulder -> elbow (within TIE samples)}
static func chain_of(sm: Dictionary, g: Dictionary, tips: Array, bat: Array, n: int) -> Dictionary:
	# the striking tip: the held bat's tip, else the faster hand
	var best := -1.0
	var side := "_r"
	var istar := 0
	var any_bat := bat.any(func(b): return b != null)
	for i in range(1, n):
		if any_bat:
			if bat[i] != null and bat[i - 1] != null:
				var sp: float = ((bat[i]["tip"] as Vector3) - (bat[i - 1]["tip"] as Vector3)).length() * HZ
				if sp > best:
					best = sp
					istar = i
					side = "_l" if String(bat[i]["hand"]).ends_with("_l") else "_r"
		else:
			for sd in ["_l", "_r"]:
				var sp2: float = ((tips[i][sd] as Vector3) - (tips[i - 1][sd] as Vector3)).length() * HZ
				if sp2 > best:
					best = sp2
					istar = i
					side = sd
	var a := maxi(int(floor(float(istar) - WINDOW * HZ)), 0)
	var b := mini(int(ceil(float(istar) + AFTER * HZ)), n - 1)
	var om := {}
	var peak := {}
	var pk_i := {}
	for nm in CHAIN:
		var jn: String = CHAIN_JOINT[nm]
		if nm == "shoulder" or nm == "elbow":
			jn += side
		var w := _omega(g[jn], n)
		var s := []
		for v in w:
			s.append((v as Vector3).length())
		s = _smooth(s)
		om[nm] = s
		var bi := a
		for i in range(a, b + 1):
			if float(s[i]) > float(s[bi]):
				bi = i
		pk_i[nm] = bi
		peak[nm] = bi / HZ
	var ok := true
	for q in range(1, CHAIN.size()):
		if float(pk_i[CHAIN[q]]) < float(pk_i[CHAIN[q - 1]]) - TIE:
			ok = false
	return {"side": side, "t_star": istar / HZ, "peak": peak, "omega": om, "a": a, "b": b, "ok": ok, "tip_speed": best, "have": true}


# ---------------------------------------------------------------- reading

## {joint: tau / limit} at time t
static func ratios_at(sm: Dictionary, t: float) -> Dictionary:
	var out := {}
	if sm.is_empty():
		return out
	var i := clampi(roundi(t * HZ), 0, int(sm["n"]) - 1)
	for j in sm["ratio"]:
		out[j] = float(sm["ratio"][j][i])
	return out


static func peak_nm(sm: Dictionary, j: String) -> float:
	var m := 0.0
	for v in sm["tau"][j]:
		m = maxf(m, v)
	return m


static func words(sm: Dictionary) -> String:
	var ch: Dictionary = sm.get("chain", {})
	if ch.is_empty():
		return ""
	var p: Dictionary = ch["peak"]
	return "power chain %s: hip %.2f s, trunk %.2f s, shoulder %.2f s, elbow %.2f s -> %s" % [String(ch["side"]).substr(1), p["hip"], p["trunk"], p["shoulder"], p["elbow"],
		"in order, proximal to distal" if ch["ok"] else "OUT OF ORDER"]


## draw the power chain strip on a Control (the window of the swing; one row per segment: its angular speed, its peak marked)
static func draw_strip(c: Control, sm: Dictionary, t: float) -> void:
	var ch: Dictionary = sm.get("chain", {})
	if ch.is_empty():
		return
	var font := c.get_theme_default_font()
	var W := c.size.x
	var rowh := 16.0
	var lab := 62.0
	var x0 := lab
	var x1 := W - 10.0
	var a: int = ch["a"]
	var b: int = ch["b"]
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Tok.c("mk_panel"))
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Tok.c("mk_border"), false, 1.0)
	_draw_need(c, sm, t, font)
	c.draw_set_transform(Vector2(0.0, 36.0))
	var col := Tok.c("fv_ok") if ch["ok"] else Tok.c("fv_hot")
	c.draw_string(font, Vector2(8, 15), "Power chain (%s hand)" % String(ch["side"]).substr(1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Tok.c("ink"))
	c.draw_string(font, Vector2(150, 15), "hip > trunk > shoulder > elbow: " + ("in order" if ch["ok"] else "OUT OF ORDER"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	var span := float(maxi(b - a, 1))
	for q in CHAIN.size():
		var nm: String = CHAIN[q]
		var y := 24.0 + q * rowh
		c.draw_string(font, Vector2(8, y + 11), nm, HORIZONTAL_ALIGNMENT_LEFT, lab - 8, 11, Tok.c("ink"))
		var s: Array = ch["omega"][nm]
		var mx := 1e-6
		for i in range(a, b + 1):
			mx = maxf(mx, float(s[i]))
		var pts := PackedVector2Array()
		for i in range(a, b + 1):
			pts.append(Vector2(x0 + (x1 - x0) * float(i - a) / span, y + rowh - 3.0 - (rowh - 5.0) * float(s[i]) / mx))
		if pts.size() > 1:
			c.draw_polyline(pts, Color(Tok.c("ink"), 0.55), 1.0)
		var px := x0 + (x1 - x0) * (float(ch["peak"][nm]) * HZ - a) / span
		c.draw_line(Vector2(px, y), Vector2(px, y + rowh - 2.0), col, 3.0)
	var tx := x0 + (x1 - x0) * (t * HZ - a) / span
	if tx >= x0 and tx <= x1:
		c.draw_line(Vector2(tx, 20.0), Vector2(tx, 24.0 + CHAIN.size() * rowh), Tok.c("card_play"), 1.0)
	c.draw_set_transform(Vector2.ZERO)


## the top line of the strip: the outside force at the pelvis (what the body would need from outside to move so). A red badge
## when it is NEED_BW body weights or more: the motion itself is not one a body can do, the joint colours are what it would cost.
static func _draw_need(c: Control, sm: Dictionary, t: float, font: Font) -> void:
	if not sm.has("need"):
		return
	var i := clampi(roundi(t * HZ), 0, int(sm["n"]) - 1)
	# the two chains' meeting point in numbers: the lumbar (top-down) and the hips (bottom-up), Nm now, and the torque the centre of
	# pressure could not give (the part of the hips that is outside help; pelvis_balance shows hips = lumbar + lever + pelvis + this)
	var hips: float = float(sm["tau"]["thigh_l"][i]) + float(sm["tau"]["thigh_r"][i])
	var rt: float = (sm["resid_tau"][i] as Vector3).length()
	var tx := "lumbar %.0f Nm   hips %.0f Nm (both)   CoP cannot give %.0f Nm" % [float(sm["tau"]["spine_01"][i]), hips, rt]
	c.draw_string(font, Vector2(8, 31), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Tok.c("ink"))
	var r: Vector3 = sm["resid"][i]
	var bw: float = sm["bw"]
	var nd: float = sm["need"][i]
	if nd >= NEED_BW:
		var txt := "NEEDS OUTSIDE FORCE  %.0f N (%.0f%% body weight)" % [maxf(r.length(), (sm["resid_tau"][i] as Vector3).length() / 1.0), nd * 100.0]
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14.0
		c.draw_rect(Rect2(6, 3, w, 15), Tok.c("fv_hot"))
		c.draw_string(font, Vector2(13, 14), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Tok.c("mk_panel"))
	else:
		c.draw_string(font, Vector2(8, 14), "Outside force at the pelvis: %.0f N (%.0f%% body weight), the body can do this" % [r.length(), nd * 100.0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Tok.c("fv_ok"))
