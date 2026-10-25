extends SceneTree
## A03 mesh undo as diffs. Bars: (1) moving 1000 verts of a 102k-vert grid, undo puts every position back exactly, redo
## forward exactly; (2) the step holds < 5 MB even when ALL 102k verts move (the plan's bar) and is a "move" diff;
## (3) a topology edit (a face deleted) undoes to the same face count + the same faces; (4) an edit that changes nothing
## leaves no step; (5) a new edit after an undo clears the redo
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
func grid(n: int) -> KMesh:
	var v := PackedVector3Array()
	var f := []
	for j in n + 1:
		for i in n + 1:
			v.append(Vector3(i, 0, j) * 0.01)
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			f.append(PackedInt32Array([a, a + 1, a + n + 2, a + n + 1]))
	return KMesh.new().from_arrays(v, f)
func _init() -> void:
	var m := grid(319)
	var U := KMeshUndo.new()
	var orig := m.verts.duplicate()
	U.begin(m)
	for i in 1000:
		m.verts[i * 97] += Vector3(0, 0.05, 0)
	var moved := m.verts.duplicate()
	var st := U.commit("lift")
	U.undo()
	var back_ok := m.verts == orig
	U.redo()
	ok(back_ok and m.verts == moved and st["kind"] == "move" and (st["idx"] as PackedInt32Array).size() == 1000, "(1) %d verts: 1000 moved, undo exact %s, redo exact %s" % [m.vert_count(), back_ok, m.verts == moved])
	U.begin(m)
	for i in m.verts.size():
		m.verts[i].y += 0.001
	var st2 := U.commit("all")
	ok(st2["kind"] == "move" and int(st2["bytes"]) < 5 * 1024 * 1024, "(2) all %d verts moved: step %.2f MB (bar 5)" % [m.vert_count(), float(st2["bytes"]) / 1048576.0])
	var c := grid(4)
	var f0 := c.faces.duplicate()
	U.begin(c)
	var fs := c.faces.duplicate()
	fs.remove_at(5)
	c.from_arrays(c.verts, fs)
	U.commit("delete face")
	var after := c.face_count()
	U.undo()
	ok(after == 15 and c.face_count() == 16 and KMeshUndo._same_faces(c.faces, f0), "(3) topology: 16 -> %d faces, undo -> %d, same faces" % [after, c.face_count()])
	var n := U.steps.size()
	U.begin(c)
	ok(U.commit("nothing").is_empty() and U.steps.size() == n, "(4) a no-change edit keeps no step")
	U.begin(c)
	c.verts[0] += Vector3.UP
	U.commit("x")
	U.undo()
	U.begin(c)
	c.verts[1] += Vector3.UP
	U.commit("y")
	ok(U.redos.is_empty(), "(5) a new edit after undo clears the redo")
	# (6) the pick survives an undo: extrude the selected face, Ctrl+Z -> the original face is selected again, so the user can
	# extrude again at once (Blender keeps the selection when its indices still exist; the UI calls sel.restore(undo.last_sel))
	var q := KMeshView.make_cube(1.0, 2)
	var sel = KMeshSelect.new(q, KMeshSelect.FACE)
	sel.faces[0] = true
	var U2 = KMeshUndo.new()
	U2.sel = sel
	U2.begin(q)
	var f_before := q.face_count()
	KMeshExtrude.extrude(q, sel, 0.1, false)
	U2.commit("extrude")
	var f_after := q.face_count()
	var grown := f_after > f_before
	U2.undo()
	sel.restore(U2.last_sel)
	ok(grown and sel.faces.has(0) and sel.count() == 1 and q.face_count() == f_before,
		"(6) extrude then Ctrl+Z: %d -> %d faces -> %d; the original face is still selected %s (one pick)" % [f_before, f_after, q.face_count(), sel.faces.has(0)])
	print("KMESH UNDO ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)
