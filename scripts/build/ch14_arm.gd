extends RefCounted
## CH14 the water-syringe arm (docs/CH14_REFERENCE.md): the physics, all of it closed form (so GDScript only: no C++ twin is needed, nothing here costs more
## than a few hundred flops per call; the equality bar is the hand-arithmetic bar 9 in tests/ch14_test.gd).
## Units: mm, N, MPa (= N/mm2), mL (= 1000 mm3), kg, degrees at the interface, radians inside.
## Frame of the arm's vertical plane: r = radial distance from the base axis, z = height over the table. Shoulder axis at (0, hs).

const G := 9.80665
const P0 := 0.101325          # MPa, atmosphere

# ---------------------------------------------------------------- the can (12 fl oz, 355 mL)
const CAN_D := 66.2
const CAN_H := 122.0
const CAN_M0 := 0.015         # kg empty
const CAN_M1 := 0.385         # kg full
const LID_R := 27.0           # 202 end: 2 2/16 in = 54.0 mm diameter, the lid the next can stands on
const BASE_R := 24.0          # standing ring of the can bottom (ASSUMED 48 mm diameter, see the reference)

# ---------------------------------------------------------------- syringes (BD plastic, bore from the Harvard Apparatus style table)
const SYR := {5: {"bore": 12.06, "vol": 5.0, "mass": 0.007}, 10: {"bore": 14.5, "vol": 10.0, "mass": 0.012}, 20: {"bore": 19.13, "vol": 20.0, "mass": 0.023}}
const WALL_BARREL := 1.0      # mm PP barrel wall (ASSUMED)
const E_PP := 1300.0          # MPa polypropylene
const F_HAND := 30.0          # N design thumb force (low end of 30 to 50 N)
const F_HAND_MAX := 50.0      # N upper end, the stretch bar
const F_SEAL := 3.0           # N plunger seal friction per syringe (ASSUMED)
const P_VAC := 0.08           # MPa the most suction a closed water line holds before it cavitates / pulls air past the seal

# ---------------------------------------------------------------- water, hoses
const K_WATER := 2200.0       # MPa bulk modulus
const HOSE_ID := 4.0
const HOSE_OD := 6.0
const NU_HOSE := 0.45
const HOSES := {"pvc": 10.0, "pu98": 50.0, "pa12": 1200.0}   # E in MPa: soft clear PVC, polyurethane 98A, nylon-12
const HOSE_KG_PER_M := 0.0314  # PU 4x6 tube (18.8 g/m) + the water in it (12.6 g/m)
const DEAD_ML := 0.3          # tip and fitting volume per syringe

# ---------------------------------------------------------------- materials of the boom: E MPa, rho kg/m3, strength MPa, wall mm (0 = solid)
static var MAT := {
	"cardboard": {"E": 1000.0, "rho": 150.0, "sigma": 5.0, "wall": 4.0},
	"pine": {"E": 8500.0, "rho": 350.0, "sigma": 59.0, "wall": 0.0},
	"plywood": {"E": 9000.0, "rho": 650.0, "sigma": 45.0, "wall": 3.0},
	"pla": {"E": 2300.0, "rho": 1240.0, "sigma": 45.0, "wall": 1.6},
}
const BOOM_W := 30.0          # mm outside of the square boom section
const MU_BEARING := 0.2
const R_BEARING := 30.0
const MU_JAW := 0.4           # TPU / silicone pad on aluminium (conservative; the reference quotes 0.5 to 0.9)
const ETA_RACK := 0.85
const PIN_CLEAR := 0.25       # mm diametral clearance of a compensated printed pin hole, worst case
const PIN_SPAN := 56.0        # mm between the two cheek holes of a clevis (the bearing length of the slop)
const GEAR_BACKLASH := 0.25   # mm at the pitch circle, printed module 2
const R_PINION := 20.0        # mm pitch radius, 20 teeth module 2


