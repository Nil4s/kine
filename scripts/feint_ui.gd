## feint_ui.gd - FEINT MAKER IN THE APP (ROADMAP Innovations I20; the maths: scripts/feint.gd). Kept out of main.gd like counter_ui.gd.
##   "Make this a feint"   on the picked strike card (the selected card, else the card the playhead is in): the FEINT ghost (where the
##   attacker stops, gold) and the REAL STRIKE ghost of the picked variant (blue) stand on the attacker, labelled with the numbers and
##   what Check says about the result. The scene is not changed until Enter:
##     Tab  the next variant (OTHER SIDE / LOW / LIBRARY)      P  preview it playing (nothing changed)
##     Enter  accept: the attacker's three moves (and the defender's counter card, moved onto the feint) in ONE undo step
##     Esc  put the ghosts away
## Any other edit (the undo list changes) puts the ghosts away: they were made for the scene as it was.
class_name FeintUI
extends RefCounted

const GHOST_A := 0.4
const PICK_A := 0.72

var m: Node
var on := false
var res := {}
var sel := 0
var att_k := -1
var def_k := -1
var n_undo := 0
var base: Array = []          # Check on the scene as it is (what was red before)
var checks := {}              # option index -> findings (Rulebook)
var root: Node3D
var _fg := {}                 # the feint ghost {node, skel, idx, mat, label}
var _rg := {}                 # the real-strike ghost
var _line: MeshInstance3D
var pv: Scene = null
var pv_def: Scene = null
var pv_t := 0.0
var pv_end := 0.0


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Make this a feint", "", start, "feint fake bluff strike feign re-chamber mirror other side low fight choreography timing counter ghost",
		true, "turn the picked strike card into a feint that starts on the strike's line and stops half way, a short re-chamber, then the real strike from the other side or another level; Tab cycles the variants, P previews, Enter accepts (one undo step), Esc puts the ghosts away (Innovations I20)")


func start(ci := -1) -> Dictionary:
	m._actors_sync()
	if m.actors_rt.size() < 2:
		m._say("Make this a feint: needs two fighters: 'Actor: add a second fighter' first, then pick the strike card")
		return {"ok": false}
	att_k = int(m.actor_on)
	def_k = (att_k + 1) % m.actors_rt.size()
	var A: Dictionary = m.actors_rt[att_k]
	var D: Dictionary = m.actors_rt[def_k]
	if ci < 0:
		ci = int(m.sel_card) if int(m.sel_card) >= 0 else Counter.card_of(A["S"], float(m.playhead))
	var r := Feint.make(A["S"], A["xf"], D["S"], D["xf"], ci)
	if not bool(r["ok"]):
		m._say("Make this a feint: " + String(r["why"]))
		return r
	res = r
	sel = 0
	checks = {}
	base = []
	on = true
	n_undo = m.undo.size()
	_build()
	m._say("Make this a feint: card %d stops at %.0f%% of its reach after %.2f s; %d variant%s.  Tab picks, P previews, Enter accepts (one undo step), Esc puts the ghosts away" % [
		ci + 1, float(r["frac"]) * 100.0, float(r["Tf"]), (r["options"] as Array).size(), "" if (r["options"] as Array).size() == 1 else "s"])
	return {"ok": true, "res": r}


func stop() -> void:
	on = false
	pv = null
	res = {}
	for g in [_fg, _rg]:
		if not g.is_empty():
			(g["node"] as Node3D).visible = false
			(g["label"] as Label3D).visible = false
	if _line != null:
		_line.visible = false


func cycle() -> void:
	if not on:
		return
	sel = (sel + 1) % (res["options"] as Array).size()
	_build()
	m._say("Make this a feint: %s  (Tab for the next, Enter accepts)" % String(res["options"][sel]["label"]))


func input(ev: InputEvent) -> bool:
	if not on or not (ev is InputEventKey) or not (ev as InputEventKey).pressed or (ev as InputEventKey).echo:
		return false
	var k := (ev as InputEventKey).keycode
	if k == KEY_TAB:
		cycle()
		return true
	if k == KEY_P:
		preview()
		return true
	if k == KEY_ENTER or k == KEY_KP_ENTER:
		accept()
		return true
	if k == KEY_ESCAPE:
		stop()
		m._say("Make this a feint: ghosts put away, nothing changed")
		return true
	return false


func refresh() -> void:
	if on and pv == null and m.undo.size() != n_undo:
		stop()


func picked() -> Dictionary:
	return res["options"][sel]


func findings(k: int) -> Array:
	if not checks.has(k):
		checks[k] = Feint.check(res["options"][k]["scene"])
	return checks[k]


func preview() -> void:
	if not on:
		m._say("Make this a feint: nothing to preview: run 'Make this a feint' on a strike card first")
		return
	var o := picked()
	pv = (o["scene"] as Scene).clone()
	pv_def = (o["def"] as Scene).clone() if o["def"] != null else null
	pv_t = 0.0
	pv_end = pv.length()
	m.playing = false
	m._say("Make this a feint: previewing %s (the scene is not changed)" % String(o["label"]))


