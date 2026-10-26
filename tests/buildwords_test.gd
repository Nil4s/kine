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
##   5 PIECES  (WORDS learns pieces, scripts/build/build_words_pieces.gd) 15 piece sentences -> the exact pieces and positions (0.5 m grid, inside the
##             room); a door's 0.9 m stays clear (a fence "along" a wall takes only the stretch the door leaves free); no two pieces overlap; a piece
##             with no room is LEFT OUT and said plainly (never half built, the house is still whole); 10 edit phrases on a house that stands (add, bare
##             "stairs in the corner", remove, turn, move, "remove all", "which one?"); "save it as Dojo" parses with its capitals; a typo of a piece word
##             gets "Did you mean"; the plan's piece cards carry editable chips
##   6 PIECES UI  real typing of the dojo sentence: its piece cards show BEFORE building (nothing built), the count chip typed and the place chip clicked
##             change the plan, Build it = ONE undo step, then typed edit phrases (add / remove / move / turn) = ONE undo step each, "save it as Dojo" writes
##             the file + picture under the TEST houses folder (user://buildwords_test_houses) and takes no undo step, a sentence that cannot fit is
##             built without the piece and says so
## Screenshot: C:/Temp/claude/wordspieces/dojo.png (the dojo built from words); C:/Temp/claude/build1e/words.png (matches build_words.png). Only user:// is written.
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/build1e"
const DIRT := "user://buildwords_test"
const MOCK := "a 2-floor house 8 x 6 m with a door and 4 windows"
const PSHOT := "C:/Temp/claude/wordspieces"
const DIRH := "user://buildwords_test_houses"
const DOJO := "a 10 x 8 dojo with a door, 4 pillars around the room, a platform in the middle and a bench by the wall"


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


## ---- 5 PIECES helpers
func built(s: String) -> Dictionary:
	return BuildWords.make_building_full(plan_of(s), "T")


## [[kind, x, z, yaw]] of the pieces on a record
func pcs(b: Dictionary) -> Array:
	return b.get("pieces", []).map(func(p): return [p["kind"], p["x"], p["z"], p["yaw"]])


func rect_hit(a: Rect2, c: Rect2) -> bool:
	return a.position.x < c.end.x - 1e-4 and a.end.x > c.position.x + 1e-4 and a.position.y < c.end.y - 1e-4 and a.end.y > c.position.y + 1e-4


## no piece stands in the 0.9 m in front of a door (measured from the door's own cut box, not from the placing code)
func doors_clear(b: Dictionary) -> bool:
	for o in b.get("openings", []):
		if String(o["kind"]) == "window":
			continue
		var r := Building.room_of(b, String(o["room"]))
		var bx := Building.opening_box(b, r, o)
		var zone := Rect2()
		match String(o["wall"]):
			"front":
				zone = Rect2(bx.position.x, bx.end.z, bx.size.x, 0.9)
			"back":
				zone = Rect2(bx.position.x, bx.position.z - 0.9, bx.size.x, 0.9)
			"left":
				zone = Rect2(bx.end.x, bx.position.z, 0.9, bx.size.z)
			_:
				zone = Rect2(bx.position.x - 0.9, bx.position.z, 0.9, bx.size.z)
		for p in b.get("pieces", []):
			if int(p.get("storey", 0)) == int(r.get("storey", 0)) and rect_hit(BuildPieces.footprint(b, p), zone):
				return false
	return true


func no_overlap(b: Dictionary) -> bool:
	var ps: Array = b.get("pieces", [])
	for i in ps.size():
		for j in range(i + 1, ps.size()):
			if int(ps[i]["storey"]) == int(ps[j]["storey"]) and rect_hit(BuildPieces.footprint(b, ps[i]), BuildPieces.footprint(b, ps[j])):
				return false
	return true


