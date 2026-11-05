## CHECK MOTION panel of the Assembly screen (G1MOTION; the engine is scripts/build/assembly_motion.gd). The Check motion button (or the
## "Assembly: check motion" command) opens it on the left:
##   drive      the assembly's drives; "Add drive" makes one for the selected part (Turn / Slide, axis, origin mm, range): ONE undo step
##   Run        sweeps the drive (steps + 1 samples, both ends) with the exact solids; each clashing pair is listed with its angle or place,
##              and the parts go red
##   slider     scrubs the drive: the parts move on screen only (the record keeps its poses); Close puts them back
##   joint      (G2LOOP) Pin / Slide / Weld from the selected part to another part or Ground, at the axis and point above: ONE undo step.
##              With joints, the drive moves every part they tie to it (AssemblyLoop): the scrub and the sweep follow the closed loop
## The only record changes are a drive or a joint added; Ctrl+Z takes it back (AssemblyUI.undo_redo).
class_name AssemblyMotionUI
extends RefCounted

const W := 290.0
const RED := Color(1.0, 0.12, 0.08, 0.55)

var a: AssemblyUI
var panel: PanelContainer
var drive_ob: OptionButton
var kind_ob: OptionButton
var axis_ob: OptionButton
var lo_e: LineEdit
var hi_e: LineEdit
var org_e: Array = []
var steps_e: LineEdit
var add_btn: Button
var run_btn: Button
var list_vb: VBoxContainer
var scrub: HSlider
var at_l: Label
var close_btn: Button
var jkind_ob: OptionButton     # G2LOOP: a joint's kind, its other part, Add joint, the count
var jto_ob: OptionButton
var jadd_btn: Button
var jcount_l: Label
var rev := 0                   # bumped on every record change: the loop pose cache's key
var _loop_key := ""
var _loop_sol := {}
var drive := ""                # the drive picked
var res := {}                  # the last sweep (AssemblyMotion.check_motion)
var scrub_on := false
var scrub_v := 0.0
var _red: StandardMaterial3D


func setup(owner: AssemblyUI) -> void:
	a = owner
	_red = StandardMaterial3D.new()
	_red.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_red.albedo_color = RED
	panel = PanelContainer.new()
	panel.name = "asm_motion_panel"
	panel.visible = false
	panel.add_theme_stylebox_override("panel", a.psb_of())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	vb.add_child(a._lbl("CHECK MOTION", 15, "asm_motion_title"))
	var h0 := HBoxContainer.new()
	h0.add_child(a._lbl("Drive", 13))
	drive_ob = OptionButton.new()
	drive_ob.name = "asm_motion_drive"
	drive_ob.focus_mode = Control.FOCUS_NONE
	drive_ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drive_ob.tooltip_text = "The drive to sweep: a part that turns or slides through a range"
	drive_ob.item_selected.connect(func(i: int): pick(drive_ob.get_item_text(i)))
	h0.add_child(drive_ob)
	vb.add_child(h0)
	vb.add_child(a._lbl("New drive for the selected part", 12))
	var h1 := HBoxContainer.new()
	kind_ob = OptionButton.new()
	kind_ob.name = "asm_motion_kind"
	kind_ob.focus_mode = Control.FOCUS_NONE
	kind_ob.add_item("Turn (deg)")
	kind_ob.add_item("Slide (mm)")
	h1.add_child(kind_ob)
	axis_ob = OptionButton.new()
	axis_ob.name = "asm_motion_axis"
	axis_ob.focus_mode = Control.FOCUS_NONE
	for t in ["about X", "about Y", "about Z"]:
		axis_ob.add_item(t)
	axis_ob.select(2)
	h1.add_child(axis_ob)
	vb.add_child(h1)
	var h2 := HBoxContainer.new()
	h2.add_child(a._lbl("From", 12))
	lo_e = _num_edit("asm_motion_lo", "0")
	h2.add_child(lo_e)
	h2.add_child(a._lbl("to", 12))
	hi_e = _num_edit("asm_motion_hi", "90")
	h2.add_child(hi_e)
	vb.add_child(h2)
	var h3 := HBoxContainer.new()
	h3.add_child(a._lbl("Axis through (mm)", 12))
	for c in ["x", "y", "z"]:
		var e := _num_edit("asm_motion_o" + c, "0")
		org_e.append(e)
		h3.add_child(e)
	vb.add_child(h3)
	add_btn = a._btn("Add drive", "asm_motion_add", "Make the selected part a drive (one Ctrl+Z takes it back)", add_drive)
	vb.add_child(add_btn)
	vb.add_child(a._lbl("New joint: the selected part to", 12))
	var hj := HBoxContainer.new()
	jkind_ob = OptionButton.new()
	jkind_ob.name = "asm_motion_jkind"
	jkind_ob.focus_mode = Control.FOCUS_NONE
	for t in ["Pin (turns)", "Slide", "Weld"]:
		jkind_ob.add_item(t)
	jkind_ob.tooltip_text = "Pin: turns about the axis through the point. Slide: moves along the axis. Weld: moves with the other part"
	hj.add_child(jkind_ob)
	jto_ob = OptionButton.new()
	jto_ob.name = "asm_motion_jto"
	jto_ob.focus_mode = Control.FOCUS_NONE
	jto_ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jto_ob.tooltip_text = "The other part of the joint, or Ground (the assembly itself)"
	hj.add_child(jto_ob)
	vb.add_child(hj)
	jadd_btn = a._btn("Add joint", "asm_motion_jadd", "Join the selected part to the other one at the axis and point above (one Ctrl+Z takes it back). With joints, a drive moves every part they tie to it (a closed loop: slider-crank, four-bar)", add_joint)
	vb.add_child(jadd_btn)
	jcount_l = a._lbl("", 12, "asm_motion_joints")
	jcount_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jcount_l.custom_minimum_size = Vector2(W - 24.0, 0)
	vb.add_child(jcount_l)
	var h4 := HBoxContainer.new()
	h4.add_child(a._lbl("Steps", 12))
	steps_e = _num_edit("asm_motion_steps", "36")
	h4.add_child(steps_e)
	run_btn = a._btn("Run the sweep", "asm_motion_run", "Move the drive through its range and check every pair of parts with the exact solids", run)
	run_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h4.add_child(run_btn)
	vb.add_child(h4)
	list_vb = VBoxContainer.new()
	list_vb.name = "asm_motion_list"
	vb.add_child(list_vb)
	scrub = HSlider.new()
	scrub.name = "asm_motion_scrub"
	scrub.focus_mode = Control.FOCUS_NONE
	scrub.custom_minimum_size = Vector2(W - 24.0, 22)
	scrub.tooltip_text = "Scrub the drive: the parts move on screen only"
	scrub.value_changed.connect(set_scrub)
	vb.add_child(scrub)
	at_l = a._lbl("", 12, "asm_motion_at")
	at_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	at_l.custom_minimum_size = Vector2(W - 24.0, 0)
	vb.add_child(at_l)
	close_btn = a._btn("Close", "asm_motion_close", "Close Check motion: the parts go back to their places", close)
	vb.add_child(close_btn)
	a.m.ui_root.add_child(panel)