static func design() -> Dictionary:
	return {
		"L1": 240.0, "L2": 220.0, "hs": 250.0, "dg": 95.0,
		"lim": {"sh": [10.0, 82.0], "el": [-136.0, -60.0], "wr": [-5.0, 100.0], "ba": [-90.0, 90.0]},
		"cyl": {"ba": [20, 20], "sh": [20, 20], "el": [20, 20], "wr": [10, 10], "gr": [5, 5]},
		"phic": {"sh": 66.0, "el": 90.0, "wr": 80.0},
		# d (axis to slave pivot), r (axis to push pin). Wrist: searched over d 50..160, r 20..45, phic 60..120 for the biggest smallest arm over its 105 deg with the
		# stroke <= 95 pct of a 10 mL: phic 80 (not 90: with a finite d the arm peaks at cos phi = r/d) gives 21.9 mm; d 126 makes the pivot-to-pin length 95..153 mm, a real 10 mL syringe
		"lever": {"sh": [117.0, 55.0], "el": [118.0, 56.0], "wr": [126.0, 36.0]},
		"hose_len": {"ba": 0.5, "sh": 0.6, "el": 0.9, "wr": 1.2, "gr": 1.4},   # m
		"hose": "mix", "flex": {"ba": 0.25, "sh": 0.2, "el": 0.3, "wr": 0.3, "gr": 0.3}, "cw_m": 1.0, "cw_l": 120.0, "air_ml": 0.0, "mat": "pla", "can_m": CAN_M0, "f_hand": F_HAND, "mu_jaw": MU_JAW,
		"pitch": 68.2, "rp": 270.0, "r_pick": 270.0, "rp_pinion": R_PINION,
	}


# ---------------------------------------------------------------- 1 syringes and Pascal

static func area(sz: int) -> float:
	var b: float = SYR[sz]["bore"]
	return PI / 4.0 * b * b


static func stroke(sz: int) -> float:
	return float(SYR[sz]["vol"]) * 1000.0 / area(sz)


## Pascal: the pressure p = F / A_master is the same everywhere in the closed water line, so F_slave = p A_slave
static func pascal_slave_force(f_master: float, sm: int, ss: int) -> float:
	return f_master / area(sm) * area(ss)


static func count_syringes(d: Dictionary) -> int:
	var n := 0
	for k in d["cyl"]:
		n += (d["cyl"][k] as Array).size()
	return n


# ---------------------------------------------------------------- 2 kinematics

static func ik(d: Dictionary, r: float, zc: float) -> Dictionary:
	var L1: float = d["L1"]
	var L2: float = d["L2"]
	var x := r
	var y: float = zc + float(d["dg"]) - float(d["hs"])
	var d2 := x * x + y * y
	var c := (d2 - L1 * L1 - L2 * L2) / (2.0 * L1 * L2)
	if absf(c) > 1.0:
		return {"ok": false, "why": "out of reach"}
	var t2 := -acos(c)
	var t1 := atan2(y, x) - atan2(L2 * sin(t2), L1 + L2 * cos(t2))
	var a1 := rad_to_deg(t1)
	var a2 := rad_to_deg(t2)
	var psi := -(a1 + a2)
	var lim: Dictionary = d["lim"]
	var inl: bool = a1 >= lim["sh"][0] and a1 <= lim["sh"][1] and a2 >= lim["el"][0] and a2 <= lim["el"][1] and psi >= lim["wr"][0] and psi <= lim["wr"][1]
	return {"ok": inl, "th1": a1, "th2": a2, "psi": psi, "why": "" if inl else "joint limit"}


## the can centre (r, z) in double precision
static func fk_c(d: Dictionary, th1: float, th2: float) -> Array:
	var a1 := deg_to_rad(th1)
	var a2 := deg_to_rad(th1 + th2)
	var wr: float = float(d["L1"]) * cos(a1) + float(d["L2"]) * cos(a2)
	var wz: float = float(d["hs"]) + float(d["L1"]) * sin(a1) + float(d["L2"]) * sin(a2)
	return [wr, wz - float(d["dg"])]


## [elbow, wrist, can centre] as (r, z)
static func fk(d: Dictionary, th1: float, th2: float) -> Dictionary:
	var a1 := deg_to_rad(th1)
	var a2 := deg_to_rad(th1 + th2)
	var e := Vector2(float(d["L1"]) * cos(a1), float(d["hs"]) + float(d["L1"]) * sin(a1))
	var w := e + Vector2(float(d["L2"]) * cos(a2), float(d["L2"]) * sin(a2))
	return {"e": e, "w": w, "c": w - Vector2(0.0, float(d["dg"]))}


## the 7 poses of the job: the pickup, then the six placements in building order (far, middle, near of row 1; far, near of row 2; top)
static func poses(d: Dictionary) -> Array:
	var s: float = d["pitch"]
	var rp: float = d["rp"]
	var zr := CAN_H
	var zc := CAN_H / 2.0
	var out := [{"name": "pickup", "r": float(d["r_pick"]), "z": zc, "yaw": -90.0}]
	var rows := [["row1 far", rp + s, zc], ["row1 mid", rp, zc], ["row1 near", rp - s, zc], ["row2 far", rp + s / 2.0, zc + zr], ["row2 near", rp - s / 2.0, zc + zr], ["top", rp, zc + 2.0 * zr]]
	for q in rows:
		out.append({"name": q[0], "r": q[1], "z": q[2], "yaw": 90.0})
	return out


