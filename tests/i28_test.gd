## godot --path . -s tests/i28_test.gd     (ROADMAP I28: the safety sheet, scripts/safety_sheet.gd + safety_ui.gd; needs a window)
## The scene: two fighters (the second stands still, facing the hero); the hero swings a free bat (tip along +z, bat pointing at the other fighter):
##   A  at ~1 s a real CONTACT: the tip lands on the other's chest at 6 m/s (the move time is bisected on Dummy.fighter_hits' own speed)
##   B  a TIP PASS: the tip sweeps sideways in front of the other's face, its closest point 8 cm from the head capsule's surface
##   C  a CLEAN strike (marked "hit"): the tip stops 30 cm short of the chest
## Bars, written before measuring:
##  (1) exactly 2 items (the contact and the tip pass; the clean strike gives none, the pass is not also a "close pass")
##  (2) the contact: red; time within 1 frame of the first 240 Hz sample where the hero's bat touches (Body.cross_contacts); number 6.0 +- 0.5 m/s,
##      and the same bat tip's speed over the 1/240 s before that time (a rigid bat moving along its axis: every point has the tip's speed) within 0.8 m/s of it
##  (3) the tip pass: red (8 < 10 cm); time within 1 frame of the closest instant found by a 240 Hz scan of my own (tip to the head capsule),
##      number within 0.5 cm of that scan's minimum and 8.0 +- 0.6 cm
##  (4) the page: written under user:// (name has the PID), exists, holds both items' texts and EXACTLY 2 <img> with data: URIs, is self-contained
##      (no http / external file), the scene's cards and markers JSON are byte-identical before and after
##  (5) placement: each thumbnail shows the fighters (>= 2 % of its pixels are body-coloured) and a red marker (>= 20 pixels of marker red),
##      two thumbnails of the same frame are identical (fixed camera), thumbnails of the two items differ
##  (6) the panel: a row per item, a click moves the playhead to the item within 1 frame
##  (7) combo3: the panel opens on the real scene (screenshot tmp/i28.png)
extends SceneTree

const TMP := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/"
var fails := 0
var m: Node
var HX := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1.5))


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func body() -> Body:
	return DistanceKeeper.new_body()


func stand() -> Dictionary:
	var b := body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b.to_dict()


## the hero's pose with the free bat pointing along +z, its tip at p
func bat(p: Vector3) -> Dictionary:
	var b := body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	b.wep_on = true
	b.wep_hand = ""
	b.wep_pos = p - Vector3(0, 0, 1) * b.wep_len
	b.wep_rot = Quaternion(Vector3.UP, Vector3(0, 0, 1))
	return b.to_dict()


func hero(move1: float, head_z: float, head_y: float) -> Scene:
	var cards := [
		{"name": "a", "pose": bat(Vector3(0.0, 1.25, 0.6)), "move": -1.0, "hold": 0.5},
		{"name": "b", "pose": bat(Vector3(0.0, 1.25, 1.56)), "move": move1, "hold": 0.3},
		{"name": "c", "pose": bat(Vector3(0.0, 1.25, 0.6)), "move": 0.6, "hold": 0.8},
		{"name": "d", "pose": bat(Vector3(0.6, head_y, head_z)), "move": 0.5, "hold": 0.0},
		{"name": "e", "pose": bat(Vector3(-0.6, head_y, head_z)), "move": 1.2, "hold": 0.2},
		{"name": "f", "pose": bat(Vector3(0.0, 1.25, 0.6)), "move": 0.6, "hold": 1.0},
		{"name": "g", "pose": bat(Vector3(0.0, 1.25, 1.08)), "move": 0.5, "hold": 0.6}]
	var s := Scene.new()
	s.from_dict({"scene": "zz_i28", "fps": 30, "cards": cards})
	var ts := s.times()
	s.markers = [{"t": float(ts[1][1]), "name": "hit", "kind": "hit"}, {"t": float(ts[6][1]), "name": "hit", "kind": "hit"}]
	return s


func other() -> Scene:
	var s := Scene.new()
	var p := stand()
	s.from_dict({"scene": "zz_other", "fps": 30, "cards": [{"name": "a", "pose": p, "move": -1.0, "hold": 2.0}, {"name": "b", "pose": p, "move": 0.5, "hold": 6.0}]})
	return s


