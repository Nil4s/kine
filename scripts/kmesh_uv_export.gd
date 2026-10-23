class_name KMeshUVExport
extends RefCounted
## KMeshUVExport: the UV layout of a KMesh as a PNG and an SVG (ROADMAP_400 D11). Pure GDScript, static funcs, no scene.
## The layout is the corner attribute "uv" (KMeshUV.UV, one Vector2 per face corner = half-edge). Both files put UV
## (0, 0) at the BOTTOM-left, the way Blender, Substance and every texture painter show it: pixel / SVG x = u * size,
## y = (1 - v) * size (an image's rows and SVG's y both run downwards).
##
## OPTIONS (a Dictionary, every key optional; defaults in DEFAULTS):
##   "size"   512 / 1024 / 2048 / 4096 (SIZES; any other number is taken as given)
##   "line"   the edge colour (Color, its alpha kept), "width" the line width in px (anti-aliased, 1 = a hairline)
##   "fill"   "none" | "island" (each UV island its own hue, golden-angle steps) | "stretch" (the D05 heat colour of each
##            face, KMeshUV.stretch()["heat"] -> KMeshUV.heat_color: blue none .. red stretched); "fill_alpha" its opacity
##   "margin" px, 0 = off: a halo that far OUTSIDE every island's border, in "margin_color" (the padding a texture needs
##            round each island so mip-maps and bleeding do not pick up the neighbour; two halos overlapping = too close)
## The background is transparent: a pixel no line, fill or halo touches has alpha 0.
## Edges shared by two faces with the same UVs on both sides are drawn once (no darker double line).
##
## FILES (policy, tests/confirm_test.gd 1e): only NEW files under DIR = user://uv_layouts, <name>_uv_<size>.png / .svg;
## a name already there gets _2, _3 (the PNG and the SVG of one export always share a number). Never scenes/, poses/,
## data/, never over an earlier export, nothing removed: no dialog is needed.

const DIR := "user://uv_layouts"
const SIZES := [512, 1024, 2048, 4096]
const FILLS := ["none", "island", "stretch"]
const DEFAULTS := {"size": 1024, "line": Color(0, 0, 0, 1), "width": 1.0, "fill": "none", "fill_alpha": 0.5,
	"margin": 0.0, "margin_color": Color(1.0, 0.45, 0.1, 0.35)}


static func _opt(o: Dictionary) -> Dictionary:
	var r := DEFAULTS.duplicate()
	r.merge(o, true)
	r["size"] = maxi(int(r["size"]), 8)
	return r


## per face its corner UVs (PackedVector2Array, in face order); [] when the mesh has no uv attribute
static func face_uvs(m: KMesh, uv := KMeshUV.UV) -> Array:
	if not m.has_attr(uv):
		return []
	var dom: String = m.attr_info(uv)["domain"]
	var d = m.attr_data(uv)
	var he0 := m.face_he0
	var out := []
	for f in m.face_count():
		var fp: PackedInt32Array = m.faces[f]
		var q := PackedVector2Array()
		for i in fp.size():
			q.append(d[fp[i] if dom == KMesh.AD_VERT else (f if dom == KMesh.AD_FACE else he0[f] + i)])
		out.append(q)
	return out


## UV islands: faces joined by an edge whose two sides carry the same UVs. {"island": PackedInt32Array per face, "islands"}
static func islands(m: KMesh, fu: Array) -> Dictionary:
	var nf := m.face_count()
	var p := PackedInt32Array()
	p.resize(nf)
	for f in nf:
		p[f] = f
	var at := {}   # half-edge -> [face, i]
	for f in nf:
		var n: int = (fu[f] as PackedVector2Array).size()
		for i in n:
			at[m.face_he0[f] + i] = Vector2i(f, i)
	for h in at:
		var t: int = m.he_twin[h]
		if t == -1 or t < h or not at.has(t):
			continue
		var a: Vector2i = at[h]
		var b: Vector2i = at[t]
		var qa: PackedVector2Array = fu[a.x]
		var qb: PackedVector2Array = fu[b.x]
		# h: x->y in face A (corners i, i+1); t: y->x in face B (corners j, j+1): same UVs when A[i] = B[j+1], A[i+1] = B[j]
		if qa[a.y].distance_to(qb[(b.y + 1) % qb.size()]) < 1e-6 and qa[(a.y + 1) % qa.size()].distance_to(qb[b.y]) < 1e-6:
			var x := KMeshUV._find(p, a.x)
			var y := KMeshUV._find(p, b.x)
			if x != y:
				p[x] = y
	var ids := {}
	var isl := PackedInt32Array()
	isl.resize(nf)
	for f in nf:
		var r := KMeshUV._find(p, f)
		if not ids.has(r):
			ids[r] = ids.size()
		isl[f] = ids[r]
	return {"island": isl, "islands": ids.size()}