## bar 1: every pose (and its 25 mm hover above) inside the limits
static func reach_check(d: Dictionary) -> Dictionary:
	var bad := []
	var ik_of := {}
	for p in poses(d):
		for dz in [0.0, 25.0]:
			var q := ik(d, p["r"], p["z"] + dz)
			if not q["ok"]:
				bad.append("%s +%.0f: %s" % [p["name"], dz, q["why"]])
			elif dz == 0.0:
				ik_of[p["name"]] = q
	return {"ok": bad.is_empty(), "bad": bad, "ik": ik_of}


# ---------------------------------------------------------------- 3 the lever-crank joint (shoulder, elbow, wrist) and the base

static func lc_len(dd: float, rr: float, phi_deg: float) -> float:
	return sqrt(dd * dd + rr * rr - 2.0 * dd * rr * cos(deg_to_rad(phi_deg)))


## the moment arm of the push pin about the joint axis: d r sin(phi) / L
static func lc_arm(dd: float, rr: float, phi_deg: float) -> float:
	return dd * rr * sin(deg_to_rad(phi_deg)) / lc_len(dd, rr, phi_deg)


## the joint angle theta (deg) to the horn angle phi: the horn turns with the joint, phi = phic in the middle of the limits (90 deg = the biggest swing, but the arm is largest near 60 deg)
static func phi_of(d: Dictionary, j: String, th: float) -> float:
	var lim: Array = d["lim"][j]
	return float(d["phic"][j]) + (th - 0.5 * (float(lim[0]) + float(lim[1])))


static func lever_arm(d: Dictionary, j: String, th: float) -> float:
	var lv: Array = d["lever"][j]
	return lc_arm(lv[0], lv[1], phi_of(d, j, th))


## slave plunger travel (mm) measured from the retracted end of the joint's range
static func lever_stroke(d: Dictionary, j: String, th: float) -> float:
	var lv: Array = d["lever"][j]
	var lim: Array = d["lim"][j]
	return lc_len(lv[0], lv[1], phi_of(d, j, th)) - lc_len(lv[0], lv[1], phi_of(d, j, lim[0]))


## the stroke chain of a joint over its whole range: {"sweep", "stroke", "avail", "monotone", "min_arm", "use"}
static func chain(d: Dictionary, j: String) -> Dictionary:
	var lim: Array = d["lim"][j]
	var n := 360
	var prev := -1e9
	var mono := true
	var min_arm := 1e9
	for i in n + 1:
		var th: float = lerpf(lim[0], lim[1], float(i) / n)
		var s := lever_stroke(d, j, th)
		if s < prev - 1e-12:
			mono = false
		prev = s
		min_arm = minf(min_arm, lever_arm(d, j, th))
	var sz: int = d["cyl"][j][1]
	var st := lever_stroke(d, j, lim[1])
	return {"sweep": float(lim[1]) - float(lim[0]), "stroke": st, "avail": stroke(sz), "monotone": mono, "min_arm": min_arm, "use": st / stroke(sz)}


## the base: a rack on the slave plunger and a pinion on the turntable (kind "rack"), or a lever-crank (kind "crank": slave pivot at distance dd, horn rr)
## swept from -90 to +90 deg about the pivot line. Returns the 180 deg question answered from one slave stroke.
static func base_chain(kind: String, sz: int, rp := R_PINION, dd := 80.0, rr := 40.0) -> Dictionary:
	if kind == "rack":
		var x := PI * rp
		return {"sweep": rad_to_deg(stroke(sz) / rp), "need": x, "avail": stroke(sz), "monotone": true, "min_arm": rp, "ok": x <= stroke(sz) and rad_to_deg(stroke(sz) / rp) >= 180.0}
	var prev := 1e9
	var mono := true
	var minarm := 1e9
	var lmin := 1e9
	var lmax := 0.0
	var dirs := 0
	var last_sign := 0
	for i in 361:
		var phi := -90.0 + 180.0 * i / 360.0
		var L := lc_len(dd, rr, phi)
		lmin = minf(lmin, L)
		lmax = maxf(lmax, L)
		minarm = minf(minarm, absf(dd * rr * sin(deg_to_rad(phi)) / L))
		if i > 0:
			var sg := 1 if L > prev + 1e-12 else (-1 if L < prev - 1e-12 else 0)
			if sg != 0 and last_sign != 0 and sg != last_sign:
				dirs += 1
				mono = false
			if sg != 0:
				last_sign = sg
		prev = L
	return {"sweep": 180.0, "need": lmax - lmin, "avail": stroke(sz), "monotone": mono, "min_arm": minarm, "ok": mono and minarm > 0.25 * rr}


