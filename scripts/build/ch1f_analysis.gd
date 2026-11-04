class_name Ch1fAnalysis
extends RefCounted
## CH1f: period, El Centro response, expansive-clay heave and NBR 6123 wind of a Ch1fSys system on a Ch1fSoil site (or fixed base).
## Heavy lifting (assembly, banded solves, Newmark) is in KineFrameNative via Ch10Frame.solve.

const SYS := preload("res://scripts/build/ch1f_systems.gd")
const SO := preload("res://scripts/build/ch1f_soil.gd")
const FR := preload("res://scripts/build/ch10_frame.gd")
const SIM := preload("res://scripts/build/ch10_sim.gd")
const PLF := 14.5939     # N/m per plf
const CAP_WOOD := 400.0 * PLF     # SDPWS 2015 Table 4.3A nominal unit shear of the 3/8 OSB 6d 6 in row
const CAP_LSF := 400.0 * PLF      # UNVERIFIED: stand-in (AISI S400 not read)
const CAP_MAS := SYS.FVK * SYS.T_WALL
const CA := {"A": 0.8, "B": 1.0, "C": 1.2, "D": 1.6, "E": 2.5}   # NBR 15421 seismic amplification Ca by site class (UNVERIFIED, from memory)
const AG_ZONE0 := 0.025   # g, NBR 15421 zone 0 (UNVERIFIED)


static func capacity(sys_name: String) -> float:
	match sys_name:
		"masonry":
			return CAP_MAS
		"lsf":
			return CAP_LSF
	return CAP_WOOD


static func first_period(sys: Dictionary, s, opts := {}, dir := 0) -> Dictionary:
	var asm := SYS.assemble(sys, s, opts)
	var model: Dictionary = asm["model"]
	var n: int = (model["xyz"] as PackedFloat64Array).size() / 3
	var load := PackedFloat64Array()
	load.resize(n * 6)
	for i in sys["top"]:
		load[i * 6 + dir] = 1.0
	var st := FR.solve(model, {"type": "static", "loads": load})
	if st.has("error"):
		return {"error": st["error"]}
	var md := FR.solve(model, {"type": "modal", "start": st["u"], "iters": opts.get("iters", 4)})
	if md.has("error"):
		return {"error": md["error"]}
	return {"T": TAU / float(md["omega"]), "omega": md["omega"], "asm": asm, "phi": md["phi"]}


## El Centro NS, x direction, 5 pct Rayleigh at T and T/5, dt 0.01 s, `seconds` of the record. Needs a soil (base shear is the soil spring force).
static func quake(sys: Dictionary, s: Dictionary, opts := {}) -> Dictionary:
	var pr := first_period(sys, s, opts, 0)
	if pr.has("error"):
		return pr
	var asm: Dictionary = pr["asm"]
	var model: Dictionary = asm["model"]
	var F: int = asm["f"]
	var w1: float = pr["omega"]
	var w2 := 5.0 * w1
	var zeta := 0.05
	var alpha := 2.0 * zeta * w1 * w2 / (w1 + w2)
	var beta := 2.0 * zeta / (w1 + w2)
	var dt := 0.01
	var seconds: float = opts.get("seconds", 30.0)
	var ag := SIM.resample(SIM.load_record(), dt, 1.0, seconds)
	var tops: PackedInt32Array = sys["top"]
	var rec := PackedInt32Array([F * 6 + 0, F * 6 + 5])
	for t in tops:
		rec.append(t * 6 + 0)
	var ns := ag.size() - 1
	var r := FR.solve(model, {"type": "newmark", "dt": dt, "nsteps": ns, "ag": ag, "dir": 0, "alpha": alpha, "beta": beta, "record": rec})
	if r.has("error"):
		return r
	var ru: PackedFloat64Array = r["rec_u"]
	var rv: PackedFloat64Array = r["rec_v"]
	var g: Dictionary = asm["g"]
	var cols := ns + 1
	var vmax := 0.0
	var dmax := 0.0
	var umax_top := 0.0
	for st in cols:
		var uF := ru[st]
		var th := ru[cols + st]
		vmax = maxf(vmax, absf(g["kx"] * uF + g["cx"] * rv[st]))
		for k in tops.size():
			var rel := ru[(2 + k) * cols + st] - uF + th * SYS.H
			dmax = maxf(dmax, absf(rel))
			umax_top = maxf(umax_top, absf(ru[(2 + k) * cols + st]))
	return {"T": pr["T"], "V": vmax, "drift": dmax / SYS.H, "drift_m": dmax, "u_top": umax_top, "mass": SYS.model_mass(model), "steps": ns}


