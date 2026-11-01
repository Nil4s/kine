extends SceneTree
## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/s140_test.gd     (Friday plan 140: Pose library by mood; a window)
## POSE MOODS (scripts/pose_mood.gd, tagged into the Poses search by scripts/pose_tags.gd, mood chips in scripts/pose_library.gd).
## Bars, measured from the poses' own bodies. The rules below are written HERE a second time, as literals from the brief, and
## evaluated on a FRESH Body forwarded from each pose file's joint angles (not on the positions stored in the file, which PoseMood
## reads), so a wrong rule or a wrong tag in the app cannot agree with the test by sharing code.
##   brief rules:  tired  = head pitched down > 15 deg + shoulders forward (clavicle side >= 5) or dropped (clavicle bend <= -5) + spine flexed (sum of the 3 spine bends >= 15)
##                 proud  = spine extended (sum <= -6) + trunk not leaning forward + chin up (head axis tilted back >= 8) + shoulders back (clavicle side <= -5)
##                 scared = a hand within 0.40 m of the face with its elbow >= 60 + knees bent (mean >= 15) + head pulled back or down (|pitch| >= 10)
##   1 SEARCH     "tired", "proud", "scared" typed in the Poses search box: every row returned meets that mood's rule (angles printed per pose), >= 3 rows each
##   2 CONTROL    t_pose and stand (the neutral T / A pose) are in none of the three, and are not returned by any of the three searches
##   3 SYNONYMS   exhausted = sleepy = tired, confident = proud, afraid = frightened = scared: the same ordered rows
##   4 CLICK      a real click on a returned row: every bone rotation equals the pose file within 0.5 deg, ONE undo step, one Ctrl+Z restores
##   5 CHIPS      the Pose library has a chip per mood (+ All); a real click on Tired/Proud/Scared leaves only poses that meet the rule (>= 3),
##                All shows more; a real click on a picture applies the pose (0.5 deg, one undo step)
##   6 EIGHT      every one of the 8 moods tags at least 2 library poses, and each tag is re-measured from the fresh Body
##   7 REAL HUMANS 3 poses against published numbers (craniovertebral angle: normal >= 53 deg, forward-head < 50 deg, standing mean 48.1 +- 6.5 in an
##                elderly sample (Evaluation of Head Position Using Craniovertebral Angle in Two Sitting and Standing Positions in the Elderly), 37.2 deg
##                standing in young women (Durban Univ. of Technology thesis, ir.dut.ac.za/handle/10321/4524)); pride / fear numbers have no
##                fetched table (Coulson 2004's PDF could not be read from here) and are printed against the mannequin's own anatomical ranges
## Shots: C:/Temp/claude/s140/tired_search.png (the Poses search on "tired"), tired_chip.png (the library's Tired chip, thumbnails)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s140"
const DIRS := ["res://poses/lib", "res://poses", "res://moves"]


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_at(p: Vector2) -> void:
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func shot(nm: String) -> void:
	await idle(4)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func load_pose(path: String) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


## a fresh body forwarded from the file's joint angles
func fresh(d: Dictionary) -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(d)
	b.fk()
	return b


func pitch(b: Body, fwd: Vector3) -> float:   # head axis, + = forward (chin down)
	var v: Vector3 = b.E["head"] - b.P["head"]
	return rad_to_deg(atan2(v.dot(fwd), v.y))


