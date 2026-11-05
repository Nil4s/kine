extends RefCounted
## CH16 Sony a7 / ILCE-7 class camera. Every named item is a separate Part record in one Assembly; all dimensions are mm in one global
## modelling frame (X right, Y up, Z toward lens). No mesh-only dummy Parts: every visible item has an exact KCad solid and a BOM material.
const KCad := preload("res://scripts/kcad.gd")
const W := 126.9
const H := 94.4
const D := 48.2
const D_MAX := 54.8
const FLANGE := 18.0
const SENSOR_W := 35.8
const SENSOR_H := 23.9
const THROAT_D := 46.1
const BLACK := [0.035, 0.040, 0.045]
const RUBBER := [0.018, 0.020, 0.022]
const MAG := [0.25, 0.28, 0.30]
const METAL := [0.62, 0.65, 0.68]
const GOLD := [0.72, 0.52, 0.16]
const PCB := [0.035, 0.24, 0.12]
const CHIP := [0.055, 0.060, 0.070]
const GLASS := [0.35, 0.75, 0.88]
const SENSOR := [0.20, 0.42, 0.72]
const COPPER := [0.72, 0.31, 0.10]
const WHITE := [0.78, 0.80, 0.82]
const RED := [0.65, 0.08, 0.055]


class PB extends RefCounted:
	var name := ""
	var feats: Array = []
	var nb := 0
	func _init(n: String) -> void:
		name = n
	func _add(f: Dictionary) -> void:
		f["id"] = "f%d" % (feats.size() + 1)
		f["name"] = "%s%d" % [String(f["t"]).capitalize(), feats.size() + 1]
		feats.append(f)
	func _paint(col: Array) -> void:
		_add({"t": "appear", "body": float(nb - 1), "color": col, "metal": 0.0, "rough": 0.65, "preset": "Custom"})
	func box(x: float, y: float, z: float, w: float, h: float, d: float, col: Array) -> int:
		_add({"t": "prim", "kind": "box", "op": "new", "x": x, "y": y, "z": z, "w": w, "h": h, "d": d})
		nb += 1
		_paint(col)
		return nb - 1
	func cyl(x: float, y: float, z: float, axis: String, r: float, ln: float, col: Array) -> int:
		_add({"t": "prim", "kind": "cylinder", "op": "new", "x": x, "y": y, "z": z, "axis": axis, "r": r, "len": ln})
		nb += 1
		_paint(col)
		return nb - 1
	func tube(x: float, y: float, z: float, axis: String, r: float, ri: float, ln: float, col: Array) -> int:
		_add({"t": "prim", "kind": "tube", "op": "new", "x": x, "y": y, "z": z, "axis": axis, "r": r, "r_in": ri, "len": ln})
		nb += 1
		_paint(col)
		return nb - 1
	func cut_box(into: int, x: float, y: float, z: float, w: float, h: float, d: float) -> void:
		_add({"t": "prim", "kind": "box", "op": "cut", "into": into, "x": x, "y": y, "z": z, "w": w, "h": h, "d": d})
	func cut_cyl(into: int, x: float, y: float, z: float, axis: String, r: float, ln: float) -> void:
		_add({"t": "prim", "kind": "cylinder", "op": "cut", "into": into, "x": x, "y": y, "z": z, "axis": axis, "r": r, "len": ln})
	func rec(seq: int) -> Dictionary:
		return {"version": 1, "name": name, "seq": seq, "features": feats}


static func _b(mat: String, buy := "", alt: Array = []) -> Dictionary:
	var r := {"material": mat}
	if buy != "":
		r["buy"] = buy
	if not alt.is_empty():
		r["alt"] = alt
	return r


static func bottom_screws() -> Array:
	return [[-55.0, -45.0], [-55.0, -5.0], [-45.0, -45.0], [-45.0, -5.0], [35.0, -45.0], [45.0, -45.0], [55.0, -45.0], [35.0, -5.0], [45.0, -5.0], [55.0, -5.0]]


static func rear_screws() -> Array:
	return [[-58.0, 10.0], [58.0, 10.0], [-58.0, 70.0], [58.0, 70.0], [-15.0, 80.0], [15.0, 80.0], [-50.0, 60.0], [50.0, 60.0]]


static func front_screws() -> Array:
	return [[-55.0, 15.0], [55.0, 15.0], [-55.0, 65.0], [55.0, 65.0], [-25.0, 72.0], [25.0, 72.0]]


