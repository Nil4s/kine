## godot --headless --path . -s tests/props_generic_test.gd     (GAP_ANALYSIS row 22: generic props; headless)
## 1. SIZES: every `kind.field = value` line of docs/research/PROPS.md against Props.KINDS (0.1 mm / 1 g).
## 2. DOOR HINGE: a door keyed 0 -> 90 deg over 1 s: its free edge stays on the hinge's arc (radius = the leaf's width,
##    height fixed) within 1 mm at every frame, the swing climbs without overshoot, ends at 90 deg on the spot the arc
##    says, and the leaf's collision box swings with it (its far edge = the free edge, 1 mm); swung into the body,
##    Check's contact (Rulebook.prop_hits) sees it, shut it does not. A ball against a hand is seen too (a sphere).
## 3. CARRY + CHILD OF: a moving box held in the right hand over a played scene stays at its grip in the hand within
##    1 mm, and the LEFT hand's Child Of on the box (target = the prop) follows the box within 1 mm. Before row 22 a
##    prop target was the box's stored place: the same measure is printed for that (it is metres off).
## 4. FILE: the scene with a keyed door, a ball and the carry saved, read back and saved again: the same JSON; the door
##    plays the same after the trip; mirrored twice = the original; mirrored once, the free edge is the reflection.
## 5. OLD SCENES: a scene with only round-37 props (a carried box tossed, a chair, a table) saves, mirrors and plays its
##    props bit for bit as before row 22: a sha256 over all of it equals the digest taken on the code before row 22
##    (poser-ui-rounds c0ea5e4). If another round changes the body or the carry, re-take it on the commit before.
extends SceneTree

const OLD_DIGEST := "6fa7666760618e52ec2cef2e2dc83bbff6f245a3da41f9804717d5d41730c4ca"
const MM := 0.001

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


## BEGIN OLD SCENE (copied verbatim into tests/props_generic_test.gd)
## a scene with only the props that existed before row 22 (a box carried in both hands, walked and tossed; a chair and a
## table standing by): what it plays and saves must not change by a bit
func old_scene(B: Body) -> Scene:
	for sd in ["_l", "_r"]:
		B.set_ang("upperarm" + sd, Vector3(0, -80, 0))
		B.set_ang("lowerarm" + sd, Vector3(90, 0, 0))
	B.fk()
	B.ground()
	var hm := ((B.cap("hand_l")[0] as Vector3) + (B.cap("hand_l")[1] as Vector3) + (B.cap("hand_r")[0] as Vector3) + (B.cap("hand_r")[1] as Vector3)) / 4.0
	var box := Props.make("box", Props.xf_at(Vector3(hm.x, hm.y - 0.10, hm.z), 0.0))
	for k in 40:
		if Rulebook.prop_hits([box], B, {0: ["hand_l", "hand_r", "lowerarm_l", "lowerarm_r"]}).is_empty():
			break
		var xf: Transform3D = box["xf"]
		xf.origin.z += 0.01
		box["xf"] = xf
	var S := Scene.new()
	S.name = "zz_old_set"
	S.props = [box, Props.make("chair", Props.xf_at(Vector3(1.2, 0, 1.0), 30.0)), Props.make("table", Props.xf_at(Vector3(-1.4, 0, 1.2), -20.0))]
	S.add("take", B.to_dict())
	B.offset.z += 0.4
	B.fk()
	S.add("walk", B.to_dict())
	for sd in ["_l", "_r"]:
		B.set_ang("lowerarm" + sd, Vector3(40, 0, 0))
	B.fk()
	S.add("toss", B.to_dict())
	S.add("after", B.to_dict())
	S.cards[0]["take"] = {"prop": 0, "hands": ["_l", "_r"]}
	S.cards[2]["drop"] = 0
	return S


func old_digest() -> String:
	var B := body()
	var S := old_scene(B)
	var M := body()
	var P := body()
	var d := S.to_dict(P, false)
	var txt := JSON.stringify(d) + JSON.stringify(Scene.mirror_file(d, M))
	for f in int(S.length() * 30.0) + 15:
		var t := f / 30.0
		S.apply(P, t)
		var pa := S.props_at(t, P)
		for p in pa:
			txt += var_to_str(p["xf"])
		txt += str(Rulebook.prop_hits(pa, P, S.holding(t, P)).size())
	var Q := Scene.new()   # no carry: props_at hands back the set itself
	Q.props = S.props.duplicate()
	txt += str(is_same(Q.props_at(0.5, P), Q.props))
	return txt.sha256_text()
