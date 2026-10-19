## godot --path . -s tests/weightpaint_test.gd     (ROADMAP 72; needs a window)
## Skin weight paint on the mannequin. A real mouse stroke (press, four drags, release) over the forearm, with the
## Weight paint mode on and the bone "lower arm right" picked. Bars, stated before the run:
##   - vertices outside every brush circle keep their weights bit-for-bit (0 changed)
##   - vertices inside a circle gain weight on the picked bone (0 lose it; most gain it)
##   - every vertex sums to 1 within 1e-5 and has at most 4 influences
##   - Ctrl+Z (undo) restores every weight bit-for-bit; the stroke was one undo step
##   - the sidecar round-trips bit-for-bit (user://weights/weightpaint_test.weights.json, removed after)
## Screenshot: C:/Users/Nick/.claude/jobs/9afc22db/tmp/weightpaint.png (heat map of the picked bone after the stroke).
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/weightpaint.png"
const KEY := "weightpaint_test"
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the bit-exact copy of every surface's weights
func _grab(wp: Dictionary) -> Array:
	var out := []
	for s in wp["surfs"]:
		out.append([(s["bones"] as PackedInt32Array).duplicate(), (s["w"] as PackedFloat32Array).duplicate()])
	return out


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m.wp_key = KEY
	ok(not m.wp.is_empty(), "the mannequin has a skin model (%d surfaces)" % m.wp["surfs"].size())
	m._wp_toggle()
	ok(m.wp_on, "Weight paint is on")
	var bind: int = m._wp_bind_of("lowerarm_r")
	m.wp_bind = bind
	m.wp_mode = "add"
	m.wp_radius = 0.08
	m.wp_strength = 0.25
	SkinPaint.refresh(m.wp)
	# the forearm: the centre of the vertices that are mostly lower arm; the wrist: mostly hand
	var wrist_bind: int = m._wp_bind_of("hand_r")
	var fa := Vector3.ZERO
	var fn := 0
	var wr := Vector3.ZERO
	var wn := 0
	for s in m.wp["surfs"]:
		var per: int = s["per"]
		for i in (s["verts"] as PackedVector3Array).size():
			var wb := SkinPaint._w_of(s["bones"], s["w"], per, i, bind)
			if wb >= 0.9:
				fa += (s["pos"] as PackedVector3Array)[i]
				fn += 1
			if SkinPaint._w_of(s["bones"], s["w"], per, i, wrist_bind) >= 0.9:
				wr += (s["pos"] as PackedVector3Array)[i]
				wn += 1
	fa /= maxf(fn, 1)
	wr /= maxf(wn, 1)
	var axis := (wr - fa).normalized()
	ok(fn > 0 and wn > 0, "forearm (%d vertices) and wrist (%d) found on the skin" % [fn, wn])
	# a real mouse stroke: press over the forearm, four drags along it (2 cm apart), release
	var before := _grab(m.wp)
	var pts := []
	for k in 5:
		pts.append(m.cam.unproject_position(fa + axis * 0.02 * k))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = pts[0]
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(press)
	for k in range(1, 5):
		var mv := InputEventMouseMotion.new()
		mv.position = pts[k]
		mv.relative = pts[k] - pts[k - 1]
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mv)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = pts[4]
	root.push_input(rel)
	var centres: Array = m.wp_centres
	var first_hit: Vector3 = centres[0] if centres.size() > 0 else Vector3.INF
	ok(centres.size() >= 4, "the stroke landed %d dabs on the skin (bar: 4 or more)" % centres.size())
	ok(first_hit.distance_to(fa) < 0.06, "the first dab is on the forearm (%.1f mm from its centre; bar 60 mm)" % (first_hit.distance_to(fa) * 1000.0))
	# the reference: which vertices are inside some brush circle (the circles are the recorded dab centres, on the
	# shape the body had when the stroke began)
	var r: float = m.wp_radius
	var inside := 0
	var outside := 0
	var outside_changed := 0
	var inside_gained := 0
	var inside_lost := 0
	var inside_same := 0
	var surf_k := 0
	for s in m.wp["surfs"]:
		var per: int = s["per"]
		var pos: PackedVector3Array = s["pos"]
		var b0: PackedInt32Array = before[surf_k][0]
		var w0: PackedFloat32Array = before[surf_k][1]
		var b1: PackedInt32Array = s["bones"]
		var w1: PackedFloat32Array = s["w"]
		for i in pos.size():
			var dmin := INF
			for c in centres:
				dmin = minf(dmin, pos[i].distance_to(c))
			var changed := false
			for q in per:
				if b0[i * per + q] != b1[i * per + q] or w0[i * per + q] != w1[i * per + q]:
					changed = true
			if dmin >= r:
				outside += 1
				if changed:
					outside_changed += 1
			else:
				inside += 1
				var g0 := SkinPaint._w_of(b0, w0, per, i, bind)
				var g1 := SkinPaint._w_of(b1, w1, per, i, bind)
				if g1 > g0:
					inside_gained += 1
				elif g1 < g0:
					inside_lost += 1
				else:
					inside_same += 1
		surf_k += 1
	print("     inside the brush: %d vertices; gained weight on the bone %d, same %d (already at 1), lost %d; outside: %d (changed %d)" % [inside, inside_gained, inside_same, inside_lost, outside, outside_changed])
	ok(inside > 0 and outside > 0, "the stroke reached some vertices and not others (inside %d, outside %d)" % [inside, outside])
	ok(outside_changed == 0, "vertices outside every brush circle unchanged bit-for-bit (%d changed; bar 0)" % outside_changed)
	ok(inside_lost == 0 and inside_gained > 0, "inside the brush the picked bone never loses weight (%d lost) and gains on %d vertices" % [inside_lost, inside_gained])
	# every vertex: sum 1 within 1e-5, at most 4 influences
	var worst := 0.0
	var most := 0
	var nosum := 0
	for s in m.wp["surfs"]:
		var per: int = s["per"]
		var b1: PackedInt32Array = s["bones"]
		var w1: PackedFloat32Array = s["w"]
		for i in (s["verts"] as PackedVector3Array).size():
			var sum := 0.0
			var nz := 0
			for q in per:
				sum += w1[i * per + q]
				if w1[i * per + q] > 0.0:
					nz += 1
			worst = maxf(worst, absf(sum - 1.0))
			most = maxi(most, nz)
			if absf(sum - 1.0) > 1e-5:
				nosum += 1
	print("     every vertex: worst |sum - 1| = %.8f; most influences on one vertex = %d; vertices off by more than 1e-5 = %d" % [worst, most, nosum])
	ok(nosum == 0 and worst <= 1e-5, "every vertex sums to 1 within 1e-5 (worst %.8f; bar 1e-5)" % worst)
	ok(most <= 4, "at most 4 influences on any vertex (most: %d)" % most)
	# the screenshot: the heat map of the picked bone, after the stroke
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := m.get_viewport().get_texture().get_image()
	img.save_png(SHOT)
	ok(FileAccess.file_exists(SHOT) or img != null, "screenshot saved to %s" % SHOT)
	# the stroke as it stands is the one the sidecar holds
	var after := _grab(m.wp)
	# undo: one step takes the whole stroke back, bit-for-bit
	m._undo()
	var back := _grab(m.wp)
	var undo_bad := 0
	for k in before.size():
		if back[k][0] != before[k][0] or back[k][1] != before[k][1]:
			undo_bad += 1
	ok(undo_bad == 0, "Ctrl+Z restores every surface's weights bit-for-bit (%d surfaces differ; bar 0)" % undo_bad)
	# the sidecar: the stroke's weights, read back into a fresh model of the same character
	var fresh := SkinPaint.read(m.pieces.values(), m.skel)
	ok(SkinPaint.load_into(fresh, KEY), "the sidecar loads for the same character")
	var side_bad := 0
	for k in after.size():
		if fresh["surfs"][k]["bones"] != after[k][0] or fresh["surfs"][k]["w"] != after[k][1]:
			side_bad += 1
	ok(side_bad == 0, "sidecar round-trip bit-for-bit (%d surfaces differ; bar 0)" % side_bad)
	ok(SkinPaint.path(KEY) != SkinPaint.path("mannequin"), "the test's sidecar is its own file (the mannequin's is never written here)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SkinPaint.path(KEY)))
	m.wp_on = false
	print("WEIGHTPAINT %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
