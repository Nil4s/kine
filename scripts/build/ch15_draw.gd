extends RefCounted
## CH15: the three drawings as Blueprint sheets (scripts/build/blueprint.gd's entity format: paper mm, y down, the same SVG / PNG writers and the same
## title block): the SITE PLAN (1:2500, plant grid, plant north up, true north arrow), the REACTOR BUILDING SECTION (1:400, the cut on the plant z = 0 plane)
## and the ELECTRICAL ONE-LINE diagram (not to scale), drawn from ch15_plant.gd's one_line() model so every bus has its kV and every transformer its MVA.
const P := preload("res://scripts/build/ch15_plant.gd")
const S := preload("res://scripts/build/ch15_site.gd")
const PT := preload("res://scripts/build/ch15_parts.gd")
const B := preload("res://scripts/build/blueprint.gd")
const TRUE_NORTH := 47.0   # deg: true north is this far counter-clockwise of plant north (docs/CH15_REFERENCE.md section 6)
const NAME := "Angra 2 class PWR, 1350 MWe (CH15)"


static func _circle(c: Vector2, r: float, n := 72) -> Array:
	var out := []
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func _arcpts(c: Vector2, r: float, a0: float, a1: float, n := 36) -> Array:
	var out := []
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func _polyline(pts: Array, cls: String) -> Array:
	var out := []
	for i in pts.size() - 1:
		out.append(B._line(pts[i], pts[i + 1], cls))
	return out


## the frame + title block, with this sheet's own title and scale text
static func _frame(title: String, denom: int, idx: int) -> Array:
	var ents: Array = B._frame({"name": NAME}, "Site", "A3", maxi(denom, 1), idx, 3)
	for e in ents:
		if e["t"] == "text" and e["d"].get("field", "") == "sheet":
			e["s"] = title
		if e["t"] == "text" and e["d"].get("field", "") == "scale" and denom <= 0:
			e["s"] = "NTS"
	return ents


static func _sheet(title: String, denom: int, ents: Array, idx: int) -> Dictionary:
	var P3 := B.paper_size("A3")
	var area: Rect2 = B._area("A3")
	var bb := B._bounds(ents)
	ents = B._shift(ents, area.get_center() - bb.get_center())
	ents.append_array(_frame(title, denom, idx))
	return {"paper": "A3", "w": P3.x, "h": P3.y, "denom": denom, "k": 1000.0 / float(denom) if denom > 0 else 0.0, "tab": title, "title": title, "name": NAME, "ents": ents, "area": area}


static func sheet(nm: String, opts := {}) -> Dictionary:
	match nm:
		"site":
			return site_sheet()
		"section":
			return section_sheet()
	return oneline_sheet(opts.get("model", P.one_line()))


