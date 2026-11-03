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
var ui_blur: CheckBox   # playblast motion blur (ROADMAP R3)
var ui_what: OptionButton   # "What to export": Everything (the default) / Only the selected object / One entry per mesh object
var ui_face: OptionButton   # laser cutting: which flat face
var ui_face_row: HBoxContainer
var ui_budget: OptionButton   # plan 157: Triangle budget (Full / 50 000 / 10 000 / 2 000) for the mesh files (.glb objects, .obj, .stl, .3mf)
var ui_budget_row: HBoxContainer
var ui_q: OptionButton   # W05: mesh quality of the STL / 3MF (Coarse / Normal / Fine / Custom), the live estimate under it
var ui_q_custom: SpinBox
var ui_q_row: HBoxContainer
var ui_q_info: Label
var ui_fit: CheckBox   # C20: Match the mesh to the fit (off = the usual quality)
var ui_support: OptionButton   # C27: support removal (3MF only)
var ui_support_info: Label
var ui_c43: Dictionary = {}   # C43: the Printer row + the re-read preview (scripts/build/c43_printer.gd)
var last_reread: Dictionary = {}
var _q_cache := {}
var ui_csv_locale: OptionButton   # C14 (#442): the cut-list CSV's locale (0 = comma + dot decimals, the default; 1 = semicolon + decimal comma, for Excel in pt-BR / EU)
var ui_safety: VBoxContainer   # C17: print safety row
var ui_price_row: HBoxContainer   # s081: the price table (BRL) behind the cost line
var opts_scroll: ScrollContainer   # C30
var ui_bed_row: HBoxContainer   # 3D printing only: the printer bed size and Split to fit (Friday plan 114)
var ui_bed: Array = []   # three SpinBoxes: bed X, Y, Z in mm
var ui_split: CheckBox
var split_fit := false
var bed_mm := Vector3(220.0, 220.0, 250.0)
var ui_objects: Label   # the mesh objects in the scene, by name (what the choice picks from)
var batch_ui: BatchDialog   # Batch... (ROADMAP 80), made on first use
var ui_slicer_box: VBoxContainer   # 3D printing only (plan 119): the slicers found + the Send to slicer button
var ui_slicer_txt: Label
var ui_slicer_opt: OptionButton
var ui_slicer_btn: Button
var ui_slicer_again: Button


var nice_real: CheckBox   # s224
var nice_btn: Button       # p105: Nice picture, in the dialog's button row
var nice_say: Label        # p105: where the picture went, in words
var slicers_override = null   # a test: the slicers to show (an Array of {name, path}) instead of looking at this computer
var slicer_launcher := Callable()   # a test: stands in for OS.create_process
var _slicers: Array = []
var _slicers_known := false

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
		"formats": [{"name": "glTF 2.0 (.glb), named _godot", "run": "engine:godot"},
			{"name": "Playable game (Godot project folder)", "run": "game_project",
				"needs": "Godot 4: open the written <name>_game folder (Project Manager > Import > project.godot) and press F5. Nothing to import first: the characters are read when the game starts.",
				"app": "A whole Godot project: the built house and every set prop as static colliders (trimesh), a ground, the hero as a CharacterBody3D (WASD or arrows, Space jumps, Q/E turn the camera, a third-person follow camera), the other characters standing idle, the stage's lights, a README.txt. Metres, Y up."}],
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
		"formats": [{"name": "glTF 2.0 (.glb)", "run": "glb"}, {"name": "Wavefront OBJ (.obj): static mesh, no animation", "run": "obj"}],
		"app": "One file: the mannequin, its skin, its one animation (a key on every frame) and the weapons as animated nodes. With several fighters, each one is its own armature at its place. The .obj is a static mesh (metres, Y up): the body as it stands at the playhead, or the picked object (the set piece) under What to export."},
	{"id": "raw", "label": "Raw data", "engine": "",
		"needs": "For your own code. BVH is text: the joint hierarchy and each frame's channels. USD is text: one time sample per frame. The PoseTable is the ARPG's keys (degrees from its rest, eased) for 11 bones; its C# is the one the ARPG's Unity 6 project reads.",
		"formats": [{"name": "BVH (.bvh): every joint, every frame", "run": "bvh"}, {"name": "USD (.usda): UsdSkel", "run": "usda"}, {"name": "PoseTable (.json + .cs): the ARPG", "run": "game"}, {"name": "USD layers (folder): root .usda, one .usda per layer", "run": "usda_layers"}],
		"app": "Written by the same writers the old commands used (the same bytes). The hands, feet and fingers do not reach the PoseTable; the weapons are not in the .usda."},
]


## 3D PRINTING (STL, 3MF): shown only while a free Part is on screen (so targets() stays the seven engine targets); scripts/build/mesh_export.gd writes the files
## C23: the third print format, listed only while the part has more than one colour (so the two-format list of a plain part is as it was)
const AUTO_FORMAT := {"name": "Best for my part (picks 3MF when the part is painted, and says why)", "run": "auto",
	"app": "A 3MF when the part has colour (an STL would lose it); the words after the export say which and why. Millimetres, Z up, the shape finely cut (0.1 mm)."}