# ---------------------------------------------------------------- 4 materials and the boom

static func section(mat: String) -> Dictionary:
	var m: Dictionary = MAT[mat]
	var w := BOOM_W
	var t: float = m["wall"]
	var wi := w - 2.0 * t if t > 0.0 else 0.0
	var A := w * w - wi * wi
	var I := (pow(w, 4) - pow(wi, 4)) / 12.0
	return {"A": A, "I": I, "w": w, "t": t, "c": w / 2.0}


## kg of one boom link of length L (mm)
static func link_mass(mat: String, L: float) -> float:
	var s := section(mat)
	return float(s["A"]) * L * 1e-9 * float(MAT[mat]["rho"])


## tip deflection (mm) of a cantilever of length L, EI, point load F at the tip, own weight w (N/mm), tip moment M (N mm)
static func cantilever(L: float, EI: float, F: float, w: float, M: float) -> float:
	return F * pow(L, 3) / (3.0 * EI) + w * pow(L, 4) / (8.0 * EI) + M * L * L / (2.0 * EI)


## the same by the unit-load (energy) method with Simpson's rule: delta = integral M m / EI dx (exact for the cubic integrand)
static func cantilever_energy(L: float, EI: float, F: float, w: float, M: float, n := 64) -> float:
	var h := L / n
	var sum := 0.0
	for i in n + 1:
		var x := h * i
		var a := L - x      # distance from the tip
		var mom := F * a + 0.5 * w * a * a + M   # bending moment at x
		var m := a           # moment of a unit tip load
		var f := mom * m / EI
		var wt := 1.0 if (i == 0 or i == n) else (4.0 if i % 2 == 1 else 2.0)
		sum += wt * f
	return sum * h / 3.0


## masses of the moving links for a boom material and a can: {"u", "f", "g", "c"} kg
static func masses(d: Dictionary, mat: String, can_m: float) -> Dictionary:
	var mu := link_mass(mat, d["L1"]) + 0.030 + float(SYR[d["cyl"]["el"][1]]["mass"]) + 0.0045 * float(SYR[d["cyl"]["el"][1]]["vol"]) + 3.0 * float(d["L1"]) * 1e-3 * HOSE_KG_PER_M
	var mf := link_mass(mat, d["L2"]) + 0.025 + float(SYR[d["cyl"]["wr"][1]]["mass"]) + 0.0045 * float(SYR[d["cyl"]["wr"][1]]["vol"]) + 2.0 * float(d["L2"]) * 1e-3 * HOSE_KG_PER_M
	var mg := 0.085 + float(SYR[d["cyl"]["gr"][1]]["mass"]) + 0.0045 * float(SYR[d["cyl"]["gr"][1]]["vol"])
	return {"u": mu, "f": mf, "g": mg, "c": can_m}


## the boom in the outstretched horizontal pose (the worst bending pose; conservative against the real pose): tip deflection mm and the peak bending stress MPa
static func boom(d: Dictionary, mat: String, can_m: float) -> Dictionary:
	var s := section(mat)
	var E: float = MAT[mat]["E"]
	var EI := E * float(s["I"])
	var m := masses(d, mat, can_m)
	var L1: float = d["L1"]
	var L2: float = d["L2"]
	var wl := G * link_mass(mat, L2) / L2         # N/mm of the forearm tube
	var wu := G * link_mass(mat, L1) / L1
	var tipf := G * (float(m["g"]) + can_m)       # gripper + can at the forearm tip
	var f_extra := G * (float(m["f"]) - link_mass(mat, L2))   # slave syringe, hose and fittings: lumped at mid forearm (carried as a tip load of equal moment)
	var f_tip_equiv := tipf + 0.5 * f_extra
	var d_f := cantilever(L2, EI, f_tip_equiv, wl, 0.0)
	# the upper arm carries the forearm's weight at the elbow (force) and its moment about the elbow (a tip moment on the upper arm)
	var F_e := G * (float(m["f"]) + float(m["g"]) + can_m)
	var M_e := wl * L2 * L2 / 2.0 + tipf * L2 + 0.5 * f_extra * L2 
	var u_extra := G * (float(m["u"]) - link_mass(mat, L1))
	var d_u := cantilever(L1, EI, F_e + 0.5 * u_extra, wu, M_e)
	var slope_u := F_e * L1 * L1 / (2.0 * EI) + wu * pow(L1, 3) / (6.0 * EI) + M_e * L1 / EI + 0.5 * u_extra * L1 * L1 / (2.0 * EI)
	var tip := d_u + slope_u * L2 + d_f
	var M_max := F_e * L1 + wu * L1 * L1 / 2.0 + M_e + 0.5 * u_extra * L1
	var sig: float = M_max * float(s["c"]) / float(s["I"])
	return {"tip": tip, "d_u": d_u, "d_f": d_f, "slope_u": slope_u, "sigma": sig, "M_max": M_max, "EI": EI, "mass": float(m["u"]) + float(m["f"])}


