## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/c16_test.gd     (C16, complaints 482 581; a window)
## BARS (written before the first run); files only in user://zz_c16_<pid>/:
##   L1 sidecar  <name>.licence.txt "CC-BY 4.0, by Ada" beside a clip: line contains "CC-BY 4.0, by Ada" and the note's file name.
##   L2 pack     a pose json with "licence":"CC0": line contains "CC0" and PosePack's own words for it.
##   L3 unknown  a clip with neither, a note saying "not given", and the bundled res://poses/lib/calm_easy.json:
##               all EXACTLY "licence not recorded" (CONTROL: none contains "CC" or "Licence:"; a line invented for them fails).
##   L4 dialog   the clip dialog's label clip_licence_line equals ClipLicence.line of the source picked, and changes when
##               another source is picked (two fixtures with different licences).
##   G1 closed   at boot guided_pose.step == -1 and the card is hidden; look/onboarded is NOT written by it (default unchanged).
##   G2 state    begin() shows step 0; 30 frames with no change stay on step 0 (CONTROL: a guide that auto-advances fails);
##               each real state change (body, sel, pose, cards, playing) advances exactly one step; the 6th ends it (step -1).
##   G3 skip     the Skip button closes the guide at once and onboarded is still not written.
##   G5 clear    at 1280x720 and 1600x900, at EVERY step (forced with _go(k)), the card is hidden or its rect (grown 2 px) intersects NO other
##               visible Button / Label / Range / LineEdit / TextureRect outside the card, and sits inside the window.
##               CONTROL: the old placement (right edge - 16, y 48) overlaps such a Control at 1280x720 at some step, so it would fail G5.
##   G4 menu     the palette registers "Guided first pose" (main.gd source) and the start screen file is unchanged by this item.
## Env C16_SHOT=<png> saves a 1280x720 shot of the guide card and of the clip dialog (C16_SHOT2).
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func wr(p: String, t: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(t)
	f.close()


func blockers(card: Node) -> Array:
	var out := []
	var st := [m.ui_root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n == card:
			continue
		for c in n.get_children():
			st.append(c)
		if n is Control and (n as Control).is_visible_in_tree() and (n is BaseButton or n is Label or n is Range or n is LineEdit or n is TextureRect):
			var r := (n as Control).get_global_rect()
			if r.size.x > 1.0 and r.size.y > 1.0:
				out.append(r)
	return out


func hits(card: Control, r: Rect2) -> int:
	var k := 0
	for b in blockers(card):
		if b.intersects(r.grow(2.0)):
			k += 1
	return k


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var dir := "user://zz_c16_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	wr(dir + "/a.json", "{}")
	wr(dir + "/a.licence.txt", "CC-BY 4.0, by Ada\nsource: x\n")
	wr(dir + "/b.json", JSON.stringify({"licence": "CC0"}))
	wr(dir + "/c.json", "{}")
	wr(dir + "/d.json", "{}")
	wr(dir + "/d.licence.txt", "licence: not given (the user's own file)\n")
	var la := ClipLicence.line(dir + "/a.json")
	ok(la.contains("CC-BY 4.0, by Ada") and la.contains("a.licence.txt"), "L1 sidecar: " + la)
	var lb := ClipLicence.line(dir + "/b.json")
	ok(lb.contains("CC0") and lb.contains(PosePack.LICENCE_SAY["CC0"]), "L2 pack: " + lb)
	var unk := [ClipLicence.line(dir + "/c.json"), ClipLicence.line(dir + "/d.json"), ClipLicence.line("poses/lib/calm_easy.json")]
	var allu := true
	for u in unk:
		allu = allu and u == "licence not recorded" and not u.contains("CC") and not u.contains("Licence:")
	ok(allu, "L3 unknown stays 'licence not recorded' %s" % [unk])
	# L4 dialog
	var cu: ClipsUI = m.clips_ui
	if cu == null:
		cu = ClipsUI.new(m)
		m.clips_ui = cu
	cu._build()
	cu._files = [dir + "/a.json", dir + "/b.json"]
	cu.ui_src.clear()
	for f in cu._files:
		cu.ui_src.add_item(f)
	cu.ui_src.select(0)
	cu.ui_src.item_selected.emit(0)
	var t0 := cu.ui_lic.text
	cu.ui_src.select(1)
	cu.ui_src.item_selected.emit(1)
	var t1 := cu.ui_lic.text
	ok(t0 == la and t1 == lb and t0 != t1, "L4 dialog line follows the picked source")
	# G
	var g: GuidedPose = m.guided_pose
	var cf := ConfigFile.new()
	cf.load(m.settings)
	var had := cf.has_section_key("look", "onboarded")
	ok(g.step == -1 and not g.card.visible, "G1 closed at boot")
	g.begin()
	for i in 30:
		await process_frame
	ok(g.step == 0 and g.card.visible, "G2 no change = stays on step 0")
	var body: Dictionary = (m.S.body as Dictionary).duplicate()
	body["stature"] = 1.9
	m.S.body = body
	await process_frame
	ok(g.step == 1, "G2 body change -> step 1 (%d)" % g.step)
	m.sel = "hand_l" if String(m.sel) != "hand_l" else "foot_l"
	await process_frame
	ok(g.step == 2, "G2 new part picked -> step 2 (%d)" % g.step)
	m.B.ang["upperarm_r"] = Vector3(40, 0, 0)
	await process_frame
	ok(g.step == 3, "G2 pose dragged -> step 3 (%d)" % g.step)
	m.sel = "head"
	m.B.ang["thigh_l"] = Vector3(30, 0, 0)
	await process_frame
	ok(g.step == 4, "G2 second part -> step 4 (%d)" % g.step)
	if OS.get_environment("C16_SHOT") != "":
		await process_frame
		root.get_texture().get_image().save_png(OS.get_environment("C16_SHOT"))
	m._card_add()
	await process_frame
	ok(g.step == 5, "G2 card added -> step 5 (%d)" % g.step)
	m.playing = true
	await process_frame
	ok(g.step == -1 and not g.card.visible, "G2 play ends the guide")
	m.playing = false
	g.begin()
	await process_frame
	var sk: Button = g.card.find_child("guided_pose_skip", true, false)
	sk.pressed.emit()
	ok(g.step == -1 and not g.card.visible, "G3 skip closes")
	cf = ConfigFile.new()
	cf.load(m.settings)
	ok(cf.has_section_key("look", "onboarded") == had, "G3/G1 onboarded flag untouched")
	var old_hits := 0
	for sz in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		root.size = sz
		await process_frame
		await process_frame
		var bad := 0
		for k in 6:
			g._go(k)
			for i in 3:
				await process_frame
			if g.card.visible:
				var r := Rect2(g.card.global_position, g.card.size)
				if hits(g.card, r) > 0 or not Rect2(Vector2.ZERO, Vector2(sz)).encloses(r):
					bad += 1
					print("  step %d overlaps %d at %s" % [k, hits(g.card, r), sz])
			if sz.x == 1280:
				var oldr := Rect2(Vector2(sz.x - g.card.size.x - 16.0, 48.0), g.card.size)
				old_hits += hits(g.card, oldr)
				if k == 2 and OS.get_environment("C16_SHOT") != "":
					root.get_texture().get_image().save_png(OS.get_environment("C16_SHOT").replace(".png", "_720.png"))
		ok(bad == 0, "G5 clear of every control at %s" % sz)
		g.finish(true)
	ok(old_hits > 0, "G5 control: the old placement overlaps controls at 1280x720 (%d)" % old_hits)
	if OS.get_environment("C16_SHOT2") != "":
		root.size = Vector2i(1280, 720)
		cu.ui_src.select(0)
		cu.ui_src.item_selected.emit(0)
		cu.dlg.popup_centered()
		for i in 5:
			await process_frame
		root.get_texture().get_image().save_png(OS.get_environment("C16_SHOT2"))
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	ok(src.contains("\"Guided first pose\""), "G4 palette command registered")
	print("c16: %d fail" % fails)
	quit(1 if fails > 0 else 0)
