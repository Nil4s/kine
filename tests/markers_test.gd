## godot --headless --path . -s tests/markers_test.gd     (GATES WW5, UPGRADES_300 #261, UPGRADES_200 #106 export half)
## MARKERS: named moments on the timeline. Checked by numbers: add keeps them sorted, the file holds "markers" only when
## there are any (a scene without them saves with no such key and the same bytes), save/load round-trips, Mirror the
## scene keeps them, a retime moves a marker with the card time it sits in (a marker at a card arrival stays at that
## arrival; one inside a stretched hold stretches with it), the game export lists "events" as t / length and is
## byte-identical without markers, Add/Delete are one undo step each, Next/Previous jump the playhead without editing.
extends SceneTree

var fails := 0
var m: Node
var n_ok := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	n_ok += 1 if c else 0
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func cmd(id: String) -> void:
	for c in m._commands():
		if c["id"] == id:
			(c["run"] as Callable).call()
			return
	ok(false, "command %s exists" % id)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	var S: Scene = m.S
	var L := S.length()
	var ts: Array = S.times().duplicate(true)

	# 1 no markers: the file has no key; the export has no events
	var d0: Dictionary = JSON.parse_string(JSON.stringify(S.to_dict(m.B)))
	ok(not d0.has("markers"), "1 a scene without markers writes no 'markers' key (has: %s)" % d0.has("markers"))
	var T0 := GameExport.table(S, m.B)
	var j0 := JSON.stringify(GameExport.to_json(S.name, T0), "\t")
	ok(not T0.has("events") and not j0.contains("events"), "2 the export of %s (%.2f s) has no 'events' (in json: %s)" % [S.name, L, j0.contains("events")])

	# 2 commands: add, undo, delete, jump
	m.undo.clear()
	m.playhead = ts[2][1]
	cmd("add_marker_at_the_playhead")
	ok(S.markers.size() == 1 and S.markers[0]["name"] == "m1" and S.markers[0]["kind"] == "note" and absf(S.markers[0]["t"] - ts[2][1]) < 1e-3,
		"3 Add marker at the playhead: 1 marker %s at %.3f (card 3 arrives %.3f)" % [S.markers[0]["name"], S.markers[0]["t"], ts[2][1]])
	ok(m.undo.size() == 1, "4 one undo step (%d)" % m.undo.size())
	m._undo()
	ok(S.markers.is_empty(), "5 Ctrl+Z removes it (%d markers)" % S.markers.size())
	m._redo()
	ok(S.markers.size() == 1, "6 Ctrl+Y puts it back (%d)" % S.markers.size())
	m.playhead = ts[0][2] * 0.5
	cmd("add_marker_at_the_playhead")
	m.playhead = L - 0.1
	cmd("add_marker_at_the_playhead")
	var tl: Array = S.markers.map(func(x): return x["t"])
	var sorted_ok := true
	for i in range(1, tl.size()):
		sorted_ok = sorted_ok and tl[i] >= tl[i - 1]
	ok(S.markers.size() == 3 and sorted_ok, "7 three markers, sorted by t: %s" % [tl])
	var names: Array = S.markers.map(func(x): return x["name"])
	ok(names.size() == 3 and names.has("m1") and names.has("m2") and names.has("m3"), "8 names m1..m3 each once: %s" % [names])
	var u0: int = m.undo.size()
	m.playhead = 0.0
	cmd("next_marker")
	ok(absf(m.playhead - tl[0]) < 1e-6, "9 Next marker from 0: playhead %.3f = first %.3f" % [m.playhead, tl[0]])
	cmd("next_marker")
	cmd("previous_marker")
	ok(absf(m.playhead - tl[0]) < 1e-6 and m.undo.size() == u0, "10 Next, Next, Previous lands on the first, no undo step (%d vs %d)" % [m.undo.size(), u0])
	m.playhead = tl[1] + 0.5 / S.fps
	var n1 := S.markers.size()
	cmd("delete_marker_at_the_playhead")
	ok(S.markers.size() == n1 - 1, "11 Delete within half a frame removes one (%d -> %d)" % [n1, S.markers.size()])
	m.playhead = tl[0] + 3.0 / S.fps
	cmd("delete_marker_at_the_playhead")
	ok(S.markers.size() == n1 - 1, "12 Delete 3 frames away removes nothing (%d)" % S.markers.size())
	m._undo()
	ok(S.markers.size() == n1, "13 undo of the delete restores it (%d)" % S.markers.size())

	# 3 save/load
	S.markers = []
	Markers.add(S.markers, ts[1][1], "hit1", "hit")
	Markers.add(S.markers, ts[2][1], "step1", "step")
	Markers.add(S.markers, L * 0.9, "", "bogus")
	var d1: Dictionary = JSON.parse_string(JSON.stringify(S.to_dict(m.B)))
	ok(d1.has("markers") and d1["markers"].size() == 3 and d1["markers"][2]["kind"] == "note", "14 the file holds 3 markers, a bad kind is a note (%s)" % [d1.get("markers")])
	var S2 := Scene.new()
	S2.from_dict(d1)
	ok(JSON.stringify(S2.markers) == JSON.stringify(S.markers), "15 load gives the same list back")
	var d_other: Dictionary = JSON.parse_string(JSON.stringify(d1))
	d_other.erase("markers")
	ok(JSON.stringify(d_other) == JSON.stringify(d0), "16 apart from 'markers' the file is byte-identical to the one without")
	var S3: Scene = S.clone()
	ok(JSON.stringify(S3.markers) == JSON.stringify(S.markers), "17 clone keeps them")

	# 4 mirror the scene keeps markers
	S.name = "_wip/zz_mk"
	m._mirror_scene()
	await idle()
	var mp := "res://scenes/_wip/zz_mk_mirrored.json"
	var mir: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(mp))
	ok(mir.has("markers") and JSON.stringify(mir["markers"]) == JSON.stringify(d1["markers"]), "18 Mirror the scene keeps the markers: %d" % mir.get("markers", []).size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(mp))

	# 5 retime: a marker at card 3 arrival, one mid-hold of card 2, one before the range
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	S = m.S
	ts = S.times().duplicate(true)
	var mid_hold: float = (ts[1][1] + ts[1][2]) * 0.5
	var at_arr: float = ts[2][1]
	var before_arr: float = ts[0][2] * 0.5
	Markers.add(S.markers, at_arr, "arr3", "hit")
	Markers.add(S.markers, mid_hold, "mid2", "swoosh")
	Markers.add(S.markers, before_arr, "early", "note")
	var res: String = m.retime(1, 2, 200.0)
	ts = S.times()
	var by := {}
	for x in S.markers:
		by[x["name"]] = x["t"]
	ok(res == "", "19 retime ok (%s)" % res)
	ok(absf(by["arr3"] - ts[2][1]) < 2e-3, "20 the marker at card 3 arrival stays at its arrival: %.3f vs %.3f" % [by["arr3"], ts[2][1]])
	var exp_mid: float = (ts[1][1] + ts[1][2]) * 0.5
	ok(absf(by["mid2"] - exp_mid) < 2e-3, "21 the marker mid-hold of card 2 stays mid-hold: %.3f vs %.3f" % [by["mid2"], exp_mid])
	ok(absf(by["early"] - before_arr) < 1e-3, "22 a marker before the range is not moved: %.3f vs %.3f" % [by["early"], before_arr])
	ok(by["arr3"] > at_arr + 0.05, "23 and it did move (%.3f -> %.3f)" % [at_arr, by["arr3"]])
	m._undo()
	var back := {}
	for x in S.markers:
		back[x["name"]] = x["t"]
	ok(absf(back["arr3"] - at_arr) < 1e-3 and absf(back["mid2"] - mid_hold) < 1e-3, "24 undo of the retime puts the markers back: %.3f %.3f" % [back["arr3"], back["mid2"]])
	var rt := Markers.remap_time(0.4, [[0, 1, 2]], [[0, 2, 4]])
	ok(absf(rt - 0.8) < 1e-9, "25 remap_time is linear inside a stretch: 0.4 -> %.3f" % rt)

	# 6 export events
	S.markers = []
	Markers.add(S.markers, S.length() * 0.25, "hit1", "hit")
	Markers.add(S.markers, S.length() * 0.5, "w", "swoosh")
	var J := GameExport.to_json(S.name, GameExport.table(S, m.B))
	var ev: Array = J.get("events", [])
	ok(ev.size() == 2 and absf(ev[0]["t_frac"] - 0.25) < 1e-3 and absf(ev[1]["t_frac"] - 0.5) < 1e-3 and ev[0]["name"] == "hit1" and ev[1]["kind"] == "swoosh",
		"26 events t_frac 0.25 / 0.5 of %.2f s: %s" % [S.length(), ev])
	var J2: Dictionary = JSON.parse_string(JSON.stringify(J))
	J2.erase("events")
	S.markers = []
	var J3: Dictionary = JSON.parse_string(JSON.stringify(GameExport.to_json(S.name, GameExport.table(S, m.B))))
	ok(JSON.stringify(J2) == JSON.stringify(J3), "27 minus 'events' the export is the one without markers, byte for byte")

	print("MARKERS TEST %s %d  (%d ok)" % ["PASS" if fails == 0 else "FAIL", fails, n_ok])
	quit(fails)
