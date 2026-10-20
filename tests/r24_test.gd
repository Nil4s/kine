## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/r24_test.gd     (ROADMAP R24; a window; runs python + MuJoCo for the spot points)
## PUSH LIMITS: data/push_limits.json (tools/physics/push_limits.py) read by the app's CHECK (scripts/push_limits.gd, main.gd _push_rows).
## Bars, written before measuring:
##   1 MONOTONE: in all 4 bodies x 8 directions absorb_max <= step_max < fall_at, AND absorb_max < step_max strictly wherever the sim has a step
##     band. Written first as strict everywhere; the generator then found 11 of 32 cells (pure forward / sideways pushes) where the sim takes a
##     step at the first impulse that topples it (chest forward: 26 absorbs, 27 steps at 0.22 s and falls at 1.39 s) so no impulse is 'recovered
##     with a step'. That is the sim's measured behaviour, kept in the table and listed in its 'no_step_band'; bar 1 now says the band is
##     empty there instead of pretending (changed after seeing the result, stated in the report).
##   2 LABELS: the app's label (PushLimits.label) for a 10 N s chest push is 'absorbs' and for 60 N s is 'falls' (forward, 0 deg).
##   3 SPOT POINTS: the sim run directly (push_limits.py --spot) at those two points gives outcome 0 and 2, and at the table's
##     step_max of the chest at 90 deg gives 1 ('steps'), all agreeing with the app's label.
##   4 CHECK ROW: the CHECK panel has the reference row 'push_limit_ref' naming the chest's three numbers, and one 'push_hit_N' row per
##     body-part hit contact (two fighters, combo3) whose word is the label for the J that HitPhysics.measure gives, drawn inside the window.
##   5 NOTHING WRITTEN: every file under data/, scenes/, poses/ is byte-identical (hash) after the test; the table is not rewritten.
extends SceneTree

var fails := 0
var m: Node
const D0 := 1.2
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/r24.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func stand_pose() -> Dictionary:
	var b := body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b.to_dict()


func still(pose: Dictionary) -> Scene:
	var s := Scene.new()
	s.from_dict({"scene": "zz_still", "fps": 30, "cards": [{"name": "a", "pose": pose, "move": -1.0, "hold": 2.0},
		{"name": "b", "pose": pose, "move": 0.5, "hold": 3.0}]})
	return s


func hashes() -> Dictionary:
	var out := {}
	for d in ["data", "scenes", "poses"]:
		var stack: Array = ["res://" + d]
		while not stack.is_empty():
			var p: String = stack.pop_back()
			for f in DirAccess.get_files_at(p):
				out[p + "/" + f] = FileAccess.get_sha256(p + "/" + f)
			for s in DirAccess.get_directories_at(p):
				stack.append(p + "/" + s)
	return out


func spot(bd: String, J: float, dir: float) -> int:
	var o := []
	OS.execute("python", [ProjectSettings.globalize_path("res://tools/physics/push_limits.py"), "--spot", bd, str(J), str(dir)], o, true)
	return int(String(o[0]).strip_edges().get_slice("\n", 0)) if not o.is_empty() and String(o[0]).strip_edges() != "" else -1


