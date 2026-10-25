## godot --headless --path . -s tests/actors_main_test.gd     (round 50, GATES TC3: two characters in main, no new UI)
## main keeps B / S as THE ACTIVE actor; actors_rt holds every actor (actor 0 = the hero = the file's top level); the
## others are posed from their own scene at the playhead by _pose_others (the end of _refresh); undo steps carry the actor.
## Bars, written before measuring (combo3 is opened read only; nothing is written to scenes/):
##   1 ADD: "Actor: add a second fighter" on combo3 -> two actors, one undo step. At 5 playheads actor 1's body equals
##     Scene.apply of its own scene on a fresh body (every joint angle and the hips within 1e-6), and the hero's state()
##     is bit-identical to a one-actor session at the same playheads.
##   2 UNDO ISOLATION: turn a joint on actor 0 (written into a card, one step), switch, the same on actor 1, Ctrl+Z twice:
##     after the first actor 1 is back (state() and cards exactly) and actor 0 still edited; after the second both are
##     back exactly; at no step does either actor's body equal the OTHER's edited state (widened after the first stub
##     run to "edited or before": the stub put actor 0's BEFORE state onto actor 1, which the narrower check missed); the
##     active actor after each undo is the one that edit was on.
##   3 SAVE / RELOAD: the save dict (main._scene_dict, what Save scene writes) to user:// and opened again: two actors,
##     actor 1's xf and scene equal (TC1's round trip: to_dict equal); saved while actor 1 is active it is still the
##     hero's file; a one-actor save writes no "actors" key; dirty tracking sees the second actor.
##   4 ONE-ACTOR COST: 100 _refresh calls with one actor within 5 % of the same with the hook stubbed out (an instance
##     whose _pose_others can be stubbed; interleaved; the numbers and an A/A control printed).
##   5 CROSS CONTACT WIRED: actor 1 placed 0.2 m in front, main.actor_contacts(1) (hero vs actor 1 at its xf) has torso
##     pairs, all "touch"; at the add's 1.5 m: none (the xf is used).
extends SceneTree

var fails := 0
var m: Node
const TORSO := ["pelvis", "spine_01", "spine_02", "spine_03", "chest_wide", "hips_wide"]


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


## the worst joint-angle (deg) or hips (m) difference between two bodies
func worst(a: Body, b: Body) -> float:
	var w := (a.offset - b.offset).length()
	for j in Body.ORDER:
		var dv: Vector3 = ((a.ang[j] as Vector3) - (b.ang[j] as Vector3)).abs()
		w = maxf(w, maxf(dv.x, maxf(dv.y, dv.z)))
	return w


func open_combo() -> void:
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.playhead = 0.0
	m._refresh()
	m.undo.clear()
	m.redo.clear()
	await idle()


func at(t: float) -> void:
	m.playhead = t
	m._ps().apply(m.B, t)   # as a scrub / play does
	m._refresh()


