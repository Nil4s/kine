class_name Nature
extends RefCounted
## nature.gd - FRIDAY 225 NATURE + SCATTER. Trees, hedges, shrubs, grass, flowers, rocks, paths and a SCATTER of any of them, all made from
## NUMBERS and a SEED (the same record gives the same mesh, bit for bit; another seed gives another tree). Pure data here: every maker returns
## plain arrays (verts, norms, cols, idx, and leaf transforms + colours); scripts/build/nature_view.gd turns them into nodes (an ArrayMesh for the
## wood, a MultiMesh of alpha-tested leaf cards for the leaves, a MultiMesh of blades for grass).
## THE RECORD: building["nature"] = [item, ...], an item is a plain dictionary with "id", "kind" and the kind's numbers (metres, Y up, x/z on the floor):
##   tree     {species: ginkgo|oak|pine|palm|birch|bare, x, z, height, crown (width, 0 = the species' own), trunk (diameter, 0 = own),
##             season: spring|summer|autumn|red|winter, density 1..10 (more branches, more leaves), seed}
##   hedge    {path: [[x,z],...], shape: box|round, height, width, seed}
##   shrub    {x, z, shape: round|cone, size (width), height (0 = own), season, seed}
##   grass    {x, z, w, d (the patch's corner and size), blade (m), density (blades per m2), tone: lawn|meadow|dry, seed}
##   flowers  {x, z, w, d, n, color (a name), seed}
##   path     {path: [[x,z],...], width}
##   scatter  {of: shrub|rock|flowers|tree:<species>|box, n, spacing, jitter 0..1, size, seed, area: {shape: rect, x, z, w, d} | {shape: line, path, width}, mask: [rect|poly|circle ...]}
## A scatter never lands on a path or inside a room (the building's rooms and every path item are its mask), keeps its min spacing between
## the middles of two copies, and says "placed k of n" when the area cannot hold n.

const SPECIES := {
	"ginkgo": {"crown": 0.46, "trunk": 0.040, "bare": 0.20, "top": 0.97, "el": 48.0, "curve": 8.0, "a": 0.18, "p": 0.75, "leaf": 0.15, "shape": 0, "leaves": 3400, "bark": Color(0.36, 0.30, 0.24)},
	"oak": {"crown": 0.95, "trunk": 0.055, "bare": 0.26, "top": 0.88, "el": 26.0, "curve": 14.0, "a": 0.38, "p": 0.55, "leaf": 0.17, "shape": 1, "leaves": 4200, "bark": Color(0.27, 0.21, 0.15)},
	"pine": {"crown": 0.46, "trunk": 0.030, "bare": 0.10, "top": 1.0, "el": -6.0, "curve": 7.0, "a": 0.0, "p": 1.0, "leaf": 0.26, "shape": 2, "leaves": 6500, "bark": Color(0.30, 0.20, 0.14)},
	"palm": {"crown": 0.62, "trunk": 0.030, "bare": 1.0, "top": 1.0, "el": 0.0, "curve": 0.0, "a": 0.0, "p": 1.0, "leaf": 0.4, "shape": 3, "leaves": 0, "bark": Color(0.50, 0.40, 0.30)},
	"birch": {"crown": 0.40, "trunk": 0.026, "bare": 0.24, "top": 0.97, "el": 42.0, "curve": 10.0, "a": 0.22, "p": 0.70, "leaf": 0.085, "shape": 4, "leaves": 4200, "bark": Color(0.86, 0.85, 0.80)},
	"bare": {"crown": 0.85, "trunk": 0.050, "bare": 0.25, "top": 0.90, "el": 34.0, "curve": 12.0, "a": 0.32, "p": 0.60, "leaf": 0.0, "shape": 1, "leaves": 0, "bark": Color(0.24, 0.20, 0.17)},
}
const SEASONS := ["spring", "summer", "autumn", "red", "winter"]
const SHAPE_FAN := 0
const SHAPE_LOBED := 1
const SHAPE_NEEDLE := 2
const SHAPE_FROND := 3
const SHAPE_OVATE := 4
const SHAPE_ROUND := 5
const FLOWER_COLORS := {"white": Color(0.97, 0.97, 0.94), "yellow": Color(1.0, 0.82, 0.12), "red": Color(0.86, 0.1, 0.1), "pink": Color(0.98, 0.5, 0.7),
	"blue": Color(0.25, 0.4, 0.95), "purple": Color(0.6, 0.25, 0.8), "orange": Color(1.0, 0.5, 0.1)}
const KINDS := ["tree", "hedge", "shrub", "grass", "flowers", "path", "scatter"]
const MAX_BLADES := 140000
const MAX_COUNT := 4000


# ---------------------------------------------------------------- the record

static func _num(d: Dictionary, k: String, dv: float, lo: float, hi: float) -> float:
	var v = d.get(k, dv)
	if not (v is float or v is int) or not is_finite(float(v)):
		return dv
	return clampf(float(v), lo, hi)


static func _path(v: Variant) -> Array:
	var out := []
	if v is Array:
		for p in v:
			if p is Array and p.size() >= 2 and (p[0] is float or p[0] is int) and (p[1] is float or p[1] is int) and is_finite(float(p[0])) and is_finite(float(p[1])):
				out.append([float(p[0]), float(p[1])])
	return out


static func path_length(path: Array) -> float:
	var s := 0.0
	for i in range(1, path.size()):
		s += Vector2(path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1]).length()
	return s


