extends RefCounted
## CH14 bill of materials with prices, and the CHEAPEST design that still passes the working bars (4 torque with an empty can, 5 grip, 6 placement without air,
## 2b stroke chains). Prices are USD, typical 2026 retail for small packs, ASSUMED (no supplier quote was fetched): replace PRICE with what Nick pays and the
## search reruns. The arm physics is ch14_arm.gd; this file only counts and multiplies.
const A := preload("res://scripts/build/ch14_arm.gd")

const PRICE := {
	"syr5": 0.25, "syr10": 0.30, "syr20": 0.45,          # each, Luer syringes from a 10-50 pack
	"hose_pvc": 0.30, "hose_pu98": 1.20, "hose_pa12": 1.80,   # per metre, 4 x 6 mm tube
	"pla_kg": 22.0,                                        # PLA+ filament per kg
	"boom_kg": {"cardboard": 0.0, "pine": 8.0, "plywood": 17.0, "pla": 22.0},   # boom material per kg (cardboard: a reused box; pine 30 x 30 strip ~2.5/m; 3 mm ply ~33/m2)
	"base_ply": 7.0,                                       # 18 mm plywood baseboard 460 x 340 and the console offcut
	"dowel": 0.10,                                         # 4 x 40 mm steel dowel pin, each
	"pad": 0.20,                                           # TPU or rubber jaw pads (a pair)
	"sundries": 1.00,                                      # screws, zip ties, glue
}
const DOWELS := 6          # shoulder, elbow, wrist, 3 slave pivots (the horn pins are printed)
const INFILL := 0.45       # printed mass / solid model mass for the printed parts (walls + 20 pct infill), ASSUMED


## the printed PLA+ parts and their solid model volumes (mm3), built through the kernel by the caller (pass {name: mm3}); kg of filament
static func print_kg(vols_mm3: Dictionary) -> float:
	var v := 0.0
	for k in vols_mm3:
		v += float(vols_mm3[k])
	return v * 1e-9 * float(A.MAT["pla"]["rho"]) * INFILL


## metres of each tube type for a design: "mix" = nylon-12 runs with polyurethane flex loops (d.flex m per circuit)
static func hose_m(d: Dictionary) -> Dictionary:
	var out := {"pvc": 0.0, "pu98": 0.0, "pa12": 0.0}
	for j in d["hose_len"]:
		var L: float = d["hose_len"][j]
		if String(d["hose"]) == "mix":
			var f: float = float(d["flex"][j])
			out["pu98"] += f
			out["pa12"] += L - f
		else:
			out[String(d["hose"])] += L
	return out


## the BOM: [{"item", "qty", "unit", "each", "cost"}] and the total. print_vols: {part: mm3} of the printed parts (boom links excluded: they are the boom material)
static func bom(d: Dictionary, print_vols: Dictionary) -> Dictionary:
	var lines := []
	var add := func(item: String, qty: float, unit: String, each: float) -> void:
		lines.append({"item": item, "qty": qty, "unit": unit, "each": each, "cost": qty * each})
	var n := {5: 0, 10: 0, 20: 0}
	for j in d["cyl"]:
		for sz in d["cyl"][j]:
			n[int(sz)] += 1
	for sz in [5, 10, 20]:
		if n[sz] > 0:
			add.call("Luer syringe %d mL (bore %.2f mm)" % [sz, A.SYR[sz]["bore"]], n[sz], "pcs", PRICE["syr%d" % sz])
	var hm := hose_m(d)
	for k in ["pa12", "pu98", "pvc"]:
		if hm[k] > 0.0:
			add.call("Tube 4 x 6 mm %s" % {"pa12": "nylon-12", "pu98": "polyurethane 98A", "pvc": "soft PVC"}[k], hm[k], "m", PRICE["hose_" + k])
	var mat: String = d["mat"]
	var boom_kg := A.link_mass(mat, d["L1"]) + A.link_mass(mat, d["L2"])
	add.call("Boom links (%s, %.0f + %.0f mm)" % [mat, d["L1"], d["L2"]], boom_kg, "kg", PRICE["boom_kg"][mat])
	add.call("PLA+ printed parts (turntable, pinion, rack, gripper, jaws, %.0f pct of solid)" % (100.0 * INFILL), print_kg(print_vols), "kg", PRICE["pla_kg"])
	add.call("Baseboard + console, 18 mm plywood", 1, "set", PRICE["base_ply"])
	add.call("Steel dowel pin 4 x 40 mm", DOWELS, "pcs", PRICE["dowel"])
	add.call("Jaw pads TPU / rubber", 1, "pair", PRICE["pad"])
	add.call("Screws, zip ties, glue", 1, "lot", PRICE["sundries"])
	var tot := 0.0
	for l in lines:
		tot += float(l["cost"])
	return {"lines": lines, "total": tot}


