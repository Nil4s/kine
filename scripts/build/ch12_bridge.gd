class_name Ch12Bridge
extends RefCounted
## CH12: a pedestrian footbridge that sways (the London Millennium Bridge, June 2000) as a Ch10Frame model plus Dallard's synchronous lateral excitation crowd.
## Every number and its source is in docs/CH12_REFERENCE.md (the section choice is recorded there before any run). Units N, m, kg, s.
## Axes: x along the span, y up, z across. Node numbering: station s (0..NSEG) owns nodes 3s (edge girder at -ZG), 3s+1 (deck centre line, "spine"), 3s+2 (girder at +ZG).
## Members (the Kine Part, data/challenges/ch12_bridge.json): two steel box edge girders, a cross frame at every station (girder to girder through the spine), the deck mass on the spine,
## simple supports at both ends (vertical and lateral held, the girders free to rotate and to slide along x at the right end).

const FR := preload("res://scripts/build/ch10_frame.gd")

const L := 144.0                 # central span (Dallard et al. 2001: 144 m centre span)
const NSEG := 48                 # 3 m stations
const ZG := 1.9                  # girder offset from the centre line (deck 4 m wide: Dallard et al.)
const E_ST := 210e9
const G_ST := 81e9
const RHO_ST := 7850.0
const A_G := 0.053               # girder steel area, m2 (chosen so the lateral first mode lands at the paper's 0.48 Hz with M_PER_LEN)
const IZ_G := 0.045              # girder own vertical bending inertia
const IY_G := 0.005              # girder own lateral bending inertia
const J_G := 0.02
const A_C := 0.02                # cross frame (stiff: the girders act as one section in plan)
const I_C := 1.0
const RHO_C := 100.0
const M_PER_LEN := 2000.0        # total dead mass per metre incl. the deck (UNVERIFIED recall of the paper's order of magnitude)
const ZETA := 0.006              # structural damping, 0.5 to 0.8 percent before retrofit (Dallard et al.)
const K_PED := 300.0             # N s/m, lateral force per unit deck velocity (Dallard et al. 2001)
const F0_PED := 25.0             # N, lateral force amplitude of one pedestrian
const F_SPREAD := 0.1            # Hz, total spread of the crowd's lateral frequencies about the deck frequency (uniform)
const DAMP_ZETA := 0.05          # total lateral damping with the retrofit dampers
const DAMP_ST0 := 19             # the dampers sit on spine stations 19..29 (the middle of the span)
const DAMP_ST1 := 29


static func nid(s: int, k: int) -> int:
	return s * 3 + k


## the members as boxes (m): the data that becomes the Kine Part
static func members() -> Array:
	var out: Array = []
	var seg := L / NSEG
	for side in 2:
		var zc := -ZG if side == 0 else ZG
		out.append({"name": "girder.%s" % ("S" if side == 0 else "N"), "kind": "girder", "box_m": [0.0, -1.8, zc - 0.5, L, 0.0, zc + 0.5]})
	out.append({"name": "deck", "kind": "deck", "box_m": [0.0, -0.1, -ZG, L, 0.0, ZG]})
	for s in range(0, NSEG + 1, 4):
		out.append({"name": "cross.%d" % s, "kind": "cross", "box_m": [s * seg - 0.15, -1.2, -ZG, s * seg + 0.15, -1.0, ZG]})
	out.append({"name": "abutment.W", "kind": "support", "box_m": [-3.0, -4.0, -3.0, 0.0, -1.8, 3.0]})
	out.append({"name": "abutment.E", "kind": "support", "box_m": [L, -4.0, -3.0, L + 3.0, -1.8, 3.0]})
	return out


static func part_json() -> Dictionary:
	var feats: Array = []
	var id := 1
	for m in members():
		var b: Array = m["box_m"]
		feats.append({"t": "prim", "id": "f%d" % id, "name": m["name"], "kind": "box", "op": "new", "x": b[0] * 1000.0, "y": b[1] * 1000.0, "z": b[2] * 1000.0, "w": (b[3] - b[0]) * 1000.0, "h": (b[4] - b[1]) * 1000.0, "d": (b[5] - b[2]) * 1000.0})
		id += 1
		var col := [0.55, 0.57, 0.60]
		if m["kind"] == "deck":
			col = [0.45, 0.46, 0.48]
		elif m["kind"] == "support":
			col = [0.62, 0.60, 0.55]
		feats.append({"t": "appear", "id": "f%d" % id, "name": "Paint " + m["name"], "body": float(id / 2 - 1), "color": col, "metal": 0.0, "rough": 0.8, "preset": "Custom"})
		id += 1
	return {"kind": "ch12_bridge", "reference": "docs/CH12_REFERENCE.md", "part": {"name": "Footbridge, sway study (CH12)", "seq": 912, "version": 1, "features": feats}}