const PRINT_TARGET := {"id": "print", "label": "3D printing (STL, 3MF)", "engine": "",
	"needs": "A slicer (Cura, PrusaSlicer, Bambu Studio, Orca) opens either file. Both hold millimetres, and the part's floor is the print bed (z = 0, Z up). STL is the plain shape; 3MF is the same shape in a package that also keeps each separate piece as its own object and the colour you painted. If you are not sure, pick 3MF.",
	"formats": [{"name": "3MF (.3mf): shape in millimetres, pieces and colour (best for most slicers)", "run": "3mf",
			"app": "A 3MF package: one object for each separate piece of the part, the colour you painted, units in millimetres, the shape finely cut (0.1 mm)."},
		{"name": "STL (.stl): the plain shape in millimetres", "run": "stl",
			"app": "A binary STL in millimetres (an STL has no units, so the slicer reads the numbers as mm), all pieces in one mesh, the shape finely cut (0.1 mm). No colour."}],
	"app": "The part as a printable solid in millimetres."}


## CUT LIST (s081, plan 81): shown only while the part on screen is made of wood boards; scripts/build/cut_list.gd writes the CSV
const CUTLIST_TARGET := {"id": "cutlist", "label": "Cut list (CSV)", "engine": "",
	"needs": "Any spreadsheet (Excel, LibreOffice, Google Sheets) opens the .csv. One line per size of board: its name, length, width and thickness in millimetres, how many of that size, and the board-metres to buy; the last line is the total.",
	"formats": [{"name": "CSV (.csv): the boards to buy", "run": "csv",
			"app": "A .csv with a header, one line for each size of board (boards of the same size are counted together) and a TOTAL line with the number of boards and the board-metres."}],
	"app": "The list of boards to cut, from the wood boards of the part."}


## LASER CUTTING (SVG, DXF; plan 116): shown with 3D printing while a free Part is on screen; scripts/build/laser_export.gd writes the outline of one flat face
const LASER_TARGET := {"id": "laser", "label": "Laser cutting (SVG, DXF)", "engine": "",
	"needs": "Any laser or CNC program (LightBurn, Inkscape, Fusion, LibreCAD) opens either file. Both hold millimetres, drawn flat: the outer edge and every hole of ONE flat face, at full size. Pick the face above: Top is the usual choice for a plate.",
	"formats": [{"name": "SVG (.svg): outline in millimetres", "run": "svg",
			"app": "An SVG whose width, height and viewBox are in millimetres: one red hairline path for the outer edge and one for each hole. Curves are cut finely (0.02 mm off the true curve at most)."},
		{"name": "DXF (.dxf): outline in millimetres (R12)", "run": "dxf",
			"app": "An R12 ASCII DXF in millimetres ($INSUNITS 4): LINE for straight runs, CIRCLE for a round hole, layer CUT. The lower-left corner of the outline is 0,0."}],
	"app": "The outline of one flat face of the part, for cutting."}


## CAD (STEP) (Friday plan 115): shown only while a free Part is on screen, just before 3D printing; scripts/build/step_export.gd writes the file
const STEP_TARGET := {"id": "step", "label": "CAD program (STEP)", "engine": "",
	"needs": "SolidWorks, Fusion, FreeCAD, Onshape, Inventor and CATIA open a .step as it is. It holds the exact solid (true curves and faces, not triangles), so holes can be edited and measured there. The file says its unit is the metre, so the part opens at its true size (a 20 mm box is 20 mm).",
	"formats": [{"name": "STEP (.step): the exact solid for CAD programs", "run": "step",
			"app": "A STEP file (ISO 10303-21) of the part: one exact solid, several pieces are joined into one file. No colour, no timeline: the shape only."}],
	"app": "The part as an exact solid."}


## MY EDITED CHARACTER + ANIMATION (P149): shown only once "Apply the body mesh to the fighter" has put a sculpted body on the fighter (the other targets
## write the stock mannequin). One .glb: the edited body, its skin and the UE5-named skeleton, and the scene's clip. glTF has no FBX writer in Godot.
const BODYANIM_TARGET := {"id": "bodyanim", "label": "My edited character + animation (GLB)", "engine": "",
	"needs": "Blender, Unreal 5, Godot and Unity (glTFast) open the .glb as it is: metres, Y up, the character faces +Z. FBX: Kine cannot write an FBX with a skinned body (Godot has no FBX writer). To get an FBX, open this .glb in Blender and use File > Export > FBX.",
	"formats": [{"name": "glTF 2.0 (.glb): your body, its skeleton and the animation", "run": "bodyanim",
			"app": "One .glb: the body you edited with its skin weights (4 per vertex), the UE5-named skeleton, and the scene's animation (a key on every frame at the scene's rate, as long as the scene). Metres, Y up. No weapons or props."}],
	"app": "Your edited body with the animation, as one .glb."}


static func targets() -> Array:
	return TARGETS


## the targets this dialog shows now: the seven, plus 3D printing while a free part is on screen
func _tg() -> Array:
	var free_part: bool = m.bld != null and m.bld.part != null and m.bld.part.on
	var out: Array = TARGETS.duplicate()
	if m.pieces.size() > 0 and BaseBody.gen(m) > 0:
		out.append(BODYANIM_TARGET)
	if free_part:
		if CutList.is_wood_build(m.S.part):
			out.append(CUTLIST_TARGET)   # s081: only a build of wood boards
		out.append(LASER_TARGET)   # before 3D printing, so the Export button still lands on the last one: 3D printing
		out.append(STEP_TARGET)
		out.append(PRINT_TARGET)
	return out


