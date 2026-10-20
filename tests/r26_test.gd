## godot --path . -s tests/r26_test.gd     (R26; needs a window)
## SHARE BY QR (Nick's idea): a pose, or a short scene, packed to KINE1: text, drawn as a QR, read back from a picture.
## BARS (stated before measuring):
##  1 codec: a pose -> text -> pose is within the quantisation: every angle within 0.05 deg (+1e-4), the hips within 0.5 mm;
##    the text is under the 4296 characters of the biggest QR; garbage / a newer version / a damaged text are refused with a next step.
##  2 PNG round trip: Share as QR on the body draws a PNG; reading it back gives the SAME text; opening it puts the pose on a
##    zeroed body within 0.05 deg, as ONE undo step, and Ctrl+Z gives the zeroed body back.
##  3 combo3 (12 cards): the scene either fits one QR and round-trips through the PNG (cards, names, angles within 0.05 deg,
##    one undo step removes all of them) or is refused with "too long for one QR" + a next step. The result is REPORTED.
##  4 a made-up scene of 300 busy cards is refused with a next step, and no picture is drawn.
##  5 a phone-photo-like copy (0.5x, 5 degrees turned on a grey table, 3x3 blur) of the pose QR and of the scene QR (if it fits) still reads.
##  6 PLACEMENT: with the popup open, the viewport screenshot (saved to $R26_PNG, default tmp/r26.png) is read as a QR: the code is
##    ON SCREEN and scannable, inside the popup, the popup inside the window and not over the body in the middle.
extends SceneTree

var fails := 0
var m: Node
const TMP := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func max_err(a: Dictionary, b: Dictionary) -> float:
	var e := 0.0
	for j in Body.ORDER:
		var x: Vector3 = a.get(j, Vector3.ZERO)
		var y: Vector3 = b.get(j, Vector3.ZERO)
		e = maxf(e, maxf(absf(x.x - y.x), maxf(absf(x.y - y.y), absf(x.z - y.z))))
	return e


