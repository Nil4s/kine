## EXPORT DIALOG (ROADMAP 57): one "Export..." for every target. Pick a target (Unreal Engine 5, Unity, Godot, Blender,
## Maya / MotionBuilder, Web / three.js, raw data) and a format; the dialog shows, for that target, the format it uses, what
## the engine needs, what the app does about it, the frame rate, and a checklist of OK / WARN lines for the open scene.
## Export runs the EXISTING writers (main.gd _export_engine / _export_glb / _export_bvh / _export_usd / _export_game), so the
## bytes are theirs. The engine checks are EngineExport.preflight (scripts/engine_export.gd); the needs are in
## docs/research/ENGINES.md and docs/EXPORT.md. Kept out of main.gd like ClipsUI: main makes one of these (main.export_ui).
class_name ExportDialog
extends RefCounted

var m: Node            # main.gd
var dlg: ConfirmationDialog
var ui_target: OptionButton
var ui_format: OptionButton
var ui_info: Label
var ui_checks: Label
var ui_app: Label
var batch_ui: BatchDialog   # Batch... (ROADMAP 80), made on first use

## run: "engine:<id>" (EngineExport preset: root motion, units, pre-flight), "glb", "bvh", "usda", "usda_layers" (ROADMAP 79) or "game" (the PoseTable)
const TARGETS := [
	{"id": "ue5", "label": "Unreal Engine 5", "engine": "ue5",
		"formats": [{"name": "glTF 2.0 (.glb), named _ue5", "run": "engine:ue5"},
			{"name": "FBX 7.4 (.fbx), named _ue5, root motion", "run": "fbx:ue5",
				"needs": "UE5 imports the FBX as a Skeletal Mesh with Import Animations on. Its unit is the centimetre, as in the file: keep Import Uniform Scale at 1. The travel is on the root bone, as in the .glb. Unverified in-engine: UE5 was never opened on this file.",
				"app": "Root motion: the pelvis's sideways travel is moved onto the root bone, so the pelvis keeps its place. Centimetres in the file (binary FBX 7.4, the app's default), UE5 bone names. The weapons and props are not in it."}],
		"app": "Root motion: the pelvis's sideways travel is moved onto the root bone, so the pelvis keeps its place. Units: the file is metres, and UE5's glTF import scales them to centimetres with Import Uniform Scale 100 (unverified in-engine). Up: the file is Y up, UE5 is Z up and converts on import (unverified in-engine). Bones: UE5 Mannequin names, checked against UE5's core list. Unverified in-engine: UE5 was never opened on this file."},
	{"id": "unity", "label": "Unity", "engine": "unity",
		"formats": [{"name": "glTF 2.0 (.glb), named _unity, for glTFast", "run": "engine:unity"},
			{"name": "FBX 7.4 (.fbx), named _unity", "run": "fbx",
				"needs": "Unity's FBX importer reads the file in centimetres and converts them (Convert Units on). Rig: Generic plays the clip on any rig; Humanoid needs an Avatar that maps the UE5 names (pelvis, spine_01, upperarm_l ...) by hand. Unverified in-engine: Unity was never opened on this file.",
				"app": "Centimetres in the file, Y up, nothing moved: the clip moves the hips (no root motion). Bones: UE5 names. Binary FBX 7.4. The weapons and props are not in it."}],
		"app": "Metres and Y up, as the file is: nothing is moved, the clip moves the hips. Unverified in-engine: Unity was never opened on this file. A Humanoid avatar needs the FBX route (Blender, docs/EXPORT.md)."},
	{"id": "godot", "label": "Godot 4", "engine": "godot",
		"formats": [{"name": "glTF 2.0 (.glb), named _godot", "run": "engine:godot"}],
		"app": "Metres and Y up: nothing is moved. Godot imports it as a Skeleton3D with one AnimationPlayer at Root Scale 1. Read back by Godot's own glTF importer (tests/glb_export_test.gd); the import dock was not run on it."},
	{"id": "blender", "label": "Blender", "engine": "",
		"needs": "Blender reads the .glb and the .bvh as they are, in metres. Set the scene's frame rate to the animation's BEFORE importing: the importer turns seconds into frames at the scene's rate (docs/EXPORT.md). Blender is Z up; both importers convert from the files' Y up.",
		"formats": [{"name": "glTF 2.0 (.glb): File > Import > glTF 2.0", "run": "glb"}, {"name": "BVH (.bvh): File > Import > Motion Capture", "run": "bvh"}],
		"app": "The .glb holds one armature with an action named after the scene, a key on every frame. The .bvh holds every joint on every frame, scale 1.0. Both checked with Blender 4.5's own importers (docs/EXPORT.md)."},
	{"id": "maya", "label": "Maya / MotionBuilder", "engine": "",
		"needs": "MotionBuilder reads BVH as motion capture. Maya has no BVH import in its base install: use a BVH plugin, or the FBX route through Blender (docs/EXPORT.md). Maya reads USD through its own importer. Neither was opened for this export. ALEMBIC (.abc) IS NOT WRITTEN: it needs the Ogawa binary writer, a large format build this app does not carry. The joints go out as a USD point cache instead (the USD layers format: <name>_points.usda, a Points prim per frame, metres), which Maya reads through its USD importer.",
		"formats": [{"name": "BVH (.bvh): motion capture", "run": "bvh"}, {"name": "USD (.usda): UsdSkel skeleton animation", "run": "usda"}, {"name": "USD layers (folder): root .usda, one .usda per layer", "run": "usda_layers"},
			{"name": "FBX 7.4 (.fbx): File > Import > FBX", "run": "fbx",
				"needs": "Maya and MotionBuilder read binary FBX 7.4 in centimetres, Y up: File > Import. The bones are joints with a bind pose, and their rotations are curves (Euler XYZ). Unverified: neither was opened on this file.",
				"app": "Centimetres, Y up, the bones as joints with their keys on every frame; one file per fighter, each at its place. The weapons and props are not in it."}],
		"app": "The .bvh holds one skeleton per file: every joint on every frame, metres, Y up, rotation order Z X Y. With several fighters, one .bvh each, placed where they stand. The .usda is UsdSkel with one time sample per frame; the weapons are not in it."},
	{"id": "web", "label": "Web / three.js", "engine": "",
		"needs": "A web app loads the .glb with three.js (GLTFLoader) or Babylon.js: glTF 2.0, metres, Y up, the front to +Z. Unverified in-engine: no browser loaded this file.",
		"formats": [{"name": "glTF 2.0 (.glb)", "run": "glb"}],
		"app": "One file: the mannequin, its skin, its one animation (a key on every frame) and the weapons as animated nodes. With several fighters, each one is its own armature at its place."},
	{"id": "raw", "label": "Raw data", "engine": "",
		"needs": "For your own code. BVH is text: the joint hierarchy and each frame's channels. USD is text: one time sample per frame. The PoseTable is the ARPG's keys (degrees from its rest, eased) for 11 bones; its C# is the one the ARPG's Unity 6 project reads.",
		"formats": [{"name": "BVH (.bvh): every joint, every frame", "run": "bvh"}, {"name": "USD (.usda): UsdSkel", "run": "usda"}, {"name": "PoseTable (.json + .cs): the ARPG", "run": "game"}, {"name": "USD layers (folder): root .usda, one .usda per layer", "run": "usda_layers"}],
		"app": "Written by the same writers the old commands used (the same bytes). The hands, feet and fingers do not reach the PoseTable; the weapons are not in the .usda."},
]


