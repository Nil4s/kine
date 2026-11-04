extends SceneTree
## godot --path . -s tests/c63_test.gd     (C63: the print estimate with no printer chosen lands on a measured flow and names the printer it assumes)
## Row C63 of LEDGER_210. Before: DEFAULT flow 3.0 gave a 20 mm cube 17 min against Bambu Studio's 10.2.
## REFERENCES, all from Bambu Studio's own CLI (bambu-studio.exe --slice) on 20 mm cube / shipped 3DBenchy STL, "0.20mm Standard" process of each profile
##   (2 walls, 4 top / 3 bottom layers, 20 % sparse infill), 0.4 nozzle, PLA unless noted. G-code in C:/Users/Nick/tools/kine_workers/out/c57/ref (X1C) and out/c63/ref (the rest):
##   Bambu PLA   X1 Carbon, Bambu PLA Basic @BBL X1C       cube 10m12s  Benchy 34m09s
##   Bambu A1    A1, Bambu PLA Basic @BBL A1               cube 28m28s  Benchy 1h40m55s   (extra reference, not a Kine preset: the slower Bambu)
##   Ender FDM   Creality Ender-3 V2, Generic PLA @Creality  cube 28m30s  Benchy 1h37m53s
##   Prusa PETG  Prusa MK3S, Generic PETG @Prusa             cube 24m25s  Benchy 1h26m37s   (same printer with Generic PLA @Prusa: 33m47s / 1h49m29s)
##   Resin       no slicer reference here -> must be labelled "estimate"
## Bars (written before the first run; the flows were set from the ratio ref time / X1C ref time, then the bars read):
##   1 DEFAULT   no printer: cube (3.73 g, 20 pct infill) and Benchy each within 25 pct of the X1C minutes
##   2 PRESETS   every preset that has a reference (Bambu PLA, Ender FDM, Prusa PETG): cube and Benchy minutes within 25 pct of that printer's reference
##   3 LABEL     the estimate line of a part with no printer says "on a typical printer (Bambu-class)"; with Ender FDM chosen "on Ender FDM"; with Resin "on Resin (estimate)"
##   4 TABLE     PRINTERS entries have a ref flag; exactly the ones without a reference (Resin) say "estimate" in the line, and the source file's table comment names them
##   5 CONTROL   the old flow 3.0 fails bar 1 on the cube (it is the origin behaviour), and a zero-minute stub fails it too
const REF := {
	"Bambu PLA": {"cube": 10.2, "benchy": 34.15},
	"Ender FDM": {"cube": 28.5, "benchy": 97.88},
	"Prusa PETG": {"cube": 24.42, "benchy": 86.62},
}
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func within(v: float, ref: float) -> bool:
	return absf(v - ref) <= 0.25 * ref


func stl_numbers(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	f.seek(80)
	var n := f.get_32()
	var vol := 0.0
	var area := 0.0
	for i in n:
		f.seek(84 + i * 50 + 12)
		var a := Vector3(f.get_float(), f.get_float(), f.get_float())
		var b := Vector3(f.get_float(), f.get_float(), f.get_float())
		var c := Vector3(f.get_float(), f.get_float(), f.get_float())
		vol += a.dot(b.cross(c)) / 6.0
		area += (b - a).cross(c - a).length() * 0.5
	return {"vol": absf(vol), "area": area}


func mins(vol: float, area: float, flow: float) -> float:
	return C57PrintEst.plastic(vol, area, flow, 1.26, 0.20)["seconds"] / 60.0


func box_rec(nm: String, w: float, d: float, h: float) -> Dictionary:
	var rec := Part.make(nm)
	var fs: Array = rec["features"]
	var s1 := PartTemplates._sk(fs, "front", [PartTemplates._rect(Vector2(0, 0), Vector2(w, d))])
	PartTemplates._ex(fs, s1, "extrude", h, "new")
	rec["seq"] = fs.size()
	rec["kept"] = true
	return rec


func _init() -> void:
	var wd = create_timer(300.0)
	wd.timeout.connect(func():
		print("FAIL watchdog: c63 timed out")
		quit(1))
	var bn := stl_numbers("C:/Program Files/Bambu Studio/resources/model/3DBenchy.stl")
	ok(not bn.is_empty(), "0 the Benchy STL is installed")
	var df := float(C57PrintEst.DEFAULT["flow"])
	var cm := mins(8000.0, 2400.0, df)
	var bm := mins(bn["vol"], bn["area"], df)
	ok(within(cm, REF["Bambu PLA"]["cube"]) and within(bm, REF["Bambu PLA"]["benchy"]), "1 default flow %.2f: cube %.1f min (ref %.1f), Benchy %.1f min (ref %.1f)" % [df, cm, REF["Bambu PLA"]["cube"], bm, REF["Bambu PLA"]["benchy"]])
	for nm in REF:
		var fl := float(C57PrintEst.PRINTERS[nm]["flow"])
		var c := mins(8000.0, 2400.0, fl)
		var b := mins(bn["vol"], bn["area"], fl)
		ok(within(c, REF[nm]["cube"]) and within(b, REF[nm]["benchy"]), "2 %s flow %.2f: cube %.1f min (ref %.1f), Benchy %.1f min (ref %.1f)" % [nm, fl, c, REF[nm]["cube"], b, REF[nm]["benchy"]])
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	var rec := box_rec("Cube", 20, 20, 20)
	var ln := "\n".join(C57PrintEst.lines(rec))
	var l_def := ln.contains("print estimate on a typical printer (Bambu-class):")
	rec["printer_preset"] = "Ender FDM"
	var l_end := "\n".join(C57PrintEst.lines(rec)).contains("print estimate on Ender FDM:")
	rec["printer_preset"] = "Resin"
	var l_res := "\n".join(C57PrintEst.lines(rec)).contains("print estimate on Resin (estimate):")
	ok(l_def and l_end and l_res, "3 label: default %s, Ender %s, Resin %s; line [%s]" % [str(l_def), str(l_end), str(l_res), ln.get_slice("\n", 0)])
	var refd := true
	var est_only := ""
	for nm in C57PrintEst.PRINTERS:
		var has: bool = C57PrintEst.PRINTERS[nm].has("ref")
		refd = refd and has
		if has and not bool(C57PrintEst.PRINTERS[nm]["ref"]):
			est_only += nm + " "
	var src := FileAccess.get_file_as_string("res://scripts/build/c57_print_est.gd")
	ok(refd and est_only.strip_edges() == "Resin" and src.contains("Resin has no slicer reference here: ESTIMATE"), "4 table: ref flags on all, estimate-only [%s], comment names it" % est_only.strip_edges())
	ok(not within(mins(8000.0, 2400.0, 3.0), REF["Bambu PLA"]["cube"]) and not within(0.0, REF["Bambu PLA"]["cube"]), "5 control: the old flow 3.0 gives the cube %.1f min (outside 25 pct of 10.2), a zero stub is outside too" % mins(8000.0, 2400.0, 3.0))
	print("c63: %d fail" % fails)
	quit(1 if fails > 0 else 0)
