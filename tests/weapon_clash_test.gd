## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/weapon_clash_test.gd     (ROADMAP 37; headless)
## WEAPON CLASH (scripts/weapon_clash.gd). Two fighters, each holding a free bat, built in memory (no file is written).
## Bat A is along z through (0, y, 0); bat B is along x through (0, y, 0). Their axes cross when their heights are equal,
## and their surfaces touch when the heights are two barrel radii apart. The bats move on the scene's own curve (smooth
## ease); the analytic truth is read from the posed bats' centres (Body.wep_xform), not from the scan. Bars, written first:
##   1 CLASH: A comes down from 1.5 m to 1.01 m, B comes up from 0.5 m to 0.99 m, then both turn back (they never cross).
##     One CLASH. Its time is within one 240 Hz sample (1/240 s) after the analytic first touch, its frame is that frame
##     (+-1), its point is within 1 cm of the midpoint of the two centres at its time, its relative speed is within 10% of
##     the analytic one (the centres' speeds at the first touch).
##   2 PARRY: A comes down onto B, still at 1.0 m. One PARRY; the same time, point and speed bars; the guard is fighter 2.
##   3 PASS-THROUGH: A drops from 1.5 to 0.6 m in 0.02 s, between two frames, straight through still B at 1.0 m. One
##     PASS-THROUGH at the analytic crossing time (within 1 ms), its point within 1 cm of (0, 1, 0), its text says MUST FIX.
##     No frame (30 fps) shows the bats touching: the test's own distance, brute force on a 3 mm grid.
##   4 ONE FIGHTER: a scene with one fighter reports nothing.
extends SceneTree

var fails := 0
const FPS := 30.0
const SAMPLE := 1.0 / 240.0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


## a card's pose: the stand pose with a free bat (not in a hand) along dir, its middle at c
func bat_pose(c: Vector3, dir: Vector3) -> Dictionary:
	var b := body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	var L := b.wep_len
	var d := dir.normalized()
	b.wep_on = true
	b.wep_hand = ""
	b.wep_pos = c - d * L * 0.5
	b.wep_rot = Quaternion(Vector3.UP, d)
	return b.to_dict()


## a fighter whose bat is at height y: cards [[y, move, hold], ...] (the first card's move is ignored). along_z: the bat
## runs along z (else along x), both through (0, y, 0)
func fighter(cards: Array, along_z: bool) -> Scene:
	var cs := []
	var dir := Vector3(0, 0, 1) if along_z else Vector3(1, 0, 0)
	for i in cards.size():
		var card := {"name": "c%d" % i, "pose": bat_pose(Vector3(0, float(cards[i][0]), 0), dir), "hold": float(cards[i][2])}
		card["move"] = -1.0 if i == 0 else float(cards[i][1])
		cs.append(card)
	var s := Scene.new()
	s.from_dict({"scene": "clash_probe", "fps": 30, "cards": cs})
	return s


## the centre of a fighter's bat at t, as posed by its scene
func centre(s: Scene, t: float) -> Vector3:
	var b := body()
	s.apply(b, t)
	var x := b.wep_xform()
	return (x[0] as Vector3) + (x[1] as Quaternion) * Vector3(0, b.wep_len * 0.5, 0)


## the surface gap of the two bats at t: their centres' distance (the axes cross at the centres) minus the two radii
func gap(sa: Scene, sb: Scene, t: float, two_r: float) -> float:
	return centre(sa, t).distance_to(centre(sb, t)) - two_r


## the first instant at which the gap is <= 0: a 1 ms scan, then bisection on the crossing
func first_touch(sa: Scene, sb: Scene, two_r: float, t_end: float) -> float:
	var t := 0.0
	while t <= t_end:
		if gap(sa, sb, t, two_r) <= 0.0:
			var lo := maxf(0.0, t - 0.001)
			var hi := t
			for s in 40:
				var mid := 0.5 * (lo + hi)
				if gap(sa, sb, mid, two_r) <= 0.0:
					hi = mid
				else:
					lo = mid
			return hi
		t += 0.001
	return -1.0