func _num_edit(nm: String, t: String) -> LineEdit:
	var e := a._edit(nm, 44)
	e.text = t
	e.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	e.text_submitted.connect(func(_t): e.release_focus())
	return e


func layout(at: Vector2) -> void:
	if panel.visible:
		panel.reset_size()
		panel.position = at
		panel.size.x = W


func is_open() -> bool:
	return panel.visible


func open() -> void:
	if not a.on:
		a._say("Check motion works in the Assembly screen: BUILD > New assembly, or open a saved one")
		return
	a.src_open = false
	a._sync_src()
	panel.visible = true
	a.m.ui_root.move_child(panel, a.m.ui_root.get_child_count() - 1)   # over the part names the overlay draws
	a._frame()
	var p := a._sel_part()
	if not p.is_empty():
		for i in 3:
			(org_e[i] as LineEdit).text = a._fmt(float(p["pos"][i]))
	_fill_drives()
	_sync_scrub()
	a._say("CHECK MOTION: pick a drive (or add one for the selected part), then Run the sweep" if not AssemblyMotion.drives(a.asm).is_empty() else "CHECK MOTION: the assembly has no drive yet. Select the moving part, set Turn or Slide, the axis and the range, then Add drive")


func close() -> void:
	panel.visible = false
	reset(false)
	a._refresh(false)
	a._frame()


## the results and the scrub go (after an undo, a new assembly, or Close); hide = the panel closes too
func reset(hide: bool) -> void:
	res = {}
	scrub_on = false
	rev += 1
	if hide and panel != null:
		panel.visible = false
	if AssemblyMotion.drive_of(a.asm, drive).is_empty():
		drive = ""
	if panel != null and panel.visible:
		_fill_drives()
		_sync_scrub()
	if list_vb != null:
		for c in list_vb.get_children():
			list_vb.remove_child(c)
			c.queue_free()