## differential-heave analysis: base nodes carried by vertical soil springs (stiffness from Gazetas Kz spread over the base nodes), x/z held;
## ground displacement field = mound(dh); response = the change in pier angular distortion against the gravity-only solve.
static func heave(sys: Dictionary, s: Dictionary, opts := {}) -> Dictionary:
	var src: Dictionary = sys["model"]
	var model := {"xyz": src["xyz"], "beams": src["beams"], "springs": src["springs"], "mass": src["mass"], "fixed": (src["fixed"] as PackedInt32Array).duplicate()}
	if src.has("ties"):
		model["ties"] = src["ties"]
	var base: PackedInt32Array = sys["base"]
	var g := SO.gazetas(s)
	var kz := PackedFloat64Array()
	var kn: float = g["ky"] / base.size()
	var xyz: PackedFloat64Array = model["xyz"]
	var fx: PackedInt32Array = model["fixed"]
	for b in base:
		fx.append_array([b * 6 + 0, b * 6 + 2])
		kz.append_array([b * 6 + 1, kn])
	model["fixed"] = fx
	model["dofk"] = kz
	# base nodes also need rotation support only through the members; vertical spring alone is enough for a stable frame with the fixed x/z
	var n := xyz.size() / 3
	var w := PackedFloat64Array()
	w.resize(n * 6)
	var mass: PackedFloat64Array = model["mass"]
	for i in n:
		w[i * 6 + 1] = -SYS.G_ACC * mass[i]
	var wt: float = (sys["mass_total"] + SYS.LX * SYS.LZ * SYS.SLAB_T * SYS.RHO_RC) * SYS.G_ACC
	var q := wt / (SYS.LX * SYS.LZ)
	var dh := SO.heave_free(q, opts.get("h_act", SO.H_ACTIVE), opts.get("eps", SO.EPS_FREE), opts.get("ps", SO.P_SWELL))
	var wh := w.duplicate()
	for b in base:
		var dz := SO.mound(xyz[b * 3], xyz[b * 3 + 2], dh)
		wh[b * 6 + 1] += kn * dz
	var u0 := FR.solve(model, {"type": "static", "loads": w})
	var u1 := FR.solve(model, {"type": "static", "loads": wh})
	if u0.has("error") or u1.has("error"):
		return {"error": str(u0.get("error", u1.get("error")))}
	var du: PackedFloat64Array = u1["u"]
	var d0: PackedFloat64Array = u0["u"]
	var gmax := 0.0
	var vmax := 0.0
	var ratio := 0.0
	var cap := capacity(sys["name"])
	for p in sys["panels"]:
		var e1 := _ext(xyz, du, d0, p["a1"], p["b1"])
		var e2 := _ext(xyz, du, d0, p["a2"], p["b2"])
		var gam: float = absf(e1 - e2) * 0.5 * p["dl"] / (p["dx"] * p["h"])
		var v: float = p["kh"] * gam * p["h"] / p["b"]
		gmax = maxf(gmax, gam)
		vmax = maxf(vmax, v)
		ratio = maxf(ratio, v / cap)
	return {"q": q, "dh": dh, "gamma": gmax, "v": vmax, "ratio": ratio, "cap": cap}


static func _ext(xyz: PackedFloat64Array, u1: PackedFloat64Array, u0: PackedFloat64Array, a: int, b: int) -> float:
	var d := Vector3(xyz[b * 3] - xyz[a * 3], xyz[b * 3 + 1] - xyz[a * 3 + 1], xyz[b * 3 + 2] - xyz[a * 3 + 2])
	var nrm := d.normalized()
	var du := Vector3(u1[b * 6] - u1[a * 6] - (u0[b * 6] - u0[a * 6]), u1[b * 6 + 1] - u1[a * 6 + 1] - (u0[b * 6 + 1] - u0[a * 6 + 1]), u1[b * 6 + 2] - u1[a * 6 + 2] - (u0[b * 6 + 2] - u0[a * 6 + 2]))
	return nrm.dot(du)


## NBR 6123 wind in +z on the long eave wall: base shear (walls only, like CH10) and the structural drift ratio. Half the shear is applied at the top nodes.
static func wind(sys: Dictionary, s, opts := {}) -> Dictionary:
	var wd := SO.wind(SYS.HW + 0.7)
	var A := SYS.LX * SYS.HW
	var Fz: float = wd["p_net"] * A
	var asm := SYS.assemble(sys, s, opts)
	var model: Dictionary = asm["model"]
	var n: int = (model["xyz"] as PackedFloat64Array).size() / 3
	var load := PackedFloat64Array()
	load.resize(n * 6)
	var tops: PackedInt32Array = sys["top"]
	for t in tops:
		load[t * 6 + 2] = 0.5 * Fz / tops.size()
	var st := FR.solve(model, {"type": "static", "loads": load})
	if st.has("error"):
		return {"error": st["error"]}
	var u: PackedFloat64Array = st["u"]
	var mean := 0.0
	for t in tops:
		mean += u[t * 6 + 2]
	mean /= tops.size()
	var ref := 0.0
	if asm["f"] >= 0:
		ref = u[asm["f"] * 6 + 2] + u[asm["f"] * 6 + 3] * SYS.H
	return {"Fz": Fz, "q": wd["q"], "vk": wd["vk"], "drift": (mean - ref) / SYS.H, "total_drift": mean / SYS.H}


## equivalent-static upper bound of the NBR 15421 zone 0 base shear with R = 1: V = 2.5 ag Ca W (class letter)
static func seismic0_shear(mass_kg: float, cls: String) -> float:
	return 2.5 * AG_ZONE0 * CA[cls] * mass_kg * SYS.G_ACC
