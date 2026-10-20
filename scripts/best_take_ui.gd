## MY BEST TAKE panel (ROADMAP I38; the maths: scripts/best_take.gd). Kept out of main.gd like StyleUI: main makes one (main.bt_ui), lists its
## commands and ribbon buttons (CHECK > GRADE) and calls tick() each frame.
##   "Star this clip"  stars / unstars the open clip (its file path, kept in user://best_take_stars.json, never in scenes/).
##   "My best take"    the top differences of the starred clip against your other clips of its kind, in words with numbers and a bar.
##   "Make this one more like my best"  the open clip nudged toward those values on a copy: Preview plays it, Accept is ONE undo step.
class_name BestTakeUI
extends RefCounted

var m: Node
var stars_path := BestTake.STARS     # a test points this at its own file under user://
var dirs: Array = ["res://scenes/"]  # the clips compared (read only)
var star_path := ""                  # the starred clip in use ("" = the newest star)
var res: Dictionary = {}             # the last analysis
var plan: Dictionary = {}            # the last nudge: {"scene", "changes"}
var pv: Scene = null
var pv_t := 0.0
var pv_end := 0.0
var ms := 0.0


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Star this clip", "", star, "star this clip best take favourite mark my best",
		false, "star (or unstar) the open clip as one of your best takes; the star is kept on this computer, not in the scene")
	add.call("My best take", "", show, "my best take starred clip differences compare your other clips wind-up hold guard stance speed anticipation follow-through",
		false, "what your starred clip does differently from your other clips of its kind: the five biggest differences in plain words with numbers")
	add.call("Make this one more like my best", "", make_like, "make this one more like my best take nudge toward starred clip preview accept",
		false, "nudge the open clip's timing, guard height and stance toward your starred clip; Preview, then Accept (one undo step)")


func halt() -> void:
	pv = null


func starred() -> bool:
	return m.scene_path != "" and BestTake.load_stars(stars_path).has(m.scene_path)


func star() -> void:
	if m.scene_path == "":
		m._say("star needs a saved clip: save this one first (Ctrl+S), then Star this clip")
		return
	var on := BestTake.toggle(m.scene_path, stars_path)
	m._say("%s is %s as one of your best takes (kept on this computer, not in the scene)" % [m.scene_path.get_file(), "starred" if on else "no longer starred"])
	if m.ui_find.visible and m.ui_find_list.find_child("bt_title", true, false) != null:
		show()


## the star in use: the chosen one if still starred, else the newest that is not the open clip
func _pick() -> String:
	var s := BestTake.load_stars(stars_path)
	if star_path != "" and s.has(star_path):
		return star_path
	for k in range(s.size() - 1, -1, -1):
		if String(s[k]) != m.scene_path:
			return String(s[k])
	return ""


## read-only analysis (the body is put back EXACTLY)
func analyze() -> Dictionary:
	var sp := _pick()
	if sp == "":
		return {"error": "no star yet: open the clip you like best, press Star this clip, then open another clip"}
	var keep: Dictionary = m.B.state()
	var t0 := Time.get_ticks_usec()
	var sf := BestTake.features_of_file(sp, m.B)
	if sf.is_empty():
		m.B.set_state(keep)
		return {"error": "the starred clip %s cannot be read: unstar it, or star another clip" % sp.get_file()}
	var peers := []
	for d in dirs:
		for p in StylePrint.clip_paths(String(d)):
			if String(p) == sp:
				continue
			var f := BestTake.features_of_file(String(p), m.B)
			if not f.is_empty() and String(f["_family"]) == String(sf["_family"]):
				peers.append(f)
	var rows := BestTake.rank(sf, peers)
	ms = float(Time.get_ticks_usec() - t0) / 1000.0
	m.B.set_state(keep)
	if peers.size() < BestTake.MIN_PEERS:
		return {"error": "only %d other clip%s of its kind: it needs %d to compare against; save more clips, then My best take" % [peers.size(), "" if peers.size() == 1 else "s", BestTake.MIN_PEERS],
			"star": sp}
	return {"star": sp, "feats": sf, "rows": rows.slice(0, BestTake.TOP), "peers": peers.size()}


static func fmt(feat: String, v: float) -> String:
	match feat:
		"windup_hold", "strike_move":
			return "%.2f s" % v
		"anticipation":
			return "%.1f×" % v
		"follow":
			return "%.0f%%" % v
		"guard_h":
			return "%.0f cm" % v
		"stance":
			return "%.2f×" % v
		"peak_hand":
			return "%.1f m/s" % v
	return "%.2f" % v


func _clear() -> VBoxContainer:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	return L


func show() -> void:
	res = analyze()
	_panel()