## END OLD SCENE


## the doc's `kind.field = value` numbers
func doc_numbers() -> Dictionary:
	var f := FileAccess.open("res://docs/research/PROPS.md", FileAccess.READ)
	var out := {}
	if f == null:
		return out
	var re := RegEx.new()
	re.compile("`([a-z_]+)\\.([a-z_]+) = ([0-9.]+)`")
	for m in re.search_all(f.get_as_text()):
		out[m.get_string(1) + "." + m.get_string(2)] = float(m.get_string(3))
	return out


func sizes() -> void:
	var D := doc_numbers()
	ok(D.size() >= 16, "the doc lists %d sourced numbers" % D.size())
	var K := Props.KINDS
	var ball: Array = K["ball"]["spheres"][0]
	var d := 2.0 * float(ball[1])
	ok(absf(d - D.get("ball.diameter", -1.0)) < 1e-4 and absf((ball[0] as Vector3).y - float(ball[1])) < 1e-6, "ball: diameter %.4f m (doc %.4f), resting on the floor" % [d, D.get("ball.diameter", -1.0)])
	ok(d * PI >= D.get("ball.circumference_min", 9.0) and d * PI <= D.get("ball.circumference_max", -9.0), "ball: circumference %.3f m inside IFAB Law 2's %.2f-%.2f" % [d * PI, D.get("ball.circumference_min", 0.0), D.get("ball.circumference_max", 0.0)])
	var mass := float(K["ball"]["mass"])
	ok(absf(mass - D.get("ball.mass", -1.0)) < 0.001 and mass >= D.get("ball.mass_min", 9.0) and mass <= D.get("ball.mass_max", -9.0), "ball: %.3f kg (doc %.3f, IFAB %.2f-%.2f)" % [mass, D.get("ball.mass", -1.0), D.get("ball.mass_min", 0.0), D.get("ball.mass_max", 0.0)])
	var leaf: Array = K["door"]["solids"][0]
	var ls: Vector3 = leaf[1]
	ok(absf(ls.x - D.get("door.width", -1.0)) < 1e-4 and absf(ls.y - D.get("door.height", -1.0)) < 1e-4 and absf(ls.z - D.get("door.thickness", -1.0)) < 1e-4
		and absf(float(K["door"]["width"]) - ls.x) < 1e-6, "door leaf %.4f x %.4f x %.4f m (doc %.4f x %.4f x %.4f)" % [ls.x, ls.y, ls.z, D.get("door.width", -1.0), D.get("door.height", -1.0), D.get("door.thickness", -1.0)])
	ok(absf((leaf[0] as Vector3).x - ls.x / 2.0) < 1e-9 and absf((leaf[0] as Vector3).y - ls.y / 2.0) < 1e-9, "door: the leaf runs from the hinge (origin) along +X, standing on the floor")
	var mb: Vector3 = K["moving_box"]["solids"][0][1]
	ok(absf(mb.x - D.get("moving_box.length", -1.0)) < 1e-4 and absf(mb.y - D.get("moving_box.height", -1.0)) < 1e-4 and absf(mb.z - D.get("moving_box.width", -1.0)) < 1e-4,
		"moving box %.4f x %.4f x %.4f m (doc U-Haul Small %.4f x %.4f x %.4f)" % [mb.x, mb.z, mb.y, D.get("moving_box.length", -1.0), D.get("moving_box.width", -1.0), D.get("moving_box.height", -1.0)])
	var seat := float(K["chair"]["supports"][0][0])
	ok(absf(seat - D.get("chair.seat_height", -1.0)) < 1e-4 and seat >= D.get("chair.popliteal_min", 9.0) and seat <= D.get("chair.popliteal_max", -9.0), "chair seat %.3f m (doc %.3f, people's popliteal %.3f-%.3f)" % [seat, D.get("chair.seat_height", -1.0), D.get("chair.popliteal_min", 0.0), D.get("chair.popliteal_max", 0.0)])
	ok(absf(float(K["table"]["supports"][0][0]) - D.get("table.top_height", -1.0)) < 1e-4, "table top %.3f m (doc %.3f, marked unverified there)" % [float(K["table"]["supports"][0][0]), D.get("table.top_height", -1.0)])