## one target's dictionary by id ({} when unknown)
static func target(id: String) -> Dictionary:
	for t in TARGETS:
		if (t as Dictionary)["id"] == id:
			return t
	if id == "bodyanim":
		return BODYANIM_TARGET
	if id == "laser":
		return LASER_TARGET
	if id == "cutlist":
		return CUTLIST_TARGET
	if id == "step":
		return STEP_TARGET
	return PRINT_TARGET if id == "print" else {}


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
	var nrow := HBoxContainer.new()   # p105: the Nice picture row sits at the TOP, where it shows however long the dialog grows
	nrow.name = "export_nice_row"
	nice_btn = Button.new()
	nice_btn.name = "btn_nice_picture"
	nice_btn.text = "Nice picture"
	nice_btn.tooltip_text = "Save a nice picture of this part as a PNG (1920 x 1080): soft light, a soft shadow, a faint floor reflection. The part does not change"
	nice_btn.pressed.connect(func(): nice_picture())
	nrow.add_child(nice_btn)
	nice_real = CheckBox.new()   # s224: the REAL-LOOK preset (sky, sun, soft shadows, occlusion, reflections); off = the soft studio picture
	nice_real.name = "chk_nice_realistic"
	nice_real.text = "Realistic"
	nice_real.focus_mode = Control.FOCUS_NONE
	nice_real.button_pressed = NiceRender.look == "real"
	nice_real.tooltip_text = "Draw the picture with a physical sky and sun, soft real shadows, ambient occlusion and reflections (a few seconds)"
	nice_real.toggled.connect(func(v: bool): NiceRender.look = "real" if v else "studio")
	nrow.add_child(nice_real)
	nice_say = Label.new()
	nice_say.name = "export_nice_text"
	nice_say.text = "A picture of the part for showing it (PNG)"
	nice_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nice_say.custom_minimum_size = Vector2(440, 0)
	nice_say.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(nice_say)
	v.add_child(nrow)
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
	var rw := HBoxContainer.new()
	var lw := Label.new()
	lw.text = "What to export"
	rw.add_child(lw)
	ui_what = OptionButton.new()
	ui_what.name = "opt_export_what"
	ui_what.add_item("Everything")
	ui_what.add_item("Only the selected object")
	ui_what.add_item("One entry per mesh object (by its name)")
	ui_what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_what.item_selected.connect(func(_i: int): _refresh())
	rw.add_child(ui_what)
	v.add_child(rw)
	ui_face_row = HBoxContainer.new()   # laser cutting only: which flat face
	ui_face_row.name = "export_face_row"
	var lfc := Label.new()
	lfc.text = "Face to cut"
	ui_face_row.add_child(lfc)
	ui_face = OptionButton.new()
	ui_face.name = "opt_export_face"
	for fl in LaserExport.face_labels():
		ui_face.add_item(String(fl))
	ui_face.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_face.item_selected.connect(func(_i: int): _refresh())
	ui_face_row.add_child(ui_face)
	ui_face_row.visible = false
	v.add_child(ui_face_row)
	ui_budget_row = HBoxContainer.new()   # plan 157: the file gets a decimated copy; the model on screen is not changed
	ui_budget_row.name = "export_budget_row"
	var lbu := Label.new()
	lbu.text = "Triangle budget"
	ui_budget_row.add_child(lbu)
	ui_budget = OptionButton.new()
	ui_budget.name = "opt_export_budget"
	for bl in ExportBudget.LABELS:
		ui_budget.add_item(String(bl))
	ui_budget.tooltip_text = "Write a lighter copy of the mesh: the file gets at most this many triangles (volume and size kept); the model on screen is not changed. Applies to the mesh files (.glb objects, .obj, .stl, .3mf)."
	ui_budget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_budget.item_selected.connect(func(_i: int): _refresh_quality())
	ui_budget_row.add_child(ui_budget)
	v.add_child(ui_budget_row)
	ui_q_row = HBoxContainer.new()   # W05: mesh quality for the printing files
	ui_q_row.name = "export_quality_row"
	var lq := Label.new()
	lq.text = "Mesh quality"
	ui_q_row.add_child(lq)
	ui_q = OptionButton.new()
	ui_q.name = "opt_export_quality"
	for qn in MeshQuality.NAMES:
		ui_q.add_item(String(qn))
	ui_q.select(1)
	ui_q.tooltip_text = "How smooth curved faces are in the file. Coarse is small and faceted, Fine is smooth and big, Normal is the usual. Custom takes the most a face may sit off the true surface, in mm."
	ui_q.item_selected.connect(func(_i: int): _refresh())
	ui_q_row.add_child(ui_q)
	ui_q_custom = SpinBox.new()
	ui_q_custom.name = "spin_export_quality_mm"
	ui_q_custom.min_value = MeshQuality.MIN_DEFL_MM
	ui_q_custom.max_value = MeshQuality.MAX_DEFL_MM
	ui_q_custom.step = 0.005
	ui_q_custom.value = 0.1
	ui_q_custom.suffix = "mm"
	ui_q_custom.value_changed.connect(func(_x: float): _refresh())
	ui_q_row.add_child(ui_q_custom)
	v.add_child(ui_q_row)
	ui_fit = CheckBox.new()   # C20: opt-in, off
	ui_fit.name = "opt_export_fit_tess"
	ui_fit.text = "Match the mesh to the fit"
	ui_fit.tooltip_text = "Make curved faces sit at most a quarter of the printer's clearance off the true surface, and check hinges and supports. Off keeps the usual quality."
	ui_fit.toggled.connect(func(_b: bool): _refresh())
	v.add_child(ui_fit)
	ui_q_info = Label.new()
	ui_q_info.name = "export_quality_info"
	ui_q_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_q_info.custom_minimum_size = Vector2(300, 0)
	v.add_child(ui_q_info)
	ui_support = OptionButton.new()   # C27
	ui_support.name = "opt_export_support"
	for sn in SupportPref.NAMES:
		ui_support.add_item(String(sn))
	ui_support.item_selected.connect(func(_i: int): _refresh_support())
	v.add_child(ui_support)
	ui_support_info = Label.new()
	ui_support_info.name = "export_support_info"
	ui_support_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_support_info.custom_minimum_size = Vector2(300, 0)
	v.add_child(ui_support_info)
	ui_c43 = C43Printer.build(self, v)   # C43
	_price_row_build(v)
	ui_safety = PrintSafety.build_row(self)   # C17
	v.add_child(ui_safety)
	_build_bed_row(v)
	ui_slicer_box = VBoxContainer.new()   # plan 119: Send to slicer (3D printing only)
	ui_slicer_box.name = "export_slicer_box"
	ui_slicer_txt = Label.new()
	ui_slicer_txt.name = "export_slicer_text"
	ui_slicer_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_slicer_txt.custom_minimum_size = Vector2(600, 0)
	ui_slicer_box.add_child(ui_slicer_txt)
	var srow := HBoxContainer.new()
	ui_slicer_opt = OptionButton.new()
	ui_slicer_opt.name = "opt_export_slicer"
	ui_slicer_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(ui_slicer_opt)
	ui_slicer_btn = Button.new()
	ui_slicer_btn.name = "btn_send_to_slicer"
	ui_slicer_btn.text = "Send to slicer"
	ui_slicer_btn.pressed.connect(send_to_slicer)
	srow.add_child(ui_slicer_btn)
	ui_slicer_again = Button.new()
	ui_slicer_again.name = "btn_slicer_look_again"
	ui_slicer_again.text = "Look again for slicers"
	ui_slicer_again.pressed.connect(look_again)
	srow.add_child(ui_slicer_again)
	ui_slicer_box.add_child(srow)
	ui_slicer_box.visible = false
	v.add_child(ui_slicer_box)
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
	ui_objects = Label.new()
	ui_objects.name = "export_objects"
	ui_objects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_objects.custom_minimum_size = Vector2(600, 0)
	inner.add_child(ui_objects)
	sc.add_child(inner)
	v.add_child(sc)
	ui_blur = CheckBox.new()
	ui_blur.name = "chk_playblast_blur"
	ui_blur.text = "Playblast video: motion blur (8 sub-frames, 180 deg shutter; slower)"
	ui_blur.button_pressed = bool(m.blast_blur)
	ui_blur.toggled.connect(func(on: bool): m.blast_blur = on)
	v.add_child(ui_blur)
	var est_row := HBoxContainer.new()   # C25: the render time estimate (complaint 730)
	var est_chk := CheckBox.new()
	est_chk.name = "chk_estimate_first"
	est_chk.text = "Say the render time first"
	est_chk.tooltip_text = "Render shots says how long it will take, and which setting costs most, before the first frame"
	est_chk.button_pressed = RenderEstimate.show_first
	est_chk.toggled.connect(func(on: bool): RenderEstimate.show_first = on)
	est_row.add_child(est_chk)
	var est_btn := Button.new()
	est_btn.name = "btn_estimate_time"
	est_btn.text = "Estimate render time"
	est_btn.tooltip_text = "how long Render shots would take now, and the costly setting; nothing is rendered"
	var est_lab := Label.new()
	est_lab.name = "lbl_estimate_time"
	est_btn.pressed.connect(func(): est_lab.text = String(m._render_estimate().get("text", "")))
	est_row.add_child(est_btn)
	est_row.add_child(est_lab)
	v.add_child(est_row)
	v.add_child(BlastBlur.controls(m))
	v.add_child(ExportNames.controls())   # C09: name template, FBX camera, lightmap UV2
	# C30: the options scroll in a box of their own (its height is set in open() to what the window can hold); the dialog's own
	# Export / Cancel / Batch... buttons sit below it, so they stay on screen on a 1024 x 600 window
	opts_scroll = ScrollContainer.new()
	opts_scroll.name = "export_opts_scroll"
	opts_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opts_scroll.add_child(v)
	dlg.add_child(opts_scroll)
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
	_slicers_known = false   # the dialog re-reads the list each open; SlicerSend.detect_cached() looks at the computer once per app run ("Look again" button)
	var tg := _tg()
	var labels_differ := ui_target.item_count != tg.size()
	for li in mini(ui_target.item_count, tg.size()):
		if ui_target.get_item_text(li) != String((tg[li] as Dictionary)["label"]):
			labels_differ = true
	if labels_differ:   # 3D printing joins the list while a free part is on screen
		ui_target.clear()
		for t in tg:
			ui_target.add_item((t as Dictionary)["label"])
	var free_on: bool = m.bld != null and m.bld.part != null and m.bld.part.on
	ui_target.select(tg.size() - 1 if free_on else 0)   # a part on screen: the Export button lands on 3D printing
	_fill_formats()
	_refresh()
	ui_blur.set_pressed_no_signal(bool(m.blast_blur))
	var free_part: bool = m.bld != null and m.bld.part != null and m.bld.part.on   # FEXPORT: a free part on screen is what the beginner made: that object by default
	ui_what.select(1 if (free_part or m._sculpt_sphere_open()) else 0)
	C43Printer.on_open(self, ui_c43)   # C43: a saved printer is taken by a part with none
	ui_budget.select(0)   # a budget is chosen each time: never a silent decimation
	_refresh()
	_fit_to_window()
	dlg.popup_centered()


