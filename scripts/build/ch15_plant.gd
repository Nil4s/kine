extends RefCounted
## CH15: the plant's engineering numbers (docs/CH15_REFERENCE.md has every source): primary heat balance, the steam cycle on IF97, the electrical system and
## its one-line model, decay heat (Way-Wigner) and the emergency feedwater that boils it off, the containment sphere's membrane stress.
const W := preload("res://scripts/build/ch15_if97.gd")

const Q_TH := 3771.0        # MWt, Eletronuclear
const P_GROSS := 1350.0     # MWe
const P_NET := 1280.0       # MWe
const LOOPS := 4
const M_LOOP := 4700.0      # kg/s per loop (FSAR via UFMG)
const T_IN := 291.3         # C
const T_OUT := 326.1        # C
const T_MEAN := 308.6       # C
const P_PRIM := 15.5        # MPa (the brief's; the plant's is 15.4 to 15.8)
const P_SG := 64.2 * 0.0980665   # 64.2 kg/cm2 abs at the turbine inlet, MPa
const X_SG := 0.9975        # moisture 0.25 pct
const SW_T := 27.0          # C seawater
const SW_FLOW := 74.4       # m3/s
const SW_RHO := 1023.0
const SW_CP := 3.99e-3      # MJ/kg K
const TTD := 3.0            # K (ASSUMED)
const CP_IG := 1.872        # kJ/kg K, steam as an ideal gas (the planted model)
const R_IG := 0.4615
# electrical
const PF := 0.9
const V_GEN := 25.0         # kV
const S_NAME := 1458.0      # MVA nameplate
const V_GRID := 500.0
const S_MT := 1560.0        # 3 x 520 MVA single-phase (ASSUMED)
const S_UAT := 50.0         # each of 2 (ASSUMED)
const S_SST := 90.0         # standby from 138 kV (ASSUMED)
const PF_HOUSE := 0.85
const DG_MW := 5.4
const DG_MVA := 6.6
const N_DG := 4
const REDUND := 2           # 4 x 50 pct: N+2
const P_SAFE := 9.2         # MW (ASSUMED)
const D2_KW := 860.0
const D2_KVA := 1050.0
# decay
const T_OP := 13.0 * 30.44 * 86400.0
const EFW_CAP := 36.0       # kg/s
const T_EFW := 303.15       # K
# containment
const P_DESIGN := 0.53      # MPa gauge
const D_SPHERE := 56.0      # m


## Q = m cp dT over the vessel. opts loops: how many loops' flow (the planted control uses 1)
static func primary(opts := {}) -> Dictionary:
	var m := M_LOOP * int(opts.get("loops", LOOPS))
	var cp: float = W.r1(P_PRIM, T_MEAN + 273.15)["cp"]
	var dt := T_OUT - T_IN
	var q := m * cp * dt / 1000.0
	var qh := m * (float(W.r1(P_PRIM, T_OUT + 273.15)["h"]) - float(W.r1(P_PRIM, T_IN + 273.15)["h"])) / 1000.0
	return {"m": m, "cp": cp, "dT": dt, "Q": q, "err": absf(q - Q_TH) / Q_TH, "Q_h": qh}


## the condenser from the cited seawater: rise, condensing temperature (C) and pressure (MPa)
static func condenser() -> Dictionary:
	var rise := (Q_TH - P_GROSS) / (SW_FLOW * SW_RHO * SW_CP)
	var tc := SW_T + rise + TTD
	return {"dT_sw": rise, "Tc": tc, "pc": W.psat(tc + 273.15)}


