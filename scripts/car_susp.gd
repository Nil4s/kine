class_name CarSusp
extends RefCounted
## VEHICLE, STEP 3 SUSPENSION: the wheels hung from the body by hard points (mm). Car coordinates: x = forward from the FRONT axle
## (rear axle at x = -wheelbase), y = out to the LEFT (+) from the centreline, z = up from the ground. Each corner is one rigid KNUCKLE
## (the wheel centre W and the contact patch C are fixed to its ball joints) on lower arms (inner bush pivots lf, lr: the arm turns about
## the line lf to lr) and an upper link: a MacPherson strut (the strut top U is on the body; the knuckle takes the strut lower mount S on
## the axis U to L at STRUT_K from the lower ball joint L) or wishbone upper arms (bush pivots uf, ur, upper ball joint T).
## Rear: twist beam (one trailing arm, the carrier turns about its bush axis) or multilink (two arms, as the wishbone).
## Bounce (+-80 mm of wheel centre height) solves the one-degree-of-freedom linkage: the lower arm angle by bisection so that the wheel
## centre is at the travel; the upper arm angle (wishbone) by a scan of the ball joint distance. Every link keeps its length.
## Readouts: camber and track from the front view (y-z), KPI, scrub, roll centre from the front view, caster and trail from the side view (x-z).
## Typical ranges (RANGES), road cars: Milliken and Milliken, Race Car Vehicle Dynamics (1995), ch. 2 (camber, caster, KPI, scrub, roll
## centre) and Reimpell, Stoll and Betzler, The Automotive Chassis (2001), ch. 3 (KPI 8-16 deg, scrub -20 to +60 mm). These are the usual
## textbook bands as recalled; they were NOT checked against the books.
## Stored in S.vehicle["susp"] = {"front": "MacPherson strut" or "Double wishbone", "rear": "Twist beam" or "Multilink"}.
## Pure functions (no nodes) except build_3d. Chassis boxes come from CarChassis.members (x across, y up, z from the nose).

const FRONT_OPTS := ["MacPherson strut", "Double wishbone"]
const REAR_OPTS := ["Twist beam", "Multilink"]
const TRAVEL := 80.0           # mm, Bounce: the wheel centre moves this far up (+) or down (-)
const CAMBER0 := -1.0          # deg, the static front camber the hard points start from (wheel centre inboard of the contact patch)
const KPI0 := 11.0             # deg, the steering axis lean the front hard points start from
const CASTER0 := 5.0           # deg, the steering axis rearward lean the front hard points start from
const STRUT_K := 200.0         # mm, the strut lower mount on the knuckle: this far up the axis from the lower ball joint
const PIVOT_LIFT := 80.0       # mm, the arm pivots sit this far above the ground clearance (the subframe)
const RANGES := {"camber": [-2.0, 0.0], "kpi": [8.0, 16.0], "scrub": [-20.0, 60.0], "caster": [2.0, 8.0], "rc": [0.0, 150.0]}
const RANGE_WORDS := {"camber": "Wheel tilt", "kpi": "Steering tilt", "scrub": "Scrub", "caster": "Caster", "rc": "Roll centre height"}
const SOLVE_LIM := 0.6         # rad, the search range of the arm angle (+-34 deg, far beyond +-80 mm)


static func start() -> Dictionary:
	return {"front": FRONT_OPTS[0], "rear": REAR_OPTS[0]}


## a suspension record, filled in where a key is missing or not one of the choices
static func norm(v: Variant) -> Dictionary:
	var out := start()
	if v is Dictionary:
		var d := v as Dictionary
		if FRONT_OPTS.has(String(d.get("front", ""))):
			out["front"] = String(d["front"])
		if REAR_OPTS.has(String(d.get("rear", ""))):
			out["rear"] = String(d["rear"])
	return out


static func in_range(key: String, v: float) -> bool:
	var r: Array = RANGES[key]
	return v >= float(r[0]) and v <= float(r[1])


