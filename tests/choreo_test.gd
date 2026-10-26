## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/choreo_test.gd     (ROADMAP 13; a window: the view is shown)
## CHOREOGRAPHY FOR 2+ FIGHTERS (scripts/choreo.gd, scripts/choreo_view.gd). Two fighters as in actors_hit_test: the hero plays
## combo3 (read only), fighter 2 stands still D0 in front of him. Bars, written before measuring:
##   1 REACH: at the strike (the first weapon contact of a 1/240 s sweep) and 0.3 s before it, the beat's reach gap equals the
##     tip-to-body distance measured here by this test's own point-to-segment formula, within 1 mm. The words say "hits" when
##     the tip is in, "out of range by" when it is out.
##   2 SHIFT: the hero's timeline shifted by 0.2 s (Choreo.shift): its length grows by 0.2 s, and every pose at t + 0.2 is the
##     original pose at t (every joint, the hips' offset: within 1e-6 deg / m) at 30 samples. A cut of -0.2 s: the length
##     shrinks by 0.2 s (its poses are reported, not barred: a cut inside a move is an approximation).
##   3 GUARD: a forearm put ON the bat's striking spot (the bat's point nearest fighter 2's body, 0.05 s before the contact):
##     the report says "between" with the part, and parry lands exactly when this test's own measure says the guard meets the
##     bat (within the two radii); with the still fighter the report says "no guard between".
##   4 FILE: "beats" is written only when there are any; it loads back equal; a clone and a mirror keep them.
##   5 VIEW: the exchange window opens, one report line per beat, and its picture is saved (CHOREO_PNG, or the default below).
extends SceneTree

var fails := 0
var m: Node
const D0 := 1.2
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/choreo.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func still(pose: Dictionary) -> Scene:
	var s := Scene.new()
	s.from_dict({"scene": "zz_still", "fps": 30, "cards": [{"name": "a", "pose": pose, "move": -1.0, "hold": 2.0},
		{"name": "b", "pose": pose, "move": 0.5, "hold": 3.0}]})
	return s


func stand_pose() -> Dictionary:
	var b := body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b.to_dict()