static func top_screws() -> Array:
	return [[-55.0, -35.0], [-55.0, -10.0], [55.0, -35.0], [55.0, -10.0], [30.0, -35.0]]


static func chassis() -> Dictionary:
	var p := PB.new("Chassis")
	p.box(-40, 1.2, -44, 68, 13.8, 40, MAG)                 # deep bottom/mid frame
	p.box(-46, 15, -44, 6, 59, 40, MAG)                    # left wall
	p.box(24, 15, -42, 4, 59, 38, MAG)                     # right wall, clears battery and rear PCB
	var fr := p.box(-30, 9, -12, 60, 60, 8, MAG)            # thick mount carrier, open through the optical path
	p.cut_cyl(fr, 0, 39, -13, "z", 28.1, 10)
	p.box(-40, 70, -6, 66, 4, 2, MAG)                      # front upper bridge
	var tr := p.box(-40, 70, -44, 66, 4, 5, MAG)            # rear upper bridge around the EVF
	p.cut_box(tr, -16, 69, -44, 32, 6, 5)
	return p.rec(1)


static func front_shell() -> Dictionary:
	var p := PB.new("Front body shell")
	var a := p.box(-63.45, 1.2, -3, 101.45, 73.8, 3, BLACK)
	p.cut_cyl(a, 0, 39, -4, "z", 28.1, 5)
	p.box(-20, 75, -3, 40, 16.4, 3, BLACK)                 # hump front
	p.box(-20, 75, -45, 2, 16.4, 42, BLACK)
	p.box(18, 75, -45, 2, 16.4, 42, BLACK)
	p.box(-20, 91.4, -45, 40, 1.0, 42, BLACK)              # hot shoe above, rather than inside, this cover
	for q in front_screws():
		if float(q[0]) <= 38.0:
			p.cut_cyl(a, q[0], q[1], -4, "z", 0.9, 5)
	return p.rec(2)


static func rear_shell() -> Dictionary:
	var p := PB.new("Rear body shell")
	var a := p.box(-63.45, 1.2, -48.2, 101.45, 73.8, 1.2, BLACK)
	p.cut_box(a, -42, 12, -49, 76, 54, 3)
	p.box(-20, 75, -48.2, 40, 16.4, 1.2, BLACK)
	p.box(-63.45, 1.2, -47, 1.2, 73.8, 44, BLACK)
	p.cut_box(2, -64, 39, -21, 3, 24, 12)                  # side I/O opening in the left wall
	for q in rear_screws():
		if float(q[0]) <= 38.0:
			p.cut_cyl(a if float(q[1]) < 75.0 else 1, q[0], q[1], -49, "z", 0.9, 3)
	return p.rec(3)


static func top_plate() -> Dictionary:
	var p := PB.new("Top plate")
	var a := p.box(-63.45, 75, -45, 43.45, 1.2, 42, BLACK)
	var b := p.box(20, 75, -45, 43.45, 1.2, 42, BLACK)
	for q in top_screws():
		p.cut_cyl(a if float(q[0]) < 0.0 else b, q[0], 74.9, q[1], "y", 0.9, 1.5)
	return p.rec(4)


static func grip() -> Dictionary:
	var p := PB.new("Grip shell")
	p.box(62.25, 1.2, -45, 1.2, 58.8, 42, RUBBER)
	p.box(38, 1.2, -47, 25.45, 0.8, 42, RUBBER)              # bottom web ends where the battery begins
	var front := p.box(38, 15, -3, 25.45, 45, 3, RUBBER)
	var rear := p.box(38, 1.2, -48.2, 25.45, 58.8, 1.2, RUBBER)
	p.box(38, 60, -47, 25.45, 1.2, 44, RUBBER)
	for q in front_screws():
		if float(q[0]) > 38.0:
			p.cut_cyl(front, q[0], q[1], -4, "z", 0.9, 5)
	for q in rear_screws():
		if float(q[0]) > 38.0:
			p.cut_cyl(rear, q[0], q[1], -49, "z", 0.9, 3)
	return p.rec(5)


static func bottom_plate() -> Dictionary:
	var p := PB.new("Bottom plate")
	var a := p.box(-63.45, 0, -48.2, 126.9, 1.2, 48.2, BLACK)
	p.cut_box(a, 29, -0.2, -40, 33, 1.6, 22)
	for q in bottom_screws():
		p.cut_cyl(a, q[0], -0.2, q[1], "y", 0.9, 1.6)
	return p.rec(6)


