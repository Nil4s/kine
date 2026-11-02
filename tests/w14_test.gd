extends SceneTree
## W14: injected adapter list [Intel, NVIDIA], Intel active -> warning + Windows Graphics steps; single GPU -> no warning.
## CONTROL: the old behaviour (plain "in use" line) fails the warning bar.
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
func _init() -> void:
	var intel := "Intel(R) UHD Graphics 770"
	var nv := "NVIDIA GeForce RTX 3070"
	var l1 := GpuNotice.line([intel, nv], intel)
	ok(l1.contains("integrated") and l1.contains(nv) and l1.contains(intel), "dual, Intel active: warning names both")
	ok(l1.contains("Graphics") and l1.contains("High performance") and l1.contains("Browse"), "steps present")
	var l2 := GpuNotice.line([intel], intel)
	ok(not l2.contains("integrated") and not l2.contains("High performance"), "single Intel: no warning")
	var l3 := GpuNotice.line([nv], nv)
	ok(not l3.contains("integrated") and l3.contains(nv), "single NVIDIA: names GPU, no warning")
	var l4 := GpuNotice.line([intel, nv], nv)
	ok(not l4.contains("High performance"), "dual, NVIDIA active: no warning")
	var ctl := "Graphics card in use: " + intel
	ok(not (ctl.contains("integrated") and ctl.contains("High performance")), "CONTROL: plain line fails the warning bar")
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	ok(src.contains("GpuNotice.line("), "main.gd shows the line at start")
	print("W14 fails=", fails)
	quit(1 if fails else 0)