## every piece inside the interior of the first room of its floor, its middle on the 0.5 m grid
func inside_grid(b: Dictionary) -> bool:
	for p in b.get("pieces", []):
		var r: Dictionary = {}
		for rr in b["rooms"]:
			if int(rr.get("storey", 0)) == int(p["storey"]) and String(rr["id"]) != "garage":
				r = rr
				break
		var t := Building.num(b, r.get("thickness"), 0.2)
		var inner := Rect2(float(r["x"]) + t, float(r["z"]) + t, float(r["w"]) - 2.0 * t, float(r["d"]) - 2.0 * t)
		var fp := BuildPieces.footprint(b, p)
		if fp.position.x < inner.position.x - 1e-4 or fp.position.y < inner.position.y - 1e-4 or fp.end.x > inner.end.x + 1e-4 or fp.end.y > inner.end.y + 1e-4:
			return false
		if absf(fposmod(float(p["x"]), 0.5)) > 1e-6 and absf(fposmod(float(p["x"]), 0.5) - 0.5) > 1e-6:
			return false
		if absf(fposmod(float(p["z"]), 0.5)) > 1e-6 and absf(fposmod(float(p["z"]), 0.5) - 0.5) > 1e-6:
			return false
	return true


func piece_row(s: String, want: Array) -> void:
	var f := built(s)
	if f.is_empty() or f["b"].is_empty():
		ok(false, "5 \"%s\" is a plan" % s)
		return
	var b: Dictionary = f["b"]
	var good := JSON.stringify(pcs(b)) == JSON.stringify(want) and doors_clear(b) and no_overlap(b) and inside_grid(b)
	ok(good, "5 \"%s\" -> %s, doors clear, no overlap, inside, on the grid%s" % [s, JSON.stringify(want), "" if good else "   GOT " + JSON.stringify(pcs(b))])


## an edit phrase on a house: {"b" (after), "r" (the parse), "d" (the apply)}
func pedit(house: Dictionary, s: String) -> Dictionary:
	var r := BuildWords.parse(s, house)
	var after: Dictionary = house.duplicate(true)
	if not bool(r["ok"]) or r["kind"] != "edit":
		return {"b": after, "r": r, "d": {"ok": false, "error": "not an edit: " + String(r.get("error", ""))}}
	return {"b": after, "r": r, "d": BuildWords.apply_edit(after, r["edit"])}


func without_pieces(b: Dictionary) -> String:
	var f := Building.to_file(b)
	f.erase("pieces")
	return JSON.stringify(f)


