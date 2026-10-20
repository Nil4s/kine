## godot --path . -s tests/r12_test.gd     (ROADMAP round 2, R12: saved characters + the blend in the scene; needs a window)
## Files: only user://zz_r12_chars/ (the panel's chars_dir is pointed there; removed after) and user://zz_r12_scene.json.
## BARS, written before measuring:
##  1 SAVE / CHANGE / LOAD: seven sliders set, saved, every slider moved elsewhere, load -> each slider's value and
##    the pr dict equal the saved ones EXACTLY (==), and the body on the stage equals BodyModel.body_for(saved pr)
##  2 APPLY = ONE UNDO STEP: undo size +1; Ctrl+Z restores the body state and the scene JSON exactly
##  3 BLEND IN THE SCENE: blend 0.3 -> S.body["blend"] == 0.3; after a save to a file and a reopen the slider reads
##    30 and S.body has blend 0.3; the saved scene's "body" keys are all in the schema's key list
##  4 OLD SCENES UNCHANGED: scenes/combo3.json loads with an empty body and re-saves with no "body" key; a body without
##    "blend" (male_95 preset) is unchanged by clean() (idempotent, no blend key) with no blend key; pure man / woman write none
##  5 LIST + PLACEMENT: three characters on the BODY page: three rows, each inside the panel's rectangle, panel left of
##    the body; a click on a row applies it. Screenshot: jobs/9afc22db/tmp/r12.png
extends SceneTree

var m: Node
var fails := 0
const DIR := "user://zz_r12_chars"
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/r12.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func setpr(P: BodyPanel, pr: Dictionary) -> void:
	P.begin.emit()
	P.pr = pr.duplicate()
	P._set_sliders()
	P._show()
	P.commit.emit(BodyModel.body_for(P.pr))


