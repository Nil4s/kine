class_name KMeshUndo
extends RefCounted
## A03 (docs/ROADMAP_400.md): undo for KMesh edits as DIFFS, not copies. An edit is bracketed begin(mesh) ... commit(label):
## a vertex-only edit (move, sculpt, smooth) keeps just the indices that moved with their old and new positions; an edit
## that changes the topology (extrude, cut, delete) keeps the old and new face lists plus the vertex arrays (it has to: the
## half-edges are rebuilt from them). One step per edit, a cap on the steps and on the bytes they hold.

const MAX_STEPS := 200
const MAX_BYTES := 256 * 1024 * 1024

var steps: Array = []   # done, oldest first
var redos: Array = []
var _mesh: KMesh
var _before_v := PackedVector3Array()
var _before_f: Array = []


func begin(m: KMesh) -> void:
	_mesh = m
	_before_v = m.verts.duplicate()   # copy-on-write: a cheap reference until either side is written
	_before_f = m.faces.duplicate()   # the PackedInt32Arrays inside are values: a shallow copy keeps the old ones


static func _same_faces(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


## close the edit: returns the step (empty when nothing changed: no step is kept)
func commit(label := "edit") -> Dictionary:
	if _mesh == null:
		return {}
	var m := _mesh
	_mesh = null
	var st := {"label": label}
	if _before_v.size() == m.verts.size() and _same_faces(_before_f, m.faces):
		var idx := PackedInt32Array()
		var old := PackedVector3Array()
		var new := PackedVector3Array()
		for i in m.verts.size():
			if m.verts[i] != _before_v[i]:
				idx.append(i)
				old.append(_before_v[i])
				new.append(m.verts[i])
		if idx.is_empty():
			return {}
		st.merge({"kind": "move", "idx": idx, "old": old, "new": new, "bytes": idx.size() * 28})
	else:
		var fb := 0
		for f in _before_f:
			fb += (f as PackedInt32Array).size() * 4
		for f in m.faces:
			fb += (f as PackedInt32Array).size() * 4
		st.merge({"kind": "topo", "old_v": _before_v, "new_v": m.verts.duplicate(), "old_f": _before_f, "new_f": m.faces.duplicate(),
			"bytes": (_before_v.size() + m.verts.size()) * 12 + fb})
	_before_v = PackedVector3Array()
	_before_f = []
	st["mesh"] = m
	steps.append(st)
	redos.clear()
	_trim()
	return st


func _trim() -> void:
	while steps.size() > MAX_STEPS or (steps.size() > 1 and bytes() > MAX_BYTES):
		steps.pop_front()


func bytes() -> int:
	var b := 0
	for s in steps:
		b += int(s["bytes"])
	return b


func _apply(st: Dictionary, back: bool) -> void:
	var m: KMesh = st["mesh"]
	if st["kind"] == "move":
		var idx: PackedInt32Array = st["idx"]
		var src: PackedVector3Array = st["old"] if back else st["new"]
		for k in idx.size():
			m.verts[idx[k]] = src[k]
		m._compute_normals()   # the topology is unchanged: only the normals follow the positions
	else:
		m.from_arrays(st["old_v"] if back else st["new_v"], (st["old_f"] if back else st["new_f"]).duplicate())


func undo() -> String:
	if steps.is_empty():
		return ""
	var st: Dictionary = steps.pop_back()
	_apply(st, true)
	redos.append(st)
	return String(st["label"])


func redo() -> String:
	if redos.is_empty():
		return ""
	var st: Dictionary = redos.pop_back()
	_apply(st, false)
	steps.append(st)
	return String(st["label"])