## the frame model + the per-node masses and the span. nseg overrides NSEG (small frames for the C++ == GDScript bar)
static func build(nseg := NSEG) -> Dictionary:
	var seg := L / nseg
	var xyz := PackedFloat64Array()
	for s in nseg + 1:
		for k in 3:
			xyz.append_array([s * seg, 0.0, (k - 1) * ZG])
	var rows: Array = []
	for s in nseg:
		for k in [0, 2]:
			rows.append([nid(s, k), nid(s + 1, k), A_G, IZ_G, IY_G, J_G, E_ST, G_ST, RHO_ST, 0.0, 1.0, 0.0])
	for s in nseg + 1:
		rows.append([nid(s, 0), nid(s, 1), A_C, I_C, I_C, 2.0 * I_C, E_ST, G_ST, RHO_C, 0.0, 1.0, 0.0])
		rows.append([nid(s, 1), nid(s, 2), A_C, I_C, I_C, 2.0 * I_C, E_ST, G_ST, RHO_C, 0.0, 1.0, 0.0])
	var beams := PackedFloat64Array()
	for r in rows:
		beams.append_array(r)
	var nn := (nseg + 1) * 3
	var fixed := PackedInt32Array()
	for s in [0, nseg]:
		for k in 3:
			fixed.append(nid(s, k) * 6 + 1)
			fixed.append(nid(s, k) * 6 + 2)
	fixed.append(nid(0, 1) * 6)
	# masses: the girders' own mass is in the elements; the deck takes the rest of M_PER_LEN on the spine
	var cross_per_len := RHO_C * A_C * 2.0 * ZG / seg
	var deck_per_len := M_PER_LEN - 2.0 * RHO_ST * A_G - cross_per_len
	var mass := PackedFloat64Array()
	mass.resize(nn)
	var lump := PackedFloat64Array()      # total translational mass per node (extra + the elements' halves) for the modal mass
	lump.resize(nn)
	for s in nseg + 1:
		var ln := seg * (0.5 if s == 0 or s == nseg else 1.0)
		mass[nid(s, 1)] = deck_per_len * ln
		lump[nid(s, 1)] = deck_per_len * ln + cross_per_len * ln
		lump[nid(s, 0)] = RHO_ST * A_G * ln
		lump[nid(s, 2)] = RHO_ST * A_G * ln
	return {"model": {"xyz": xyz, "beams": beams, "fixed": fixed, "mass": mass}, "nn": nn, "lump": lump, "seg": seg, "nseg": nseg}


## first mode of a kind: "lat" (uz) or "vert" (uy): omega, phi (6n, max 1 at the middle spine), modal mass (phi max 1), frequency Hz
static func mode(br: Dictionary, kind: String, iters := 20) -> Dictionary:
	var nn: int = br["nn"]
	var nseg: int = br["nseg"]
	var start := PackedFloat64Array()
	start.resize(nn * 6)
	var dof := 2 if kind == "lat" else 1
	for s in nseg + 1:
		for k in 3:
			start[nid(s, k) * 6 + dof] = sin(PI * s / nseg)
	var md := FR.solve(br["model"], {"type": "modal", "start": start, "iters": iters})
	var phi: PackedFloat64Array = md["phi"]
	var mid := phi[nid(nseg / 2, 1) * 6 + dof]
	for i in phi.size():
		phi[i] = phi[i] / mid
	var lump: PackedFloat64Array = br["lump"]
	var mg := 0.0
	for i in nn:
		mg += lump[i] * (phi[i * 6 + 1] * phi[i * 6 + 1] + phi[i * 6 + 2] * phi[i * 6 + 2] + phi[i * 6] * phi[i * 6])
	return {"omega": md["omega"], "f": md["omega"] / TAU, "phi": phi, "mgen": mg, "dof": dof}


## Dallard's critical number N = 8 pi zeta f M / k (M the modal mass, phi max 1, uniform crowd)
static func n_paper(zeta: float, f: float, mgen: float, k := K_PED) -> float:
	return 8.0 * PI * zeta * f * mgen / k


## the crowd: n pedestrians spread uniformly along the span, lateral frequencies spread uniformly about omega0, start phases from fixed sequences (no RNG state)
## kind "locked": theta' = omega + cp v cos(theta) with cp set so the crowd's in-phase gain is K_PED;  "random": cp = 0 (free-running, the control)
static func crowd(br: Dictionary, n: int, omega0: float, kind := "locked") -> Dictionary:
	var seg: float = br["seg"]
	var nseg: int = br["nseg"]
	var n1 := PackedInt32Array()
	var n2 := PackedInt32Array()
	var w := PackedFloat64Array()
	var om := PackedFloat64Array()
	var th := PackedFloat64Array()
	var wspread := TAU * F_SPREAD
	for i in n:
		var x := (i + 0.5) / n * L
		var s := mini(int(x / seg), nseg - 1)
		n1.append(nid(s, 1))
		n2.append(nid(s + 1, 1))
		w.append(x / seg - s)
		om.append(omega0 + wspread * (fposmod(i * 0.6180339887, 1.0) - 0.5))
		th.append(TAU * fposmod(i * 0.7548776662 + 0.3, 1.0))
	var cp := 4.0 * wspread * K_PED / (PI * F0_PED) if kind == "locked" else 0.0
	return {"n1": n1, "n2": n2, "w": w, "omega": om, "theta0": th, "F0": F0_PED, "cp": cp, "dir": 2}