func _fill_drives() -> void:
	drive_ob.clear()
	var ds := AssemblyMotion.drives(a.asm)
	for d in ds:
		drive_ob.add_item(String(d["name"]))
	drive_ob.disabled = ds.is_empty()
	if ds.is_empty():
		drive_ob.add_item("(none yet: add one below)")
	if drive == "" and not ds.is_empty():
		drive = String(ds[0]["name"])
	for i in drive_ob.item_count:
		if drive_ob.get_item_text(i) == drive:
			drive_ob.select(i)
	run_btn.disabled = drive == ""
	var keep := jto_ob.get_item_text(jto_ob.selected) if jto_ob.selected >= 0 else "Ground"
	jto_ob.clear()
	jto_ob.add_item("Ground")
	for p in a.asm["parts"]:
		jto_ob.add_item(String(p["name"]))
	for i in jto_ob.item_count:
		if jto_ob.get_item_text(i) == keep:
			jto_ob.select(i)
	var nj := AssemblyLoop.joints(a.asm).size()
	jcount_l.text = "No joints: a drive moves only its part and its links" if nj == 0 else "%d joint%s: the drive moves every part they tie to it" % [nj, "" if nj == 1 else "s"]


## G2LOOP: a joint from the selected part to the part (or Ground) picked, at the axis and point typed above
func add_joint() -> void:
	var p := a._sel_part()
	if p.is_empty():
		a._say("Select the part to join first (click it or its row), then Add joint")
		return
	var to_name := jto_ob.get_item_text(jto_ob.selected) if jto_ob.selected >= 0 else "Ground"
	var to := "ground"
	if to_name != "Ground":
		for q in a.asm["parts"]:
			if String(q["name"]) == to_name:
				to = String(q["id"])
	if to == String(p["id"]):
		a._say("A part can't be joined to itself: pick the other part or Ground")
		return
	var kind: String = AssemblyLoop.KINDS[jkind_ob.selected]
	var axis: Vector3 = AssemblyUI.AXES[axis_ob.selected]
	var o := [a._num((org_e[0] as LineEdit).text, 0.0), a._num((org_e[1] as LineEdit).text, 0.0), a._num((org_e[2] as LineEdit).text, 0.0)]   # doubles (G4)
	var nm := "%s %s %s" % [String(p["name"]), ["on", "in", "welded to"][jkind_ob.selected], to_name]
	a.push_undo("joint " + nm)
	AssemblyLoop.add_joint(a.asm, AssemblyLoop.joint_at(a.asm, kind, String(p["id"]), to, axis, o, nm))
	rev += 1
	res = {}
	_fill_drives()
	_sync_scrub()
	a._refresh(false)
	a._say("Joint added: %s (%s). Scrub or Run the sweep to see the loop move" % [nm, ["turns about", "slides along", "welded, axis"][jkind_ob.selected] + " " + ["X", "Y", "Z"][axis_ob.selected]])


func pick(nm: String) -> void:
	drive = nm
	rev += 1
	res = {}
	scrub_on = false
	_fill_drives()
	_sync_scrub()
	a._refresh(false)


func add_drive() -> void:
	var p := a._sel_part()
	if p.is_empty():
		a._say("Select the part that moves first (click it or its row), then Add drive")
		return
	var lo := a._num(lo_e.text, 0.0)
	var hi := a._num(hi_e.text, 90.0)
	if absf(hi - lo) < 1e-9:
		a._say("The range is empty: From and To must differ")
		return
	var kind := "rotate" if kind_ob.selected == 0 else "slide"
	var axis: Vector3 = AssemblyUI.AXES[axis_ob.selected]
	var o := Vector3(a._num((org_e[0] as LineEdit).text, 0.0), a._num((org_e[1] as LineEdit).text, 0.0), a._num((org_e[2] as LineEdit).text, 0.0))
	var nm := AssemblyMotion.free_drive_name(a.asm, String(p["name"]))
	a.push_undo("drive " + nm)
	AssemblyMotion.set_drive(a.asm, AssemblyMotion.make_drive(nm, String(p["id"]), kind, axis, o, lo, hi))
	drive = nm
	rev += 1
	res = {}
	scrub_on = false
	_fill_drives()
	_sync_scrub()
	a._refresh(false)
	a._say("%s is a drive: it %s %s %s to %s %s. Run the sweep to check it" % [nm, "turns about" if kind == "rotate" else "slides along", ["X", "Y", "Z"][axis_ob.selected], a._fmt(lo), a._fmt(hi), "deg" if kind == "rotate" else "mm"])


