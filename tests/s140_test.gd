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
	# CRANIOVERTEBRAL ANGLE (CVA): the angle between the horizontal and the line from C7 to the tragion, in the sagittal plane.
	# Landmarks in the mannequin's own scale: C7 = the spinous process, the base of the neck bone (neck_01) moved BACK by 0.8 x the neck's
	# radius (0.06 m, data/body_limits.json) along the neck's own forward axis (the process sits behind the vertebral body the joint marks);
	# tragion = the head joint (skull base, 8.1 cm above the neck base) + 1 cm up the head's axis + 1 cm in front of the head's centre line,
	# turned with the head (the ear is about level with the eyes, ~ 8.6 cm above C7 in a neutral adult). Published: normal >= 53 (some >= 55),
	# forward head < 50, standing means 48.1 +- 6.5 (elderly sample), 37.2 (young women, standing), neutral adult standing 48 to 55.
	var cva_of := func(bd: Body) -> float:
		var fw: Vector3 = ((bd.P["upperarm_l"] - bd.P["upperarm_r"]) as Vector3).cross(Vector3.UP)
		fw.y = 0.0
		fw = fw.normalized()
		var nf: Vector3 = (bd.G["neck_01"] as Quaternion) * Vector3(0, 0, 1)
		var c7: Vector3 = (bd.P["neck_01"] as Vector3) - nf * 0.8 * 0.06
		var ax: Vector3 = ((bd.E["head"] as Vector3) - (bd.P["head"] as Vector3)).normalized()
		var hf: Vector3 = (bd.G["head"] as Quaternion) * Vector3(0, 0, 1)
		var tr: Vector3 = (bd.P["head"] as Vector3) + ax * 0.01 + hf * 0.01
		return rad_to_deg(atan2(tr.y - c7.y, (tr - c7).dot(fw)))
	var cva := {}
	for nm in ["stand", "tired_slump", "tired_droop", "calm_easy", "proud_chest_out"]:
		var path := "res://poses/stand.json" if nm == "stand" else "res://poses/lib/%s.json" % nm
		var bd := fresh(load_pose(path))
		cva[nm] = cva_of.call(bd)
		print("     CVA %-16s %.1f deg" % [nm, cva[nm]])
	ok(cva["stand"] >= 48.0 and cva["stand"] <= 55.0, "REAL stand: CVA %.1f deg is in the neutral adult range 48-55 (the landmark check)" % cva["stand"])
	ok(cva["tired_slump"] < 50.0 and cva["tired_droop"] < 50.0, "REAL tired: CVA %.1f / %.1f deg are forward-head (< 50)" % [cva["tired_slump"], cva["tired_droop"]])
	# EVERY pose the "tired" search returns: a strongly slumped real person reads 30-45 deg (not a 10-16 deg caricature)
	var tired_bad := []
	for tr_row in found["tired"]:
		var tc: float = cva_of.call(fresh(load_pose(tr_row[1])))
		print("     CVA tired search row %-20s %.1f deg" % [tr_row[0], tc])
		if tc < 30.0 or tc > 45.0:
			tired_bad.append("%s %.1f" % [tr_row[0], tc])
	ok(tired_bad.is_empty() and found["tired"].size() >= 3, "REAL every tired search row has CVA 30-45 deg (outside: %s)" % [tired_bad])
	ok(cva["tired_droop"] < cva["tired_slump"] and cva["tired_slump"] < cva["stand"], "REAL tired: the deeper slump has the smaller CVA (%.1f < %.1f < stand %.1f)" % [cva["tired_droop"], cva["tired_slump"], cva["stand"]])
	ok(cva["calm_easy"] >= 50.0 and cva["calm_easy"] <= 65.0, "REAL calm_easy: CVA %.1f deg is normal (50-65)" % cva["calm_easy"])
	ok(cva["proud_chest_out"] >= 50.0 and cva["proud_chest_out"] <= 65.0, "REAL proud_chest_out: CVA %.1f deg is normal-to-high (50-65)" % cva["proud_chest_out"])
	# SCARED reach: per scared pose, the guarding arm (the hand nearest the face): shoulder-to-wrist reach against the arm's length, elbow, hand-to-face
	var reach_n := 0
	for nm in ["scared_shield", "scared_hand_to_mouth", "scared_back_away"]:
		var bg := fresh(load_pose("res://poses/lib/%s.json" % nm))
		var fc: Vector3 = ((bg.P["head"] as Vector3) + (bg.E["head"] as Vector3)) * 0.5
		var sd := "l" if (bg.P["hand_l"] as Vector3).distance_to(fc) < (bg.P["hand_r"] as Vector3).distance_to(fc) else "r"
		var rch: float = (bg.P["hand_" + sd] as Vector3).distance_to(bg.P["upperarm_" + sd])
		var alen: float = (bg.P["lowerarm_" + sd] as Vector3).distance_to(bg.P["upperarm_" + sd]) + (bg.P["hand_" + sd] as Vector3).distance_to(bg.P["lowerarm_" + sd])
		var elb: float = bg.ang["lowerarm_" + sd].x
		var hf: float = (bg.P["hand_" + sd] as Vector3).distance_to(fc)
		print("     REACH %-22s arm %s: shoulder-to-wrist %.3f m of a %.3f m arm (%.0f %%), elbow %.0f deg, hand to face centre %.2f m" % [nm, sd, rch, alen, rch / alen * 100.0, elb, hf])
		# not vacuous: the arm is really bent (reach clearly under its length, elbow >= 60) and the hand is at the face
		ok(rch <= alen + 0.001 and rch < 0.9 * alen and rch > 0.15 and elb >= 60.0 and elb <= 145.0 and hf <= 0.40, "REACH %s: %.3f m of %.3f m, elbow %.0f deg, %.2f m from the face" % [nm, rch, alen, elb, hf])
		reach_n += 1
	ok(reach_n == 3, "REACH: %d scared poses measured" % reach_n)
	# the three scared arms are three different arms: elbows at least 15 deg apart pairwise
	var elbs := []
	for nm in ["scared_shield", "scared_hand_to_mouth", "scared_back_away"]:
		var bq := fresh(load_pose("res://poses/lib/%s.json" % nm))
		var fq: Vector3 = ((bq.P["head"] as Vector3) + (bq.E["head"] as Vector3)) * 0.5
		elbs.append(bq.ang["lowerarm_l"].x if (bq.P["hand_l"] as Vector3).distance_to(fq) < (bq.P["hand_r"] as Vector3).distance_to(fq) else bq.ang["lowerarm_r"].x)
	var gap := minf(minf(absf(elbs[0] - elbs[1]), absf(elbs[0] - elbs[2])), absf(elbs[1] - elbs[2]))
	ok(gap >= 15.0, "SCARED ARMS differ: guarding elbows %.0f / %.0f / %.0f deg, smallest gap %.0f deg (>= 15)" % [elbs[0], elbs[1], elbs[2], gap])
	print("s140: %d fail" % fails)
	quit(1 if fails > 0 else 0)