# ---------------------------------------------------------------- site plan
static func site_sheet() -> Dictionary:
	var denom := 2500
	var k := 1000.0 / denom
	var asm := S.assembly()
	var ents := []
	var pp := func(x: float, z: float) -> Vector2: return Vector2(x, z) * k
	for b in S.buildings(asm):
		var fp := S.footprint(b)
		var bb: AABB = fp["box"]
		var nm := String(b["name"])
		var c: Vector2 = pp.call(bb.get_center().x, bb.get_center().z)
		if nm == "Reactor building":
			ents.append(B._poly(_circle(c, PT.R_SHIELD * k), "elev-wall", {"bld": nm}))
			ents.append(B._poly(_circle(c, PT.R_SPH * k), "dashed", {"bld": nm}))
			ents.append_array(B._dim(c + Vector2(-PT.R_SHIELD * k, 0), c + Vector2(PT.R_SHIELD * k, 0), Vector2(0, -1), PT.R_SHIELD * k + 6.0, "D %s" % B._m2(fp["w"]), {"bld": nm}))
		else:
			var a: Vector2 = pp.call(bb.position.x, bb.position.z)
			var e: Vector2 = pp.call(bb.end.x, bb.end.z)
			ents.append(B._poly([a, Vector2(e.x, a.y), e, Vector2(a.x, e.y)], "elev-wall", {"bld": nm}))
			ents.append_array(B._dim(a, Vector2(e.x, a.y), Vector2(0, -1), 4.0, B._m2(fp["w"]), {"bld": nm}))
			ents.append_array(B._dim(Vector2(e.x, a.y), e, Vector2(1, 0), 4.0, B._m2(fp["d"]), {"bld": nm}))
		var below := nm != "Reactor building" and float(fp["w"]) < 45.0   # a small block's name goes under it (it does not fit inside at 1:2500)
		ents.append(B._text(c + (Vector2(0, float(fp["d"]) * k / 2.0 + 3.0) if below else Vector2(0, 1.0)), nm, 1.8 if below else 2.0, "m", "text", {"bld": nm}))
	# the primary loops' places and the turbine axis, light
	var th: Dictionary = S.REF["Turbine hall"]
	ents.append(B._line(pp.call(PT.R_SHIELD, float(th["pos"][1])), pp.call(float(th["pos"][0]) + 46.5, float(th["pos"][1])), "dashed"))
	# shoreline (ASSUMED trace from the satellite view): the sea is south-west of the plant
	ents.append_array(_polyline([pp.call(-130, 140), pp.call(-40, 120), pp.call(20, 130), pp.call(90, 175), pp.call(130, 230)], "ground"))
	ents.append(B._text(pp.call(-40, 175), "Itaorna bay (sea)", 2.5, "m", "text"))
	# true north arrow and a scale bar
	var na: Vector2 = pp.call(-110, -260)
	var dir := Vector2(0, -1).rotated(-deg_to_rad(TRUE_NORTH))
	ents.append(B._line(na, na + dir * 14.0, "north"))
	ents.append(B._poly([na + dir * 16.0, na + dir * 11.0 + dir.orthogonal() * 2.0, na + dir * 11.0 - dir.orthogonal() * 2.0], "north-head"))
	ents.append(B._text(na + dir * 19.0, "N (true)", 2.5, "m", "text"))
	ents.append(B._text(na + Vector2(0, 6), "plant north = up; true north 47 deg left", 2.0, "m", "text"))
	var sb: Vector2 = pp.call(-110, -300)
	ents.append(B._line(sb, sb + Vector2(100 * k, 0), "dim"))
	ents.append(B._text(sb + Vector2(50 * k, -1.5), "100 m", 2.5, "m", "dim-text"))
	ents.append(B._text(pp.call(80, -330), "SITE PLAN (plant grid, metres; footprints of SEEN buildings measured on Esri World Imagery z17)", 3.0, "m", "text"))
	return _sheet("Site plan", denom, ents, 1)


