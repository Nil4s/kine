## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/actors_hit_test.gd     (round 50, GATES TC5; a window)
## THE DUMMY'S CHECK BETWEEN TWO FIGHTERS, ON THE DUMMY'S WORKER. With 2+ fighters main measures who hits whom over
## the whole scene (Dummy.fighter_hits: Body.cross_contacts every frame at the scene's fps, weapons included, the onset
## bisected) in the same job as the dummy's (_dm_start / _dm_poll), and shows it where the dummy's report is shown (the
## browser's dummy row, a row per contact; the red dot and tag in the view). The strike scene is built HERE: the hero
## plays combo3 (opened read only: nothing is written to scenes/), fighter 2 stands still (poses/stand.json) facing
## him at a known xf, or holds a forearm in the bat's path. Bars, written before measuring:
##   1 GROUND TRUTH: a brute-force sweep in this test (every 1/240 s, Body.cross_contacts on posed copies) gives the
##     first contact's time and zone; the app's first row has the same zone and kind, and a time within 1 frame at the
##     scene's fps. That contact is the WEAPON's ("hit": the bat is in cross_contacts). The view's tag and dot show it
##     at that time, and the browser row lists every contact.
##   2 NO TOUCH / BLOCK: fighter 2 moved 3 m further: no contact reported (and the sweep agrees). A forearm put in the
##     bat's path: the first row is that arm (ARMS), the sweep's first contact, before any torso / head row.
##   3 UI NEVER BLOCKED: dummy_async's bar is a card add on the main thread under 300 ms where the synchronous work took
##     1400 ms (0.214 of it). Raw ms are not load-proof (drag_speed_test RATIO_BAR), so here: the same measurement (a
##     card add while the check is wanted) and the longest main-thread frame while the job runs, each as a ratio to the
##     synchronous check timed beside it on the main thread (the yardstick): both <= 0.214.
##   4 ONE FIGHTER UNCHANGED: the dummy's report (text and landed scene) at 4 ranges equals the synchronous
##     _dummy_measure, and equals what the build before TC5 printed (hashes recorded from HEAD b1eb082 by
##     tests/zz_tc5_base.gd, checked while combo3.json is the file they were taken on); after fighter 2 is removed the
##     dummy is back and its report is the same again.
##   5 EDITS INVALIDATE: a card added after a report: at once no rows and "measuring" (the old report is not shown);
##     what lands is the synchronous check of the edited scene (its first contact later by the added card's time), and
##     two quick edits land once.
extends SceneTree

var fails := 0
var m: Node
const RATIO_BAR := 300.0 / 1400.0   # dummy_async: its 300 ms bar over the 1400 ms the synchronous work took
const D0 := 1.2                     # fighter 2 this far in front (the dummy at 1.2 m takes combo3's swing on the CHEST)
## tests/zz_tc5_base.gd on HEAD b1eb082 (before TC5): sha256(ui_dummy.text + "|" + SL cards) at 1.6 / 1.2 / 1.0 / 0.8 m
const BASE := {1.6: "b8d94522690182ca", 1.2: "7ff6a91bca3f3fe2", 1.0: "5320ba210c53d737", 0.8: "47c33a56e8225aa5"}
const COMBO3_SHA := "31cbcf4d17c55edf1b1dda70d3aa48091d5eb6872cc667e12b9a1e34518e03e8"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


## fighter 2's scene: the one pose held (two cards: the scene check wants 2)
func still(pose: Dictionary) -> Scene:
	var s := Scene.new()
	s.from_dict({"scene": "zz_still", "fps": 30, "cards": [{"name": "a", "pose": pose, "move": -1.0, "hold": 2.0},
		{"name": "b", "pose": pose, "move": 0.5, "hold": 3.0}]})
	return s


func stand_pose() -> Dictionary:
	var b := body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b.to_dict()


## THE GROUND TRUTH: the first 1/240 s tick at which the two posed copies touch: [t, zone, kind, row] or [] for never
func truth(hs: Scene, os: Scene, xf: Transform3D) -> Array:
	var a := hs.clone()
	var o := os.clone()
	var ba := body()
	var bo := body()
	var n := int(ceil(maxf(a.length(), o.length()) * 240.0))
	for i in n + 1:
		var t := i / 240.0
		a.apply(ba, t)
		o.apply(bo, t)
		var cs: Array = ba.cross_contacts(bo, xf)
		if not cs.is_empty():
			var c: Array = cs[0]
			var zone := ""
			match c[3]:
				"struck": zone = Body.cross_zone(c[0])
				"clash": zone = "WEAPON"
				_: zone = Body.cross_zone(c[1])
			return [t, zone, c[3], c]
	return []


func f2() -> Dictionary:
	return m.actors_rt[1]