static func mount_ring() -> Dictionary:
	var p := PB.new("E-mount ring and flange")
	p.tube(0, 39, -3, "z", 28.0, THROAT_D / 2.0, 3.0, METAL)
	return p.rec(7)


static func sensor_carrier() -> Dictionary:
	var p := PB.new("Sensor carrier")
	var a := p.box(-23, 22, -19.65, 46, 34, 1.0, MAG)
	p.cut_box(a, -18.5, 26.5, -20, 37, 25, 2)
	return p.rec(8)


static func cover_glass() -> Dictionary:
	var p := PB.new("Sensor cover glass")
	p.box(-19, 26, -21.5, 38, 26, 1.5, GLASS)
	return p.rec(9)


static func sensor_die() -> Dictionary:
	var p := PB.new("Full-frame CMOS sensor 35.8 x 23.9 mm")
	p.box(-SENSOR_W / 2.0, 39.0 - SENSOR_H / 2.0, -18.35, SENSOR_W, SENSOR_H, 0.35, SENSOR)
	return p.rec(10)


static func sensor_flex() -> Dictionary:
	var p := PB.new("Sensor flex")
	p.box(-35, 15, -44.6, 18, 2, 24.77, COPPER)
	p.box(-35, 15, -19.83, 18, 15, 0.18, COPPER)
	return p.rec(11)


static func shutter_frame() -> Dictionary:
	var p := PB.new("Shutter mechanism frame")
	var a := p.box(-24, 22, -23.5, 48, 34, 1.2, CHIP)
	p.cut_box(a, -19, 26, -24, 38, 26, 2)
	return p.rec(12)


static func curtain(which: int) -> Dictionary:
	var p := PB.new("Shutter curtain %d" % which)
	var z := -22.2 if which == 1 else -21.98
	p.box(-18.5, 26.5, z, 37, 25, 0.12, METAL if which == 1 else MAG)
	return p.rec(12 + which)


static func main_pcb() -> Dictionary:
	var p := PB.new("Main PCB with BIONZ X, DRAM and power ICs")
	p.box(-39, 12, -45.8, 78, 58, 1.2, PCB)
	p.box(-10, 30, -44.6, 18, 18, 3.0, CHIP)                # BIONZ X
	p.box(12, 40, -44.6, 14, 14, 2.0, CHIP)                 # DRAM
	p.box(-28, 50, -44.6, 14, 10, 2.0, CHIP)                # power IC
	p.box(20, 20, -44.6, 10, 8, 1.6, CHIP)                  # shutter driver
	return p.rec(20)


static func evf() -> Dictionary:
	var p := PB.new("OLED EVF module")
	p.box(-14, 68, -42, 28, 22, 30, CHIP)
	p.box(-10, 73, -44, 20, 12, 2, GLASS)                   # rear eyepiece, clear of the shell
	return p.rec(21)


static func lcd() -> Dictionary:
	var p := PB.new("LCD module")
	p.box(-42, 12, -54.6, 76, 54, 4.0, CHIP)
	p.box(-39, 15, -54.8, 70, 48, 0.2, GLASS)
	return p.rec(22)


static func lcd_hinge() -> Dictionary:
	var p := PB.new("LCD hinge")
	p.box(-30, 60, -50.6, 50, 4, 2.4, METAL)
	return p.rec(23)


static func rear_controls() -> Dictionary:
	var p := PB.new("Rear control cluster")
	p.cyl(49, 47, -50.5, "z", 10, 2.3, CHIP)
	p.cyl(49, 47, -51.0, "z", 3, 0.5, METAL)
	return p.rec(24)


static func top_dials() -> Dictionary:
	var p := PB.new("Top command and exposure dials")
	p.cyl(-45, 76.2, -20, "y", 11, 6.3, CHIP)
	p.cyl(45, 76.2, -20, "y", 11, 6.3, CHIP)
	return p.rec(25)


static func shutter_button() -> Dictionary:
	var p := PB.new("Shutter button")
	p.cyl(50, 61.2, -10, "y", 5, 4.0, METAL)
	return p.rec(26)


static func hot_shoe() -> Dictionary:
	var p := PB.new("Hot shoe")
	p.box(-10, 92.4, -30, 20, 2.0, 15, METAL)
	p.box(-8, 94.0, -28, 16, 0.4, 11, GOLD)
	return p.rec(27)


static func battery() -> Dictionary:
	var p := PB.new("NP-FW50 battery 7.2 V 1020 mAh")
	p.box(30, 2, -38.5, 31.8, 45, 18.5, CHIP)
	p.box(34, 47, -33, 10, 3, 8, GOLD)
	return p.rec(28)


