extends RefCounted
## CH16 A3 sheets through CH15's Blueprint entity/title-block/SVG/PNG path. Dimensions are generated from ch16_parts constants;
## the electrical diagram is generated from ch16_electronics so a missing IC/rail label is testable.
const P := preload("res://scripts/build/ch16_parts.gd")
const E := preload("res://scripts/build/ch16_electronics.gd")
const B := preload("res://scripts/build/blueprint.gd")
const NAME := "Sony a7 / ILCE-7 class camera (CH16)"


static func _circle(c: Vector2, r: float, n := 64) -> Array:
	var out: Array = []
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func _rect(c: Vector2, w: float, h: float, cls := "piece", data := {}) -> Dictionary:
	return B._poly([c + Vector2(-w / 2, -h / 2), c + Vector2(w / 2, -h / 2), c + Vector2(w / 2, h / 2), c + Vector2(-w / 2, h / 2)], cls, data)


static func _frame(title: String, denom: int, idx: int) -> Array:
	var ents: Array = B._frame({"name": NAME}, "Front", "A3", maxi(denom, 1), idx, 2)
	for e in ents:
		if e["t"] == "text" and e["d"].get("field", "") == "sheet":
			e["s"] = title
		if e["t"] == "text" and e["d"].get("field", "") == "scale" and denom <= 0:
			e["s"] = "NTS"
	return ents


static func _sheet(title: String, denom: int, ents: Array, idx: int, centre := true) -> Dictionary:
	var size := B.paper_size("A3")
	var area: Rect2 = B._area("A3")
	if centre:
		var bb := B._bounds(ents)
		ents = B._shift(ents, area.get_center() - bb.get_center())
	ents.append_array(_frame(title, denom, idx))
	return {"paper": "A3", "w": size.x, "h": size.y, "denom": denom, "k": 1000.0 / float(denom) if denom > 0 else 0.0,
		"tab": title, "title": title, "name": NAME, "ents": ents, "area": area}