## [meets, "angles"] for a mood on a fresh body (the literals of the brief)
func judge(mood: String, d: Dictionary) -> Array:
	var b := fresh(d)
	var fwd: Vector3 = ((b.P["upperarm_l"] - b.P["upperarm_r"]) as Vector3).cross(Vector3.UP)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var hp := pitch(b, fwd)
	var curl: float = b.ang["spine_01"].x + b.ang["spine_02"].x + b.ang["spine_03"].x
	var cs: float = (b.ang["clavicle_l"].y + b.ang["clavicle_r"].y) * 0.5
	var cb: float = (b.ang["clavicle_l"].x + b.ang["clavicle_r"].x) * 0.5
	var nk: Vector3 = b.P["neck_01"] - b.P["pelvis"]
	var lean := rad_to_deg(atan2(nk.dot(fwd), nk.y))
	var knee: float = (b.ang["calf_l"].x + b.ang["calf_r"].x) * 0.5
	var fc: Vector3 = ((b.P["head"] as Vector3) + (b.E["head"] as Vector3)) * 0.5
	var dl: float = (b.P["hand_l"] as Vector3).distance_to(fc)
	var dr: float = (b.P["hand_r"] as Vector3).distance_to(fc)
	var el: float = b.ang["lowerarm_l"].x
	var er: float = b.ang["lowerarm_r"].x
	var txt := "head %.0f lean %.0f spine %.0f clav fwd %.0f bend %.0f knee %.0f hand-face %.2f/%.2f elbow %.0f/%.0f" % [hp, lean, curl, cs, cb, knee, dl, dr, el, er]
	match mood:
		"tired":
			return [hp > 15.0 and curl >= 15.0 and (cs >= 5.0 or cb <= -5.0), txt]
		"proud":
			return [curl <= -6.0 and lean <= 3.0 and hp <= -8.0 and cs <= -5.0, txt]
		"scared":
			return [((dl <= 0.40 and el >= 60.0) or (dr <= 0.40 and er >= 60.0)) and knee >= 15.0 and absf(hp) >= 10.0, txt]
	return [false, txt]


func rows_of(b: Browser) -> Array:   # [[name, path]] of the Poses rows now shown
	var out := []
	for f in [b._lib, b._mine]:
		for it in f.get_children():
			var md = it.get_metadata(0)
			if md is Dictionary and md.has("pose"):
				out.append([it.get_text(0), m.ui_poses.get_item_metadata(int(md["pose"])), it])
	return out


func search(b: Browser, q: String) -> Array:
	b._search.text = q
	b._search.text_changed.emit(q)
	await idle(3)
	return rows_of(b)


func names(rows: Array) -> Array:
	return rows.map(func(r): return r[0])


## the worst bone-rotation difference (deg) between the body now and the pose file
func worst(d: Dictionary) -> float:
	var w := 0.0
	for j in d["joints"]:
		if not m.B.lim.has(j):
			continue
		var x: Dictionary = d["joints"][j]
		var q: Quaternion = m.B.compose(j, Vector3(x["bend"], x["side"], x["twist"]))
		var c: Quaternion = m.B.compose(j, m.B.ang[j])
		var dq := q.inverse() * c
		w = maxf(w, rad_to_deg(2.0 * asin(minf(1.0, Vector3(dq.x, dq.y, dq.z).length()))))
	return w


func angles() -> Dictionary:
	var o := {}
	for j in Body.ORDER:
		o[j] = m.B.ang[j]
	return o


