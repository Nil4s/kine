## godot --headless --path . -s tests/ghosts_follow_test.gd     (GATES Z3, UPGRADES #9)
## GHOSTS FOLLOW THE SCENE: spacing ghosts on, the playhead mid-scene. What the ghost mesh DRAWS is compared with the
## ghosts the scene now playing makes (posed fresh on a body of its own: every SPACE_DT around the playhead, the fan of
## Overlays.fan): after a card is deleted, after another scene is opened, after cards are deleted down to one, after
## New empty scene: each time the drawing is the scene now playing, or nothing when there is nothing to space.
extends SceneTree

var fails := 0
var m: Node
var GB: Body


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the vertices the ghost mesh draws now (none when it is hidden)
func drawn() -> PackedVector3Array:
	var mi: MeshInstance3D = m.ov._space_mesh
	if not mi.visible or (mi.mesh as ImmediateMesh).get_surface_count() == 0:
		return PackedVector3Array()
	var v: PackedVector3Array = (mi.mesh as ImmediateMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var out := PackedVector3Array()
	for p in v:   # the invisible placeholder (two points at the origin) is not a ghost
		if p != Vector3.ZERO:
			out.append(p)
	return out


## the ghosts of the scene now playing at the playhead, posed fresh
func want() -> PackedVector3Array:
	var S: Scene = m._ps()
	var out := PackedVector3Array()
	if S.cards.size() < 2:
		return out
	var fps := float(S.fps)
	var every := maxi(1, int(round(Overlays.SPACE_DT * fps)))
	var n := int(ceil(S.length() * fps)) + 1
	for i in range(0, n, every):
		var t := minf(i / fps, S.length())
		var dt: float = t - m.playhead
		if absf(dt) < Overlays.SPACE_DT * 0.5 or absf(dt) > Overlays.SPACE_SPAN + 1e-4:
			continue
		S.apply(GB, t)
		out.append_array(PackedVector3Array(Overlays.fan(GB)))
	return out


func same(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size():
		return INF
	var w := 0.0
	for i in a.size():
		w = maxf(w, a[i].distance_to(b[i]))
	return w


func check(what: String) -> void:
	m.playhead = minf(m.playhead, m._ps().length())
	m._refresh()
	await idle(4)
	m._refresh()
	await idle(2)
	var d := drawn()
	var w := want()
	ok(same(d, w) < 1e-4, "%s: the ghosts drawn = the scene now playing's (%d points drawn, %d wanted, %d cards, playhead %.2f s)" % [what, d.size(), w.size(), m.S.cards.size(), m.playhead])


func _init() -> void:
	GB = Body.new()
	GB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.ov.spacing_on = true
	m.ov.mark_dirty()
	m.playhead = 1.0
	await check("1 combo3, spacing on")
	ok(drawn().size() > 20, "1b and there are ghosts to compare (%d points)" % drawn().size())
	m._card_del(2)
	await check("2 card 3 deleted")
	m._load_scene("res://scenes/thrust.json")
	m._rebuild_cards()
	m.playhead = 0.8
	await check("3 another scene opened (thrust)")
	while m.S.cards.size() > 1:
		m._card_del(m.S.cards.size() - 1)
	await check("4 deleted down to one card (nothing to space)")
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.playhead = 1.0
	await check("5a combo3 again")
	m.S = Scene.new()
	m.scene_path = ""
	m.sel_card = -1
	m.playhead = 0.0
	m._rebuild_cards()
	await check("5 New empty scene")
	print("GHOSTS FOLLOW: %d failed" % fails)
	quit(1 if fails > 0 else 0)
