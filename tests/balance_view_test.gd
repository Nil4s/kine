## godot --headless --path . -s tests/balance_view_test.gd     (round 43, GATES YY1)
## LIVE BALANCE: what BalanceView draws is Balance's own reading, not a second model of it. Bars: standing, the drawn
## COM floor point equals Balance.com's (x, z) exactly and the drawn polygon is Balance.read's; GREEN. A lean whose hips
## go 34 cm forward over planted feet (balance_test's lean) passes through AMBER (inside by < 2 cm) to RED (outside);
## lifted off the floor it is GREY ("air"); the mesh has one line per polygon edge + the cross's two + the plumb line;
## off = no surface and no reading.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var V := BalanceView.new()
	get_root().add_child(V)
	if V._im == null:
		V._ready()
	V.on = true
	V.show_body(B)
	var r := Balance.read(B)
	var c := Balance.com(B)
	ok(V.last["state"] == "inside" and V.last["foot"] == Vector2(c.x, c.z), "1 standing: GREEN, the drawn COM point (%.4f, %.4f) = Balance.com's exactly; inside by %.1f cm" % [V.last["foot"].x, V.last["foot"].y, V.last["margin"] * 100.0])
	ok(V.last["poly"] == r["poly"] and (r["poly"] as PackedVector2Array).size() >= 3, "2 the drawn polygon is Balance.read's (%d points)" % (r["poly"] as PackedVector2Array).size())
	var n_poly := (r["poly"] as PackedVector2Array).size()
	var verts: int = V.verts if V._im.get_surface_count() == 2 else -1
	ok(verts == (n_poly + 3) * 2, "3 the mesh: 2 surfaces (fill + disc, lines); %d line vertices = (%d edges + 2 cross + 1 plumb) x 2" % [verts, n_poly])
	ok(V.words().begins_with("balance: inside by"), "4 the status words: '%s'" % V.words())

	# the lean: the hips 34 cm forward and 12 down over the feet planted where he stood (as balance_test)
	var keep := B.state()
	var S := Scene.new()
	S.name = "zz_lean"
	S.add("stand", B.to_dict())
	B.offset = Vector3(0.0, -0.12, 0.34)
	B.fk()
	S.add("lean", B.to_dict())
	B.set_state(keep)
	S.cards[1]["hold"] = 0.5
	S.cards[1]["plant"] = ["_l", "_r"]
	var t1: float = S.times()[1][1]
	var seen := []
	for k in 61:
		S.apply(B, t1 * k / 60.0)
		V.show_body(B)
		if seen.is_empty() or seen[-1] != V.last["state"]:
			seen.append(V.last["state"])
	ok(seen == ["inside", "edge", "outside"], "5 the lean, in order: %s (bar: inside -> edge -> outside)" % str(seen))
	ok(V.words().contains("OUTSIDE") and BalanceView.colour("outside") == BalanceView.RED, "6 leaned past the toes: RED, '%s'" % V.words())

	B.set_state(keep)
	B.offset.y += 0.3
	B.fk()
	V.show_body(B)
	ok(V.last["state"] == "air" and BalanceView.colour("air") == BalanceView.GREY, "7 lifted 30 cm: GREY, '%s'" % V.words())

	V.on = false
	V.show_body(B)
	ok(V._im.get_surface_count() == 0 and V.last.is_empty() and V.words() == "", "8 off: nothing drawn, nothing read")
	print("BALANCE VIEW TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