func run() -> Dictionary:
	if drive == "":
		a._say("Add a drive first")
		return {}
	var steps := clampi(int(a._num(steps_e.text, 36.0)), 1, 720)
	res = AssemblyMotion.check_motion(a.asm, drive, steps)
	for c in list_vb.get_children():
		list_vb.remove_child(c)
		c.queue_free()
	var lines := AssemblyMotion.words(a.asm, drive, res)
	if not bool(res.get("ok", false)):
		a._say("NOT DONE: " + String(res.get("why", "")))
	elif lines.is_empty():
		list_vb.add_child(a._lbl("No clash over the whole range", 12, "asm_motion_none"))
	for i in lines.size():
		var l := a._lbl(lines[i], 12, "asm_motion_row_%d" % i)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(W - 24.0, 0)
		l.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		list_vb.add_child(l)
	var lw := AssemblyLoop.lock_words(res, "deg" if String(AssemblyMotion.drive_of(a.asm, drive).get("kind", "rotate")) == "rotate" else "mm")
	for i in lw.size():
		var l := a._lbl(lw[i], 12, "asm_motion_lock_%d" % i)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(W - 24.0, 0)
		l.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
		list_vb.add_child(l)
	_sync_scrub()
	var cl: Array = res.get("clashes", [])
	if not cl.is_empty():
		scrub.value = float(cl[0]["at"])   # the first clash on screen
		set_scrub(float(cl[0]["at"]))
	a._refresh(false)
	if bool(res.get("ok", false)):
		a._say("Check motion: %d clash%s, %d steps, %d ms" % [lines.size(), "" if lines.size() == 1 else "es", steps, int(res["ms"])])   # short: a long line drew over the Export row (the kernel-call counts are in the result)
	return res


func _sync_scrub() -> void:
	var d := AssemblyMotion.drive_of(a.asm, drive)
	scrub.editable = not d.is_empty()
	if d.is_empty():
		scrub.set_block_signals(true)
		scrub.value = scrub.min_value
		scrub.set_block_signals(false)
		at_l.text = ""
		return
	var r: Array = d["range"]
	scrub.set_block_signals(true)
	scrub.min_value = minf(float(r[0]), float(r[1]))
	scrub.max_value = maxf(float(r[0]), float(r[1]))
	scrub.step = 0.0
	scrub.value = scrub_v if scrub_on else float(r[0])
	scrub.set_block_signals(false)
	_at_words()


func set_scrub(v: float) -> void:
	if AssemblyMotion.drive_of(a.asm, drive).is_empty():
		return
	scrub_on = true
	scrub_v = v
	_at_words()
	a._refresh(false)


func _at_words() -> void:
	var d := AssemblyMotion.drive_of(a.asm, drive)
	if d.is_empty():
		at_l.text = ""
		return
	var u := "deg" if String(d.get("kind", "rotate")) == "rotate" else "mm"
	var v := scrub_v if scrub_on else float((d["range"] as Array)[0])
	var t := "%s at %s %s" % [drive, a._fmt(snappedf(v, 0.01)), u]
	if AssemblyLoop.has_joints(a.asm):
		var s := _loop_at(v)
		if not bool(s["ok"]):
			at_l.text = t + ": NOT SOLVED: " + String(s["why"])
			return
	if not res.is_empty():
		var pairs := AssemblyMotion.clashing_at(res, v)
		var names: PackedStringArray = []
		for pr in pairs:
			names.append("%s x %s" % [_name(pr[0]), _name(pr[1])])
		t += (": CLASH " + ", ".join(names)) if not names.is_empty() else ": clear"
	at_l.text = t


func _name(id: String) -> String:
	var i := Assembly.index_of(a.asm, id)
	return String(a.asm["parts"][i]["name"]) if i >= 0 else id


func scrubbing() -> bool:
	return scrub_on and panel.visible and not AssemblyMotion.drive_of(a.asm, drive).is_empty()


## the part's place on screen: moved by the scrubbed drive, else the record's pose
func xf_of(p: Dictionary) -> Transform3D:
	if scrubbing():
		if AssemblyLoop.has_joints(a.asm):
			var mv: Dictionary = _loop_at(scrub_v)["moves"]
			var id := String(p["id"])
			return (mv[id] as Transform3D) * Assembly.xf_of(p) if mv.has(id) else Assembly.xf_of(p)
		return AssemblyMotion.xf_at(a.asm, drive, scrub_v, p)
	return Assembly.xf_of(p)


## G2LOOP: the loop solver's pose at v, solved once per value and record change (every part's xf_of asks)
func _loop_at(v: float) -> Dictionary:
	var k := "%d|%s|%s" % [rev, drive, str(v)]
	if k != _loop_key:
		_loop_sol = AssemblyLoop.solve(a.asm, drive, v)
		_loop_key = k
	return _loop_sol


## red over every part in a clash of the last sweep
func overlay_of(id: String) -> Material:
	if res.is_empty() or not panel.visible:
		return null
	for c in res.get("clashes", []):
		if String(c["ida"]) == id or String(c["idb"]) == id:
			return _red
	return null


func red_ids() -> Array:
	var out: Array = []
	for p in a.asm["parts"]:
		if overlay_of(String(p["id"])) != null:
			out.append(String(p["id"]))
	return out
