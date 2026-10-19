## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/pose_library_test.gd     (GAP_ANALYSIS row 8; a window)
## THE POSE LIBRARY (scripts/pose_library.gd) on the real poser, with its own poses in user://zz_poselib_<pid>/ (never
## poses/ or moves/: their file lists and md5s are compared before and after):
##   thumbnails  one .png per pose, next to it, with the mannequin in it (not the bare backdrop), two poses -> two
##               different pictures; a pose file rewritten -> its picture is made again and its bytes change
##   apply       every joint = the library pose within 0.01 deg (quaternion angle), the hips too; ONE undo step; Ctrl+Z back
##   blend       0 % = the body as it was, 50 % = the per-joint slerp midpoint, 100 % = the library pose (0.01 deg);
##               the release is ONE undo step; also by a real mouse drag on a thumbnail (80 px = 50 %)
##   flipped     = Mirror pose of the plain apply (0.01 deg), hips' x reflected; one undo step
##   selected    with Only the selected parts on: those parts = the pose, every other joint and the hips bit for bit
## Env POSELIB_SHOT=<png>: also renders Nick's library in memory and saves a screenshot of the grid there.
extends SceneTree

var fails := 0
var m: Node
var lib: PoseLibrary
var dir := ""


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## degrees between joint j's turn at angles a and at b
func qerr(j: String, a: Vector3, b: Vector3) -> float:
	return qang(m.B.compose(j, a), m.B.compose(j, b))


## the angle between two turns from the vector part of their difference (the acos of a dot product near 1, as
## Quaternion's own angle function takes, reads up to 0.05 deg for two equal turns in single precision)
func qang(a: Quaternion, b: Quaternion) -> float:
	var d := a.inverse() * b
	return rad_to_deg(2.0 * asin(minf(1.0, Vector3(d.x, d.y, d.z).length())))


## the worst per-joint error of the body now against want (joints in `only`, [] = all) -> [deg, joint]
func worst(want: Dictionary, only := []) -> Array:
	var w := 0.0
	var at := ""
	for j in Body.ORDER:
		if not only.is_empty() and not j in only:
			continue
		var e := qerr(j, m.B.ang[j], want[j])
		if e > w:
			w = e
			at = j
	return [w, at]


func nick_files() -> Dictionary:
	var out := {}
	for d in ["res://poses", "res://poses/lib", "res://moves"]:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			out[d + "/" + f] = FileAccess.get_md5(d + "/" + f)
	return out


func write_pose(nm: String, d: Dictionary) -> String:
	var p := dir + "/" + nm + ".json"
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, " "))
	f.close()
	return p


## a pose dictionary: the body at these angles (rest elsewhere), offset o
func pose_dict(angs: Dictionary, o := Vector3.ZERO) -> Dictionary:
	var keep: Dictionary = m.B.state()
	for j in Body.ORDER:
		m.B.ang[j] = Vector3.ZERO
	for j in angs:
		m.B.ang[j] = m.B.clamp_ang(j, angs[j])
	m.B.offset = o
	m.B.fk()
	var d: Dictionary = m.B.to_dict()
	m.B.set_state(keep)
	return d


