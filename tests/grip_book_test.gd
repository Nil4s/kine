extends SceneTree
## THE GRIP BOOK (scripts/grip_book.gd; Nick 10-20: "the weapons have a body for limits and parts for grip, so we record
## all the possible grips and stop guessing"). Bars:
##   1 every weapon has a body (parts covering it end to end) and a book; every hand of every grip is on a part a hand holds
##   2 the main hand is EXACT on every grip: from Nick's bo pose and from a T-pose (two different arms), its palm sits the
##     same distance off the shaft's axis (as recorded: 1.9 cm for Nick's bat hand, 1.4 for his bo hand) within 1 mm, at
##     the grip's spot within 1 mm
##   3 from Nick's two-hand bo pose, the wide grips (staff x3, spear two hands + close, sledge spread, axe two hands,
##     half-sword) put the second wrist on its recorded place within 3 cm (only the arm is fitted)
##   4 a grip recorded with its arms (Nick's bo hold), applied to a T-posed body: both hands land on the shaft, the second
##     within 1 cm (no search)
##   5 RECORD -> PLAY: Nick's bo guard pose recorded into a test book, then applied to a fresh T-posed body: both palms
##     back on the shaft within 1 cm of their recorded spots
##   6 the body is a LIMIT: [ ] can't slide the second hand onto a katana's tsuba or blade (it stops at the tsuka's end)
##   7 the palette has Grip: next grip in the book / Grip: record this one; the command cycles the bat's grips
## Screenshots tmp/grip_book_<name>.png (looked at before merging)
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/grip_book_%s.png"
const WIDE := [["staff", "nick_bo"], ["staff", "thirds"], ["staff", "long_reach"], ["spear", "two_hand"], ["spear", "close"],
	["long_hammer", "sledge_spread"], ["long_axe", "two_hand"], ["longsword", "half_sword"]]
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return b


