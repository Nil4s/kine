## godot --position 4000,4000 --audio-driver Dummy --path . -s tests/impactcurve_test.gd     (ROADMAP I3; a window, off-screen)
## IMPACT FEEL CURVES (scripts/impact_feel.gd; the export writes <name>_impact_feel.json beside the .glb, from _export_engine).
## The scene is i13's: a hero of 5 cards and fighter 2 in front, three hits (rows as Dummy.fighter_hits gives them, impulse by I2's
## HitPhysics.measure): a light jab (J ~ 5 N s), a body punch (J ~ 15), a bat to the head (J ~ 27). Bars, written before the run:
##   1 RATIO (synthetic): two blows of 10 and 20 N s give peak strengths 0.40 and 0.80: the ratio is 2.00 within 5 %.
##   2 RATIO (measured): the punch's strength over the jab's is their measured J ratio (about 3) within 5 %.
##   3 FILE: _export_engine('godot') writes <name>_impact_feel.json beside the .glb; it reads back as JSON with format, fps 30 and
##     three events, one per hit, at the contact times (1e-6 s), for victim 1 (fighter 2).
##   4 VALUES: strength = the blow's J / 25 N s, clamped to 0..1: the jab 0.20 +- 0.01, the punch 0.60 +- 0.02, the bat 1.000;
##     length = the shake's length of the blow: the jab 0.20 +- 0.01 s, the bat 0.40 +- 0.01 s.
##   5 NO IMPACT: fighter 2 six metres away: the file exists with "events" = [] (an empty curve, not a missing file).
##   6 ONE FIGHTER: the hero alone: the file exists with "events" = [].
##   7 REAL CONTACT: combo3 against a standing fighter 2 through _export_engine: the file has the contacts and the status line says
##     "Impact feel: N hits" (plain words); each event's strength is 0..1 and its length 0.2..0.4 s; a screenshot of the window is saved.
##   8 SCENE: the export leaves both fighters' scenes exactly as they were (JSON, shots, attrs).
extends SceneTree

var fails := 0
var m: Node
const D0 := 1.2
const DIR := "user://zz_impactcurve"
const SHOT := "C:/Temp/claude/impactcurve/status.png"


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


func pose_of(arm: float) -> Dictionary:
	var b := body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.set_ang("upperarm_r", Vector3(0, 0, arm))
	b.ground()
	return b.to_dict()


func hero_scene() -> Scene:
	var s := Scene.new()
	s.from_dict({"scene": "zz_impactcurve", "fps": 30, "cards": [
		{"name": "a", "pose": pose_of(0), "move": -1.0, "hold": 0.5},
		{"name": "b", "pose": pose_of(80), "move": 0.6, "hold": 0.4},
		{"name": "c", "pose": pose_of(0), "move": 0.6, "hold": 0.5},
		{"name": "d", "pose": pose_of(80), "move": 0.6, "hold": 0.4},
		{"name": "e", "pose": pose_of(0), "move": 0.6, "hold": 0.5}]})
	s.shots = [{"t": 0.0, "name": "Shot 1", "keys": [], "fx": {}}]
	return s


func still() -> Scene:
	var p := pose_of(0)
	var s := Scene.new()
	s.from_dict({"scene": "zz_still", "fps": 30, "cards": [{"name": "a", "pose": p, "move": -1.0, "hold": 2.0}, {"name": "b", "pose": p, "move": 0.5, "hold": 3.0}]})
	return s


func sj(s: Scene) -> String:
	var d := s.to_dict(body())
	d.erase("actors")
	return JSON.stringify(d) + var_to_str(s.shots) + var_to_str(s.attrs)


func all_json() -> String:
	return sj(m.actors_rt[0]["S"]) + "|" + sj(m.actors_rt[1]["S"])