func contact_speed(S: Scene, O: Scene) -> float:
	var hs := Dummy.fighter_hits(S.clone(), body(), O.clone(), body(), HX, 30)
	for h in hs:
		if h["by"] == "hero":
			return float(h["speed"])
	return -1.0


func jsn(S: Scene) -> String:
	return JSON.stringify([S.cards, S.markers])


func reds(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.r > 0.85 and c.g < 0.3 and c.b < 0.3:
				n += 1
	return n


## the share of pixels that are a body (chromatic: the backdrop and the floor are grey) and not the red marker
func differ(img: Image) -> float:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var sp := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			if sp > 0.12 and not (c.r > 0.85 and c.g < 0.3 and c.b < 0.3):
				n += 1
	return float(n) / float(img.get_width() * img.get_height())


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var O := other()
	# the head of the other fighter: the pass line sits 8 cm outside its capsule's surface, facing the hero
	var BD := body()
	O.apply(BD, 0.0)
	var hc: Array = BD.cap("head")
	var ha: Vector3 = HX * (hc[0] as Vector3)
	var hb: Vector3 = HX * (hc[1] as Vector3)
	var hr: float = BD.rad["head"]
	var hy := (ha.y + hb.y) * 0.5
	var head_z := ha.z - (hr + 0.08)
	# (A) tune the move time for 6 m/s
	var mv := 0.2
	var bd := INF
	for i in 70:   # (the speed is read between two frames, so it is not monotonic in the move time: scan, keep the closest to 6)
		var cand := 0.08 + 0.01 * i
		var d := absf(contact_speed(hero(cand, head_z, hy), O) - 6.0)
		if d < bd:
			bd = d
			mv = cand
	var H := hero(mv, head_z, hy)
	print("     tuned move %.3f s -> Dummy speed %.2f m/s, head y %.3f z %.3f r %.3f" % [mv, contact_speed(H, O), hy, head_z, hr])
	var before := jsn(H) + jsn(O)
	var names := ["the hero", "fighter 2"]
	var rep := SafetySheet.analyze([H, O], names, [Transform3D.IDENTITY, HX], 30)
	var items: Array = rep["items"]
	for it in items:
		print("     %s %.3f s f%d %s | %s" % [it["sev"], it["t"], it["frame"], it["kind"], it["text"]])
	ok(items.size() == 2 and items[0]["kind"] == "contact" and items[1]["kind"] == "tip", "(1) exactly 2 items: contact then tip pass (%d: %s)" % [items.size(), ", ".join(items.map(func(i): return i["kind"]))])
	if items.size() != 2:
		TestFiles.cleanup()
		quit(1)
		return
	# (2) the contact
	var c: Dictionary = items[0]
	var B1 := body()
	var t_touch := -1.0
	for k in int(H.length() * 240.0):
		var t := float(k) / 240.0
		H.apply(B1, t)
		O.apply(BD, t)
		if not B1.cross_contacts(BD, HX).is_empty():
			t_touch = t
			break
	var Bp := body()
	H.apply(Bp, float(c["t"]) - 1.0 / 240.0)
	var p0: Vector3 = Bp.wep_point(Bp.wep_len)
	H.apply(Bp, float(c["t"]))
	var fd := p0.distance_to(Bp.wep_point(Bp.wep_len)) * 240.0
	ok(c["sev"] == "red" and absf(float(c["t"]) - t_touch) <= 1.0 / 30.0 + 1e-6 and absf(float(c["num"]) - 6.0) <= 0.5 and absf(fd - float(c["num"])) <= 0.8,
		"(2) contact red, t %.3f vs first touch %.3f s (+-1 frame), %.2f m/s (6.0 +- 0.5), tip speed over the 1/240 s before %.2f" % [c["t"], t_touch, c["num"], fd])
	# (3) the tip pass
	var tp: Dictionary = items[1]
	var best := INF
	var best_t := 0.0
	for k in int(H.length() * 240.0):
		var t := float(k) / 240.0
		H.apply(B1, t)
		O.apply(BD, t)
		var cc: Array = BD.cap("head")
		var d := DistanceKeeper._seg_dist(B1.wep_point(B1.wep_len), HX * (cc[0] as Vector3), HX * (cc[1] as Vector3)) - float(BD.rad["head"])
		if d < best and t > 2.0:
			best = d
			best_t = t
	ok(tp["sev"] == "red" and absf(float(tp["t"]) - best_t) <= 1.0 / 30.0 + 1e-6 and absf(float(tp["num"]) - best * 100.0) <= 0.5 and absf(float(tp["num"]) - 8.0) <= 0.6,
		"(3) tip pass red, t %.3f vs scan %.3f s, %.2f cm vs scan %.2f cm (8.0 +- 0.6)" % [tp["t"], best_t, tp["num"], best * 100.0])
	# (4) the page
	var ui := SafetyUI.new(m)
	ui.forced = {"scenes": [H, O], "names": names, "xfs": [Transform3D.IDENTITY, HX]}
	ui.compute()
	var dir := "user://i28_%d" % OS.get_process_id()
	var path: String = await ui.write_page(m, dir)
	var html := FileAccess.get_file_as_string(path) if path != "" else ""
	var nimg := html.count("<img ")
	ok(path != "" and FileAccess.file_exists(path) and html.contains(String(items[0]["text"]).replace("&", "&amp;")) and html.contains(String(items[1]["text"])) and nimg == 2 and html.count("src=\"data:image/png;base64,") == 2
		and not html.contains("http://") and not html.contains("https://") and jsn(H) + jsn(O) == before,
		"(4) the page %s holds both items, %d <img> as data: URIs, self-contained; the scene JSON is untouched" % [path.get_file(), nimg])
	# (5) placement
	var r0 := reds(ui.imgs[0])
	var r1 := reds(ui.imgs[1])
	var d0 := differ(ui.imgs[0])
	var d1 := differ(ui.imgs[1])
	var g2 := {"scenes": [H.clone(), O.clone()], "names": names, "xfs": [Transform3D.IDENTITY, HX]}
	var again: Image = await ui.draw(m, g2, [body(), body()], float(items[0]["t"]), items[0]["at"])
	var same := again.get_data() == (ui.imgs[0] as Image).get_data()
	var diff_items := (ui.imgs[0] as Image).get_data() != (ui.imgs[1] as Image).get_data()
	ok(d0 >= 0.02 and d1 >= 0.02 and r0 >= 20 and r1 >= 20 and same and diff_items,
		"(5) thumbnails: bodies %.1f / %.1f %% of the pixels, marker red %d / %d px, same frame redrawn identical, the two items differ" % [d0 * 100.0, d1 * 100.0, r0, r1])
	(ui.imgs[0] as Image).save_png(TMP + "i28_thumb0.png")
	(ui.imgs[1] as Image).save_png(TMP + "i28_thumb1.png")
	# (6) the panel
	ui._panel()
	await idle()
	var b1: Button = m.ui_find_list.find_child("sf_item_1", true, false)
	var rows: int = m.ui_find_list.find_children("sf_item_*", "Button", true, false).size()
	m.playhead = 0.0
	if b1 != null:
		b1.pressed.emit()
	ok(rows == 2 and b1 != null and absf(m.playhead - float(items[1]["t"])) <= 1.0 / 30.0 + 1e-6, "(6) the panel lists %d items; a click puts the playhead at %.3f s (item at %.3f)" % [rows, m.playhead, items[1]["t"]])
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	# (7) combo3
	ui = SafetyUI.new(m)
	m.sf_ui = ui
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, 1.1], "yaw": 180.0}, "scene": other()})
	m._actors_sync()
	m._refresh()
	await idle()
	ui.show()
	await ui.render_thumbs(m)
	ui._panel()
	await idle(5)
	for it in ui.rep["items"]:
		print("     combo3 %s %.2f s %s" % [it["sev"], it["t"], it["text"]])
	if ui.rep["items"].size() > 0:
		ui.jump(0)
	await idle(5)
	root.get_texture().get_image().save_png(TMP + "i28.png")
	ok(m.ui_find.visible and ui.rep.has("items"), "(7) the panel is up on combo3 with %d items (screenshot i28.png)" % ui.rep["items"].size())
	var hp: String = await ui.write_page(m, "user://i28_%d" % OS.get_process_id())
	var fh := FileAccess.open(TMP + "i28.html", FileAccess.WRITE)
	fh.store_string(FileAccess.get_file_as_string(hp))
	fh.close()
	DirAccess.remove_absolute(hp)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://i28_%d" % OS.get_process_id()))
	print("i28: %d failures" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
