## godot --path . -s tests/easygen_test.gd     (MAKE IT WITH AI VIDEO in Easy, "monkey brain easy"; needs a window)
## RETAKE (7-10): one retake when the first take is bad (EasyTake), under a fake tracker (tests/py/see_video_stub.py) and the stand-in generator; 0a-0k: the score on synthetic arrays
## No ComfyUI here: main's gen_move points at a stand-in (tests/py/gen_video_stub.py) that copies the video_import_test clip
## (GEN_STUB_SRC), or makes nothing (ComfyUI down), or sleeps first (GEN_STUB_SLEEP, for Cancel). The tracking and the landing are the real ones.
## BARS (stated before measuring):
##  1 typed "backflip" (Kine cannot build it): the plain reason on the message line AND the one button "Make it with AI video (about 3 minutes)"
##  2 typed "punch" (a known word, a template): it builds, and NO button
##  3 with the stand-in clip: clicking the button shows "Making the video" on the say line, then the clip lands: at least 2 cards, playing
##  4 one Undo after that success gives back the card count the scene had before it (the punch clip's)
##  5 ComfyUI down (the stand-in makes nothing): the one plain sentence on the message line and the say line, cards unchanged, no script error
##  6 Cancel mid-run (a stand-in that sleeps): the generator is stopped, "Stopped. Nothing was changed.", card count and undo size unchanged
##  8 the Easy generator call (first take AND the retake) carries the FAST setting: --steps 20 --width 640 --height 368
##  9 the message says "about 3 minutes" (the button, and the retake line "about 3 more minutes")
## 10 the one plain line under the button: what it does and that it takes about 3 minutes (shown with the button)
## 11 the AI video maker not set up here (comfy_main missing): no button, no line, the plain "isn't set up" line shows, Make does nothing
## 12 the failed button's sentence carries no path, no colon and no slash (a beginner should not see a stack trace or a folder)
## 0l-0o THE STILL BAR (EasyTake.frozen_fraction): the jab file (tracked well, a statue) is bad; the real moving take is good with its
##     old score; a still clip with good tracking is bad; a moving synthetic clip reads 0 still
## 7e a still first take is made again with the next seed, and the moving retake is imported; 7f two still takes import nothing and
##     say "The AI video barely moved..." (both fail on the old code: a still take was judged good)
extends SceneTree

const CLIP := "res://tests/fixtures/fps16_hammer_2s.webm"
const WORDS := "backflip"
const NOT_RUNNING := "The AI video maker is not running on this computer, so this move can't be made. Try one of the cards."
const BUTTON := "Make it with AI video (about 3 minutes)"
const WHY := "The computer makes a short video of a person doing it, then copies the move. Takes about 3 minutes."
const NA_LINE := "AI video isn't set up on this computer."
const BARELY := "The AI video barely moved. Try other words, like 'throws a fast punch'."
const STUB_MAIN := "res://tests/py/gen_video_stub.py"   # the ComfyUI entry point this test counts as present (no D:/ComfyUI needed)
const NO_MAIN := "res://tests/py/no_comfyui_here/main.py"   # a missing one: the maker is not set up

var fails := 0
var m: Node
var home: EasyHome


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func make_btn() -> Button:
	return home.panel.find_child("eh_make_ai", true, false) as Button


func cancel_btn() -> Button:
	return home.panel.find_child("eh_gen_cancel", true, false) as Button


## a typed line, as the panel's text box submits it
func type_line(t: String) -> void:
	home._change()
	home._edit.text = t
	home._edit.text_submitted.emit(t)
	await idle(3)


## wait (bounded) until the generator is no longer making the clip and the copy-style landing is over
func wait_run(limit_s: float) -> void:
	var t_end := Time.get_ticks_msec() + int(limit_s * 1000.0)
	while Time.get_ticks_msec() < t_end and (home._gen_on or home._vid_busy):
		await process_frame


## the score on synthetic visibility arrays (EasyTake): 33 landmarks per tracked frame
func frames_of(n: int, vis := 0.95, lost_hand := false, lost_foot := false) -> Array:
	var out := []
	for i in n:
		var v := []
		for k in 33:
			v.append(vis)
		if lost_hand:
			for k in [15, 17, 19, 21]:
				v[k] = 0.1
		if lost_foot:
			for k in [27, 29, 31]:
				v[k] = 0.45
		out.append(v)
	return out