## do the working bars pass for this design? {"ok", "why"}: 2b (lever chains), 4 (empty can, 30 N, min margin >= 1.5), 5 (full can grip >= 1.5), 6 (2 x in-plane <= tau_x, 2 x sideways <= tau_y, no air)
static func works(d: Dictionary) -> Dictionary:
	var why := PackedStringArray()
	for j in ["sh", "el", "wr"]:
		var ch := A.chain(d, j)
		if not (ch["monotone"] and ch["use"] <= 0.95 and ch["min_arm"] >= 20.0):
			why.append("2b " + j)
	var wm := A.worst_margins(d, d["mat"], A.CAN_M0, A.F_HAND)
	for j in wm:
		if float(wm[j]["margin"]) < 1.5:
			why.append("4 %s %.2f" % [j, wm[j]["margin"]])
	if float(A.grip(d, A.CAN_M1, 1.5, A.F_HAND)["ratio"]) < 1.5:
		why.append("5 grip")
	var tol := A.stack_tolerance(d["pitch"])
	var e := A.placement_error(d, 0.0)
	if 2.0 * float(e["in"]) > float(tol["x"]) or 2.0 * float(e["y"]) > float(tol["y"]):
		why.append("6 place %.1f mm" % (2.0 * float(e["in"])))
	return {"ok": why.is_empty(), "why": ", ".join(why), "in": e["in"]}


## every combination of boom material x tube x syringe sizes (master|slave per joint from {10,20}, gripper/wrist from {5,10}); the cheapest that works
static func cheapest(print_vols: Dictionary) -> Dictionary:
	var rows := []
	for mat in ["cardboard", "pine", "plywood", "pla"]:
		for hose in ["pvc", "pu98", "pa12", "mix"]:
			for big in [[20, 20], [10, 20], [10, 10]]:
				for small in [[5, 5], [10, 10]]:
					var d := A.design()
					d["mat"] = mat
					d["hose"] = hose
					d["cyl"]["sh"] = big.duplicate()
					d["cyl"]["el"] = big.duplicate()
					d["cyl"]["gr"] = small.duplicate()
					var w := works(d)
					var b := bom(d, print_vols)
					rows.append({"mat": mat, "hose": hose, "big": big, "small": small, "ok": w["ok"], "why": w["why"], "cost": b["total"], "in": w["in"]})
	rows.sort_custom(func(a, b): return float(a["cost"]) < float(b["cost"]))
	var best := {}
	for r in rows:
		if r["ok"]:
			best = r
			break
	return {"rows": rows, "best": best}


# ---------------------------------------------------------------- G8BOM: the arm as an Assembly with "bom" fields (scripts/build/assembly_bom.gd)

const PT := preload("res://scripts/build/ch14_parts.gd")
const PRINT_ALT := ["pla"]   # the printed holes are compensated for PLA+ (CH14_REFERENCE section 7): another filament needs its own numbers first
const BOOM_ALT := ["cardboard", "pine", "plywood", "pla"]   # the materials ch14_arm.gd models (MAT)
const TUBE_ALT := ["tube_pvc", "tube_pu98", "tube_pa12"]


static func _with(rec: Dictionary, b: Dictionary) -> Dictionary:
	var r := rec.duplicate(true)
	r["bom"] = b
	return r


## a 4 x 40 mm steel dowel pin, a Part
static func dowel_rec() -> Dictionary:
	var p := PT.PB.new("Steel dowel pin 4 x 40 mm")
	p.cyl(0, 0, 0, "z", PT.PIN_D / 2.0, 40.0, PT.STEEL)
	return p.rec(13)