## a plain hint for a readout out of its typical range ("" when inside)
static func hint(key: String, v: float) -> String:
	if in_range(key, v):
		return ""
	var r: Array = RANGES[key]
	return "%s is %s: a road car is usually %s to %s" % [RANGE_WORDS[key], str(snappedf(v, 0.1)), str(float(r[0])), str(float(r[1]))]


# ---------------------------------------------------------------- the hard points

## the two corner hard point sets, left side (y > 0): {front: corner, rear: corner}. corner = {axle, kind, C, W, L, T, S, lf, lr, uf, ur, d, r, tw}
## kind: "strut" (T = the strut top U, S = the strut lower mount), "wish" or "multi" (T = the upper ball joint, uf and ur the upper bushes), "trail" (one arm)
static func geo(p: Dictionary, c: Dictionary, susp: Dictionary) -> Dictionary:
	var s := norm(susp)
	var dd := CarPackage.derive(p)
	var tf := float(p["track_f"])
	var tr := float(p["track_r"])
	var tw := float(dd["tyre_w"])
	var r := float(dd["r"])
	var wb := float(p["wheelbase"])
	var clr := float(p["clearance"])
	var z_in := clr + PIVOT_LIFT
	var up_z := z_in + 300.0
	var sub_f := (tf * 0.5 - tw * 0.5 - CarChassis.RAIL_IN) * 0.5    # the subframe pivots: halfway between the centreline and the front rail
	var sub_r := (tr * 0.5 - tw * 0.5 - CarChassis.RAIL_IN) * 0.5
	var yc := tf * 0.5
	var g0 := deg_to_rad(CAMBER0)
	var C := Vector3(0.0, yc, 0.0)
	var W := Vector3(0.0, yc + r * sin(g0), r * cos(g0))
	var L := Vector3(0.0, yc - 45.0, r - 130.0)
	var dz := 560.0
	var U := Vector3(-dz * tan(deg_to_rad(CASTER0)), L.y - dz * tan(deg_to_rad(KPI0)), L.z + dz)
	var front := {"axle": "front", "C": C, "W": W, "L": L, "T": U, "S": U, "r": r, "tw": tw,
		"lf": Vector3(150.0, sub_f, z_in), "lr": Vector3(-150.0, sub_f, z_in), "uf": U, "ur": U, "d": (U - L).length()}
	if s["front"] == FRONT_OPTS[0]:
		front["kind"] = "strut"
		front["S"] = L + (U - L).normalized() * STRUT_K
	else:
		front["kind"] = "wish"
		front["uf"] = Vector3(120.0, sub_f * 0.9, up_z)
		front["ur"] = Vector3(-120.0, sub_f * 0.9, up_z)
	var xr := -wb
	var yr := tr * 0.5
	var Cr := Vector3(xr, yr, 0.0)
	var Wr := Vector3(xr, yr, r)
	var Lr := Vector3(xr, yr - 45.0, r - 130.0)
	var rear := {"axle": "rear", "C": Cr, "W": Wr, "L": Lr, "T": Lr, "S": Lr, "r": r, "tw": tw,
		"lf": Vector3(xr + 300.0, sub_r - 40.0, z_in), "lr": Vector3(xr + 300.0, sub_r + 40.0, z_in), "uf": Lr, "ur": Lr, "d": 0.0}
	if s["rear"] == REAR_OPTS[0]:
		rear["kind"] = "trail"
	else:
		rear["kind"] = "multi"
		rear["lf"] = Vector3(xr + 250.0, sub_r, z_in)
		rear["lr"] = Vector3(xr - 250.0, sub_r, z_in)
		rear["uf"] = Vector3(xr + 200.0, sub_r * 0.9, up_z)
		rear["ur"] = Vector3(xr - 200.0, sub_r * 0.9, up_z)
		rear["T"] = Vector3(xr, yr - 60.0, r + 320.0)
		rear["d"] = (rear["T"] as Vector3).distance_to(Lr)
	return {"front": front, "rear": rear}


## rotate point q about the line a to b by ang (rad)
static func _rot(q: Vector3, a: Vector3, b: Vector3, ang: float) -> Vector3:
	return a + (q - a).rotated((b - a).normalized(), ang)


