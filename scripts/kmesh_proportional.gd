class_name KMeshProportional
extends RefCounted
## PROPORTIONAL EDITING (ROADMAP_400 B07). In the model preview (kmesh_edit_ui.gd), with the Blender-style layer on
## (bl_keys.gd, B16), the G / R / S of the selected vertices also carries the UNSELECTED vertices within a radius, each
## by the falloff's weight of its distance to the nearest selected vertex:
##   O  proportional on / off        Shift+O  next falloff (smooth, sphere, root, linear, sharp, constant)
##   Alt+O  connected only on / off: the distance is walked along the edges (geodesic, Dijkstra), so a part that is near
##          in space but not joined by edges (another island, the other lip) stays put
##   the mouse wheel during a live G / R / S: the radius x 1.1 / 1.1 (the wheel zooms otherwise); a circle in the
##   viewport shows it round the selection's centre.
## With t = 1 - d / r (0 past the radius): smooth 3t^2 - 2t^3, sphere sqrt(2t - t^2), root sqrt(t), linear t,
## sharp t^2, constant 1. G moves a vertex by w * the offset, R turns it by w * the angle about the same centre and
## axis, S scales it by 1 + w * (s - 1). The whole edit stays ONE KMeshUndo step (bl_keys.gd brackets it).
## The curves are the ones Blender's manual names; no Blender code. Tests: tests/proportional_test.gd.

const FALLOFFS := ["smooth", "sphere", "root", "linear", "sharp", "constant"]
const RADIUS_DEF := 0.3
const RADIUS_MIN := 0.002
const RADIUS_MAX := 50.0
const WHEEL := 1.1

var on := false
var falloff := "smooth"
var connected := false
var radius := RADIUS_DEF
var dist := {}            # vert -> distance to the selection (only the unselected ones inside the radius)
var last_circle := {}     # {"centre": Vector2, "r": float} as last drawn (px), {} when not drawn
var _mesh: KMesh
var _start := PackedVector3Array()
var _sel := {}


## the weight of a vertex at distance d for radius r (0 past the radius)
static func factor(kind: String, d: float, r: float) -> float:
	if r <= 0.0 or d > r:
		return 0.0
	var t := clampf(1.0 - d / r, 0.0, 1.0)
	match kind:
		"smooth":
			return 3.0 * t * t - 2.0 * t * t * t
		"sphere":
			return sqrt(maxf(2.0 * t - t * t, 0.0))
		"root":
			return sqrt(t)
		"linear":
			return t
		"sharp":
			return t * t
		"constant":
			return 1.0
	return t


## O / Shift+O / Alt+O; returns what to say
func key(k: InputEventKey, layer_on: bool) -> String:
	if k.alt_pressed:
		connected = not connected
	elif k.shift_pressed:
		falloff = FALLOFFS[(FALLOFFS.find(falloff) + 1) % FALLOFFS.size()]
		on = true
	else:
		on = not on
	if not on:
		return "Model: proportional editing off (O turns it on)"
	var s := "Model: proportional editing on: %s falloff, radius %s, %s. Shift+O next falloff, Alt+O connected only, the wheel sizes it during G / R / S" % [
		falloff, Units.len(radius), "connected only (along the edges)" if connected else "everything within the radius"]
	if not layer_on:
		s += ". It works on the G / R / S of the model preview"
	return s


## a G / R / S starts: the selection (idx) and the vertices as they were (start)
func begin(mesh: KMesh, idx: PackedInt32Array, start: PackedVector3Array) -> void:
	_mesh = mesh
	_start = start
	_sel = {}
	for i in idx:
		_sel[i] = true
	_measure()


