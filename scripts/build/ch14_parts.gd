extends RefCounted
## CH14 the arm as Kine PARTS (feature lists of "prim" steps: box / cylinder / tube / cone, joins, cuts, patterns) and an ASSEMBLY of them.
## Every part is built in its own frame, mm, x right, y up, z toward the viewer, in the arm's vertical plane (r along +x, height +y).
## The renderer (tools/ch14_render3d.gd) moves the parts with the joint angles; assembly() is the arm at its rest pose (yaw 0, mid joints).
## Printed holes are drawn at A.hole_design(d): nominal + running clearance + the FDM undersize (docs/CH14_REFERENCE.md section 7).
const A := preload("res://scripts/build/ch14_arm.gd")

const WOOD := [0.78, 0.62, 0.40]
const PLA := [0.95, 0.52, 0.12]
const STEEL := [0.70, 0.72, 0.76]
const BLACK := [0.12, 0.12, 0.13]
const GLASS := [0.82, 0.92, 1.0]
const WATER := [0.20, 0.45, 0.95]
const WHITE := [0.93, 0.93, 0.92]
const CANRED := [0.78, 0.08, 0.10]
const ALU := [0.82, 0.83, 0.86]
const PIN_D := 4.0


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
		_add({"t": "appear", "body": float(nb - 1), "color": col, "metal": 0.0, "rough": 0.7, "preset": "Custom"})

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

	func tube(x: float, y: float, z: float, axis: String, r: float, r_in: float, ln: float, col: Array) -> int:
		_add({"t": "prim", "kind": "tube", "op": "new", "x": x, "y": y, "z": z, "axis": axis, "r": r, "r_in": r_in, "len": ln})
		nb += 1
		_paint(col)
		return nb - 1

	func cone(x: float, y: float, z: float, axis: String, r: float, r2: float, ln: float, col: Array) -> int:
		_add({"t": "prim", "kind": "cone", "op": "new", "x": x, "y": y, "z": z, "axis": axis, "r": r, "r2": r2, "len": ln})
		nb += 1
		_paint(col)
		return nb - 1

	## a prim that joins (op "join") into body `into` or cuts (op "cut") it: no new body
	func join_box(into: int, x: float, y: float, z: float, w: float, h: float, d: float) -> void:
		_add({"t": "prim", "kind": "box", "op": "join", "into": into, "x": x, "y": y, "z": z, "w": w, "h": h, "d": d})

	func cut_box(into: int, x: float, y: float, z: float, w: float, h: float, d: float) -> void:
		_add({"t": "prim", "kind": "box", "op": "cut", "into": into, "x": x, "y": y, "z": z, "w": w, "h": h, "d": d})

	func cut_cyl(into: int, x: float, y: float, z: float, axis: String, r: float, ln: float) -> void:
		_add({"t": "prim", "kind": "cylinder", "op": "cut", "into": into, "x": x, "y": y, "z": z, "axis": axis, "r": r, "len": ln})

	## a pin hole along z through a part: drawn at the compensated diameter
	func pin_hole(into: int, x: float, y: float, z0: float, ln: float) -> void:
		cut_cyl(into, x, y, z0, "z", A.hole_design(PIN_D) / 2.0, ln)

	func pattern(body: int, kind: String, count: int, mm := 0.0, dir := "x", axis := "y") -> void:
		var f := {"t": "pattern", "body": body, "kind": kind, "count": count, "op": "join"}
		if kind == "linear":
			f["mm"] = mm
			f["dir"] = dir
		else:
			f["axis"] = axis
			f["deg"] = 360.0
		_add(f)

	func combine(target: int, tools: Array) -> void:
		_add({"t": "combine", "target": target, "tools": tools, "op": "join", "keep": false})

	func rec(seq: int) -> Dictionary:
		return {"version": 1, "name": name, "seq": seq, "features": feats}


static func syringe_barrel(sz: int) -> Dictionary:
	var b: float = A.SYR[sz]["bore"]
	var r := b / 2.0
	var lb := A.stroke(sz) + 12.0
	var p := PB.new("Syringe barrel %d mL (BD Luer-Lok class)" % sz)
	p.tube(0, 0, 0, "x", r + 1.0, r, lb, GLASS)
	p.cone(-10, 0, 0, "x", 2.2, 3.2, 10.0, GLASS)
	var fl := p.box(lb - 2.0, -(r + 9.0), -(r + 9.0), 2.0, 2.0 * (r + 9.0), 2.0 * (r + 9.0), GLASS)
	p.cut_cyl(fl, lb - 2.5, 0, 0, "x", r, 3.0)
	p.cut_box(fl, lb - 3.0, -(r + 11.0), -(r + 11.0) + 0.0, 4.0, 2.0 * (r + 11.0), 12.0)
	p.cut_box(fl, lb - 3.0, -(r + 11.0), r - 1.0, 4.0, 2.0 * (r + 11.0), 12.0)
	return p.rec(1000 + sz)