## an item as the record keeps it, every number in its range; {} when it is not an item
static func clean(d: Variant) -> Dictionary:
	if not (d is Dictionary):
		return {}
	var k := String(d.get("kind", ""))
	if not KINDS.has(k):
		return {}
	var o := {"id": String(d.get("id", "")), "kind": k, "seed": int(_num(d, "seed", 1.0, 0.0, 1.0e9))}
	match k:
		"tree":
			var sp := String(d.get("species", "oak"))
			o["species"] = sp if SPECIES.has(sp) else "oak"
			o["x"] = _num(d, "x", 0.0, -2000.0, 2000.0)
			o["z"] = _num(d, "z", 0.0, -2000.0, 2000.0)
			o["height"] = _num(d, "height", 6.0, 0.5, 40.0)
			o["crown"] = _num(d, "crown", 0.0, 0.0, 40.0)
			o["trunk"] = _num(d, "trunk", 0.0, 0.0, 3.0)
			var se := String(d.get("season", "summer"))
			o["season"] = se if SEASONS.has(se) else "summer"
			o["density"] = int(_num(d, "density", 5.0, 1.0, 10.0))
		"hedge":
			o["path"] = _path(d.get("path"))
			if o["path"].size() < 2:
				return {}
			o["shape"] = "round" if String(d.get("shape", "box")) == "round" else "box"
			o["height"] = _num(d, "height", 1.0, 0.2, 6.0)
			o["width"] = _num(d, "width", 0.6, 0.2, 3.0)
		"shrub":
			o["x"] = _num(d, "x", 0.0, -2000.0, 2000.0)
			o["z"] = _num(d, "z", 0.0, -2000.0, 2000.0)
			o["shape"] = "cone" if String(d.get("shape", "round")) == "cone" else "round"
			o["size"] = _num(d, "size", 1.0, 0.2, 8.0)
			o["height"] = _num(d, "height", 0.0, 0.0, 10.0)
			var se2 := String(d.get("season", "summer"))
			o["season"] = se2 if SEASONS.has(se2) else "summer"
		"grass":
			o["x"] = _num(d, "x", 0.0, -2000.0, 2000.0)
			o["z"] = _num(d, "z", 0.0, -2000.0, 2000.0)
			o["w"] = _num(d, "w", 4.0, 0.5, 200.0)
			o["d"] = _num(d, "d", 4.0, 0.5, 200.0)
			o["blade"] = _num(d, "blade", 0.22, 0.03, 1.2)
			o["density"] = _num(d, "density", 40.0, 2.0, 400.0)
			var tn := String(d.get("tone", "lawn"))
			o["tone"] = tn if ["lawn", "meadow", "dry"].has(tn) else "lawn"
		"flowers":
			o["x"] = _num(d, "x", 0.0, -2000.0, 2000.0)
			o["z"] = _num(d, "z", 0.0, -2000.0, 2000.0)
			o["w"] = _num(d, "w", 2.0, 0.2, 200.0)
			o["d"] = _num(d, "d", 2.0, 0.2, 200.0)
			o["n"] = int(_num(d, "n", 30.0, 1.0, 2000.0))
			var cn := String(d.get("color", "yellow"))
			o["color"] = cn if FLOWER_COLORS.has(cn) else "yellow"
		"path":
			o["path"] = _path(d.get("path"))
			if o["path"].size() < 2:
				return {}
			o["width"] = _num(d, "width", 1.2, 0.3, 12.0)
		"scatter":
			var of := String(d.get("of", "shrub"))
			var okof: bool = ["shrub", "rock", "flowers", "box", "part"].has(of) or (of.begins_with("tree:") and SPECIES.has(of.substr(5)))
			o["of"] = of if okof else "shrub"
			o["n"] = int(_num(d, "n", 10.0, 1.0, MAX_COUNT))
			o["spacing"] = _num(d, "spacing", 1.0, 0.0, 100.0)
			o["jitter"] = _num(d, "jitter", 0.5, 0.0, 1.0)
			o["size"] = _num(d, "size", 1.0, 0.05, 40.0)
			var ar: Variant = d.get("area", {})
			if not (ar is Dictionary):
				return {}
			if String(ar.get("shape", "rect")) == "line":
				var lp := _path(ar.get("path"))
				if lp.size() < 2:
					return {}
				o["area"] = {"shape": "line", "path": lp, "width": _num(ar, "width", 2.0, 0.1, 100.0)}
			else:
				o["area"] = {"shape": "rect", "x": _num(ar, "x", 0.0, -2000.0, 2000.0), "z": _num(ar, "z", 0.0, -2000.0, 2000.0),
					"w": _num(ar, "w", 10.0, 0.2, 400.0), "d": _num(ar, "d", 10.0, 0.2, 400.0)}
			var mk := []
			for e in d.get("mask", []):
				if e is Dictionary and ["rect", "poly", "circle"].has(String(e.get("t", ""))):
					mk.append(e.duplicate(true))
			o["mask"] = mk
	return o


## the item with every float snapped (the file stays short and stable)
static func snap_item(it: Dictionary) -> Dictionary:
	return _snap(it)


static func _snap(v: Variant) -> Variant:
	if v is float:
		return snappedf(v, 0.0001)
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = _snap(v[k])
		return o
	if v is Array:
		return v.map(func(e): return _snap(e))
	return v


static func new_id(items: Array) -> String:
	var n := items.size() + 1
	while true:
		var id := "n%d" % n
		var used := false
		for it in items:
			if String(it.get("id", "")) == id:
				used = true
		if not used:
			return id
		n += 1
	return ""


## add an item to a building record (the record is made if the caller has none); returns its id, "" when the item is not one
static func add(b: Dictionary, item: Dictionary) -> String:
	var it := clean(item)
	if it.is_empty():
		return ""
	if not b.has("nature"):
		b["nature"] = []
	it["id"] = new_id(b["nature"])
	b["nature"].append(it)
	return it["id"]


static func item_of(b: Dictionary, id: String) -> Dictionary:
	for it in b.get("nature", []):
		if String(it["id"]) == id:
			return it
	return {}


static func remove(b: Dictionary, id: String) -> bool:
	var it := item_of(b, id)
	if it.is_empty():
		return false
	b["nature"].erase(it)
	if b["nature"].is_empty():
		b.erase("nature")
	return true


## the file's nature list, cleaned (ids made unique)
static func from_file(list: Variant) -> Array:
	var out := []
	if list is Array:
		for d in list:
			var it := clean(d)
			if it.is_empty():
				continue
			if it["id"] == "" or not item_of({"nature": out}, String(it["id"])).is_empty():
				it["id"] = new_id(out)
			out.append(it)
	return out


## the nature list mirrored across x = 0
static func mirror_list(list: Array) -> Array:
	var out := []
	for it in list:
		var e: Dictionary = (it as Dictionary).duplicate(true)
		if e.has("x"):
			e["x"] = -float(e["x"])
			if e.has("w"):
				e["x"] = float(e["x"]) - float(e["w"])
		if e.has("path"):
			e["path"] = (e["path"] as Array).map(func(p): return [-float(p[0]), float(p[1])])
		if e.has("area"):
			var ar: Dictionary = e["area"]
			if ar.has("path"):
				ar["path"] = (ar["path"] as Array).map(func(p): return [-float(p[0]), float(p[1])])
			elif ar.has("x"):
				ar["x"] = -float(ar["x"]) - float(ar["w"])
		out.append(e)
	return out


# ---------------------------------------------------------------- noise and small helpers

static func _h(ix: int, iz: int, s: int) -> float:
	var n := ix * 374761393 + iz * 668265263 + s * 1274126177
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xffff) / 65535.0


static func vnoise(x: float, z: float, s: int) -> float:
	var ix := int(floorf(x))
	var iz := int(floorf(z))
	var fx := x - floorf(x)
	var fz := z - floorf(z)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var a := lerpf(_h(ix, iz, s), _h(ix + 1, iz, s), fx)
	var b := lerpf(_h(ix, iz + 1, s), _h(ix + 1, iz + 1, s), fx)
	return lerpf(a, b, fz)


