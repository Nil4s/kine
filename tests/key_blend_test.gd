## godot --path . -s tests/key_blend_test.gd     (round 48, GATES DD1, UPGRADES_300 #246)
## SHAPE TOOLS: Blender's Key > Blend set in the curve editor (scripts/key_blend.gd). Seven keys on the right forearm,
## one a second (bend 0, 10, 30, 50, 40, 20, 0; side 7; twist -3); the three middle BEND keys (t 2, 3, 4) selected, so
## the left neighbour is (1 s, 10) and the right (5 s, 20). Every expected number below is the manual's sentence worked
## by hand (editing.rst, Key > Blend), not read from the code:
##   breakdown f 0 -> all (10+20)/2 = 15; f -1 -> all 10; f 1 -> all 20
##   blend to neighbour f 0.5 -> halfway to R: 25, 35, 30; f -0.5 -> halfway to L: 20, 30, 25
##   push / pull f 0 -> onto the line through the first and last selected (2 s, 30)-(4 s, 40): 30, 35, 40; f 2 -> 30, 65, 40
##   ease f 0 -> an S from L to R: at 3 s (the middle) (10+20)/2 = 15, the curve's slope at the middle above the straight
##     line's and below it at the ends (an S); f 1 (bend right) puts the middle nearer R than f 0 does
##   match slope f 1 -> on the line through the two keys right of the selection, (5, 20)-(6, 0): 80, 60, 40; f 0.5 -> halfway
##   scale from neighbour f 2 (pivot L = 10) -> 50, 90, 70
##   blend offset f 1 -> the last (40) meets R (20): all -20: 10, 30, 20; f -1 -> the first (30) meets L (10): 10, 30, 20
## and for every tool: the unselected keys, the side and twist angles and every time unchanged; one undo step; Ctrl+Z
## exact. A run at the end (key 0 selected) is skipped by breakdown (no left neighbour) and reported. The menu: its
## seven items, and the item chosen through the popup applies with the factor box's value.
extends SceneTree

var fails := 0
var m: Node
var ce: CurveEditor
const BEND := [0.0, 10.0, 30.0, 50.0, 40.0, 20.0, 0.0]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ks() -> Array:
	return m.S.part_keys["lowerarm_r"]


func bends() -> Array:
	return ks().map(func(k): return snappedf((k["v"] as Vector3).x, 0.001))


func reset() -> void:
	var a := []
	for i in 7:
		a.append({"t": float(i), "v": Vector3(BEND[i], 7.0, -3.0)})
	m.S.part_keys = {"lowerarm_r": a}
	ce.scene = m.S
	ce.picked = [[0, 2], [0, 3], [0, 4]]


