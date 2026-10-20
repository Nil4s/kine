## godot --path . -s tests/i21_test.gd     (ROADMAP I21: sell the hit, scripts/sell_hit.gd + sell_hit_ui.gd; needs a window)
## The scene: the hero plays combo3's first two strikes (as i18), fighter 2 stands still facing him; the fighter's distance is set (by bisection on
## the strike's measured closest approach) so the first strike misses by an exact amount. The shot camera is built from the strike's own
## geometry (the tip and the nearest point of the target at the closest instant).
## Bars, written before measuring:
##  (1) 15 cm miss, camera at 4 m SIDEWAYS to the miss (axis perpendicular to it): NOT SOLD, with a visible gap > 20 px and a cm figure at the
##      target's depth within 40 % of the true 15 cm (the tip disc is 4.5 cm and the capsule has a radius, so the surface gap is smaller)
##  (2) Move the camera: the fix turns it <= 75 deg; after it the strike is SOLD (overlap >= 3 px) and the 3D miss is unchanged to 0.01 mm;
##      distance to the aim point and the lens are unchanged to 0.1 mm / 0.001 mm
##  (3) 20 cm miss, camera on the line of action (the tip between the camera and the target): SOLD as it is, no fix offered
##  (4) a real contact (the defender stood where the strike lands deepest): UNSAFE with the contact flag; both fixes refuse and say why; the timeline badge is red
##  (5) Offset the aim on the sideways case: the strike is SOLD after it, the 3D miss >= 10 cm (the margin) and the tip moved less than 50 cm (the commanded travel, summed over the rounds)
##  (6) one undo each: Accept adds exactly one step, Ctrl+Z restores the whole scene's JSON exactly; the JSON is byte-identical after the fix is
##      built and after Preview; the camera Accept leaves the cards alone, the aim Accept leaves the shots alone
##  (7) placement: a badge per strike inside the timeline track, the panel rows carry the numbers, and the screenshot is seen through the shot camera
extends SceneTree

const D_OK := 1.1
var fails := 0
var m: Node
var bodies := [DistanceKeeper.new_body(), DistanceKeeper.new_body()]


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


func xf() -> Transform3D:
	return (m.actors_rt[0]["xf"] as Transform3D).affine_inverse() * (m.actors_rt[1]["xf"] as Transform3D)


func miss0(z: float) -> float:
	m.actor_place(1, Vector2(0.0, z), 180.0)
	var A: Scene = m.actors_rt[0]["S"]
	return float(DistanceKeeper.span(A.clone(), bodies[0], (m.actors_rt[1]["S"] as Scene).clone(), bodies[1], xf(), BeatFight.contacts(A)[0], 30)["miss"])


## the defender's distance (z) at which the first strike's closest approach is `want` metres
func place_for(want: float) -> void:
	var lo := 0.5
	var hi := 2.2
	for i in 13:
		var mid := (lo + hi) * 0.5
		if miss0(mid) > want:
			hi = mid
		else:
			lo = mid
	miss0((lo + hi) * 0.5)


func shots_of(pos: Vector3, aim: Vector3) -> Array:
	return [{"t": 0.0, "name": "Shot 1", "keys": [{"t": 0.0, "pos": pos, "aim": aim, "f": 50.0}]}]


