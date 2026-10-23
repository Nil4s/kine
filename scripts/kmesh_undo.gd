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
var _before_a := {}   # A09: attribute snapshot (only taken when the mesh has attributes)
var _before_s := {}   # A13: shape keys snapshot (only taken when the mesh has shape keys)
var _before_m: Array = []   # E01: material slots snapshot


func begin(m: KMesh) -> void:
	_mesh = m
	_before_v = m.verts.duplicate()   # copy-on-write: a cheap reference until either side is written
	_before_f = m.faces.duplicate()   # the PackedInt32Arrays inside are values: a shallow copy keeps the old ones
	_before_a = m.attr_snapshot() if not m.attrs.is_empty() else {}
	_before_s = KMeshShapes.snapshot(m.shapes) if not m.shapes.is_empty() else {}
	_before_m = KMeshMaterial.snapshot(m.materials)


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
	if _before_s != m.shapes:   # A13: the shape keys changed (added, removed, a value, a driver): keep both sides whole
		st["s_old"] = _before_s
		st["s_new"] = KMeshShapes.snapshot(m.shapes)
	if _before_m != m.materials:   # E01: a slot added, removed or edited: keep both lists whole (they are small)
		st["m_old"] = _before_m
		st["m_new"] = KMeshMaterial.snapshot(m.materials)
	if _before_v.size() == m.verts.size() and _same_faces(_before_f, m.faces):
		var idx := PackedInt32Array()
		var old := PackedVector3Array()
		var new := PackedVector3Array()
		for i in m.verts.size():
			if m.verts[i] != _before_v[i]:
				idx.append(i)
				old.append(_before_v[i])
				new.append(m.verts[i])
		var ch := _attr_changes(_before_a, m.attrs)
		if idx.is_empty() and ch.is_empty() and not st.has("s_old") and not st.has("m_old"):
			return {}
		if idx.is_empty() and ch.is_empty():
			st.merge({"kind": "shape", "bytes": KMeshShapes.bytes(st["s_old"]) + KMeshShapes.bytes(st["s_new"]) if st.has("s_old") else 0})
		elif idx.is_empty():
			st.merge({"kind": "attr", "a_old": ch["old"], "a_new": ch["new"], "bytes": ch["bytes"]})
		else:
			st.merge({"kind": "move", "idx": idx, "old": old, "new": new, "bytes": idx.size() * 28 + int(ch.get("bytes", 0))})
			if not ch.is_empty():
				st["a_old"] = ch["old"]
				st["a_new"] = ch["new"]
	else:
		var fb := 0
		for f in _before_f:
			fb += (f as PackedInt32Array).size() * 4
		for f in m.faces:
			fb += (f as PackedInt32Array).size() * 4
		st.merge({"kind": "topo", "old_v": _before_v, "new_v": m.verts.duplicate(), "old_f": _before_f, "new_f": m.faces.duplicate(),
			"bytes": (_before_v.size() + m.verts.size()) * 12 + fb})
		if not _before_a.is_empty() or not m.attrs.is_empty():   # the topology changed: keep every channel whole
			var na := m.attr_snapshot()
			st["a_old"] = _before_a
			st["a_new"] = na
			st["bytes"] = int(st["bytes"]) + _attr_bytes(_before_a) + _attr_bytes(na)
	_before_v = PackedVector3Array()
	_before_f = []
	_before_a = {}
	_before_s = {}
	_before_m = []
	if st.has("s_old") and st["kind"] != "shape":
		st["bytes"] = int(st["bytes"]) + KMeshShapes.bytes(st["s_old"]) + KMeshShapes.bytes(st["s_new"])
	st["mesh"] = m
	steps.append(st)
	redos.clear()
	_trim()
	return st


static func _attr_bytes(a: Dictionary) -> int:
	var b := 0
	for k in a:
		var d = a[k]["data"]
		b += d.size() * (4 if a[k]["type"] == TYPE_FLOAT else (8 if a[k]["type"] == TYPE_VECTOR2 else (12 if a[k]["type"] == TYPE_VECTOR3 else 16)))
	return b


## channels that differ between two snapshots: {"old": {name: record or null}, "new": {...}, "bytes"}; {} when none.
## The records are shared, not copied: both sides were already snapshots (before) or are replaced when edited (after).
func _attr_changes(before: Dictionary, now: Dictionary) -> Dictionary:
	var o := {}
	var n := {}
	var b := 0
	for k in before:
		if not now.has(k) or now[k]["domain"] != before[k]["domain"] or now[k]["type"] != before[k]["type"] or now[k]["data"] != before[k]["data"]:
			o[k] = before[k]
			n[k] = _rec(now, k)
			b += _attr_bytes({k: before[k]})
	for k in now:
		if not before.has(k):
			o[k] = null
			n[k] = _rec(now, k)
			b += _attr_bytes({k: now[k]})
	if o.is_empty():
		return {}
	return {"old": o, "new": n, "bytes": b}


static func _rec(a: Dictionary, k):
	if not a.has(k):
		return null
	var r: Dictionary = a[k]
	return {"domain": r["domain"], "type": r["type"], "default": r["default"], "data": r["data"].duplicate()}


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
	elif st["kind"] == "topo":
		m.attrs = {}   # the old channels are the wrong size for the new faces: from_arrays must not fit them
		m.from_arrays(st["old_v"] if back else st["new_v"], (st["old_f"] if back else st["new_f"]).duplicate())
	if st.has("a_old"):
		var src: Dictionary = st["a_old"] if back else st["a_new"]
		if st["kind"] == "topo":
			m.attrs = {}
			for k in src:
				m.attrs[k] = _rec(src, k)
		else:
			for k in src:
				if src[k] == null:
					m.attrs.erase(k)
				else:
					m.attrs[k] = _rec(src, k)
	if st.has("s_old"):
		m.shapes = KMeshShapes.snapshot(st["s_old"] if back else st["s_new"])
	if st.has("m_old"):
		m.materials = KMeshMaterial.snapshot(st["m_old"] if back else st["m_new"])


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