## the analytic relative speed of the two centres at t (a central difference)
func rel_speed(sa: Scene, sb: Scene, t: float) -> float:
	var h := 1e-4
	var va := (centre(sa, t + h) - centre(sa, t - h)) / (2.0 * h)
	var vb := (centre(sb, t + h) - centre(sb, t - h)) / (2.0 * h)
	return (va - vb).length()


func fighters_of(sa: Scene, sb: Scene) -> Array:
	return [{"name": "hero", "S": sa, "xf": Transform3D.IDENTITY}, {"name": "fighter 2", "S": sb, "xf": Transform3D.IDENTITY}]


func kinds(ev: Array) -> String:
	var out := ""
	for e in ev:
		out += String(e["kind"]) + " "
	return out.strip_edges()


func kind_count(ev: Array, kind: String) -> int:
	var n := 0
	for e in ev:
		if e["kind"] == kind:
			n += 1
	return n


## the brute-force distance of the two bats' axes at t (3 mm grid on both axes), minus the two radii
func brute_gap(sa: Scene, sb: Scene, t: float, two_r: float) -> float:
	var ba := body()
	var bb := body()
	sa.apply(ba, t)
	sb.apply(bb, t)
	var a: Dictionary = WeaponClash.named(WeaponClash.weapons(ba, Transform3D.IDENTITY), "weapon")
	var b: Dictionary = WeaponClash.named(WeaponClash.weapons(bb, Transform3D.IDENTITY), "weapon")
	var best := INF
	for i in 281:
		var p: Vector3 = (a["a"] as Vector3).lerp(a["b"], i / 280.0)
		for j in 281:
			var q: Vector3 = (b["a"] as Vector3).lerp(b["b"], j / 280.0)
			best = minf(best, p.distance_to(q))
	return best - two_r


## one contact check against the analytic values at the event's time: the first touch, the point and the speed
func check_contact(name: String, e: Dictionary, sa: Scene, sb: Scene, t_star: float, two_r: float) -> void:
	var t: float = e["t"]
	var p: Vector3 = e["point"]
	var mid := (centre(sa, t) + centre(sb, t)) * 0.5
	var rs := rel_speed(sa, sb, t)   # the speed at the event's own sample (the bats slow down after the touch)
	ok(t - t_star >= -1e-6 and t - t_star <= SAMPLE + 1e-6,
		"%s time %.5f s: %.5f s after the analytic first touch %.5f s (bar: within one 240 Hz sample)" % [name, t, t - t_star, t_star])
	ok(absf(float(e["frame"]) - t_star * FPS) <= 1.0 + 1e-9,
		"%s frame %d (analytic first touch at frame %.2f, bar +-1)" % [name, int(e["frame"]), t_star * FPS])
	ok(p.distance_to(mid) <= 0.01,
		"%s point (%.3f, %.3f, %.3f) m vs the midpoint of the centres (%.3f, %.3f, %.3f) m: %.2f mm (bar 1 cm)" % [name,
		p.x, p.y, p.z, mid.x, mid.y, mid.z, p.distance_to(mid) * 1000.0])
	ok(absf(float(e["rel"]) - rs) <= 0.1 * rs,
		"%s relative speed %.2f m/s vs the analytic %.2f m/s (bar 10%%)" % [name, float(e["rel"]), rs])


