## godot --path . -s tests/partfirst_test.gd     (N068 part-first actions, N069 weight split, N070 stances that fit the body; needs a window)
## BARS, written BEFORE the implementation and never moved after a run:
##  1 PART-FIRST (real right-clicks and ring clicks through root.push_input)
##    a right-click on the right foot opens the ring with a "Moves" wedge; its second ring offers "Kick"; picking it builds a scene
##      whose MEASURED striker (the foot or hand whose point peaks fastest in the clip) is foot_r; the build is ONE undo step (undo.size()+1)
##      and Ctrl+Z gives the previous scene back
##    the right hand offers "Punch" and builds a clip whose measured striker is hand_r, ONE undo step
##    knee (thigh), elbow (lowerarm), head each OFFER knee strike / elbow / headbutt; hand also offers Block
##  2 WEIGHT SPLIT (WeightSplit)
##    COM at the midpoint of the two feet: 50/50 within 1 percentage point; COM over the left foot: 100/0; over the right: 0/100
##    l + r == 100 for 40 random COM points (always); COM past a foot clamps (0 / 100)
##    one foot down (other lifted): 100/0 on that foot; both feet up (offset y 0.30): shown == false, nothing in the viewport
##    the viewport labels (BalanceView) carry the same numbers as WeightSplit.read on the standing body; hidden in the air
##  3 STANCES (StanceFit, ratios in StanceFit.TABLE; each ratio's source cites a PMID or DOI, or says UNVERIFIED)
##    for boxer, karate (zenkutsu) and fencing (en garde) on a 1.66 m and a 1.91 m body: the planted feet's lateral gap equals
##    ratio x (shoulder width or leg length) within 1 cm, the fore-aft gap likewise; the taller body's width ratio tall/short equals
##    the basis ratio tall/short within 2 percent. CONTROL: a fixed-size stance (the short body's width on the tall body) FAILS the 1 cm bar.
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