## run tool f, check the three middle bends against want; everything else unchanged; one undo; undo exact
func check(tool: String, f: float, want: Array, label: String) -> void:
	reset()
	var before := JSON.stringify(PartKeys.to_file(m.S.part_keys))
	var u0: int = m.undo.size()
	var r: Dictionary = ce.shape(tool, f)
	var b := bends()
	var good := true
	for k in 3:
		good = good and absf(float(b[2 + k]) - float(want[k])) < 0.01
	var rest := float(b[0]) == 0.0 and float(b[1]) == 10.0 and float(b[5]) == 20.0 and float(b[6]) == 0.0
	var other := true
	for i in 7:
		var v: Vector3 = ks()[i]["v"]
		other = other and v.y == 7.0 and v.z == -3.0 and float(ks()[i]["t"]) == float(i)
	var one: bool = m.undo.size() == u0 + 1
	m._undo()
	var back := JSON.stringify(PartKeys.to_file(m.S.part_keys)) == before
	ok(good and rest and other and one and back, "%s %s f %+.1f: %s (want %s); the rest untouched %s, one undo %s, Ctrl+Z exact %s" % [label, tool, f, b.slice(2, 5), want, rest and other, one, back])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var B0 := Body.new()
	B0.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B0.fk()
	var S := Scene.new()
	S.name = "zz_key_blend"
	S.add("a", B0.to_dict())
	S.add("b", B0.to_dict())
	m.S = S
	m._rebuild_cards()
	m.sel = "lowerarm_r"
	m._refresh()
	for c in m._commands():
		if c["id"] == "curve_editor":
			c["run"].call()
	await idle(3)
	ce = m.ui_curve
	ce.limit = Callable()   # the manual's numbers: no joint limits in the way (the elbow's own range is tested apart)
	check("breakdown", 0.0, [15, 15, 15], "1")
	check("breakdown", -1.0, [10, 10, 10], "1")
	check("breakdown", 1.0, [20, 20, 20], "1")
	check("blend_neighbor", 0.5, [25, 35, 30], "2")
	check("blend_neighbor", -0.5, [20, 30, 25], "2")
	check("push_pull", 0.0, [30, 35, 40], "3")
	check("push_pull", 2.0, [30, 65, 40], "3")
	check("match_slope", 1.0, [80, 60, 40], "5")
	check("match_slope", 0.5, [55, 55, 40], "5")
	check("scale_neighbor", 2.0, [50, 90, 70], "6")
	check("blend_offset", 1.0, [10, 30, 20], "7")
	check("blend_offset", -1.0, [10, 30, 20], "7")
	# 4 ease: an S from L (1 s, 10) to R (5 s, 20)
	reset()
	ce.shape("ease", 0.0)
	var e0 := bends()
	var curve := []
	for i in 41:
		var t := 1.0 + 4.0 * i / 40.0
		curve.append(PartKeys.at(ks(), t).x)
	m._undo()
	reset()
	ce.shape("ease", 1.0)
	var e1 := bends()
	m._undo()
	var mid_ok := absf(float(e0[3]) - 15.0) < 0.01
	var s_ok := float(e0[2]) < 12.5 and float(e0[4]) > 17.5   # x = 1/4 below the straight line, x = 3/4 above it
	var right_ok := float(e1[3]) > float(e0[3])
	ok(mid_ok and s_ok and right_ok, "4 ease f 0: %s (the middle 15; at 1/4 below the line's 12.5, at 3/4 above its 17.5: an S); f 1: middle %.2f > %.2f (more weight right)" % [e0.slice(2, 5), e1[3], e0[3]])
	# skipped at the end
	reset()
	ce.picked = [[0, 0]]
	var r: Dictionary = ce.shape("breakdown", 0.0)
	m._undo()
	ok(r["skipped"] == 1 and r["changed"] == 0, "a run at the start (no left neighbour): breakdown skips it and says so (%s)" % [r])
	# the menu
	reset()
	var pop := ce._shape.get_popup()
	var items := []
	for i in pop.item_count:
		items.append(pop.get_item_text(i))
	ce._factor.value = 2.0
	pop.id_pressed.emit(KeyBlend.TOOLS.find("scale_neighbor"))
	await idle(2)
	ok(items.size() == 7 and bends().slice(2, 5) == [50.0, 90.0, 70.0], "the Shape menu: %s; 'Scale from neighbour' chosen with the factor box at 2 -> %s" % [items, bends().slice(2, 5)])
	# DD2: the Mods menu on the same keys (a limits modifier = the keys' bend range 0..50 on angle 0)
	reset()
	ce.sel_ch = 0
	var before := JSON.stringify(PartKeys.to_file(m.S.part_keys))
	var u0: int = m.undo.size()
	var mp := ce._mods.get_popup()
	mp.id_pressed.emit(2)
	await idle(2)
	var md: Dictionary = (PartKeys.mods_of(ks())[0] as Dictionary).duplicate() if not PartKeys.mods_of(ks()).is_empty() else {}
	var keys_same := bends() == [0.0, 10.0, 30.0, 50.0, 40.0, 20.0, 0.0]
	ce._factor.value = 0.25
	mp.id_pressed.emit(3)
	await idle(2)
	var mix_ok := float(PartKeys.mods_of(ks())[0].get("mix", -1)) == 0.25
	var drawn_max := -INF
	var played_max := -INF
	ce._factor.value = 1.0
	mp.id_pressed.emit(3)
	await idle(2)
	m.S.part_keys["lowerarm_r"][0]["mods"][0]["max"] = 45.0
	ce.frame_all()
	await idle(2)
	for p in ce.polyline(0):
		drawn_max = maxf(drawn_max, ce.y_to_v(p.y))
	for i in 61:
		played_max = maxf(played_max, (m.S.sample(6.0 * i / 60.0)["ang"] as Dictionary)["lowerarm_r"].x)
	var steps: int = m.undo.size() - u0
	for i in steps:
		m._undo()
	await idle(2)
	ok(md.get("type") == "limits" and md.get("ch") == 0 and float(md.get("min")) == 0.0 and float(md.get("max")) == 50.0 and keys_same and mix_ok and absf(drawn_max - 45.0) < 0.6 and absf(played_max - 45.0) < 1e-3 and steps == 3 and JSON.stringify(PartKeys.to_file(m.S.part_keys)) == before,
		"DD2 Mods menu: 'Add limits' on bend -> %s..%s (the keys' range), keys untouched %s; 'Mix = factor' -> 0.25 %s; max 45: the drawn line tops at %.2f, the scene plays at most %.3f; 3 undo steps (%d) back to the bare keys" % [md.get("min"), md.get("max"), keys_same, mix_ok, drawn_max, played_max, steps])
	var bottoms := [ce._shape.position.y + ce._shape.size.y, ce._factor.position.y + ce._factor.size.y, ce._mods.position.y + ce._mods.size.y]
	var lefts_ok: bool = ce._factor.position.x >= ce._shape.position.x + ce._shape.size.x and ce._mods.position.x >= ce._factor.position.x + ce._factor.size.x
	ok(bottoms.max() <= CurveEditor.PAD_T and lefts_ok, "the header controls end at %s px (bar <= the 22 px header: none covers the plot) and do not overlap" % [bottoms])
	m.queue_free()
	print("KEY BLEND TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
