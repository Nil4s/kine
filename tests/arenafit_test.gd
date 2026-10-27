## godot --path . -s tests/arenafit_test.gd     (ROADMAP I1: arena fit, scripts/arena_fit.gd + arena_fit_ui.gd; needs a window)
## The scene: as i18, the hero plays combo3's first two strikes; fighter 2 stands still (poses/stand.json) facing him along Z. The ring is
## centred between the two starting pelvises. Setup (not a bar): the spacing is bisected until the fight needs 3.40 m of ring side.
## Bars, written before measuring:
##  (1) the 3.0 m ring does NOT fit the fight, and the panel and the message say so
##  (2) the tightest fighter is pushed past a wall on the fight line (+Z or -Z), by 0.20 m +- 0.02 (3.40 m needed, 1.5 m half side)
##  (3) the 5.0 m ring fits, and the tightest fighter has 0.80 m +- 0.02 to the nearest wall = 1 whole step (0.7 m)
##  (4) the moment he is furthest toward that wall falls inside one of the hero's strike spans (+- 50 ms): the exchange that does it
##  (5) the ring side box in the panel is live: 3.0 -> 5.0 m flips the title from NOT fit to fits, with no re-open
##  (6) read only: the cards and both fighters' places are the same before and after the checks
##  (7) the CHECK ribbon's FIGHT group holds a "Fit the ring" tool (by its tooltip)
extends SceneTree

const SIDE_TIGHT := 3.0
const SIDE_OK := 5.0
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func still(pose: Dictionary) -> Scene:
	var s := Scene.new()
	s.from_dict({"scene": "zz_still", "fps": 30, "cards": [{"name": "a", "pose": pose, "move": -1.0, "hold": 2.0},
		{"name": "b", "pose": pose, "move": 0.5, "hold": 3.0}]})
	return s


func scenes() -> Array:
	return [m.actors_rt[0]["S"], m.actors_rt[1]["S"]]


func xfs() -> Array:
	return [m.actors_rt[0]["xf"], m.actors_rt[1]["xf"]]


func fit(side: float) -> Dictionary:
	return ArenaFit.analyze(scenes(), xfs(), side, 30)


## the fight's needed side (m) with fighter 2 at z = d
func need_at(d: float) -> float:
	m.actor_place(1, Vector2(0.0, d), 180.0)
	m._actors_sync()
	return float(fit(SIDE_TIGHT)["need"])


func cards_json() -> String:
	return JSON.stringify([m.actors_rt[0]["S"].cards, m.actors_rt[1]["S"].cards, (m.actors_rt[1]["xf"] as Transform3D).origin])


## the first label under node whose text holds sub, or null
func find_label(node: Node, sub: String) -> Label:
	if node is Label and String((node as Label).text).contains(sub):
		return node as Label
	for c in node.get_children():
		var f := find_label(c, sub)
		if f != null:
			return f
	return null


func find_node(node: Node, name_: String) -> Node:
	if node.name == name_:
		return node
	for c in node.get_children():
		var f := find_node(c, name_)
		if f != null:
			return f
	return null


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	m.S.cards = m.S.cards.slice(0, 7)
	m._rebuild_cards()
	var sb := DistanceKeeper.new_body()
	sb.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	sb.ground()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, 1.6], "yaw": 180.0}, "scene": still(sb.to_dict())})
	m._actors_sync()
	m._refresh()
	await idle()

	# setup: bisect the spacing until the fight needs 3.40 m (need grows with the spacing)
	var lo := 0.5
	var hi := 4.0
	for i in 40:
		var mid := (lo + hi) * 0.5
		if need_at(mid) < 3.4:
			lo = mid
		else:
			hi = mid
	var d := (lo + hi) * 0.5
	var need := need_at(d)
	print("       spacing %.3f m, the fight needs %.3f m of ring side" % [d, need])

	var c1 := cards_json()
	var at := m.actors_rt[1]["xf"] as Transform3D
	var r3 := fit(SIDE_TIGHT)
	var f3: Dictionary = r3["fighters"][0]
	for f in r3["fighters"]:
		if float(f["room"]) < float(f3["room"]):
			f3 = f
	ok(not bool(r3["fits"]), "(1) %.1f m ring: does NOT fit (%s)" % [SIDE_TIGHT, r3["msg"]])
	ok(String(f3["wall"]) in ["+Z", "-Z"], "(2a) the tightest fighter is pushed toward a wall on the fight line (%s)" % String(f3["wall"]))
	ok(absf(float(f3["room"]) + 0.2) <= 0.02, "(2b) he is %.3f m past it (0.20 m +- 0.02)" % -float(f3["room"]))

	var r5 := fit(SIDE_OK)
	var f5: Dictionary = r5["fighters"][0]
	for f in r5["fighters"]:
		if float(f["room"]) < float(f5["room"]):
			f5 = f
	ok(bool(r5["fits"]), "(3a) %.1f m ring: fits (%s)" % [SIDE_OK, r5["msg"]])
	ok(absf(float(f5["room"]) - 0.8) <= 0.02 and int(f5["steps"]) == 1, "(3b) the tightest room is %.3f m = %d step (0.80 m +- 0.02 = 1)" % [float(f5["room"]), int(f5["steps"])])

	# (4) the moment of the worst reach is inside a strike span of the hero
	var xf_rel: Transform3D = (m.actors_rt[0]["xf"] as Transform3D).affine_inverse() * at
	var spans: Array = DistanceKeeper.analyze(m.actors_rt[0]["S"], m.actors_rt[1]["S"], xf_rel, 30)["spans"]
	var inside := false
	for s in spans:
		if float(f3["t"]) >= float(s["t0"]) - 0.05 and float(f3["t"]) <= float(s["t1"]) + 0.05:
			inside = true
	ok(inside, "(4) the pushed moment %.2f s is inside a strike span (%d spans)" % [float(f3["t"]), spans.size()])

	# (5) and (7): the panel, live
	m.arena_ui.size = SIDE_TIGHT
	m.arena_ui.show()
	await idle()
	var title := find_label(m.ui_find_list, "ARENA FIT")
	ok(title != null and title.text.contains("does NOT fit"), "(5a) the panel says the 3.0 m ring does not fit")
	var sp := find_node(m.ui_find_list, "arena_size") as SpinBox
	ok(sp != null, "(5b) the ring side box is in the panel")
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/arenafit")
	root.get_texture().get_image().save_png("C:/Temp/claude/arenafit/panel_3m.png")
	if sp != null:
		sp.value = SIDE_OK
		await idle()
	title = find_label(m.ui_find_list, "ARENA FIT")
	ok(title != null and title.text.contains("fits a 5.0 m ring") and not title.text.contains("NOT"), "(5c) at 5.0 m the same panel says it fits")
	root.get_texture().get_image().save_png("C:/Temp/claude/arenafit/panel_5m.png")

	var tool := find_tool(m.ui_ribbon["CHECK"], "does the fight fit a ring")
	ok(tool != null, "(7) CHECK ribbon: the Fit the ring tool is there (under FIGHT)")

	ok(cards_json() == c1 and (m.actors_rt[1]["xf"] as Transform3D).origin == at.origin, "(6) read only: cards and the defender's place unchanged")

	print("ARENA FIT %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	quit(1 if fails > 0 else 0)


func find_tool(node: Node, tip_sub: String) -> Node:
	if node is Button and String((node as Button).tooltip_text).contains(tip_sub):
		return node
	for c in node.get_children():
		var f := find_tool(c, tip_sub)
		if f != null:
			return f
	return null
