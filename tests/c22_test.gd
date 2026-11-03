## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/c22_test.gd     (C22, complaints 177 20 2; a window)
## BARS (written and committed before the first run). Env C22_SHOT=<dir> saves 1280x720 screenshots.
##  A  attach on EITHER hand (scripts/c22_hands.gd take_with; palette commands "Prop: attach to the LEFT / RIGHT hand")
##   A1 for hand in right, left: a 10 cm pillar under that hand; two cards (rest; that ARM only turned 40 degrees at the shoulder):
##      take_with on card 1 gives carries()[0].hands == [hand]; at card 2 the pillar moved by the hand's own displacement
##      (<= 1 mm), and that displacement is >= 10 cm so the bar can see it.
##      CONTROL: the other hand did not move (<= 1 mm), so a prop held by the wrong hand would differ by >= 10 cm.
##   A2 the command (real call of the handler, card and prop picked): one undo step, card 1's mark = {"prop":0,"hands":[hand]};
##      Ctrl+Z gives the cards back byte for byte (var_to_str); no card picked: refused with a reason, nothing changed.
##   A3 Mirror (Scene.mirror_file) of the left-hand scene holds it in the right hand.
##  B  grip a prop by its handle, no dummy (C22Hands.grip_handle)
##   B1 cases sword_r, sword_l (a sword lying in front of the hand) and bar_r (a 4 cm bar standing, axis y): the handle axis is the
##      long axis (|component| > 0.999). After the grip: the palm is -1 mm .. +30 mm from the prop's surface, within HAND_SPAN/2
##      (5 cm) of the handle centre along the axis, the wrist reached (wrist_m <= 1 cm), every fingertip on the surface (<= 3 mm)
##      or at its limit, no finger segment or thumb segment inside by more than 1 mm, the 15 finger joints keyed at the playhead.
##      CONTROL: AnyGrip.grip_prop alone (the old path, no placement) from the rest pose leaves the palm > 10 cm from the prop.
##   B3 the command says "handle" in the status line; a screenshot at 1280x720.
##  C  IK/FK snap, JOINT POSITIONS (scripts/limb_ik.gd to_fk / to_ik; ikfk_test already bars the tip and the angles)
##   C1 combo3, hand_r, hand_l, foot_l, both directions, the middle of cards 4, 7, 11 (18 switches): the worst gap of the three chain
##      joints (shoulder or hip, elbow or knee, wrist or ankle) between the pose just before and just after the switch <= 1 mm.
##      CONTROL: an IK key whose target is 2 cm off the FK tip moves the tip by >= 1 cm (the measure sees a pop).
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


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func shot(name: String) -> void:
	var d := OS.get_environment("C22_SHOT")
	if d == "":
		return
	DirAccess.make_dir_recursive_absolute(d)
	root.get_viewport().get_texture().get_image().save_png(d + "/" + name + ".png")


func hand_p(S: Scene, B: Body, hand: String, t: float) -> Vector3:
	S.apply(B, t)
	return B.P[hand]


func chain_p(B: Body, tip: String) -> Array:
	var mid: String = B.parent[tip]
	return [B.P[B.parent[mid]], B.P[mid], B.P[tip]]


func gap(a: Array, b: Array) -> float:
	var w := 0.0
	for i in a.size():
		w = maxf(w, ((a[i] as Vector3) - (b[i] as Vector3)).length())
	return w


