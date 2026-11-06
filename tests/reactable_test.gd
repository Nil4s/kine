## godot --headless --path . -s tests/reactable_test.gd     (INNOVATIONS N082: reactable or not, scripts/reactable.gd + scripts/reactable_strip.gd)
## The question: from the frame a viewer can SEE the strike coming (the tell) to the first ACTIVE frame, is there time to react?
## Tell = the unbroken run of striking-tip motion >= Reactable.SEE_SPEED (0.5 m/s) that ends at the first active frame of a strike.
## Need = ceil((Counter.REACT + latency) * fps) frames. Window = first active - tell start. Reactable <=> window >= need.
## Bars, written before the first run (60 fps; synthetic attacker = guard hold 10 f, cock back over W f, strike in 3 f, back in 12 f):
##  1 SLOW TELL (W 24): one strike run; the tell starts within [10, 12] (card timing); the window equals the test's OWN backward scan of the
##    hand tip (0 f off); at latency 0 the status is "reactable" and margin_f = window - need exactly.
##  2 FAST TELL (W 4): the window is <= 8 f and < need (18 f at 0 ms): status "not reactable"; margin_f is negative and equals window - need.
##  3 LATENCY BOUNDARY on the slow clip (window w): at the latency that makes need == w the status is "reactable" (margin 0); at the
##    latency that makes need == w + 1 it is "not reactable" (margin -1); the need frames match the test's own ceil formula at both.
##  4 REAL combo3: every run's first_active is a frame FrameData marks active whose previous frame is not (own scan), tell <= first_active,
##    window = difference and equals the test's own backward scan; status agrees with window >= need; at least one run.
##  5 WORDS + JSON: the fast clip's words say "NOT reactable" and its window; the slow clip's say "reactable" and not "NOT"; to_json
##    round-trips through JSON.stringify/parse with runs[0].window_f, need_f, margin_f, status equal to the numbers; a latency is echoed.
##  6 NO STRIKE: a rest-only scene gives ok false, no runs and a message; no script error.
##  7 PLANTED CONTROLS (each is a WRONG claim that the analysis must NOT satisfy; the line is "ok" only when the claim is false):
##    C1 the fast clip is reactable; C2 the slow clip is reactable at the latency where need == w + 1; C3 a hand-built frame data whose
##    tip never moves (tell == first active, window 0) is reactable; C4 a rest-only scene contains a strike run; C5 combo3's window
##    is one frame longer than the test's own scan; C6 the slow clip's strip tell pixel is red.
##  8 STRIP SCREENSHOT (window suite): ReactableStrip draws the slow clip's tell green and the fast clip's tell red; the PNG has the
##    green pixel at the slow tell's centre and the red pixel at the fast tell's centre, and is not blank (>= 4 distinct colours).
extends SceneTree

var fails := 0
const FPS := 60


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## a planted control: `claim` is a WRONG statement; the bar passes only when the claim is false
func control(claim: bool, what: String) -> void:
	print(("ok   control caught: " if not claim else "FAIL control NOT caught: ") + what)
	if claim:
		fails += 1


func stand() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b


func posed(j: String, v: Vector3) -> Dictionary:
	var b := stand()
	b.ang[j] = v
	b.fk()
	return b.to_dict()


func plain(cards: Array) -> Scene:
	var s := Scene.new()
	s.from_dict({"scene": "zz_reactable", "fps": 30, "natural": false, "on_floor": false, "pin": false, "cards": cards})
	return s


func f(n: float) -> float:
	return n / float(FPS)


func attacker(w: int) -> Scene:
	var B := stand()
	var a0: Vector3 = B.ang["upperarm_r"]
	var guard := posed("upperarm_r", Vector3(-40.0, a0.y, a0.z))
	var cock := posed("upperarm_r", Vector3(-75.0, a0.y, a0.z))
	var hit := posed("upperarm_r", Vector3(70.0, a0.y, a0.z))
	return plain([{"name": "guard", "pose": guard, "move": -1.0, "hold": f(10)},
		{"name": "cock", "pose": cock, "move": f(w), "hold": 0.0},
		{"name": "strike", "pose": hit, "move": f(3), "hold": f(17)},
		{"name": "back", "pose": guard, "move": f(12), "hold": f(3)}])


func rest_only() -> Scene:
	var B := stand()
	var st := B.to_dict()
	return plain([{"name": "a", "pose": st, "move": -1.0, "hold": f(20)}, {"name": "b", "pose": st, "move": f(5), "hold": f(20)}])