## C30: the options box takes the height the window leaves (title bar, button row and margins taken off), never more than the options need
func _fit_to_window() -> void:
	var room := int(dlg.get_parent().get_viewport().get_visible_rect().size.y) - 190
	var need := int(opts_scroll.get_child(0).get_combined_minimum_size().y)
	opts_scroll.custom_minimum_size = Vector2(640, clampi(need, 120, maxi(room, 120)))
	dlg.size = Vector2i(dlg.min_size.x, 0)


func _on_target(_i: int) -> void:
	_fill_formats()
	_refresh()


func _on_format(_i: int) -> void:
	_refresh()


func _cur_id() -> String:
	return String((_tg()[ui_target.selected] as Dictionary)["id"])


func _fill_formats() -> void:
	ui_format.clear()
	for f in (_tg()[ui_target.selected] as Dictionary)["formats"]:
		ui_format.add_item(String((f as Dictionary)["name"]))
	if _cur_id() == "print" and m.S != null and C23Colour.colours_of(MeshExport.bodies_of(m.S.part, {})["bodies"]).size() > 1:   # C23
		ui_format.add_item(String(AUTO_FORMAT["name"]))
	ui_format.select(0)


func _refresh() -> void:
	var d := text_of(_cur_id(), maxi(ui_format.selected, 0))
	ui_info.text = "%s\n\n%s %s" % [dlg.tr(d["format"]), dlg.tr("Needs:"), dlg.tr(d["needs"])]   # FRIDAY 99: each piece through the translation (English is unchanged)
	ui_checks.text = dlg.tr("Checklist for this scene") + "\n" + "\n".join(d["checks"])
	ui_app.text = "%s %s\n\n%s %s" % [dlg.tr("What the app does:"), dlg.tr(d["app"]), dlg.tr("Frame rate:"), dlg.tr(d["fps"])]
	var plain := _cur_run() == "glb" or _cur_run() == "obj"
	ui_what.disabled = not plain
	var why := "" if plain else "\n\nThe choice is for the plain .glb (one mesh per object, no animation); this format always holds everything."
	ui_face_row.visible = _cur_id() == "laser"
	ui_budget_row.visible = _cur_run() in ["glb", "obj", "stl", "3mf", "auto"]
	ui_price_row.visible = _cur_id() == "cutlist" or _cur_id() == "print"
	if ui_safety != null:
		ui_safety.visible = _cur_id() == "print"
	_refresh_quality()
	_refresh_support()
	C43Printer.refresh(self, ui_c43)   # C43
	if ui_bed_row != null:
		ui_bed_row.visible = _cur_id() == "print"
	_refresh_slicer()
	if _cur_id() == "cutlist":
		ui_objects.text = "The part on screen is what is read: each wood board is one line. The prices above set the cost line on the Size label."
		return
	if _cur_id() == "laser":
		ui_objects.text = "The part on screen is what is read. Pick the face above; its outer edge and holes are written in millimetres."
		return
	if _cur_id() == "step":
		ui_objects.text = "The part on screen is what is written, as one exact solid. The file says metres, so a CAD program shows the true size."
		return
	if _cur_id() == "print":
		var sc = ui_checks.get_parent().get_parent()   # the "Ready to print?" lines are last in the checklist: scroll them into view
		if sc is ScrollContainer:
			(func(): (sc as ScrollContainer).ensure_control_visible(ui_checks)).call_deferred()
		ui_objects.text = dlg.tr("The part on screen is what is written. It holds millimetres, Z up, and the floor of the part is the print bed.")
		return
	var names := m.scene_object_names() as Array   # only the targets that list the scene's objects pay for it (it skins the body: ~0.5 s)
	var lst := ", ".join(names) if not names.is_empty() else "none"
	ui_objects.text = "Mesh objects in the scene: %s. Only the selected object writes just the one picked in the scene (the test cube when it is open, else the set piece picked, else the body); one entry per mesh object writes each by its name.%s" % [lst, why]