## a clip of n tracked frames of one body: shoulders at y 0.3, ankles at y 0.8 (body height 0.5), every point moved sideways
## by step per frame (0 = a statue)
func xy_of(n: int, step: float) -> Array:
	var out := []
	for i in n:
		var pts := []
		for k in 33:
			var y := 0.3 if k in [11, 12] else (0.8 if k in [27, 28] else 0.5)
			pts.append([0.4 + step * i, y])
		out.append(pts)
	return out


func unit_bar() -> void:
	var g := EasyTake.score(frames_of(81), 81)
	ok(not g["bad"] and absf(float(g["score"]) - 0.95) < 1e-6 and float(g["found"]) == 1.0,
		"0a score: 81 of 81 frames whole at 0.95 is good (score %.3f, found %.2f)" % [g["score"], g["found"]])
	var half := EasyTake.score(frames_of(40), 81)
	ok(bool(half["bad"]) and float(half["found"]) < 0.5, "0b a person in 40 of 81 frames is bad (found %.3f, score %.3f)" % [half["found"], half["score"]])
	var at_line := EasyTake.score(frames_of(1, 1.0), 2)
	ok(not at_line["bad"] and absf(float(at_line["score"]) - 0.5) < 1e-9, "0c score exactly 0.5 is not bad (score %.3f)" % at_line["score"])
	var under := EasyTake.score(frames_of(1, 0.99), 2)
	ok(bool(under["bad"]), "0d score 0.49 is bad (score %.3f)" % under["score"])
	var one_lost := EasyTake.score(frames_of(80), 81)
	ok(not one_lost["bad"] and absf(float(one_lost["lost"]) - 1.0 / 81.0) < 1e-6, "0e one lost frame of 81 is good (lost %.4f, score %.4f)" % [one_lost["lost"], one_lost["score"]])
	var hand := EasyTake.score(frames_of(81, 0.95, true), 81)
	ok(bool(hand["bad"]) and float(hand["lost"]) == 1.0, "0f a hand lost in every frame is bad (score %.3f)" % hand["score"])
	var foot := EasyTake.score(frames_of(81, 0.95, false, true), 81)
	ok(bool(foot["bad"]), "0g a foot lost in every frame is bad (score %.3f)" % foot["score"])
	var soft := EasyTake.score(frames_of(81, 0.6), 81)
	ok(not soft["bad"] and absf(float(soft["score"]) - 0.6) < 1e-6, "0h everything at 0.6, no lost frame, is good (score %.3f)" % soft["score"])
	var seen_only := EasyTake.score(frames_of(60, 0.9), 81)
	ok(not seen_only["bad"], "0i 60 of 81 frames at 0.9 is good (found %.2f, score %.3f)" % [seen_only["found"], seen_only["score"]])
	var none := EasyTake.score([], 81)
	ok(bool(none["bad"]) and float(none["found"]) == 0.0, "0j no frames at all is bad")
	var no_seen := EasyTake.score(frames_of(5), 0)
	ok(bool(no_seen["bad"]), "0k a clip with no sampled frames count is bad")
	# 0l the jab file: its tracking is fine (the old score alone passes), it is still for most of the clip: bad
	var jab := EasyTake.judge("res://tests/fixtures/easy_jab_frozen_pose.json")
	ok(bool(jab["bad"]) and float(jab.get("frozen", 0.0)) > 0.5 and float(jab["score"]) >= EasyTake.BAD_SCORE,
		"0l the jab file is BAD for still: still %.3f (bar > 0.5), tracking score %.3f (passes alone)" % [float(jab.get("frozen", 0.0)), jab["score"]])
	# 0m the real moving take (gen_hammer, tracked): good, still for 1 % of its clip, its tracking score unchanged (0.862)
	var mov := EasyTake.judge("res://tests/fixtures/vidspeed_pose_A.json")
	ok(not bool(mov["bad"]) and float(mov.get("frozen", 1.0)) < 0.1 and absf(float(mov["score"]) - 0.862) < 0.005,
		"0m the moving take is good: still %.3f (bar 0.5), score %.3f (was 0.862)" % [float(mov.get("frozen", 1.0)), mov["score"]])
	# 0n a still clip with good tracking is bad; 0o a moving one with the same frames reads 0 still
	var statue := EasyTake.frozen_fraction(xy_of(81, 0.0), 81)
	var walk := EasyTake.frozen_fraction(xy_of(81, 0.02), 81)
	ok(statue > 0.9 and walk == 0.0, "0n a statue (every frame the same) reads still %.3f; 0o a walk of 0.04 body heights a frame reads still %.3f" % [statue, walk])
	ok(bool(EasyTake.score(frames_of(81), 81, 1.0)["bad"]) and not bool(EasyTake.score(frames_of(81), 81, 0.5)["bad"]),
		"0p still 1.0 with good tracking is bad; still exactly 0.5 is not")