func _init() -> void:
	var two_r: float = 2.0 * float(body().rad["bat_barrel"])

	# 1 CLASH: both bats come in and turn back before their axes cross
	var sa := fighter([[1.5, -1.0, 0.1], [1.01, 0.2, 0.0], [1.5, 0.2, 0.0]], true)
	var sb := fighter([[0.5, -1.0, 0.1], [0.99, 0.2, 0.0], [0.5, 0.2, 0.0]], false)
	var ev := WeaponClash.scan(fighters_of(sa, sb), FPS)
	ok(ev.size() == 1 and kind_count(ev, "CLASH") == 1, "1 clash: one event, a CLASH (%d events: %s)" % [ev.size(), kinds(ev)])
	var t1 := first_touch(sa, sb, two_r, 0.6)
	if ev.size() == 1:
		check_contact("1 clash", ev[0], sa, sb, t1, two_r)
		print("     " + String(ev[0]["text"]))

	# 2 PARRY: bat A comes down onto bat B, still at 1.0 m
	var sa2 := fighter([[1.5, -1.0, 0.1], [1.01, 0.2, 0.0]], true)
	var sb2 := fighter([[1.0, -1.0, 0.5]], false)
	var ev2 := WeaponClash.scan(fighters_of(sa2, sb2), FPS)
	ok(ev2.size() == 1 and kind_count(ev2, "PARRY") == 1, "2 parry: one event, a PARRY (%d events: %s)" % [ev2.size(), kinds(ev2)])
	var t2 := first_touch(sa2, sb2, two_r, 0.6)
	if ev2.size() == 1:
		check_contact("2 parry", ev2[0], sa2, sb2, t2, two_r)
		ok(int(ev2[0]["guard"]) == 1 and int(ev2[0]["a"]) == 0, "2 parry: the guard is fighter 2 (%d), the striker the hero" % int(ev2[0]["guard"]))
		print("     " + String(ev2[0]["text"]))

	# 3 PASS-THROUGH: A drops straight through still B between two frames (0.1 s hold, then 0.02 s)
	var sa3 := fighter([[1.5, -1.0, 0.1], [0.6, 0.02, 0.1]], true)
	var sb3 := fighter([[1.0, -1.0, 0.22]], false)
	var ev3 := WeaponClash.scan(fighters_of(sa3, sb3), FPS)
	ok(ev3.size() == 1 and kind_count(ev3, "PASS-THROUGH") == 1,
		"3 pass-through: one event, a PASS-THROUGH (%d events: %s)" % [ev3.size(), kinds(ev3)])
	var lo := 0.1
	var hi := 0.13
	for s in 40:
		var mid := 0.5 * (lo + hi)
		if centre(sa3, mid).y > centre(sb3, mid).y:
			lo = mid
		else:
			hi = mid
	var t_cross := 0.5 * (lo + hi)
	if ev3.size() == 1:
		var e3: Dictionary = ev3[0]
		var p3: Vector3 = e3["point"]
		ok(absf(float(e3["t"]) - t_cross) <= 0.001,
			"3 pass-through at %.5f s; analytic crossing %.5f s (bar 1 ms)" % [float(e3["t"]), t_cross])
		ok(p3.distance_to(Vector3(0, 1.0, 0)) <= 0.01,
			"3 pass-through point (%.3f, %.3f, %.3f) m vs (0, 1, 0) m (bar 1 cm)" % [p3.x, p3.y, p3.z])
		ok(String(e3["text"]).begins_with("PASS-THROUGH") and "MUST FIX" in String(e3["text"]),
			"3 the report says PASS-THROUGH and MUST FIX")
		print("     " + String(e3["text"]))
	var worst := INF
	for f in 8:
		worst = minf(worst, brute_gap(sa3, sb3, f / FPS, two_r))
	ok(worst > 0.0, "3 no frame shows the bats touching (30 fps, brute force 3 mm grid): the closest frame is %.1f mm apart" % (worst * 1000.0))

	# 4 ONE FIGHTER
	var one := WeaponClash.scan([{"name": "hero", "S": sa, "xf": Transform3D.IDENTITY}], FPS)
	ok(one.is_empty(), "4 one fighter: nothing reported (%d)" % one.size())

	print("%s: %d failure(s)" % ["PASS" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
