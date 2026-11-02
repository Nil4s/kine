## godot --path . -s tests/hit_boxes_test.gd [-- --shot=C:/x.png]     (ROADMAP 36: hit and hurt boxes per frame; needs a window: the view and the lane)
## HIT / HURT BOXES (scripts/hit_boxes.gd, scripts/hit_boxes_ui.gd). Read only from scenes/ (combo3, walk_bat); nothing is
## written outside user:// (never scenes/, poses/, data/). Bars, written before the run:
##   1 default hurtboxes = the body capsules, frame by frame, 0 mm (and the same list as the body's Body.cap per part)
##   2 an attack box on the bat (bat_barrel) over frames 10-14: exported on exactly frames 10..14, its ends = the bat's
##     world capsule at that frame (0 mm); the export file round-trips it; the top-level "boxes" is the scene's own list
##   3 a box on a part rides with it: its ends = the part's capsule + the part's frame x da (1e-9)
##   4 hurt edits: invincible frames have no hurtbox at all; a half-size head is half the radius on its frames only
##   5 mirror: the box's part goes to its twin, its da x negated; mirrored twice = the original; Scene.MIRROR_SCENE has "boxes"
##   6 old scenes load bit-identical: combo3 + walk_bat with no boxes hash to clips_test's BASE_HASH (the base commit's)
##   7 in the app: Hit box adds ONE undo step, Ctrl+Z / Ctrl+Y take it back and put it again; edit and delete are one step each;
##     the lane shows the box at its frames; the view draws the boxes (the --shot PNG shows them)
extends SceneTree

const BASE_HASH := "4b8adc1bf7de3875d588a7f5d51b75fd"   # re-baselined from caaff2e7fb3fea766505ed63b31cb573 (s255): 37457e51 (HANDS) added state key free_hand and 80bdf6ec (Blade turn) added wep_turn + wep_tilt to Body.state(); with those 3 keys erased the 247 frames hash to caaff2e7 exactly, so every joint angle and weapon value is bit-identical, only the dict shape grew. Was: clips_test's: combo3 + walk_bat, no boxes, the base commit's body states
const SHOT_FPS := 60
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b


