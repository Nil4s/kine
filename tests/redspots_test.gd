## godot --path . -s tests/redspots_test.gd     (N074 RED SPOTS ON THE BODY; needs a window: the skin look and a screenshot)
## BARS (stated before the run):
##  (1) MAPPING ON COMBO3 (spline on, "could a human do this?" on, so FOOT SLIDE and JOINT SPEED are in the list beside
##      TIP SPEED / HITCH / HEAD QUIET): every finding with a part lights that part (skin look = the token colour of its
##      severity at RedSpots.FILL, or the weapon halo) at every 30 fps frame inside its span, and at every frame outside
##      ALL the spans of that part no problem look is on it. Sweep: every frame of the clip, every part.
##      Findings with no part (TIPPING, FEASIBLE) are only in the panel: RedSpots.unmapped lists them.
##  (2) SCRUB: a left FOOT SLIDE over frames 40-60: at frame 40 the left foot (and its toes) glow; at frame 39 and 61 not.
##  (3) CLICK (combo3, spline off): a press on the first glowing part with a Fix (main's own pick; the weapon counts) opens the popup with that finding's line; its Fix button
##      runs Check's Fix: the finding is gone from main.findings after it and the undo stack grew by exactly 1.
##  (4) TOGGLE: VIEW > "Show problems on the body" off -> no part lit at any frame, no halo, and the settings file says
##      false; on again -> lit again.
##  (5) COST: main._refresh with the glow on vs off, interleaved at the same 300 playhead times: medians differ < 1 ms.
##  (6) PLACEMENT: a 1280 x 720 view (a SubViewport on the same world, the same camera pose) with the glow on vs off:
##      the changed pixels (>= 40) lie >= 90 % inside the glowing part's screen box (its capsule projected, + 6 px).
##      Measured with that one finding alone (set_findings([it])). Shots: user://zz_redspots.png (that glow), _off.png, _all.png (every spot)
##  (7) THEME: the look's colour is Tok.c("fail") / Tok.c("warn") in both palettes (and theme_test audits red_spots.gd)
extends SceneTree

var fails := 0
var m: Node
var rs: RedSpots


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func at(t: float) -> void:
	m.playhead = t
	m._ps().apply(m.B, t)
	m._refresh()


## what the skin / halo shows on part p now: "FAIL", "WARN" or ""
func lit(p: String) -> String:
	if p in Body.WEAPON or p in Body.WEAPON2:
		return String(rs.last.get(p, "")) if rs.halo_visible(p) else ""
	var lk: Array = m.skp.look_of(p)
	if lk == RedSpots.look("FAIL"):
		return "FAIL"
	if lk == RedSpots.look("WARN"):
		return "WARN"
	return ""


## the test's OWN reading of a finding's span (from the bar's words, not RedSpots.span_of): a run [start, t1], a moment +- 0.25 s
func span(f: Dictionary) -> Vector2:
	var t := float(f["t"])
	if not f.has("t1") or float(f["t1"]) - t < 1.0 / 60.0:
		return Vector2(t - 0.25, float(f.get("t1", t)) + 0.25)
	var t0 := t
	var w := String(f["msg"]).get_slice(" ", 0)
	if "-" in w and w.get_slice("-", 0).is_valid_float():
		t0 = minf(t0, w.get_slice("-", 0).to_float())
	return Vector2(t0, float(f["t1"]))


