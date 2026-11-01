class_name EasySearch
## s097 (Friday plan 97): ONE search box for any Easy Part action. Ctrl+K (or the search icon on the Easy Part bar) opens the S box
## (scripts/command_search.gd); typing "hole", "round", "screw", "m3", "export", "fix" lists the Easy Part buttons by name and by
## the words people use for them. Arrow keys pick, Enter runs, Esc closes (the box gives the keyboard back to the view).
## A row runs EXACTLY the presses a click on that button runs (the button's own `pressed` signal, so the same undo step and the
## same panel opens); a chip that sits inside a panel ("M3 screw hole" is a chip of Cut a hole) first presses the button that opens
## that panel, but only when the chip is not already on the screen. Rows are static; the buttons are looked up when a row runs.
## Easy Part must be open (else the words say how to open it).
## Row ids all start with "easy_" (command_search.gd ranks an Easy Part row first among equal name hits).


## [label, words it also answers to, [button refs from the outside in]]. A ref is "kind:key": make:, hole:, hpat:, round:, lib:, screw:, bar:, parts:, fill:
const ACTIONS := [
	["Cut a hole", "hole holes drill bore through hollow pocket", ["make:hole"]],
	["Round the edges", "round fillet bevel soften smooth corner edge rounded", ["make:round"]],
	["Draw shape", "sketch draw box rectangle circle outline", ["make:draw"]],
	["Pull it up", "extrude raise height solid push pull", ["make:pull"]],
	["Spin it round", "revolve lathe turn spin", ["make:spin"]],
	["Mirror that", "mirror flip symmetry copy other side", ["make:mirror"]],
	["Curvy line", "curve spline wobbly freehand", ["make:curve"]],
	["Blend two shapes", "loft blend morph", ["make:blend"]],
	["Cut in two", "split slice section half", ["make:split"]],
	["Colour", "color paint glass metal", ["make:colour"]],
	["Repeat it", "repeat pattern array copy row ring", ["make:repeat"]],
	["Stick together", "join combine boolean union glue merge", ["make:stick"]],
	["Undo", "undo back take back", ["bar:undo"]],
	["Redo", "redo again put back", ["bar:redo"]],
	["Duplicate", "duplicate copy clone second", ["bar:dup"]],
	["Fix it", "fix repair broken wrong problem heal", ["bar:fix"]],
	["Export", "export save stl 3mf obj glb print printer file", ["bar:export"]],
	["Save and use in a scene", "save my parts scene prop use", ["bar:scene"]],
	["Give to a character", "give hold weapon character hand", ["bar:give"]],
	["Through hole", "hole through drill round straight", ["make:hole", "hole:through"]],
	["Hollow inside", "hollow shell wall box open top hole", ["make:hole", "hole:hollow"]],
	["Hollow with a lid", "hollow lid box cover hole", ["make:hole", "hole:lid"]],
	["M3 screw hole", "m3 screw hole clearance counterbore bolt 3.4", ["make:hole", "hole:screw3"]],
	["M4 screw hole", "m4 screw hole clearance counterbore bolt 4.5", ["make:hole", "hole:screw4"]],
	["M5 screw hole", "m5 screw hole clearance counterbore bolt 5.5", ["make:hole", "hole:screw5"]],
	["M6 screw hole", "m6 screw hole clearance counterbore bolt 6.6", ["make:hole", "hole:screw6"]],
	["Magnet pocket", "magnet hole pocket round", ["make:hole", "hole:magnet"]],
	["Make it lighter", "lighter lightweight holes weight material save", ["make:hole", "hole:lighter"]],
	["Holes: Row", "hole holes row line copy pattern", ["make:hole", "hole:through", "hpat:row"]],
	["Holes: Around", "hole holes around circle ring copy pattern", ["make:hole", "hole:through", "hpat:around"]],
	["Holes: Grid", "hole holes grid rows columns copy pattern", ["make:hole", "hole:through", "hpat:grid"]],
	["Fill the face with holes", "hole holes fill face sheet perforated grille", ["make:hole", "fill:"]],
	["Round all edges", "round fillet every edge all", ["make:round", "round:all"]],
	["Round only the outside", "round fillet outside outer edges", ["make:round", "round:outside"]],
	["Round only the top", "round fillet top edges", ["make:round", "round:top"]],
	["Parts library", "parts library screws nuts gears bearings hinges", ["parts:"]],
]