func load_combo() -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	return S


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var B := body()
	# ------------------------------------------------------------ A
	for hand in ["hand_r", "hand_l"]:
		var sd: String = hand.right(2)
		var B0 := body()
		var c := B0.cap(hand)
		var mid: Vector3 = ((c[0] as Vector3) + (c[1] as Vector3)) / 2.0
		var h: float = mid.y - float(B0.rad[hand]) + 0.01
		Props.register("zz pillar", AABB(Vector3(-0.05, 0, -0.05), Vector3(0.1, h, 0.1)), "", 1.0)
		var raised := body()
		var up_j := "upperarm" + sd
		raised.ang[up_j] = (raised.ang[up_j] as Vector3) + Vector3(40.0, 0.0, 0.0)
		raised.fk()
		var S := Scene.new()
		S.props = [Props.make("zz pillar", Props.xf_at(Vector3(mid.x, 0, mid.z), 0.0))]
		S.on_floor = false
		S.add("rest", B0.to_dict())
		S.add("raised", raised.to_dict())
		var why := C22Hands.take_with(S, 0, 0, sd)
		var cs := S.carries()
		ok(why == "" and cs.size() == 1 and cs[0]["hands"] == [sd], "A1 %s: take_with gives the carry hands %s" % [hand, cs[0]["hands"] if cs.size() == 1 else "none"])
		var t1: float = S.times()[1][1]
		var other := "hand_l" if hand == "hand_r" else "hand_r"
		S.apply(B, 0.0)
		var fr0 := Scene.hand_frame(B, [sd])
		var fo0 := Scene.hand_frame(B, [("_l" if sd == "_r" else "_r")])
		S.apply(B, t1)
		var fr1 := Scene.hand_frame(B, [sd])
		var fo1 := Scene.hand_frame(B, [("_l" if sd == "_r" else "_r")])
		S.apply(B, 0.0)
		var p0: Vector3 = (S.props_at(0.0, B)[0]["xf"] as Transform3D).origin
		S.apply(B, t1)
		var p1: Vector3 = (S.props_at(t1, B)[0]["xf"] as Transform3D).origin
		# the pillar is rigid in the chosen hand's frame: p1 = frame1 * frame0^-1 * p0 (the frame turns, so the wrist's own move is not the test)
		var exp1 := fr1 * (fr0.affine_inverse() * p0)
		var exo1 := fo1 * (fo0.affine_inverse() * p0)
		ok((fr1.origin - fr0.origin).length() >= 0.10, "A1 %s: the hand moved %.1f cm (>= 10 cm, the bar can see it)" % [hand, (fr1.origin - fr0.origin).length() * 100.0])
		ok(p1.distance_to(exp1) <= 0.001, "A1 %s: the pillar is %.2f mm from where the chosen hand's frame puts it" % [hand, p1.distance_to(exp1) * 1000.0])
		ok(p1.distance_to(exo1) >= 0.10, "A1 CONTROL %s: the other hand's frame would put it %.1f cm away (>= 10 cm)" % [hand, p1.distance_to(exo1) * 100.0])
		if sd == "_l":
			var M := Scene.new()
			M.from_dict(Scene.mirror_file(S.to_dict(B), body()))
			var mc := M.carries()
			ok(mc.size() == 1 and mc[0]["hands"] == ["_r"], "A3 Mirror of the left-hand scene holds it in the right hand (%s)" % [mc[0]["hands"] if mc.size() == 1 else "none"])
		# A2 the command
		m.S = S
		m._rebuild_cards()
		m.sel_prop = 0
		m.sel_card = 0
		S.cards[0].erase("take")
		var before := var_to_str(S.cards)
		var u0: int = m.undo.size()
		if sd == "_l":
			C22Hands.take_left(m)
		else:
			C22Hands.take_right(m)
		ok(m.S.cards[0].get("take", {}) == {"prop": 0, "hands": [sd]} and m.undo.size() == u0 + 1, "A2 %s: the command marks card 1 with %s, one undo step" % [hand, m.S.cards[0].get("take", {})])
		m._undo()
		await idle(2)
		ok(var_to_str(m.S.cards) == before, "A2 %s: Ctrl+Z gives the cards back byte for byte" % hand)
		m.sel_card = 9
		var u1: int = m.undo.size()
		if sd == "_l":
			C22Hands.take_left(m)
		else:
			C22Hands.take_right(m)
		ok(var_to_str(m.S.cards) == before and m.undo.size() == u1, "A2 %s: card out of range: refused, nothing changed ('%s')" % [hand, m.ui_status.text.left(60)])
	# ------------------------------------------------------------ B
	for case in ["sword_r", "sword_l", "bar_r"]:
		var h := "hand_l" if case.ends_with("_l") else "hand_r"
		var Bg := body()
		var pc: Vector3 = Bg.palm_point(h) + AnyGrip.curl_dir(Bg, h) * 0.06 + Vector3(0, 0, 0.1)
		var prop: Dictionary
		var axis_i := 0
		if case.begins_with("sword"):
			prop = Props.make("sword", Props.xf_at(Vector3(pc.x, pc.y - 0.015, pc.z), 0.0))
		else:
			Props.register("zz bar", AABB(Vector3(-0.02, 0, -0.02), Vector3(0.04, 0.5, 0.04)), "", 1.0)
			prop = Props.make("zz bar", Props.xf_at(Vector3(pc.x, pc.y - 0.25, pc.z), 0.0))
			axis_i = 1
		var hd := C22Hands.handle_of(prop)
		ok(not hd.is_empty() and absf((hd["ax"] as Vector3)[axis_i]) > 0.999, "B1 %s: the handle axis is the long axis (%s)" % [case, hd.get("ax", "none")])
		if hd.is_empty():
			continue
		var ctr: Vector3 = hd["c"]
		var F := AnyGrip.field_of(prop)
		var fn: Callable = F["sd"]
		var Bc := body()
		AnyGrip.grip_prop(Bc, h, F, {}, 0.0)
		var far := float(fn.call(Bc.palm_point(h)))
		var pk := {}
		var rep := C22Hands.grip_handle(Bg, h, prop, pk, 0.0)
		var palm := Bg.palm_point(h)
		var sdp := float(fn.call(palm))
		var along := absf((palm - ctr).dot(hd["ax"]))
		ok(sdp >= -0.001 and sdp <= 0.03, "B1 %s: the palm is %.1f mm from the prop surface (-1 .. 30 mm)" % [case, sdp * 1000.0])
		ok(along <= C22Hands.HAND_SPAN * 0.5, "B1 %s: the palm is %.1f cm along the axis from the handle centre (<= 5 cm)" % [case, along * 100.0])
		ok(float(rep["place"]["wrist_m"]) <= 0.01, "B1 %s: the wrist reached (%.1f mm off)" % [case, float(rep["place"]["wrist_m"]) * 1000.0])
		var bad := []
		for f in GripWrap.LONG:
			var tip: Array = rep[f][2]
			if not (float(tip[1]) <= 0.003 or tip[2] == "limit"):
				bad.append("%s tip %.1f mm off" % [f, float(tip[1]) * 1000.0])
			for row in rep[f]:
				if float(row[1]) < -0.001:
					bad.append("%s joint inside %.1f mm" % [f, float(row[1]) * 1000.0])
		for row in rep["thumb"]:
			if float(row[1]) < -0.001:
				bad.append("thumb inside %.1f mm" % [float(row[1]) * 1000.0])
		ok(bad.is_empty(), "B1 %s: every fingertip on the surface or at its limit, nothing inside by > 1 mm %s" % [case, bad])
		ok(pk.size() == 15, "B1 %s: %d finger joints keyed" % [case, pk.size()])
		ok(far > 0.10, "B1 CONTROL %s: grip_prop alone from rest leaves the palm %.1f cm from the prop (> 10 cm)" % [case, far * 100.0])
	# the command on screen
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle(3)
	var Bm := m.B as Body
	var pc2: Vector3 = Bm.palm_point("hand_r") + AnyGrip.curl_dir(Bm, "hand_r") * 0.06 + Vector3(0, 0, 0.1)
	m.S.props = [Props.make("sword", Props.xf_at(Vector3(pc2.x, pc2.y - 0.015, pc2.z), 0.0))]
	m.sel_prop = 0
	m.sel = "hand_r"
	m._props_show()
	C22Hands.grip_handle_cmd(m)
	await idle(4)
	ok(m.ui_status.text.contains("handle"), "B3 the command says: '%s'" % m.ui_status.text.left(90))
	shot("grip_handle")
	# ------------------------------------------------------------ C
	var base := load_combo()
	var ts := base.times()
	var worst := 0.0
	var n := 0
	for tip in ["hand_r", "hand_l", "foot_l"]:
		for dir in ["fk2ik", "ik2fk"]:
			for ci in [3, 6, 10]:
				var f := int(round((float(ts[ci][1]) + float(ts[ci][2])) * 0.5 * base.fps))
				var t := float(f) / base.fps
				var S2 := load_combo()
				if dir == "ik2fk":
					var t0 := (float(ts[0][1]) + float(ts[0][2])) * 0.5
					S2.apply(B, t0)
					LimbIK.pin(S2, B, tip, t0)
				S2.apply(B, t)
				var a := chain_p(B, tip)
				var r: Dictionary = LimbIK.to_ik(S2, B, tip, t) if dir == "fk2ik" else LimbIK.to_fk(S2, B, tip, t)
				if dir == "ik2fk" and not r["ok"]:
					ok(false, "C1 %s %s f%d: refused" % [tip, dir, f])
					continue
				S2.apply(B, t)
				var g := gap(a, chain_p(B, tip))
				worst = maxf(worst, g)
				n += 1
				print("  C1 %s %s f%d: worst joint gap %.4f mm" % [tip, dir, f, g * 1000.0])
	ok(n == 18 and worst <= 0.001, "C1 %d switches, worst joint gap %.4f mm (<= 1 mm)" % [n, worst * 1000.0])
	var Sn := load_combo()
	var tn: float = (float(ts[3][1]) + float(ts[3][2])) * 0.5
	Sn.apply(B, tn)
	var a0: Vector3 = B.P["hand_r"]
	LimbIK.put(Sn.ik, "hand_r", {"t": tn, "target": a0 + Vector3(0, 0.02, 0), "pole": LimbIK.pole_from_pose(B, "hand_r"), "w": 1.0, "rot": B.G["hand_r"]})
	Sn.apply(B, tn)
	var pop := ((B.P["hand_r"] as Vector3) - a0).length()
	ok(pop >= 0.01, "C1 CONTROL: an IK key 2 cm off moves the tip %.1f mm (>= 10 mm)" % [pop * 1000.0])
	print("c22: %d fail%s" % [fails, "" if fails == 1 else "s"])
	quit(1 if fails > 0 else 0)