## the knuckle at lower arm angle a: {L, T, S, W, C, ok}
static func _eval(cn: Dictionary, a: float) -> Dictionary:
	var L0: Vector3 = cn["L"]
	var W0: Vector3 = cn["W"]
	var C0: Vector3 = cn["C"]
	var lf: Vector3 = cn["lf"]
	var lr: Vector3 = cn["lr"]
	var Lp := _rot(L0, lf, lr, a)
	if String(cn["kind"]) == "trail":
		return {"L": Lp, "T": Lp, "S": Lp, "W": _rot(W0, lf, lr, a), "C": _rot(C0, lf, lr, a), "ok": true}
	var T0: Vector3 = cn["T"]
	if String(cn["kind"]) == "strut":
		var S0: Vector3 = cn["S"]
		var Sp := Lp + (T0 - Lp).normalized() * (S0 - L0).length()
		var q := Quaternion((S0 - L0).normalized(), (Sp - Lp).normalized())
		return {"L": Lp, "T": T0, "S": Sp, "W": Lp + q * (W0 - L0), "C": Lp + q * (C0 - L0), "ok": true}
	var ph := _phi(cn, Lp)
	var Tp := _rot(T0, cn["uf"], cn["ur"], float(ph["phi"]))
	var qq := Quaternion((T0 - L0).normalized(), (Tp - Lp).normalized())
	return {"L": Lp, "T": Tp, "S": Tp, "W": Lp + qq * (W0 - L0), "C": Lp + qq * (C0 - L0), "ok": bool(ph["ok"])}


## the upper arm angle that keeps the upper ball joint at the knuckle length d from the lower ball joint (the root nearest zero)
static func _phi(cn: Dictionary, Lp: Vector3) -> Dictionary:
	var T0: Vector3 = cn["T"]
	var d := float(cn["d"])
	var uf: Vector3 = cn["uf"]
	var ur: Vector3 = cn["ur"]
	var g0 := T0.distance_to(Lp) - d
	for dir in [1.0, -1.0]:
		var pf := 0.0
		var pg := g0
		for k in range(1, 161):
			var f: float = dir * deg_to_rad(0.5 * float(k))
			var gv: float = _rot(T0, uf, ur, f).distance_to(Lp) - d
			if (gv > 0.0) != (pg > 0.0):
				var lo := pf
				var hi: float = f
				var glo := pg
				for i in 50:
					var mid := (lo + hi) * 0.5
					var gm: float = _rot(T0, uf, ur, mid).distance_to(Lp) - d
					if (gm > 0.0) == (glo > 0.0):
						lo = mid
						glo = gm
					else:
						hi = mid
				return {"phi": (lo + hi) * 0.5, "ok": true}
			pf = f
			pg = gv
	return {"phi": 0.0, "ok": false}


## the corner at a Bounce of s mm (wheel centre height change, + = up): {L, T, S, W, C, ok}. Every link keeps its length
static func pose(cn: Dictionary, s: float) -> Dictionary:
	var target: float = (cn["W"] as Vector3).z + s
	var lo := -SOLVE_LIM
	var hi := SOLVE_LIM
	var flo: float = (_eval(cn, lo)["W"] as Vector3).z - target
	var fhi: float = (_eval(cn, hi)["W"] as Vector3).z - target
	if (flo > 0.0) == (fhi > 0.0):
		var e := _eval(cn, 0.0)
		e["ok"] = false
		return e
	for i in 60:
		var mid := (lo + hi) * 0.5
		var fm: float = (_eval(cn, mid)["W"] as Vector3).z - target
		if (fm > 0.0) == (flo > 0.0):
			lo = mid
			flo = fm
		else:
			hi = mid
	return _eval(cn, (lo + hi) * 0.5)


