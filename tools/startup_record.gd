## godot --path . -s tools/startup_record.gd -- --tour [--no-autosave] [--press recover|discard|esc] [--sweep] [--out C:/Temp/qq1]     (GATES QQ1/QQ2)
## THE FIRST SIX SECONDS, RECORDED. The app starts as on a first run (the tour due; with an autosave of unsaved work
## waiting unless --no-autosave), in a real window, with nobody touching it. Every frame: which intro things are on
## screen (the tour card and its step, the recover dialog, help, keys, the toast) -> <out>/events.txt, one line per
## CHANGE; a screenshot every 100 ms -> <out>/f_0000.png ... Settings and autosave are this run's own files (a script
## run uses per-process ones), never the user's. Prints a summary: each thing's appearances and how long each lasted.
extends SceneTree

const SECS := 6.0
const SHOT_EVERY := 0.1


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var oi := args.find("--out")
	var out: String = args[oi + 1] if oi >= 0 and oi + 1 < args.size() else "C:/Temp/qq1"
	DirAccess.make_dir_recursive_absolute(out)
	for f in DirAccess.get_files_at(out):
		DirAccess.remove_absolute(out + "/" + f)
	var auto := "user://zz_rec_autosave_%d.json" % OS.get_process_id()
	if not args.has("--no-autosave"):
		# unsaved work: combo3 with its last card gone, never saved to a file
		var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json"))
		(sc["cards"] as Array).pop_back()
		sc["name"] = "untitled"
		var fa := FileAccess.open(auto, FileAccess.WRITE)
		fa.store_string(JSON.stringify({"scene": sc, "path": "", "time": Time.get_datetime_string_from_system()}))
		fa.close()
		OS.set_environment("POSER_AUTOSAVE", auto)
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	var t0 := Time.get_ticks_msec()
	var last := {}
	var log := PackedStringArray()
	var spans := {}   # thing -> [[on, off], ...]
	var next_shot := 0.0
	var k := 0
	var pressed := false
	var mouse_at := Vector2.ZERO
	while true:
		await process_frame
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		var now := {
			"tour": m.ui_tour != null and m.ui_tour.visible,
			"tour_step": m.tour_step,
			"recover": m.ui_recover != null and m.ui_recover.visible,
			"help": m.ui_help != null and m.ui_help.visible,
			"keys": m.ui_keys != null and m.ui_keys.visible,
			"toast": m.ui_toast != null and m.ui_toast.visible and m.ui_toast.modulate.a > 0.05,
			"toast_text": m.ui_toast.text if m.ui_toast != null else "",
			"tag": m.tag != null and m.tag.visible,
			"tag_text": m.tag.text if m.tag != null else "",
			"how": m.ui_how.text if m.ui_how != null else "",
			"bar": m.ui_bar.text if m.ui_bar != null else "",
			"hit_tag": m.hit_tag != null and m.hit_tag.visible,
		}
		for key in now:
			if not last.has(key) or last[key] != now[key]:
				log.append("%6.3f s  %-10s %s" % [t, key, str(now[key])])
				if now[key] is bool:
					if not spans.has(key):
						spans[key] = []
					if now[key]:
						spans[key].append([t, -1.0])
					elif not (spans[key] as Array).is_empty():
						spans[key][-1][1] = t
		last = now
		var pi := args.find("--press")
		if pi >= 0 and not pressed and t >= 1.5 and m.ui_recover != null and m.ui_recover.visible:
			pressed = true
			if args[pi + 1] == "esc":   # a real key, as the user's
				log.append("%6.3f s  PRESS      Esc" % t)
				for down in [true, false]:
					var ke := InputEventKey.new()
					ke.keycode = KEY_ESCAPE
					ke.physical_keycode = KEY_ESCAPE
					ke.pressed = down
					get_root().push_input(ke)
			else:
				var b: Button = m.ui_recover.get_ok_button() if args[pi + 1] == "recover" else m.ui_recover.get_cancel_button()
				log.append("%6.3f s  PRESS      %s" % [t, b.text])
				b.pressed.emit()
		if args.has("--sweep") and t >= 2.0:
			# a person moving the mouse around after opening: zig-zag over the window, 1.5 passes a second
			var vs := get_root().get_visible_rect().size
			var u := (t - 2.0) * 0.75
			var x := vs.x * (0.05 + 0.9 * absf(fmod(u, 2.0) - 1.0))
			var y := vs.y * (0.15 + 0.7 * (0.5 + 0.5 * sin(t * 2.3)))
			var ev := InputEventMouseMotion.new()
			ev.position = Vector2(x, y)
			ev.global_position = ev.position
			ev.relative = ev.position - mouse_at
			mouse_at = ev.position
			get_root().push_input(ev)
		if t >= next_shot:
			get_root().get_texture().get_image().save_png("%s/f_%04d.png" % [out, k])
			k += 1
			next_shot += SHOT_EVERY
		if t >= SECS:
			break
	var fe := FileAccess.open(out + "/events.txt", FileAccess.WRITE)
	fe.store_string("\n".join(log) + "\n")
	fe.close()
	print("RECORDED %d screenshots, %d changes -> %s" % [k, log.size(), out])
	# FLIPS: how often each thing changed (a text or a visibility); "blinking" is a thing that flips many times
	var flips := {}
	for line in log:
		var key := line.substr(10, 10).strip_edges()
		flips[key] = flips.get(key, 0) + 1
	print("FLIPS %s" % [flips])
	for key in spans:
		var parts := []
		for s in spans[key]:
			parts.append("%.2f-%s" % [s[0], ("%.2f" % s[1]) if s[1] >= 0 else "end"])
		print("SPAN %-8s shown %d time(s): %s" % [key, (spans[key] as Array).size(), ", ".join(parts)])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(auto))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(auto).get_basename() + "_later.json")
	quit()