# ---------------------------------------------------------------- 5 joint torques and the syringe margins

## the torque (N mm) the shoulder, elbow and wrist must hold at a pose, with the boom material and can mass; plus the base friction torque
static func torques(d: Dictionary, th1: float, th2: float, mat: String, can_m: float) -> Dictionary:
	var m := masses(d, mat, can_m)
	var a1 := deg_to_rad(th1)
	var a2 := deg_to_rad(th1 + th2)
	var L1: float = d["L1"]
	var L2: float = d["L2"]
	var xe := L1 * cos(a1)
	var xw := xe + L2 * cos(a2)
	var ts: float = G * (float(m["u"]) * 0.5 * xe + float(m["f"]) * (xe + 0.5 * L2 * cos(a2)) + (float(m["g"]) + can_m) * xw - float(d.get("cw_m", 0.0)) * float(d.get("cw_l", 0.0)) * cos(a1))
	var te: float = G * (float(m["f"]) * 0.5 * L2 * cos(a2) + (float(m["g"]) + can_m) * L2 * cos(a2))
	var tw: float = G * (float(m["g"]) + can_m) * 8.0          # 8 mm of off-centre can / gripper centre of mass
	var w_all: float = G * (float(m["u"]) + float(m["f"]) + float(m["g"]) + can_m + 0.25 + float(d.get("cw_m", 0.0)))
	return {"sh": ts, "el": absf(te), "wr": tw, "ba": MU_BEARING * w_all * R_BEARING}


## capacity vs need of one axis in newtons at the slave plunger. f_hand: the thumb force
static func axis_force(d: Dictionary, j: String, t_nmm: float, arm: float, f_hand: float) -> Dictionary:
	var sm: int = d["cyl"][j][0]
	var ss: int = d["cyl"][j][1]
	var cap := pascal_slave_force(f_hand - F_SEAL, sm, ss)
	if t_nmm < 0.0:       # the counterweight wins: the slave must PULL, and a closed water line only holds P_VAC of suction
		cap = minf(cap, P_VAC * area(ss))
	var load := absf(t_nmm) / arm
	var need := load + F_SEAL
	return {"cap": cap, "load": load, "need": need, "margin": cap / need}


## torque margin of every axis at one pose
static func margins(d: Dictionary, th1: float, th2: float, mat: String, can_m: float, f_hand: float) -> Dictionary:
	var t := torques(d, th1, th2, mat, can_m)
	var psi := -(th1 + th2)
	var out := {}
	out["sh"] = axis_force(d, "sh", t["sh"], lever_arm(d, "sh", th1), f_hand)
	out["el"] = axis_force(d, "el", t["el"], lever_arm(d, "el", th2), f_hand)
	out["wr"] = axis_force(d, "wr", t["wr"], lever_arm(d, "wr", psi), f_hand)
	out["ba"] = axis_force(d, "ba", t["ba"], float(d["rp_pinion"]), f_hand)
	return out


## the worst (smallest) margin over the 7 poses and their hovers, per axis, and where
static func worst_margins(d: Dictionary, mat: String, can_m: float, f_hand: float) -> Dictionary:
	var worst := {}
	for p in poses(d):
		for dz in [0.0, 25.0]:
			var q := ik(d, p["r"], p["z"] + dz)
			if not q.has("th1"):
				continue
			var mg := margins(d, q["th1"], q["th2"], mat, can_m, f_hand)
			for j in mg:
				if not worst.has(j) or float(mg[j]["margin"]) < float(worst[j]["margin"]):
					var e: Dictionary = (mg[j] as Dictionary).duplicate()
					e["pose"] = "%s +%.0f" % [p["name"], dz]
					worst[j] = e
	return worst


# ---------------------------------------------------------------- 6 the gripper