static func island_color(i: int) -> Color:
	return Color.from_hsv(fposmod(i * 0.618034, 1.0), 0.65, 0.9)


## the UV segments to draw, each once: [[a, b, border]] in UV units. border = only one face has it with these UVs
## (an island's edge: where the margin halo goes)
static func segments(fu: Array) -> Array:
	var seen := {}
	for q in fu:
		var n: int = (q as PackedVector2Array).size()
		for i in n:
			var a: Vector2 = q[i]
			var b: Vector2 = q[(i + 1) % n]
			var ka := Vector2i(roundi(a.x * 1e6), roundi(a.y * 1e6))
			var kb := Vector2i(roundi(b.x * 1e6), roundi(b.y * 1e6))
			var k := [ka, kb] if (ka.x < kb.x or (ka.x == kb.x and ka.y <= kb.y)) else [kb, ka]
			if seen.has(k):
				seen[k][2] = false
			else:
				seen[k] = [a, b, true]
	return seen.values()


## UV -> pixel (continuous: pixel (x, y) covers [x, x+1) x [y, y+1)); v = 0 is the bottom row
static func to_px(q: Vector2, size: int) -> Vector2:
	return Vector2(q.x * size, (1.0 - q.y) * size)


## the colour each face is filled with (alpha included), or [] for fill "none"
static func fill_colors(m: KMesh, fu: Array, o: Dictionary) -> Array:
	var out := []
	var a := float(o["fill_alpha"])
	match String(o["fill"]):
		"island":
			var isl: PackedInt32Array = islands(m, fu)["island"]
			for f in fu.size():
				var c := island_color(isl[f])
				c.a = a
				out.append(c)
		"stretch":
			var heat: PackedFloat32Array = KMeshUV.stretch(m).get("heat", PackedFloat32Array())
			for f in fu.size():
				var c := KMeshUV.heat_color(heat[f] if f < heat.size() else 0.0)
				c.a = a
				out.append(c)
	return out


