## godot --path . -s tools/ai_bench.gd -- --task pose|wave|fight [--backend ollama] [--model glm-4.7-flash] [--url ...]
##   [--out C:/Temp/r46_bb3] [--cap 1800]
## ROUND 46 (GATES BB3 / BB4 / BB5): one REAL model drives the Ask AI box on an empty scene, as a user would (the box,
## the same tools, the same loop): what it asked for, seconds, turns, tool calls, refusals, tokens, Check's verdict, and
## the pose task's arms measured from the body's own points against the reference band. Writes <out>/<task>.json and
## a screenshot <out>/<task>.png. The key, for a cloud backend, comes from the environment (POSER_AI_KEY), never an
## argument (it would sit in the process list) and never a file.
extends SceneTree

const TASKS := {
	"pose": "Both arms up like a goal celebration: make ONE card of it, named goal.",
	"wave": "He waves hello with his right hand: about 6 cards (the hand comes up, waves side to side twice, comes down).",
	"fight": "Build a short fight with a weapon (commands has weapon_metal_bat): a guard, two strikes with wind-ups, a recovery and back to the guard, at least 10 cards, each named. Check must end with 0 MUST FIX.",
}
## REAL reference for the pose task (According to PubMed, Kenner et al. 2026, doi 10.1186/s12891-026-10073-y: healthy
## maximal shoulder abduction "averaging around 150 deg", ~125 deg needed for daily tasks). Arms "up" in a celebration
## are near that maximum: humerus elevation from the trunk's down axis in [125, 180]; the elbows near straight (>= 150).
const ELEV_BAND := Vector2(125, 180)
const ELBOW_MIN := 150.0


func _arg(name: String, dflt: String) -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--" + name)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else dflt


static func ang(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.normalized().angle_to(b.normalized()))


## the arms of a body's state: elevation of each upper arm from the trunk's down axis, and each elbow's angle (180 straight)
static func arms(st: Dictionary) -> Dictionary:
	var P := {}
	for k in st["points"]:
		var v: Array = st["points"][k]
		P[k] = Vector3(v[0], v[1], v[2])
	var down: Vector3 = P["pelvis"] - P["spine_03"]
	var out := {}
	for s in ["_l", "_r"]:
		out["elev" + s] = snappedf(ang(P["lowerarm" + s] - P["upperarm" + s], down), 0.1)
		out["elbow" + s] = snappedf(ang(P["upperarm" + s] - P["lowerarm" + s], P["hand" + s] - P["lowerarm" + s]), 0.1)
	return out


func _init() -> void:
	var task := _arg("task", "pose")
	var out_dir := _arg("out", "C:/Temp/r46_bb3")
	var cap := float(_arg("cap", "1800"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)
	await T.request(0, "new", {})
	m.undo.clear()
	m._ai_toggle()
	await process_frame
	var box: AiBox = m.ui_ai
	box.ui_backend.select(LlmClient.BACKENDS.find(_arg("backend", "ollama")))
	box.ui_model.text = _arg("model", "glm-4.7-flash")
	box.ui_url.text = _arg("url", "")
	box.ui_key.text = OS.get_environment("POSER_AI_KEY")
	var t0 := Time.get_ticks_msec()
	box.ask(TASKS[task])
	var capped := false
	while box.running:
		await process_frame
		if (Time.get_ticks_msec() - t0) / 1000.0 > cap:
			capped = true
			box.stop()
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	var fs: Array = T.findings() if m.S.cards.size() >= 2 else []
	var cards := []
	for c in m.S.cards:
		cards.append(c["name"])
	var r := {"task": task, "ask": TASKS[task], "backend": _arg("backend", "ollama"), "model": box.ui_model.text,
		"seconds": snappedf(secs, 0.1), "capped": capped, "cap_s": cap, "stats": box.stats, "cards": cards,
		"must_fix": fs.filter(func(f): return f["sev"] == "MUST FIX").size(), "looks": fs.filter(func(f): return f["sev"] != "MUST FIX").size(),
		"undo_steps": m.undo.size(), "log": box.log_lines}
	if task == "pose" and not m.S.cards.is_empty():
		var last: int = m.S.cards.size() - 1
		await T.request(1, "run", {"steps": ["card=%d" % (last + 1)]})
		var st: Dictionary = (await T.request(2, "state", {}))["result"]
		var a := arms(st)
		a["band_elev"] = [ELEV_BAND.x, ELEV_BAND.y]
		a["elbow_min"] = ELBOW_MIN
		a["in_band"] = ELEV_BAND.x <= a["elev_l"] and a["elev_l"] <= ELEV_BAND.y and ELEV_BAND.x <= a["elev_r"] and a["elev_r"] <= ELEV_BAND.y \
			and a["elbow_l"] >= ELBOW_MIN and a["elbow_r"] >= ELBOW_MIN
		r["arms"] = a
	m._view(1)
	m.playhead = m.S.length() * 0.5
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	for k in 20:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(task + ".png"))
	var f := FileAccess.open(out_dir.path_join(task + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(r, "  "))
	f.close()
	print("BENCH ", JSON.stringify({"task": task, "seconds": r["seconds"], "stats": box.stats, "cards": cards.size(), "must_fix": r["must_fix"], "arms": r.get("arms", {})}))
	m.queue_free()
	quit()
