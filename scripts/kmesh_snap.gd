class_name KMeshSnap
extends Node
## SNAPPING WHILE MOVING VERTICES (ROADMAP_400 B08), for the Blender-style G / R / S of the model preview (bl_keys.gd).
## Hold Ctrl while moving to snap; the command "Model: snapping always on / off" makes it snap without Ctrl (then Ctrl
## lets go, as in Blender). Shift+Tab (model preview) cycles the TARGET:
##   vert    the nearest vertex                    edge   the closest point on the nearest edge
##   mid     the nearest edge's midpoint           face   the closest point on the nearest face (onto its plane)
##   grid1 / grid5 / grid10   the world grid of 1 / 5 / 10 cm
##   body    the closest point on the fighter's skin (the posed mannequin triangles, SkinPick's data)
## G: of the selected vertices, the one that lands CLOSEST to its target is put exactly on it (Blender's "snap with:
## closest"); the others keep their offsets. Past MAX_SRC selected vertices their centre is used instead. The moving
## vertices, and the edges / faces they belong to, are never targets (the mesh does not snap onto itself as it moves).
## With an axis (G X) only that axis's part of the snap is kept. A typed number is never snapped.
## R snaps the angle to ANGLE_STEP degrees, S the factor to SCALE_STEP.
## The marker: a ring and a cross on the target point, in screen space, while a snap holds (drawn_at = its centre).
## Tests: tests/snap_test.gd.

const TARGETS := ["vert", "edge", "mid", "face", "grid1", "grid5", "grid10", "body"]
const NAMES := {"vert": "vertex", "edge": "edge (closest point)", "mid": "edge midpoint", "face": "face (onto the surface)",
	"grid1": "grid 1 cm", "grid5": "grid 5 cm", "grid10": "grid 10 cm", "body": "the fighter's skin"}
const GRID := {"grid1": 0.01, "grid5": 0.05, "grid10": 0.1}
const ANGLE_STEP := 5.0
const SCALE_STEP := 0.1
const MAX_SRC := 64
const MARK_R := 9.0

var ui                    # the model preview (KMeshEditUI)
var m                     # the poser (main.gd)
var target := "vert"
var always := false       # the toggle: snap without Ctrl
var held := false         # Ctrl held now (read from the events, so a test's pushed events count)
var hit := {}             # the last snap: {"point" (world), "kind", "face" (face snaps)}; {} = none
var drawn_at := Vector2(NAN, NAN)   # where the marker was last drawn (screen)
var _ov: Control


func setup(edit_ui) -> void:
	ui = edit_ui
	m = ui.m
	name = "kmesh_snap"
	_ov = Control.new()
	_ov.name = "snap_marker"
	_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ov.draw.connect(_draw)
	m.ui_root.add_child(_ov)


## snapping now: the toggle, flipped while Ctrl is held
func active() -> bool:
	return always != held


func cycle() -> String:
	target = TARGETS[(TARGETS.find(target) + 1) % TARGETS.size()]
	m._say("Model: snap to %s (Shift+Tab next; hold Ctrl while G / R / S moves to snap%s)" % [NAMES[target], ", or it is always on now" if always else ""])
	return target


func toggle() -> bool:
	always = not always
	m._say("Model: snapping %s, target %s (Shift+Tab changes it)" % ["always on: Ctrl held lets go" if always else "only while Ctrl is held", NAMES[target]])
	return always


## the model preview's keys (KMeshEditUI.input calls this first): Shift+Tab cycles the target; true = used
func input(ev: InputEvent) -> bool:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k := ev as InputEventKey
		if k.keycode == KEY_TAB and k.shift_pressed and not k.ctrl_pressed and not k.alt_pressed:
			cycle()
			return true
	return false


## every event of a modal G / R / S on the mesh (bl_keys._modal): keeps `held` up to date. true = a Ctrl press or
## release, used here (the caller re-applies the move so the snap comes or goes at once)
func watch(ev: InputEvent) -> bool:
	if ev is InputEventKey and (ev as InputEventKey).keycode == KEY_CTRL:
		if not ev.echo:
			held = ev.pressed
		return true
	if ev is InputEventWithModifiers and not (ev is InputEventKey):
		held = (ev as InputEventWithModifiers).ctrl_pressed
	return false


## R / S: the angle / factor in steps while snapping
func step(kind: String, v: float) -> float:
	if not active() or kind == "G":
		return v
	hit = {}
	return snappedf(v, ANGLE_STEP if kind == "R" else SCALE_STEP)


## G: the move d (mesh space, as bl_keys applies it) changed so that one selected vertex lands on the target
func grab(idx: PackedInt32Array, start: PackedVector3Array, d: Vector3, axis := -1) -> Vector3:
	hit = {}
	if not active() or idx.is_empty():
		_ov.queue_redraw()
		return d
	var mesh: KMesh = ui.mesh
	var xf: Transform3D = ui.view.global_transform
	var moving := {}
	for i in idx:
		moving[i] = true
	var srcs := PackedVector3Array()
	if idx.size() <= MAX_SRC:
		for i in idx:
			srcs.append(start[i] + d)
	else:
		var c := Vector3.ZERO
		for i in idx:
			c += start[i]
		srcs.append(c / float(idx.size()) + d)
	var best := INF
	var best_q := Vector3.ZERO
	var best_t := {}
	for q in srcs:
		var t := nearest(mesh, xf, q, moving, target)
		if not t.is_empty() and float(t["dist"]) < best:
			best = t["dist"]
			best_q = q
			best_t = t
	if best_t.is_empty():
		_ov.queue_redraw()
		return d
	var corr: Vector3 = (best_t["point"] as Vector3) - best_q
	if axis >= 0:
		var only := Vector3.ZERO
		only[axis] = corr[axis]
		corr = only
	hit = {"point": xf * (best_q + corr), "kind": target, "face": int(best_t.get("face", -1))}
	_ov.queue_redraw()
	return d + corr