## plunger: stopper head at x in [0, 8] (front face x = 0), rod to x = 8 + lrod, thumb disc after it. lrod: the rod length
static func syringe_plunger(sz: int, lrod: float) -> Dictionary:
	var r: float = float(A.SYR[sz]["bore"]) / 2.0
	var p := PB.new("Syringe plunger %d mL" % sz)
	p.cyl(0, 0, 0, "x", r - 0.1, 8.0, BLACK)
	p.cyl(8.0, 0, 0, "x", 3.0, lrod, WHITE)
	p.cyl(8.0 + lrod, 0, 0, "x", 9.0, 3.0, WHITE)
	return p.rec(1100 + sz)


static func baseboard() -> Dictionary:
	var p := PB.new("Baseboard (18 mm plywood) and four posts")
	p.box(-230, -18, -170, 460, 18, 340, WOOD)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			p.box(sx * 45 - 10, 0, sz * 45 - 10, 20, 36, 20, WOOD)
	return p.rec(1)


static func console() -> Dictionary:
	var p := PB.new("Console of the five master syringes (plywood)")
	p.box(-240, 0, -100, 120, 10, 200, WOOD)
	for k in 5:
		p.box(-124, 10, -90 + k * 40.0 - 10, 8, 26, 20, WOOD)    # tip block each master leans on
	return p.rec(2)


static func turntable() -> Dictionary:
	var p := PB.new("Turntable, shaft, tower and shoulder clevis (PLA+)")
	var disc := p.cyl(0, 36, 0, "y", 60, 12, PLA)
	p.join_box(disc, -20, 48, -10, 40, 187, 20)           # tower to y = 235
	p.join_box(disc, -25, 225, 13.5, 50, 50, 4.0)         # shoulder cheek +z
	p.join_box(disc, -25, 225, -17.5, 50, 50, 4.0)        # cheek -z
	var pv: Vector2 = A.pivot(A.design(), "sh")
	p.join_box(disc, -8, 250 + pv.y - 8, 14, 16, 16, 24)  # trunnion block for the shoulder slave at z 14 to 38
	p.cut_cyl(disc, 0, 250, -22, "z", A.hole_design(PIN_D) / 2.0, 44)
	p.cut_cyl(disc, 0, 250 + pv.y, 10, "z", A.hole_design(PIN_D) / 2.0, 34)
	p.cyl(0, 12, 0, "y", 5, 26, STEEL)                   # pinion shaft
	return p.rec(3)


static func pinion() -> Dictionary:
	var p := PB.new("Pinion, 20 teeth module 2 (PLA+)")
	var root := p.cyl(0, 0, 0, "y", 17.5, 12, PLA)
	var t := p.box(17.0, 0, -1.57, 5.0, 12.0, 3.14, PLA)
	p.pattern(t, "circular", 20, 0.0, "x", "y")
	p.combine(root, [t])
	p.cut_cyl(root, 0, -1, 0, "y", 2.6, 14)
	return p.rec(4)


static func rack() -> Dictionary:
	var p := PB.new("Rack, module 2 (PLA+)")
	var bar := p.box(-55, 0, 22, 110, 12, 8, PLA)
	var t := p.box(-55, 0, 18, 3.14, 12.0, 4.5, PLA)
	p.pattern(t, "linear", 17, 6.2832, "x")
	p.combine(bar, [t])
	return p.rec(5)


static func upper_arm() -> Dictionary:
	var d := A.design()
	var L: float = d["L1"]
	var p := PB.new("Upper arm, 25 mm square PLA+ tube 1.6 mm wall")
	var b := p.box(0, -12.5, -12.5, L, 25, 25, PLA)
	p.cut_box(b, 8, -10.9, -10.9, L - 16, 21.8, 21.8)
	p.pin_hole(b, 0, 0, -20, 40)
	p.pin_hole(b, L, 0, -20, 40)
	p.join_box(b, L - 25, -12.5, 12.5, 50, 25, 5)           # elbow cheek +z (the forearm runs inside)
	p.join_box(b, L - 25, -12.5, -17.5, 50, 25, 5)
	p.cut_cyl(b, L, 0, -20, "z", A.hole_design(PIN_D) / 2.0, 40)
	var h: Vector2 = A.horn_pin(d, "sh")
	p.join_box(b, h.x - 7, h.y - 7, 12.5, 14, 14, 20)       # shoulder horn lug, reaching z 32.5
	p.join_box(b, 0, h.y, 12.5, h.x, 6, 6)                  # web from the arm to the lug
	var pe: Vector2 = A.pivot(d, "el")
	p.join_box(b, pe.x - 8, -8, 12.5, 16, 16, 24)           # elbow slave trunnion block
	return p.rec(6)


static func forearm() -> Dictionary:
	var d := A.design()
	var L: float = d["L2"]
	var p := PB.new("Forearm, 25 mm square PLA+ tube 1.6 mm wall")
	var b := p.box(0, -12.5, -12.5, L, 25, 25, PLA)
	p.cut_box(b, 8, -10.9, -10.9, L - 16, 21.8, 21.8)
	p.pin_hole(b, 0, 0, -20, 40)
	p.join_box(b, L - 25, -12.5, 12.5, 50, 25, 5)
	p.join_box(b, L - 25, -12.5, -17.5, 50, 25, 5)
	p.pin_hole(b, L, 0, -20, 40)
	var h: Vector2 = A.horn_pin(d, "el")
	p.join_box(b, h.x - 7, h.y - 7, 12.5, 14, 14, 20)
	var pw: Vector2 = A.pivot(d, "wr")
	p.join_box(b, pw.x - 8, -8, 12.5, 16, 16, 24)
	p.cyl(0, 0, -17.5, "z", 2.0, 35, STEEL)                 # the elbow dowel
	return p.rec(7)


