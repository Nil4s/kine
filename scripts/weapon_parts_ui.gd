class_name WeaponPartsUI
extends RefCounted
## B28 commands of the MODEL page (mesh_tools.gd "op:wpart_*"): tag the selected faces as grip / guard / blade / pommel (one undo
## step each), and "wpart_book" puts the tagged weapon in the grip book with its mass and centre of mass (scripts/weapon_parts.gd).


## the words it said
static func op(name: String, m) -> String:
	var ui = m.kmed
	var mesh: KMesh = ui.mesh
	if name == "wpart_book":
		var r := WeaponParts.join_book(mesh, WeaponParts.model_name)
		if not r["ok"]:
			return "Model: not in the grip book: " + String(r["why"])
		return "Model: in the grip book as %s: %.3f kg, centre of mass (%.1f, %.1f, %.1f) cm" % [r["kind"], r["mass_kg"], r["com"].x * 100.0, r["com"].y * 100.0, r["com"].z * 100.0]
	var role := name.trim_prefix("wpart_")
	if WeaponParts.id_of(role) <= 0:
		return ""
	var fs := KMeshFaceSetsUI.selected_faces(ui)
	if fs.is_empty():
		return "Model: select the faces of the %s first" % role
	WeaponParts.ensure(mesh)   # the channel exists before the step, as the diff wants
	ui.undo.begin(mesh)
	var n := WeaponParts.tag(mesh, fs, role)
	ui.undo.commit("Tag weapon part: " + role)
	ui.view.mark_dirty()
	return "Model: %d faces tagged as the %s (one undo step)" % [n, role]
