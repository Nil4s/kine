## godot --path . -s tests/r4_test.gd     (ROADMAP R4; needs a window: it renders)
## CONTACT SHADOWS (scripts/contact_shadow.gd; main.gd cshadow, VIEW > Contact shadows). Top view of the floor with the body
## hidden (so the sole's floor patch is visible), luminance = mean grey of a 7x7 px patch. "under" = the sole's floor centre
## (midpoint of the ankle and toe tip), "beside" = 20 cm outward from it (away from the other foot). ratio = under / beside.
## BARS (stated before measuring):
##   1 foot planted: ratio(on) < 0.80 (at least 20 % darker), and with the toggle OFF the same two spots are equal (ratio
##     0.97..1.03: the darkening is the blob, not the grid or the sun)
##   2 foot lifted 15 cm (sole >= 15 cm up): ratio >= 0.97 (darkening gone); at 7 cm it is in between (0.80 < ratio < 0.97 is
##     not required, only: ratio(planted) < ratio(7 cm) < ratio(15 cm))
##   3 the body moves (offset 0.30 m x, 0.20 m z, a 40 deg turn): each blob's centre is within 2 cm of the midpoint of the
##     sole's ankle / toe tip floor projection, both feet
##   4 PLACEMENT in a whole-body view (body shown): the blob's screen centre is within 40 px of the ankle's and not above it
##     by more than 10 px, left and right; the raised foot's blob alpha is 0 when 15 cm up, ALPHA_MAX when planted
##   5 the VIEW toggle: on by default; off hides every blob; it is not an edit (no undo step)
extends SceneTree

var fails := 0
var m: Node
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/r4.png"


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


func lum(img: Image, p: Vector2) -> float:
	var s := 0.0
	var n := 0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var c := img.get_pixel(clampi(int(p.x) + dx, 0, img.get_width() - 1), clampi(int(p.y) + dy, 0, img.get_height() - 1))
			s += 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			n += 1
	return s / n


## raise the left ankle until that sole is `h` m off the floor (reach keeps the foot's own tilt, so the sole's height is
## measured and the target corrected)
func lift_to(B: Body, base: Dictionary, h: float) -> void:
	B.set_state(base)
	var ank: Vector3 = B.P["foot_l"]
	var up := h
	for i in 8:
		B.set_state(base)
		B.reach("foot_l", ank + Vector3(0, up, 0))
		B.fk()
		up += h - B.foot_sole_low("_l")


func sole_mid(B: Body, sd: String) -> Vector3:
	var a: Vector3 = B.P["foot" + sd]
	var b: Vector3 = B.E["ball" + sd]
	return Vector3((a.x + b.x) * 0.5, 0.0, (a.z + b.z) * 0.5)


