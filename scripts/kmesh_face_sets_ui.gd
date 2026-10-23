class_name KMeshFaceSetsUI
extends RefCounted
## ROADMAP_400 C09 face sets on screen (the sets themselves: scripts/kmesh_face_sets.gd).
## SCULPT (the test sphere, kmesh_sculpt_ui.gd; keys free there, Blender's where it has one):
##   W  face-set brush: a drag paints a NEW set (Ctrl+drag: grows the set under the press)
##   H  hide the set under the mouse     Shift+H  isolate it (every other set hidden)     Alt+H  show every set
##   Shift+W  "sculpt only this set" on / off: each stroke moves only the verts of the set under its press
##   Alt+]  grow the set under the mouse one ring of faces     Alt+[  shrink it one ring
##   Ctrl+M  mask the set under the mouse (adds to the C03 mask)     Ctrl+Shift+M  mask everything but that set
##   Alt+W  the face-set colours on / off.  Every op is one undo step (Ctrl+Z).
## MODEL (the model preview, kmesh_edit_ui.gd: H / Shift+H / Alt+H are taken there, so commands only, mesh_tools.gd
## "op:fset_*"): sets from the selected faces, from the anatomy tags (A19), body regions (A18), material slots or UV
## islands; hide / isolate the sets of the selected faces, show all; grow / shrink them; colours on / off.

var only := false     # sculpt only the set under the press
var tint: KMeshFaceSetTint


## the sculpt sphere just started: the channel is made before the first undo step (every step diffs the same channels)
func attach(ui) -> void:
	KMeshFaceSets.ensure(ui.mesh)
	tint = KMeshFaceSetTint.on(ui.view, ui.mesh)


## the stroke's params with the face-set ones: `s` is surface_at's hit at the press ({"face", ...})
func params(ui, p: Dictionary, s: Dictionary) -> Dictionary:
	var f := int(s.get("face", -1))
	var under := KMeshFaceSets.set_of(ui.mesh, f) if f >= 0 else 0
	if only and under > 0:
		p["only_set"] = under
	if p["brush"] == KMeshSculpt.FSET:
		p["fset_id"] = under if p["invert"] and under > 0 else KMeshFaceSets.next_id(ui.mesh)
	return p


func _under(ui) -> int:
	var s: Dictionary = ui.surface_at(ui.m.cam, ui._mouse)
	return KMeshFaceSets.set_of(ui.mesh, int(s["face"])) if not s.is_empty() else -1


## the sculpt keys; true = used
func key(ui, ke: InputEventKey) -> bool:
	var k := ke.keycode
	var c := ke.ctrl_pressed
	var sh := ke.shift_pressed
	var al := ke.alt_pressed
	if k == KEY_W and not c:
		if sh:
			only = not only
			ui.m._say("Sculpt: %s" % ("only the set under the press moves (every other set and its seam stay put)" if only else "every set can be sculpted again"))
		elif al:
			if tint != null:
				tint.visible = not tint.visible
			ui.m._say("Sculpt: face-set colours %s" % ("on" if tint == null or tint.visible else "off"))
		else:
			ui.brush = KMeshSculpt.FSET
			ui.m._say("Sculpt: face-set brush: drag paints a new set, Ctrl+drag grows the set you press on. H hides a set, Shift+H isolates, Alt+H shows all")
		return true
	var op := ""
	if k == KEY_H and not c:
		op = "show_all" if al else ("isolate" if sh else "hide")
	elif al and not c and (k == KEY_BRACKETRIGHT or k == KEY_BRACKETLEFT):
		op = "grow" if k == KEY_BRACKETRIGHT else "shrink"
	elif c and not al and k == KEY_M:
		op = "mask_others" if sh else "mask_set"
	if op == "":
		return false
	var id := 0
	if op != "show_all":
		id = _under(ui)
		if id < 0:
			ui.m._say("Sculpt: point at the sphere first (the face set under the mouse is the one %s)" % op.replace("_", " "))
			return true
	ui.undo.begin(ui.mesh)
	var said := run(ui.mesh, op, id)
	var st: Dictionary = ui.undo.commit("face set " + op)
	ui.view.mark_dirty()
	ui.m._say("Sculpt: %s%s" % [said, " (one undo step)" if not st.is_empty() else ""])
	return true


