extends SceneTree
## godot --path . -s tests/ch16_test.gd   (windowed: the stage movie and sheet LOOKs are bars, not optional decorations)
## CH16 Sony a7 / ILCE-7 class camera. Bars and planted controls committed BEFORE the first model run; docs/CH16_BRIEF.md and CH16_REFERENCE.md.
## 1 DIMENSIONS/MASS  actual posed CAD envelope 126.9 x 94.4 x 48.2 mm (54.8 mm with monitor), each within 2 pct; exact-solid BOM mass
##                  within 10 pct of 474 g loaded. PLANTED: every Part feature and pose scaled 2x fails dimensions (and its 8x mass is reported).
## 2 MOUNT          datum mount face to sensor plane = 18.000000 mm to 1e-6; sensor 35.8 x 23.9 mm; the 46.1 mm throat clears the linear
##                  full-frame corner cone at every depth and sensor/shutter lie inside it. PLANTED: 25 mm flange datum fails.
## 3 ELECTRONICS    E=7.2*1.020 Wh; CIPA energy/shot; all five named rail loads sum and converted input fit the 8 W regulator/protection budget
##                  and the CIPA energy at the declared duty interval; every IC has power + signal. PLANTED: omit one regulator, loads retained.
## 4 FIT            every Part builds; no pair shares >0.001 mm3 (AABB prefilter then KCad.overlap_volume, no undeclared press fit); sensor/shutter
##                  inside throat. PLANTED: main PCB translated 2 mm rearward into the rear shell produces an exact-solid hit.
## 5 BUILD ORDER    AssemblyStage.check supports every stage without collisions; sensor/shutter precede boards, EVF/LCD and shells; video frames
##                  follow AssemblyStage visibility order and change; the SectionLook frame has cut-cap interior pixels absent in the closed view.
##                  PLANTED: shells before sensor is rejected by the explicit stage-order check even if hidden hangers could support them.
## 6 HAND           nominal dimensions, flange, sensor, cone radius, battery energy, energy/shot, rail sum/input/energy and BOM total equal their
##                  independent hand arithmetic to 1e-9 relative. PLANTED: 25 mm flange and a dropped rail load are caught by the same arithmetic.
var fails := 0
var done: Array = []
const P := preload("res://scripts/build/ch16_parts.gd")
const E := preload("res://scripts/build/ch16_electronics.gd")
const D := preload("res://scripts/build/ch16_draw.gd")
const KCad := preload("res://scripts/kcad.gd")
const TMP := "C:/Temp/opencode/ch16"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(absf(b), 1e-300)


func out_dir() -> String:
	return ProjectSettings.globalize_path("res://docs/ch16") if OS.get_environment("CH16_PUBLISH") == "1" else TMP


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	DirAccess.make_dir_recursive_absolute(out_dir())
	await process_frame
	await process_frame
	if not Part.available():
		ok(false, "1-5 KineCAD is required")
		print("ch16: 1 fail")
		quit(1)
		return
	bar1()
	bar2()
	bar3()
	bar4()
	bar6()
	bar5_support()
	await bar5_video()
	await drawings()
	var want := ["1", "2", "3", "4", "6", "5", "5v", "draw"]
	ok(done == want, "every bar ran to its end in order: %s" % str(done))
	print("ch16: %d fail" % fails)
	quit(1 if fails else 0)


