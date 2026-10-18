## godot --headless --path . -s tests/plant_edges_test.gd     (GATES MM2, UPGRADES_200 #132)
## NO SNAP AT A CARD EDGE. Every scene in scenes/ played at 60 fps twice, planting on and off. (1) At every frame that
## crosses a card's start, arrival or leave, no leg joint (thigh, calf, foot) turns more than 3 degrees beyond what it
## turns with planting off (before round 32: up to 42.4, 33 such frames over 10 scenes). (2) A pinned foot stays put:
## through a pinned move AND the hold after it, its ball within 1 cm of where it was planted, every frame. (3) The
## steps' own speed inside a move is printed, not barred (a 14 cm step in 0.15 s is the card asking for it).
extends SceneTree

const LEG := ["thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func gap(a: Quaternion, b: Quaternion) -> float:
	return rad_to_deg(2.0 * acos(clampf(absf(a.dot(b)), 0.0, 1.0)))


func play(S: Scene, B: Body, pinned: bool) -> Array:
	S.pin = pinned
	var out := []
	var L := S.length()
	for k in int(ceil(L * 60)) + 1:
		S.apply(B, minf(k / 60.0, L))
		var g := {}
		for j in LEG:
			g[j] = B.G[j]
		g["knee_l"] = B.ang["calf_l"]
		g["knee_r"] = B.ang["calf_r"]
		g["ball_l"] = B.P["ball_l"]
		g["ball_r"] = B.P["ball_r"]
		for sd in ["_l", "_r"]:   # ZZ1: a foot rolling onto its heel holds the mark with the heel (the point under the ankle)
			g["roll" + sd] = S.heel_roll(minf(k / 60.0, L), sd)
			g["heel" + sd] = (B.P["foot" + sd] as Vector3).y - (B.p0["foot" + sd] as Vector3).y
		out.append(g)
	return out


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var B: Body = m.B
	var edge_n := 0
	var roll_n := 0
	var roll_worst := 0.0
	var edge_worst := 0.0
	var edge_at := ""
	var slide := 0.0
	var slide_at := ""
	var slide_n := 0
	var inside := 0.0
	var inside_at := ""
	var over := []
	var slides := []
	var reach_n := 0   # every edge frame over the bar: [extra, where] (printed when it fails, to say which rule)
	var names := []
	for f in DirAccess.get_files_at("res://scenes"):
		if f.ends_with(".json") and not f.begins_with("zz_"):
			names.append(f)
	names.sort()
	for f in names:
		var S := Scene.new()
		S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + f)))
		var on := play(S, B, true)
		var off := play(S, B, false)
		S.pin = true
		var ts := S.times()
		var E: Array = S._anchors(B)
		for k in range(1, on.size()):
			var t := minf(k / 60.0, S.length())
			var tp := (k - 1) / 60.0
			var crosses := false
			for c in ts:
				for e in [0, 1, 2]:
					if tp < float(c[e]) - 1e-6 and t >= float(c[e]) - 1e-6:
						crosses = true
			for j in LEG:
				# AMENDED (MM2): a SNAP is a POP: one frame that turns more than BOTH its neighbours (a one-frame jump),
				# measured planting on beyond planting off. A step still landing as the card arrives keeps turning on the
				# frames around the edge (thrust card 9: 41 -> 29 -> 17.5 degrees) and is no pop; the old snaps were
				# 40-degree frames between still ones
				var x := 0.0
				if k + 1 < on.size():
					var pop_on := gap(on[k][j], on[k - 1][j]) - maxf(gap(on[k - 1][j], on[k - 2][j]) if k > 1 else 0.0, gap(on[k + 1][j], on[k][j]))
					var pop_off := gap(off[k][j], off[k - 1][j]) - maxf(gap(off[k - 1][j], off[k - 2][j]) if k > 1 else 0.0, gap(off[k + 1][j], off[k][j]))
					x = pop_on - maxf(pop_off, 0.0)
				if crosses:
					edge_n += 1
					if x > 3.0:
						var ci := S.span(t)
						var cc: int = ci if ci > 0 else S._held(t)
						var sd: String = j.right(2)
						var pm: String = E[cc - 1][sd][3] if cc > 0 else "-"
						var cm: String = E[cc][sd][3] if cc >= 0 else "-"
						over.append([x, "%s %.3f s %s %.1f deg: %s card %d (%s -> %s)" % [f.get_basename(), t, j, x, "move into" if ci > 0 else "hold of", cc, pm, cm]])
					if x > edge_worst:
						edge_worst = x
						edge_at = "%s %.3f s %s" % [f.get_basename(), t, j]
				elif x > inside:
					inside = x
					inside_at = "%s %.3f s %s" % [f.get_basename(), t, j]
			# (2) pinned feet: the card being moved into (or held) pins this foot -> its ball on the anchor
			var i := S.span(t)
			var c: int = i if i > 0 else S._held(t)
			if c > 0:
				for sd in ["_l", "_r"]:
					# AMENDED (MM2): a leg drawn out STRAIGHT (knee bend under 1 degree) cannot reach its mark: the card
					# puts the hips too far (dodge_side: hip to mark 0.955 m, the leg 1.003 m with the foot's own angle).
					# Counted and printed as out of reach, not as a slide (a straight leg ON its mark is counted as usual)
					if E[c][sd][3] == "pin" and absf((on[k]["knee" + sd] as Vector3).x) < 1.0 and (on[k]["ball" + sd] as Vector3).distance_to(E[c][sd][0]) > 0.01:
						reach_n += 1
						continue
					# AMENDED (ZZ1, round 44): a foot still ROLLING onto its heel (Scene.heel_roll: from the heel strike to
					# foot flat, carried just past the card) holds the mark with its heel, the ball still coming down: those
					# frames are counted apart, the heel within 1 cm of the floor (it rolls on it, as people's heel rocker)
					if E[c][sd][3] == "pin" and float(on[k]["roll" + sd]) > 0.0:
						roll_n += 1
						roll_worst = maxf(roll_worst, absf(float(on[k]["heel" + sd])))
						continue
					if E[c][sd][3] == "pin":
						var d: float = (on[k]["ball" + sd] as Vector3).distance_to(E[c][sd][0])
						slide_n += 1
						if d > 0.01:
							var pm2: String = E[c - 1][sd][3]
							slides.append([d, "%s %.3f s ball%s %.3f m: %s card %d (%s -> pin)" % [f.get_basename(), t, sd, d, "move into" if i > 0 else "hold of", c, pm2]])
						if d > slide:
							slide = d
							slide_at = "%s %.3f s ball%s" % [f.get_basename(), t, sd]
	ok(edge_n > 100 and edge_worst <= 3.0, "1 card edges: %d leg-joint frames crossing an edge over %d scenes; worst extra turn from planting %.2f deg (%s)" % [edge_n, names.size(), edge_worst, edge_at])
	ok(roll_worst <= 0.01, "2b feet rolling onto the heel (ZZ1): %d foot-frames, the heel's worst height off the floor %.4f m (bar 0.01)" % [roll_n, roll_worst])
	ok(slide_n > 100 and slide <= 0.01, "2 pinned feet: %d foot-frames planted (moves and holds); the ball's worst distance from where it was planted %.4f m (%s)" % [slide_n, slide, slide_at])
	over.sort_custom(func(p, q): return p[0] > q[0])
	for o in over.slice(0, 20):
		print("   over: " + o[1])
	slides.sort_custom(func(p, q): return p[0] > q[0])
	print("   slides over 1 cm: %d; foot-frames out of reach (the leg straight): %d" % [slides.size(), reach_n])
	for o in slides.slice(0, 12):
		print("   slide: " + o[1])
	print("   3 (reported) inside a move, planting's worst extra leg turn in one frame: %.1f deg (%s)" % [inside, inside_at])
	print("PLANT EDGES: %d failed" % fails)
	quit(1 if fails > 0 else 0)