static func blueprint_sheet() -> Dictionary:
	var ents: Array = []
	var k := 0.5                                                # model mm -> paper mm at 1:2
	# FRONT, model X right / Y up
	var fc := Vector2(85, 126)
	ents.append(_rect(fc, P.W * k, P.H * k, "elev-wall", {"view": "front"}))
	ents.append(B._poly(_circle(fc + Vector2(0, (39.0 - P.H / 2.0) * k), 28.0 * k), "piece", {"part": "mount"}))
	ents.append(B._poly(_circle(fc + Vector2(0, (39.0 - P.H / 2.0) * k), P.THROAT_D / 2.0 * k), "dashed", {"part": "throat"}))
	var sc := fc + Vector2(0, (39.0 - P.H / 2.0) * k)
	ents.append(_rect(sc, P.SENSOR_W * k, P.SENSOR_H * k, "dashed", {"part": "sensor"}))
	ents.append_array(B._dim(fc + Vector2(-P.W * k / 2, P.H * k / 2), fc + Vector2(P.W * k / 2, P.H * k / 2), Vector2(0, 1), 7.0, "126.9 mm"))
	ents.append_array(B._dim(fc + Vector2(-P.W * k / 2, -P.H * k / 2), fc + Vector2(-P.W * k / 2, P.H * k / 2), Vector2(-1, 0), 8.0, "94.4 mm"))
	ents.append_array(B._dim(sc + Vector2(-P.SENSOR_W * k / 2, -P.SENSOR_H * k / 2), sc + Vector2(P.SENSOR_W * k / 2, -P.SENSOR_H * k / 2), Vector2(0, 1), 25.0, "35.8 mm sensor"))
	ents.append_array(B._dim(sc + Vector2(P.SENSOR_W * k / 2, -P.SENSOR_H * k / 2), sc + Vector2(P.SENSOR_W * k / 2, P.SENSOR_H * k / 2), Vector2(1, 0), 25.0, "23.9 mm"))
	ents.append(B._text(fc + Vector2(0, -P.H * k / 2 - 10), "FRONT", 3.0, "m", "title-text"))
	ents.append(B._text(fc + Vector2(0, P.H * k / 2 + 14), "Sensor active area 35.8 x 23.9 mm", 2.1, "m", "text"))
	# TOP, model X right / Z down the paper (front at the bottom)
	var tc := Vector2(85, 49)
	ents.append(_rect(tc, P.W * k, P.D_MAX * k, "elev-wall", {"view": "top"}))
	ents.append(B._line(tc + Vector2(-P.W * k / 2, -P.D_MAX * k / 2), tc + Vector2(P.W * k / 2, -P.D_MAX * k / 2), "dashed"))
	for x in [-45.0, 45.0]:
		ents.append(B._poly(_circle(tc + Vector2(x * k, 5.0), 11.0 * k), "piece"))
	ents.append(_rect(tc + Vector2(0, 5), 20.0 * k, 15.0 * k, "piece", {"part": "hot shoe"}))
	ents.append_array(B._dim(tc + Vector2(-P.W * k / 2, -P.D_MAX * k / 2), tc + Vector2(-P.W * k / 2, P.D_MAX * k / 2), Vector2(-1, 0), 8.0, "54.8 mm max"))
	ents.append_array(B._dim(tc + Vector2(P.W * k / 2, 0), tc + Vector2(P.W * k / 2, P.D_MAX * k / 2), Vector2(1, 0), 18.0, "48.2 mm body"))
	ents.append(B._text(tc + Vector2(0, -P.D_MAX * k / 2 - 6), "TOP", 3.0, "m", "title-text"))
	# SECTION on the optical axis: horizontal is depth, vertical is Y. Front/mount is at the right.
	var xc := Vector2(260, 128)
	var z0 := xc.x + P.D_MAX * k / 2                              # mount face Z=0
	var pp := func(z: float, y: float) -> Vector2: return Vector2(z0 + z * k, xc.y - (y - P.H / 2.0) * k)
	ents.append(B._line(pp.call(-P.D_MAX, 0), pp.call(0, 0), "ground"))
	ents.append(B._line(pp.call(-P.D_MAX, P.H), pp.call(0, P.H), "ground"))
	ents.append(B._line(pp.call(0, 0), pp.call(0, P.H), "elev-wall"))
	ents.append(B._line(pp.call(-P.D_MAX, 0), pp.call(-P.D_MAX, P.H), "elev-wall"))
	# sensor/shutter/PCB/LCD stack, cut solids heavy, beyond outlines light
	var leaders: Array = []
	for row in [[-23.5, -22.3, 22.0, 56.0, "SHUTTER"], [-21.5, -20.0, 26.0, 52.0, "COVER GLASS"], [-18.35, -18.0, 27.05, 50.95, "SENSOR"], [-45.8, -44.6, 12.0, 70.0, "MAIN PCB"], [-54.8, -50.6, 12.0, 66.0, "LCD"]]:
		var za: float = row[0]
		var zb: float = row[1]
		var ya: float = row[2]
		var yb: float = row[3]
		var a: Vector2 = pp.call(za, ya)
		var b: Vector2 = pp.call(zb, yb)
		var c := (a + b) / 2.0
		ents.append(_rect(c, absf(b.x - a.x), absf(b.y - a.y), "wall" if String(row[4]) == "SENSOR" else "piece", {"part": row[4]}))
		leaders.append([c, String(row[4])])
	for i in leaders.size():
		var c: Vector2 = leaders[i][0]
		var label := Vector2(310, 100.0 + i * 18.0)
		ents.append(B._line(c, label + Vector2(-3, 0), "dim"))
		ents.append(B._text(label, String(leaders[i][1]), 2.0, "l", "text"))
	# flange dimension on a long offset below the stack; the label is clear of the section title and part leaders
	var mface: Vector2 = pp.call(0, 39)
	var splane: Vector2 = pp.call(-P.FLANGE, 39)
	ents.append_array(B._dim(splane, mface, Vector2(0, 1), 48.0, "18.00 mm"))
	ents.append(B._text(Vector2(260, 187), "FLANGE FOCAL DISTANCE", 2.0, "m", "text"))
	ents.append(B._text(xc + Vector2(0, -P.H * k / 2 - 12), "SECTION A-A: sensor / shutter / board stack", 3.0, "m", "title-text"))
	ents.append(B._text(Vector2(180, 205), "SEEN: Sony envelope, sensor, E-mount flange. Internal block envelopes and wall thicknesses: ASSUMED; see CH16_REFERENCE.", 2.2, "l", "text"))
	return _sheet("Dimensioned front, top and optical section", 2, ents, 1)


