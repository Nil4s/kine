## godot --path . -s tests/marker_notes_test.gd     (ROADMAP 97; a real window, real mouse events on the ruler)
## MARKER NOTES: a marker carries a note (several lines) and a colour (Tok mk_*). Checked by numbers: a note and a colour
## survive save/load byte for byte; an old marker list (t, name, kind) comes back byte for byte; the timeline flag's
## tooltip IS the note; a real click on a flag puts the playhead on it exactly and opens its popover; a real drag moves
## it by whole frames (one undo step, undo restores it); a list pick jumps the playhead exactly; each popover edit is one
## undo step (a no-op is none); retime 2x doubles the marker times and keeps the note; the .glb carries the markers as
## extras "poser_markers" on its animation. Writes a screenshot of the timeline with 3 coloured markers and a popover.
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/markers.png"
const SHOT_CROP := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/markers_timeline.png"

var fails := 0
var m: Node
var tl: Timeline


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the timeline's own input (as retime_handles_test does): p is LOCAL to the timeline
func mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = tl.get_global_transform() * p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	tl._gui_input(e)


func drag_to(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = tl.get_global_transform() * p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	tl._gui_input(e)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	tl = m.ui_timeline
	var S: Scene = m.S
	var fps: int = S.fps
	var L := S.length()
	var ts: Array = S.times().duplicate(true)

	# 1 an old list (t, name, kind only) comes back byte for byte: the note and colour keys are not invented
	var old_list := [{"t": 1.25, "name": "hit1", "kind": "hit"}, {"t": 2.5, "name": "m2", "kind": "note"}]
	ok(JSON.stringify(Markers.from_list(old_list)) == JSON.stringify(old_list), "1 an old marker list comes back byte for byte (%s)" % JSON.stringify(Markers.from_list(old_list)))
	S.markers = []
	ok(not S.to_dict(m.B).has("markers"), "2 a scene with no markers writes no 'markers' key")

	# 3 add three markers, one with a note, each a colour from the palette; a note of several lines
	var note0 := "Left foot lands here.\nBrace before the hit, spine tall."
	m.playhead = ts[1][1]
	m._marker_add()
	m._mk_commit(0, "", note0, "red")
	m.playhead = ts[3][1]
	m._marker_add()
	m._mk_commit(1, "", "", "green")
	m.playhead = ts[5][1]
	m._marker_add()
	m._mk_commit(2, "", "", "blue")
	ok(S.markers.size() == 3 and S.markers[0]["note"] == note0 and S.markers[0]["color"] == "red" and S.markers[2]["color"] == "blue",
		"3 three markers, the first with a 2-line note and red, the others green and blue (%s)" % JSON.stringify(S.markers))

	# 4 save/load round trip: the file's JSON, read back, gives the same markers
	var d1: Dictionary = JSON.parse_string(JSON.stringify(S.to_dict(m.B)))
	var S2 := Scene.new()
	S2.from_dict(d1)
	ok(JSON.stringify(S2.markers) == JSON.stringify(S.markers), "4 save/load: the notes and colours come back identical")
	var j1 := JSON.stringify(S.to_dict(m.B))
	var S3 := Scene.new()
	S3.from_dict(JSON.parse_string(j1))
	ok(JSON.stringify(S3.to_dict(m.B)) == j1, "5 saving the loaded scene again gives the same bytes")

	# 6 the tooltip of the flag IS the note
	var x0 := tl.x_of(float(S.markers[0]["t"]))
	var tip := tl._get_tooltip(Vector2(x0, 3.0))
	ok(tip == note0, "6 the tooltip on the flag equals the note (%s)" % tip.replace("\n", " | "))

	# 7 a REAL drag of the green marker (m2) by ~1.6 frames: it lands on whole frames, one undo step, undo restores it
	var j2 := S.markers.find_custom(func(x): return String(x["name"]) == "m2")
	var t_before := float(S.markers[j2]["t"])
	var p0 := Vector2(tl.x_of(t_before), 3.0)
	var u0: int = m.undo.size()
	await mouse(p0, true)
	var dx := tl.pps() / float(fps) * 1.6
	await drag_to(p0 + Vector2(dx * 0.5, 0))
	await drag_to(p0 + Vector2(dx, 0))
	await mouse(p0 + Vector2(dx, 0), false)
	var mi := S.markers.find_custom(func(x): return String(x["name"]) == "m2")
	var t_after := float(S.markers[mi]["t"])
	var f_after := t_after * float(fps)
	var f_want := Markers.frame_of(tl.t_of(tl.x_of(t_before) + dx), fps)
	ok(absf(f_after - roundf(f_after)) < 1e-4, "7a the dragged marker sits on a whole frame (%.6f frames)" % f_after)
	ok(int(roundf(f_after)) == f_want and f_want != int(roundf(t_before * float(fps))), "7b it moved to frame %d (%.3f s -> %.3f s; the drag said frame %d)" % [int(roundf(f_after)), t_before, t_after, f_want])
	ok(m.undo.size() == u0 + 1, "7c the whole drag is ONE undo step (%d -> %d)" % [u0, m.undo.size()])
	m._undo()
	ok(absf(float(S.markers[S.markers.find_custom(func(x): return String(x["name"]) == "m2")]["t"]) - t_before) < 1e-9, "7d undo puts the marker back (%.6f)" % t_before)

	# 8 a REAL click (no movement) on the red flag: the playhead on it exactly, its popover open, the list of it in sight
	var p1 := Vector2(tl.x_of(float(S.markers[0]["t"])), 3.0)
	await mouse(p1, true)
	await mouse(p1, false)
	await idle(3)
	ok(m.playhead == float(S.markers[0]["t"]) and m.mk_pop != null and m.mk_pop.visible and m.mk_i == 0,
		"8 a click on the flag: playhead %.6f = the marker's %.6f exactly; popover open (%s)" % [m.playhead, float(S.markers[0]["t"]), m.mk_pop != null and m.mk_pop.visible])
	m.mk_pop.hide()
	await idle(2)

	# 9 the Markers list jumps the playhead to a marker exactly
	m._markers_list_open()
	m.mk_list.item_selected.emit(2)
	await idle(2)
	ok(m.playhead == float(S.markers[2]["t"]), "9 the list's pick: the playhead %.6f = %.6f exactly" % [m.playhead, float(S.markers[2]["t"])])

	# 10 each popover edit is one undo step; a no-op is none
	var u1: int = m.undo.size()
	m._mk_commit(0, "stomp", note0, "red")
	ok(m.undo.size() == u1 + 1 and S.markers[0]["name"] == "stomp", "10a rename is one undo step (%d -> %d)" % [u1, m.undo.size()])
	m._mk_commit(0, "stomp", "Foot lands. Brace.", "red")
	ok(m.undo.size() == u1 + 2 and S.markers[0]["note"] == "Foot lands. Brace.", "10b a note edit is one undo step (%d)" % m.undo.size())
	m._mk_commit(0, "stomp", "Foot lands. Brace.", "red")
	ok(m.undo.size() == u1 + 2, "10c committing the same values is no undo step (%d)" % m.undo.size())
	m._mk_pop_show(0)
	m._mk_pick_color("blue")
	ok(m.undo.size() == u1 + 3 and S.markers[0]["color"] == "blue", "10d a colour pick is one undo step; the marker is %s" % S.markers[0]["color"])
	ok(Markers.token_of(S.markers[0]) == "mk_blue", "10e drawn in the Tok token mk_blue (%s)" % Markers.token_of(S.markers[0]))
	m._mk_delete_open()
	ok(S.markers.size() == 2 and m.undo.size() == u1 + 4, "10f Delete marker is one undo step (%d markers, %d undo)" % [S.markers.size(), m.undo.size()])
	m._undo()
	ok(S.markers.size() == 3 and S.markers[0]["color"] == "blue", "10g undo of the delete brings it back (%d)" % S.markers.size())

	# 11 retime 2x doubles every marker time and keeps the note
	var before: Array = S.markers.map(func(x): return float(x["t"]))
	RetimeRange.apply(S, 0.0, L, 0.0, 200.0)
	var dbl := true
	for i in before.size():
		dbl = dbl and absf(float(S.markers[i]["t"]) - 2.0 * float(before[i])) < 0.002
	ok(dbl and S.markers[0].has("note"), "11 retime 2x doubles the marker times (%s -> %s) and keeps the note" % [before, S.markers.map(func(x): return snappedf(float(x["t"]), 0.001))])

	# 12 the .glb carries the markers as extras "poser_markers" on its animation; no markers, no extras
	var glb := "user://marker_notes_test.glb"
	GltfExport.write(S, m.B, glb, false)
	var gb := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(glb))
	var gjl := gb.decode_u32(12)
	var gdoc: Dictionary = JSON.parse_string(gb.slice(20, 20 + gjl).get_string_from_utf8())
	var gx: Dictionary = (gdoc.get("animations", [{}])[0] as Dictionary).get("extras", {})
	var gl: Array = gx.get("poser_markers", [])
	ok(gl.size() == 3 and String(gl[0]["note"]) == "Foot lands. Brace." and String(gl[2]["color"]) == "blue" and int(gl[1]["frame"]) == Markers.frame_of(float(S.markers[1]["t"]), fps),
		"12 the glb's animation extras hold the 3 markers with note, colour and frame (%d)" % gl.size())

	# 13 the screenshot: three coloured flags and the note popover open
	m.playhead = float(S.markers[0]["t"])
	m._refresh()
	# the first show in this harness is closed by the window's focus churn one frame later (a click keeps it: check 8);
	# showing it again once the frame has settled is the same popover, so the capture is taken with it open
	m._mk_pop_show(0)
	await idle(2)
	m._mk_pop_show(0)
	await idle(11)
	ok(m.mk_pop.visible, "13a the note popover is open in the capture")
	var img := root.get_texture().get_image()
	img.save_png(SHOT)
	img.get_region(Rect2i(0, 480, img.get_width(), img.get_height() - 480)).save_png(SHOT_CROP)
	ok(FileAccess.file_exists(SHOT), "13 screenshot saved (%s)" % SHOT)

	print("MARKER NOTES: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
