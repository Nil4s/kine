## godot --path . -s tests/physlane_test.gd   (window)  A1 "Make it physical" lane: priority cards ("Keep this pose"), blue = edited since
## the judge read the clip, gray = not processed yet, the red span count after one Accept span. Seeded clip: a body lifted 0.4 m for 1 s
## (a hover; the test's tweak lifts the sampled clip, the same as i1_test). Three real judge runs.
## Bars (written before measuring):
##  1 the picked card, kept with its own ribbon button, is a priority card; Make it physical leaves EVERY card byte-identical (0 changed)
##  2 Accept span over the red airborne span: the kept card inside it is byte-identical after (var_to_str), and cards were replaced (>= 2)
##  3 the red span count drops by at least 1 after that one fix (the judge re-run on the fixed clip, no lift): before N, after M, M <= N - 1
##  4 after one card edit the lane shows a blue block covering that card's frames; after the next run lands there is no blue block
##  5 while the next run judges, a gray block covers the part not judged yet (up to the clip's end); after it lands, no gray block
##  6 the priority flag survives a save and a load (Scene.to_dict / from_dict)
## Shots: C:/Temp/claude/physlane/
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the judge runs in a child process; the window keeps drawing (tick polls it). Waits until the result has landed
func wait_judge(ui: MakePhysicalUI) -> void:
	await idle(2)
	var t0 := Time.get_ticks_msec()
	while ui.mp.running() and Time.get_ticks_msec() - t0 < 300000:
		await process_frame
	await idle(3)


func btn(label: String) -> Button:
	for c in m.ui_ribbon["CHECK"].get_children():
		if c is Button and m.label_of(c) == label:
			return c
	return null


