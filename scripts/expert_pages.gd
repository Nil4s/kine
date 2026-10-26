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

## the hint in the view while a page has no mesh open (main._mesh_hint_sync): what to click first. Gone when a mesh is open.
const HINTS := {"MODEL": "Start with Test cube, or Body mesh to edit the body's mesh", "SCULPT": "Start with Test sphere",
	"SURFACE": "Open UV editor, or Material from photo"}

## the sculpt brushes on the ribbon: label, the key the sphere reads (main's KEYS table in kmesh_sculpt_ui.gd)
const BRUSHES := [["Draw", KEY_D], ["Inflate", KEY_I], ["Grab", KEY_G], ["Clay", KEY_C], ["Crease", KEY_E],
	["Smooth", KEY_S], ["Flatten", KEY_F], ["Pinch", KEY_P], ["Snake", KEY_K]]


## the Extrude / Inset buttons: opens the test cube if it is not open, then applies the op at once (KMeshEditUI.quick)
static func _quick(m, kind: String) -> void:
	if not MeshTools._model_on(m):
		m._kmesh_edit_start()
	if m.kmed != null and m.kmed.on:
		m.kmed.quick(kind)


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
	row.add_child(tool.call("mesh_save", "Save"))
	row.add_child(tool.call("mesh_open", "Open..."))
	row.add_child(m._button("Use in scene", m._mesh_use_in_scene, "put the open mesh into the scene next to the body as a prop, on the floor at its real size with its material (one undo step); the POSE page shows it"))
	row.add_child(m._button("Extrude", _quick.bind(m, "extrude"), "lift the picked faces 10 cm along their normal, now (one undo step; E then a drag sizes it differently)"))
	row.add_child(m._button("Inset", _quick.bind(m, "inset"), "inset the picked faces by 20 % of their size, now (one undo step; I then a drag sizes it differently)"))
	row.add_child(tool.call("mesh_grab", "Move"))
	row.add_child(tool.call("mesh_rotate", "Rotate"))
	row.add_child(tool.call("mesh_scale", "Scale"))
	row.add_child(tool.call("mesh_loopcut", "Loop cut"))
	row.add_child(tool.call("mesh_knife", "Knife"))
	row.add_child(tool.call("mesh_bevel", "Bevel"))
	row.add_child(tool.call("mesh_proportional", "Proportional"))
	row.add_child(tool.call("mesh_modifiers", "Modifiers"))
	row.add_child(tool.call("mesh_validate", "Validate"))
	row.add_child(tool.call("mesh_repair", "Repair"))
	row = m.ui_ribbon["SCULPT"]
	row.add_child(m._button("Test sphere", m._sculpt_start, "a sphere on the stage to sculpt (nothing is saved)"))
	row.add_child(m._button("Sculpt the body", _sculpt_body.bind(m), "sculpt the fighter's body mesh (the one MODEL edits) with the brushes below; each stroke one undo step, Esc goes back to MODEL (Apply body writes it to the fighter)"))
	for b in BRUSHES:
		var key: Key = b[1]
		row.add_child(m._button(b[0], _brush.bind(m, key), "sculpt with %s: drag on the sphere (key %s)" % [String(b[0]).to_lower(), OS.get_keycode_string(key)]))
	row = m.ui_ribbon["SURFACE"]
	row.add_child(tool.call("mesh_vpaint", "Paint"))   # the same op the S box runs (op:vpaint): paint mode on / off on the model
	row.add_child(tool.call("mesh_uv_editor", "UV editor"))
	row.add_child(tool.call("mesh_uvgame2k", "Game UVs 2k"))
	row.add_child(tool.call("mesh_uvpack", "Pack UVs"))
	row.add_child(m._button("Export UVs", m._kmesh_uv_export, "the UV layout as PNG and SVG (Model: export UV layout)"))
	row.add_child(m._button("Material from photo", m.photomat.ask, "a picture becomes a PBR material: albedo, roughness, normal map (Surface: material from a photo...)"))


## SCULPT, "Sculpt the body": the body mesh MODEL edits (BaseBody.start opens it when it is not open) is the sculpt UI's
## mesh (KMeshSculpt takes any KMesh through the source callable, as the pose sculpt does). Its undo is the body's own, so
## a stroke is one step on the body (Ctrl+Z, and Apply body still writes it). Esc (the sculpt's leave) puts the body back.
static func _sculpt_body(m) -> void:
	if not BaseBody.is_open(m):
		BaseBody.start(m)
	if not BaseBody.is_open(m):
		return   # BaseBody.start said why (no skinned body)
	if m.get("ksc") == null:
		m.ksc = load("res://scripts/kmesh_sculpt_ui.gd").new()
		m.add_child(m.ksc)
		m.ksc.setup(m)
	if m.ksc.on:
		m._say("Sculpt: leave the sculpt first (Esc), then Sculpt the body")
		return
	var kmed = m.kmed
	var at: Transform3D = kmed.view.transform
	var say := "Model: sculpting the BODY mesh (the one MODEL edits): every brush works on it, one undo step per stroke (Ctrl+Z). D C I S F P E G K brushes, [ ] radius, Esc back to the body on MODEL"
	m.ksc.source = func(): return {"mesh": kmed.mesh, "at": at, "undo": kmed.undo, "say": say}
	m.ksc.left = func(): _sculpt_body_left(m)
	kmed.on = false            # the body mesh stands in for the sculpt; its keys and clicks wait until Esc
	kmed.view.visible = false
	m._mesh_page_for("SCULPT")
	m.ksc.start()
	m._mesh_show_sync()


## Esc in the sculpt of the body: the body mesh back on MODEL (its strokes are on its undo stack)
static func _sculpt_body_left(m) -> void:
	var kmed = m.kmed
	m.ksc.source = Callable()
	m.ksc.left = Callable()
	if kmed != null and kmed.view != null:
		kmed.on = true
		kmed.view.visible = true
		kmed.view.mark_dirty()
	m._say("Model: left the sculpt; back on the body mesh (Ctrl+Z takes the strokes back one by one; Apply body writes it to the fighter)")


## a sculpt brush: the test sphere opens first if it is not on, then the brush key goes to it the way a real key does
static func _brush(m: Node, key: Key) -> void:
	if m.ksc == null or not m.ksc.on:
		m._sculpt_start()
	m._press(key)
