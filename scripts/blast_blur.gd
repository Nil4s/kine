class_name BlastBlur
extends RefCounted
## Motion blur options for playblast and the shots-to-video render (item 259). The maths stays in PlayblastExport
## (shutter_times, average); this holds the choices (shutter 0.25 / 0.5 / 1.0 of the frame interval, 4 / 8 / 16 sub-frames),
## the dialog row, the per-frame time list and a per-sub-frame hook. Defaults: 0.5 shutter (180 deg) and 8 steps, so r3 holds.

const SHUTTERS := [0.25, 0.5, 1.0]
const STEPS := [4, 8, 16]

## called with every sub-frame time just after the pose is applied (lets a free Part body animate by time); empty = none
static var time_hook := Callable()


## shutter fraction of the frame interval -> shutter angle in degrees
static func angle_of(frac: float) -> float:
	return frac * 360.0


## the render times for a frame at t: [t] when blur is off (the old single render), else the shutter's sub-frame times
static func times(on: bool, t: float, fps: int, n: int, frac: float, lo: float, hi: float) -> Array:
	if not on:
		return [t]
	return PlayblastExport.shutter_times(t, fps, n, lo, hi, angle_of(frac))


static func on_time(t: float) -> void:
	if time_hook.is_valid():
		time_hook.call(t)


## the Export dialog's row: shutter and step choosers writing m.blast_shutter and m.blast_blur_n
static func controls(m: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "blast_blur_opts"
	var l := Label.new()
	l.text = "Motion blur shutter / sub-frames:"
	row.add_child(l)
	var sh := OptionButton.new()
	sh.name = "opt_blur_shutter"
	for f in SHUTTERS:
		sh.add_item("%s of a frame" % str(f))
	sh.select(SHUTTERS.find(m.blast_shutter) if SHUTTERS.has(m.blast_shutter) else 1)
	sh.item_selected.connect(func(i: int): m.blast_shutter = SHUTTERS[i])
	row.add_child(sh)
	var st := OptionButton.new()
	st.name = "opt_blur_steps"
	for n in STEPS:
		st.add_item("%d sub-frames" % n)
	st.select(STEPS.find(m.blast_blur_n) if STEPS.has(m.blast_blur_n) else 1)
	st.item_selected.connect(func(i: int): m.blast_blur_n = STEPS[i])
	row.add_child(st)
	return row
