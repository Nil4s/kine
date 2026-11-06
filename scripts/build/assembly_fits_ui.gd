## FITS panel of the Assembly screen (G3; the maths is scripts/build/iso_fits.gd, the data and checks are scripts/build/dim_fit.gd). The Fits button opens it:
##   mating pairs  a hole dimension and a shaft dimension (each carries an ISO 286 class typed in the Part's dimension list) -> the fit kind
##                 (clearance / transition / interference) and the min / max clearance in um; an interference fit that the assembly draws as a
##                 sliding joint (a slider or revolute joint between the two parts, or the Sliding box) is flagged
##   stack-up      pick dimensions with a sign (+ adds, - subtracts): nominal, worst case and RSS (root sum of squares); CSV into the exports folder
## Every edit is ONE undo step (Ctrl+Z, AssemblyUI.undo_redo). Opening, closing and picking change nothing in the record.
class_name AssemblyFitsUI
extends RefCounted

const W := 640.0

var a: AssemblyUI
var panel: PanelContainer
var pairs_vb: VBoxContainer
var stack_vb: VBoxContainer
var hole_opt: OptionButton
var shaft_opt: OptionButton
var slide_chk: CheckBox
var dim_opt: OptionButton
var totals_l: Label
var cur := 0                     # the stack on screen
var hole_keys: Array = []
var shaft_keys: Array = []
var dim_keys: Array = []
var last_csv := {}


func setup(owner: AssemblyUI) -> void:
	a = owner
	panel = PanelContainer.new()
	panel.name = "asm_fits_panel"
	panel.visible = false
	panel.add_theme_stylebox_override("panel", a.psb_of())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	vb.add_child(a._lbl("FITS AND STACK-UP", 15, "asm_fits_title"))
	vb.add_child(a._lbl("Mating pairs (hole + shaft, ISO 286)", 12))
	pairs_vb = VBoxContainer.new()
	pairs_vb.name = "asm_fits_pairs"
	vb.add_child(pairs_vb)
	var h1 := HBoxContainer.new()
	hole_opt = OptionButton.new()
	hole_opt.name = "asm_fits_hole"
	shaft_opt = OptionButton.new()
	shaft_opt.name = "asm_fits_shaft"
	slide_chk = CheckBox.new()
	slide_chk.text = "Sliding"
	slide_chk.name = "asm_fits_sliding"
	slide_chk.tooltip_text = "This pair is meant to slide or turn (an interference fit here is flagged)"
	for c in [hole_opt, shaft_opt]:
		(c as OptionButton).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(c as OptionButton).clip_text = true
		h1.add_child(c)
	h1.add_child(slide_chk)
	h1.add_child(a._btn("Add pair", "asm_fits_add_pair", "Pair the picked hole and shaft dimensions (give each dimension a class in the Part first)", add_pair))
	vb.add_child(h1)
	vb.add_child(a._lbl("Stack-up (pick dimensions with a sign)", 12))
	stack_vb = VBoxContainer.new()
	stack_vb.name = "asm_fits_stack"
	vb.add_child(stack_vb)
	var h2 := HBoxContainer.new()
	dim_opt = OptionButton.new()
	dim_opt.name = "asm_fits_dim"
	dim_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dim_opt.clip_text = true
	h2.add_child(dim_opt)
	h2.add_child(a._btn("+ add", "asm_fits_plus", "Add the picked dimension to the chain with a plus sign", func(): add_link(1)))
	h2.add_child(a._btn("- subtract", "asm_fits_minus", "Add the picked dimension to the chain with a minus sign", func(): add_link(-1)))
	h2.add_child(a._btn("New stack", "asm_fits_new_stack", "Start another chain", new_stack))
	vb.add_child(h2)
	totals_l = a._lbl("", 12, "asm_fits_totals")
	totals_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	totals_l.custom_minimum_size = Vector2(W - 24.0, 0)
	vb.add_child(totals_l)
	var hb := HBoxContainer.new()
	for b in [a._btn("CSV", "asm_fits_csv", "Write the chain, its worst case and RSS as a .csv in the exports folder", export_csv), a._btn("Close", "asm_fits_close", "Close", close)]:
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
		a._say("Fits work in the Assembly screen: BUILD > New assembly, or open a saved one")
		return
	a.motion.close()
	a.bom.close()
	a.stages.close()
	a.src_open = false
	a._sync_src()
	panel.visible = true
	a.m.ui_root.move_child(panel, a.m.ui_root.get_child_count() - 1)
	refresh()
	a._say("FITS: %d pairs, %d chains. Give a hole or shaft size a class (H7, g6) in its Part, then pair them here" % [(a.asm.get("fits", []) as Array).size(), (a.asm.get("stacks", []) as Array).size()])


func close() -> void:
	if panel != null:
		panel.visible = false


func _clear(c: Control) -> void:
	for k in c.get_children():
		c.remove_child(k)
		k.queue_free()


func _fill_opt(o: OptionButton, keys: Array, items: Array) -> void:
	o.clear()
	keys.clear()
	for e in items:
		o.add_item("%s: %s  %s" % [String(e["part_name"]), String(e["name"]), ("%s %s" % [IsoFits.fmt(float(e["size_mm"])), String(e["fit"])]).strip_edges()])
		keys.append({"part": e["part"], "dim": e["key"]})


