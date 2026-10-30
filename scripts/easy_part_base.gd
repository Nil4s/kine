extends Node
## EASY PART BASE: what every Easy Part file reads: the controls and fields of the screen (made by build, scripts/easy_part.gd), the
## constants, and the small shared helpers (the status sentence, the undo step round a press, the record, numbers in plain words).
## Easy Part is ONE Node made of a chain of files, each extending the one below it:
##   easy_part.gd (class_name EasyPart) > easy_part_pull.gd > easy_part_repeat.gd > easy_part_stick.gd > easy_part_layout.gd > easy_part_base.gd > Node
## A file calls what is in it or below it. The few calls that go UP the chain are declared at the end of this file with an empty body
## (UP THE CHAIN); the file named beside each one makes it, and that one is the one that runs.

const PW := 318.0
const CHIP_TEXT := {"sword": "Blade"}   # template chips shown before anything is chosen (plain words)
const ROUND_BUDGET_US := 300000   # EROUND: the Round press stops trying edges after this (usec) and keeps the best found
const MAKE_H := 76.0
const REP_WORDS := {"count": ["Fewer", "More"], "gap": ["Closer", "Further apart"]}   # the Repeat it sliders' ends
const STICK_OPS := [["join", "Join", "Make the two pieces one solid"], ["cut", "Cut away", "Cut the second piece out of the first"], ["intersect", "Keep the overlap", "Keep only the part where the two pieces overlap"]]
const SCREW_DS := [3, 4, 5, 6]         # NSCREW2: the Parts category's screw sizes (M3..M6, columns of the grid)
const SCREW_LENS := [10, 16, 20, 30]   # NSCREW2: the screw lengths in mm (rows of the grid)
const BRACKET_CHIPS := [["L", "L-bracket", 1, "An L: a foot and an upright, two screw holes"], ["T", "T-bracket", 2, "A T: a bar on a stem, two screw holes"], ["corner", "Corner brace", 3, "An L with a gusset in the corner, two screw holes"]]   # FRIDAY 73: the Brackets page chips (key, words, kind 1 / 2 / 3)
const LIB_CATS := ["Screws", "Nuts", "Washers", "Gears", "Hinges", "Bearings", "Springs", "Handles", "Wheels", "Brackets", "Clips and feet", "Boards"]   # NLIBPAGE: the Parts library page, in this order
const LIB_READY := ["Screws", "Gears", "Bearings", "Brackets", "Clips and feet", "Handles", "Wheels", "Boards"]   # NLIBPAGE: the categories with parts today; the others say coming soon
const CLIP_KINDS := ["foot", "clip", "slot"]   # P075: the Clips and feet chips: a rubber foot, a cable clip, a zip-tie slot (template kinds in part_templates.gd)
const COLOUR_PRESETS := ["Glass", "Metal"]   # the two material chips after the five colour chips
const WEIGHT_CHIPS := [["wood", "wood"], ["steel", "metal"], ["plastic", "plastic"]]   # p057: the weight chips after Wood (PartWeapon.DENSITY key, the word on the chip)
const WOOD_COLOUR := Color("#9a6b3f")   # the Wood chip (after Glass and Metal): a wood brown, red > green > blue
const TILT_DEG := 20.0           # Tilt it: the lean of the newest solid (degrees, sideways about its middle)
const HOLLOW_MM := 3.0           # Hollow inside: the wall the shell starts with (the Wall slider moves it: 1 to 10 mm)
const LID_MM := 5.0             # Hollow with a lid (nlid): the top slice that comes off as the lid (a solid plate, the box's footprint)
const DRAFT_DEG := 2.0           # Draft angle (p021): the side walls of a pulled-up solid lean this many degrees, so the part comes out of a mould
const LIP_RIDGE_MM := 0.5            # Snap-fit lip (nsnaplip): the ridge sticks out of the lip by this much, and the box wall has a groove this deep
const LID_LIP_MM := 3.0         # the lid's lip: how far it goes down inside the box (1 mm wide ring, 0.2 mm gap to the wall)
const THROTTLE_MS := 100
const CLIP_MM := 6.0             # FBOWL2: a spun curve that dips past the middle line by less than this (a spline overshoot) is clipped onto it
const NARROW_W := 1200.0         # FMOBILE: a window narrower than this (1024 x 600) shrinks the bar's buttons and the title
const SKY := Color("#73BFFF")
const AMBER := Color("#FFC933")
const MAKES := [
	["draw", "Draw shape", "part_rectangle", "Drag on the grid to draw a box or a round shape"],
	["pull", "Pull it up", "part_extrude", "Make the newest shape into a solid, then say how far"],
	["spin", "Spin it round", "part_revolve", "Turn the newest shape round the middle line into a solid"],
	["round", "Round the edges", "part_fillet", "Soften the sharp edges"],
	["hole", "Cut a hole", "part_circle", "Cut a round hole through the middle, or hollow the solid out (Hollow inside)"],
	["mirror", "Mirror that", "part_mirror", "Add a mirror copy on the other side of the middle line"],
	["curve", "Curvy line", "part_spline", "Drag a wobbly loop on the grid. Drag back to the start to close it"],
	["blend", "Blend two shapes", "part_loft", "Blend the last two shapes into one solid that runs from one to the other"],
	["split", "Cut in two", "part_split", "Cut the solid in two across its middle. Drag the slider to move the cut"],
	["colour", "Colour", "part_appearance", "Pick a colour for the solid, or Glass or Metal"],
	["repeat", "Repeat it", "part_pattern", "Copy the newest solid in a row, or round in a ring. Then move the sliders"],
	["stick", "Stick together", "part_combine", "Click two solid pieces in the view, then pick Join, Cut away or Keep the overlap"]]