## jaw clamp force needed (N per jaw) for a safety factor sf, and the force the gripper syringe pair can give
static func grip(d: Dictionary, can_m: float, sf: float, f_hand: float) -> Dictionary:
	var mu: float = d["mu_jaw"]
	var need := sf * can_m * G / (2.0 * mu)
	var sm: int = d["cyl"]["gr"][0]
	var ss: int = d["cyl"]["gr"][1]
	var have := ETA_RACK * (pascal_slave_force(f_hand - F_SEAL, sm, ss) - F_SEAL)
	return {"need": need, "have": have, "friction": 2.0 * mu * have, "weight": can_m * G, "ratio": 2.0 * mu * have / (can_m * G)}


# ---------------------------------------------------------------- 7 compliance: water, hose, barrel, bubble

## hose volume per MPa of internal gauge pressure, as a fraction (Lame thick wall, plane stress, free ends): dV/V = 2 (p/E) ((b2 + a2)/(b2 - a2) + nu)
static func hose_k(e_mpa: float) -> float:
	var a := HOSE_ID / 2.0
	var b := HOSE_OD / 2.0
	return 2.0 / e_mpa * ((b * b + a * a) / (b * b - a * a) + NU_HOSE)


## volume change (mL) of one circuit at a gauge pressure p (MPa, may be negative down to -P_VAC)
static func circuit_dv(d: Dictionary, j: String, p: float, air_ml := -1.0, hose := "") -> Dictionary:
	var sm: int = d["cyl"][j][0]
	var ss: int = d["cyl"][j][1]
	var hk := String(d["hose"]) if hose == "" else hose
	var flex := 0.0
	if hk == "mix":
		flex = float(d["flex"][j])
	var vh: float = PI / 4.0 * HOSE_ID * HOSE_ID * float(d["hose_len"][j]) * 1000.0 / 1000.0     # mm3 -> mL: (mm2 * m*1000 mm) / 1000
	var swept := 0.0
	if j == "ba":
		swept = PI * float(d["rp_pinion"]) * area(ss) / 1000.0
	elif j == "gr":
		swept = 8.0 * area(ss) / 1000.0
	else:
		swept = float(chain(d, j)["stroke"]) * area(ss) / 1000.0
	var vw := vh + swept + 2.0 * DEAD_ML                          # water in the circuit (mL), master + slave barrels hold the swept volume between them
	var dv_w := vw * p / K_WATER
	var dv_h := 0.0
	if hk != "mix":
		dv_h = vh * hose_k(float(HOSES[hk])) * p
	else:
		var vf: float = PI / 4.0 * HOSE_ID * HOSE_ID * flex
		dv_h = vf * hose_k(float(HOSES["pu98"])) * p + (vh - vf) * hose_k(float(HOSES["pa12"])) * p
	# barrels: thin wall, hoop strain p r / (t E) each way, dV/V = 2 p r /(t E) per barrel on the water they hold (the swept volume)
	var rb := (float(SYR[sm]["bore"]) + float(SYR[ss]["bore"])) / 4.0
	var dv_b := swept * 2.0 * p * rb / (WALL_BARREL * E_PP)
	var va: float = float(d["air_ml"]) if air_ml < 0.0 else air_ml
	var dv_a := va * p / (P0 + p)                                  # isothermal ideal gas: (P0 + p)(Va - dV) = P0 Va
	return {"water": dv_w, "hose": dv_h, "barrel": dv_b, "air": dv_a, "total": dv_w + dv_h + dv_b + dv_a, "vh": vh, "vw": vw}


## the lost stroke (mm of slave plunger) of one axis between the least and the most pressure the work cycle puts on it, with the seal friction band
static func axis_band(d: Dictionary, j: String, loads: Array, air_ml := -1.0, hose := "") -> Dictionary:
	var ss: int = d["cyl"][j][1]
	var a := area(ss)
	var phi := 1e9
	var plo := -1e9
	var pmax := -1e9
	var pmin := 1e9
	for f in loads:
		pmax = maxf(pmax, (float(f) + F_SEAL) / a)
		pmin = minf(pmin, maxf(-P_VAC, (float(f) - F_SEAL) / a))
	var hi := circuit_dv(d, j, pmax, air_ml, hose)
	var lo := circuit_dv(d, j, pmin, air_ml, hose)
	return {"mm": ((hi["total"] as float) - (lo["total"] as float)) * 1000.0 / a, "pmax": pmax, "pmin": pmin, "hi": hi, "lo": lo,
		"master_mm": ((hi["total"] as float) * 1000.0) / area(d["cyl"][j][0])}


