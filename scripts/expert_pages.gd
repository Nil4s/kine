class_name ExpertPages
extends RefCounted
## THE EXPERT PAGES (ROADMAP_400 MODEL / SCULPT / SURFACE): the three page-bar pages that were greyed "coming" until the
## mesh tools landed. Each is a page like BODY or POSE: a ribbon row of real tools, built here, one button per tool.
## Every button runs what the S box row runs (MeshTools.run for the mesh tools; the registry's own Callable for the
## commands: the test cube, the body mesh, the test sphere, the UV layout export, the photo material), so a tool does
## the same thing from the ribbon, from the S box and from its key. A MODEL tool on another page opens the test cube
## first (MeshTools.run does that); a brush opens the test sphere first (_brush below).
## EASY MODE: these pages are hidden (the page-bar buttons and any page switch to them), because they are the expert
## tools: scripts/main.gd _sides_apply / _page_set read PAGES here.

const PAGES := ["MODEL", "SCULPT", "SURFACE"]

## the sculpt brushes on the ribbon: label, the key the sphere reads (main's KEYS table in kmesh_sculpt_ui.gd)
const BRUSHES := [["Draw", KEY_D], ["Inflate", KEY_I], ["Grab", KEY_G], ["Clay", KEY_C], ["Crease", KEY_E],
	["Smooth", KEY_S], ["Flatten", KEY_F], ["Pinch", KEY_P], ["Snake", KEY_K]]


## adds the ribbon buttons of the three pages to main's ribbon rows (main.ui_ribbon[...]); called once, from main's _ui
static func build(m: Node) -> void:
	var by_id := {}
	for t in MeshTools.TOOLS:
		by_id[String(t["id"])] = t
	var tool := func(id: String, label: String) -> Button:
		var t: Dictionary = by_id[id]
		return m._button(label, MeshTools.run.bind(t, m), String(t.get("desc", "")) + " (%s)" % String(t["keys"]) if String(t["keys"]) != "" else String(t.get("desc", "")))
	var row: HBoxContainer = m.ui_ribbon["MODEL"]
	row.add_child(m._button("Test cube", m._kmesh_edit_start, "a 4 x 4 cube on the stage to model on (nothing is saved)"))
	row.add_child(m._button("Body mesh", func(): BaseBody.start(m), "open the fighter's own skin as the mesh to edit (Model: edit the body mesh)"))
	row.add_child(m._button("Apply body", func(): BaseBody.apply_cmd(m), "write the edited body back to the fighter, one undo step (Model: apply the body mesh to the fighter)"))
	row.add_child(tool.call("mesh_extrude", "Extrude"))
	row.add_child(tool.call("mesh_inset", "Inset"))
	row.add_child(tool.call("mesh_loopcut", "Loop cut"))
	row.add_child(tool.call("mesh_knife", "Knife"))
	row.add_child(tool.call("mesh_bevel", "Bevel"))
	row.add_child(tool.call("mesh_proportional", "Proportional"))
	row.add_child(tool.call("mesh_modifiers", "Modifiers"))
	row.add_child(tool.call("mesh_validate", "Validate"))
	row.add_child(tool.call("mesh_repair", "Repair"))
	row = m.ui_ribbon["SCULPT"]
	row.add_child(m._button("Test sphere", m._sculpt_start, "a sphere on the stage to sculpt (nothing is saved)"))
	for b in BRUSHES:
		var key: Key = b[1]
		row.add_child(m._button(b[0], _brush.bind(m, key), "sculpt with %s: drag on the sphere (key %s)" % [String(b[0]).to_lower(), OS.get_keycode_string(key)]))
	row = m.ui_ribbon["SURFACE"]
	row.add_child(tool.call("mesh_uv_editor", "UV editor"))
	row.add_child(tool.call("mesh_uvgame2k", "Game UVs 2k"))
	row.add_child(tool.call("mesh_uvpack", "Pack UVs"))
	row.add_child(m._button("Export UVs", m._kmesh_uv_export, "the UV layout as PNG and SVG (Model: export UV layout)"))
	row.add_child(m._button("Material from photo", m.photomat.ask, "a picture becomes a PBR material: albedo, roughness, normal map (Surface: material from a photo...)"))


## a sculpt brush: the test sphere opens first if it is not on, then the brush key goes to it the way a real key does
static func _brush(m: Node, key: Key) -> void:
	if m.ksc == null or not m.ksc.on:
		m._sculpt_start()
	m._press(key)