## the target nearest to q (mesh space): {"point" (mesh space), "dist", "face"?} or {} if there is none.
## moving: the vertices that move (not targets, nor their edges / faces)
func nearest(mesh: KMesh, xf: Transform3D, q: Vector3, moving: Dictionary, kind: String) -> Dictionary:
	if GRID.has(kind):
		var g: float = GRID[kind]
		var w := xf * q
		var s := Vector3(snappedf(w.x, g), snappedf(w.y, g), snappedf(w.z, g))
		var p := xf.affine_inverse() * s
		return {"point": p, "dist": p.distance_to(q)}
	if kind == "body":
		var b := body_closest(xf * q)
		if b.is_empty():
			return {}
		var p: Vector3 = xf.affine_inverse() * (b["point"] as Vector3)
		return {"point": p, "dist": p.distance_to(q)}
	var best := INF
	var bp := Vector3.ZERO
	var bf := -1
	if kind == "vert":
		for i in mesh.verts.size():
			if moving.has(i):
				continue
			var dd := mesh.verts[i].distance_squared_to(q)
			if dd < best:
				best = dd
				bp = mesh.verts[i]
		return {} if best == INF else {"point": bp, "dist": sqrt(best)}
	for fi in mesh.faces.size():
		var f: PackedInt32Array = mesh.faces[fi]
		var n := f.size()
		if kind == "face":
			var still := true
			for v in f:
				if moving.has(v):
					still = false
					break
			if not still:
				continue
			for k in range(1, n - 1):
				var c := closest_on_tri(q, mesh.verts[f[0]], mesh.verts[f[k]], mesh.verts[f[k + 1]])
				var dd := c.distance_squared_to(q)
				if dd < best:
					best = dd
					bp = c
					bf = fi
			continue
		for k in n:
			var a := f[k]
			var b := f[(k + 1) % n]
			if moving.has(a) or moving.has(b):
				continue
			var c: Vector3 = (mesh.verts[a] + mesh.verts[b]) * 0.5 if kind == "mid" else Geometry3D.get_closest_point_to_segment(q, mesh.verts[a], mesh.verts[b])
			var dd := c.distance_squared_to(q)
			if dd < best:
				best = dd
				bp = c
	if best == INF:
		return {}
	var out := {"point": bp, "dist": sqrt(best)}
	if bf >= 0:
		out["face"] = bf
	return out


## the closest point of the fighter's skin to world point w: {"point", "dist"} or {} (no skin). The posed triangles of
## SkinPick (main.skp), chunk boxes as the broad phase (a chunk farther than the best so far is skipped)
func body_closest(w: Vector3) -> Dictionary:
	var sp: SkinPick = m.get("skp")
	if sp == null:
		return {}
	sp.refresh()
	var best := INF
	var bp := Vector3.ZERO
	for gr in sp.groups:
		if not (gr["mi"] as MeshInstance3D).is_visible_in_tree() or m.hidden_parts.has(gr["part"]):
			continue
		if box_dist2(gr["box"], w) >= best:
			continue
		var pos: PackedVector3Array = sp.surfs[gr["k"]]["pos"]
		for c in gr["chunks"]:
			if box_dist2(c["box"], w) >= best:
				continue
			var tris: PackedInt32Array = c["tris"]
			for t in range(0, tris.size(), 3):
				var p := closest_on_tri(w, pos[tris[t]], pos[tris[t + 1]], pos[tris[t + 2]])
				var dd := p.distance_squared_to(w)
				if dd < best:
					best = dd
					bp = p
	return {} if best == INF else {"point": bp, "dist": sqrt(best)}


static func box_dist2(bx: AABB, p: Vector3) -> float:
	return p.clamp(bx.position, bx.end).distance_squared_to(p)


## the closest point of triangle abc to p (Ericson, Real-Time Collision Detection 5.1.5)
static func closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var dn := 1.0 / (va + vb + vc)
	return a + ab * (vb * dn) + ac * (vc * dn)


func _process(_dt: float) -> void:
	if ui == null:
		return
	var moving: bool = ui.on and m.blk != null and m.blk.active != "" and m.blk.where == "mesh"
	if not moving and not hit.is_empty():
		hit = {}
		_ov.queue_redraw()
	elif not hit.is_empty():
		_ov.queue_redraw()   # the wheel still zooms mid-move: the marker follows the camera


func _draw() -> void:
	drawn_at = Vector2(NAN, NAN)
	if hit.is_empty() or not ui.on:
		return
	var cam: Camera3D = m.cam
	var w: Vector3 = hit["point"]
	if cam.is_position_behind(w):
		return
	var s := cam.unproject_position(w)
	var col := Tok.c("focus")
	_ov.draw_arc(s, MARK_R, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 3.5)
	_ov.draw_arc(s, MARK_R, 0.0, TAU, 24, col, 1.8)
	_ov.draw_line(s - Vector2(MARK_R * 0.6, 0), s + Vector2(MARK_R * 0.6, 0), col, 1.5)
	_ov.draw_line(s - Vector2(0, MARK_R * 0.6), s + Vector2(0, MARK_R * 0.6), col, 1.5)
	drawn_at = s