## ratio under/beside for foot_l, in the top view over that foot
func ratio(sd: String) -> Array:
	var B: Body = m.B
	var c := sole_mid(B, sd)
	var other := sole_mid(B, "_r" if sd == "_l" else "_l")
	var out := (c - other).normalized()
	m.target = c
	m.yaw = 0.0
	m.pitch = -89.0
	m.dist = 1.2
	m._cam()
	var img: Image = await grab()
	var pu: Vector2 = m.cam.unproject_position(c + Vector3(0, 0.003, 0))
	var pb: Vector2 = m.cam.unproject_position(c + out * 0.20 + Vector3(0, 0.003, 0))
	var u := lum(img, pu)
	var b := lum(img, pb)
	return [u / maxf(b, 1e-6), u, b]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var B: Body = m.B
	var cs: ContactShadow = m.cshadow
	ok(cs.on, "5 on by default")
	B.fk()
	B.offset.y -= B.sole_low()
	B.fk()
	m._refresh()
	var base: Dictionary = B.state()
	m.clean = true
	m.ui_root.visible = false
	for j in m.pieces:
		m.hidden_parts[j] = true
	m._refresh()
	await idle(3)

	# 1 planted
	print("  sole low l %.4f r %.4f" % [B.foot_sole_low("_l"), B.foot_sole_low("_r")])
	var r_on: Array = await ratio("_l")
	cs.on = false
	m._refresh()
	var r_off: Array = await ratio("_l")
	cs.on = true
	m._refresh()
	ok(r_on[0] < 0.80, "1 planted: under %.3f beside %.3f, ratio %.3f (bar < 0.80)" % [r_on[1], r_on[2], r_on[0]])
	ok(absf(r_off[0] - 1.0) < 0.03, "  toggle OFF: ratio %.3f (bar 0.97..1.03: the darkening is the blob)" % r_off[0])

	# 2 lifted: the sole goes up 7 cm, then 16 cm (>= 15 cm: the blob is gone)
	var rs := []
	for up in [0.07, 0.16]:
		lift_to(B, base, up)
		m._refresh()
		await idle(2)
		var h := B.foot_sole_low("_l")
		var rr: Array = await ratio("_l")
		rs.append(rr[0])
		print("  ankle +%.0f cm: sole %.1f cm up, alpha %.3f, ratio %.3f" % [up * 100.0, h * 100.0, cs.last["foot_l"]["alpha"], rr[0]])
		if up > 0.1:
			ok(h >= 0.15, "  (the sole is %.1f cm up, bar >= 15)" % [h * 100.0])
	ok(rs[1] >= 0.97, "2 lifted 15 cm: ratio %.3f (bar >= 0.97, the darkening is gone)" % rs[1])
	ok(r_on[0] < rs[0] and rs[0] < rs[1], "  in between at 7 cm: planted %.3f < 7 cm %.3f < 15 cm %.3f" % [r_on[0], rs[0], rs[1]])

	# 3 the body moves
	B.set_state(base)
	B.offset += Vector3(0.30, 0.0, 0.20)
	B.fk()
	B.set_state(B.state())
	m._refresh()
	await idle(2)
	for sd in ["_l", "_r"]:
		var want := sole_mid(B, sd)
		var got: Vector2 = cs.last["foot" + sd]["centre"]
		var nd := (cs.get_node("contact_foot" + sd) as Node3D).global_position
		var e := Vector2(want.x, want.z).distance_to(got)
		ok(e < 0.02 and Vector2(nd.x, nd.z).distance_to(Vector2(want.x, want.z)) < 0.02, "3 moved body, foot%s: blob %.3f,%.3f vs sole %.3f,%.3f, off by %.1f mm (bar < 20)" % [sd, got.x, got.y, want.x, want.z, e * 1000.0])

	# 4 placement, whole body, and the screenshot: standing | one foot raised
	B.set_state(base)
	B.fk()
	m.hidden_parts.clear()
	m.clean = false
	m.yaw = 25.0
	m.pitch = -28.0
	m.dist = 2.2
	m.target = Vector3(0, 0.45, 0)
	m._cam()
	m._refresh()
	var imgs := []
	for lift in [0.0, 0.16]:
		B.set_state(base)
		if lift > 0.0:
			lift_to(B, base, lift)
		B.fk()
		m._refresh()
		m._cam()
		await idle(2)
		imgs.append(await grab())
		for sd in ["_l", "_r"]:
			var e: Dictionary = cs.last["foot" + sd]
			var node := cs.get_node("contact_foot" + sd) as MeshInstance3D
			var pb: Vector2 = m.cam.unproject_position(node.global_position)
			var pa: Vector2 = m.cam.unproject_position(B.P["foot" + sd])
			if lift == 0.0 or sd == "_r":
				ok(node.visible and absf(pb.x - pa.x) < 40.0 and pb.y > pa.y - 10.0, "4 whole body, lift %.0f, foot%s: blob at %s, ankle at %s px, alpha %.2f" % [lift * 100.0, sd, pb.round(), pa.round(), e["alpha"]])
			else:
				ok(not node.visible and e["alpha"] == 0.0, "4 foot_l raised 15+ cm: blob hidden (alpha %.3f)" % e["alpha"])
	var w: int = imgs[0].get_width()
	var h2: int = imgs[0].get_height()
	var crop := Rect2i(int(w * 0.3), int(h2 * 0.05), int(w * 0.4), int(h2 * 0.9))
	var both := Image.create(crop.size.x * 2 + 8, crop.size.y, false, imgs[0].get_format())
	both.fill(Color.BLACK)
	both.blit_rect(imgs[0], crop, Vector2i(0, 0))
	both.blit_rect(imgs[1], crop, Vector2i(crop.size.x + 8, 0))
	both.save_png(OUT)
	print("  screenshot %s (left: standing, right: left foot raised)" % OUT)

	# 5 the toggle
	var n0: int = m.undo.size()
	cs.on = false
	m._refresh()
	var any_vis := false
	for ch in cs.get_children():
		any_vis = any_vis or (ch as MeshInstance3D).visible
	ok(not any_vis and cs.last.is_empty() and m.undo.size() == n0, "5 off: no blob drawn, no undo step")
	if fails == 0:
		print("R4 TEST PASS")
	else:
		print("R4 TEST FAIL (%d)" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
