class_name C48Joints
extends RefCounted
## C48 JOINTS LEAVE THE APP (complaints #314, #320). Nothing here changes how a part is built or how any existing file is written.
##  GLB   write_glb: one glTF node per hinged piece. The node's ORIGIN is the hinge pivot, the piece's mesh hangs under it in pivot-local
##        coordinates, and the node's "extras" state the joint: {"kine_joint": {"type": "revolute", "axis": [x, y, z] (unit, in the node's
##        local frame = the file's frame, because the node is not rotated), "lower_deg", "upper_deg", "hinge", "body"}}. Turning the node about
##        that axis moves only that piece and keeps it on the pivot (Blender / Unity / Godot rotate the node). A piece turned by two hinges
##        (C24's second axis) nests: the first hinge's node holds the second's. Units: metres, the part's own axes (no Y-up swap).
##  URDF  write_urdf: the same joints as revolute joints of a base_link (origin = pivot, axis, limit in radians). Links carry no geometry;
##        the shapes are in the .glb.
##  FRAMES  a named, reusable joint frame (pivot + axis) kept on the part record as rec["frames"][name] = {"o": [mm], "axis": [x, y, z]}.
##        save_frame stores one from a hinge; use_on_hinge puts it on another hinge (its pivot and axis, nothing else).
const MM := 0.001

const SURVIVE := "Joint types that leave the app: Part hinge (turns about an axis, with its limit) -> glTF: a node whose origin is the pivot and whose extras state the axis; URDF: a revolute joint with origin, axis and limits.\nJoint types that do not: slide joints, the swing's angle curve (only the limit is written) and the must-not-touch pairs stay in Kine; a body skeleton joint is exported by the animation targets."


## the part's hinges as plain data, in feature order: [{id, name, body, pivot_mm: Vector3, axis: Vector3, lo, hi (degrees)}]
static func joints(rec: Dictionary) -> Array:
	var out: Array = []
	for f in rec.get("features", []):
		if String(f.get("t", "")) != "hinge" or not (f.get("o") is Array) or not (f.get("axis") is Array):
			continue
		var lim := Part.hinge_limit(f)
		out.append({"id": String(f["id"]), "name": String(f.get("name", f["id"])), "body": int(f.get("body", -1)),
			"pivot_mm": Vector3(float(f["o"][0]), float(f["o"][1]), float(f["o"][2])), "axis": Part._axis(f), "lo": -lim, "hi": lim})
	return out


## the dialog's checklist for the Joints target (lines start OK or WARN; no animation is needed)
static func check_lines(rec: Dictionary) -> Array:
	var js := joints(rec)
	if js.is_empty():
		return ["WARN  no hinge in this part: the .glb holds its shape only and the .urdf is not written"]
	var out: Array = ["OK    %d hinge(s) will be written as joints (glTF node + URDF revolute joint)" % js.size()]
	for j in js:
		if int(j["body"]) < 0:
			out.append("WARN  %s turns no part yet: it is left out of the .glb" % String(j["name"]))
	return out


## the words for the dialog: what this part would write
static func summary(rec: Dictionary) -> String:
	var js := joints(rec)
	var s := ""
	if js.is_empty():
		return s + "This part has no hinge, so the files hold its shape only."
	var names: PackedStringArray = []
	for j in js:
		names.append("%s (axis %.2f, %.2f, %.2f, +-%d deg)" % [j["name"], j["axis"].x, j["axis"].y, j["axis"].z, roundi(float(j["hi"]))])
	return s + "This part writes %d revolute joint(s): %s." % [js.size(), "; ".join(names)]


