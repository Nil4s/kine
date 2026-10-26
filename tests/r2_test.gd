## godot --path . -s tests/r2_test.gd     (ROADMAP R2; needs a window: it renders)
## DEPTH OF FIELD on the shot camera (shot_fx.gd ShotFx.dof; main.gd _shot_dof_set, _shot_fstop). A whole-body shot (50 mm, camera
## 5.5 m from the hero, 2.2 m of height in the frame). Two noise cards of the same size on the screen: A at the head's depth
## (5.5 m), B 2 m behind it (7.5 m, scaled 7.5/5.5 so both cover the same pixels). Sharpness = variance of the 4-neighbour
## Laplacian of the grey frame over the card's projected rectangle (ShotCam.project), clean look-through.
## BARS (stated before measuring):
##   1 thin-lens maths: ShotFx.dof(50 mm, f/1.4, 5.5 m) near/far against the textbook formula, written out here, within 1 mm
##   2 focus on the picked head: sharp(A) > 1.5 x sharp(B) at f/1.4
##   3 the focus moves to 7.5 m: sharp(B) > 1.5 x sharp(A), and A is blurrier than it was in 2 (it flips)
##   4 f/22 is deep: sharp(A) / sharp(B) < 1.2 (nearly everything sharp), and f/1.4's ratio is more than 2 x f/22's
##   5 the playblast: the frame the playblast draws (_shot_blast_begin/_frame) shows the same ordering as 2
##   6 one undo step per f-stop change, undo restores; the f-stop survives the file round trip; out-of-range values clamp
##   7 PLACEMENT: in the whole-body view the head and the feet are inside the 16:9 frame (head in its top 40 %, soles in the
##     lowest 15 %), card A's detail is centred where ShotCam.project puts it, and the DOF's sharp zone is centred on the
##     head's own distance (within 5 cm)
## Thin lens: Kingslake, "Optics in Photography"; c = 0.024 mm on the 36 mm sensor (d / 1500).
extends SceneTree

var fails := 0
var m: Node
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/r2.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func grab() -> Image:
	await idle(3)
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()


func grey(img: Image, x: int, y: int) -> float:
	var c := img.get_pixel(x, y)
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


## variance of the 4-neighbour Laplacian of the grey image inside r
func lap_var(img: Image, r: Rect2i) -> float:
	var s := 0.0
	var s2 := 0.0
	var n := 0
	for y in range(r.position.y + 1, r.end.y - 1):
		for x in range(r.position.x + 1, r.end.x - 1):
			var l := grey(img, x - 1, y) + grey(img, x + 1, y) + grey(img, x, y - 1) + grey(img, x, y + 1) - 4.0 * grey(img, x, y)
			s += l
			s2 += l * l
			n += 1
	var mean := s / maxf(n, 1)
	return s2 / maxf(n, 1) - mean * mean


func lap_centre(img: Image, r: Rect2i) -> Vector2i:
	var sx := 0.0
	var sy := 0.0
	var sw := 0.0
	for y in range(r.position.y + 1, r.end.y - 1, 2):
		for x in range(r.position.x + 1, r.end.x - 1, 2):
			var l := absf(grey(img, x - 1, y) + grey(img, x + 1, y) + grey(img, x, y - 1) + grey(img, x, y + 1) - 4.0 * grey(img, x, y))
			sx += x * l
			sy += y * l
			sw += l
	return Vector2i(int(sx / maxf(sw, 1e-9)), int(sy / maxf(sw, 1e-9)))