# ---------------------------------------------------------------- reactor building section (plant z = 0, seen from +z: x right, y up)
static func section_sheet() -> Dictionary:
	var denom := 400
	var k := 1000.0 / denom
	var pp := func(x: float, y: float) -> Vector2: return Vector2(x, -y) * k
	var ents := []
	# ground and the pit
	ents.append_array(_polyline([pp.call(-60, 0), pp.call(-40, 0), pp.call(-40, PT.Y_PIT), pp.call(40, PT.Y_PIT), pp.call(40, 0), pp.call(60, 0)], "ground"))
	# base mat (cut)
	ents.append(B._poly([pp.call(-37, PT.Y_PIT), pp.call(37, PT.Y_PIT), pp.call(37, PT.Y_MAT), pp.call(-37, PT.Y_MAT)], "wall", {"part": "mat"}))
	# shield walls (cut) and dome (cut, as two arcs)
	for sx in [-1.0, 1.0]:
		var xo: float = sx * PT.R_SHIELD
		var xi: float = sx * (PT.R_SHIELD - PT.T_SHIELD)
		ents.append(B._poly([pp.call(xo, PT.Y_MAT), pp.call(xi, PT.Y_MAT), pp.call(xi, PT.Y_WALL_TOP), pp.call(xo, PT.Y_WALL_TOP)], "wall", {"part": "shield wall"}))
	var dc: Vector2 = pp.call(0, PT.Y_WALL_TOP)
	var dome := _arcpts(dc, PT.R_SHIELD * k, PI, TAU) + _arcpts(dc, (PT.R_SHIELD - PT.T_SHIELD) * k, TAU, PI)
	ents.append(B._poly(dome, "wall", {"part": "dome"}))
	# steel sphere (cut, 30 mm: a line at this scale)
	ents.append(B._poly(_circle(pp.call(0, PT.Y_SPH), PT.R_SPH * k, 144), "piece", {"part": "steel sphere"}))
	# fill (the bowl up to +2) and the internal concrete: cavity walls and deck
	var rf := sqrt(pow(PT.R_SPH, 2) - pow(PT.Y_SPH - PT.Y_FILL, 2))
	var bowl := _arcpts(pp.call(0, PT.Y_SPH), PT.R_SPH * k, PI - asin((PT.Y_SPH - PT.Y_FILL) / PT.R_SPH), asin((PT.Y_SPH - PT.Y_FILL) / PT.R_SPH), 48)
	ents.append(B._poly([pp.call(-rf, PT.Y_FILL)] + bowl.slice(0, bowl.size()) + [pp.call(rf, PT.Y_FILL)], "elev-wall", {"part": "fill"}))
	for sx in [-1.0, 1.0]:
		ents.append(B._poly([pp.call(sx * 3.3, PT.Y_FILL), pp.call(sx * 6.0, PT.Y_FILL), pp.call(sx * 6.0, PT.Y_DECK + 1.0), pp.call(sx * 3.3, PT.Y_DECK + 1.0)], "wall", {"part": "cavity"}))
		ents.append(B._poly([pp.call(sx * 6.0, PT.Y_DECK), pp.call(sx * 24.0, PT.Y_DECK), pp.call(sx * 24.0, PT.Y_DECK + 1.0), pp.call(sx * 6.0, PT.Y_DECK + 1.0)], "wall", {"part": "deck"}))
	# vessel (cut on its axis)
	ents.append(B._poly([pp.call(-PT.RPV_R, PT.Y_FILL), pp.call(PT.RPV_R, PT.Y_FILL), pp.call(PT.RPV_R, PT.Y_FILL + 9.25)] + _arcpts(pp.call(0, PT.Y_FILL + 9.25), PT.RPV_R * k, TAU, PI, 24) + [pp.call(-PT.RPV_R, PT.Y_FILL + 9.25)], "elev-door", {"part": "vessel"}))
	# the SGs, pumps, pressurizer beyond the cut (behind, z < 0), projected
	for kk in 4:
		var c := PT.at_az(PT.R_SG, PT.LOOP_AZ[kk])
		if c.y > 0.0:
			continue
		var x := c.x
		ents.append(B._poly([pp.call(x - 1.9, PT.Y_FILL), pp.call(x + 1.9, PT.Y_FILL), pp.call(x + 1.9, PT.Y_FILL + 12), pp.call(x + PT.SG_R, PT.Y_FILL + 13.5), pp.call(x + PT.SG_R, PT.Y_FILL + 19)]
			+ _arcpts(pp.call(x, PT.Y_FILL + 19), PT.SG_R * k, TAU, PI, 18) + [pp.call(x - PT.SG_R, PT.Y_FILL + 13.5), pp.call(x - 1.9, PT.Y_FILL + 12)], "piece", {"part": "SG %d" % (kk + 1)}))
		ents.append(B._text(pp.call(x, PT.Y_FILL + 23.5), "SG %d" % (kk + 1), 2.0, "m", "text"))
		var r := PT.at_az(PT.R_RCP, PT.LOOP_AZ[kk] + PT.RCP_DAZ)
		ents.append(B._poly([pp.call(r.x - PT.RCP_R, PT.Y_FILL), pp.call(r.x + PT.RCP_R, PT.Y_FILL), pp.call(r.x + PT.RCP_R, PT.Y_FILL + 9), pp.call(r.x - PT.RCP_R, PT.Y_FILL + 9)], "dashed", {"part": "RCP %d" % (kk + 1)}))
	# polar crane
	ents.append(B._poly([pp.call(-25, 30), pp.call(25, 30), pp.call(25, 32.5), pp.call(-25, 32.5)], "piece", {"part": "polar crane"}))
	ents.append(B._text(pp.call(0, 34.5), "polar crane", 2.0, "m", "text"))
	ents.append(B._text(pp.call(0, PT.Y_FILL + 3.5), "RPV", 2.0, "m", "text"))
	ents.append(B._text(pp.call(0, 42), "steel sphere 56 m, 30 mm WStE 51", 2.0, "m", "text"))
	ents.append(B._text(pp.call(-18, PT.Y_DECK + 2.0), "operating deck +15.50", 2.0, "m", "text"))
	# levels on the right
	for lv in [[PT.Y_PIT, "-9.00 excavation"], [PT.Y_MAT, "-6.00 mat top"], [0.0, "+0.00 grade"], [PT.Y_FILL, "+2.00 fill"], [PT.Y_SPH, "+22.00 sphere centre"],
			[PT.Y_WALL_TOP, "+24.25 dome springing"], [PT.Y_SPH + PT.R_SPH, "+50.00 sphere top"], [PT.Y_WALL_TOP + PT.R_SHIELD, "+60.00 dome top"]]:
		var y: float = lv[0]
		ents.append(B._line(pp.call(38, y), pp.call(47, y), "level"))
		ents.append(B._text(pp.call(47.5, y) + Vector2(0, 0.8), String(lv[1]), 2.0, "l", "text"))
	# dimensions
	ents.append_array(B._dim(pp.call(-PT.R_SHIELD, 0), pp.call(PT.R_SHIELD, 0), Vector2(0, 1), 12.0, B._m2(2 * PT.R_SHIELD)))
	ents.append_array(B._dim(pp.call(-PT.R_SPH, PT.Y_SPH), pp.call(PT.R_SPH, PT.Y_SPH), Vector2(0, -1), 3.0, B._m2(2 * PT.R_SPH)))
	ents.append_array(B._dim(pp.call(-PT.R_SHIELD, 0), pp.call(-PT.R_SHIELD, PT.Y_WALL_TOP + PT.R_SHIELD), Vector2(-1, 0), 8.0, B._m2(PT.Y_WALL_TOP + PT.R_SHIELD)))
	ents.append_array(B._dim(pp.call(-37, PT.Y_PIT), pp.call(-37, PT.Y_MAT), Vector2(-1, 0), 4.0, B._m2(PT.MAT_T)))
	ents.append_array(B._dim(pp.call(PT.R_SHIELD - PT.T_SHIELD, 10), pp.call(PT.R_SHIELD, 10), Vector2(0, -1), 3.0, B._m2(PT.T_SHIELD)))
	ents.append(B._text(pp.call(0, -16), "SECTION A-A through the reactor building (plant z = 0, seen from plant south)", 3.0, "m", "text"))
	return _sheet("Reactor building section A-A", denom, ents, 2)


