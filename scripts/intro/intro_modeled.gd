## INTRO A, MODELED (scripts/intro/intro.gd): the K is modelled in front of you as on the MODEL page. A clay cube pops into
## the dark viewport over its floor grid; S stretches it into the stem (a squash first), E pulls a second block out beside
## it, leaving the stencil gap; G snaps that block's verts one by one into the two 45 deg limbs; a small cube is dropped on
## the pivot as the diamond; the material washes in; the camera turns front-on and the depth flattens into the flat mark.
## A tiny 3D: each piece is a prism of its 2D outline, projected by hand (yaw, pitch, perspective), back faces culled,
## pieces sorted back to front. At yaw = pitch = depth = 0 the projection IS the flat mark, so the hand-over is exact.
class_name IntroModeled
extends RefCounted

const A := preload("res://scripts/intro/intro_art.gd")
const CLAY := Color(0.56, 0.59, 0.65)
const WIRE := Color(0.86, 0.9, 0.98)
const F := 230.0   # focal length in mark units: a gentle perspective
const LIGHT := Vector3(-0.42, -0.62, 0.66)

# corner order per piece: matches the final outline's vertex order (see IntroArt) so every vert travels to its own place
const ORDER := {
	"stem": ["tl", "tr", "br", "bl"],
	"upper": ["bl", "br", "tr", "tl"],
	"lower": ["tr", "br", "bl", "tl"],
}
const KEYS := [["S", "scale", 0.42, 0.86], ["E", "extrude", 0.86, 1.12], ["G", "snap verts", 1.1, 1.56], ["M", "material", 1.56, 1.86]]


func mark_at() -> float:
	return 2.12


static func corners(r: Rect2, order: Array) -> Array:
	var m := {"tl": r.position, "tr": Vector2(r.end.x, r.position.y), "br": r.end, "bl": Vector2(r.position.x, r.end.y)}
	var out := []
	for c in order:
		out.append(m[c])
	return out


static func lerp_poly(a: Array, b: Array, x: float) -> Array:
	var out := []
	for i in a.size():
		out.append((a[i] as Vector2).lerp(b[i], x))
	return out


## the 2D outline of piece `name` at time t, and which of its verts are moving (for the gold "selected" dots)
func outline(name: String, t: float) -> Array:
	var cube := Rect2(A.MARK_C.x - 8.0, 36.0, 16.0, 16.0)   # on the floor
	var stem := Rect2(10, 12, 9, 40)
	var s0 := corners(cube, ORDER.get(name, ["tl", "tr", "br", "bl"]))
	var s1 := corners(stem, ORDER.get(name, ["tl", "tr", "br", "bl"]))
	var active := []
	# S: squash, then stretch up into the stem with a little overshoot
	var sx := A.in_out_back(A.k(t, 0.42, 0.86), 1.25)
	var poly := lerp_poly(s0, s1, sx)
	if name == "stem":
		return [poly, active]
	# E: the right half slides out of the stem, leaving the stencil gap
	var bar := Rect2(26, 12, 9, 40)
	var s2: Array
	if name == "upper":
		s2 = corners(Rect2(26, 12, 9, 20), ORDER["upper"])
	else:
		s2 = corners(Rect2(26, 32, 9, 20), ORDER["lower"])
	var s1h := []   # the same half, still inside the stem
	for v in s2:
		s1h.append(Vector2(lerpf(10, 19, ((v as Vector2).x - bar.position.x) / bar.size.x), v.y))
	var ex := A.out_back(A.k(t, 0.86, 1.12), 2.0)
	if t < 0.86:
		return [poly, active]
	poly = lerp_poly(s1h, s2, ex)
	# G: each vert snaps to its place in the chevron, one after another
	var fin: Array = A.UPPER if name == "upper" else A.LOWER
	var start: Array = {"upper": [1.18, 1.10, 1.14, 1.22], "lower": [1.16, 1.26, 1.30, 1.20]}[name]
	for i in poly.size():
		var x := A.k(t, start[i], start[i] + 0.24)
		if x > 0.0 and x < 1.0:
			active.append(i)
		poly[i] = (s2[i] as Vector2).lerp(fin[i], A.out_back(x, 2.2))
	return [poly, active]