func shot_to(dir: String, nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png("%s/%s.png" % [dir, nm])


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

	# ---- 5 PIECES (no window needed)
	piece_row("a 2-floor house 8 x 6 m with a door and stairs in the corner", [["stairs", 1.0, 3.5, 0.0]])
	piece_row("a 2-floor house 8 x 6 with a door and L stairs to the second floor", [["stairs_l", 2.0, 4.0, 0.0]])
	piece_row("an 8 x 6 house with a table and 2 benches in the middle", [["table", 4.0, 3.0, 0.0], ["bench", 4.0, 2.0, 0.0], ["bench", 4.0, 4.0, 0.0]])
	piece_row("an 8 x 6 house with a crate by the door", [["crate", 3.0, 0.5, 0.0]])
	piece_row("an 8 x 6 house with 4 pillars around the room", [["pillar", 0.5, 5.5, 0.0], ["pillar", 7.5, 5.5, 0.0], ["pillar", 0.5, 0.5, 0.0], ["pillar", 7.5, 0.5, 0.0]])
	piece_row("an 8 x 6 house with a fence along the back wall", [["fence", 4.0, 5.5, 0.0]])
	piece_row("an 8 x 6 house with a platform in the middle and a ramp to the platform", [["platform", 4.0, 3.0, 0.0], ["ramp", 2.0, 3.0, 90.0]])
	piece_row("an 8 x 6 house with a bench by the left wall", [["bench", 0.5, 3.0, 90.0]])
	piece_row("an 8 x 6 house with 2 crates in the corner", [["crate", 0.5, 5.5, 0.0], ["crate", 7.5, 5.5, 0.0]])
	piece_row(DOJO, [["pillar", 0.5, 7.5, 0.0], ["pillar", 9.5, 7.5, 0.0], ["pillar", 0.5, 0.5, 0.0], ["pillar", 9.5, 0.5, 0.0], ["platform", 5.0, 4.0, 0.0], ["bench", 5.0, 7.5, 0.0]])
	piece_row("an 8 x 6 house with a table in the middle and 2 crates by the door", [["table", 4.0, 3.0, 0.0], ["crate", 3.0, 0.5, 0.0], ["crate", 5.0, 0.5, 0.0]])
	piece_row("an 8 x 6 house with stairs on the right wall", [["stairs", 7.0, 3.0, 0.0]])
	piece_row("a 2 floor house 8 x 6 with a door and 3 benches along the back wall", [["bench", 1.5, 5.5, 0.0], ["bench", 4.0, 5.5, 0.0], ["bench", 6.5, 5.5, 0.0]])
	piece_row("an 8 x 6 house with a table and a bench in the back left corner", [["table", 1.0, 5.0, 0.0], ["bench", 2.0, 5.0, 90.0]])
	piece_row("an 8 x 6 house with 6 pillars around the room", [["pillar", 0.5, 5.5, 0.0], ["pillar", 7.5, 5.5, 0.0], ["pillar", 0.5, 0.5, 0.0], ["pillar", 7.5, 0.5, 0.0], ["pillar", 4.0, 5.5, 0.0], ["pillar", 0.5, 3.0, 0.0]])
	# the words alone: the plan has the pieces as editable specs, stairs raise a defaulted floor count and say so
	var ps_plan := BuildWords.parse("stairs in the corner", {})
	ok(bool(ps_plan["ok"]) and ps_plan["kind"] == "plan" and ps_plan["plan"]["floors"] == 2 and String(ps_plan["notes"][0]).contains("Stairs go up, so the house has 2 floors"), "5 'stairs in the corner' with nothing built is a plan (a default room, 2 floors for the stairs, said): %s" % [ps_plan["notes"]])
	var sp: Array = BuildWords.parse(DOJO, {})["plan"]["pieces"]
	ok(sp.size() == 3 and sp[0]["kind"] == "pillar" and sp[0]["n"] == 4 and sp[0]["at"] == "around" and sp[1]["kind"] == "platform" and sp[1]["at"] == "middle" and sp[2]["kind"] == "bench" and sp[2]["at"] == "wall", "5 the dojo sentence is three piece specs: 4 pillars around, a platform in the middle, a bench by the wall")
	var dcards := BuildWords.cards(BuildWords.parse(DOJO, {})["plan"], {})
	ok(dcards.size() == 8 and String(dcards[5]["title"]) == "Pillar" and dcards[5]["chips"][0]["key"] == "pc0_n" and dcards[5]["chips"][0]["text"] == "4" and dcards[5]["chips"][2]["text"] == "around the room" and dcards[7]["chips"][2]["text"] == "by the wall",
		"5 the plan shows a card per piece with editable chips (4 | pillars | around the room): %s" % [dcards.slice(5).map(func(c): return c["chips"].map(func(h): return h["text"]))])
	# doorway kept clear: a fence along the FRONT wall takes only the stretch the door leaves free; a crate, a bench and a table crowd the back door
	var fz: Dictionary = built("an 8 x 6 house with a fence along the front wall")["b"]
	var fw := float(fz["pieces"][0]["w"]) if not fz.get("pieces", []).is_empty() else 0.0
	ok(not fz.get("pieces", []).is_empty() and fw < 7.5 and fw >= 3.0 and doors_clear(fz) and inside_grid(fz), "5 a fence along the front wall (the door is there) is %.1f m, not the whole 7.6: the doorway is clear" % fw)
	var dz: Dictionary = built("an 8 x 6 house with a door on the back and a bench by the back wall and 2 crates by the door and a table by the door")["b"]
	ok(dz["pieces"].size() == 4 and doors_clear(dz) and no_overlap(dz) and inside_grid(dz), "5 a bench, 2 crates and a table crowded round the back door: %d stand, the 0.9 m in front of the door is empty, no overlap" % dz["pieces"].size())
	var cr := built("an 8 x 6 house with 12 crates in the corner")
	ok(doors_clear(cr["b"]) and no_overlap(cr["b"]) and inside_grid(cr["b"]) and cr["b"]["pieces"].size() >= 4, "5 12 crates in the corner: %d stand, never through the door's space, never overlapping" % cr["b"]["pieces"].size())
	# can't fit: said plainly, left out, the house is whole
	var nf := built("a 4 x 3 house with stairs in the corner")
	ok(nf["b"].get("pieces", []).is_empty() and String(nf["res"][0]["why"]).begins_with("Can't fit the stairs") and String(nf["res"][0]["why"]).contains("1 x 4.2 m") and closed(nf["b"]) and Building.storey_count(nf["b"]) == 2,
		"5 stairs in a 4 x 3 house: left out, said plainly (\"%s\"), the house is still whole" % nf["res"][0]["why"])
	var nfc := BuildWords.cards(plan_of("a 4 x 3 house with stairs in the corner"), {})
	ok(String(nfc[nfc.size() - 1]["tail"]).contains("Can't fit") and String(nfc[nfc.size() - 1]["tail"]).ends_with("Left out."), "5 and its plan card says it BEFORE building: \"%s\"" % nfc[nfc.size() - 1]["tail"])
	var nr := built("an 8 x 6 house with a ramp to the platform")
	ok(nr["b"].get("pieces", []).is_empty() and String(nr["res"][0]["why"]).contains("no platform"), "5 a ramp with no platform to go to: left out, said (\"%s\")" % nr["res"][0]["why"])
	var ns: Dictionary = built("an 8 x 6 house with 12 stairs in the corner")
	ok(ns["b"].get("pieces", []).size() >= 1 and ns["b"].get("pieces", []).size() < 12 and String(ns["res"][0]["why"]).begins_with("Can't fit") and doors_clear(ns["b"]) and no_overlap(ns["b"]) and inside_grid(ns["b"]),
		"5 12 stairs: %d stand whole, the rest are left out and said, no overlap, inside" % ns["b"].get("pieces", []).size())
	# edits on a house that stands
	var H := BuildWords.make_building(plan_of("a 2-floor house 8 x 6 with a door and 4 windows"), "H")
	var e1 := pedit(H, "add 4 pillars around the room")
	ok(bool(e1["d"]["ok"]) and e1["b"]["pieces"].size() == 4 and without_pieces(e1["b"]) == without_pieces(H) and String(e1["d"]["say"]).begins_with("Added 4 pillars"), "5 edit \"add 4 pillars around the room\": 4 pillars, the rest of the record equal: %s" % e1["d"].get("say", e1["d"].get("error", "")))
	var e2 := pedit(H, "stairs in the corner")
	ok(String(e2["r"]["kind"]) == "edit" and bool(e2["d"]["ok"]) and JSON.stringify(pcs(e2["b"])) == JSON.stringify([["stairs", 1.0, 3.5, 0.0]]) and without_pieces(e2["b"]) == without_pieces(H),
		"5 edit (no verb) \"stairs in the corner\" on a house that stands ADDS the stairs, it does not rebuild: %s" % [pcs(e2["b"])])
	var HT := BuildWords.make_building(plan_of("an 8 x 6 house with a door"), "HT")
	var e3 := pedit(HT, "put a table in the middle and a crate by the door")
	var H3: Dictionary = e3["b"]
	ok(bool(e3["d"]["ok"]) and JSON.stringify(pcs(H3)) == JSON.stringify([["table", 4.0, 3.0, 0.0], ["crate", 3.0, 0.5, 0.0]]), "5 edit \"put a table in the middle and a crate by the door\": %s" % [pcs(H3)])
	var e4 := pedit(H3, "turn the table")
	ok(bool(e4["d"]["ok"]) and e4["b"]["pieces"][0]["yaw"] == 90.0 and e4["b"]["pieces"][1] == H3["pieces"][1] and without_pieces(e4["b"]) == without_pieces(H3), "5 edit \"turn the table\": yaw 0 -> 90, the crate and the house untouched: %s" % e4["d"].get("say", e4["d"].get("error", "")))
	var e5 := pedit(H3, "remove the crate")
	ok(bool(e5["d"]["ok"]) and JSON.stringify(pcs(e5["b"])) == JSON.stringify([["table", 4.0, 3.0, 0.0]]) and String(e5["d"]["say"]).begins_with("Removed 1 crate"), "5 edit \"remove the crate\": only the crate goes: %s" % e5["d"].get("say", e5["d"].get("error", "")))
	var HS: Dictionary = pedit(H, "stairs in the corner")["b"]
	var e6 := pedit(HS, "move the stairs to the left wall")
	ok(bool(e6["d"]["ok"]) and JSON.stringify(pcs(e6["b"])) == JSON.stringify([["stairs", 1.0, 3.0, 0.0]]) and without_pieces(e6["b"]) == without_pieces(HS) and doors_clear(e6["b"]), "5 edit \"move the stairs to the left wall\": %s" % [pcs(e6["b"])])
	var H2c: Dictionary = pedit(H3, "add 2 crates by the door")["b"]
	var e7 := pedit(H2c, "remove the crate")
	ok(not bool(e7["d"]["ok"]) and String(e7["d"]["error"]).begins_with("Which crate? There are 3"), "5 edit \"remove the crate\" with 3 crates asks which, changes nothing: %s" % e7["d"].get("error", ""))
	var e8 := pedit(H2c, "remove all the crates")
	ok(bool(e8["d"]["ok"]) and JSON.stringify(pcs(e8["b"])) == JSON.stringify([["table", 4.0, 3.0, 0.0]]), "5 edit \"remove all the crates\": %s" % e8["d"].get("say", e8["d"].get("error", "")))
	var e9 := pedit(HS, "turn the stairs")
	ok(not bool(e9["d"]["ok"]) and String(e9["d"]["error"]).contains("cannot turn here") and pcs(e9["b"]) == pcs(HS), "5 edit \"turn the stairs\" where they would not fit: refused plainly, unchanged: %s" % e9["d"].get("error", ""))
	var e10 := pedit(H, "remove the table")
	ok(not bool(e10["d"]["ok"]) and String(e10["d"]["error"]).contains("There is no table"), "5 edit \"remove the table\" with none: %s" % e10["d"].get("error", ""))
	# save as + typos
	var sv := BuildWords.parse("save it as Dojo", H)
	ok(bool(sv["ok"]) and sv["kind"] == "edit" and sv["edit"]["op"] == "save" and sv["edit"]["name"] == "Dojo" and BuildWords.describe_edit(sv["edit"]) == "Save this house as \"Dojo\"", "5 \"save it as Dojo\" is an edit that keeps the capital: %s" % [sv["edit"]])
	ok(BuildWords.parse("Save as 'My Dojo 2'", H)["edit"]["name"] == "My Dojo 2", "5 \"Save as 'My Dojo 2'\" -> name My Dojo 2")
	refuse_row("save it as Dojo", {})
	refuse_row("save it as", H)
	refuse_row("an 8 x 6 house with a bnech by the wall", {}, "bench")
	refuse_row("stiars in the corner", H, "stairs")
	refuse_row("an 8 x 6 house with 13 crates", {})
	var pdel := BuildWords.parse("a house with a purple door and a table", {})
	ok(bool(pdel["ok"]) and (pdel["ignored"] as Array) == ["purple"], "5 unknown words next to pieces are still LISTED, not guessed: %s" % [pdel["ignored"]])

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
	if m.ui_save_ask != null and m.ui_save_ask.visible: m._save_ask_choose("discard")   # unsaved work above: a new project asks first (startscreen bar 13)
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
	# ---- 6 PIECES UI: real typing + clicks
	var houses_dir0 := Houses.dir
	Houses.dir = DIRH
	for ext in ["json", "png"]:
		var old := ProjectSettings.globalize_path("%s/Dojo.%s" % [DIRH, ext])
		if FileAccess.file_exists(old):
			DirAccess.remove_absolute(old)
	await click_ctl(edit)
	await key(KEY_A, 0, true)
	await type_text(DOJO)
	ok(edit.text == DOJO, "6 the dojo sentence typed with real keys")
	var rec_before := rec(m.S.building)
	n0 = m.undo.size()
	var cu: VBoxContainer = bld.words.cards_box
	var scr: ScrollContainer = bld.words.cards_scroll
	var c6 := cu.find_child("build_words_card_7", true, false)
	ok(cu.get_child_count() == 8 and c6 != null and c6.find_children("*", "Label", true, false).any(func(l): return (l as Label).text == "Platform"), "6 BEFORE building the plan has 8 cards: the house's five and a card per piece (pillars, platform, bench)")
	ok(rec(m.S.building) == rec_before and m.undo.size() == n0, "6 nothing built yet, no undo step")
	var cn: LineEdit = cu.find_child("build_words_chip_pc0_n", true, false)
	ok(cn != null and cn.text == "4", "6 the pillars card has a count chip: 4")
	await idle(6)
	scr.ensure_control_visible(cu.find_child("build_words_chip_pc0_n", true, false))
	await idle(3)
	await click_ctl(cu.find_child("build_words_chip_pc0_n", true, false))
	ok(root.gui_get_focus_owner() is LineEdit and root.gui_get_focus_owner() != edit, "6 a click on the count chip gives the chip the keyboard")
	await key(KEY_A, 0, true)
	await type_text("2")
	await key(KEY_ENTER)
	await idle(4)
	ok(int(bld.words.plan["pieces"][0]["n"]) == 2 and (cu.find_child("build_words_chip_pc0_n", true, false) as LineEdit).text == "2" and rec(m.S.building) == rec_before, "6 the count typed (2) changes the plan only: 2 pillars, still nothing built")
	scr.ensure_control_visible(cu.find_child("build_words_chip_pc0_n", true, false))
	await idle(3)
	await click_ctl(cu.find_child("build_words_chip_pc0_n", true, false))
	await key(KEY_A, 0, true)
	await type_text("4")
	await key(KEY_ENTER)
	await idle(4)
	ok(scr.size.y < cu.get_combined_minimum_size().y and bld.words.plan_panel.get_global_rect().end.y <= root.get_visible_rect().size.y + 1.0 and bld.words.foot.get_global_rect().end.y <= root.get_visible_rect().size.y + 1.0,
		"6 the 8 cards are taller than the page, so they scroll: the panel (%.0f) and its footer stay inside the window (%d)" % [bld.words.plan_panel.get_global_rect().end.y, root.get_visible_rect().size.y])
	scr.ensure_control_visible(cu.find_child("build_words_cycle_pc2_at", true, false))
	await idle(3)
	await click_ctl(cu.find_child("build_words_cycle_pc2_at", true, false))
	ok(String(bld.words.plan["pieces"][2]["at"]) == "around" and (cu.find_child("build_words_cycle_pc2_at", true, false) as Button).text == "around the room", "6 a click on the bench's place chip cycles 'by the wall' -> 'around the room'")
	for i in 8:
		scr.ensure_control_visible(cu.find_child("build_words_cycle_pc2_at", true, false))
		await idle(2)
		await click_ctl(cu.find_child("build_words_cycle_pc2_at", true, false))
	ok(String(bld.words.plan["pieces"][2]["at"]) == "wall" and (cu.find_child("build_words_cycle_pc2_at", true, false) as Button).text == "by the wall" and int(bld.words.plan["pieces"][0]["n"]) == 4, "6 and round again to 'by the wall' (the pillars still 4)")
	n0 = m.undo.size()
	await click_ctl(bld.words.go)
	await idle(5)
	var dj: Dictionary = m.S.building
	ok(not dj.is_empty() and float(dj["rooms"][0]["w"]) == 10.0 and float(dj["rooms"][0]["d"]) == 8.0 and JSON.stringify(pcs(dj)) == JSON.stringify([["pillar", 0.5, 7.5, 0.0], ["pillar", 9.5, 7.5, 0.0], ["pillar", 0.5, 0.5, 0.0], ["pillar", 9.5, 0.5, 0.0], ["platform", 5.0, 4.0, 0.0], ["bench", 5.0, 7.5, 0.0]]) and doors_clear(dj) and no_overlap(dj),
		"6 Build it: the dojo 10 x 8 with 4 pillars, the platform in the middle, the bench: %s" % [pcs(dj)])
	ok(m.undo.size() == n0 + 1 and String(m.ui_status.text).begins_with("Built: 10 x 8 m, 1 floor, 1 door, 0 windows") and String(m.ui_status.text).contains("4 pillars, a platform, a bench"), "6 Build it with pieces is ONE undo step (%d -> %d): %s" % [n0, m.undo.size(), m.ui_status.text])
	await shot_to(PSHOT, "dojo")
	m._undo()
	await idle(3)
	ok(rec(m.S.building) == rec_before, "6 Undo takes the whole dojo back in one step (the house before returns exactly)")
	m._redo()
	await idle(3)
	ok(JSON.stringify(pcs(m.S.building)) == JSON.stringify(pcs(dj)), "6 Redo brings the dojo and its pieces back")
	# the same dojo with the roof off, to SEE the pieces (a typed edit phrase, one undo step, undone again)
	n0 = m.undo.size()
	await click_ctl(edit)
	await key(KEY_A, 0, true)
	await type_text("remove the roof")
	await key(KEY_ENTER)
	await idle(4)
	ok(m.S.building.get("roof", {}).is_empty() and m.undo.size() == n0 + 1, "6 'remove the roof' on the dojo: ONE undo step")
	m._turn_to(30.0, -50.0, 24.0, Vector3(5.0, 0.5, 4.0), false)
	await idle(6)
	await shot_to(PSHOT, "dojo_open")
	m._undo()
	await idle(3)
	ok(not m.S.building.get("roof", {}).is_empty() and JSON.stringify(pcs(m.S.building)) == JSON.stringify(pcs(dj)), "6 Undo puts the roof back; the pieces are as built")
	# typed edit phrases: ONE undo step each
	var np0: int = m.S.building["pieces"].size()
	n0 = m.undo.size()
	await click_ctl(edit)
	await key(KEY_A, 0, true)
	await type_text("a crate by the door")
	ok(String(bld.words.res.get("kind", "")) == "edit" and cu.find_child("build_words_chip_pc0_n", true, false) != null and m.S.building["pieces"].size() == np0, "6 'a crate by the door' on the dojo is a change with its own piece card (a count chip), nothing yet")
	await key(KEY_ENTER)
	await idle(3)
	ok(m.S.building["pieces"].size() == np0 + 1 and m.undo.size() == n0 + 1 and doors_clear(m.S.building) and no_overlap(m.S.building), "6 Enter: the crate is added, ONE undo step (%d -> %d), the door still clear: %s" % [n0, m.undo.size(), m.ui_status.text])
	n0 = m.undo.size()
	await click_ctl(edit)
	await type_text("remove the bench")
	await key(KEY_ENTER)
	await idle(3)
	ok(m.S.building["pieces"].filter(func(p): return p["kind"] == "bench").is_empty() and m.undo.size() == n0 + 1, "6 'remove the bench': gone, ONE undo step: %s" % m.ui_status.text)
	n0 = m.undo.size()
	await click_ctl(edit)
	await type_text("move the platform to the left wall")
	await key(KEY_ENTER)
	await idle(3)
	var plat: Dictionary = m.S.building["pieces"].filter(func(p): return p["kind"] == "platform")[0]
	ok(float(plat["x"]) == 1.5 and float(plat["z"]) == 4.0 and m.undo.size() == n0 + 1 and no_overlap(m.S.building), "6 'move the platform to the left wall': it stands against the left wall (%.1f, %.1f), ONE undo step" % [plat["x"], plat["z"]])
	n0 = m.undo.size()
	await click_ctl(edit)
	await type_text("turn the crate")
	await key(KEY_ENTER)
	await idle(3)
	var crt: Dictionary = m.S.building["pieces"].filter(func(p): return p["kind"] == "crate")[0]
	ok(float(crt["yaw"]) == 90.0 and m.undo.size() == n0 + 1, "6 'turn the crate': yaw 90, ONE undo step: %s" % m.ui_status.text)
	m._undo()
	await idle(2)
	crt = m.S.building["pieces"].filter(func(p): return p["kind"] == "crate")[0]
	ok(float(crt["yaw"]) == 0.0, "6 Undo turns it back")
	# save as
	n0 = m.undo.size()
	var rec_s2: Dictionary = Building.to_file(m.S.building).duplicate(true)
	await click_ctl(edit)
	await type_text("save it as Dojo")
	ok(String(bld.words.res.get("kind", "")) == "edit" and String(bld.words.res["edit"]["op"]) == "save" and String((bld.words.cards_box.find_child("build_words_card_body", true, false) as Label).text) == "Save this house as \"Dojo\"", "6 'save it as Dojo' shows its card before it is done")
	ok(not Houses.exists("Dojo"), "6 nothing is saved until Enter")
	await key(KEY_ENTER)
	await idle(8)
	var saved := Houses.read(Houses.path_of("Dojo"))
	ok(Houses.exists("Dojo") and Houses.path_of("Dojo").begins_with(DIRH) and not saved.is_empty() and JSON.stringify(pcs(saved)) == JSON.stringify(pcs(m.S.building)) and FileAccess.file_exists(ProjectSettings.globalize_path(Houses.thumb_of("Dojo"))),
		"6 Enter: the house is saved as Dojo under the TEST folder (%s), its pieces in the file, its picture beside it" % Houses.path_of("Dojo"))
	var rec_n: Dictionary = Building.to_file(m.S.building)
	rec_n.erase("name")
	rec_s2.erase("name")
	ok(m.undo.size() == n0 and JSON.stringify(rec_n) == JSON.stringify(rec_s2), "6 saving takes no undo step and changes nothing in the record (but its name: the house is called Dojo now)")
	await click_ctl(edit)
	await type_text("save it as Dojo")
	await key(KEY_ENTER)
	await idle(3)
	ok(Houses.list().size() == 1 and m.undo.size() == n0, "6 saving again under the same name (the house just saved): still one file on the test folder, no undo step: %s" % m.ui_status.text)
	# a sentence that cannot fit is built without the piece
	n0 = m.undo.size()
	await click_ctl(edit)
	await key(KEY_A, 0, true)
	await type_text("a 4 x 3 house with stairs in the corner")
	var tailtxt := ""
	for lb in bld.words.cards_box.find_children("*", "Label", true, false):
		if (lb as Label).text.contains("Left out."):
			tailtxt = (lb as Label).text
	ok(tailtxt.begins_with("Can't fit the stairs") and m.undo.size() == n0, "6 the plan card says it before building: \"%s\"" % tailtxt)
	await click_ctl(bld.words.go)
	await idle(4)
	ok(m.S.building.get("pieces", []).is_empty() and m.undo.size() == n0 + 1 and Building.storey_count(m.S.building) == 2 and String(m.ui_status.text).contains("Left out, no room: 1 stairs (Can't fit the stairs"),
		"6 Build it builds the house WITHOUT the stairs (never half-built), ONE undo step, and says: %s" % m.ui_status.text)
	Houses.dir = houses_dir0
	print("BUILDWORDS %s: %d failed" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
