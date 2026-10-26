extends SceneTree
## godot --headless --path . -s tests/uvexport_test.gd     (ROADMAP_400 D11 export UV layout as PNG / SVG, scripts/kmesh_uv_export.gd)
## The unwrapped test cube (KMeshView.make_cube(0.6, 4), seams by angle, LSCM: 96 faces, 6 islands), exported at 1024.
## Bars, written before measuring:
##   1 PNG LINES WHERE THE EDGES ARE: 1024 x 1024 RGBA; at the midpoint pixel of 10 UV edges spread over the list
##     (x = u * 1024, y = (1 - v) * 1024) alpha > 0 (10 of 10), and with an opaque red line the midpoint pixel is red
##     (r > 0.8, g < 0.2, b < 0.2); the centroid pixel of EVERY face (96) has alpha 0 with fill off (transparent
##     background); width 1: the pixel 3 px off the midpoint across the edge has alpha 0 (10 of 10), width 8: alpha > 0
##   2 Y FLIPPED THE RIGHT WAY: one triangle at UV (0.1, 0.1) (0.5, 0.1) (0.1, 0.5): its bottom edge (v = 0.1) is on
##     row 921 (alpha > 0 at x 307) and NOT on row 102 (alpha 0 there): v = 0 is the bottom of the image
##   3 FILL: by island, every face centroid has alpha 0.5 +- 0.02 and its island's colour (within 0.02), 6 islands,
##     6 different colours; by stretch, every centroid is KMeshUV.heat_color(heat) of its face (within 0.02), the LSCM
##     cube is blue (b > r) everywhere; one interior UV vertex moved by 0.04 turns a face red-ish (r > b) in the fill
##   4 MARGIN OUTLINE (6 px): 4 px outside an island's border edge (away from its face) alpha > 0, 4 px inside alpha 0
##     (fill off); margin 0: that outside pixel alpha 0
##   5 SVG: parses (XMLParser, no error), root viewBox "0 0 1024 1024", one <polygon> per face (96), id f<k> in face
##     order, every point = (u * 1024, (1 - v) * 1024) within 0.5 px (the worst error printed)
##   6 FILES: export() writes <name>_uv_1024.png + .svg under user://uv_layouts; a second export of the same name
##     goes to _2 and leaves the first PNG's bytes unchanged; the files read back give the same PNG as render_png
##   7 SIZES: 512 / 2048 / 4096 give images of that size; the 4096 PNG renders in < 10 s (printed)
##   8 THE DIALOG: KMeshUVExport.ask with 2048 and fill by island picked, Export pressed: a 2048 PNG is written and the
##     message names its path

var fails := 0
const N := "zz_uvexport_test"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func px(img: Image, p: Vector2) -> Color:
	var s := img.get_width()
	return img.get_pixel(clampi(int(floor(p.x)), 0, s - 1), clampi(int(floor(p.y)), 0, s - 1))


func at(q: Vector2, s: int) -> Vector2:   # the test's own mapping (not the module's): x = u s, y = (1 - v) s
	return Vector2(q.x * s, (1.0 - q.y) * s)


func cube() -> KMesh:
	var m := KMeshView.make_cube(0.6, 4)
	KMeshUV.seams_by_angle(m, 60.0)
	KMeshUV.unwrap_lscm(m)
	return m