## the strike's geometry at its closest instant: {"tip", "q" (nearest point of the target), "t"}
func geom() -> Dictionary:
	var A: Scene = m.actors_rt[0]["S"]
	var D: Scene = m.actors_rt[1]["S"]
	var BA := DistanceKeeper.new_body()
	var BD := DistanceKeeper.new_body()
	var sp := DistanceKeeper.span(A.clone(), BA, D.clone(), BD, xf(), BeatFight.contacts(A)[0], 30)
	var at := SellHit._at(A, D, xf(), {"t": sp["t_min"], "tip": sp["tip"]})
	var best := INF
	var q := Vector3.ZERO
	for c in at["caps"]:
		var ab: Vector3 = (c[2] as Vector3) - (c[1] as Vector3)
		var u := clampf((at["tip"] - (c[1] as Vector3)).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var p: Vector3 = (c[1] as Vector3) + ab * u
		var g: float = (at["tip"] as Vector3).distance_to(p) - float(c[3])
		if g < best:
			best = g
			q = p
	return {"tip": at["tip"], "q": q, "t": sp["t_min"], "gap": best}


func sidecam(g: Dictionary) -> Array:
	var tip: Vector3 = g["tip"]
	var q: Vector3 = g["q"]
	var v := (q - tip).normalized()
	var n := v.cross(Vector3.UP)
	if n.length() < 0.2:
		n = v.cross(Vector3.RIGHT)
	n = n.normalized()
	var mid := (tip + q) * 0.5
	return shots_of(mid + n * 4.0, mid)


func full_json() -> String:
	return JSON.stringify([m.actors_rt[0]["S"].cards, m.actors_rt[1]["S"].cards, m._hero_scene().shots.map(func(s): return var_to_str(s))])


func analyze() -> Dictionary:
	return SellHit.analyze(m.actors_rt[0]["S"], m.actors_rt[1]["S"], xf(), m._hero_scene().shots)


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
	ok(m._fighters_on() and m.actor_on == 0, "two fighters, the hero attacks")
	var ui = m.sh_ui
	var hero: Scene = m._hero_scene()

	# (1) 15 cm miss, camera sideways
	place_for(0.15)
	var g := geom()
	hero.shots = sidecam(g)
	ui.show()
	await idle()
	var rep: Dictionary = ui.rep
	for r in rep["rows"]:
		print("       card %d t %.2f  %s  3D miss %.2f cm  screen gap %.1f px = %.1f cm" % [int(r["card"]) + 1, r["t"], r["cls"], float(r["miss"]) * 100.0, r["gap_px"], r["gap_cm"]])
	var r0: Dictionary = rep["rows"][0]
	ok(absf(float(r0["miss"]) - 0.15) < 0.005 and r0["cls"] == "notsold" and float(r0["gap_px"]) > 20.0 and absf(float(r0["gap_cm"]) / 100.0 - 0.15) < 0.06,
		"(1) 15 cm miss seen from the side: NOT SOLD, 3D %.1f cm, gap %.0f px = %.1f cm at the target's depth" % [float(r0["miss"]) * 100.0, r0["gap_px"], r0["gap_cm"]])
	var j0 := full_json()
	var u0: int = m.undo.size()

	# (2) move the camera
	var cam0: Dictionary = r0["cam"]
	ui.select(0, "camera")
	var fx: Dictionary = ui.fx
	var af: Dictionary = fx.get("after", {})
	var k1: Dictionary = fx["shots"][0]["keys"][0]
	print("       camera turn %.0f deg, after: %s, 3D miss %.4f cm, overlap %.1f px" % [fx["deg"], af["cls"], float(af["miss"]) * 100.0, -float(af["gap_px"])])
	ok(absf(float(fx["deg"])) <= 75.0 and af["cls"] == "sold" and -float(af["gap_px"]) >= 3.0, "(2) turning the camera %.0f deg: SOLD, overlap %.1f px" % [fx["deg"], -float(af["gap_px"])])
	ok(absf(float(af["miss"]) - float(r0["miss"])) < 1e-5 and absf(((k1["pos"] as Vector3) - (k1["aim"] as Vector3)).length() - (cam0["pos"] as Vector3).distance_to(cam0["aim"])) < 1e-4
		and (k1["aim"] as Vector3).is_equal_approx(cam0["aim"]) and absf(float(k1["f"]) - float(cam0["f"])) < 1e-6,
		"(2) the 3D miss is unchanged (%.5f vs %.5f cm), the distance to the aim point, the aim and the lens are kept" % [float(af["miss"]) * 100.0, float(r0["miss"]) * 100.0])
	ok(full_json() == j0, "(6) the JSON is byte-identical after the fix is built")
	ui.preview()
	var ticks := 0
	while ui.pv and ticks < 900:
		await process_frame
		ticks += 1
	ok(not ui.pv and ticks > 5 and full_json() == j0, "(6) Preview played %d frames and the scene is byte-identical" % ticks)
	var cards_before := JSON.stringify(m.actors_rt[0]["S"].cards)
	ui.accept()
	await idle()
	var rep2 := analyze()
	ok(m.undo.size() == u0 + 1 and rep2["rows"][0]["cls"] == "sold" and JSON.stringify(m.actors_rt[0]["S"].cards) == cards_before and absf(float(rep2["rows"][0]["miss"]) - float(r0["miss"])) < 1e-5,
		"(6) Accept (camera) is one undo step (%d -> %d), the cards untouched, the strike SOLD with the same 3D miss" % [u0, m.undo.size()])
	# (7) the screenshot: seen through the shot camera, a SOLD strike
	var tl = m.ui_timeline
	await idle(4)
	var inside := true
	for b in tl.sh:
		var x0: float = tl.x_of(float(b["t0"]))
		var x1: float = tl.x_of(float(b["t1"]))
		inside = inside and x0 >= 0.0 and x1 <= tl.size.x and x1 > x0
	var nrows := 0
	for c in m.ui_find_list.get_children():
		if c is HBoxContainer and c.get_child_count() > 0 and c.get_child(0) is Label and String((c.get_child(0) as Label).text).begins_with("card "):
			nrows += 1
	ok(tl.sh.size() == rep2["rows"].size() and inside and nrows == rep2["rows"].size() and m.ui_find.visible, "(7) the timeline holds %d badges inside the track, the panel %d numbered rows" % [tl.sh.size(), nrows])
	m.playhead = float(rep2["rows"][0]["t"])
	m._ps().apply(m.B, m.playhead)
	m.shot_through = true
	m._shot_apply()
	m._refresh()
	await idle(5)
	m._shot_apply()
	await idle(3)
	root.get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i21.png")
	var pr: Vector2 = SellHit.screen(rep2["rows"][0]["cam"], geom()["tip"], 0.045, SellHit._at(m.actors_rt[0]["S"], m.actors_rt[1]["S"], xf(), rep2["rows"][0])["caps"])["tip2"]
	print("       the tip is at pixel (%.0f, %.0f) of the 1280x720 shot frame" % [pr.x, pr.y])
	m._shot_off()
	m._undo()
	await idle()
	m._actors_sync()
	ok(full_json() == j0 and m.undo.size() == u0, "(6) Ctrl+Z (camera): the cards and the shots are exact")

	# (5) offset the aim, same scene
	ui.show()
	await idle()
	ui.select(0, "aim")
	fx = ui.fx
	af = fx.get("after", {})
	print("       aim: moved %.1f cm, after: %s, 3D miss %.2f cm, overlap %.1f px" % [float(fx.get("move", 0.0)) * 100.0, af.get("cls", "-"), float(af.get("miss", 0.0)) * 100.0, -float(af.get("gap_px", 0.0))])
	ok(fx.get("ok", false) and af["cls"] == "sold" and float(af["miss"]) >= SellHit.SAFE and float(fx["move"]) < 0.5,
		"(5) offsetting the aim %.0f cm: SOLD with the 3D miss %.1f cm (margin 10)" % [float(fx.get("move", 0.0)) * 100.0, float(af.get("miss", 0.0)) * 100.0])
	ok(full_json() == j0, "(6) the JSON is byte-identical after the aim fix is built")
	var shots_before := JSON.stringify(hero.shots.map(func(s): return var_to_str(s)))
	ui.accept()
	await idle()
	var rep3 := analyze()
	ok(m.undo.size() == u0 + 1 and rep3["rows"][0]["cls"] == "sold" and JSON.stringify(hero.shots.map(func(s): return var_to_str(s))) == shots_before and JSON.stringify(m.actors_rt[0]["S"].cards) != cards_before,
		"(6) Accept (aim) is one undo step, the shots untouched, the cards changed, the strike SOLD")
	m._undo()
	await idle()
	m._actors_sync()
	ok(full_json() == j0 and m.undo.size() == u0, "(6) Ctrl+Z (aim): the cards and the shots are exact")

	# (3) 20 cm miss straight along the camera axis
	place_for(0.20)
	g = geom()
	var tip: Vector3 = g["tip"]
	hero.shots = shots_of(tip + (tip - (g["q"] as Vector3)).normalized() * 4.0, g["q"])
	ui.show()
	await idle()
	var r3: Dictionary = ui.rep["rows"][0]
	var u1: int = m.undo.size()
	ui.select(0, "camera")
	ok(absf(float(r3["miss"]) - 0.20) < 0.005 and r3["cls"] == "sold" and ui.fx.is_empty() and m.undo.size() == u1,
		"(3) 20 cm miss along the camera axis: SOLD as it is (3D %.1f cm, overlap %.0f px), no fix offered" % [float(r3["miss"]) * 100.0, -float(r3["gap_px"])])

	# (4) a real contact
	var zb := 1.1
	var mb := INF
	for zi in 40:
		var zz := 0.7 + 0.02 * zi
		var mm := miss0(zz)
		if mm < mb:
			mb = mm
			zb = zz
	miss0(zb)
	print("       deepest approach of strike 1: %.1f cm at z = %.2f" % [mb * 100.0, zb])
	g = geom()
	hero.shots = sidecam(g)
	ui.show()
	await idle()
	var r4: Dictionary = ui.rep["rows"][0]
	ui.select(0, "camera")
	var w1: bool = ui.fx.is_empty()
	ui.select(0, "aim")
	var red := false
	for b in tl.sh:
		red = red or b["cls"] == "unsafe"
	ok(r4["cls"] == "unsafe" and r4["contact"] and w1 and ui.fx.is_empty() and red and not full_json().is_empty(),
		"(4) a contact (3D %.1f cm): UNSAFE with the contact flag, both fixes refuse, the badge is red" % [float(r4["miss"]) * 100.0])

	print("I21 SELL THE HIT %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	quit(1 if fails > 0 else 0)
