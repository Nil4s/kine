class_name C57PrintEst
extends RefCounted
## C57 (Nick 11-03 "5 million to print, are we printing diamonds"): a SLICER-LIKE print estimate instead of solid plastic at real size.
##   mass  = (shell + infill) x density: the shell is the surface area x SHELL_MM (2 perimeters 0.45 mm each, plus the top / bottom skins, averaged),
##           the inside is infill (default 15 %) of what is left. Never more than the solid volume.
##   time  = extruded volume / the printer's average volumetric flow (the flow a slicer's estimate really averages, below the nozzle's top flow
##           because of acceleration and corners) + a fixed warm-up.
##   bed   = the part sorted largest side first against the printer's bed sorted the same way (it can be turned to lie any way).
##   oversize = says so, and gives mass / time / cost again at 1:10, 1:50 and 1:100 (all three sides scaled; the shell stays 0.85 mm thick).
##   sanity = a line when the mass is over 5 kg.
## Printer numbers (bed in mm, avg flow in mm3/s) are Kine's own table beside C03Tools.PRESETS; "" (no printer chosen) takes DEFAULT, which is the
## Bambu-class flow and says so on the estimate line (C63: it was 3.0, which made a 20 mm cube 17 min against Bambu Studio's 10.2).
## Each flow is fitted to Bambu Studio's own CLI slicing a 20 mm cube and 3DBenchy at 0.20 mm Standard (reference G-code in
## C:/Users/Nick/tools/kine_workers/out/c57/ref and out/c63/ref, settings in the header of tests/c63_test.gd). Resin has no slicer reference here: ESTIMATE.
const SHELL_MM := 0.85
const INFILL := 0.15
const WARMUP_S := 15.0
const SANITY_KG := 5.0
const SCALES := [10, 50, 100]
const DEFAULT_NAME := "a typical printer (Bambu-class)"
const DEFAULT := {"bed": Vector3(220, 220, 250), "flow": 4.5}
## "ref": true = fitted to a Bambu Studio slice (measured); false = an estimate
const PRINTERS := {
	"Resin": {"bed": Vector3(192, 120, 200), "flow": 2.0, "ref": false},
	"Bambu PLA": {"bed": Vector3(256, 256, 256), "flow": 4.5, "ref": true},
	"Prusa PETG": {"bed": Vector3(250, 210, 210), "flow": 1.83, "ref": true},
	"Ender FDM": {"bed": Vector3(220, 220, 250), "flow": 1.59, "ref": true},
}


static func printer_of(rec: Dictionary) -> Dictionary:
	return PRINTERS.get(String(rec.get("printer_preset", "")), DEFAULT)


## one solid: vol_mm3, area_mm2 -> {"cm3": plastic used, "grams", "seconds"}
static func plastic(vol_mm3: float, area_mm2: float, flow: float, density := 1.24, infill := INFILL) -> Dictionary:
	var shell := minf(vol_mm3, area_mm2 * SHELL_MM)
	var used := shell + (vol_mm3 - shell) * clampf(infill, 0.0, 1.0)
	return {"cm3": used / 1000.0, "grams": used / 1000.0 * density, "seconds": used / maxf(flow, 0.1) + WARMUP_S}


static func fits(size: Vector3, bed: Vector3) -> bool:
	var a := [size.x, size.y, size.z]
	var b := [bed.x, bed.y, bed.z]
	a.sort()
	b.sort()
	return a[0] <= b[0] + 0.001 and a[1] <= b[1] + 0.001 and a[2] <= b[2] + 0.001


