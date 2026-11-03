class_name CharCost
extends RefCounted
## C26 (complaint 798, "each extra character costs compute"): a cost line in the scene panel, per character, in ms per frame
## for skinning, the pose / IK solve and the cloth. Opt-in: the palette's "Scene: show cost per character" measures (a few
## repeats of each block, the median) and shows one line in the scene panel's header row; "Scene: hide cost per character"
## takes it off. Nothing is measured or drawn otherwise. The blocks timed are the ones a frame runs for that character:
##   skin  = Overlays.pose_skeleton on its mannequin
##   pose  = Scene.apply (the keys + the IK pins) at the playhead; the body is put back exactly as it was
##   cloth = the secondary chains + the cape draw (only the active character's are drawn, the others show 0)

static var burn := {}   # TEST-ONLY: character name -> ms busy-waited inside its skin block (a planted cost)
const REPS := 15

var m: Node
var rows: Array = []     # [{"name", "skin", "pose", "cloth", "total"}] in ms, one per character
var label: Label


func _init(main: Node) -> void:
	m = main


static func _med(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2]) if not b.is_empty() else 0.0


static func _time(f: Callable, reps: int, spin_ms := 0.0) -> float:
	var ts := []
	for i in reps:
		var t0 := Time.get_ticks_usec()
		f.call()
		if spin_ms > 0.0:
			var until := Time.get_ticks_usec() + int(spin_ms * 1000.0)
			while Time.get_ticks_usec() < until:
				pass
		ts.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	return _med(ts)


func measure(reps := REPS) -> Array:
	rows = []
	var multi: bool = m.actors_rt.size() >= 2
	var n: int = m.actors_rt.size() if multi else 1
	if multi and m.actor_men.size() < n:
		m._refresh()   # the other fighters' mannequins are built by a refresh
	for k in n:
		var B: Body = m.actors_rt[k]["B"] if multi else m.B
		var S: Scene = m.actors_rt[k]["S"] if multi else m.S
		var nm := ("hero" if k == 0 else String(m.actors_rt[k]["name"])) if multi else "hero"
		var active: bool = (k == m.actor_on) if multi else true
		var skel = m.skel
		var idx = m.bone_idx
		if multi and not active:
			skel = null
			if k < m.actor_men.size():
				skel = m.actor_men[k]["skel"]
				idx = m.actor_men[k]["idx"]
		var skin := 0.0
		if skel != null:
			skin = _time(func(): Overlays.pose_skeleton(skel, idx, B), reps, float(burn.get(nm, 0.0)))
		var keep := B.state()
		var at: float = clampf(m.playhead, 0.0, S.length())
		var pose := _time(func(): S.apply(B, at), reps)
		B.set_state(keep)   # the measurement leaves the body exactly as it was
		var cloth := 0.0
		if active:
			cloth = _time(func(): m._sec_draw(); m._cape_draw(), reps)
		rows.append({"name": nm, "skin": skin, "pose": pose, "cloth": cloth, "total": skin + pose + cloth})
	return rows


func total() -> float:
	var s := 0.0
	for r in rows:
		s += float(r["total"])
	return s


func text() -> String:
	var parts := []
	for r in rows:
		parts.append("%s %.2f ms (skin %.2f, pose %.2f, cloth %.2f)" % [r["name"], r["total"], r["skin"], r["pose"], r["cloth"]])
	return "cost per character: " + "  |  ".join(parts) + ("  |  all %.2f ms a frame" % total() if rows.size() > 1 else " a frame")


## measure and show the line in the scene panel's header row
func show() -> void:
	measure()
	if label == null:
		label = Label.new()
		label.name = "char_cost"
		label.add_theme_font_size_override("font_size", 12)
		label.clip_text = true
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size = Vector2(60, 0)
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		(m.ui_bh as Control).add_child(label)
		(m.ui_bh as Control).move_child(label, maxi(0, (m.ui_bh as Control).get_child_count() - 2))   # before the Fold button
	label.text = text()
	label.tooltip_text = text() + "\nms of work per frame for each character's skinning, pose / IK solve and cloth (this machine, just now). More characters cost more: hide the ones you are not posing."
	label.visible = true
	m._say_plain("cost per character: %d shown in the scene panel, %.2f ms a frame in all" % [rows.size(), total()])


func hide() -> void:
	if label != null:
		label.visible = false
