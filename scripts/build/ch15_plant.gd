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