func pose(nm: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://moves/%s.json" % nm))


## a hand's palm against the shaft now: [off the axis (m), u (m from the butt)]
func palm(B: Body, h: String) -> Array:
	var x := B.wep_xform()
	var pl := (x[1] as Quaternion).inverse() * (B.palm_point(h) - (x[0] as Vector3))
	return [Vector2(pl.x, pl.z).length(), pl.y]


func _init() -> void:
	# (1)
	var bad := []
	var n := 0
	for k in Body.KINDS:
		var parts: Array = Body.KINDS[k].get("parts", [])
		var L := float(Body.KINDS[k]["len"])
		var u := 0.0
		var cover := not parts.is_empty()
		while u <= L and cover:
			cover = not GripBook.part_at(k, L, u).is_empty()
			u += 0.01
		var gs := GripBook.grips(k)
		if not cover or gs.is_empty():
			bad.append(k)
		for g in gs:
			for hd in g["hands"]:
				n += 1
				if not GripBook.holdable(k, L, float(hd["u"]), true):
					bad.append("%s/%s" % [k, g["name"]])
	ok(bad.is_empty(), "(1) %d weapons have a body and a book; %d hands, all on a holdable part %s" % [Body.KINDS.size(), n, bad])

	# (2) + (3)
	var worst_off := 0.0
	var worst_u := 0.0
	var wide := []
	var B := body()
	var bo := pose("bo_two_hand_nick")
	for k in Body.KINDS:
		for g in GripBook.grips(k):
			B.from_dict(bo)
			B.set_kind(k)
			var r := GripBook.apply(B, g)
			var mh: Dictionary = {}
			for hd in g["hands"]:
				if hd["role"] == "main":
					mh = hd
			var p := palm(B, B.wep_hand)
			var T0 := body()
			T0.set_kind(k)
			T0.weapon_to_hand("hand_r")
			GripBook.apply(T0, g)
			worst_off = maxf(worst_off, absf(float(p[0]) - float(palm(T0, T0.wep_hand)[0])))
			worst_u = maxf(worst_u, absf(float(p[1]) - float(mh["u"])))
			for w in WIDE:
				if w[0] == k and w[1] == g["name"]:
					wide.append("%s/%s %.1f" % [k, g["name"], float(r["miss"]) * 100.0])
					if float(r["miss"]) > 0.03:
						wide.append("<- FAIL")
	ok(worst_off < 0.002 and worst_u < 0.002, "(2) the main hand exact on every grip: palm off the axis the same from two poses within %.2f mm, at its spot within %.2f mm" % [worst_off * 1000.0, worst_u * 1000.0])
	ok(wide.size() == WIDE.size() and not "<- FAIL" in wide, "(3) from Nick's bo pose, the wide grips' second wrist (cm off): %s" % ", ".join(wide))

	# (4)
	var T := body()
	T.set_kind("staff")
	T.weapon_to_hand("hand_r")
	var r4 := GripBook.apply(T, GripBook.find("staff", "nick_bo"))
	var pl4 := palm(T, "hand_l")
	ok(r4["arms"] and float(r4["miss"]) < 0.01 and float(pl4[0]) < 0.05, "(4) Nick's bo hold from a T-pose (arms as recorded): the second wrist %.1f cm off, its palm %.1f cm from the axis" % [float(r4["miss"]) * 100.0, float(pl4[0]) * 100.0])

	# (5)
	GripBook.dir = "user://grip_book_test_%d" % OS.get_process_id()
	var G := body()
	G.from_dict(pose("bo_guard"))
	var e := GripBook.capture(G, "rt", "round trip")
	var want := []
	for h in ["hand_r", "hand_l"]:
		want.append(palm(G, h))
	var two := not e.has("why") and (e["hands"] as Array).size() == 2
	if not e.has("why"):
		GripBook.record(G.wep_kind, e)
	var F := body()
	F.set_kind(G.wep_kind)
	F.weapon_to_hand("hand_r")
	var r5 := GripBook.apply(F, GripBook.find(G.wep_kind, "rt"))
	var du := 0.0
	for i in 2:
		var p5 := palm(F, ["hand_r", "hand_l"][i])
		du = maxf(du, absf(float(p5[1]) - float(want[i][1])) + absf(float(p5[0]) - float(want[i][0])))
	ok(two and float(r5["miss"]) < 0.01 and du < 0.01, "(5) Nick's bo guard recorded, then played on a T-posed body: both palms back within %.1f mm (second wrist %.1f cm off)" % [du * 1000.0, float(r5["miss"]) * 100.0])
	for f in DirAccess.get_files_at(GripBook.dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GripBook.dir).path_join(f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GripBook.dir))
	GripBook.dir = GripBook.DIR

	# (6) + (7) in the app
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._do(m._kind.bind("katana"))
	await idle(2)
	m.B.grip = true
	m.B.grip_u = 0.20
	for i in 10:
		m._press(KEY_BRACKETRIGHT)
	await idle(2)
	ok(m.B.grip_u <= 0.26 + 1e-4, "(6) ] ten times from 20 cm on a katana: the second hand stops at %.0f cm (the tsuka ends at 26, the tsuba is not held)" % (m.B.grip_u * 100.0))
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	m._do(m._kind.bind("metal_bat"))
	await idle(2)
	var seen := []
	for i in 3:
		m._grip_next()
		await idle(1)
		seen.append(String(m.ui_status.text).get_slice(":", 0))
	ok(src.contains('add.call("Grip: next grip in the book"') and src.contains('add.call("Grip: record this one"') and seen[0] != seen[1] and seen[1] != seen[2], "(7) the palette commands; next grip cycles: %s" % str(seen))

	# screenshots: Nick's bo hold on the staff, the spear two hands, from his pose
	for sh in [["staff", "thirds"], ["spear", "two_hand"], ["long_hammer", "sledge_spread"]]:
		m.B.from_dict(bo)
		m.B.set_kind(sh[0])
		GripBook.apply(m.B, GripBook.find(sh[0], sh[1]))
		m.yaw = 30.0
		m.dist = 3.0
		m.pitch = -5.0
		m.target = Vector3(m.B.P["pelvis"].x, 1.1, m.B.P["pelvis"].z)
		m._cam()
		m._refresh()
		await idle(4)
		root.get_texture().get_image().save_png(SHOT % ("%s_%s" % sh))
	print("GRIP BOOK ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
