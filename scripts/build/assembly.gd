## ASSEMBLY (Friday plan 213): several separately made Parts put together, each placed (move + turn), each still a whole Part record
## that can be opened and edited. The engine only: records in, meshes / files out (the screen is scripts/build/assembly_ui.gd).
##   {"version": 1, "kind": "assembly", "name": "Engine", "seq": 2, "parts": [
##     {"id": "p1", "name": "Screw M4 x 16", "src": "library:screw_m4" | "mine:<saved name>" | "", "rec": <the Part record, a full copy>,
##      "pos": [x, y, z] (mm, where the part's own origin sits), "rot": [rx, ry, rz] (degrees, Basis.from_euler's XYZ order)}]}
## A part keeps its own origin: a part built on the floor stays on the floor of its own frame, then pos / rot place that frame in the
## assembly. Kine's frame: x right, y up, z toward the viewer; the kernel's metres, the record's millimetres.
## Files: one JSON per assembly under user://assemblies/ (the part records are inside it, so the file is the whole assembly). Tests use
## user://assembly_test (while a res://tests script runs) unless Assembly.dir is set.
## Exports: STL (MeshExport's writer, Z up, mm), GLB (Godot's GLTFDocument, one node per part), STEP (the exact solids placed and fused).
class_name Assembly
extends RefCounted

const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const VERSION := 1
const DIR := "user://assemblies"
const TEST_DIR := "user://assembly_test"
const GAP_MM := 10.0   # a part inserted beside the others starts this far from the nearest one

static var dir := ""            # "" = the default for the running script
static var export_dir := "user://exports"
static var _memo := {}          # hash of a part record -> {"mesh", "aabb", "volume", "bodies"}


static func make(name := "Assembly") -> Dictionary:
	return {"version": VERSION, "kind": "assembly", "name": name, "seq": 0, "parts": []}


static func is_assembly(d: Dictionary) -> bool:
	return String(d.get("kind", "")) == "assembly" and d.get("parts", null) is Array


# ---------------------------------------------------------------- the parts

static func index_of(asm: Dictionary, id: String) -> int:
	var ps: Array = asm["parts"]
	for i in ps.size():
		if String((ps[i] as Dictionary)["id"]) == id:
			return i
	return -1


## a name no part of the assembly has yet ("Gear", then "Gear 2", "Gear 3")
static func free_name(asm: Dictionary, base: String) -> String:
	var taken := {}
	for p in asm["parts"]:
		taken[String((p as Dictionary)["name"])] = true
	if not taken.has(base):
		return base
	var i := 2
	while taken.has("%s %d" % [base, i]):
		i += 1
	return "%s %d" % [base, i]


## the built shape of a part record: {"mesh": ArrayMesh painted with the part's looks, "aabb": AABB (m, the part's own frame), "volume": m3, "bodies": n}.
## Built once per record text (a memo), so moving a part never rebuilds it
static func built(rec: Dictionary) -> Dictionary:
	var key := JSON.stringify(rec).hash()
	if _memo.has(key):
		return _memo[key]
	var out := {"mesh": null, "aabb": AABB(), "volume": 0.0, "bodies": 0}
	if Part.available() and not rec.is_empty():
		var res := Part.replay(rec, -1, {})
		var mesh = res.get("mesh", null)
		if mesh != null:
			var pm := (mesh as ArrayMesh).duplicate() as ArrayMesh
			Part.paint(pm, res.get("looks", []))
			out = {"mesh": pm, "aabb": pm.get_aabb(), "volume": float(res.get("volume", 0.0)), "bodies": int(res.get("bodies", 0))}
	if _memo.size() > 64:
		_memo.clear()
	_memo[key] = out
	return out


## add a part record to the assembly; it sits beside the others (its left edge GAP_MM right of the assembly's right edge, on the floor of its own frame).
## Answers the new part's id ("" when the record builds nothing)
static func add_part(asm: Dictionary, rec: Dictionary, name := "", src := "") -> String:
	var b := built(rec)
	if b["mesh"] == null:
		return ""
	asm["seq"] = int(asm["seq"]) + 1
	var id := "p%d" % int(asm["seq"])
	var nm := free_name(asm, name if name != "" else String(rec.get("name", "Part")))
	var pos := Vector3.ZERO
	if not (asm["parts"] as Array).is_empty():
		var right := -INF
		for p in asm["parts"]:
			right = maxf(right, world_aabb(p).end.x)
		pos.x = right / MM + GAP_MM - (b["aabb"] as AABB).position.x / MM
	var r := rec.duplicate(true)
	asm["parts"].append({"id": id, "name": nm, "src": src, "rec": r, "pos": [snappedf(pos.x, 0.01), 0.0, 0.0], "rot": [0.0, 0.0, 0.0]})
	return id


static func remove_part(asm: Dictionary, id: String) -> bool:
	var i := index_of(asm, id)
	if i < 0:
		return false
	(asm["parts"] as Array).remove_at(i)
	return true