## placement error (mm) at the can centre over all poses: {"in": in-plane, "y": sideways, "parts": per-axis, "worst_pose"}
static func placement_error(d: Dictionary, air_ml := -1.0, hose := "") -> Dictionary:
	var mat: String = d["mat"]
	var can_m: float = d["can_m"]
	var loads := {"sh": [], "el": [], "wr": [], "ba": []}
	var list := []
	for p in poses(d):
		for dz in [0.0, 25.0]:
			var q := ik(d, p["r"], p["z"] + dz)
			if not q.has("th1"):
				continue
			var mg := margins(d, q["th1"], q["th2"], mat, can_m, d["f_hand"])
			for j in loads:
				(loads[j] as Array).append(mg[j]["load"])
			list.append([p, q, dz])
	var bands := {}
	for j in loads:
		bands[j] = axis_band(d, j, loads[j], air_ml, hose)
	var slop := PIN_CLEAR / PIN_SPAN
	var bm := boom(d, mat, can_m)
	var worst := {"in": -1.0}
	for it in list:
		var p: Dictionary = it[0]
		var q: Dictionary = it[1]
		var f := fk(d, q["th1"], q["th2"])
		var sh_to_c: float = (f["c"] - Vector2(0.0, d["hs"])).length()
		var el_to_c: float = (f["c"] - (f["e"] as Vector2)).length()
		var parts := {}
		parts["sh"] = sh_to_c * (float(bands["sh"]["mm"]) / lever_arm(d, "sh", q["th1"]) + slop)
		parts["el"] = el_to_c * (float(bands["el"]["mm"]) / lever_arm(d, "el", q["th2"]) + slop)
		parts["wr"] = float(d["dg"]) * (float(bands["wr"]["mm"]) / lever_arm(d, "wr", q["psi"]) + slop)
		parts["boom"] = float(bm["tip"])
		var tot: float = parts["sh"] + parts["el"] + parts["wr"] + parts["boom"]
		if tot > worst["in"]:
			worst = {"in": tot, "parts": parts, "pose": "%s +%.0f" % [p["name"], it[2]], "r": p["r"]}
	var rmax := 0.0
	for p in poses(d):
		rmax = maxf(rmax, float(p["r"]))
	var ba_x: float = float(bands["ba"]["mm"]) + GEAR_BACKLASH
	worst["y"] = rmax / float(d["rp_pinion"]) * ba_x + 0.15
	worst["bands"] = bands
	return worst


## the largest bubble (mL per circuit) the in-plane budget survives: bisection on the error
static func air_tolerance(d: Dictionary, budget_in: float) -> float:
	var lo := 0.0
	var hi := 5.0
	for i in 60:
		var mid := 0.5 * (lo + hi)
		if float(placement_error(d, mid)["in"]) <= budget_in:
			lo = mid
		else:
			hi = mid
	return lo


# ---------------------------------------------------------------- 8 the stack

static func _hull(pts: PackedVector2Array) -> PackedVector2Array:
	var p := Array(pts)
	p.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	var lower: Array = []
	for q in p:
		while lower.size() >= 2 and ((lower[-1] - lower[-2]).cross(q - lower[-2])) <= 0.0:
			lower.pop_back()
		lower.append(q)
	var upper: Array = []
	for i in range(p.size() - 1, -1, -1):
		var q: Vector2 = p[i]
		while upper.size() >= 2 and ((upper[-1] - upper[-2]).cross(q - upper[-2])) <= 0.0:
			upper.pop_back()
		upper.append(q)
	lower.pop_back()
	upper.pop_back()
	return PackedVector2Array(lower + upper)


## the contact patch of a can standing on a lid: the lens where the standing ring (radius BASE_R at u) overlaps the lid (radius LID_R at v), as boundary points
static func lens(u: Vector2, v: Vector2, n := 360) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		var pb := u + Vector2(cos(a), sin(a)) * BASE_R
		if pb.distance_to(v) <= LID_R:
			out.append(pb)
		var pl := v + Vector2(cos(a), sin(a)) * LID_R
		if pl.distance_to(u) <= BASE_R:
			out.append(pl)
	return out


## margin (mm, positive = inside) of a point to a convex polygon given counter-clockwise; -1e9 for an empty polygon
static func hull_margin(poly: PackedVector2Array, pt: Vector2) -> float:
	if poly.size() < 3:
		return -1e9
	var m := 1e9
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := b - a
		var dist := e.cross(pt - a) / e.length()
		m = minf(m, dist)
	return m


## stability of an upper can at plan position u (x radial, y sideways) on two lower cans at v1, v2: {"margin", "both": both lids touched}
static func stack_check(u: Vector2, v1: Vector2, v2: Vector2) -> Dictionary:
	var l1 := lens(u, v1)
	var l2 := lens(u, v2)
	var all := PackedVector2Array()
	all.append_array(l1)
	all.append_array(l2)
	var hull := _hull(all) if all.size() >= 3 else PackedVector2Array()
	return {"margin": hull_margin(hull, u), "both": l1.size() > 0 and l2.size() > 0}


