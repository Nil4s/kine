extends RefCounted
## s228 PATTERNS ALONG PATHS AND GRIDS, the Expert Pattern dialog's two extra kinds (Grid, Along a path) and the variation rows. The dialog (part_ui.gd
## _pattern_open) calls attach() once; _pattern_sync() calls sync(); _pattern_feature() calls finish(). The engine is part_array.gd.
## ui is the PartUI. Controls are named part_grid_*, part_route_*, part_vary_* (tests drive them by name).
const PartArray := preload("res://scripts/build/part_array.gd")

const KIND_GRID := 2
const KIND_ROUTE := 3


static func attach(ui, f: Dictionary, edit: int) -> void:
	var pat: Dictionary = ui.pat
	var kind_o: OptionButton = pat["kind"]
	kind_o.add_item("Grid (columns x rows x layers)")
	kind_o.add_item("Along a path (a sketch or an outline)")
	var kk := String(f.get("kind", "linear")) if edit >= 0 else ""
	if kk == "grid":
		kind_o.select(KIND_GRID)
	elif kk == "route":
		kind_o.select(KIND_ROUTE)
	var g: Array = []
	# --- grid: columns along a direction, rows along another, layers along a third; spacing for each
	var gd := [["cols", "Columns", "count", 3, "mm", 20.0, "dir", "x"], ["rows", "Rows", "rows", 2, "mm2", 20.0, "dir2", "z"], ["layers", "Layers", "layers", 1, "mm3", 20.0, "dir3", "y"]]
	for d in gd:
		var cnt: LineEdit = ui._field("part_grid_" + String(d[0]))
		cnt.text = str(int(f.get(String(d[2]), d[3]))) if (edit >= 0 and kk == "grid") else str(d[3])
		var sp: LineEdit = ui._field("part_grid_" + String(d[0]) + "_mm")
		sp.text = ui._fmt(float(f.get(String(d[4]), d[5]))) if (edit >= 0 and kk == "grid") else ui._fmt(float(d[5]))
		var dr: OptionButton = ui._pat_axis_option("part_grid_" + String(d[0]) + "_dir", String(f.get(String(d[6]), d[7])) if (edit >= 0 and kk == "grid") else String(d[7]))
		pat["g_" + String(d[0])] = cnt
		pat["g_" + String(d[0]) + "_mm"] = sp
		pat["g_" + String(d[0]) + "_dir"] = dr
		var h := HBoxContainer.new()
		var l: Label = ui._label(String(d[1]))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(cnt)
		h.add_child(sp)
		h.add_child(ui._label("mm", 13, true))
		h.add_child(dr)
		ui.dlg_rows.add_child(h)
		g.append(h)
	pat["grid_rows"] = g
	# --- route: the path (a sketch, or the plan outline of a body), how many / how far apart, fit, corners, follow, hold
	var r: Array = []
	var rec: Dictionary = ui._rec()
	var src_o := OptionButton.new()
	src_o.name = "part_route_path"
	src_o.focus_mode = Control.FOCUS_NONE
	var srcs: Array = []
	for sid in ui._sketch_ids(rec):
		src_o.add_item("Sketch: %s" % String(Part.feature(rec, String(sid)).get("name", sid)))
		srcs.append(["sketch", String(sid)])
	var nb := maxi(int(ui.res.get("bodies", 0)), 1)
	for i in nb:
		src_o.add_item("Outline of Body %d" % (i + 1))
		srcs.append(["body", i])
	if edit >= 0 and kk == "route" and String(f.get("path", "")) != "":
		for i in srcs.size():
			if srcs[i][0] == "sketch" and srcs[i][1] == String(f["path"]):
				src_o.select(i)
	elif srcs.size() > nb and not (edit >= 0 and kk == "route"):
		src_o.select(srcs.size() - nb - 1)   # the newest sketch
	src_o.item_selected.connect(func(_i): ui._preview())
	pat["route_srcs"] = srcs
	pat["r_path"] = src_o
	r.append(ui._pat_row("Path", src_o, ""))
	ui.dlg_rows.add_child(r[0])
	var rc: LineEdit = ui._field("part_route_count")
	rc.text = str(int(f.get("count", 0))) if (edit >= 0 and kk == "route") else "0"
	rc.custom_minimum_size.x = 48
	pat["r_count"] = rc
	var rm: LineEdit = ui._field("part_route_mm")
	rm.text = ui._fmt(float(f.get("mm", 20.0))) if (edit >= 0 and kk == "route") else "20"
	rm.custom_minimum_size.x = 56
	pat["r_mm"] = rm
	var rg: LineEdit = ui._field("part_route_grow")
	rg.text = ui._fmt(float(f.get("fgrow", 0.0))) if (edit >= 0 and kk == "route") else "0"
	rg.custom_minimum_size.x = 48
	pat["r_grow"] = rg
	var nums := _inline(ui, [["Copies", rc, "(0 = by gap)"], ["Every", rm, "mm"], ["Grow", rg, "mm"]])
	ui.dlg_rows.add_child(nums)
	r.append(nums)
	var cbs: Array = []
	for cb in [["fit", "Fit to length", "Spacing adjusts so the first copy lands on the start and the last on the end", "fit", false], ["corners", "Corners", "A copy exactly at every corner, each straight part divided evenly by the gap", "corners", false], ["follow", "Turn with path", "Each copy turns to follow the path (to the bisector at a corner)", "follow", false], ["hold", "Keep distance", "A piece beside the path keeps its distance from it all the way round", "hold", true]]:
		var c := CheckBox.new()
		c.name = "part_route_" + String(cb[0])
		c.text = String(cb[1])
		c.tooltip_text = String(cb[2])
		c.focus_mode = Control.FOCUS_NONE
		c.set_pressed_no_signal(bool(f.get(String(cb[3]), cb[4])) if (edit >= 0 and kk == "route") else bool(cb[4]))
		c.toggled.connect(func(_v): ui._preview())
		pat["r_" + String(cb[0])] = c
		cbs.append(c)
	for pair in [[cbs[0], cbs[1]], [cbs[2], cbs[3]]]:
		var h := HBoxContainer.new()
		for c in pair:
			(c as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(c)
		ui.dlg_rows.add_child(h)
		r.append(h)
	pat["route_rows"] = r
	# --- variation (grid and path): seed, jitter, skip in one line
	var vf := {}
	for d in [["seed", "seed", 1, 44], ["jit", "jit", 0, 44], ["turn", "jit_turn", 0, 40], ["skip", "skip", 0, 36]]:
		var le: LineEdit = ui._field("part_vary_" + String(d[0]))
		le.text = ui._fmt(float(f.get(String(d[1]), d[2]))) if (edit >= 0 and kk in ["grid", "route"]) else str(d[2])
		le.custom_minimum_size.x = float(d[3])
		pat["v_" + String(d[0])] = le
		vf[d[0]] = le
	var vrow := _inline(ui, [["Vary: seed", vf["seed"], ""], ["move", vf["jit"], "mm"], ["turn", vf["turn"], "deg"], ["skip every", vf["skip"], ""]])
	ui.dlg_rows.add_child(vrow)
	pat["vary_rows"] = [vrow]


## one line of "label field unit" groups: items = [[label, control, unit], ...]
static func _inline(ui, items: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	for it in items:
		h.add_child(ui._label(String(it[0]), 13))
		h.add_child(it[1])
		if String(it[2]) != "":
			h.add_child(ui._label(String(it[2]), 12, true))
	return h


## show the rows of the kind picked; hide the others
static func sync(ui) -> void:
	var pat: Dictionary = ui.pat
	if not pat.has("grid_rows"):
		return
	var sel := int((pat["kind"] as OptionButton).selected)
	var ext := sel >= KIND_GRID
	if ext:
		for r in pat["lin"]:
			(r as Control).visible = false
		for r in pat["circ"]:
			(r as Control).visible = false
		(pat["count"] as Control).get_parent().visible = false
	else:
		(pat["count"] as Control).get_parent().visible = true
	for r in pat["grid_rows"]:
		(r as Control).visible = sel == KIND_GRID
	for r in pat["route_rows"]:
		(r as Control).visible = sel == KIND_ROUTE
	for r in pat["vary_rows"]:
		(r as Control).visible = ext


## the feature of the grid / path kinds ({} when a number is wrong). f has kind/count/body/op/bodies already
static func finish(ui, f: Dictionary, sel: int) -> Dictionary:
	var pat: Dictionary = ui.pat
	f.erase("count")
	var seed_v: float = ui._num(pat["v_seed"])
	var jit: float = ui._num(pat["v_jit"])
	var jt: float = ui._num(pat["v_turn"])
	var skip: float = ui._num(pat["v_skip"])
	if is_nan(seed_v) or is_nan(jit) or is_nan(jt) or is_nan(skip) or jit < 0.0 or skip < 0.0 or skip == 1.0 or skip != floorf(skip):
		return {}
	f["seed"] = int(seed_v)
	if jit > 0.0:
		f["jit"] = jit
	if jt != 0.0:
		f["jit_turn"] = jt
	if skip >= 2.0:
		f["skip"] = int(skip)
	if sel == KIND_GRID:
		f["kind"] = "grid"
		var tot := 1
		for d in [["cols", "count", "mm", "dir"], ["rows", "rows", "mm2", "dir2"], ["layers", "layers", "mm3", "dir3"]]:
			var n: float = ui._num(pat["g_" + String(d[0])])
			var s: float = ui._num(pat["g_" + String(d[0]) + "_mm"])
			if is_nan(n) or n != floorf(n) or n < 1.0 or n > 100.0 or is_nan(s):
				return {}
			if n > 1.0 and absf(s) < 1e-6:
				return {}
			f[String(d[1])] = int(n)
			f[String(d[2])] = s
			f[String(d[3])] = ui.PAT_AXES[int((pat["g_" + String(d[0]) + "_dir"] as OptionButton).selected)]
			tot *= int(n)
		if tot < 2 or tot > PartArray.MAX_COPIES:
			return {}
		return f
	f["kind"] = "route"
	var cnt: float = ui._num(pat["r_count"])
	var mm: float = ui._num(pat["r_mm"])
	var gr: float = ui._num(pat["r_grow"])
	if is_nan(cnt) or cnt != floorf(cnt) or cnt < 0.0 or cnt == 1.0 or is_nan(mm) or mm < 0.0 or is_nan(gr):
		return {}
	if mm <= 0.0 and not (bool((pat["r_fit"] as CheckBox).button_pressed) and cnt >= 2.0):
		return {}
	f["count"] = int(cnt)
	f["mm"] = mm
	for k in ["fit", "corners", "follow", "hold"]:
		f[k] = (pat["r_" + k] as CheckBox).button_pressed
	var srcs: Array = pat["route_srcs"]
	var pi := int((pat["r_path"] as OptionButton).selected)
	if pi < 0 or pi >= srcs.size():
		return {}
	if srcs[pi][0] == "sketch":
		f["path"] = srcs[pi][1]
	else:
		var fp := PartArray.footprint_pts(ui._rec(), int(srcs[pi][1]), gr)
		if String(fp["err"]) != "":
			return {}
		f["pts"] = fp["pts"]
		f["closed"] = true
		f["fgrow"] = gr
		f["fbody"] = int(srcs[pi][1])
	return f

