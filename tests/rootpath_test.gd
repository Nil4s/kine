## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/rootpath_test.gd     (needs a window: the screenshot and the UI; ROADMAP 91, scripts/root_path.gd)
## Bars, written before measuring:
##   THE SCENE: a standing body whose LEFT foot is planted ahead (ball at z = 0.35 m, the leg solved onto it), the right foot
##     back. Cards 0 (anchor, no plant), 1 and 2 (plant "_l", the left foot held where card 0 put it), 3 (no plant).
##     The planted front foot is what makes a 50 cm move reachable: a standing body with both feet held cannot move its pelvis
##     25 cm (the knee clamps at its limit, the ball misses by 28 cm; measured with the probe, see the report).
##   1 DRAG 50 CM: card index 2 (the spec's card 3) moved 50 cm on the floor: its pelvis moves 50 cm, +-1 mm, along the drag.
##   2 OTHER ROOTS: the roots of cards 0, 1 and 3 are unchanged, < 0.1 mm (card 3 is planted: it is pinned, not moved).
##   3 PLANTED FEET: the held foot's ball stays within 5 mm (horizontal) of its anchor on EVERY frame at 120 Hz over the
##     planted range (the move into card 1 to the end of card 3's hold, card 3 planted too so no release falls inside it),
##     after the drag.
##   4 HEADING: the facing turned by 25 deg: the heading moves 25 deg +-0.5 deg, the root stays (< 0.1 mm).
##   5 EXPORT: the glTF root bone (root_motion on, GltfExport) equals the played path's travel since frame 0 at 5 frames,
##     +-1 mm (the root bone is the pelvis's horizontal travel: the path, read back from the exported animation).
##   6 STRAIGHTEN: the interior roots of a curved 4-card path lie on the chord between the ends (< 0.1 mm off it); the
##     ends stay where they were; the cards keep their place along the chord (to 1 mm).
##   7 SCALE LENGTH: scale 2.0: every root's distance from card 0's root doubles (+-0.1 mm), direction unchanged.
##   8 PLACEMENT: each card's handle is on the floor (y = FLOOR) directly under its pelvis (< 1 mm), the pelvis 0.5 m+ up.
##   9 READ ONLY: reading the roots and sampling the path change no card (the cards' poses are the same before and after).
##  11 UI: the real main window (tests/foot_handles_test style: pushed mouse events): a press on card 3's root handle
##     takes it, a 45 px drag moves the root by the floor delta (1 mm), the other roots stay, one undo step, a bare press leaves none.
##  10 SCREENSHOT: the path on the floor with its handles, whole body, saved to tmp/rootmotion.png (read and described in
##     the report). Placement is the bar: the handles sit under the pelvis (8), the path runs through them.
extends SceneTree

const STANCE := {"thigh_l": Vector3(-6, 0, 0), "calf_l": Vector3(38, 0, 0), "foot_l": Vector3(25, 0, 0), "thigh_r": Vector3(-6, 0, 0), "calf_r": Vector3(38, 0, 0), "foot_r": Vector3(25, 0, 0)}
const ZF := 0.35        # m: the planted front foot's ball, ahead of the start
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/rootmotion.png"
const HZ := 120.0

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func pose_of(B: Body, angs: Dictionary, off: Vector3) -> Dictionary:
	for j in Body.ORDER:
		B.ang[j] = Vector3.ZERO
	B.offset = off
	B.wep_on = false
	for j in angs:
		B.ang[j] = B.clamp_ang(j, angs[j])
	B.fk()
	return B.to_dict()


## card 0's pose: the stance with the left ball planted ZF ahead (the leg solved onto it), grounded as the scene grounds it
func stance_pose(B: Body) -> Dictionary:
	B.from_dict(pose_of(B, STANCE, Vector3.ZERO))
	var b0: Vector3 = B.P["ball_l"]
	B.plant("_l", Vector3(b0.x, b0.y, ZF), 0.0, true)
	B.apply_grip()
	return B.to_dict()


func scene(p0: Dictionary) -> Scene:
	var S := Scene.new()
	S.fps = 30
	S.pin = false
	S.on_floor = true
	for k in 4:
		S.add("card%d" % k, p0.duplicate(true))
	S.cards[0]["move"] = 0.0
	S.cards[0]["hold"] = 0.4
	for k in [1, 2, 3]:
		S.cards[k]["move"] = 1.0
		S.cards[k]["hold"] = 0.5
	S.cards[1]["plant"] = ["_l"]
	S.cards[2]["plant"] = ["_l"]
	S.cards[3]["plant"] = ["_l"]
	return S


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	run()