func door() -> void:
	var hinge := Vector3(0.3, 0.0, 0.35)
	var p := Props.make("door", Props.xf_at(hinge, 0.0))
	Props.key_at(p, 0.0, p["xf"], 0.0)
	Props.key_at(p, 1.0, p["xf"], 90.0)
	var w := float(Props.KINDS["door"]["width"])
	var worst_r := 0.0
	var worst_y := 0.0
	var worst_box := 0.0
	var last := -1.0
	var mono := true
	for f in 61:
		var q := Props.posed(p, f / 60.0)
		var s := float(q["swing"])
		mono = mono and s >= last - 1e-9 and s >= -1e-9 and s <= 90.0 + 1e-9
		last = s
		var e := Props.free_edge(q)
		worst_r = maxf(worst_r, absf(Vector2(e.x - hinge.x, e.z - hinge.z).length() - w))
		worst_y = maxf(worst_y, absf(e.y - 1.016))
		var want := hinge + Vector3(w * cos(deg_to_rad(s)), 1.016, w * sin(deg_to_rad(s)))
		worst_r = maxf(worst_r, e.distance_to(want))
		var sw: Dictionary = Props.solids(q)[0]
		var far: Vector3 = (sw["xf"] as Transform3D) * Vector3((sw["half"] as Vector3).x, 0.0, 0.0)
		worst_box = maxf(worst_box, far.distance_to(e))
	ok(worst_r < MM and worst_y < MM, "door 0 -> 90 deg: the free edge on the hinge's arc, worst %.4f mm off (radius / spot), height %.4f mm" % [worst_r * 1000.0, worst_y * 1000.0])
	ok(mono, "door: the swing climbs 0 -> 90 without going back or past (keys' monotone curve)")
	var e1 := Props.free_edge(Props.posed(p, 1.0))
	var at90 := hinge + Vector3(0.0, 1.016, w)
	ok(e1.distance_to(at90) < MM, "door at 1 s: the free edge %.4f mm from the 90 deg spot" % (e1.distance_to(at90) * 1000.0))
	ok(worst_box < MM, "door: the leaf's collision box swings with it (far edge %.4f mm from the free edge)" % (worst_box * 1000.0))
	# contact: the door shut 0.5 m in front of him (he faces +Z), hinged on his middle line; swung 90 deg toward him
	# (-90: toward -Z) the leaf sweeps through where he stands
	var B := body()
	B.ground()
	var chest: Vector3 = B.P["spine_03"] if B.P.has("spine_03") else B.P["pelvis"]
	var dp := Props.make("door", Props.xf_at(Vector3(chest.x, 0.0, chest.z + 0.5), 0.0))
	Props.key_at(dp, 0.0, dp["xf"], 0.0)
	Props.key_at(dp, 1.0, dp["xf"], -90.0)
	var shut := Rulebook.prop_hits([Props.posed(dp, 0.0)], B)
	var open := Rulebook.prop_hits([Props.posed(dp, 1.0)], B)
	ok(shut.is_empty() and not open.is_empty(), "door: shut it touches nothing (%d), swung 90 deg into the body Check's contact sees %d parts (%s, %.1f cm)" % [shut.size(), open.size(), String(open[0][0]) if not open.is_empty() else "-", float(open[0][2]) * 100.0 if not open.is_empty() else 0.0])
	var DS := Scene.new()   # the same through Check over a played scene (Scene.props_at plays the keys)
	DS.name = "zz_door"
	DS.add("stand", B.to_dict())
	B.offset.x += 0.001
	B.fk()
	DS.add("stand2", B.to_dict())
	DS.props = [dp]
	var thr := Rulebook.check(DS, body()).filter(func(f): return f["rule"] == "THROUGH A PROP")
	DS.props = [Props.make("door", dp["xf"])]
	var thr0 := Rulebook.check(DS, body()).filter(func(f): return f["rule"] == "THROUGH A PROP")
	ok(not thr.is_empty() and thr0.is_empty(), "Check: the keyed door swinging into him is THROUGH A PROP (%d findings, first at %.2f s); the same door unkeyed and shut: %d" % [thr.size(), float(thr[0]["t"]) if not thr.is_empty() else -1.0, thr0.size()])
	var hand: Vector3 = B.P["hand_r"]
	var bl := Props.make("ball", Props.xf_at(hand + Vector3(0.0, -0.1098, 0.08), 0.0))
	var far := Props.make("ball", Props.xf_at(hand + Vector3(0.0, -0.1098, 0.08 + 0.1098 + 0.12), 0.0))
	var hit := Rulebook.prop_hits([bl], B)
	ok(not hit.is_empty() and Rulebook.prop_hits([far], B).is_empty(), "ball: 8 cm from the hand's joint it is in contact (%s, %.1f cm); 23 cm further it is not" % [String(hit[0][0]) if not hit.is_empty() else "-", float(hit[0][2]) * 100.0 if not hit.is_empty() else 0.0])
	var c: Dictionary = Props.solids(bl)[0]
	var cen: Vector3 = (c["xf"] as Transform3D).origin
	var corner := cen + Vector3(0.1, 0.1, 0.1)   # inside the bounding cube, outside the sphere (0.173 > 0.1098)
	ok(Props._sd(c, corner) > 0.05 and absf(Props._sd(c, cen + Vector3(0.1098, 0, 0))) < 1e-6, "ball: a true sphere (a cube corner is %.1f cm outside it)" % (Props._sd(c, corner) * 100.0))


