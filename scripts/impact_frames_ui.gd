## impact_frames_ui.gd - I13: the commands "Add impact frames" (measure every contact, show the plan, PLAY it on copies: the scene is not
## touched) and "Remove impact frames"; Accept writes it as ONE undo step. The maths is scripts/impact_frames.gd; the blow's impulse is I2's
## HitPhysics.measure. Kept out of main.gd: main makes one (main.if_ui), lists its commands and calls tick() each frame.
class_name ImpactFramesUI
extends RefCounted

const LEAD_IN := 0.5    # s before the first stop the preview starts
const LEAD_OUT := 0.8   # s after the last stop it runs on

var m: Node
var pl: Array = []           # the plan
var pv: Array = []           # the preview's scenes (clones with the impact frames); [] = not previewing
var pv_t := 0.0
var pv_end := 0.0
var shaking := {}            # the shake the preview applies to the viewport camera now ({} = none), for the test


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Add impact frames", "", show, "impact frames hit stop freeze frames camera shake squash contact juice game feel punch hit pause",
		false, "at every contact of the fighters Kine adds, scaled by the blow's impulse: a hit-stop (2 to 6 frames at 30 fps, both fighters hold and everything after shifts), a camera shake on the shot camera and a squash on the struck part. Preview plays it without changing the scene; Accept is one undo step (ROADMAP I13)")
	add.call("Remove impact frames", "", remove, "impact frames remove hit stop shake squash undo tag",
		false, "takes the impact frames out by their tags (the holds, the shake, the squash) and shifts the scene back; one undo step")


func halt() -> void:
	if not pv.is_empty():
		pv = []
		for a in m.actors_rt:
			a["t"] = NAN
		m._ps().apply(m.B, m.playhead)
		if not shaking.is_empty():
			shaking = {}
			m._cam()   # the view without the preview's shake


func _scenes() -> Array:
	m._actors_sync()
	return m.actors_rt.map(func(a): return a["S"])


func _bodies() -> Array:
	return m.actors_rt.map(func(a): return a["B"])


## the plan for the scene as it is now ([] and a message when there is nothing to do)
func compute() -> Array:
	m._actors_sync()
	if not m._fighters_on():
		m._say("Add impact frames needs two fighters: 'Actor: add a second fighter' first, then let a weapon or fist touch the other one")
		return []
	if ImpactFrames.already(m._hero_scene()):
		m._say("this scene already has impact frames: use 'Remove impact frames' first, then add them again")
		return []
	var out := ImpactFrames.plan(m._impact_blows())
	if out.is_empty():
		m._say("no weapon or fist touches a fighter's body in this scene: swing into the other fighter (Check > Dummy lists the contacts), then try again")
	return out


func show() -> void:
	pl = compute()
	if pl.is_empty():
		return
	_panel()
	preview()


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("IMPACT FRAMES  -  %d contact%s" % [pl.size(), "" if pl.size() == 1 else "s"], 18, "heading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", close))
	L.add_child(m._label("Each contact: hit-stop (both fighters hold), shot-camera shake, squash on the struck part, all scaled by the impulse J = effective mass x speed. Preview changes nothing; Accept is one undo step (Ctrl+Z).", 13, "text:0.6", true))
	for k in pl.size():
		var p: Dictionary = pl[k]
		var lb: Label = m._label("%s  %s: J %.1f N s (%.2f kg x %.1f m/s)  ->  hit-stop %d frames, squash %.2f" % [Units.time(float(p["t"]), m.S.fps), String(p["on"]).replace("_", " "),
			float(p["J"]), float(p["m_eff"]), float(p["v_rel"]), int(p["frames"]), float(p["squash"])], 14, "text:0.85", true)
		lb.name = "if_line_%d" % (k + 1)
		lb.custom_minimum_size = Vector2(380, 0)
		L.add_child(lb)
	var row := HBoxContainer.new()
	var pb: Button = m._button("Preview", preview, "play the scene with the impact frames; the scene is not changed")
	pb.name = "if_preview"
	var ab: Button = m._button("Accept", accept, "write the impact frames; one undo step")
	ab.name = "if_accept"
	row.add_child(pb)
	row.add_child(ab)
	L.add_child(row)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(400, clampf(150.0 + 40.0 * pl.size(), 120.0, 420.0))
	m.ui_find.visible = true
	m._say("impact frames: %d contact%s. Preview plays them, Accept writes them (Ctrl+Z undoes)" % [pl.size(), "" if pl.size() == 1 else "s"])


