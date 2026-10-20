## floor_plan.gd - I42 FLOOR PLAN. A top-down rehearsal plan of the fight for the stunt crew, from the judges and the scene the app already has:
##   FOOTPRINTS  every foot placement, numbered in order for its fighter, with its time. A placement is a FOOT PLANT of the scene (Scene.plants,
##               foot_plant.gd) when the scene has any; a scene with none gets them from SOLE CONTACT: a stretch where the sole (heel, ball, toe
##               tip) is within STAND_Y = 3 cm of the floor and its centre moves under STAND_V = 0.25 m/s, lasting at least STAND_T = 0.1 s. The
##               footprint is the sole's outline (heel to toe tip) at the placement's start time, on the floor.
##   PATHS       each fighter's centre of mass (Balance.com) on the floor, one sample per frame, in the fighter's colour.
##   STRIKES     for each strike card (BeatFight.contacts) the striking hand / weapon tip that travels furthest, from the wind-up pose (the previous
##               card's arrival) to the contact (this card's arrival), as an arrow, if it travels at least STRIKE_MIN = 0.2 m.
##   SAFETY      the I28 items that have a place (SafetySheet: contacts, weapon tip passes, close passes) as rings of their margin.
## A 100 cm grid and a scale bar. Nothing is written to the scenes and the bodies here are the plan's own (the scenes are cloned).
## {"fighters": [{"name", "color" (Tok token), "steps", "com": PackedVector2Array, "com_t", "strikes", "from_plants"}], "safety", "bounds": Rect2 (x, z; m), "length" (s)}
class_name FloorPlan
extends RefCounted

const STAND_Y := 0.03
const STAND_V := 0.25
const STAND_T := 0.1
const STRIKE_MIN := 0.2
const PAD := 0.5          # m of floor shown beyond the outermost thing drawn
const FEET := ["_l", "_r"]
const COLORS := ["fp_1", "fp_2", "fp_3", "fp_4"]
const DIR := "user://floor_plan"   # where the page and the picture are written (a policy in tests/confirm_test.gd)


static func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## the sole's heel and toe tip on the floor of body B (fighter space)
static func sole(B: Body, sd: String) -> Array:
	return [_xz(FootRoll.heel_point(B, sd)), _xz(B.E["ball" + sd])]


static func foot_poly(heel: Vector2, toe: Vector2) -> PackedVector2Array:
	var d := toe - heel
	var L := maxf(d.length(), 0.01)
	var u := d / L
	var p := Vector2(-u.y, u.x)
	var ball := heel + u * L * 0.7
	return PackedVector2Array([heel + p * 0.032, heel - p * 0.032, ball - p * 0.045, toe - p * 0.02, toe + p * 0.02, ball + p * 0.045])


## the placements of one fighter. S is cloned by the caller. [{"n", "foot", "t", "t1", "heel", "toe", "pos"}] in world space, numbered by time
static func steps(S: Scene, B: Body, xf: Transform3D, fps: int) -> Dictionary:
	var runs := []   # [{"foot", "t", "t1"}]
	var from_plants := not S.plants.is_empty()
	if from_plants:
		for p in S.plants:
			runs.append({"foot": String(p["foot"]).right(2), "t": float(p["t0"]), "t1": float(p["t1"])})
	else:
		var n := int(ceil(S.length() * fps))
		for sd in FEET:
			var start := -1
			var prev := Vector2.ZERO
			for f in n + 2:
				var down := false
				if f <= n:
					S.apply(B, float(f) / fps)
					var h := FootRoll.heel_point(B, sd)
					var ball: Vector3 = B.P["ball" + sd]
					var toe: Vector3 = B.E["ball" + sd]
					var c := (_xz(h) + _xz(toe)) * 0.5
					down = minf(h.y, minf(ball.y, toe.y)) <= STAND_Y and (f == 0 or (c - prev).length() * fps <= STAND_V)
					prev = c
				if down and start < 0:
					start = f
				elif not down and start >= 0:
					if float(f - start) / fps >= STAND_T:
						runs.append({"foot": sd, "t": float(start) / fps, "t1": float(f - 1) / fps})
					start = -1
	runs.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]) if float(a["t"]) != float(b["t"]) else String(a["foot"]) < String(b["foot"]))
	var out := []
	for k in runs.size():
		var r: Dictionary = runs[k]
		# a plant is read at the middle of its range, where it is fully held (at t0 the previous plant of the same foot may still be releasing)
		var tr: float = (float(r["t"]) + float(r["t1"])) * 0.5 if from_plants else float(r["t"])
		S.apply(B, tr)
		var s := sole(B, String(r["foot"]))
		var h := _xz(xf * Vector3(s[0].x, 0.0, s[0].y))
		var t := _xz(xf * Vector3(s[1].x, 0.0, s[1].y))
		out.append({"n": k + 1, "foot": "left" if r["foot"] == "_l" else "right", "t": r["t"], "t1": r["t1"], "tr": tr, "heel": h, "toe": t, "pos": (h + t) * 0.5})
	return {"steps": out, "from_plants": from_plants}


