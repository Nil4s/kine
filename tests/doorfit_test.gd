extends SceneTree
## godot --path . --position 4000,4000 -s tests/doorfit_test.gd     (BUILD B2: doorway and body clearance on STAGE; needs a window for the UI bars)
## Bars, written before measuring. Logic bars (BuildStage.clearance / walk_scene / Building.anchors): the doorway's height is the
## opening's clear height above the floor (sill + height); the fighter fits when the doorway stands CLEAR_MARGIN (5 cm) over the
## fighter's stature (the body's own stature, or the default body's when it has none).
##   1 a 1.95 m door, a 1.80 m body: fits, gap 15.0 cm
##   2 a 1.70 m door, a 1.80 m body: flagged, gap -10.0 cm, the words say "10 cm shorter" and "1.70 m"
##   3 a 2.00 m door, a 1.95 m body: fits with exactly 5.0 cm (the margin passes)
##   4 a 1.99 m door, a 1.95 m body: flagged, gap 4.0 cm, "only 4 cm over the fighter's head, 5 cm is needed"
##   5 the default body (no stature in the scene) at the default 2.10 m door: fits, gap 27.1 cm
##   6 two doors (front 2.10, back 1.70), a 1.80 m body: "front door" fits, "back door" is flagged; the anchors' clear heights are 2.10 and 1.70
##   7 a window is not a doorway: a house with only a window (1.20 m high, sill 0.90 m) has no anchor, so nothing is flagged
##   8 the door height's minimum (1.00 m) is flagged for a 1.80 m body with gap -80.0 cm
##   9 a body made by BodyFromNumbers at 195 cm (scene body dict): a 2.00 m door fits with 5.0 cm, a 1.95 m door is flagged with gap 0.0 cm
##  10 walk_scene refuses a walk under a flagged door: {ok false}, the same words as clearance, and no cards are made
##  11 walk_scene on a door that fits makes cards (ok true, more than 6 cards)
## UI bars (real house, real clicks, main.tscn at 1280 x 720; the default body 1.83 m):
##  12 STAGE: the front door (1.70 m) button reads "(too low)", its tooltip gives the words; a click does not replace the open scene
##  13 the same house with the door at 2.10 m: the button reads plain "Walk through the front door"; a click walks (a new scene, cards > 6)
## Screenshots: C:/Temp/claude/doorfit/{stage_low,stage_fit}.png. Only user:// is written (nothing).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/doorfit"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## a house: one 4 x 3 room, a front door of the given height (m), and an optional back door of its own height
func house(front_h: float, back_h := -1.0) -> Dictionary:
	var b := Building.make("Doorfit")
	var r := Building.add_room(b, 0.0, 0.0, 4.0, 3.0)
	Building.add_opening(b, r, "front", "door", 1.0)
	b["params"]["door_height"] = front_h
	if back_h > 0.0:
		Building.add_opening(b, r, "back", "door", 1.0)
		b["openings"][-1]["h"] = back_h   # a door of its own height (a number, not the named door_height)
	return b


func stature(v: float) -> Body:
	var B := Body.new()
	B.body = {"stature": v}
	return B


