## godot --headless --path . -s tests/shapekeys_test.gd     (ROADMAP_400 A13; scripts/kmesh_shapes.gd)
## Shape keys on a unit cube (8 verts). Deltas are powers of two, so the blend is bit-exact in float32. Bars, written
## before measuring:
##   1 RELATIVE: A (+0.5 x on vert 6) at 0.5 and B (+0.25 y on all) at 0.75: every vert == basis + 0.25 x (vert 6) +
##     0.1875 y, exactly (==). C made relative to A (A's shape + 0.5 z on vert 6) alone at 1: only vert 6 moves, by
##     exactly (0, 0, 0.5) (the delta from A, not from the basis); shape_of(C) = basis + A + C. Clamp: value 3 kept as 1;
##     max 2 -> value 2 doubles B. Mute: a muted key adds nothing. Mask: B masked by a vert float attribute (1 on the
##     4 top verts, 0.5 on vert 0, 0 else): top verts +0.25 y, vert 0 +0.125, the rest 0. Remove A: C keeps its shape.
##   2 ABSOLUTE: relative off, A at frame 10, B at 20: t = 5 -> basis + half of A; t = 15 -> halfway A..B; t = 30 -> B;
##     t = -1 -> basis (all exact)
##   3 FILE: to_dict -> JSON text -> from_dict: the shape set equal (==), evaluate equal at two value sets; a file without
##     keys has no "shapes" block; a key with the wrong vertex count fails the load with a message and changes nothing
##   4 UNDO: add a key = one step (kind "shape"); undo -> no key, redo -> key back (==); a value change + apply in one step:
##     undo puts back the value AND the positions bit-exact
##   5 DRIVEN: an expression driver "clamp((lowerarm_r_bend - 30.0) / 60.0, 0.0, 1.0)" on a real Body: the bend 30 / 60 /
##     120 deg gives 0 / 0.5 / 1 (clamped); a linear driver (source, factor, from) gives (src - from) * factor; a key
##     driven by another key's value ("A * 0.5") follows it in list order; a bad expression leaves the value and says why;
##     drivers survive the save / load
##   6 UI (main scene, Model test cube): move 5 verts by +0.25 x, K -> a key at 1.0, the cube does not move; [ five times ->
##     the cube is basis + 0.5 x the edit, exactly; Ctrl+Z (undo) back to 0.6, then to 1.0
extends SceneTree

var fails := 0
const CV := [Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0), Vector3(0,0,1), Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1)]
const CF := [[0,3,2,1], [4,5,6,7], [0,1,5,4], [2,3,7,6], [1,2,6,5], [0,4,7,3]]


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func cube() -> KMesh:
	return KMesh.new().from_arrays(PackedVector3Array(CV), CF)


func dA() -> PackedVector3Array:
	var d := PackedVector3Array()
	d.resize(8)
	d[6] = Vector3(0.5, 0, 0)
	return d


func dB() -> PackedVector3Array:
	var d := PackedVector3Array()
	d.resize(8)
	d.fill(Vector3(0, 0.25, 0))
	return d


func two() -> KMesh:
	var m := cube()
	KMeshShapes.add_key(m, "A", dA())
	KMeshShapes.add_key(m, "B", dB())
	return m