## W05: the chosen mesh quality ({} when the dialog is not on the printing files, which then write as before)
func quality() -> Dictionary:
	if ui_q == null:
		return {}
	if ui_fit != null and ui_fit.button_pressed:   # C20
		var fq := C20Fit.quality_for_fit(m.S.part)
		if not fq.is_empty():
			return fq
	return MeshQuality.of(ui_q.get_item_text(maxi(ui_q.selected, 0)), ui_q_custom.value)


func _refresh_support() -> void:   # C27
	var on: bool = _cur_id() == "print" and _cur_run() == "3mf"
	ui_support.visible = on
	ui_support_info.visible = on
	ui_support_info.text = SupportPref.words(ui_support.selected)


func _refresh_quality() -> void:
	var on: bool = (_cur_id() == "print" and _cur_run() in ["stl", "3mf", "auto"]) or (_cur_run() in ["glb", "obj"] and ui_what.selected > 0 and not (m.S.part as Dictionary).is_empty() and Part.available())   # W05b: and the OBJ / GLB of the part's objects
	ui_q_row.visible = on
	ui_q_info.visible = on
	ui_q_custom.visible = on and ui_q.selected == 3
	if not on:
		return
	var q := quality()
	var rec: Dictionary = m.S.part
	var budget: int = ExportBudget.BUDGETS[ui_budget.selected] if ui_budget.selected >= 0 else 0
	var key := "%d|%s|%s|%d" % [rec.hash(), str(q), _cur_run(), budget]
	var fmt := ("3mf" if _cur_run() == "auto" else _cur_run()) if _cur_run() in ["stl", "3mf", "auto"] else "stl"
	if not _q_cache.has(key):
		var bo := MeshExport.bodies_of(rec, q)
		_q_cache[key] = MeshQuality.estimate(ExportBudget.apply_bodies(bo["bodies"], budget), fmt, String(rec.get("name", "Part"))) if (bo["bodies"] as Array).size() > 0 else {"tris": 0, "bytes": 0, "text": "nothing to export yet"}
	ui_q_info.text = String((_q_cache[key] as Dictionary)["text"])
	if ui_fit != null and ui_fit.button_pressed and not q.is_empty() and String(q.get("name", "")) == "Fit":   # C20: reported
		ui_q_info.text = C20Fit.tess_words(q, int((_q_cache[key] as Dictionary)["tris"])) + ". " + ui_q_info.text


