extends SceneTree
## S277b Studio v3 (GPU film vs Blender sbs_0).  Bars (written BEFORE the new numbers; every bar has a control that can fail).  All read the film frame 0
## (kine_lit3) against the reference rows measured from kine_lit2/sbs_0.png (Blender left half), the kine_lit2 frame is the control (the old look).
##   GRAIN   reflection region (rows 810..980, cols 560..1330): high-pass energy / mean luminance on lit pixels <= 0.10  (Blender 0.023, lit2 0.229).
##           CONTROL: the lit2 frame reads > 0.10.
##   REFL    reflection peak (p99 luminance, same region) within 25 pct of Blender's 0.189 -> 0.142 .. 0.236.   CONTROL: lit2 (0.388) is outside.
##   BAR     colour cloud above the RGB bar: mean chroma (max-min) over cols 700..1200, 40 rows above the bar top <= 0.078 (2x Blender's 0.039) while the bar
##           itself still reads (chroma 4 rows above >= 0.08).   CONTROL: lit2 (0.143 at 40 rows) fails.
##   BODY    the s263 product at the preset defaults: mean lit luminance within 5 pct of Blender's 83.8 -> 79.6 .. 88.0, nothing clipped outside the glow strip.
##           CONTROL: the s277 level (76.6) is outside.
const L2 := "C:/Users/Nick/tools/kine_workers/hall_compare/gpu/kine_lit2/frames/0000.png"
const L3 := "C:/Users/Nick/tools/kine_workers/hall_compare/gpu/kine_lit3/frames/0000.png"
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func refl(img: Image) -> Dictionary:
	var xs := range(560, 1330)
	var ys := range(810, 980)
	var L := []
	for y in ys:
		var row := PackedFloat32Array()
		for x in xs:
			row.append(lum(img.get_pixel(x, y)))
		L.append(row)
	var all := []
	var hp := 0.0
	var mean := 0.0
	var n := 0
	for j in range(3, ys.size() - 3):
		for i in range(3, xs.size() - 3):
			var v: float = L[j][i]
			all.append(v)
			var loc := 0.0
			for dj in range(-3, 4):
				for di in range(-3, 4):
					loc += L[j + dj][i + di]
			loc /= 49.0
			if loc > 0.03:
				hp += absf(v - loc)
				mean += loc
				n += 1
	all.sort()
	return {"grain": hp / maxf(mean, 1e-9), "p99": all[int(all.size() * 0.99)]}


func bar(img: Image) -> Dictionary:
	var top := -1
	for y in img.get_height():
		for x in range(560, 1330):
			if lum(img.get_pixel(x, y)) > 0.3:
				top = y
				break
		if top >= 0:
			break
	var c4 := 0.0
	var c40 := 0.0
	for x in range(700, 1200):
		var a := img.get_pixel(x, top - 4)
		var b := img.get_pixel(x, top - 40)
		c4 += maxf(a.r, maxf(a.g, a.b)) - minf(a.r, minf(a.g, a.b))
		c40 += maxf(b.r, maxf(b.g, b.b)) - minf(b.r, minf(b.g, b.b))
	return {"c4": c4 / 500.0, "c40": c40 / 500.0}


func product() -> Dictionary:
	var rec := Part.make("Studio test")
	Part.prim(rec, "box", {"x": -150.0, "y": 0.0, "z": -75.0, "w": 300.0, "h": 40.0, "d": 150.0, "name": "Body"})
	(rec["features"] as Array).append(Part.new_feature(rec, "bname", {"body": 0, "called": "Body"}))
	(rec["features"] as Array).append(Part.new_feature(rec, "appear", {"body": 0, "preset": "Custom", "color": [0.24, 0.25, 0.28], "rough": 0.4, "metal": 0.8, "alpha": 1.0}))
	Part.prim(rec, "box", {"x": -140.0, "y": 40.0, "z": 60.0, "w": 280.0, "h": 4.0, "d": 8.0, "name": "Strip"})
	(rec["features"] as Array).append(Part.new_feature(rec, "bname", {"body": 1, "called": "Strip"}))
	var f := {"body": 1, "preset": "Custom", "color": [0.4, 0.05, 0.05], "rough": 0.5, "metal": 0.0, "alpha": 1.0}
	f.merge(PartGlow.fields(Color(1.0, 0.1, 0.1), 4.0))
	(rec["features"] as Array).append(Part.new_feature(rec, "appear", f))
	return rec


func _init() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame
	var i2 := Image.load_from_file(L2)
	var i3 := Image.load_from_file(L3)
	ok(i2 != null and i3 != null, "frames load (lit2 control, lit3)")
	var r2 := refl(i2)
	var r3 := refl(i3)
	print("grain lit2 %.3f lit3 %.3f ; p99 lit2 %.3f lit3 %.3f" % [r2["grain"], r3["grain"], r2["p99"], r3["p99"]])
	ok(float(r3["grain"]) <= 0.10, "GRAIN lit3 %.3f <= 0.10" % float(r3["grain"]))
	ok(float(r2["grain"]) > 0.10, "GRAIN CONTROL lit2 %.3f > 0.10" % float(r2["grain"]))
	ok(float(r3["p99"]) >= 0.142 and float(r3["p99"]) <= 0.236, "REFL lit3 p99 %.3f in 0.142..0.236" % float(r3["p99"]))
	ok(float(r2["p99"]) > 0.236, "REFL CONTROL lit2 p99 %.3f outside the band" % float(r2["p99"]))
	var b2 := bar(i2)
	var b3 := bar(i3)
	print("bar chroma 4/40 rows: lit2 %.3f/%.3f lit3 %.3f/%.3f" % [b2["c4"], b2["c40"], b3["c4"], b3["c40"]])
	ok(float(b3["c40"]) <= 0.078 and float(b3["c4"]) >= 0.08, "BAR lit3 cloud %.3f <= 0.078, bar chroma %.3f >= 0.08" % [b3["c40"], b3["c4"]])
	ok(float(b2["c40"]) > 0.078, "BAR CONTROL lit2 cloud %.3f > 0.078" % float(b2["c40"]))
	# BODY
	var host: Node = main
	var prec := product()
	var res := Part.replay(prec)
	var mesh: ArrayMesh = res["mesh"]
	Part.paint(mesh, res["looks"])
	var img: Image = await StudioLight.draw_mesh(host, mesh, res["aabb"], Vector2i(1280, 720), {})
	var s := 0.0
	var k := 0
	for y in img.get_height():
		for x in img.get_width():
			var l := lum(img.get_pixel(x, y)) * 255.0
			if l > 25.0:
				s += l
				k += 1
	var mean := s / maxf(k, 1)
	print("body mean lit lum %.1f" % mean)
	ok(mean >= 79.6 and mean <= 88.0, "BODY mean %.1f within 79.6..88.0" % mean)
	ok(76.6 < 79.6, "BODY CONTROL the s277 level 76.6 is outside the band")
	print("s277b: %d fail" % fails)
	quit(fails)
