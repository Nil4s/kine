## godot --headless --path . -s tests/textview_test.gd     (docs/INNOVATIONS.md N001: TEXT VIEW OF A POSE)
## The bars, stated BEFORE measuring:
##   1 determinism: the same pose gives byte-identical text (twice in a row, and again after the body is put back from its
##     saved state), on every test pose.
##   2 landmarks: on 6 poses, every fist's height word is the landmark nearest its MEASURED height (this test reads the
##     fist and say_it.gd's landmarks itself); a raised fist reads "above his head" and a guard's fists read "chin height".
##   3 projection: every one of the 18 symbols, in both views, is drawn within 1 character (Chebyshev) of the exact cell
##     this test computes from the joint's position (his frame, 6 x 11 cm cells, centred on the figure's extent), and the
##     character there IS that symbol.
##   4 weight: the paragraph's split is within 5 percentage points of the lever rule computed here from balance.gd's own
##     com() and footprint(), on every pose with both feet down; and a "weight on the left foot" pose reads left > 50 %.
##   5 size: the whole text is under 2,500 characters on every pose.
##   6 reach: serve's `text_view {card: N}` on combo3 answers the same text as TextView.view of that card's pose, adds no
##     undo step; a bad card is a -32602 error; the CLI `textview <scene> card=N` prints it and ends with {"ok": true ...}.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func near_word(B: Body, sd: String, y: float) -> String:
	var lm := {"head": (B.E["head"] as Vector3).y}
	if y > float(lm["head"]):
		return "above his head"
	for n in ["eyes", "chin", "shoulder", "chest", "belly", "hip", "knee"]:
		lm[n] = (SayIt.landmark(B, n, sd, sd) as Vector3).y
	lm["ankle"] = (B.P["foot" + sd] as Vector3).y
	var best := ""
	var bd := INF
	for n in ["head", "eyes", "chin", "shoulder", "chest", "belly", "hip", "knee", "ankle"]:
		if absf(y - float(lm[n])) < bd:
			bd = absf(y - float(lm[n]))
			best = n
	return {"head": "the top of his head", "eyes": "eye height"}.get(best, best + " height")


