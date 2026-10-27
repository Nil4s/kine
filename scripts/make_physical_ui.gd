## MAKE IT PHYSICAL, the app side (ROADMAP Innovations I1; the maths: scripts/make_physical.gd, the judge: tools/physics/judge.py).
## Kept out of main.gd: main makes one (main.mp_ui), lists its commands, calls tick() each frame.
##   "Make it physical"  judges the scene in a child Python process (the window keeps drawing; progress in the status line); the red spans
##                       paint a lane on the timeline (hover = the reason), the physical version stands as a ghost body that follows
##                       the playhead (scrub it).
##   "Accept span"       replaces the cards inside the picked red span by the physical version at card density: ONE undo step.
class_name MakePhysicalUI
extends RefCounted

var m: Node
var mp := MakePhysical.new()
var python := "python"       # tests may point it elsewhere
var ghost: Node3D = null
var gskel: Skeleton3D = null
var gidx := {}
var gbody: Body = null
var sel := -1                # the red span picked (an index into mp.spans)
var _say_t := 0.0
var _hooked := false
var _seen: Array = []        # what the lane was last drawn from (scene, cards, length, run state): a change redraws it


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Make it physical", "", run, "make it physical physics judge mujoco jump fall torque slide force impossible human body red span ghost", false,
		"judge the motion with a 75 kg body in a physics engine: red on the timeline where no human body can do it (a jump with no push, a fall, a joint over its strength, a slipping foot), with the reason; the physical version stands as a ghost you can scrub")
	add.call("Accept span", "", accept, "accept span physical replace cards red", false,
		"replace the cards inside the picked red span (click it on the timeline) with the physical version, keyed as densely as your cards; one undo step")
	add.call("Keep this pose", "", keep_toggle, "keep this pose priority card protect freeze physical accept span", false,
		"the picked card becomes a priority card: Make it physical never changes it and Accept span keeps it as it is; press again to clear it")
	add.call("Physical ghost off", "", clear, "physical ghost off clear red spans make it physical", false, "remove the red lane and the ghost body")


func run() -> void:
	if m.S.cards.size() < 2:
		m._say("Make it physical needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	if mp.running():
		m._say("still judging: %d %% done; the red spans appear on the timeline when it ends" % int(mp.progress * 100.0))
		return
	_ghost_build()   # the mannequin loads now, not in the frame the result lands
	var body0: Dictionary = m.B.state()   # a view: the body comes back as it was
	var err := mp.begin(m.S, m.B, python)
	m.B.set_state(body0)
	m.B.fk()
	if err != "":
		m._say(err)
		return
	_say_t = 0.0
	m._say("judging '%s' in physics (a minute for a few seconds of motion; keep working)..." % m.S.name)


func tick(dt: float) -> void:
	# A1: the lane follows the cards and the judge: a card edit turns its frames blue, the run's progress moves the gray
	var seen := [m.S.get_instance_id(), m.S.cards.hash(), m.S.length(), mp.progress if mp.running() else -1.0]
	if m.ui_timeline != null and seen != _seen:
		_seen = seen
		_lane()
	if mp.running():
		_say_t += dt
		if _say_t > 2.0:
			_say_t = 0.0
			m._say("judging in physics: %d %%" % int(mp.progress * 100.0))
		if mp.poll():
			_landed()
		elif mp.done:
			m._say(mp.failed)
	if ghost != null and ghost.visible:
		_ghost_update()


func _landed() -> void:
	sel = -1
	_lane()
	_ghost_build()
	_ghost_update()
	var n := mp.spans.size()
	var note := ""
	if not mp.notes.is_empty():
		note = " (and %d gold note%s: the clip's own foot slide)" % [mp.notes.size(), "" if mp.notes.size() == 1 else "s"]
	m._say("physical: %.0f %% of the motion is red in %d span%s%s; hover a red block for the reason, click it, then Accept span" % [mp.red_pct(), n, "" if n == 1 else "s", note])


func _lane() -> void:
	var tl: Timeline = m.ui_timeline
	var before := tl.ph_px()
	tl.ph = mp.lane(m.S)
	tl.ph_sel = sel
	if not _hooked:
		_hooked = true
		tl.ph_picked.connect(pick)
	if before != tl.ph_px():
		m._tl_height()
		m._layout_bottom()
	tl.queue_redraw()


func pick(i: int) -> void:
	sel = i
	m.ui_timeline.ph_sel = i
	m.ui_timeline.queue_redraw()
	if i >= 0 and i < mp.spans.size():
		m._say("picked the red span %.2f-%.2f s: %s.  Accept span replaces its cards." % [float(mp.spans[i]["t0"]), float(mp.spans[i]["t1"]), mp.spans[i]["reason"]])


func _ghost_build() -> void:
	if ghost != null:
		return
	var mat := StandardMaterial3D.new()
	var c := Tok.c("fd_active")
	c.a = 0.45
	mat.albedo_color = c
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.7
	var q := Overlays.mannequin(m, mat)
	ghost = q[0]
	gskel = q[1]
	gidx = q[2]
	gbody = Body.new()
	gbody.load_files("res://data/skeleton.json", "res://data/body_limits.json")


func _ghost_update() -> void:
	if ghost == null or gbody == null:
		return
	if not mp.ghost_pose(gbody, m.playhead):
		ghost.visible = false
		return
	ghost.visible = true
	Overlays.pose_skeleton(gskel, gidx, gbody)


func accept() -> void:
	if sel < 0 or sel >= mp.spans.size():
		m._say("pick a red span first: run Make it physical, then click a red block on the timeline")
		return
	if MakePhysical.cards_in(m.S, mp.spans[sel]).is_empty():
		m._say("no card lies inside this red span (it is between two cards): add a card at the playhead inside it, then Accept span")
		return
	if MakePhysical.replaceable(m.S, mp.spans[sel]) == 0:
		m._say("every card inside this red span is kept (Keep this pose): none is replaced; press Keep this pose again on one to clear it")
		return
	m._step_hint = "Accept physical span"
	m._push_undo()
	m._markers_hold()
	var n := mp.accept(m.S, m.B, sel)
	m._markers_follow()
	m._retimed()
	m._rebuild_cards()
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	m._say("accepted: the span's cards are now %d physical cards; Ctrl+Z puts them back. Run Make it physical again to judge the new motion" % n)
	clear()


## A1: the picked card is a priority card ("keep"): Make it physical never changes it, Accept span keeps it. A second press clears it
func keep_toggle() -> void:
	var i: int = m.sel_card
	if i < 0 or i >= m.S.cards.size():
		m._say("pick a card first: click it on the timeline, then press Keep this pose")
		return
	m._push_undo()
	var c: Dictionary = m.S.cards[i]
	if bool(c.get("keep", false)):
		c.erase("keep")
	else:
		c["keep"] = true
	m._rebuild_cards()
	m._refresh()
	m._say("card %d is kept: Make it physical and Accept span leave it as it is" % (i + 1) if c.has("keep") else "card %d is no longer kept" % (i + 1))


func clear() -> void:
	mp.stop()
	mp.spans = []
	mp.notes = []
	mp.phys = []
	sel = -1
	if ghost != null:
		ghost.visible = false
	if m.ui_timeline != null:
		_lane()


func halt() -> void:
	mp.stop()
