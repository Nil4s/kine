## godot --path . -s tests/playblast_test.gd     (GATES WW6; needs a window: the frames are read back from the screen)
## A 0.5 s two-card scene is played blast at 30 fps three ways: PNGs with no burn-in, PNGs with it, and an MJPEG AVI.
## Burn-in: the saved frame differs from the plain one inside the burn-in box and matches it outside (small tolerance).
## AVI: RIFF/AVI headers parse, frame count = ceil(length * fps) + 1 (the recorder's own rule), every frame is a JPEG
## (FFD8 ... FFD9) of the viewport's size, the header's frame count and idx1 agree, and the frames look like the PNGs.
extends SceneTree

var fails := 0
var m: Node
const DIR := "C:/Temp/zz_playblast"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func pose(thigh: float) -> Dictionary:
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.set_ang("thigh_l", Vector3(thigh, 0, 0))
	R.fk()
	return R.to_dict()


## [pixels inside the burn-in box that differ, pixels outside that differ by more than tol, biggest outside diff]
func compare(a: Image, b: Image, tol: float) -> Array:
	var inside := 0
	var outside := 0
	var worst := 0.0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b)))
			if Playblast.AREA.has_point(Vector2i(x, y)):
				if d > tol:
					inside += 1
			else:
				worst = maxf(worst, d)
				if d > tol:
					outside += 1
	return [inside, outside, worst]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S := Scene.new()
	S.name = "zz_playblast"
	S.add("a", pose(0))
	S.add("b", pose(60))
	S.cards[0]["move"] = 0.2
	S.cards[0]["hold"] = 0.1
	S.cards[1]["move"] = 0.2
	S.cards[1]["hold"] = 0.2
	m.S = S
	m._rebuild_cards()
	m._refresh()
	await idle(2)
	DirAccess.make_dir_recursive_absolute(DIR + "/plain")
	DirAccess.make_dir_recursive_absolute(DIR + "/burn")
	var fps := 30
	var len: float = m._ps().length()
	var want := int(ceil(len * fps)) + 1
	ok(len > 0.3 and len < 0.7, "the scene is %.3f s long (bar: about 0.5 s)" % len)

	var n0: int = await m._record(DIR + "/plain", fps, false, "")
	var n1: int = await m._record(DIR + "/burn", fps, true, DIR + "/out.avi")
	ok(n0 == want and n1 == want, "frames recorded plain %d, burned %d (bar: ceil(len*fps)+1 = %d)" % [n0, n1, want])

	# BURN-IN: read the saved PNGs back
	var worst_in := 1 << 30
	var worst_out := 0
	var worst_diff := 0.0
	for f in [0, want / 2, want - 1]:
		var a := Image.load_from_file("%s/plain/frame_%04d.png" % [DIR, f])
		var b := Image.load_from_file("%s/burn/frame_%04d.png" % [DIR, f])
		ok(a != null and b != null and a.get_size() == b.get_size(), "frame %d saved both ways, %s" % [f, a.get_size() if a != null else "missing"])
		if a == null or b == null:
			continue
		var r := compare(a, b, 0.02)
		worst_in = mini(worst_in, r[0])
		worst_out = maxi(worst_out, r[1])
		worst_diff = maxf(worst_diff, r[2])
		ok(r[0] > 300, "  frame %d: %d pixels in the burn-in box differ from the plain frame (bar: > 300)" % [f, r[0]])
		ok(r[1] == 0, "  frame %d: %d pixels outside the box differ by more than 2/255; biggest %.4f (bar: 0)" % [f, r[1], r[2]])
	var b0 := Image.load_from_file("%s/burn/frame_0000.png" % DIR)
	var bl := Image.load_from_file("%s/burn/frame_%04d.png" % [DIR, want - 1])
	var box0 := b0.get_region(Playblast.AREA)
	var boxl := bl.get_region(Playblast.AREA)
	var changed := 0
	for y in box0.get_height():
		for x in box0.get_width():
			if box0.get_pixel(x, y) != boxl.get_pixel(x, y):
				changed += 1
	ok(changed > 30, "the burn-in text changes between the first and last frame: %d pixels (bar: > 30)" % changed)
	ok(Playblast.text("zz", 12, 0.4, 3) == "zz   frame 0012   0.40 s   check: 3", "burn-in text: '%s'" % Playblast.text("zz", 12, 0.4, 3))

	# AVI
	var avi := Playblast.read_avi(DIR + "/out.avi")
	ok(not avi.is_empty(), "RIFF 'AVI ' headers parse")
	if avi.is_empty():
		print("PLAYBLAST TEST FAIL %d" % fails)
		TestFiles.cleanup()
		quit(fails)
		return
	var fr: Array = avi["frames"]
	ok(avi["riff_size"] == avi["size"] - 8, "RIFF size %d = file %d - 8" % [avi["riff_size"], avi["size"]])
	ok(fr.size() == want, "AVI holds %d frames (bar: %d)" % [fr.size(), want])
	ok(avi["avih_frames"] == want and avi["idx"] == want, "header says %d frames, idx1 lists %d (bar: %d)" % [avi["avih_frames"], avi["idx"], want])
	ok(avi["us"] == 1000000 / fps, "%d us per frame (bar: %d)" % [avi["us"], 1000000 / fps])
	var vp := Vector2i(b0.get_width(), b0.get_height())
	ok(avi["w"] == vp.x and avi["h"] == vp.y, "header size %dx%d = the frames' %dx%d" % [avi["w"], avi["h"], vp.x, vp.y])
	var bad := 0
	var sized := 0
	var drift := 0.0
	for f in fr.size():
		var j: PackedByteArray = fr[f]
		if not (j.size() > 4 and j[0] == 0xFF and j[1] == 0xD8 and j[j.size() - 2] == 0xFF and j[j.size() - 1] == 0xD9):
			bad += 1
		var im := Image.new()
		if im.load_jpg_from_buffer(j) == OK and im.get_size() == vp:
			sized += 1
			if f == fr.size() / 2:
				var ref := Image.load_from_file("%s/burn/frame_%04d.png" % [DIR, f])
				var tot := 0.0
				for y in range(0, vp.y, 7):
					for x in range(0, vp.x, 7):
						tot += absf(im.get_pixel(x, y).r - ref.get_pixel(x, y).r)
				drift = tot / (float(vp.y / 7) * float(vp.x / 7))
	ok(bad == 0, "%d of %d frames lack FFD8...FFD9 (bar: 0)" % [bad, fr.size()])
	ok(sized == fr.size(), "%d of %d frames decode at %dx%d (bar: all)" % [sized, fr.size(), vp.x, vp.y])
	ok(drift < 0.02, "the middle JPEG frame matches its PNG: mean red error %.4f (bar: < 0.02)" % drift)

	# clean up: delete every output
	for sub in ["plain", "burn"]:
		for f in DirAccess.get_files_at(DIR + "/" + sub):
			DirAccess.remove_absolute("%s/%s/%s" % [DIR, sub, f])
		DirAccess.remove_absolute(DIR + "/" + sub)
	DirAccess.remove_absolute(DIR + "/out.avi")
	DirAccess.remove_absolute(DIR)
	ok(not DirAccess.dir_exists_absolute(DIR), "outputs deleted")
	print("PLAYBLAST TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
