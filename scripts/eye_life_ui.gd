## LIVING EYES panel (ROADMAP I08; the maths: scripts/eye_life.gd). Generates the eye look-at track (saccades, main sequence 2.2 ms/deg + 21 ms,
## fixations 200-400 ms) and the blinks (17 / min at rest, coupled to large gaze shifts, a reflex blink after a hit) for the active fighter.
## Target: with two fighters the opponent's head / chest / weapon, else the camera. Preview plays the clip with the new eyes (the scene is not
## changed), Accept writes the eye_yaw, eye_pitch and blink keys as ONE undo step, Remove takes every key it wrote out again (by its tag).
class_name EyeLifeUI
extends RefCounted

var m: Node
var seed := 1
var plan: Dictionary = {}
var pv := false
var pv_t := 0.0
var pv_face: Dictionary = {}


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Living eyes: saccades and blinks", "", show, "eyes eye look gaze saccade saccades blink blinks living alive face generate",
		false, "an eye look-at track over the scene: saccades to the opponent (head, chest, weapon) or the camera, timed by the main sequence (2.2 ms/deg + 21 ms) with 200-400 ms fixations, and blinks at 17 / min (with large gaze shifts, after hits); preview, then Accept = one undo step; Remove takes it out by its tag")
	add.call("Living eyes: remove the generated eyes", "", remove, "eyes saccade blink remove clear tag generated living",
		false, "takes out every eye and blink key the living eyes generator wrote (by its tag); your own face keys stay; one undo step")


func halt() -> void:
	pv = false


## the target spec for EyeLife.compute: the opponent with two fighters, else the camera (in the active fighter's space)
func opts() -> Dictionary:
	var o := {"seed": seed}
	m._actors_sync()
	if m.actors_rt.size() >= 2:
		var a: int = m.actor_on
		var d := 1 - a if a <= 1 else 0
		o["D"] = m.actors_rt[d]["S"]
		o["xf"] = (m.actors_rt[a]["xf"] as Transform3D).affine_inverse() * (m.actors_rt[d]["xf"] as Transform3D)
	elif m.cam != null:
		o["point"] = m.cam.global_position   # the stage is put under the active fighter (main._stage_xf): his space is the world's
	return o


func compute() -> void:
	plan = EyeLife.compute(m.S, opts())


func show() -> void:
	if m.S.cards.is_empty():
		m._say("living eyes are generated over a scene: open a scene with cards first")
		return
	halt()
	compute()
	_panel()


func reseed() -> void:
	seed += 1
	halt()
	compute()
	_panel()


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("LIVING EYES  -  %s" % String(plan.get("msg", "")), 14, "heading", true)
	title.name = "el_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	L.add_child(m._label("Eyes look at %s. Saccades last 2.2 ms per degree + 21 ms (the main sequence), fixations 200-400 ms; blinks %d / min at rest (more on effort), the lid down in 40-60 ms and up about twice as slow, a blink with each large gaze shift (>= %d deg) and one 40 ms after a hit. Written only to the eye look and blink channels; Accept is one undo step, Remove takes these keys out again." % [
		"the opponent (head, chest, weapon)" if plan.get("two", false) else "the camera", int(EyeLife.REST_RATE), int(EyeLife.LARGE_DEG)], 13, "text:0.6", true))
	var dn := EyeLife.displaced(m.S.face)
	if dn > 0:
		L.add_child(m._label("Accept replaces %d of your own eye / blink key%s (the brows, jaw, lids and mouth stay)." % [dn, "" if dn == 1 else "s"], 13, "text:0.85", true))
	var r2 := HBoxContainer.new()
	var sb: Button = m._button("New seed (%d)" % seed, reseed, "another random track (the same seed always gives the same track)")
	sb.name = "el_seed"
	var pb: Button = m._button("Preview", preview, "play the clip with the new eyes; the scene is not changed")
	pb.name = "el_preview"
	var ab: Button = m._button("Accept", accept, "write the eye look and blink keys; one undo step")
	ab.name = "el_accept"
	var rb: Button = m._button("Remove", remove, "take out every key the generator wrote (by its tag); one undo step")
	rb.name = "el_remove"
	for b in [sb, pb, ab, rb]:
		r2.add_child(b)
	L.add_child(r2)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(420, 220)
	m.ui_find.visible = true
	m._say("living eyes: " + String(plan.get("msg", "")) + ".  Preview plays it, Accept writes it")


func _close() -> void:
	halt()
	m._close_findings()


func preview() -> void:
	if plan.is_empty() or not plan.get("ok", false):
		m._say("nothing to preview: open Living eyes on a scene with cards first")
		return
	pv_face = EyeLife.applied(m.S.face, plan)
	pv_t = 0.0
	pv = true
	m.playing = false
	m._say("living eyes: previewing (the scene is not changed)")


## the face pose the head shows while previewing (main._face_draw asks)
func pose_now() -> Dictionary:
	return Face.at(pv_face, m.S.lip, pv_t, m.S.expr_at(pv_t))


func tick(dt: float) -> void:
	if not pv:
		return
	pv_t += dt
	if pv_t >= float(plan["L"]):
		halt()
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		return
	m._ps().apply(m.B, pv_t)
	m._refresh()


func accept() -> void:
	if plan.is_empty() or not plan.get("ok", false):
		m._say("nothing to accept: open Living eyes on a scene with cards first")
		return
	halt()
	var S: Scene = m.S
	var g := plan
	m._step_hint = "Living eyes"
	m._do(func(): EyeLife.write(S.face, g))
	m._say("living eyes: %s.  Ctrl+Z undoes it in one step" % String(g["msg"]))


func remove() -> void:
	halt()
	var S: Scene = m.S
	var n := EyeLife.count(S.face)
	if n == 0:
		m._say("no generated eyes on this scene to remove")
		return
	m._step_hint = "Remove living eyes"
	m._do(func(): EyeLife.remove(S.face))
	m._say("living eyes removed: %d generated key%s taken out (your own face keys stay).  Ctrl+Z puts them back" % [n, "" if n == 1 else "s"])
