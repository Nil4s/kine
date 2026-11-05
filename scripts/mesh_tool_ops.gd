class_name MeshToolOps
extends RefCounted
## THE MODEL-PREVIEW OPS of the mesh tools (scripts/mesh_tools.gd op:<name> lines). Split out of MeshTools so the
## registry (TOOLS, rows, decorate, keys) loads at boot without the ~21 scripts these ops reach (9.8k lines, see
## docs/BOOT_TIME.md): MeshTools.op / MeshTools.run load this file on the first op that runs.


## the ops on the model preview's mesh. validate: what is wrong, said; repair: one KMeshUndo step; wire: the edges on / off
static func op(name: String, m) -> String:
	var ui = m.kmed
	var said := ""
	match name:
		"validate":
			var rep := KMeshValidate.report(ui.mesh)
			if rep["ok"]:
				said = "Model: the mesh is clean (%d verts, %d faces): no doubled or loose verts, no holes, nothing flipped" % [ui.mesh.verts.size(), ui.mesh.faces.size()]
			else:
				said = "Model: %d problems: %s" % [rep["problems"].size(), "; ".join(rep["problems"].map(func(p): return p["fix"]))]
		"repair":
			ui.undo.begin(ui.mesh)
			var done := KMeshValidate.repair(ui.mesh)
			ui.undo.commit("Repair the mesh")
			ui.sel.clear()   # the repair renumbers verts and faces: the old selection would name others
			ui.view.mark_dirty()
			said = "Model: nothing to repair" if done.is_empty() else "Model: repaired %s (one mesh undo step)" % ", ".join(done.keys().map(func(k): return "%s %d" % [k, done[k]]))
		"save_mesh":   # the mesh file (scripts/kmesh_file_ui.gd): Ctrl+S / Save asks the name the first time
			ui.files.save_cmd()
		"open_mesh":   # Open...: the saved meshes (kmesh_file_ui.gd), one undo step
			ui.files.open_cmd()
		"snap_target":
			said = "Model: snap to " + KMeshSnap.NAMES[ui.snap.cycle()]
		"snap_toggle":
			ui.snap.toggle()
		"pivot":
			said = "Model: pivot " + KMeshPivot.NAMES[ui.pivot.cycle()]
		"vpaint", "vpaint_fill":   # E04
			return KMeshVPaintUI.toggle(m) if name == "vpaint" else KMeshVPaintUI.fill_op(m)
		"armour":   # B23 (scripts/armour_from_body.gd, armour_ui.gd)
			return ArmourUI.toggle(m)
		"romclash":   # B24 / B25 (scripts/rom_clash.gd, rom_clash_ui.gd)
			if m.clash_ui == null:
				m.clash_ui = RomClashUI.new(m)
			return m.clash_ui.run_said("rom")
		"wpaint":
			said = KMeshWPaintUI.toggle(m)
		"bevel":
			said = KMeshBevel.run(ui)
			return said   # run() said it
		"anatomy":   # A19 (scripts/kmesh_anatomy.gd)
			ui.anat.toggle()
			return String(m.ui_status.text) if m.get("ui_status") != null else ""
		"anatomy_seed":
			if m.skel == null:
				return "Model: no fighter to take the anatomy tags from"
			ui.undo.begin(ui.mesh)
			KMeshAnatomy.seed_tags(ui.mesh, m.skel, ui.view.global_transform)
			ui.undo.commit("anatomy tags from the bones")
			if ui.anat.on:
				ui.anat._rebuild()
			said = "Model: anatomy tags from the bones again (%d tags; one undo step)" % KMeshAnatomy.counts(ui.mesh).size()
		"body_regions":   # A18 (scripts/kmesh_body.gd)
			ui.body.toggle()
			return String(m.ui_status.text) if m.get("ui_status") != null else ""
		"mesh_spots":   # C05 (scripts/kmesh_spots_ui.gd)
			return KMeshSpotsUI.toggle(m)
		"model_checks":   # B30 (scripts/model_checks_ui.gd): the panel says what it found
			return ModelChecksUI.toggle(m)
		"modifiers":
			said = ui.mods.say_stack()
		"shrinkwrap", "shrinkwrap_view", "shrinkwrap_other", "shrinkwrap_target":   # B13 (scripts/kmesh_shrinkwrap.gd)
			said = KMeshShrinkwrap.op(name, m)
		"uv_pack", "uv_game_2k", "uv_game_4k":   # D04 / D15 (KMeshUVPack): one undo step, says the px/cm
			return KMeshUVPack.run_ui(ui, {"uv_pack": "pack", "uv_game_2k": "2k", "uv_game_4k": "4k"}[name])
		"uv_editor":
			ui.toggle_uv_editor()
		"mat_assign", "mat_select":   # E01: the Materials panel says what it did
			var _n: int = ui.mat_panel.assign_selection() if name == "mat_assign" else ui.mat_panel.select_by(ui.mat_panel.cur)
		"realsize":   # B27 (scripts/real_size.gd): the readout says it
			return RealSizeUI.toggle(m)
		"realsize_fix":
			return RealSizeUI.fix_op(m)
		"wire":
			ui.view.show_wire = not ui.view.show_wire
			ui.view.mark_dirty()
			said = "Model: wire %s" % ("on: every edge drawn over the surface" if ui.view.show_wire else "off: the surface alone")
		_:
			if name.begins_with("decimate"):
				said = KMeshDecimate.op(name, m)   # F03
			elif name.begins_with("lod"):
				said = KMeshLOD.op(name, m)   # F04
			elif name == "retopo":
				return KMeshRetopoUI.toggle(m)   # I11: it says what it did
			elif name == "rigretopo":
				said = KMeshRigRetopo.op(m)   # F10
			elif name.begins_with("refplane"):   # B21 (scripts/kmesh_refplanes_ui.gd): it says what it did
				return ui.refp.open_dialog() if name == "refplane_add" else ui.refp.arm_two_points()
			elif name.begins_with("fset_"):
				said = KMeshFaceSetsUI.op(name, m)   # C09
			elif name.begins_with("sculpt_pose"):
				return SculptPoseUI.op(name, m)   # C19 (scripts/sculpt_pose_ui.gd): it says what it did
			elif name.begins_with("boolean_"):
				said = KMeshBoolean.op(name, m)   # B10
			elif name.begins_with("curve") or name.begins_with("lathe"):
				return KMeshCurvesUI.op(name, m)   # B11 / B12 (scripts/kmesh_curves_ui.gd): it says what it did
			elif name.begins_with("edgeflow_"):
				said = KMeshEdgeFlow.op(name, m)   # B18
			elif name.begins_with("mirror_") or name.begins_with("symmetrize"):
				said = KMeshTopoMirror.op(name, m)   # B22
			elif name.begins_with("separate") or name.begins_with("join") or name.begins_with("origin_"):
				said = KMeshSepJoin.op(name, m)   # B17
	if said != "":
		m._say(said)
	return said
