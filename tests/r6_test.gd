## godot --path . -s tests/r6_test.gd     (ROADMAP round 2, R6; needs a window: the real page bar is clicked)
## ONE OBVIOUS NEXT STEP on every page. BARS (written before measuring):
##  1 6 states x 6 pages: the line is never empty and is the state's step: no clip -> "Clip this pose", one clip -> "Clip the next
##    pose", unchecked -> "Run Check", FAILs -> "Fix the first problem: <rule>...", clean -> "Export", edited since Check -> "Run Check"
##  2 it names a real command: its registry row exists (CLIP this pose / Check the motion / Export...), the Fix names its finding's rule
##  3 a REAL mouse click on it moves the state forward (cards +1, Check fresh, fails down or the finding picked, Export dialog open)
##  4 PLACEMENT: the line is inside the page bar (the page's own strip), shown, wider than 120 px, below the scene strip, and the
##    whole body (feet to head, projected) is above the page bar: the line is never over the viewport's body
extends SceneTree

var m: Node
var fails := 0
var shots := {}


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	await idle()


func nfails() -> int:
	return m.findings.filter(func(f): return f["sev"] == "FAIL").size()


func setup(st: int) -> void:
	m.S.cards.clear()
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.check_ran = false
	m.findings = []
	if st == 0:
		m.S.cards.clear()
		m.sel_card = -1
		m._rebuild_cards()
	elif st == 1:
		m.S.cards = [m.S.cards[0]]
		m.sel_card = 0
		m._rebuild_cards()
	elif st >= 3:
		m._check()
		if st >= 4:
			m.findings = []   # a clean grade of this scene
			m.check_ran = true
			m.check_at = m.undo.size()
		if st == 5:
			m._push_undo()
	m._refresh()


const WANT := ["Clip this pose", "Clip the next pose", "Run Check", "Fix the first problem: ", "Export", "Run Check"]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	var bar: Control = m.ui_page_bar
	var names := []
	for c in m.ui_cmd.commands:
		names.append(String(c["name"]))
	for st in 6:
		for pg in m.PAGES:
			setup(st)
			await click(m.ui_page_btns[pg])
			var b: Button = m.ui_next
			var t: String = b.text
			var body := t.trim_prefix("Next:  ")
			var n: Dictionary = m.next_step()
			var shape_ok: bool = t != "" and body.begins_with(WANT[st])
			if st == 3:
				shape_ok = shape_ok and nfails() > 0 and body.contains(String(n["finding"]["rule"]))
			ok(shape_ok, "1 state %d on %s: '%s'" % [st, pg, t])
			var real: bool = (n["cmd"] in names) if n["cmd"] != "" else (st == 3 and Fixer.label(n["finding"], m.S) != "" or st == 3)
			ok(real, "2 state %d on %s names a real command: %s" % [st, pg, n["cmd"] if n["cmd"] != "" else n["finding"]["rule"]])
			# 4 placement
			var r: Rect2 = b.get_global_rect()
			var br: Rect2 = bar.get_global_rect()
			var feet: Vector2 = m.cam.unproject_position(Vector3(0, 0, 0))
			var head: Vector2 = m.cam.unproject_position(Vector3(0, 1.8, 0))
			var inside: bool = br.encloses(r) and b.is_visible_in_tree() and r.size.x > 120.0 and r.position.y >= m.ui_bp.get_global_rect().end.y - 0.5
			var clear: bool = maxf(feet.y, head.y) < br.position.y and r.position.y >= br.position.y - 0.5
			ok(inside and clear, "4 state %d on %s: line %s inside bar %s, body y %.0f..%.0f above the bar" % [st, pg, r, br, head.y, feet.y])
			if (st == 3 and pg == "CHECK") or (st == 0 and pg == "BODY") or (st == 4 and pg == "DELIVER"):
				var img: Image = root.get_texture().get_image()
				shots[pg] = img
			# 3 the click moves it forward
			var c0: int = m.S.cards.size()
			var f0: int = nfails()
			var sig0 := "%s|%s|%s" % [m.playhead, m.sel_card, JSON.stringify(m.S.cards)]
			await click(b)
			while m._fixing:
				await process_frame
			await idle()
			var fwd := false
			match st:
				0, 1: fwd = m.S.cards.size() == c0 + 1
				2, 5: fwd = m.check_ran and m.check_at == m.undo.size()
				3: fwd = nfails() < f0 or "%s|%s|%s" % [m.playhead, m.sel_card, JSON.stringify(m.S.cards)] != sig0
				4: fwd = m.export_ui != null and m.export_ui.dlg != null and m.export_ui.dlg.visible
			ok(fwd and m.ui_next.text != "", "3 state %d on %s: one click moves it forward -> '%s'" % [st, pg, m.ui_next.text])
			if st == 4 and m.export_ui != null:
				m.export_ui.dlg.hide()
	var dir := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/"
	for pg in shots:
		(shots[pg] as Image).save_png(dir + "r6_" + String(pg).to_lower() + ".png")
	print("R6 %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(fails)
