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

const FEINT_A := 0.8     # the feint ghost (gold) is the more opaque, the real strike (blue) the clearer: neither hides the other
const REAL_A := 0.34
const GAP := 6.0

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
var hud: CanvasLayer          # the two labels are 2D (exact rectangles, stacked inside the window, a leader line to each ghost's head)
var rects: Array = []         # their rectangles, [feint, real]
var trails := {}              # option index -> the real strike's tip path (world points)
var pv: Scene = null
var pv_def: Scene = null
var pv_t := 0.0
var pv_end := 0.0
var label_at := Vector2(-1.0, 100.0)   # where the labels stack: x < 0 = the default (left of the stage, right of the browser); the fight rhythm panel puts them at the right


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
	rects = []
	trails = {}
	for g in [_fg, _rg]:
		if not g.is_empty():
			(g["node"] as Node3D).visible = false
			(g["label"] as Label).visible = false
			(g["lead"] as Line2D).visible = false
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
		layout()   # the leader lines follow the camera
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

func _ghost() -> Dictionary:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	var mq := Overlays.mannequin(root, mat)
	var lab := Label.new()
	lab.add_theme_font_size_override("font_size", 14)
	lab.add_theme_constant_override("outline_size", 5)
	lab.add_theme_constant_override("line_spacing", -3)
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.custom_minimum_size = Vector2(235, 0)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(lab)
	var lead := Line2D.new()
	lead.width = 1.5
	hud.add_child(lead)
	return {"node": mq[0], "skel": mq[1], "idx": mq[2], "mat": mat, "label": lab, "lead": lead}


func _put(g: Dictionary, pose: Dictionary, xf: Transform3D, col: Color, text: String) -> void:
	var G := Counter.scratch(m.actors_rt[att_k]["S"])
	G.from_dict(pose)
	G.fk()
	var n := g["node"] as Node3D
	n.transform = xf
	Overlays.pose_skeleton(g["skel"], g["idx"], G)
	n.visible = true
	(g["mat"] as StandardMaterial3D).albedo_color = col
	var lab := g["label"] as Label
	lab.text = text
	var solid := Color(col.r, col.g, col.b, 1.0)
	lab.add_theme_color_override("font_color", solid)
	lab.add_theme_color_override("font_outline_color", Tok.c("ink") if not Tok.dark else Color(0, 0, 0, 0.9))
	lab.visible = true
	(g["lead"] as Line2D).default_color = solid
	(g["lead"] as Line2D).visible = true
	g["head"] = xf * (G.P["head"] as Vector3)


## the two labels stacked at the left of the stage (right of the browser panel), the feint's above the real strike's, each fully
## inside the window, with a leader line to the ghost's head
func layout() -> void:
	if not on or _fg.is_empty():
		return
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	rects = []
	var y := label_at.y
	for g in [_fg, _rg]:
		var lab := g["label"] as Label
		lab.size = Vector2(239, 0)
		var sz := Vector2(239, lab.get_combined_minimum_size().y + 2.0)
		lab.size = sz
		var r := Rect2(Vector2(minf(252.0 if label_at.x < 0.0 else label_at.x, maxf(8.0, vp.x - sz.x - 8.0)), clampf(y, 8.0, maxf(8.0, vp.y - sz.y - 8.0))), sz)
		lab.position = r.position
		rects.append(r)
		y = r.end.y + GAP
		var h: Vector3 = m.stage_root.global_transform * (g["head"] as Vector3)
		var ln := g["lead"] as Line2D
		ln.clear_points()
		if not m.cam.is_position_behind(h):
			ln.add_point(Vector2(r.end.x, r.get_center().y))
			ln.add_point(m.cam.unproject_position(h))


func _strip(im: ImmediateMesh, pts: Array, col: Color, w: float) -> void:
	if pts.size() < 2:
		return
	for o in ([Vector3.ZERO] if w <= 1.0 else [Vector3.ZERO, Vector3(0, 0.004, 0), Vector3(0, -0.004, 0), Vector3(0.004, 0, 0), Vector3(-0.004, 0, 0)]):   # 1 px lines: a thick one is a few side by side
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for q in pts:
			im.surface_set_color(col)
			im.surface_add_vertex(q + o)
		im.surface_end()