## the plan of scenes[k] placed by xfs[k] (hero space), names[k]. The scenes are cloned.
static func analyze(scenes: Array, names: Array, xfs: Array, fps := 30, with_safety := true) -> Dictionary:
	var fighters := []
	var pts := []
	var length := 0.0
	for k in scenes.size():
		var S: Scene = (scenes[k] as Scene).clone()
		var B := DistanceKeeper.new_body()
		var xf: Transform3D = xfs[k]
		var st := steps(S, B, xf, fps)
		var com := PackedVector2Array()
		var com_t := PackedFloat32Array()
		var n := int(ceil(S.length() * fps))
		length = maxf(length, S.length())
		for f in n + 1:
			S.apply(B, float(f) / fps)
			com.append(_xz(xf * Balance.com(B)))
			com_t.append(float(f) / fps)
		# the strikes
		var strikes := []
		var ts := S.times()
		for i in BeatFight.contacts(S):
			var ta: float = ts[i - 1][1]
			var tb: float = ts[i][1]
			S.apply(B, ta)
			var a3: Dictionary = DistanceKeeper.tips(B).duplicate()
			S.apply(B, tb)
			var b3: Dictionary = DistanceKeeper.tips(B)
			var best := ""
			var bd := 0.0
			for key in b3:
				var d: float = (xf * (a3[key] as Vector3)).distance_to(xf * (b3[key] as Vector3))
				if d > bd:
					bd = d
					best = key
			if best != "" and bd >= STRIKE_MIN:
				var pa: Vector3 = xf * (a3[best] as Vector3)
				var pb: Vector3 = xf * (b3[best] as Vector3)
				strikes.append({"card": i, "tip": best, "t0": ta, "t1": tb, "from": _xz(pa), "to": _xz(pb), "len": bd, "y": pb.y})
				pts.append(_xz(pa))
				pts.append(_xz(pb))
		for s in st["steps"]:
			for q in [s["heel"], s["toe"]]:
				pts.append(q)
		for q in com:
			pts.append(q)
		fighters.append({"name": names[k], "color": COLORS[k % COLORS.size()], "steps": st["steps"], "from_plants": st["from_plants"],
			"com": com, "com_t": com_t, "strikes": strikes})
	var safety := []
	if with_safety and scenes.size() >= 1:
		var rep := SafetySheet.analyze(scenes, names, xfs, fps)
		for it in rep["items"]:
			if it["at"] is Vector3:
				var kind := String(it["kind"])
				safety.append({"t": it["t"], "sev": it["sev"], "kind": kind, "who": it["who"], "text": it["text"], "at": _xz(it["at"]),
					"r": SafetySheet.TIP_NEAR if kind == "tip" else (SellHit.SAFE if kind == "close" else 0.05), "r_in": SellHit.SAFE if kind == "tip" else 0.0})
				pts.append(_xz(it["at"]))
	return {"fighters": fighters, "safety": safety, "bounds": bounds_of(pts), "length": length}