static func targets() -> Array:
	return TARGETS


## one target's dictionary by id ({} when unknown)
static func target(id: String) -> Dictionary:
	for t in TARGETS:
		if (t as Dictionary)["id"] == id:
			return t
	return {}


## the needs text: an engine target's comes from EngineExport (the one place the engines' needs are written)
static func needs_of(t: Dictionary) -> String:
	var eng := String(t.get("engine", ""))
	if eng != "":
		return String(EngineExport.preset(eng).get("needs", ""))
	return String(t.get("needs", ""))


func _init(main_: Node) -> void:
	m = main_


func _build() -> void:
	dlg = ConfirmationDialog.new()
	dlg.name = "export_dialog"
	dlg.title = "Export"
	dlg.ok_button_text = "Export"
	dlg.min_size = Vector2i(640, 0)
	dlg.exclusive = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	var lt := Label.new()
	lt.text = "Target"
	row.add_child(lt)
	ui_target = OptionButton.new()
	ui_target.name = "opt_export_target"
	for t in TARGETS:
		ui_target.add_item((t as Dictionary)["label"])
	ui_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ui_target)
	v.add_child(row)
	var rf := HBoxContainer.new()
	var lf := Label.new()
	lf.text = "Format"
	rf.add_child(lf)
	ui_format = OptionButton.new()
	ui_format.name = "opt_export_format"
	ui_format.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rf.add_child(ui_format)
	v.add_child(rf)
	# the text scrolls in its own box, so the dialog's buttons stay on a small window too
	var sc := ScrollContainer.new()
	sc.name = "export_scroll"
	sc.custom_minimum_size = Vector2(640, 340)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 14)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_info = Label.new()
	ui_info.name = "export_info"
	ui_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_info.custom_minimum_size = Vector2(600, 0)
	inner.add_child(ui_info)
	ui_checks = Label.new()
	ui_checks.name = "export_checks"
	ui_checks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_checks.custom_minimum_size = Vector2(600, 0)
	inner.add_child(ui_checks)
	ui_app = Label.new()
	ui_app.name = "export_app"
	ui_app.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_app.custom_minimum_size = Vector2(600, 0)
	inner.add_child(ui_app)
	sc.add_child(inner)
	v.add_child(sc)
	dlg.add_child(v)
	ui_target.item_selected.connect(_on_target)
	ui_format.item_selected.connect(_on_format)
	dlg.confirmed.connect(_on_export)
	# ROADMAP 80: Batch... exports many scenes from scenes/ in one go (scripts/batch_dialog.gd); the open scene is not touched
	dlg.add_button("Batch...", false, "batch")
	dlg.custom_action.connect(_on_custom)
	m.add_child(dlg)


