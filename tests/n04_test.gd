extends SceneTree
## godot --headless --path . -s tests/n04_test.gd     (N04: native cape sim, native/ KineClothNative, scripts/cloth.gd)
## Native vs GDScript Cloth.simulate on the app's own data: scenes/walk_bat.json (3.5 s, 30 fps = the cloth_test walk) and the quick turn.
## Bars, written before measuring:
##   1 DLL: the class loads (reported) or every native bar says SKIP
##   2 EQUAL: after 10 frames the two capes agree within 1e-6 m per vertex; at the last frame within 1e-4 m (cloth is chaotic,
##     the C++ is compiled float math and may differ in the last bit of a float; the max deviation is printed); same frame count
##   3 CHUNKED: simulate() with a ctl (one native call per frame) equals the one-call result bit for bit
##   4 NO DLL: Cloth.force_gdscript = true runs the GDScript sim and is deterministic
##   5 TIMING (median of 5): the sim of the walk bake, GDScript vs native; BAR native >= 5x faster
const REPS := 5
const TOL10 := 1e-6
const TOLEND := 1e-4
var fails := 0
var skips := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


static func med(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])


class Ctl:
	var n := 0
	func report(_f: float) -> void:
		n += 1
	func cancelled() -> bool:
		return false


func max_dev(a: Array, b: Array, upto: int) -> float:
	var w := 0.0
	for k in mini(upto, mini(a.size(), b.size())):
		var fa: PackedVector3Array = a[k]
		var fb: PackedVector3Array = b[k]
		for i in fa.size():
			w = maxf(w, fa[i].distance_to(fb[i]))
	return w


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	var fps := S.fps
	var nf := maxi(int(ceil(S.length() * float(fps) - 1e-6)), 1) + 1
	var t0 := Time.get_ticks_usec()
	var sm := Cloth.sample_frames(B, nf, fps, func(t: float) -> void: S.apply(B, minf(t, S.length())))
	var t_sample := (Time.get_ticks_usec() - t0) / 1000.0
	var rads := Cloth.radii(B, sm["names"])
	print("walk_bat: %d frames at %d fps, %d capsules; sampling %.0f ms" % [nf, fps, rads.size(), t_sample])

	Cloth.force_gdscript = true
	ok(not Cloth.native_on(), "4a force_gdscript turns the door off")
	var g1: Dictionary = Cloth.simulate(sm["A"], sm["C"], rads, fps, null)
	var g2: Dictionary = Cloth.simulate(sm["A"], sm["C"], rads, fps, null)
	ok(var_to_str(g1["frames"]) == var_to_str(g2["frames"]), "4b the GDScript sim is deterministic")
	Cloth.force_gdscript = false
	if not Cloth.native_on():
		print("SKIP native bars (no KineClothNative: the DLL is missing)")
		print("n04: %d fail" % fails)
		quit(fails)
		return
	ok(true, "1 KineClothNative loaded")
	var n1: Dictionary = Cloth.simulate(sm["A"], sm["C"], rads, fps, null)
	var gf: Array = g1["frames"]
	var nfr: Array = n1["frames"]
	ok(gf.size() == nfr.size() and gf.size() == nf, "2a frame count identical (%d)" % gf.size())
	var d10 := max_dev(gf, nfr, 10)
	var dend := max_dev(gf, nfr, gf.size())
	var dlast := max_dev([gf[-1]], [nfr[-1]], 1)
	print("   max deviation: first 10 frames %s m, all frames %s m, last frame %s m" % [String.num_scientific(d10), String.num_scientific(dend), String.num_scientific(dlast)])
	ok(d10 < TOL10, "2b first 10 frames within 1e-6 m")
	ok(dend < TOLEND and dlast < TOLEND, "2c all frames / last frame within 1e-4 m")
	var ctl := Ctl.new()
	var n2: Dictionary = Cloth.simulate(sm["A"], sm["C"], rads, fps, ctl)
	ok(var_to_str(n2["frames"]) == var_to_str(n1["frames"]) and ctl.n > 0, "3 chunked (ctl, %d reports) equals the one-call result" % ctl.n)

	# the quick turn too (fast motion, collisions)
	var T := Scene.new()
	T.fps = 30
	var rest := {}
	for j in Body.ORDER:
		rest[j] = {"bend": 0.0, "side": 0.0, "twist": 0.0}
	T.add("stand", {"joints": rest.duplicate(true), "offset": [0.0, 0.0, 0.0]})
	(T.cards[-1] as Dictionary)["hold"] = 1.0
	var turned := rest.duplicate(true)
	(turned["pelvis"] as Dictionary)["twist"] = 90.0
	T.add("turn", {"joints": turned, "offset": [0.0, 0.0, 0.0]})
	(T.cards[-1] as Dictionary)["move"] = 0.25
	(T.cards[-1] as Dictionary)["hold"] = 2.0
	var tn := maxi(int(ceil(T.length() * 30.0 - 1e-6)), 1) + 1
	var tsm := Cloth.sample_frames(B, tn, 30, func(t: float) -> void: T.apply(B, minf(t, T.length())))
	Cloth.force_gdscript = true
	var tg: Dictionary = Cloth.simulate(tsm["A"], tsm["C"], rads, 30, null)
	Cloth.force_gdscript = false
	var tnat: Dictionary = Cloth.simulate(tsm["A"], tsm["C"], rads, 30, null)
	var td10 := max_dev(tg["frames"], tnat["frames"], 10)
	var tdend := max_dev(tg["frames"], tnat["frames"], tn)
	print("   quick turn: first 10 frames %s m, all frames %s m" % [String.num_scientific(td10), String.num_scientific(tdend)])
	ok(td10 < TOL10 and tdend < TOLEND, "2d quick turn within tolerance")

	# timing: the sim (what the app's worker runs) and the whole bake_scene
	var tg_a := []
	var tn_a := []
	for r in REPS:
		Cloth.force_gdscript = true
		var a := Time.get_ticks_usec()
		Cloth.simulate(sm["A"], sm["C"], rads, fps, null)
		tg_a.append((Time.get_ticks_usec() - a) / 1000.0)
		Cloth.force_gdscript = false
		a = Time.get_ticks_usec()
		Cloth.simulate(sm["A"], sm["C"], rads, fps, null)
		tn_a.append((Time.get_ticks_usec() - a) / 1000.0)
	var mg := med(tg_a)
	var mn := med(tn_a)
	print("TIMING simulate (walk_bat %d frames, median of %d): GDScript %.1f ms | native %.1f ms | x%.1f" % [nf, REPS, mg, mn, mg / maxf(mn, 1e-6)])
	var bg := []
	var bn := []
	for r in 3:
		Cloth.force_gdscript = true
		var a := Time.get_ticks_usec()
		Cloth.bake_scene(S, B)
		bg.append((Time.get_ticks_usec() - a) / 1000.0)
		Cloth.force_gdscript = false
		a = Time.get_ticks_usec()
		Cloth.bake_scene(S, B)
		bn.append((Time.get_ticks_usec() - a) / 1000.0)
	print("APP-LEVEL full cape bake (Cloth.bake_scene on walk_bat, sampling + sim, median of 3): before %.2f s | after %.2f s | x%.1f" % [med(bg) / 1000.0, med(bn) / 1000.0, med(bg) / maxf(med(bn), 1e-6)])
	ok(mg / maxf(mn, 1e-6) >= 5.0, "5 native >= 5x faster on the sim (x%.1f)" % (mg / maxf(mn, 1e-6)))
	ok(med(bn) < med(bg), "5b the whole bake is faster")
	print("n04: %d fail" % fails)
	quit(fails)