static func bounds_of(pts: Array) -> Rect2:
	if pts.is_empty():
		return Rect2(-1.5, -1.5, 3.0, 3.0)
	var lo: Vector2 = pts[0]
	var hi: Vector2 = pts[0]
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var r := Rect2(lo - Vector2(PAD, PAD), hi - lo + Vector2(PAD, PAD) * 2.0)
	return r


## world (x, z) -> pixels in a box of w x h: {"s" (px per m), "o" (the pixel of the world point bounds.position)}; the whole bounds fit, centred
static func fit(bounds: Rect2, w: float, h: float, margin := 8.0) -> Dictionary:
	var s := minf((w - 2.0 * margin) / bounds.size.x, (h - 2.0 * margin) / bounds.size.y)
	var o := Vector2((w - bounds.size.x * s) * 0.5, (h - bounds.size.y * s) * 0.5)
	return {"s": s, "o": o}


static func to_px(fx: Dictionary, bounds: Rect2, p: Vector2) -> Vector2:
	return (fx["o"] as Vector2) + (p - bounds.position) * float(fx["s"])


static func summary(plan: Dictionary) -> String:
	var n := 0
	var ns := 0
	for f in plan["fighters"]:
		n += (f["steps"] as Array).size()
		ns += (f["strikes"] as Array).size()
	return "floor plan: %d footprint%s, %d strike line%s, %d safety mark%s over %.1f s" % [n, "" if n == 1 else "s", ns, "" if ns == 1 else "s",
		(plan["safety"] as Array).size(), "" if (plan["safety"] as Array).size() == 1 else "s", float(plan["length"])]


## ---- the page ----

static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


static func _hex(tok: String) -> String:
	return "#" + (Tok.LIGHT[tok] as Color).to_html(false)


