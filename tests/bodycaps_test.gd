## godot --headless --path . -s tests/bodycaps_test.gd     (N031 whole-body speed caps, scripts/body_caps.gd; headless is fine)
## Bars (stated before measuring):
##  1 a synthetic COM dash 0 -> 8 m/s in 0.2 s (40 m/s^2) is a BODY ACCEL FAIL of kind start, its peak within 10 % of 40 m/s^2, its frames
##    inside the push (+- 6 frames, the difference's reach), its message naming the frames, the m/s^2 and the cap
##  2 0 -> 5 m/s in 1 s (5 m/s^2), then a cruise: no BODY ACCEL finding of any kind
##  3 a 2 m/s run that stops in 0.2 s (10 m/s^2) is a STOP WARN; a 6 m/s run pushed sideways at 20 m/s^2 for 0.3 s is a CUT FAIL; a
##    0.2 s push up at 25 m/s^2 is a RISE FAIL (each kind is reachable)
##  4 the COM dropping at 1.5 g with no hand holding on is a FALL FAIL inside the drop; the same drop at exactly g has no FALL finding;
##    the 1.5 g drop with a hand holding on has none. A scene (on_floor off) whose body drops 0.4 m in 0.12 s gets a FALL FAIL through
##    the real Check path (HumanLimits.findings)
##  5 the scenes in scenes/ (walk_bat, combo3 and every walk* / combo* in scenes/_wip): every finding printed. walk_bat and the plain
##    walks have NONE; each finding's peak equals an independent recomputation (a fresh 60 Hz COM sample by Scene.apply_true +
##    Balance.com and the closed form (c[i+6] - 2 c[i] + c[i-6]) / 0.1^2) within 2 %
##  6 the fix: a scene that dashes 1 m in 0.25 s has a start FAIL; BodyCaps.retime brings that start peak under its WARN cap (10 m/s^2,
##    re-measured on the retimed scene), changing only "move" of the cards under the peak; Fixer.apply with Check's human limits on
##    keeps it. combo3's step-strike start (card 9) retimed on a copy: its start peak under the cap
##  7 deterministic: the findings of combo3 and of the synthetic dash, run twice, are byte-identical
##  8 facts: "how fast can a person accelerate" -> body_accel (10 m/s^2, MEASURED); stop / change direction / jump push / fall answer
##    their facts; Trust.for_rule("BODY ACCEL") lists every bar with a value
extends SceneTree

var fails := 0
const F := 60.0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


## a COM track at 60 Hz from per-frame accelerations (exact integration of a piecewise constant acceleration)
func track(p0: Vector3, v0: Vector3, segs: Array) -> Array:
	var out := [p0]
	var p := p0
	var v := v0
	var dt := 1.0 / F
	for s in segs:
		var a: Vector3 = s[1]
		for k in int(round(float(s[0]) * F)):
			p += v * dt + a * (0.5 * dt * dt)
			v += a * dt
			out.append(p)
	return out


func kinds(fs: Array) -> Array:
	return fs.map(func(f): return "%s %s %.1f f%d-%d" % [f["sev"], f["kind"], f["accel"], f["frames"][0], f["frames"][1]])