## the carry scene: arms in the carry pose (upper arms down, elbows 90: carry_form_test's reference), a moving box between
## the hands held in the RIGHT hand from card 1; the body walks 40 cm and lifts the forearms; the LEFT hand's Child Of
## targets the box (at 0 s: on for the whole scene)
func carry_scene(B: Body) -> Scene:
	for sd in ["_l", "_r"]:
		B.set_ang("upperarm" + sd, Vector3(0, -80, 0))
		B.set_ang("lowerarm" + sd, Vector3(90, 0, 0))
	B.fk()
	B.ground()
	var hm := ((B.P["hand_l"] as Vector3) + (B.P["hand_r"] as Vector3)) / 2.0
	var box := Props.make("moving_box", Props.xf_at(Vector3(hm.x, hm.y - 0.12, hm.z + 0.06), 0.0))
	var S := Scene.new()
	S.name = "zz_props_generic"
	S.props = [box]
	S.add("take", B.to_dict())
	B.offset.z += 0.4
	for sd in ["_l", "_r"]:
		B.set_ang("lowerarm" + sd, Vector3(110, 0, 0))
	B.fk()
	S.add("walk", B.to_dict())
	B.offset.z += 0.3
	for sd in ["_l", "_r"]:
		B.set_ang("lowerarm" + sd, Vector3(95, 0, 0))
		B.set_ang("upperarm" + sd, Vector3(10, -75, 0))
	B.fk()
	S.add("on", B.to_dict())
	S.cards[0]["take"] = {"prop": 0, "hands": ["_r"]}
	return S


func carry() -> Scene:
	var B := body()
	var S := carry_scene(B)
	var P := body()
	S.apply(P, 0.0)
	var c: Dictionary = Constraints.add_child_of(S, P, "hand_l", {"kind": "prop", "prop": 0}, 0.0)
	ok(not c.is_empty() and (c["wk"] as Array).is_empty(), "Child Of: the left hand on the box (its target the prop), on from 0 s")
	var grip := Scene.hand_frame(P, ["_r"]).affine_inverse() * (S.props_at(0.0, P)[0]["xf"] as Transform3D)
	var half: Vector3 = Props.KINDS["moving_box"]["solids"][0][1] * 0.5
	var corners := []
	for sx in [-1.0, 1.0]:
		for sy in [0.0, 2.0]:
			for sz in [-1.0, 1.0]:
				corners.append(Vector3(half.x * sx, half.y * sy, half.z * sz))
	var worst_grip := 0.0
	var worst_l := 0.0
	var worst_old := 0.0
	var travel := 0.0
	var n := int(S.length() * 30.0) + 1
	var b0: Vector3 = (S.props_at(0.0, P)[0]["xf"] as Transform3D).origin
	for f in n + 3:
		var t := minf(f / 30.0, S.length())
		S.apply(P, t)
		var bx: Transform3D = S.props_at(t, P)[0]["xf"]
		var want := Scene.hand_frame(P, ["_r"]) * grip
		for k in corners:
			worst_grip = maxf(worst_grip, (bx * k).distance_to(want * k))
		var off: Dictionary = c["offset"]
		var C := bx * Transform3D(Basis(off["rot"] as Quaternion), off["pos"])
		worst_l = maxf(worst_l, (P.P["hand_l"] as Vector3).distance_to(C.origin))
		var C_old := (S.props[0]["xf"] as Transform3D) * Transform3D(Basis(off["rot"] as Quaternion), off["pos"])   # before row 22: the stored place
		worst_old = maxf(worst_old, (P.P["hand_l"] as Vector3).distance_to(C_old.origin))
		travel = maxf(travel, bx.origin.distance_to(b0))
	ok(travel > 0.5, "the carried box travels %.2f m over the played scene (%d frames)" % [travel, n])
	ok(worst_grip < MM, "the carried box stays at its grip in the right hand: worst %.4f mm (8 corners, every frame)" % (worst_grip * 1000.0))
	ok(worst_l < MM, "the left hand's Child Of on the carried box follows it: worst %.4f mm (before row 22 the target stayed home: the hand would be %.2f m from where the box puts it)" % [worst_l * 1000.0, worst_old])
	return S