## solids = CutList.solids rows (wood rows are skipped). Whole-part answer:
## {"grams","seconds","brl","oversize","size","bed","scaled":[{"n","grams","seconds","brl","fits"}],"sanity":bool}
static func estimate(rec: Dictionary, solids: Array, pr: Dictionary) -> Dictionary:
	var pt := printer_of(rec)
	var flow := float(pt["flow"])
	var bed: Vector3 = pt["bed"]
	var dens := float(pr["pla_g_cm3"])
	var perkg := float(pr["pla_brl_kg"])
	var out := {"grams": 0.0, "seconds": 0.0, "brl": 0.0, "oversize": false, "size": Vector3.ZERO, "bed": bed, "scaled": [], "sanity": false}
	var rows := []
	for s in solids:
		if bool(s["wood"]):
			continue
		rows.append(s)
		var d: Array = s["dims"]
		var sz := Vector3(d[2], d[1], d[0])
		if not fits(sz, bed):
			out["oversize"] = true
		if sz.length() > (out["size"] as Vector3).length():
			out["size"] = sz
	for s in rows:
		var p := plastic(float(s["vol_cm3"]) * 1000.0, float(s.get("area_mm2", 0.0)), flow, dens)
		out["grams"] += p["grams"]
		out["seconds"] += p["seconds"]
	out["brl"] = float(out["grams"]) / 1000.0 * perkg
	out["sanity"] = float(out["grams"]) > SANITY_KG * 1000.0
	if out["oversize"]:
		for n in SCALES:
			var g := 0.0
			var t := 0.0
			var allfit := true
			var k := 1.0 / float(n)
			for s in rows:
				var d: Array = s["dims"]
				if not fits(Vector3(d[2], d[1], d[0]) * k, bed):
					allfit = false
				var p := plastic(float(s["vol_cm3"]) * 1000.0 * k * k * k, float(s.get("area_mm2", 0.0)) * k * k, flow, dens)
				g += p["grams"]
				t += p["seconds"]
			(out["scaled"] as Array).append({"n": n, "grams": g, "seconds": t, "brl": g / 1000.0 * perkg, "fits": allfit})
	return out


## C63: the printer the time assumes, in words ("on Bambu PLA", "on Resin (estimate)", or the default's name)
static func assumed(rec: Dictionary) -> String:
	var pn := String(rec.get("printer_preset", ""))
	if not PRINTERS.has(pn):
		return "on " + DEFAULT_NAME
	return "on %s%s" % [pn, "" if bool(PRINTERS[pn].get("ref", false)) else " (estimate)"]


static func mass_words(g: float) -> String:
	return ("%s kg" % CutList.brl_num(g / 1000.0, 1)) if g >= 1000.0 else ("%s g" % CutList.brl_num(g, 1))


static func time_words(s: float) -> String:
	var m := int(round(s / 60.0))
	if m < 60:
		return "%d min" % maxi(m, 1)
	var h := m / 60
	if h < 48:
		return "%d h %02d min" % [h, m % 60]
	return "%s days" % CutList.brl_num(float(h) / 24.0, 0)


## the Export dialog's lines for the 3D printing checklist ([] when the part has no plastic)
static func lines(rec: Dictionary) -> Array:
	var ss := CutList.solids(rec)
	var any := false
	for s in ss:
		any = any or not bool(s["wood"])
	if not any:
		return []
	var e := estimate(rec, ss, CutList.prices())
	var pn := String(rec.get("printer_preset", ""))
	var out := []
	out.append("OK    print estimate %s: %s of plastic (walls + %d%% infill), %s, %s" % [assumed(rec), mass_words(e["grams"]), int(INFILL * 100.0), time_words(e["seconds"]), CutList.brl_words(e["brl"])])
	if e["oversize"]:
		var b: Vector3 = e["bed"]
		var z: Vector3 = e["size"]
		out.append("WARN  bigger than the printer bed (%.0f x %.0f x %.0f mm; the part is %.0f x %.0f x %.0f mm): at full size %s, %s. Print a model of it instead:" % [b.x, b.y, b.z, z.x, z.y, z.z, mass_words(e["grams"]), time_words(e["seconds"])])
		for r in e["scaled"]:
			out.append("OK    model at 1:%d: %s, %s, %s%s" % [r["n"], mass_words(r["grams"]), time_words(r["seconds"]), CutList.brl_words(r["brl"]), "" if bool(r["fits"]) else " (still bigger than the bed)"])
	if e["sanity"]:
		out.append("WARN  %s of plastic is over %d kg, and a full spool is 1 kg: check the size is in the units you meant" % [mass_words(e["grams"]), int(SANITY_KG)])
	return out