## every link length at a pose (the bars check these keep their static values): arm bushes to ball joints, the knuckle
static func links(cn: Dictionary, po: Dictionary) -> Array:
	var out := []
	var L: Vector3 = po["L"]
	var W: Vector3 = po["W"]
	var C: Vector3 = po["C"]
	out.append((cn["lf"] as Vector3).distance_to(L))
	out.append((cn["lr"] as Vector3).distance_to(L))
	out.append(W.distance_to(L))
	out.append(C.distance_to(L))
	out.append(W.distance_to(C))
	if String(cn["kind"]) == "strut":
		out.append((po["S"] as Vector3).distance_to(L))
	elif String(cn["kind"]) != "trail":
		var T: Vector3 = po["T"]
		out.append((cn["uf"] as Vector3).distance_to(T))
		out.append((cn["ur"] as Vector3).distance_to(T))
		out.append(T.distance_to(L))
	return out


# ---------------------------------------------------------------- readouts (front view = y-z, side view = x-z)

## wheel tilt (deg): the wheel plane lean from vertical, seen from the front; negative = the top leans in. camber = atan2(W_y - C_y, W_z - C_z), sign flipped on the right side
static func camber_deg(W: Vector3, C: Vector3) -> float:
	var sg := 1.0 if C.y >= 0.0 else -1.0
	return rad_to_deg(atan2(sg * (W.y - C.y), W.z - C.z))


## kingpin inclination (deg): the steering axis (lower ball joint L to top T) from vertical in the front view; + = the top leans in. KPI = atan2(L_y - T_y, T_z - L_z)
static func kpi_deg(L: Vector3, T: Vector3) -> float:
	return rad_to_deg(atan2(L.y - T.y, T.z - L.z))


## scrub radius (mm): on the ground, the steering axis ground point G to the contact patch C (front view); + = G inboard of C. scrub = C_y - G_y, G = L + t (T - L), t = -L_z / (T_z - L_z)
static func scrub_mm(L: Vector3, T: Vector3, C: Vector3) -> float:
	var t := -L.z / (T.z - L.z)
	var g := L + (T - L) * t
	return C.y - g.y


## caster (deg): the steering axis from vertical in the side view; + = the top leans back. caster = atan2(L_x - T_x, T_z - L_z)
static func caster_deg(L: Vector3, T: Vector3) -> float:
	return rad_to_deg(atan2(L.x - T.x, T.z - L.z))


## the mechanical trail (mm): the ground trail (G_x - C_x, G = the steering axis ground point) times cos(caster), measured along the wheel plane
static func trail_mm(L: Vector3, T: Vector3, C: Vector3) -> float:
	var t := -L.z / (T.z - L.z)
	var g := L + (T - L) * t
	return (g.x - C.x) * cos(deg_to_rad(caster_deg(L, T)))