func load_scene(path: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return S


## an independent check of one finding: a fresh COM sample and the closed-form second difference over 6 frames
func fresh_com(S: Scene, B: Body) -> Array:
	var n := int(ceil(S.length() * F)) + 1
	var c := []
	for i in n:
		S.apply_true(B, i / F)
		c.append(Balance.com(B))
	return c


func recompute(c: Array, f: Dictionary) -> float:
	var n := c.size()
	var i: int = f["peak_frame"]
	var g := func(j: int) -> Vector3: return c[clampi(j, 0, n - 1)]
	var a: Vector3 = ((g.call(i + 6) as Vector3) - 2.0 * (g.call(i) as Vector3) + (g.call(i - 6) as Vector3)) / 0.01
	var v0: Vector3 = ((g.call(i) as Vector3) - (g.call(i - 6) as Vector3)) / 0.1
	var v1: Vector3 = ((g.call(i + 6) as Vector3) - (g.call(i) as Vector3)) / 0.1
	var h0 := Vector2(v0.x, v0.z)
	var h1 := Vector2(v1.x, v1.z)
	var ref := h1 if h1.length() >= h0.length() else h0
	var ah := Vector2(a.x, a.z)
	match String(f["kind"]):
		"start":
			return ah.length() if ref.length() < BodyCaps.STILL else ah.dot(ref.normalized())
		"stop":
			return -ah.dot(ref.normalized())
		"cut":
			var u := ref.normalized()
			return (ah - u * ah.dot(u)).length()
		"rise":
			return a.y
	return -a.y


func dash_scene(d: float, t: float) -> Scene:
	var B := body()
	var S := Scene.new()
	S.name = "zz_dash"
	S.add("stand", B.to_dict())
	B.offset = Vector3(0, 0, d)
	B.fk()
	S.add("dash", B.to_dict())
	S.cards[0]["hold"] = 0.3
	S.cards[1]["move"] = t
	S.cards[1]["hold"] = 0.5
	return S


func _init() -> void:
	var B := body()
	# 1 the dash
	var dash := track(Vector3(0, 1, 0), Vector3.ZERO, [[0.5, Vector3.ZERO], [0.2, Vector3(40, 0, 0)], [0.5, Vector3.ZERO]])
	var f1 := BodyCaps.rule(dash)
	print("     dash: ", kinds(f1))
	var st := f1.filter(func(f): return f["kind"] == "start")
	var good1: bool = st.size() == 1 and st[0]["sev"] == "FAIL" and absf(float(st[0]["accel"]) - 40.0) <= 4.0 \
		and int(st[0]["frames"][0]) >= 30 - 6 and int(st[0]["frames"][1]) <= 42 + 6 and String(st[0]["msg"]).contains("frames") \
		and String(st[0]["msg"]).contains("m/s^2") and String(st[0]["msg"]).contains("cap is 10.0")
	ok(good1, "1 0->8 m/s in 0.2 s: start FAIL %s" % [kinds(st)])
	if not st.is_empty():
		print("     ", st[0]["msg"])
	# 2 the honest sprint start
	var easy := track(Vector3(0, 1, 0), Vector3.ZERO, [[0.5, Vector3.ZERO], [1.0, Vector3(5, 0, 0)], [1.0, Vector3.ZERO]])
	var f2 := BodyCaps.rule(easy)
	ok(f2.is_empty(), "2 0->5 m/s in 1 s: no finding %s" % [kinds(f2)])
	# 3 every kind can fire
	var stop := BodyCaps.rule(track(Vector3(0, 1, 0), Vector3(2, 0, 0), [[0.5, Vector3.ZERO], [0.2, Vector3(-10, 0, 0)], [0.5, Vector3.ZERO]]))
	var cut := BodyCaps.rule(track(Vector3(0, 1, 0), Vector3(6, 0, 0), [[0.5, Vector3.ZERO], [0.3, Vector3(0, 0, 20)], [0.5, Vector3.ZERO]]))
	var rise := BodyCaps.rule(track(Vector3(0, 0.8, 0), Vector3.ZERO, [[0.5, Vector3.ZERO], [0.2, Vector3(0, 25, 0)], [0.1, Vector3(0, -9.81, 0)]]))
	var k3: bool = stop.filter(func(f): return f["kind"] == "stop" and f["sev"] == "WARN").size() == 1 and stop.filter(func(f): return f["sev"] == "FAIL").is_empty() \
		and cut.filter(func(f): return f["kind"] == "cut" and f["sev"] == "FAIL").size() == 1 \
		and rise.filter(func(f): return f["kind"] == "rise" and f["sev"] == "FAIL").size() == 1
	ok(k3, "3 stop %s, cut %s, rise %s" % [kinds(stop), kinds(cut), kinds(rise)])
	# 4 drops
	var drop_segs := [[0.3, Vector3.ZERO], [0.3, Vector3(0, -1.5 * 9.81, 0)]]
	var dr := track(Vector3(0, 1.2, 0), Vector3.ZERO, drop_segs)
	var fd := BodyCaps.rule(dr).filter(func(f): return f["kind"] == "fall")
	var fg := BodyCaps.rule(track(Vector3(0, 1.2, 0), Vector3.ZERO, [[0.3, Vector3.ZERO], [0.3, Vector3(0, -9.81, 0)]])).filter(func(f): return f["kind"] == "fall")
	var held := []
	held.resize(dr.size())
	held.fill(true)
	var fh := BodyCaps.rule(dr, held).filter(func(f): return f["kind"] == "fall")
	var B4 := body()
	B4.offset = Vector3(0, -0.4, 0)
	B4.fk()
	var S4b := Scene.new()
	S4b.name = "zz_drop"
	S4b.on_floor = false
	S4b.add("stand", body().to_dict())
	S4b.add("drop", B4.to_dict())
	S4b.cards[0]["hold"] = 0.3
	S4b.cards[1]["move"] = 0.12
	S4b.cards[1]["hold"] = 0.4
	var hs := HumanLimits.findings(S4b, B).filter(func(f): return f["rule"] == "BODY ACCEL" and f["kind"] == "fall")
	ok(fd.size() == 1 and fd[0]["sev"] == "FAIL" and int(fd[0]["frames"][0]) >= 18 - 6 and fg.is_empty() and fh.is_empty() and hs.size() >= 1 and hs[0]["sev"] == "FAIL",
		"4 1.5 g drop %s; at g %s; held %s; scene drop 0.4 m in 0.12 s via Check %s" % [kinds(fd), kinds(fg), kinds(fh), kinds(hs)])
	# 5 the scenes
	var files := ["res://scenes/walk_bat.json", "res://scenes/combo3.json"]
	for f in DirAccess.get_files_at("res://scenes/_wip"):
		if f.ends_with(".json") and (f.begins_with("walk") or f.begins_with("combo")):
			files.append("res://scenes/_wip/" + f)
	var quiet_walks := true
	var worst := 0.0
	var checked := 0
	var seen := {}
	for p in files:
		if not FileAccess.file_exists(p):
			continue
		var txt := FileAccess.get_file_as_string(p)
		if seen.has(txt.hash()):   # _wip keeps byte-identical copies (walk_bat_phone_2..9): judged once, named here
			print("     %-34s same file as %s" % [String(p).get_file(), seen[txt.hash()]])
			continue
		seen[txt.hash()] = String(p).get_file()
		var S := load_scene(p)
		var fs := HumanLimits.findings(S, B).filter(func(f): return f["rule"] == "BODY ACCEL")
		print("     %-34s %d: %s" % [p.get_file(), fs.size(), kinds(fs)])
		var nm: String = String(p).get_file()
		if nm.begins_with("walk") and not nm.contains("phone") and not fs.is_empty():
			quiet_walks = false
		var cc := fresh_com(S, B) if not fs.is_empty() else []
		for f in fs:
			var r := recompute(cc, f)
			worst = maxf(worst, absf(r - float(f["v"])) / maxf(float(f["v"]), 1e-6))
			checked += 1
	ok(quiet_walks and checked > 0 and worst <= 0.02, "5 walk_bat and the plain walks quiet: %s; %d findings recomputed independently, worst %.2f %% off (bar 2 %%)" % [quiet_walks, checked, worst * 100.0])
	# 6 the fix
	var D := dash_scene(1.0, 0.25)
	var fs6 := BodyCaps.findings(D, B).filter(func(f): return f["kind"] == "start")
	var good6 := false
	var msg6 := "no start finding"
	if not fs6.is_empty():
		var D2 := dash_scene(1.0, 0.25)
		var before := JSON.stringify(D2.cards)
		var r := BodyCaps.retime(fs6[0], D2, B)
		var after_fs := BodyCaps.findings(D2, B).filter(func(f): return f["kind"] == "start")
		var pk := float(BodyCaps.peak_in(D2, B, "start", 0.0, D2.length())[0])
		var only := true
		var c0: Array = JSON.parse_string(before)
		for i in D2.cards.size():
			var a: Dictionary = (c0[i] as Dictionary).duplicate(true)
			var b: Dictionary = JSON.parse_string(JSON.stringify(D2.cards[i]))
			a.erase("move")
			b.erase("move")
			if JSON.stringify(a) != JSON.stringify(b) or (not i in r["cards"] and float(c0[i].get("move", 0.0)) != float(D2.cards[i].get("move", 0.0))):
				only = false
		HumanLimits.on = true
		var D3 := dash_scene(1.0, 0.25)
		var fx := HumanLimits.findings(D3, B).filter(func(f): return f["rule"] == "BODY ACCEL" and f["kind"] == "start")
		var fr := Fixer.apply(fx[0], D3, B) if not fx.is_empty() else {"kept": false, "msg": "no finding"}
		HumanLimits.on = false
		good6 = fs6[0]["sev"] == "FAIL" and after_fs.is_empty() and pk < BodyCaps.START_WARN and only and bool(fr["kept"])
		msg6 = "dash %.1f m/s^2 FAIL -> %s; start peak now %.2f (cap %.1f); only moves changed %s; Fixer: %s" % [float(fs6[0]["v"]), r["did"], pk, BodyCaps.START_WARN, only, fr["msg"]]
	var C := load_scene("res://scenes/combo3.json")
	var cst := HumanLimits.findings(C, B).filter(func(f): return f["rule"] == "BODY ACCEL" and f["kind"] == "start")
	var good6b := false
	if not cst.is_empty():
		var C2 := load_scene("res://scenes/combo3.json")
		var rc := BodyCaps.retime(cst[0], C2, B)
		good6b = float(rc["peak_after"]) < BodyCaps.START_WARN and BodyCaps.findings(C2, B).filter(func(f): return f["kind"] == "start").is_empty()
		msg6 += "; combo3: " + String(rc["did"])
	ok(good6 and good6b, "6 " + msg6)
	# 7 deterministic
	var j1 := JSON.stringify(HumanLimits.findings(load_scene("res://scenes/combo3.json"), B).filter(func(f): return f["rule"] == "BODY ACCEL"))
	var j2 := JSON.stringify(HumanLimits.findings(load_scene("res://scenes/combo3.json"), B).filter(func(f): return f["rule"] == "BODY ACCEL"))
	var j3 := JSON.stringify(BodyCaps.rule(dash))
	var j4 := JSON.stringify(BodyCaps.rule(track(Vector3(0, 1, 0), Vector3.ZERO, [[0.5, Vector3.ZERO], [0.2, Vector3(40, 0, 0)], [0.5, Vector3.ZERO]])))
	ok(j1 == j2 and j3 == j4 and j1.length() > 2, "7 deterministic: combo3 %d chars, dash %d chars, identical twice" % [j1.length(), j3.length()])
	# 8 facts and trust
	var qs := {"how fast can a person accelerate": "body_accel", "how fast can a person stop": "body_decel",
		"how fast can a person change direction": "body_cut", "how hard does a jump push the body up": "jump_push", "how fast does a body fall": "fall_rate"}
	var miss := []
	for q in qs:
		var a := HumanFacts.ask(q)
		if not a["found"] or a["id"] != qs[q]:
			miss.append("%s -> %s" % [q, a.get("id", "none")])
	var acc := HumanFacts.ask("how fast can a person accelerate")
	var tr := Trust.for_rule("BODY ACCEL")
	var noval := (tr["bars"] as Array).filter(func(r): return r.get("value") == null)
	print("     ", acc.get("answer", ""))
	ok(miss.is_empty() and float(acc.get("value", 0.0)) == 10.0 and acc["trust"] == Trust.M and noval.is_empty() and (tr["bars"] as Array).size() >= 10,
		"8 facts %s; BODY ACCEL trust %s over %d bars (without a value: %s)" % ["all answered" if miss.is_empty() else str(miss), tr["status"], (tr["bars"] as Array).size(), noval])
	print("BODYCAPS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