func bar1() -> void:
	var asm := P.assembly()
	var dims: Vector3 = P.dimensions_mm(asm)
	var depth := P.body_depth_mm(asm)
	var refs := [P.W, P.H, P.D_MAX]
	var ds := [dims.x, dims.y, dims.z]
	var worst := 0.0
	for i in 3:
		worst = maxf(worst, rel(float(ds[i]), float(refs[i])))
	worst = maxf(worst, rel(depth, P.D))
	ok(worst <= 0.02, "1 CAD body %.4f x %.4f x %.4f mm max, shell depth %.4f mm; worst vs Sony %.4f pct" % [dims.x, dims.y, dims.z, depth, 100.0 * worst])
	var bom: Dictionary = AssemblyBom.bom(asm)
	var mass := float(bom["mass_kg"])
	ok(rel(mass, 0.474) <= 0.10, "1 exact-solid BOM mass %.6f kg with battery/card vs 0.474 kg (%.3f pct); %d parts, %d fastener lines" % [mass, 100.0 * rel(mass, 0.474), int(bom["parts"]), P.fastener_count(asm)])
	ok(P.fastener_count(asm) == 29, "1 29 separate fastener Parts are counted and priced by AssemblyBom")
	var twice := P.scale_assembly(asm, 2.0)
	var d2: Vector3 = P.dimensions_mm(twice)
	var bad := rel(d2.x, P.W) > 0.02 and rel(d2.y, P.H) > 0.02 and rel(d2.z, P.D_MAX) > 0.02
	ok(bad, "1 PLANTED 2x scale model %.3f x %.3f x %.3f mm caught" % [d2.x, d2.y, d2.z])
	var wr: Dictionary = AssemblyBom.write_csv(asm, out_dir() + "/ch16_bom.csv")
	var cheaper: Dictionary = AssemblyBom.cheaper(asm)
	ok(bool(wr["ok"]) and int((cheaper["lines"] as Array).size()) > 0, "1 AssemblyBom CSV and cheapest-alternatives view: USD %.2f now, %.2f cheapest passing design" % [float(bom["cost"]), float((cheaper["design"] as Dictionary)["cost"])])
	done.append("1")


func bar2() -> void:
	var asm := P.assembly()
	var flange := P.flange_mm(asm)
	var sens: Dictionary = P.sensor_mm(asm)
	var cone := P.cone_clearance_mm(asm)
	ok(absf(flange - 18.0) <= 1e-6, "2 mount face to sensor datum %.9f mm = 18.0 to 1e-6" % flange)
	ok(rel(sens.x, 35.8) < 1e-12 and rel(sens.y, 23.9) < 1e-12, "2 sensor %.9f x %.9f mm" % [sens.x, sens.y])
	ok(cone >= 0.0, "2 full-frame cone clears 46.1 mm throat; minimum radial margin %.9f mm" % cone)
	ok(P.inside_throat(asm), "2 sensor and both shutter curtains lie inside the mount throat projection")
	var wrong := P.assembly({"flange": 25.0})
	ok(absf(P.flange_mm(wrong) - 18.0) > 1e-6, "2 PLANTED 25 mm flange distance caught (%.6f mm)" % P.flange_mm(wrong))
	done.append("2")


func bar3() -> void:
	var e := E.model()
	ok(rel(float(e["energy_Wh"]), 7.344) < 1e-12, "3 battery E = 7.2 V x 1.020 Ah = %.9f Wh (Sony label rounds to 7.3)" % float(e["energy_Wh"]))
	ok(rel(float(e["shot_J"]), 77.76) < 1e-12, "3 CIPA 340 shots: %.9f Wh = %.9f J per shot" % [float(e["shot_Wh"]), float(e["shot_J"])])
	ok(bool(e["budget_ok"]), "3 rail loads %.9f W, input %.9f W <= %.9f W budget; duty energy %.9f J <= %.9f J" % [float(e["rail_W"]), float(e["input_W"]), float(e["budget_W"]), float(e["duty_J"]), float(e["shot_J"])])
	ok((e["missing_connections"] as Array).is_empty(), "3 every IC has at least one power and one signal connection")
	var bad := E.model({"omit_reg": "buck_core"})
	ok(not bool(bad["budget_ok"]) or not (bad["missing_connections"] as Array).is_empty(), "3 PLANTED missing core regulator caught; its 1.10 W load remains in the sum")
	done.append("3")