func file_trip(S0: Scene) -> void:
	var B := body()
	var S := S0
	var hinge := Vector3(-0.9, 0.0, 1.2)
	var d := Props.make("door", Props.xf_at(hinge, 20.0))
	Props.key_at(d, 0.0, d["xf"], 0.0)
	Props.key_at(d, 0.8, d["xf"], 60.0)
	Props.key_at(d, 1.4, Props.xf_at(hinge, 20.0), 90.0)
	S.props.append(d)
	var bl := Props.make("ball", Props.xf_at(Vector3(0.6, 0.0, 1.5), 0.0))
	Props.key_at(bl, 0.0, bl["xf"])
	Props.key_at(bl, 1.0, Props.xf_at(Vector3(0.9, 0.0, 2.5), 0.0))
	S.props.append(bl)
	var j1 := JSON.stringify(S.to_dict(B, false))
	var R := Scene.new()
	R.from_dict(JSON.parse_string(j1))
	var j2 := JSON.stringify(R.to_dict(B, false))
	ok(j1 == j2 and j1.contains("\"swing\"") and j1.contains("\"keys\"") and j1.contains("\"take\""), "file: saved, read, saved again = the same JSON (%d bytes; keys, swing, the carry kept)" % j1.length())
	var worst := 0.0
	for f in 31:
		var t := f / 20.0
		worst = maxf(worst, Props.free_edge(Props.posed(S.props[1], t)).distance_to(Props.free_edge(Props.posed(R.props[1], t))))
		worst = maxf(worst, (Props.posed(S.props[2], t)["xf"] as Transform3D).origin.distance_to((Props.posed(R.props[2], t)["xf"] as Transform3D).origin))
	ok(worst < 0.0002, "file: the door and the ball play the same after the trip (worst %.4f mm, the file keeps 0.1 mm)" % (worst * 1000.0))
	var M := body()
	var m1 := Scene.mirror_file(JSON.parse_string(j1), M)
	var m2 := Scene.mirror_file(m1, M)
	ok(JSON.stringify(m2["props"]) == JSON.stringify((JSON.parse_string(j1) as Dictionary)["props"]), "mirror twice: the props are the original")
	var Mi := Scene.new()
	Mi.from_dict(m1)
	var wm := 0.0
	for f in 31:
		var t := f / 20.0
		var e := Props.free_edge(Props.posed(R.props[1], t))
		var em := Props.free_edge(Props.posed(Mi.props[1], t))
		wm = maxf(wm, em.distance_to(Vector3(-e.x, e.y, e.z)))
		var h0: Vector3 = (Props.posed(R.props[1], t)["xf"] as Transform3D).origin
		var hm: Vector3 = (Props.posed(Mi.props[1], t)["xf"] as Transform3D).origin
		wm = maxf(wm, hm.distance_to(Vector3(-h0.x, h0.y, h0.z)))
	ok(wm < MM, "mirror once: the door's hinge and free edge are the reflection at every frame (worst %.4f mm)" % (wm * 1000.0))
	var plain := Props.to_dict(Props.make("chair", Props.xf_at(Vector3(1, 0, 2), 15.0)))
	ok(plain.keys() == ["kind", "pos", "yaw"], "a prop without keys or swing writes only kind, pos, yaw (%s)" % [plain.keys()])


func _init() -> void:
	sizes()
	door()
	var S := carry()
	file_trip(S)
	var dg := old_digest()
	ok(dg == OLD_DIGEST, "old scenes (round-37 props, a carried box tossed) save, mirror and play bit for bit as before row 22 (sha256 %s)" % dg.left(16))
	print("PROPS GENERIC TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