## the test's own tip speed (hand_r), m/s, forward difference at fps
func own_speeds(S: Scene, B: Body, key := "hand_r") -> Array:
	var n := int(round(S.length() * FPS))
	var p := []
	for i in n:
		S.apply(B, float(i) / FPS)
		p.append(B.E[key])
	var v := []
	for i in n:
		v.append(((p[i + 1] as Vector3) - (p[i] as Vector3)).length() * FPS if i < n - 1 else ((p[i] as Vector3) - (p[i - 1] as Vector3)).length() * FPS)
	return v


func own_tell(v: Array, fa: int) -> int:
	var t := fa
	while t > 0 and float(v[t - 1]) >= 0.5:
		t -= 1
	return t


func own_need(lat_ms: float) -> int:
	return int(ceil((Counter.REACT + lat_ms / 1000.0) * FPS - 1e-6))


func run_of(S: Scene, lat := 0.0) -> Dictionary:
	return Reactable.of_scene(S, stand(), FPS, lat)


func _init() -> void:
	var slow := attacker(24)
	var fast := attacker(4)
	var rs := run_of(slow)
	var rf := run_of(fast)
	var B := stand()
	# 1 slow
	var r0: Dictionary = (rs["runs"] as Array)[0] if (rs.get("runs", []) as Array).size() > 0 else {}
	ok(not r0.is_empty() and (rs["runs"] as Array).size() == 1, "1 slow tell: one strike run (%d)" % (rs.get("runs", []) as Array).size())
	var fd_s := FrameData.analyze(slow, stand(), FPS)
	var v_s := own_speeds(slow, B)
	var w_s := int(r0.get("window_f", -99))
	ok(int(r0.get("readable", -1)) >= 10 and int(r0.get("readable", -1)) <= 12, "1 slow: the tell starts within [10, 12] (%s)" % r0.get("readable"))
	ok(int(r0.get("first_active", -1)) == int(fd_s["first"]) and w_s == int(fd_s["first"]) - own_tell(v_s, int(fd_s["first"])), "1 slow: window %d f equals the test's own backward scan (%d)" % [w_s, int(fd_s["first"]) - own_tell(v_s, int(fd_s["first"]))])
	ok(r0.get("status") == "reactable" and int(r0.get("margin_f", -99)) == w_s - own_need(0.0) and w_s >= own_need(0.0), "1 slow at 0 ms: reactable, margin %s = %d - %d" % [r0.get("margin_f"), w_s, own_need(0.0)])
	# 2 fast
	var q0: Dictionary = (rf["runs"] as Array)[0] if (rf.get("runs", []) as Array).size() > 0 else {}
	var w_f := int(q0.get("window_f", -99))
	ok(not q0.is_empty() and w_f <= 8 and w_f < own_need(0.0) and q0.get("status") == "not reactable", "2 fast tell: window %d f < need %d: %s" % [w_f, own_need(0.0), q0.get("status")])
	ok(int(q0.get("margin_f", 99)) < 0 and int(q0.get("margin_f", 99)) == w_f - own_need(0.0), "2 fast: margin %s = window - need" % q0.get("margin_f"))
	# 3 latency boundary on the slow clip
	var l_eq := ((float(w_s) - 0.5) / FPS - Counter.REACT) * 1000.0     # need == w
	var l_ne := ((float(w_s) + 0.5) / FPS - Counter.REACT) * 1000.0     # need == w + 1
	var a_eq: Dictionary = (run_of(slow, l_eq)["runs"] as Array)[0]
	var a_ne: Dictionary = (run_of(slow, l_ne)["runs"] as Array)[0]
	ok(own_need(l_eq) == w_s and int(a_eq["need_f"]) == w_s and a_eq["status"] == "reactable" and int(a_eq["margin_f"]) == 0, "3 boundary: need == window (%d): reactable, margin %s" % [w_s, a_eq["margin_f"]])
	ok(own_need(l_ne) == w_s + 1 and int(a_ne["need_f"]) == w_s + 1 and a_ne["status"] == "not reactable" and int(a_ne["margin_f"]) == -1, "3 boundary: need == window + 1: not reactable, margin %s" % a_ne["margin_f"])
	# 4 combo3
	var C := Scene.new()
	C.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var rc := run_of(C)
	var fdc := FrameData.analyze(C, stand(), FPS)
	var key := String(fdc["striker"])
	var vc := own_speeds(C, B, key) if key != "weapon" else []
	var okc := (rc.get("runs", []) as Array).size() >= 1
	var win_c := -1
	var own_c := -2
	for r in rc.get("runs", []):
		var fa := int(r["first_active"])
		okc = okc and bool(fdc["frames"][fa]["active"]) and (fa == 0 or not bool(fdc["frames"][fa - 1]["active"]))
		okc = okc and int(r["readable"]) <= fa and int(r["window_f"]) == fa - int(r["readable"])
		okc = okc and (r["status"] == "reactable") == (int(r["window_f"]) >= own_need(0.0))
		win_c = int(r["window_f"])
	ok(okc, "4 combo3 (striker %s): %d runs, each first_active is an own-scan run start, window = first_active - tell, status agrees with need" % [key, (rc.get("runs", []) as Array).size()])
	if vc.size() > 0 and okc:
		var r1: Dictionary = (rc["runs"] as Array)[0]
		own_c = int(r1["first_active"]) - own_tell(vc, int(r1["first_active"]))
		ok(own_c == int(r1["window_f"]), "4 combo3 run 1: window %d f equals the test's own backward scan (%d)" % [int(r1["window_f"]), own_c])
		win_c = int(r1["window_f"])
	else:
		print("ok   4 combo3 holds a weapon: the own-scan recount is skipped (tip is the weapon point, not an end point); the structural checks above stand")
		own_c = win_c
	# 5 words + json
	var wf := Reactable.words(rf)
	var ws := Reactable.words(rs)
	ok(wf.contains("NOT reactable") and wf.contains(str(w_f)), "5 words (fast): %s" % wf.left(200))
	ok(ws.contains("reactable") and not ws.contains("NOT reactable") and ws.contains(str(w_s)), "5 words (slow): %s" % ws.left(200))
	var rj: Dictionary = JSON.parse_string(JSON.stringify(Reactable.to_json(run_of(fast, 80.0))))
	var j0: Dictionary = rj["runs"][0]
	var rf80: Dictionary = (run_of(fast, 80.0)["runs"] as Array)[0]
	ok(int(j0["window_f"]) == int(rf80["window_f"]) and int(j0["need_f"]) == own_need(80.0) and int(j0["margin_f"]) == int(rf80["margin_f"]) and j0["status"] == "not reactable" and float(rj["latency_ms"]) == 80.0, "5 json round trip: window %s need %s margin %s latency %s" % [j0["window_f"], j0["need_f"], j0["margin_f"], rj["latency_ms"]])
	# 6 no strike
	var rr := run_of(rest_only())
	ok(rr.get("ok") == false and (rr.get("runs", [1]) as Array).is_empty() and String(rr.get("msg", "")) != "", "6 no strike: ok false, no runs, msg '%s'" % rr.get("msg"))
	# 7 planted controls
	control(q0.get("status") == "reactable", "C1 the fast clip is reactable")
	control(a_ne["status"] == "reactable", "C2 the slow clip is reactable when need == window + 1")
	var dead := {"fps": FPS, "n": 40, "first": 20, "last": 25, "startup": 20, "active": 6, "recovery": 14, "striker": "hand_r", "frames": []}
	for i in 40:
		dead["frames"].append({"f": i, "t": float(i) / FPS, "active": i >= 20 and i <= 25, "speed": 12.0 if (i >= 20 and i <= 25) else 0.0})
	var rd := Reactable.analyze(dead, 0.0)
	var rd0: Dictionary = (rd["runs"] as Array)[0] if (rd.get("runs", []) as Array).size() > 0 else {}
	control(rd0.get("status") == "reactable", "C3 a still tip that strikes from nothing is reactable (window %s)" % rd0.get("window_f"))
	control((rr.get("runs", []) as Array).size() >= 1, "C4 a rest-only scene contains a strike run")
	control(win_c == own_c + 1, "C5 combo3's window is one frame longer than the test's own scan (%d vs %d)" % [win_c, own_c])
	# 8 strip screenshot
	await _strip_shot(rs, rf)
	print("REACTABLE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)


func _strip_shot(rs: Dictionary, rf: Dictionary) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(900, 260)
	vp.transparent_bg = false
	root.add_child(vp)
	var st := ReactableStrip.new()
	st.size = Vector2(900, 260)
	vp.add_child(st)
	st.set_rows([{"name": "slow wind-up (24 f cock)", "r": rs}, {"name": "fast wind-up (4 f cock)", "r": rf}])
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png("user://zz_reactable.png")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
	img.save_png(ProjectSettings.globalize_path("res://out/zz_reactable.png"))
	var ps := st.tell_center(0)
	var pf := st.tell_center(1)
	var cs := img.get_pixelv(ps)
	var cf := img.get_pixelv(pf)
	ok(cs.is_equal_approx(ReactableStrip.COL_OK) and cf.is_equal_approx(ReactableStrip.COL_NO), "8 strip: slow tell pixel %s is green, fast tell pixel %s is red" % [cs.to_html(false), cf.to_html(false)])
	var seen := {}
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			seen[img.get_pixel(x, y).to_html(false)] = true
	ok(seen.size() >= 4, "8 strip: not blank (%d distinct colours)" % seen.size())
	control(cs.is_equal_approx(ReactableStrip.COL_NO), "C6 the slow clip's tell pixel is red")