func lever_left(B: Body) -> float:
	var c := Balance.com(B)
	var cen := []
	for sd in ["_l", "_r"]:
		var f := Balance.footprint(B, sd)
		if f.is_empty():
			return -1.0
		var r := Rect2(f[0], Vector2.ZERO)
		for q in f:
			r = r.expand(q)
		cen.append(r.get_center())
	var d: Vector2 = cen[0] - cen[1]
	return clampf((Vector2(c.x, c.z) - cen[1]).dot(d) / d.length_squared(), 0.0, 1.0)


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var rest := B.state()
	var poses := {"rest": "", "guard": "guard", "raised right fist": "right hand over the head",
		"crouch, weight left": "crouched, weight on the left foot", "lunge lean": "lunge, lean forward 20",
		"deep crouch, high guard": "deep crouch, high guard"}
	var seen := {}
	var worst_proj := 0
	var n_proj := 0
	var land_ok := 0
	var land_n := 0
	var wmax := 0.0
	var wn := 0
	var maxc := 0
	for name in poses:
		B.set_state(rest)
		if poses[name] != "":
			SayIt.apply(B, poses[name], false)
		var keep := B.state()
		var v := TextView.view(B)
		var v2 := TextView.view(B)
		B.set_state(keep)
		var v3 := TextView.view(B)
		ok(v["text"] == v2["text"] and v["text"] == v3["text"], "1 %s: byte-identical three times (%d chars)" % [name, v["chars"]])
		seen[name] = v
		print("---- %s\n%s" % [name, v["text"]])
		# 2 landmarks
		for sd in ["_r", "_l"]:
			var fc: Array = B.cap("hand" + sd)
			var y: float = (((fc[0] as Vector3) + (fc[1] as Vector3)) * 0.5).y
			var want := near_word(B, sd, y)
			var got: String = v["facts"]["fist_" + ("right" if sd == "_r" else "left")]["word"]
			land_n += 1
			if got == want and (want + "") in v["words"]:
				land_ok += 1
			else:
				print("     %s %s fist y %.3f: said '%s', nearest '%s'" % [name, sd, y, got, want])
		# 3 projection
		var yw := TextView.yaw(B)
		var pts := TextView.points(B)
		var grid: PackedStringArray = v["ascii"].split("\n")
		for vi in 2:
			var view := "front" if vi == 0 else "side"
			var lo := INF
			var hi := -INF
			for k in TextView.SYM:
				var q: Vector3 = ((pts[k] as Vector3) - Vector3((B.P["pelvis"] as Vector3).x, 0, (B.P["pelvis"] as Vector3).z)).rotated(Vector3.UP, -deg_to_rad(yw))
				lo = minf(lo, q.x if vi == 0 else q.z)
				hi = maxf(hi, q.x if vi == 0 else q.z)
			var cen := (lo + hi) * 0.5
			for k in TextView.SYM:
				var l: Vector3 = (pts[k] as Vector3) - Vector3((B.P["pelvis"] as Vector3).x, 0, (B.P["pelvis"] as Vector3).z)
				l = l.rotated(Vector3.UP, -deg_to_rad(yw))
				var h := l.x if view == "front" else l.z
				var exact := Vector2i(15 + roundi((h - cen) / 0.06), 20 - roundi(l.y / 0.11))
				n_proj += 1
				var d := 99
				if v["cells"][view].has(k):
					var at: Vector2i = v["cells"][view][k]
					var line: String = grid[1 + at.y]
					var col := at.x + (0 if vi == 0 else TextView.COLS + 2)
					if col < line.length() and line[col] == k:
						d = maxi(absi(at.x - exact.x), absi(at.y - exact.y))
				worst_proj = maxi(worst_proj, d)
				if d > 1:
					print("     %s %s '%s': exact %s, drawn %s" % [name, view, k, exact, v["cells"][view].get(k, "none")])
		# 4 weight
		var lv := lever_left(B)
		if lv >= 0.0:
			var said := -1.0
			var rx := RegEx.create_from_string("Weight (\\d+) % on the (left|right) foot|Weight even")
			var mt := rx.search(v["words"])
			if mt != null:
				said = 0.5 if mt.get_string(0) == "Weight even" else (float(mt.get_string(1)) / 100.0 if mt.get_string(2) == "left" else 1.0 - float(mt.get_string(1)) / 100.0)
			wn += 1
			wmax = maxf(wmax, absf(said - lv) if said >= 0.0 else 1.0)
			print("     %s: weight left said %.2f, lever %.3f" % [name, said, lv])
		maxc = maxi(maxc, v["chars"])
	ok(land_n >= 10 and land_ok == land_n, "2 landmarks: %d of %d fists named by their measured nearest landmark" % [land_ok, land_n])
	ok("right fist above his head" in String(seen["raised right fist"]["words"]).to_lower(), "2 a raised fist reads 'above his head': " + str(seen["raised right fist"]["facts"]["fist_right"]))
	var gw := String(seen["guard"]["words"]).to_lower()
	ok("right fist at chin height" in gw and "left fist at chin height" in gw and "guard up" in gw,
		"2 a guard reads 'chin height' on both fists, 'guard up': %s / %s" % [seen["guard"]["facts"]["fist_right"], seen["guard"]["facts"]["fist_left"]])
	ok(worst_proj <= 1, "3 projection: %d symbol placements, the worst %d char from its exact cell" % [n_proj, worst_proj])
	ok(wn >= 4 and wmax <= 0.05, "4 weight: %d poses with both feet down, the words within %.1f points of the lever rule (bar 5)" % [wn, wmax * 100.0])
	var wl: Variant = seen["crouch, weight left"]["facts"]["weight_left"]
	ok(wl != null and wl > 0.5 and "on the left foot" in seen["crouch, weight left"]["words"], "4 'weight on the left foot' reads left: %s" % str(wl))
	ok(maxc < 2500, "5 size: the longest text is %d chars (bar 2,500)" % maxc)

	# 6 serve and the CLI
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)
	await T.request(1, "open", {"path": "scenes/combo3.json"})
	var u0: int = m.undo.size()
	var r: Dictionary = await T.request(2, "text_view", {"card": 2})
	var u1: int = m.undo.size()
	await T.step("card=1")
	await T.step("card=2")   # the card picker's own way to put card 2 on the body
	var want: String = TextView.view(m.B)["text"]
	ok(r.has("result") and r["result"]["text"] == want and u1 == u0, "6 serve text_view {card: 2}: %s, undo steps added %d" % [
		"the view of card 2" if r.has("result") and r["result"]["text"] == want else str(r).left(200), u1 - u0])
	var bad: Dictionary = await T.request(3, "text_view", {"card": 99})
	ok(bad.has("error") and bad["error"]["code"] == -32602, "6 a bad card is -32602: " + str(bad.get("error", {}).get("message", "")))
	var rt: Dictionary = await T.request(4, "text_view", {"t": 0.5})
	ok(rt.has("result") and rt["result"]["chars"] < 2500, "6 text_view {t: 0.5}: %d chars" % (rt["result"]["chars"] if rt.has("result") else -1))
	var out := []
	OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "tools/poser_cli.gd", "--", "textview", "scenes/combo3.json", "card=2"], out, true)
	var txt: String = "".join(out)
	var last := ""
	for l in txt.split("\n"):
		if l.begins_with("{\"") and "\"ok\"" in l:
			last = l
	ok("FRONT" in txt and "Weight" in txt and last != "" and JSON.parse_string(last) is Dictionary and JSON.parse_string(last).get("ok", false),
		"6 CLI textview combo3 card=2 prints the view and ends with ok: %s" % last.left(80))
	print("TEXTVIEW %s: %d failed" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
