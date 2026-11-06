## reactable_cells.gd - N082 on the frame-data strip (L11): one cell per frame of the clip, under the strip's phase blocks.
##   active frame -> COL_ACT; the TELL of a strike ([readable, first_active)) -> green when reactable, red when not (ReactableStrip's colours); else COL_IDLE.
## Built from FrameData.analyze's result and Reactable.analyze's verdict of it; the maths stays in reactable.gd.
class_name ReactableCells
extends Control

const COL_ACT := Color("2b2b33")
const COL_IDLE := Color(0.33, 0.33, 0.37, 0.55)
const H := 9.0   # px (L15: was a 3 px underline nobody saw)

var cells: Array = []        # Color per frame
var fps := 60
var fd_src: Dictionary = {}
var rv_src: Dictionary = {}
var xmap := Callable()       # time (s) -> x; unset = 6 px a frame from 20


## null when there is no clip (empty frame data or no frames)
static func build(fd: Dictionary, r: Dictionary) -> ReactableCells:
	if fd.is_empty() or (fd.get("frames", []) as Array).is_empty():
		return null
	var c := ReactableCells.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_data(fd, r)
	return c


func set_data(fd: Dictionary, r: Dictionary) -> void:
	fps = int(fd.get("fps", 60))
	fd_src = fd
	rv_src = r
	cells = colours(fd, r)
	queue_redraw()


static func colours(fd: Dictionary, r: Dictionary) -> Array:
	var fr: Array = fd.get("frames", [])
	var out := []
	var runs: Array = r.get("runs", [])
	for i in fr.size():
		var col := COL_IDLE
		if bool(fr[i]["active"]):
			col = COL_ACT
		else:
			for run in runs:
				if i >= int(run["readable"]) and i < int(run["first_active"]):
					col = ReactableStrip.COL_OK if run["status"] == "reactable" else ReactableStrip.COL_NO
					break
		out.append(col)
	return out


## the state of frame i for words: "active" | "tell" | "idle" (and the run number of a tell / active frame, 0 for idle)
static func state_at(fd: Dictionary, r: Dictionary, i: int) -> Dictionary:
	var fr: Array = fd.get("frames", [])
	if i < 0 or i >= fr.size():
		return {}
	var runs: Array = r.get("runs", [])
	if bool(fr[i]["active"]):
		var k := 0
		for run in runs:
			if int(run["first_active"]) <= i:
				k = int(run["n"])
		return {"frame": i, "state": "active", "run": k}
	for run in runs:
		if i >= int(run["readable"]) and i < int(run["first_active"]):
			return {"frame": i, "state": "tell", "run": int(run["n"]), "status": run["status"]}
	return {"frame": i, "state": "idle", "run": 0}


## WCAG relative luminance and contrast ratio of two colours
static func rel_lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


static func ratio(a: Color, b: Color) -> float:
	var la := rel_lum(a)
	var lb := rel_lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## a tell cell's colour as drawn: the verdict hue pushed to black or white (whichever separates it more) until it is >= 3.2:1 against the
## strip's startup block, so it reads next to it (the plain green/red sat at 1.3:1 against the green startup block)
static func tell_col(base: Color, startup: Color) -> Color:
	var best := base
	var best_r := ratio(base, startup)
	for target in [Color.BLACK, Color.WHITE]:
		for k in range(1, 21):
			var c := base.lerp(target, k / 20.0)
			var r := ratio(c, startup)
			if r >= 3.2:
				if best_r < 3.2 or r < best_r:   # the first (closest to the hue) that clears the bar
					best = c
					best_r = r
				break
	return best


func shown_col(i: int) -> Color:
	var c: Color = cells[i]
	if c == ReactableStrip.COL_OK or c == ReactableStrip.COL_NO:
		return tell_col(c, Tok.c("fd_startup"))
	return c


## the words for the cell under local x (a tooltip): its frame, its time and its state
func tip_at(x: float) -> String:
	for i in cells.size():
		var x0: float = xmap.call(float(i) / float(fps)) if xmap.is_valid() else 20.0 + i * 6.0
		var x1: float = xmap.call(float(i + 1) / float(fps)) if xmap.is_valid() else x0 + 6.0
		if x >= x0 and x < x1:
			var st := state_at(fd_src, rv_src, i)
			if st.is_empty():
				return ""
			var words: String = {"active": "active: a hitbox is out", "idle": "idle"}.get(st["state"], "")
			if st["state"] == "tell":
				words = "the tell of strike %d: %s" % [int(st["run"]), "readable, a defender can react" if st.get("status", "") == "reactable" else "NOT reactable in time"]
			return "frame %d (%.3f s): %s" % [i, float(i) / float(fps), words]
	return ""


func _draw() -> void:
	for i in cells.size():
		var x0: float = xmap.call(float(i) / float(fps)) if xmap.is_valid() else 20.0 + i * 6.0
		var x1: float = xmap.call(float(i + 1) / float(fps)) if xmap.is_valid() else x0 + 6.0
		draw_rect(Rect2(x0, 0.0, maxf(x1 - x0 - 0.5, 1.0), H), shown_col(i))