func refresh() -> void:
	if panel == null or not panel.visible:
		return
	var all := DimFit.all_dims(a.asm)
	var hole_i := hole_opt.selected
	var shaft_i := shaft_opt.selected
	var dim_i := dim_opt.selected
	_fill_opt(hole_opt, hole_keys, all.filter(func(e): return String(e["fit"]) != "" and String(e["fit"]).to_upper() == String(e["fit"])))
	_fill_opt(shaft_opt, shaft_keys, all.filter(func(e): return String(e["fit"]) != "" and String(e["fit"]).to_lower() == String(e["fit"])))
	_fill_opt(dim_opt, dim_keys, all)
	if hole_i >= 0 and hole_i < hole_opt.item_count:
		hole_opt.select(hole_i)
	if shaft_i >= 0 and shaft_i < shaft_opt.item_count:
		shaft_opt.select(shaft_i)
	if dim_i >= 0 and dim_i < dim_opt.item_count:
		dim_opt.select(dim_i)
	_clear(pairs_vb)
	var n := 0
	for fx in a.asm.get("fits", []):
		var r := DimFit.pair_report(a.asm, fx)
		var l := a._lbl(DimFit.pair_text(r), 12, "asm_fits_pair_%d" % n)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = W - 24.0
		if bool(r["flag"]):
			l.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3))
		elif not bool(r["ok"]):
			l.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
		pairs_vb.add_child(l)
		n += 1
	if n == 0:
		pairs_vb.add_child(a._lbl("None yet.", 12))
	_clear(stack_vb)
	var sts: Array = a.asm.get("stacks", [])
	cur = clampi(cur, 0, maxi(sts.size() - 1, 0))
	if sts.is_empty():
		stack_vb.add_child(a._lbl("None yet: pick a dimension and press + add.", 12))
		totals_l.text = ""
		return
	var st: Dictionary = sts[cur]
	stack_vb.add_child(a._lbl("%s (%d of %d)" % [String(st["name"]), cur + 1, sts.size()], 12, "asm_fits_stack_name"))
	var rep := DimFit.stack_report(a.asm, st)
	var links: Array = st["links"]
	for i in links.size():
		var h := HBoxContainer.new()
		var lk := DimFit.link_of(a.asm, links[i])
		var t := String(lk["why"]) if not bool(lk["ok"]) else "%s  %s %s mm  +-%s um  (%s)" % ["+" if int(lk["sign"]) > 0 else "-", String(lk["name"]), IsoFits.fmt(float(lk["nom"])), String.num(float(lk["tol"]), 2), String(lk["src"])]
		var l := a._lbl(t, 12, "asm_fits_link_%d" % i)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(a._btn("+/-", "asm_fits_flip_%d" % i, "Flip the sign", flip.bind(i)))
		h.add_child(a._btn("x", "asm_fits_del_%d" % i, "Remove this link", del_link.bind(i)))
		stack_vb.add_child(h)
	totals_l.text = DimFit.stack_text(rep)


func _commit(label: String, edit: Callable) -> void:
	a.push_undo(label)
	var cp: Dictionary = a.asm.duplicate(true)
	edit.call(cp)
	a.asm = cp
	refresh()


func add_pair() -> bool:
	if hole_opt.selected < 0 or shaft_opt.selected < 0:
		a._say("NOT DONE: a pair needs a hole size with an upper-case class (H7) and a shaft size with a lower-case one (g6) in the Parts")
		return false
	var h: Dictionary = hole_keys[hole_opt.selected]
	var s: Dictionary = shaft_keys[shaft_opt.selected]
	_commit("Fits: add a pair", func(cp): DimFit.add_pair(cp, "", String(h["part"]), String(h["dim"]), String(s["part"]), String(s["dim"]), "slide" if slide_chk.button_pressed else ""))
	a._say(DimFit.pair_text(DimFit.pair_report(a.asm, (a.asm["fits"] as Array)[-1])))
	return true


func new_stack() -> void:
	_commit("Fits: new stack-up", func(cp): DimFit.add_stack(cp))
	cur = (a.asm["stacks"] as Array).size() - 1
	refresh()


func add_link(sign: int) -> bool:
	if dim_opt.selected < 0:
		a._say("NOT DONE: no dimensions yet. Draw a sketch with sizes in a Part first")
		return false
	var k: Dictionary = dim_keys[dim_opt.selected]
	var had: bool = not (a.asm.get("stacks", []) as Array).is_empty()
	var ci := cur
	if not had:
		ci = 0
	_commit("Fits: add a link", func(cp):
		if not had:
			DimFit.add_stack(cp)
		DimFit.add_link(cp, ci, String(k["part"]), String(k["dim"]), sign))
	cur = ci
	refresh()
	return true


func flip(i: int) -> void:
	var ci := cur
	_commit("Fits: flip a sign", func(cp):
		var lk: Dictionary = cp["stacks"][ci]["links"][i]
		lk["sign"] = -int(lk["sign"]))


func del_link(i: int) -> void:
	var ci := cur
	_commit("Fits: remove a link", func(cp): (cp["stacks"][ci]["links"] as Array).remove_at(i))


func export_csv(path := "") -> Dictionary:
	last_csv = DimFit.write_stack_csv(a.asm, cur, path)
	a.last_export = last_csv
	a._say(String(last_csv["text"]))
	return last_csv
