extends SceneTree
## THE WEAPON LIST (round 49, Nick 10-20: "we need to create a list of weapons ... 2 hands, then 1 hand, then back").
## Every Body.KINDS entry, picked the way the app picks one (main._kind, one undo step):
##   1 it is in the dropdown and the palette, and its line in the status names its length
##   2 the bat hand holds the HANDLE (the hand's grip point between the butt and the handle's end), never the blade or head
##   3 two-handed kinds (longsword, katana, spear, staff, hammer, axe): G is on, the second hand's spot is on the part a
##     hand can hold (a blade's grip; a haft's lower three quarters), at least one hand's width (8 cm) from the bat hand
##     and no further than the shoulders allow (75 cm). The hand goes there when the arms are posed (as for every kind:
##     an automatic guard from a T-pose was tried and dropped, round 49: the arm search trades the wrist's place against
##     the weapon's aim and misses by 10-25 cm)
##   4 one-handed kinds (sword, dagger, bat): no second hand
##   5 G takes the second hand off a longsword and puts it back (the switch Nick asked for), each one undo step
## Screenshots, one per kind: tmp/kinds_<kind>.png (looked at before merging)
const SHOTS := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/kinds_%s.png"
const TWO := ["staff", "long_hammer", "long_axe", "longsword", "katana", "spear"]
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	for k in Body.KINDS:
		var listed := false
		for w in m.WEAPONS:
			listed = listed or w[1] == k
		var cmd: bool = src.contains('_kind.bind("%s")' % k)
		m._do(m._kind.bind(k))
		await idle(2)
		var B: Body = m.B
		var said: String = m.ui_status.text
		ok(listed and cmd and B.wep_kind == k and (said.contains("cm") or said.contains(" m")), "(1) %s: in the dropdown %s, the palette %s; it says: %s" % [k, listed, cmd, said.left(70)])
		var hu := B.hold_u()
		var hend := B.wep_handle
		ok(hu > 0.0 and hu < hend + 0.01, "(2) %s: the bat hand holds the handle at %.0f cm from the butt (the handle ends at %.0f cm)" % [k, hu * 100.0, hend * 100.0])
		if k in TWO:
			var hold_max: float = hend if k in ["longsword", "katana"] else B.wep_len * 0.75
			var on_handle := B.grip_u >= 0.0 and B.grip_u <= hold_max + 0.01
			var apart := absf(B.grip_u - hu)
			ok(B.grip and on_handle and apart >= 0.08 and apart <= 0.75, "(3) %s: G on, the second hand's spot at %.0f cm from the butt (holdable to %.0f cm), %.0f cm from the bat hand" % [k, B.grip_u * 100.0, hold_max * 100.0, apart * 100.0])
		else:
			ok(not B.grip, "(4) %s: one hand" % k)
		m.yaw = 35.0
		m.dist = 3.2
		m.pitch = -6.0
		m.target = Vector3(B.P["pelvis"].x, 1.0, B.P["pelvis"].z)
		m._cam()
		m._refresh()
		await idle(4)
		root.get_texture().get_image().save_png(SHOTS % k)

	# (5) the longsword: G off, G on
	m._do(m._kind.bind("longsword"))
	await idle(2)
	m._press(KEY_G)
	await idle(2)
	var off: bool = not m.B.grip
	m._press(KEY_G)
	await idle(2)
	ok(off and m.B.grip, "(5) longsword: G takes the second hand off (%s) and puts it back (%s)" % [off, m.B.grip])
	print("WEAPON KINDS ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