func centroid(q: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in q:
		c += p
	return c / q.size()


func cdist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## the files there now (none when the folder does not exist yet)
func listing() -> Array:
	return Array(DirAccess.get_files_at(KMeshUVExport.DIR)) if DirAccess.dir_exists_absolute(KMeshUVExport.DIR) else []


## removes only what this run wrote: the files that were not there at its start (the user's own exports stay)
func cleanup(before: Array) -> void:
	for f in listing():
		if not before.has(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(KMeshUVExport.DIR + "/" + f))


func _init() -> void:
	await process_frame   # the root is in the tree from here (the dialog's popup needs it)
	var before := listing()
	var m := cube()
	var fu := KMeshUVExport.face_uvs(m)
	var isl := KMeshUVExport.islands(m, fu)
	print("     cube: %d faces, %d UV islands" % [fu.size(), isl["islands"]])
	ok(fu.size() == 96 and isl["islands"] == 6, "the unwrapped test cube: 96 faces, 6 UV islands")
	# 1 lines
	var S := 1024
	var red := {"size": S, "line": Color(1, 0, 0, 1), "width": 1.0}
	var img := KMeshUVExport.render_png(m, red)
	ok(img.get_width() == S and img.get_height() == S and img.get_format() == Image.FORMAT_RGBA8, "1 PNG is 1024 x 1024 RGBA8")
	var segs := KMeshUVExport.segments(fu)
	var pick := []
	for k in 10:
		pick.append(segs[k * segs.size() / 10])
	var on := 0
	var redc := 0
	var off1 := 0
	var img8 := KMeshUVExport.render_png(m, {"size": S, "width": 8.0})
	var off8 := 0
	for s in pick:
		var a := at(s[0], S)
		var b := at(s[1], S)
		var mid := (a + b) * 0.5
		var c := px(img, mid)
		on += 1 if c.a > 0.0 else 0
		redc += 1 if (c.r > 0.8 and c.g < 0.2 and c.b < 0.2) else 0
		var nrm := (b - a).normalized().orthogonal()
		off1 += 1 if px(img, mid + nrm * 3.0).a == 0.0 else 0
		off8 += 1 if px(img8, mid + nrm * 3.0).a > 0.0 else 0
	ok(on == 10, "1a line pixels at the midpoints of 10 UV edges: alpha > 0 at %d of 10" % on)
	ok(redc == 10, "1b the line has the chosen colour (red) at %d of 10 midpoints" % redc)
	var clear := 0
	for q in fu:
		clear += 1 if px(img, at(centroid(q), S)).a == 0.0 else 0
	ok(clear == fu.size(), "1c fill off: %d of %d face centroids have alpha 0 (transparent background)" % [clear, fu.size()])
	ok(off1 == 10 and off8 == 10, "1d width: 3 px across the edge alpha 0 at width 1 (%d of 10), alpha > 0 at width 8 (%d of 10)" % [off1, off8])
	# 2 the y flip
	var tri := KMesh.new().from_arrays(PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]), [[0, 1, 2]])
	tri.add_attr(KMeshUV.UV, KMesh.AD_CORNER, TYPE_VECTOR2, Vector2.ZERO)
	tri.set_attr_data(KMeshUV.UV, PackedVector2Array([Vector2(0.1, 0.1), Vector2(0.5, 0.1), Vector2(0.1, 0.5)]))
	var ti := KMeshUVExport.render_png(tri, {"size": S})
	var lo := ti.get_pixel(307, 921).a
	var hi := ti.get_pixel(307, 102).a
	ok(lo > 0.0 and hi == 0.0, "2 v = 0.1 lands on row 921 (alpha %.2f), not on row 102 (alpha %.2f): UV v = 0 is the bottom" % [lo, hi])
	# 3 fill
	var fi := KMeshUVExport.render_png(m, {"size": S, "fill": "island", "fill_alpha": 0.5})
	var good := 0
	var cols := {}
	for f in fu.size():
		var c := px(fi, at(centroid(fu[f]), S))
		var want := KMeshUVExport.island_color(isl["island"][f])
		if absf(c.a - 0.5) <= 0.02 and cdist(c, want) <= 0.02:
			good += 1
		cols[c.to_html(false)] = true
	ok(good == fu.size() and cols.size() == 6, "3a fill by island: %d of %d centroids alpha 0.5 in their island's colour, %d colours" % [good, fu.size(), cols.size()])
	var st := KMeshUV.stretch(m)
	var fs := KMeshUVExport.render_png(m, {"size": S, "fill": "stretch", "fill_alpha": 1.0})
	good = 0
	var blue := 0
	for f in fu.size():
		var c := px(fs, at(centroid(fu[f]), S))
		good += 1 if cdist(c, KMeshUV.heat_color(st["heat"][f])) <= 0.02 else 0
		blue += 1 if c.b > c.r else 0
	ok(good == fu.size() and blue == fu.size(), "3b fill by stretch: %d of %d centroids are the heat colour, %d blue (LSCM: no stretch)" % [good, fu.size(), blue])
	# move one interior UV vertex (a wedge with 4 corners at the same UV inside an island) and look again
	var m2 := cube()
	var d: PackedVector2Array = m2.attr_data(KMeshUV.UV)
	var count := {}
	for q in d:
		var k := Vector2i(roundi(q.x * 1e5), roundi(q.y * 1e5))
		count[k] = count.get(k, 0) + 1
	var key := Vector2i(-1, -1)
	for k in count:
		if count[k] == 4:
			key = k
			break
	for i in d.size():
		if Vector2i(roundi(d[i].x * 1e5), roundi(d[i].y * 1e5)) == key:
			d[i] += Vector2(0.04, 0.0)
	m2.set_attr_data(KMeshUV.UV, d)
	var st2 := KMeshUV.stretch(m2)
	var fu2 := KMeshUVExport.face_uvs(m2)
	var fs2 := KMeshUVExport.render_png(m2, {"size": S, "fill": "stretch", "fill_alpha": 1.0})
	var hot := 0
	var worst := 0.0
	for f in fu2.size():
		worst = maxf(worst, st2["heat"][f])
		var c := px(fs2, at(centroid(fu2[f]), S))
		hot += 1 if c.r > c.b else 0
	ok(key != Vector2i(-1, -1) and hot >= 1, "3c one interior UV vertex moved 0.04: %d faces fill red-ish (worst heat %.2f)" % [hot, worst])
	# 4 margin
	var mg := KMeshUVExport.render_png(m, {"size": S, "margin": 6.0})
	var m0 := img
	var border := []
	for s in segs:
		if s[2]:
			border.append(s)
	var outside := 0
	var inside := 0
	var out0 := 0
	var tried := 0
	for s in border:
		var a := at(s[0], S)
		var b := at(s[1], S)
		var mid := (a + b) * 0.5
		# the face this border edge belongs to: the centroid side is inside
		var fc := Vector2.ZERO
		for q in fu:
			var n: int = q.size()
			for i in n:
				if (q[i].is_equal_approx(s[0]) and q[(i + 1) % n].is_equal_approx(s[1])) or (q[i].is_equal_approx(s[1]) and q[(i + 1) % n].is_equal_approx(s[0])):
					fc = at(centroid(q), S)
		var nrm := (b - a).normalized().orthogonal()
		if nrm.dot(fc - mid) > 0.0:
			nrm = -nrm   # nrm points away from the face: outward
		var po := mid + nrm * 4.0
		if po.x < 0 or po.y < 0 or po.x >= S or po.y >= S:
			continue
		tried += 1
		outside += 1 if px(mg, po).a > 0.0 else 0
		inside += 1 if px(mg, mid - nrm * 4.0).a == 0.0 else 0
		out0 += 1 if px(m0, po).a == 0.0 else 0
	ok(tried >= 10 and outside == tried and inside == tried and out0 == tried, "4 margin 6 px: %d border edges: 4 px outside alpha > 0 at %d, 4 px inside alpha 0 at %d; margin 0 outside alpha 0 at %d" % [tried, outside, inside, out0])
	# 5 SVG
	var svg := KMeshUVExport.render_svg(m, {"size": S})
	var xp := XMLParser.new()
	var e := xp.open_buffer(svg.to_utf8_buffer())
	var vb := ""
	var polys := 0
	var order_ok := true
	var worst_px := 0.0
	var pts_ok := true
	while e == OK:
		e = xp.read()
		if e != OK:
			break
		if xp.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var tag := xp.get_node_name()
		if tag == "svg":
			vb = xp.get_named_attribute_value_safe("viewBox")
		elif tag == "polygon":
			var f := polys
			order_ok = order_ok and xp.get_named_attribute_value_safe("id") == "f%d" % f
			var pts := xp.get_named_attribute_value_safe("points").split(" ", false)
			var q: PackedVector2Array = fu[f] if f < fu.size() else PackedVector2Array()
			if pts.size() != q.size():
				pts_ok = false
			else:
				for i in q.size():
					var xy := pts[i].split(",")
					worst_px = maxf(worst_px, Vector2(float(xy[0]), float(xy[1])).distance_to(at(q[i], S)))
			polys += 1
	ok(e == ERR_FILE_EOF, "5a the SVG parses to the end (XMLParser: %s)" % error_string(e))
	ok(vb == "0 0 1024 1024", "5b viewBox \"%s\"" % vb)
	ok(polys == fu.size() and order_ok, "5c %d polygons for %d faces, ids f0.. in face order" % [polys, fu.size()])
	ok(pts_ok and worst_px <= 0.5, "5d every point = (u * 1024, (1 - v) * 1024): worst %.4f px (bar 0.5)" % worst_px)
	# 6 files
	var r1 := KMeshUVExport.export(m, N, red)
	var png1 := String(r1.get("png", ""))
	var bytes1 := FileAccess.get_file_as_bytes(png1)
	var r2 := KMeshUVExport.export(m, N, red)
	var png2 := String(r2.get("png", ""))
	print("     wrote %s, %s (%s ms)" % [ProjectSettings.globalize_path(png1), png2.get_file(), r1.get("ms", -1)])
	ok(png1.ends_with("/%s_uv_1024.png" % N) and FileAccess.file_exists(String(r1.get("svg", ""))) and png1.begins_with(KMeshUVExport.DIR), "6a export writes %s_uv_1024.png + .svg under %s" % [N, KMeshUVExport.DIR])
	ok(png2.ends_with("/%s_uv_1024_2.png" % N) and FileAccess.get_file_as_bytes(png1) == bytes1, "6b a second export goes to _2 and leaves the first file's bytes alone")
	var back := Image.load_from_file(png1)
	var same := back != null and back.get_width() == S and back.get_data() == img.get_data()
	ok(same, "6c the PNG read back is the rendered image, pixel for pixel")
	ok(FileAccess.get_file_as_string(String(r1["svg"])) == KMeshUVExport.render_svg(m, red), "6d the SVG file is the rendered text")
	# 7 sizes
	var dims := []
	for s in [512, 2048]:
		dims.append(KMeshUVExport.render_png(m, {"size": s}).get_width())
	var t0 := Time.get_ticks_msec()
	var big := KMeshUVExport.render_png(m, {"size": 4096, "fill": "stretch", "width": 2.0})
	var ms := Time.get_ticks_msec() - t0
	dims.append(big.get_width())
	ok(dims == [512, 2048, 4096] and big.get_height() == 4096, "7a sizes %s" % [dims])
	ok(ms < 10000, "7b the 4096 PNG (fill by stretch, width 2) renders in %d ms (bar 10 s)" % ms)
	# 8 the dialog
	var said := []
	var pp := KMeshUVExport.ask(root, func() -> KMesh: return m, func(t): said.append(t))
	await process_frame
	var opts: Array = pp.find_children("*", "OptionButton", true, false)
	(opts[0] as OptionButton).select(2)   # 2048
	(opts[1] as OptionButton).select(1)   # fill by island
	var go: Button = pp.find_children("*", "Button", true, false).filter(func(b): return b is Button and not (b is OptionButton) and not (b is ColorPickerButton) and b.text == "Export")[0]
	go.pressed.emit()
	await process_frame
	var path := ""
	for f in listing():
		if not before.has(f) and f.begins_with("test_cube_uv_2048") and f.ends_with(".png"):
			path = KMeshUVExport.DIR + "/" + f
	var di := Image.load_from_file(path) if path != "" else null
	print("     dialog said: %s" % [said])
	ok(di != null and di.get_width() == 2048 and said.size() == 1 and String(said[0]).contains(ProjectSettings.globalize_path(path)), "8 the dialog wrote a 2048 PNG and named it")
	ok(di != null and di.get_pixelv(Vector2i(at(centroid(fu[0]), 2048))).a > 0.4, "8b ... with the island fill it was given")
	cleanup(before)
	print("UVEXPORT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
