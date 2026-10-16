## godot --headless --path . -s tests/onion_fade_test.gd     (GATES DD1, UPGRADES #43)
## ONION FADES: Onion on over combo3 (12 cards). With the playhead mid-scene: four ghosts, the two cards before it and
## the two after; each ghost's skeleton holds exactly its card's pose (bone by bone against the card posed fresh); the
## alpha of a side's far ghost is below its near one's; past hues warm and future cool (>= 0.2 apart on the wheel),
## and each far ghost's hue farther from the other side than its near one. At the first card: only the future; at the
## end: only the past. A 2-card scene at its middle: one each side. Onion off, or one card: none.
extends SceneTree

var fails := 0
var m: Node
var GB: Body


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the ghost in slot k: [shown, its material colour, the worst bone miss (deg) against card ci]
func ghost(k: int, ci: int) -> Array:
	var g: Array = m.ov._ghosts[k]
	var man: Node3D = g[0]
	var col := Color()
	for mi in man.find_children("*", "MeshInstance3D", true, false):
		col = ((mi as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
		break
	var miss := INF
	if ci >= 0 and ci < m.S.cards.size():
		m.S.apply(GB, float(m.S.times()[ci][1]))
		var sk: Skeleton3D = g[1]
		miss = 0.0
		for j in Body.ORDER:
			var b: int = g[2][j]
			if b >= 0:
				# component by component (up to the quaternion's sign): angle_to's acos of a dot near 1 turns float32
				# rounding into ~0.1 deg of fake miss
				var q1: Quaternion = sk.get_bone_pose_rotation(b)
				var q2: Quaternion = GB.gltf_local(j)
				var dq := minf((q1 - q2).length(), (q1 + q2).length())
				miss = maxf(miss, dq)
	return [man.visible, col, miss]


func hue_gap(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, 1.0 - d)


func shown() -> Array:
	var out := []
	for k in [0, 1, 3, 4]:
		if m.ov._ghosts[k][0].visible:
			out.append(k)
	return out


func at(t: float) -> void:
	m.playhead = t
	m._refresh()
	await idle(2)


func _init() -> void:
	GB = Body.new()
	GB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.ov.onion_on = true
	var ts: Array = m.S.times()
	var mid := (float(ts[5][1]) + float(ts[6][1])) * 0.5   # between card 6 and card 7
	await at(mid)
	var nb: Array = m.ov.neighbours(m.S, mid)
	var want := {0: nb[0], 3: nb[0] - 1, 1: nb[1], 4: nb[1] + 1}
	var gs := {}
	var worst := 0.0
	for k in want:
		gs[k] = ghost(k, want[k])
		worst = maxf(worst, gs[k][2])
	ok(shown() == [0, 1, 3, 4] and worst < 1e-5, "1 mid-scene (between cards %d and %d): 4 ghosts, cards %d %d | %d %d, each its card's pose (worst bone quaternion difference %.7f)" % [nb[0] + 1, nb[1] + 1, want[3] + 1, want[0] + 1, want[1] + 1, want[4] + 1, worst])
	var a := [gs[0][1].a, gs[3][1].a, gs[1][1].a, gs[4][1].a]
	ok(a[1] < a[0] and a[3] < a[2], "2 the far ghost fainter on both sides: past %.2f -> %.2f, future %.2f -> %.2f" % a)
	var h := {}
	for k in gs:
		h[k] = (gs[k][1] as Color).h
	ok(hue_gap(h[0], h[1]) >= 0.2 and hue_gap(h[3], h[1]) > hue_gap(h[0], h[1]) and hue_gap(h[4], h[0]) > hue_gap(h[1], h[0]),
		"3 hues: past near %.2f far %.2f, future near %.2f far %.2f (near past/future %.2f apart; each far one farther from the other side)" % [h[0], h[3], h[1], h[4], hue_gap(h[0], h[1])])
	ok(h[0] < 0.17 and h[3] < 0.17 or h[3] > 0.9, "3b past is warm (red-orange-yellow), future cool")
	await at(0.0)
	var s0 := shown()
	await at(m.S.length())
	var s1 := shown()
	ok(s0 == [1, 4] and s1 == [0, 3], "4 at the first card only the future (%s), at the end only the past (%s)" % [s0, s1])
	m.ov.onion_on = false
	await at(mid)
	ok(shown().is_empty(), "5 Onion off: no ghosts")
	m.ov.onion_on = true
	m._load_scene("res://scenes/combo3.json")
	while m.S.cards.size() > 2:
		m._card_del(m.S.cards.size() - 1)
	await at(m.S.length() * 0.5)
	var s2 := shown()
	m._card_del(1)
	await at(0.0)
	ok(s2 == [0, 1] and shown().is_empty(), "6 two cards, at the middle: one each side (%s); one card: none (%s)" % [s2, shown()])
	print("ONION FADE: %d failed" % fails)
	quit(1 if fails > 0 else 0)