static func battery_door() -> Dictionary:
	var p := PB.new("Battery door")
	p.box(29.2, 0, -39.8, 32.6, 1.0, 21.6, BLACK)
	return p.rec(29)


static func sd_card() -> Dictionary:
	var p := PB.new("SD card")
	p.box(-10, 16, -29, 24, 32, 2.1, CHIP)
	return p.rec(30)


static func sd_slot() -> Dictionary:
	var p := PB.new("SD card slot and board")
	var a := p.box(-12, 15, -30.5, 28, 34.4, 4.0, PCB)
	p.cut_box(a, -10.2, 15.8, -29.2, 24.4, 32.4, 2.5)
	return p.rec(31)


static func ports() -> Dictionary:
	var p := PB.new("USB and HDMI port block")
	p.box(-61.9, 40, -20, 13.9, 22, 8, METAL)
	p.box(-62.1, 44, -18, 0.2, 6, 4, CHIP)
	return p.rec(32)


static func antenna() -> Dictionary:
	var p := PB.new("Wi-Fi NFC antenna")
	p.box(40, 62, -44, 20, 12, 0.4, COPPER)
	return p.rec(33)


static func screw(axis: String) -> Dictionary:
	var p := PB.new("M1.5 x 4 fastener " + axis.to_upper())
	p.cyl(0, 0, 0, axis, 0.75, 4.0, METAL)
	return p.rec(40 if axis == "y" else 41)


static func _add(asm: Dictionary, groups: Dictionary, stage: String, rec: Dictionary, bom: Dictionary, hang: Array = []) -> String:
	var r := rec.duplicate(true)
	r["bom"] = bom
	var id := Assembly.add_part(asm, r)
	if id == "":
		push_error("CH16 part did not build: " + String(rec["name"]))
		return ""
	var p: Dictionary = asm["parts"][-1]
	Assembly.set_pose(p, Vector3.ZERO, Vector3.ZERO)
	if not hang.is_empty():
		p["hang"] = hang
	if not groups.has(stage):
		groups[stage] = []
	(groups[stage] as Array).append(id)
	return id