func _init() -> void:
	# 1 relative
	var m := two()
	KMeshShapes.set_value(m, "A", 0.5)
	KMeshShapes.set_value(m, "B", 0.75)
	var p := KMeshShapes.evaluate(m)
	var exact := true
	for i in 8:
		var want: Vector3 = CV[i] + Vector3(0.25 if i == 6 else 0.0, 0.1875, 0)
		exact = exact and p[i] == want
	ok(exact, "1a relative A 0.5 + B 0.75: every vert exact (vert 6 %s)" % str(p[6]))
	var dc := PackedVector3Array()
	dc.resize(8)
	dc[6] = Vector3(0, 0, 0.5)
	KMeshShapes.add_key(m, "C", dc, "A")
	var pc := KMeshShapes.evaluate(m, {"A": 0.0, "B": 0.0, "C": 1.0})
	var only6 := true
	for i in 8:
		only6 = only6 and pc[i] == CV[i] + (Vector3(0, 0, 0.5) if i == 6 else Vector3.ZERO)
	var sc := KMeshShapes.shape_of(m, "C")
	ok(only6 and sc[6] == Vector3(1.5, 1, 1.5) and sc[0] == Vector3.ZERO, "1b C relative to A: alone it moves vert 6 by the delta from A only (%s); its shape %s" % [str(pc[6]), str(sc[6])])
	var kept := KMeshShapes.set_value(m, "B", 3.0)
	m.shapes["keys"][1]["max"] = 2.0
	var p2 := KMeshShapes.evaluate(m, {"A": 0.0, "C": 0.0, "B": 2.0})
	ok(kept == 1.0 and p2[0] == Vector3(0, 0.5, 0), "1c clamp: value 3 kept as %.1f; with max 2, B at 2 moves vert 0 to %s" % [kept, str(p2[0])])
	m.shapes["keys"][1]["mute"] = true
	ok(KMeshShapes.evaluate(m, {"A": 0.0, "C": 0.0, "B": 1.0}) == PackedVector3Array(CV), "1d a muted key adds nothing")
	m.shapes["keys"][1]["mute"] = false
	m.add_attr("top", KMesh.AD_VERT, TYPE_FLOAT)
	for i in 8:
		m.set_attr("top", i, 1.0 if CV[i].y == 1.0 else (0.5 if i == 0 else 0.0))
	m.shapes["keys"][1]["group"] = "top"
	var pm := KMeshShapes.evaluate(m, {"A": 0.0, "C": 0.0, "B": 1.0})
	var mask_ok := true
	for i in 8:
		mask_ok = mask_ok and pm[i] == CV[i] + Vector3(0, 0.25 if CV[i].y == 1.0 else (0.125 if i == 0 else 0.0), 0)
	ok(mask_ok, "1e mask: top +0.25, vert 0 +0.125 (%s), the rest 0" % str(pm[0]))
	var before := KMeshShapes.shape_of(m, "C")
	KMeshShapes.remove_key(m, "A")
	ok(KMeshShapes.find(m, "A") < 0 and KMeshShapes.shape_of(m, "C") == before and m.shapes["keys"][1]["rel"] == "Basis", "1f remove A: C keeps its shape, now relative to Basis")

	# 2 absolute
	var a := two()
	a.shapes["relative"] = false
	var b0 := PackedVector3Array(CV)
	var sA := KMeshShapes.shape_of(a, "A")
	var sB := KMeshShapes.shape_of(a, "B")
	var t5 := KMeshShapes.evaluate(a, {}, 5.0)
	var t15 := KMeshShapes.evaluate(a, {}, 15.0)
	var ab := true
	for i in 8:
		ab = ab and t5[i] == b0[i] + (sA[i] - b0[i]) * 0.5 and t15[i] == sA[i] + (sB[i] - sA[i]) * 0.5
	ok(ab and t15[6] == Vector3(1.25, 1.125, 1), "2a absolute: t 5 halfway basis..A, t 15 halfway A..B (vert 6 %s)" % str(t15[6]))
	ok(KMeshShapes.evaluate(a, {}, 30.0) == sB and KMeshShapes.evaluate(a, {}, -1.0) == b0, "2b absolute: t 30 = B, t -1 = basis")

	# 3 file
	var f := two()
	KMeshShapes.set_value(f, "A", 0.25)
	KMeshShapes.put_driver(f, {"key": "B", "expr": "A * 0.5"})
	var txt := JSON.stringify(f.to_dict())
	var g := KMesh.new().from_dict(JSON.parse_string(txt))
	ok(g != null and g.shapes == f.shapes, "3a JSON round trip: the shape set equal (%d bytes of text)" % txt.length())
	ok(g != null and KMeshShapes.evaluate(g) == KMeshShapes.evaluate(f) and KMeshShapes.evaluate(g, {"A": 1, "B": 0.5}) == KMeshShapes.evaluate(f, {"A": 1, "B": 0.5}), "3b round trip evaluates the same at two value sets")
	ok(not cube().to_dict().has("shapes"), "3c no keys, no shapes block")
	var bad: Dictionary = JSON.parse_string(txt)
	var short := PackedVector3Array([Vector3.ONE])
	bad["shapes"]["keys"][0]["d"] = KMesh._pack(short.to_byte_array())
	var h := cube()
	var r := h.from_dict(bad)
	ok(r == null and KMesh.last_error.contains("does not match") and h.shapes.is_empty(), "3d a key of the wrong size fails the load: %s" % KMesh.last_error)

	# 4 undo
	var u := cube()
	var un := KMeshUndo.new()
	un.begin(u)
	KMeshShapes.add_key(u, "A", dA())
	var st := un.commit("Add shape key")
	var after := u.shapes.duplicate(true)
	un.undo()
	var gone := KMeshShapes.keys(u).is_empty()
	un.redo()
	ok(st.get("kind") == "shape" and gone and u.shapes == after, "4a add key: one '%s' step; undo removes it, redo puts it back" % st.get("kind"))
	var v0 := u.verts.duplicate()
	un.begin(u)
	KMeshShapes.set_value(u, "A", 1.0)
	KMeshShapes.apply(u)
	var st2 := un.commit("Shape key value")
	var moved := u.verts[6]
	un.undo()
	ok(st2.get("kind") == "move" and moved == Vector3(1.5, 1, 1) and u.verts == v0 and float(KMeshShapes.keys(u)[0]["value"]) == 0.0 and un.steps.size() == 1, "4b value + apply one step: undo puts back value 0 and the positions bit-exact (vert 6 was %s)" % str(moved))

	# 5 driven
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var d := two()
	KMeshShapes.put_driver(d, {"key": "A", "expr": "clamp((lowerarm_r_bend - 30.0) / 60.0, 0.0, 1.0)"})
	var got := []
	for deg in [30.0, 60.0, 120.0]:
		B.ang["lowerarm_r"] = Vector3(deg, 0, 0)
		KMeshShapes.drive(d, KMeshShapes.body_inputs(B))
		got.append(float(KMeshShapes.keys(d)[0]["value"]))
	ok(got == [0.0, 0.5, 1.0], "5a expression driver on the elbow bend 30 / 60 / 120: %s" % str(got))
	KMeshShapes.put_driver(d, {"key": "B", "source": "lowerarm_r_bend", "factor": 0.01, "offset": 0.0, "from": 40.0})
	B.ang["lowerarm_r"] = Vector3(60, 0, 0)
	var w := KMeshShapes.drive(d, KMeshShapes.body_inputs(B))
	ok(is_equal_approx(float(w["B"]), 0.2) and float(w["A"]) == 0.5, "5b linear driver (60 - 40) * 0.01 = %s" % str(w["B"]))
	KMeshShapes.put_driver(d, {"key": "B", "expr": "A * 0.5"})
	w = KMeshShapes.drive(d, KMeshShapes.body_inputs(B))
	var pd := KMeshShapes.evaluate(d)
	ok(float(w["B"]) == 0.25 and pd[6] == Vector3(1.25, 1.0625, 1), "5c B driven by A (0.5 * 0.5 = %s), the blend follows (vert 6 %s)" % [str(w["B"]), str(pd[6])])
	KMeshShapes.put_driver(d, {"key": "B", "expr": "A *"})
	w = KMeshShapes.drive(d, KMeshShapes.body_inputs(B))
	ok(not w.has("B") and float(KMeshShapes.keys(d)[1]["value"]) == 0.25 and KMeshShapes.last_error != "", "5d a bad expression leaves B at 0.25: %s" % KMeshShapes.last_error)
	KMeshShapes.put_driver(d, {"key": "B", "expr": "A * 0.5"})
	var dl := KMesh.new().from_dict(JSON.parse_string(JSON.stringify(d.to_dict())))
	B.ang["lowerarm_r"] = Vector3(120, 0, 0)
	KMeshShapes.drive(dl, KMeshShapes.body_inputs(B))
	ok(float(KMeshShapes.keys(dl)[1]["value"]) == 0.5, "5e drivers survive save / load (elbow 120 -> A 1 -> B %s)" % str(KMeshShapes.keys(dl)[1]["value"]))

	# 6 UI
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	main._kmesh_edit_start()
	await process_frame
	var ui: KMeshEditUI = main.kmed
	var base := ui.mesh.verts.duplicate()
	ui.undo.begin(ui.mesh)
	for i in [0, 3, 7, 11, 20]:
		ui.mesh.verts[i] += Vector3(0.25, 0, 0)
	ui.undo.commit("Move vertices")
	var edited := ui.mesh.verts.duplicate()
	var ki := ui.add_shape_key()
	ok(ki == 0 and ui.mesh.verts == edited and KMeshShapes.keys(ui.mesh)[0]["value"] == 1.0, "6a K: key '%s' at 1.0, the cube unchanged" % KMeshShapes.keys(ui.mesh)[0]["name"])
	for i in 5:
		ui.nudge_shape_key(-0.1)
	var half := true
	for i in base.size():
		half = half and ui.mesh.verts[i] == base[i] + (Vector3(0.125, 0, 0) if i in [0, 3, 7, 11, 20] else Vector3.ZERO)
	ok(half and is_equal_approx(float(KMeshShapes.keys(ui.mesh)[0]["value"]), 0.5), "6b [ x5: value %.2f, the cube = basis + half the edit" % float(KMeshShapes.keys(ui.mesh)[0]["value"]))
	ui.undo.undo()
	var v6 := float(KMeshShapes.keys(ui.mesh)[0]["value"])
	for i in 4:
		ui.undo.undo()
	ok(is_equal_approx(v6, 0.6) and ui.mesh.verts == edited and float(KMeshShapes.keys(ui.mesh)[0]["value"]) == 1.0, "6c undo: 0.6, then back to 1.0 and the edited cube")
	ui.stop()
	print("SHAPEKEYS: %d failed" % fails)
	quit(1 if fails > 0 else 0)
