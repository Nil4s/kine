## godot --path . --position 4000,4000 -s tests/walk6_beginner_test.gd   (BEGINNER WALK-THROUGH, round 6: BUILDING, chooser, Easy Part, Expert Part)
## A first-time user who only clicks what they SEE (no keys, no docs). Start screen -> new 3D BUILDING project -> "What do you want
## to build?" -> a house in Easy, Part in Easy, Part in Expert, "Use in a scene", and back. Every press is a real mouse click or
## drag on a visible control found by its visible text or its tooltip. A goal the UI does not offer is NOT DONE; nothing is worked
## around. Screenshot of every stuck point: C:/Temp/claude/walk6/. Each goal prints "== END <goal>: done=yes|NO clicks=N" and, for
## a NO, "STUCK: ...". KNOWN = a goal that does not pass today (baseline in BASE): the suite exits 0 and prints "FAIL" only for a
## goal that passed in the baseline and no longer does (a regression). A KNOWN goal that starts passing prints "NOW PASSES".
## Only user:// is written (the project's own test folder); the AI video button is never pressed.
extends SceneTree

const OUT := "C:/Temp/claude/walk6/"
## baseline: true = passes today (a miss is a FAIL), false = KNOWN not done (a miss is only reported)
const BASE := {
	"1 house in Easy": true,
	"2 part in Easy from the chooser": true,
	"2b (detour) Part Expert, then find Easy on the ribbon": true,
	"3 sword 1 m long": false,
	"4 round the blade edges": true,
	"5 cut a hole in the crate": true,
	"6 undo my last change": true,
	"7 put my sword in a scene": true,
	"8 part in Expert: draw a box, pull it up": true,
	"9 undo in Expert": true,
	"10 go back to the house": true,
}

var m: Node
var bc: BuildChoose
var n_shot := 0
var lines: Array = []
var clicks := 0
var t0 := 0
var goal := ""
var regress := 0
var results := {}
var stuck_at := {}


func say(s: String) -> void:
	print(s)
	lines.append(s)


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):
		walk(c, out)
	return out


func visible_nodes() -> Array:
	var out := []
	for n in walk(root, []):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			out.append(n)
	return out


func visible_buttons() -> Array:
	var out := []
	for n in visible_nodes():
		if n is Button and not (n as Button).disabled:
			out.append(n)
	return out


func text_of(b: Button) -> String:
	if b.text.strip_edges() != "":
		return b.text.strip_edges()
	for n in walk(b, []):
		if n is Label and (n as Label).text.strip_edges() != "":
			return (n as Label).text.strip_edges()
	return ""


## a visible button by the words on it ("contains"), or by its tooltip when it is an icon only
func find_btn(txt: String, tip := false) -> Button:
	var low := txt.to_lower()
	for b in visible_buttons():
		if tip:
			if b.tooltip_text.to_lower().contains(low):
				return b
		elif text_of(b).to_lower().contains(low):
			return b
	return null


func btn_names() -> String:
	var out := []
	for b in visible_buttons():
		var t := text_of(b)
		if t == "" and b.tooltip_text != "":
			t = "[icon: " + b.tooltip_text.left(40) + "]"
		if t != "":
			out.append(t.replace("\n", " / "))
	return str(out)


func visible_words() -> String:
	var out := []
	for n in visible_nodes():
		if n is Label and (n as Label).text.strip_edges() != "":
			out.append((n as Label).text.strip_edges().left(70))
	return str(out)


