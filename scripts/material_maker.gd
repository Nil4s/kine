class_name MaterialMaker
extends RefCounted
## MATERIAL MAKER (Friday plan 223, LOOKS): a material library MADE IN CODE. No picture files, no AI model: each material is a small
## recipe of seeded, tileable noise that writes three maps (Images, 512 px by default): ALBEDO (sRGB), ROUGHNESS (L8) and NORMAL.
## A material is a SPEC, a Dictionary of numbers, so a variant is a number change, not a file:
##   {"kind": "oak", "color": "#9a6b3f", "scale": 200.0 (mm one tile covers), "wear": 0..1, "gloss": 0..1, "seed": int,
##    "warp": 0..1 (wood: how much the rings wander), "vein": "#.." (marble), "brushed": 0|1 (steel), "metal": 0..1, "alpha": 0..1}
## SAME SPEC -> SAME BYTES (the noise is seeded by the spec; nothing reads a clock). A different seed -> different bytes.
## TILEABLE: every noise field is built from a lattice that wraps and a 2^k scale-up, so the right edge continues into the left edge.
## MAPPING: standard() gives a StandardMaterial3D with TRIPLANAR mapping in the mesh's own space, one tile = "scale" mm
## (meshes are in metres), so a grain is the same size in mm on a 10 mm cube and on a 100 mm cube and never stretches on a bad UV.
## Words ("dark oak", "red lacquer, a bit worn") are scripts/material_words.gd.

const SIZE := 512
const MM := 0.001   # a mesh unit is a metre (Part.MM)
const MAX_CACHE := 40

## kind -> defaults. color is sRGB html; gloss 0 (dull) .. 1 (mirror); metal is the StandardMaterial3D metallic; scale is mm per tile.
const DEFS := {
	"oak": {"label": "Oak", "color": "#a9794a", "scale": 240.0, "gloss": 0.35, "wear": 0.0, "metal": 0.0, "warp": 0.35},
	"pine": {"label": "Pine", "color": "#dcb279", "scale": 240.0, "gloss": 0.3, "wear": 0.0, "metal": 0.0, "warp": 0.45},
	"plywood": {"label": "Plywood edge", "color": "#d9b682", "scale": 120.0, "gloss": 0.25, "wear": 0.0, "metal": 0.0, "warp": 0.3},
	"steel": {"label": "Brushed steel", "color": "#c4c7cc", "scale": 120.0, "gloss": 0.7, "wear": 0.0, "metal": 1.0, "brushed": 1},
	"iron": {"label": "Cast iron", "color": "#4a4a4d", "scale": 160.0, "gloss": 0.35, "wear": 0.0, "metal": 0.9},
	"copper": {"label": "Copper", "color": "#e08a62", "scale": 160.0, "gloss": 0.65, "wear": 0.0, "metal": 1.0},
	"brass": {"label": "Brass", "color": "#e2bb5c", "scale": 160.0, "gloss": 0.7, "wear": 0.0, "metal": 1.0},
	"lacquer": {"label": "Red lacquer", "color": "#b3121a", "scale": 160.0, "gloss": 0.92, "wear": 0.0, "metal": 0.0},
	"tile": {"label": "Glazed roof tile", "color": "#e8741c", "scale": 800.0, "gloss": 0.9, "wear": 0.0, "metal": 0.0},
	"terracotta": {"label": "Terracotta", "color": "#b8623c", "scale": 300.0, "gloss": 0.12, "wear": 0.0, "metal": 0.0},
	"granite": {"label": "Granite", "color": "#8e8584", "scale": 300.0, "gloss": 0.55, "wear": 0.0, "metal": 0.0},
	"marble": {"label": "White marble", "color": "#eeeeec", "scale": 600.0, "gloss": 0.8, "wear": 0.0, "metal": 0.0, "vein": "#77797e"},
	"concrete": {"label": "Concrete", "color": "#8a8a86", "scale": 500.0, "gloss": 0.08, "wear": 0.0, "metal": 0.0},
	"brick": {"label": "Brick", "color": "#a94f3a", "scale": 900.0, "gloss": 0.08, "wear": 0.0, "metal": 0.0},
	"plaster": {"label": "Plaster", "color": "#e6dfd0", "scale": 600.0, "gloss": 0.06, "wear": 0.0, "metal": 0.0},
	"grass": {"label": "Grass", "color": "#4f8f2a", "scale": 400.0, "gloss": 0.12, "wear": 0.0, "metal": 0.0},
	"gravel": {"label": "Gravel", "color": "#9a958c", "scale": 400.0, "gloss": 0.1, "wear": 0.0, "metal": 0.0},
	"fabric": {"label": "Fabric", "color": "#3d5a8c", "scale": 80.0, "gloss": 0.05, "wear": 0.0, "metal": 0.0},
	"leather": {"label": "Leather", "color": "#6b3a1f", "scale": 160.0, "gloss": 0.45, "wear": 0.0, "metal": 0.0},
	"rubber": {"label": "Rubber", "color": "#232325", "scale": 120.0, "gloss": 0.06, "wear": 0.0, "metal": 0.0},
	"glass": {"label": "Glass (tint)", "color": "#a8d4e0", "scale": 300.0, "gloss": 0.97, "wear": 0.0, "metal": 0.0, "alpha": 0.38},
	"plastic": {"label": "Plastic, glossy", "color": "#2f6fd0", "scale": 200.0, "gloss": 0.85, "wear": 0.0, "metal": 0.0},
}
## the library, in the order the pickers show it: [id, kind, overrides]. "plastic_matte" is the same recipe, matte
const LIBRARY := [
	["oak", "oak", {}], ["pine", "pine", {}], ["plywood", "plywood", {}], ["steel", "steel", {}], ["iron", "iron", {}],
	["copper", "copper", {}], ["brass", "brass", {}], ["lacquer", "lacquer", {"wear": 0.3}], ["tile", "tile", {}],
	["terracotta", "terracotta", {}], ["granite", "granite", {}], ["marble", "marble", {}], ["concrete", "concrete", {}],
	["brick", "brick", {}], ["plaster", "plaster", {}], ["grass", "grass", {}], ["gravel", "gravel", {}],
	["fabric", "fabric", {}], ["leather", "leather", {}], ["rubber", "rubber", {}], ["glass", "glass", {}],
	["plastic", "plastic", {}], ["plastic_matte", "plastic", {"gloss": 0.15, "color": "#d8d4c8"}],
]

