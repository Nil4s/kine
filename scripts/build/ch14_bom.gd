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