func run() -> void:
	var W := body()
	var p0 := stance_pose(W)
	var S := scene(p0)
	var rs0 := RootPath.roots(S)
	var before := var_to_str(S.cards)

	# 9 READ ONLY
	RootPath.played(S)
	RootPath.handles(RootPath.roots(S))
	ok(var_to_str(S.cards) == before, "9 read only: reading the roots and the played path changes no card")

	# the anchor: card 0's left ball, grounded as the scene plays it
	var wb := body()
	wb.from_dict(S.cards[0]["pose"])
	S._ground(wb)
	var anchor: Vector3 = wb.P["ball_l"]

	# 1 DRAG 50 CM on card index 2 (the spec's card 3)
	var k := 2
	var r_before := RootPath.root_of(W, S.cards[k]["pose"])
	var xz_want: Vector2 = (r_before["xz"] as Vector2) + Vector2(0.0, 0.5)
	S.cards[k]["pose"] = RootPath.posed(W, S.cards[k]["pose"], xz_want, float(r_before["heading"]))
	var r_after := RootPath.root_of(W, S.cards[k]["pose"])
	var moved: Vector2 = (r_after["xz"] as Vector2) - (r_before["xz"] as Vector2)
	var err1 := (moved - Vector2(0.0, 0.5)).length()
	ok(err1 <= 0.001, "1 drag 50 cm: card 3's pelvis moved %.4f m on the floor (%.4f, %.4f), error %.2f mm (bar 1 mm)" % [moved.length(), moved.x, moved.y, err1 * 1000.0])

	# 2 OTHER ROOTS
	var rs1 := RootPath.roots(S)
	var worst := 0.0
	for i in [0, 1, 3]:
		worst = maxf(worst, ((rs1[i]["xz"] as Vector2) - (rs0[i]["xz"] as Vector2)).length())
	ok(worst < 0.0001, "2 other roots: cards 0, 1, 3 unchanged, worst %.6f mm (bar 0.1 mm)" % (worst * 1000.0))

	# 3 PLANTED FEET: the held ball within 5 mm of its anchor, every frame at 120 Hz over the planted range
	var ts: Array = S.times()
	var t_a: float = float(ts[1][0])
	var t_b: float = float(ts[3][2]) - 0.001
	var slide := 0.0
	var n := int(S.length() * HZ)
	for f in n + 1:
		var t := float(f) / HZ
		if t < t_a or t > t_b:
			continue
		S.apply(W, t)
		var d: Vector3 = W.P["ball_l"] - anchor
		slide = maxf(slide, Vector2(d.x, d.z).length())
	ok(slide < 0.005, "3 planted feet: the held ball's worst horizontal slide %.2f mm over %.2f s (bar 5 mm)" % [slide * 1000.0, t_b - t_a])

	# 4 HEADING: 25 deg
	var r2 := RootPath.root_of(W, S.cards[k]["pose"])
	S.cards[k]["pose"] = RootPath.posed(W, S.cards[k]["pose"], r2["xz"], float(r2["heading"]) + 25.0)
	var r3 := RootPath.root_of(W, S.cards[k]["pose"])
	var dh := wrapf(float(r3["heading"]) - float(r2["heading"]), -180.0, 180.0)
	var dxz := ((r3["xz"] as Vector2) - (r2["xz"] as Vector2)).length()
	ok(absf(dh - 25.0) <= 0.5 and dxz < 0.0001, "4 heading: the facing turned %.3f deg (bar 25 +-0.5), the root moved %.6f mm" % [dh, dxz * 1000.0])

	# 5 EXPORT: the glTF root bone against the played path
	var E := body()
	var expn := GltfExport.build(S, E, "rootpath", false, true)
	var ap: AnimationPlayer = expn.find_children("*", "AnimationPlayer", true, false)[0]
	var anim: Animation = ap.get_animation(ap.get_animation_list()[0])
	var rti := -1
	for i in anim.get_track_count():
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D and String(anim.track_get_path(i)).ends_with(":root"):
			rti = i
	var export_err := -1.0
	var export_ok := rti >= 0
	if export_ok:
		var P0 := Vector2.ZERO
		S.apply(W, 0.0)
		P0 = Vector2(W.P["pelvis"].x, W.P["pelvis"].z)
		for fr in [10, 40, 75, 100, 140]:
			var tt := float(fr) / 30.0
			S.apply(W, tt)
			var pz := Vector2(W.P["pelvis"].x, W.P["pelvis"].z) - P0
			var v: Vector3 = anim.position_track_interpolate(rti, tt)
			var e := (Vector2(v.x, v.z) - pz).length()
			export_err = maxf(export_err, e)
	ok(export_ok and export_err < 0.001, "5 export: root bone track found %s, worst error vs the path at 5 frames %.3f mm (bar 1 mm)" % [str(export_ok), export_err * 1000.0])
	expn.free()

	# 6 STRAIGHTEN and 7 SCALE on a curved 4-card path
	var C := scene(p0)
	var targets := [Vector2(0, 0), Vector2(0.2, 0.3), Vector2(0.5, 0.05), Vector2(1.0, 0.5)]
	for i in 4:
		var hh := float(RootPath.root_of(W, C.cards[i]["pose"])["heading"])
		C.cards[i]["pose"] = RootPath.posed(W, C.cards[i]["pose"], targets[i], hh)
	var a: Vector2 = targets[0]
	var bb: Vector2 = targets[3]
	var ab: Vector2 = bb - a
	var offchord := 0.0
	var along0: float = (targets[1] - a).dot(ab) / ab.length_squared()
	var nmoved := RootPath.straighten(C)
	var rs := RootPath.roots(C)
	for i in [1, 2]:
		var x: Vector2 = rs[i]["xz"]
		var cross: float = absf((x - a).x * ab.y - (x - a).y * ab.x) / ab.length()
		offchord = maxf(offchord, cross)
	var ends_ok: bool = ((rs[0]["xz"] as Vector2) - a).length() < 1e-4 and ((rs[3]["xz"] as Vector2) - bb).length() < 1e-4
	var along1: float = ((rs[1]["xz"] as Vector2) - a).dot(ab) / ab.length_squared()
	ok(nmoved == 2 and offchord < 0.0001 and ends_ok and absf(along1 - along0) < 0.001, "6 straighten: %d cards moved, interior off the chord by %.4f mm (bar 0.1 mm), ends kept %s, card 1 along %.3f (was %.3f)" % [nmoved, offchord * 1000.0, str(ends_ok), along1, along0])

	var d0 := []
	for i in 4:
		d0.append(((rs[i]["xz"] as Vector2) - (rs[0]["xz"] as Vector2)))
	var n2 := RootPath.scale_length(C, 2.0)
	var rs2 := RootPath.roots(C)
	var sc_err := 0.0
	for i in range(1, 4):
		var dd: Vector2 = (rs2[i]["xz"] as Vector2) - (rs2[0]["xz"] as Vector2)
		sc_err = maxf(sc_err, absf(dd.length() - 2.0 * (d0[i] as Vector2).length()))
		sc_err = maxf(sc_err, (dd - 2.0 * (d0[i] as Vector2)).length())
	ok(n2 == 3 and sc_err < 0.0001, "7 scale 2.0: %d cards moved, worst error %.4f mm (bar 0.1 mm)" % [n2, sc_err * 1000.0])

	# 8 PLACEMENT: each handle on the floor under its pelvis
	var hs := RootPath.handles(RootPath.roots(S))
	var place_err := 0.0
	var pelvis_h := 1e9
	for h in hs:
		var rr := RootPath.root_of(W, S.cards[int(h["card"])]["pose"])
		var hp: Vector3 = h["root"]
		place_err = maxf(place_err, Vector2(hp.x - (rr["p"] as Vector3).x, hp.z - (rr["p"] as Vector3).z).length())
		pelvis_h = minf(pelvis_h, (rr["p"] as Vector3).y)
	ok(place_err < 0.001 and pelvis_h > 0.5, "8 placement: every handle under its pelvis, worst %.4f mm off; lowest pelvis %.3f m up (bar 1 mm, > 0.5 m)" % [place_err * 1000.0, pelvis_h])

	# 10 SCREENSHOT: the path on the floor with its handles, the whole body at card index 2
	var sh_ok := await shot(S, W)
	ok(sh_ok, "10 screenshot: saved to %s (read it: the path, the handles, the body)" % SHOT)

	# 11 THE UI: the real main window, real pushed mouse events on a root handle (the view toggle on)
	await ui_section()
	print("%s  (%d fails)" % ["PASS" if fails == 0 else "FAILED", fails])
	quit(fails)


func mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func move(p: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func ui_section() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	# the lunge scene (the bars above) with card 3 moved 50 cm: written to user:// (scenes/ is read only here)
	var W2 := body()
	var S2 := scene(stance_pose(W2))
	var c2 := RootPath.root_of(W2, S2.cards[2]["pose"])
	S2.cards[2]["pose"] = RootPath.posed(W2, S2.cards[2]["pose"], (c2["xz"] as Vector2) + Vector2(0.0, 0.5), float(c2["heading"]))
	var f := FileAccess.open("user://rootpath_ui.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(S2.to_dict(W2, false)))
	f.close()
	m._load_scene("user://rootpath_ui.json")
	m._rebuild_cards()
	m.playing = false
	m.playhead = float(m.S.times()[1][1])
	m._ps().apply(m.B, m.playhead)
	m.hover_part = ""
	m.root_path_on = true
	m._refresh()
	m._turn_to(20.0, -12.0, 2.2, Vector3(0.25, 0.45, 0.3), false)   # the whole body and its path in the view (as foot_handles_test frames its foot)
	await idle(4)
	var hs: Array = RootPath.handles(RootPath.roots(m.S))
	# the card whose root handle is most alone on the screen (cards that stand on one spot share a handle: a press takes the nearest)
	var i := 0
	var best_gap := -1.0
	for j in hs.size():
		var pj: Vector2 = m.cam.unproject_position(hs[j]["root"])
		var gap := 1e9
		for k in hs.size():
			if k != j:
				gap = minf(gap, pj.distance_to(m.cam.unproject_position(hs[k]["root"])))
		if gap > best_gap:
			best_gap = gap
			i = j
	var p0: Vector2 = m.cam.unproject_position(hs[i]["root"])
	ok(best_gap > 30.0, "11 the picked card %d stands alone on screen: its nearest other handle is %.0f px away (bar 30)" % [i + 1, best_gap])
	var hit: Dictionary = RootPath.hit(m.cam, p0, hs)
	ok(hit.get("card", -1) == i and hit.get("kind", "") == "root", "11a a press on card %d's root handle takes it (%s)" % [i + 1, str(hit)])
	var rs0: Array = RootPath.roots(m.S)
	var u0: int = m.undo.size()
	var h0: Variant = RootPath.floor_hit(m.cam, p0)
	await mouse(p0, true)
	var q := p0
	for k in 10:
		q = p0 + Vector2(45.0 * float(k + 1) / 10.0, 0.0)
		await move(q, Vector2(4.5, 0.0))
	var h1: Variant = RootPath.floor_hit(m.cam, q)
	await mouse(q, false)
	await idle(3)
	var rs1: Array = RootPath.roots(m.S)
	var want := Vector2(float(h1.x) - float(h0.x), float(h1.z) - float(h0.z))
	var got := (rs1[i]["xz"] as Vector2) - (rs0[i]["xz"] as Vector2)
	ok((got - want).length() < 0.001 and want.length() > 0.05, "11b the drag moved card %d's root by the floor delta: %.1f cm, %.2f mm off (bar 1 mm)" % [i + 1, want.length() * 100.0, (got - want).length() * 1000.0])
	var others := 0.0
	for j in rs0.size():
		if j != i:
			others = maxf(others, ((rs1[j]["xz"] as Vector2) - (rs0[j]["xz"] as Vector2)).length())
	ok(others < 0.0001, "11c the other cards' roots unchanged, worst %.6f mm" % (others * 1000.0))
	ok(m.undo.size() == u0 + 1, "11d one undo step for the drag (%d added)" % (m.undo.size() - u0))
	var u1: int = m.undo.size()
	await mouse(p0, true)
	await mouse(p0, false)
	await idle(2)
	ok(m.undo.size() == u1, "11e a press and release on the handle with no move leaves no undo step (%d -> %d)" % [u1, m.undo.size()])
	m.root_path_on = false
	m._refresh()
	await idle(1)


func shot(S: Scene, W: Body) -> bool:
	var vp := SubViewport.new()
	vp.size = Vector2i(900, 640)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.14, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.62)
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var floor_m := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(6, 5)
	floor_m.mesh = pl
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.22, 0.23, 0.25)
	floor_m.material_override = fm
	world.add_child(floor_m)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.74, 0.78)
	var parts: Array = Overlays.mannequin(world, mat)
	var sk: Skeleton3D = parts[1]
	W.from_dict(S.cards[2]["pose"])
	Overlays.pose_skeleton(sk, parts[2], W)
	var line := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	line.mesh = im
	world.add_child(line)
	RootPath.draw(im, RootPath.played(S), RootPath.handles(RootPath.roots(S)), {"card": 2, "kind": "root"})
	var cam := Camera3D.new()
	cam.fov = 40
	world.add_child(cam)
	cam.look_at_from_position(Vector3(2.9, 2.3, 3.6), Vector3(0.25, 0.7, 0.3), Vector3.UP)
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var err := img.save_png(SHOT)
	vp.queue_free()
	return err == OK