func close() -> void:
	halt()
	m._close_findings()


func preview() -> void:
	if pl.is_empty():
		return
	var scenes := _scenes().map(func(s): return (s as Scene).clone())
	var bodies := []
	for s in scenes:
		var b := Body.new()
		b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		b.fk()
		bodies.append(b)
	ImpactFrames.apply(scenes, bodies, pl)
	pv = scenes
	pv_t = maxf(0.0, float(pl[0]["tf"]) - LEAD_IN)
	var last: Dictionary = pl[-1]
	pv_end = minf((scenes[0] as Scene).length(), float(last["tf"]) + float(last["hold"]) + LEAD_OUT)
	m.playing = false
	m._say("impact frames preview: %s (the scene is not changed)" % ", ".join(pl.map(func(p): return "%d f at %s" % [int(p["frames"]), Units.time(float(p["tf"]), m.S.fps)])))


func tick(dt: float) -> void:
	if pv.is_empty():
		return
	pv_t += dt
	if pv_t >= pv_end:
		halt()
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		return
	for k in pv.size():
		(pv[k] as Scene).apply(m.actors_rt[k]["B"], pv_t)
		if k != m.actor_on:
			m.actors_rt[k]["t"] = m.playhead   # _pose_others would pose it from its own scene at the playhead
	m._refresh()
	_shake_view()


## the preview's camera shake (the scene is untouched): the shot's shake at pv_t on the view the user is looking through (the free view or the shot camera)
func _shake_view() -> void:
	var shakes: Array = ShotCam.fx_at((pv[0] as Scene).shots, pv_t).get("shake", [])
	var off := ShotFx.shake_at(shakes, pv_t)
	if off.is_empty():
		if not shaking.is_empty():
			shaking = {}
			m._cam()
		return
	m._cam()
	m.cam.transform = ShotFx.shaken(m.cam.transform, shakes, pv_t)
	shaking = off


func accept() -> void:
	halt()
	var fresh := compute()
	if fresh.is_empty():
		return
	commit(fresh)


## write a plan: ONE undo step on the hero (the shots and markers are its)
func commit(plan: Array) -> void:
	pl = plan
	m._actor_set(0)   # the shots and markers are the hero's; the step is taken on it
	m._step_hint = "Add impact frames"
	m._push_undo()
	ImpactFrames.apply(_scenes(), _bodies(), pl)
	m._retimed()
	m._say("impact frames: %s; the shot camera shakes at each contact, the struck part squashes (Ctrl+Z takes it all back, or 'Remove impact frames')" % ", ".join(pl.map(func(p): return "hit-stop of %d frames at %s (J %.1f N s)" % [int(p["frames"]), Units.time(float(p["tf"]), m.S.fps), float(p["J"])])))
	m.ui_find.visible = false


func remove() -> void:
	halt()
	m._actors_sync()
	if not ImpactFrames.already(m._hero_scene()):
		m._say("no impact frames in this scene: 'Add impact frames' puts them at the contacts")
		return
	m._actor_set(0)
	m._step_hint = "Remove impact frames"
	m._push_undo()
	var n := ImpactFrames.remove(_scenes())
	m._retimed()
	m._say("removed %d hit-stop%s with their shake and squash (Ctrl+Z puts them back)" % [n, "" if n == 1 else "s"])