const ROUND_FILTERS := [["all", "All edges", "part_filter_all", "Round every edge of the solid"], ["outside", "Only the outside", "part_filter_outside", "Round only the edges on the outside, not the inside of a hole or a cup"], ["top", "Only the top", "part_filter_top", "Round only the top edges of the solid"]]   # NROUNDFILTER
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]

var pu: PartUI
var m: Node
var bar: PanelContainer
var title_l: Label
var name_edit: LineEdit   # FNAMECHANGE: the name box that a click on the title opens (hidden otherwise)
var _renaming := false
var undo_btn: Button
var redo_btn: Button
var dup_btn: Button            # FDUP: the top bar's Duplicate (a second copy of the whole part beside it)
var fix_btn: Button            # NFIXIT: the top bar's Fix it (one press = one fix: a failed step, a wall with no thickness, a loose piece)
var use_scene_btn: Button
var size_l: Label              # FMEASURE: "18 x 6 x 2 cm" (wide x deep x high) under the part, plain words, while a solid is there
var whole_l: Label             # "Whole sword: N cm": the shape's biggest size, under the sliders (the blade slider is not the whole length)
var easy_btn: Button
var expert_btn: Button
var bar_home: Button = null   # the bar's Home button (narrowed at 1024 wide, see layout)
var bar_row: HBoxContainer   # the bar's row: Part's "What to build" moves in here while Easy Part is on (part_ui._place_reopen)
var make_box: HBoxContainer
var make_btns := {}
var hint: PanelContainer
var hint_l: Label
var shape_box: PanelContainer
var shape_btns := {}
var repeat_box: PanelContainer   # Repeat it: Row / Ring and the How many and Gap sliders (for the last Repeat it step, rep_id)
var rep_btns := {}
var tilt_box: PanelContainer     # Tilt it: one chip under the newest solid (a Spin or a Pull), leans it 20 degrees once
var steps_box: PanelContainer    # NSTEPLIST: the step list under the panel, in plain words; a click on a step reopens it (see _steps_sync)
var flat_box: PanelContainer    # p113: the printing box under the step list (Lay it flat, Show overhangs); see _printing_box
var steps_vb: VBoxContainer
var _steps_sig := ""
var scrub_sl: HSlider            # p089scrubthehi: Scrub the history, a view of the part after the first N steps (no undo step; see _scrub_to)
var scrub_lbl: Label
var tilt_btn: Button
var swing_btn: Button            # p123driveit: Swing it (Drive it), the chip in the Tilt it panel: the newest piece swings on a hinge step
var draft_btn: Button            # p021: Draft angle, the chip beside Tilt it (the side walls lean DRAFT_DEG for a mould)
var pull_along_btn: Button       # P026: Pull along, the same box as Tilt it: shows after a curve or a shape is drawn (the newest step is a sketch)
var parts_btn: Button            # NSCREW2: the Parts category chip (opens the screw grid under the template chips)
var board_box: PanelContainer     # p078makeacasef: the Boards page's two chips (Raspberry Pi, Arduino Uno): shown while Boards is open or a case is the part
var board_btns := {}              # p078makeacasef: 1 / 2 -> the board chip
var screw_box: PanelContainer    # NSCREW2: the screw grid: sixteen size chips, shown while Parts is open or a screw is the part
var wheel_box: PanelContainer      # P072: the Wheels page: the Wheel and Castor chips (axle hole), shown while Parts is open on Wheels
var wheel_btns := {}               # P072: "wheel" / "castor" -> its chip
var screw_btns := {}             # NSCREW2: "d_L" -> the size chip (M<d> x <L>)
var clip_box: PanelContainer     # P075: the Clips and feet chips (rubber foot, cable clip, zip-tie slot), shown while that category is open
var clip_btns := {}              # P075: kind -> its chip
var screw_words: Label           # the grid's one-line instruction: hidden while the library page is open (the page and the status line say it)
var bracket_box: PanelContainer   # FRIDAY 73: the bracket chips (L-bracket, T-bracket, Corner brace), shown while Brackets is open or a bracket is the part
var bracket_btns := {}
var nw_btn: Button               # NNUTWASHER: "Add its nut and washer" (in the screw grid): the screw on the floor takes its nut and washer, one click
var boss_btn: Button             # FRIDAY 37 BOSS CHIP: "Add its boss" (in the screw grid): a round post beside the screw, sized to it, one click
var parts_open := false          # NSCREW2: the Parts category is open (the grid shows even with no screw on the floor)
var lib_box: PanelContainer      # NLIBPAGE: the Parts library page: ten category chips, under the template chips while Parts is open
var lib_btns := {}               # NLIBPAGE: category -> its chip
var lib_soon: Label              # NLIBPAGE: "Coming soon" line for an empty category (names the next step)
var handle_box: PanelContainer    # P071 HANDLES: the Handles grid (three kinds x three sizes), under the library page while Handles is open or a handle is the part
var handle_btns := {}            # P071 HANDLES: "kind_size" -> its size chip
var handle_words: Label          # P071 HANDLES: the grid's one-line instruction: hidden while the library page is open (the page says it), so the grid fits
var lib_cat := ""                # NLIBPAGE: the category open on the page ("" = none); Screws opens when Parts opens
var explode_box: PanelContainer  # EXPLODE (p103): the Pull apart slider, shown while the part has two or more pieces (view only, no step)
var explode_slider: HSlider
var explode_label: Label
const EXPLODE_MAX_MM := 100.0   # the Pull apart slider: how far a piece can be pulled from the middle (mm)
var bear_box: PanelContainer      # P069 BEARINGS: the bearing chips (608, 625, 688) and the seat button: shown with the Bearings page or a bearing / seat on the floor
var bear_btns := {}              # P069 BEARINGS: "608" / "625" / "688" -> its chip
var seat_btn: Button             # P069 BEARINGS: "Make a seat for it": cuts the seat for the bearing on the floor
var stick_box: PanelContainer    # Stick together: Join / Cut away / Keep the overlap, shown once two pieces are picked
var stick_btns := {}
var smooth_btn: Button    # P035: Smooth the joints, in the stick box after a Join (the three Join / Cut / Keep buttons hide then)
var joint_btns: Array = []   # p121: This turns here / This slides here, in the stick box with two pieces picked (hidden after a Join)
var stick_picks: Array = []      # the body indices clicked in the view (the first = the target, the second = the tool)
var stick_tris := {}             # body index -> its triangles, for the glow of a picked piece
var stick_edges := {}            # body index -> its crease edges (pairs of points): the glow's outline, no triangle diagonals
const EDGE_PX := 10.0            # NROUNDDRAG: a press this close (screen px) to a solid's edge takes it in hand
const EDGE_MAX_MM := 10.0        # NROUNDDRAG: the radius a drag can reach (mm)
const PICK_PX := 12.0            # a click this close (screen px) to a piece picks it when the ray hits nothing
var rep_id := ""                 # the last Repeat it step's feature id ("" = none)
var rep_rows := []               # the two slider rows of the Repeat it box (see _make_row)
var hole_box: PanelContainer     # Cut a hole: the Through / Hollow inside chips, under the MAKE row, after a Cut a hole press (see _hole_on)
var hole_btns := {}
var snap_btn: Button            # Snap-fit lip (nsnaplip): an on/off chip under Hollow with a lid (the lid gets a ridge, the box a groove)
var hole_base: Dictionary = {}   # the record before the last Cut a hole press: each chip rebuilds the hole from it ({} = no hole chips)
var hole_id := ""                # the feature id of the last hole step (the hole's sketch, or the hollow's shell): its slider's step
var hole_mode := "through"       # "through" | "hollow": the chip that is on
var wall_btn: Button             # Thicker wall (p022shellwalls): under Hollow inside; the next side-wall click makes that wall thicker
var wall_pick := false           # true while Thicker wall waits for the wall click (a press on a face then goes to _wall_press)
var split_box: PanelContainer   # ECUT2: Cut in two's keep chips (both halves / the lower half / the upper half), after a Cut in two press (see _split_on)
var split_btns := {}
var round_box: PanelContainer   # NROUNDFILTER: the All edges / Only the outside / Only the top chips, beside Round the edges (see _round_box)
var round_btns := {}
var round_mode := "all"          # the filter the next Round the edges press uses: "all" | "outside" | "top"