## the plan as SVG (print palette: Tok.LIGHT), W px wide, as tall as the floor needs
static func to_svg(plan: Dictionary, W := 900.0) -> String:
	var b: Rect2 = plan["bounds"]
	var H := W * b.size.y / b.size.x
	var fx := fit(b, W, H, 4.0)
	var s: float = fx["s"]
	var ink := _hex("ink")
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 %.0f %.0f\" width=\"%.0f\" height=\"%.0f\" font-family=\"system-ui,Segoe UI,sans-serif\">\n" % [W, H, W, H]
	svg += "<rect width=\"100%%\" height=\"100%%\" fill=\"#ffffff\" stroke=\"%s\"/>\n" % _hex("grid_major")
	var x0: float = ceil(b.position.x)
	while x0 <= b.end.x:
		var p := to_px(fx, b, Vector2(x0, b.position.y))
		svg += "<line x1=\"%.1f\" y1=\"0\" x2=\"%.1f\" y2=\"%.0f\" stroke=\"%s\" stroke-width=\"%s\"/>\n" % [p.x, p.x, H, _hex("grid"), "1.5" if int(x0) % 5 == 0 else "0.6"]
		svg += "<text x=\"%.1f\" y=\"11\" font-size=\"10\" fill=\"%s\">%s</text>\n" % [p.x + 2.0, ink, Units.len(x0)]
		x0 += 1.0
	var z0: float = ceil(b.position.y)
	while z0 <= b.end.y:
		var p := to_px(fx, b, Vector2(b.position.x, z0))
		svg += "<line x1=\"0\" y1=\"%.1f\" x2=\"%.0f\" y2=\"%.1f\" stroke=\"%s\" stroke-width=\"%s\"/>\n" % [p.y, W, p.y, _hex("grid"), "1.5" if int(z0) % 5 == 0 else "0.6"]
		svg += "<text x=\"2\" y=\"%.1f\" font-size=\"10\" fill=\"%s\">%s</text>\n" % [p.y - 2.0, ink, Units.len(z0)]
		z0 += 1.0
	for sf in plan["safety"]:
		var c := to_px(fx, b, sf["at"])
		var col := _hex("fail" if sf["sev"] == "red" else "warn")
		svg += "<circle cx=\"%.1f\" cy=\"%.1f\" r=\"%.1f\" fill=\"%s\" fill-opacity=\"0.12\" stroke=\"%s\" stroke-width=\"1.5\"/>\n" % [c.x, c.y, maxf(float(sf["r"]) * s, 4.0), col, col]
		if float(sf["r_in"]) > 0.0:
			svg += "<circle cx=\"%.1f\" cy=\"%.1f\" r=\"%.1f\" fill=\"none\" stroke=\"%s\" stroke-width=\"1\" stroke-dasharray=\"3 2\"/>\n" % [c.x, c.y, float(sf["r_in"]) * s, col]
		svg += "<text x=\"%.1f\" y=\"%.1f\" font-size=\"10\" font-weight=\"700\" fill=\"%s\">%s %.2f s</text>\n" % [c.x + maxf(float(sf["r"]) * s, 4.0) + 2.0, c.y + 3.0, col, String(sf["kind"]).to_upper(), float(sf["t"])]
	for f in plan["fighters"]:
		var col := _hex(String(f["color"]))
		var pl := ""
		for p in f["com"]:
			var q := to_px(fx, b, p)
			pl += "%.1f,%.1f " % [q.x, q.y]
		svg += "<polyline points=\"%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"2.5\" stroke-opacity=\"0.8\" stroke-linejoin=\"round\"/>\n" % [pl, col]
		var tk := 1.0
		var com_t: PackedFloat32Array = f["com_t"]
		for i in com_t.size():
			if float(com_t[i]) + 1e-4 >= tk:
				var q := to_px(fx, b, (f["com"] as PackedVector2Array)[i])
				svg += "<circle cx=\"%.1f\" cy=\"%.1f\" r=\"3\" fill=\"%s\"/><text x=\"%.1f\" y=\"%.1f\" font-size=\"9\" fill=\"%s\">%.0f s</text>\n" % [q.x, q.y, col, q.x + 4.0, q.y - 4.0, ink, tk]
				tk += 1.0
		for st in f["strikes"]:
			var a := to_px(fx, b, st["from"])
			var e := to_px(fx, b, st["to"])
			var d := (e - a).normalized()
			var n := Vector2(-d.y, d.x)
			svg += "<line x1=\"%.1f\" y1=\"%.1f\" x2=\"%.1f\" y2=\"%.1f\" stroke=\"%s\" stroke-width=\"2\" stroke-dasharray=\"6 3\"/>\n" % [a.x, a.y, e.x, e.y, col]
			svg += "<polygon points=\"%.1f,%.1f %.1f,%.1f %.1f,%.1f\" fill=\"%s\"/>\n" % [e.x, e.y, e.x - d.x * 9.0 + n.x * 4.5, e.y - d.y * 9.0 + n.y * 4.5, e.x - d.x * 9.0 - n.x * 4.5, e.y - d.y * 9.0 - n.y * 4.5, col]
			svg += "<text x=\"%.1f\" y=\"%.1f\" font-size=\"9\" fill=\"%s\">%s %.2f s</text>\n" % [e.x + 5.0, e.y + 10.0, ink, String(st["tip"]).replace("_", " "), float(st["t1"])]
		for stp in f["steps"]:
			var poly := foot_poly(stp["heel"], stp["toe"])
			var pp := ""
			for v in poly:
				var q := to_px(fx, b, v)
				pp += "%.1f,%.1f " % [q.x, q.y]
			var c := to_px(fx, b, stp["pos"])
			svg += "<polygon points=\"%s\" fill=\"%s\" fill-opacity=\"0.55\" stroke=\"%s\" stroke-width=\"1.2\"/>\n" % [pp, col, ink]
			svg += "<text x=\"%.1f\" y=\"%.1f\" font-size=\"11\" font-weight=\"700\" fill=\"%s\">%d</text><text x=\"%.1f\" y=\"%.1f\" font-size=\"9\" fill=\"%s\">%.2f s</text>\n" % [c.x - 3.0, c.y + 4.0, ink, int(stp["n"]), c.x + 8.0, c.y + 14.0, ink, float(stp["t"])]
	# the scale bar: 100 cm
	var sb := Vector2(14.0, H - 14.0)
	svg += "<line x1=\"%.1f\" y1=\"%.1f\" x2=\"%.1f\" y2=\"%.1f\" stroke=\"%s\" stroke-width=\"3\"/><text x=\"%.1f\" y=\"%.1f\" font-size=\"10\" fill=\"%s\">100 cm</text>\n" % [sb.x, sb.y, sb.x + s, sb.y, ink, sb.x + s + 4.0, sb.y + 3.0, ink]
	return svg + "</svg>\n"