static func rows(m: Node) -> Array:
	var out := []
	for a in ACTIONS:
		out.append(_row(m, "easy_act_" + String(a[0]).to_lower().replace(" ", "_").replace(":", ""), "Easy Part: " + String(a[0]),
			String(a[1]), a[2], _desc(a)))
	for cat in EasyPart.LIB_CATS:
		out.append(_row(m, "easy_lib_" + String(cat).to_lower().replace(" ", "_"), "Easy Part: Parts: " + String(cat),
			"parts library " + String(cat).to_lower() + " category", ["parts:", "lib:" + String(cat)], "open the %s page of the Parts library" % cat))
	for d in EasyPart.SCREW_DS:
		for L in EasyPart.SCREW_LENS:
			out.append(_row(m, "easy_screw_%d_%d" % [d, L], "Easy Part: Screw M%d x %d mm" % [d, L],
				"easy part screw bolt nut socket head iso parts m%d %d" % [d, L], ["parts:", "lib:Screws", "screw:%d_%d" % [d, L]],
				"a socket head screw M%d, %d mm long, dropped on the floor (Parts > Screws)" % [d, L]))
	return out


static func _desc(a: Array) -> String:
	return "the same press as the %s button on Easy Part (one click, the same undo step)" % String(a[0])


static func _row(m: Node, id: String, label: String, also: String, refs: Array, desc: String) -> Dictionary:
	return {"id": id, "name": label, "keys": "", "run": Callable(EasySearch, "go").bind(m, refs), "also": "easy part " + also, "edits": true, "desc": desc}


## the Easy Part panel owner, or null when Easy Part is not open
static func _ep(m: Node):
	var ep = m.bld.part.ep if m.bld != null and m.bld.part != null else null
	return ep if ep != null and ep.active() else null


## the button a ref names (null when the panel has no such button)
static func button(ep, ref: String) -> Button:
	var p := ref.split(":")
	var key: String = p[1] if p.size() > 1 else ""
	match p[0]:
		"make":
			return ep.make_btns.get(key, null)
		"hole":
			return ep.hole_btns.get(key, null)
		"hpat":
			return ep.hpat_btns.get(key, null)
		"round":
			return ep.round_btns.get(key, null)
		"lib":
			return ep.lib_btns.get(key, null)
		"screw":
			return ep.screw_btns.get(key, null)
		"parts":
			return ep.parts_btn
		"fill":
			return ep.fill_btn
		"bar":
			var bars := {"undo": ep.undo_btn, "redo": ep.redo_btn, "dup": ep.dup_btn, "fix": ep.fix_btn, "export": ep.export_btn, "scene": ep.use_scene_btn, "give": ep.give_btn}
			return bars.get(key, null)
	return null


## the row's presses. The chain's last button is what the row is for; the first ref from the end that is on the screen is where the
## presses start (a chip already showing is pressed alone), else the whole chain runs from the outside button in. A press is the
## button's own `pressed` signal: what a click emits (the button's look is the panel's own sync, as after a click).
static func go(m: Node, refs: Array) -> void:
	var ep = _ep(m)
	if ep == null:
		m._say("Easy Part is not open: go to BUILD, press Easy, then search again")
		return
	var start := 0
	for i in range(refs.size() - 1, -1, -1):
		var b := button(ep, String(refs[i]))
		if b != null and b.is_visible_in_tree():
			start = i
			break
	for i in range(start, refs.size()):
		var b2 := button(ep, String(refs[i]))
		if b2 == null:
			m._say("That button is not on Easy Part")
			return
		if i > start and not b2.is_visible_in_tree():
			return   # the press before it said why (for example "Nothing solid to cut a hole in yet")
		if i == 0 and String(refs[0]) == "parts:" and ep.parts_open and refs.size() > 1:
			continue   # Parts is open already: pressing it again would shut it
		b2.pressed.emit()
		if i < refs.size() - 1:
			await m.get_tree().process_frame


## the bar's search icon: opens the same box as Ctrl+K (a small square icon button; the title label gives up the width)
static func bar_button(m: Node) -> Button:
	var b := Button.new()
	b.name = "easypart_search"
	b.icon = Icons.sized("search", 22)
	b.expand_icon = false
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Search every action: type hole, round or screw"
	b.custom_minimum_size = Vector2(44, m.TOP_H - 12)
	b.pressed.connect(func(): m.ui_cmd.open())
	return b


## the icon shows only where the bar has room: the bar row without it must be at least its width short of the window (the 1280 wide row is
## tight, Expert must stay on the screen). Called from layout(); Ctrl+K and the S box work with or without the icon.
static func fit(ep) -> void:
	var b := ep.bar_row.find_child("easypart_search", false, false) as Button
	if b == null:
		return
	b.visible = false
	var w0: float = ep.bar_row.get_combined_minimum_size().x
	b.visible = w0 + b.custom_minimum_size.x + 8.0 <= ep.get_viewport().get_visible_rect().size.x - 4.0