var split_id := ""              # the feature id of the last Cut in two step: the keep chips edit its "keep" field
var colour_box: PanelContainer   # Colour: the five colour chips and Glass / Metal, under the MAKE row (armed "colour")
var weight_btns := {}   # p057: the weight chips by WEIGHT_CHIPS key (read by _weight_sync)
var weight_kg_by := {}   # p057: the weights of the Part as last read ({} = no solid)
var weight_key := -1   # p057: the features hash the weights were read from (read again only when the Part changes)
var panel: PanelContainer
var panel_vb: VBoxContainer   # the panel's column: it scrolls inside the panel when the window is short (1280 x 720)
var panel_title: Label
var chips := {}
var empty_chip: Button   # "Empty": start from nothing (not in chips: those are the templates)
var rows_vb: VBoxContainer
var rows := []                 # [{"key", "slider", "pill", "kind": "tpl" | "tweak", "def": row dict}]
var give_btn: Button
var export_btn: Button          # FEXPORT: Export on the Easy Part bar (the export dialog, the free part picked)
var back_btn: Button
var use_btn: Button
var status: PanelContainer
var status_l: Label
var dots: Control
var armed := ""                # "draw" while the next drag draws a shape
var shape := "box"
var sides := 6                  # NPOLY2: the Sides slider (3 to 12): a regular prism of this many sides (shape "poly"); Hex is the 6 of it
var msg := ""                  # the sentence of the last press, until the next one
var taper_tw := {}             # FPLANTER: the Taper slider of the last Pull it up (its extrude's id; shown while that pull is the newest step)
var taper_row: Dictionary = {}  # FPLANTER: the Taper slider's row ({} = none); kept out of rows so rows[-1] is still How far
var twist_tw := {}            # P024: the Twist slider of the last Pull it up (its extrude's id; shown with the Taper slider while that pull is the newest step)
var twist_row: Dictionary = {}  # P024: the Twist slider's row ({} = none); kept out of rows like the Taper row
var tweak := {}                # the last step's own slider: {"id", "ent", "field", "label", "unit", "lo", "hi", "step", "scale"}
var _pending := {}
var _draft_px0 := Vector2.ZERO   # the draft's raw pointer pixels, first press and last move (the sides are read from these when the grid folds them)
var _draft_px1 := Vector2.ZERO
var _dirty := false
var _last_ms := 0
var _drag := {}                # an amber dot in hand: {"k", "mouse", "val", "dir", "pxmm", "gain"}
var _draft := {}               # a shape being drawn: {"a": Vector2 mm, "b": Vector2 mm}
var _edit_n := -1
var _edit_before := ""
var _sig := ""
var _rows_sig := ""
var _hover := ""
var _was := false
var _compact := false
var _cl := Rect2()              # the clear view's rectangle of the last layout (free_rect)
const FRAME_FILL := 0.55        # EFRAME: the part's box fills this share of the free view (its bigger side)
const FRAME_EASE := 0.3         # seconds the camera eases to a new framing (never a jump)
const FRAME_CHANGE := 0.25      # the box's diagonal must change this much to frame again (a small nudge moves nothing)
var _fr_ref := AABB()           # the bounds the camera last framed (or the bounds on entry)
var _fr_has := false
var _fr_lk := ""               # EPANELVIEW: the left boxes shown when the camera last framed (see _frame_step)
var _near_saved := -1.0         # the camera's near plane before Easy Part (put back when it is left)
const FRAME_NEAR := 0.004
const GRID_TILE_FILL := 0.95         # the empty part's grid tile fills this share of the free view (a flat square seen at a slant is narrow)
const GRID_TILE := AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 0.0, 1.0))   # the 1 m grid square an empty part stands on (metres)
var _bar_press = null           # a draw press that began on the top bar (Vector2), or null: a drag starts the sketch there, a click is the button's
var _press_btn: BaseButton = null # the button under that press (its click when the press is not a drag)
var _off_tried := AABB()         # the box the D2 off-screen check last framed (see _frame_step)
var _ease := {}                 # the camera ease in progress: {"t0", "d0", "t1", "d1", "s"}
var del_btn: Button              # FDELETE: Remove, on the bar while a piece is picked (the click on a piece; see _pick_at)
var del_on := false              # FDELETE: a piece is picked (its step id in del_id, the features count it was picked at in del_n)
var del_id := ""
var del_n := -1
var del_pt := Vector3.ZERO       # the point clicked on the piece (metres, the same units as the faces)
var del_tris := PackedVector3Array()   # the picked piece's triangles: its glow
var _edge := {}                  # NROUNDDRAG: an edge in hand (a press within EDGE_PX of a solid's edge, dragged outward): {"e", "press", "out", "pxmm", "r"}
var edge_num: Label             # NROUNDDRAG: the radius in mm, beside the cursor while an edge is dragged (hidden otherwise)
var _pick_p := Vector2(-1, -1)   # a left press on the grid with nothing armed: a click (no drag) picks the piece under it on release
var flushes := 0                # rebuilds made by sliders and dots (the tests count them against the clock)
var auto_path := "user://nautosave/part.json"   # NAUTOSAVE: the part as it is after every step (Part record, plain JSON); the next start offers it back (a test sets its own)
var restore_btn: Button         # NAUTOSAVE: "Bring back your part", on the bar while the part is empty and a saved part is there
var _auto_json := ""           # NAUTOSAVE: the last text written to auto_path (a step is written once)


