## godot --path . -s tests/mirror_inplace_test.gd     (ROADMAP 54; needs a window: the ribbon's layout)
## MIRROR IN PLACE: the open scene (combo3) mirrored in memory equals the copy Mirror the scene writes, card by card,
## within 0.01 deg on every joint's bend, side and twist, and the offset. Mirroring twice gives the original back
## within 0.01 deg. One Ctrl+Z restores the scene's hash. The ribbon button exists, has its icon and sits in its group.
## A control: the mirrored cards must differ from the originals by a real amount (or the check proves nothing).
extends SceneTree

var fails := 0
var m: Node
const TOL := 0.01


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the worst difference in degrees between two lists of cards' joint angles (bend, side, twist) and offsets, and where
func worst(a: Array, b: Array) -> Array:
	var w := 0.0
	var at := ""
	if a.size() != b.size():
		return [INF, "card count %d vs %d" % [a.size(), b.size()]]
	for i in a.size():
		var pa: Dictionary = a[i]["pose"]
		var pb: Dictionary = b[i]["pose"]
		var ja: Dictionary = pa["joints"]
		var jb: Dictionary = pb["joints"]
		if ja.size() != jb.size():
			return [INF, "card %d: %d joints vs %d" % [i, ja.size(), jb.size()]]
		for j in ja:
			if not jb.has(j):
				return [INF, "card %d: %s missing" % [i, j]]
			for k in ["bend", "side", "twist"]:
				var e := absf(float(ja[j][k]) - float(jb[j][k]))
				if e > w:
					w = e
					at = "card %d %s %s" % [i, j, k]
		var oa: Array = pa.get("offset", [0, 0, 0])
		var ob: Array = pb.get("offset", [0, 0, 0])
		for k in 3:
			var e := absf(float(oa[k]) - float(ob[k]))
			if e > w:
				w = e
				at = "card %d offset %d" % [i, k]
	return [w, at]


func cards() -> Array:
	return m._scene_dict(false)["cards"]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle(4)
	var orig: Array = JSON.parse_string(JSON.stringify(cards()))
	var h0: int = JSON.stringify(m._scene_dict(false)).hash()
	var name0: String = m.S.name
	# the copy Mirror the scene writes (the same dict, through the file's own JSON)
	var want: Array = JSON.parse_string(JSON.stringify(m._mirrored_dict()))["cards"]
	var ctl: Array = worst(orig, want)
	ok(ctl[0] > 5.0, "control: the mirrored cards differ from the originals by %.1f deg (%s), so the check can fail" % [ctl[0], ctl[1]])
	# the button: in ANIMATE, its icon, in its group's span
	var btn: Button = null
	for b in m.ui_ribbon["ANIMATE"].get_children():
		if b is Button and m.label_of(b) == "Mirror in place":
			btn = b
	var in_group: bool = "Mirror in place" in (m.RIBBON_GROUPS["ANIMATE"].filter(func(g): return g[0] == "MIRROR")[0][1])
	var at_bar := false
	var under_cap := false
	m.ui_ribbon_tabs["ANIMATE"].pressed.emit()   # the tab the button lives on (its caption shows only on its tab)
	await idle(6)
	if btn != null:
		at_bar = btn.visible and btn.get_global_rect().end.y <= m.TOP_H and btn.get_global_rect().end.x <= m.get_viewport().get_visible_rect().size.x
		for pair in m.ui_caps["ANIMATE"]:
			if pair[0].text.begins_with("MIRROR"):
				var c: Rect2 = pair[0].get_global_rect()
				var r: Rect2 = btn.get_global_rect()
				under_cap = pair[0].visible and c.position.x <= r.end.x and c.end.x >= r.position.x
	ok(btn != null and btn.icon != null and btn.text == "" and m.ICON_OF.get("Mirror in place", "") == "mirror_inplace" and in_group,
		"ANIMATE has 'Mirror in place' with its icon (%s), no words, in the MIRROR group" % m.ICON_OF.get("Mirror in place", "-"))
	ok(at_bar and under_cap, "the button sits on the bar (%s) inside its group's caption (%s)" % [at_bar, under_cap])
	# one press = the mirror in place, as one undo step
	btn.pressed.emit()
	await idle(2)
	var r1: Array = worst(want, cards())
	ok(r1[0] <= TOL, "mirror in place on combo3 == the Mirror-the-scene copy's cards: worst %.4f deg (%s), tolerance %.2f" % [r1[0], r1[1], TOL])
	ok(m.S.name == name0 and m.S.cards.size() == orig.size(), "the scene keeps its name '%s' and its %d cards (the copy's name would be _mirrored)" % [m.S.name, m.S.cards.size()])
	m._undo()
	await idle(3)
	var h1: int = JSON.stringify(m._scene_dict(false)).hash()
	ok(h1 == h0, "one undo restores the scene hash (%d)" % h0 if h1 == h0 else "one undo restores the scene hash: %d became %d" % [h0, h1])
	# mirroring twice returns the original, card by card
	m._mirror_in_place()
	m._mirror_in_place()
	await idle(2)
	var r2: Array = worst(orig, cards())
	ok(r2[0] <= TOL, "mirroring twice gives the original back: worst %.4f deg (%s), tolerance %.2f" % [r2[0], r2[1], TOL])
	ok(m.undo.size() >= 2, "two presses are two undo steps (the undo stack holds %d)" % m.undo.size())
	m._undo()
	m._undo()
	await idle(2)
	ok(JSON.stringify(m._scene_dict(false)).hash() == h0, "two undos bring the scene hash back to the start")
	print("MIRROR IN PLACE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
