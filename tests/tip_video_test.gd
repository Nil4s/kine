## godot --path . -s tests/tip_video_test.gd     (ROADMAP 49; needs a window)
## TOOLTIP VIDEOS: a ribbon button with a clip, hovered 0.6 s, shows a panel looping a 2 s clip of the tool. Bars, before measuring:
##   1 assets/tips: >= 12 clips, every sheet a whole number of 320x200 frames (30 per clip, 15 fps = 2 s), total under 6 MB
##   2 hover 3 buttons (Mirror, Onion, Check; each on its own tab): at 0.3 s no panel; at 0.7 s the panel shows that button's
##     clip; over the next 0.5 s the frame index takes >= 5 different values (15 fps: 7 or 8 expected) and the picture changes
##   3 Reset body (no clip): after 0.9 s no panel, its text tooltip untouched
##   4 mouse out: the panel is gone the same frame, and a different button then shows its own clip
##   5 a REAL mouse on the button (motion events, not a signal): the engine's text tooltip is parked while it hovers
##     (tooltip_text empty, the panel carries the words) and is back after the mouse leaves
## TIPV_SHOT=<path.png>: a picture of the window with a tip mid-clip
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func wait(sec: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < int(sec * 1000.0):
		await process_frame


func tab(name: String) -> void:
	for b in m.ui_root.find_children("*", "Button", true, false):
		if m.label_of(b) == name and b.is_visible_in_tree():
			b.pressed.emit()
	await idle(3)


func btn(label: String) -> Button:
	for b in m.ui_root.find_children("*", "Button", true, false):
		if m.label_of(b) == label:
			return b
	return null


func region_x(t: TipVideo) -> int:
	return int((t.rect.texture as AtlasTexture).region.position.x) + 10000 * int((t.rect.texture as AtlasTexture).region.position.y)


func _init() -> void:
	var man := TipVideo.load_manifest()
	var ids: Array = man.get("clips", {}).keys()
	var bad := []
	for id in ids:
		var c: Dictionary = man["clips"][id]
		var img := Image.load_from_file(ProjectSettings.globalize_path(TipVideo.DIR + String(c["sheet"])))
		var rows := int(ceil(float(c["frames"]) / float(c["cols"])))
		if img == null or img.get_width() != int(c["cols"]) * 320 or img.get_height() != rows * 200 or int(c["frames"]) != 30:
			bad.append(id)
	var bytes := TipVideo.dir_bytes()
	print("     assets/tips: %d clips, %.2f MB (%d bytes)" % [ids.size(), bytes / 1048576.0, bytes])
	ok(ids.size() >= 12 and bad.is_empty() and int(man["fps"]) == 15 and bytes < 6 * 1048576,
		"1 %d clips, every sheet a whole number of 320x200 frames, 30 each at 15 fps (bad: %s); assets %.2f MB (bar 6)" % [ids.size(), bad, bytes / 1048576.0])

	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var tv: TipVideo = m.tips
	var cases := [["POSE", "Mirror pose (Shift+M)", "mirror"], ["ANIMATE", "Onion (O)", "onion"], ["CHECK", "Check", "critique"]]
	var shot_done := false
	for cs in cases:
		await tab(cs[0])
		var b := btn(cs[1])
		b.mouse_entered.emit()
		await wait(0.3)
		var early: bool = tv.panel.visible
		await wait(0.4)
		var shown: bool = tv.panel.visible and tv.shown_id == cs[2]
		var seen := {}
		var pix := {}
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 500:
			seen[tv.frame] = true
			pix[region_x(tv)] = true
			await process_frame
		if not shot_done and OS.get_environment("TIPV_SHOT") != "":
			shot_done = true
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("TIPV_SHOT"))
			print("     shot: %s" % OS.get_environment("TIPV_SHOT"))
		ok(not early and shown and seen.size() >= 5 and pix.size() >= 5 and tv.title.text == cs[1],
			"2 %s: none at 0.3 s (%s), the '%s' clip at 0.7 s (%s, title '%s'); over 0.5 s %d frame indices %s, %d different pictures" % [cs[1], early, cs[2], shown, tv.title.text, seen.size(), seen.keys(), pix.size()])
		b.mouse_exited.emit()
		await process_frame
		ok(not tv.panel.visible, "4 %s: mouse out, the panel is gone" % cs[1])

	await tab("POSE")
	var rb := btn("Reset body")
	var txt := rb.tooltip_text
	rb.mouse_entered.emit()
	await wait(0.9)
	ok(not tv.panel.visible and rb.tooltip_text == txt and txt != "", "3 Reset body (no clip): after 0.9 s no panel, text tooltip untouched ('%s')" % txt.get_slice("\n", 0))
	rb.mouse_exited.emit()

	var mb := btn("Mirror pose (Shift+M)")
	var c := mb.get_global_rect().get_center()
	var tip0 := mb.tooltip_text
	for p in [c + Vector2(-60, 0), c]:
		var e := InputEventMouseMotion.new()
		e.position = p
		e.global_position = p
		root.push_input(e)
		await process_frame
	await wait(0.75)
	var parked := mb.tooltip_text == "" and tv.panel.visible and tv.body.text.length() > 8
	var e2 := InputEventMouseMotion.new()
	e2.position = Vector2(800, 400)
	e2.global_position = e2.position
	root.push_input(e2)
	await idle(2)
	ok(parked and not tv.panel.visible and mb.tooltip_text == tip0 and tip0 != "",
		"5 a real mouse on Mirror: its text parked and the panel up with the words (%s); moved away: the panel gone, the text back (%s)" % [parked, mb.tooltip_text == tip0])
	print("TIP VIDEO TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