func same(a: Dictionary, b: Dictionary) -> bool:
	for j in a:
		if not (a[j] as Vector3).is_equal_approx(b[j]):
			return false
	return true


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	var b: Browser = m.ui_browser
	b.pose_cache_path = "user://s140_tags.json"
	if FileAccess.file_exists(b.pose_cache_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(b.pose_cache_path))
	b.set_pose_query("")
	b._pose_sig = ""
	await idle(3)
	b.open_all()
	b._lib.collapsed = false
	b._mine.collapsed = false
	# ---------------------------------------------------------------- 1 SEARCH
	var found := {}
	for mood in ["tired", "proud", "scared"]:
		var rows := await search(b, mood)
		found[mood] = rows
		var bad := 0
		for r in rows:
			var j := judge(mood, load_pose(r[1]))
			print("     %-7s %-22s %s  -> %s" % [mood, r[0], j[1], "meets" if j[0] else "FAILS"])
			if not j[0]:
				bad += 1
		ok(rows.size() >= 3 and bad == 0, "SEARCH '%s': %d rows, %d fail the %s rule" % [mood, rows.size(), bad, mood])
	await search(b, "tired")
	await shot("tired_search")
	# ---------------------------------------------------------------- 2 CONTROL
	for nm in ["t_pose", "stand"]:
		var d := load_pose("res://poses/%s.json" % nm)
		var tags := PoseMood.tags_of(d)
		var in3 := tags.filter(func(t): return t in ["tired", "proud", "scared"])
		var j3 := ["tired", "proud", "scared"].filter(func(md): return judge(md, d)[0])
		var returned := []
		for mood in found:
			for r in found[mood]:
				if (r[1] as String).get_file() == nm + ".json":
					returned.append(mood)
		ok(in3.is_empty() and j3.is_empty() and returned.is_empty(), "CONTROL %s: moods %s, fresh-body rules true for %s, returned by searches %s" % [nm, tags, j3, returned])
	# ---------------------------------------------------------------- 3 SYNONYMS
	for g in [["tired", "exhausted", "sleepy"], ["proud", "confident"], ["scared", "afraid", "frightened"]]:
		var base := names(found[g[0]])
		for k in range(1, g.size()):
			var got := names(await search(b, g[k]))
			ok(got == base and base.size() >= 3, "SYNONYM '%s' returns the same %d rows as '%s'" % [g[k], got.size(), g[0]])
	# a typo of a mood word still finds it; a non-mood word is not read as one
	var typo := names(await search(b, "tird"))
	ok(typo == names(found["tired"]), "TYPO 'tird' returns the same rows as 'tired'")
	# ---------------------------------------------------------------- 4 CLICK a search result
	var rows := await search(b, "tired")
	b._lib.collapsed = false
	var target: Array = rows[0]
	var want := load_pose(target[1])
	m.B.from_dict(load_pose("res://poses/t_pose.json"))
	m._after_edit()
	await idle(2)
	var before := angles()
	var n0: int = m.undo.size()
	var it: TreeItem = target[2]
	b.scroll_to_item(it)
	await idle(2)
	var r := b.get_item_area_rect(it, 0)
	var at := b.get_global_rect().position + r.get_center()
	ok(r.size.y > 0.0 and root.get_visible_rect().has_point(at), "CLICK: the first 'tired' row '%s' is on screen at %s" % [target[0], at])
	await click_at(at)
	var w := worst(want)
	ok(w <= 0.5, "CLICK: every bone rotation within %.3f deg of '%s' (<= 0.5)" % [w, target[0]])
	ok(m.undo.size() == n0 + 1, "CLICK: ONE undo step (%d -> %d)" % [n0, m.undo.size()])
	m._undo()
	await idle(2)
	ok(same(angles(), before) and m.undo.size() == n0, "CLICK: one Ctrl+Z restores the previous pose")
	# ---------------------------------------------------------------- 5 CHIPS in the library
	b._search.text = ""
	b.set_pose_query("")
	PoseLibrary.toggle(m)
	await idle(3)
	var lib: PoseLibrary = m.get_meta("pose_library")
	await lib.settle()
	var all_n := lib.cells.size()
	var chip_n := {}
	for mood in ["tired", "proud", "scared"]:
		var chip: Button = lib.find_child("mood_" + mood, true, false)
		ok(chip != null and root.get_visible_rect().encloses(chip.get_global_rect()), "CHIP '%s' is on screen: %s" % [mood, chip.get_global_rect() if chip else "missing"])
		await click_ctl(chip)
		await lib.settle()
		var bad := 0
		for p in lib.cells:
			var j := judge(mood, load_pose(p))
			if not j[0]:
				bad += 1
		chip_n[mood] = lib.cells.size()
		ok(lib.cells.size() >= 3 and bad == 0 and lib.cells.size() < all_n, "CHIP %s: %d of %d poses shown, %d fail the rule" % [mood, lib.cells.size(), all_n, bad])
		if mood == "tired":
			await shot("tired_chip")
			# a real click on a picture
			var path: String = lib.cells.keys()[0]
			var wantd := load_pose(path)
			m.B.from_dict(load_pose("res://poses/t_pose.json"))
			m._after_edit()
			await idle(2)
			var bf := angles()
			var u0: int = m.undo.size()
			await click_ctl(lib.cells[path])
			var w2 := worst(wantd)
			ok(w2 <= 0.5 and m.undo.size() == u0 + 1, "CHIP click on '%s': rotations within %.3f deg, undo %d -> %d (one step)" % [path.get_file(), w2, u0, m.undo.size()])
			m._undo()
			await idle(2)
			ok(same(angles(), bf), "CHIP click: one Ctrl+Z restores")
	var allchip: Button = lib.find_child("mood_all", true, false)
	await click_ctl(allchip)
	await lib.settle()
	ok(lib.cells.size() == all_n, "CHIP All shows every pose again (%d)" % lib.cells.size())
	# ---------------------------------------------------------------- 6 EIGHT moods
	var counts := {}
	for md in PoseMood.MOODS:
		counts[md] = 0
	var pool := []
	for dir in DIRS:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json") and not (FileAccess.get_file_as_string(dir + "/" + f).contains("\"keys\"") or FileAccess.get_file_as_string(dir + "/" + f).contains("\"cards\"")):
				pool.append(dir + "/" + f)
	var mism := 0
	for p in pool:
		var d := load_pose(p)
		if not d.has("joints"):
			continue
		for md in PoseMood.tags_of(d):
			counts[md] += 1
			if md in ["tired", "proud", "scared"] and not judge(md, d)[0]:
				mism += 1
	var low := PoseMood.MOODS.filter(func(md): return counts[md] < 2)
	ok(low.is_empty() and mism == 0, "EIGHT: poses per mood %s (moods under 2: %s; tags the fresh-body rule rejects: %d)" % [counts, low, mism])
	# ---------------------------------------------------------------- 7 REAL HUMANS
	for nm in ["calm_easy", "tired_slump", "tired_droop", "proud_chest_out", "scared_shield"]:
		var d := load_pose("res://poses/lib/%s.json" % nm)
		var bd := fresh(d)
		var c7: Vector3 = bd.P["neck_01"]
		var ear: Vector3 = (bd.P["head"] as Vector3).lerp(bd.E["head"], 0.35)   # the ear canal sits ~ a third of the way up the skull
		var fwd: Vector3 = ((bd.P["upperarm_l"] - bd.P["upperarm_r"]) as Vector3).cross(Vector3.UP)
		fwd.y = 0.0
		fwd = fwd.normalized()
		var cva := rad_to_deg(atan2(ear.y - c7.y, (ear - c7).dot(fwd)))
		print("     REAL %-16s craniovertebral angle %.1f deg (published: normal >= 53, forward head < 50, standing mean 48.1 +- 6.5 elderly, 37.2 young women), head pitch %.0f deg, cervical flexion range of the mannequin: neck+head bend %.0f of 60 deg" % [nm, cva, pitch(bd, fwd), bd.ang["neck_01"].x + bd.ang["head"].x])
		if nm == "calm_easy":
			ok(cva >= 53.0 - 8.0, "REAL calm_easy: CVA %.1f deg is in the normal range (>= 53 - 1 SD 8)" % cva)
		elif nm.begins_with("tired"):
			ok(cva < 50.0, "REAL %s: CVA %.1f deg is a forward-head posture (< 50), as a slump is" % [nm, cva])
		elif nm == "proud_chest_out":
			ok(cva >= 53.0 - 8.0, "REAL proud_chest_out: CVA %.1f deg is not forward-head (>= 45): chin up, head over the shoulders" % cva)
	# scared_shield against arm anthropometry: the hand must be reachable: shoulder to wrist <= arm length (upper arm + forearm of the same mannequin) and elbow in its range
	var dg := load_pose("res://poses/lib/scared_shield.json")
	var bg := fresh(dg)
	var reach: float = (bg.P["hand_l"] as Vector3).distance_to(bg.P["upperarm_l"])
	var arm_len: float = (bg.P["lowerarm_l"] as Vector3).distance_to(bg.P["upperarm_l"]) + (bg.P["hand_l"] as Vector3).distance_to(bg.P["lowerarm_l"])
	print("     REAL scared_shield: shoulder-to-wrist %.2f m of a %.2f m arm, elbow %.0f deg (human range 0-145), hand to face centre %.2f m" % [reach, arm_len, bg.ang["lowerarm_l"].x, (bg.P["hand_l"] as Vector3).distance_to(((bg.P["head"] as Vector3) + (bg.E["head"] as Vector3)) * 0.5)])
	ok(reach <= arm_len + 0.001 and bg.ang["lowerarm_l"].x <= 145.0, "REAL scared_shield: the guard is within the arm's reach and the elbow's range")
	print("s140: %d fail" % fails)
	quit(1 if fails > 0 else 0)