static func _rng(seed_v: int, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v * 7919 + salt * 104729 + 17
	return r


static func _perp(t: Vector3) -> Vector3:
	var ref := Vector3.FORWARD if absf(t.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	return ref.cross(t).normalized()


static func _empty_mesh() -> Dictionary:
	return {"verts": PackedVector3Array(), "norms": PackedVector3Array(), "cols": PackedColorArray(), "idx": PackedInt32Array()}


## a leaf card's basis: y along dir (the card's length), z the card's normal; scaled w across and l along
static func _leaf_xf(pos: Vector3, dir: Vector3, roll: float, w: float, l: float) -> Transform3D:
	var y := dir.normalized()
	var x := _perp(y)
	x = x.rotated(y, roll)
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x * w, y * l, z), pos)


# ---------------------------------------------------------------- tubes

## a tapered tube along points (rings share vertices: a bend leaves no gap), appended to a mesh dictionary
static func tube(mesh: Dictionary, pts: Array, rads: Array, sides: int, c0: Color, c1: Color, rng: RandomNumberGenerator = null) -> void:
	var n := pts.size()
	if n < 2:
		return
	var base: int = mesh["verts"].size()
	for i in n:
		var t: Vector3
		if i == 0:
			t = pts[1] - pts[0]
		elif i == n - 1:
			t = pts[n - 1] - pts[n - 2]
		else:
			t = pts[i + 1] - pts[i - 1]
		t = t.normalized()
		var u := _perp(t)
		var v := t.cross(u)
		var f := float(i) / float(n - 1)
		var col := c0.lerp(c1, f)
		if rng != null:
			var j := 1.0 + rng.randf_range(-0.06, 0.06)
			col = Color(col.r * j, col.g * j, col.b * j)
		for s in sides:
			var a := TAU * float(s) / float(sides)
			var rad := u * cos(a) + v * sin(a)
			mesh["verts"].append(pts[i] + rad * float(rads[i]))
			mesh["norms"].append(rad)
			mesh["cols"].append(col)
	for i in n - 1:
		for s in sides:
			var s2 := (s + 1) % sides
			var a0 := base + i * sides + s
			var a1 := base + i * sides + s2
			var b0 := base + (i + 1) * sides + s
			var b1 := base + (i + 1) * sides + s2
			mesh["idx"].append_array(PackedInt32Array([a0, b0, a1, a1, b0, b1]))


# ---------------------------------------------------------------- trees

static func leaf_color(species: String, season: String, shrub: bool, rng: RandomNumberGenerator) -> Color:
	if species == "pine":
		return Color.from_hsv(0.34 + rng.randf_range(-0.02, 0.02), 0.62, 0.24 + rng.randf_range(-0.04, 0.08))
	if species == "palm":
		return Color.from_hsv(0.30 + rng.randf_range(-0.02, 0.02), 0.62, 0.40 + rng.randf_range(-0.06, 0.08))
	match season:
		"spring":
			return Color.from_hsv(0.235 + rng.randf_range(-0.025, 0.025), 0.62, 0.74 + rng.randf_range(-0.08, 0.1))
		"autumn":
			if shrub:
				return Color.from_hsv(0.12 + rng.randf_range(-0.02, 0.02), 0.85, 0.8 + rng.randf_range(-0.1, 0.1))
			return Color.from_hsv(0.128 + rng.randf_range(-0.016, 0.016), 0.88, 0.90 + rng.randf_range(-0.07, 0.08))
		"red":
			return Color.from_hsv(0.012 + rng.randf_range(-0.014, 0.014), 0.86, 0.68 + rng.randf_range(-0.1, 0.1))
	return Color.from_hsv(0.285 + rng.randf_range(-0.03, 0.03), 0.72, 0.50 + rng.randf_range(-0.09, 0.1))