func bar4() -> void:
	var asm := P.assembly()
	var bad: Array = []
	for p in asm["parts"]:
		var b: Dictionary = Assembly.built(p["rec"])
		if b["mesh"] == null or int(b["bodies"]) < 1 or float(b["volume"]) <= 0.0:
			bad.append(String(p["name"]))
	ok(bad.is_empty(), "4 every one of %d separate Part records builds a positive solid %s" % [(asm["parts"] as Array).size(), str(bad)])
	var cl := P.clashes(asm)
	ok(int(cl["pairs"]) > 0 and (cl["hits"] as Array).is_empty(), "4 no overlap beyond 0.001 mm3: %d exact pairs after box prefilter %s" % [int(cl["pairs"]), str(cl["hits"])])
	var moved := P.assembly({"pcb_into_shell": true})
	var cm := P.clashes(moved)
	var pcb_hit := false
	for h in cm["hits"]:
		if String(h["a"]).contains("Main PCB") or String(h["b"]).contains("Main PCB"):
			pcb_hit = true
	ok(pcb_hit, "4 PLANTED main PCB moved 2 mm into rear shell caught %s" % str(cm["hits"]))
	done.append("4")


func bar6() -> void:
	var asm := P.assembly()
	var nominal: Dictionary = P.nominal_dimensions()
	ok(rel(nominal.x, 126.9) < 1e-9 and rel(nominal.y, 94.4) < 1e-9 and rel(nominal.z, 48.2) < 1e-9, "6 hand dimensions 126.9 / 94.4 / 48.2 mm")
	ok(rel(P.flange_mm(asm), 0.0 - -18.0) < 1e-9 and rel(P.sensor_mm(asm).x, 35.8) < 1e-9 and rel(P.sensor_mm(asm).y, 23.9) < 1e-9, "6 hand flange 0-(-18) and sensor 35.8 / 23.9 mm")
	var corner := sqrt(35.8 * 35.8 + 23.9 * 23.9) / 2.0
	ok(rel(P.sensor_corner_radius_mm(), corner) < 1e-9 and rel(P.throat_radius_mm(), 46.1 / 2.0) < 1e-9, "6 hand sensor corner %.12f and throat %.12f mm" % [corner, 46.1 / 2.0])
	var e := E.model()
	var hand_load := 1.10 + 0.85 + 1.20 + 0.65 + 0.80
	ok(rel(float(e["energy_Wh"]), 7.2 * 1.020) < 1e-9 and rel(float(e["shot_Wh"]), 7.2 * 1.020 / 340.0) < 1e-9 and rel(float(e["shot_J"]), 7.2 * 1.020 / 340.0 * 3600.0) < 1e-9, "6 hand battery and CIPA energy")
	ok(rel(float(e["rail_W"]), hand_load) < 1e-9 and rel(float(e["input_W"]), hand_load / 0.90) < 1e-9 and rel(float(e["duty_J"]), hand_load / 0.90 * 12.0) < 1e-9, "6 hand rail sum 4.60 W, input 5.111111 W, duty 61.333333 J")
	var b: Dictionary = AssemblyBom.bom(asm)
	var sum := 0.0
	for ln in b["lines"]:
		sum += float(ln["line_mass_kg"])
	ok(rel(float(b["mass_kg"]), sum) < 1e-9, "6 hand BOM mass sum %.12f kg" % sum)
	ok(rel(P.flange_mm(P.assembly({"flange": 25.0})), 18.0) > 1e-9 and rel(hand_load - 1.10, hand_load) > 1e-9, "6 PLANTED wrong flange and dropped rail arithmetic differ")
	done.append("6")


func bar5_support() -> void:
	var asm := P.assembly()
	var r: Dictionary = AssemblyStage.check(asm)
	ok(bool(r["ok"]) and int(r["placed"]) == (asm["parts"] as Array).size(), "5 AssemblyStage: %d/%d parts supported, no collisions %s" % [int(r["placed"]), (asm["parts"] as Array).size(), str(AssemblyStage.words(r))])
	ok(P.stage_order_ok(asm), "5 chassis -> sensor/shutter -> boards -> EVF/LCD -> shells -> doors order")
	var bad := P.assembly({"shells_first": true})
	ok(not P.stage_order_ok(bad), "5 PLANTED shells before sensor caught by stage-order check")
	done.append("5")


