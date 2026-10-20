## godot --path . -s tests/i15_test.gd     (ROADMAP I15: fight to the beat, scripts/beat_fight.gd + beat_fight_ui.gd; needs a window)
## Bars, written before measuring (a synthetic 120 bpm track: a beat every 0.5 s from 0, a downbeat every 4th; combo3):
##  (1) every beat: each FITTED contact arrives within 1 frame (1/30 s) of a beat; at least 2 of combo3's 3 contacts are fitted
##  (2) every strike move stays inside the timing coach's range for that strike (strike_range of the new scene) or is unchanged
##  (3) a contact whose nearest beat lies 50 ms beyond the reach is FLAGGED (reason names the recorded limit), its cards are
##      untouched and its strike move did not go under the coach's lowest time
##  (4) off-beat: each fitted contact lands half way between two beats, within 1 frame
##  (5) downbeats only: each fitted contact lands on a multiple of 2.0 s (every 4th beat); every 2nd beat: on a multiple of 1.0 s
##  (6) Preview plays to its end and the scene JSON is byte-identical before and after
##  (7) Accept is ONE undo step; Ctrl+Z restores the cards and the scene JSON exactly
##  (8) placement: the timeline holds one mark per contact (fitted and flagged) at an x inside the track, and the beat ticks
extends SceneTree

const FRAME := 1.0 / 30.0
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func beats120(n := 40) -> Array:
	var out := []
	for k in n:
		out.append({"t": 0.5 * k, "down": k % 4 == 0})
	return out


