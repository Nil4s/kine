extends SceneTree
## godot --path . --position 4000,4000 -s tests/buildwords_test.gd     (BUILD mode phase 1e: WORDS; scripts/build/build_words.gd + build_words_ui.gd; needs a window)
## Bars, written before measuring:
##   1 PARSE   30+ sentences -> the expected plan fields (sizes snapped to 0.5 m, "8.3" -> 8.5 with a note; counts, walls, floors, roof, garage;
##             the words that were not understood are LISTED); the mockup's sentence builds a closed, manifold 8 x 6 house, 2 floors, 1 door,
##             4 windows (2 front upstairs, 1 each side), gable overhang 0.45; the defaults it did not hear are tagged
##   2 EDITS   12 edit phrases on that house each change exactly the one thing they say (the rest of the record is equal), and say what was done
##   3 REFUSE  a typo gets "Did you mean", a size out of range, a sentence that is no building, an edit with nothing built, an edit that
##             cannot be done: refused plainly; nothing is built or changed by a refusal
##   4 UI      real clicks and keys: the Words tool, typing the sentence, the cards (numbered, with their "default:" tags) BEFORE building, the
##             record still empty and no undo step; a card's number typed in (8.3 -> 8.5 said), Build it = exactly ONE undo step (undo empties,
##             redo brings it back), Build it again = "built already", no step; "Then just say" chips fill the box; an edit sentence + Build it =
##             ONE undo step each (move the door, remove the roof, make the second floor taller); a typo is refused with a "Did you mean" button
##             that fixes the word; half-understood words are listed in the plan; Piece stays greyed
## Screenshot: C:/Temp/claude/build1e/words.png (matches build_words.png). Only user:// is written.
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/build1e"
const DIRT := "user://buildwords_test"
const MOCK := "a 2-floor house 8 x 6 m with a door and 4 windows"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func key(k: Key, uni := 0, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.unicode = uni
		e.pressed = down
		e.ctrl_pressed = ctrl
		root.push_input(e, true)
		await process_frame


## real key presses, one per character
func type_text(s: String) -> void:
	for i in s.length():
		var c := s.substr(i, 1)
		var code := c.to_upper().unicode_at(0)
		var k: Key = KEY_SPACE
		if c == ".":
			k = KEY_PERIOD
		elif c == ",":
			k = KEY_COMMA
		elif c != " ":
			k = code as Key
		await key(k, c.unicode_at(0))
	await idle(2)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func vol(b: Dictionary) -> float:
	return KMeshValidate._volume(Building.to_kmesh(b))


func closed(b: Dictionary) -> bool:
	var k := Building.to_kmesh(b)
	return k.boundary_edge_count() == 0 and k.is_manifold()


func rec(b: Dictionary) -> String:
	return JSON.stringify(Building.to_file(b)) if not b.is_empty() else "{}"


## the plan a sentence gives, or {} (refused)
func plan_of(s: String, b := {}) -> Dictionary:
	var r := BuildWords.parse(s, b)
	return r["plan"] if bool(r["ok"]) and r["kind"] == "plan" else {}


func has(P: Dictionary, want: Dictionary) -> bool:
	if P.is_empty():
		return false
	for k in want:
		var a: Variant = P.get(k)
		var w: Variant = want[k]
		if (w is float or w is int) and (a is float or a is int):
			if absf(float(a) - float(w)) > 1e-6:
				return false
		elif a != w:
			return false
	return true


func parse_row(s: String, want: Dictionary, extra := "") -> void:
	var r := BuildWords.parse(s, {})
	var P: Dictionary = r.get("plan", {})
	var good := bool(r["ok"]) and has(P, want)
	if good and extra == "notes":
		good = not (r["notes"] as Array).is_empty()
	ok(good, "1 \"%s\" -> %s%s" % [s, JSON.stringify(want), "" if good else "   GOT " + JSON.stringify(P) + " " + String(r.get("error", ""))])


func same_except(a: Dictionary, b: Dictionary, mutate: Callable) -> bool:
	var a2: Dictionary = a.duplicate(true)
	mutate.call(a2)
	return JSON.stringify(Building.to_file(a2)) == JSON.stringify(Building.to_file(b))


func edit_row(house: Dictionary, s: String, mutate: Callable, label: String) -> void:
	var r := BuildWords.parse(s, house)
	if not bool(r["ok"]) or r["kind"] != "edit":
		ok(false, "2 \"%s\" is an edit: %s" % [s, r.get("error", r["kind"])])
		return
	var after: Dictionary = house.duplicate(true)
	var d := BuildWords.apply_edit(after, r["edit"])
	var good: bool = bool(d["ok"]) and same_except(house, after, mutate) and rec(house) != rec(after) and String(d["say"]) != ""
	ok(good, "2 \"%s\": %s -> \"%s\"%s" % [s, label, d.get("say", d.get("error", "")), "" if good else "   (the record changed more or less than said)"])


func refuse_row(s: String, b: Dictionary, want_did := "") -> void:
	var r := BuildWords.parse(s, b)
	var good := not bool(r["ok"]) and String(r["error"]) != "" and (want_did == "" or (String(r["did"]) == want_did and String(r["error"]).contains("Did you mean: " + want_did)))
	ok(good, "3 \"%s\" is refused: %s" % [s, r["error"] if not bool(r["ok"]) else "BUILT " + JSON.stringify(r.get("plan", {}))])


func _init() -> void:
	# ---- 1 PARSE (no window needed)
	parse_row(MOCK, {"w": 8.0, "d": 6.0, "floors": 2, "door_n": 1, "win_n": 4, "roof": "gable", "overhang": 0.45, "floor_h": 2.8})
	parse_row("8 by 6 m house", {"w": 8.0, "d": 6.0, "floors": 1})
	parse_row("a 4 metres wide, 6 long cottage", {"w": 4.0, "d": 6.0})
	parse_row("two storeys 10x7 house", {"floors": 2, "w": 10.0, "d": 7.0})
	parse_row("three floor house 6 x 6", {"floors": 3, "w": 6.0, "d": 6.0})
	parse_row("a bungalow 9 x 5 with 2 windows", {"floors": 1, "w": 9.0, "d": 5.0, "win_n": 2})
	parse_row("8.3 x 6 house", {"w": 8.5, "d": 6.0}, "notes")
	parse_row("house 7.8 by 5.2 m", {"w": 8.0, "d": 5.0}, "notes")
	parse_row("a house with a door on the back", {"door_walls": ["back"], "door_n": 1})
	parse_row("a house with 2 doors", {"door_n": 2})
	parse_row("a house with no door and 2 windows", {"door_n": 0, "win_n": 2})
	parse_row("a house with windows on each side", {"win_each": true, "win_n": 1})
	parse_row("2 windows on each side", {"win_each": true, "win_n": 2})
	parse_row("a flat roof house", {"roof": "flat"})
	parse_row("a house with a shed roof", {"roof": "shed"})
	parse_row("a house with no roof", {"roof": "none"})
	parse_row("a house with a 0.6 m overhang", {"overhang": 0.6})
	parse_row("a house with a garage", {"garage": "right"})
	parse_row("a house with a garage on the left", {"garage": "left"})
	parse_row("a 2 floor house with 3 m floors", {"floors": 2, "floor_h": 3.0})
	parse_row("a house 6 x 4 with windows on the left and right", {"win_walls": ["left", "right"], "win_each": false})
	parse_row("a house with a 1.2 m door", {"door_w": 1.2, "door_n": 1})
	parse_row("a house with a front door and 3 windows at the back", {"door_walls": ["front"], "win_walls": ["back"], "win_n": 3})
	parse_row("single storey house 5 x 5", {"floors": 1, "w": 5.0, "d": 5.0})
	parse_row("a 2 storey house with a garage and 6 windows", {"floors": 2, "garage": "right", "win_n": 6})
	parse_row("make a 2-floor house 6 x 6", {"floors": 2, "w": 6.0, "d": 6.0})
	parse_row("a house 8 m wide 5 m deep", {"w": 8.0, "d": 5.0})
	parse_row("I want a small cottage 6 by 4 please", {"w": 6.0, "d": 4.0})
	parse_row("a house with 4 windows and a door in the centre", {"win_n": 4, "door_n": 1, "door_at": "centre"})
	var pur := BuildWords.parse("a house with a purple door", {})
	ok(bool(pur["ok"]) and (pur["ignored"] as Array) == ["purple"] and String(pur["notes"][0]).contains("purple"), "1 an unknown word is LISTED, not guessed: %s" % [pur["notes"]])
	var sn := BuildWords.parse("8.3 x 6 house", {})
	ok(String(sn["notes"][0]).contains("8.3 became 8.5") and float(sn["plan"]["w"]) == 8.5, "1 \"8.3 x 6\" -> 8.5 and says so: %s" % [sn["notes"]])
	var mk := BuildWords.parse(MOCK, {})
	var mp: Dictionary = mk["plan"]
	var lay := BuildWords.layout(mp)
	var front_up: int = lay["windows"].filter(func(w): return w["wall"] == "front" and w["storey"] == 1).size()
	var left_w: int = lay["windows"].filter(func(w): return w["wall"] == "left").size()
	var right_w: int = lay["windows"].filter(func(w): return w["wall"] == "right").size()
	ok(lay["doors"].size() == 1 and lay["doors"][0]["wall"] == "front" and lay["doors"][0]["at"] == 0.0 and lay["windows"].size() == 4 and front_up == 2 and left_w == 1 and right_w == 1,
		"1 the mockup's layout: door front centre; 4 windows = 2 front upstairs, 1 each side")
	var df: Dictionary = mk["defaults"]
	ok(bool(df["roof"]) and bool(df["door_at"]) and bool(df["win_spread"]) and not bool(df["w"]) and not bool(df["floors"]) and not bool(df["win_n"]),
		"1 defaults tagged only where the words did not say: roof, door position, window spread")
	var house := BuildWords.make_building(mp, "Bay house")
	ok(Building.storey_count(house) == 2 and house["rooms"].size() == 2 and float(house["rooms"][0]["w"]) == 8.0 and float(house["rooms"][0]["d"]) == 6.0 and house["openings"].size() == 5
		and house["roof"]["kind"] == "gable" and Building.num(house, house["roof"]["overhang"]) == 0.45 and absf(Building.num(house, "floor_height") - 2.8) < 1e-9 and closed(house) and vol(house) > 50.0,
		"1 the mockup's sentence builds 8 x 6, 2 floors, 1 door + 4 windows, gable 0.45; closed and manifold, volume %.1f m3" % vol(house))
	var cards := BuildWords.cards(mp, df)
	var titles := cards.map(func(c): return String(c["title"]))
	ok(titles == ["Room", "Floors", "Door", "Windows", "Roof"] and cards[0]["chips"][0]["text"] == "8.0 m" and cards[1]["chips"][2]["text"] == "2.8 m" and cards[2]["tag"] == "default: centre"
		and cards[3]["tag"] == "default: evenly spread" and cards[4]["tag"] == "default: gable" and cards[4]["chips"][2]["text"] == "0.45 m" and cards[2]["chips"][2]["text"] == "0.9 m",
		"1 the five cards read as the mockup: Room 8.0 m x 6.0 m, Floors 2 each 2.8 m, Door front wall centre 0.9 m, Windows 4, Roof gable 0.45 m, with their default tags")
	var gar := BuildWords.make_building(plan_of("a house 8 x 6 with a garage"), "G")
	ok(gar["rooms"].size() == 2 and String(gar["rooms"][1]["id"]) == "garage" and closed(gar), "1 a garage is a second room beside the house, one closed solid")

	# ---- 2 EDITS (on the mockup house)
	edit_row(house, "move the door to the left", func(b): b["openings"][0]["at"] = 1.0, "the front door 1.0 m to the left (seen from outside: toward +X)")
	edit_row(house, "move the door to the right", func(b): b["openings"][0]["at"] = -1.0, "the front door 1.0 m to the right")
	edit_row(house, "move the door 2 m to the left", func(b): b["openings"][0]["at"] = 2.0, "the door 2 m")
	edit_row(house, "move the door to the back wall", func(b): b["openings"][0]["wall"] = "back", "the door onto the back wall, in the middle")
	edit_row(house, "make the second floor taller", func(b): b["rooms"][1]["height"] = 3.2, "floor 2: wall 2.7 -> 3.2")
	edit_row(house, "add a window on the back", func(b): b["openings"].append({"id": "o6", "room": "r1", "wall": "back", "kind": "window", "at": 0.0, "w": "window_width", "h": "window_height", "sill": "window_sill"}), "a window on the back, ground floor")
	edit_row(house, "remove the roof", func(b): b.erase("roof"), "no roof")
	edit_row(house, "make the roof flat", func(b): b["roof"]["kind"] = "flat", "a flat roof")
	edit_row(house, "add a garage", func(b):
		b["rooms"].append({"id": "garage", "x": 7.8, "z": 0.0, "w": 3.5, "d": 6.0, "yaw": 0.0, "height": "wall_height", "thickness": "wall_thickness", "floor": true})
		b["openings"].append({"id": "o6", "room": "garage", "wall": "front", "kind": "door", "at": 0.0, "w": 2.4, "h": "door_height", "sill": 0.0}), "a garage on the right")
	edit_row(house, "add a floor", func(b): Building.add_floor(b), "a third floor")
	edit_row(house, "make the door wider", func(b): b["params"]["door_width"] = 1.2, "door_width 0.9 -> 1.2")
	var with_g: Dictionary = house.duplicate(true)
	BuildWords.apply_edit(with_g, BuildWords.parse("add a garage", house)["edit"])
	ok(closed(with_g) and with_g["rooms"].size() == 3, "2 the house with its garage is one closed solid")
	edit_row(with_g, "remove the garage", func(b):
		b["rooms"].pop_back()
		b["openings"].pop_back(), "the garage and its door go")

	# ---- 3 REFUSE
	refuse_row("make me a sandwich", {})
	refuse_row("hosue 8 x 6 m", {}, "house")
	refuse_row("a house with a doro", {}, "door")
	refuse_row("a 100 x 6 m house", {})
	refuse_row("a 9 floor house", {})
	refuse_row("make a 0 floor house", {})
	refuse_row("", {})
	refuse_row("move the door to the left", {})
	refuse_row("move the door to the moon", house)
	var r_first := BuildWords.parse("make the first floor taller", house)
	var d_first := BuildWords.apply_edit(house.duplicate(true), r_first["edit"]) if bool(r_first["ok"]) else {"ok": true, "error": ""}
	ok(not bool(d_first["ok"]) and String(d_first["error"]).contains("floors above it"), "3 \"make the first floor taller\" with a floor above: said plainly (%s)" % d_first.get("error", ""))
	var r_g := BuildWords.parse("remove the garage", house)
	ok(bool(r_g["ok"]) and not bool(BuildWords.apply_edit(house.duplicate(true), r_g["edit"])["ok"]), "3 \"remove the garage\" with no garage: refused when applied")

	# ---- 4 UI
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	var bld: BuildUI = m.bld
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	await idle(6)
	var wbtn: Button = m.ui_ribbon["BUILD"].find_child("build_tool_words", true, false)
	var pbtn: Button = m.ui_ribbon["BUILD"].find_child("build_tool_piece", true, false)
	ok(wbtn != null and not wbtn.disabled and wbtn.text == "Words" and wbtn.icon != null and not pbtn.disabled, "4 Words is a tool on the ribbon (1f: so is Piece, it is no longer greyed)")
	var n0: int = m.undo.size()
	await click_ctl(wbtn)
	await idle(3)
	var edit: LineEdit = bld.words.edit
	ok(bld.tool == "Words" and bld.words.box.visible and bld.words.plan_panel.visible and bld.words.say_row.visible and not bld.panel.visible, "4 a click on Words opens the words box, the plan and the 'Then just say' chips")
	ok(edit.has_focus(), "4 the box has the keyboard")
	var chips_t := []
	for i in 3:
		chips_t.append((bld.words.say_row.find_child("build_words_chip_%d" % i, true, false) as Button).text)
	ok(chips_t == ["move the door to the left", "make the second floor taller", "add a garage"], "4 the chips say: %s" % [chips_t])
	await click_ctl(edit)
	await type_text(MOCK)
	ok(edit.text == MOCK, "4 typed with real keys: \"%s\"" % edit.text)
	var cards_ui: VBoxContainer = bld.words.cards_box
	var nc := cards_ui.get_child_count()
	var tag_txt := []
	for i in range(1, 6):
		var tg := cards_ui.find_child("build_words_tag_%d" % i, true, false)
		tag_txt.append(((tg.get_child(0) as Label).text) if tg != null else "")
	ok(nc == 5 and tag_txt == ["", "", "default: centre", "default: evenly spread", "default: gable"], "4 BEFORE building the plan shows 5 cards, defaults tagged: %s" % [tag_txt])
	ok(m.S.building.is_empty() and m.undo.size() == n0, "4 nothing is built yet: the record is empty, no undo step")
	ok(bld.words.foot.text.contains("Nothing is built until you press Build it."), "4 the plan says: Nothing is built until you press Build it.")
	# a card's number, typed
	var wchip: LineEdit = cards_ui.find_child("build_words_chip_w", true, false)
	await click_ctl(wchip)
	await key(KEY_A, 0, true)
	await type_text("8.3")
	await key(KEY_ENTER)
	await idle(4)
	ok(float(bld.words.plan["w"]) == 8.5 and bld.words.foot.text.contains("8.3 became 8.5") and (cards_ui.find_child("build_words_chip_w", true, false) as LineEdit).text == "8.5 m",
		"4 a card's number typed (8.3) snaps to 8.5 and says so: \"%s\"" % bld.words.foot.text.replace("\n", " | "))
	var cyc: Button = cards_ui.find_child("build_words_cycle_roof", true, false)
	await click_ctl(cyc)
	await idle(3)
	ok(String(bld.words.plan["roof"]) == "flat" and m.S.building.is_empty(), "4 a click on the roof chip cycles gable -> flat (still nothing built)")
	for i in 3:
		await click_ctl(cards_ui.find_child("build_words_cycle_roof", true, false))
		await idle(2)
	ok(String(bld.words.plan["roof"]) == "gable", "4 and round to gable again")
	await click_ctl(cards_ui.find_child("build_words_chip_w", true, false))
	await key(KEY_A, 0, true)
	await type_text("8")
	await key(KEY_ENTER)
	await idle(4)
	ok(float(bld.words.plan["w"]) == 8.0, "4 the width is 8.0 m again")
	# Build it
	n0 = m.undo.size()
	await click_ctl(bld.words.go)
	await idle(4)
	var bb: Dictionary = m.S.building
	ok(not bb.is_empty() and bb["rooms"].size() == 2 and float(bb["rooms"][0]["w"]) == 8.0 and bb["openings"].size() == 5 and Building.storey_count(bb) == 2 and bb["roof"]["kind"] == "gable" and closed(bb),
		"4 Build it: 8 x 6, 2 floors, 1 door, 4 windows, gable; closed and manifold")
	ok(m.undo.size() == n0 + 1, "4 Build it is ONE undo step (%d -> %d)" % [n0, m.undo.size()])
	ok(bld.house.mesh != null and String(m.ui_status.text).begins_with("Built: 8 x 6 m, 2 floors, 1 door, 4 windows"), "4 the house shows and the status says: %s" % m.ui_status.text)
	await shot("words")
	var built_rec := rec(bb)
	m._undo()
	await idle(3)
	ok(m.S.building.is_empty() or m.S.building.get("rooms", []).is_empty(), "4 Undo takes the whole building back in one step")
	m._redo()
	await idle(3)
	ok(rec(m.S.building) == built_rec, "4 Redo brings it back exactly")
	n0 = m.undo.size()
	await click_ctl(bld.words.go)
	await idle(3)
	ok(m.undo.size() == n0 and String(m.ui_status.text).contains("built already"), "4 Build it again: \"%s\", no undo step" % m.ui_status.text)
	# edits, by the chips and Build it
	var door_at0 := float(m.S.building["openings"][0]["at"])
	await click_ctl(bld.words.say_row.find_child("build_words_chip_0", true, false))
	await idle(3)
	var cardtxt := ""
	var ct := bld.words.cards_box.find_child("build_words_card_body", true, false)
	if ct != null:
		cardtxt = (ct as Label).text
	ok(edit.text == "move the door to the left" and cardtxt.begins_with("Move the door to the left") and float(m.S.building["openings"][0]["at"]) == door_at0, "4 a 'Then just say' chip fills the box and shows the change first: \"%s\"; nothing moved yet" % cardtxt)
	n0 = m.undo.size()
	await click_ctl(bld.words.go)
	await idle(3)
	ok(m.undo.size() == n0 + 1 and float(m.S.building["openings"][0]["at"]) == door_at0 + 1.0 and String(m.ui_status.text).begins_with("Moved the door"),
		"4 Build it on 'move the door to the left': ONE undo step, the door 1 m left (at %.1f): %s" % [float(m.S.building["openings"][0]["at"]), m.ui_status.text])
	m._undo()
	await idle(2)
	ok(float(m.S.building["openings"][0]["at"]) == door_at0, "4 Undo puts the door back")
	n0 = m.undo.size()
	await click_ctl(edit)
	await type_text("remove the roof")
	await key(KEY_ENTER)
	await idle(3)
	ok(m.S.building.get("roof", {}).is_empty() and m.undo.size() == n0 + 1, "4 typing 'remove the roof' + Enter: the roof is gone, ONE undo step (%d -> %d)" % [n0, m.undo.size()])
	n0 = m.undo.size()
	await click_ctl(bld.words.say_row.find_child("build_words_chip_1", true, false))
	await click_ctl(bld.words.go)
	await idle(3)
	ok(m.undo.size() == n0 + 1 and absf(Building.num(m.S.building, m.S.building["rooms"][1]["height"]) - 3.2) < 1e-6, "4 'make the second floor taller': ONE undo step, floor 2 is 3.2 m of wall: %s" % m.ui_status.text)
	# refusals
	n0 = m.undo.size()
	var rec0 := rec(m.S.building)
	await click_ctl(edit)
	await key(KEY_A, 0, true)
	await type_text("hosue 8 x 6")
	await key(KEY_ENTER)
	await idle(3)
	var did: Button = bld.words.did_btn
	ok(did != null and did.text == "Did you mean: house?" and rec(m.S.building) == rec0 and m.undo.size() == n0 and String(m.ui_status.text).contains("Did you mean: house?"),
		"4 a typo is refused plainly with a button: \"%s\"; nothing changed, no undo step" % m.ui_status.text)
	await click_ctl(did)
	await idle(3)
	ok(edit.text == "house 8 x 6" and String(bld.words.res.get("kind", "")) == "plan" and rec(m.S.building) == rec0, "4 the button fixes the word (\"%s\") and shows the plan, still nothing built" % edit.text)
	await click_ctl(edit)
	await key(KEY_A, 0, true)
	await type_text("a purple house with a moat")
	var ignored_live: Array = bld.words.res.get("ignored", [])
	ok(String(bld.words.res.get("kind", "")) == "plan" and ignored_live == ["purple", "moat"] and bld.words.foot.text.contains("Not understood, left out: purple, moat."), "4 half-understood words are listed in the plan BEFORE building: %s" % bld.words.foot.text.replace("\n", " | "))
	print("BUILDWORDS %s: %d failed" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