## the test's own distance from point p to segment ab
func seg_pt(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l := ab.length_squared()
	var t := 0.0
	if l > 1e-12:
		t = clampf((p - a).dot(ab) / l, 0.0, 1.0)
	return (a + ab * t - p).length()


## the parts a fighter can be hit on: every capsule but the fingers and the weapons
func parts_of(B: Body) -> Array:
	var out := []
	for p in B.cross_parts():
		if not Body.is_wep(p) and not (p in Body.FINGERS):
			out.append(p)
	return out


## the tip-to-body gap by this test's formula: min over the target's parts of (distance to the axis - radius)
func gap_of(tip: Vector3, T: Body, xf: Transform3D) -> float:
	var g := INF
	for p in parts_of(T):
		var c: Array = T.cap(p)
		g = minf(g, seg_pt(tip, xf * (c[0] as Vector3), xf * (c[1] as Vector3)) - float(T.rad[p]))
	return g


## the first weapon contact of the hero against fighter 2 (1/240 s sweep, the first row of kind "hit")
func strike_t(hs: Scene, fs: Scene, xf: Transform3D) -> float:
	var a := hs.clone()
	var o := fs.clone()
	var ba := body()
	var bo := body()
	var n := int(ceil(maxf(a.length(), o.length()) * 240.0))
	for i in n + 1:
		var t := i / 240.0
		a.apply(ba, t)
		o.apply(bo, t)
		for c in ba.cross_contacts(bo, xf):
			if c[3] == "hit":
				return t
	return -1.0


func fighters_now() -> Array:
	var out := []
	for k in m.actors_rt.size():
		out.append({"name": "hero" if k == 0 else String(m.actors_rt[k]["name"]), "S": m.actors_rt[k]["S"], "xf": m.actors_rt[k]["xf"]})
	return out


## the largest difference between two pose values (numbers, vectors, arrays, dictionaries), in the values' units
func maxdev(a, b) -> float:
	if a is Dictionary and b is Dictionary:
		var d := 0.0
		for k in a:
			if not b.has(k):
				return INF
			d = maxf(d, maxdev(a[k], b[k]))
		return d
	if a is Array and b is Array:
		if a.size() != b.size():
			return INF
		var d2 := 0.0
		for i in a.size():
			d2 = maxf(d2, maxdev(a[i], b[i]))
		return d2
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b))
	if a is Vector3 and b is Vector3:
		return (a as Vector3).distance_to(b)
	if a is String and b is String:
		return 0.0 if a == b else INF
	return 0.0 if var_to_str(a) == var_to_str(b) else INF


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._load_scene("res://scenes/combo3.json")   # read only
	m._rebuild_cards()
	await idle()
	var stand := stand_pose()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, D0], "yaw": 180.0}, "scene": still(stand)})
	m._actors_sync()
	m._refresh()
	await idle()
	ok(m.actors_rt.size() == 2, "two fighters: the hero and fighter 2 (%d)" % m.actors_rt.size())
	var hs: Scene = m.actors_rt[0]["S"]
	var fs: Scene = m.actors_rt[1]["S"]
	var xf2: Transform3D = m.actors_rt[1]["xf"]
	var t_hit := strike_t(hs, fs, xf2)
	ok(t_hit > 0.0, "the strike: the hero's bat first meets fighter 2 at %.4f s (the sweep)" % t_hit)

	# 1 REACH
	for tb in [t_hit, t_hit - 0.3]:
		var bb := body()
		hs.apply(bb, tb)
		var fb := body()
		fs.apply(fb, tb)
		var tp: Vector3 = bb.wep_point(bb.wep_len) if bb.wep_on else bb.palm_point("hand_r")
		var want := gap_of(tp, fb, xf2)
		var beat := {"t": tb, "name": "hero attacks fighter 2", "by": 0, "on": 1}
		var r: Dictionary = Choreo.report(fighters_now(), [beat])[0]
		var gap: float = r["gap"]
		var words_ok: bool = (("out of range by" in r["text"]) == (want > 0.0)) and (("hits" in r["text"]) == (want <= 0.0))
		ok(absf(gap - want) <= 0.001 and words_ok,
			"1 reach at %.4f s (%s, %s): the beat says %+.1f mm, the measured tip-to-body gap %+.1f mm (bar 1 mm); '%s'" % [
			tb, "the strike" if tb == t_hit else "0.3 s before", r["what"], gap * 1000.0, want * 1000.0, r["text"]])

	# 2 SHIFT (the hero's timeline, a moving scene)
	var S0 := hs.clone()
	var S1 := hs.clone()
	var got := Choreo.shift(S1, 0.2)
	ok(absf(got - 0.2) < 1e-9 and absf(S1.length() - S0.length() - 0.2) < 1e-6,
		"2 shift +0.2 s: applied %.3f s, the length %.4f -> %.4f s" % [got, S0.length(), S1.length()])
	var worst := 0.0
	for i in 31:
		var t := S0.length() * float(i) / 30.0
		worst = maxf(worst, maxdev(Choreo.pose_at(S0, t), Choreo.pose_at(S1, t + 0.2)))
	ok(worst <= 1e-6, "2 shifted by 0.2 s: every pose at t + 0.2 is the original at t, 31 samples, worst difference %.9f (bar 1e-6)" % worst)
	var S2 := hs.clone()
	var cut := Choreo.shift(S2, -0.2)
	var worst_cut := 0.0
	for i in 16:
		var t2 := 0.2 + (S0.length() - 0.2) * float(i) / 15.0
		worst_cut = maxf(worst_cut, maxdev(Choreo.pose_at(S0, t2), Choreo.pose_at(S2, t2 - 0.2)))
	ok(absf(cut + 0.2) < 1e-9 and absf(S2.length() - (S0.length() - 0.2)) < 1e-6 and worst_cut <= 1e-6,
		"2 cut -0.2 s: the length %.4f -> %.4f s; the poses after it differ by at most %.9f (bar 1e-6: exact inside a hold)" % [S0.length(), S2.length(), worst_cut])

	# 3 GUARD: the forearm is put ON the bat's striking spot (the bat's point nearest fighter 2's body) a moment before the
	# contact: the first of a few moments at which the arm reaches that spot within 30 mm (the test's own search)
	var tg := t_hit
	var P := Vector3.ZERO
	var C := Vector3.ZERO
	var side := "_r"
	var miss := INF
	var tgt := Vector3.ZERO
	var stand_b := body()
	stand_b.from_dict(stand)
	for dtg in [0.02, 0.03, 0.015, 0.04, 0.01, 0.05]:
		tg = t_hit - dtg
		var bg := body()
		hs.apply(bg, tg)
		var fb_still := body()
		fs.apply(fb_still, tg)
		P = Vector3.ZERO
		var bestg := INF
		var u := 0.0
		while u <= bg.wep_len + 1e-6:
			var q := bg.wep_point(u)
			var gq := gap_of(q, fb_still, xf2)
			if gq < bestg:
				bestg = gq
				P = q
			u += 0.005
		C = P
		var bc := INF
		for p in parts_of(fb_still):
			var c: Array = fb_still.cap(p)
			var a: Vector3 = xf2 * (c[0] as Vector3)
			var b: Vector3 = xf2 * (c[1] as Vector3)
			for k in 41:
				var pt := a.lerp(b, k / 40.0)
				var dd := pt.distance_to(P) - float(fb_still.rad[p])
				if dd < bc:
					bc = dd
					C = pt
		tgt = xf2.affine_inverse() * P
		side = "_l" if (fb_still.P["upperarm_l"] as Vector3).distance_to(tgt) < (fb_still.P["upperarm_r"] as Vector3).distance_to(tgt) else "_r"
		var arm := body()
		arm.from_dict(stand)
		miss = arm.reach("hand" + side, tgt)
		if miss < 0.03:
			break
	var arm2 := body()
	arm2.from_dict(stand)
	arm2.reach("hand" + side, tgt)
	var block := arm2.to_dict()
	var bg_final := body()
	hs.apply(bg_final, tg)
	var fb2 := body()
	still(block).apply(fb2, tg)
	m.S.actors[0]["scene"] = still(block)
	m._actors_build(m.actors_rt[0]["B"], hs)
	var guard_beat := {"t": tg, "name": "hero attacks fighter 2", "by": 0, "on": 1}
	var rg: Dictionary = Choreo.report(fighters_now(), [guard_beat])[0]
	# this test's own between / meet: the guard's sampled axis against the bat's striking segment, the radii taken off
	var seg_a := P
	var seg_b := C
	var between_t := false
	var meet_t := false
	for gp in ["lowerarm" + side, "hand" + side]:
		var gc: Array = fb2.cap(gp)
		var ga: Vector3 = xf2 * (gc[0] as Vector3)
		var gb: Vector3 = xf2 * (gc[1] as Vector3)
		var gr := float(fb2.rad[gp])
		for k in 41:
			var gpt := ga.lerp(gb, k / 40.0)
			if seg_pt(gpt, seg_a, seg_b) - gr <= 0.0:
				between_t = true
			for j in 41:
				var bpt := bg_final.wep_point(bg_final.wep_len * j / 40.0)
				if seg_pt(bpt, gpt, gpt) - gr - float(bg_final.rad["bat_barrel"]) <= 0.0:
					meet_t = true
	ok(rg["between"] == between_t and rg["parry"] == meet_t,
		"3 the guard (hand%s, reach miss %.1f mm) between the bat and fighter 2: the report says between %s, parry %s; this test %s, %s (bar: equal)" % [
		side, miss * 1000.0, rg["between"], rg["parry"], between_t, meet_t])
	ok(bool(rg["between"]) and (("parry lands" in rg["text"]) == bool(rg["parry"])), "3 the words: '%s'" % rg["text"])
	m.S.actors[0]["scene"] = still(stand)
	m._actors_build(m.actors_rt[0]["B"], hs)
	var rs: Dictionary = Choreo.report(fighters_now(), [guard_beat])[0]
	ok(not rs["between"] and "no guard between" in rs["text"], "3 the still fighter: no guard between ('%s')" % rs["text"])

	# 4 FILE
	hs.beats = []
	var bb0 := body()
	ok(not hs.to_dict(bb0).has("beats"), "4 no beats: the file has no 'beats' key")
	hs.beats = Choreo.from_list([{"t": t_hit, "name": "hero attacks fighter 2", "by": 0, "on": 1},
		{"t": tg, "name": "fighter 2 parries", "by": 1, "on": 0}])
	var d: Dictionary = hs.to_dict(bb0)
	var back := Scene.new()
	back.from_dict(d)
	ok(d.has("beats") and JSON.stringify(back.beats) == JSON.stringify(Choreo.from_list(d["beats"])) and back.beats.size() == 2,
		"4 the file holds 2 beats and loads back equal (%s)" % [d.get("beats")])
	var cl := hs.clone()
	var mir := Scene.mirror_file(d, body())
	ok(JSON.stringify(cl.beats) == JSON.stringify(hs.beats) and JSON.stringify(mir.get("beats")) == JSON.stringify(d["beats"]),
		"4 a clone and a mirror keep the beats")

	# 5 VIEW: beats through the app's own functions (undo steps), the window, its picture
	hs.beats = []
	m._choreo_beat_add(t_hit, 0, 1, "hero attacks fighter 2")
	m._choreo_beat_add(tg, 1, 0, "fighter 2 parries hero")
	m._choreo_open()
	await idle(3)
	var v = m.ui_choreo
	ok(v != null and is_instance_valid(v.win) and v.report.size() == 2 and v.report[0]["text"] != "",
		"5 the exchange window: a row per fighter (%d) and one report line per beat (%d)" % [m.actors_rt.size(), v.report.size() if v != null else -1])
	var before: float = m.actors_rt[1]["S"].length()
	m._choreo_shift(1, 0.2)
	ok(absf(float(m.actors_rt[1]["S"].length()) - before - 0.2) < 1e-6 and m.undo.size() > 0 and m._hero_scene().beats.size() == 2,
		"5 the view's shift (fighter 2 by 0.2 s): its length %.3f -> %.3f s, one undo step" % [before, m.actors_rt[1]["S"].length()])
	await idle(2)
	var shot: String = OS.get_environment("CHOREO_PNG") if OS.get_environment("CHOREO_PNG") != "" else SHOT
	DirAccess.make_dir_recursive_absolute(shot.get_base_dir())
	await RenderingServer.frame_post_draw
	var img: Image = v.win.get_texture().get_image()
	var saved := img.save_png(shot)
	ok(saved == OK and FileAccess.file_exists(shot), "5 the exchange view's picture saved: %s" % shot)
	for line in v.report:
		print("     %.2f s  %s" % [float(line["t"]), line["text"]])

	print("CHOREO: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