func _cur_run() -> String:
	if _cur_id() == "print" and ui_format.selected == 2:   # C23: the listed-only-when-painted third format
		return "auto"
	var fs: Array = (_tg()[ui_target.selected] as Dictionary)["formats"]
	return String((fs[clampi(maxi(ui_format.selected, 0), 0, fs.size() - 1)] as Dictionary)["run"])


func _on_export() -> void:
	export_now(_cur_id(), maxi(ui_format.selected, 0), "res://exports", maxi(ui_face.selected, 0) if _cur_id() == "laser" else maxi(ui_what.selected, 0))


## everything the dialog shows for one target and format, for the scene now: format, needs, app, fps, checks
func text_of(id: String, fi: int) -> Dictionary:
	var t := target(id)
	if t.is_empty():
		return {}
	var fs: Array = t["formats"]
	var f: Dictionary = AUTO_FORMAT if (id == "print" and fi == 2) else fs[clampi(fi, 0, fs.size() - 1)]
	var S: Scene = m.S
	var fps_s := "%d fps, the scene's own rate; the file keys every frame at it" % S.fps
	if id == "bodyanim":
		fps_s = "%d fps, the scene's own rate; a key on every frame" % S.fps
	if id == "print" or id == "step":
		fps_s = "none: a printed part is one still shape"
	if id == "laser":
		fps_s = "none: a cut outline is one still shape"
	if id == "cutlist":
		fps_s = "none: a cut list is a table"
	# a format with its own "needs" / "app" replaces the target's (they describe that file type: glTF's scale is not FBX's)
	var needs := String(f["needs"]) if f.has("needs") else needs_of(t)
	var app := String(f["app"]) if f.has("app") else String(t["app"])
	return {"id": id, "format": String(f["name"]), "needs": needs, "app": app, "fps": fps_s,
		"checks": checks(id, String(f["run"]))}


## the checklist: each line starts "OK" or "WARN" (or "WRONG" from the engine pre-flight) and says what it means here
func checks(id: String, run: String) -> Array:
	var out := []
	if id == "step":
		return StepExport.check_lines(m.S.part)
	if id == "print":   # the printability check of the part on screen
		var pl: Array = MeshExport.check_lines(m.S.part, quality(), ExportBudget.BUDGETS[ui_budget.selected] if ui_budget != null and ui_budget.selected >= 0 else 0)
		if not (m.S.part as Dictionary).is_empty() and Part.available():
			pl.append_array(PrintSplit.size_lines(m.S.part, bed_mm, split_fit))
			if ui_fit != null and ui_fit.button_pressed:   # C20
				var fbo := MeshExport.bodies_of(m.S.part, quality())
				if not (fbo["bodies"] as Array).is_empty():
					pl.append_array(C20Fit.check_lines(m.S.part, fbo["bodies"], quality()))
			var cl := C23Colour.dialog_line(m.S.part, run, quality())   # C23: a part with more than one colour says what each format does with it
			if cl != "":
				pl.append(cl)
		return pl
	if id == "cutlist":
		return CutList.check_lines(m.S.part)
	if id == "laser":
		return LaserExport.check_lines(m.S.part, ui_face.selected if ui_face != null else 0)
	if id == "bodyanim":
		var bl := []
		var n := int(ceil(m.S.length() * m.S.fps - 1e-6)) + 1
		bl.append("OK    body: your edited body, skinned to the UE5-named skeleton")
		if m.S.cards.size() < 2:
			bl.append("WARN  no animation yet: with fewer than 2 cards there is nothing to write; make a move first")
		else:
			bl.append("OK    animation: %d keys at %d fps, %.2f s" % [n, m.S.fps, m.S.length()])
		bl.append("WARN  FBX is not written: open the .glb in Blender and export FBX from there")
		return bl
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
		if run == "game_project":   # s200: the characters hold their first pose in the game, so the .glb's root-motion warning does not apply
			out = out.filter(func(l): return not String(l).contains("root motion"))
			out.append("OK    game: the hero walks by the game's own script and holds its first pose (the move is not played); the other characters stand idle")
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
	if not S.audio_tracks.is_empty():
		out.append("WARN  the sound track is not in any export: import the sound into the engine yourself")
	if not S.shots.is_empty():
		out.append("WARN  the shot camera is not in any export")
	var fighters: int = (m._export_actors() as Array).size()
	if fighters > 1:
		out.append("OK    %d fighters: each one is in the file at its place" % fighters)
	return out