func sweep(fs: Array, label: String) -> void:
	var L: float = m._ps().length()
	var fps: int = m.S.fps
	var bad := []
	var seen := {}
	for k in int(L * fps) + 1:
		var t := float(k) / fps
		at(t)
		var want := {}
		for f in fs:
			var ps := RedSpots.part_map(f)
			var s := span(f)
			if t >= s.x - 1e-6 and t <= s.y + 1e-6:
				for p in ps:
					if f["sev"] == "FAIL" or not want.has(p):
						want[p] = "FAIL" if f["sev"] == "FAIL" else "WARN"
		for p in Body.ORDER + Body.WEAPON:
			if p == m.sel:
				continue
			var w := String(want.get(p, ""))
			if (p in Body.WEAPON) and not m.B.wep_on:
				w = ""
			var g := lit(p)
			if g != w:
				bad.append("%s @f%d want '%s' got '%s'" % [p, k, w, g])
			if g != "":
				seen[p] = true
	ok(bad.is_empty(), "%s: every frame, every part lit exactly as its findings' spans say (%d mismatches%s); lit parts %s" % [label, bad.size(), (": " + ", ".join(bad.slice(0, 6))) if not bad.is_empty() else "", str(seen.keys())])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	rs = m.redspots
	ok(rs != null and rs.on, "the red spots exist and are on by default")

	var fs: Array = []
	for spl in [true, false]:   # the spline pass and the stepped pass list different findings (FOOT SLIDE / TIP SPEED / HITCH)
		m._load_scene("res://scenes/combo3.json")
		m.S.spline = spl
		m._rebuild_cards()
		HumanLimits.on = true
		m._check()
		await process_frame
		m.sel = "pinky_03_l"   # the picked part keeps the pick look: pick one no rule names
		fs = m.findings
		var tag := "(1) combo3 spline %s" % ("on" if spl else "off")
		var mapped := fs.filter(func(f): return not RedSpots.part_map(f).is_empty())
		var rules := {}
		for f in fs:
			rules[String(f["rule"])] = RedSpots.part_map(f)
		print("     %s findings -> parts: %s" % [tag, str(rules)])
		print("     no part (panel only): %s" % str(rs.unmapped))
		ok(mapped.size() >= 4 and rs.spots.size() == mapped.size(), "%s: %d findings, %d with a part, %d spots" % [tag, fs.size(), mapped.size(), rs.spots.size()])
		var want_map := {"FOOT SLIDE": "foot_", "HEAD QUIET": "head", "TIP SPEED": "bat_barrel", "JOINT SPEED": "calf_"}
		for r in want_map:
			if rules.has(r):
				ok(str(rules[r]).contains(want_map[r]), "%s: %s maps to %s: %s" % [tag, r, want_map[r], str(rules[r])])
		ok(rs.unmapped.all(func(r): return r in ["TIPPING", "FEASIBLE", "BALANCE", "FEASIBLE BALANCE", "FEASIBLE FLIGHT", "GAIT", "JUMP", "STRIKE FRAMES", "ASSERT", "BODY ACCEL"]), "%s: only the whole-body rules have no part: %s" % [tag, str(rs.unmapped)])
		sweep(fs, tag)

	# (2) frame 40-60 left foot slide
	var fps: int = m.S.fps
	var slide := Rulebook._f("WARN", 40.0 / fps, "FOOT SLIDE", "the left foot creeps 4.0 cm along the floor while it should stand", 0.04)
	slide["foot"] = "_l"
	slide["t1"] = 60.0 / fps
	rs.set_findings([slide])
	at(40.0 / fps)
	var on40 := [lit("foot_l"), lit("ball_l"), lit("foot_r")]
	at(39.0 / fps)
	var on39 := lit("foot_l")
	at(61.0 / fps)
	var on61 := lit("foot_l")
	ok(on40 == ["WARN", "WARN", ""] and on39 == "" and on61 == "", "(2) foot slide at frames 40-60: frame 40 left foot/toes/right foot %s, frame 39 '%s', frame 61 '%s'" % [str(on40), on39, on61])
	for dark in [true, false]:
		Tok.set_dark(dark)
		at(50.0 / fps)
		var lk: Array = m.skp.look_of("foot_l")
		var tok := Tok.c("warn")
		ok(not lk.is_empty() and (lk[0] as Color).is_equal_approx(Color(tok, RedSpots.FILL)), "(7) %s palette: the WARN glow is the warn token %s (got %s)" % ["dark" if dark else "light", str(tok), str(lk[0]) if not lk.is_empty() else "none"])
	Tok.set_dark(true)
	m._retheme()
	rs.set_findings(m.findings)

	# (3) click a glowing body part with a Fix
	var target: Dictionary = {}
	for s in rs.spots:
		var p: String = s["parts"][0]
		if Fixer.label(s["f"], m.S) != "":
			target = s
			break
	ok(not target.is_empty(), "(3) combo3 (spline off) has a glowing finding with a Fix: %s" % (("%s on %s" % [target["f"]["rule"], target["parts"]]) if not target.is_empty() else "none"))
	if not target.is_empty():
		var p: String = target["parts"][0]
		var f: Dictionary = target["f"]
		at(float(f["t"]))
		var mp := Vector2(-1, -1)
		var c: Array = m.B.cap(p)
		for u in [0.5, 0.3, 0.7, 0.1, 0.9]:
			var q: Vector2 = m.cam.unproject_position((c[0] as Vector3).lerp(c[1], u))
			if m._pick(q) == p:
				mp = q
				break
		ok(mp.x >= 0.0, "(3) a screen point that main's pick reads as %s: %s" % [p, str(mp)])
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = mp
		ev.pressed = true
		m._unhandled_input(ev)
		var up := ev.duplicate()
		up.pressed = false
		m._unhandled_input(up)
		await process_frame
		var pop: PanelContainer = rs.popup
		var k := int(target["k"]) + 1
		var line: Label = pop.find_child("redspot_line_%d" % k, true, false) if pop != null else null
		var fb: Button = pop.find_child("redspot_fix_%d" % k, true, false) if pop != null else null
		ok(pop != null and pop.is_inside_tree() and line != null and line.text.contains(String(f["rule"])) and fb != null and fb.text == Fixer.label(f, m.S),
			"(3) the click opened the popup: '%s' / button '%s'" % [line.text.left(90) if line != null else "-", fb.text if fb != null else "-"])
		if fb != null:
			var u0: int = m.undo.size()
			fb.pressed.emit()
			for i in 900:
				await process_frame
				if not m._fixing:
					break
			var still: Array = m.findings.filter(func(x): return x["rule"] == f["rule"] and absf(float(x["t"]) - float(f["t"])) < 0.05 and RedSpots.part_map(x) == target["parts"])
			ok(still.is_empty() and m.undo.size() == u0 + 1 and rs.popup == null, "(3) Fix: the %s at %.2f s is gone (%d left), undo %d -> %d (one step), popup closed; status: %s" % [f["rule"], f["t"], still.size(), u0, m.undo.size(), m.ui_status.text.left(80)])
			m._undo()
			m._check()

	# (4) the toggle
	var tb: Button = null
	for b in m.ui_ribbon["VIEW"].get_children():
		if b is Button and m.label_of(b) == "Show problems on the body":
			tb = b
	ok(tb != null, "(4) VIEW has 'Show problems on the body'")
	if tb != null:
		tb.pressed.emit()
		var any := []
		var L: float = m._ps().length()
		for k in int(L * fps) + 1:
			at(float(k) / fps)
			for p in Body.ORDER + Body.WEAPON:
				if lit(p) != "":
					any.append("%s@%d" % [p, k])
		var cf := ConfigFile.new()
		cf.load(m.settings)
		ok(not rs.on and any.is_empty() and cf.get_value("view", "problems_on_body", true) == false, "(4) off: nothing lit on any frame (%d), the setting saved false" % any.size())
		tb.pressed.emit()
		at(float(rs.spots[0]["t0"]) + 0.01 if not rs.spots.is_empty() else 0.0)
		ok(rs.on and not rs.last.is_empty(), "(4) on again: lit again %s" % str(rs.last))

	# (5) cost
	var L2: float = m._ps().length()
	var on_ms := []
	var off_ms := []
	for k in 300:
		var t := L2 * k / 299.0
		m.playhead = t
		m._ps().apply(m.B, t)
		for flag in ([true, false] if k % 2 == 0 else [false, true]):
			rs.on = flag
			var t0 := Time.get_ticks_usec()
			m._refresh()
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			(on_ms if flag else off_ms).append(ms)
	rs.on = true
	on_ms.sort()
	off_ms.sort()
	var d: float = on_ms[150] - off_ms[150]
	ok(absf(d) < 1.0, "(5) _refresh median %.2f ms on vs %.2f ms off over 300 frames: %+.3f ms (bar < 1 ms)" % [on_ms[150], off_ms[150], d])

	# (6) placement at 1280 x 720
	var body_spot: Dictionary = {}
	for s in rs.spots:
		if not s["parts"][0] in Body.WEAPON:
			body_spot = s
			break
	ok(not body_spot.is_empty(), "(6) a body-part spot to shoot")
	if not body_spot.is_empty():
		var p: String = body_spot["parts"][0]
		at((float(body_spot["t0"]) + float(body_spot["t1"])) * 0.5)
		var sv := SubViewport.new()
		sv.size = Vector2i(1280, 720)
		sv.world_3d = m.get_viewport().world_3d
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var sc := Camera3D.new()
		sv.add_child(sc)
		root.add_child(sv)
		sc.fov = m.cam.fov
		sc.near = m.cam.near
		sc.far = m.cam.far
		sc.global_transform = m.cam.global_transform
		sc.current = true
		m._refresh()
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		sv.get_texture().get_image().save_png("user://zz_redspots_all.png")   # every spot at this frame, to look at
		rs.set_findings([body_spot["f"]])   # the bar: ONE finding's glow, so every changed pixel is that part's
		var shots := {}
		for flag in [false, true]:
			rs.on = flag
			m._refresh()
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			shots[flag] = sv.get_texture().get_image()
		shots[true].save_png("user://zz_redspots.png")
		shots[false].save_png("user://zz_redspots_off.png")
		var c: Array = m.B.cap(p)
		var r: float = float(m.B.rad[p])
		var box := Rect2(sc.unproject_position(c[0]), Vector2.ZERO)
		var right: Vector3 = sc.global_transform.basis.x
		var upv: Vector3 = sc.global_transform.basis.y
		for e in [c[0], c[1]]:
			for o in [right * r, -right * r, upv * r, -upv * r]:
				box = box.expand(sc.unproject_position((e as Vector3) + o))
		box = box.grow(6.0)
		var n := 0
		var inside := 0
		var a: Image = shots[true]
		var b0: Image = shots[false]
		for y in range(0, 720, 2):
			for x in range(0, 1280, 2):
				var ca := a.get_pixel(x, y)
				var cb := b0.get_pixel(x, y)
				if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
					n += 1
					if box.has_point(Vector2(x, y)):
						inside += 1
		ok(a.get_width() == 1280 and a.get_height() == 720 and n >= 40 and inside >= 0.9 * n, "(6) %s glow at 1280x720: %d changed pixels (every 2nd), %d inside its screen box %s (%.0f %%); shot %s" % [
			p, n, inside, str(box), 100.0 * inside / maxf(1.0, n), ProjectSettings.globalize_path("user://zz_redspots.png")])
		sv.queue_free()
	HumanLimits.on = false
	print("REDSPOTS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
