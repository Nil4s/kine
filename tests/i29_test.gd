## godot --path . -s tests/i29_test.gd     (ROADMAP I29: match the reference's timing, scripts/timing_match.gd + timing_match_ui.gd; needs a window)
## Bars, written before measuring:
##  (1) the reference = combo3 retimed by 0.8x (cards 0-3), 1.3x (4-7), 1.0x (8-11): the clip and the reference both show at least 4
##      events (peaks + valleys) and the same number; after the match EVERY event of the retimed clip is within 1 frame (1/30 s) of the
##      reference's event it was matched to, and all clip events are matched
##  (2) a reference with an EXTRA action (cards 4-5 played twice): at least one reference event is left out, all the left-out ones lie
##      inside the extra stretch, every clip event is matched, and each lands within 1 frame of its partner
##  (3) poses byte-equal: every card's "pose" is identical after the retime
##  (4) the JSON of the open scene is byte-identical after Preview (nothing is written until Accept)
##  (5) Accept is ONE undo step; Ctrl+Z restores the scene JSON byte for byte
##  (6) PLACEMENT: the overlay sits inside the window, and in the captured image its rectangle holds the three curve colours (grey, amber,
##      blue) in that order of drawing; the picture is saved and looked at
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i29.png"
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


func scaled(S: Scene, groups: Array) -> Scene:
	var R := S.clone()
	for i in R.cards.size():
		var f := 1.0
		for g in groups:
			if i >= g[0] and i <= g[1]:
				f = g[2]
		if i > 0:
			R.cards[i]["move"] = snappedf(float(R.cards[i]["move"]) * f, 0.001)
		R.cards[i]["hold"] = snappedf(float(R.cards[i]["hold"]) * f, 0.001)
	return R


func poses(S: Scene) -> String:
	return var_to_str(S.cards.map(func(c): return c["pose"]))