func S_cards_short() -> bool:
	return m._hero_scene().cards.size() < 2


## runs the existing writer for this target and format into dir; returns what that writer returns (a path, or the
## PoseTable's paths). Used by the Export button and by tests/export_dialog_test.gd, so both take the same road.
## what: 0 Everything (the writers above, unchanged), 1 only the selected object, 2 one entry per mesh object (plain .glb only)
func export_now(id: String, fi: int, dir: String, what := 0) -> Variant:
	var budget: int = ExportBudget.BUDGETS[ui_budget.selected] if ui_budget != null and ui_budget.selected >= 0 else 0   # plan 157
	var t := target(id)
	if t.is_empty():
		return ""
	var fs: Array = t["formats"]
	var run := "auto" if (id == "print" and fi == 2) else String((fs[clampi(fi, 0, fs.size() - 1)] as Dictionary)["run"])
	if id == "cutlist":   # s081: the CSV of the boards
		var rc := CutList.export_csv(m.S.part, UserPaths.w(dir), ui_csv_locale.selected if ui_csv_locale != null and ui_csv_locale.selected > 0 else 0)
		m._say_plain(String(rc["text"]))
		return String(rc["path"]) if bool(rc["ok"]) else ""
	if id == "laser":   # SVG / DXF of one flat face (what = the face's index in LaserExport.FACES)
		var rl := LaserExport.export_part(m.S.part, run, UserPaths.w(dir), what)
		m._say_plain(String(rl["text"]))
		return String(rl["path"]) if bool(rl["ok"]) else ""
	if id == "print":   # STL / 3MF of the part on screen (never blocked: an open shape still writes, with the warning in the words)
		var why23 := ""
		if run == "auto":   # C23: the part decides; the words say why
			var pk23 := C23Colour.pick(m.S.part, quality(), "auto")
			run = String(pk23["fmt"])
			why23 = String(pk23["why"])
		var r := PrintSplit.export_part(m.S.part, run, UserPaths.w(dir), bed_mm, quality(), SupportPref.of(ui_support.selected) if run == "3mf" and ui_support != null else {}) if split_fit else MeshExport.export_part(m.S.part, run, UserPaths.w(dir), budget, quality(), SupportPref.of(ui_support.selected) if run == "3mf" and ui_support != null else {})
		m._say_plain(String(r["text"]) + (". " + why23 if why23 != "" and bool(r["ok"]) else ""))
		if not split_fit and bool(r["ok"]):   # C43: the written file is read back and drawn as the preview
			var bo43: Array = MeshExport.bodies_of(m.S.part, quality())["bodies"]
			last_reread = C43Printer.after_export(ui_c43, r, ExportBudget.apply_bodies(bo43, budget))
		return String(r["path"]) if bool(r["ok"]) else ""
	if id == "step":   # STEP of the part on screen (the exact solid)
		var rs := StepExport.export_part(m.S.part, UserPaths.w(dir))
		m._say_plain(String(rs["text"]))
		return String(rs["path"]) if bool(rs["ok"]) else ""
	if run == "bodyanim":
		if S_cards_short():
			m._say_plain("NOT NOW: an animation needs at least 2 cards (a move). Make a move, then export again")
			return ""
		var rb := BodyExport.write_anim(BaseBody.read(m), m._hero_scene(), m.B, "%s/%s_body_anim.glb" % [UserPaths.w(dir), m._export_base()])
		m._refresh()
		if int(rb["err"]) != OK:
			m._say_plain("NOT DONE: the .glb could not be written (%s)" % error_string(int(rb["err"])))
			return ""
		m._say_plain("exported %s: your body (%d verts) with its skeleton and the animation. FBX: open this .glb in Blender and export FBX" % [String(rb["path"]).get_file(), int(rb["verts"])])
		return String(rb["path"])
	if what > 0 and run == "glb":
		return m._export_objects(dir, what == 1, budget, quality())
	if run == "obj":   # OBJ: Everything is the posed body (the old writer); a picked object or one entry per object is its own mesh
		return m._export_obj_objects(dir, what == 1, budget, quality()) if what > 0 else m._export_obj(dir, budget)
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
		"game_project":
			return GameProject.write(m, dir)
	return ""


