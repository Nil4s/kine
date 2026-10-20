## godot --path . -s tests/r1_test.gd   (needs a window: the PLACEMENT bar reads a screenshot through the shot camera)
## ROADMAP round 2, R1: LIGHTING PRESETS on the shot camera (scripts/light_rig.gd; main.gd _light_preset / _light_apply).
## Bars, stated before measuring:
##   1 each preset sets the three lights and the ambient to exactly what LightRig.rig says for the keyed camera, and the
##     four presets are pairwise different
##   2 real ratios (Brown, Cinematography: Theory and Practice): key:fill three-point 2..4, rim 1.5..4, noir >= 8,
##     daylight sun:sky 3..5
##   3 geometry: the key is on the camera's side of the subject (dot with the direction to the lens > 0.25) and to the
##     camera's LEFT; the rim of "three_point" and "rim" is BEHIND the subject (dot < 0)
##   4 each click is ONE undo step: undo restores the shots AND the lights exactly (energies, colours, bases), redo
##     brings the preset back
##   5 saved with the scene: to_dict -> JSON -> from_dict keeps the preset; the lights rebuilt from the loaded scene
##     equal the ones before the save
##   6 PLACEMENT (screenshot through the shot camera): the half of the character on the key's side (screen left) is brighter
##     than the other half: mean luminance ratio >= 1.8 for three_point, >= 4 for noir (8:1), daylight >= 1.4 (soft)
##   7 RIM (R1b): in the "rim" preset the outermost 3 px of the silhouette's edge (the side the back light is on, screen
##     left) are >= 1.5x brighter than the pixels 10..12 px inside it; the four looks are unmistakable
## Nothing is written outside the process but the screenshot (POSER_R1_PNG) and the 4-up sheet (POSER_R1_SHEET).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func pose() -> Dictionary:
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.fk()
	return R.to_dict()


func lights(m: Node) -> Array:
	var out := []
	for L in [m.light_key, m.light_fill, m.light_rim]:
		out.append([L.light_energy, L.light_color, L.basis])
	out.append([m.world_env.ambient_light_energy, m.world_env.ambient_light_color, m.world_env.adjustment_enabled, m.world_env.adjustment_brightness, m.world_env.adjustment_contrast])
	return out


## two light states equal: energies, colours and bases to 1e-5 (a Node3D rebuilds its basis from Euler angles, so a basis
## set and read back differs in the last float bits)
func same(a: Array, b: Array) -> bool:
	for i in 3:
		if absf(a[i][0] - b[i][0]) > 1e-6 or not (a[i][1] as Color).is_equal_approx(b[i][1]) or not (a[i][2] as Basis).is_equal_approx(b[i][2]):
			return false
	return absf(a[3][0] - b[3][0]) < 1e-6 and (a[3][1] as Color).is_equal_approx(b[3][1]) and a[3][2] == b[3][2] and absf(a[3][3] - b[3][3]) < 1e-6 and absf(a[3][4] - b[3][4]) < 1e-6