# ---------------------------------------------------------------- one-line diagram (paper mm directly, not to scale)
static func _fmt(v: float) -> String:
	return String.num(v)


static func _bus(ents: Array, a: Vector2, b: Vector2, bus: Dictionary) -> void:
	ents.append(B._line(a, b, "border"))
	ents.append(B._text(a + Vector2(0, -1.5), "%s  %s kV" % [bus["id"], _fmt(bus["kv"])], 2.2, "l", "title-text", {"bus": bus["id"]}))


static func _xfmr(ents: Array, top: Vector2, xf: Dictionary) -> Vector2:
	ents.append(B._poly(_circle(top + Vector2(0, 3.0), 3.0, 36), "piece", {"xf": xf["id"]}))
	ents.append(B._poly(_circle(top + Vector2(0, 7.0), 3.0, 36), "piece", {"xf": xf["id"]}))
	ents.append(B._text(top + Vector2(4.5, 4.0), "%s %s MVA" % [xf["id"], _fmt(xf["mva"])], 2.0, "l", "text", {"xf": xf["id"]}))
	ents.append(B._text(top + Vector2(4.5, 7.0), "%s/%s kV" % [_fmt(xf["hv"]), _fmt(xf["lv"])], 1.8, "l", "title-label", {"xf": xf["id"]}))
	return top + Vector2(0, 10.0)


static func _breaker(ents: Array, c: Vector2, label := "") -> void:
	ents.append(B._poly([c + Vector2(-1.5, -1.5), c + Vector2(1.5, -1.5), c + Vector2(1.5, 1.5), c + Vector2(-1.5, 1.5)], "piece"))
	if label != "":
		ents.append(B._text(c + Vector2(2.5, 0.8), label, 1.8, "l", "title-label"))