static func _profile(P: Dictionary, t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	if float(P["a"]) <= 0.0:
		return pow(1.0 - t, 1.2) * 0.97 + 0.03
	return lerpf(float(P["a"]), 1.0, sin(PI * pow(t, float(P["p"]))))


static func _pt_on(pts: Array, y: float) -> Vector3:
	for i in range(1, pts.size()):
		if pts[i].y >= y:
			var f: float = (y - pts[i - 1].y) / maxf(pts[i].y - pts[i - 1].y, 1e-6)
			return (pts[i - 1] as Vector3).lerp(pts[i], clampf(f, 0.0, 1.0))
	return pts[pts.size() - 1]


static func _rad_on(pts: Array, rads: Array, y: float) -> float:
	for i in range(1, pts.size()):
		if pts[i].y >= y:
			var f: float = (y - pts[i - 1].y) / maxf(pts[i].y - pts[i - 1].y, 1e-6)
			return lerpf(float(rads[i - 1]), float(rads[i]), clampf(f, 0.0, 1.0))
	return float(rads[rads.size() - 1])


## a branch chain from p0 in direction d0 (a unit vector), length L, k pieces, bending toward `up` by curve degrees per piece
static func _chain(rng: RandomNumberGenerator, p0: Vector3, d0: Vector3, L: float, k: int, curve: float, r0: float, r1: float) -> Dictionary:
	var pts: Array = [p0]
	var rads: Array = [r0]
	var d := d0
	var p := p0
	for i in k:
		var side := _perp(d)
		d = (d + Vector3.UP * sin(deg_to_rad(curve)) + side.rotated(d, rng.randf() * TAU) * rng.randf_range(0.0, 0.16)).normalized()
		p += d * (L / float(k))
		pts.append(p)
		rads.append(lerpf(r0, r1, float(i + 1) / float(k)))
	return {"pts": pts, "rads": rads, "dir": d}


static func tree_default(sp: String) -> Dictionary:
	return clean({"kind": "tree", "species": sp, "height": 6.0, "season": "summer"})


## THE TREE: skeleton (chains of points + radii), leaf cards, normalised so its height and crown width are the asked numbers.
## Returns {"chains", "leaves" ({xf, col}), "branches", "height", "crown", "trunk_d", "leaf_n", "mesh": wood arrays}
static func make_tree(item: Dictionary) -> Dictionary:
	var it := clean(item) if item.get("kind", "") == "tree" else clean(item.merged({"kind": "tree"}))
	var sp := String(it["species"])
	var P: Dictionary = SPECIES[sp]
	var H := float(it["height"])
	var dens := int(it["density"])
	var rng := _rng(int(it["seed"]), sp.hash() & 0xffff)
	var crown_w := float(it["crown"]) if float(it["crown"]) > 0.0 else H * float(P["crown"])
	var trunk_d := float(it["trunk"]) if float(it["trunk"]) > 0.0 else H * float(P["trunk"])
	var base_r := trunk_d * 0.5
	var season := String(it["season"])
	var leafless: bool = sp == "bare" or (season == "winter" and sp != "pine" and sp != "palm")
	var chains: Array = []
	var leaves_xf: Array = []
	var leaves_col := PackedColorArray()
	var tips: Array = []   # [from, to, level]
	var leaf_size := float(P["leaf"]) * 1.15 * clampf(pow(H / 6.0, 0.35), 0.6, 1.8)
	var top_y := H * float(P["top"])
	# --- the trunk (the leader): wanders a little, tapers
	var npt := 8
	var tp: Array = []
	var tr: Array = []
	var wx := 0.0
	var wz := 0.0
	for i in npt:
		var f := float(i) / float(npt - 1)
		wx += rng.randf_range(-0.012, 0.012) * H
		wz += rng.randf_range(-0.012, 0.012) * H
		if sp == "palm":
			wx += 0.01 * H
		tp.append(Vector3(wx * f, f * top_y, wz * f))
		var taper := lerpf(1.0, 0.1 if sp != "palm" else 0.7, pow(f, 0.8))
		tr.append(base_r * taper * (1.0 + (0.10 * pow(1.0 - f * 6.0, 2.0) if f < 0.166 else 0.0)))
	chains.append({"pts": tp, "rads": tr, "level": 0})
	var counted := 1
	if sp == "palm":
		var nf := 7 + dens
		var top: Vector3 = tp[npt - 1]
		for i in nf:
			var az := TAU * float(i) / float(nf) + rng.randf_range(-0.2, 0.2)
			var el := deg_to_rad(rng.randf_range(35.0, 70.0))
			var d := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
			var flen := H * float(P["crown"]) * 0.62 * rng.randf_range(0.9, 1.1)
			var pts: Array = [top]
			var rads: Array = [0.03 * H * 0.2]
			var p := top
			var segs := 5
			var col := leaf_color(sp, season, false, rng)
			for s in segs:
				d = (d + Vector3.DOWN * (0.16 + 0.06 * float(s))).normalized()
				var p2 := p + d * (flen / float(segs))
				leaves_xf.append(_leaf_xf((p + p2) * 0.5 - d * (flen / float(segs)) * 0.5, d, rng.randf_range(-0.12, 0.12), leaf_size * 0.8, flen / float(segs) * 1.15))
				var cj := Color(col.r * rng.randf_range(0.9, 1.1), col.g * rng.randf_range(0.9, 1.1), col.b)
				leaves_col.append(cj)
				p = p2
				pts.append(p)
				rads.append(0.012)
			chains.append({"pts": pts, "rads": rads, "level": 1})
			counted += 1
	else:
		var n_main := int(round(5.0 + dens * 1.4)) if sp != "pine" else int(round(14.0 + dens * 3.0))
		var h0 := H * float(P["bare"])
		var c1 := int(round(1.0 + dens * 0.5))
		var c2 := int(round(dens * 0.35)) + 1
		if sp == "pine":
			c1 = int(round(dens * 0.7)) + 3
			c2 = 0
		var azim := rng.randf() * TAU
		for i in n_main:
			var f := (float(i) + 0.5) / float(n_main)
			var y := lerpf(h0, top_y * 0.96, pow(f, 0.9))
			var base_pt := _pt_on(tp, y)
			var t_rel := (y - h0) / maxf(top_y * 0.96 - h0, 0.01)
			azim += 2.39996 + rng.randf_range(-0.25, 0.25)
			var el := deg_to_rad(float(P["el"]) + (t_rel * 22.0 if sp == "pine" else rng.randf_range(-6.0, 8.0) + t_rel * 12.0))
			var R := crown_w * 0.5 * _profile(P, t_rel)
			var L := maxf(R / maxf(cos(el), 0.3), 0.3)
			var d0 := Vector3(cos(azim) * cos(el), sin(el), sin(azim) * cos(el)).normalized()
			var r0 := _rad_on(tp, tr, y) * 0.42
			var ch := _chain(rng, base_pt, d0, L, 3, float(P["curve"]) * (1.0 if sp != "pine" else 0.5), r0, r0 * 0.12)
			ch["level"] = 1
			chains.append(ch)
			counted += 1
			var kids: Array = [ch]
			var lvl_tips: Array = []
			for lv in [1, 2]:
				var nc := c1 if lv == 1 else c2
				var next_kids: Array = []
				for par in kids:
					var ppts: Array = par["pts"]
					for j in nc:
						var fj := lerpf(0.3, 0.92, (float(j) + 0.5) / float(nc))
						var seg := clampi(int(fj * float(ppts.size() - 1)), 0, ppts.size() - 2)
						var sf := fj * float(ppts.size() - 1) - float(seg)
						var pp: Vector3 = (ppts[seg] as Vector3).lerp(ppts[seg + 1], sf)
						var pd: Vector3 = ((ppts[seg + 1] as Vector3) - ppts[seg]).normalized()
						var rr := lerpf(float(par["rads"][seg]), float(par["rads"][seg + 1]), sf)
						var side := _perp(pd).rotated(pd, rng.randf() * TAU + float(j) * 2.4)
						var cd: Vector3 = (pd * cos(deg_to_rad(rng.randf_range(35.0, 65.0))) + side * sin(deg_to_rad(55.0)) + Vector3.UP * 0.15).normalized()
						if sp == "pine":
							cd = (side * 0.95 + pd * 0.25 + Vector3.UP * 0.05).normalized()
						var clen := (ppts[ppts.size() - 1] as Vector3).distance_to(ppts[0]) * (0.5 if lv == 1 else 0.42) * rng.randf_range(0.8, 1.2)
						if sp == "pine":
							clen *= 0.85
						var cc := _chain(rng, pp, cd, maxf(clen, 0.12), 2, float(P["curve"]) * 0.6, rr * 0.55, rr * 0.12)
						cc["level"] = lv + 1
						chains.append(cc)
						counted += 1
						next_kids.append(cc)
						if lv == 2 or c2 == 0:
							lvl_tips.append(cc)
				kids = next_kids
				if c2 == 0:
					break
			if c2 > 0 and lvl_tips.is_empty():
				lvl_tips.append(ch)
			for tcn in lvl_tips:
				var tpts: Array = tcn["pts"]
				tips.append([tpts[tpts.size() - 2], tpts[tpts.size() - 1], int(tcn["level"])])
		if not leafless:
			var total := int(round(float(P["leaves"]) * (0.4 + 0.12 * dens) * clampf(pow(H / 6.0, 0.6), 0.3, 3.0)))
			total = mini(total, 14000)
			var cr := leaf_size * 1.3
			for i in total:
				var tpl: Array = tips[rng.randi() % tips.size()]
				var a: Vector3 = tpl[0]
				var b: Vector3 = tpl[1]
				var pos := a.lerp(b, rng.randf_range(0.25, 1.0)) + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.9), rng.randf_range(-1, 1)) * cr
				var dir := ((b - a).normalized() * 0.6 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1.0), rng.randf_range(-1, 1))).normalized()
				if sp == "pine":
					dir = ((b - a).normalized() * 0.5 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.8, 0.4), rng.randf_range(-1, 1))).normalized()
				var sz := leaf_size * rng.randf_range(0.8, 1.25)
				leaves_xf.append(_leaf_xf(pos, dir, rng.randf() * TAU, sz, sz))
				leaves_col.append(leaf_color(sp, season, false, rng))
	var tree := {"chains": chains, "leaf_xf": leaves_xf, "leaf_col": leaves_col, "branches": counted, "species": sp, "shape": int(P["shape"]),
		"leaf_size": leaf_size, "bark": P["bark"]}
	_normalise(tree, H, crown_w)
	tree["height"] = H
	tree["crown"] = crown_w
	tree["trunk_d"] = trunk_d
	tree["leaf_n"] = leaves_xf.size()
	tree["mesh"] = _wood(tree, rng)
	return tree


