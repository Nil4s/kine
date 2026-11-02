class_name PickStack
extends RefCounted
## W09 PICK THROUGH OVERLAPPING PIECES: every piece under the pointer, nearest first. A repeated click at the same spot walks down that
## list (front piece, the one behind it, ... and round to the front again); when two or more pieces are there a small list shows their
## plain names ("Piece 1", "Piece 2") and a press on a name picks that piece. Used by easy_part_stick.gd _pick_at.

const SAME_PX := 5.0   # a click this close to the last one is "the same spot"

var last_p := Vector2(-1000, -1000)
var ids: Array = []     # body indices under the last click, nearest first
var idx := -1           # which of them is picked
var hits: Array = []    # [{body, at, n, depth}] same order as ids
var panel: PanelContainer
var title: Label
var col: VBoxContainer
var btns: Array = []


## every body the ray through screen point p meets: its nearest hit, sorted by distance from the eye
static func stack_at(cam: Camera3D, p: Vector2, faces: Array) -> Array:
	var ro: Vector3 = cam.project_ray_origin(p)
	var rd: Vector3 = cam.project_ray_normal(p)
	var out := []
	for bi in faces.size():
		var tris: PackedVector3Array = faces[bi]
		var best := INF
		var rec := {}
		for k in range(0, tris.size() - 2, 3):
			var h: Variant = SkinPick.ray_tri_mm(ro, rd, tris[k], tris[k + 1], tris[k + 2])
			if h != null:
				var dd := ro.distance_to(h as Vector3)
				if dd < best:
					best = dd
					var nrm := (tris[k + 1] - tris[k]).cross(tris[k + 2] - tris[k]).normalized()
					rec = {"body": bi, "at": h, "n": nrm if nrm.dot(rd) < 0.0 else -nrm, "depth": dd}
		if not rec.is_empty():
			out.append(rec)
	out.sort_custom(func(a, b): return float(a["depth"]) < float(b["depth"]))
	return out


static func name_of(bi: int) -> String:
	return "Piece %d" % (bi + 1)


## the hit to pick for a click at p: the front piece, or the next one down when the click repeats the last spot. {} = nothing there
func cycled(ep: Node, p: Vector2, faces: Array) -> Dictionary:
	var st := stack_at(ep.m.cam, p, faces)
	var now := []
	for h in st:
		now.append(int(h["body"]))
	if st.is_empty():
		ids = []
		idx = -1
		hits = []
		last_p = Vector2(-1000, -1000)
		_sync(ep)
		return {}
	if p.distance_to(last_p) <= SAME_PX and now == ids and idx >= 0:
		idx = (idx + 1) % st.size()
	else:
		idx = 0
	last_p = p
	ids = now
	hits = st
	_sync(ep)
	return st[idx]


## a press on a name in the list: that piece is picked (the list stays, so the others are one press away)
func pick_named(ep: Node, nm: String) -> bool:
	for i in ids.size():
		if name_of(int(ids[i])) == nm:
			idx = i
			ep._pick_at(last_p, hits[i])
			return true
	return false


func _sync(ep: Node) -> void:
	if panel == null:
		_build(ep)
	var show := ids.size() >= 2
	panel.visible = show
	if not show:
		return
	for b in btns:
		(b as Node).queue_free()
	btns = []
	for i in ids.size():
		var nm := name_of(int(ids[i]))
		var b := Button.new()
		b.name = "pickstack_" + nm.replace(" ", "_")
		b.text = nm + ("  (picked)" if i == idx else "")
		b.toggle_mode = true
		b.button_pressed = i == idx
		b.custom_minimum_size = Vector2(150, 34)
		b.pressed.connect(func(): pick_named(ep, nm))
		col.add_child(b)
		btns.append(b)
	title.text = "Pieces here (click again to go behind)"
	panel.reset_size()
	var vs: Vector2 = ep.get_viewport().get_visible_rect().size
	panel.position = Vector2(clampf(last_p.x + 18.0, 8.0, maxf(vs.x - panel.size.x - 8.0, 8.0)), clampf(last_p.y + 18.0, 8.0, maxf(vs.y - panel.size.y - 8.0, 8.0)))


func _build(ep: Node) -> void:
	panel = PanelContainer.new()
	panel.name = "easypart_pickstack"
	panel.visible = false
	col = VBoxContainer.new()
	panel.add_child(col)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 13)
	col.add_child(title)
	ep.dots.get_parent().add_child(panel)
