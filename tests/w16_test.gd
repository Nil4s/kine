extends SceneTree
## godot --headless --path . -s tests/w16_test.gd     (W16 TEST PRINT: TOLERANCE / FIT STRIP; needs the CAD DLL)
## Bars (written before the first run):
##   1 CELLS   default strip: 5 pegs + 5 holes, clearances 0.1 .. 0.5 step 0.1 (0.1 Snug, 0.2 Slides, 0.4 Loose from the app's presets), each labelled with its value;
##             hole diameter - peg diameter = 2 x clearance (1e-9)
##   2 VOLUME  the kernel's volume of the peg body and of the hole body within 1 % of the closed form (plate + pegs - text, plate - holes - text)
##   3 STL     the exported STL/3MF is two bodies, each manifold (open 0, bad 0), signed volume of each within 1 % of the closed form, file on disk
##   4 TEXT    the engraving is real: body volume is smaller than the same strip's plate + pegs by at least half the text volume
##   5 RANGE   a changed range (0.05 .. 0.25 step 0.05) gives 5 cells and its own closed form within 1 %
##   6 CONTROL a planted wrong closed form (clearance 0.1 mm too small on the holes) fails the 1 % bar; an empty range is refused
const KCad := preload("res://scripts/kcad.gd")
const OUT := "C:/Users/Nick/tools/kine_workers/out/w16"
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(absf(b), 1e-9)


func bodies_vol(b: Dictionary) -> Array:
	var r := Part.replay(b["rec"], -1, {"keep": true})
	var out := []
	for id in r.get("ids", []):
		out.append(KCad.volume(int(id)) * 1e9)
	for id in r.get("ids", []):
		KCad.release(int(id))
	return [out, r]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	ok(Part.available(), "CAD kernel present")
	var s := FitStrip.build()
	ok(bool(s["ok"]), "default strip builds: " + String(s["why"]))
	var cells: Array = s["cells"]
	var want := [0.1, 0.2, 0.3, 0.4, 0.5]
	var good := cells.size() == 5
	for i in cells.size():
		good = good and absf(float(cells[i]["c"]) - float(want[i])) < 1e-9 and absf(float(cells[i]["hole_d"]) - float(cells[i]["peg_d"]) - 2.0 * float(want[i])) < 1e-9 and String(cells[i]["label"]) == "%.1f" % float(want[i])
	ok(good, "1 five cells 0.1..0.5, hole_d - peg_d = 2c, labelled")
	ok(cells[0]["preset"] == "Snug" and cells[1]["preset"] == "Slides" and cells[3]["preset"] == "Loose" and cells[2]["preset"] == "", "1b presets from the app: 0.1 %s, 0.2 %s, 0.3 '%s', 0.4 %s" % [cells[0]["preset"], cells[1]["preset"], cells[2]["preset"], cells[3]["preset"]])
	var bv := bodies_vol(s)
	var vs: Array = bv[0]
	ok(vs.size() == 2 and (bv[1]["errors"] as Dictionary).is_empty(), "replay: 2 bodies, no errors %s" % str(bv[1]["errors"]))
	var ep: float = s["exp_peg_mm3"]
	var eh: float = s["exp_hole_mm3"]
	print("     kernel peg %.2f vs %.2f (%.4f %%), hole %.2f vs %.2f (%.4f %%)" % [vs[0], ep, 100.0 * rel(vs[0], ep), vs[1], eh, 100.0 * rel(vs[1], eh)])
	ok(rel(vs[0], ep) <= 0.01 and rel(vs[1], eh) <= 0.01, "2 kernel volumes within 1 % of closed form")
	var plain: float = s["length"] * FitStrip.PLATE_W * FitStrip.PLATE_T + 5.0 * PI * 16.0 * FitStrip.PEG_H
	var tv: float = s["text_area_peg"] * FitStrip.ENGRAVE
	ok(plain - vs[0] >= 0.5 * tv and tv > 5.0, "4 engraving removes material: plate+pegs %.2f - body %.2f = %.2f mm3 (text %.2f)" % [plain, vs[0], plain - vs[0], tv])
	# export
	for fmt in ["stl", "3mf"]:
		var ex := MeshExport.export_part(s["rec"], fmt, OUT)
		ok(bool(ex["ok"]) and FileAccess.file_exists(String(ex["path"])), "3 %s written: %s" % [fmt, str(ex["text"])])
	var bo := MeshExport.bodies_of(s["rec"])
	var bodies: Array = bo["bodies"]
	ok(bodies.size() == 2, "3 two bodies in the file")
	var sv := []
	for b in bodies:
		var ch := MeshExport.check(b)
		sv.append(MeshExport.signed_volume(b))
		ok(bool(ch["closed"]), "3 body manifold: open %d bad %d tris %d" % [ch["open"], ch["bad"], ch["tris"]])
	print("     mesh peg %.2f (%.4f %%), hole %.2f (%.4f %%)" % [sv[0], 100.0 * rel(sv[0], ep), sv[1], 100.0 * rel(sv[1], eh)])
	ok(rel(sv[0], ep) <= 0.01 and rel(sv[1], eh) <= 0.01, "3 STL mesh volumes within 1 % of closed form")
	# range
	var r := FitStrip.build(0.05, 0.25, 0.05)
	var rv := bodies_vol(r)
	ok((r["cells"] as Array).size() == 5 and rv[0].size() == 2 and rel(rv[0][0], r["exp_peg_mm3"]) <= 0.01 and rel(rv[0][1], r["exp_hole_mm3"]) <= 0.01, "5 range 0.05..0.25: %d cells, volumes %s vs [%.2f, %.2f]" % [(r["cells"] as Array).size(), str(rv[0]), r["exp_peg_mm3"], r["exp_hole_mm3"]])
	# control
	# the body volume is dominated by the plate, so the holes themselves are held to the bar too: volume removed by the holes = plate - body - text
	var plate: float = s["length"] * FitStrip.PLATE_W * FitStrip.PLATE_T
	var removed: float = plate - sv[1] - s["text_area_hole"] * FitStrip.ENGRAVE
	var cf := 0.0
	var planted := 0.0
	for c in s["cells"]:
		cf += PI * pow(4.0 + float(c["c"]), 2) * FitStrip.PLATE_T
		planted += PI * pow(4.0 + float(c["c"]) - 0.1, 2) * FitStrip.PLATE_T
	ok(rel(removed, cf) <= 0.01, "2b hole volume from the STL %.2f vs closed form %.2f (%.4f %%)" % [removed, cf, 100.0 * rel(removed, cf)])
	ok(rel(removed, planted) > 0.01, "6 control: closed form with every clearance 0.1 short is %.2f %% off the same mesh, fails the 1 %% bar" % (100.0 * rel(removed, planted)))
	ok(not bool(FitStrip.build(0.5, 0.1, 0.1)["ok"]) and not bool(FitStrip.build(0.1, 0.5, 0.0)["ok"]), "6 empty range / zero step refused")
	print("W16 %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