func cards_of(sc: Scene) -> String:
	return JSON.stringify(sc.cards)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	await open_combo()
	var L: float = m.S.length()
	var T := [0.0, 0.37, L * 0.5, L * 0.81, L]

	# ---- (1) ADD
	var ref := []
	for t in T:
		at(t)
		ref.append(m.B.state())
	ok(m.actors_rt.is_empty(), "1: combo3 opened: one actor (actors_rt empty, nothing built)")
	await open_combo()
	m._actor_add()
	await idle()
	ok(m.actors_rt.size() == 2 and m.S.actors.size() == 1 and m.actor_on == 0 and m.undo.size() == 1,
		"1: add -> %d actors, S.actors %d, active %d, undo steps %d" % [m.actors_rt.size(), m.S.actors.size(), m.actor_on, m.undo.size()])
	var a1: Dictionary = m.actors_rt[1]
	ok(a1["xf"].origin.is_equal_approx(Vector3(0, 0, 1.5)) and absf(a1["xf"].basis.get_euler().y) > 3.14,
		"1: actor 1 stands 1.5 m in front, turned 180 (xf origin %s)" % a1["xf"].origin)
	var w1 := 0.0
	var hero_same := true
	var moves := 0.0
	var mirror_diff := 0.0
	var prev: Dictionary = {}
	for i in T.size():
		at(T[i])
		var R := fresh()
		(a1["S"] as Scene).apply(R, T[i])
		w1 = maxf(w1, worst(R, a1["B"]))
		if m.B.state() != ref[i]:
			hero_same = false
		mirror_diff = maxf(mirror_diff, worst(m.B, a1["B"]))
		if not prev.is_empty():
			var P := fresh()
			P.set_state(prev)
			moves = maxf(moves, worst(P, a1["B"]))
		prev = (a1["B"] as Body).state()
	print("     actor 1 vs Scene.apply of its own scene: worst %.9f (deg / m) over %d playheads; it moves between them by up to %.1f deg; differs from the hero by up to %.1f deg" % [w1, T.size(), moves, mirror_diff])
	ok(w1 <= 1e-6 and moves > 1.0, "1: actor 1's body = Scene.apply of its own scene at 5 playheads (worst %.9f <= 1e-6), and it moves (%.1f deg)" % [w1, moves])
	ok(hero_same, "1: the hero's state() bit-identical to the one-actor session at the same 5 playheads")

	# ---- (2) UNDO ISOLATION
	m.undo.clear()
	m.redo.clear()
	at(T[2])
	m._card_pick(2)
	m.playhead = T[2]
	m._refresh()
	var B0: Body = m.actors_rt[0]["B"]
	var B1: Body = m.actors_rt[1]["B"]
	var S0: Scene = m.actors_rt[0]["S"]
	var S1: Scene = m.actors_rt[1]["S"]
	var s0 := B0.state()
	var s1 := B1.state()
	var c0 := cards_of(S0)
	var c1 := cards_of(S1)
	m.sel = "lowerarm_r"
	m._do(func(): m.B.set_ang_safe("lowerarm_r", m.B.ang["lowerarm_r"] + Vector3(17.3333, 0, 0)); m.S.cards[2]["pose"] = m.B.to_dict())
	var e0 := B0.state()
	ok(e0 != s0 and cards_of(S0) != c0 and B1.state() == s1 and cards_of(S1) == c1, "2: edit on actor 0 changed actor 0 only (body and card 3)")
	m._actor_next()
	await idle()
	ok(m.actor_on == 1 and m.B == B1 and m.S == S1, "2: switched: B and S are actor 1's")
	ok(B0.state() == e0, "2: actor 0 keeps its edit after the switch (not re-posed at the same playhead)")
	m.sel = "upperarm_l"
	m._do(func(): m.B.set_ang_safe("upperarm_l", m.B.ang["upperarm_l"] + Vector3(-23.1111, 9.5, 0)); m.S.cards[2]["pose"] = m.B.to_dict())
	var e1 := B1.state()
	ok(e1 != s1 and cards_of(S1) != c1 and B0.state() == e0 and cards_of(S0) != c0, "2: edit on actor 1 changed actor 1 only")
	var crossed := false
	m._undo()
	await idle()
	crossed = crossed or B0.state() in [e1, s1] or B1.state() in [e0, s0]   # the other's edited OR original state
	ok(m.actor_on == 1 and B1.state() == s1 and cards_of(S1) == c1 and B0.state() == e0,
		"2: Ctrl+Z 1: active %d (actor 1's edit), actor 1 back exactly (state %s, cards %s), actor 0 still edited %s" % [m.actor_on, B1.state() == s1, cards_of(S1) == c1, B0.state() == e0])
	m._undo()
	await idle()
	crossed = crossed or B0.state() in [e1, s1] or B1.state() in [e0, s0]   # the other's edited OR original state
	ok(m.actor_on == 0 and B0.state() == s0 and cards_of(S0) == c0 and B1.state() == s1 and cards_of(S1) == c1,
		"2: Ctrl+Z 2: active %d (actor 0's edit), actor 0 back exactly (state %s, cards %s), actor 1 still back %s" % [m.actor_on, B0.state() == s0, cards_of(S0) == c0, B1.state() == s1 and cards_of(S1) == c1])
	ok(not crossed, "2: at no step did one actor's body hold the other's state (edited or before)")
	m._redo()
	m._redo()
	await idle()
	ok(B0.state() == e0 and B1.state() == e1 and m.actor_on == 1, "2: Ctrl+Y twice puts both edits back on their own actors (active %d)" % m.actor_on)
	m._undo()
	m._undo()
	await idle()

	# ---- (3) SAVE / RELOAD
	var path := "user://zz_actors_main_%d.json" % OS.get_process_id()
	ok(m._unsaved(), "3: with a second actor added the scene reads unsaved (dirty tracking sees it)")
	m._actor_next()   # saved from actor 1: still the hero's file
	var d: Dictionary = m._scene_dict()
	m._actor_next()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, " "))
	f.close()
	var M := fresh()
	var want_scene: Dictionary = S1.to_dict(M)
	var want_name: String = S0.name
	ok(String(d["scene"]) == want_name and d.has("actors") and d["actors"].size() == 1, "3: saved with actor 1 active: the file is the hero's ('%s') with %d actor(s)" % [d["scene"], d.get("actors", []).size()])
	m._load_scene(path)
	m._rebuild_cards()
	m._refresh()
	await idle()
	ok(m.actors_rt.size() == 2 and m.actor_on == 0, "3: reopened: %d actors, active %d" % [m.actors_rt.size(), m.actor_on])
	var xf: Dictionary = m.S.actors[0]["xf"] if m.S.actors.size() > 0 else {}
	ok(xf == {"pos": [0.0, 1.5], "yaw": 180.0}, "3: actor 1's xf round-trips: %s" % xf)
	var got_scene: Dictionary = (m.S.actors[0]["scene"] as Scene).to_dict(M) if m.S.actors.size() > 0 else {}
	ok(JSON.stringify(got_scene) == JSON.stringify(want_scene), "3: actor 1's scene round-trips (to_dict equal, %d chars)" % JSON.stringify(want_scene).length())
	ok(not m._unsaved(), "3: just opened: not unsaved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await open_combo()
	var d1: Dictionary = m._scene_dict()
	ok(not d1.has("actors"), "3: a one-actor save writes no \"actors\" key")

	# ---- (5) CROSS CONTACT
	await open_combo()
	m._actor_add()
	m.playhead = 0.0
	m._refresh()
	var far: Array = m.actor_contacts(1)
	m.actor_place(1, Vector2(0, 0.2), 180.0)
	var near: Array = m.actor_contacts(1)
	var n_torso := 0
	var all_touch := true
	var deep := 0.0
	for c in near:
		if c[0] in TORSO and c[1] in TORSO:
			n_torso += 1
			deep = maxf(deep, float(c[2]))
			all_touch = all_touch and c[3] == "touch"
	print("     at 1.5 m: %d contacts; at 0.2 m: %d contacts, %d torso pairs, deepest %.1f cm" % [far.size(), near.size(), n_torso, deep * 100.0])
	ok(far.is_empty() and n_torso > 0 and all_touch, "5: hero vs actor 1: none at 1.5 m, torso \"touch\" at 0.2 m (%d pairs, all touch %s)" % [n_torso, all_touch])

	# ---- (4) ONE-ACTOR COST (an instance whose hook can be stubbed, interleaved with the real one)
	m.queue_free()
	await idle()
	var gs := GDScript.new()
	gs.source_code = "extends \"res://scripts/main.gd\"\nvar hook_on := true\nfunc _pose_others() -> void:\n\tif hook_on:\n\t\tsuper()\n"
	gs.reload()
	m = Node3D.new()
	m.set_script(gs)
	root.add_child(m)
	await idle()
	await open_combo()
	at(T[2])
	# each refresh alternates hook on / stubbed (the order flipped every pair), so a drift of the machine lands on both;
	# compared by the MEDIAN single-refresh time (a suite run in parallel spikes single calls: means over rounds moved
	# 4.5 % with nothing changed), scaled to 100 calls; the same run with BOTH stubbed is the instrument's noise (A/A)
	var paired := func(a_on: bool) -> Array:
		var on := []
		var off := []
		for i in 1100:
			for first in ([true, false] if i % 2 == 0 else [false, true]):
				m.hook_on = a_on if first else false
				var t0 := Time.get_ticks_usec()
				m._refresh()
				(on if first else off).append(Time.get_ticks_usec() - t0)
		on.sort()
		off.sort()
		return [on[550] / 10.0, off[550] / 10.0]   # 100 calls at the median call, in ms
	var aa: Array = paired.call(false)
	var ab: Array = paired.call(true)
	m.hook_on = true
	var t1 := Time.get_ticks_usec()
	for i in 100:
		m._pose_others()
	var hook_us := float(Time.get_ticks_usec() - t1)
	var pct: float = (ab[0] / ab[1] - 1.0) * 100.0
	var pct_aa: float = (aa[0] / aa[1] - 1.0) * 100.0
	print("     100 _refresh at the median call (1100 interleaved pairs): hook on %.2f ms, stubbed %.2f ms (%+.2f %%); A/A both stubbed %.2f vs %.2f ms (%+.2f %%)" % [ab[0], ab[1], pct, aa[0], aa[1], pct_aa])
	print("     100 calls of the hook alone (one actor): %.0f us" % hook_us)
	ok(absf(pct) <= 5.0, "4: one actor: 100 refreshes %.2f ms with the hook vs %.2f ms stubbed (%+.2f %%, bar 5 %%; A/A noise %+.2f %%)" % [ab[0], ab[1], pct, pct_aa])

	print("ACTORS MAIN TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