static func _card_corners(xf: Transform3D) -> Array:
	return [xf * Vector3(-0.5, 0, 0), xf * Vector3(0.5, 0, 0), xf * Vector3(-0.5, 1, 0), xf * Vector3(0.5, 1, 0)]


static func _bounds(tree: Dictionary) -> AABB:
	var bb := AABB(Vector3(0, 0, 0), Vector3(0.001, 0.001, 0.001))
	for c in tree["chains"]:
		for i in c["pts"].size():
			var p: Vector3 = c["pts"][i]
			var r: float = c["rads"][i]
			bb = bb.expand(p + Vector3(r, 0, r)).expand(p - Vector3(r, 0, r))
	for xf in tree["leaf_xf"]:
		for q in _card_corners(xf):
			bb = bb.expand(q)
	return bb


static func _normalise(tree: Dictionary, H: float, W: float) -> void:
	for _it in 5:
		var bb := _bounds(tree)
		var sy := H / maxf(bb.end.y, 0.01)
		var wide := maxf(bb.size.x, bb.size.z)
		var sxz := clampf(W / maxf(wide, 0.01), 0.1, 10.0)
		var f := func(p: Vector3) -> Vector3:
			return Vector3(p.x * sxz, p.y * sy, p.z * sxz)
		for c in tree["chains"]:
			c["pts"] = (c["pts"] as Array).map(f)
		for i in tree["leaf_xf"].size():
			var xf: Transform3D = tree["leaf_xf"][i]
			xf.origin = f.call(xf.origin)
			tree["leaf_xf"][i] = xf
		if absf(sy - 1.0) < 0.004 and absf(sxz - 1.0) < 0.004:
			break


static func _wood(tree: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var mesh := _empty_mesh()
	var bark: Color = tree["bark"]
	var birch: bool = tree["species"] == "birch"
	for c in tree["chains"]:
		var lvl := int(c["level"])
		var sides := 8 if lvl == 0 else (5 if lvl == 1 else 4)
		var c0 := bark.darkened(0.0 if lvl == 0 else 0.15)
		var c1 := bark.darkened(0.35) if not birch else Color(0.3, 0.26, 0.22)
		if birch and lvl == 0:
			c1 = bark
		tube(mesh, c["pts"], c["rads"], sides, c0, c1, rng)
	return mesh


# ---------------------------------------------------------------- stations along a path (hedges, paths)

## [{pos: Vector2, tan: Vector2, miter: float, s: float}] every `step` metres and at each corner; the first at s = 0 and the last at s = L
static func stations(path: Array, step: float) -> Array:
	var segs: Array = []
	var total := 0.0
	for i in range(1, path.size()):
		var a := Vector2(path[i - 1][0], path[i - 1][1])
		var b := Vector2(path[i][0], path[i][1])
		var l := a.distance_to(b)
		if l > 1e-6:
			segs.append({"a": a, "b": b, "l": l, "s0": total, "t": (b - a) / l})
			total += l
	var out: Array = []
	for si in segs.size():
		var sg: Dictionary = segs[si]
		var n := maxi(int(ceil(float(sg["l"]) / step)), 1)
		for k in n + 1:
			if k == 0 and si > 0:
				continue
			var pos: Vector2 = (sg["a"] as Vector2).lerp(sg["b"], float(k) / float(n))
			var tn: Vector2 = sg["t"]
			var miter := 1.0
			if k == n and si < segs.size() - 1:
				var t2: Vector2 = segs[si + 1]["t"]
				var avg := tn + t2
				tn = avg.normalized() if avg.length() > 0.2 else tn
				miter = 1.0 / maxf(tn.dot(sg["t"]), 0.35)
			elif k == 0 and si == 0:
				pass
			out.append({"pos": pos, "tan": tn, "miter": miter, "s": float(sg["s0"]) + float(sg["l"]) * float(k) / float(n)})
	return out


# ---------------------------------------------------------------- hedges

static func _hedge_profile(shape: String, w: float, h: float) -> Array:
	var pts: Array = []
	var hw := w * 0.5
	if shape == "round":
		var hs := h * 0.55
		pts.append(Vector2(-hw, 0.0))
		pts.append(Vector2(-hw, hs * 0.5))
		pts.append(Vector2(-hw, hs))
		var n := 8
		for i in range(1, n):
			var a := PI * float(i) / float(n)
			pts.append(Vector2(-cos(a) * hw, hs + sin(a) * (h - hs)))
		pts.append(Vector2(hw, hs))
		pts.append(Vector2(hw, hs * 0.5))
		pts.append(Vector2(hw, 0.0))
	else:
		var rc := minf(0.05, minf(w, h) * 0.12)   # a clipped box: a crisp edge, a flat top, the sides cut straight
		var ns := maxi(int(ceil((h - rc) / 0.12)), 2)
		for i in ns + 1:
			pts.append(Vector2(-hw, (h - rc) * float(i) / float(ns)))
		pts.append(Vector2(-hw + rc * 0.3, h - rc * 0.3))
		var nt := maxi(int(ceil((w - 2.0 * rc) / 0.12)), 2)
		for i in nt + 1:
			pts.append(Vector2(-hw + rc + (w - 2.0 * rc) * float(i) / float(nt), h))
		pts.append(Vector2(hw - rc * 0.3, h - rc * 0.3))
		for i in range(ns, -1, -1):
			pts.append(Vector2(hw, (h - rc) * float(i) / float(ns)))
	return pts


static func _profile_normals(pts: Array) -> Array:
	var out: Array = []
	for i in pts.size():
		var a: Vector2 = pts[maxi(i - 1, 0)]
		var b: Vector2 = pts[mini(i + 1, pts.size() - 1)]
		var t := (b - a).normalized()
		out.append(Vector2(t.y, -t.x))   # the profile runs left -> over the top -> right: this points out
	return out


## leaf cards over a grid of vertices (rows x cols, `wrap` joins the last column to the first): [{xf}] from the surface
static func grid_leaves(mesh: Dictionary, rows: int, cols: int, wrap: bool, count: int, rng: RandomNumberGenerator, size: float, sp: String, season: String, shrub: bool, only_up := false) -> Dictionary:
	var xfs: Array = []
	var cl := PackedColorArray()
	var crow := cols if not wrap else cols
	for i in count:
		var r := rng.randi() % (rows - 1)
		var c := rng.randi() % (cols - 1 if not wrap else cols)
		var fr := rng.randf()
		var fc := rng.randf()
		var c2 := (c + 1) % cols if wrap else c + 1
		var v: PackedVector3Array = mesh["verts"]
		var nm: PackedVector3Array = mesh["norms"]
		var p00 := v[r * crow + c]
		var p01 := v[r * crow + c2]
		var p10 := v[(r + 1) * crow + c]
		var p11 := v[(r + 1) * crow + c2]
		var pos := (p00.lerp(p01, fc)).lerp(p10.lerp(p11, fc), fr)
		var n := ((nm[r * crow + c].lerp(nm[r * crow + c2], fc)).lerp(nm[(r + 1) * crow + c].lerp(nm[(r + 1) * crow + c2], fc), fr)).normalized()
		if only_up and n.y < -0.2:
			continue
		var dir := (n * 0.75 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 1), rng.randf_range(-1, 1)) * 0.55).normalized()
		var sz := size * rng.randf_range(0.8, 1.3)
		xfs.append(_leaf_xf(pos - n * sz * 0.2, dir, rng.randf() * TAU, sz, sz))
		cl.append(leaf_color(sp, season, shrub, rng))
	return {"xf": xfs, "col": cl}