func dist_to(ts: Array, t: float) -> float:
	var best := INF
	for b in ts:
		best = minf(best, absf(float(b) - t))
	return best


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var B: Body = m.B
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	var S: Scene = m.S
	S.beats_audio = beats120()
	var beat_t := []
	for b in S.beats_audio:
		beat_t.append(float(b["t"]))
	var half_t := []
	for k in beat_t.size() - 1:
		half_t.append((float(beat_t[k]) + float(beat_t[k + 1])) * 0.5)
	var cs := BeatFight.contacts(S)
	print("     contacts (cards): ", cs, "  arrivals: ", cs.map(func(i): return snappedf(float(S.times()[i][1]), 0.001)))
	var orig_moves := []
	for i in S.cards.size():
		orig_moves.append(S.move_time(i))

	# (1) every beat
	var t1: Scene = S.clone()
	var r1 := BeatFight.fit(t1, B, S.beats_audio, 0.0, "every", false)
	print("     ", r1["msg"])
	for f in r1["fits"]:
		print("       card %d %.3f -> %.3f s (beat %.2f)  %s" % [int(f["card"]) + 1, f["from"], f["to"], f["beat"], f["changes"]])
	for f in r1["flags"]:
		print("       FLAG ", f["why"])
	var worst := 0.0
	for f in r1["fits"]:
		worst = maxf(worst, dist_to(beat_t, float(t1.times()[int(f["card"])][1])))
	ok(r1["fits"].size() >= 2 and worst <= FRAME, "(1) %d of %d contacts fitted, the worst %.1f ms from a beat (<= %.1f ms)" % [r1["fits"].size(), cs.size(), worst * 1000.0, FRAME * 1000.0])

	# (2) the strike moves stay in the coach's range
	var bad := 0
	for i in cs:
		var rg := BeatFight.strike_range(t1, B, i)
		var mv := t1.move_time(i)
		var inside: bool = mv >= float(rg[0]) - 1e-3 and mv <= float(rg[1]) + 1e-3
		var same: bool = absf(mv - float(orig_moves[i])) < 1e-6
		print("       strike card %d: move %.3f s (was %.3f), coach range %.3f - %.3f s" % [i + 1, mv, orig_moves[i], rg[0], rg[1]])
		if not (inside or same):
			bad += 1
	ok(bad == 0, "(2) every strike move is inside the coach's range or unchanged (%d outside)" % bad)

	# (3) a contact out of reach is flagged, not forced
	var c0: int = cs[0]
	var rc := BeatFight.reach(S, B, c0, 0, 0.0)
	var arr0 := float(S.times()[c0][1])
	var far := [{"t": arr0 - float(rc["early"]) - 0.05, "down": true}]
	var t3: Scene = S.clone()
	var r3 := BeatFight.fit(t3, B, far, 0.0, "every", false)
	var flagged := (r3["flags"] as Array).filter(func(f): return int(f["card"]) == c0)
	var untouched := true
	for i in range(0, c0 + 1):
		untouched = untouched and absf(t3.move_time(i) - float(orig_moves[i])) < 1e-9
	print("       reach of card %d: earlier %.0f ms, later %.0f ms; beat put %.0f ms earlier than the reach; reason: %s" % [c0 + 1, rc["early"] * 1000.0, rc["late"] * 1000.0, (arr0 - float(far[0]["t"])) * 1000.0, flagged[0]["why"] if flagged.size() > 0 else "-"])
	ok(flagged.size() == 1 and String(flagged[0]["why"]).contains("recorded punch") and untouched and t3.move_time(c0) >= float(rc["lo"]) - 1e-6,
		"(3) the contact is flagged with the limit named, its cards untouched, the strike not below %.3f s" % float(rc["lo"]))

	# (4) off-beat
	var t4: Scene = S.clone()
	var r4 := BeatFight.fit(t4, B, S.beats_audio, 0.0, "every", true)
	var worst4 := 0.0
	for f in r4["fits"]:
		worst4 = maxf(worst4, dist_to(half_t, float(t4.times()[int(f["card"])][1])))
	ok(r4["fits"].size() >= 2 and worst4 <= FRAME, "(4) off-beat: %d contacts, the worst %.1f ms from a half-way point (<= %.1f ms)" % [r4["fits"].size(), worst4 * 1000.0, FRAME * 1000.0])

	# (5) downbeats / every 2nd beat
	var t5: Scene = S.clone()
	var r5 := BeatFight.fit(t5, B, S.beats_audio, 0.0, "down", false)
	var w5 := 0.0
	for f in r5["fits"]:
		var a := float(t5.times()[int(f["card"])][1])
		w5 = maxf(w5, absf(a - 2.0 * roundf(a / 2.0)))
	print("     downbeats: ", r5["msg"], "  every 2nd: ", BeatFight.fit(S.clone(), B, S.beats_audio, 0.0, "every2", false)["msg"])
	var t6: Scene = S.clone()
	var r6 := BeatFight.fit(t6, B, S.beats_audio, 0.0, "every2", false)
	var w6 := 0.0
	for f in r6["fits"]:
		var a := float(t6.times()[int(f["card"])][1])
		w6 = maxf(w6, absf(a - 1.0 * roundf(a / 1.0)))
	ok(w5 <= FRAME and w6 <= FRAME and (r5["fits"].size() + r5["flags"].size()) == cs.size(), "(5) downbeats %d fitted/%d flagged worst %.1f ms off a bar line; every 2nd beat %d fitted worst %.1f ms off a whole second" % [r5["fits"].size(), r5["flags"].size(), w5 * 1000.0, r6["fits"].size(), w6 * 1000.0])

	# panel
	m.bf_ui.mode = "every"
	m.bf_ui.offbeat = false
	m.bf_ui.show()
	await idle()
	var before := JSON.stringify(S.to_dict(B, false))
	var cards0 := JSON.stringify(S.cards)
	ok(m.bf_ui.res.get("ok", false) and m.ui_find.visible and m.ui_find_list.find_child("bf_accept", true, false) != null, "panel: shown with Preview and Accept")

	# (6) preview
	m.bf_ui.preview()
	var ticks := 0
	while m.bf_ui.pv != null and ticks < 900:
		await process_frame
		ticks += 1
	ok(m.bf_ui.pv == null and ticks > 5 and JSON.stringify(S.to_dict(B, false)) == before and JSON.stringify(S.cards) == cards0, "(6) the preview played %d frames; the scene JSON is byte-identical" % ticks)

	# (8) placement + screenshot: the grid that flags one contact if any
	var tl = m.ui_timeline
	# a break in the music (no beats from 0.6 to 1.4 s): the first contact has nothing within reach and is flagged
	var full: Array = S.beats_audio.duplicate(true)
	S.beats_audio = full.filter(func(b): return float(b["t"]) < 0.6 or float(b["t"]) > 1.4)
	m.bf_ui.set_grid("every", false)
	await idle(4)
	var nmarks: int = tl.bf.size()
	var inside_x := true
	for c in tl.bf:
		var x: float = tl.x_of(float(c["t"]))
		inside_x = inside_x and x >= 0.0 and x <= tl.size.x
	var nflag := 0
	for c in tl.bf:
		if not c["ok"]:
			nflag += 1
	ok(nmarks == cs.size() and inside_x and tl.bf_grid.size() > 3, "(8) the timeline marks %d contacts (%d flagged) inside the track, with %d beat ticks (mode %s)" % [nmarks, nflag, tl.bf_grid.size(), m.bf_ui.mode])
	ok(nflag == 1, "(8) exactly the contact beside the break is flagged (%d)" % nflag)
	m.playhead = 0.0
	await idle(3)
	root.get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i15.png")

	# (7) accept: one undo step, exact undo
	S.beats_audio = full
	m.bf_ui.set_grid("every", false)
	var u0: int = m.undo.size()
	m.bf_ui.accept()
	await idle()
	var moved := JSON.stringify(m.S.cards) != cards0
	var wm := 0.0
	for f in m.bf_ui.res["fits"]:
		wm = maxf(wm, dist_to(beat_t, float(m.S.times()[int(f["card"])][1])))
	ok(m.undo.size() == u0 + 1 and moved and wm <= FRAME, "(7) Accept is one undo step (%d -> %d), the scene changed, contacts %.1f ms from the beat" % [u0, m.undo.size(), wm * 1000.0])
	m._undo()
	await idle()
	ok(JSON.stringify(m.S.cards) == cards0 and JSON.stringify(m.S.to_dict(m.B, false)) == before, "(7) Ctrl+Z: cards and scene JSON exact")

	print("I15 FIGHT TO THE BEAT %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	quit(1 if fails > 0 else 0)