## even-odd scanline fill of one polygon (pixel centres), each span one native fill_rect
static func _fill_poly(img: Image, pts: PackedVector2Array, c: Color) -> void:
	var size := img.get_width()
	var y0 := size
	var y1 := -1
	for p in pts:
		y0 = mini(y0, int(floor(p.y - 0.5)))
		y1 = maxi(y1, int(ceil(p.y - 0.5)))
	y0 = maxi(y0, 0)
	y1 = mini(y1, size - 1)
	var n := pts.size()
	for y in range(y0, y1 + 1):
		var cy := y + 0.5
		var xs := PackedFloat32Array()
		for i in n:
			var a := pts[i]
			var b := pts[(i + 1) % n]
			if (a.y <= cy) != (b.y <= cy):
				xs.append(a.x + (cy - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var xa := maxi(int(ceil(xs[k] - 0.5)), 0)
			var xb := mini(int(ceil(xs[k + 1] - 0.5)) - 1, size - 1)
			if xb >= xa:
				img.fill_rect(Rect2i(xa, y, xb - xa + 1, 1), c)


## coverage of a segment of half-width r (anti-aliased by 1 px) into cov (one float per pixel, max kept); calls
## touch(i) for each pixel index it reaches first. Walks the long axis, scanning only the cross band
static func _stroke(cov: PackedFloat32Array, size: int, a: Vector2, b: Vector2, r: float, touched: PackedInt32Array) -> PackedInt32Array:
	var d := b - a
	var L2 := d.length_squared()
	var reach := r + 1.0
	var horiz := absf(d.x) >= absf(d.y)
	var lo := minf(a.x, b.x) if horiz else minf(a.y, b.y)
	var hi := maxf(a.x, b.x) if horiz else maxf(a.y, b.y)
	var slope := (d.y / d.x if absf(d.x) > 1e-12 else 0.0) if horiz else (d.x / d.y if absf(d.y) > 1e-12 else 0.0)
	var band := reach * sqrt(1.0 + slope * slope) + 1.0
	for s in range(maxi(int(floor(lo - reach)), 0), mini(int(ceil(hi + reach)), size - 1) + 1):
		var sc := clampf(s + 0.5, lo, hi)
		var mid := (a.y + (sc - a.x) * slope) if horiz else (a.x + (sc - a.y) * slope)
		for t in range(maxi(int(floor(mid - band)), 0), mini(int(ceil(mid + band)), size - 1) + 1):
			var p := Vector2(s + 0.5, t + 0.5) if horiz else Vector2(t + 0.5, s + 0.5)
			var k := clampf((p - a).dot(d) / L2, 0.0, 1.0) if L2 > 1e-20 else 0.0
			var dist := p.distance_to(a + d * k)
			var c := clampf(r + 0.5 - dist, 0.0, 1.0)
			if c <= 0.0:
				continue
			var i := (t * size + s) if horiz else (s * size + t)
			if cov[i] == 0.0:
				touched.append(i)
			cov[i] = maxf(cov[i], c)
	return touched


## the layout as an RGBA8 image (transparent background), size x size
static func render_png(m: KMesh, opts := {}, uv := KMeshUV.UV) -> Image:
	var o := _opt(opts)
	var size: int = o["size"]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)   # all (0, 0, 0, 0)
	var fu := face_uvs(m, uv)
	if fu.is_empty():
		return img
	var px := []
	for q in fu:
		var p := PackedVector2Array()
		for c in q:
			p.append(to_px(c, size))
		px.append(p)
	var segs := segments(fu)
	var margin := float(o["margin"])
	if margin > 0.0:   # the halo: outside every island (an inside mask stops it), under fills and lines
		var inside := Image.create(size, size, false, Image.FORMAT_L8)
		for p in px:
			_fill_poly(inside, p, Color.WHITE)
		var hc := PackedFloat32Array()
		hc.resize(size * size)
		var ht := PackedInt32Array()
		for s in segs:
			if s[2]:
				ht = _stroke(hc, size, to_px(s[0], size), to_px(s[1], size), margin, ht)
		var mc: Color = o["margin_color"]
		for i in ht:
			var x := i % size
			var y := i / size
			if inside.get_pixel(x, y).r < 0.5:
				img.set_pixel(x, y, Color(mc.r, mc.g, mc.b, mc.a * hc[i]))
	var fc := fill_colors(m, fu, o)
	for f in fc.size():
		var c: Color = fc[f]
		_fill_poly(img, px[f], c)   # faces of one layout do not overlap, the halo is outside them: a plain write
	# lines: coverage first (max per pixel, so crossings and shared vertices do not darken), then one blend per pixel
	var cov := PackedFloat32Array()
	cov.resize(size * size)
	var touched := PackedInt32Array()
	var r := maxf(float(o["width"]), 0.01) * 0.5
	for s in segs:
		touched = _stroke(cov, size, to_px(s[0], size), to_px(s[1], size), r, touched)
	var lc: Color = o["line"]
	for i in touched:
		var x := i % size
		var y := i / size
		var src := Color(lc.r, lc.g, lc.b, lc.a * cov[i])
		img.set_pixel(x, y, _over(src, img.get_pixel(x, y)))
	return img


## src over dst (straight alpha)
static func _over(s: Color, d: Color) -> Color:
	var a := s.a + d.a * (1.0 - s.a)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	return Color((s.r * s.a + d.r * d.a * (1.0 - s.a)) / a, (s.g * s.a + d.g * d.a * (1.0 - s.a)) / a, (s.b * s.a + d.b * d.a * (1.0 - s.a)) / a, a)


static func _hex(c: Color) -> String:
	return "#" + c.to_html(false)


static func _n(x: float) -> String:
	return String.num(x, 3)


## the layout as SVG text: viewBox 0 0 size size, one <polygon> per face (id "f<face>", in face order, data-island),
## points = u * size, (1 - v) * size; the margin halo (when on) as a <g id="margin"> of <use> under the faces
static func render_svg(m: KMesh, opts := {}, uv := KMeshUV.UV) -> String:
	var o := _opt(opts)
	var size: int = o["size"]
	var fu := face_uvs(m, uv)
	var fc := fill_colors(m, fu, o)
	var isl: PackedInt32Array = islands(m, fu)["island"] if not fu.is_empty() else PackedInt32Array()
	var lc: Color = o["line"]
	var s := PackedStringArray()
	s.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
	s.append("<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\">" % [size, size, size, size])
	s.append("<!-- UV layout (Kine, ROADMAP_400 D11): x = u * %d, y = (1 - v) * %d, so UV (0, 0) is the bottom-left corner -->" % [size, size])
	var margin := float(o["margin"])
	if margin > 0.0 and not fu.is_empty():
		var mc: Color = o["margin_color"]
		s.append("<g id=\"margin\" fill=\"none\" stroke=\"%s\" stroke-opacity=\"%s\" stroke-width=\"%s\" stroke-linejoin=\"round\">" % [_hex(mc), _n(mc.a), _n(margin * 2.0)])
		for f in fu.size():
			s.append("<use xlink:href=\"#f%d\" href=\"#f%d\"/>" % [f, f])
		s.append("</g>")
	s.append("<g id=\"faces\" stroke=\"%s\" stroke-opacity=\"%s\" stroke-width=\"%s\" stroke-linejoin=\"round\">" % [_hex(lc), _n(lc.a), _n(float(o["width"]))])
	for f in fu.size():
		var pts := PackedStringArray()
		for c in fu[f]:
			var p := to_px(c, size)
			pts.append("%s,%s" % [_n(p.x), _n(p.y)])
		var fill := "fill=\"none\""
		if f < fc.size():
			fill = "fill=\"%s\" fill-opacity=\"%s\"" % [_hex(fc[f]), _n((fc[f] as Color).a)]
		s.append("<polygon id=\"f%d\" data-island=\"%d\" %s points=\"%s\"/>" % [f, isl[f], fill, " ".join(pts)])
	s.append("</g>")
	s.append("</svg>")
	return "\n".join(s) + "\n"


## a file-safe name (letters, digits, - and _), "layout" when nothing is left
static func clean_name(n: String) -> String:
	var out := ""
	for ch in n.strip_edges():
		out += ch if (ch.is_valid_identifier() or ch.is_valid_int() or ch == "-") else "_"
	return out if out.replace("_", "") != "" else "layout"


## the first free pair <dir>/<name>_uv_<size>[_N].png / .svg (neither file there yet)
static func free_base(dir: String, name: String, size: int) -> String:
	var base := "%s/%s_uv_%d" % [dir, clean_name(name), size]
	var b := base
	var k := 2
	while FileAccess.file_exists(b + ".png") or FileAccess.file_exists(b + ".svg"):
		b = "%s_%d" % [base, k]
		k += 1
	return b


## write the PNG and the SVG as NEW files. {"png", "svg", "faces", "ms"} or {"why"}
static func export(m: KMesh, name: String, opts := {}, dir := DIR, uv := KMeshUV.UV) -> Dictionary:
	if not m.has_attr(uv):
		return {"why": "the mesh has no UVs yet: unwrap it first (U on the test cube)"}
	var o := _opt(opts)
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var b := free_base(dir, name, o["size"])
	var img := render_png(m, o, uv)
	var e := img.save_png(b + ".png")
	if e != OK:
		return {"why": "could not write %s (error %d)" % [b + ".png", e]}
	var f := FileAccess.open(b + ".svg", FileAccess.WRITE)
	if f == null:
		return {"why": "could not write %s" % (b + ".svg")}
	f.store_string(render_svg(m, o, uv))
	f.close()
	return {"png": b + ".png", "svg": b + ".svg", "faces": m.face_count(), "ms": Time.get_ticks_msec() - t0}


# ---------------------------------------------------------------- the dialog ("Model: export UV layout")

## a small panel: size, line colour and width, fill, margin; Export writes both files and says where.
## mesh_of: a Callable returning the KMesh to export (the test cube's, unwrapped first when it has no UVs)
static func ask(host: Node, mesh_of: Callable, say: Callable) -> PopupPanel:
	var pp := PopupPanel.new()
	pp.name = "UVExport"
	var v := VBoxContainer.new()
	pp.add_child(v)
	var title := Label.new()
	title.text = "Export UV layout (PNG + SVG, transparent)"
	v.add_child(title)
	var g := GridContainer.new()
	g.columns = 2
	v.add_child(g)
	var row := func(t: String, c: Control) -> void:
		var l := Label.new()
		l.text = t
		g.add_child(l)
		g.add_child(c)
	var sz := OptionButton.new()
	for s in SIZES:
		sz.add_item("%d px" % s, s)
	sz.select(SIZES.find(DEFAULTS["size"]))
	row.call("Size", sz)
	var col := ColorPickerButton.new()
	col.color = DEFAULTS["line"]
	col.custom_minimum_size = Vector2(80, 24)
	row.call("Line colour", col)
	var wd := SpinBox.new()
	wd.min_value = 0.5
	wd.max_value = 16.0
	wd.step = 0.5
	wd.value = DEFAULTS["width"]
	wd.suffix = "px"
	row.call("Line width", wd)
	var fl := OptionButton.new()
	for t in ["No fill", "Fill by island", "Fill by stretch (heat)"]:
		fl.add_item(t)
	row.call("Faces", fl)
	var mg := SpinBox.new()
	mg.min_value = 0.0
	mg.max_value = 64.0
	mg.step = 1.0
	mg.value = 0.0
	mg.suffix = "px"
	row.call("Margin outline", mg)
	var go := Button.new()
	go.text = "Export"
	v.add_child(go)
	go.pressed.connect(func():
		var o := {"size": SIZES[sz.selected], "line": col.color, "width": wd.value, "fill": FILLS[fl.selected], "margin": mg.value}
		var r := export(mesh_of.call(), "test_cube", o)
		pp.hide()
		if r.has("why"):
			say.call("Model: " + String(r["why"]))
		else:
			say.call("Model: UV layout, %d faces, %d px -> %s and .svg (new files; nothing overwritten)" % [r["faces"], o["size"], ProjectSettings.globalize_path(r["png"])])
		pp.queue_free())
	host.add_child(pp)
	pp.popup_centered()
	return pp