## THE HEDGE: a body that runs the whole path (rings every 0.25 m, bumpy), flush ends, and leaf cards over it. {mesh, leaf_xf, leaf_col, length}
static func make_hedge(item: Dictionary) -> Dictionary:
	var it := clean(item)
	var path: Array = it["path"]
	var prof := _hedge_profile(String(it["shape"]), float(it["width"]), float(it["height"]))
	var pn := _profile_normals(prof)
	var st := stations(path, 0.10)
	var K := prof.size()
	var rng := _rng(int(it["seed"]), 31)
	var mesh := _empty_mesh()
	var dark := Color(0.09, 0.21, 0.07)
	for si in st.size():
		var s: Dictionary = st[si]
		var tn: Vector2 = s["tan"]
		var lat := Vector2(-tn.y, tn.x)
		for k in K:
			var pf: Vector2 = prof[k]
			var disp := 0.0
			if k > 0 and k < K - 1:
				var sv := float(s["s"])
				disp = (vnoise(sv * 5.0, float(k) * 1.3, int(it["seed"])) - 0.5) * 0.09 + (vnoise(sv * 11.0, float(k) * 2.9, int(it["seed"]) + 5) - 0.5) * 0.05
			var q: Vector2 = pn[k]
			var off := lat * (pf.x + q.x * disp) * float(s["miter"])
			var pos2: Vector2 = (s["pos"] as Vector2) + off
			mesh["verts"].append(Vector3(pos2.x, maxf(pf.y + q.y * disp, 0.0), pos2.y))
			var nrm := Vector3(lat.x * q.x, q.y, lat.y * q.x).normalized()
			mesh["norms"].append(nrm)
			var shade := clampf(pf.y / float(it["height"]), 0.0, 1.0)
			var patch := vnoise(float(s["s"]) * 7.0, float(k) * 1.7, int(it["seed"]) + 9)   # mottled: clumps of leaves catch more light
			mesh["cols"].append(dark.lerp(Color(0.2, 0.36, 0.12), shade * 0.5 + patch * 0.5))
	for si in st.size() - 1:
		for k in K - 1:
			var a := si * K + k
			var b := si * K + k + 1
			var c := (si + 1) * K + k
			var d := (si + 1) * K + k + 1
			mesh["idx"].append_array(PackedInt32Array([a, c, b, b, c, d]))
	# the two flat ends
	for end in [0, 1]:
		var si2 := 0 if end == 0 else st.size() - 1
		var s2: Dictionary = st[si2]
		var tn2: Vector2 = s2["tan"]
		var cen := Vector3((s2["pos"] as Vector2).x, float(it["height"]) * 0.45, (s2["pos"] as Vector2).y)
		var nn := Vector3(tn2.x, 0, tn2.y) * (-1.0 if end == 0 else 1.0)
		var cb: int = mesh["verts"].size()
		mesh["verts"].append(cen)
		mesh["norms"].append(nn)
		mesh["cols"].append(dark)
		for k in K:
			mesh["verts"].append(mesh["verts"][si2 * K + k])
			mesh["norms"].append(nn)
			mesh["cols"].append(dark)
		for k in K - 1:
			if end == 0:
				mesh["idx"].append_array(PackedInt32Array([cb, cb + 2 + k, cb + 1 + k]))
			else:
				mesh["idx"].append_array(PackedInt32Array([cb, cb + 1 + k, cb + 2 + k]))
	var perim := 0.0
	for k in range(1, K):
		perim += (prof[k] as Vector2).distance_to(prof[k - 1])
	var length := path_length(path)
	var cnt := mini(int(length * perim * 700.0), 60000)
	var lv := grid_leaves(mesh, st.size(), K, false, cnt, rng, 0.075, "oak", "summer", true, true)
	var hc: Array = lv["col"]
	for i in hc.size():
		hc[i] = (hc[i] as Color).darkened(0.32)   # a trimmed box hedge reads dark and matte
	# the grid leaves above read the first st.size() x K vertices only (the end caps come after them)
	return {"mesh": mesh, "leaf_xf": lv["xf"], "leaf_col": lv["col"], "length": length}


# ---------------------------------------------------------------- shrubs and rocks (a lathe: rings of a profile turned about Y)