## 0.5x, turned 5 degrees on a grey table, then a 3x3 box blur: a phone photo of a screen, roughly
func distort(src: String, dst: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(src))
	img.convert(Image.FORMAT_L8)
	img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	var w := img.get_width()
	var h := img.get_height()
	var sd := img.get_data()
	var cw := int(w * 1.3)
	var ch := int(h * 1.3)
	var out := PackedByteArray()
	out.resize(cw * ch)
	out.fill(140)
	var a := deg_to_rad(5.0)
	var ca := cos(a)
	var sa := sin(a)
	for y in ch:
		for x in cw:
			var dx := x - cw / 2.0
			var dy := y - ch / 2.0
			var sx := ca * dx + sa * dy + w / 2.0
			var sy := -sa * dx + ca * dy + h / 2.0
			if sx < 0 or sy < 0 or sx >= w - 1 or sy >= h - 1:
				continue
			var x0 := int(sx)
			var y0 := int(sy)
			var fx := sx - x0
			var fy := sy - y0
			var v := (sd[y0 * w + x0] * (1 - fx) + sd[y0 * w + x0 + 1] * fx) * (1 - fy) + (sd[(y0 + 1) * w + x0] * (1 - fx) + sd[(y0 + 1) * w + x0 + 1] * fx) * fy
			out[y * cw + x] = int(v)
	var tmp := out.duplicate()   # blur: rows then columns
	for y in ch:
		for x in range(1, cw - 1):
			tmp[y * cw + x] = (out[y * cw + x - 1] + out[y * cw + x] + out[y * cw + x + 1]) / 3
	var res := tmp.duplicate()
	for y in range(1, ch - 1):
		for x in cw:
			res[y * cw + x] = (tmp[(y - 1) * cw + x] + tmp[y * cw + x] + tmp[(y + 1) * cw + x]) / 3
	Image.create_from_data(cw, ch, false, Image.FORMAT_L8, res).save_png(ProjectSettings.globalize_path(dst))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	await idle(2)
	m._card_pick(2)   # CONTACT: a pose well away from rest
	await idle(2)

	# ---- 1 the codec
	var ang0: Dictionary = m.B.ang.duplicate()
	var off0: Vector3 = m.B.offset
	var txt := QrShare.pack_pose(ang0, off0)
	var u := QrShare.unpack(txt)
	var moved := 0
	for j in ang0:
		if (ang0[j] as Vector3).length() > 0.05:
			moved += 1
	ok(u["ok"] and u["kind"] == "pose", "the pose text unpacks as a pose")
	var e1 := max_err(ang0, u["cards"][0]["ang"])
	var eo := ((u["cards"][0]["off"] as Vector3) - off0).length()
	ok(e1 <= 0.05 + 1e-4 and eo <= 0.0005 * 1.74, "round trip within quantisation: worst angle %.4f deg (bar 0.05), hips %.2f mm (bar 0.87)" % [e1, eo * 1000.0])
	ok(txt.length() < QrShare.CAP_L and txt.begins_with("KINE1:"), "one pose is %d characters of the %d one QR holds (%d%%), %d of %d joints off rest" % [txt.length(), QrShare.CAP_L, roundi(100.0 * txt.length() / QrShare.CAP_L), moved, ang0.size()])
	ok(not QrShare.unpack("HELLO WORLD")["ok"] and "not a Kine code" in QrShare.unpack("HELLO WORLD")["why"], "a stranger's QR is refused, naming what to do: %s" % QrShare.unpack("HELLO WORLD")["why"].left(70))
	ok("newer Kine" in QrShare.unpack("KINE2:ABC")["why"], "a newer version says to update Kine")
	var dmg := txt.substr(0, txt.length() - 9) + "!!!"
	ok(not QrShare.unpack(dmg)["ok"] and "photograph" in QrShare.unpack(dmg)["why"], "a damaged text is refused with 'photograph it again'")
	ok(QrShare.b45_decode(QrShare.b45_encode(PackedByteArray([0, 255, 17, 200, 3]))) == PackedByteArray([0, 255, 17, 200, 3]), "base45 round-trips 5 odd bytes")

	# ---- 2 PNG round trip, then open
	m._qr_share()
	await idle(3)
	ok(m.ui_qr_scene.visible and m.ui_qr_scene.button_pressed and m.qr_last["kind"] == "scene", "with a short scene the popup offers (and ticks) the whole scene")
	m.ui_qr_scene.button_pressed = false   # the body's pose alone
	await idle(6)
	var q: Dictionary = m.qr_last
	ok(q["kind"] == "pose" and q["text"] == txt, "unticking it shares the body's pose: the same text as the codec's")
	ok(bool(q.get("ok", false)) and FileAccess.file_exists(q["png"]), "Share as QR drew %s (QR version %s, level %s)" % [q.get("png", ""), q.get("version", "?"), q.get("ecc", "?")])
	var back: Dictionary = QrShare.read_png(q["png"])
	ok(bool(back.get("ok", false)) and back["text"] == txt, "the picture reads back as the SAME %d characters" % String(back.get("text", "")).length())

	# ---- 6 placement (popup open now)
	await RenderingServer.frame_post_draw
	var shot := OS.get_environment("R26_PNG")
	if shot == "":
		shot = TMP + "r26.png"
	var img: Image = m.get_viewport().get_texture().get_image()
	img.save_png(shot)
	var dlg: Window = m.ui_qr
	var vr: Rect2 = m.get_viewport().get_visible_rect()
	var pic: Control = m.ui_qr_pic
	var pr := Rect2(pic.global_position, pic.size)   # in the popup's own coordinates
	ok(dlg.visible and vr.encloses(Rect2(dlg.position, dlg.size)), "the popup is open and inside the window: %s in %s" % [Rect2(dlg.position, dlg.size), vr])
	ok(Rect2(Vector2.ZERO, dlg.size).encloses(pr) and pic.texture != null, "the QR picture is inside the popup: %s" % pr)
	ok(dlg.position.x > vr.size.x * 0.5, "the popup sits at the right (x %d of %d): the body in the middle stays in view" % [dlg.position.x, vr.size.x])
	var onscreen := QrShare.read_png(shot)
	ok(bool(onscreen.get("ok", false)) and onscreen["text"] == txt, "the screenshot itself is scannable: the QR on screen reads as the pose (%s)" % (str(onscreen.get("why", "same text"))))
	ok((m.ui_qr_info as Label).text.contains("QR version") and (m.ui_qr_info as Label).text.contains("4296"), "the popup says how much of one QR it uses: %s" % (m.ui_qr_info as Label).text.get_slice("\n", 0))
	m.ui_qr.hide()

	# ---- 5a the phone photo of the pose QR
	distort(q["png"], "user://qr/zz_r26_photo_pose.png")
	var ph := QrShare.read_png("user://qr/zz_r26_photo_pose.png")
	ok(bool(ph.get("ok", false)) and ph["text"] == txt, "phone-photo copy of the pose QR (0.5x, 5 deg, blur) still reads: %s" % ph.get("why", "same text"))

	# ---- 2b open: zero the body, open the picture, one undo step, Ctrl+Z
	for j in Body.ORDER:
		m.B.ang[j] = Vector3.ZERO
	m.B.offset = Vector3.ZERO
	m.B.fk()
	var n0: int = m.undo.size()
	var r: Dictionary = m._qr_open_file(q["png"])
	await idle(2)
	ok(bool(r.get("ok", false)) and m.undo.size() == n0 + 1, "Open from QR is ONE undo step (%d -> %d)" % [n0, m.undo.size()])
	var e2 := max_err(ang0, m.B.ang)
	ok(e2 <= 0.05 + 1e-4, "the opened pose equals the shared one: worst angle %.4f deg (bar 0.05)" % e2)
	m._undo()
	await idle(2)
	ok(max_err({}, m.B.ang) < 1e-6, "Ctrl+Z gives the zeroed body back (worst %.5f deg)" % max_err({}, m.B.ang))
	m._redo()
	await idle(2)

	# ---- 3 combo3 as a scene
	var cards0: Array = m.S.cards.duplicate(true)
	var view := QrShare.view_cards(cards0)
	var stxt := QrShare.pack_scene(m.S.name, m.S.fps, view)
	var cap := QrShare.capacity(stxt)
	print("     combo3: %d cards -> %d characters of %d (%d%%), %d cards would fit" % [cards0.size(), cap["chars"], QrShare.CAP_L, roundi(cap["pct"]), QrShare.max_cards(m.S.name, m.S.fps, view)])
	m._qr_share()   # scene mode is ticked by itself when it fits
	await idle(6)
	var sq: Dictionary = m.qr_last
	if cap["fits"]:
		ok(sq["kind"] == "scene" and bool(sq["ok"]), "combo3 fits one QR: %d characters, QR version %s level %s" % [sq["chars"], sq.get("version", "?"), sq.get("ecc", "?")])
		var sr: Dictionary = QrShare.read_png(sq["png"])
		ok(bool(sr.get("ok", false)) and sr["text"] == stxt, "the scene picture reads back as the same text")
		m.ui_qr.hide()
		# a new empty scene, then open the picture
		m.S.cards.clear()
		m._rebuild_cards()
		await idle(2)
		var n1: int = m.undo.size()
		var cnt0: int = m.S.cards.size()
		var r3: Dictionary = m._qr_open_file(sq["png"])
		await idle(2)
		ok(bool(r3.get("ok", false)) and m.S.cards.size() == cnt0 + cards0.size(), "Open from QR added %d cards (%d -> %d)" % [cards0.size(), cnt0, m.S.cards.size()])
		ok(m.undo.size() == n1 + 1, "the whole scene is ONE undo step (%d -> %d)" % [n1, m.undo.size()])
		var worst := 0.0
		var names_ok := true
		var timing_ok := true
		var got := QrShare.view_cards(m.S.cards.slice(cnt0))
		for i in cards0.size():
			worst = maxf(worst, max_err(view[i]["ang"], got[i]["ang"]))
			names_ok = names_ok and got[i]["name"] == view[i]["name"]
			timing_ok = timing_ok and absf(got[i]["move"] - view[i]["move"]) < 0.0051 and absf(got[i]["hold"] - view[i]["hold"]) < 0.0051
		ok(worst <= 0.05 + 1e-4, "all %d cards' angles within quantisation: worst %.4f deg (bar 0.05)" % [cards0.size(), worst])
		ok(names_ok and timing_ok, "card names and move / hold times are kept (to 0.01 s)")
		m._undo()
		await idle(2)
		ok(m.S.cards.size() == cnt0, "Ctrl+Z takes all %d cards out again (%d left)" % [cards0.size(), m.S.cards.size()])
		# 5b the phone photo of the scene QR
		distort(sq["png"], "user://qr/zz_r26_photo_scene.png")
		var ps := QrShare.read_png("user://qr/zz_r26_photo_scene.png")
		ok(bool(ps.get("ok", false)) and ps["text"] == stxt, "phone-photo copy of the scene QR (version %s, 0.5x, 5 deg, blur) reads: %s" % [sq.get("version", "?"), ps.get("why", "same text")])
	else:
		ok(not bool(sq["ok"]) and "too long for one QR" in sq["say"] and "Share the pose" in sq["say"], "combo3 is too long and says so with a next step: %s" % sq["say"].left(110))
		m.ui_qr.hide()
		print("     (5b skipped: combo3 does not fit)")

	# ---- 4 a scene that cannot fit
	m._load_scene("res://scenes/combo3.json")
	await idle(2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 26
	var big := []
	for i in 300:
		var ang := {}
		for j in Body.ORDER:
			ang[j] = Vector3(rng.randf_range(-90, 90), rng.randf_range(-40, 40), rng.randf_range(-40, 40))
		big.append({"name": "c%d" % i, "move": 0.2, "hold": 0.1, "ang": ang, "off": Vector3.ZERO})
	var bigtxt := QrShare.pack_scene("big", 30, big)
	ok(not QrShare.capacity(bigtxt)["fits"], "a 300-card busy scene is %d characters: over the %d" % [bigtxt.length(), QrShare.CAP_L])
	var fit := QrShare.max_cards("big", 30, big)
	ok(fit >= 1 and fit < 300, "max_cards says %d of 300 would fit one QR" % fit)
	var cards_keep: Array = m.S.cards
	m.S.cards = QrShare.to_scene_cards(big)
	m._qr_share()
	await idle(4)
	ok(m.ui_qr_scene.visible and not m.ui_qr_scene.button_pressed and "too long for one QR" in (m.ui_qr_info as Label).text, "a scene too long is not ticked; the popup shows the pose and says up front the scene is too long")
	m.ui_qr_scene.button_pressed = true
	await idle(4)
	var bq: Dictionary = m.qr_last
	ok(not bool(bq["ok"]) and bq["png"] == "" and "too long for one QR" in bq["say"] and "split" in bq["say"] and "Share the pose" in bq["say"], "refused with the next step: %s" % bq["say"].left(160))
	m.ui_qr.hide()
	m.S.cards = cards_keep

	print("r26: %d fails" % fails)
	quit(1 if fails > 0 else 0)