func _panel() -> void:
	var L := _clear()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("MY BEST TAKE" + ("" if res.has("error") else "  -  %s against %d clips" % [String(res["star"]).get_file(), int(res["peers"])]), 14,
		"warn" if res.has("error") else "heading", true)
	title.name = "bt_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var sb: Button = m._button(("Unstar this clip" if starred() else "Star this clip"), star, "star or unstar the open clip (kept on this computer)")
	sb.name = "bt_star"
	head.add_child(sb)
	head.add_child(m._button("Close", m._close_findings))
	var rows := 0
	if res.has("error"):
		var e: Label = m._label(String(res["error"]), 13, "warn", true)
		e.name = "bt_error"
		e.custom_minimum_size = Vector2(460, 0)
		L.add_child(e)
		rows = 2
	else:
		L.add_child(m._label("The biggest differences, in units of how much your other clips differ among themselves (the bar). Read from your own clips; nothing is changed.", 13, "text:0.6", true))
		var k := 0
		for r in res["rows"]:
			var box := VBoxContainer.new()
			var t: Label = m._label(BestTake.words(r), 13, "text:0.85", true)
			t.name = "bt_row_%d" % k
			t.custom_minimum_size = Vector2(460, 0)
			box.add_child(t)
			var bar := ProgressBar.new()
			bar.name = "bt_bar_%d" % k
			bar.min_value = 0.0
			bar.max_value = 4.0
			bar.value = minf(absf(float(r["effect"])), 4.0)
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(300, 8)
			bar.tooltip_text = "%s: %.1f times the spread of your other clips" % [BestTake.NAME[r["feat"]], absf(float(r["effect"]))]
			box.add_child(bar)
			L.add_child(box)
			k += 1
			rows += 2
		var mb: Button = m._button("Make this one more like my best", make_like, "nudge the open clip toward these values; Preview, then Accept")
		mb.name = "bt_make"
		L.add_child(mb)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(480, clampf(150.0 + 30.0 * rows, 230.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("my best take: " + (String(res["error"]) if res.has("error") else "%d change%s to try, from your other clips" % [(res["rows"] as Array).size(), "" if (res["rows"] as Array).size() == 1 else "s"]))


func make_like() -> void:
	if m.S.cards.size() < 2:
		m._say("make this one more like my best needs a clip of two cards or more: press Enter to add the body as a card (two at least)")
		return
	if res.is_empty() or res.has("error") or String(res.get("star", "")) != _pick():
		res = analyze()
	if res.has("error"):
		_panel()
		return
	var keep: Dictionary = m.B.state()
	var feats := []
	for r in res["rows"]:
		if BestTake.LEVER.has(String(r["feat"])):
			feats.append(String(r["feat"]))
	plan = BestTake.nudge(m.S, m.B, res["feats"], feats)
	m.B.set_state(keep)
	_plan_panel()


func _plan_panel() -> void:
	var L := _clear()
	var ch: Array = plan["changes"]
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("MAKE IT MORE LIKE MY BEST  -  " + ("%d of the differences move" % ch.size() if not ch.is_empty() else "nothing to move in this clip"), 14, "heading", true)
	title.name = "bt_plan_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", m._close_findings))
	L.add_child(m._label("The open clip is nudged toward %s on a copy. Preview changes nothing; Accept is one undo step (Ctrl+Z)." % String(res["star"]).get_file(), 13, "text:0.6", true))
	var row := HBoxContainer.new()
	var pb: Button = m._button("Preview", preview, "play the clip nudged toward your best take; the scene is not changed")
	pb.name = "bt_preview"
	var ab: Button = m._button("Accept", accept, "write the nudge; one undo step")
	ab.name = "bt_accept"
	row.add_child(pb)
	row.add_child(ab)
	L.add_child(row)
	var k := 0
	for c in ch:
		var t: Label = m._label("%s  %s -> %s  (your best take: %s)" % [BestTake.NAME[c["feat"]], fmt(c["feat"], float(c["from"])), fmt(c["feat"], float(c["got"])), fmt(c["feat"], float(c["to"]))], 13, "text:0.85", true)
		t.name = "bt_change_%d" % k
		t.custom_minimum_size = Vector2(460, 0)
		L.add_child(t)
		k += 1
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(480, clampf(190.0 + 26.0 * ch.size(), 230.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("make this one more like my best: %d change%s; Preview plays it, Accept writes it (Ctrl+Z undoes)" % [ch.size(), "" if ch.size() == 1 else "s"])


func preview() -> void:
	if plan.is_empty() or (plan["changes"] as Array).is_empty():
		m._say("nothing to preview: this clip is already near your best take; star another clip, or pick another clip")
		return
	pv = (plan["scene"] as Scene).clone()
	pv_t = 0.0
	pv_end = pv.length()
	m.playing = false
	m._say("make this one more like my best: previewing (the scene is not changed)")


func tick(dt: float) -> void:
	if pv == null:
		return
	pv_t += dt
	if pv_t >= pv_end:
		pv = null
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		return
	pv.apply(m.B, pv_t)
	m._refresh()


func accept() -> void:
	if plan.is_empty() or (plan["changes"] as Array).is_empty():
		m._say("nothing to accept: this clip is already near your best take; star another clip, or pick another clip")
		return
	pv = null
	var n: int = (plan["changes"] as Array).size()
	m._step_hint = "Make this one more like my best"
	m._push_undo()
	m._markers_hold()
	m.S.cards = ((plan["scene"] as Scene).cards).duplicate(true)
	m._markers_follow()
	m._retimed()
	m._say("make this one more like my best: %d change%s moved.  Ctrl+Z undoes it in one step" % [n, "" if n == 1 else "s"])
	plan = {}
	res = {}
	m._ps().apply(m.B, m.playhead)