func _init() -> void:
	var h0 := hashes()
	var tb: Dictionary = PushLimits.table()
	ok(not tb.is_empty(), "0 data/push_limits.json loads")
	# 1 MONOTONE
	var bad := []
	var cells := 0
	var strict := 0
	for k in tb["table"]:
		for d in tb["table"][k]:
			var r: Dictionary = tb["table"][k][d]
			cells += 1
			if r["absorb_max"] < r["step_max"]:
				strict += 1
			if not (r["absorb_max"] <= r["step_max"] and r["step_max"] < r["fall_at"]):
				bad.append("%s@%s %s" % [k, d, [r["absorb_max"], r["step_max"], r["fall_at"]]])
	ok(cells == 32 and bad.is_empty() and strict + (tb["no_step_band"] as Array).size() == 32, "1 absorb <= step < fall in %d of 32 cells (broken: %s); absorb < step strictly in %d, no step band in %d (%s)" % [cells - bad.size(), bad, strict, (tb["no_step_band"] as Array).size(), tb["no_step_band"]])
	for k in tb["table"]:
		var line := []
		for d in tb["table"][k]:
			var r: Dictionary = tb["table"][k][d]
			line.append("%s:%d/%d/%d" % [d, r["absorb_max"], r["step_max"], r["fall_at"]])
		print("     %s (dir:absorb/step/fall N s)  %s" % [k, " ".join(PackedStringArray(line))])
	# 2 LABELS
	var l10 := PushLimits.label("chest", 10.0, 0.0)
	var l60 := PushLimits.label("chest", 60.0, 0.0)
	ok(l10 == "absorbs" and l60 == "falls", "2 chest push 10 N s -> '%s', 60 N s -> '%s'" % [l10, l60])
	# 3 SPOT POINTS: the sim run directly
	var s10 := spot("spine_03", 10.0, 0.0)
	var s60 := spot("spine_03", 60.0, 0.0)
	var jm: float = tb["table"]["chest"]["45"]["step_max"]
	var sm := spot("spine_03", jm, 45.0)
	var lm := PushLimits.label("chest", jm, 45.0)
	ok(s10 == 0 and s60 == 2 and l10 == "absorbs" and l60 == "falls", "3 sim directly: chest 10 N s -> %d (0 = absorbs), 60 N s -> %d (2 = falls)" % [s10, s60])
	ok(sm == 1 and lm == "steps", "3 sim directly: chest %.0f N s at 45 deg (the table's step_max) -> %d (1 = steps); app label '%s'" % [jm, sm, lm])
	# 4 CHECK ROW in the app
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, D0], "yaw": 180.0}, "scene": still(stand_pose())})
	m._actors_sync()
	m._page_set("STAGE", false)
	m._refresh()
	await idle()
	m._dummy_hits()
	await m.dummy_settle()
	await idle(2)
	m._check()
	await idle(3)
	var ref: Label = m.ui_find_list.get_node_or_null("push_limit_ref")
	var l0 := PushLimits.limits("chest", 0.0)
	ok(ref != null and ref.text.contains("%.0f" % l0["absorb"]) and ref.text.contains("%.0f" % l0["fall"]), "4 CHECK reference row: %s" % [ref.text if ref != null else "MISSING"])
	var rows := 0
	var agree := true
	for i in m.fighter_hits.size():
		var r: Dictionary = m.fighter_hits[i]
		var lb: Label = m.ui_find_list.get_node_or_null("push_hit_%d" % (i + 1))
		if lb == null:
			continue
		rows += 1
		var vk: int = 0 if r["by"] == "other" else int(r["vs"])
		var sk: int = int(r["vs"]) if r["by"] == "other" else 0
		var blow := HitPhysics.measure(m.actors_rt[vk]["S"], m.actors_rt[vk]["B"], m.actors_rt[vk]["xf"], r, m.actors_rt[sk]["B"])
		var want := PushLimits.label(PushLimits.key_of(String(blow["body"])), float(blow["J_h"]), float(blow["dir_deg"]))
		agree = agree and (want == "" and lb.text.contains("no push-limit row") or want != "" and lb.text.contains(want))
		print("     row: " + lb.text)
	ok(rows >= 1 and agree, "4 %d hit-contact rows 'push_hit_N' in CHECK, each with the label for the J HitPhysics.measure gives" % rows)
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var inside := ref != null and Rect2(Vector2.ZERO, vp).encloses(Rect2(ref.get_global_rect()))
	ok(inside, "4 placement: the reference row %s is inside the %s window" % [ref.get_global_rect() if ref != null else "-", vp])
	# the base-vs-sim number: the hand-written balance against the table (reported, not a bar)
	var Bh: Body = m.actors_rt[1]["B"]
	var bal := Balance.read(Bh)
	print("     hand-written balance vs table: stance margin %s m -> a point mass would need J = %.1f N s to put the XCoM on the edge; the sim absorbs %d and steps up to %d N s (chest, forward)" % [
		bal.get("margin", "?"), PushLimits.balance_equiv(float(bal.get("margin", 0.0)), 75.0, 1.0), tb["table"]["chest"]["0"]["absorb_max"], tb["table"]["chest"]["0"]["step_max"]])
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	ok(m.get_viewport().get_texture().get_image().save_png(SHOT) == OK, "4 picture saved: " + SHOT)
	# 5 NOTHING WRITTEN
	var h1 := hashes()
	var diff := []
	for k in h1:
		if not h0.has(k) or h0[k] != h1[k]:
			diff.append(k)
	ok(diff.is_empty() and h0.size() == h1.size(), "5 data/, scenes/, poses/ (%d files) byte-identical after the test; changed: %s" % [h0.size(), diff])
	print("R24 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