## the part's place in the assembly (metres)
static func xf_of(p: Dictionary) -> Transform3D:
	var pos: Array = p["pos"]
	var rot: Array = p["rot"]
	var b := Basis.from_euler(Vector3(deg_to_rad(float(rot[0])), deg_to_rad(float(rot[1])), deg_to_rad(float(rot[2]))))
	return Transform3D(b, Vector3(float(pos[0]), float(pos[1]), float(pos[2])) * MM)


static func set_pose(p: Dictionary, pos: Vector3, rot_deg: Vector3) -> void:
	p["pos"] = [snappedf(pos.x, 0.001), snappedf(pos.y, 0.001), snappedf(pos.z, 0.001)]
	p["rot"] = [snappedf(rot_deg.x, 0.001), snappedf(rot_deg.y, 0.001), snappedf(rot_deg.z, 0.001)]


## the part's box in the assembly frame (metres)
static func world_aabb(p: Dictionary) -> AABB:
	var b := built(p["rec"])
	if b["mesh"] == null:
		return AABB()
	return xf_of(p) * (b["aabb"] as AABB)


## the box of the whole assembly (metres)
static func total_aabb(asm: Dictionary) -> AABB:
	var out := AABB()
	var first := true
	for p in asm["parts"]:
		var a := world_aabb(p)
		if a.size == Vector3.ZERO and a.position == Vector3.ZERO:
			continue
		out = a if first else out.merge(a)
		first = false
	return out


## a part that was turned by a drag: about a world axis through its own origin, by deg (the Euler numbers are read back)
static func turn_about(p: Dictionary, axis: Vector3, deg: float) -> void:
	var xf := xf_of(p)
	var nb := Basis(axis.normalized(), deg_to_rad(deg)) * xf.basis
	var e := nb.get_euler()
	p["rot"] = [snappedf(rad_to_deg(e.x), 0.001), snappedf(rad_to_deg(e.y), 0.001), snappedf(rad_to_deg(e.z), 0.001)]


# ---------------------------------------------------------------- the file

static func folder() -> String:
	if dir != "":
		return dir
	var ml := Engine.get_main_loop()
	var sc: Script = ml.get_script() if ml != null else null
	if sc != null and sc.resource_path.begins_with("res://tests/"):
		return TEST_DIR
	return DIR


static func path_of(nm: String) -> String:
	return "%s/%s.json" % [folder(), MyParts.file_stem(nm)]


static func exists(nm: String) -> bool:
	return FileAccess.file_exists(ProjectSettings.globalize_path(path_of(nm)))


## the first "<base> N" not saved yet
static func free_file_name(base: String) -> String:
	var i := 1
	while exists("%s %d" % [base, i]):
		i += 1
	return "%s %d" % [base, i]


## save as the assembly called nm (the same name replaces); answers the path ("" when the file could not be written)
static func save(asm: Dictionary, nm := "") -> String:
	if nm.strip_edges() != "":
		asm["name"] = nm.strip_edges()
	var path := path_of(String(asm["name"]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(asm, "\t"))
	f.close()
	return path


static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		return {}
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK or not (j.data is Dictionary):
		return {}
	var d: Dictionary = j.data
	if not is_assembly(d):
		return {}
	return d


## every saved assembly: [{"name", "path", "parts": count}], by name
static func list() -> Array:
	var out: Array = []
	var d := folder()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(d)):
		return out
	var files := DirAccess.get_files_at(ProjectSettings.globalize_path(d))
	files.sort()
	for fn in files:
		if not fn.ends_with(".json"):
			continue
		var rec := read("%s/%s" % [d, fn])
		if rec.is_empty():
			continue
		out.append({"name": String(rec.get("name", fn.trim_suffix(".json"))), "path": "%s/%s" % [d, fn], "parts": (rec["parts"] as Array).size()})
	return out


# ---------------------------------------------------------------- export

## the bodies of every part, placed: MeshExport's body dictionaries (mm, Z up), one or more per part
static func bodies_of(asm: Dictionary) -> Dictionary:
	var out: Array = []
	for p in asm["parts"]:
		var bo := MeshExport.bodies_of(p["rec"])
		var xf := xf_of(p)
		var bs: Array = bo["bodies"]
		for i in bs.size():
			var b: Dictionary = bs[i]
			var v: PackedVector3Array = (b["v"] as PackedVector3Array).duplicate()
			for k in v.size():
				v[k] = MeshExport.to_print(xf * MeshExport.to_print_inv(v[k]))
			var nb := b.duplicate()
			nb["v"] = v
			nb["name"] = String(p["name"]) if bs.size() == 1 else "%s %d" % [String(p["name"]), i + 1]
			out.append(nb)
	if out.is_empty():
		return {"bodies": [], "why": "Nothing to export: put a part in the assembly first"}
	return {"bodies": out, "why": ""}


static func _stem(asm: Dictionary) -> String:
	return MeshExport.stem(String(asm.get("name", "Assembly")))