# ---------------------------------------------------------------- the state

func active() -> bool:
	return m != null and pu != null and pu.shows() and pu.easy


func _rec() -> Dictionary:
	return m.S.part


func _tpl() -> String:
	return String(_rec().get("easy", {}).get("t", ""))


func _nm() -> String:
	var t := _tpl()
	return String(PartTemplates.T[t]["title"]).to_lower() if t != "" else "part"


## an error the Part tools give, in words a child reads: sketch -> shape, body -> solid, and anything still technical -> a plain line
static func _plain(e: String) -> String:
	var t := e.replace("its sketch is gone", "its shape is gone").replace("sketch", "shape").replace("body", "solid").replace("feature", "step").replace("extrude", "pull").replace("fillet", "round").replace("loft", "blend").replace("boolean", "join").replace("profile", "shape")
	var jargon := RegEx.new()
	jargon.compile("(?i)\\b(kernel|manifold|mesh|primitive|kcad|revolve|shell|plane|offset|dll|cad|wire|f\\d{1,2})\\w*")
	if jargon.search(t) != null:
		return "That step cannot be made here: Undo takes the last step back"
	return t


func _say(t: String) -> void:
	msg = t


# ---------------------------------------------------------------- undo steps

func _begin(label: String) -> void:
	m._step_hint = label
	m._push_undo()
	_edit_n = m.undo.size()
	_edit_before = JSON.stringify(_rec())