## the gripper hangs level from the wrist axis (its origin); the can centre is dg = 70 mm below
static func gripper_body() -> Dictionary:
	var d := A.design()
	var p := PB.new("Gripper body and wrist (PLA+, 5 mL slave)")
	var b := p.box(-25, -4, -60, 50, 28, 120, PLA)
	p.cut_box(b, -13, -4.5, -45, 26, 5, 90)                 # slot the jaw bars slide in
	p.join_box(b, -25, 24, -17.5, 50, 22, 5)                # wrist cheeks
	p.join_box(b, -25, 24, 12.5, 50, 22, 5)
	p.pin_hole(b, 0, 0, -20, 40)
	var h: Vector2 = A.horn_pin(d, "wr")
	p.join_box(b, h.x - 6, h.y - 6, 12.5, 12, 12, 20)
	p.cyl(0, 6, 0, "y", 8, 14, STEEL)                        # the idler pinion that makes the jaws move together
	# the slave syringe seat on top of the housing
	p.join_box(b, -12, 24, 60, 24, 14, 10)
	return p.rec(8)


static func jaw() -> Dictionary:
	var p := PB.new("Gripper jaw with TPU pad (right jaw; the left is its mirror)")
	var pl := p.box(-22, -90, 0, 44, 86, 4, PLA)
	p.box(-22, -90, -2, 44, 86, 2, BLACK)                    # TPU pad on the can side
	p.box(-12, 6, 0, 24, 6, 15, PLA)                         # bar to the rack, along +z at y 6..12
	p.join_box(pl, -12, 6, 0, 24, 6, 15)
	return p.rec(9)


static func can_rec() -> Dictionary:
	var p := PB.new("Cola can 12 fl oz, 66.2 x 122 mm")
	p.cyl(0, 0, 0, "y", 33.1, 106, CANRED)
	p.cone(0, 106, 0, "y", 33.1, 27.0, 11, ALU)
	p.cyl(0, 117, 0, "y", 27.0, 5, ALU)
	return p.rec(10)


static func stand() -> Dictionary:
	var p := PB.new("Can feeder stand (cardboard)")
	p.box(-45, -18, -45, 90, 18, 90, [0.70, 0.55, 0.38])
	return p.rec(11)


## the section of one syringe pair (a 10 mL master and a 20 mL slave, hose between, all water filled), cut in half through the axis (keep the z < 0 half)
static func pair_section() -> Dictionary:
	var p := PB.new("Syringe pair, section (10 mL master, 20 mL slave, 4 x 6 mm hose)")
	var rm: float = float(A.SYR[10]["bore"]) / 2.0
	var rs: float = float(A.SYR[20]["bore"]) / 2.0
	var lm := A.stroke(10) + 12.0
	var ls := A.stroke(20) + 12.0
	var hx := 90.0                       # the hose is drawn 80 mm long (the real one is 0.5 to 1.4 m)
	var xh := -4.0 - 25.0                # master stopper front face: 25 mm out from fully pushed in
	var slave_s := 25.0 * A.area(10) / A.area(20)
	p.tube(-lm, 0, 0, "x", rm + 1.0, rm, lm, GLASS)                      # master barrel, tip at x = 0
	p.cone(0, 0, 0, "x", 3.2, 2.2, 10.0, GLASS)
	p.cyl(xh, 0, 0, "x", rm - 0.05, -xh, WATER)                           # water, tip to stopper
	p.cyl(xh - 8.0, 0, 0, "x", rm - 0.1, 8.0, BLACK)                      # stopper
	p.cyl(xh - 8.0 - 60.0, 0, 0, "x", 3.0, 60.0, WHITE)                   # rod
	p.cyl(10.0, 0, 0, "x", 2.0, hx - 10.0, WATER)                         # water in the hose
	p.tube(10.0, 0, 0, "x", 3.0, 2.0, hx - 10.0, [0.9, 0.9, 0.95])         # hose wall
	var sx := hx + 10.0                                                    # slave barrel tip face
	p.cone(hx, 0, 0, "x", 2.2, 3.2, 10.0, GLASS)
	p.tube(sx, 0, 0, "x", rs + 1.0, rs, ls, GLASS)
	var xs := sx + 4.0 + slave_s
	p.cyl(sx, 0, 0, "x", rs - 0.05, xs - sx, WATER)
	p.cyl(xs, 0, 0, "x", rs - 0.1, 8.0, BLACK)
	p.cyl(xs + 8.0, 0, 0, "x", 3.0, sx + ls + 15.0 - xs - 8.0, WHITE)
	p._add({"t": "split", "plane": "front", "at": 0.0, "keep": -1})
	return p.rec(12)