func _cross(im: ImmediateMesh, X: Vector3, col: Color, r: float) -> void:
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for d in [Vector3(r, 0, 0), Vector3(0, r, 0), Vector3(0, 0, r)]:
		im.surface_set_color(col)
		im.surface_add_vertex(X - d)
		im.surface_set_color(col)
		im.surface_add_vertex(X + d)
	im.surface_end()


## the real strike's tip path over its own move (world points), for variant k
func real_trail(k: int) -> Array:
	if not trails.has(k):
		var o: Dictionary = res["options"][k]
		var N: Scene = o["scene"]
		var DS: Scene = (o["def"] as Scene) if o["def"] != null else (m.actors_rt[def_k]["S"] as Scene)
		var B := Counter.scratch(N)
		var DB := Counter.scratch(DS)
		var ts := N.times()
		var ta := float(ts[int(o["k_real"])][0])
		var tb := float(ts[int(o["k_real"])][1])
		var pts := []
		var n := int(ceil((tb - ta) * 60.0))
		for i in n + 1:
			var t := minf(ta + float(i) / 60.0, tb)
			N.apply(B, t)
			DS.apply(DB, t)
			pts.append(Choreo.tip(B, m.actors_rt[att_k]["xf"], DB, m.actors_rt[def_k]["xf"])["p"])
		trails[k] = pts
	return trails[k]


func _build() -> void:
	if root == null or not is_instance_valid(root):
		root = Node3D.new()
		root.name = "feint_ghosts"
		m.stage_root.add_child(root)
		hud = CanvasLayer.new()
		hud.layer = 5
		m.add_child(hud)
		_line = MeshInstance3D.new()
		_line.mesh = ImmediateMesh.new()
		var lm := StandardMaterial3D.new()
		lm.vertex_color_use_as_albedo = true
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.no_depth_test = true
		lm.render_priority = 2
		_line.material_override = lm
		root.add_child(_line)
		_fg = _ghost()
		_rg = _ghost()
	var o := picked()
	var xf: Transform3D = m.actors_rt[att_k]["xf"]
	var fc := Tok.c("mk_gold")
	var rc := Tok.c("mk_blue")
	var fl := findings(sel)
	if base.is_empty():
		base = Feint.check(m.actors_rt[att_k]["S"])
	var red := Feint.red_new(fl, base)
	var chk := "Check: no new problems (%d already in the scene)" % fl.size() if red.is_empty() else "Check: %d NEW red (%s)" % [red.size(), ", ".join(red.slice(0, 2).map(func(f): return "%s %.2f s" % [f["rule"], f["t"]]))]
	var rd := float(o["t_stop"]) - float(res["t_read"])
	var fa := fc
	fa.a = FEINT_A
	var ra := rc
	ra.a = REAL_A
	_put(_fg, res["F"], xf, fa, "FEINT (gold)  stops at %.0f%% of the reach\n%.2f s after the wind-up can be read (a human needs %.1f s)" % [float(res["frac"]) * 100.0, rd, Feint.REACT])
	_put(_rg, o["real_pose"], xf, ra, "REAL STRIKE (blue)  %s  (%d/%d, Tab)\nmove %.2f s, lands %.0f cm from the target\n%s" % [
		String(o["label"]), sel + 1, (res["options"] as Array).size(), float(o["move"]), maxf(0.0, float(o["gap"])) * 100.0, chk])
	# the original tip path (thin red) to the arrival; the feint's part of it (gold) to the stop; the real strike's own path (blue)
	var im := _line.mesh as ImmediateMesh
	im.clear_surfaces()
	var P: Dictionary = res["path"]
	var red_c := Tok.c("mk_red")
	red_c.a = 0.55
	var pp := []
	var fp := []
	for i in (P["p"] as Array).size():
		pp.append(P["p"][i])
		if float(P["ts"][i]) <= float(res["tf"]):
			fp.append(P["p"][i])
	fp.append(Counter.path_at(P, float(res["tf"])))
	_strip(im, pp, red_c, 1.0)
	_strip(im, fp, fc, 3.0)
	_strip(im, real_trail(sel), rc, 3.0)
	_cross(im, Counter.path_at(P, float(res["tf"])), fc, 0.06)
	var tr := real_trail(sel)
	if not tr.is_empty():
		_cross(im, tr[-1], rc, 0.06)
	_line.visible = true
	layout()
