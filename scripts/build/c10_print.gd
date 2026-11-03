## C10 PRINT HONESTY (complaints #371, #365, #296). Three small readers, no state:
##   layer_note   the print time a slicer shows is stretched when a layer is laid down faster than the minimum layer time (small cross-sections, thin
##                towers): the model says by how much, in plain words. Worked from the same numbers as the size label (volume, skin area, height).
##   verify_file  after an STL / 3MF export the file is read back from disk; its volume and its box are compared with the part's. OFF_PCT = 0.5.
##   SCREW_FIT    metric screw clearance table M2..M10: close / normal / loose hole across in mm (ISO 273 fine / medium / coarse), used by Cut a hole's Fit chip.
class_name C10Print
extends RefCounted

const LAYER_MM := 0.2         # a typical layer
const RATE_CM3_H := 20.0      # the size label's desktop rate (easy_part_layout._print_words)
const MIN_LAYER_S := 8.0      # a slicer's usual minimum layer time for PLA
const OFF_PCT := 0.5          # a re-read file that differs from the part by more than this is warned about

const FITS := ["close", "normal", "loose"]
## M -> [close, normal, loose] hole across, mm. normal for M3..M6 is what Cut a hole always cut; close = the resin hole, loose = the FDM hole
const SCREW_FIT := {2: [2.2, 2.4, 2.6], 3: [3.2, 3.4, 3.6], 4: [4.3, 4.5, 4.8], 5: [5.3, 5.5, 5.8], 6: [6.4, 6.6, 7.0], 8: [8.4, 9.0, 10.0], 10: [10.5, 11.0, 12.0]}
## ISO 4762 socket head: [across, high] mm, for the sizes PartTemplates.SCREW_HEAD does not hold
const HEAD_EXTRA := {2: [3.8, 2.0], 8: [13.0, 8.0], 10: [16.0, 10.0]}


static func clear(d: int, fit: String) -> float:
	return float((SCREW_FIT[d] as Array)[FITS.find(fit)])


static func head(d: int) -> Array:
	return HEAD_EXTRA[d] if HEAD_EXTRA.has(d) else PartTemplates.SCREW_HEAD[d]


## the minutes a minimum layer time adds, for a part of vol_m3 / area_m2 (as the size label counts them) and height_m: 0 when it adds none
static func slow_minutes(vol_m3: float, area_m2: float, height_m: float) -> int:
	if vol_m3 <= 0.0 or height_m <= 0.0:
		return 0
	var wall := minf(area_m2 * 0.0012, vol_m3)
	var cm3 := (wall + (vol_m3 - wall) * 0.2) * 1.0e6
	var layers := maxf(1.0, height_m * 1000.0 / LAYER_MM)
	var per := cm3 / RATE_CM3_H * 3600.0 / layers   # seconds a layer takes at the rate
	if per >= MIN_LAYER_S:
		return 0
	return roundi((MIN_LAYER_S - per) * layers / 60.0)


## "" when the slicer will not stretch it, else the plain words
static func layer_note(vol_m3: float, area_m2: float, height_m: float) -> String:
	var mins := slow_minutes(vol_m3, area_m2, height_m)
	if mins < 1:
		return ""
	var t := "%d min" % mins if mins < 60 else "%d h %d min" % [mins / 60, mins % 60]
	return " (slowed by minimum layer time: a slicer may add about %s)" % t


## signed volume and box of triangles given as vertex + index arrays, mm
static func _acc(acc: Dictionary, v: PackedVector3Array, t: PackedInt32Array) -> void:
	for i in range(0, t.size() - 2, 3):
		var a := v[t[i]]
		var b := v[t[i + 1]]
		var c := v[t[i + 2]]
		acc["vol"] = float(acc["vol"]) + a.dot(b.cross(c)) / 6.0
		for p in [a, b, c]:
			acc["box"] = (acc["box"] as AABB).expand(p) if acc["has"] else AABB(p, Vector3.ZERO)
			acc["has"] = true


static func _new() -> Dictionary:
	return {"vol": 0.0, "box": AABB(), "has": false}


## read the written file back: {"ok": read fine, "vol": mm3, "size": Vector3 mm}
static func read_file(path: String, fmt: String) -> Dictionary:
	var acc := _new()
	if fmt == "stl":
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			return {"ok": false}
		var buf := f.get_buffer(f.get_length())
		f.close()
		if buf.size() < 84:
			return {"ok": false}
		var n := buf.decode_u32(80)
		if buf.size() < 84 + n * 50:
			return {"ok": false}
		var v := PackedVector3Array()
		var t := PackedInt32Array()
		for k in n:
			var o := 84 + k * 50 + 12
			for j in 3:
				t.append(v.size())
				v.append(Vector3(buf.decode_float(o + j * 12), buf.decode_float(o + j * 12 + 4), buf.decode_float(o + j * 12 + 8)))
		_acc(acc, v, t)
	else:
		var z := ZIPReader.new()
		if z.open(path) != OK:
			return {"ok": false}
		var xml := z.read_file("3D/3dmodel.model")
		z.close()
		var p := XMLParser.new()
		if p.open_buffer(xml) != OK:
			return {"ok": false}
		var v := PackedVector3Array()
		var t := PackedInt32Array()
		while p.read() == OK:
			if p.get_node_type() == XMLParser.NODE_ELEMENT_END and p.get_node_name() == "mesh":
				_acc(acc, v, t)
				v = PackedVector3Array()
				t = PackedInt32Array()
			elif p.get_node_type() == XMLParser.NODE_ELEMENT:
				var nm := p.get_node_name()
				if nm == "vertex":
					v.append(Vector3(float(p.get_named_attribute_value("x")), float(p.get_named_attribute_value("y")), float(p.get_named_attribute_value("z"))))
				elif nm == "triangle":
					for a in ["v1", "v2", "v3"]:
						t.append(int(p.get_named_attribute_value(a)))
	if not bool(acc["has"]):
		return {"ok": false}
	return {"ok": true, "vol": absf(float(acc["vol"])), "size": (acc["box"] as AABB).size}


## re-read the file and compare with the bodies that were written: {"ok", "off": bool, "vol_pct", "size_pct", "text": "" when it matches}
static func verify_file(path: String, fmt: String, bodies: Array) -> Dictionary:
	var acc := _new()
	for b in bodies:
		_acc(acc, b["v"], b["t"])
	var got := read_file(path, fmt)
	if not bool(got["ok"]) or not bool(acc["has"]):
		return {"ok": false, "off": true, "vol_pct": 0.0, "size_pct": 0.0, "text": "WARN  the file could not be read back to check it. Open it in your slicer before you print"}
	var pv := absf(float(acc["vol"]))
	var ps: Vector3 = (acc["box"] as AABB).size
	var vp := absf(float(got["vol"]) - pv) / maxf(pv, 1e-9) * 100.0
	var sp := 0.0
	for k in 3:
		sp = maxf(sp, absf((got["size"] as Vector3)[k] - ps[k]) / maxf(ps[k], 1e-3) * 100.0)
	var off := vp > OFF_PCT or sp > OFF_PCT
	var text := ""
	if off:
		text = "WARN  the file on disk is not the part: re-read, its volume is %.1f %% and its size %.1f %% off. Do not print it; export again" % [vp, sp]
	return {"ok": true, "off": off, "vol_pct": vp, "size_pct": sp, "text": text}
