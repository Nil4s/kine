## godot --path . -s tests/easygen_test.gd     (MAKE IT WITH AI VIDEO in Easy, "monkey brain easy"; needs a window)
## No ComfyUI here: main's gen_move points at a stand-in (tests/py/gen_video_stub.py) that copies the video_import_test clip
## (GEN_STUB_SRC), or makes nothing (ComfyUI down), or sleeps first (GEN_STUB_SLEEP, for Cancel). The tracking and the landing are the real ones.
## BARS (stated before measuring):
##  1 typed "backflip" (Kine cannot build it): the plain reason on the message line AND the one button "Make it with AI video (takes a few minutes)"
##  2 typed "punch" (a known word, a template): it builds, and NO button
##  3 with the stand-in clip: clicking the button shows "Making the video" on the say line, then the clip lands: at least 2 cards, playing
##  4 one Undo after that success gives back the card count the scene had before it (the punch clip's)
##  5 ComfyUI down (the stand-in makes nothing): the one plain sentence on the message line and the say line, cards unchanged, no script error
##  6 Cancel mid-run (a stand-in that sleeps): the generator is stopped, "Stopped. Nothing was changed.", card count and undo size unchanged
extends SceneTree

const CLIP := "res://tests/fixtures/fps16_hammer_2s.webm"
const WORDS := "backflip"
const NOT_RUNNING := "The AI video maker is not running on this computer, so this move can't be made. Try one of the cards."
const BUTTON := "Make it with AI video (takes a few minutes)"

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


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var dir := OS.get_user_data_dir().path_join("easygen_test_%d" % OS.get_process_id())
	m.gen_move.out_dir = dir
	m.gen_move.tool = "res://tests/py/gen_video_stub.py"
	m.easy.set_on(true, false)
	m._new_scene()
	await idle(3)
	home = m.easy.home

	# 1 unknown words: the reason and the button
	await type_line(WORDS)
	var msg := String(home._msg.text)
	ok(msg.begins_with("Kine can't build") and make_btn() != null and make_btn().visible and make_btn().text == BUTTON,
		"1 typed \"%s\": reason \"%s\", button shown %s" % [WORDS, msg, make_btn().visible if make_btn() != null else false])

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

	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	m.easy.set_on(false, false)
	m.queue_free()
	print("EASY GEN TEST ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