static func _block(ents: Array, c: Vector2, w: float, h: float, title: String, sub: String, data := {}) -> void:
	ents.append(_rect(c, w, h, "piece", data))
	ents.append(B._text(c + Vector2(0, -1), title, 2.3, "m", "title-text", data))
	ents.append(B._text(c + Vector2(0, 3), sub, 1.65, "m", "text", data))


static func electronics_sheet(m: Dictionary) -> Dictionary:
	var ents: Array = []
	_block(ents, Vector2(43, 42), 54, 20, "NP-FW50 BATTERY", "7.2 V; 1.020 Ah; 7.344 Wh", {"ic": "BATTERY"})
	_block(ents, Vector2(118, 42), 48, 20, "PROTECTION", "battery ID / fault", {"ic": "PROTECTION"})
	_block(ents, Vector2(188, 42), 46, 20, "PMIC", "8.00 W input budget", {"ic": "PMIC"})
	for x in [70, 142]:
		ents.append(B._line(Vector2(x, 42), Vector2(x + 24, 42), "border"))
	ents.append(B._line(Vector2(94, 42), Vector2(94, 42), "border"))
	ents.append(B._text(Vector2(24, 68), "CIPA 340 shots = 0.0216 Wh = 77.76 J/shot (SEEN inputs; hand arithmetic)", 2.0, "l", "text"))
	var ys: Array = []
	for i in (m["rails"] as Array).size():
		var r: Dictionary = m["rails"][i]
		var y := 88.0 + i * 30.0
		ys.append(y)
		var sub := "%.1f V  %.2f W" % [float(r["v"]), float(r["w"])]
		_block(ents, Vector2(160, y), 70, 18, String(r["reg"]), sub, {"rail": r["id"]})
		_block(ents, Vector2(300, y), 170, 18, "+".join(PackedStringArray(r["loads"])), "power + signal (see paths below)", {"rail_loads": r["id"]})
		ents.append(B._line(Vector2(195, y), Vector2(215, y), "border"))
		ents.append(B._line(Vector2(211, 52), Vector2(211, y), "dim"))
		ents.append(B._line(Vector2(211, y), Vector2(225, y), "dim"))
	# Signal chain is separate from the power tree, but every destination IC also appears on a powered row above.
	_block(ents, Vector2(60, 228), 70, 18, "CMOS SENSOR", "MIPI/LVDS image data", {"ic": "CMOS SENSOR"})
	_block(ents, Vector2(160, 228), 64, 18, "BIONZ X", "processor / control", {"ic": "BIONZ X"})
	_block(ents, Vector2(296, 228), 156, 18, "DRAM / SD / EVF / LCD / HDMI", "image buffer, storage and video outputs", {"ic": "DRAM"})
	ents.append(B._line(Vector2(95, 228), Vector2(128, 228), "border"))
	ents.append(B._line(Vector2(192, 228), Vector2(218, 228), "border"))
	ents.append(B._text(Vector2(35, 246), "USB D+/D- and Wi-Fi/NFC SDIO are bidirectional to BIONZ X; BIONZ X controls sensor timing and shutter H-bridge. RF goes to the separate antenna.", 1.8, "l", "text"))
	ents.append(B._text(Vector2(35, 253), "ASSUMED loads: 1.10 + 0.85 + 1.20 + 0.65 + 0.80 = 4.60 W; 4.60/0.90 = 5.11111 W; 12 s duty = 61.3333 J < 77.76 J.", 1.8, "l", "text"))
	return _sheet("Power and signal block diagram", 0, ents, 2, false)


static func sheet(nm: String, opts := {}) -> Dictionary:
	if nm == "blueprint":
		return blueprint_sheet()
	return electronics_sheet(opts.get("model", E.model()))


static func missing_labels(m: Dictionary, sh: Dictionary) -> Array:
	var text := ""
	for e in sh["ents"]:
		if e["t"] == "text":
			text += String(e["s"]) + "\n"
	var miss: Array = []
	for r in m["rails"]:
		var label := "%.1f V  %.2f W" % [float(r["v"]), float(r["w"])]
		if not text.contains(label):
			miss.append(String(r["id"]) + " rating")
	for ic in m["ics"]:
		var id := String(ic["id"])
		# USB/Wi-Fi/LCD/EVF/SD are named in the destination or signal rows; all others have their own block.
		var token: String = {"SD CARD": "SD", "WI-FI/NFC": "Wi-Fi/NFC", "OLED EVF": "EVF"}.get(id, id)
		if not text.contains(String(token)):
			miss.append(id)
	return miss


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