## the step ends; a step that changed nothing is taken back out
func _end() -> void:
	if _edit_n >= 0 and m.undo.size() == _edit_n and JSON.stringify(_rec()) == _edit_before:
		m._drop_undo()
	_edit_n = -1


## EREPEATUP: the size of the body along the copy direction (a row: its width, Up: its height, Forward: its depth), in mm
func _span(f: Dictionary) -> float:
	var ax := String(f.get("dir", "x"))
	return float(f.get("h" if ax == "y" else ("d" if ax == "z" else "w"), f.get("w", 10.0)))


func _flush_if_dirty() -> void:
	if _dirty:
		_flush()


func _flush() -> void:
	flushes += 1
	_dirty = false
	_last_ms = Time.get_ticks_msec()
	if _rec().is_empty():   # no part (the {} record): a slider has nothing to write to; the pending numbers go
		_pending = {}
		return
	if not _pending.is_empty():
		PartTemplates.retemplate(_rec(), _pending)
		_pending = {}
	var note := PartTemplates.fit_rounds(_rec())   # a new size (or the How round slider) can leave a round too big for its edges: it shrinks, and says so
	if note != "":
		_say(note)
	pu.sync()
	m.part_weapon_changed(_rec())   # a held Part weapon takes the new numbers and shape
	_values_sync()