static func _cross2(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


## the front roll centre height (mm): the instant centre IC of the lower line (lower bush midpoint to L) and the upper line (upper bush midpoint to T; for the strut,
## the line through the strut top T perpendicular to the strut axis). The line from the contact patch C to IC crosses the centreline (y = 0) at the roll centre.
## Parallel lines: IC at infinity along the arms. NAN when no crossing exists.
static func rc_height(po: Dictionary, arms: Dictionary) -> float:
	var C: Vector3 = po["C"]
	var L: Vector3 = po["L"]
	var T: Vector3 = po["T"]
	var pl: Vector3 = ((arms["lf"] as Vector3) + (arms["lr"] as Vector3)) * 0.5
	var Pl := Vector2(pl.y, pl.z)
	var dl := Vector2(L.y, L.z) - Pl
	var du: Vector2
	var Pu: Vector2
	if bool(arms.get("strut", false)):
		Pu = Vector2(T.y, T.z)
		var ax := Vector2(T.y - L.y, T.z - L.z)
		du = Vector2(ax.y, -ax.x)
	else:
		var pu: Vector3 = ((arms["uf"] as Vector3) + (arms["ur"] as Vector3)) * 0.5
		Pu = Vector2(pu.y, pu.z)
		du = Vector2(T.y, T.z) - Pu
	var cr := _cross2(dl, du)
	if absf(cr) < 1e-9 * dl.length() * du.length():
		if absf(dl.x) < 1e-9:
			return NAN
		return C.z - C.y * dl.y / dl.x
	var a := _cross2(Pu - Pl, du) / cr
	var ic := Pl + dl * a
	if absf(ic.x - C.y) < 1e-9:
		return NAN
	var t := -C.y / (ic.x - C.y)
	return C.z + t * (ic.y - C.z)


## the arms of a front corner for rc_height (strut: the strut top line; wishbone: the upper pair)
static func arms_of(cn: Dictionary) -> Dictionary:
	return {"lf": cn["lf"], "lr": cn["lr"], "uf": cn["uf"], "ur": cn["ur"], "strut": String(cn["kind"]) == "strut"}


## the readouts at a Bounce s (front corner): camber, kpi, scrub, caster, trail, rc (roll centre), track (mm, the contact patches spacing), ok
static func readouts(p: Dictionary, c: Dictionary, susp: Dictionary, s: float) -> Dictionary:
	var cn: Dictionary = geo(p, c, susp)["front"]
	var po := pose(cn, s)
	var L: Vector3 = po["L"]
	var T: Vector3 = po["T"]
	var W: Vector3 = po["W"]
	var C: Vector3 = po["C"]
	return {"camber": camber_deg(W, C), "kpi": kpi_deg(L, T), "scrub": scrub_mm(L, T, C), "caster": caster_deg(L, T),
		"trail": trail_mm(L, T, C), "rc": rc_height(po, arms_of(cn)), "track": 2.0 * C.y, "ok": bool(po["ok"])}


## the static readouts and the typical-range rows: [{key, label, value, red, hint}] for the five ranged readouts
static func checks(p: Dictionary, c: Dictionary, susp: Dictionary) -> Array:
	var r := readouts(p, c, susp, 0.0)
	var out := []
	for k in ["camber", "kpi", "scrub", "caster", "rc"]:
		var v := float(r[k])
		out.append({"key": k, "label": RANGE_WORDS[k], "value": v, "red": not in_range(k, v), "hint": hint(k, v)})
	return out


## the free space at a Bounce s: the smallest gap between a tyre (a box round each wheel, both sides, both axles) and any chassis member
## (mm; below 0 = they overlap). Chassis axes: x across, y up, z from the nose (= front overhang minus car x)
static func clearance(p: Dictionary, c: Dictionary, susp: Dictionary, s: float) -> float:
	var g := geo(p, c, susp)
	var foh := float(p["front_oh"])
	var mem := CarChassis.members(p, c)
	var best := INF
	for axle in ["front", "rear"]:
		var cn: Dictionary = g[axle]
		var po := pose(cn, s)
		var W: Vector3 = po["W"]
		var r := float(cn["r"])
		var hw := float(cn["tw"]) * 0.5
		for sd in [1.0, -1.0]:
			var lo := Vector3(sd * W.y - hw, W.z - r, foh - W.x - r)
			var hi := Vector3(sd * W.y + hw, W.z + r, foh - W.x + r)
			for m in mem:
				best = minf(best, _box_gap(lo, hi, m["lo"], m["hi"]))
	return best


static func _box_gap(alo: Vector3, ahi: Vector3, blo: Vector3, bhi: Vector3) -> float:
	var dx := maxf(0.0, maxf(alo.x - bhi.x, blo.x - ahi.x))
	var dy := maxf(0.0, maxf(alo.y - bhi.y, blo.y - ahi.y))
	var dz := maxf(0.0, maxf(alo.z - bhi.z, blo.z - ahi.z))
	if dx == 0.0 and dy == 0.0 and dz == 0.0:
		var pen := minf(minf(minf(ahi.x, bhi.x) - maxf(alo.x, blo.x), minf(ahi.y, bhi.y) - maxf(alo.y, blo.y)), minf(ahi.z, bhi.z) - maxf(alo.z, blo.z))
		return -pen
	return Vector3(dx, dy, dz).length()


# ---------------------------------------------------------------- the 3D view

const LOWER_COL := Color(1.0, 0.12, 0.3)       # lower arms: bright crimson (the chassis rails are green and pink)
const UPPER_COL := Color(0.0, 0.95, 0.95)      # upper arms: bright cyan
const STRUT_COL := Color(1.0, 0.55, 0.1)       # the MacPherson strut: bright orange
const KNUCKLE_COL := Color(1.0, 0.9, 0.2)      # the knuckle block: yellow
const TWIST_COL := Color(1.0, 0.3, 0.9)        # the rear trailing arms and the twist beam: magenta
const PIVOT_COL := Color(0.95, 0.95, 0.95)     # the pivot spheres: white
const ARM_R := 0.0175                          # m, the links are 35 mm thick
const KNUCKLE_HALF := 0.0225                   # m, the knuckle block is 45 mm square
const PIVOT_R := 0.013                         # m, the pivot sphere radius


## a car point (mm) in the 3D frame (m): the car left = +X, up = +Y, front = +Z, the axles midpoint at the origin (like CarPackage.build_3d)
static func to3(v: Vector3, wb: float) -> Vector3:
	return Vector3(v.y, v.z, v.x + wb * 0.5) * 0.001


## a point mirrored to the right side (sd = -1 flips y)
static func _mir(v: Vector3, sd: float) -> Vector3:
	return Vector3(v.x, sd * v.y, v.z)


## every link and pivot of one corner at a pose, for one side (sd = +1 left, -1 right), in car mm. [{name, type, a, b}]
## type: "lower", "upper", "strut", "twist" (rear trailing arm), "knuckle" (a block between the ball joints) or "pivot" (a sphere, a == b)
static func link_list(cn: Dictionary, po: Dictionary, sd: float) -> Array:
	var out := []
	var L := _mir(po["L"], sd)
	var W := _mir(po["W"], sd)
	var lf := _mir(cn["lf"], sd)
	var lr := _mir(cn["lr"], sd)
	var pv := [["pivot_lf", lf], ["pivot_lr", lr], ["pivot_ball", L]]
	if String(cn["kind"]) == "trail":
		out.append({"name": "link_trail_f", "type": "twist", "a": L, "b": lf})
		out.append({"name": "link_trail_r", "type": "twist", "a": L, "b": lr})
		out.append({"name": "link_knuckle", "type": "knuckle", "a": L, "b": W})
	else:
		var T := _mir(po["T"], sd)
		out.append({"name": "link_lower_f", "type": "lower", "a": lf, "b": L})
		out.append({"name": "link_lower_r", "type": "lower", "a": lr, "b": L})
		if String(cn["kind"]) == "strut":
			var S := _mir(po["S"], sd)
			out.append({"name": "link_strut", "type": "strut", "a": T, "b": S})
			out.append({"name": "link_knuckle", "type": "knuckle", "a": L, "b": S})
			pv.append(["pivot_strut_top", T])
			pv.append(["pivot_strut_mount", S])
		else:
			var uf := _mir(cn["uf"], sd)
			var ur := _mir(cn["ur"], sd)
			out.append({"name": "link_upper_f", "type": "upper", "a": uf, "b": T})
			out.append({"name": "link_upper_r", "type": "upper", "a": ur, "b": T})
			out.append({"name": "link_knuckle", "type": "knuckle", "a": L, "b": T})
			pv.append(["pivot_upper_f", uf])
			pv.append(["pivot_upper_r", ur])
			pv.append(["pivot_ball_top", T])
	for q in pv:
		out.append({"name": String(q[0]), "type": "pivot", "a": q[1], "b": q[1]})
	return out


## the two ends (m, 3D frame) of a link node built by build_3d, read from its transform and its mesh
static func ends(mi: MeshInstance3D) -> Array:
	var h := 0.0
	if mi.mesh is CylinderMesh:
		h = (mi.mesh as CylinderMesh).height
	elif mi.mesh is BoxMesh:
		h = (mi.mesh as BoxMesh).size.y
	var d := mi.quaternion * Vector3.UP
	return [mi.position - d * h * 0.5, mi.position + d * h * 0.5]


## the suspension node (arms, knuckles, pivots, tyres) for both sides of both axles at a Bounce s. The right side is the mirror of the left
static func build_3d(p: Dictionary, c: Dictionary, susp: Dictionary, s: float) -> Node3D:
	var root := Node3D.new()
	root.name = "suspension3d"
	var wb := float(p["wheelbase"])
	var g := geo(p, c, susp)
	for axle in ["front", "rear"]:
		var cn: Dictionary = g[axle]
		var po := pose(cn, s)
		for sd in [1.0, -1.0]:
			var node := Node3D.new()
			node.name = "%s_%s" % [axle, "left" if sd > 0.0 else "right"]
			root.add_child(node)
			var W := _mir(po["W"], sd)
			var tyre := MeshInstance3D.new()
			tyre.name = "tyre"
			var cy := CylinderMesh.new()
			cy.top_radius = float(cn["r"]) * 0.001
			cy.bottom_radius = float(cn["r"]) * 0.001
			cy.height = float(cn["tw"]) * 0.001
			tyre.mesh = cy
			# the wheel axle is the normal of the wheel plane, which leans with the camber (the plane holds the contact patch and the centre)
			var C := _mir(po["C"], sd)
			var up := to3(W - C, wb).normalized()
			var nrm := Vector3.FORWARD.cross(up).normalized()
			tyre.quaternion = Quaternion(Vector3.UP, nrm)
			tyre.position = to3(W, wb)
			tyre.material_override = _mat(Color(0.06, 0.06, 0.07))
			node.add_child(tyre)
			for li in link_list(cn, po, sd):
				var a := to3(li["a"], wb)
				var b := to3(li["b"], wb)
				match String(li["type"]):
					"pivot":
						_ball(node, String(li["name"]), a)
					"knuckle":
						_bar(node, String(li["name"]), a, b, KNUCKLE_HALF, KNUCKLE_COL, true)
					"lower":
						_bar(node, String(li["name"]), a, b, ARM_R, LOWER_COL, false)
					"upper":
						_bar(node, String(li["name"]), a, b, ARM_R, UPPER_COL, false)
					"strut":
						_bar(node, String(li["name"]), a, b, ARM_R, STRUT_COL, false)
					"twist":
						_bar(node, String(li["name"]), a, b, ARM_R, TWIST_COL, false)
		if String(cn["kind"]) == "trail":
			# the twist beam: the cross member joining the two trailing arms (the left and right ball points)
			var poL := _mir(po["L"], 1.0)
			var poR := _mir(po["L"], -1.0)
			_bar(root, "link_twist_beam_%s" % axle, to3(poL, wb), to3(poR, wb), ARM_R, TWIST_COL, false)
	return root


## a link between two points: a cylinder (or a box) ARM_R thick along a -> b, named so the bars find it
static func _bar(parent: Node3D, nm: String, a: Vector3, b: Vector3, rad: float, col: Color, box: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var len := maxf(a.distance_to(b), 0.001)
	if box:
		var bm := BoxMesh.new()
		bm.size = Vector3(rad * 2.0, len, rad * 2.0)
		mi.mesh = bm
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = rad
		cm.bottom_radius = rad
		cm.height = len
		mi.mesh = cm
	mi.position = (a + b) * 0.5
	mi.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	mi.material_override = _mat(col, true)
	parent.add_child(mi)


## a pivot: a small sphere at a ball joint or a bush
static func _ball(parent: Node3D, nm: String, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var sm := SphereMesh.new()
	sm.radius = PIVOT_R
	sm.height = PIVOT_R * 2.0
	mi.mesh = sm
	mi.position = at
	mi.material_override = _mat(PIVOT_COL, true)
	parent.add_child(mi)


## a material; on_top: drawn over the chassis floor pan (the arms run under the floor, at the subframe height), so they read in the 3D view
static func _mat(col: Color, on_top := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if on_top:
		m.no_depth_test = true
		m.render_priority = 1
	return m