## a hit row as Dummy.fighter_hits gives it, in the hero's space: the striker's part moves along the victim's -z (toward it) at v
func row(Bv: Body, xf: Transform3D, part: String, on: String, v: float, t: float) -> Dictionary:
	var a: Array = Bv.cap(on)
	var mid := ((a[0] as Vector3) + (a[1] as Vector3)) * 0.5
	return {"t": t, "kind": "hit", "zone": "X", "part": part, "on": on, "by": "hero", "vs": 1, "u": 0.6, "depth": 0.01, "speed": v,
		"at": xf * (mid + Vector3(0, 0, float(Bv.rad[on]))), "vec": xf.basis * Vector3(0, 0, -v)}


func J_of(r: Dictionary) -> float:
	var bl := HitPhysics.measure(m.actors_rt[1]["S"], m.actors_rt[1]["B"], m.actors_rt[1]["xf"], r, m.actors_rt[0]["B"])
	return float(bl["m_eff"]) * float(bl["v_rel"])


## the feel file of the last export, read back from disk (the .glb's own folder), {} when missing
func feel_of(glb: String) -> Dictionary:
	var p := ImpactFeel.path_for(glb)
	var abs_p: String = ProjectSettings.globalize_path(p) if p.begins_with("user://") or p.begins_with("res://") else p
	if not FileAccess.file_exists(abs_p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(abs_p))
	return d if d is Dictionary else {}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))

	# 1: the mapping, synthetic blows of 10 and 20 N s
	var syn := ImpactFeel.events([{"t": 1.0, "J": 10.0, "victim": 1}, {"t": 2.0, "J": 20.0, "victim": 1}])
	var s1: float = syn[0]["strength"]
	var s2: float = syn[1]["strength"]
	ok(absf(s1 - 0.4) < 1e-6 and absf(s2 - 0.8) < 1e-6 and absf((s2 / s1) - 2.0) < 0.05 * 2.0, "1 ratio: J 10 and 20 N s give strength %.3f and %.3f (ratio %.3f, bar 2.00 +- 5%%)" % [s1, s2, s2 / s1])

	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var hero := hero_scene()
	m.S = hero
	m._rebuild_cards()
	hero.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, D0], "yaw": 180.0}, "scene": still()})
	m._actors_sync()
	m._page_set("STAGE", false)
	m._refresh()
	await idle(2)
	var xf: Transform3D = m.actors_rt[1]["xf"]
	var Bv: Body = m.actors_rt[1]["B"]
	var fist_m := J_of(row(Bv, xf, "hand_r", "head", 1.0, 0.8))
	var bat_m := J_of(row(Bv, xf, "bat_barrel", "head", 1.0, 2.0))
	var rows := [row(Bv, xf, "hand_r", "head", 5.0 / fist_m, 0.8), row(Bv, xf, "hand_r", "spine_03", 15.0 / fist_m, 2.0), row(Bv, xf, "bat_barrel", "head", 27.0 / bat_m, 3.0)]
	var hits := ImpactFrames.blows(m.actors_rt, rows)
	var Js: Array = hits.map(func(e): return float(e["J"]))

	# 2: the measured ratio: the punch over the jab (5 and 15 N s, both below full strength)
	var jab_s := ImpactFeel.strength_of(float(Js[0]))
	var punch_s := ImpactFeel.strength_of(float(Js[1]))
	var jr: float = float(Js[1]) / float(Js[0])
	ok(absf((punch_s / jab_s) / jr - 1.0) < 0.05 and absf(jr - 3.0) < 0.15, "2 ratio: jab J %.2f, punch J %.2f (ratio %.3f, bar 3 +- 5%%); strengths %.3f, %.3f" % [Js[0], Js[1], jr, jab_s, punch_s])

	# 3, 4, 8: the file for the three blows, written by the exporter with the blows the report gives it
	var before := all_json()
	var ex := EngineExport.export(hero, body(), "godot", DIR + "/rows", Callable(), hits)
	var f := feel_of(String(ex["path"]))
	var evs: Array = f.get("events", [])
	ok(String(ex["feel"]) != "" and not f.is_empty() and String(f.get("format", "")) == ImpactFeel.FORMAT and int(f.get("fps", 0)) == 30,
		"3 file: %s beside the .glb (format %s, fps %s)" % [ImpactFeel.path_for(String(ex["path"])).get_file(), f.get("format", "none"), f.get("fps", 0)])
	var tok := evs.size() == 3 and hits.size() == 3
	for i in range(evs.size()):
		tok = tok and absf(float(evs[i]["t"]) - float(hits[i]["t"])) < 1e-6 and int(evs[i]["victim"]) == 1
	ok(tok, "3 three events, one per hit, at the contact times (1e-6 s), victim 1 (fighter 2): %d events" % evs.size())
	var st: Array = evs.map(func(e): return float(e["strength"]))
	var ln: Array = evs.map(func(e): return float(e["length"]))
	print("     J %s, strength %s, length %s" % [Js.map(func(x): return snappedf(float(x), 0.01)), st, ln])
	ok(absf(st[0] - 0.20) < 0.01 and absf(st[1] - 0.60) < 0.02 and absf(st[2] - 1.0) < 1e-9, "4 strength: jab %.3f (0.20 +- 0.01), punch %.3f (0.60 +- 0.02), bat %.3f (1.000)" % [st[0], st[1], st[2]])
	ok(absf(ln[0] - 0.20) < 0.01 and absf(ln[2] - 0.40) < 0.01, "4 length: jab %.3f s (0.20 +- 0.01), bat %.3f s (0.40 +- 0.01)" % [ln[0], ln[2]])
	ok(all_json() == before, "8 the export leaves both fighters' scenes exactly as they were")

	# 5: fighter 2 six metres away: no contact; the file is still written, with an empty curve (the real export path)
	m.S.actors[0]["xf"] = {"pos": [0.0, 6.0], "yaw": 180.0}
	m.actors_rt = []   # the fighters are built again from the file (the old copies would keep their old place)
	m._actors_sync()
	m._refresh()
	await idle(2)
	var far := (m.actors_rt[1]["xf"] as Transform3D).origin.length()
	ok(m._impact_blows().is_empty(), "5 no impact: fighter 2 at %.1f m (%d fighters), the report finds no blow" % [far, m.actors_rt.size()])
	var glb5: String = m._export_engine("godot", DIR + "/far")
	var f5 := feel_of(glb5)
	ok(not f5.is_empty() and (f5.get("events", ["x"]) as Array).is_empty(), "5 no impact (fighter 2 at 6 m): the file exists with an empty events list")

	# 7: a real contact through the export: combo3 against a standing fighter 2 (as i13's test 9); the status line and a picture
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, D0], "yaw": 180.0}, "scene": still()})
	m._actors_sync()
	m._refresh()
	await idle()
	var glb7: String = m._export_engine("godot", DIR + "/real")
	await idle(2)
	var f7 := feel_of(glb7)
	var n7 := (f7.get("events", []) as Array).size()
	var status: String = m.ui_status.text if m.ui_status != null else ""
	ok(n7 >= 1 and status.contains("Impact feel: %d hits" % n7), "7 real contact: %d hit(s) in the file; status '%s'" % [n7, status.substr(status.find("Impact feel"), 60)])
	var ev7: Array = f7.get("events", [])
	var okr := true
	for e in ev7:
		okr = okr and float(e["strength"]) > 0.0 and float(e["strength"]) <= 1.0 and float(e["length"]) >= 0.2 - 1e-3 and float(e["length"]) <= 0.4 + 1e-3
	ok(okr, "7 every real event has strength 0..1 and length 0.2..0.4 s: %s" % [ev7.map(func(e): return "%.2fs %.2f %.2fs" % [e["t"], e["strength"], e["length"]])])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(SHOT)

	# 6: one fighter alone: an empty curve
	m.S.actors = []
	m.actors_rt = []
	m._actors_sync()
	m._refresh()
	await idle(2)
	var glb6: String = m._export_engine("godot", DIR + "/one")
	var f6 := feel_of(glb6)
	ok(not f6.is_empty() and (f6.get("events", ["x"]) as Array).is_empty(), "6 one fighter: the file exists with an empty events list")

	print("IMPACTCURVE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(0 if fails == 0 else 1)
