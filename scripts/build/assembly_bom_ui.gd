## BILL OF MATERIALS panel of the Assembly screen (G8BOM; the engine is scripts/build/assembly_bom.gd). The BOM button beside Check motion
## opens it on the left:
##   table      one line per group of identical parts (and per bought extra): part, qty, material / item, mass, cost, and the cheaper choice.
##              The Part / Qty / Mass / Cost heads sort the table (press again: the other way)
##   material   a made part's material is picked in its line (all the identical parts of the line): ONE undo step
##   cheaper    the cheapest material or item the line may use that still meets the part's own needs, with the saving: press it to use it
##              (ONE undo step). Under the table: the cheapest whole design that also passes the assembly's named check, and Use it (ONE step)
##   CSV, Copy  the table as a .csv in the exports folder, or on the clipboard
## Opening the panel, sorting and Close change nothing in the record; Ctrl+Z takes back a material change (AssemblyUI.undo_redo).
class_name AssemblyBomUI
extends RefCounted

const W := 640.0
const COLW := [164.0, 64.0, 120.0, 66.0, 62.0, 112.0]   # part, qty, material, mass, cost, cheaper

var a: AssemblyUI
var panel: PanelContainer
var totals_l: Label
var grid: GridContainer
var design_l: Label
var design_btn: Button
var csv_btn: Button
var copy_btn: Button
var close_btn: Button
var sort_btns := {}
var sort_col := "cost"
var sort_asc := false
var rows: Array = []            # the lines on screen, in their order
var cheap := {}                 # AssemblyBom.cheaper of the record on screen
var last_csv := {}