static func to_html(plan: Dictionary, title: String, png_name: String) -> String:
	var h := "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><title>Floor plan - %s</title>\n<style>\n" % _esc(title)
	h += "body{font:14px/1.45 system-ui,Segoe UI,sans-serif;margin:24px auto;max-width:960px;color:#1b1d22;background:#fff}\n"
	h += "h1{font-size:22px;margin:0 0 4px}h2{font-size:16px;margin:18px 0 6px}.sub{color:#555;margin:0 0 12px}\n"
	h += "table{border-collapse:collapse;font-size:13px}td,th{border:1px solid #bbc;padding:2px 8px;text-align:left}.sw{display:inline-block;width:12px;height:12px;margin-right:6px;border:1px solid #333}\n"
	h += ".red{color:#b71c1c}.amber{color:#9a5b00}.note{color:#555;font-size:12px;margin-top:18px}\n@media print{body{margin:8mm}svg{max-width:100%;height:auto}}\n</style></head><body>\n"
	h += "<h1>Floor plan - %s</h1>\n<p class=\"sub\">%s. Top view, grid 100 cm. The picture is also saved as %s.</p>\n" % [_esc(title), _esc(summary(plan)), _esc(png_name)]
	h += to_svg(plan)
	for f in plan["fighters"]:
		h += "<h2><span class=\"sw\" style=\"background:%s\"></span>%s</h2>\n" % [_hex(String(f["color"])), _esc(String(f["name"]))]
		h += "<table><tr><th>No.</th><th>Foot</th><th>From</th><th>To</th><th>Where (x, z)</th></tr>\n"
		for s in f["steps"]:
			h += "<tr><td>%d</td><td>%s</td><td>%.2f s</td><td>%.2f s</td><td>%s, %s</td></tr>\n" % [int(s["n"]), s["foot"], float(s["t"]), float(s["t1"]), Units.len(s["pos"].x), Units.len(s["pos"].y)]
		h += "</table>\n<p class=\"note\">%s</p>\n" % ("The footprints are the scene's foot plants." if f["from_plants"] else "The scene has no foot plants: the footprints are read from sole contact (sole within 3 cm of the floor, moving under 0.25 m/s, for at least 0.1 s).")
		for st in f["strikes"]:
			h += "<div>Strike at %.2f s: %s travels %.2f m from the wind-up (%.2f s).</div>\n" % [float(st["t1"]), String(st["tip"]).replace("_", " "), float(st["len"]), float(st["t0"])]
	if not (plan["safety"] as Array).is_empty():
		h += "<h2>Safety margins (from the safety sheet)</h2>\n"
		for sf in plan["safety"]:
			h += "<div class=\"%s\">%.2f s - %s</div>\n" % [sf["sev"], float(sf["t"]), _esc(String(sf["text"]))]
	h += "<p class=\"note\">The 15 cm and 10 cm rings are the safety sheet's heuristics, not a safety standard. Paths are the centre of mass on the floor, a dot each second. Footprints are the sole outline at the start of the placement.</p>\n"
	return h + "</body></html>\n"