static func _gen(ents: Array, c: Vector2, g: Dictionary) -> void:
	ents.append(B._poly(_circle(c, 4.0, 36), "piece", {"gen": g["id"]}))
	ents.append(B._text(c + Vector2(0, 1.0), "G" if g["id"] == "G" else "D", 2.5, "m", "text"))
	ents.append(B._text(c + Vector2(0, 7.5), "%s %s MVA" % [g["id"], _fmt(g["mva"])], 1.8, "m", "text", {"gen": g["id"]}))


static func oneline_sheet(m: Dictionary) -> Dictionary:
	var ents := []
	var bus := {}
	for b in m["buses"]:
		bus[b["id"]] = b
	var xf := {}
	for x in m["xfmrs"]:
		xf[x["id"]] = x
	var gens := {}
	for g in m["gens"]:
		gens[g["id"]] = g
	# 500 kV grid bus at the top, the 138 kV line at the right
	_bus(ents, Vector2(40, 30), Vector2(200, 30), bus["GRID500"])
	_bus(ents, Vector2(250, 30), Vector2(340, 30), bus["GRID138"])
	# main transformer chain: grid -> breaker -> MT -> generator bus -> GCB -> generator
	ents.append(B._line(Vector2(110, 30), Vector2(110, 38), "dim"))
	_breaker(ents, Vector2(110, 40), "500 kV breaker")
	ents.append(B._line(Vector2(110, 41.5), Vector2(110, 46), "dim"))
	var b1 := _xfmr(ents, Vector2(110, 46), xf["MT"])
	_bus(ents, Vector2(60, b1.y + 6), Vector2(230, b1.y + 6), bus["GEN"])
	ents.append(B._line(b1, Vector2(110, b1.y + 6), "dim"))
	ents.append(B._line(Vector2(110, b1.y + 6), Vector2(110, b1.y + 12), "dim"))
	_breaker(ents, Vector2(110, b1.y + 14), "generator breaker 25 kV")
	ents.append(B._line(Vector2(110, b1.y + 15.5), Vector2(110, b1.y + 20), "dim"))
	_gen(ents, Vector2(110, b1.y + 24), gens["G"])
	ents.append(B._text(Vector2(110, b1.y + 35), "1350 MW, cos phi 0.9, 1800 rpm, 60 Hz", 1.8, "m", "title-label"))
	# unit auxiliary transformers from the generator bus (left of the GCB), standby from 138 kV
	var ybus := b1.y + 50.0
	var xs := {"BA": 40.0, "BB": 115.0, "BC": 190.0, "BD": 265.0}
	for pair in [["UAT1", 60.0], ["UAT2", 210.0]]:
		var x0: float = pair[1]
		ents.append(B._line(Vector2(x0, b1.y + 6), Vector2(x0, b1.y + 16), "dim"))
		var bot := _xfmr(ents, Vector2(x0, b1.y + 16), xf[pair[0]])
		var to := String(xf[pair[0]]["to"])
		ents.append(B._line(bot, Vector2(x0, ybus), "dim"))   # drops straight onto its bus (BA at 40..95, BC at 190..245)
	ents.append(B._line(Vector2(295, 30), Vector2(295, 46), "dim"))
	var sbot := _xfmr(ents, Vector2(295, 46), xf["SST"])
	ents.append(B._line(sbot, Vector2(295, ybus), "dim"))   # onto BD (265..320)
	for id in ["BA", "BB", "BC", "BD"]:
		_bus(ents, Vector2(xs[id], ybus), Vector2(float(xs[id]) + 55.0, ybus), bus[id])
	# bus ties BA-BB, BC-BD
	for t in [["BA", "BB"], ["BC", "BD"]]:
		var xa: float = float(xs[t[0]]) + 55.0
		var xb: float = xs[t[1]]
		ents.append(B._line(Vector2(xa, ybus), Vector2(xb, ybus), "dashed"))
		_breaker(ents, Vector2((xa + xb) / 2.0, ybus), "")
	# emergency buses one per train, fed from the normal bus above and from its diesel
	var ysafe := ybus + 30.0
	var trains := [["BA", "BU"], ["BB", "BV"], ["BC", "BW"], ["BD", "BX"]]
	for k in 4:
		var nb: String = trains[k][0]
		var sbid: String = trains[k][1]
		var x0: float = float(xs[nb]) + 10.0
		ents.append(B._line(Vector2(x0, ybus), Vector2(x0, ysafe), "dim"))
		_breaker(ents, Vector2(x0, (ybus + ysafe) / 2.0), "")
		_bus(ents, Vector2(xs[nb], ysafe), Vector2(float(xs[nb]) + 55.0, ysafe), bus[sbid])
		var dg: Dictionary = gens["DG%d" % (k + 1)]
		var xd: float = float(xs[nb]) + 30.0
		ents.append(B._line(Vector2(xd, ysafe), Vector2(xd, ysafe + 8), "dim"))
		_breaker(ents, Vector2(xd, ysafe + 9.5), "")
		ents.append(B._line(Vector2(xd, ysafe + 11), Vector2(xd, ysafe + 14), "dim"))
		_gen(ents, Vector2(xd, ysafe + 18), dg)
		ents.append(B._text(Vector2(xd, ysafe + 28.5), "%s MW" % _fmt(dg["mw"]), 1.8, "m", "title-label"))
		# load centre transformer to the D2 bus with its D2 diesel
		var lt: Dictionary = xf["LT%d" % (k + 1)]
		var xl: float = float(xs[nb]) + 48.0
		ents.append(B._line(Vector2(xl, ysafe), Vector2(xl, ysafe + 4), "dim"))
		var lb := _xfmr(ents, Vector2(xl, ysafe + 4), lt)
		var yd2 := ysafe + 42.0
		ents.append(B._line(lb, Vector2(xl, yd2), "dim"))
		_bus(ents, Vector2(float(xs[nb]) + 30.0, yd2), Vector2(float(xs[nb]) + 62.0, yd2), bus["D2_%d" % (k + 1)])
		var g2: Dictionary = gens["D2G%d" % (k + 1)]
		ents.append(B._line(Vector2(xl - 8, yd2), Vector2(xl - 8, yd2 + 6), "dim"))
		_gen(ents, Vector2(xl - 8, yd2 + 10), g2)
	ents.append(B._text(Vector2(40, ysafe + 70), "Safety trains: 4 x 50 pct (any 2 of 4 carry the safety load: N+2). Diesels system 1: 4 x 5.4 MW / 6.6 MVA at 10 kV; system 2 (bunkered emergency feed): 4 x 0.86 MW at 0.4 kV.", 2.0, "l", "text"))
	ents.append(B._text(Vector2(40, ysafe + 74), "House load 70 MW (1350 - 1280) = 82.35 MVA at pf 0.85 <= 2 x 50 MVA unit auxiliary, <= 90 MVA standby. Values marked ASSUMED in docs/CH15_REFERENCE.md: MT, UAT, SST, LT, GCB.", 2.0, "l", "text"))
	return _sheet("Electrical one-line diagram", 0, ents, 3)


## the buses / transformers of the model whose voltage / MVA text is NOT on the sheet (bar 9)
static func oneline_missing(m: Dictionary, sh: Dictionary) -> Array:
	var texts := {}
	for e in sh["ents"]:
		if e["t"] == "text":
			texts[String(e["s"])] = true
	var miss := []
	for b in m["buses"]:
		if not texts.has("%s  %s kV" % [b["id"], _fmt(b["kv"])]):
			miss.append(String(b["id"]))
	for x in m["xfmrs"]:
		if float(x["mva"]) <= 0.0 or not texts.has("%s %s MVA" % [x["id"], _fmt(x["mva"])]):
			miss.append(String(x["id"]))
	return miss


## a sheet as a PNG (ppm pixels per paper mm), painted by BlueprintView in a SubViewport
static func render_png(root: Node, sh: Dictionary, ppm: float) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(int(float(sh["w"]) * ppm), int(float(sh["h"]) * ppm))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	var bv := BlueprintView.new()
	bv.sheet = sh
	bv.ppm = ppm
	bv.size = Vector2(vp.size)
	vp.add_child(bv)
	root.add_child(vp)
	for i in 4:
		await root.get_tree().process_frame
	var im := vp.get_texture().get_image()
	vp.queue_free()
	return im