func wipe() -> void:
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._page_set("BODY", false)
	await idle(4)
	var P: BodyPanel = m.ui_body
	P.chars_dir = DIR
	wipe()
	P.refresh_list()
	# ---- 1 save / change / load
	var A := {"blend": 0.0, "stat": 83.0, "mass": 35.5, "arm": 62.0, "leg": 71.5, "trunk": 28.0, "head": 44.5}
	setpr(P, A)
	await idle()
	ok(P.save_character("Ana") == "" and FileAccess.file_exists(DIR + "/Ana.json"), "1 saved 'Ana' to %s" % DIR)
	var saved_pr: Dictionary = P.pr.duplicate()
	var saved_sl := {}
	for k in P.sliders:
		saved_sl[k] = (P.sliders[k] as HSlider).value
	setpr(P, {"blend": 1.0, "stat": 10.0, "mass": 90.0, "arm": 15.0, "leg": 33.0, "trunk": 80.0, "head": 99.0})
	await idle()
	var moved := true
	for k in P.sliders:
		moved = moved and (P.sliders[k] as HSlider).value != saved_sl[k]
	ok(moved, "1 every one of the 7 sliders was moved away")
	var u0: int = m.undo.size()
	var scene_before := JSON.stringify(m.S.to_dict(m.B))
	var state_before := JSON.stringify(m.B.state())
	ok(P.apply_character("Ana"), "1 apply 'Ana'")
	await idle()
	var same := true
	var worst := 0.0
	for k in P.sliders:
		var v := (P.sliders[k] as HSlider).value
		same = same and v == saved_sl[k]
		worst = maxf(worst, absf(v - saved_sl[k]))
	ok(same and P.pr == saved_pr, "1 all 7 sliders restored exactly (worst difference %.6f); pr == saved pr: %s" % [worst, P.pr == saved_pr])
	ok(m.S.body == BodyModel.body_for(saved_pr), "1 the stage's body equals body_for(saved) (stature %.4f m)" % float(m.S.body.get("stature", 0)))
	# ---- 2 one undo step
	ok(m.undo.size() == u0 + 1, "2 apply = exactly one undo step (%d -> %d)" % [u0, m.undo.size()])
	m._undo()
	await idle()
	# the undo goes back to the body BEFORE the apply (the 10th/90 kg man), exactly
	ok(JSON.stringify(m.S.to_dict(m.B)) == scene_before and JSON.stringify(m.B.state()) == state_before, "2 Ctrl+Z gives back the body state and the scene JSON exactly")
	# ---- 3 blend in the scene
	setpr(P, {"blend": 0.3, "stat": 50.0, "mass": 50.0, "arm": 50.0, "leg": 50.0, "trunk": 50.0, "head": 50.0})
	await idle()
	ok(is_equal_approx(float(m.S.body.get("blend", -1.0)), 0.3) and m.S.body.get("sex") == "female", "3 scene body blend = %s, sex %s" % [m.S.body.get("blend"), m.S.body.get("sex")])
	var path := "user://zz_r12_scene.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(m._scene_dict(), " "))
	f.close()
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	var keys_ok := true
	var allowed: Array = (JSON.parse_string(FileAccess.get_file_as_string("res://docs/scene.schema.json"))["$defs"]["scene"]["properties"]["body"]["properties"] as Dictionary).keys()
	for k in raw["body"]:
		keys_ok = keys_ok and k in allowed
	setpr(P, BodyModel.DEFAULT)
	await idle()
	m._load_scene(path)
	await idle(3)
	P.sync(m.S.body, m.B, true)
	ok(keys_ok and is_equal_approx(float(m.S.body.get("blend", -1.0)), 0.3) and is_equal_approx((P.sliders["blend"] as HSlider).value, 30.0), "3 after save + reopen: file body keys %s all in the schema; S.body blend %s; blend slider %.1f" % [raw["body"].keys(), m.S.body.get("blend"), (P.sliders["blend"] as HSlider).value])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# ---- 4 old scenes
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	var d4: Dictionary = m._scene_dict()
	ok(m.S.body.is_empty() and not d4.has("body"), "4 scenes/combo3.json: empty body, no body key on save")
	var old := Proportions.preset("male_95")
	var pm := {"blend": 1.0, "stat": 50.0, "mass": 50.0, "arm": 50.0, "leg": 50.0, "trunk": 50.0, "head": 50.0}
	var pw := pm.duplicate()
	pw["blend"] = 0.0
	ok(not old.has("blend") and not Proportions.clean(old).has("blend") and Proportions.clean(Proportions.clean(old)) == Proportions.clean(old) and not BodyModel.body_for(pm).has("blend") and not BodyModel.body_for(pw).has("blend"), "4 a body without blend is unchanged by clean() (idempotent, no blend key); pure man / pure woman write no blend")
	# ---- 5 list + placement: three characters
	setpr(P, {"blend": 0.0, "stat": 83.0, "mass": 35.5, "arm": 62.0, "leg": 71.5, "trunk": 28.0, "head": 44.5})
	P.save_character("Ana")
	setpr(P, {"blend": 1.0, "stat": 95.0, "mass": 80.0, "arm": 55.0, "leg": 60.0, "trunk": 50.0, "head": 40.0})
	P.save_character("Big Joe")
	setpr(P, {"blend": 0.3, "stat": 20.0, "mass": 25.0, "arm": 50.0, "leg": 35.0, "trunk": 60.0, "head": 70.0})
	P.save_character("Mix 30")
	await idle(3)
	var rows := P.list_box.get_children()
	var inside := rows.size() == 3
	for r in rows:
		inside = inside and P.get_global_rect().encloses((r as Control).get_global_rect())
	ok(inside, "5 three rows in the list %s, each inside the panel rect %s" % [P.character_names(), P.get_global_rect()])
	var u1: int = m.undo.size()
	var btn: Button = P.list_box.get_node("char_Big Joe").get_child(0)
	btn.pressed.emit()
	await idle(3)
	await m._view(1)
	await idle(6)
	ok(m.undo.size() == u1 + 1 and absf(float(m.S.body["stature"]) - BodyModel.stature_at(1.0, 95.0)) < 0.001, "5 clicking 'Big Joe' applied the 95th man: stature %.3f m, one undo step" % float(m.S.body["stature"]))
	var lo := Vector2(INF, INF)
	for j in Body.ORDER:
		lo = lo.min(m.cam.unproject_position(m.B.P[j]))
	ok(P.get_global_rect().end.x <= lo.x and absf(m.B.sole_low()) < 0.005, "5 the panel ends at x=%.0f, the body starts at x=%.0f, soles %.1f mm off the floor" % [P.get_global_rect().end.x, lo.x, m.B.sole_low() * 1000.0])
	await RenderingServer.frame_post_draw
	m.get_viewport().get_texture().get_image().save_png(OUT)
	wipe()
	ok(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIR)), "scratch dir removed")
	print("R12 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