## after the plan's anchors are applied to a copy: each matched pair's event time on the copy vs the reference's
func gaps(S: Scene, R: Scene, pl: Dictionary, B: Body) -> Array:
	var C := S.clone()
	TimingMatch.apply(C, pl["anc"])
	var ec2 := TimingMatch.events(TimingMatch.speed_curve(C, B))
	var er: Array = pl["er"]
	var out := []
	# the retimed clip's events are the same events in the same order (kinds and count); pair them with the reference by the alignment
	var al2 := TimingMatch.align(ec2, er)
	for p in al2["pairs"]:
		out.append(absf(float(ec2[p[0]]["t"]) - float(er[p[1]]["t"])))
	return [out, ec2.size(), al2]


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

	# (1) known per-segment factors
	var R := scaled(S, [[0, 3, 0.8], [4, 7, 1.3], [8, 11, 1.0]])
	var pl := TimingMatch.plan(S, R, B)
	var ec: Array = pl["ec"]
	var er: Array = pl["er"]
	print("     clip events %d (%.2f s), reference events %d (%.2f s)" % [ec.size(), S.length(), er.size(), R.length()])
	for e in ec:
		print("       clip %s %.3f" % [e["kind"], e["t"]])
	for e in er:
		print("       ref  %s %.3f" % [e["kind"], e["t"]])
	ok(ec.size() >= 4 and ec.size() == er.size(), "(1) %d clip events, %d reference events (>= 4 and equal)" % [ec.size(), er.size()])
	ok((pl["al"]["pairs"] as Array).size() == ec.size(), "(1) all %d clip events matched (%d pairs)" % [ec.size(), (pl["al"]["pairs"] as Array).size()])
	var g: Array = gaps(S, R, pl, B)
	var mx := 0.0
	for x in g[0]:
		mx = maxf(mx, x)
	print("     event gaps after the match (ms): ", (g[0] as Array).map(func(x): return roundi(x * 1000.0)))
	ok(not (g[0] as Array).is_empty() and mx <= FRAME + 1e-6 and (g[0] as Array).size() == ec.size(), "(1) every event within 1 frame of the reference: worst %.1f ms (frame %.1f ms)" % [mx * 1000.0, FRAME * 1000.0])
	var before_gap := 0.0
	for p in pl["al"]["pairs"]:
		before_gap = maxf(before_gap, absf(float(ec[p[0]]["t"]) - float(er[p[1]]["t"])))
	print("     worst gap BEFORE the match: %.0f ms" % (before_gap * 1000.0))
	ok(before_gap > 3.0 * mx and before_gap > 0.1, "(1) the match moved things: the worst gap fell from %.0f ms to %.1f ms" % [before_gap * 1000.0, mx * 1000.0])

	# (2) an extra action in the reference
	var cards2 := R.cards.duplicate(true)
	var extra := [cards2[4].duplicate(true), cards2[5].duplicate(true)]
	var R2 := R.clone()
	R2.cards = []
	for i in cards2.size():
		R2.cards.append(cards2[i])
		if i == 5:
			R2.cards.append_array(extra)
	var ts_r := R.times()
	var w0 := float(ts_r[5][2])
	var w1 := w0 + float(extra[0]["move"]) + float(extra[0]["hold"]) + float(extra[1]["move"]) + float(extra[1]["hold"])
	var pl2 := TimingMatch.plan(S, R2, B)
	var al: Dictionary = pl2["al"]
	var er2: Array = pl2["er"]
	var inside := true
	for j in al["skip_ref"]:
		var t := float(er2[j]["t"])
		if t < w0 - (w1 - w0) - 0.15 or t > w1 + 0.3:   # either play of the repeated pair is "the extra one"
			inside = false
	print("     extra stretch %.2f-%.2f s; reference events %d, skipped ref %s, skipped clip %s" % [w0, w1, er2.size(), al["skip_ref"], al["skip_clip"]])
	ok((al["skip_ref"] as Array).size() >= 1 and inside, "(2) %d reference event(s) left out, all inside the extra stretch" % (al["skip_ref"] as Array).size())
	ok((al["skip_clip"] as Array).is_empty(), "(2) every clip event matched (%d pairs)" % (al["pairs"] as Array).size())
	var C2 := S.clone()
	TimingMatch.apply(C2, pl2["anc"])
	var ec2b := TimingMatch.events(TimingMatch.speed_curve(C2, B))
	# the retimed clip must still show the same events in the same order: pair them by the plan's own pairs
	var mx2 := 0.0
	for p in al["pairs"]:
		if p[0] < ec2b.size():
			mx2 = maxf(mx2, absf(float(ec2b[p[0]]["t"]) - float(er2[p[1]]["t"])))
	ok(ec2b.size() == (pl2["ec"] as Array).size() and mx2 <= FRAME + 1e-6, "(2) each matched event within 1 frame of its partner: worst %.1f ms over %d (%d events after)" % [mx2 * 1000.0, (al["pairs"] as Array).size(), ec2b.size()])
	print("     anchors ", (pl2["anc"] as Array).map(func(a): return [snappedf(a[0], 0.001), snappedf(a[1], 0.001)]))
	print("     after clip events ", ec2b.map(func(e): return "%s%.2f" % [e["kind"], e["t"]]))
	print("     ref events ", er2.map(func(e): return "%s%.2f" % [e["kind"], e["t"]]))
	print("     skipped ref times: ", (al["skip_ref"] as Array).map(func(j): return snappedf(float(er2[j]["t"]), 0.001)))

	# (3) poses byte-equal
	var P0 := poses(S)
	var C3 := S.clone()
	TimingMatch.apply(C3, pl["anc"])
	ok(poses(C3) == P0, "(3) every card's pose is byte-identical after the retime (%d cards)" % C3.cards.size())

	# (4)-(5) through the panel
	var json0 := JSON.stringify(S.to_dict(B, false))
	m.tm_ui.show()
	await idle()
	m.tm_ui.set_reference(R, "synthetic")
	ok(m.tm_ui.preview(), "(4) Preview ran")
	await idle(3)
	ok(JSON.stringify(m.S.to_dict(B, false)) == json0, "(4) the scene JSON is byte-identical after Preview")
	var n_undo: int = m.undo.size()

	# (6) placement + picture (before Accept: the overlay shows grey, amber and blue)
	var ov: Control = m.ui_find_list.find_child("tm_overlay", true, false)
	await idle(3)
	var img: Image = root.get_texture().get_image()
	var rect: Rect2 = ov.get_global_rect()
	var win := Rect2(Vector2.ZERO, Vector2(img.get_size()))
	ok(win.encloses(rect) and rect.size.x > 200.0 and rect.size.y > 100.0, "(6) the overlay is inside the window: %s of %s" % [rect, win])
	var cols := {"grey": Tok.dim(0.55), "amber": Tok.c("onion_past"), "blue": Tok.c("pick_sel")}
	var found := {}
	for k in cols:
		found[k] = 0
	for y in range(int(rect.position.y), int(rect.end.y)):
		for x in range(int(rect.position.x), int(rect.end.x)):
			var px := img.get_pixel(x, y)
			for k in cols:
				var c: Color = cols[k]
				if absf(px.r - c.r) < 0.06 and absf(px.g - c.g) < 0.06 and absf(px.b - c.b) < 0.06:
					found[k] += 1
	print("     curve pixels in the overlay: ", found)
	ok(found["grey"] > 40 and found["amber"] > 40 and found["blue"] > 40, "(6) the overlay shows all three curves (grey, amber, blue pixels > 40 each)")
	img.save_png(SHOT)

	m.tm_ui.accept()
	await idle(3)
	ok(m.undo.size() == n_undo + 1, "(5) Accept is one undo step (%d -> %d)" % [n_undo, m.undo.size()])
	ok(poses(m.S) == P0, "(3) poses byte-identical in the open scene after Accept")
	var post := TimingMatch.events(TimingMatch.speed_curve(m.S, B))
	var al3 := TimingMatch.align(post, er)
	var mx3 := 0.0
	for p in al3["pairs"]:
		mx3 = maxf(mx3, absf(float(post[p[0]]["t"]) - float(er[p[1]]["t"])))
	ok((al3["pairs"] as Array).size() == post.size() and mx3 <= FRAME + 1e-6, "(1) the open scene after Accept: every event within 1 frame, worst %.1f ms" % (mx3 * 1000.0))
	ok(JSON.stringify(m.S.to_dict(B, false)) != json0, "(5) the scene changed on Accept")
	m._undo()
	await idle(2)
	ok(JSON.stringify(m.S.to_dict(B, false)) == json0, "(5) Ctrl+Z restores the scene JSON byte for byte")

	print("I29 %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
