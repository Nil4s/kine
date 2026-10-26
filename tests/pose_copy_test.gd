## godot --headless --path . -s tests/pose_copy_test.gd     (ROADMAP 53: Pose: copy to the other fighter)
## Bars, written before measuring. combo3 is opened read only; fighter 2 is made by Actor: add a second fighter, then
## scaled to a 1.9 m stature (the hero is combo3's own). Nothing is written to scenes/.
##   1 COPY ANGLES: at a card's arrival, every joint rotation of fighter 2 after "Pose: copy to the other fighter" equals the
##     hero's within 0.01 deg (the largest of the 3 angles over every joint).
##   2 PLACE: fighter 2's world placement (its xf: where it stands) is unchanged to 1e-9. Its hips are its own (reported).
##   3 FEET: fighter 2's lowest sole is within 1 mm of the floor after the copy (|sole_low| <= 0.001 m).
##   4 MIRRORED: "copy ... mirrored" leaves fighter 2 at the app's own Body.mirror_pose of the hero's pose, every joint
##     within 0.01 deg (the mirror is computed on a fresh body by Body.mirror_pose, not by the copy code).
##   5 UNDO: one Ctrl+Z after a copy restores fighter 2's cards (JSON) and its body state() bit-identical; the undo count
##     grows by exactly 1 per copy.
##   6 CARD: at a playhead in the middle of a move, where fighter 2 has no card, the copy makes one card that arrives at the
##     playhead (its arrival within 1 ms), the card count grows by 1, the cards after it keep their arrival times (1 ms);
##     a second copy at the same playhead updates that card (no third card).
extends SceneTree

var fails := 0
var m: Node
const ORDER_TOL_DEG := 0.01


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func fresh() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


## the largest angle difference (deg) over every joint, between two bodies' ang dictionaries
func worst_ang(a: Dictionary, b: Dictionary) -> float:
	var w := 0.0
	for j in Body.ORDER:
		var dv: Vector3 = ((a[j] as Vector3) - (b[j] as Vector3)).abs()
		w = maxf(w, maxf(dv.x, maxf(dv.y, dv.z)))
	return w


func at(t: float) -> void:
	m.playhead = t
	m._ps().apply(m.B, t)   # as a scrub or play does
	m._refresh()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.playhead = 0.0
	m._refresh()
	m.undo.clear()
	m.redo.clear()
	await idle()
	m._actor_add()
	await idle()
	var f2: Dictionary = m.actors_rt[1]
	var TS: Scene = f2["S"]
	TS.body = Proportions.clean({"stature": 1.9})   # fighter 2 is taller than the hero (the hero is the file's own)
	m.actors_rt[1]["t"] = NAN

	# ---- (1) ANGLES, PLACE, FEET
	var ts: Array = m.S.times()
	var t: float = ts[2][1]
	at(t)
	var src_ang: Dictionary = m.B.ang.duplicate()
	var src_state: Dictionary = m.B.state()
	var src_off: Vector3 = m.B.offset
	var xf0: Transform3D = f2["xf"]
	var undo0: int = m.undo.size()
	var tb_before: Dictionary = (f2["B"] as Body).state()
	var cards_before := JSON.stringify(TS.cards)
	var n0 := TS.cards.size()
	m._pose_to_other(false)
	await idle()
	var TB: Body = m.actors_rt[1]["B"]
	var rot_err := worst_ang(TB.ang, src_ang)
	ok(rot_err <= ORDER_TOL_DEG, "1: fighter 2's joint rotations equal the hero's at t=%.3f s (worst %.5f deg <= %.2f)" % [t, rot_err, ORDER_TOL_DEG])
	var xf_err: float = (m.actors_rt[1]["xf"] as Transform3D).origin.distance_to(xf0.origin) + (m.actors_rt[1]["xf"] as Transform3D).basis.get_euler().distance_to(xf0.basis.get_euler())
	ok(xf_err < 1e-9 and (m.actors_rt[1]["xf"] as Transform3D) == xf0, "2: fighter 2's placement (xf) unchanged (diff %.9f)" % xf_err)
	print("     hips: hero %s, fighter 2 %s (before %s); its stature %.2f m, the hero's %.2f m" % [
		src_off, TB.offset, tb_before["offset"], float(TS.body.get("stature", 0.0)), float(m.S.body.get("stature", 1.75))])
	var sole := TB.sole_low()
	ok(absf(sole) <= 0.001, "3: fighter 2's lowest sole %.6f m from the floor (<= 0.001)" % sole)
	ok(TS.cards.size() == n0 + 1 or TS.cards.size() == n0, "5: the copy makes at most one card (%d -> %d)" % [n0, TS.cards.size()])
	ok(m.undo.size() == undo0 + 1, "5: one copy = one undo step (%d -> %d)" % [undo0, m.undo.size()])

	# ---- (5) UNDO: one step puts fighter 2 back exactly
	m._undo()
	await idle()
	at(t)
	var back_cards := JSON.stringify(TS.cards) == cards_before
	var back_body := (f2["B"] as Body).state() == tb_before
	ok(back_cards, "5: one Ctrl+Z restores fighter 2's cards (JSON equal)")
	ok(back_body, "5: and its body state() bit-identical")

	# ---- (4) MIRRORED
	m._pose_to_other(true)
	await idle()
	TB = m.actors_rt[1]["B"]
	var ref := fresh()
	ref.set_state(src_state)
	ref.mirror_pose()
	var mir_err := worst_ang(TB.ang, ref.ang)
	ok(mir_err <= ORDER_TOL_DEG, "4: mirrored copy = the app's Body.mirror_pose of the hero's pose (worst %.5f deg <= %.2f)" % [mir_err, ORDER_TOL_DEG])
	m._undo()
	await idle()
	at(t)

	# ---- (6) CARD: mid-move, fighter 2 has no card there
	var mid: float = (float(ts[2][0]) + float(ts[2][1])) * 0.5
	at(mid)
	var n1 := TS.cards.size()
	var tsf: Array = TS.times()
	var arr_before: Array = []
	for i in TS.cards.size():
		arr_before.append(float(tsf[i][1]))
	m._pose_to_other(false)
	await idle()
	var tsa: Array = TS.times()
	var made := -1
	for i in TS.cards.size():
		if absf(float(tsa[i][1]) - mid) <= 0.001:
			made = i
	ok(TS.cards.size() == n1 + 1 and made >= 0, "6: a card made at the playhead %.3f s (cards %d -> %d, arrival %s)" % [mid, n1, TS.cards.size(), str(tsa[made][1]) if made >= 0 else "none"])
	var kept := 0.0   # the cards after the new one: old index i is now i + 1
	for i in arr_before.size():
		if made >= 0 and i >= made:
			kept = maxf(kept, absf(float(tsa[i + 1][1]) - float(arr_before[i])))
	ok(made >= 0 and kept <= 0.001, "6: the cards after it keep their arrival (worst %.5f s, <= 1 ms)" % kept)
	var n2 := TS.cards.size()
	m._pose_to_other(false)
	await idle()
	ok(TS.cards.size() == n2, "6: a second copy at the same playhead updates the card (cards %d -> %d)" % [n2, TS.cards.size()])
	m._undo()
	m._undo()
	await idle()
	ok(TS.cards.size() == n1, "6: two Ctrl+Z take both copies back (cards %d)" % TS.cards.size())

	print("done: %d failure(s)" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