## the "Printer bed" size boxes and the "Split to fit" tick (Friday plan 114), in the 3D printing target only
func _build_bed_row(v: VBoxContainer) -> void:
	ui_bed_row = HBoxContainer.new()
	ui_bed_row.name = "export_bed_row"
	var l := Label.new()
	l.text = "Printer bed (mm)"
	ui_bed_row.add_child(l)
	ui_bed = []
	for a in 3:
		var sb := SpinBox.new()
		sb.name = "spin_export_bed_%s" % ["x", "y", "z"][a]
		sb.min_value = 10.0
		sb.max_value = 2000.0
		sb.step = 1.0
		sb.value = bed_mm[a]
		sb.custom_minimum_size = Vector2(80, 0)
		sb.value_changed.connect(func(x: float):
			bed_mm[a] = x
			_refresh())
		ui_bed_row.add_child(sb)
		ui_bed.append(sb)
	ui_split = CheckBox.new()
	ui_split.name = "chk_export_split"
	ui_split.text = "Split to fit (cut into pieces, with dowel holes)"
	ui_split.button_pressed = split_fit
	ui_split.toggled.connect(func(on: bool):
		split_fit = on
		_refresh())
	ui_bed_row.add_child(ui_split)
	ui_bed_row.visible = false
	v.add_child(ui_bed_row)
## SEND TO SLICER (plan 119): the slicers this computer has (looked up once per opening of the dialog)
func slicers() -> Array:
	if not _slicers_known:
		_slicers = (slicers_override as Array) if slicers_override != null else SlicerSend.detect_cached()
		_slicers_known = true
	return _slicers


## the user installed a slicer while the app runs: look at the computer again
func look_again() -> void:
	SlicerSend.forget()
	_slicers_known = false
	_refresh_slicer()


func _refresh_slicer() -> void:
	if ui_slicer_box == null:
		return
	var on := _cur_id() == "print"
	ui_slicer_box.visible = on
	if not on:
		return
	var sl := slicers()
	var keep := ui_slicer_opt.selected
	ui_slicer_opt.clear()
	for s in sl:
		ui_slicer_opt.add_item(String((s as Dictionary)["name"]))
	if not sl.is_empty():
		ui_slicer_opt.select(clampi(keep, 0, sl.size() - 1))
	ui_slicer_opt.visible = not sl.is_empty()
	ui_slicer_btn.disabled = sl.is_empty()
	ui_slicer_txt.text = SlicerSend.found_text(sl)


## writes the part's 3MF to user://exports and starts the picked slicer on it
func send_to_slicer() -> Dictionary:
	var sl := slicers()
	var pick: Dictionary = sl[clampi(ui_slicer_opt.selected, 0, sl.size() - 1)] if not sl.is_empty() else {}
	var lch: Callable = slicer_launcher if slicer_launcher.is_valid() else Callable(SlicerSend, "launch")
	var r := SlicerSend.send(m.S.part, pick, lch)
	m._say_plain(String(r["text"]))
	return r


## s081: the price table row (Cut list and 3D printing): PLA R$ per kg and pine board R$ per metre; each change is kept in user://kine_prices.json
func _price_row_build(v: VBoxContainer) -> void:
	ui_price_row = HBoxContainer.new()
	ui_price_row.name = "export_price_row"
	ui_price_row.visible = false
	for spec in [["pla_brl_kg", "Prices: PLA R$ per kg"], ["pine_brl_m", "pine board R$ per metre"]]:
		var l := Label.new()
		l.text = String(spec[1])
		ui_price_row.add_child(l)
		var sb := SpinBox.new()
		sb.name = "export_price_" + String(spec[0])
		sb.min_value = 0.0
		sb.max_value = 100000.0
		sb.step = 0.5
		sb.value = float(CutList.prices()[spec[0]])
		sb.value_changed.connect(func(x: float): CutList.set_price(String(spec[0]), x))
		ui_price_row.add_child(sb)
	var ll := Label.new()
	ll.text = "CSV for"
	ui_price_row.add_child(ll)
	ui_csv_locale = OptionButton.new()
	ui_csv_locale.name = "opt_export_csv_locale"
	for nm in CutList.LOCALES:
		ui_csv_locale.add_item(String(nm))
	ui_csv_locale.tooltip_text = "Which spreadsheet setup opens the cut list cleanly. Default: comma between columns, dot decimals. Excel with a comma-decimal language (Portuguese, German, French...): semicolon between columns, decimal comma."
	ui_price_row.add_child(ui_csv_locale)
	v.add_child(ui_price_row)


## p105 NICE PICTURE: the part on screen drawn off-screen at 1920 x 1080 and saved as <part>_nice.png beside its other exports.
## Returns the saved path ("" when not made); the words go in the dialog and on the status line. The app view and the part do not change
func nice_picture() -> String:
	if nice_say == null:
		return ""
	var free_part: bool = m.bld != null and m.bld.part != null and m.bld.part.on
	if not free_part or not Part.available() or Part.replay(m.S.part)["mesh"] == null:
		nice_say.text = "NOT NOW: there is no part to picture. Draw a shape and press Pull it up, then press Nice picture"
		return ""
	nice_say.text = "Drawing the nice picture..."
	var r: Dictionary = await NiceRender.save(m, m.S.part, UserPaths.w("res://exports"), SectionLook.live_cut(m))
	nice_say.text = String(r["text"])
	return String(r["path"]) if bool(r["ok"]) else ""