func _init() -> void:
	# ---- logic bars (no scene touched)
	var st180 := 1.80
	var b195 := house(1.95)
	var c1 := BuildStage.clearance(b195, "front door", st180)
	ok(bool(c1["ok"]) and absf(float(c1["gap_cm"]) - 15.0) < 0.01 and String(c1["why"]) == "", "1 a 1.95 m door, a 1.80 m body: fits, gap %.2f cm" % float(c1["gap_cm"]))

	var b170 := house(1.70)
	var c2 := BuildStage.clearance(b170, "front door", st180)
	var w2 := String(c2["why"])
	ok(not bool(c2["ok"]) and absf(float(c2["gap_cm"]) + 10.0) < 0.01 and w2.contains("10 cm shorter") and w2.contains("1.70 m"),
		"2 a 1.70 m door, a 1.80 m body: flagged, gap %.2f cm; \"%s\"" % [float(c2["gap_cm"]), w2])

	var b200 := house(2.00)
	var c3 := BuildStage.clearance(b200, "front door", 1.95)
	ok(bool(c3["ok"]) and absf(float(c3["gap_cm"]) - 5.0) < 0.01, "3 a 2.00 m door, a 1.95 m body: fits, gap %.4f cm (margin 5 cm)" % float(c3["gap_cm"]))

	var b199 := house(1.99)
	var c4 := BuildStage.clearance(b199, "front door", 1.95)
	ok(not bool(c4["ok"]) and absf(float(c4["gap_cm"]) - 4.0) < 0.01 and String(c4["why"]).contains("only 4 cm over the fighter's head, 5 cm is needed"),
		"4 a 1.99 m door, a 1.95 m body: flagged, gap %.2f cm; \"%s\"" % [float(c4["gap_cm"]), String(c4["why"])])

	var b210 := house(2.10)
	var stock := BuildStage.stature_of(Body.new())
	var c5 := BuildStage.clearance(b210, "front door", stock)
	ok(bool(c5["ok"]) and absf(float(c5["gap_cm"]) - (210.0 - stock * 100.0)) < 0.01 and absf(stock - 1.82872) < 1e-4,
		"5 the default body (%.4f m) at the 2.10 m door: fits, gap %.2f cm" % [stock, float(c5["gap_cm"])])

	var b2d := house(2.10, 1.70)
	var a2d := Building.anchors(b2d)
	var cf := BuildStage.clearance(b2d, "front door", st180)
	var cb := BuildStage.clearance(b2d, "back door", st180)
	ok(a2d.size() == 2 and absf(float(a2d[0]["clear"]) - 2.10) < 1e-4 and absf(float(a2d[1]["clear"]) - 1.70) < 1e-4
		and bool(cf["ok"]) and not bool(cb["ok"]) and absf(float(cb["gap_cm"]) + 10.0) < 0.01,
		"6 two doors: clear %.2f and %.2f m; front fits %s, back flagged %s (gap %.2f cm)" % [float(a2d[0]["clear"]), float(a2d[1]["clear"]), bool(cf["ok"]), not bool(cb["ok"]), float(cb["gap_cm"])])

	var bw := Building.make("Window only")
	var rw := Building.add_room(bw, 0.0, 0.0, 4.0, 3.0)
	Building.add_opening(bw, rw, "front", "window", 1.0)
	var cw := BuildStage.clearance(bw, "front door", st180)
	ok(Building.anchors(bw).is_empty() and bool(cw["ok"]), "7 a window is not a doorway: %d anchors, nothing flagged" % Building.anchors(bw).size())

	var b100 := house(1.00)
	var c8 := BuildStage.clearance(b100, "front door", st180)
	ok(not bool(c8["ok"]) and absf(float(c8["gap_cm"]) + 80.0) < 0.01, "8 the 1.00 m minimum door, a 1.80 m body: gap %.2f cm" % float(c8["gap_cm"]))

	var fromnum := Body.new()
	fromnum.body = BodyFromNumbers.body_for(195.0, 95.0, "male", 30.0, "average")
	var st195 := BuildStage.stature_of(fromnum)
	var c9a := BuildStage.clearance(b200, "front door", st195)
	var c9b := BuildStage.clearance(b195, "front door", st195)
	ok(absf(st195 - 1.95) < 0.001 and bool(c9a["ok"]) and absf(float(c9a["gap_cm"]) - 5.0) < 0.1 and not bool(c9b["ok"]) and absf(float(c9b["gap_cm"])) < 0.1,
		"9 BodyFromNumbers 195 cm (stature %.4f m): 2.00 m door fits with %.2f cm; 1.95 m door flagged, gap %.2f cm" % [st195, float(c9a["gap_cm"]), float(c9b["gap_cm"])])

	var S := Scene.new()
	S.building = b170
	var rf := BuildStage.walk_scene(S, stature(1.80), "front door")
	ok(not bool(rf["ok"]) and String(rf["why"]) == w2 and not rf.has("scene"), "10 walk_scene under the 1.70 m door: refused with the same words (ok %s)" % bool(rf["ok"]))

	S.building = b195
	var rp := BuildStage.walk_scene(S, stature(1.80), "front door")
	var cards: int = (rp["scene"] as Dictionary)["cards"].size() if bool(rp["ok"]) else 0
	ok(bool(rp["ok"]) and cards > 6, "11 walk_scene under the 1.95 m door: ok, %d cards" % cards)

	# ---- UI bars (a real house on STAGE)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	m._new_scene()
	m.S.kind = "building"
	m._page_set("BUILD")
	m.bld.reset_view()
	m._refresh()
	await idle(3)

	m.S.building = house(1.70)
	m.bld.use_in_scene()
	await idle(6)
	var btn: Button = m.bld.walk_btns.get("front door")
	ok(m.cur_page == "STAGE" and btn != null and btn.text.contains("(too low)") and not btn.tooltip_text.is_empty(),
		"12 STAGE: the front door button reads \"%s\"; tooltip \"%s\"" % [btn.text if btn != null else "none", btn.tooltip_text if btn != null else ""])
	await _shot("stage_low")
	var scene_before: Scene = m.S
	var cards_before: int = m.S.cards.size()
	var undo_before: int = m.undo.size()
	if btn != null:
		btn.pressed.emit()
	await idle(4)
	ok(m.S == scene_before and m.S.cards.size() == cards_before and m.undo.size() == undo_before, "12 a click on the flagged button keeps the open scene (no new scene, no undo step)")

	m.S.building["params"]["door_height"] = 2.10
	m.bld._stage_sync()
	await idle(4)
	btn = m.bld.walk_btns.get("front door")
	ok(btn != null and btn.text == "Walk through the front door" and btn.tooltip_text != "", "13 door at 2.10 m: the button reads \"%s\"" % (btn.text if btn != null else "none"))
	await _shot("stage_fit")
	if btn != null:
		btn.pressed.emit()
	await idle(6)
	ok(m.S != scene_before and m.S.cards.size() > 6, "13 a click walks: a new scene with %d cards" % m.S.cards.size())

	print("DOORFIT: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)


func _shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])