## the distances of the unselected vertices inside the radius: straight, or along the edges (connected only)
func _measure() -> void:
	dist = {}
	if _mesh == null or _sel.is_empty():
		return
	if connected:
		_geodesic()
		return
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for s in _sel:
		lo = lo.min(_start[s])
		hi = hi.max(_start[s])
	var box := AABB(lo, hi - lo).grow(radius)
	for v in _start.size():
		if _sel.has(v) or not box.has_point(_start[v]):
			continue
		var best := INF
		for s in _sel:
			best = minf(best, _start[v].distance_to(_start[s]))
		if best <= radius:
			dist[v] = best


## multi-source Dijkstra over the edges from every selected vertex, cut at the radius (a binary heap of [d, v])
func _geodesic() -> void:
	var best := {}
	var heap: Array = []
	for s in _sel:
		best[s] = 0.0
		_push(heap, [0.0, s])
	while not heap.is_empty():
		var top: Array = _pop(heap)
		var d: float = top[0]
		var v: int = top[1]
		if d > float(best[v]):
			continue
		for n in _mesh.vert_neighbors(v):
			var nd := d + _start[v].distance_to(_start[n])
			if nd <= radius and nd < float(best.get(n, INF)):
				best[n] = nd
				_push(heap, [nd, n])
	for v in best:
		if not _sel.has(v):
			dist[v] = best[v]


static func _push(h: Array, e: Array) -> void:
	h.append(e)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if h[p][0] <= h[i][0]:
			break
		var t = h[p]
		h[p] = h[i]
		h[i] = t
		i = p


static func _pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < h.size() and h[l][0] < h[m][0]:
				m = l
			if r < h.size() and h[r][0] < h[m][0]:
				m = r
			if m == i:
				break
			var t = h[m]
			h[m] = h[i]
			h[i] = t
			i = m
	return top


## the wheel during a live G / R / S: the radius grows (up) or shrinks; the vertices it left go back to the start
func wheel(up: bool) -> void:
	radius = clampf(radius * (WHEEL if up else 1.0 / WHEEL), RADIUS_MIN, RADIUS_MAX)
	if _mesh == null:
		return
	for v in dist:
		_mesh.verts[v] = _start[v]
	_measure()


## move the weighted vertices: op "G" (offset d), "R" (axis ax, angle ang radians, about centre), "S" (factors sc)
func apply(mesh: KMesh, op: String, d: Vector3, ax: Vector3, ang: float, sc: Vector3, centre: Vector3) -> void:
	for v in dist:
		var w := factor(falloff, float(dist[v]), radius)
		var p := _start[v]
		match op:
			"G":
				mesh.verts[v] = p + d * w
			"R":
				mesh.verts[v] = centre + Basis(ax, ang * w) * (p - centre)
			"S":
				mesh.verts[v] = centre + (p - centre) * (Vector3.ONE + (sc - Vector3.ONE) * w)


## is the circle to be drawn: on, and a G / R / S of the model preview is live
func showing(blk) -> bool:
	return on and blk != null and blk.active != "" and blk.where == "mesh"


## the radius as a circle round the selection's current centre (screen space, at that depth)
func draw(ci: CanvasItem, cam: Camera3D, view: Node3D, blk) -> void:
	last_circle = {}
	if not showing(blk) or _mesh == null or _sel.is_empty():
		return
	var c := Vector3.ZERO
	for s in _sel:
		c += _mesh.verts[s]
	c /= float(_sel.size())
	var wc := view.global_transform * c
	if cam.is_position_behind(wc):
		return
	var px := cam.unproject_position(wc)
	var rw := radius * view.global_basis.get_scale().x
	var rpx := px.distance_to(cam.unproject_position(wc + cam.global_basis.x * rw))
	var col := Tok.c("pick_hover")
	ci.draw_arc(px, rpx, 0.0, TAU, maxi(48, int(rpx * 0.5)), col, 2.0, true)
	ci.draw_string(ThemeDB.fallback_font, px + Vector2(rpx * 0.71 + 4.0, -rpx * 0.71 - 4.0), "%s %s" % [falloff, Units.len(radius)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	last_circle = {"centre": px, "r": rpx}