func _on_custom(action: StringName) -> void:
	if action == &"batch":
		open_batch()


func open_batch() -> void:
	if batch_ui == null:
		batch_ui = BatchDialog.new(m)
	if dlg != null:
		dlg.hide()
	batch_ui.open()


func open() -> void:
	if dlg == null:
		_build()
	_fill_formats()
	_refresh()
	dlg.popup_centered()


func _on_target(_i: int) -> void:
	_fill_formats()
	_refresh()


func _on_format(_i: int) -> void:
	_refresh()


func _cur_id() -> String:
	return String((TARGETS[ui_target.selected] as Dictionary)["id"])


func _fill_formats() -> void:
	ui_format.clear()
	for f in (TARGETS[ui_target.selected] as Dictionary)["formats"]:
		ui_format.add_item(String((f as Dictionary)["name"]))
	ui_format.select(0)


func _refresh() -> void:
	var d := text_of(_cur_id(), maxi(ui_format.selected, 0))
	ui_info.text = "%s\n\nNeeds: %s" % [d["format"], d["needs"]]
	ui_checks.text = "Checklist for this scene\n" + "\n".join(d["checks"])
	ui_app.text = "What the app does: %s\n\nFrame rate: %s" % [d["app"], d["fps"]]


func _on_export() -> void:
	export_now(_cur_id(), maxi(ui_format.selected, 0), "res://exports")


## everything the dialog shows for one target and format, for the scene now: format, needs, app, fps, checks
func text_of(id: String, fi: int) -> Dictionary:
	var t := target(id)
	if t.is_empty():
		return {}
	var fs: Array = t["formats"]
	var f: Dictionary = fs[clampi(fi, 0, fs.size() - 1)]
	var S: Scene = m.S
	var fps_s := "%d fps, the scene's own rate; the file keys every frame at it" % S.fps
	# a format with its own "needs" / "app" replaces the target's (they describe that file type: glTF's scale is not FBX's)
	var needs := String(f["needs"]) if f.has("needs") else needs_of(t)
	var app := String(f["app"]) if f.has("app") else String(t["app"])
	return {"id": id, "format": String(f["name"]), "needs": needs, "app": app, "fps": fps_s,
		"checks": checks(id, String(f["run"]))}