static func assembly(opts := {}) -> Dictionary:
	var asm := Assembly.make("CH16 Sony a7 ILCE-7 class camera")
	asm["datums"] = {"mount_face_z_mm": 0.0, "sensor_plane_z_mm": -float(opts.get("flange", FLANGE)), "sensor_w_mm": SENSOR_W, "sensor_h_mm": SENSOR_H, "throat_d_mm": THROAT_D}
	var g := {}
	var chassis_id := _add(asm, g, "Chassis", chassis(), _b("camera_magnesium"))
	_add(asm, g, "Chassis", bottom_plate(), _b("camera_polymer", "", ["camera_polymer", "abs"]))
	_add(asm, g, "Chassis", mount_ring(), _b("aluminium", "camera_mount"), [chassis_id])
	_add(asm, g, "Sensor and shutter", sensor_carrier(), _b("camera_magnesium", "camera_sensor_carrier"), [chassis_id])
	_add(asm, g, "Sensor and shutter", cover_glass(), _b("camera_glass", "camera_cover_glass"), [chassis_id])
	_add(asm, g, "Sensor and shutter", sensor_die(), _b("camera_silicon", "camera_sensor"), [chassis_id])
	_add(asm, g, "Sensor and shutter", sensor_flex(), _b("camera_copper", "camera_sensor_flex"), [chassis_id])
	_add(asm, g, "Sensor and shutter", shutter_frame(), _b("steel", "camera_shutter"), [chassis_id])
	_add(asm, g, "Sensor and shutter", curtain(1), _b("steel", "camera_shutter"), [chassis_id])
	_add(asm, g, "Sensor and shutter", curtain(2), _b("steel", "camera_shutter"), [chassis_id])
	_add(asm, g, "Boards and power", main_pcb(), _b("camera_fr4", "camera_main_pcb"), [chassis_id])
	_add(asm, g, "Boards and power", sd_slot(), _b("camera_fr4", "camera_sd_slot"), [chassis_id])
	_add(asm, g, "Boards and power", sd_card(), _b("camera_sd_plastic", "camera_sd_card"), [chassis_id])
	_add(asm, g, "Boards and power", ports(), _b("camera_fr4", "camera_ports"), [chassis_id])
	_add(asm, g, "Boards and power", antenna(), _b("camera_copper", "camera_antenna"), [chassis_id])
	_add(asm, g, "Boards and power", battery(), _b("camera_battery", "np_fw50_sony", ["np_fw50_sony", "np_fw50_pattern"]), [chassis_id])
	_add(asm, g, "EVF and LCD", evf(), _b("camera_display", "camera_evf"), [chassis_id])
	_add(asm, g, "EVF and LCD", lcd(), _b("camera_display", "camera_lcd"), [chassis_id])
	_add(asm, g, "EVF and LCD", lcd_hinge(), _b("aluminium", "camera_lcd_hinge"), [chassis_id])
	_add(asm, g, "EVF and LCD", rear_controls(), _b("camera_fr4", "camera_controls"), [chassis_id])
	_add(asm, g, "EVF and LCD", top_dials(), _b("camera_fr4", "camera_controls"), [chassis_id])
	_add(asm, g, "EVF and LCD", shutter_button(), _b("aluminium", "camera_controls"), [chassis_id])
	_add(asm, g, "EVF and LCD", hot_shoe(), _b("aluminium", "camera_hotshoe"), [chassis_id])
	_add(asm, g, "Shells", front_shell(), _b("camera_polymer", "", ["camera_polymer", "abs"]), [chassis_id])
	_add(asm, g, "Shells", rear_shell(), _b("camera_polymer", "", ["camera_polymer", "abs"]), [chassis_id])
	_add(asm, g, "Shells", top_plate(), _b("camera_polymer", "", ["camera_polymer", "abs"]), [chassis_id])
	_add(asm, g, "Shells", grip(), _b("camera_polymer", "", ["camera_polymer", "abs"]), [chassis_id])
	_add(asm, g, "Doors and fasteners", battery_door(), _b("camera_polymer", "", ["camera_polymer", "abs"]), [chassis_id])
	for q in bottom_screws():
		var id := _add(asm, g, "Doors and fasteners", screw("y"), _b("steel", "camera_screw_m1_5"), [chassis_id])
		Assembly.set_pose(asm["parts"][-1], Vector3(q[0], 0, q[1]), Vector3.ZERO)
	for q in rear_screws():
		_add(asm, g, "Doors and fasteners", screw("z"), _b("steel", "camera_screw_m1_5"), [chassis_id])
		Assembly.set_pose(asm["parts"][-1], Vector3(q[0], q[1], -48.2), Vector3.ZERO)
	for q in front_screws():
		_add(asm, g, "Doors and fasteners", screw("z"), _b("steel", "camera_screw_m1_5"), [chassis_id])
		Assembly.set_pose(asm["parts"][-1], Vector3(q[0], q[1], -4.0), Vector3.ZERO)
	for q in top_screws():
		_add(asm, g, "Doors and fasteners", screw("y"), _b("steel", "camera_screw_m1_5"), [chassis_id])
		Assembly.set_pose(asm["parts"][-1], Vector3(q[0], 76.2, q[1]), Vector3.ZERO)
	var order := ["Chassis", "Sensor and shutter", "Boards and power", "EVF and LCD", "Shells", "Doors and fasteners"]
	if bool(opts.get("shells_first", false)):
		order = ["Chassis", "Shells", "Sensor and shutter", "Boards and power", "EVF and LCD", "Doors and fasteners"]
	asm["stages"] = []
	for nm in order:
		asm["stages"].append({"name": nm, "parts": g.get(nm, []), "dur": 1.0})
	asm["stage_opts"] = {"tol": 0.1, "ground": 0.0, "drop": 40.0, "fps": 2}
	if bool(opts.get("pcb_into_shell", false)):
		for p in asm["parts"]:
			if String(p["name"]).begins_with("Main PCB"):
				Assembly.set_pose(p, Vector3(0, 0, -2), Vector3.ZERO)
	return asm


static func part_named(asm: Dictionary, begins: String) -> Dictionary:
	for p in asm["parts"]:
		if String(p["name"]).begins_with(begins):
			return p
	return {}


static func dimensions_mm(asm: Dictionary) -> Vector3:
	return Assembly.total_aabb(asm).size / Assembly.MM


static func body_depth_mm(asm: Dictionary) -> float:
	var f := part_named(asm, "Front body")
	var r := part_named(asm, "Rear body")
	if f.is_empty() or r.is_empty():
		return 0.0
	return (Assembly.world_aabb(f).end.z - Assembly.world_aabb(r).position.z) / Assembly.MM


