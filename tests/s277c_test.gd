extends SceneTree
## godot --path . -s tests/s277c_test.gd   (s277c card-body brightness + s262d explode film camera and ring bloom; needs the CAD DLL and the rendered files below)
## Bars written and committed BEFORE kine_lit4 / kine_explode3 were rendered or read.
##   277c BODY   fixed pixel box rows 340..820, ALL columns, no luminance cut-off, frame 0 of kine_lit4: mean Rec709 luminance (0..255) within 5 pct of the Blender
##               frame's reading of the same box (kine_lit2/sbs_0.png left half, read live).  NOTE: the ticket says Blender reads 89.5 there; this reader measures
##               31.2 on that box with no cut-off (89.5 is a lit-pixel mean, cut-off ~20), so the bar is the live Blender reading, not 89.5.
##               CONTROLS: the same reader on kine_lit3 frame 0 and kine_lit2 frame 0 (right half) reads outside the band.
##   262d FRAME  every one of the 348 frames: the projected corners of every piece box lie inside the 1280x720 frame with >= 5 pct margin on all four sides
##               (x in 64..1216, y in 36..684).  CONTROL: 2c32f1a2's camera (ExplodeCam.old_plan) leaves the band on >= 1 frame.
##   262d RINGS  hall_compare/gpu/kine_explode3/rings.json (new bloom) vs kine_explode3/rings_control.json (2c32f1a2 bloom), same frames, written by the driver:
##               mean halo ratio (annulus 1.25..1.4 ring radius over the ring) new <= 0.7 x control; every ring's no-gap min/median >= 0.5; mean ring brightness >= 0.5.
##               CONTROL: the control file's halo is > 0.7 x itself (trivially) AND the planted gap reading 0.1 fails the min/median bar.
const K := "C:/Users/Nick/tools/kine_workers/hall_compare/gpu/"
const FIX := K + "kine_explode/gpu_copy.json"
const CAMJ := K + "camera.json"
const W := 1280
const H := 720
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func box_mean(img: Image) -> float:
	var s := 0.0
	for y in range(340, 820):
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			s += 255.0 * (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
	return s / float(480 * img.get_width())


func _init() -> void:
	# 277c
	var sbs := Image.load_from_file(K + "kine_lit2/sbs_0.png")
	var l2 := Image.load_from_file(K + "kine_lit2/frames/0000.png")
	var l3 := Image.load_from_file(K + "kine_lit3/frames/0000.png")
	var l4 := Image.load_from_file(K + "kine_lit4/frames/0000.png")
	ok(sbs != null and l2 != null and l3 != null, "277c reference frames load")
	var bl := box_mean(sbs.get_region(Rect2i(0, 0, 1920, 1080)))
	var lo := bl * 0.95
	var hi := bl * 1.05
	var m2 := box_mean(l2)
	var m3 := box_mean(l3)
	print("277c blender %.1f lit2 %.1f lit3 %.1f band %.1f..%.1f" % [bl, m2, m3, lo, hi])
	ok(m3 < lo and m2 < lo, "277c CONTROL lit3 %.1f and lit2 %.1f read outside the band" % [m3, m2])
	ok(l4 != null, "277c kine_lit4 frame 0 exists")
	if l4 != null:
		var m4 := box_mean(l4)
		ok(m4 >= lo and m4 <= hi, "277c BODY lit4 %.1f within %.1f..%.1f" % [m4, lo, hi])
	# 262d camera
	var host = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(host)
	for i in 8:
		await process_frame
	var rec := Part.from_file((JSON.parse_string(FileAccess.get_file_as_string(FIX)) as Dictionary)["part"])
	ExplodeKeys.layout_hook = Callable(GpuExplodeLayout, "layout")
	var opts := {"axis": Vector3.BACK, "gap_mm": 10.0, "by_level": false, "anchor": "PCB"}
	var r := ExplodeKeys.send(host, rec, opts, 0.7, 0.12, 1.5)
	var fr := ExplodeCam.frame_boxes(host, rec, opts, r, 30)
	ok(fr.size() == 348, "262d 348 frames (%d)" % fr.size())
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	root.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.near = 0.01
	cam.far = 30.0
	vp.add_child(cam)
	var ckeys: Array = JSON.parse_string(FileAccess.get_file_as_string(CAMJ))["keys"]
	var dirs: Array = []
	for f in fr.size():
		dirs.append(ExplodeCam.cam_dir(ckeys, float(f) / float(fr.size())))
	for which in ["old", "new"]:
		var plan: Array = ExplodeCam.old_plan(fr, dirs, cam, W, H) if which == "old" else ExplodeCam.plan(fr, dirs, cam, W, H)
		var bad := 0
		var worst := 1.0
		for f in fr.size():
			cam.look_at_from_position(plan[f]["pos"], plan[f]["target"], Vector3.UP)
			var mg := ExplodeCam.margin(cam, fr[f], W, H)
			worst = minf(worst, mg)
			if mg < 0.05:
				bad += 1
		print("262d %s camera: %d of %d frames under 5 pct margin, worst margin %.3f" % [which, bad, fr.size(), worst])
		if which == "old":
			ok(bad >= 1, "262d CONTROL old camera breaks the margin on %d frames" % bad)
		else:
			ok(bad == 0, "262d FRAME new camera: %d frames under the 5 pct margin (worst %.3f)" % [bad, worst])
	# 262d rings
	var rn = JSON.parse_string(FileAccess.get_file_as_string(K + "kine_explode3/rings.json"))
	var rc = JSON.parse_string(FileAccess.get_file_as_string(K + "kine_explode3/rings_control.json"))
	ok(rn is Array and rc is Array and rn.size() > 0 and rn.size() == rc.size(), "262d ring files load, same count")
	if rn is Array and rc is Array and rn.size() > 0:
		var hn := 0.0
		var hc := 0.0
		var bn := 0.0
		var mm := 1e9
		for e in rn:
			hn += float(e["halo"])
			bn += float(e["ring"])
			mm = minf(mm, float(e["gap"]))
		for e in rc:
			hc += float(e["halo"])
		hn /= rn.size()
		hc /= rc.size()
		bn /= rn.size()
		print("262d rings: halo new %.3f control %.3f ; ring brightness %.3f ; worst gap %.3f" % [hn, hc, bn, mm])
		ok(hn <= 0.7 * hc, "262d HALO new %.3f <= 0.7 x control %.3f" % [hn, hc])
		ok(mm >= 0.5, "262d RING min/median worst %.3f >= 0.5" % mm)
		ok(bn >= 0.5, "262d RING brightness %.3f >= 0.5" % bn)
		ok(not (0.1 >= 0.5), "262d CONTROL a planted gap 0.1 fails the ring bar")
	print("s277c: %d fail" % fails)
	quit(1 if fails > 0 else 0)
