## godot --path . -s tests/r15_test.gd     (needs a window)
## R15: IMPORT A PHYSICS REACTION. tools/physics/samples/hit_fall.bvh (python tools/physics/export.py: chest 40 N s, the body
## steps twice and falls) comes in through the app's command (main._import_physics, what "Import physics reaction..." and
## poser_cli's physics=<file> run). BARS (written before measuring), at 10 sample times spread over the 2.0 s clip, against
## the export read by BvhImport at every sim frame (the truth):
##  1 every joint's rotation within 2 deg (BvhExport.rt_err, wrap-proof), at all 10 times
##  2 the root (offset) within 1 cm at all 10 times
##  3 soles never below the floor: the lowest sole over 400 sample times >= -2 mm
##  4 the fall reads as a fall: the pelvis is above 0.8 m at the start and below 0.4 m at the end
##  5 key cards, not a card per frame: 120 frames -> fewer than 70 cards
##  6 policy: a NEW scene in scenes/_wip (the open one is untouched, the file exists), the status line says so
##  7 PLACEMENT: mid-fall with the card strip, the whole body on screen, the pelvis in the viewport and lower than at the start
extends SceneTree

var fails := 0
var m: Node
const SRC := "res://tools/physics/samples/hit_fall.bvh"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(2)
	root.get_window().size = Vector2i(1600, 900)
	await idle(6)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	var before := JSON.stringify(m.S.to_dict(m.B), "", true)
	var path_before: String = m.scene_path
	var out: String = m._import_physics(SRC)
	await idle(4)
	ok(out != "" and out.begins_with("res://scenes/_wip/") and FileAccess.file_exists(out) and m.scene_path == out and path_before != out, "6 a NEW scene in scenes/_wip: %s (the status: %s)" % [out, String(m.ui_status.text).left(120)])
	ok(FileAccess.get_file_as_string(path_before) != "" and JSON.stringify(m.S.to_dict(m.B), "", true) != before, "6b the open scene was replaced by the import, combo3's file untouched")
	var bv := BvhImport.load_file(SRC)
	var Bt := Body.new()
	Bt.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var truth: Scene = BvhImport.to_scene(bv, Bt, 1, 1.0, "truth")["scene"]
	truth.free_limits = true   # the export as simulated, unclamped
	var dt: float = bv["dt"]
	var n: int = bv["frames"].size()
	var S: Scene = m.S
	ok(n == 120 and S.cards.size() < 70, "5 %d sim frames -> %d key cards (bar < 70)" % [n, S.cards.size()])
	var worst_deg := 0.0
	var worst_off := 0.0
	var at := ""
	for k in 10:
		var f := int(round((k + 0.5) / 10.0 * (n - 1)))
		truth.apply(Bt, f * dt)
		var q0 := {}
		for j in Body.ORDER:
			q0[j] = Bt.compose(j, Bt.ang[j])
		var off0: Vector3 = Bt.offset
		S.apply(m.B, f * dt)
		worst_off = maxf(worst_off, (m.B.offset - off0).length())
		for j in Body.ORDER:
			var e := BvhExport.rt_err(q0[j], m.B.compose(j, m.B.ang[j]))
			if e > worst_deg:
				worst_deg = e
				at = "%s at %.2f s" % [j, f * dt]
	ok(worst_deg <= 2.0, "1 worst joint rotation difference over 10 times x all joints: %.3f deg (bar 2) at %s" % [worst_deg, at])
	ok(worst_off <= 0.01, "2 worst root difference %.2f cm (bar 1)" % (worst_off * 100.0))
	var low := 0.0
	for i in 400:
		S.apply(m.B, S.length() * i / 399.0)
		low = minf(low, PhysImport.sole_y(m.B))
	ok(low >= -0.002, "3 lowest sole over the clip %.1f mm (bar >= -2)" % (low * 1000.0))
	S.apply(m.B, 0.0)
	var h0: float = m.B.P["pelvis"].y
	S.apply(m.B, S.length())
	var h1: float = m.B.P["pelvis"].y
	ok(h0 > 0.8 and h1 < 0.4, "4 the pelvis %.2f m at the start, %.2f m at the end (bars > 0.8, < 0.4)" % [h0, h1])
	# 7 placement: mid-fall, whole window
	m._page_set("ANIMATE", false)
	await idle(3)
	m._rebuild_cards()
	await m.thumbs.settle()
	var t_mid := S.length() * 0.55
	m.playhead = t_mid
	m._ps().apply(m.B, t_mid)
	m._refresh()
	await idle(6)
	var hm: float = m.B.P["pelvis"].y
	var strip_ok: bool = m.ui_cards != null and m.ui_cards.get_child_count() >= 5 and m.ui_cards.is_visible_in_tree()
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var inside := true
	if cam != null:
		var vp := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
		for j in ["head", "pelvis", "foot_l", "foot_r", "hand_l", "hand_r"]:
			var sp := cam.unproject_position(m.B.P[j])
			inside = inside and vp.has_point(sp)
	ok(hm < h0 - 0.1 and hm > h1 - 0.05 and strip_ok and inside, "7 mid-fall t=%.2f s: pelvis %.2f m (start %.2f, end %.2f), card strip shown (%d cards), head/pelvis/hands/feet on screen: %s" % [t_mid, hm, h0, h1, m.ui_cards.get_child_count(), inside])
	var img := root.get_texture().get_image()
	img.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/r15.png")
	if out != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(out))
	print("r15: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit(0 if fails == 0 else 1)
