## godot --path . -s tools/firstframe_dump.gd -- --out=DIR
## Easy home card click -> first moving frame, as the app orders it (the click is made right after a draw, so the next
## process_frame is the click's own frame: input, process_frame, _process, draw). Each card is clicked once (Run twice: the
## last line is Run warm). Per card prints: the click's synchronous time, home.last_ms (click -> the first _process that plays),
## and the click -> the END of the first DRAWN frame with the body moving (what the beginner sees).
## Writes DIR/card_<i>.txt (the second Run: card_1b.txt) = the clip's cards (var_to_str) and the body's joints at 12 playhead
## times, and the camera, so two builds compare with cmp (the cards' build time stamps are blanked). The machine's load moves every number: compare runs interleaved, base and new.
extends SceneTree

var m: Node
var _t0 := 0
var _drawn := -1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the build's time stamp inside a card's "from" tag (name|ticks) differs run to run: it is not clip content
func _unstamp(t: String) -> String:
	var re := RegEx.new()
	re.compile("[|][0-9]+\"")
	return re.sub(t, "|N\"", true)


func _post() -> void:
	if _drawn < 0 and m.playing and m.playhead > 0.0:
		_drawn = Time.get_ticks_usec() - _t0


func _init() -> void:
	var outdir := "user://ffdump"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			outdir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(outdir)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	await idle(8)
	var home: EasyHome = m.easy.home
	m._new_scene()
	await idle()
	m.easy.set_on(true, false)
	await idle(20)   # the idle warm-up reads the templates
	RenderingServer.frame_post_draw.connect(_post)
	var seen := {}
	for i in [0, 1, 2, 3, 4, 5, 6, 7, 1]:
		m.playing = false
		m._new_scene()
		await idle(2)
		await RenderingServer.frame_post_draw
		var btn := home.panel.find_child("eh_card_%d" % i, true, false) as Button
		_drawn = -1
		_t0 = Time.get_ticks_usec()
		btn.pressed.emit()
		var sync_ms := (Time.get_ticks_usec() - _t0) / 1000.0
		for k in 120:
			if _drawn >= 0:
				break
			await process_frame
		print("card %d%s: sync %.0f ms; home.last_ms %d (builder %d); click -> first drawn moving frame %.0f ms" % [i, "b" if seen.has(i) else "", sync_ms, home.last_ms, home.last_build_ms, _drawn / 1000.0])
		await idle(4)   # the deferred bookkeeping has run
		m.playing = false
		var out := _unstamp(var_to_str(m.S.cards)) + "\n"
		m.playhead = 0.0   # the follow point rides the body at the playhead: read the camera at a fixed one
		m.S.apply(m.B, 0.0)
		m.easy.follow_tick()
		out += "camera dist %.6f target %s origin %s basis %s track %s %s\n" % [m.dist, str(m.target), str(m.cam.global_position), str(m.cam.global_basis), str(m.easy._track), str(m.easy._track_ks)]
		var len: float = m.S.length()
		for s in 12:
			m.S.apply(m.B, len * s / 11.0)
			m.B.fk()
			var js := []
			for k in m.B.P.keys():
				var v: Vector3 = m.B.P[k]
				js.append("%s:%.5f,%.5f,%.5f" % [k, v.x, v.y, v.z])
			out += ";".join(js) + "\n"
		var f := FileAccess.open("%s/card_%d%s.txt" % [outdir, i, "b" if seen.has(i) else ""], FileAccess.WRITE)
		f.store_string(out)
		f.close()
		seen[i] = true
	quit(0)