func _fmt(v: float, unit: String) -> String:
	if unit == "deg":
		return "%d degrees" % int(roundf(v))
	if unit == "copies":
		return "%d copies" % int(roundf(v))
	if unit == "teeth":   # NGEAR
		return "%d teeth" % int(roundf(v))
	if unit == "size":   # NGEAR: the module 1 / 2 / 3 as Small / Medium / Big teeth
		return ["Small", "Medium", "Big"][clampi(int(roundf(v)) - 1, 0, 2)] + " teeth"
	if unit == "mm":
		return "%s mm" % str(snappedf(v, 0.1))
	return "%s cm" % str(snappedf(v, 0.1))


func _pill_text(row: Dictionary, v: float) -> void:
	(row["pill"] as Label).text = _fmt(v, String(row["unit"]))


func _knob() -> ImageTexture:
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	for y in 24:
		for x in 24:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(12, 12))
			img.set_pixel(x, y, Color(1, 0.79, 0.2, clampf(12.0 - d, 0.0, 1.0)) if d > 6.5 else Color(1, 0.79, 0.2, clampf(12.0 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## FROOM: the How far slider on a building project reaches 3 m (a wall is 2 m or more); the other projects keep 40 cm
func _pull_hi() -> float:
	return 300.0 if m != null and m.S != null and m.S.kind == "building" else 40.0


## EMPTY: a part with no steps (one undo step); Draw shape on the grid starts it
## FHELP3: Easy is already on: the press says what the screen is and what to press, and the button stays lit
func _easy_on() -> void:
	easy_btn.set_pressed_no_signal(true)
	_say("You are in Easy: big buttons and sliders. Press Expert for every tool and exact numbers")


func _arm_words(a: String) -> String:
	match a:
		"stick":
			if stick_picks.size() == 0:
				return "Click the first solid piece in the view"
			if stick_picks.size() == 1:
				return "Now click the other piece"
			return "Pick Join, Cut away or Keep the overlap"
		"draw":
			return "Drag on the grid to draw a shape"
		"curve":
			return "Drag a wobbly loop on the grid. Drag back to the start to close it"
		"colour":
			return "Pick a colour below, or Glass or Metal"
	return ""


func _last_error(rec: Dictionary, fid: String) -> String:
	return String(pu.replay_full(rec)["errors"].get(fid, ""))


## FROOM: the newest sketch step of a record ({} when none)
func _last_sketch(rec: Dictionary) -> Dictionary:
	var out := {}
	for f in rec.get("features", []):
		if f["t"] == "sketch":
			out = f
	return out


## the Part base plane ("front" | "top" | "right") a sketch's plane id sits on: an offset plane's base is its "from"
func _base_plane(rec: Dictionary, pid: String) -> String:
	if pid in Part.PLANES:
		return pid
	var pf := Part.feature(rec, pid)
	return String(pf.get("from", "front")) if String(pf.get("t", "")) == "plane" else "front"


func _cm1(v: float) -> String:
	return str(roundi(v)) if absf(v - roundf(v)) < 0.05 else str(v)


## a length in mm for the words: 0 -> "0", 2.5 -> "2.5"
static func _mm_words(x: float) -> String:
	return ("%.1f" % x).trim_suffix(".0")


## the pieces of the replay's mesh that do not touch (vertices welded at 0.01 mm, then joined by triangles), counted once per replay mesh
var _lump_mesh: Object = null   # the mesh it was counted on (the replay result dictionary is reused; each replay makes a new mesh)
var _lump_n := 1


func _lumps(r: Dictionary) -> int:
	var mesh: ArrayMesh = r.get("mesh")
	if is_same(mesh, _lump_mesh):
		return _lump_n
	_lump_mesh = mesh
	_lump_n = 1
	if mesh == null or mesh.get_surface_count() == 0:
		return _lump_n
	var weld := {}
	var parent := PackedInt32Array()
	var wpos := PackedVector3Array()   # FLAMP5: the welded position of each vertex id (for the touch test below)
	var tris: Array = []               # FLAMP5: each triangle as its three welded ids
	var find := func(i: int) -> int:
		while parent[i] != i:
			parent[i] = parent[parent[i]]
			i = parent[i]
		return i
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var ids := PackedInt32Array()
		for v in vs:
			var key := Vector3i(roundi(v.x * 1e5), roundi(v.y * 1e5), roundi(v.z * 1e5))
			if not weld.has(key):
				weld[key] = parent.size()
				parent.append(parent.size())
				wpos.append(v)
			ids.append(int(weld[key]))
		var tri := idx.size() if idx.size() > 0 else vs.size()
		for t in range(0, tri - 2, 3):
			var a: int = ids[idx[t] if idx.size() > 0 else t]
			var b1: int = ids[idx[t + 1] if idx.size() > 0 else t + 1]
			var b2: int = ids[idx[t + 2] if idx.size() > 0 else t + 2]
			tris.append([a, b1, b2])
			for b in [b1, b2]:
				var ra: int = find.call(a)
				var rb: int = find.call(b)
				if ra != rb:
					parent[ra] = rb
	# FLAMP5: a shape pulled up off a face of a solid is a separate shell that sits ON the face: the two meet on a face patch,
	# with no vertex shared, so the welding above sees two pieces. A corner of one shell lying on a triangle of the other joins them.
	var merged := true
	while merged and tris.size() > 0:
		merged = false
		var roots := {}
		for i in parent.size():
			roots[find.call(i)] = true
		if roots.size() < 2:
			break
		var groups := {}   # root -> {"v": vertex ids, "t": triangle indices, "bb": AABB}
		for i in parent.size():
			var rr: int = find.call(i)
			if not groups.has(rr):
				groups[rr] = {"v": PackedInt32Array(), "t": PackedInt32Array(), "bb": AABB(wpos[i], Vector3.ZERO)}
			groups[rr]["v"].append(i)
			groups[rr]["bb"] = (groups[rr]["bb"] as AABB).expand(wpos[i])
		for ti in tris.size():
			var rt: int = find.call(int(tris[ti][0]))
			groups[rt]["t"].append(ti)
		var keys := groups.keys()
		for x in keys.size():
			for y in range(x + 1, keys.size()):
				var ga: Dictionary = groups[keys[x]]
				var gb: Dictionary = groups[keys[y]]
				if not (ga["bb"] as AABB).grow(1e-4).intersects(gb["bb"] as AABB):
					continue
				if Part.touch_patch(_group_pts(ga, wpos), _group_tri_pts(gb, wpos, tris), gb["bb"]) or Part.touch_patch(_group_pts(gb, wpos), _group_tri_pts(ga, wpos, tris), ga["bb"]):
					parent[find.call(int(keys[x]))] = find.call(int(keys[y]))
					merged = true
					break
			if merged:
				break
	var roots := {}
	for i in parent.size():
		roots[find.call(i)] = true
	_lump_n = maxi(roots.size(), 1)
	return _lump_n


## FLAMP5: the points of a welded group, and the flat triangle points of the group's triangles (see Part.touch_patch)
func _group_pts(g: Dictionary, wpos: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for vi in g["v"]:
		out.append(wpos[vi])
	return out


func _group_tri_pts(g: Dictionary, wpos: PackedVector3Array, tris: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for ti in g["t"]:
		var tr: Array = tris[ti]
		out.append(wpos[tr[0]])
		out.append(wpos[tr[1]])
		out.append(wpos[tr[2]])
	return out


static func _fmt_cm(mm_v: float) -> String:
	return "%s cm" % _plain_num(mm_v / 10.0)


## NSTEPLIST: a number in plain words: 3 (not 3.0), 2.5
static func _plain_num(v: float) -> String:
	var x := snappedf(v, 0.1)
	return str(int(x)) if x == floorf(x) else "%.1f" % x


## UP THE CHAIN: called from a file below the one that makes it (named on each line). These bodies never run: EasyPart is always
## the whole chain, and the file named makes the real one.

func _hole_sync() -> void:   # made in easy_part_pull.gd (read by easy_part_layout.gd)
	pass


func _make_row(label: String, lo: float, hi: float, step: float, words: Array, kind: String, key: String, unit: String, into: Control = null, raw := false) -> Dictionary:   # made in easy_part.gd (read by easy_part_repeat.gd)
	return {}


func _rows_sync() -> void:   # made in easy_part.gd (read by easy_part_layout.gd, easy_part_stick.gd, easy_part_pull.gd)
	pass


func _values_sync() -> void:   # made in easy_part.gd (read by easy_part_base.gd, easy_part_layout.gd, easy_part_stick.gd, easy_part_repeat.gd, easy_part_pull.gd)
	pass


func _chips_sync() -> void:   # made in easy_part.gd (read by easy_part_layout.gd)
	pass


func _hole(rec: Dictionary) -> String:   # made in easy_part.gd (read by easy_part_pull.gd)
	return ""


func _steps_sync() -> void:   # made in easy_part.gd (read by easy_part_layout.gd)
	pass