## one op on mesh `m` for set `id`; returns the words
static func run(m: KMesh, op: String, id: int) -> String:
	match op:
		"hide":
			return "face set %d hidden (%d faces): not drawn, not sculpted. Alt+H shows every set" % [id, KMeshFaceSets.hide(m, id)]
		"isolate":
			return "face set %d isolated (%d faces of other sets hidden)" % [id, KMeshFaceSets.isolate(m, id)]
		"show_all":
			return "every face set shown (%d faces were hidden)" % KMeshFaceSets.show_all(m)
		"grow":
			return "face set %d grew by one ring (%d faces)" % [id, KMeshFaceSets.grow(m, id)]
		"shrink":
			return "face set %d shrank by one ring (%d faces)" % [id, KMeshFaceSets.shrink(m, id)]
		"mask_set":
			return "masked face set %d (%d more verts frozen)" % [id, KMeshFaceSets.mask_from(m, id, "set")]
		"mask_others":
			return "masked everything but face set %d (%d more verts frozen)" % [id, KMeshFaceSets.mask_from(m, id, "others")]
	return ""


# ---------------------------------------------------------------- MODEL commands (mesh_tools.gd "op:fset_*")

## the selected faces of the model preview (in vert / edge mode: the faces whose every corner is selected)
static func selected_faces(ui) -> PackedInt32Array:
	var out := PackedInt32Array()
	var sel: KMeshSelect = ui.sel
	if not sel.faces.is_empty():
		for f in sel.faces:
			out.append(int(f))
		return out
	var vs := {}
	for v in sel.verts:
		vs[v] = true
	for e in sel.edges:
		vs[e.x] = true
		vs[e.y] = true
	if vs.is_empty():
		return out
	for fi in ui.mesh.face_count():
		var all := true
		for v in (ui.mesh.faces[fi] as PackedInt32Array):
			if not vs.has(v):
				all = false
				break
		if all:
			out.append(fi)
	return out


static func op(name: String, m) -> String:
	var ui = m.kmed
	var mesh: KMesh = ui.mesh
	var t := KMeshFaceSetTint.on(ui.view, mesh)
	if name == "fset_colors":
		t.visible = not t.visible
		return "Model: face-set colours %s" % ("on" if t.visible else "off")
	t.visible = true
	var sets := PackedInt32Array()   # the sets of the selected faces (hide / isolate / grow / shrink)
	if name in ["fset_hide", "fset_isolate", "fset_grow", "fset_shrink"]:
		var seen := {}
		for fi in selected_faces(ui):
			seen[KMeshFaceSets.set_of(mesh, fi)] = true
		sets = PackedInt32Array(seen.keys())
		if sets.is_empty():
			return "Model: select a face of the face set first"
		if name == "fset_isolate" and sets.size() > 1:
			return "Model: the selection touches %d face sets: select faces of one set to isolate it" % sets.size()
	ui.undo.begin(mesh)
	var said := ""
	match name:
		"fset_from_sel":
			var fs := selected_faces(ui)
			said = "select faces first" if fs.is_empty() else "the %d selected faces are face set %d" % [fs.size(), KMeshFaceSets.from_faces(mesh, fs)]
		"fset_anatomy", "fset_regions", "fset_materials", "fset_uv":
			var kind: String = {"fset_anatomy": "anatomy", "fset_regions": "region", "fset_materials": "material", "fset_uv": "uv"}[name]
			var n := KMeshFaceSets.from_labels(mesh, kind)
			var what: String = {"anatomy": "anatomy tag", "region": "body region", "material": "material slot", "uv": "UV island"}[kind]
			said = ("no %ss on this mesh (%s)" % [what, {"anatomy": "Model: colour by anatomy makes them", "region": "Model: colour by body region makes them", "material": "assign a material first", "uv": "unwrap first"}[kind]]) if n < 0 else "one face set per %s: %d sets" % [what, n]
		"fset_show_all":
			said = run(mesh, "show_all", 0)
		"fset_isolate":
			said = run(mesh, "isolate", sets[0])
		_:
			var parts := PackedStringArray()
			for id in sets:
				parts.append(run(mesh, name.trim_prefix("fset_"), id))
			said = "; ".join(parts)
	ui.undo.commit("face sets: " + name.trim_prefix("fset_"))
	ui.view.mark_dirty()
	return "Model: " + said