## share of the picture's pixels that are not the backdrop
func ink(img: Image) -> float:
	var n := 0
	var bg := PoseLibrary.BG
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > 0.12:
				n += 1
	return float(n) / float((img.get_width() / 2) * (img.get_height() / 2))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var before := nick_files()
	dir = "user://zz_poselib_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var pa := write_pose("reach", pose_dict({"upperarm_r": Vector3(80, 30, 20), "lowerarm_r": Vector3(70, 0, 0), "upperarm_l": Vector3(-20, 10, 0),
		"thigh_l": Vector3(45, 0, 0), "calf_l": Vector3(-60, 0, 0), "spine_02": Vector3(15, 8, 12), "head": Vector3(0, 0, 25)}, Vector3(0.03, -0.05, 0.02)))
	var pb := write_pose("crouch", pose_dict({"thigh_l": Vector3(90, 0, 0), "thigh_r": Vector3(90, 0, 0), "calf_l": Vector3(-110, 0, 0),
		"calf_r": Vector3(-110, 0, 0), "upperarm_l": Vector3(60, 0, 0), "upperarm_r": Vector3(60, 0, 0)}, Vector3(0, -0.35, 0)))
	lib = PoseLibrary.new()
	lib.m = m
	lib.name = "pose_library"
	lib.dirs = [dir]
	m.ui_root.add_child(lib)
	m.set_meta("pose_library", lib)
	await lib.settle()

	# ---- thumbnails
	ok(lib.cells.size() == 2, "the grid has a cell per pose (%d)" % lib.cells.size())
	var ta := PoseLibrary.thumb_path(pa)
	var tb := PoseLibrary.thumb_path(pb)
	ok(FileAccess.file_exists(ta) and FileAccess.file_exists(tb), "a thumbnail next to each pose: %s, %s" % [ta.get_file(), tb.get_file()])
	var ia := Image.load_from_file(ProjectSettings.globalize_path(ta))
	var ib := Image.load_from_file(ProjectSettings.globalize_path(tb))
	ok(ia.get_size() == PoseLibrary.THUMB, "  %dx%d px" % [ia.get_width(), ia.get_height()])
	var ka := ink(ia)
	ok(ka > 0.03 and ka < 0.6, "  the mannequin is in the picture (%.1f %% of the pixels are not the backdrop)" % (ka * 100.0))
	var md_a := FileAccess.get_md5(ta)
	ok(md_a != FileAccess.get_md5(tb), "  two poses, two different pictures")
	var r0 := lib.renders
	await lib.settle()
	ok(lib.renders == r0 and FileAccess.get_md5(ta) == md_a, "  nothing changed: nothing rendered again")
	var shown: Texture2D = (lib.cells[pa].find_child("thumb", true, false) as TextureRect).texture
	ok(shown != null, "  the cell shows it")
	# the pose changes -> the thumbnail is made again
	write_pose("reach", pose_dict({"upperarm_r": Vector3(-30, 80, 0), "upperarm_l": Vector3(-30, 80, 0), "thigh_r": Vector3(-30, 0, 0)}))
	await lib.settle()
	ok(lib.renders == r0 + 1 and FileAccess.get_md5(ta) != md_a, "the pose file changed: its picture was made again (%d render) and its bytes changed" % (lib.renders - r0))
	write_pose("reach", pose_dict({"upperarm_r": Vector3(80, 30, 20), "lowerarm_r": Vector3(70, 0, 0), "upperarm_l": Vector3(-20, 10, 0),
		"thigh_l": Vector3(45, 0, 0), "calf_l": Vector3(-60, 0, 0), "spine_02": Vector3(15, 8, 12), "head": Vector3(0, 0, 25)}, Vector3(0.03, -0.05, 0.02)))
	await lib.settle()

	# ---- the start: the body somewhere else, empty-handed (a two-hand grip re-aims the second arm after every edit by
	# design, which is not the library's maths)
	m.B.wep_on = false
	m.B.wep2_on = false
	m.B.grip = false
	for j in Body.ORDER:
		m.B.ang[j] = Vector3.ZERO
	m.B.ang["upperarm_l"] = m.B.clamp_ang("upperarm_l", Vector3(40, 20, -10))
	m.B.ang["lowerarm_l"] = m.B.clamp_ang("lowerarm_l", Vector3(50, 0, 0))
	m.B.ang["thigh_r"] = m.B.clamp_ang("thigh_r", Vector3(30, -10, 5))
	m.B.ang["spine_03"] = m.B.clamp_ang("spine_03", Vector3(-10, 5, -15))
	m.B.offset = Vector3(-0.02, 0.0, 0.01)
	m.B.fk()
	m._after_edit()   # the start as the app keeps it (its own after-edit pass settles the forearm's twist)
	m._after_edit()
	var base: Dictionary = m.B.state()
	var clip := lib.clip_of(pa)
	var want := {}
	var wantf := {}
	for j in Body.ORDER:
		want[j] = PoseLibrary.target(m.B, clip, j, false)
		wantf[j] = PoseLibrary.target(m.B, clip, j, true)
	var d0 := 0.0
	for j in Body.ORDER:
		d0 = maxf(d0, qerr(j, base["ang"][j], want[j]))
	ok(d0 > 30.0, "the start differs from the library pose (by up to %.0f deg)" % d0)

	# ---- apply
	var u0: int = m.undo.size()
	lib.apply(pa)
	var w := worst(want)
	ok(w[0] < 0.01, "apply: every joint is the library pose (worst %.5f deg at %s)" % w)
	ok(m.B.offset.is_equal_approx(clip["offset"]), "  the hips' offset too %s" % m.B.offset)
	ok(m.undo.size() == u0 + 1, "  ONE undo step (%d)" % (m.undo.size() - u0))
	m._undo()
	w = worst(base["ang"])
	ok(w[0] < 1e-4 and m.B.offset.is_equal_approx(base["offset"]), "  Ctrl+Z: the start again (worst %.6f deg)" % w[0])

	# ---- blend 0 / 50 / 100
	u0 = m.undo.size()
	lib.begin_blend(pa, false)
	lib.blend_to(0.0)
	w = worst(base["ang"])
	ok(w[0] < 0.01, "blend 0 %%: the body as it was (worst %.5f deg at %s)" % w)
	lib.blend_to(0.5)
	var mid := 0.0
	var mid_at := ""
	for j in Body.ORDER:
		var q: Quaternion = m.B.compose(j, base["ang"][j]).slerp(m.B.compose(j, want[j]), 0.5)
		var e := qang(m.B.compose(j, m.B.ang[j]), q)
		if e > mid:
			mid = e
			mid_at = j
	ok(mid < 0.01, "blend 50 %%: every joint is the slerp midpoint of start and library pose (worst %.5f deg at %s)" % [mid, mid_at])
	ok(m.B.offset.is_equal_approx((base["offset"] as Vector3).lerp(clip["offset"], 0.5)), "  the hips halfway")
	ok(worst(base["ang"])[0] > 10.0 and worst(want)[0] > 10.0, "  and it is neither end (%.1f deg from the start, %.1f from the pose)" % [worst(base["ang"])[0], worst(want)[0]])
	lib.blend_to(1.0)
	w = worst(want)
	ok(w[0] < 0.01, "blend 100 %%: the library pose (worst %.5f deg at %s)" % w)
	lib.blend_to(0.5)
	lib.end_blend()
	ok(m.undo.size() == u0 + 1, "  release: ONE undo step for the whole drag (%d)" % (m.undo.size() - u0))
	m._undo()
	ok(worst(base["ang"])[0] < 1e-4, "  Ctrl+Z: the start again")
	# a 0 % blend leaves no step
	u0 = m.undo.size()
	lib.begin_blend(pa, false)
	lib.blend_to(0.0)
	lib.end_blend()
	ok(m.undo.size() == u0, "  a blend released at 0 %% leaves no undo step (%d)" % (m.undo.size() - u0))

	# ---- the same by a real mouse drag on the thumbnail
	var cell: Control = lib.cells[pa]
	var at := cell.get_global_rect().get_center()
	u0 = m.undo.size()
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = at
	mb.global_position = at
	root.push_input(mb)
	await process_frame
	for k in range(1, 9):
		var mm := InputEventMouseMotion.new()
		mm.position = at + Vector2(10.0 * k, 0)
		mm.global_position = mm.position
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mm)
		await process_frame
	mid = 0.0
	for j in Body.ORDER:
		var q2: Quaternion = m.B.compose(j, base["ang"][j]).slerp(m.B.compose(j, want[j]), 0.5)
		mid = maxf(mid, qang(m.B.compose(j, m.B.ang[j]), q2))
	ok(lib.readout.text == "50 %" and mid < 0.01, "mouse: an 80 px drag on the picture = blend 50 %% live (reads '%s', worst %.5f deg)" % [lib.readout.text, mid])
	var up := mb.duplicate() as InputEventMouseButton
	up.pressed = false
	up.position = at + Vector2(80, 0)
	up.global_position = up.position
	root.push_input(up)
	await process_frame
	ok(m.undo.size() == u0 + 1, "  the release: ONE undo step (%d), says '%s'" % [m.undo.size() - u0, String(m.ui_status.text).left(50)])
	m._undo()
	# a click (no drag) applies
	u0 = m.undo.size()
	mb.position = at
	mb.global_position = at
	root.push_input(mb)
	await process_frame
	up.position = at
	up.global_position = at
	root.push_input(up)
	await process_frame
	ok(worst(want)[0] < 0.01 and m.undo.size() == u0 + 1, "mouse: a click on the picture applies the pose (one undo step)")
	m._undo()

	# ---- flipped = Mirror pose of the plain apply
	lib.apply(pa)
	m.B.mirror_pose()
	var mir: Dictionary = m.B.ang.duplicate()
	var mir_off: Vector3 = m.B.offset
	m.B.set_state(base)
	m._refresh()
	u0 = m.undo.size()
	lib.apply(pa, true)
	w = worst(mir)
	ok(w[0] < 0.01, "flipped: = Mirror pose of the library pose (worst %.5f deg at %s)" % w)
	ok(worst(wantf)[0] < 0.01 and m.B.offset.is_equal_approx(mir_off), "  the hips' x reflected %s" % m.B.offset)
	ok(m.undo.size() == u0 + 1, "  ONE undo step (%d)" % (m.undo.size() - u0))
	m._undo()

	# ---- only the selected parts
	m.sel = "upperarm_r"
	m.sel_more = ["lowerarm_r", "thigh_l"]
	lib.only_box.button_pressed = true
	var only := ["upperarm_r", "lowerarm_r", "thigh_l"]
	u0 = m.undo.size()
	lib.apply(pa)
	ok(worst(want, only)[0] < 0.01, "selected only: the 3 selected parts are the library pose")
	var same := true
	var moved := []
	for j in Body.ORDER:
		if not j in only and m.B.ang[j] != base["ang"][j]:
			same = false
			moved.append(j)
	ok(same and m.B.offset == base["offset"], "  every other joint and the hips bit for bit as they were %s" % str(moved))
	ok(m.undo.size() == u0 + 1, "  ONE undo step (%d)" % (m.undo.size() - u0))
	# a blend on the selected parts only
	m._undo()
	lib.begin_blend(pa, false)
	lib.blend_to(0.5)
	lib.end_blend()
	same = true
	for j in Body.ORDER:
		if not j in only and m.B.ang[j] != base["ang"][j]:
			same = false
	ok(same and qerr("upperarm_r", m.B.ang["upperarm_r"], base["ang"]["upperarm_r"]) > 1.0, "  blend 50 % on the selected parts: they moved, nothing else")
	m._undo()
	lib.only_box.button_pressed = false

	# ---- a screenshot of the grid (Nick's library, in memory only)
	var shot := OS.get_environment("POSELIB_SHOT")
	if shot != "":
		lib.dirs = PoseLibrary.DIRS.duplicate()
		await lib.settle()
		lib.pick(lib.entries[1]["path"])
		for k in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		m.get_viewport().get_texture().get_image().save_png(shot)
		print("shot: " + shot)
		lib.dirs = [dir]

	# ---- nothing of Nick's written
	var after := nick_files()
	ok(after == before, "poses/, poses/lib/, moves/: the same files, byte for byte (%d files)" % after.size())
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	ok(not DirAccess.dir_exists_absolute(dir), "the zz_ scratch folder is gone")
	print("failures: %d" % fails)
	quit(1 if fails > 0 else 0)