func scene(path: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return S


## the largest difference (m) between two capsule lists, element by element (both lists in the same order)
func gap(xs: Array, ys: Array) -> float:
	if xs.size() != ys.size():
		return INF
	var worst := 0.0
	for i in xs.size():
		var a: Dictionary = xs[i]
		var b: Dictionary = ys[i]
		worst = maxf(worst, (a["a"] as Vector3).distance_to(b["a"]))
		worst = maxf(worst, (a["b"] as Vector3).distance_to(b["b"]))
		worst = maxf(worst, absf(float(a["r"]) - float(b["r"])))
	return worst


func _init() -> void:
	var B := body()
	var S := scene("res://scenes/combo3.json")
	var N := 0
	var fd := FrameData.analyze(S, B, SHOT_FPS)
	N = int(fd["n"])

	# 1 default hurtboxes = the body's capsules, frame by frame
	var worst := 0.0
	var P := body()
	for f in N:
		S.apply(P, float(f) / SHOT_FPS)
		var want := []
		for part in Body.BODY + Body.WIDE.keys():
			var c: Array = P.cap(part)
			want.append({"a": c[0], "b": c[1], "r": float(P.rad[part])})
		worst = maxf(worst, gap(fd["frames"][f]["hurtboxes"], want))
	ok(N > 20 and worst == 0.0, "1 default hurtboxes = the body capsules on all %d frames (worst %.6f mm)" % [N, worst * 1000.0])

	# 2 an attack box on the bat over frames 10-14
	S.boxes = HitBoxes.clean([{"kind": "hit", "part": "bat_barrel", "f0": 10, "f1": 14, "damage": 12, "hitstun": 14}])
	fd = FrameData.analyze(S, B, SHOT_FPS)
	var on := []
	var pos_worst := 0.0
	var Q := body()
	for f in N:
		var authored := []
		for c in fd["frames"][f]["hitboxes"]:
			if c.has("src"):
				authored.append(c)
		if not authored.is_empty():
			on.append(f)
			S.apply(Q, float(f) / SHOT_FPS)
			pos_worst = maxf(pos_worst, gap(authored, [{"a": Q.cap("bat_barrel")[0], "b": Q.cap("bat_barrel")[1], "r": float(Q.rad["bat_barrel"])}]))
	var want_on := []
	for f in range(10, 15):
		want_on.append(f)
	ok(on == want_on, "2 the attack box is on exactly frames 10..14 (%s)" % str(on))
	ok(pos_worst == 0.0, "2 its ends = the bat's world capsule on those frames (worst %.6f mm)" % (pos_worst * 1000.0))
	var dmg_ok := true
	for f in on:
		for c in fd["frames"][f]["hitboxes"]:
			if c.has("src") and (String(c["part"]) != "bat_barrel" or absf(float(c["damage"]) - 12.0) > 1e-3 or int(c["hitstun"]) != 14):
				dmg_ok = false
	ok(dmg_ok, "2 each such capsule carries part bat_barrel, damage 12 and hitstun 14")
	var path := "user://hit_boxes_test.json"
	ok(FrameData.write_json(fd, path) == OK, "2 the export written to user://")
	var back: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var back_on := []
	for fr in back["frames"]:
		for c in fr["hitboxes"]:
			if c.has("src"):
				back_on.append(int(fr["f"]))
				break
	ok(back_on == want_on and back.has("boxes") and (back["boxes"] as Array).size() == 1 and String(back["boxes"][0]["part"]) == "bat_barrel",
		"2 the file: the box on frames %s and \"boxes\" holds it" % str(back_on))

	# 3 a box rides with its part: the offset is in the part's own frame
	S.boxes = HitBoxes.clean([{"kind": "hit", "part": "hand_r", "f0": 5, "f1": 5, "damage": 3, "hitstun": 4, "da": [0.1, 0.02, -0.03], "db": [0.0, 0.0, 0.05]}])
	var R := body()
	S.apply(R, 5.0 / SHOT_FPS)
	var hc := HitBoxes.hit_cap(R, S.boxes[0])
	var q: Quaternion = R.G["hand_r"]
	var ea: Vector3 = (R.cap("hand_r")[0] as Vector3) + q * Vector3(0.1, 0.02, -0.03)
	var eb: Vector3 = (R.cap("hand_r")[1] as Vector3) + q * Vector3(0.0, 0.0, 0.05)
	ok((hc["a"] as Vector3).distance_to(ea) < 1e-9 and (hc["b"] as Vector3).distance_to(eb) < 1e-9,
		"3 the hand's box ends are its capsule plus the hand's frame x da (worst %.6f mm)" % (maxf((hc["a"] as Vector3).distance_to(ea), (hc["b"] as Vector3).distance_to(eb)) * 1000.0))

	# 4 hurt edits: invincible frames have no hurtbox; a half head is half the radius on its frames only
	S.boxes = HitBoxes.clean([{"kind": "hurt", "part": "*", "f0": 20, "f1": 25, "off": true},
		{"kind": "hurt", "part": "head", "f0": 30, "f1": 30, "scale": 0.5}])
	fd = FrameData.analyze(S, B, SHOT_FPS)
	var inv_ok := true
	var full := Body.BODY.size() + Body.WIDE.size()
	for f in N:
		var hb: Array = fd["frames"][f]["hurtboxes"]
		if f >= 20 and f <= 25:
			inv_ok = inv_ok and hb.is_empty()
		else:
			inv_ok = inv_ok and hb.size() == full
	ok(inv_ok, "4 invincible frames 20..25 have no hurtbox; every other frame has the full set")
	var P2 := body()
	S.apply(P2, 30.0 / SHOT_FPS)
	var head_full := float(P2.rad["head"])
	var idx := (Body.BODY + Body.WIDE.keys()).find("head")
	var head_r := float(fd["frames"][30]["hurtboxes"][idx]["r"])
	var head_31 := float(fd["frames"][31]["hurtboxes"][idx]["r"])
	ok(absf(head_r - head_full * 0.5) < 1e-12 and absf(head_31 - head_full) < 1e-12,
		"4 the head is half its radius on frame 30 (%.4f m) and whole on 31 (%.4f m)" % [head_r, head_31])

	# 5 mirror: twin part, offsets' x negated, twice = the original; the key has a side in the mirror list
	S.boxes = HitBoxes.clean([{"kind": "hit", "part": "hand_r", "f0": 5, "f1": 7, "damage": 3, "hitstun": 4, "da": [0.1, 0.02, -0.03]},
		{"kind": "hurt", "part": "calf_l", "f0": 9, "f1": 9, "scale": 2.0}])
	var M := body()
	var d := Scene.mirror_file(S.to_dict(M, false), M)
	var m1: Array = d["boxes"]
	var m2: Array = HitBoxes.mirror_file(m1)
	var mir_ok := String(m1[0]["part"]) == "hand_l" and String(m1[1]["part"]) == "calf_r" \
		and absf(float(m1[0]["da"][0]) + 0.1) < 1e-9 and absf(float(m1[0]["da"][1]) - 0.02) < 1e-9
	ok(mir_ok, "5 mirrored: hand_r -> hand_l and calf_l -> calf_r, da x negated, y and z kept")
	ok(JSON.stringify(m2) == JSON.stringify(S.boxes), "5 mirrored twice = the original boxes")
	ok("boxes" in Scene.MIRROR_SCENE, "5 Scene.MIRROR_SCENE holds \"boxes\" (the mirror list test passes it)")

	# 6 old scenes: no boxes, no key in the file, and the body hashes to the base commit's
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	var old_keys := true
	for p in ["res://scenes/combo3.json", "res://scenes/walk_bat.json"]:
		var Sx := scene(p)
		old_keys = old_keys and Sx.boxes.is_empty() and not Sx.to_dict(body(), false).has("boxes")
		var f := 0
		while f / 30.0 <= Sx.length():
			Sx.apply(B, f / 30.0)
			h.update(var_to_str(B.state()).to_utf8_buffer())
			f += 1
	var got := h.finish().hex_encode()
	ok(old_keys and got == BASE_HASH, "6 old scenes: no \"boxes\" key, body states hash to the base commit's (%s)" % got)

	# 7 the app: one undo step per edit, the lane and the view
	await app_part()
	print("HIT BOXES TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)


# 7
func app_part() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 3:
		await process_frame
	m.S = scene("res://scenes/combo3.json")
	m.scene_path = ""
	m._rebuild_cards()
	m.undo.clear()
	m.fd_fps = 60
	var ids: Array = m._commands().map(func(c): return c["id"])
	ok(ids.filter(func(i): return String(i).begins_with("hit_box") or String(i).begins_with("hurt_box") or String(i).begins_with("box_")).size() == 4,
		"7 the four box commands are in the registry")
	m.sel = "bat_barrel"
	m.playhead = 10.0 / 60.0
	var u0: int = m.undo.size()
	m.hitbox_ui.open("hit")
	m.hitbox_ui.ui_f0.value = 10
	m.hitbox_ui.ui_f1.value = 14
	m.hitbox_ui.ui_dmg.value = 12
	m.hitbox_ui.ui_stun.value = 14
	m.hitbox_ui._ok()
	ok(m.S.boxes.size() == 1 and m.undo.size() == u0 + 1 and String(m.S.boxes[0]["part"]) == "bat_barrel",
		"7 Hit box on the bat: one box, one undo step (%d)" % (m.undo.size() - u0))
	await process_frame
	var tl: Timeline = m.ui_timeline
	ok(tl.bx.size() == 1 and absf(float(tl.bx[0]["t0"]) - 10.0 / 60.0) < 1e-9 and String(tl.bx[0]["kind"]) == "hit",
		"7 the lane has the attack box from frame 10 (%.3f s)" % float(tl.bx[0]["t0"]))
	m._undo()
	ok(m.S.boxes.is_empty(), "7 Ctrl+Z takes the box back")
	m._redo()
	ok(m.S.boxes.size() == 1, "7 Ctrl+Y puts it back")
	m.hitbox_ui.open_edit()
	m.hitbox_ui.ui_dmg.value = 20
	var u1: int = m.undo.size()
	m.hitbox_ui._ok()
	ok(float(m.S.boxes[0]["damage"]) == 20.0 and m.undo.size() == u1 + 1, "7 edit the box's damage: one undo step")
	m._undo()
	ok(float(m.S.boxes[0]["damage"]) == 12.0, "7 Ctrl+Z puts the damage back to 12")
	m.hitbox_ui.open_edit()
	var u2: int = m.undo.size()
	m.hitbox_ui._delete()
	ok(m.S.boxes.is_empty() and m.undo.size() == u2 + 1, "7 delete: one undo step")
	m._undo()
	ok(m.S.boxes.size() == 1, "7 Ctrl+Z brings the box back")
	# 7b the lane picks the box; a press on its end handle, a move and a release (through main's input) move the end 5 cm
	# along the view, within 1 mm; the drag is one undo step and Ctrl+Z puts the end back
	m.playhead = 12.0 / 60.0
	m.S.apply(m.B, m.playhead)
	m._refresh()
	var tl0: Timeline = m.ui_timeline
	var lp := InputEventMouseButton.new()
	lp.button_index = MOUSE_BUTTON_LEFT
	lp.pressed = true
	lp.position = Vector2(tl0.x_of(float(tl0.bx[0]["t0"]) + 0.01), Timeline.RULER + 2.0 + 2.0)
	tl0._gui_input(lp)
	ok(m.hitbox_ui.sel == 0, "7b a click on the box's lane picks it (sel %d)" % m.hitbox_ui.sel)
	var a_old: Vector3 = (m.hitbox_ui.handles() as Dictionary)["a"]
	var want: Vector3 = a_old + m.cam.global_basis.x * 0.05
	var sp: Vector2 = m.cam.unproject_position(a_old)
	var sq: Vector2 = m.cam.unproject_position(want)
	var u4: int = m.undo.size()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = sp
	m._unhandled_input(press)
	var mv := InputEventMouseMotion.new()
	mv.position = sp.lerp(sq, 0.5)
	m._unhandled_input(mv)
	mv.position = sq
	m._unhandled_input(mv)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = sq
	m._unhandled_input(rel)
	var a_new: Vector3 = HitBoxes.hit_cap(m.B, m.S.boxes[0])["a"]
	var err := (a_new - want).length()
	ok(err < 0.001 and absf((a_new - a_old).length() - 0.05) < 0.001 and m.undo.size() == u4 + 1,
		"7b the end's handle, dragged, moves the end 5 cm along the view: %.3f mm from the target, one undo step" % (err * 1000.0))
	m._undo()
	ok(not m.S.boxes[0].has("da") and (HitBoxes.hit_cap(m.B, m.S.boxes[0])["a"] - a_old).length() < 1e-9,
		"7b Ctrl+Z puts the end back where it was")
	m._redo()
	# an invincible range and the picked hurt edit, then the view with the boxes drawn at frame 12
	m.sel = "head"
	m.hitbox_ui.open("hurt")
	m.hitbox_ui.ui_f0.value = 20
	m.hitbox_ui.ui_f1.value = 25
	m.hitbox_ui.ui_scale.value = 50
	m.hitbox_ui._ok()
	m.hitbox_ui.open("inv")
	m.hitbox_ui.ui_f0.value = 40
	m.hitbox_ui.ui_f1.value = 46
	m.hitbox_ui._ok()
	ok(m.S.boxes.size() == 3 and HitBoxes.is_invincible(m.S.boxes[2]), "7 a hurt edit and an invincible range are boxes too (%d)" % m.S.boxes.size())
	m.fd_on = true
	m.fd_boxes = true
	m.playhead = 12.0 / 60.0
	m.S.apply(m.B, m.playhead)
	m._refresh()
	for i in 3:
		await process_frame
	ok(tl.bx.size() == 3, "7 the lane shows three boxes (hit, hurt, invincible)")
	m.hitbox_ui.dlg.hide()   # the dialog is shut for the picture: the view and the lane show
	m.hitbox_ui.pick(0)   # the attack box is picked: its handles show on frame 12
	m.playhead = 12.0 / 60.0
	m.S.apply(m.B, m.playhead)
	m._refresh()
	ok(not (m.hitbox_ui.handles() as Dictionary).is_empty(), "7 the picked box's handles show on its frames")
	for i in 2:
		await process_frame
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var img: Image = root.get_viewport().get_texture().get_image()
			img.save_png(a.substr(7))
			print("     shot: %s" % a.substr(7))
	m.queue_free()
	await process_frame