## the arguments of each generator call (GEN_STUB_ARGS, a JSON list per line) as Arrays of strings
func args_of(path: String) -> Array:
	var out := []
	for l in lines_of(path):
		out.append(JSON.parse_string(String(l)))
	return out


## the value after a flag in one call's arguments, "" when the flag is not there
func flag_of(argv: Array, flag: String) -> String:
	var i := argv.find(flag)
	return String(argv[i + 1]) if i >= 0 and i + 1 < argv.size() else ""


## a call carries the Easy fast setting: 20 steps at 640x368
func is_fast(argv: Variant) -> bool:
	return argv is Array and flag_of(argv, "--steps") == "20" and flag_of(argv, "--width") == "640" and flag_of(argv, "--height") == "368"


func lines_of(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	return Array(FileAccess.get_file_as_string(path).split("\n", false))


## one press of MAKE IT WITH AI VIDEO on the typed move, under the fake tracker's plan, run to its end. stop_at > 0: Cancel is
## pressed once that many generator runs have started. Returns what the beginner sees and what is left on disk.
func take_run(label: String, plan: String, slow_call := 0, stop_at := 0) -> Dictionary:
	var gl: String = String(m.gen_move.out_dir).path_join(label + "_gen.log")
	var tl: String = String(m.gen_move.out_dir).path_join(label + "_trk.log")
	var al: String = String(m.gen_move.out_dir).path_join(label + "_args.log")
	OS.set_environment("GEN_STUB_LOG", gl)
	OS.set_environment("GEN_STUB_ARGS", al)
	OS.set_environment("TRK_STUB_LOG", tl)
	OS.set_environment("TRK_STUB_PLAN", plan)
	OS.set_environment("GEN_STUB_SLOW_CALL", str(slow_call))
	OS.set_environment("GEN_STUB_SLEEP", "30" if slow_call > 0 else "")
	var c0: int = m.S.cards.size()
	var sp0: String = m.scene_path
	var u0: int = m.undo.size()
	make_btn().pressed.emit()
	var saw := ""
	var cancelled := false
	var seen_cancel := false
	var t_end := Time.get_ticks_msec() + 240000
	while Time.get_ticks_msec() < t_end and (home._gen_on or home._vid_busy):
		await process_frame
		var st := String(m.ui_status.text)
		if st.begins_with("That video came out unclear") and saw == "":
			saw = st
		if stop_at > 0 and not cancelled and lines_of(gl).size() >= stop_at:
			seen_cancel = cancel_btn() != null and cancel_btn().visible
			cancel_btn().pressed.emit()
			cancelled = true
	await idle(4)
	var left := []
	for f in lines_of(gl):
		if FileAccess.file_exists(String(f)):
			left.append(String(f))
	var first_gone := true
	var rows := lines_of(tl)
	for i in rows.size():
		var c := String(rows[i]).split("\t")
		for f in [c[1], c[2]]:
			if FileAccess.file_exists(String(f)):
				left.append(String(f))
				if i == 0:
					first_gone = false
	var first_gen: String = String(lines_of(gl)[0]) if not lines_of(gl).is_empty() else ""
	if first_gen != "" and FileAccess.file_exists(first_gen):
		first_gone = false
		left.append(first_gen)
	return {"gens": lines_of(gl).size(), "tracks": rows.size(), "saw": saw, "msg": String(home._msg.text),
		"status": String(m.ui_status.text), "cards": m.S.cards.size(), "added": m.S.cards.size() - c0,
		"moved": m.scene_path != sp0, "undo": m.undo.size() - u0, "left": left, "first_gone": first_gone,
		"cancelled": cancelled, "seen_cancel": seen_cancel, "wip": m.scene_path.begins_with("res://scenes/_wip/"),
		"args": args_of(al),
		"landed": m.scene_path, "playing": m.playing}


func _init() -> void:
	unit_bar()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var dir := OS.get_user_data_dir().path_join("easygen_test_%d" % OS.get_process_id())
	m.gen_move.out_dir = dir
	m.gen_move.tool = "res://tests/py/gen_video_stub.py"
	m.gen_move.comfy_main = STUB_MAIN   # the maker counts as set up here (bars 1-9); bar 11 points it at a missing one
	m.easy.set_on(true, false)
	m._new_scene()
	await idle(3)
	home = m.easy.home

	# 1 unknown words: the reason and the button
	await type_line(WORDS)
	var msg := String(home._msg.text)
	ok(msg.begins_with("Kine can't build") and make_btn() != null and make_btn().visible and make_btn().text == BUTTON,
		"1 typed \"%s\": reason \"%s\", button shown %s" % [WORDS, msg, make_btn().visible if make_btn() != null else false])

	# 10 the plain line under the button says what it does and how long (the same panel, shown with the button)
	var why := home.panel.find_child("eh_make_why", true, false) as Label
	var why_ok: bool = why != null and why.visible and why.text == WHY and make_btn().visible
	ok(why_ok, "10 the explaining line under the button: shown %s, \"%s\"" % [why != null and why.visible, why.text if why != null else "(no line)"])

	# 11 the maker is not set up here: no button and no explaining line, one plain sentence instead; Make does nothing
	m.gen_move.comfy_main = NO_MAIN
	await type_line(WORDS)
	var na := home.panel.find_child("eh_ai_no", true, false) as Label
	var why11 := home.panel.find_child("eh_make_why", true, false) as Label
	var na_shown: bool = na != null and na.visible and na.text == NA_LINE
	var btn_hidden: bool = make_btn() != null and not make_btn().visible and why11 != null and not why11.visible
	var busy0: bool = m.gen_move.busy()
	home.make_ai()
	await idle(3)
	ok(na_shown and btn_hidden and not busy0 and not m.gen_move.busy() and not home._gen_on and String(home._msg.text) == NA_LINE,
		"11 maker not set up: button hidden %s, plain line shown %s (\"%s\"), Make starts nothing %s"
		% [btn_hidden, na_shown, na.text if na != null else "(no line)", not m.gen_move.busy()])
	m.gen_move.comfy_main = STUB_MAIN
	await type_line(WORDS)
	ok(make_btn().visible and not (na != null and na.visible), "11 set up again: the button is back and the plain line is hidden")

	# 2 a known word builds, no button
	await type_line("punch")
	await idle(3)
	var n0: int = m.S.cards.size()
	ok(n0 >= 1 and make_btn() != null and not make_btn().visible and home._gen_words == "",
		"2 typed \"punch\": builds %d cards, no button" % n0)

	# 3 the stand-in clip: the progress sentence, then it lands and plays
	await type_line(WORDS)
	ok(make_btn().visible, "3 the button is up again for \"%s\" (scene %d cards)" % [WORDS, m.S.cards.size()])
	OS.set_environment("GEN_STUB_SRC", ProjectSettings.globalize_path(CLIP))
	OS.set_environment("GEN_STUB_SLEEP", "")
	var u0: int = m.undo.size()
	var before: String = m.scene_path
	make_btn().pressed.emit()
	var saw := false
	var t_end := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < t_end:   # the progress line, while the generator runs
		await process_frame
		if String(m.ui_status.text).begins_with("Making the video"):
			saw = true
	await wait_run(240.0)
	await idle(6)
	var c1: int = m.S.cards.size()
	var landed: String = m.scene_path
	ok(saw and c1 >= 2 and m.playing and landed != before and landed.begins_with("res://scenes/_wip/"),
		"3 the clip made and landed: %d cards (bar >= 2), playing %s, progress line seen %s, scene %s, say: \"%s\"" % [c1, m.playing, saw, landed.get_file(), m.ui_status.text])
	var u1: int = m.undo.size()
	ok(u1 == u0 + 1, "3 one undo step for the landing (undo %d -> %d)" % [u0, u1])
	if landed.begins_with("res://scenes/_wip/"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(landed))

	# 4 one Undo gives back the punch clip's card count
	m._undo()
	await idle(3)
	ok(m.S.cards.size() == n0, "4 one Undo: %d cards (before the make: %d)" % [m.S.cards.size(), n0])

	# 5 ComfyUI down: one plain sentence, nothing changes
	OS.set_environment("GEN_STUB_SRC", "")
	await type_line(WORDS)
	var n5: int = m.S.cards.size()
	var sp5: String = m.scene_path
	make_btn().pressed.emit()
	await wait_run(60.0)
	await idle(4)
	ok(String(home._msg.text) == NOT_RUNNING and String(m.ui_status.text) == NOT_RUNNING and not home._gen_on
		and m.S.cards.size() == n5 and m.scene_path == sp5,
		"5 ComfyUI down: \"%s\" (cards %d, as before)" % [m.ui_status.text, m.S.cards.size()])

	# 12 the failed button's sentence is plain: no path, colon or slash (no stack trace, no folder)
	var plain := true
	for s in [String(home._msg.text), String(m.ui_status.text)]:
		plain = plain and not (s.contains("/") or s.contains("\\") or s.contains(":") or s.contains("res://"))
	ok(plain and home._msg.text != "", "12 the failed button's sentences carry no path or colon: \"%s\" / \"%s\"" % [home._msg.text, m.ui_status.text])

	# 6 Cancel mid-run: the generator is stopped and nothing changes
	OS.set_environment("GEN_STUB_SRC", ProjectSettings.globalize_path(CLIP))
	OS.set_environment("GEN_STUB_SLEEP", "30")
	await idle(2)
	make_btn().pressed.emit()
	var t_run := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < t_run and not m.gen_move.busy():
		await process_frame
	await idle(3)
	var c6: int = m.S.cards.size()
	var u6: int = m.undo.size()
	var seen_cancel := cancel_btn() != null and cancel_btn().visible
	cancel_btn().pressed.emit()
	await idle(4)
	ok(seen_cancel and not m.gen_move.busy() and not home._gen_on and String(m.ui_status.text) == "Stopped. Nothing was changed."
		and m.S.cards.size() == c6 and m.undo.size() == u6,
		"6 Cancel mid-run: cancel shown %s, generator stopped %s, say \"%s\", cards %d (as before %d), undo %d (as before %d)"
		% [seen_cancel, not m.gen_move.busy(), m.ui_status.text, m.S.cards.size(), c6, m.undo.size(), u6])
	OS.set_environment("GEN_STUB_SLEEP", "")

	# 7 - 10 THE RETAKE (EasyTake): the tracker is the fake (tests/py/see_video_stub.py, TRK_STUB_PLAN in call order), the
	# generator the stand-in. Good first take: one generation. A bad one: one more with seed + 1; the good take is imported.
	m.video_tool = "res://tests/py/see_video_stub.py"
	await type_line("punch")
	await idle(2)
	await type_line(WORDS)
	var retake_line := "That video came out unclear. Making another one (about %d more minutes)" % EasyTake.TAKE_MINUTES

	var a := await take_run("a", "good")
	ok(a["gens"] == 1 and a["tracks"] == 1 and a["saw"] == "" and a["wip"] and m.S.cards.size() >= 2 and a["left"].size() >= 1 and a["msg"] == "",
		"7a good first take: %d generation, %d tracking, no retake line, landed %s (%d cards, playing %s)"
		% [a["gens"], a["tracks"], String(a["landed"]).get_file(), m.S.cards.size(), a["playing"]])
	if a["wip"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(String(a["landed"])))
	for f in a["left"]:
		DirAccess.remove_absolute(String(f))
	await type_line(WORDS)

	var b := await take_run("b", "lost,good")
	ok(b["gens"] == 2 and b["tracks"] == 2 and b["saw"].begins_with(retake_line) and b["wip"] and m.S.cards.size() >= 2
		and b["undo"] == 1 and b["first_gone"] and b["msg"] == "",
		"7b bad then good: %d generations, %d trackings, the message \"%s\" seen %s, landed %s (undo +%d), the first take's files gone %s"
		% [b["gens"], b["tracks"], retake_line, b["saw"] != "", String(b["landed"]).get_file(), b["undo"], b["first_gone"]])
	if b["wip"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(String(b["landed"])))
	for f in b["left"]:
		if FileAccess.file_exists(String(f)):
			DirAccess.remove_absolute(String(f))
	await type_line(WORDS)

	var c := await take_run("c", "bad,bad")
	ok(c["gens"] == 2 and c["tracks"] == 2 and not c["moved"] and c["added"] == 0 and c["undo"] == 0 and c["msg"] == EasyHome.NO_PERSON
		and c["left"].is_empty() and home._gen_words != "" and make_btn().visible,
		"7c bad then bad: %d generations, %d trackings, nothing imported (scene moved %s, cards %+d, undo %+d), message \"%s\", no files left %s"
		% [c["gens"], c["tracks"], c["moved"], c["added"], c["undo"], c["msg"], c["left"].is_empty()])

	# 8 the fast setting: the first take's one call, and both calls of the retake (b), carry 20 steps at 640x368
	var fast_a: bool = a["args"].size() == 1 and is_fast(a["args"][0])
	var fast_b: bool = b["args"].size() == 2 and is_fast(b["args"][0]) and is_fast(b["args"][1])
	ok(fast_a and fast_b, "8 Easy's generator calls carry --steps 20 --width 640 --height 368: first take %s, retake %s (call args %s / %s)"
		% [fast_a, fast_b, str(a["args"]), str(b["args"])])
	# 9 the time the beginner is told: about 3 minutes (the button, the retake line)
	ok(BUTTON.ends_with("(about 3 minutes)") and EasyTake.TAKE_MINUTES == 3 and b["saw"].begins_with("That video came out unclear. Making another one (about 3 more minutes)"),
		"9 the button says \"%s\" and the retake line says \"about 3 more minutes\" (seen: \"%s\")" % [BUTTON, String(b["saw"]).substr(0, 80)])

	var d := await take_run("d", "bad", 2, 2)
	ok(d["cancelled"] and d["seen_cancel"] and d["gens"] == 2 and d["tracks"] == 1 and not d["moved"] and d["added"] == 0 and d["undo"] == 0
		and d["status"] == "Stopped. Nothing was changed." and d["left"].is_empty() and not home._gen_on and not m.gen_move.busy()
		and not m.video_gate.is_valid(),
		"7d Cancel during the retake: Cancel shown %s, %d generations, nothing imported (cards %+d, undo %+d), say \"%s\", no files left %s"
		% [d["seen_cancel"], d["gens"], d["added"], d["undo"], d["status"], d["left"].is_empty()])

	# 7e - 7f THE STILL TAKE: a first take the person holds still is made again; the moving retake is imported
	await type_line(WORDS)
	var e := await take_run("e", "frozen,good")
	ok(e["gens"] == 2 and e["tracks"] == 2 and e["saw"].begins_with(retake_line) and e["wip"] and m.S.cards.size() >= 2
		and e["undo"] == 1 and e["first_gone"] and e["msg"] == "",
		"7e still then moving: %d generations, %d trackings, the retake line seen %s, landed %s (undo +%d), the still take's files gone %s"
		% [e["gens"], e["tracks"], e["saw"] != "", String(e["landed"]).get_file(), e["undo"], e["first_gone"]])
	if e["wip"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(String(e["landed"])))
	for f in e["left"]:
		if FileAccess.file_exists(String(f)):
			DirAccess.remove_absolute(String(f))
	# 7f two still takes: nothing imported, and the sentence says the video barely moved
	await type_line(WORDS)
	var f7 := await take_run("f", "frozen,frozen")
	ok(f7["gens"] == 2 and f7["tracks"] == 2 and not f7["moved"] and f7["added"] == 0 and f7["undo"] == 0 and f7["msg"] == BARELY
		and f7["left"].is_empty() and home._gen_words != "" and make_btn().visible,
		"7f still then still: %d generations, %d trackings, nothing imported (scene moved %s, cards %+d), message \"%s\", no files left %s"
		% [f7["gens"], f7["tracks"], f7["moved"], f7["added"], f7["msg"], f7["left"].is_empty()])

	m.video_tool = "res://tools/see_video.py"
	OS.set_environment("GEN_STUB_LOG", "")
	OS.set_environment("GEN_STUB_ARGS", "")
	OS.set_environment("TRK_STUB_LOG", "")
	OS.set_environment("GEN_STUB_SLOW_CALL", "")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	m.easy.set_on(false, false)
	m.queue_free()
	print("EASY GEN TEST ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