func blocks(tone: String) -> Array:
	return m.ui_timeline.ph.filter(func(b): return String(b.get("tone", "")) == tone)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/physlane")
	var B: Body = m.B
	var rest := B.to_dict()
	B.offset = Vector3(0, 0.4, 0)
	B.fk()
	var up := B.to_dict()
	B.offset = Vector3.ZERO
	B.fk()
	# the seeded clip: stand, three lifted cards (the middle one is the priority card), a landing. The lift 0.5 .. 1.7 s is the hover
	m.S.from_dict({"scene": "zz_physlane", "fps": 30, "cards": [
		{"name": "stand", "pose": rest, "move": -1.0, "hold": 0.5},
		{"name": "lift a", "pose": up, "move": 0.1, "hold": 0.4},
		{"name": "kept", "pose": up, "move": 0.1, "hold": 0.4},
		{"name": "lift b", "pose": up, "move": 0.1, "hold": 0.4},
		{"name": "down", "pose": rest, "move": 0.1, "hold": 0.1}]})
	m._rebuild_cards()
	m._refresh()
	await idle(3)
	var ui: MakePhysicalUI = m.mp_ui
	var tl: Timeline = m.ui_timeline
	var lift := func(frames: Array, offs: Array) -> void:
		for i in frames.size():
			var t: float = frames[i]["t"]
			var h := 0.4 * clampf(minf((t - 0.5) / 0.1, (1.7 - t) / 0.1), 0.0, 1.0)
			frames[i]["pelvis"][1] += h
			offs[i][0].y += h
			offs[i][1].y += h
	# 1. the priority flag, pressed on its own ribbon button, then Make it physical
	m.sel_card = 2
	var kb := btn("Keep this pose")
	ok(kb != null, "1a the CHECK ribbon has a Keep this pose button")
	if kb != null:
		kb.pressed.emit()
	await idle(2)
	ok(m.S.cards[2].get("keep", false) == true, "1b the picked card is kept (flag: %s)" % str(m.S.cards[2].get("keep", false)))
	var cards0: Array = m.S.cards.duplicate(true)
	ui.mp.tweak = lift
	ui.run()
	await wait_judge(ui)
	ok(ui.mp.done and ui.mp.failed == "", "1c the judge finished (%s)" % ui.mp.failed)
	var changed := 0
	for i in cards0.size():
		if var_to_str(m.S.cards[i]) != var_to_str(cards0[i]):
			changed += 1
	ok(m.S.cards.size() == cards0.size() and changed == 0, "1d Make it physical changed %d of %d cards (bar: 0)" % [changed, cards0.size()])
	var spans_a := ui.mp.spans.size()
	var air := ui.mp.spans.filter(func(s): return s["kind"] == "airborne")
	ok(air.size() >= 1, "1e the red airborne span is there (%d red span(s) before the fix)" % spans_a)
	if air.is_empty():
		print("FAILS %d" % fails)
		quit(1)
		return
	# 2. Accept span over the airborne span: the kept card inside it stays as it was
	var kept_before := var_to_str(m.S.cards[2])
	var inside := MakePhysical.cards_in(m.S, air[0])
	ui.pick(ui.mp.spans.find(air[0]))
	ui.accept()
	await idle(3)
	var ki := -1
	var replaced := 0
	for i in m.S.cards.size():
		if String(m.S.cards[i]["name"]) == "kept":
			ki = i
		if String(m.S.cards[i]["name"]).begins_with("physical"):
			replaced += 1
	ok(ki >= 0 and var_to_str(m.S.cards[ki]) == kept_before, "2a the kept card inside the span is byte-identical (%d card(s) lay in the span)" % inside.size())
	ok(replaced >= 2, "2b the span's other cards were replaced: %d physical cards" % replaced)
	# 3. the fixed clip, judged again without the lift (the lift was the fault the cards had; the physical cards do not carry it)
	ui.mp.tweak = Callable()
	ui.run()
	await wait_judge(ui)
	var spans_b := ui.mp.spans.size()
	ok(ui.mp.done and ui.mp.failed == "", "3a the judge finished on the fixed clip (%s)" % ui.mp.failed)
	ok(spans_b <= spans_a - 1, "3b red spans %d -> %d after one Accept span (bar: drop by >= 1)" % [spans_a, spans_b])
	# 4 + 5. one edit: blue over the edited card; the next run: gray while it judges, and nothing blue or gray after it lands
	var ei := 2
	var ts: Array = m.S.times()
	var arr := float(ts[ei][1])
	var len_before: float = m.S.length()
	m.S.cards[ei]["hold"] = float(m.S.cards[ei]["hold"]) + 0.3
	m._refresh()
	await idle(3)
	ok(absf(m.S.length() - len_before - 0.3) < 0.01, "4d the +0.3 s hold lengthens the clip: %.2f -> %.2f s" % [len_before, m.S.length()])
	var bl := blocks("blue")
	var covers := bl.any(func(b): return float(b["t0"]) <= arr and arr <= float(b["t1"]))
	ok(bl.size() >= 1 and covers, "4a after one edit the lane has %d blue block(s), one covering card %d at %.2f s" % [bl.size(), ei + 1, arr])
	ok(tl.ph_px() > 0.0, "4b the lane is on the timeline")
	await idle(2)
	root.get_viewport().get_texture().get_image().save_png("C:/Temp/claude/physlane/blue_after_edit.png")
	ui.run()
	await idle(3)
	var gr := blocks("gray")
	var L: float = m.S.length()
	ok(gr.size() == 1 and absf(float(gr[0]["t1"]) - L) < 0.01, "5a while it judges: %d gray block(s) to the clip's end %.2f s" % [gr.size(), L])
	await wait_judge(ui)
	ok(blocks("blue").is_empty(), "4c the run cleared the blue: %d block(s) left (bar: 0)" % blocks("blue").size())
	ok(blocks("gray").is_empty(), "5b after the run: %d gray block(s) left (bar: 0)" % blocks("gray").size())
	# 6. the flag survives a save and a load
	var d: Dictionary = m.S.to_dict(m.B, false)
	var S2: Scene = Scene.new()
	S2.from_dict(JSON.parse_string(JSON.stringify(d)))
	var kept_back: Array = S2.cards.filter(func(c): return String(c["name"]) == "kept" and bool(c.get("keep", false)))
	ok(kept_back.size() == 1, "6 the priority flag survives save and load (%d kept card(s) back)" % kept_back.size())
	print("FAILS %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)