## the ideal Rankine cycle: model "if97" (water and steam) or "ideal_gas" (the planted control)
static func rankine(model := "if97") -> Dictionary:
	var cd := condenser()
	var pc: float = cd["pc"]
	var tc := W.tsat(pc)
	var th := W.tsat(P_SG)
	var carnot := 1.0 - tc / th
	if model == "ideal_gas":
		var wt := CP_IG * th * (1.0 - pow(pc / P_SG, R_IG / CP_IG))
		var qin := CP_IG * (th - tc)
		return {"eta": wt / qin, "carnot": carnot, "Th": th, "Tc": tc, "pc": pc, "wt": wt, "qin": qin}
	var f: Dictionary = W.r1(pc, tc)
	var g: Dictionary = W.r2(pc, tc)
	var fh: Dictionary = W.r1(P_SG, th)
	var gh: Dictionary = W.r2(P_SG, th)
	var h1: float = f["h"]
	var h2: float = h1 + float(f["v"]) * (P_SG - pc) * 1000.0
	var h3: float = float(fh["h"]) + X_SG * (float(gh["h"]) - float(fh["h"]))
	var s3: float = float(fh["s"]) + X_SG * (float(gh["s"]) - float(fh["s"]))
	var x4: float = (s3 - float(f["s"])) / (float(g["s"]) - float(f["s"]))
	var h4: float = h1 + x4 * (float(g["h"]) - h1)
	var wt2 := h3 - h4
	var wp := h2 - h1
	var qin2 := h3 - h2
	return {"eta": (wt2 - wp) / qin2, "carnot": carnot, "Th": th, "Tc": tc, "pc": pc, "h1": h1, "h2": h2, "h3": h3, "h4": h4, "s3": s3, "x4": x4, "wt": wt2, "wp": wp, "qin": qin2}


## opts diesels: how many system-1 diesels (the planted control uses 3)
static func electrical(opts := {}) -> Dictionary:
	var s := P_GROSS / PF
	var n := int(opts.get("diesels", N_DG))
	var house := P_GROSS - P_NET
	var avail := float(n - REDUND) * DG_MW
	return {"S_gen": s, "S_name": S_NAME, "I": s * 1e6 / (sqrt(3.0) * V_GEN * 1e3), "I_name": S_NAME * 1e6 / (sqrt(3.0) * V_GEN * 1e3), "S_mt": S_MT,
		"house_MW": house, "house_MVA": house / PF_HOUSE, "S_uat": 2.0 * S_UAT, "S_sst": S_SST, "n_dg": n, "dg_MW": DG_MW, "redund": REDUND,
		"dg_avail": avail, "P_safe": P_SAFE, "dg_ok": avail >= P_SAFE}


## the one-line model: buses {id, kv, label, kind}, transformers {id, mva, hv, lv, from, to}, generators, breakers. Drawn by ch15_draw.gd
static func one_line() -> Dictionary:
	var buses := [{"id": "GRID500", "kv": V_GRID, "label": "500 kV grid (Furnas)", "kind": "grid"}, {"id": "GRID138", "kv": 138.0, "label": "138 kV line", "kind": "grid"},
		{"id": "GEN", "kv": V_GEN, "label": "Generator bus (isolated phase)", "kind": "gen"}]
	for b in ["BA", "BB", "BC", "BD"]:
		buses.append({"id": b, "kv": 10.0, "label": "Normal bus " + b, "kind": "normal"})
	for b in ["BU", "BV", "BW", "BX"]:
		buses.append({"id": b, "kv": 10.0, "label": "Emergency bus " + b, "kind": "safety"})
	for k in 4:
		buses.append({"id": "D2_%d" % (k + 1), "kv": 0.4, "label": "Emergency feed bus %d" % (k + 1), "kind": "d2"})
	var xf := [{"id": "MT", "mva": S_MT, "hv": V_GRID, "lv": V_GEN, "from": "GRID500", "to": "GEN", "label": "Main step-up 3 x 520 MVA"},
		{"id": "UAT1", "mva": S_UAT, "hv": V_GEN, "lv": 10.5, "from": "GEN", "to": "BA", "label": "Unit aux 1"},
		{"id": "UAT2", "mva": S_UAT, "hv": V_GEN, "lv": 10.5, "from": "GEN", "to": "BC", "label": "Unit aux 2"},
		{"id": "SST", "mva": S_SST, "hv": 138.0, "lv": 10.5, "from": "GRID138", "to": "BD", "label": "Standby"}]
	for k in 4:
		xf.append({"id": "LT%d" % (k + 1), "mva": 2.5, "hv": 10.0, "lv": 0.4, "from": ["BU", "BV", "BW", "BX"][k], "to": "D2_%d" % (k + 1), "label": "Load centre %d" % (k + 1)})
	var gens := [{"id": "G", "mva": S_NAME, "kv": V_GEN, "pf": PF, "bus": "GEN", "label": "Generator THFF 1458 MVA"}]
	for k in 4:
		gens.append({"id": "DG%d" % (k + 1), "mva": DG_MVA, "mw": DG_MW, "kv": 10.0, "bus": ["BU", "BV", "BW", "BX"][k], "label": "Diesel %d" % (k + 1)})
		gens.append({"id": "D2G%d" % (k + 1), "mva": D2_KVA / 1000.0, "mw": D2_KW / 1000.0, "kv": 0.4, "bus": "D2_%d" % (k + 1), "label": "D2 diesel %d" % (k + 1)})
	var brk := [{"id": "GCB", "kv": V_GEN, "between": ["G", "GEN"], "label": "Generator breaker"}, {"id": "CB500", "kv": V_GRID, "between": ["MT", "GRID500"], "label": "500 kV breaker"}]
	return {"buses": buses, "xfmrs": xf, "gens": gens, "breakers": brk, "ties": [["BA", "BU"], ["BB", "BV"], ["BC", "BW"], ["BD", "BX"], ["BA", "BB"], ["BC", "BD"]]}