static var _cache := {}        # key -> {"albedo": Image, "rough": Image, "normal": Image, "tex": [..]}
static var _cache_order := []
static var makes := 0          # maps generated this run (a test counts them)


# ---------------------------------------------------------------- the spec

## a spec with every number filled and clamped. Accepts a Color or an html string for "color" and "vein". {} for an unknown kind
static func norm(spec: Dictionary) -> Dictionary:
	var kind := String(spec.get("kind", ""))
	if not DEFS.has(kind):
		return {}
	var d: Dictionary = DEFS[kind]
	var out := {"kind": kind}
	out["color"] = _html(spec.get("color", d["color"]), String(d["color"]))
	out["scale"] = clampf(float(spec.get("scale", d["scale"])), 2.0, 5000.0)
	out["wear"] = clampf(float(spec.get("wear", d["wear"])), 0.0, 1.0)
	out["gloss"] = clampf(float(spec.get("gloss", d["gloss"])), 0.0, 1.0)
	out["seed"] = int(spec.get("seed", 1))
	out["metal"] = clampf(float(spec.get("metal", d["metal"])), 0.0, 1.0)
	if d.has("warp"):
		out["warp"] = clampf(float(spec.get("warp", d["warp"])), 0.0, 1.0)
	if d.has("vein"):
		out["vein"] = _html(spec.get("vein", d["vein"]), String(d["vein"]))
	if d.has("brushed"):
		out["brushed"] = 1 if float(spec.get("brushed", d["brushed"])) >= 0.5 else 0
	if d.has("alpha"):
		out["alpha"] = clampf(float(spec.get("alpha", d["alpha"])), 0.05, 1.0)
	return out


static func _html(v: Variant, fallback: String) -> String:
	if v is Color:
		return "#" + (v as Color).to_html(false)
	var s := String(v)
	if s.is_valid_html_color():
		return "#" + Color(s).to_html(false)
	return fallback


## the library entry (id) as a spec
static func library_spec(id: String) -> Dictionary:
	for e in LIBRARY:
		if String(e[0]) == id:
			var s: Dictionary = (e[2] as Dictionary).duplicate()
			s["kind"] = e[1]
			return norm(s)
	return {}


static func library_ids() -> Array:
	var out := []
	for e in LIBRARY:
		out.append(String(e[0]))
	return out


static func label_of(id: String) -> String:
	for e in LIBRARY:
		if String(e[0]) == id:
			return "Plastic, matte" if id == "plastic_matte" else String(DEFS[e[1]]["label"])
	return id


static func key_of(spec: Dictionary, size := SIZE) -> String:
	return "%s@%d" % [JSON.stringify(spec, "", true), size]


# ---------------------------------------------------------------- the maps

## the three maps of a spec: {"spec", "albedo": Image (RGB8), "rough": Image (L8), "normal": Image (RGB8), "size"}. Not cached (see maps())
static func make(spec_in: Dictionary, size := SIZE) -> Dictionary:
	var sp := norm(spec_in)
	if sp.is_empty():
		return {}
	makes += 1
	var n := clampi(size, 16, 1024)
	var g := _Gen.new(sp, n)
	g.run()
	var h := g.ht
	return {"spec": sp, "size": n,
		"albedo": Image.create_from_data(n, n, false, Image.FORMAT_RGB8, g.al),
		"rough": Image.create_from_data(n, n, false, Image.FORMAT_L8, g.ro),
		"normal": Image.create_from_data(n, n, false, Image.FORMAT_RGB8, _normal(h, n, g.bump))}


## the same, remembered (the pickers and the view ask again and again)
static func maps(spec_in: Dictionary, size := SIZE) -> Dictionary:
	var sp := norm(spec_in)
	if sp.is_empty():
		return {}
	var key := key_of(sp, size)
	if _cache.has(key):
		return _cache[key]
	var r := make(sp, size)
	_cache[key] = r
	_cache_order.append(key)
	while _cache_order.size() > MAX_CACHE:
		_cache.erase(_cache_order.pop_front())
	return r


## a height field -> a tangent-space normal map (OpenGL green up). Wraps at the edges, so a tileable height stays tileable
static func _normal(h: PackedFloat32Array, n: int, strength: float) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n * n * 3)
	var m := n - 1
	var k := strength * float(n) / 256.0
	for y in n:
		var y0 := ((y - 1) & m) * n
		var y1 := ((y + 1) & m) * n
		var yy := y * n
		for x in n:
			var dx := (h[yy + ((x + 1) & m)] - h[yy + ((x - 1) & m)]) * k
			var dy := (h[y1 + x] - h[y0 + x]) * k
			var il := 1.0 / sqrt(dx * dx + dy * dy + 1.0)
			var j := (yy + x) * 3
			out[j] = int(clampf(0.5 - dx * il * 0.5, 0.0, 1.0) * 255.0 + 0.5)
			out[j + 1] = int(clampf(0.5 + dy * il * 0.5, 0.0, 1.0) * 255.0 + 0.5)
			out[j + 2] = int(clampf(0.5 + il * 0.5, 0.0, 1.0) * 255.0 + 0.5)
	return out


# ---------------------------------------------------------------- the material

## a StandardMaterial3D with the maps, TRIPLANAR in the mesh's own space (one tile = spec.scale mm). Glass is see-through
static func standard(spec_in: Dictionary, size := SIZE) -> StandardMaterial3D:
	var r := maps(spec_in, size)
	var mt := StandardMaterial3D.new()
	if r.is_empty():
		return mt
	var sp: Dictionary = r["spec"]
	var tx := textures(r)
	mt.albedo_texture = tx[0]
	mt.roughness_texture = tx[1]
	mt.roughness = 1.0
	mt.metallic = float(sp["metal"])
	mt.normal_enabled = true
	mt.normal_texture = tx[2]
	mt.normal_scale = 1.0
	mt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mt.texture_repeat = true
	mt.uv1_triplanar = true
	mt.uv1_triplanar_sharpness = 4.0
	var k := 1.0 / (float(sp["scale"]) * MM)
	mt.uv1_scale = Vector3(k, k, k)
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	var a := float(sp.get("alpha", 1.0))
	if a < 1.0:
		mt.albedo_color = Color(1, 1, 1, a)
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mt


