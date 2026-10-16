## VIEWCUBE (round 7, Fusion 360's cube in the corner). A small cube that turns with the camera: you always see which
## side of the body you are looking at, and clicking a face goes to that view (the same as the keys 1-5).
## It is drawn flat from the camera's own rotation each frame; nothing in the 3D scene.
## Round 22 (GATES CC2, UPGRADES #22): near a face's EDGE a click looks from between the two faces, near a CORNER from
## between the three; the house mark top left goes HOME (the view the poser opens with); cube moves are smooth.
class_name ViewCube
extends Control

const SIZE := 132.0
const HALF := 38.0   # the cube's half-size on screen, px
const EDGE := 0.55   # past this far from a face's middle (1 = its border) a click counts as that edge
const HOME_R := Rect2(2, 2, 24, 22)   # the home mark
## each face: its outward direction in the world = where the camera sits for that view (main._cam: target + basis*Z),
## the label, and the view it opens (main._view); 6 = from below (no key)
const FACES := [
	[Vector3(0, 0, 1), "FRONT", 1],
	[Vector3(-1, 0, 0), "RIGHT", 2],   # HIS right: on the screen's left in the front view, like the "His right (2)" button
	[Vector3(0, 1, 0), "TOP", 3],
	[Vector3(0, 0, -1), "BACK", 4],
	[Vector3(1, 0, 0), "LEFT", 5],
	[Vector3(0, -1, 0), "BOTTOM", 6],
]

var m: Node
var hover := -1
var _b := Basis()   # the camera rotation last drawn


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "click a face to look from that side (keys 1-5), near an edge or a corner for the view between; the house = back home"


func _process(_dt: float) -> void:
	if m != null and not m.cam.global_basis.is_equal_approx(_b):
		_b = m.cam.global_basis
		queue_redraw()


## a world direction -> where it lands on the cube's square, and how much it faces the camera (>0 = toward you)
func _proj(d: Vector3) -> Vector3:
	var v: Vector3 = _b.inverse() * d
	return Vector3(SIZE * 0.5 + v.x * HALF, SIZE * 0.5 - v.y * HALF, v.z)


## the four screen corners of face i (its two in-plane axes from its normal)
func _quad(i: int) -> PackedVector2Array:
	var n: Vector3 = FACES[i][0]
	var a := Vector3.UP if absf(n.y) < 0.5 else Vector3.BACK
	var u := n.cross(a).normalized()
	var w := n.cross(u)
	var q := PackedVector2Array()
	for s in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1)]:
		var p := _proj(n + u * s.x + w * s.y)
		q.append(Vector2(p.x, p.y))
	return q


## the faces turned toward the camera, the nearest last (drawn on top, hit first)
func _visible() -> Array:
	var f := []
	for i in FACES.size():
		var z := _proj(FACES[i][0]).z
		if z > 0.05:
			f.append([z, i])
	f.sort_custom(func(a, b): return a[0] < b[0])
	return f.map(func(e): return e[1])


## where a click at p looks from: the face's normal, plus each neighbour whose border the click is near; ZERO = no face.
## The cube is drawn by a LINEAR map, so a point on face i is C + U s + W t with s, t in [-1, 1] (the corner order of
## _quad: (1,1) (1,-1) (-1,-1) (-1,1)), solved exactly from the corners
func dir_at(p: Vector2) -> Vector3:
	var i := face_at(p)
	if i < 0:
		return Vector3.ZERO
	var st := face_st(i, p)
	var n: Vector3 = FACES[i][0]
	var a := Vector3.UP if absf(n.y) < 0.5 else Vector3.BACK
	var u := n.cross(a).normalized()
	var w := n.cross(u)
	var d := n
	if absf(st.x) > EDGE:
		d += u * signf(st.x)
	if absf(st.y) > EDGE:
		d += w * signf(st.y)
	return d.normalized()


func face_st(i: int, p: Vector2) -> Vector2:
	var q := _quad(i)
	var c := (q[0] + q[2]) * 0.5
	var U := (q[0] - q[3]) * 0.5
	var W := (q[0] - q[1]) * 0.5
	var det := U.x * W.y - U.y * W.x
	if absf(det) < 1e-6:
		return Vector2.ZERO
	var r := p - c
	return Vector2((r.x * W.y - r.y * W.x) / det, (U.x * r.y - U.y * r.x) / det)


func face_at(p: Vector2) -> int:
	var vis := _visible()
	vis.reverse()
	for i in vis:
		if Geometry2D.is_point_in_polygon(p, _quad(i)):
			return i
	return -1


func _draw() -> void:
	draw_circle(Vector2(SIZE, SIZE) * 0.5, SIZE * 0.47, Color(Tok.c("panel"), 0.55))
	# the home mark: a small house
	var hc := Tok.c("accent") if hover == -2 else Color(Tok.c("ink"), 0.75)
	var o := HOME_R.position + Vector2(5, 4)
	draw_colored_polygon(PackedVector2Array([o + Vector2(7, 0), o + Vector2(14, 6), o + Vector2(0, 6)]), hc)
	draw_rect(Rect2(o + Vector2(2, 6), Vector2(10, 8)), hc)
	var font := get_theme_default_font()
	for i in _visible():
		var z := _proj(FACES[i][0]).z
		var q := _quad(i)
		var c := Tok.c("cube").darkened(0.4).lerp(Tok.c("cube"), z)
		if i == hover:
			c = Tok.c("accent")
		draw_colored_polygon(q, c)
		var ring := q.duplicate()
		ring.append(q[0])
		draw_polyline(ring, Color(Tok.c("cube_edge"), 0.7), 1.2, true)
		if z > 0.35:   # a label only on a face you can read
			var t: String = FACES[i][1]
			var cen := (q[0] + q[1] + q[2] + q[3]) * 0.25
			# as big as fits across the face's middle (a face seen edge-on is narrow): 13 px down to 8
			var across := ((q[0] + q[1]) * 0.5).distance_to((q[2] + q[3]) * 0.5)
			across = minf(across, ((q[1] + q[2]) * 0.5).distance_to((q[3] + q[0]) * 0.5)) if absf(FACES[i][0].y) > 0.5 else absf(((q[0] + q[1]) * 0.5).x - ((q[2] + q[3]) * 0.5).x)
			var fs := 13
			while fs > 8 and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > across - 6.0:
				fs -= 1
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, cen + Vector2(-tw * 0.5, fs * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Tok.c("ink"), clampf(z * 1.6, 0.0, 1.0)))


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var h := -2 if HOME_R.has_point((ev as InputEventMouseMotion).position) else face_at((ev as InputEventMouseMotion).position)
		if h != hover:
			hover = h
			queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var p := (ev as InputEventMouseButton).position
		if HOME_R.has_point(p):
			m._view_home()
			accept_event()
			return
		var d := dir_at(p)
		if d != Vector3.ZERO:
			var i := face_at(p)
			if d.is_equal_approx(FACES[i][0]):
				m._view(FACES[i][2], true)   # a face's middle: that face's view, as its key gives it (a little from above)
			else:
				m._view_dir(d)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hover != -1:
		hover = -1
		queue_redraw()