func xf2() -> Transform3D:
	return m.actors_rt[1]["xf"]


## the app's report as it would be measured now, synchronously (the job's own function, on this thread)
func sync_now() -> Dictionary:
	var hs: Scene = (m.actors_rt[0]["S"] as Scene).clone()
	hs.actors = []
	return m._fighters_measure(hs, [{"name": f2()["name"], "S": (f2()["S"] as Scene).clone(), "xf": xf2()}])


func dummy_row() -> TreeItem:
	var it: TreeItem = m.ui_browser.get_root().get_first_child()
	while it != null:
		if it.get_text(0).begins_with("Hits:") or it.get_text(0).begins_with("Target dummy"):
			return it
		it = it.get_next()
	return null


func one_fighter_same(tag: String) -> void:
	var bad := []
	var base_ok: bool = FileAccess.get_sha256("res://scenes/combo3.json") == COMBO3_SHA
	for d in [1.6, 1.2, 1.0, 0.8]:
		m.T.place(d)
		m._dummy_hits()
		await m.dummy_settle()
		var want: Dictionary = m._dummy_measure(m.S.clone(), m.T.dist, m.T.yaw, m.solid)
		var same: bool = m.ui_dummy.text == want["txt"] and (m.SL == null) == (want["SL"] == null) and (m.SL == null or JSON.stringify(m.SL.cards) == JSON.stringify(want["SL"].cards))
		var h: String = (m.ui_dummy.text + "|" + (JSON.stringify(m.SL.cards) if m.SL != null else "null")).sha256_text().left(16)
		if not same or (base_ok and h != BASE[d]):
			bad.append("%.1f m: sync %s, hash %s vs %s" % [d, same, h, BASE[d]])
	ok(bad.is_empty(), "4 %s: the dummy's report at 1.6 / 1.2 / 1.0 / 0.8 m == the synchronous _dummy_measure, and %s %s" % [tag,
		"== the pre-TC5 build's hashes" if base_ok else "(combo3.json changed since the hashes were taken: hash check skipped)", bad])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._load_scene("res://scenes/combo3.json")   # read only
	m._rebuild_cards()
	m.dummy_on = true
	m.solid = true
	await idle()

	# 4 (first half): one fighter, before any second one exists
	await one_fighter_same("one fighter")

	# the second fighter: standing still, facing the hero, D0 in front
	var stand := stand_pose()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, D0], "yaw": 180.0}, "scene": still(stand)})
	m._actors_sync()
	m._refresh()
	ok(m._fighters_on() and not m.dummy_on and m._dm_job.size() > 0, "two fighters: the dummy put away, the fighters' check started on the dummy's job (%s)" % m.ui_dummy.text)
	await m.dummy_settle()
	var hs: Scene = m.actors_rt[0]["S"]
	var fps: int = hs.fps

	# 1 ground truth
	var tr := truth(hs, f2()["S"], xf2())
	var rows: Array = m.fighter_hits
	var first: Dictionary = rows[0] if not rows.is_empty() else {}
	var dt := absf(float(first.get("t", INF)) - float(tr[0] if not tr.is_empty() else -INF))
	ok(not tr.is_empty() and not first.is_empty() and first["zone"] == tr[1] and first["kind"] == tr[2] and dt <= 1.0 / fps,
		"1 still fighter at %.1f m: the sweep's first contact %.4f s %s %s (%s on %s); the app's %.4f s %s %s (%s on %s, %.1f m/s, %.1f cm deep): %.4f s apart (bar 1 frame = %.4f s)" % [
		D0, tr[0] if not tr.is_empty() else -1.0, tr[1] if not tr.is_empty() else "-", tr[2] if not tr.is_empty() else "-",
		tr[3][0] if not tr.is_empty() else "-", tr[3][1] if not tr.is_empty() else "-",
		first.get("t", -1.0), first.get("zone", "-"), first.get("kind", "-"), first.get("part", "-"), first.get("on", "-"),
		first.get("speed", 0.0), float(first.get("depth", 0.0)) * 100.0, dt, 1.0 / fps])
	ok(not first.is_empty() and first["kind"] == "hit" and Body.is_wep(first["part"]) and float(first["u"]) > 0.0,
		"1 it is the WEAPON's: %s %s, %.2f m up the bat" % [first.get("kind", "-"), first.get("part", "-"), first.get("u", -1.0)])
	print("     the report:\n       " + m.ui_dummy.text.replace("\n", "\n       "))
	ok(JSON.stringify(m.ui_dummy.text) == JSON.stringify(sync_now()["txt"]), "1 what landed == the synchronous check (the job's own function on this thread)")
	await idle()
	var row := dummy_row()
	ok(row != null and row.get_text(0) == "Hits: " + m.ui_dummy.text.get_slice("\n", 0) and row.get_child_count() == rows.size(),
		"1 the browser's dummy row: '%s', %d rows under it (%d contacts)" % [row.get_text(0) if row else "-", row.get_child_count() if row else -1, rows.size()])
	if not first.is_empty():
		m._goto_hit(0)   # the browser row's click: the playhead to the onset
		var at: Vector3 = first["at"]
		ok(is_equal_approx(m.playhead, float(first["t"])) and m.hit_tag.visible and m.hit_dot.visible and m.hit_tag.text.begins_with(first["zone"]) and (m.hit_dot.position as Vector3).distance_to(at) < 0.01,
			"1 in the view at %.3f s: the tag '%s', the dot %.1f cm from the reported contact" % [m.playhead, m.hit_tag.text, (m.hit_dot.position as Vector3).distance_to(at) * 100.0])
		m.playhead = 0.0
		m._ps().apply(m.B, 0.0)
		m._refresh()
		ok(not m.hit_tag.visible, "1 at 0 s (apart): no tag")

	# 2a never touch: 3 m further
	m.actor_place(1, Vector2(0.0, D0 + 3.0), 180.0)
	ok(m.fighter_hits.is_empty() and "measuring" in m.ui_dummy.text, "2 moved: the report cleared at once ('%s')" % m.ui_dummy.text)
	await m.dummy_settle()
	var tr_far := truth(hs, f2()["S"], xf2())
	ok(m.fighter_hits.is_empty() and "never touch" in m.ui_dummy.text and tr_far.is_empty(), "2 fighter 2 at %.1f m: '%s'; the sweep: %s" % [D0 + 3.0, m.ui_dummy.text, "no contact" if tr_far.is_empty() else str(tr_far)])

	# 2b block: fighter 2 back, a forearm in the bat's path: the hand put where the striking spot was ~15 cm before it landed
	m.actor_place(1, Vector2(0.0, D0), 180.0)
	await m.dummy_settle()
	var hb := body()
	var hcl: Scene = hs.clone()
	var t_hit := float(first.get("t", 0.0))
	var u_hit := float(first.get("u", 0.0))
	var lead: float = clampf(0.15 / maxf(float(first.get("speed", 10.0)), 1.0), 0.004, 0.05)
	hcl.apply(hb, t_hit - lead)
	var p_before: Vector3 = hb.wep_point(u_hit)
	var bb := body()
	bb.from_dict(stand)
	var tgt: Vector3 = xf2().affine_inverse() * p_before   # in fighter 2's own space
	var side := "_l" if (bb.P["upperarm_l"] as Vector3).distance_to(tgt) < (bb.P["upperarm_r"] as Vector3).distance_to(tgt) else "_r"
	var miss := bb.reach("hand" + side, tgt)
	var block := bb.to_dict()
	var hero_S: Scene = m.actors_rt[0]["S"]
	hero_S.actors[0]["scene"] = still(block)
	m._actors_build(m.actors_rt[0]["B"], hero_S)
	m._dummy_hits()
	await m.dummy_settle()
	var tr_b := truth(hs, f2()["S"], xf2())
	var brows: Array = m.fighter_hits
	var bfirst: Dictionary = brows[0] if not brows.is_empty() else {}
	var torso_t := INF
	for h in brows:
		if h["zone"] in ["HEAD", "CHEST", "BELLY", "HIPS"]:
			torso_t = minf(torso_t, float(h["t"]))
	ok(not bfirst.is_empty() and bfirst["zone"] == "ARMS" and not tr_b.is_empty() and tr_b[1] == "ARMS" and absf(float(bfirst["t"]) - float(tr_b[0])) <= 1.0 / fps and float(bfirst["t"]) < torso_t,
		"2 block (hand%s put %.1f cm from the bat's spot %.3f s before it landed): first %.4f s %s %s (%s on %s); the sweep %s; the first torso/head row %s" % [
		side, miss * 100.0, lead, bfirst.get("t", -1.0), bfirst.get("zone", "-"), bfirst.get("kind", "-"), bfirst.get("part", "-"), bfirst.get("on", "-"),
		("%.4f s %s %s" % [tr_b[0], tr_b[1], tr_b[2]]) if not tr_b.is_empty() else "none", ("%.4f s" % torso_t) if torso_t < INF else "none"])
	print("     the block report:\n       " + m.ui_dummy.text.replace("\n", "\n       "))

	# back to the still fighter for 3 and 5
	hero_S.actors[0]["scene"] = still(stand)
	m._actors_build(m.actors_rt[0]["B"], hero_S)
	m._dummy_hits()
	await m.dummy_settle()

	# 5 edits invalidate
	var old_first := float(m.fighter_hits[0]["t"]) if not m.fighter_hits.is_empty() else -1.0
	var old_txt: String = m.ui_dummy.text
	m._card_pick(0)
	await m.dummy_settle()
	m._card_add()   # a copy of the ready pose after card 1: everything after it later
	var cleared: bool = m.fighter_hits.is_empty() and "measuring" in m.ui_dummy.text
	await idle()
	var r5 := dummy_row()
	var stale_rows := r5.get_child_count() if r5 != null and not m._dm_job.is_empty() else 0
	await m.dummy_settle()
	var want5 := sync_now()
	var new_first := float(m.fighter_hits[0]["t"]) if not m.fighter_hits.is_empty() else -1.0
	var shift := new_first - old_first
	ok(cleared and stale_rows == 0 and m.ui_dummy.text == want5["txt"] and m.ui_dummy.text != old_txt and new_first > old_first,
		"5 a card added: at once %s; rows while measuring %d; landed == the synchronous check of the edited scene; first contact %.3f -> %.3f s (+%.3f)" % [
		"cleared + 'measuring'" if cleared else "NOT cleared ('%s')" % m.ui_dummy.text.get_slice("\n", 0), stale_rows, old_first, new_first, shift])
	var lands := 0
	var landed_ok := true
	m._card_pick(2)
	m._card_add()
	m._card_pick(3)
	m._card_add()
	var last_txt: String = m.ui_dummy.text
	while not m._dm_job.is_empty():
		await process_frame
		m._dm_poll()
		if m.ui_dummy.text != last_txt:
			lands += 1
			last_txt = m.ui_dummy.text
	ok(lands == 1 and m.ui_dummy.text == sync_now()["txt"], "5 two quick edits: the text changed %d time(s) after them, to the check of the scene after both" % lands)

	# 3 UI never blocked: a bigger scene (30 cards: combo3's, repeated, as dummy_async), the yardstick beside each run
	var base: Array = hs.cards.duplicate(true)
	while hs.cards.size() < 30:
		hs.cards.append(base[hs.cards.size() % base.size()].duplicate(true))
	m._dummy_hits()
	await m.dummy_settle()
	var worst_add := 0.0
	var worst_frame := 0.0
	var yard := INF
	var raw := []
	# the first run of this bar saw a 1.8 s frame in 2 of 3 runs: the 15 s AUTOSAVE (its own main-thread work, not this
	# check: timed here). It is held off while the frames are timed, so the bar reads the check alone
	m._as_last = ""
	var a0 := Time.get_ticks_usec()
	var saved: bool = m.autosave_now()
	var as_ms := (Time.get_ticks_usec() - a0) / 1000.0
	print("     (not the check) the 15 s autosave of this 30-card two-fighter scene: %.0f ms on the main thread (wrote: %s)" % [as_ms, saved])
	for rep in 3:
		m._as_wait = -1000.0
		var y0 := Time.get_ticks_usec()
		var _y := sync_now()
		var ys := (Time.get_ticks_usec() - y0) / 1000.0
		yard = minf(yard, ys)
		m._card_pick(4 + rep)
		await m.dummy_settle()
		var t0 := Time.get_ticks_usec()
		m._card_add()
		var add_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var longest := 0.0
		var nf := 0
		var tl := Time.get_ticks_usec()
		var j0 := Time.get_ticks_msec()
		while not m._dm_job.is_empty():
			await process_frame
			m._dm_poll()
			var now := Time.get_ticks_usec()
			longest = maxf(longest, (now - tl) / 1000.0)
			tl = now
			nf += 1
		var job_ms := Time.get_ticks_msec() - j0
		worst_add = maxf(worst_add, add_ms / ys)
		worst_frame = maxf(worst_frame, longest / ys)
		raw.append("yardstick %.0f ms, add %.1f ms, job %d ms over %d frames, longest frame %.1f ms" % [ys, add_ms, job_ms, nf, longest])
	m._as_wait = 0.0
	ok(worst_add <= RATIO_BAR and worst_frame <= RATIO_BAR, "3 UI never blocked (30 cards, 3 runs): worst card add %.3f x the synchronous check, worst frame while the job ran %.3f x (bar %.3f, dummy_async's 300 / 1400): %s" % [worst_add, worst_frame, RATIO_BAR, raw])

	# 4 (second half): fighter 2 removed: the dummy back, its report as before
	m._card_pick(0)
	m._actor_next()
	m._actor_remove()
	await idle()
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.dummy_on = true
	m.solid = true
	await idle()
	ok(not m._fighters_on() and m.dummy_on and not m.ui_dummy.text.contains("fighters"), "4 fighter 2 removed: one fighter, the dummy on ('%s')" % m.ui_dummy.text.get_slice("\n", 0))
	await one_fighter_same("after two fighters")

	print("ACTORS HIT: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