func mouse(p: Vector2, btn: int, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_RIGHT if btn == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func rclick(p: Vector2) -> void:
	await move(p)
	await mouse(p, MOUSE_BUTTON_RIGHT, true)
	await mouse(p, MOUSE_BUTTON_RIGHT, false)
	await idle(2)


func screen_of(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position(((c[0] as Vector3) + (c[1] as Vector3)) * 0.5)


func ring_item(prefix: String) -> int:
	for i in m.ui_ring.items.size():
		if String(m.ui_ring.items[i]["name"]).replace("\n", " ").begins_with(prefix):
			return i
	return -1


func ring_names() -> Array:
	return m.ui_ring.items.map(func(it): return String(it["name"]).replace("\n", " "))


func ring_click(i: int) -> void:
	var p: Vector2 = m.ui_ring.at + m.ui_ring.dir(i) * RingMenu.R_TXT
	await move(p)
	await mouse(p, MOUSE_BUTTON_LEFT, true)
	await mouse(p, MOUSE_BUTTON_LEFT, false)
	await idle(3)


## right-click part `j`, open "Moves", return the offered names ([] = no Moves wedge)
func open_moves(j: String) -> Array:
	m.ui_ring.close()
	await rclick(screen_of(j))
	var w := ring_item("Moves")
	if not m.ui_ring.visible or w < 0:
		return []
	await ring_click(w)
	return ring_names() if m.ui_ring.visible else []


func fresh(d: Dictionary) -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	if not d.is_empty():
		b.set_proportions(d)
	b.fk()
	return b


func measure_leg(b: Body) -> float:
	return ((b.P["calf_l"] - b.P["thigh_l"]) as Vector3).length() + ((b.P["foot_l"] - b.P["calf_l"]) as Vector3).length()


func measure_shoulder(b: Body) -> float:
	return absf(float(b.P["upperarm_l"].x) - float(b.P["upperarm_r"].x))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._page_set("POSE", false)
	await idle(4)
	if m.dummy_on:
		m._dummy_toggle()
	# ---- 1 part-first
	var u0: int = m.undo.size()
	var scene0 := JSON.stringify(m.S.to_dict(m.B))
	var names := await open_moves("foot_r")
	print("     foot_r offers: ", names)
	ok(names.size() > 0 and names.any(func(n): return n.begins_with("Kick")), "1 right foot: the Moves ring offers Kick (%s)" % str(names))
	var k := ring_item("Kick")
	if k >= 0:
		await ring_click(k)
		await idle(4)
	var st: String = PartFirst.striker_of(m.S, m.B)
	ok(st == "foot_r", "1 the kick built from the right foot has striker foot_r (measured: %s)" % st)
	ok(m.undo.size() == u0 + 1, "1 the kick build is ONE undo step (%d -> %d)" % [u0, m.undo.size()])
	m._undo()
	await idle(3)
	ok(m.undo.size() == u0 and JSON.stringify(m.S.to_dict(m.B)) == scene0, "1 Ctrl+Z gives the previous scene back")
	u0 = m.undo.size()
	names = await open_moves("hand_r")
	print("     hand_r offers: ", names)
	ok(names.any(func(n): return n.begins_with("Punch")) and names.any(func(n): return n.begins_with("Block")), "1 right hand offers Punch and Block (%s)" % str(names))
	var pu := ring_item("Punch")
	if pu >= 0:
		await ring_click(pu)
		await idle(4)
	st = PartFirst.striker_of(m.S, m.B)
	ok(st == "hand_r", "1 the punch built from the right hand has striker hand_r (measured: %s)" % st)
	ok(m.undo.size() == u0 + 1, "1 the punch build is ONE undo step (%d -> %d)" % [u0, m.undo.size()])
	m._undo()
	await idle(3)
	for pr in [["thigh_r", "Knee"], ["lowerarm_r", "Elbow"], ["head", "Head"]]:
		names = await open_moves(pr[0])
		ok(names.any(func(n): return n.begins_with(pr[1])), "1 %s offers %s (%s)" % [pr[0], pr[1], str(names)])
	m.ui_ring.close()
	# ---- 2 weight split
	var L := Vector2(0.12, 0.0)
	var R := Vector2(-0.12, 0.0)
	var mid := WeightSplit.from_points((L + R) * 0.5, L, R)
	ok(absf(float(mid["l"]) - 50.0) <= 1.0 and absf(float(mid["r"]) - 50.0) <= 1.0, "2 COM at the midpoint: %d / %d (50/50 within 1)" % [mid["l"], mid["r"]])
	var onl := WeightSplit.from_points(L, L, R)
	ok(int(onl["l"]) == 100 and int(onl["r"]) == 0, "2 COM over the left foot: %d / %d" % [onl["l"], onl["r"]])
	var onr := WeightSplit.from_points(R, L, R)
	ok(int(onr["l"]) == 0 and int(onr["r"]) == 100, "2 COM over the right foot: %d / %d" % [onr["l"], onr["r"]])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var all100 := true
	for i in 40:
		var q := Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.3, 0.3))
		var s := WeightSplit.from_points(q, L, R)
		all100 = all100 and int(s["l"]) + int(s["r"]) == 100 and int(s["l"]) >= 0 and int(s["r"]) >= 0
	ok(all100, "2 the two sides sum to 100 (and neither is negative) for 40 random COM points")
	var past := WeightSplit.from_points(Vector2(0.5, 0), L, R)
	ok(int(past["l"]) == 100 and int(past["r"]) == 0, "2 COM past the left foot clamps to 100 / 0")
	var B := fresh({})
	var rd := WeightSplit.read(B)
	ok(bool(rd["shown"]) and int(rd["l"]) + int(rd["r"]) == 100 and int(rd["l"]) >= 40 and int(rd["l"]) <= 60, "2 standing body: %d / %d, shown" % [rd["l"], rd["r"]])
	var lifted := fresh({})
	lifted.offset = Vector3(0, 0.30, 0)
	lifted.fk()
	ok(not bool(WeightSplit.read(lifted)["shown"]), "2 both feet up (offset +0.30 m): nothing shown")
	var one := fresh({})
	one.ang["thigh_r"] = one.clamp_ang("thigh_r", Vector3(80, 0, 0))
	one.ang["calf_r"] = one.clamp_ang("calf_r", Vector3(90, 0, 0))
	one.fk()
	var o1 := WeightSplit.read(one)
	ok(bool(o1["shown"]) and int(o1["l"]) == 100 and int(o1["r"]) == 0, "2 right foot lifted: %d / %d (shown %s)" % [o1["l"], o1["r"], str(o1["shown"])])
	var V := BalanceView.new()
	root.add_child(V)
	if V._im == null:
		V._ready()
	V.on = true
	V.show_body(B)
	var lt: Array = V.split_text()
	ok(lt.size() == 2 and lt[0] == str(rd["l"]) and lt[1] == str(rd["r"]), "2 viewport labels %s equal WeightSplit.read (%d, %d)" % [str(lt), rd["l"], rd["r"]])
	V.show_body(lifted)
	ok(V.split_text().is_empty(), "2 airborne: no label in the viewport")
	# ---- 3 stances
	ok(StanceFit.TABLE.size() == 3, "3 three stances in the table (boxer, karate, fencing)")
	var tall_b := Archetypes.body_for("boxer_heavy")
	var short_b := Archetypes.body_for("boxer_fly")
	for id in ["boxer", "karate", "fencing"]:
		var src := String(StanceFit.TABLE[id]["src"])
		ok(src.contains("PMID") or src.contains("DOI") or src.contains("UNVERIFIED"), "3 %s ratios cite PMID/DOI or say UNVERIFIED" % id)
		var res := {}
		for nm in ["short", "tall"]:
			var b := fresh(short_b if nm == "short" else tall_b)
			var leg := measure_leg(b)
			var sh := measure_shoulder(b)
			StanceFit.apply(b, id)
			var w := absf(float(b.P["ball_l"].x) - float(b.P["ball_r"].x))
			var ln := absf(float(b.P["ball_l"].z) - float(b.P["ball_r"].z))
			var T: Dictionary = StanceFit.TABLE[id]
			var ew: float = float(T["w"][1]) * (sh if T["w"][0] == "shoulder" else leg)
			var el: float = float(T["l"][1]) * (sh if T["l"][0] == "shoulder" else leg)
			ok(absf(w - ew) <= 0.01, "3 %s %s: width %.3f m vs ratio x basis %.3f m (within 1 cm)" % [id, nm, w, ew])
			ok(absf(ln - el) <= 0.01, "3 %s %s: length %.3f m vs ratio x basis %.3f m (within 1 cm)" % [id, nm, ln, el])
			res[nm] = {"w": w, "ew": ew}
		var rw: float = float(res["tall"]["w"]) / float(res["short"]["w"])
		var rb: float = float(res["tall"]["ew"]) / float(res["short"]["ew"])
		ok(float(res["tall"]["w"]) > float(res["short"]["w"]) and absf(rw / rb - 1.0) <= 0.02, "3 %s: tall/short width %.3f vs basis ratio %.3f (within 2%%)" % [id, rw, rb])
		# CONTROL: a fixed-size stance (the short body's width on the tall body) must fail the same 1 cm bar
		var fixed: float = float(res["short"]["w"])
		ok(absf(fixed - float(res["tall"]["ew"])) > 0.01, "3 CONTROL %s: a fixed %.3f m stance on the tall body misses %.3f m by > 1 cm (the bar can fail)" % [id, fixed, float(res["tall"]["ew"])])
	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
