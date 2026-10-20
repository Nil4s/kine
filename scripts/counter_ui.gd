## counter_ui.gd - COUNTER SUGGESTION IN THE APP (ROADMAP Innovations I3). Kept out of main.gd like hit_boxes_ui.gd: main makes
## one (main.counter_ui), lists its command, gives it the keys while it shows, and calls draw() at the end of a refresh.
##   "Counter: suggest the defender's block, slip and parry"   the maths is scripts/counter.gd. The attacker is the active
##   fighter, the defender the next one. Up to three GHOSTS stand on the defender, each with a label (the numbers); the
##   attacker's tip path is drawn in the view. NOTHING of the scene changes until Enter:
##     Tab    the next ghost (the picked one is the brightest)         Esc    put the ghosts away
##     Enter  place the picked one as the defender's card at its time: ONE undo step (the defender becomes the active fighter)
## Any other edit (the undo list changes) puts the ghosts away: they were made for the scene as it was.
class_name CounterUI
extends RefCounted

const KINDS := {"BLOCK": "mk_blue", "SLIP": "mk_green", "DUCK": "mk_green", "PARRY": "mk_gold"}
const GHOST_A := 0.38
const PICK_A := 0.7

var m: Node                    # main.gd
var on := false
var res := {}                  # Counter.suggest's result
var shown := []                # the proposals with a ghost (res["list"] entries that are ok)
var sel := 0                   # the picked one, an index into shown
var def_k := -1                # the defender (actors_rt index)
var att_k := -1
var n_undo := 0                # main.undo.size() when the ghosts were made
var root: Node3D
var _men := []                 # [{node, skel, idx, mat, label}] one per proposal
var _line: MeshInstance3D


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Counter: suggest the defender's block, slip and parry", "", start, "counter suggest defend defender block slip duck parry intercept choreography fight dodge dodge guard ghost",
		true, "for the attacker's current card, three poses for the other fighter built from its own body: a forearm across the weapon's path, a slip or duck that clears it by 10 cm, a parry that deflects it; Tab cycles the ghosts, Enter places one as the defender's card (one undo step), Esc puts them away (Innovations I3)")


## the ghosts for the playhead. Nothing of the scene is touched
func start() -> Dictionary:
	m._actors_sync()
	if m.actors_rt.size() < 2:
		m._say("Counter: needs two fighters: 'Actor: add a second fighter' first, then put the playhead on the attacker's card")
		return {"ok": false}
	att_k = int(m.actor_on)
	def_k = (att_k + 1) % m.actors_rt.size()
	var A: Dictionary = m.actors_rt[att_k]
	var D: Dictionary = m.actors_rt[def_k]
	var r := Counter.suggest(A["S"], A["xf"], D["S"], D["xf"], float(m.playhead))
	if not bool(r["ok"]):
		m._say("Counter: " + String(r["why"]))
		return r
	res = r
	shown = []
	for p in r["list"]:
		if bool(p["ok"]):
			shown.append(p)
	if shown.is_empty():
		var why := []
		for p in r["list"]:
			why.append("%s: %s" % [p["kind"], p["why"]])
		m._say("Counter: nothing intercepts this card. " + " | ".join(why))
		return {"ok": false, "res": r}
	sel = 0
	on = true
	n_undo = m.undo.size()
	_build()
	m._say("Counter: %d ghost%s on %s for %s (%.2f s).  Tab picks the next, Enter places it as %s's card (one undo step), Esc puts them away" % [
		shown.size(), "" if shown.size() == 1 else "s", D["name"], "the attacker's card %d" % (int(r["path"]["ci"]) + 1),
		float(r["path"]["tc"]), D["name"]])
	return {"ok": true, "res": r}


func stop() -> void:
	on = false
	shown = []
	res = {}
	for g in _men:
		(g["node"] as Node3D).visible = false
		(g["label"] as Label3D).visible = false
	if _line != null:
		_line.visible = false


func cycle() -> void:
	if not on or shown.is_empty():
		return
	sel = (sel + 1) % shown.size()
	_tint()
	m._say("Counter: %s  (Tab for the next, Enter places it)" % String(shown[sel]["label"]).get_slice("\n", 0))


## the keys while the ghosts show; true = taken
func input(ev: InputEvent) -> bool:
	if not on or not (ev is InputEventKey) or not (ev as InputEventKey).pressed or (ev as InputEventKey).echo:
		return false
	var k := (ev as InputEventKey).keycode
	if k == KEY_TAB:
		cycle()
		return true
	if k == KEY_ENTER or k == KEY_KP_ENTER:
		accept()
		return true
	if k == KEY_ESCAPE:
		stop()
		m._say("Counter: ghosts put away, nothing changed")
		return true
	return false


## end of a refresh: an edit since the ghosts were made puts them away
func refresh() -> void:
	if on and m.undo.size() != n_undo:
		stop()


