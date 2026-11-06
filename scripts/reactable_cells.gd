## reactable_cells.gd - N082 on the frame-data strip (L11): one cell per frame of the clip, under the strip's phase blocks.
##   active frame -> COL_ACT; the TELL of a strike ([readable, first_active)) -> green when reactable, red when not (ReactableStrip's colours); else COL_IDLE.
## Built from FrameData.analyze's result and Reactable.analyze's verdict of it; the maths stays in reactable.gd.
class_name ReactableCells
extends Control

const COL_ACT := Color("2b2b33")
const COL_IDLE := Color(0.33, 0.33, 0.37, 0.55)
const H := 3.0

var cells: Array = []        # Color per frame
var fps := 60
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


func _draw() -> void:
	for i in cells.size():
		var x0: float = xmap.call(float(i) / float(fps)) if xmap.is_valid() else 20.0 + i * 6.0
		var x1: float = xmap.call(float(i + 1) / float(fps)) if xmap.is_valid() else x0 + 6.0
		draw_rect(Rect2(x0, 0.0, maxf(x1 - x0 - 0.5, 1.0), H), cells[i])