static func _mesh_of(tris: PackedVector3Array, shift: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in tris:
		st.add_vertex(v - shift)
	st.generate_normals()
	return st.commit()


## Builds the node tree (a Node3D root the caller frees, or null with "why" in out), so a test can read the nodes without a file
static func build(rec: Dictionary, out: Dictionary) -> Node3D:
	if not Part.available():
		out["why"] = "the CAD library is not here"
		return null
	var ids: Array = Part.replay(rec, -1, {"keep": true}).get("ids", [])
	if ids.is_empty():
		out["why"] = "the part has no solid yet"
		return null
	var root := Node3D.new()
	root.name = "scene"
	var chains := {}   # body index -> hinge dicts, in feature order
	for j in joints(rec):
		var b := int(j["body"])
		if b >= 0 and b < ids.size():
			if not chains.has(b):
				chains[b] = []
			chains[b].append(j)
	for b in ids.size():
		var tris := Part._tris_of(int(ids[b]))
		var parent: Node3D = root
		var shift := Vector3.ZERO
		for j in chains.get(b, []):
			var piv = PartRefs.hinge_pivot(rec, String(j["id"]))
			var p: Vector3 = (piv * MM) if piv is Vector3 else (j["pivot_mm"] as Vector3) * MM
			var n := Node3D.new()
			n.name = String(j["name"])
			n.position = p - shift   # local to its parent node
			shift = p
			var ax: Vector3 = j["axis"]
			n.set_meta("extras", {"kine_joint": {"type": "revolute", "axis": [ax.x, ax.y, ax.z], "lower_deg": float(j["lo"]), "upper_deg": float(j["hi"]),
				"hinge": String(j["id"]), "body": b}})
			parent.add_child(n)
			n.owner = root
			parent = n
		var mi := MeshInstance3D.new()
		mi.name = "Body_%d" % b
		mi.mesh = _mesh_of(tris, shift)
		parent.add_child(mi)
		mi.owner = root
	Part.release_kept(ids)
	return root


static func stem(rec: Dictionary) -> String:
	return MeshExport.stem(String(rec.get("name", "Part")))


static func _dir(dir: String) -> String:
	var g := ProjectSettings.globalize_path(dir) if dir.begins_with("res://") or dir.begins_with("user://") else dir
	DirAccess.make_dir_recursive_absolute(g)
	return g


## <dir>/<name>_joints.glb. {"ok", "path", "joints": count, "text"}
static func write_glb(rec: Dictionary, dir: String) -> Dictionary:
	var info := {}
	var root := build(rec, info)
	if root == null:
		return {"ok": false, "path": "", "joints": 0, "text": "NOT DONE: " + String(info.get("why", "nothing to write"))}
	var path := "%s/%s_joints.glb" % [_dir(dir), stem(rec)]
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(root, st)
	if err == OK:
		err = doc.write_to_filesystem(st, path)
	root.free()
	var n := joints(rec).size()
	if err != OK:
		return {"ok": false, "path": path, "joints": n, "text": "NOT DONE: the .glb could not be written (%s)" % error_string(err)}
	return {"ok": true, "path": path, "joints": n, "text": "exported %s: %d hinge(s) as joints (node origin = pivot, axis stated in the node). Metres, the part's own axes" % [path.get_file(), n]}


static func urdf_text(rec: Dictionary) -> String:
	var s := "<?xml version=\"1.0\"?>\n<robot name=\"%s\">\n  <link name=\"base_link\"/>\n" % stem(rec)
	for j in joints(rec):
		var ln := "link_" + String(j["id"])
		var p: Vector3 = (j["pivot_mm"] as Vector3) * MM
		var a: Vector3 = j["axis"]
		s += "  <link name=\"%s\"/>\n" % ln
		s += "  <joint name=\"%s\" type=\"revolute\">\n    <parent link=\"base_link\"/>\n    <child link=\"%s\"/>\n" % [String(j["id"]), ln]
		s += "    <origin xyz=\"%.6f %.6f %.6f\" rpy=\"0 0 0\"/>\n    <axis xyz=\"%.6f %.6f %.6f\"/>\n" % [p.x, p.y, p.z, a.x, a.y, a.z]
		s += "    <limit lower=\"%.6f\" upper=\"%.6f\" effort=\"100\" velocity=\"3.14\"/>\n  </joint>\n" % [deg_to_rad(float(j["lo"])), deg_to_rad(float(j["hi"]))]
	return s + "</robot>\n"


## <dir>/<name>.urdf
static func write_urdf(rec: Dictionary, dir: String) -> Dictionary:
	var js := joints(rec)
	if js.is_empty():
		return {"ok": false, "path": "", "joints": 0, "text": "NOT DONE: the part has no hinge, so there is no joint to list"}
	var path := "%s/%s.urdf" % [_dir(dir), stem(rec)]
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return {"ok": false, "path": path, "joints": js.size(), "text": "NOT DONE: the .urdf could not be written"}
	fa.store_string(urdf_text(rec))
	fa.close()
	return {"ok": true, "path": path, "joints": js.size(), "text": "exported %s: %d revolute joint(s) with origin, axis and limits" % [path.get_file(), js.size()]}


# ---- named joint frames -------------------------------------------------------------------------------------------------

static func frame_names(rec: Dictionary) -> Array:
	var k: Array = (rec.get("frames", {}) as Dictionary).keys()
	k.sort()
	return k


## stores a frame from o_mm and axis under name. "" or the words of why not
static func save_frame(rec: Dictionary, name: String, o_mm: Vector3, axis: Vector3) -> String:
	var n := name.strip_edges().left(40)
	if n == "":
		return "give the frame a name"
	if axis.length() < 1e-6:
		return "the frame needs an axis: pick the hinge line first"
	if not (rec.get("frames") is Dictionary):
		rec["frames"] = {}
	var a := axis.normalized()
	rec["frames"][n] = {"o": [o_mm.x, o_mm.y, o_mm.z], "axis": [a.x, a.y, a.z]}
	return ""


## the frame by name as {"o": Vector3 mm, "axis": Vector3}, or {}
static func get_frame(rec: Dictionary, name: String) -> Dictionary:
	var fr: Variant = (rec.get("frames", {}) as Dictionary).get(name)
	if not (fr is Dictionary) or not (fr.get("o") is Array) or not (fr.get("axis") is Array):
		return {}
	return {"o": Vector3(float(fr["o"][0]), float(fr["o"][1]), float(fr["o"][2])), "axis": Vector3(float(fr["axis"][0]), float(fr["axis"][1]), float(fr["axis"][2]))}


## saves hinge hinge_id's pivot and axis as frame name. "" or why
static func save_from_hinge(rec: Dictionary, hinge_id: String, name: String) -> String:
	var f := Part.feature(rec, hinge_id)
	if f.is_empty() or String(f.get("t", "")) != "hinge":
		return "there is no hinge %s" % hinge_id
	return save_frame(rec, name, Vector3(float(f["o"][0]), float(f["o"][1]), float(f["o"][2])), Part._axis(f))


## puts frame name on hinge hinge_id (pivot and axis only; the angles, limit and pairs stay). "" or why
static func use_on_hinge(rec: Dictionary, hinge_id: String, name: String) -> String:
	var fr := get_frame(rec, name)
	if fr.is_empty():
		return "there is no frame called %s" % name
	var i := Part.index_of(rec, hinge_id)
	if i < 0 or String(rec["features"][i]["t"]) != "hinge":
		return "there is no hinge %s" % hinge_id
	var o: Vector3 = fr["o"]
	var a: Vector3 = fr["axis"]
	rec["features"][i]["o"] = [o.x, o.y, o.z]
	rec["features"][i]["axis"] = [a.x, a.y, a.z]
	return ""


# ---- the hinge dialog's frame row (PartUI) ------------------------------------------------------------------------------

## ONE compact row for the hinge dialog (the panel has no room for two: a taller one pushed OK under the timeline at 1280 x 720):
## a name box, Save frame (the line picked now), and, once a frame is saved, a list that puts one on this hinge
static func frame_row(ui: Object) -> Control:
	var h := HBoxContainer.new()
	h.name = "part_frame_box"
	h.add_theme_constant_override("separation", 4)
	var rec: Dictionary = ui._rec()
	var hp: Dictionary = ui.hp
	var le := LineEdit.new()
	le.name = "part_frame_name"
	le.placeholder_text = "Frame name"
	le.custom_minimum_size.x = 60.0
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(le)
	var sb := Button.new()
	sb.name = "part_frame_save"
	sb.text = "Save frame"
	sb.focus_mode = Control.FOCUS_NONE
	sb.tooltip_text = "Keep this pivot and axis under the name, to use on another hinge"
	sb.disabled = not hp.has("d")
	sb.pressed.connect(func():
		var why := save_frame(ui._rec(), le.text, (hp["o"] as Vector3) / Part.MM, hp["d"])
		ui.m._say_plain(("frame %s saved" % le.text.strip_edges()) if why == "" else "NOT DONE: " + why)
		if why == "":
			ui._hinge_rows())
	h.add_child(sb)
	var names := frame_names(rec)
	if not names.is_empty():
		var ob := OptionButton.new()
		ob.name = "part_frame_use"
		ob.add_item("Use frame")
		for n in names:
			ob.add_item(String(n))
		ob.focus_mode = Control.FOCUS_NONE
		ob.tooltip_text = "Use a saved frame: its pivot and axis go on this hinge"
		ob.item_selected.connect(func(i: int):
			if i <= 0:
				return
			var fr := get_frame(ui._rec(), ob.get_item_text(i))
			if not fr.is_empty():
				hp["o"] = (fr["o"] as Vector3) * Part.MM
				hp["d"] = fr["axis"]
				ui._hinge_rows())
		h.add_child(ob)
	return h