## [albedo, roughness, normal] ImageTextures of a maps() result, made once per result
static func textures(r: Dictionary) -> Array:
	if r.has("tex"):
		return r["tex"]
	var out := []
	for k in ["albedo", "rough", "normal"]:
		var im: Image = (r[k] as Image).duplicate()
		im.generate_mipmaps()
		out.append(ImageTexture.create_from_image(im))
	r["tex"] = out
	return out


## the material a Part look wears: its "mat" spec when it has one (else null, so the caller keeps its plain colour)
static func look_material(look: Dictionary, xray_alpha := 1.0) -> StandardMaterial3D:
	var spec: Variant = look.get("mat", null)
	if not (spec is Dictionary) or (spec as Dictionary).is_empty():
		return null
	var mt := standard(spec as Dictionary)
	var a := minf(float(look.get("alpha", 1.0)), xray_alpha)   # the look's alpha (a mat feature stores the spec's alpha) and X-ray
	if a < 1.0:
		mt.albedo_color = Color(1, 1, 1, a)
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mt


## the Part look numbers a spec stands for: roughness (mean of the map's roughness), metal, alpha, and the average colour
static func look_numbers(spec_in: Dictionary) -> Dictionary:
	var sp := norm(spec_in)
	if sp.is_empty():
		return {}
	var r := maps(sp, 64)
	var im: Image = r["albedo"]
	var rg: Image = r["rough"]
	var sum := Color(0, 0, 0)
	var rs := 0.0
	var step := 4
	var cnt := 0
	for y in range(0, 64, step):
		for x in range(0, 64, step):
			sum += im.get_pixel(x, y)
			rs += rg.get_pixel(x, y).r
			cnt += 1
	return {"c": Color(sum.r / cnt, sum.g / cnt, sum.b / cnt), "rough": rs / cnt, "metal": float(sp["metal"]), "alpha": float(sp.get("alpha", 1.0))}


## a small picture of a material for a chip: the albedo at px x px (a 64 px render of the same recipe)
static func swatch(spec_in: Dictionary, px := 32) -> Image:
	var r := maps(spec_in, 64)
	if r.is_empty():
		return null
	var im: Image = (r["albedo"] as Image).duplicate()
	if px != 64:
		im.resize(px, px, Image.INTERPOLATE_LANCZOS)
	return im


# ---------------------------------------------------------------- tests of a map (used by the tests and by the checks)

## per column pair (x, x+1 wrapping) and per row pair: mean |difference| over the other axis and all channels. The pair (n-1, 0) is the SEAM.
## {"cols": PackedFloat32Array(n), "rows": PackedFloat32Array(n)}; the tile is seamless when its seam is no worse than any other pair
static func seam_profile(im: Image) -> Dictionary:
	var n := im.get_width()
	var d := im.get_data()
	var ch := 3 if im.get_format() == Image.FORMAT_RGB8 else 1
	var cols := PackedFloat32Array()
	cols.resize(n)
	var rows := PackedFloat32Array()
	rows.resize(n)
	for y in n:
		var y1 := ((y + 1) % n) * n
		var yy := y * n
		for x in n:
			var x1 := (x + 1) % n
			var a := (yy + x) * ch
			var bx := (yy + x1) * ch
			var by := (y1 + x) * ch
			for c in ch:
				cols[x] += absf(float(d[a + c]) - float(d[bx + c]))
				rows[y] += absf(float(d[a + c]) - float(d[by + c]))
	var k := 1.0 / float(n * ch)
	for i in n:
		cols[i] *= k
		rows[i] *= k
	return {"cols": cols, "rows": rows}


## the seam of one axis against the other pairs: {"seam", "inner" (mean of the n-1 inner pairs), "ratio", "z" (how many spreads above the inner mean)}
static func seam_stat(prof: PackedFloat32Array) -> Dictionary:
	var n := prof.size()
	var mean := 0.0
	for i in n - 1:
		mean += prof[i]
	mean /= float(n - 1)
	var v := 0.0
	for i in n - 1:
		v += (prof[i] - mean) * (prof[i] - mean)
	var sd := sqrt(v / float(n - 1))
	var seam := prof[n - 1]
	return {"seam": seam, "inner": mean, "ratio": seam / maxf(mean, 1e-6), "z": (seam - mean) / maxf(sd, 1e-6)}


# ================================================================ the generator