## the placement tolerances of an upper can from the geometry: x along the row, y across it (mm): contact with BOTH supports is kept
static func stack_tolerance(pitch: float) -> Dictionary:
	var tx := BASE_R + LID_R - pitch / 2.0
	var ty := sqrt(pow(BASE_R + LID_R, 2) - pow(pitch / 2.0, 2))
	return {"x": tx, "y": ty}


## the whole pyramid at plan positions (list of Vector2 per can in building order: row1 far, mid, near, row2 far, near, top) -> list of {"name", "margin", "both"}
static func pyramid_check(pos: Array) -> Array:
	var out := []
	out.append({"name": "row2 far", "c": stack_check(pos[3], pos[0], pos[1])})
	out.append({"name": "row2 near", "c": stack_check(pos[4], pos[1], pos[2])})
	out.append({"name": "top", "c": stack_check(pos[5], pos[3], pos[4])})
	return out


# ---------------------------------------------------------------- 9 where the pins are (the parts and the animation both read these)

const FDM_UNDERSIZE := 0.30   # mm a printed hole of 4 to 15 mm comes out small (reference section 7)
const RUN_CLEAR := 0.15       # mm running clearance wanted on a 4 mm steel dowel after printing


## the diameter to draw in the CAD for a hole that must print at d_nom + clearance
static func hole_design(d_nom: float, clearance := RUN_CLEAR) -> float:
	return d_nom + clearance + FDM_UNDERSIZE


## horn angle (deg) of the push pin in the frame of the part that carries the horn, and the pivot position in the carrier's frame
static func horn_pin(d: Dictionary, j: String) -> Vector2:
	var lim: Array = d["lim"][j]
	var tc := 0.5 * (float(lim[0]) + float(lim[1]))
	var r: float = d["lever"][j][1]
	var dl: float = float(d["phic"][j]) - 90.0
	var a := 0.0
	if j == "sh":
		a = dl - tc
	else:
		a = -90.0 + dl - tc      # elbow: in the forearm frame; wrist: in the level gripper frame (world angle -90 - psi_c + dl)
	return Vector2(r * cos(deg_to_rad(a)), r * sin(deg_to_rad(a)))


static func pivot(d: Dictionary, j: String) -> Vector2:
	var dd: float = d["lever"][j][0]
	if j == "sh":
		return Vector2(0.0, -dd)
	if j == "el":
		return Vector2(float(d["L1"]) - dd, 0.0)
	return Vector2(float(d["L2"]) - dd, 0.0)


## the slave's two ends in the CARRIER's frame (mm): P the pivot it hangs from, Q the push pin on the horn turned by the joint angle th (sh: th1, el: th2, wr: psi).
## The carrier frame has the joint at (0, 0) for the shoulder (the turntable seen from the shoulder axis), (L1, 0) for the elbow (upper arm), (L2, 0) for the wrist (forearm)
static func slave_line(d: Dictionary, j: String, th: float) -> Dictionary:
	var jo := Vector2.ZERO
	if j == "el":
		jo = Vector2(float(d["L1"]), 0.0)
	elif j == "wr":
		jo = Vector2(float(d["L2"]), 0.0)
	return {"P": pivot(d, j), "Q": jo + horn_pin(d, j).rotated(deg_to_rad(th))}


## the rod, barrel offset and so on of a slave syringe: rod length Lrod and the barrel tip distance t0 from the pivot along the push line
static func slave_layout(d: Dictionary, j: String) -> Dictionary:
	var ss: int = d["cyl"][j][1]
	var lv: Array = d["lever"][j]
	var lim: Array = d["lim"][j]
	var lmin := lc_len(lv[0], lv[1], phi_of(d, j, lim[0]))
	var lrod := stroke(ss) + 15.0
	return {"lmin": lmin, "lrod": lrod, "t0": lmin - 12.0 - lrod, "barrel": stroke(ss) + 12.0}


## everything a frame needs: joint angles from yaw, th1, th2, grip travel -> world transforms are built by the renderer; this answers the slave stroke of each axis
static func strokes(d: Dictionary, yaw: float, th1: float, th2: float) -> Dictionary:
	return {"ba": R_PINION * deg_to_rad(yaw + 90.0), "sh": lever_stroke(d, "sh", th1), "el": lever_stroke(d, "el", th2), "wr": lever_stroke(d, "wr", -(th1 + th2))}