## the design d as an Assembly whose "bom" fields price it as bom(d) does: the ten syringes bought (the shoulder and elbow masters may be a
## 10 or a 20 mL), the printed parts at INFILL of their solid, the boom links in any MAT material (their mass from the CAD solid, not from
## ch14_arm's 30 mm section), the plywood set, six dowels, and the tube, pads and sundries as extras. "bom_check": ch14_works = works()
static func assembly(d := {}) -> Dictionary:
	if d.is_empty():
		d = A.design()
	var asm := Assembly.make("CH14 syringe arm")
	for j in ["ba", "sh", "el", "wr", "gr"]:
		for k in 2:
			var sz := int(d["cyl"][j][k])
			var b := {"buy": "syr%d" % sz}
			if k == 0 and j in ["sh", "el"]:
				b = {"buy": "syr%d" % sz, "alt": ["syr10", "syr20"], "role": "master_lever", "name": "Master syringes of the shoulder and elbow (10 or 20 mL; drawn as %d mL)" % sz}
			Assembly.add_part(asm, _with(PT.syringe_barrel(sz), b), "%s %s" % ["Master" if k == 0 else "Slave", j])
	Assembly.add_part(asm, _with(PT.baseboard(), {"buy": "ply18_base_set", "material": "plywood"}))
	Assembly.add_part(asm, _with(PT.console(), {"material": "plywood", "included": "cut from the baseboard set (Baseboard + console, 18 mm plywood)"}))
	for f in [PT.turntable(), PT.pinion(), PT.rack(), PT.gripper_body(), PT.jaw(), PT.jaw()]:
		Assembly.add_part(asm, _with(f, {"material": "pla", "fill": INFILL, "alt": PRINT_ALT}))
	var mat := String(d["mat"])
	for f in [PT.upper_arm(), PT.forearm()]:
		Assembly.add_part(asm, _with(f, {"material": mat, "alt": BOOM_ALT, "need": {"sigma_MPa": 45.0}, "role": "boom"}))
	for i in DOWELS:
		Assembly.add_part(asm, _with(dowel_rec(), {"buy": "dowel_4x40", "material": "steel"}))
	var hm := hose_m(d)
	var ex: Array = []
	var hose := String(d["hose"])
	var runs := "tube_pa12" if hose == "mix" else "tube_" + hose
	var flex := "tube_pu98"
	var run_m: float = hm["pa12"] if hose == "mix" else float(hm[hose])
	ex.append({"name": "Tube 4 x 6 mm, the runs", "bom": {"buy": runs, "qty": run_m, "alt": TUBE_ALT, "need": {"E_MPa": 50.0}, "role": "hose_runs"}})
	if hose == "mix":
		ex.append({"name": "Tube 4 x 6 mm, the flex loops at the joints", "bom": {"buy": flex, "qty": float(hm["pu98"]), "role": "hose_flex"}})
	ex.append({"name": "Jaw pads TPU / rubber", "bom": {"buy": "pad_pair"}})
	ex.append({"name": "Screws, zip ties, glue", "bom": {"buy": "sundries"}})
	asm["bom_extra"] = ex
	asm["bom_check"] = "ch14_works"
	return asm


## the ch14_arm design an assembly made by assembly() describes now ({} with "why" when its choices are not one the arm model knows)
static func design_of(asm: Dictionary) -> Dictionary:
	var d := A.design()
	var booms := {}
	var masters := {}
	for p in asm["parts"]:
		var b: Dictionary = (p["rec"] as Dictionary).get("bom", {})
		match String(b.get("role", "")):
			"boom":
				booms[String(b.get("material", ""))] = true
			"master_lever":
				masters[String(b.get("buy", ""))] = true
	var runs := ""
	var flex := ""
	for e in asm.get("bom_extra", []):
		var b: Dictionary = (e as Dictionary).get("bom", {})
		if String(b.get("role", "")) == "hose_runs":
			runs = String(b.get("buy", ""))
		elif String(b.get("role", "")) == "hose_flex":
			flex = String(b.get("buy", ""))
	if booms.size() != 1 or not A.MAT.has(String(booms.keys()[0])):
		return {"why": "the boom links are not one material the arm model knows (%s)" % str(booms.keys())}
	d["mat"] = String(booms.keys()[0])
	if masters.size() != 1 or not String(masters.keys()[0]) in ["syr10", "syr20"]:
		return {"why": "the shoulder and elbow masters differ (%s)" % str(masters.keys())}
	var msz := int(String(masters.keys()[0]).trim_prefix("syr"))
	d["cyl"]["sh"][0] = msz
	d["cyl"]["el"][0] = msz
	if flex == "" or flex == runs:
		d["hose"] = runs.trim_prefix("tube_")
	elif runs == "tube_pa12" and flex == "tube_pu98":
		d["hose"] = "mix"
	else:
		return {"why": "runs %s with %s loops is a tube mix the arm model does not know" % [runs, flex]}
	if not A.HOSES.has(String(d["hose"])) and String(d["hose"]) != "mix":
		return {"why": "the tube %s is not in the arm model" % runs}
	return d


## AssemblyBom's "ch14_works" check: the arm still passes its working bars (works(): 2b, 4, 5, 6) with the assembly's choices
static func check_asm(asm: Dictionary) -> Dictionary:
	var d := design_of(asm)
	if d.has("why"):
		return {"ok": false, "why": String(d["why"])}
	var w := works(d)
	return {"ok": bool(w["ok"]), "why": "fails CH14 bars " + String(w["why"]) if not w["ok"] else ""}