class _Gen:
	var sp: Dictionary
	var n: int
	var sd: int
	var al := PackedByteArray()
	var ro := PackedByteArray()
	var ht := PackedFloat32Array()
	var bump := 2.0
	var cr := 0.5
	var cg := 0.5
	var cb := 0.5
	var gloss := 0.5
	var wear := 0.0
	var wm := PackedFloat32Array()   # wear mask 0..1 (empty when wear == 0)

	func _init(spec: Dictionary, size: int) -> void:
		sp = spec
		n = size
		sd = int(spec["seed"]) * 1000003 + (String(spec["kind"]).hash() & 0xffffff)
		var c := Color(String(spec["color"]))
		cr = c.r
		cg = c.g
		cb = c.b
		gloss = float(spec["gloss"])
		wear = float(spec["wear"])
		al.resize(n * n * 3)
		ro.resize(n * n)
		ht.resize(n * n)

	func run() -> void:
		if wear > 0.001:
			wm = _wear_mask()
		match String(sp["kind"]):
			"oak", "pine":
				_wood()
			"plywood":
				_plywood()
			"steel":
				_steel()
			"iron":
				_iron()
			"copper", "brass":
				_coppery()
			"lacquer", "plastic", "rubber", "glass":
				_paint()
			"tile":
				_tile()
			"terracotta":
				_terracotta()
			"granite":
				_granite()
			"marble":
				_marble()
			"concrete", "plaster":
				_concrete()
			"brick":
				_brick()
			"grass":
				_grass()
			"gravel":
				_gravel()
			"fabric":
				_fabric()
			"leather":
				_leather()

	# ------------------------------------------------ fields

	## a tileable random field in about 0..1: a lattice of nx x ny random values (powers of two, wrapped), scaled up to n x n with cubic
	## interpolation. nx much smaller than ny = streaks along x
	@warning_ignore("integer_division")
	func fld(nx: int, ny: int, salt: int) -> PackedFloat32Array:
		nx = clampi(nx, 1, n)
		ny = clampi(ny, 1, n)
		var px := n / nx
		var py := n / ny
		var rng := RandomNumberGenerator.new()
		rng.seed = (sd + salt * 7919 + nx * 131 + ny) & 0x7fffffffffff
		var lat := PackedFloat32Array()
		lat.resize(nx * ny)
		for i in lat.size():
			lat[i] = rng.randf()
		var w := nx + 4
		var h := ny + 4
		var pad := PackedFloat32Array()
		pad.resize(w * h)
		for y in h:
			var ly := (((y - 2) % ny) + ny) % ny
			for x in w:
				pad[y * w + x] = lat[ly * nx + (((x - 2) % nx) + nx) % nx]
		var im := Image.create_from_data(w, h, false, Image.FORMAT_RF, pad.to_byte_array())
		if px > 1 or py > 1:
			im.resize(w * px, h * py, Image.INTERPOLATE_CUBIC)
		return im.get_region(Rect2i(2 * px, 2 * py, n, n)).get_data().to_float32_array()

	## fractal sum of fields, about 0.2..0.8, with nx x ny at the first octave and the lattice doubling each octave
	func fbm(nx: int, ny: int, oct: int, salt: int) -> PackedFloat32Array:
		var acc := fld(nx, ny, salt)
		var amp := 1.0
		var tot := 1.0
		for o in range(1, oct):
			amp *= 0.5
			tot += amp
			var f := fld(nx << o, ny << o, salt + o * 17)
			for i in acc.size():
				acc[i] += f[i] * amp
		var inv := 1.0 / tot
		for i in acc.size():
			acc[i] *= inv
		return acc

	## where the material is worn (1) and where it is not (0): blotches that grow with wear, and thin scratches
	func _wear_mask() -> PackedFloat32Array:
		var a := fbm(4, 4, 4, 900)
		var s1 := fld(2, 256, 901)
		var s2 := fld(256, 2, 902)
		var out := PackedFloat32Array()
		out.resize(n * n)
		var thr := 1.0 - wear * 0.62
		for i in n * n:
			var blot := smoothstep(thr - 0.02, thr + 0.1, a[i])
			var sc := smoothstep(0.95 - wear * 0.1, 0.985, s1[i]) + smoothstep(0.95 - wear * 0.1, 0.985, s2[i])
			out[i] = clampf(maxf(blot, minf(sc, 1.0) * minf(wear * 1.6, 1.0)), 0.0, 1.0)
		return out

	func rough_base() -> float:
		return lerpf(0.92, 0.06, gloss)

	# write one pixel (colour 0..1, roughness 0..1, height)
	func put(i: int, r: float, g: float, b: float, rough: float, h: float) -> void:
		var j := i * 3
		al[j] = int(clampf(r, 0.0, 1.0) * 255.0 + 0.5)
		al[j + 1] = int(clampf(g, 0.0, 1.0) * 255.0 + 0.5)
		al[j + 2] = int(clampf(b, 0.0, 1.0) * 255.0 + 0.5)
		ro[i] = int(clampf(rough, 0.02, 1.0) * 255.0 + 0.5)
		ht[i] = h

	# ------------------------------------------------ wood

	func _knots(count: int) -> Array:
		var rng := RandomNumberGenerator.new()
		rng.seed = sd + 4242
		var out := []
		for k in count:
			out.append([rng.randf(), rng.randf(), rng.randf_range(0.04, 0.08)])
		return out

	func _wood() -> void:
		var pine := String(sp["kind"]) == "pine"
		var rings := 5.0 if pine else 9.0
		var warp := float(sp.get("warp", 0.35))
		var fw := fbm(2, 8, 3, 1)
		var ff := fld(256, 4, 2)
		var ff2 := fld(64, 8, 3)
		var fp := fld(256, 32, 4)
		var knots := _knots(2 if pine else 1)
		if warp <= 0.0:
			knots = []
		var dr := cr * 0.5
		var dg := cg * 0.4
		var db := cb * 0.34
		var rb := rough_base()
		for y in n:
			var v := float(y) / float(n)
			for x in n:
				var i := y * n + x
				var u := float(x) / float(n)
				var t := u * rings + (fw[i] - 0.5) * warp * rings * 0.22
				var core := 0.0
				for k in knots:
					var sdx := u - float(k[0])
					sdx -= roundf(sdx)
					var dx := absf(sdx)
					var dy := absf(v - float(k[1]))
					dy = minf(dy, 1.0 - dy)
					var d2 := (dx * dx + dy * dy) / (float(k[2]) * float(k[2]))
					if d2 < 9.0:
						var e := exp(-d2 * 0.35)
						t += e * 3.0 * sdx / float(k[2])
						core = maxf(core, exp(-d2 * 2.2))
				var fr := t - floorf(t)
				var band := fr * fr * fr
				var fib := ff[i] * 0.6 + ff2[i] * 0.4
				var pore := smoothstep(0.84, 0.97, fp[i]) * (0.35 if pine else 0.8)
				var k2 := clampf(band * (0.7 if pine else 0.82) + (fib - 0.5) * 0.55 + core * 0.6, 0.0, 1.0)
				var r := lerpf(cr, dr, k2) * (1.0 - 0.4 * pore)
				var g := lerpf(cg, dg, k2) * (1.0 - 0.42 * pore)
				var b := lerpf(cb, db, k2) * (1.0 - 0.45 * pore)
				var rough := rb + (fib - 0.5) * 0.18 + band * 0.1 + pore * 0.2
				if wm.size() > 0:
					var w := wm[i]
					var gr := (r + g + b) / 3.0 * 0.85 + 0.12
					r = lerpf(r, gr, w * 0.6)
					g = lerpf(g, gr * 0.97, w * 0.6)
					b = lerpf(b, gr * 0.93, w * 0.6)
					rough += w * 0.3
				put(i, r, g, b, rough, -band * 0.35 + fib * 0.18 - pore * 0.6 - core * 0.2)
		bump = 3.0

	func _plywood() -> void:
		var plies := 9
		var rng := RandomNumberGenerator.new()
		rng.seed = sd + 77
		var tone := []
		for k in plies:
			tone.append(0.84 + rng.randf() * 0.3)
		var ff := fld(4, 256, 5)
		var ff2 := fld(16, 128, 6)
		var fw := fbm(4, 16, 3, 7)
		var rb := rough_base()
		var dg := Color(String(sp["color"]))
		for y in n:
			var tv := float(y) / float(n) * plies
			var li := int(floorf(tv))
			var fr := tv - float(li)
			var glue := 1.0 - smoothstep(0.0, 0.05, fr) * (1.0 - smoothstep(0.93, 1.0, fr))
			for x in n:
				var i := y * n + x
				var u := float(x) / float(n)
				var wave := sin((u * 3.0 + (fw[i] - 0.5) * 1.6) * TAU)
				var tn: float = tone[li % plies] + 0.06 * wave
				var fib := ff[i] * 0.6 + ff2[i] * 0.4
				var k := (fib - 0.5) * 0.5
				var f := tn * (1.0 - k * 0.6) * (1.0 - glue * 0.4)
				var r := cr * f
				var g := cg * f * (1.0 - 0.03 * k)
				var b := cb * f * (1.0 - 0.1 * k)
				var rough := rb + (fib - 0.5) * 0.2 + glue * 0.15
				if wm.size() > 0:
					r = lerpf(r, dg.r * 0.6, wm[i] * 0.5)
					g = lerpf(g, dg.g * 0.55, wm[i] * 0.5)
					b = lerpf(b, dg.b * 0.5, wm[i] * 0.5)
					rough += wm[i] * 0.3
				put(i, r, g, b, rough, fib * 0.25 - glue * 0.6)
		bump = 3.0

	# ------------------------------------------------ metals

	func _steel() -> void:
		var brushed := int(sp.get("brushed", 1)) == 1
		var s1 := fld(2, 256, 11)
		var s2 := fld(4, 256, 12)
		var s3 := fld(8, 512, 13)
		var cl := fbm(4, 4, 3, 14)
		var amp := 1.0 if brushed else 0.25
		var rb := lerpf(0.5, 0.1, gloss) + (0.1 if brushed else 0.0)
		for i in n * n:
			var st := (s1[i] - 0.5) * 0.26 + (s2[i] - 0.5) * 0.2 + (s3[i] - 0.5) * 0.12
			var tone := 1.0 + st * amp + (cl[i] - 0.5) * 0.1
			var r := cr * tone
			var g := cg * tone
			var b := cb * tone
			var rough := rb + (s2[i] - 0.5) * 0.2 * amp + (cl[i] - 0.5) * 0.15
			if wm.size() > 0:
				var w := wm[i]
				r *= 1.0 - 0.3 * w
				g *= 1.0 - 0.3 * w
				b *= 1.0 - 0.27 * w
				rough += w * 0.3
			put(i, r, g, b, rough, st * 0.5)
		bump = 1.5

	func _iron() -> void:
		var cl := fbm(8, 8, 5, 21)
		var sp1 := fld(256, 256, 22)
		var pit := fld(128, 128, 23)
		var rb := lerpf(0.9, 0.35, gloss)
		for i in n * n:
			var mot := (cl[i] - 0.5)
			var sparkle := smoothstep(0.9, 0.99, sp1[i])
			var pitm := smoothstep(0.86, 0.96, pit[i])
			var tone := 1.0 + mot * 0.5 + sparkle * 0.5 - pitm * 0.5
			var r := cr * tone
			var g := cg * tone
			var b := cb * tone * 1.02
			var rough := rb + mot * 0.3 + pitm * 0.2
			if wm.size() > 0:
				var w := wm[i] * smoothstep(0.35, 0.6, cl[i] + 0.1)
				r = lerpf(r, 0.5 + mot * 0.3, w)
				g = lerpf(g, 0.24 + mot * 0.12, w)
				b = lerpf(b, 0.1, w)
				rough = lerpf(rough, 0.9, w)
			put(i, r, g, b, rough, mot * 0.6 - pitm * 0.8)
		bump = 3.0

	func _coppery() -> void:
		var copper := String(sp["kind"]) == "copper"
		var cl := fbm(4, 4, 5, 31)
		var s2 := fld(4, 256, 32)
		var s3 := fld(2, 128, 33)
		var rb := lerpf(0.65, 0.1, gloss)
		for i in n * n:
			var mot := cl[i] - 0.5
			var st := (s2[i] - 0.5) * 0.08 + (s3[i] - 0.5) * 0.05
			var tone := 1.0 + mot * 0.4 + st
			var r := cr * tone
			var g := cg * tone * (1.0 - mot * 0.1)
			var b := cb * tone * (1.0 - mot * 0.15)
			var rough := rb + mot * 0.3 + st * 0.4
			if wm.size() > 0:
				var w := wm[i] * smoothstep(0.38, 0.62, cl[i] + 0.1)
				if copper:   # verdigris
					r = lerpf(r, 0.26 + mot * 0.2, w)
					g = lerpf(g, 0.62 + mot * 0.2, w)
					b = lerpf(b, 0.52 + mot * 0.2, w)
				else:   # dull tarnish
					r = lerpf(r, 0.42, w * 0.8)
					g = lerpf(g, 0.31, w * 0.8)
					b = lerpf(b, 0.14, w * 0.8)
				rough = lerpf(rough, 0.85, w)
			put(i, r, g, b, rough, mot * 0.4 + st)
		bump = 1.8

	# ------------------------------------------------ paint family

	func _paint() -> void:
		var kind := String(sp["kind"])
		var peel := fbm(64, 64, 3, 41)
		var low := fbm(4, 4, 3, 42)
		var grain := fld(256, 256, 43)
		var rb := lerpf(0.88, 0.05, gloss)
		var primer := Color(0.5, 0.5, 0.53)
		for i in n * n:
			var p := peel[i] - 0.5
			var l := low[i] - 0.5
			var tone := 1.0 + l * 0.06
			var amp := 0.0
			match kind:
				"rubber":
					tone = 1.0 + (grain[i] - 0.5) * 0.5 + l * 0.25
					amp = 0.5
				"plastic":
					tone = 1.0 + l * 0.03
					amp = 0.18
				"glass":
					tone = 1.0 + l * 0.12
					amp = 0.06
				_:   # lacquer: deep colour, a little pooled darker
					tone = 1.0 + l * 0.4
					amp = 0.2
			var r := cr * tone
			var g := cg * tone
			var b := cb * tone
			var rough := rb + p * (0.25 if kind == "rubber" else 0.05)
			var h := p * amp
			if wm.size() > 0:
				var w := wm[i]
				if kind == "lacquer":
					var chip := smoothstep(0.4, 0.55, w)
					var rim := smoothstep(0.2, 0.4, w) * (1.0 - chip)
					r = lerpf(r * (1.0 + 0.12 * rim), primer.r, chip)
					g = lerpf(g * (1.0 + 0.12 * rim), primer.g, chip)
					b = lerpf(b * (1.0 + 0.12 * rim), primer.b, chip)
					rough = lerpf(rough + rim * 0.3, 0.7, chip)
					h -= chip * 0.7
				else:
					var lg := (r + g + b) / 3.0
					r = lerpf(r, lg * 0.8 + 0.12, w * 0.5)
					g = lerpf(g, lg * 0.8 + 0.12, w * 0.5)
					b = lerpf(b, lg * 0.8 + 0.12, w * 0.5)
					rough += w * 0.35
					h -= w * 0.2
			put(i, r, g, b, rough, h)
		bump = 2.0

	# ------------------------------------------------ ceramics

	func _tile() -> void:
		var cols := 4
		var rows := 4
		var rng := RandomNumberGenerator.new()
		rng.seed = sd + 55
		var vr := []
		for k in cols * rows:
			vr.append([rng.randf(), rng.randf()])
		var mo := fbm(16, 16, 3, 51)
		var fine := fld(128, 128, 52)
		var rb := lerpf(0.75, 0.07, gloss)
		for y in n:
			var cv := float(y) / float(n) * rows + 0.5
			var ri := int(floorf(cv))
			var fy := cv - float(ri)
			var shade := 0.5 + 0.5 * smoothstep(0.0, 0.3, fy)
			var lip := smoothstep(0.88, 1.0, fy)
			for x in n:
				var i := y * n + x
				var cu := float(x) / float(n) * cols + 0.5
				var ci := int(floorf(cu))
				var fx := cu - float(ci)
				var crown := sin(fx * PI)
				var tv: Array = vr[(ri % rows) * cols + (ci % cols)]
				var glaze := (mo[i] - 0.5) * 0.12 + (fine[i] - 0.5) * 0.03
				var tone := (0.88 + 0.22 * float(tv[0]) + glaze) * shade * (0.72 + 0.28 * crown) * (1.0 + lip * 0.15)
				var r := cr * tone
				var g := cg * tone * (0.94 + 0.12 * float(tv[1]))
				var b := cb * tone
				var rough := rb + (fine[i] - 0.5) * 0.06 + (1.0 - crown) * 0.1
				if wm.size() > 0:
					var w := wm[i]
					r = lerpf(r, 0.36, w * 0.6)
					g = lerpf(g, 0.31, w * 0.6)
					b = lerpf(b, 0.24, w * 0.6)
					rough = lerpf(rough, 0.85, w * 0.8)
				put(i, r, g, b, rough, crown * 0.7 + fy * 0.3 - lip * 0.5)
		bump = 3.0

	func _terracotta() -> void:
		var cl := fbm(8, 8, 5, 61)
		var grit := fld(256, 256, 62)
		var spk := fld(256, 256, 63)
		var rb := lerpf(0.94, 0.4, gloss)
		for i in n * n:
			var mot := cl[i] - 0.5
			var sp1 := smoothstep(0.9, 0.99, spk[i])
			var tone := 1.0 + mot * 0.5 + (grit[i] - 0.5) * 0.12 - sp1 * 0.3
			var r := cr * tone
			var g := cg * tone * (1.0 + mot * 0.1)
			var b := cb * tone
			var rough := rb + (grit[i] - 0.5) * 0.1
			if wm.size() > 0:
				var w := wm[i]
				r = lerpf(r, 0.62, w * 0.5)
				g = lerpf(g, 0.55, w * 0.5)
				b = lerpf(b, 0.47, w * 0.5)
			put(i, r, g, b, rough, mot * 0.5 + (grit[i] - 0.5) * 0.5)
		bump = 2.5

	func _brick() -> void:
		var cols := 4
		var rows := 12
		var rng := RandomNumberGenerator.new()
		rng.seed = sd + 88
		var vr := []
		for k in cols * rows:
			vr.append([rng.randf(), rng.randf()])
		var cl := fbm(8, 8, 4, 81)
		var grit := fld(256, 256, 82)
		var pit := fld(128, 128, 83)
		var mortar := Color(0.66, 0.63, 0.57)
		var rb := lerpf(0.95, 0.5, gloss)
		var mx := 0.045
		var my := 0.1
		for y in n:
			var cv := float(y) / float(n) * rows + 0.5
			var ri := int(floorf(cv))
			var fy := cv - float(ri)
			var stag := 0.5 if (ri & 1) == 1 else 0.0
			for x in n:
				var i := y * n + x
				var cu := float(x) / float(n) * cols + stag + 0.25
				var ci := int(floorf(cu))
				var fx := cu - float(ci)
				var edge := minf(minf(fx / mx, (1.0 - fx) / mx), minf(fy / my, (1.0 - fy) / my))
				var body := smoothstep(0.0, 1.0, clampf(edge, 0.0, 1.0))
				var tv: Array = vr[(ri % rows) * cols + (((ci % cols) + cols) % cols)]
				var mot := cl[i] - 0.5
				var pitm := smoothstep(0.88, 0.97, pit[i])
				var t := 0.78 + 0.4 * float(tv[0]) + mot * 0.3 + (grit[i] - 0.5) * 0.15 - pitm * 0.25
				var br := cr * t
				var bg := cg * t * (0.9 + 0.2 * float(tv[1]))
				var bb := cb * t * (0.92 + 0.16 * float(tv[1]))
				var mt := 0.85 + (grit[i] - 0.5) * 0.3 + mot * 0.2
				var r := lerpf(mortar.r * mt, br, body)
				var g := lerpf(mortar.g * mt, bg, body)
				var b := lerpf(mortar.b * mt, bb, body)
				var rough := rb + (grit[i] - 0.5) * 0.08 + (1.0 - body) * 0.04
				if wm.size() > 0:
					var w := wm[i] * 0.7
					r = lerpf(r, 0.6, w * 0.4)
					g = lerpf(g, 0.57, w * 0.4)
					b = lerpf(b, 0.52, w * 0.4)
				put(i, r, g, b, rough, body * 0.8 + (grit[i] - 0.5) * 0.15 - pitm * 0.3)
		bump = 1.5

	# ------------------------------------------------ stone

	func _granite() -> void:
		var cl := fbm(16, 16, 3, 91)
		var f1 := fld(256, 256, 92)
		var f2 := fld(256, 256, 93)
		var f3 := fld(128, 128, 94)
		var rb := lerpf(0.8, 0.1, gloss)
		for i in n * n:
			var base := 1.0 + (cl[i] - 0.5) * 0.3
			var black := smoothstep(0.72, 0.8, f1[i])
			var white := smoothstep(0.76, 0.84, f2[i])
			var pinkm := smoothstep(0.55, 0.75, f3[i]) * 0.5
			var r := cr * base
			var g := cg * base
			var b := cb * base
			r = lerpf(r, minf(r * 1.35 + 0.1, 1.0), pinkm * 0.5)
			g = lerpf(g, g * 0.9, pinkm * 0.5)
			r = lerpf(r, 0.1, black * 0.9)
			g = lerpf(g, 0.1, black * 0.9)
			b = lerpf(b, 0.11, black * 0.9)
			r = lerpf(r, 0.9, white * 0.8)
			g = lerpf(g, 0.88, white * 0.8)
			b = lerpf(b, 0.86, white * 0.8)
			var rough := rb + black * 0.1 + (cl[i] - 0.5) * 0.15
			if wm.size() > 0:
				var w := wm[i]
				r = lerpf(r, 0.5, w * 0.4)
				g = lerpf(g, 0.5, w * 0.4)
				b = lerpf(b, 0.5, w * 0.4)
				rough += w * 0.25
			put(i, r, g, b, rough, (f1[i] - 0.5) * 0.1)
		bump = 0.6

	func _marble() -> void:
		var veinc := Color(String(sp.get("vein", "#77797e")))
		var cl := fbm(4, 4, 5, 101)
		var w1 := fbm(4, 4, 4, 102)
		var w2 := fbm(8, 8, 4, 103)
		var wid := fbm(8, 8, 3, 104)
		var gate := fbm(2, 2, 3, 105)
		var rb := lerpf(0.7, 0.05, gloss)
		for y in n:
			var v := float(y) / float(n)
			for x in n:
				var i := y * n + x
				var u := float(x) / float(n)
				var t1 := u * 2.0 + v * 1.0 + (w1[i] - 0.5) * 2.2
				var t2 := u * 3.0 - v * 2.0 + (w2[i] - 0.5) * 1.4
				var s1 := absf(sin(PI * t1))
				var s2 := absf(sin(PI * t2))
				var vw := 0.03 + 0.14 * clampf((wid[i] - 0.3) * 2.0, 0.0, 1.0)
				var vein1 := (1.0 - smoothstep(0.0, vw, s1)) * smoothstep(0.2, 0.45, gate[i])
				var vein2 := (1.0 - smoothstep(0.0, vw * 0.6, s2)) * 0.6 * smoothstep(0.3, 0.55, w1[i])
				var vein := clampf(vein1 + vein2, 0.0, 1.0)
				var cloud := (cl[i] - 0.5) * 0.07
				var r := cr * (1.0 + cloud)
				var g := cg * (1.0 + cloud)
				var b := cb * (1.0 + cloud * 0.8)
				r = lerpf(r, veinc.r, vein * 0.85)
				g = lerpf(g, veinc.g, vein * 0.85)
				b = lerpf(b, veinc.b, vein * 0.85)
				var rough := rb + vein * 0.04 + cloud * 0.5
				if wm.size() > 0:
					r = lerpf(r, 0.78, wm[i] * 0.4)
					g = lerpf(g, 0.76, wm[i] * 0.4)
					b = lerpf(b, 0.72, wm[i] * 0.4)
					rough += wm[i] * 0.3
				put(i, r, g, b, rough, -vein * 0.05 + cloud * 0.2)
		bump = 0.4

	func _concrete() -> void:
		var plaster := String(sp["kind"]) == "plaster"
		var cl := fbm(4, 4, 6, 111)
		var stain := fbm(2, 2, 3, 112)
		var grain := fld(256, 256, 113)
		var pit := fld(128, 128, 114)
		var swirl := fld(8, 2, 115)
		var rb := lerpf(0.95, 0.3, gloss)
		for i in n * n:
			var mot := cl[i] - 0.5
			var pitm := smoothstep(0.88, 0.97, pit[i])
			var tone: float
			var h: float
			if plaster:
				tone = 1.0 + mot * 0.12 + (swirl[i] - 0.5) * 0.06 + (grain[i] - 0.5) * 0.03
				h = mot * 0.4 + (swirl[i] - 0.5) * 0.3 + (grain[i] - 0.5) * 0.1
			else:
				tone = 1.0 + mot * 0.55 + (stain[i] - 0.5) * 0.3 + (grain[i] - 0.5) * 0.12 - pitm * 0.45
				h = mot * 0.8 + (grain[i] - 0.5) * 0.3 - pitm * 0.9
			var r := cr * tone
			var g := cg * tone
			var b := cb * tone * (1.0 - 0.02 * mot)
			var rough := rb + (grain[i] - 0.5) * 0.06
			if wm.size() > 0:
				var w := wm[i]
				r *= 1.0 - w * 0.25
				g *= 1.0 - w * 0.22
				b *= 1.0 - w * 0.28
				rough += w * 0.04
			put(i, r, g, b, rough, h)
		bump = 1.2 if plaster else 2.5

	func _gravel() -> void:
		var g1 := fbm(16, 16, 3, 121)
		var tn := fld(16, 16, 122)
		var fine := fld(256, 256, 123)
		var palette := [Color(0.62, 0.6, 0.57), Color(0.74, 0.69, 0.6), Color(0.5, 0.45, 0.4), Color(0.8, 0.78, 0.74), Color(0.36, 0.34, 0.33), Color(0.66, 0.55, 0.42)]
		var rb := lerpf(0.9, 0.35, gloss)
		for i in n * n:
			var d := absf(g1[i] - 0.5) * 2.0
			var pebble := smoothstep(0.03, 0.2, d)
			var pc: Color = palette[int(clampf(tn[i], 0.0, 0.999) * palette.size())]
			var tint := Color(cr / 0.6, cg / 0.6, cb / 0.6)
			var t := (0.8 + 0.4 * pebble) * (1.0 + (fine[i] - 0.5) * 0.25)
			var r := pc.r * minf(tint.r, 1.4) * t
			var g := pc.g * minf(tint.g, 1.4) * t
			var b := pc.b * minf(tint.b, 1.4) * t
			var rough := rb + (fine[i] - 0.5) * 0.1 + (1.0 - pebble) * 0.05
			if wm.size() > 0:
				r = lerpf(r, 0.42, wm[i] * 0.35)
				g = lerpf(g, 0.38, wm[i] * 0.35)
				b = lerpf(b, 0.3, wm[i] * 0.35)
			put(i, r, g, b, rough, pebble * 1.0 + (fine[i] - 0.5) * 0.15)
		bump = 3.5

	# ------------------------------------------------ soft materials

	func _grass() -> void:
		var b1 := fld(256, 8, 131)
		var b2 := fld(128, 4, 132)
		var b3 := fld(512, 32, 133)
		var patch := fbm(4, 4, 3, 134)
		var rb := lerpf(0.95, 0.5, gloss)
		for i in n * n:
			var bl := b1[i] * 0.45 + b2[i] * 0.35 + b3[i] * 0.2
			var yel := clampf((patch[i] - 0.4) * 2.0, 0.0, 1.0)
			var t := 0.55 + bl * 0.8
			var r := cr * t * (1.0 + yel * 0.4)
			var g := cg * t * (1.0 + yel * 0.1)
			var b := cb * t * (1.0 - yel * 0.2)
			var rough := rb + (bl - 0.5) * 0.2
			if wm.size() > 0:
				r = lerpf(r, 0.5, wm[i] * 0.5)
				g = lerpf(g, 0.4, wm[i] * 0.5)
				b = lerpf(b, 0.2, wm[i] * 0.5)
			put(i, r, g, b, rough, bl * 0.8)
		bump = 3.0

	@warning_ignore("integer_division")
	func _fabric() -> void:
		var cnt := 64
		var fib := fld(256, 256, 141)
		var slub := fld(8, 128, 142)
		var slub2 := fld(128, 8, 143)
		var cl := fbm(4, 4, 3, 144)
		var rb := lerpf(0.97, 0.6, gloss)
		var cell := float(n) / cnt
		for y in n:
			var fv := (float(y) + cell * 0.5) / cell
			var jv := int(fv)
			var tv := fv - float(jv)
			var hv := sin(tv * PI)
			for x in n:
				var i := y * n + x
				var fu := (float(x) + cell * 0.5) / cell
				var ju := int(fu)
				var tu := fu - float(ju)
				var hu := sin(tu * PI)
				var over := ((ju + jv) & 1) == 0
				var thread: float = hu if over else hv
				var other: float = hv if over else hu
				var th := 0.55 + 0.45 * thread - 0.15 * (1.0 - other) * 0.5
				var s := slub[i] if over else slub2[i]
				var t := th * (1.0 + (fib[i] - 0.5) * 0.25 + (s - 0.5) * 0.2) * (1.0 + (cl[i] - 0.5) * 0.12)
				var r := cr * t
				var g := cg * t
				var b := cb * t
				var rough := rb + (fib[i] - 0.5) * 0.08
				if wm.size() > 0:
					var lg := (r + g + b) / 3.0
					r = lerpf(r, lg + 0.1, wm[i] * 0.5)
					g = lerpf(g, lg + 0.1, wm[i] * 0.5)
					b = lerpf(b, lg + 0.1, wm[i] * 0.5)
				put(i, r, g, b, rough, th * 0.8 + (fib[i] - 0.5) * 0.1)
		bump = 3.0

	func _leather() -> void:
		var g1 := fbm(64, 64, 3, 151)
		var g2 := fld(128, 128, 152)
		var wr := fbm(4, 4, 4, 153)
		var rb := lerpf(0.85, 0.3, gloss)
		for i in n * n:
			var d := absf(g1[i] - 0.5) * 2.0
			var pebble := smoothstep(0.02, 0.28, d)
			var crease := 1.0 - pebble
			var t := (0.7 + 0.3 * pebble) * (1.0 + (wr[i] - 0.5) * 0.4) * (1.0 + (g2[i] - 0.5) * 0.1)
			var r := cr * t
			var g := cg * t
			var b := cb * t
			var rough := rb + crease * 0.12 + (wr[i] - 0.5) * 0.12
			if wm.size() > 0:
				var w := wm[i]
				r = lerpf(r, minf(cr * 1.7, 1.0), w * 0.55)
				g = lerpf(g, minf(cg * 1.7, 1.0), w * 0.55)
				b = lerpf(b, minf(cb * 1.6, 1.0), w * 0.55)
				rough += w * 0.2
			put(i, r, g, b, rough, pebble * 0.6 + (wr[i] - 0.5) * 0.4)
		bump = 3.0


# ================================================================ Part appearance

## the fields of an "appear" step for a made material: the look numbers the plain view and the lists use (colour, roughness, metal,
## opacity) and the spec itself ("mat"), which the view turns into triplanar maps
static func appear_fields(spec_in: Dictionary) -> Dictionary:
	var sp := norm(spec_in)
	if sp.is_empty():
		return {}
	var ln := look_numbers(sp)
	var c: Color = ln["c"]
	return {"preset": "Material", "color": [c.r, c.g, c.b], "rough": float(ln["rough"]), "metal": float(ln["metal"]), "alpha": float(ln["alpha"]), "mat": sp}