static func nominal_dimensions() -> Vector3:
	return Vector3(W, H, D)


static func flange_mm(asm: Dictionary) -> float:
	var d: Dictionary = asm["datums"]
	return float(d["mount_face_z_mm"]) - float(d["sensor_plane_z_mm"])


static func sensor_mm(_asm: Dictionary) -> Vector2:
	return Vector2(SENSOR_W, SENSOR_H)


static func sensor_corner_radius_mm() -> float:
	return sqrt(SENSOR_W * SENSOR_W + SENSOR_H * SENSOR_H) / 2.0


static func throat_radius_mm() -> float:
	return THROAT_D / 2.0


static func cone_clearance_mm(asm: Dictionary) -> float:
	# Both end circles clear; a linear cone between them therefore clears at every intermediate depth.
	return minf(throat_radius_mm() - sensor_corner_radius_mm(), throat_radius_mm() - sensor_corner_radius_mm() * (1.0 - flange_mm(asm) / maxf(flange_mm(asm), 1e-9)))


static func inside_throat(_asm: Dictionary) -> bool:
	return sensor_corner_radius_mm() <= throat_radius_mm() and sqrt(18.5 * 18.5 + 12.5 * 12.5) <= throat_radius_mm()


static func fastener_count(asm: Dictionary) -> int:
	var n := 0
	for p in asm["parts"]:
		if String((p["rec"] as Dictionary).get("bom", {}).get("buy", "")) == "camera_screw_m1_5":
			n += 1
	return n


static func scale_assembly(asm: Dictionary, factor: float) -> Dictionary:
	var out := asm.duplicate(true)
	var keys := ["x", "y", "z", "w", "h", "d", "r", "r_in", "r2", "len", "mm"]
	for p in out["parts"]:
		for f in (p["rec"] as Dictionary).get("features", []):
			for k in keys:
				if f.has(k):
					f[k] = float(f[k]) * factor
		for i in 3:
			p["pos"][i] = float(p["pos"][i]) * factor
	out["datums"]["mount_face_z_mm"] = float(out["datums"]["mount_face_z_mm"]) * factor
	out["datums"]["sensor_plane_z_mm"] = float(out["datums"]["sensor_plane_z_mm"]) * factor
	Assembly._memo.clear()
	return out


static func stage_order_ok(asm: Dictionary) -> bool:
	var idx := {}
	for i in (asm["stages"] as Array).size():
		idx[String(asm["stages"][i]["name"])] = i
	for nm in ["Chassis", "Sensor and shutter", "Boards and power", "EVF and LCD", "Shells", "Doors and fasteners"]:
		if not idx.has(nm):
			return false
	return int(idx["Chassis"]) < int(idx["Sensor and shutter"]) and int(idx["Sensor and shutter"]) < int(idx["Boards and power"]) and int(idx["Boards and power"]) < int(idx["EVF and LCD"]) and int(idx["EVF and LCD"]) < int(idx["Shells"]) and int(idx["Shells"]) < int(idx["Doors and fasteners"])


static func clashes(asm: Dictionary) -> Dictionary:
	var sol := {}
	var boxes := {}
	for p in asm["parts"]:
		var id := String(p["id"])
		var ids: Array = Part.replay(p["rec"], -1, {"keep": true, "errors_only": true}).get("ids", [])
		sol[id] = AssemblyMotion._place_all(ids, Assembly.xf_of(p))
		Part.release_kept(ids)
		var first := true
		var box := AABB()
		for s in sol[id]:
			var b := KCad.bounds_aabb(int(s))
			box = b if first else box.merge(b)
			first = false
		boxes[id] = box
	var hits: Array = []
	var pairs := 0
	var ps: Array = asm["parts"]
	for i in ps.size():
		for j in range(i + 1, ps.size()):
			var a := String(ps[i]["id"])
			var b := String(ps[j]["id"])
			if not (boxes[a] as AABB).intersects(boxes[b]):
				continue
			var v := 0.0
			for sa in sol[a]:
				for sb in sol[b]:
					pairs += 1
					v += maxf(0.0, float(KCad.overlap_volume(int(sa), int(sb))))
			if v > 1e-12:                       # 0.001 mm3: numerical contact only, no declared press fit
				hits.append({"a": String(ps[i]["name"]), "b": String(ps[j]["name"]), "mm3": v * 1e9})
	for id in sol:
		for s in sol[id]:
			KCad.release(int(s))
	return {"hits": hits, "pairs": pairs}
