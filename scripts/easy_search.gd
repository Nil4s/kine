class_name EasySearch
## p097searchboxf (Friday plan 97): the S box (scripts/command_search.gd) finds the Easy Part actions too. Each MAKE button is a row
## ("Easy Part: Cut a hole", "Easy Part: Round the edges") and each screw size is a row ("Easy Part: Screw M4 x 16 mm").
## A row runs the same press its button runs (one undo step, the same as a click); Easy Part must be open, else the words say how to open it.
## main._commands() appends these rows; the rows are static, the press is looked up when the row runs.


static func rows(m: Node) -> Array:
	var out := []
	for mk in EasyPart.MAKES:
		out.append(_row(m, "easy_make_" + String(mk[0]), "Easy Part: " + String(mk[1]), "make", String(mk[0]),
			"easy part build make " + String(mk[0]) + " " + String(mk[1]).to_lower(), String(mk[3])))
	for d in EasyPart.SCREW_DS:
		for L in EasyPart.SCREW_LENS:
			out.append(_row(m, "easy_screw_%d_%d" % [d, L], "Easy Part: Screw M%d x %d mm" % [d, L], "screw", "%d_%d" % [d, L],
				"easy part screw bolt nut socket head iso parts m%d %d" % [d, L],
				"a socket head screw M%d, %d mm long, dropped on the floor (Parts > Screws)" % [d, L]))
	return out


static func _row(m: Node, id: String, label: String, kind: String, key: String, also: String, desc: String) -> Dictionary:
	return {"id": id, "name": label, "keys": "", "run": Callable(EasySearch, "go").bind(m, kind, key), "also": also, "edits": true, "desc": desc}


## the row's press: a MAKE button (kind "make") or a screw size (kind "screw", Parts is opened first if it is shut)
static func go(m: Node, kind: String, key: String) -> void:
	var ep = m.bld.part.ep if m.bld != null and m.bld.part != null else null
	if ep == null or not ep.active():
		m._say("Easy Part is not open: go to BUILD, press Easy, then search again")
		return
	if kind == "make":
		ep.make_btns[key].pressed.emit()
	else:
		if not ep.parts_open:
			ep._parts_press()
		ep.screw_btns[key].pressed.emit()