func mouse_btn(down: bool, p: Vector2, which := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = which
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if which == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	root.push_input(e, true)


func move(p: Vector2, rel: Vector2, mask := MOUSE_BUTTON_MASK_LEFT) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = mask
	root.push_input(e, true)


func hover(p: Vector2) -> void:
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await process_frame


func hit_name() -> String:
	var h := get_root().get_viewport().gui_get_hovered_control()
	return "none" if h == null else str(h.name) + " (" + h.get_class() + ")"


func click_at(p: Vector2) -> void:
	await hover(p)
	mouse_btn(true, p)
	await process_frame
	mouse_btn(false, p)
	await idle(3)


## a real click on a Control: the mouse goes down and up on its middle
func click_ctl(c: Control) -> bool:
	var p := c.get_global_rect().get_center()
	await hover(p)
	var under := get_root().get_viewport().gui_get_hovered_control()
	var inside := under != null and (under == c or c.is_ancestor_of(under))
	if not inside and c is Button and not (under is Button and under.get_parent() == c.get_parent()):
		say("   COVERED: the click at %s lands on %s, not on the button" % [str(p), hit_name()])
	await click_at(p)
	return true   # the press happened; "COVERED" above is only a hint (the hovered control lags one frame behind the pointer)


## is the button what the pointer reaches at its middle? (a button under another bar is not something a beginner can see or press)
func reachable(b: Button) -> bool:
	var p := b.get_global_rect().get_center()
	var top: Control = null
	for n in visible_nodes():   # tree order = draw order: the last control under the point that takes the mouse wins
		if n is Control and (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE and (n as Control).get_global_rect().has_point(p):
			top = n
	return top != null and (top == b or b.is_ancestor_of(top))


func click_text(txt: String, tip := false) -> bool:
	var low := txt.to_lower()
	var hidden := 0
	for b in visible_buttons():
		var hit: bool = b.tooltip_text.to_lower().contains(low) if tip else text_of(b).to_lower().contains(low)
		if not hit:
			continue
		if not await reachable(b):
			hidden += 1
			continue
		clicks += 1
		say("   click '%s'" % (text_of(b).replace("
", " / ") if not tip else "[" + b.tooltip_text.left(50) + "]"))
		await click_at(b.get_global_rect().get_center())
		return true
	say("   NOT VISIBLE: no %s reads '%s'%s" % ["tooltip" if tip else "button", txt, (" (%d match(es) are covered by another bar)" % hidden) if hidden > 0 else ""])
	return false


func drag_path(a: Vector2, b: Vector2) -> void:
	clicks += 1
	await hover(a)
	say("   drag %s -> %s (under the pointer: %s)" % [str(a), str(b), hit_name()])
	mouse_btn(true, a)
	await process_frame
	var st := (b - a) / 8.0
	for i in 8:
		move(a + st * (i + 1), st)
		await process_frame
	mouse_btn(false, b)
	await idle(4)


func shot(nm: String) -> void:
	await idle(3)
	await RenderingServer.frame_post_draw
	n_shot += 1
	var f := "%s%02d_%s.png" % [OUT, n_shot, nm]
	root.get_texture().get_image().save_png(f)
	say("   shot %s | page %s | easy %s | part on %s easy-part %s" % [f.get_file(), str(m.cur_page), str(m.easy.on), str(m.bld.part.on), str(m.bld.part.easy)])
	say("   visible buttons: %s" % btn_names())
	say("   words: %s" % visible_words())


func begin_goal(s: String) -> void:
	goal = s
	clicks = 0
	t0 = Time.get_ticks_msec()
	say("\n== GOAL %s ==" % s)


func stuck(why: String, nm: String) -> void:
	stuck_at[goal] = why
	say("   STUCK: " + why)
	await shot("STUCK_" + nm)


func end_goal(ok: bool, note: String) -> void:
	results[goal] = {"ok": ok, "clicks": clicks, "stuck": stuck_at.get(goal, "")}
	var base: bool = BASE.get(goal, false)
	var tag := ""
	if base and not ok:
		tag = " FAIL (regressed from PASS)"
		regress += 1
	elif ok and not base:
		tag = " NOW PASSES (update BASE)"
	elif not ok:
		tag = " KNOWN"
	say("== END %s: done=%s clicks=%d time=%.1fs %s%s" % [goal, "yes" if ok else "NO", clicks, (Time.get_ticks_msec() - t0) / 1000.0, note, tag])


func rec() -> Dictionary:
	return m.S.part if m.S.part is Dictionary else {}


func feats(t := "") -> int:
	var n := 0
	for f in rec().get("features", []):
		if t == "" or String(f.get("t", "")) == t:
			n += 1
	return n


## the longest side of the solid, in mm (0 = nothing solid)
func longest_mm() -> float:
	if rec().is_empty() or not Part.available():
		return 0.0
	var r: Dictionary = Part.replay(rec())
	if int(r.get("bodies", 0)) == 0:
		return 0.0
	var a: AABB = r["aabb"]
	return maxf(a.size.x, maxf(a.size.y, a.size.z)) / Part.MM


func sliders() -> Array:
	var out := []
	for n in visible_nodes():
		if n is HSlider:
			out.append(n)
	return out


## the words next to a slider: the first Label of its row
func slider_label(s: HSlider) -> String:
	var p := s.get_parent()
	for c in p.get_children():
		if c is HBoxContainer:
			for cc in c.get_children():
				if cc is Label and (cc as Label).text.strip_edges() != "":
					return (cc as Label).text
	return str(s.name)


## a real click on the slider's track at a value (a beginner drags the knob; a click on the track is the same press and release)
func slide_to(s: HSlider, v: float) -> void:
	clicks += 1
	var r := s.get_global_rect()
	var ratio := clampf((v - s.min_value) / (s.max_value - s.min_value), 0.0, 1.0)
	var p := Vector2(r.position.x + 8.0 + (r.size.x - 16.0) * ratio, r.get_center().y)
	say("   slider '%s' (%s..%s) to %s at %s" % [slider_label(s), str(s.min_value), str(s.max_value), str(v), str(p)])
	await hover(p)
	mouse_btn(true, p)
	await process_frame
	move(p + Vector2(1, 0), Vector2(1, 0))
	await process_frame
	mouse_btn(false, p + Vector2(1, 0))
	await idle(8)


func start_building(ss: StartScreen) -> void:
	ss.show_screen()
	await idle(12)
	var card: Control = ss._cards["building"]
	var go: Control = card.find_child("start_building", true, false)   # the card's own "Start" button (Easy / Expert buttons exist for animation only)
	clicks += 1
	say("   (check) building card rect %s, Start button %s, start screen visible %s" % [str(card.get_global_rect()), "none" if go == null else str(go.get_global_rect()) + " vis " + str(go.is_visible_in_tree()), str(ss.is_visible_in_tree())])
	if go != null and go.is_visible_in_tree():
		say("   click 'Start' on the 3D BUILDING card")
		await click_ctl(go)
	else:
		say("   click the 3D BUILDING card")
		await click_ctl(card)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(8)


func viewport_center() -> Vector2:
	var vs := root.get_visible_rect().size
	return Vector2(vs.x * 0.42, vs.y * 0.55)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for old in DirAccess.get_files_at(OUT):   # this test's own shots from an earlier run
		if old.ends_with(".png"):
			DirAccess.remove_absolute(OUT + old)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(6)
	var ss: StartScreen = m.start_screen
	bc = m.build_choose
	bc.auto = true   # a real launch gets the chooser; a test does not unless asked
	var dirt := "user://walk6_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dirt))
	ss.dirs_override = [dirt]
	say("CAD kernel available: %s" % str(Part.available()))

	# 1. A HOUSE IN EASY: the start screen's Building card, then the chooser's House card (Easy)
	begin_goal("1 house in Easy")
	await start_building(ss)
	await shot("chooser")
	var chooser_ok: bool = bc.open and bc.root_box.is_visible_in_tree()
	var hz := false
	var rooms0 := 0
	if chooser_ok:
		hz = await click_text("Rooms and walls")   # the House card's Easy button (the words on it)
	else:
		await stuck("the chooser did not open after the Building card", "no_chooser")
	await idle(6)
	if hz:
		await drag_path(m.cam.unproject_position(Vector3(0, 0, 0)), m.cam.unproject_position(Vector3(6, 0, 4)))   # drag on the floor, as the hint says
		await shot("house_room")
	var bd: Dictionary = m.bld._bld() if m.bld.has_method("_bld") else {}
	var nrooms: int = bd.get("rooms", []).size()
	if nrooms == 0:
		await stuck("after House > Easy the drag on the floor made no room (rooms %d); on screen: %s" % [nrooms, btn_names()], "house_no_room")
	end_goal(chooser_ok and hz and m.easy.on and nrooms > 0, "(chooser %s, Easy on %s, rooms %d)" % [str(chooser_ok), str(m.easy.on), nrooms])

	# 2. PART IN EASY FROM THE CHOOSER: the little icon-only button reopens the chooser, then the Part card's Easy button
	begin_goal("2 part in Easy from the chooser")
	var reopen := false
	if not bc.open:
		reopen = await click_text("Pick what to build", true)
		await idle(6)
	if not bc.open:
		await stuck("no way to reopen the chooser: its button is icon-only (tooltip 'Pick what to build...') or hidden in Easy", "no_reopen")
	var pe := false
	if bc.open:
		await shot("chooser_again")
		pe = await click_text("Shape + sliders")
		await idle(8)
	var easy_part_open: bool = m.bld.part.easy and m.bld.part.on
	await shot("part_easy_try")
	if not easy_part_open:
		await stuck("Part > 'Shape + sliders' did not open Easy Part: build_choose.gd _start() still answers 'Easy Part is coming' for easy_on (the one-line status, not a button)", "easy_part_blocked")
	end_goal(easy_part_open, "(reopen clicked %s, Shape+sliders clicked %s)" % [str(reopen), str(pe)])

	# the beginner who got refused tries the other card: Part > Expert, then looks for the Easy button on the Part ribbon
	var via_expert := false
	if not easy_part_open:
		begin_goal("2b (detour) Part Expert, then find Easy on the ribbon")
		if not bc.open:
			await click_text("Pick what to build", true)
		var px := await click_text("Sketch + timeline")
		await idle(8)
		await shot("part_expert_first")
		var eb := await click_text("Easy")   # the only "Easy" a beginner can see on the Part ribbon
		await idle(10)
		via_expert = m.bld.part.easy
		if not via_expert:
			await stuck("after Part > Expert the ribbon's 'Easy' did not open Easy Part", "no_easy_btn")
		await shot("part_easy_via_expert")
		end_goal(via_expert, "(Expert card %s, Easy clicked %s)" % [str(px), str(eb)])
	if not m.bld.part.easy:
		m.bld.part.open_easy()   # not a goal step: the walk needs Easy Part open for goals 3-7 (reported above)
		await idle(10)
		say("   (check) Easy Part forced open through code so goals 3-7 can be walked")

	# 3. A SWORD 1 M LONG: pick the Sword chip and drag the length slider
	begin_goal("3 sword 1 m long")
	await click_text("Sword")
	await shot("sword")
	var before := longest_mm()
	var ss_ := sliders()
	var names := []
	for s in ss_:
		names.append("%s %s..%s" % [slider_label(s), str(s.min_value), str(s.max_value)])
	say("   sliders on screen: %s | solid is %.0f mm long" % [str(names), before])
	var len_s: HSlider = null
	for s in ss_:
		var l := slider_label(s).to_lower()
		if l.contains("length") or l.contains("long") or l.contains("blade"):
			len_s = s
			break
	if len_s == null and not ss_.is_empty():
		len_s = ss_[0]
	var got := before
	if len_s != null:
		var cm := 100.0   # 1 m in the slider's own unit (cm)
		await slide_to(len_s, minf(cm, len_s.max_value))
		got = longest_mm()
		await shot("sword_slid")
		if len_s.max_value < cm:
			await stuck("the longest the '%s' slider goes is %s cm: a 1 m sword cannot be made with it" % [slider_label(len_s), str(len_s.max_value)], "sword_max")
		elif absf(got - 1000.0) > 30.0:
			await stuck("slid '%s' to 100 but the solid is %.0f mm long (the slider's unit is not said on the control, or it measures one part only)" % [slider_label(len_s), got], "sword_len")
	else:
		await stuck("no slider on screen", "no_slider")
	end_goal(absf(got - 1000.0) <= 30.0, "(solid %.0f mm)" % got)

	# 4. ROUND THE BLADE EDGES
	begin_goal("4 round the blade edges")
	var f0 := feats("fillet")
	await click_text("Round the edges")
	await idle(8)
	await shot("rounded")
	var f1 := feats("fillet")
	if f1 <= f0:
		await stuck("'Round the edges' added no fillet (status: %s)" % visible_words().left(300), "round_none")
	end_goal(f1 > f0, "(fillets %d -> %d)" % [f0, f1])

	# 5. CUT A HOLE IN THE CRATE
	begin_goal("5 cut a hole in the crate")
	var cr := await click_text("Crate")
	await idle(8)
	var h0 := feats("extrude") + feats("hole") + feats("cut")
	var cuts0 := 0
	for f in rec().get("features", []):
		if String(f.get("op", "")) == "cut" or String(f.get("t", "")) == "hole":
			cuts0 += 1
	await click_text("Cut a hole")
	await idle(10)
	var cuts1 := 0
	for f in rec().get("features", []):
		if String(f.get("op", "")) == "cut" or String(f.get("t", "")) == "hole":
			cuts1 += 1
	await shot("crate_hole")
	if cuts1 <= cuts0:
		await stuck("'Cut a hole' on the crate cut nothing (crate chip clicked %s; words: %s)" % [str(cr), visible_words().left(300)], "hole_none")
	end_goal(cuts1 > cuts0, "(cut steps %d -> %d, h0 %d)" % [cuts0, cuts1, h0])

	# 6. UNDO MY LAST CHANGE
	begin_goal("6 undo my last change")
	var js0 := JSON.stringify(rec())
	var ub := await click_text("Undo")
	await idle(8)
	var js1 := JSON.stringify(rec())
	await shot("undone")
	if js0 == js1:
		await stuck("the visible 'Undo' (clicked %s) changed nothing in the part" % str(ub), "undo_none")
	end_goal(js0 != js1, "(record changed %s)" % str(js0 != js1))

	# 7. PUT MY SWORD IN A SCENE
	begin_goal("7 put my sword in a scene")
	var dbg := find_btn("Sword")
	say("   (check) before goal 7: Sword chip %s rect %s panel vis %s easy-part %s" % [str(dbg != null), str(dbg.get_global_rect()) if dbg else "-", str(m.bld.part.ep.panel.is_visible_in_tree()), str(m.bld.part.easy)])
	await click_text("Sword")
	await idle(6)
	var us := await click_text("Use in a scene")
	await idle(10)
	await shot("use_in_scene_easy")
	var staged: bool = m.cur_page == "STAGE"
	if not us:
		await stuck("Easy Part's screen has no 'Use in a scene' button (it only exists on the Expert BUILD bar)", "no_use_btn")
	elif not staged:
		await stuck("'Use in a scene' did not go to STAGE: use_in_scene only knows houses with a room (build_ui.gd use_in_scene), page is %s" % str(m.cur_page), "use_refused")
	end_goal(staged, "(button found %s, page %s)" % [str(us), str(m.cur_page)])

	# 8. PART IN EXPERT: draw a box, pull it up (a fresh part)
	begin_goal("8 part in Expert: draw a box, pull it up")
	if m.bld.part.easy:
		await click_text("Expert")
		await idle(8)
	await shot("expert_part")
	m.S.part = {}   # a fresh Part project for the draw (not a goal step; undo is not used for it)
	m.bld.part._rec_sig = ""
	m.bld.part.sync()
	await idle(6)
	var e0 := feats("extrude")
	var rb := await click_text("Rectangle")
	var vc2 := viewport_center()
	await drag_path(vc2, vc2 + Vector2(160, 100))
	await shot("expert_rect")
	var fin := await click_text("Finish sketch")
	await idle(6)
	var ex := await click_text("Extrude")
	await idle(8)
	await shot("expert_extrude_dialog")
	var okb := await click_text("OK")
	await idle(10)
	await shot("expert_extruded")
	var e1 := feats("extrude")
	if e1 <= e0:
		await stuck("a first-time click path Rectangle > drag > Finish sketch > Extrude > OK made no solid (rect %s, finish %s, extrude %s, ok %s); words: %s" % [str(rb), str(fin), str(ex), str(okb), visible_words().left(260)], "expert_no_solid")
	end_goal(e1 > e0, "(extrudes %d -> %d)" % [e0, e1])

	# 9. UNDO IN EXPERT
	begin_goal("9 undo in Expert")
	var j0 := JSON.stringify(rec())
	var ub2 := await click_text("Undo")
	if ub2 == false:
		await click_text("Undo", true)
	await idle(8)
	var j1 := JSON.stringify(rec())
	await shot("expert_undone")
	if j0 == j1:
		await stuck("no visible Undo on the Expert Part screen changed the part (Undo is on the top bar, or only a key)", "expert_undo_none")
	end_goal(j0 != j1, "(record changed %s)" % str(j0 != j1))

	# 10. GO BACK TO THE HOUSE: the way back a beginner would look for
	begin_goal("10 go back to the house")
	var had_part: bool = m.bld.part.on
	var b10 := await click_text("What to build") if find_btn("What to build") != null else await click_text("Pick what to build", true)
	await idle(8)
	var h_btn := false
	if bc.open:
		h_btn = await click_text("Rooms and walls")
		if not h_btn:
			h_btn = await click_text("Plans, stairs")
		await idle(8)
	else:
		await stuck("no visible way back to the house from Expert Part: the ribbon's reopen-chooser button is hidden while Part is on; only the pressed 'Part' button is left to try", "no_back_house")
		var pt := await click_text("Part")   # the pressed Part button: a beginner tries it as a toggle
		await idle(8)
		h_btn = pt and not m.bld.part.on and find_btn("Room") != null
	await shot("back_to_house")
	var bd2: Dictionary = m.bld._bld()
	var rooms_back: int = bd2.get("rooms", []).size()
	var still_part: bool = m.bld.part.on
	if bc.open == false and h_btn and still_part:
		await stuck("House card clicked but the Part workspace is still on (part.on) and the house tools are hidden", "house_still_part")
	elif h_btn and rooms_back == 0:
		await stuck("back on the house page but the room from goal 1 is gone (rooms %d)" % rooms_back, "house_room_lost")
	end_goal(h_btn and not still_part and rooms_back > 0, "(was in Part %s, button %s, house button %s, part still on %s, rooms %d)" % [str(had_part), str(b10), str(h_btn), str(still_part), rooms_back])

	say("\n== SUMMARY ==")
	for g in BASE:
		var r: Dictionary = results.get(g, {})
		var tag := "n/a " if not results.has(g) else ("PASS" if r.get("ok", false) else "NO  ")   # not walked: the flow skipped it (e.g. the detour when Easy Part opens)
		say("%-44s %s  clicks=%s  %s" % [g, tag, str(r.get("clicks", "-")), String(r.get("stuck", "")).left(140)])
	say("regressions: %d" % regress)
	var f := FileAccess.open(OUT + "log.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	TestFiles.cleanup()
	quit(1 if regress > 0 else 0)