static func _out_dir() -> String:
	var g := ProjectSettings.globalize_path(export_dir)
	DirAccess.make_dir_recursive_absolute(g)
	return g


## "stl" | "3mf": one file with every part. {"ok", "path", "why", "text", "tris", "parts"}
static func export_mesh(asm: Dictionary, fmt: String) -> Dictionary:
	var bo := bodies_of(asm)
	if (bo["bodies"] as Array).is_empty():
		return {"ok": false, "path": "", "why": String(bo["why"]), "text": "NOT DONE: " + String(bo["why"]), "tris": 0, "parts": 0}
	var bodies: Array = bo["bodies"]
	var path := "%s/%s.%s" % [_out_dir(), _stem(asm), fmt]
	var e := MeshExport.write_stl(path, bodies) if fmt == "stl" else MeshExport.write_3mf(path, bodies, String(asm["name"]))
	var tris := 0
	for b in bodies:
		tris += (b["t"] as PackedInt32Array).size() / 3
	if e != OK:
		return {"ok": false, "path": path, "why": error_string(e), "text": "NOT DONE: the file could not be written (%s)" % error_string(e), "tris": 0, "parts": 0}
	return {"ok": true, "path": path, "why": "", "text": "exported %s: %d parts, %d triangles" % [path.get_file(), (asm["parts"] as Array).size(), tris], "tris": tris, "parts": (asm["parts"] as Array).size()}


## a .glb: one node per part (named as in the parts list), each placed, with its colours
static func export_glb(asm: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = MeshExport.stem(String(asm["name"]))
	var n := 0
	for p in asm["parts"]:
		var b := built(p["rec"])
		if b["mesh"] == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = String(p["name"])
		mi.mesh = b["mesh"]
		mi.transform = xf_of(p)
		root.add_child(mi)
		n += 1
	if n == 0:
		root.free()
		return {"ok": false, "path": "", "why": "Nothing to export: put a part in the assembly first", "text": "NOT DONE: Nothing to export: put a part in the assembly first", "parts": 0}
	var path := "%s/%s.glb" % [_out_dir(), _stem(asm)]
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var e := doc.append_from_scene(root, st)
	if e == OK:
		e = doc.write_to_filesystem(st, path)
	root.free()
	if e != OK:
		return {"ok": false, "path": path, "why": error_string(e), "text": "NOT DONE: the .glb could not be written (%s)" % error_string(e), "parts": 0}
	return {"ok": true, "path": path, "why": "", "text": "exported %s: %d parts, each its own node" % [path.get_file(), n], "parts": n}


## a .step: every part's exact solids moved and turned into place, fused into one shape (the file says metres, as StepExport does)
static func export_step(asm: Dictionary) -> Dictionary:
	if not Part.available():
		var w := "Nothing to export: " + Part.why_not()
		return {"ok": false, "path": "", "why": w, "text": "NOT DONE: " + w, "solids": 0}
	var shapes: Array = []
	var temp: Array = []
	for p in asm["parts"]:
		var res := Part.replay(p["rec"], -1, {"keep": true})
		var xf := xf_of(p)
		var e := xf.basis.get_euler()   # R = Rx * Ry * Rz: the kernel turns about z first, then y, then x
		for idv in res.get("ids", []):
			var s := int(idv)
			for step in [[Vector3.BACK, e.z], [Vector3.UP, e.y], [Vector3.RIGHT, e.x]]:
				if absf(float(step[1])) > 1e-9:
					var t := KCad.rotate(s, step[0], float(step[1]))
					if t != 0:
						temp.append(s)
						s = t
			var mv := KCad.translate(s, xf.origin)
			if mv != 0:
				temp.append(s)
				s = mv
			shapes.append(s)
	if shapes.is_empty():
		return {"ok": false, "path": "", "why": "no solid", "text": "NOT DONE: Nothing to export: put a part in the assembly first", "solids": 0}
	var shape := int(shapes[0])
	for i in range(1, shapes.size()):
		var u := KCad.union(shape, int(shapes[i]))
		if u == 0:
			break
		if shape != int(shapes[0]):
			temp.append(shape)
		shape = u
	var path := "%s/%s.step" % [_out_dir(), _stem(asm)]
	var ok := KCad.export_step(shape, path)
	var err := KCad.last_error()
	temp.append(shape)
	for s in shapes:
		temp.append(s)
	var seen := {}
	for s in temp:
		if not seen.has(int(s)):
			seen[int(s)] = true
			KCad.release(int(s))
	if not ok:
		return {"ok": false, "path": path, "why": err, "text": "NOT DONE: the .step could not be written (%s)" % err, "solids": 0}
	var s := FileAccess.get_file_as_string(path)
	if s.contains(StepExport.MILLI_UNIT):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(s.replace(StepExport.MILLI_UNIT, StepExport.METRE_UNIT))
			f.close()
	return {"ok": true, "path": path, "why": "", "text": "exported %s: %d exact solids from %d parts, true size in millimetres" % [path.get_file(), shapes.size(), (asm["parts"] as Array).size()], "solids": shapes.size()}