## dashpots for the retrofit: lateral dampers on the spine at stations DAMP_ST0..DAMP_ST1 sized for zeta_total
static func dampers(br: Dictionary, lat: Dictionary, zeta_total := DAMP_ZETA) -> PackedFloat64Array:
	var phi: PackedFloat64Array = lat["phi"]
	var sum2 := 0.0
	for s in range(DAMP_ST0, DAMP_ST1 + 1):
		var p := phi[nid(s, 1) * 6 + 2]
		sum2 += p * p
	var c_total := (zeta_total - ZETA) * 2.0 * float(lat["omega"]) * float(lat["mgen"])
	var cd := c_total / sum2
	var o := PackedFloat64Array()
	for s in range(DAMP_ST0, DAMP_ST1 + 1):
		o.append(float(nid(s, 1) * 6 + 2))
		o.append(cd)
	return o


## a run: mid-span lateral displacement history. o: n (pedestrians), kind ("locked" | "random" | "none"), retrofit (bool), T, dt, amp0 (m), zeta
static func run(br: Dictionary, lat: Dictionary, o: Dictionary, force_gd := false) -> Dictionary:
	var dt: float = o.get("dt", 0.02)
	var T: float = o.get("T", 300.0)
	var ns := int(round(T / dt))
	var om1: float = lat["omega"]
	var zeta: float = o.get("zeta", ZETA)
	var nseg: int = br["nseg"]
	var model: Dictionary = br["model"].duplicate()
	if o.get("retrofit", false):
		model["dashpots"] = o["dash"] if o.has("dash") else dampers(br, lat, o.get("zeta_total", DAMP_ZETA))
	var nn: int = br["nn"]
	var phi: PackedFloat64Array = lat["phi"]
	var u0 := PackedFloat64Array()
	u0.resize(nn * 6)
	var a0: float = o.get("amp0", 0.006)
	for i in nn * 6:
		u0[i] = a0 * phi[i]
	var job := {"type": "newmark", "dt": dt, "nsteps": ns, "alpha": 2.0 * zeta * om1, "beta": 0.0, "u0": u0,
		"record": PackedInt32Array([nid(nseg / 2, 1) * 6 + 2, nid(nseg / 2, 1) * 6 + 1]), "snap_every": int(o.get("snap_every", 0))}
	var kind: String = o.get("kind", "locked")
	var n: int = o.get("n", 0)
	if n > 0 and kind != "none":
		job["crowd"] = crowd(br, n, om1, kind)
	var t0 := Time.get_ticks_msec()
	var r := FR.solve(model, job, force_gd)
	r["wall_ms"] = Time.get_ticks_msec() - t0
	r["dt"] = dt
	r["ns"] = ns
	return r


## per-cycle amplitude: max |u| over each window of one period t1 (s); returns {t, a}
static func envelope(u: PackedFloat64Array, dt: float, t1: float) -> Dictionary:
	var wn := int(round(t1 / dt))
	var ts := PackedFloat64Array()
	var am := PackedFloat64Array()
	var k := 0
	while k + wn <= u.size():
		var m := 0.0
		for i in range(k, k + wn):
			m = maxf(m, absf(u[i]))
		ts.append((k + wn) * dt)
		am.append(m)
		k += wn
	return {"t": ts, "a": am}


## growth rate sigma (1/s) of the amplitude: least squares of ln(amp) on t over windows with t >= t_skip and amp <= a_max (the linear regime)
static func growth(env: Dictionary, t_skip: float, a_max: float) -> Dictionary:
	var ts: PackedFloat64Array = env["t"]
	var am: PackedFloat64Array = env["a"]
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var sxy := 0.0
	var n := 0
	for i in ts.size():
		if ts[i] < t_skip or am[i] > a_max or am[i] <= 0.0:
			continue
		var y := log(am[i])
		sx += ts[i]
		sy += y
		sxx += ts[i] * ts[i]
		sxy += ts[i] * y
		n += 1
	if n < 3:
		return {"sigma": NAN, "n": n}
	var den := n * sxx - sx * sx
	return {"sigma": (n * sxy - sx * sy) / den, "n": n}