## mean luminance of the character pixels in a column range; a pixel is "character" when the lit render differs from the
## body-less background by more than a hair: here, the region is the torso box the caller gives
func lum(img: Image, r: Rect2i) -> float:
	var s := 0.0
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y)
			s += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return s / maxf(1.0, float(n))


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S := Scene.new()
	S.name = "zz_r1"
	S.fps = 24
	S.shots = [{"t": 0.0, "name": "Shot 1", "keys": [], "fx": {}}]
	S.add("c0", pose())
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 0.0
	m._refresh()
	await idle(3)
	var CAM := {"t": 0.0, "pos": Vector3(0, 1.0, 5.0), "aim": Vector3(0, 0.9, 0), "f": 50.0}

	# no camera yet: the command refuses with a next step and changes nothing
	var base := lights(m)
	m._light_preset("noir")
	ok(not S.shots[0].has("light") and same(lights(m), base), "0 no shot camera yet: the preset refuses (nothing changed)")

	ShotCam.put(S.shots[0]["keys"], CAM)
	m._refresh()
	await idle(2)
	base = lights(m)
	var shots0: Array = S.shots.duplicate(true)

	var seen := []
	for id in LightRig.IDS:
		m._light_preset(id)
		await idle(2)
		var r := LightRig.rig(id, CAM["pos"], CAM["aim"])
		var good: bool = S.shots[0].get("light", "") == id
		for pair in [[m.light_key, "key"], [m.light_fill, "fill"], [m.light_rim, "rim"]]:
			var L: DirectionalLight3D = pair[0]
			var d: Dictionary = r[pair[1]]
			good = good and absf(L.light_energy - float(d["energy"])) < 1e-6 and L.light_color.is_equal_approx(d["color"])
			good = good and (-L.global_transform.basis.z * 1.0).distance_to(d["dir"]) < 1e-4
		good = good and absf(m.world_env.ambient_light_energy - float(r["ambient"]["energy"])) < 1e-6
		ok(good, "1 %s: the key, fill, rim and ambient are the rig's (key %.2f fill %.3f rim %.2f ambient %.2f)" % [id, r["key"]["energy"], r["fill"]["energy"], r["rim"]["energy"], r["ambient"]["energy"]])
		seen.append(lights(m))
		var f := LightRig.forward_h(CAM["pos"], CAM["aim"])
		var key_src: Vector3 = -(r["key"]["dir"] as Vector3)
		var rim_src: Vector3 = -(r["rim"]["dir"] as Vector3)
		ok(key_src.dot(-f) > 0.25 and key_src.dot(-f.cross(Vector3.UP)) > 0.3, "3 %s: the key is on the lens side (dot %.2f) and to the camera's left (%.2f)" % [id, key_src.dot(-f), key_src.dot(-f.cross(Vector3.UP))])
		if id == "three_point" or id == "rim":
			ok(rim_src.dot(-f) < 0.0, "3 %s: the rim is behind the subject (dot %.2f)" % [id, rim_src.dot(-f)])
	for i in 4:
		for j in range(i + 1, 4):
			ok(not same(seen[i], seen[j]), "1 %s and %s differ" % [LightRig.IDS[i], LightRig.IDS[j]])
	var rt := {"three_point": [2.0, 4.0], "rim": [1.5, 4.0], "noir": [8.0, 100.0], "daylight": [3.0, 5.0]}
	for id in LightRig.IDS:
		var q: float = LightRig.ratio(id)
		ok(q >= rt[id][0] - 1e-6 and q <= rt[id][1] + 1e-6, "2 %s key:fill %.2f:1 within %.1f..%.1f" % [id, q, rt[id][0], rt[id][1]])

	# 4 one undo step each; the lights come back exactly
	m._light_preset("")
	await idle(2)
	ok(not S.shots[0].has("light") and S.shots[0] == shots0[0] and same(lights(m), base), "4 'back to the default lights' is exactly the stage's own lights and the shot as it was keyed")
	m._light_preset("three_point")
	var with := lights(m)
	m._light_preset("noir")
	m._undo()
	await idle(2)
	ok(S.shots[0].get("light", "") == "three_point" and same(lights(m), with), "4 one undo after 'noir' is back to three_point, lights exactly as before")
	m._undo()
	await idle(2)
	ok(m.S.shots == shots0 and same(lights(m), base), "4 the next undo is back to no preset: shots equal the start's, lights exactly the stage's own")
	m._redo()
	await idle(2)
	ok(m.S.shots[0].get("light", "") == "three_point" and same(lights(m), with), "4 redo brings three_point back")

	# 5 saved with the scene, restored on load
	m._light_preset("noir")
	var noir := lights(m)
	var txt := JSON.stringify(m.S.to_dict(m.B))
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(txt))
	ok(S2.shots.size() == 1 and S2.shots[0].get("light", "") == "noir", "5 the loaded scene's shot carries 'noir'")
	m.S = S2
	m._light_sig = "x"
	m._rebuild_cards()
	m._refresh()
	await idle(2)
	ok(same(lights(m), noir), "5 the lights after the load equal the lights before the save")
	ok(not JSON.stringify(Scene.new().to_dict(m.B)).contains("\"light\""), "5 a scene with no preset writes no 'light' key")

	# 6 PLACEMENT + the 4-up sheet: look through the shot camera (a clean render: no UI, no highlights, no floor or grid),
	# read the character's two halves. The character's pixels = where a lit render differs from the same frame with every
	# light off; its two halves split at the middle of those pixels.
	m.S = S
	m._rebuild_cards()
	m._refresh()
	m.clean = true
	m.ui_root.visible = false
	for c in m.stage_root.get_children():
		if c is MeshInstance3D:
			c.visible = false
	m._shot_toggle()
	await idle(6)
	var rect: Rect2i = m.shot_rect()
	var imgs := []
	for id in LightRig.IDS:
		if S.shots[0].get("light", "") != id:
			m._light_preset(id)
		await idle(5)
		imgs.append(root.get_texture().get_image().get_region(rect))
	var keep := lights(m)
	var e_key: float = m.light_key.light_energy
	for L in [m.light_key, m.light_fill, m.light_rim]:
		L.light_energy = 0.0
	m.world_env.ambient_light_energy = 0.0
	await idle(5)
	var dark: Image = root.get_texture().get_image().get_region(rect)
	var img0: Image = imgs[0]
	var x0 := img0.get_width()
	var x1 := 0
	var npx := 0
	var mask := {}
	for y in range(0, img0.get_height(), 2):
		for x in range(0, img0.get_width(), 2):
			var a := img0.get_pixel(x, y)
			var b := dark.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.12:
				mask[Vector2i(x, y)] = true
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
	var cx := (x0 + x1) / 2
	ok(mask.size() > 400, "6 the character is found in the frame: %d lit pixels, x %d..%d of %d" % [mask.size(), x0, x1, img0.get_width()])
	var want := {"three_point": 1.8, "rim": 0.0, "noir": 4.0, "daylight": 1.4}
	for i in 4:
		var id: String = LightRig.IDS[i]
		var sl := 0.0
		var sr := 0.0
		var nl := 0
		var nr := 0
		for k in mask:
			if absf(float(k.x - cx)) > 0.12 * float(x1 - x0):
				continue   # the torso, legs and head: the two halves are both body (the arms' reach would add only distance)
			var c: Color = (imgs[i] as Image).get_pixelv(k)
			var v := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			if k.x < cx:
				sl += v
				nl += 1
			else:
				sr += v
				nr += 1
		var left := sl / maxf(1.0, float(nl))
		var right := sr / maxf(1.0, float(nr))
		print("  %s lit-side %.4f other-side %.4f ratio %.2f" % [id, left, right, left / maxf(1e-6, right)])
		if want[id] > 0.0:
			ok(left / maxf(1e-6, right) >= want[id], "6 %s: the key's half (screen left) is brighter than the other: %.2f (bar %.2f)" % [id, left / maxf(1e-6, right), want[id]])
	# 7 rim: full-resolution silhouette = where the lit frame differs from the all-lights-off frame; per row, each run of
	# silhouette pixels at least 40 px wide gives an edge sample (3 px at the run's end) and an inside sample (10..12 px in)
	var ri: Image = imgs[1]
	var res := {}
	for side in ["L", "R"]:
		res[side] = [0.0, 0.0, 0]
	for y in range(0, ri.get_height()):
		var x := 0
		var W := ri.get_width()
		while x < W:
			var a := img0.get_pixel(x, y)
			var b := dark.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) <= 0.12:
				x += 1
				continue
			var s0 := x
			while x < W:
				var a2 := img0.get_pixel(x, y)
				var b2 := dark.get_pixel(x, y)
				if absf(a2.r - b2.r) + absf(a2.g - b2.g) + absf(a2.b - b2.b) <= 0.12:
					break
				x += 1
			var e0 := x - 1
			if e0 - s0 < 40:
				continue
			for pr in [["L", s0, 1], ["R", e0, -1]]:
				var e := 0.0
				var n := 0.0
				for d in 3:
					var c: Color = ri.get_pixel(pr[1] + pr[2] * d, y)
					e += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
				for d in range(10, 13):
					var c: Color = ri.get_pixel(pr[1] + pr[2] * d, y)
					n += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
				res[pr[0]][0] += e / 3.0
				res[pr[0]][1] += n / 3.0
				res[pr[0]][2] += 1
	var rl: float = res["L"][0] / maxf(1e-6, res["L"][1])
	var rr: float = res["R"][0] / maxf(1e-6, res["R"][1])
	print("  rim edge/inside: left %.2f right %.2f (%d / %d rows)" % [rl, rr, res["L"][2], res["R"][2]])
	ok(res["L"][2] > 30 and rl >= 1.5, "7 rim: the silhouette's back-lit edge (3 px) is %.2fx the pixels 10 px inside (bar 1.5)" % rl)
	var png := OS.get_environment("POSER_R1_PNG")
	var sheet := OS.get_environment("POSER_R1_SHEET")
	if sheet != "":
		var w := 480
		var h := int(float(w) * float(img0.get_height()) / float(img0.get_width()))
		var out := Image.create(w * 4, h, false, Image.FORMAT_RGB8)
		for i in 4:
			var im: Image = (imgs[i] as Image).duplicate()
			im.convert(Image.FORMAT_RGB8)
			im.resize(w, h, Image.INTERPOLATE_LANCZOS)
			out.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(i * w, 0))
		out.save_png(sheet)
	if png != "":
		(imgs[0] as Image).save_png(png)
	print("r1_test: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