static func lathe(prof: Array, segs: int, noise_amp: float, seed_v: int, col_lo: Color, col_hi: Color) -> Dictionary:
	var mesh := _empty_mesh()
	var rows := prof.size()
	for r in rows:
		var pf: Vector2 = prof[r]
		for s in segs:
			var a := TAU * float(s) / float(segs)
			var nz := (vnoise(cos(a) * 1.7 + float(r) * 0.9, sin(a) * 1.7 + float(r) * 1.3, seed_v) - 0.5) * noise_amp
			var rad := maxf(pf.x * (1.0 + nz), 0.0)
			mesh["verts"].append(Vector3(cos(a) * rad, pf.y + nz * 0.3, sin(a) * rad))
			var pn := Vector2(1.0, 0.0)
			if r < rows - 1 and r > 0:
				var t := (prof[r + 1] as Vector2) - (prof[r - 1] as Vector2)
				pn = Vector2(t.y, -t.x).normalized()
			elif r == 0:
				var t0 := (prof[1] as Vector2) - (prof[0] as Vector2)
				pn = Vector2(t0.y, -t0.x).normalized()
			else:
				var t1 := (prof[r] as Vector2) - (prof[r - 1] as Vector2)
				pn = Vector2(t1.y, -t1.x).normalized()
			mesh["norms"].append(Vector3(cos(a) * pn.x, pn.y, sin(a) * pn.x).normalized())
			mesh["cols"].append(col_lo.lerp(col_hi, clampf(pf.y / maxf((prof[rows - 1] as Vector2).y, 0.01), 0.0, 1.0)))
	for r in rows - 1:
		for s in segs:
			var s2 := (s + 1) % segs
			var a0 := r * segs + s
			var a1 := r * segs + s2
			var b0 := (r + 1) * segs + s
			var b1 := (r + 1) * segs + s2
			mesh["idx"].append_array(PackedInt32Array([a0, a1, b0, a1, b1, b0]))
	return mesh


static func make_shrub(item: Dictionary) -> Dictionary:
	var it := clean(item)
	var size := float(it["size"])
	var h := float(it["height"]) if float(it["height"]) > 0.0 else (size * 0.85 if it["shape"] == "round" else size * 1.6)
	var prof: Array = []
	var rows := 9
	var rng := _rng(int(it["seed"]), 53)
	if it["shape"] == "round":
		for i in rows:
			var a := PI * 0.5 * float(i) / float(rows - 1)
			prof.append(Vector2(cos(a) * size * 0.5, sin(a) * h))
	else:
		for i in rows:
			var f := float(i) / float(rows - 1)
			prof.append(Vector2(size * 0.5 * pow(1.0 - f, 0.85), f * h))
	var mesh := lathe(prof, 14, 0.22, int(it["seed"]), Color(0.07, 0.16, 0.05), Color(0.16, 0.32, 0.1))
	var cnt := int(clampf(size * (size + h) * 260.0, 120.0, 5000.0))
	var sp := "pine" if it["shape"] == "cone" else "oak"
	var lv := grid_leaves(mesh, rows, 14, true, cnt, rng, 0.085 * clampf(size, 0.6, 2.0), sp, String(it["season"]), true, true)
	return {"mesh": mesh, "leaf_xf": lv["xf"], "leaf_col": lv["col"], "height": h, "size": size, "shape": 2 if it["shape"] == "cone" else 5}


static func make_rock(size: float, seed_v: int) -> Dictionary:
	var prof: Array = []
	var rows := 7
	for i in rows:
		var a := PI * 0.5 * float(i) / float(rows - 1)
		prof.append(Vector2(cos(a) * size * 0.5, sin(a) * size * 0.38))
	return {"mesh": lathe(prof, 10, 0.55, seed_v, Color(0.30, 0.29, 0.27), Color(0.50, 0.49, 0.46))}


# ---------------------------------------------------------------- the mask

## what a scatter or a lawn must keep off: every room of the building (its rectangle, turned by its yaw) and every path item
static func mask_of(b: Dictionary, margin := 0.3) -> Array:
	var out: Array = []
	for r in b.get("rooms", []):
		out.append({"t": "rect", "x": float(r["x"]), "z": float(r["z"]), "w": float(r["w"]), "d": float(r["d"]), "yaw": float(r.get("yaw", 0.0)), "m": margin})
	for it in b.get("nature", []):
		if String(it.get("kind", "")) == "path":
			out.append({"t": "poly", "path": it["path"], "w": float(it["width"]), "m": 0.0})
	return out


## true when a disc of radius r at (x, z) touches the mask
static func mask_hit(mask: Array, x: float, z: float, r: float) -> bool:
	for e in mask:
		var mg := float(e.get("m", 0.0)) + r
		match String(e.get("t", "")):
			"rect":
				var q := Vector3(x - float(e["x"]), 0, z - float(e["z"])).rotated(Vector3.UP, -deg_to_rad(float(e.get("yaw", 0.0))))
				var dx := maxf(maxf(-q.x, q.x - float(e["w"])), 0.0)
				var dz := maxf(maxf(-q.z, q.z - float(e["d"])), 0.0)
				if dx * dx + dz * dz <= mg * mg:
					return true
			"circle":
				if Vector2(x - float(e["x"]), z - float(e["z"])).length() <= float(e["r"]) + mg:
					return true
			"poly":
				var pts: Array = e["path"]
				var lim := float(e["w"]) * 0.5 + mg
				for i in range(1, pts.size()):
					var a := Vector2(pts[i - 1][0], pts[i - 1][1])
					var bb := Vector2(pts[i][0], pts[i][1])
					var cl := Geometry2D.get_closest_point_to_segment(Vector2(x, z), a, bb)
					if cl.distance_to(Vector2(x, z)) <= lim:
						return true
	return false


# ---------------------------------------------------------------- scatter

## the copies of a scatter: {pts: [{x, z, yaw, scale}], placed, asked, why}. Seeded dart throwing: a point is taken when it is in the area, off the mask and at
## least `spacing` from every copy already placed; jitter sets how far the turn and the size wander. Never more than asked.
static func scatter(item: Dictionary, building: Dictionary = {}) -> Dictionary:
	var it := clean(item)
	var n := int(it["n"])
	var spacing := float(it["spacing"])
	var jit := float(it["jitter"])
	var rng := _rng(int(it["seed"]), 97)
	var mask: Array = mask_of(building) + (it["mask"] as Array)
	var clear := float(it["size"]) * 0.5
	var area: Dictionary = it["area"]
	var pts: Array = []
	var tries := 0
	var cap := n * 600 + 2000
	var segs: Array = []
	var total := 0.0
	if area["shape"] == "line":
		var ap: Array = area["path"]
		for i in range(1, ap.size()):
			var a := Vector2(ap[i - 1][0], ap[i - 1][1])
			var b := Vector2(ap[i][0], ap[i][1])
			segs.append([a, b, total])
			total += a.distance_to(b)
	while pts.size() < n and tries < cap:
		tries += 1
		var x := 0.0
		var z := 0.0
		if area["shape"] == "line":
			var s := rng.randf() * total
			var sg: Array = segs[0]
			for g in segs:
				if s >= float(g[2]):
					sg = g
			var a2: Vector2 = sg[0]
			var b2: Vector2 = sg[1]
			var t := ((b2 - a2).normalized())
			var p := a2 + t * (s - float(sg[2])) + Vector2(-t.y, t.x) * rng.randf_range(-0.5, 0.5) * float(area["width"])
			x = p.x
			z = p.y
		else:
			x = float(area["x"]) + rng.randf() * float(area["w"])
			z = float(area["z"]) + rng.randf() * float(area["d"])
		if mask_hit(mask, x, z, clear):
			continue
		var good := true
		for q in pts:
			if Vector2(x - float(q["x"]), z - float(q["z"])).length() < spacing:
				good = false
				break
		if not good:
			continue
		pts.append({"x": x, "z": z, "yaw": rng.randf_range(-PI, PI) * jit, "scale": 1.0 + rng.randf_range(-0.4, 0.4) * jit})
	var why := ""
	if pts.size() < n:
		why = "placed %d of %d: the area cannot hold more at %.2f m apart off the paths and rooms" % [pts.size(), n, spacing]
	return {"pts": pts, "placed": pts.size(), "asked": n, "why": why}


