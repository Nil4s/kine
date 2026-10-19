## godot --path . -s tests/fighter_hover_test.gd     (a window: real mouse motion through the viewport)
## FIGHTER HOVER. With two fighters, the mouse over a part of the fighter that is NOT active lights that part the way
## hovering the active fighter does (PRECISE PICK: the hover light on that part's own skin, SkinPick). Each fighter that is not active also draws
## its off-hand weapon (the dagger) where its Body holds it, as its main weapon is drawn. combo3 is opened read only.
## Bars, written before measuring:
##   1 HOVER: a mouse motion over fighter 2's right forearm (its projected centre) makes hover_fighter 1 and hover_fpart
##     lowerarm_r, the active fighter's hover_part stays "", and fighter 2's skin carries the hover look on that part only
##   2 OFF HAND: fighter 2's dagger (wep2) is drawn: its handle and blade cylinders end at Body.wep2_point(0),
##     wep2_point(handle) and wep2_point(handle), wep2_point(len), each end within 1 mm, in fighter 2's body space
##   3 OFF: a motion over empty space clears the fighter hover (hover_fighter -1, the light hidden)
## Shot: none. Nothing is written to scenes/, poses/ or data/.
extends SceneTree

var fails := 0
var m: Node
const BOTH := [70.0, -12.0, 4.6, Vector3(0, 0.95, 0.75)]   # both fighters side by side (as actors_view_test)


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## a mouse motion with no button down (hover)
func hover(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e)
	await idle(3)


func cam(c: Array) -> void:
	m._turn_to(c[0], c[1], c[2], c[3], false)
	await idle(2)


func open_combo() -> void:
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.playhead = 0.9
	m.playing = false
	m._ps().apply(m.B, m.playhead)
	m.sel = "head"
	m.hover_part = ""
	m._refresh()
	m.undo.clear()
	m.redo.clear()
	await m.dummy_settle()
	m._refresh()
	await idle(3)


## actor k's body space -> the world (the stage's transform, then its placement), as actors_view_test
func body_to_world(k: int) -> Transform3D:
	return m.stage_root.global_transform * (m.actors_rt[k]["xf"] as Transform3D)


## where a cylinder's two ends sit in its parent's (body) space: its local Y runs from -h/2 to +h/2
func ends(mi: MeshInstance3D) -> Array:
	var h := (mi.mesh as CylinderMesh).height
	return [mi.transform * Vector3(0, -h * 0.5, 0), mi.transform * Vector3(0, h * 0.5, 0)]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await open_combo()

	m._actor_add()
	await idle(3)
	ok(m.actors_rt.size() == 2 and m.actor_men.size() == 2, "setup: two fighters, fighter 2's mannequin drawn")
	var B1: Body = m.actors_rt[1]["B"]
	B1.wep2_to_hand("hand_l")   # fighter 2 holds the dagger in its left hand (the Body's own call, no undo step)
	m._refresh()
	await idle(3)
	await cam(BOTH)

	# ---- (1) hover over fighter 2's right forearm
	var c: Array = B1.cap("lowerarm_r")
	var mid: Vector3 = (c[0] + c[1]) * 0.5
	var sp: Vector2 = m.cam.unproject_position(body_to_world(1) * mid)
	await hover(sp)
	var fp: SkinPick = m.actor_men[1]["skp"]
	ok(m.hover_fighter == 1 and m.hover_fpart == "lowerarm_r" and m.hover_part == "",
		"1: hover over fighter 2's forearm at %s: hover_fighter %d, part %s, the active fighter's hover %s" % [str(sp), m.hover_fighter, m.hover_fpart, str(m.hover_part)])
	ok(fp._state.keys() == ["lowerarm_r"] and not fp.look_of("lowerarm_r").is_empty(),
		"1: fighter 2's light is on its forearm's own skin, nothing else (%s)" % [str(fp._state.keys())])

	# ---- (2) the second weapon, at fighter 2's Body points
	var hu := float(Body.KINDS[B1.wep2_kind]["handle"])
	var hm: MeshInstance3D = m.actor_men[1]["wep2"][0]
	var bl: MeshInstance3D = m.actor_men[1]["wep2"][1]
	ok(hm.visible and bl.visible, "2: fighter 2's dagger is drawn (handle and blade visible)")
	var eh := ends(hm)
	var eb := ends(bl)
	var e_h0 := B1.wep2_point(0.0)
	var e_h1 := B1.wep2_point(hu)
	var e_b1 := B1.wep2_point(B1.wep2_len())
	var errs := [(eh[0] - e_h0).length(), (eh[1] - e_h1).length(), (eb[0] - e_h1).length(), (eb[1] - e_b1).length()]
	var worst := 0.0
	for e in errs:
		worst = maxf(worst, float(e))
	ok(worst < 0.001, "2: the dagger's handle and blade end on fighter 2's wep2 points, worst %.3f mm" % (worst * 1000.0))

	# ---- (3) off the fighters: the hover goes
	await hover(Vector2(4, 4))
	ok(m.hover_fighter == -1 and fp._state.is_empty(), "3: the mouse over empty space: no fighter hover, the light off")

	print("fighter_hover: %d fail(s)" % fails)
	quit(fails)