## Way-Wigner decay heat fraction P/P0 at t s after shutdown, after T s at power
static func decay(t: float, t_op: float) -> float:
	return 0.0622 * (pow(t, -0.2) - pow(t + t_op, -0.2))


static func boiloff(t: float, t_op: float) -> Dictionary:
	var fr := decay(t, t_op)
	var p := fr * Q_TH
	var th := W.tsat(P_SG)
	var dh := float(W.r2(P_SG, th)["h"]) - float(W.r1(P_SG, T_EFW)["h"])
	return {"frac": fr, "P_MW": p, "dh": dh, "m": p * 1000.0 / dh, "cap": EFW_CAP}


## the steel sphere's membrane stress (MPa). case "angra2" (WStE 51, 30 mm, allowable 0.67 Rp(145 C)) or "angra3" (WStE 370, 38 mm, the cited 214);
## formula "sphere" p R / 2t or "cylinder" p R / t (the planted wrong formula)
static func containment(case := "angra2", formula := "sphere") -> Dictionary:
	var t := 30.0 if case == "angra2" else 38.0
	var allow := 0.67 * 500.0 * 320.0 / 370.0 if case == "angra2" else 214.0
	var r := D_SPHERE / 2.0 * 1000.0
	var sig := P_DESIGN * r / ((2.0 if formula == "sphere" else 1.0) * t)
	return {"sigma": sig, "allow": allow, "p": P_DESIGN, "R": r, "t": t}


# ------------------------------------------------ L4 (docs/CH15_REFERENCE.md section 9; every input there is ASSUMED)
const SK_GRID := 25000.0     # MVA at 500 kV
const UK_MT := 0.14
const XD2 := 0.28
const C_MAX := 1.1
const UK_UAT := 0.10
const V_HOUSE := 10.5
const MOT_SHARE := 0.8
const MOT_LOAD_MW := 35.0
const MOT_ETA := 0.95
const MOT_COS := 0.85
const ILR := 5.0


