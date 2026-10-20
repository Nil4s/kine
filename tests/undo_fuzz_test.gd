## godot --path . -s tests/undo_fuzz_test.gd     (GATES O4; needs a window: the real poser UI is built)
## Seeded random runs on combo3: each step picks a random part and a random card, then runs a random EDIT: a registry
## command marked "edits", a card button (pick / update / delete / move / add), or a nudge of the part like a drag.
## Every step must push at most one undo step, and a step that pushed none must not have changed anything.
## Then undo ALL of them: after each undo the body + scene equal the state before that step (the start at the end);
## then redo all: each equals the state after its step. Runs are <= 60 steps (the stack holds 60).
extends SceneTree

const SEEDS := [1, 2, 3, 4]
const STEPS := 40

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func fp() -> String:
	# the body + what the scene IS (its cards and settings). Not S.to_dict: that POSES the body it is given (round 8:
	# the fingerprint moved with nothing done) and adds derived data (bad_frames) that re-plays the whole scene per call
	var sd := {"cards": m.S.cards, "name": m.S.name, "natural": m.S.natural, "spline": m.S.spline, "on_floor": m.S.on_floor,
		"floor_body": m.S.floor_body, "pin": m.S.pin, "fps": m.S.fps, "moving_holds": m.S.moving_holds}
	return JSON.stringify(m.B.to_dict()) + "|" + JSON.stringify(sd)


func run(seed: int, pool: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	m.playing = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._card_pick(1)
	m.undo.clear()
	m.redo.clear()
	await process_frame
	var hist := [fp()]   # hist[k] = the state after k undoable steps
	var names := []
	var silent_bad := []
	var multi := []
	for i in STEPS:
		m.sel = Body.BODY[rng.randi() % Body.BODY.size()]
		var nc: int = m.S.cards.size()
		var k := rng.randi() % (pool.size() + 6)
		var what := ""
		var f0 := fp()
		var u0: int = m.undo.size()
		if k < pool.size():
			what = pool[k]["id"]
			(pool[k]["run"] as Callable).call()
		else:
			var ci := rng.randi() % maxi(1, nc)
			match k - pool.size():
				0:
					what = "card pick %d" % ci
					m._card_pick(ci)
				1:
					what = "card update %d" % ci
					m._card_update(ci)
				2:
					if nc > 3:
						what = "card delete %d" % ci
						m._card_del(ci)
				3:
					what = "card move %d" % ci
					m._card_move(ci, 1 if rng.randf() < 0.5 else -1)
				4:
					what = "card add"
					m._card_add()
				5:
					what = "nudge %s" % m.sel
					var d := Vector3(rng.randf_range(-25, 25), rng.randf_range(-25, 25), rng.randf_range(-25, 25))
					m._do(func(): m.B.set_ang_safe(m.sel, m.B.ang[m.sel] + d))
		if m.mm_ui != null:
			m.mm_ui.halt()   # the motion matching preview is a MODE that plays the body every frame until it is toggled off (tests/motion_match_test.gd); left on it would move the body under every later step
		await process_frame
		m.playing = false
		var steps: int = m.undo.size() - u0
		if steps > 1:
			multi.append("%d %s (%d steps)" % [i, what, steps])
		if steps == 0:
			if fp() != f0:
				silent_bad.append("%d %s" % [i, what])
				hist[-1] = fp()   # carry on from here, the step is reported
			continue
		hist.append(fp())
		names.append(what)
	ok(multi.is_empty(), "seed %d: no step pushed more than one undo step %s" % [seed, multi])
	ok(silent_bad.is_empty(), "seed %d: no step changed the body/scene without an undo step %s" % [seed, silent_bad])
	var n := names.size()
	var bad_u := []
	for j in range(n - 1, -1, -1):
		m._undo()
		await process_frame
		if fp() != hist[j]:
			if bad_u.is_empty():
				var a: String = hist[j]
				var b := fp()
				var q := 0
				while q < mini(a.length(), b.length()) and a[q] == b[q]:
					q += 1
				print("     first undo miss (step %d %s) at char %d: ...%s...  vs  ...%s..." % [j, names[j], q, a.substr(maxi(0, q - 70), 100), b.substr(maxi(0, q - 70), 100)])
			bad_u.append("%d %s" % [j, names[j]])
	ok(bad_u.is_empty() and n > 10, "seed %d: %d undoable steps; undo all -> each state comes back exactly, ending at the start %s" % [seed, n, bad_u])
	var bad_r := []
	for j in n:
		m._redo()
		await process_frame
		if fp() != hist[j + 1]:
			bad_r.append("%d %s" % [j, names[j]])
	ok(bad_r.is_empty(), "seed %d: redo all -> each step's result comes back exactly %s" % [seed, bad_r])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	# the edit commands, minus the slow scene-wide passes (they are in undo_audit) and the stepped view toggle
	var pool := (m._commands() as Array).filter(func(c): return c["edits"] and not c["id"] in ["fix_moves_through_the_body"])
	print("pool: %d edit commands + 6 card/drag actions, %d steps x %d seeds" % [pool.size(), STEPS, SEEDS.size()])
	for s in SEEDS:
		await run(s, pool)
	print("UNDO FUZZ %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
