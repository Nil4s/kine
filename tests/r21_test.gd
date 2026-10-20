## godot --path . -s tests/r21_test.gd     (ROADMAP round 2, R21: the pose library searched by words; needs a window)
## BARS, written before measuring:
##  1 EACH TAG RULE true on its crafted pose (crouch, guard, kick, lunge, one-leg, arms-up, seated, lying, high, low) and
##    false on 'stand' (which has no tag at all)
##  2 "low kik" (a typo) finds the crafted 'low kick' pose FIRST, and no pose whose name and tags lack "low"
##  3 SPEED: each keystroke of "low kick" refilled the Browser's Poses rows in < 16 ms, on the real library and on the
##    library x 20 (the index parsed once; a keystroke only scores)
##  4 CACHE: the tags are cached in a file (a temp one here); a second build reads 0 pose files
##  5 NOTHING WRITTEN: every file under res://poses (bytes + modified time) identical after the run
##  6 PLACEMENT (whole window): the search box is over the first row under Poses, inside the Browser, above the Library row;
##    typing "bat high" leaves rows that carry chips, and the chips' rows are inside the visible Browser. Screenshot
##    jobs/9afc22db/tmp/r21.png
extends SceneTree

var m: Node
var fails := 0
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/r21.png"
const TMP := "user://r21_tmp"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func put(d: Dictionary, jn: String, pos: Array) -> void:   # move a joint (its end follows by the same shift)
	var j: Dictionary = d["joints"][jn]
	var old: Array = j["pos"]
	var e: Array = j["end"]
	j["end"] = [e[0] + pos[0] - old[0], e[1] + pos[1] - old[1], e[2] + pos[2] - old[2]]
	j["pos"] = pos


func stand() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json"))


func save(name: String, d: Dictionary) -> String:
	var p := TMP + "/" + name + ".json"
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	return p