func tick(dt: float) -> void:
	if pv == null:
		return
	pv_t += dt
	if pv_t >= pv_end:
		pv = null
		pv_def = null
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		return
	pv.apply(m.actors_rt[att_k]["B"], pv_t)
	(pv_def if pv_def != null else (m.actors_rt[def_k]["S"] as Scene)).apply(m.actors_rt[def_k]["B"], pv_t)
	m._refresh()


## the three moves are the attacker's cards from now on; ONE undo step
func accept() -> Dictionary:
	if not on:
		m._say("Make this a feint: nothing to accept: run 'Make this a feint' on a strike card first")
		return {"ok": false}
	var o := picked()
	pv = null
	m._actors_sync()
	m._step_hint = "Make this a feint"
	m._push_undo()
	(m.actors_rt[att_k]["S"] as Scene).cards = (o["scene"] as Scene).cards.duplicate(true)
	if o["def"] != null:
		(m.actors_rt[def_k]["S"] as Scene).cards = (o["def"] as Scene).cards.duplicate(true)
	m._actors_sync()
	m._rebuild_cards()
	m.ov.mark_dirty()
	m.wt.mark_dirty()
	var lbl := String(o["label"])
	stop()
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	m._say("Make this a feint: %s real strike placed after a feint.  Ctrl+Z takes it back in one step" % lbl.to_lower())
	return {"ok": true}


# ---------------------------------------------------------------- drawing

func _ghost(name: String) -> Dictionary:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	var mq := Overlays.mannequin(root, mat)
	var lab := Label3D.new()
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.fixed_size = true
	lab.pixel_size = 0.0007
	lab.font_size = 15
	lab.outline_size = 6
	lab.render_priority = 3
	root.add_child(lab)
	return {"node": mq[0], "skel": mq[1], "idx": mq[2], "mat": mat, "label": lab}


func _put(g: Dictionary, pose: Dictionary, xf: Transform3D, col: Color, text: String, up: float) -> void:
	var G := Counter.scratch(m.actors_rt[att_k]["S"])
	G.from_dict(pose)
	G.fk()
	var n := g["node"] as Node3D
	n.transform = xf
	Overlays.pose_skeleton(g["skel"], g["idx"], G)
	n.visible = true
	(g["mat"] as StandardMaterial3D).albedo_color = col
	var lab := g["label"] as Label3D
	lab.text = text
	lab.modulate = Color(col.r, col.g, col.b, 1.0)
	lab.outline_modulate = Tok.c("ink") if Tok.dark == false else Color(0, 0, 0, 0.9)
	lab.position = xf * (G.P["head"] as Vector3) + Vector3(0, 0.3 + up, 0)
	lab.visible = true


func _build() -> void:
	if root == null or not is_instance_valid(root):
		root = Node3D.new()
		root.name = "feint_ghosts"
		m.stage_root.add_child(root)
		_line = MeshInstance3D.new()
		_line.mesh = ImmediateMesh.new()
		var lm := StandardMaterial3D.new()
		lm.vertex_color_use_as_albedo = true
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.no_depth_test = true
		lm.render_priority = 2
		_line.material_override = lm
		root.add_child(_line)
		_fg = _ghost("feint")
		_rg = _ghost("real")
	var o := picked()
	var xf: Transform3D = m.actors_rt[att_k]["xf"]
	var fc := Tok.c("mk_gold")
	fc.a = PICK_A
	var rc := Tok.c("mk_blue")
	rc.a = PICK_A
	var fl := findings(sel)
	if base.is_empty():
		base = Feint.check(m.actors_rt[att_k]["S"])
	var red := Feint.red_new(fl, base)
	var chk := "Check: no new problems (%d already in the scene)" % fl.size() if red.is_empty() else "Check: %d NEW red (%s)" % [red.size(), ", ".join(red.slice(0, 2).map(func(f): return "%s %.2f s" % [f["rule"], f["t"]]))]
	_put(_fg, res["F"], xf, fc, "FEINT  stops at %.0f%% of the reach, %.2f s after the wind-up starts to read\n(the stop comes %.2f s after it is readable; a human needs %.1f s)" % [
		float(res["frac"]) * 100.0, float(o["t_stop"]) - float(res["t_read"]), float(o["t_stop"]) - float(res["t_read"]), Feint.REACT], 0.0)
	_put(_rg, o["real_pose"], xf, rc, "REAL STRIKE  %s  (%d/%d, Tab)\nmove %.2f s, lands %.0f cm from the target\n%s" % [
		String(o["label"]), sel + 1, (res["options"] as Array).size(), float(o["move"]), maxf(0.0, float(o["gap"])) * 100.0, chk], 0.55)
	# the original tip path (red) up to the arrival, and the feint's stop (a cross)
	var im := _line.mesh as ImmediateMesh
	im.clear_surfaces()
	var P: Dictionary = res["path"]
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for q in P["p"]:
		im.surface_set_color(Tok.c("mk_red"))
		im.surface_add_vertex(q)
	im.surface_end()
	var X := Counter.path_at(P, float(res["tf"]))
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for d in [Vector3(0.05, 0, 0), Vector3(0, 0.05, 0), Vector3(0, 0, 0.05)]:
		im.surface_set_color(fc)
		im.surface_add_vertex(X - d)
		im.surface_set_color(fc)
		im.surface_add_vertex(X + d)
	im.surface_end()
	_line.visible = true