func paint(ci: CanvasItem, t: float, L: Dictionary) -> void:
	var u: float = L["u"]
	var o: Vector2 = L["hero"]
	# the camera: a slow turntable drift while modelling, then front-on with a small overshoot
	var cam := A.out_back(A.k(t, 1.5, 2.06), 1.3)
	var yaw := deg_to_rad(lerpf(-34.0 + 12.0 * A.in_out_sine(A.k(t, 0.0, 1.5)), 0.0, cam))
	var pitch := deg_to_rad(lerpf(-20.0 + 4.0 * A.in_out_sine(A.k(t, 0.0, 1.5)), 0.0, cam))
	var zoom := lerpf(1.45, 1.0, A.in_out_cubic(A.k(t, 0.2, 1.9)))   # the camera pulls back as the model grows
	var appear := A.out_back(A.k(t, 0.04, 0.42), 2.4)
	var depth := lerpf(16.0, 10.0, A.in_out_cubic(A.k(t, 0.42, 0.86))) * (1.0 - A.in_out_cubic(A.k(t, 1.62, 2.06)))
	var flat := 1.0 - depth / 10.0 if t > 1.0 else 0.0
	var wire_a := 0.75 * A.out_cubic(A.k(t, 0.1, 0.4)) * (1.0 - A.in_out_cubic(A.k(t, 1.56, 1.86)))
	var grid_a := 0.22 * A.out_cubic(A.k(t, 0.0, 0.5)) * (1.0 - A.in_out_cubic(A.k(t, 1.45, 1.8)))
	var proj := func(p: Vector3) -> Vector3:
		var q := Vector3(p.x - A.MARK_C.x, p.y - A.MARK_C.y, p.z)
		var x1 := q.x * cos(yaw) + q.z * sin(yaw)
		var z1 := -q.x * sin(yaw) + q.z * cos(yaw)
		var y2 := q.y * cos(pitch) - z1 * sin(pitch)
		var z2 := q.y * sin(pitch) + z1 * cos(pitch)
		var kk := F / (F - z2) * zoom
		return Vector3(o.x + (A.MARK_C.x + x1 * kk) * u, o.y + (A.MARK_C.y + y2 * kk) * u, z2)
	_grid(ci, proj, grid_a, u)
	# the pieces: [outline, colour, depth scale, active verts]
	var wash := func(a0: float, c: Color) -> Color:
		return CLAY.lerp(c, A.in_out_cubic(A.k(t, a0, a0 + 0.3)))
	var pieces := []
	var st: Array = outline("stem", t)
	var stem_poly := A.scaled(st[0], Vector2(A.MARK_C.x, 52.0), appear)
	pieces.append([stem_poly, wash.call(1.56, A.BONE), 1.0, st[1], 0])
	if t >= 0.86:
		var up: Array = outline("upper", t)
		var lo: Array = outline("lower", t)
		pieces.append([up[0], wash.call(1.6, A.BONE), 1.0, up[1], 1])
		pieces.append([lo[0], wash.call(1.64, A.BLUE), 1.0, lo[1], 2])
	var dz := A.out_back(A.k(t, 1.34, 1.62), 2.8)
	if dz > 0.0:
		var d := A.scaled(A.DIAMOND, A.APEX, dz)
		pieces.append([d, wash.call(1.62, A.GOLD), 1.25, [], 3])
	# back to front by the piece's middle (ties keep the brand's order: stem, upper, lower, diamond)
	var keyed := []
	for p in pieces:
		var c := Vector2.ZERO
		for v in p[0]:
			c += v
		c /= (p[0] as Array).size()
		var z: float = proj.call(Vector3(c.x, c.y, 0.0)).z + (0.6 if p[4] == 3 else 0.0)
		keyed.append([z if flat < 0.98 else float(p[4]), p])
	keyed.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1][4] < b[1][4]))
	var dots := []
	for kp in keyed:
		var p: Array = kp[1]
		_prism(ci, proj, p[0], depth * p[2], p[1], wire_a, flat, p[3], dots)
	for d in dots:   # the verts on top, as edit mode shows them
		var r := (4.2 if d[1] else 2.4) * maxf(1.0, u / 4.0)
		var col := A.GOLD if d[1] else Color(A.BONE, 0.9)
		ci.draw_rect(Rect2(d[0] - Vector2(r, r) * 0.5, Vector2(r, r)), Color(col, wire_a / 0.75 * (1.0 if d[1] else 0.85)))
	_keys(ci, t, L)