func setup(owner: AssemblyUI) -> void:
	a = owner
	panel = PanelContainer.new()
	panel.name = "asm_bom_panel"
	panel.visible = false
	panel.add_theme_stylebox_override("panel", a.psb_of())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	vb.add_child(a._lbl("BILL OF MATERIALS", 15, "asm_bom_title"))
	totals_l = a._lbl("", 12, "asm_bom_totals")
	totals_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	totals_l.custom_minimum_size = Vector2(W - 24.0, 0)
	vb.add_child(totals_l)
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", 6)
	for c in [["part", "Part", 0], ["qty", "Qty", 1], ["", "Material / item", 2], ["mass", "Mass", 3], ["cost", "Cost", 4], ["", "Cheaper", 5]]:
		var w: float = COLW[int(c[2])]
		if String(c[0]) == "":
			var l := a._lbl(String(c[1]), 12)
			l.custom_minimum_size.x = w
			hh.add_child(l)
			continue
		var b := a._btn(String(c[1]), "asm_bom_sort_" + String(c[0]), "Sort the table by %s (press again: the other way)" % String(c[1]).to_lower(), sort_by.bind(String(c[0])))
		b.custom_minimum_size.x = w
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		hh.add_child(b)
		sort_btns[String(c[0])] = b
	vb.add_child(hh)
	var sc := ScrollContainer.new()
	sc.name = "asm_bom_scroll"
	sc.custom_minimum_size = Vector2(W - 20.0, 300)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid = GridContainer.new()
	grid.name = "asm_bom_grid"
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 1)
	sc.add_child(grid)
	vb.add_child(sc)
	design_l = a._lbl("", 12, "asm_bom_design")
	design_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	design_l.custom_minimum_size = Vector2(W - 24.0, 0)
	vb.add_child(design_l)
	var hb := HBoxContainer.new()
	design_btn = a._btn("Use the cheapest design", "asm_bom_use_design", "Put every change of the cheapest design that still works into the record (one Ctrl+Z takes it back)", use_design)
	csv_btn = a._btn("CSV", "asm_bom_csv", "Write the table as a .csv in the exports folder", export_csv)
	copy_btn = a._btn("Copy", "asm_bom_copy", "Copy the table (CSV) to the clipboard, to paste in a spreadsheet", copy)
	close_btn = a._btn("Close", "asm_bom_close", "Close the bill of materials", close)
	for b in [design_btn, csv_btn, copy_btn, close_btn]:
		(b as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(b)
	vb.add_child(hb)
	a.m.ui_root.add_child(panel)


func layout(at: Vector2) -> void:
	if panel.visible:
		panel.reset_size()
		panel.position = at
		panel.size.x = W


func is_open() -> bool:
	return panel != null and panel.visible


func open() -> void:
	if not a.on:
		a._say("The bill of materials works in the Assembly screen: BUILD > New assembly, or open a saved one")
		return
	if a.motion.is_open():
		a.motion.close()
	a.src_open = false
	a._sync_src()
	panel.visible = true
	a.m.ui_root.move_child(panel, a.m.ui_root.get_child_count() - 1)
	refresh()
	var b: Dictionary = cheap.get("bom", {})
	a._say("BILL OF MATERIALS: %d lines, %s %.2f, %.3f kg%s" % [rows.size(), String(b.get("currency", "USD")), float(b.get("cost", 0.0)), float(b.get("mass_kg", 0.0)), (". %d lines have no material yet: pick one in the line" % int(b["unpriced"])) if int(b.get("unpriced", 0)) > 0 else ""])


func close() -> void:
	panel.visible = false


func sort_by(col: String) -> void:
	if sort_col == col:
		sort_asc = not sort_asc
	else:
		sort_col = col
		sort_asc = col == "part"
	_fill()


## read the record again (after a change, an undo or a new assembly)
func refresh() -> void:
	if panel == null or not panel.visible:
		return
	cheap = AssemblyBom.cheaper(a.asm)
	_fill()


func _cell(t: String, w: float, nm := "") -> Label:
	var l := a._lbl(t, 12, nm)
	l.custom_minimum_size.x = w
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


func _fill() -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	var b: Dictionary = cheap.get("bom", {"lines": [], "cost": 0.0, "mass_kg": 0.0, "parts": 0, "items": 0, "currency": "USD", "unpriced": 0})
	var cur := String(b["currency"])
	var by_key := {}
	for r in cheap.get("lines", []):
		by_key[String(r["key"])] = r
	rows = AssemblyBom.sorted_lines(b["lines"], sort_col, sort_asc)
	for c in sort_btns:
		(sort_btns[c] as Button).text = String((sort_btns[c] as Button).text).trim_suffix(" ^").trim_suffix(" v") + ((" ^" if sort_asc else " v") if c == sort_col else "")
	var mats: Dictionary = AssemblyBom.prices().get("materials", {})
	var mkeys: Array = mats.keys()
	for i in rows.size():
		var ln: Dictionary = rows[i]
		var nm := _cell(("%d x " % int(ln["count"]) if int(ln["count"]) > 1 else "") + String(ln["part"]), COLW[0], "asm_bom_part_%d" % i)
		nm.tooltip_text = "%s\nprice: %s" % [String(ln["part"]), String(ln["source"]) if ln["priced"] else String(ln["why"])]
		grid.add_child(nm)
		var qv := float(ln["qty"])
		var q := ("%d" % int(roundf(qv)) if absf(qv - roundf(qv)) < 1e-9 else "%.2f" % qv) + ("" if String(ln["unit"]) == "pcs" else " " + String(ln["unit"]))
		grid.add_child(_cell(q, COLW[1], "asm_bom_qty_%d" % i))
		if not ln["extra"] and String(ln["item"]) == "":
			var ob := OptionButton.new()
			ob.name = "asm_bom_mat_%d" % i
			ob.focus_mode = Control.FOCUS_NONE
			ob.custom_minimum_size.x = COLW[2]
			ob.clip_text = true
			ob.add_theme_font_size_override("font_size", 12)
			ob.tooltip_text = "The material of this part (every identical part of the line): one Ctrl+Z takes it back"
			ob.add_item("(none)")
			for k in mkeys:
				ob.add_item(String(k))
			ob.select(mkeys.find(String(ln["material"])) + 1)
			var key := String(ln["key"])
			ob.item_selected.connect(func(j: int):
				if j > 0:
					use(key, String(mkeys[j - 1]), "material"))
			grid.add_child(ob)
		else:
			var it := String(ln["item"]) if String(ln["item"]) != "" else String(ln["material"])
			grid.add_child(_cell(it, COLW[2], "asm_bom_mat_%d" % i))
		grid.add_child(_cell("%.3f kg" % float(ln["line_mass_kg"]) if ln["mass_known"] else "-", COLW[3], "asm_bom_mass_%d" % i))
		var cl := _cell("%.2f" % float(ln["line_cost"]) if ln["priced"] else "-", COLW[4], "asm_bom_cost_%d" % i)
		grid.add_child(cl)
		var r: Dictionary = by_key.get(String(ln["key"]), {})
		var best: Dictionary = r.get("best", {})
		if best.is_empty():
			var why := "no cheaper choice meets its needs" if not (r.get("alts", []) as Array).is_empty() else ""
			var nl := _cell("-" if why != "" else "", COLW[5], "asm_bom_cheaper_%d" % i)
			nl.tooltip_text = why
			grid.add_child(nl)
		else:
			var bt := a._btn("%s -%.2f" % [String(best["key"]), float(r["saving"])], "asm_bom_cheaper_%d" % i, "Use %s here: %s %.2f instead of %.2f (meets: %s). One Ctrl+Z takes it back" % [String(best["name"]), cur, float(best["line_cost"]), float(ln["line_cost"]), _needs(ln)], use.bind(String(ln["key"]), String(best["key"]), "cheaper"))
			bt.custom_minimum_size.x = COLW[5]
			bt.clip_text = true
			bt.add_theme_font_size_override("font_size", 12)
			grid.add_child(bt)
	totals_l.text = "%d parts + %d bought items, %.3f kg, %s %.2f%s.  Cheaper line by line: save %.2f" % [int(b["parts"]), int(b["items"]), float(b["mass_kg"]), cur, float(b["cost"]),
		(" (%d lines not priced)" % int(b["unpriced"])) if int(b["unpriced"]) > 0 else "", float(cheap.get("saving_lines", 0.0))]
	var d: Dictionary = cheap.get("design", {})
	var chk := String(d.get("check", ""))
	if d.is_empty() or (d["changes"] as Dictionary).is_empty():
		design_l.text = "The cheapest design that works is this one%s" % ((" (%s: %s)" % [chk, "passes" if d.get("now_ok", true) else "FAILS: " + String(d.get("now_why", ""))]) if chk != "" else "")
		design_btn.disabled = true
	else:
		var ch: Array = []
		for k in d["changes"]:
			ch.append("%s -> %s" % [_part_of(String(k)), String(d["changes"][k])])
		design_l.text = "Cheapest design that works: %s %.2f (save %.2f)%s: %s" % [cur, float(d["cost"]), float(d["saving"]), (", %s passes" % chk) if chk != "" else "", "; ".join(PackedStringArray(ch))]
		design_btn.disabled = false


func _needs(ln: Dictionary) -> String:
	var n = (ln["bom"] as Dictionary).get("need", {})
	return "no stated need" if not (n is Dictionary) or (n as Dictionary).is_empty() else ", ".join(PackedStringArray((n as Dictionary).keys().map(func(k): return "%s %s" % [k, str(n[k])])))


func _part_of(key: String) -> String:
	for ln in rows:
		if String(ln["key"]) == key:
			return String(ln["part"])
	return key


## line key uses c (a material or an item): ONE undo step
func use(key: String, c: String, why: String) -> bool:
	var nm := _part_of(key)
	var cp: Dictionary = a.asm.duplicate(true)
	if not AssemblyBom.apply(cp, key, c):
		a._say("NOT DONE: %s has no price in data/prices.json" % c)
		return false
	a.push_undo("BOM: %s uses %s" % [nm, c])
	a.asm = cp
	a._refresh(false)
	refresh()
	var b: Dictionary = cheap.get("bom", {})
	a._say("Now %s: total %s %.2f" % [c, String(b.get("currency", "USD")), float(b.get("cost", 0.0))])   # short: the long line drew over the Export row (part name and reason are in the table)
	return true


func use_design() -> bool:
	var d: Dictionary = cheap.get("design", {})
	if d.is_empty() or (d["changes"] as Dictionary).is_empty():
		return false
	a.push_undo("BOM: the cheapest design")
	AssemblyBom.apply_design(a.asm, d["changes"])
	a._refresh(false)
	refresh()
	a._say("Cheapest design in: %s %.2f" % [String(cheap["bom"]["currency"]), float(cheap["bom"]["cost"])])
	return true


func export_csv(path := "") -> Dictionary:
	last_csv = AssemblyBom.write_csv(a.asm, path)
	a.last_export = last_csv
	a._say(String(last_csv["text"]))
	return last_csv


func copy() -> String:
	var t := AssemblyBom.csv(AssemblyBom.bom(a.asm))
	DisplayServer.clipboard_set(t)
	a._say("The bill of materials is on the clipboard (CSV, %d lines): paste it in a spreadsheet" % (t.count("\n") - 2))
	return t