## the checklist: each line starts "OK" or "WARN" (or "WRONG" from the engine pre-flight) and says what it means here
func checks(id: String, run: String) -> Array:
	var out := []
	var S: Scene = m.S
	var B: Body = m.B
	if S.cards.size() < 2:
		out.append("WARN  no animation yet: an export needs at least 2 cards (a move); nothing is written until then")
		return out
	var t := target(id)
	var eng := String(t.get("engine", ""))
	if eng != "":
		out.append_array(EngineExport.preflight(S, B, eng, S.name if S.name != "" else "scene"))
		if run.begins_with("fbx"):
			# the engine's pre-flight describes the .glb's units (metres, scale 100); the FBX is centimetres at scale 1
			for i in out.size():
				var l := String(out[i])
				if l.begins_with("OK    units:") or l.begins_with("WRONG units:"):
					out[i] = l.replace("the file is metres; the mannequin is", "the file is centimetres; the mannequin is").replace("with Import Uniform Scale 100 (the glTF default)", "at Import Uniform Scale 1 (the FBX is centimetres)")
	else:
		if S.fps >= 1 and S.fps <= 120:
			out.append("OK    frame rate: %d fps, a key on every frame (%d keys)" % [S.fps, int(ceil(S.length() * S.fps - 1e-6)) + 1])
		else:
			out.append("WRONG frame rate: %d fps is outside 1-120; set the scene's fps" % S.fps)
	if B.wep_on or B.wep2_on:
		if run.begins_with("engine:") or run == "glb":
			out.append("OK    weapons: animated nodes (weapon, weapon2) with a plain shaft")
		elif run == "bvh":
			out.append("OK    weapons: joints under the hand that holds them")
		elif run == "usda" or run == "usda_layers":
			out.append("WARN  weapons are not in the .usda: the file holds the body only")
		elif run.begins_with("fbx"):
			out.append("WARN  weapons are not in the .fbx: the file holds the body only")
		else:
			out.append("WARN  weapons are not in the PoseTable: its 11 bones are the body; the bat's edge points come with the engine exports (weapon trail .json)")
	if run == "usda_layers":
		var nl := S.layers.size() + (0 if S.layer.is_empty() else 1)
		out.append("OK    layers: the stack, the YY9 one first; each is its own file, and a mute is exact from the top only" if nl > 0 else "OK    layers: none in this scene; the base animation is the whole pose")
		if nl > 1:
			out.append("WARN  a lower layer muted under a live layer above it changes nothing in the DCC: the layer above carries the whole pose")
		out.append("WARN  the joint point cache is a Points prim, not Alembic: it is not an Alembic file")
	var sec := int((S.secondary.get("items", []) as Array).size())
	if sec > 0:
		out.append("WARN  secondary motion (%d item%s) is not in exports: the file has the poses, and the app's swing on top is not written" % [sec, "" if sec == 1 else "s"])
	else:
		out.append("OK    secondary motion: none in this scene")
	if S.props.size() > 0:
		out.append("WARN  %d prop%s not in any export: the files hold the body and its weapons only" % [S.props.size(), "" if S.props.size() == 1 else "s"])
	else:
		out.append("OK    props: none in this scene")
	if not S.audio.is_empty():
		out.append("WARN  the sound track is not in any export: import the sound into the engine yourself")
	if not S.camera.is_empty():
		out.append("WARN  the shot camera is not in any export")
	var fighters: int = (m._export_actors() as Array).size()
	if fighters > 1:
		out.append("OK    %d fighters: each one is in the file at its place" % fighters)
	return out


## runs the existing writer for this target and format into dir; returns what that writer returns (a path, or the
## PoseTable's paths). Used by the Export button and by tests/export_dialog_test.gd, so both take the same road.
func export_now(id: String, fi: int, dir: String) -> Variant:
	var t := target(id)
	if t.is_empty():
		return ""
	var fs: Array = t["formats"]
	var run := String((fs[clampi(fi, 0, fs.size() - 1)] as Dictionary)["run"])
	if run.begins_with("engine:"):
		return m._export_engine(run.trim_prefix("engine:"), dir)
	if run.begins_with("fbx"):
		return m._export_fbx(dir, run == "fbx:ue5")
	match run:
		"glb":
			return m._export_glb(dir)
		"bvh":
			return m._export_bvh(dir)
		"usda":
			return m._export_usd(dir)
		"usda_layers":
			return m._export_usd_layers(dir)
		"game":
			return m._export_game(dir)
	return ""