## one piece: a prism of `poly` (mark units), `depth` deep, back faces culled; its edges drawn as it is (occluded edges
## are covered by whatever is drawn later in front)
func _prism(ci: CanvasItem, proj: Callable, poly: Array, depth: float, col: Color, wire_a: float, flat: float, active: Array,
		dots: Array) -> void:
	var n := poly.size()
	if n < 3:
		return
	var s0 := signf(A.area(A.pts(poly)))
	var front := []
	var back := []
	var front3 := []
	var back3 := []
	for v in poly:
		var a: Vector3 = proj.call(Vector3(v.x, v.y, depth * 0.5))
		var b: Vector3 = proj.call(Vector3(v.x, v.y, -depth * 0.5))
		front.append(Vector2(a.x, a.y))
		back.append(Vector2(b.x, b.y))
		front3.append(a)
		back3.append(b)
	var faces := []   # [screen polygon, shade]
	var lt := LIGHT.normalized()
	var face_n := func(q3: Array) -> Vector3:
		var nn: Vector3 = ((q3[1] as Vector3) - q3[0]).cross((q3[2] as Vector3) - q3[0]).normalized()
		return nn
	# sides first (they sit behind the front face when seen from the front)
	if depth > 0.05:
		var rb := back.duplicate()
		rb.reverse()
		var rb3 := back3.duplicate()
		rb3.reverse()
		faces.append([rb, rb3])
		for i in n:
			var j := (i + 1) % n
			faces.append([[front[i], back[i], back[j], front[j]], [front3[i], back3[i], back3[j], front3[j]]])
	faces.append([front, front3])
	for f in faces:
		var sp := A.pts(f[0])
		if signf(A.area(sp)) != s0 or absf(A.area(sp)) < 0.5:
			continue
		var nn: Vector3 = face_n.call(f[1])
		var lam := absf(nn.dot(lt))
		var shade := lerpf(0.42 + 0.58 * lam, 1.0, flat)
		var c := Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
		A.fill(ci, sp, c)
		if wire_a > 0.01:
			A.outline(ci, sp, Color(WIRE, wire_a * 0.8), 1.0)
	if wire_a > 0.01:
		for i in n:
			dots.append([front[i], i in active])


## the viewport's floor grid under the model, fading out toward its edges
func _grid(ci: CanvasItem, proj: Callable, a: float, u: float) -> void:
	if a <= 0.005:
		return
	var y := 52.0
	for i in range(-6, 7):
		var g := float(i) * 10.0
		var p1: Vector3 = proj.call(Vector3(A.MARK_C.x + g, y, -60.0))
		var p2: Vector3 = proj.call(Vector3(A.MARK_C.x + g, y, 60.0))
		var q1: Vector3 = proj.call(Vector3(A.MARK_C.x - 60.0, y, g))
		var q2: Vector3 = proj.call(Vector3(A.MARK_C.x + 60.0, y, g))
		var fade := 1.0 - absf(float(i)) / 7.0
		var col := Color(A.BONE, a * fade * (1.6 if i == 0 else 1.0))
		ci.draw_line(Vector2(p1.x, p1.y), Vector2(p2.x, p2.y), col, 1.0, true)
		ci.draw_line(Vector2(q1.x, q1.y), Vector2(q2.x, q2.y), col, 1.0, true)


## the key being pressed, small, under the model (the app's key overlay)
func _keys(ci: CanvasItem, t: float, L: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	var fs := maxi(10, int(round(L["base"] * 0.0105)))
	var size: Vector2 = L["size"]
	for kk in KEYS:
		var x := A.k(t, kk[2], kk[2] + 0.12) * (1.0 - A.k(t, kk[3] - 0.04, kk[3] + 0.06))
		if x <= 0.0:
			continue
		var a := A.out_cubic(x)
		var label := "%s   %s" % [kk[0], kk[1]]
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(size.x * 0.5 - w * 0.5, size.y * 0.84 + (1.0 - a) * fs * 0.4)
		var cap := font.get_string_size(kk[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pad := fs * 0.45
		var r := Rect2(pos + Vector2(-pad, -font.get_ascent(fs) - pad * 0.6), Vector2(cap.x + pad * 2.0, font.get_height(fs) + pad * 1.2))
		ci.draw_rect(r, Color(A.BONE, 0.5 * a), false, 1.0, true)
		ci.draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(A.BONE, 0.55 * a))