# ---------------------------------------------------------------- grass, flowers, ribbons

static func lawn_color(x: float, z: float, tone: String, seed_v: int) -> Color:
	var n := vnoise(x * 0.35, z * 0.35, seed_v) * 0.6 + vnoise(x * 1.7, z * 1.7, seed_v + 5) * 0.4
	var stripe := 0.04 * sin(x * 1.6)
	match tone:
		"meadow":
			return Color.from_hsv(lerpf(0.20, 0.27, n), lerpf(0.55, 0.75, n), lerpf(0.45, 0.72, n) + stripe)
		"dry":
			return Color.from_hsv(lerpf(0.10, 0.15, n), lerpf(0.45, 0.65, n), lerpf(0.55, 0.78, n))
	return Color.from_hsv(lerpf(0.235, 0.29, n), lerpf(0.62, 0.82, n), lerpf(0.50, 0.80, n) + stripe)


## the lawn: blade transforms + colours, and the ground cells (a flat mesh), off the mask
static func make_grass(item: Dictionary, building: Dictionary = {}) -> Dictionary:
	var it := clean(item)
	var rng := _rng(int(it["seed"]), 71)
	var mask := mask_of(building, 0.15)
	var x0 := float(it["x"])
	var z0 := float(it["z"])
	var w := float(it["w"])
	var d := float(it["d"])
	var want := mini(int(w * d * float(it["density"])), MAX_BLADES)
	var xf: Array = []
	var col := PackedColorArray()
	var tone := String(it["tone"])
	var bl := float(it["blade"]) * (1.6 if tone == "meadow" else 1.0)
	var guard := 0
	while xf.size() < want and guard < want * 3:
		guard += 1
		var x := x0 + rng.randf() * w
		var z := z0 + rng.randf() * d
		if mask_hit(mask, x, z, 0.0):
			continue
		var h := bl * rng.randf_range(0.6, 1.4)
		var yaw := rng.randf() * TAU
		var tilt := rng.randf_range(-0.25, 0.25)
		var bs := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
		bs = bs.scaled(Vector3(1.0, h, 1.0))
		xf.append(Transform3D(bs, Vector3(x, 0, z)))
		var c := lawn_color(x, z, tone, int(it["seed"]))
		var j := rng.randf_range(0.85, 1.15)
		col.append(Color(c.r * j, c.g * j, c.b * j))
	var ground := _empty_mesh()
	var cell := 0.5
	var nx := int(ceil(w / cell))
	var nz := int(ceil(d / cell))
	while nx * nz > 40000:
		cell *= 1.5
		nx = int(ceil(w / cell))
		nz = int(ceil(d / cell))
	for iz in nz:
		for ix in nx:
			var ax := x0 + float(ix) * cell
			var az := z0 + float(iz) * cell
			var bx := minf(ax + cell, x0 + w)
			var bz := minf(az + cell, z0 + d)
			if mask_hit(mask, (ax + bx) * 0.5, (az + bz) * 0.5, cell * 0.5):
				continue
			var base: int = ground["verts"].size()
			for cc in [Vector2(ax, az), Vector2(bx, az), Vector2(ax, bz), Vector2(bx, bz)]:
				ground["verts"].append(Vector3(cc.x, -0.004, cc.y))
				ground["norms"].append(Vector3.UP)
				ground["cols"].append(lawn_color(cc.x, cc.y, tone, int(it["seed"])).darkened(0.30))
			ground["idx"].append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
	return {"xf": xf, "col": col, "ground": ground, "blades": xf.size()}


static func make_flowers(item: Dictionary, building: Dictionary = {}) -> Dictionary:
	var it := clean(item)
	var rng := _rng(int(it["seed"]), 83)
	var mask := mask_of(building, 0.1)
	var xf: Array = []
	var col := PackedColorArray()
	var base: Color = FLOWER_COLORS[String(it["color"])]
	var guard := 0
	while xf.size() < int(it["n"]) and guard < int(it["n"]) * 40:
		guard += 1
		var x := float(it["x"]) + rng.randf() * float(it["w"])
		var z := float(it["z"]) + rng.randf() * float(it["d"])
		if mask_hit(mask, x, z, 0.0):
			continue
		var sc := rng.randf_range(0.8, 1.3)
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(x, 0, z)))
		col.append(Color.from_hsv(base.h + rng.randf_range(-0.02, 0.02), base.s, clampf(base.v * rng.randf_range(0.85, 1.05), 0.0, 1.0)))
	return {"xf": xf, "col": col}


## a flat ribbon along a path (a path item): {mesh, length}
static func make_ribbon(path: Array, width: float, y: float, c: Color) -> Dictionary:
	var st := stations(path, 0.5)
	var mesh := _empty_mesh()
	for s in st:
		var tn: Vector2 = s["tan"]
		var lat := Vector2(-tn.y, tn.x) * width * 0.5 * float(s["miter"])
		for sgn in [-1.0, 1.0]:
			var p: Vector2 = (s["pos"] as Vector2) + lat * sgn
			mesh["verts"].append(Vector3(p.x, y, p.y))
			mesh["norms"].append(Vector3.UP)
			mesh["cols"].append(c.lightened(0.04 * vnoise(float(s["s"]) * 2.0, sgn, 3)))
	for i in st.size() - 1:
		var a := i * 2
		mesh["idx"].append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
	return {"mesh": mesh, "length": path_length(path)}


# ---------------------------------------------------------------- measures read from a made thing (the tests and the agent)

## the hue (0..1) averaged over leaf colours, weighted equally; the number the season is judged by
static func mean_hue(cols: PackedColorArray) -> float:
	var sx := 0.0
	var sy := 0.0
	for c in cols:
		sx += cos(c.h * TAU)
		sy += sin(c.h * TAU)
	return fposmod(atan2(sy, sx) / TAU, 1.0)
