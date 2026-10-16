## godot --path . -s tests/dummy_async_test.gd     (GATES U1; needs a window)
## THE DUMMY OFF THE MAIN THREAD: on a 30-card scene a card edit used to wait 1.3 s while the whole scene was sampled
## against the dummy. Now the edit only starts a job. Checked: the main thread's card add is quick; while the job runs
## the panel says "measuring" and nothing stale plays; what lands is IDENTICAL to measuring synchronously; three quick
## edits land only the last one's result.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


## the synchronous measurement of the scene as it stands now (the old path, run here on the main thread)
func sync_now() -> Dictionary:
	return m._dummy_measure(m.S.clone(), m.T.dist, m.T.yaw, m.solid)


func same(out: Dictionary) -> bool:
	if m.ui_dummy.text != out["txt"]:
		return false
	if (m.SL == null) != (out["SL"] == null):
		return false
	return m.SL == null or JSON.stringify(m.SL.cards) == JSON.stringify(out["SL"].cards)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	m._load_scene("res://scenes/combo3.json")   # read only: nothing is saved
	var base: Array = m.S.cards.duplicate(true)
	while m.S.cards.size() < 30:   # 30 cards: combo3's 12, repeated
		m.S.cards.append(base[m.S.cards.size() % base.size()].duplicate(true))
	m.dummy_on = true
	m.solid = true
	for d in [1.6, 1.4, 1.2, 1.0, 0.9, 0.8, 0.7]:   # in until the swing lands
		m.T.place(d)
		m._dummy_hits()
		await m.dummy_settle()
		if m.SL != null:
			break
	ok(m.SL != null, "30 cards, the dummy %.1f m out: the swing lands (%s)" % [m.T.dist, m.ui_dummy.text.get_slice("\n", 1)])
	ok(same(sync_now()), "what landed == the synchronous measurement (text and the landed scene, card for card)")

	# one edit: the main thread only starts the job
	m._card_pick(5)
	await m.dummy_settle()
	var t0 := Time.get_ticks_usec()
	m._card_add()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	ok(ms < 300.0, "a card add on 31 cards takes %.0f ms on the main thread (the bar: 300; it was 1400)" % ms)
	ok(m.SL == null and "measuring" in m.ui_dummy.text, "  meanwhile: 'measuring...' and no old landing plays (SL cleared; _ps() is the scene as made)")
	ok(m._ps() == m.S, "  the window plays the cards as made until the new landing is in")
	var t1 := Time.get_ticks_msec()
	await m.dummy_settle()
	print("     the job took %d ms (off the main thread)" % (Time.get_ticks_msec() - t1))
	var want := sync_now()
	ok(same(want), "  what landed == the synchronous measurement of the 31-card scene")
	ok(m._ps() == m.SL, "  and it plays (the landed copy, %.2f s)" % (m.SL.length() if m.SL != null else -1.0))

	# three quick edits: only the newest result lands
	for k in 3:
		m._card_pick(2 + k)
		m._card_add()
	var n: int = m.S.cards.size()
	var lands := 0
	var last_txt: String = m.ui_dummy.text
	while not m._dm_job.is_empty():
		await process_frame
		m._dm_poll()
		if m.ui_dummy.text != last_txt:
			lands += 1
			last_txt = m.ui_dummy.text
	ok(lands == 1, "3 quick edits -> the text changed %d time(s) after them: only the newest result landed" % lands)
	ok(same(sync_now()), "  and it is the measurement of the scene after all 3 (%d cards), not a stale one" % n)

	# the dummy off and on again: off says so at once; on measures again
	m._dummy_toggle()
	ok(m.ui_dummy.text == "dummy off" and m.SL == null, "the dummy off: 'dummy off', nothing landed")
	m._dummy_toggle()
	await m.dummy_settle()
	ok(same(sync_now()), "on again: measured again, identical")

	print("DUMMY ASYNC: %d failed" % fails)
	quit(1 if fails > 0 else 0)