## IEC 60909 initial symmetrical short-circuit currents (kA). opts uk_uat. ik_sys / ik_gen: what a GCB must break (fault on the generator / transformer side);
## ik_net10 + ik_mot10 = ik_house: the 10.5 kV house bus (both sources in parallel behind one UAT, plus the motors)
static func short_circuit(opts := {}) -> Dictionary:
	var c := C_MAX
	var kt := 0.95 * c / (1.0 + 0.6 * UK_MT)
	var zq := c * V_GEN * V_GEN / SK_GRID
	var zt := kt * UK_MT * V_GEN * V_GEN / S_MT
	var zs := zq + zt
	var kg := c / (1.0 + XD2 * sin(acos(PF)))
	var zg := kg * XD2 * V_GEN * V_GEN / S_NAME
	var zp := zs * zg / (zs + zg) * pow(V_HOUSE / V_GEN, 2.0)
	var uk_u := float(opts.get("uk_uat", UK_UAT))
	var ku := 0.95 * c / (1.0 + 0.6 * uk_u)
	var zu := ku * uk_u * V_HOUSE * V_HOUSE / S_UAT
	var ik_net := c * V_HOUSE / (sqrt(3.0) * (zp + zu))
	var sm := MOT_SHARE * MOT_LOAD_MW / (MOT_ETA * MOT_COS)
	var zm := V_HOUSE * V_HOUSE / (ILR * sm)
	var ik_mot := c * V_HOUSE / (sqrt(3.0) * zm)
	return {"ik_sys": c * V_GEN / (sqrt(3.0) * zs), "ik_gen": c * V_GEN / (sqrt(3.0) * zg), "ik_net10": ik_net, "ik_mot10": ik_mot, "ik_house": ik_net + ik_mot}


const DG_XD2 := 0.16
const DG_SEQ := [1.2, 1.2, 0.9, 0.8, 0.5]   # MW per step
const ILR_DG := 5.5


## emergency diesel: voltage dip of each start step, S_start / (S_start + Sk''gen). opts one_step: the whole sequence at once (the planted control)
static func diesel_start(opts := {}) -> Dictionary:
	var ssc := DG_MVA / DG_XD2
	var steps: Array = [0.0]
	var tot := 0.0
	for p in DG_SEQ:
		tot += p
	steps = [tot] if opts.get("one_step", false) else DG_SEQ
	var dips := []
	for p in steps:
		var ss: float = ILR_DG * p / (MOT_ETA * MOT_COS)
		dips.append(ss / (ss + ssc))
	return {"ssc": ssc, "dips": dips, "total_MW": tot}


## external-pressure buckling of the sphere (Zoelly x knock-down). opts t (mm)
static func buckling(opts := {}) -> Dictionary:
	var t := float(opts.get("t", 30.0))
	var e := 195000.0
	var nu := 0.3
	var r := D_SPHERE / 2.0 * 1000.0
	var pcl := 2.0 * e / sqrt(3.0 * (1.0 - nu * nu)) * pow(t / r, 2.0)
	return {"p_cl": pcl, "p_allow": 0.2 * pcl / 2.0, "p_ext": 0.02, "t": t}


const OUTAGE := 30.0 * 86400.0


## decay heat fraction of a core of `batches` equal-weight batches irradiated 1..batches cycles (T_OP each, OUTAGE between), Way-Wigner superposition
## (an interval that ended tau_e and began tau_s before shutdown adds 0.0622 [(t + tau_e)^-0.2 - (t + tau_s)^-0.2]). Weights must sum to 1: -1 otherwise.
static func decay_history(t: float, opts := {}) -> float:
	var nb := int(opts.get("batches", 3))
	if nb != 3:
		return -1.0   # the equal thirds of a 3-batch core are the only weights on offer: any other count does not sum to 1
	var s := 0.0
	for b in range(1, nb + 1):
		for j in b:
			var te := float(j) * (T_OP + OUTAGE)
			s += 0.0622 * (pow(t + te, -0.2) - pow(t + te + T_OP, -0.2))
	return s / float(nb)


static func boiloff_history(t: float) -> Dictionary:
	var fr := decay_history(t)
	var p := fr * Q_TH
	var th := W.tsat(P_SG)
	var dh := float(W.r2(P_SG, th)["h"]) - float(W.r1(P_SG, T_EFW)["h"])
	return {"frac": fr, "P_MW": p, "m": p * 1000.0 / dh}