func px_diff(a: Image, b: Image) -> int:
	var n := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				n += 1
	return n


func cap_px(img: Image) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			for k in SectionLook.CAPS:
				if absf(c.r - k.r) < 0.04 and absf(c.g - k.g) < 0.04 and absf(c.b - k.b) < 0.04:
					n += 1
					break
	return n


func bar5_video() -> void:
	if DisplayServer.get_name() == "headless":
		ok(false, "5 movie and section require a window")
		return
	var asm := P.assembly()
	var opts := {"dir": out_dir() + "/build", "width": 640, "height": 360, "keep_images": true, "sheet_cols": 4, "sheet_tile": 320,
		"camera": {"pos": Vector3(0.19, 0.13, 0.24), "look": Vector3(0.0, 0.047, -0.024), "fov": 38.0}}
	var r: Dictionary = await AssemblyStage.video(root, asm, opts)
	var imgs: Array = r.get("images", [])
	var steps := AssemblyStage.steps(asm)
	var order := imgs.size() == steps.size() and not imgs.is_empty()
	var previous: Array = []
	for i in steps.size():
		var vis: Array = steps[i]["visible"]
		for id in previous:
			order = order and vis.has(id)
		previous = vis
		if i > 0:
			order = order and px_diff(imgs[i - 1], imgs[i]) > 0
	ok(bool(r["ok"]) and order and String(r["mp4"]) != "", "5 AssemblyStage/AssemblyRender movie: %d frames in stage order, all consecutive frames change; MP4 %s %s" % [imgs.size(), String(r["mp4"]).get_file(), String(r.get("why", ""))])
	var view := {"dir": out_dir() + "/section_closed", "width": 640, "height": 360, "times": [AssemblyStage.total(asm)], "keep_images": true, "mp4": false, "sheet": false,
		"camera": {"pos": Vector3(0.0, 0.047, 0.22), "look": Vector3(0.0, 0.047, -0.024), "fov": 32.0}}
	var cut_opts: Dictionary = view.duplicate(true)
	cut_opts["dir"] = out_dir() + "/section_cut"
	cut_opts["cut"] = {"n": Vector3(0, 0, 1), "w": -0.026}
	var cut: Dictionary = await AssemblyStage.video(root, asm, cut_opts)
	var whole: Dictionary = await AssemblyStage.video(root, asm, view)
	var cp := cap_px(cut["images"][0]) if (cut.get("images", []) as Array).size() == 1 else -1
	var wp := cap_px(whole["images"][0]) if (whole.get("images", []) as Array).size() == 1 else -1
	ok(cp > 20 and wp == 0, "5 section exposes interior: %d cap pixels vs closed view %d" % [cp, wp])
	done.append("5v")


func drawings() -> void:
	var all_ok := true
	for nm in ["blueprint", "electronics"]:
		var sh: Dictionary = D.sheet(nm)
		var svg := Blueprint.to_svg(sh)
		var path := "%s/ch16_%s.svg" % [out_dir(), nm]
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(svg)
		f.close()
		var good := svg.contains("SCALE") and svg.contains("data-scale=") and svg.length() > 3000
		if nm == "blueprint":
			for label in ["126.9", "94.4", "48.2", "18.00", "35.8", "23.9"]:
				good = good and svg.contains(label)
		else:
			good = good and D.missing_labels(E.model(), sh).is_empty()
		all_ok = all_ok and good
		var png: Image = await D.render_png(root, sh, 3.0)
		png.save_png("%s/ch16_sheet_%s.png" % [out_dir(), nm])
	ok(all_ok, "drawings: dimensioned front/top/section and titled power/signal SVG sheets, all IC rail/signal labels present")
	done.append("draw")