## the picked ghost becomes the defender's card at its time. ONE undo step: the defender is made the active fighter first
## (its own cards, its own Ctrl+Z), the step is pushed, the card is made (PoseCopy.card_at: the card before holds up to
## the move, the card after keeps its arrival)
func accept() -> Dictionary:
	if not on or shown.is_empty():
		m._say("Counter: no ghosts to place: run 'Counter: suggest...' on the attacker's card first")
		return {"ok": false}
	var p: Dictionary = shown[sel]
	var k := def_k
	if k >= m.actors_rt.size():
		stop()
		return {"ok": false}
	m._actor_set(k)
	if int(m.actor_on) != k:
		m._say("Counter: that fighter is read only here: press Co-edit: stop to animate it, then try again")
		return {"ok": false}
	m._push_undo()
	var flags := {"steps": {"_l": [0.0, 0.0, 0.0], "_r": [0.0, 0.0, 0.0]}}
	var kind := String(p["kind"])
	var ci := PoseCopy.card_at(m.S, float(p["t"]), p["pose"], "counter " + kind.to_lower(), flags)
	m.actors_rt[k]["t"] = NAN
	m._rebuild_cards()
	m.ov.mark_dirty()
	m.wt.mark_dirty()
	var t := float(p["t"])
	stop()
	m._refresh()
	m._say("Counter %s placed as %s's card %d at %.2f s.  Ctrl+Z takes it back" % [kind.to_lower(), m.actors_rt[k]["name"], ci + 1, t])
	return {"ok": true, "card": ci, "t": t}


# ---------------------------------------------------------------- drawing

func _build() -> void:
	if root == null or not is_instance_valid(root):
		root = Node3D.new()
		root.name = "counter_ghosts"
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
	while _men.size() < shown.size():
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		var mq := Overlays.mannequin(root, mat)
		var lab := Label3D.new()
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.no_depth_test = true
		lab.fixed_size = true
		lab.pixel_size = 0.0011
		lab.font_size = 20
		lab.outline_size = 6
		lab.render_priority = 3
		root.add_child(lab)
		_men.append({"node": mq[0], "skel": mq[1], "idx": mq[2], "mat": mat, "label": lab})
	for g in _men:
		(g["node"] as Node3D).visible = false
		(g["label"] as Label3D).visible = false
	var D: Dictionary = m.actors_rt[def_k]
	var dxf: Transform3D = D["xf"]
	var lat: Vector3 = dxf.basis * Vector3.RIGHT
	for i in shown.size():
		var p: Dictionary = shown[i]
		var g: Dictionary = _men[i]
		var G: Body = p["B"]
		var n := g["node"] as Node3D
		n.transform = dxf
		Overlays.pose_skeleton(g["skel"], g["idx"], G)
		n.visible = true
		var lab := g["label"] as Label3D
		lab.text = String(p["label"])
		lab.position = dxf * (G.P["head"] as Vector3) + Vector3(0, 0.45, 0) + lat * (float(i) - float(shown.size() - 1) * 0.5) * 0.95
		lab.visible = true
	_tint()
	_path_draw()


func _tint() -> void:
	for i in shown.size():
		var g: Dictionary = _men[i]
		var col: Color = Tok.c(String(KINDS.get(String(shown[i]["kind"]), "mk_blue")))
		col.a = PICK_A if i == sel else GHOST_A
		(g["mat"] as StandardMaterial3D).albedo_color = col
		var lab := g["label"] as Label3D
		lab.modulate = Tok.c(String(KINDS.get(String(shown[i]["kind"]), "mk_blue")))
		lab.outline_modulate = Tok.c("ink") if Tok.dark == false else Color(0, 0, 0, 0.9)
		lab.font_size = 24 if i == sel else 20


## the attacker's tip path, a cross where each block / parry meets it, a leader from each label to its ghost's point
func _path_draw() -> void:
	var im := _line.mesh as ImmediateMesh
	im.clear_surfaces()
	var P: Dictionary = res["path"]
	var ps: Array = P["p"]
	var red: Color = Tok.c("mk_red")
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for q in ps:
		im.surface_set_color(red)
		im.surface_add_vertex(q)
	im.surface_end()
	var marks := shown.filter(func(q): return q.has("X"))
	if not marks.is_empty():
		im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in shown.size():
		var p: Dictionary = shown[i]
		var col: Color = Tok.c(String(KINDS.get(String(p["kind"]), "mk_blue")))
		if p.has("X"):
			var X: Vector3 = p["X"]
			for d in [Vector3(0.05, 0, 0), Vector3(0, 0.05, 0), Vector3(0, 0, 0.05)]:
				im.surface_set_color(col)
				im.surface_add_vertex(X - d)
				im.surface_set_color(col)
				im.surface_add_vertex(X + d)
	if not marks.is_empty():
		im.surface_end()
	_line.visible = true