func snapshot() -> Dictionary:
	var out := {}
	var stack := ["res://poses"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		for f in DirAccess.get_files_at(dir):
			out[dir + "/" + f] = [FileAccess.get_file_as_bytes(dir + "/" + f).size(), FileAccess.get_modified_time(dir + "/" + f), FileAccess.get_file_as_bytes(dir + "/" + f).hex_encode().hash()]
		for s in DirAccess.get_directories_at(dir):
			stack.append(dir + "/" + s)
	return out


func _init() -> void:
	var before := snapshot()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP))
	# ---- crafted poses (the standing figure edited; positions in metres)
	var P := {}
	var d := stand()
	put(d, "pelvis", [0.0, 0.55, 0.0])   # crouch: hips at 60 % of 0.9167, thighs slope (not a chair)
	put(d, "head", [0.0, 1.2, 0.1])
	put(d, "calf_r", [-0.09, 0.3, 0.3])
	put(d, "calf_l", [0.09, 0.3, 0.3])
	put(d, "thigh_r", [-0.09, 0.55, 0.0])
	put(d, "thigh_l", [0.09, 0.55, 0.0])
	P["crouch"] = d
	d = stand()   # guard: both fists at the face, in front
	put(d, "hand_r", [-0.1, 1.5, 0.3])
	put(d, "hand_l", [0.1, 1.5, 0.3])
	P["guard"] = d
	d = stand()   # kick: the right ankle at 0.8 m, in front
	put(d, "foot_r", [-0.09, 0.8, 0.5])
	put(d, "calf_r", [-0.09, 0.7, 0.25])
	P["low kick"] = d
	P["high kick"] = d.duplicate(true)
	d = stand()   # lunge: feet 0.9 m apart front to back, the front knee bent
	put(d, "foot_r", [-0.18, 0.1, 0.45])
	put(d, "calf_r", [-0.15, 0.5, 0.5])
	put(d, "foot_l", [0.18, 0.1, -0.45])
	P["lunge"] = d
	d = stand()   # one leg: the left ankle 0.25 m up
	put(d, "foot_l", [0.09, 0.25, -0.04])
	P["one leg"] = d
	d = stand()   # both hands above the head top (1.74)
	put(d, "hand_r", [-0.2, 1.95, 0.0])
	put(d, "hand_l", [0.2, 1.95, 0.0])
	P["arms up"] = d
	d = stand()   # seated: hips 0.47, thighs flat, shins upright
	put(d, "pelvis", [0.0, 0.47, 0.0])
	put(d, "head", [0.0, 1.1, 0.0])
	for s in ["r", "l"]:
		var x := -0.09 if s == "r" else 0.09
		put(d, "thigh_" + s, [x, 0.47, 0.0])
		put(d, "calf_" + s, [x, 0.47, 0.4])
		put(d, "foot_" + s, [x, 0.1, 0.4])
	P["seated"] = d
	d = stand()   # lying: hips 0.15, head along the floor
	put(d, "pelvis", [0.0, 0.15, 0.0])
	put(d, "head", [0.0, 0.2, 1.5])
	for s in ["r", "l"]:
		var x := -0.09 if s == "r" else 0.09
		put(d, "thigh_" + s, [x, 0.15, 0.0])
		put(d, "calf_" + s, [x, 0.15, -0.45])
		put(d, "foot_" + s, [x, 0.15, -0.9])
	P["lying"] = d
	d = stand()   # the right hand at 0.3 m: low; a weapon tip above the head: high
	put(d, "hand_r", [-0.3, 0.3, 0.2])
	P["low reach"] = d
	d = stand()
	d["weapon"] = {"kind": "metal_bat", "tip": [-0.2, 2.1, 0.3]}
	P["bat up high"] = d
	var want := {"crouch": "crouch", "guard": "guard", "low kick": "kick", "lunge": "lunge", "one leg": "one-leg", "arms up": "arms-up", "seated": "seated",
		"lying": "lying", "low reach": "low", "bat up high": "high"}
	var st := PoseTags.tags_of(stand())
	ok(st.is_empty(), "'stand' has no tag at all: %s" % [st])
	for k in want:
		var t := PoseTags.tags_of(P[k])
		ok(want[k] in t and not want[k] in st, "'%s' gets '%s' (stand does not): %s" % [k, want[k], t])
	# the real library, for the eye (not barred)
	for f in ["bo_low_coil", "walk_bat_down", "bat_up", "windup_high", "strike_lunge", "guard_bat", "dodge_low"]:
		print("     real %s: %s" % [f, PoseTags.tags_of(JSON.parse_string(FileAccess.get_file_as_string("res://poses/lib/%s.json" % f)))])
	# ---- the index over the crafted set, cache in a temp file
	var items := []
	for k in P:
		items.append({"name": k, "path": save(k, P[k])})
	items.append({"name": "stand", "path": save("stand", stand())})
	var cache := TMP + "/tags.json"
	if FileAccess.file_exists(cache):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cache))
	var ix := PoseTags.Index.new()
	ix.cache_path = cache
	ix.build(items)
	var r1 := ix.read_files
	var ix2 := PoseTags.Index.new()
	ix2.cache_path = cache
	ix2.build(items)
	ok(r1 == items.size() and ix2.read_files == 0 and FileAccess.file_exists(cache), "CACHE: first build parsed %d of %d pose files, the second %d" % [r1, items.size(), ix2.read_files])
	var hits := ix2.search("low kik")
	var names := hits.map(func(h): return ix2.entries[h["i"]]["name"])
	ok(names.size() > 0 and names[0] == "low kick", "'low kik' finds 'low kick' first: %s" % [names])
	ok(not names.has("high kick") and not names.has("stand"), "...and not 'high kick' or 'stand'")
	var g := ix2.search("guard").map(func(h): return ix2.entries[h["i"]]["name"])
	ok(g.size() == 1 and g[0] == "guard", "'guard' finds the guard pose only: %s" % [g])
	var c := ix2.search("crouching").map(func(h): return ix2.entries[h["i"]]["name"])
	ok(c.has("crouch"), "'crouching' (a synonym of the tag) finds 'crouch': %s" % [c])
	var bu := ix2.search("bat up high").map(func(h): return ix2.entries[h["i"]]["name"])
	ok(bu.size() > 0 and bu[0] == "bat up high", "'bat up high' finds the bat pose first: %s" % [bu])
	# ---- the app
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	var b: Browser = m.ui_browser
	b.pose_cache_path = TMP + "/app_tags.json"
	if FileAccess.file_exists(b.pose_cache_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(b.pose_cache_path))
	var n_real: int = m.ui_poses.item_count
	var worst := 0.0
	var first := 0.0
	var typed := ""
	for ch in "low kick":
		typed += ch
		var t0 := Time.get_ticks_usec()
		b.set_pose_query(typed)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if typed == "l":
			first = ms
		else:
			worst = maxf(worst, ms)
	ok(worst < 16.0, "SPEED: real library (%d poses): worst keystroke %.2f ms after the first %.2f ms (index built then)" % [n_real, worst, first])
	# the library x 20
	for k in 19:
		for i in n_real:
			var j: int = m.ui_poses.add_item(m.ui_poses.get_item_text(i))
			m.ui_poses.set_item_metadata(j, m.ui_poses.get_item_metadata(i))
	b.set_pose_query("")
	typed = ""
	worst = 0.0
	for ch in "bat up high":
		typed += ch
		var t0 := Time.get_ticks_usec()
		b.set_pose_query(typed)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if typed.length() > 1:
			worst = maxf(worst, ms)
	ok(worst < 16.0, "SPEED: library x 20 (%d rows): worst keystroke %.2f ms (shown %d rows)" % [m.ui_poses.item_count, worst, b._lib.get_child_count() + b._mine.get_child_count()])
	# back to the real list for the picture
	while m.ui_poses.item_count > n_real:
		m.ui_poses.remove_item(m.ui_poses.item_count - 1)
	b.set_pose_query("")
	b._pose_sig = ""
	await idle(3)
	b.open_all()
	b._lib.collapsed = false
	b._search.text = "bat high"
	b._search.text_changed.emit("bat high")
	await idle(4)
	var sr := b._search.get_global_rect()
	var br := b.get_global_rect()
	var lib_r := b.get_item_area_rect(b._lib, 0)
	var rows_with_chips := 0
	var rows_in := 0
	for it in b._lib.get_children():
		if it.has_meta("chips"):
			rows_with_chips += 1
			var ar := b.get_item_area_rect(it, 0)
			if ar.size.y > 0.0 and ar.position.y >= 0.0 and ar.end.y <= b.size.y:
				rows_in += 1
	ok(b._search.visible and br.encloses(sr) and sr.position.y < br.position.y + lib_r.position.y, "PLACEMENT: the search box %s is inside the Browser %s and above the Library row (y %.0f < %.0f)" % [sr, br, sr.position.y, br.position.y + lib_r.position.y])
	ok(rows_with_chips > 0 and rows_in == rows_with_chips, "PLACEMENT: 'bat high' leaves %d pose rows with chips, %d of them inside the Browser's view" % [rows_with_chips, rows_in])
	await idle(4)
	await RenderingServer.frame_post_draw
	var lines := []
	for it in b._lib.get_children():
		lines.append("%s %s" % [it.get_text(0), it.get_meta("chips", [])])
	print("     'bat high' over the real library: ", lines)
	m.get_viewport().get_texture().get_image().save_png(OUT)
	var after := snapshot()
	ok(after == before and before.size() > 0, "NOTHING WRITTEN: %d files under poses/ identical (bytes, modified time)" % before.size())
	print("R21 ", "ALL OK" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails > 0 else 0)