func card(world: Vector3, size: float, seed_n: int) -> MeshInstance3D:
	var im := Image.create(16, 16, false, Image.FORMAT_L8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	for y in 16:
		for x in 16:
			im.set_pixel(x, y, Color.WHITE if rng.randi() % 2 == 0 else Color.BLACK)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = ImageTexture.create_from_image(im)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mi.material_override = mat
	mi.position = world
	return mi


func rect_of(p: Vector3, size: float, pos: Vector3, aim: Vector3, f: float, fr: Rect2i) -> Rect2i:
	var a := ShotCam.project(pos, aim, f, fr, p + Vector3(-size, size, 0) * 0.5)
	var b := ShotCam.project(pos, aim, f, fr, p + Vector3(size, -size, 0) * 0.5)
	return Rect2i(Vector2i(a.round()), Vector2i((b - a).round()))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.fk()
	var S := Scene.new()
	S.name = "zz_r2"
	S.fps = 24
	S.shots = [{"t": 0.0, "name": "Shot 1", "keys": [], "fx": {}}]
	S.add("c0", R.to_dict())
	S.cards[0]["hold"] = 1.0
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 0.0
	m._refresh()
	await idle(3)
	var cpos := Vector3(0, 1.0, 5.5)
	var aim := Vector3(0, 0.95, 0)
	ShotCam.put(S.shots[0]["keys"], {"t": 0.0, "pos": cpos, "aim": aim, "f": 50.0})
	var sz_b := 0.5 * 7.5 / 5.5
	var A := card(Vector3(-1.0, 1.0, 0.0), 0.5, 11)
	var B := card(Vector3(1.0 * 7.5 / 5.5, 1.0, -2.0), sz_b, 22)
	m.add_child(A)
	m.add_child(B)
	m.clean = true
	m.ui_root.visible = false   # no panels over the frame
	m._refresh()
	m._shot_toggle()
	await idle(4)
	var fr: Rect2i = m.shot_rect()
	var ra := rect_of(A.position, 0.5, cpos, aim, 50.0, fr).grow(-3)
	var rb := rect_of(B.position, sz_b, cpos, aim, 50.0, fr).grow(-3)
	print("  frame %s, card A %s, card B %s" % [fr, ra, rb])

	# 1 the textbook numbers
	var f := 50.0
	var Smm := 5500.0
	var H := f * f / (1.4 * 0.024) + f
	var near_w := Smm * (H - f) / (H + Smm - 2.0 * f) / 1000.0
	var far_w := Smm * (H - f) / (H - Smm) / 1000.0
	var d := ShotFx.dof(50.0, 1.4, 5.5)
	ok(absf(float(d["near"]) - near_w) < 0.001 and absf(float(d["far"]) - far_w) < 0.001, "1 ShotFx.dof 50 mm f/1.4 at 5.5 m: sharp from %.3f to %.3f m (formula %.3f to %.3f)" % [float(d["near"]), float(d["far"]), near_w, far_w])
	var d22 := ShotFx.dof(50.0, 22.0, 5.5)
	ok(float(d22["far"]) > 40.0, "  at f/22 the far limit is far away (%.1f m)" % float(d22["far"]))

	# 2 focus on the head (the picked part)
	m.sel = "head"
	m._shot_focus_part()
	m._shot_fstop(1.4)
	m._refresh()
	await idle(3)
	var head_d: float = cpos.distance_to(ShotFx.part_at(S, "head", 0.0))
	var img1: Image = await grab()
	var a1 := lap_var(img1, ra)
	var b1 := lap_var(img1, rb)
	ok(a1 > 1.5 * b1, "2 focused on the head (%.2f m) at f/1.4: sharp(A %.5f) > 1.5 x sharp(B %.5f), ratio %.2f" % [head_d, a1, b1, a1 / maxf(b1, 1e-9)])

	# 3 the focus moves behind
	S.shots[0]["fx"]["focus"] = [{"t": 0.0, "dist": 7.5}]
	m._refresh()
	await idle(3)
	var img2: Image = await grab()
	var a2 := lap_var(img2, ra)
	var b2 := lap_var(img2, rb)
	ok(b2 > 1.5 * a2 and a2 < a1, "3 focus at 7.5 m: sharp(B %.5f) > 1.5 x sharp(A %.5f), ratio %.2f; A fell from %.5f" % [b2, a2, b2 / maxf(a2, 1e-9), a1])

	# 4 f/22
	S.shots[0]["fx"]["focus"] = [{"t": 0.0, "part": "head"}]
	m._shot_fstop(22.0)
	m._refresh()
	await idle(3)
	var img3: Image = await grab()
	var a3 := lap_var(img3, ra)
	var b3 := lap_var(img3, rb)
	var r22 := a3 / maxf(b3, 1e-9)
	var r14 := a1 / maxf(b1, 1e-9)
	ok(r22 < 1.2 and r14 > 2.0 * r22, "4 f/22: sharp(A %.5f) / sharp(B %.5f) = %.2f (< 1.2); f/1.4's ratio %.2f is more than 2 x that" % [a3, b3, r22, r14])

	# 5 the playblast's own frames
	m._shot_fstop(1.4)
	var sb: Dictionary = m._shot_blast_begin()
	m._shot_blast_frame(sb)
	var img5: Image = await grab()
	var a5 := lap_var(img5, ra)
	var b5 := lap_var(img5, rb)
	var cut: Image = m._shot_blast_image(sb, img5)
	m._shot_blast_end(sb)
	ok(not sb.is_empty() and a5 > 1.5 * b5 and cut.get_size() == fr.size, "5 playblast frame (cut %s): sharp(A %.5f) > 1.5 x sharp(B %.5f)" % [cut.get_size(), a5, b5])

	# 6 undo, file, clamp
	var n0: int = m.undo.size()
	m._shot_fstop(8.0)
	var n1: int = m.undo.size()
	ok(n1 == n0 + 1 and absf(float(S.shots[0]["fx"]["fstop"]) - 8.0) < 1e-6, "6 an f-stop change is one undo step (%d -> %d), f/8" % [n0, n1])
	m._undo()
	ok(absf(float(S.shots[0]["fx"]["fstop"]) - 1.4) < 1e-6, "  undo puts f/1.4 back")
	var back := ShotCam.shots_from_file({"shots": ShotCam.shots_to_file(S.shots)})
	ok(back.size() == 1 and absf(float(back[0]["fx"].get("fstop", 0.0)) - 1.4) < 1e-6, "  the f-stop survives the file round trip (f/%s)" % str(back[0]["fx"].get("fstop")))
	var mir: Dictionary = ShotFx.mirror_file(ShotFx.to_file(S.shots[0]["fx"]))
	ok(absf(float(mir.get("fstop", 0.0)) - 1.4) < 1e-6, "  a mirrored scene keeps it")
	ok(ShotFx.fstop_of({"fstop": 0.5}) == 1.4 and ShotFx.fstop_of({"fstop": 90.0}) == 22.0 and ShotFx.fstop_of({}) == ShotFx.F_DEFAULT, "  out-of-range f-stops clamp to f/1.4 .. f/22; none = f/2.8")

	# 7 placement
	var hp := ShotCam.project(cpos, aim, 50.0, fr, ShotFx.part_at(S, "head", 0.0))
	var fp := ShotCam.project(cpos, aim, 50.0, fr, ShotFx.part_at(S, "foot_l", 0.0) - Vector3(0, 0.08, 0))
	var hy := (hp.y - fr.position.y) / fr.size.y
	var fy := (fr.end.y - fp.y) / fr.size.y
	ok(fr.has_point(Vector2i(hp)) and fr.has_point(Vector2i(fp)) and hy < 0.4 and fy < 0.15 and fy >= 0.0, "7 whole body in the frame: head %.0f %% from the top (< 40), soles %.0f %% above the bottom (< 15)" % [hy * 100.0, fy * 100.0])
	var cen_a := lap_centre(img1, ra.grow(8))
	ok(Vector2(cen_a).distance_to(Vector2(ra.get_center())) < ra.size.x * 0.3, "  card A is where it projects: detail centre %s, projected centre %s" % [cen_a, ra.get_center()])
	var dd := ShotFx.dof(50.0, 1.4, head_d)
	var sharp_mid := 0.5 * (float(dd["near"]) + float(dd["far"]))
	ok(absf(sharp_mid - head_d) < 0.05, "  the sharp zone is centred on the head's distance %.3f m (middle %.3f m)" % [head_d, sharp_mid])

	# the screenshot: focused near | focused far
	var both := Image.create(fr.size.x * 2 + 8, fr.size.y, false, img1.get_format())
	both.fill(Color.BLACK)
	both.blit_rect(img1, fr, Vector2i(0, 0))
	both.blit_rect(img2, fr, Vector2i(fr.size.x + 8, 0))
	both.save_png(OUT)
	print("  screenshot %s (left: focus on the head at f/1.4, right: focus 2 m behind)" % OUT)
	m._shot_toggle()
	if fails == 0:
		print("R2 TEST PASS")
	else:
		print("R2 TEST FAIL (%d)" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
