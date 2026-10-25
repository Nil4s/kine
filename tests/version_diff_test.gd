## godot --path . -s tests/version_diff_test.gd [-- shot=<png>]   (ROADMAP 28, COMPARE WITH; a window: main is built)
## Two versions in user:// only: OLD = start / reach / hold (3 cards, moves 0.5 s each, the hold's elbow at 60 deg); NEW =
## the same with 'reach' retimed (move 0.5 -> 1.0) and 'hold' elbow 60 -> 90 deg. Expected rows, exactly: retimed reach
## (1.30 s -> 1.80 s), joints hold lowerarm_r 30.0 deg. Identical versions: no rows, no marks. The ghost at the playhead:
## the old version's joints and joint positions, 0 diff. Restore: one undo step, and Ctrl+Z-equivalent takes it back.
## With shot=<png> the screen with the ghost and the diff list is saved to that file (the one shot, not a check).
extends SceneTree

var fails := 0
var m: Node
const DIR := "user://vdiff_test"
const OLD := "user://vdiff_test/v001.json"
const SAME := "user://vdiff_test/v_same.json"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


## a pose: the upper arm and the elbow (lowerarm_r) bent, every other joint at 0; the body's own dictionary
func pose_dict(upper: float, elbow: float) -> Dictionary:
	for j in Body.ORDER:
		m.B.ang[j] = Vector3.ZERO
	m.B.ang["upperarm_r"] = Vector3(upper, 0, 0)
	m.B.ang["lowerarm_r"] = Vector3(elbow, 0, 0)
	m.B.fk()
	return m.B.to_dict()


func cleanup() -> void:
	for f in [OLD, SAME]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	cleanup()
	# OLD: three cards, every move set (no auto time), written to user:// the way _save_version writes one
	m._new_scene()
	m.S.name = "_wip/zz_vdiff"
	m.S.add("start", pose_dict(0, 0))
	m.S.add("reach", pose_dict(40, 30))
	m.S.add("hold", pose_dict(40, 60))
	for c in m.S.cards:
		c["move"] = 0.5
	m._write(OLD, m._scene_dict())
	# NEW: 'reach' retimed, 'hold' elbow changed by 30 deg
	m.S.cards[1]["move"] = 1.0
	m.S.cards[2]["pose"] = pose_dict(40, 90)
	m._refresh()
	await idle()
	# a real menu entry: the compare item for the first version (ids 50+i), as the menu's pick
	m._version_paths = [OLD]
	m._version_picked(50)
	await idle(3)
	var rows: Array = m.vdiff.get("rows", [])
	var r_reach: Dictionary = rows[0] if rows.size() > 0 else {}
	var r_hold: Dictionary = rows[1] if rows.size() > 1 else {}
	# the first card has no move (it starts the scene): reach starts at the first hold's end (0.3 s), so its arrival is
	# 0.8 s (move 0.5) before and 1.3 s (move 1.0) now
	ok(rows.size() == 2 and r_reach.get("kind", "") == "retimed" and r_reach.get("name", "") == "reach"
		and absf(float(r_reach.get("t", 0.0)) - 1.3) < 1e-3 and "0.80 s -> 1.30 s" in String(r_reach.get("detail", "")),
		"1 the retimed card: %s" % [r_reach])
	ok(r_hold.get("kind", "") == "joints" and r_hold.get("name", "") == "hold" and r_hold.get("joint", "") == "lowerarm_r"
		and absf(float(r_hold.get("deg", 0.0)) - 30.0) < 0.05 and int(r_hold.get("n", 0)) == 1,
		"2 the elbow: exactly one joint, lowerarm_r, %.2f deg (%s)" % [float(r_hold.get("deg", 0.0)), r_hold])
	var marks: Array = m.vdiff.get("marks", [])
	ok(marks.size() > 0 and float(marks[-1]["t"]) >= 2.3 and float(marks[0]["t"]) < 1.3,
		"3 frame marks where a joint differs over 2 deg: %d, from %.2f s to %.2f s" % [marks.size(), float(marks[0]["t"]) if marks.size() > 0 else -1.0, float(marks[-1]["t"]) if marks.size() > 0 else -1.0])
	ok(m.ui_vdiff.visible and "~ retimed" in m.ui_vdiff_text.text and "~ joints" in m.ui_vdiff_text.text and "lowerarm_r 30.0°" in m.ui_vdiff_text.text,
		"4 the diff list is on screen (%s): %s" % [m.ui_vdiff.visible, m.ui_vdiff_text.text.replace("
", " | ")])
	# the ghost: the old version's body at the playhead, joint by joint (angles and positions), 0 diff
	var t := 1.0
	m.playhead = t
	m._refresh()
	m.ov.version_ghost(m.vdiff["scene"], t)
	var fresh := Body.new()
	fresh.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	(m.vdiff["scene"] as Scene).apply(fresh, t)
	var worst := 0.0
	for j in Body.ORDER:
		worst = maxf(worst, (m.ov.GB.ang[j] - fresh.ang[j]).length())
		worst = maxf(worst, (m.ov.GB.P[j] - fresh.P[j]).length())
	ok(worst < 1e-6 and m.ov._ghosts[5][0].visible, "5 the ghost at %.1f s = the old version's pose, joint by joint: worst diff %s" % [t, str(worst)])
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			shot = a.trim_prefix("shot=")
	if shot != "":
		m.playhead = 2.4
		m._refresh()
		await idle(2)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shot)
		print("shot saved: %s" % shot)
	# restore: the compared version as the cards, one undo step; undo takes it back
	var u0: int = m.undo.size()
	m._version_picked(3)
	await idle(2)
	var back_move: float = m.S.cards[1]["move"]
	var back_ok: bool = back_move == 0.5 and m.S.cards.size() == 3 and m.undo.size() == u0 + 1 and m.vdiff.is_empty()
	ok(back_ok, "6 restore this one: reach's move %.2f, %d cards, +%d undo step, comparing off" % [back_move, m.S.cards.size(), m.undo.size() - u0])
	m._undo()
	await idle(2)
	ok(m.S.cards[1]["move"] == 1.0, "7 undo: reach's move back to %.2f" % m.S.cards[1]["move"])
	# identical: the open scene made the old way (one restore), compared with itself
	m._open_version(OLD)
	m._write(SAME, m._scene_dict())   # the open scene as it is now = the old version's cards
	m._version_paths = [SAME]
	m._version_picked(50)
	await idle(2)
	ok(m.vdiff["rows"].is_empty() and m.vdiff["marks"].is_empty() and "no differences" in m.ui_vdiff_text.text,
		"8 identical versions: %d rows, %d marks" % [m.vdiff["rows"].size(), m.vdiff["marks"].size()])
	m._vdiff_clear()
	cleanup()
	var left := FileAccess.file_exists(OLD) or FileAccess.file_exists(SAME) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIR))
	ok(not left, "9 everything it wrote in user:// removed (%s)" % left)
	print("VERSION_DIFF: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
