## godot --path . -s tests/s259_test.gd   (item 259: playblast motion blur options; needs a window, it renders)
## A Part body (a long bar) spins at 300 deg/frame about the view axis; the frame is rendered through main._blast_frame.
## BARS (stated before measuring):
##   1 SPIN: pixels whose value varies across the sharp sub-steps (per-pixel variance > 0): > 500 of them
##   2 SMEAR: the blurred frame differs from the sharp one in > 500 pixels
##   3 STATIC: with the spin off, blurred frame == sharp frame byte for byte
##   4 OFF: blur off == a hand capture of the viewport at t, byte for byte
##   5 OPTIONS: shutter 0.25 smears fewer pixels than 1.0; 16 steps give a different frame than 4; defaults are 0.5 and 8
##   6 CONTROL: a planted wrong value (sharp frame at a different time) must fail bar 3's comparison
extends SceneTree
var fails := 0
var m: Node
var bar: MeshInstance3D
var spin := true
const FPS := 24


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func hook(t: float) -> void:
	bar.rotation = Vector3(0, 0, deg_to_rad(300.0 * t * FPS) if spin else 0.0)


func ndiff(a: Image, b: Image) -> int:
	var da := a.get_data()
	var db := b.get_data()
	var c := 0
	for i in range(0, da.size(), 3):
		if da[i] != db[i] or da[i + 1] != db[i + 1] or da[i + 2] != db[i + 2]:
			c += 1
	return c


func _init() -> void:
	var ps: PackedScene = load("res://main.tscn")
	m = ps.instantiate()
	root.add_child(m)
	await idle(8)
	m.wt.render_on = false
	bar = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 0.25, 0.25)
	bar.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.2, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar.material_override = mat
	m.add_child(bar)
	bar.position = Vector3(0, 1.4, 0)
	m.clean = true
	m._sides_apply()
	m.ui_root.visible = false
	m.dist = 8.0
	m.target = Vector3(0, 1.4, 0)
	m._refresh()
	m._cam()
	BlastBlur.time_hook = hook
	await idle(3)
	var t0 := 0.25
	var hi := 2.0
	ok(m.blast_blur == false and m.blast_shutter == 0.5 and m.blast_blur_n == 8, "0 defaults: blur off, shutter 0.5, 8 steps")
	var sharp: Image = await m._blast_frame({}, t0, FPS, 0.0, hi)
	# 4 off == hand capture
	m.playhead = t0
	m._ps().apply(m.B, t0)
	hook(t0)
	m._refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	var hand: Image = root.get_viewport().get_texture().get_image()
	ok(sharp.get_data() == hand.get_data(), "4 blur off is byte-identical to a hand capture at t")
	# 1 variance across sub-steps
	var ts := PlayblastExport.shutter_times(t0, FPS, 8, 0.0, hi)
	var subs := []
	for tt in ts:
		subs.append(await m._blast_frame({}, tt, FPS, 0.0, hi))
	var d0: PackedByteArray = (subs[0] as Image).get_data()
	var varpx := 0
	for i in range(0, d0.size(), 3):
		var mn := 255
		var mx := 0
		for im in subs:
			var v: int = (im as Image).get_data()[i]
			mn = mini(mn, v)
			mx = maxi(mx, v)
		if mx > mn:
			varpx += 1
	ok(varpx > 500, "1 per-pixel variance across the 8 sub-steps > 0 in %d pixels (bar > 500)" % varpx)
	m.blast_blur = true
	var blur: Image = await m._blast_frame({}, t0, FPS, 0.0, hi)
	var nd := ndiff(blur, sharp)
	ok(nd > 500, "2 the averaged frame differs from the sharp one in %d pixels (bar > 500)" % nd)
	# 5 options
	m.blast_shutter = 0.25
	var b25: Image = await m._blast_frame({}, t0, FPS, 0.0, hi)
	m.blast_shutter = 1.0
	var b100: Image = await m._blast_frame({}, t0, FPS, 0.0, hi)
	var d25 := ndiff(b25, sharp)
	var d100 := ndiff(b100, sharp)
	ok(d25 < d100, "5 shutter 0.25 changes %d pixels, shutter 1.0 changes %d" % [d25, d100])
	m.blast_shutter = 0.5
	m.blast_blur_n = 4
	var n4: Image = await m._blast_frame({}, t0, FPS, 0.0, hi)
	m.blast_blur_n = 16
	var n16: Image = await m._blast_frame({}, t0, FPS, 0.0, hi)
	ok(ndiff(n4, n16) > 0, "5 4 steps vs 16 steps give different frames (%d px)" % ndiff(n4, n16))
	m.blast_blur_n = 8
	# 3 static
	spin = false
	m.blast_blur = false
	var ssharp: Image = await m._blast_frame({}, t0, FPS, 0.0, hi)
	m.blast_blur = true
	var sblur: Image = await m._blast_frame({}, t0, FPS, 0.0, hi)
	ok(ssharp.get_data() == sblur.get_data(), "3 static scene: blurred frame identical to the sharp one")
	# 6 control
	spin = true
	var other: Image = await m._blast_frame({}, t0 + 0.0125, FPS, 0.0, hi)
	m.blast_blur = false
	var wrong: Image = await m._blast_frame({}, t0 + 0.0125, FPS, 0.0, hi)
	ok(ndiff(wrong, ssharp) > 0 and other.get_data() != ssharp.get_data(), "6 control: a frame at another time differs from the static one, so the equality bar can fail")
	BlastBlur.time_hook = Callable()
	print("s259: %d fail" % fails)
	quit(fails)
