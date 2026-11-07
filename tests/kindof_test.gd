## godot --path . -s tests/kindof_test.gd     (L61: Props.kind_of on synthetic part kinds across undo / redo)
## N unique "part:" props (each a registered part kind), then undo / redo cycles of a move. Bars: every prop's kind resolves
## (Props.has_kind and kind_of with "solids") before, after each undo and after each redo; the set keeps its size; no crash.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func all_resolve() -> bool:
	for p in m.S.props:
		var k := String(p["kind"])
		if not Props.has_kind(k):
			return false
		if not (Props.kind_of(k) as Dictionary).has("solids"):
			return false
	return true


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.easy.set_on(false, false)
	m._load_scene("res://scenes/combo3.json")
	m.undo.clear()
	m.redo.clear()
	for n in [20, 98, 400]:
		var props := []
		for i in n:
			var kind := "part:kindof%d_%d#%d" % [n, i, i]
			var am := ArrayMesh.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.3 + 0.0001 * i, 0.4, 0.3)
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bm.get_mesh_arrays())
			Props.register_part(kind, am)
			props.append(Props.make(kind, Props.xf_at(Vector3((i % 20) * 1.5, 0, (i / 20) * 1.5 + 4.0), float(i * 37 % 360))))
		m.S.props = props
		m._props_show()
		await idle(2)
		ok(all_resolve(), "n=%d: kinds resolve before undo" % n)
		for c in 6:
			m._push_undo()
			m.S.props[0]["xf"] = Props.xf_at(Vector3(0.1 * (c + 1), 0, 4), 0.0)
			m._undo()
			ok(m.S.props.size() == n and all_resolve(), "n=%d cycle %d: undo keeps %d props, every kind resolves" % [n, c, n])
			m._redo()
			ok(m.S.props.size() == n and all_resolve(), "n=%d cycle %d: redo keeps %d props, every kind resolves" % [n, c, n])
		await idle(2)
	print("kindof: %d fail" % fails)
	quit(1 if fails > 0 else 0)
