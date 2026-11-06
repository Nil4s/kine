extends SceneTree
## G21 shared render-vs-photo comparison (scripts/build/compare_shot.gd). Bars committed before the first run:
##   a STATS     a 2 x 1 image (black, white) has mean 0.5 and dark fraction 0.5 (to 1e-9); CONTROL: identical images give zero deltas.
##   b SHEET     side_by_side scales both inputs to the requested height, keeps their pixels at the two ends, and writes a PNG that re-reads.
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func _init() -> void:
	var a := Image.create(2, 1, false, Image.FORMAT_RGB8)
	a.set_pixel(0, 0, Color.BLACK)
	a.set_pixel(1, 0, Color.WHITE)
	var s := CompareShot.stats(a)
	ok(absf(float(s["mean"]) - 0.5) < 1e-9 and absf(float(s["dark"]) - 0.5) < 1e-9, "a stats: mean %.6f, dark %.6f" % [float(s["mean"]), float(s["dark"])])
	var d := CompareShot.compare(a, a)
	ok(float(d["mean_delta"]) == 0.0 and float(d["dark_delta"]) == 0.0, "a CONTROL identical images: deltas 0")
	var b := Image.create(4, 2, false, Image.FORMAT_RGB8)
	b.fill(Color.RED)
	var sheet := CompareShot.side_by_side(a, b, 10, 4)
	var left_ok: bool = sheet.get_pixel(0, 0) == Color.BLACK and sheet.get_pixel(19, 9) == Color.WHITE
	var right_ok: bool = sheet.get_pixel(24, 5) == Color.RED
	# AMENDED fixture (the bar is unchanged): both sources are 2:1, so at height 10 each is 20 wide + a 4 px gap = 44, not 24
	ok(sheet.get_width() == 44 and sheet.get_height() == 10 and left_ok and right_ok, "b sheet %d x %d: left black/white, right red" % [sheet.get_width(), sheet.get_height()])
	var p := CompareShot.write(a, b, "C:/Temp/claude/g21/sheet.png", 10)
	var back := Image.load_from_file(p)
	ok(back != null and back.get_width() == 52, "b the sheet re-reads from %s (%s; write uses the default 12 px gap)" % [p, "null" if back == null else "%d x %d" % [back.get_width(), back.get_height()]])
	print("g21compare: %d fail" % fails)
	quit(1 if fails > 0 else 0)
