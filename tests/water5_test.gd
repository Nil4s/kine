extends SceneTree
## L50 WATER5: free-slip floor. A block of water sliding along the floor must keep its speed under FREE-SLIP walls.
## wtest.sh water5.  Written and committed BEFORE the fix. No existing bar is edited.
## SCENE (the l44diag A scene): 62 x 10 x 8 cells of 10 mm (and the same box at 5 mm), no gravity, block of water 0.3 x 0.07 x 0.07 m moving at 1 m/s in +x,
## advanced 0.1 s. MEASURE: mean u of the particles in the bottom band (y < 10 mm + h), divided by the initial 1 m/s.
## BARS (fixed before the fix; the defect report read 0.816 at both cell sizes):
##   (A) retention >= 0.98 at h = 10 mm and at h = 5 mm with free slip (wall friction 0).
##   (g) CONTROL: the same run with forced no-slip walls (set_wall_friction(1.0)) must FAIL the 0.98 bar.
## INFO: the retention by row (y / h) and the whole-block mean, to see where speed goes.
var fails := 0


func ok(c: bool, m: String) -> void:
	print(("ok   " if c else "FAIL ") + m)
	if not c:
		fails += 1


func _slide(h: float, wfr: float, force_gd := false, xs := 0.0) -> Dictionary:
	var s := 0.01 / h
	var F = Fluid.make(force_gd)
	F.setup(int(62 * s), int(10 * s), int(8 * s), h, Vector3.ZERO)
	F.set_params(0.0, 0.2, 0.5, 0.005, 300, 1e-7)
	F.set_threads(4)
	if wfr > 0.0:
		F.set_wall_friction(wfr)
	F.add_fluid_box(Vector3(h + xs, h, h), Vector3(0.31 + xs, 0.01 + 6 * 0.01, 7.0 * 0.01 + h), Vector3(1.0, 0, 0), 1)
	F.advance(0.1)
	var d: PackedFloat64Array = F.particle_data()
	var n := d.size() / 6
	var low := 0.0
	var nl := 0
	var all := 0.0
	var rows := {}
	var rear := 0.0
	var nr := 0
	for p in n:
		all += d[6 * p + 3]
		var r := int(floor(d[6 * p + 1] / h))
		if not rows.has(r):
			rows[r] = [0.0, 0]
		rows[r][0] += d[6 * p + 3]
		rows[r][1] += 1
		if d[6 * p + 1] < 0.01 + h and d[6 * p] < 0.06:
			rear += d[6 * p + 3]
			nr += 1
		if d[6 * p + 1] < 0.01 + h:
			low += d[6 * p + 3]
			nl += 1
	var keys := rows.keys()
	keys.sort()
	var prof := ""
	for r in keys.slice(0, 6):
		prof += " r%d %.3f" % [r, rows[r][0] / rows[r][1]]
	return {"band": low / maxi(nl, 1), "all": all / n, "nl": nl, "prof": prof, "rear": rear / maxi(nr, 1)}


func _init() -> void:
	for h in [0.01, 0.005]:
		var a := _slide(h, 0.0)
		print("      info h %.3f: band %.4f  whole block %.4f  (%d band particles)  rows:%s" % [h, a["band"], a["all"], a["nl"], a["prof"]])
		ok(a["band"] >= 0.98, "(A) free-slip floor-row retention at h %.0f mm = %.4f (>= 0.98)" % [h * 1000.0, a["band"]])
		var g := _slide(h, 1.0)
		ok(g["band"] < 0.98, "(g) CONTROL forced no-slip at h %.0f mm reads %.4f and fails the bar" % [h * 1000.0, g["band"]])
	# ---- (B) added after (A) failed and a probe showed the floor is exact: the same block started 0.15 m from the x = 0 wall (a block that starts IN CONTACT
	# with the rear wall cannot detach from it: that wall face is pinned at u = 0). Bars B written before the fix attempt; (A) above is left as committed.
	for h in [0.01, 0.005]:
		var b := _slide(h, 0.0, false, 0.15)
		print("      info B h %.3f: band %.4f  whole block %.4f  rows:%s" % [h, b["band"], b["all"], b["prof"]])
		ok(b["band"] >= 0.98, "(B) free-slip floor-row retention, block clear of the rear wall, h %.0f mm = %.4f (>= 0.98)" % [h * 1000.0, b["band"]])
		var g := _slide(h, 1.0, false, 0.15)
		ok(g["band"] < 0.98, "(g) CONTROL (B) forced no-slip at h %.0f mm reads %.4f and fails" % [h * 1000.0, g["band"]])
	var tw := _slide(0.01, 0.0, true, 0.15)
	var nt := _slide(0.01, 0.0, false, 0.15)
	ok(absf(tw["band"] - nt["band"]) <= 0.005, "(E) GDScript twin equals C++: band %.4f vs %.4f (<= 0.005)" % [tw["band"], nt["band"]])
	var tw2 := _slide(0.01, 0.0, true, 0.0)
	var nt2 := _slide(0.01, 0.0, false, 0.0)
	ok(absf(tw2["band"] - nt2["band"]) <= 0.005, "(E2) GDScript twin equals C++ in the rear-wall scene (separating wall): band %.4f vs %.4f (<= 0.005)" % [tw2["band"], nt2["band"]])
	print("water5: %d fail" % fails)
	quit(1 if fails > 0 else 0)
