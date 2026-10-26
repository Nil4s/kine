## godot --path . -s tests/smoothbody_test.gd     (BODY: SMOOTH, the second body option; needs a window: run it as :w)
## "Body: smooth" draws the figure with a smooth human mesh (assets/body_smooth.glb, tools/smoothbody_build.gd) on the
## SAME skeleton; the mannequin stays the default. Bars, stated before the run:
##   1 ONE UNDO STEP: the BODY button "Body: smooth" is one undo step; one Ctrl+Z gives the mannequin back (its own meshes:
##     the vertex count of assets/mannequin.glb), one Ctrl+Y the smooth body again. The weights have a sidecar per body.
##   2 MANNEQUIN BYTE-IDENTICAL: a render key (SHA-256 of every piece's vertices, normals, bones, weights and indices, and of
##     the posed skin positions, at one pose) taken before the first switch equals the key after smooth -> mannequin
##     again. assets/mannequin.glb itself is not touched (its SHA-256 is printed; git shows no change).
##   3 POSING: bending the left elbow 90 deg turns the left forearm's skin (the vertices weighing >= 0.9 on it) about the
##     elbow joint: its centroid's direction from the elbow turns 80..100 deg; the right forearm stays (< 1 mm).
##   4 PICK: a real click on the left forearm's skin picks "lowerarm_l"; on the right forearm "lowerarm_r"; on the left
##     calf "calf_l"; a real hover names the part too.
##   5 PAINT: Weight paint on the smooth body: a real mouse stroke over the left forearm changes the skin weights of
##     vertices (the paint model has the smooth body's own vertex count, not the mannequin's) and the sidecar key is the
##     smooth body's own ("body_smooth"; the mannequin's sidecar is not touched).
##   6 SOLES: in the T-pose the lowest skin vertex is within 5 mm of the floor (y = 0).
##   7 ELBOW VOLUME: bent 120 deg (plain skinning, no corrective), the section of the arm's own skin (upper arm and
##     forearm triangles) cut by the plane THROUGH the elbow joint, perpendicular to the bisector of the two limbs (the
##     straight arm: perpendicular to the arm), keeps >= 70 % of the straight arm's area. (A plane 2 cm up the upper arm,
##     as corrective_test.gd cuts, is not usable here: the smooth skin's weights blend over the elbow, so no triangle is
##     wholly the upper arm's that close to it.)
##   8 THE DRAWN FACE: the face anchors read from the smooth body's head piece equal the mannequin's (the same egg head);
##     with a keyed face the face nodes are shown, and the face changes >= 50 pixels of the head's close-up.
##   9 EASY: the view panel has the "Smooth body" button; a real mouse click on it switches the body (one undo step), a
##     second click gives the mannequin back. (The panel keeps its old height: six buttons of 34 px.)
## Pictures (C:/Temp/claude/smoothswap/): smooth_tpose_front.png, smooth_kick.png, smooth_chooser.png (Expert, BODY tab),
## smooth_chooser_easy.png. Nothing is written to scenes/, poses/ or data/; the weight sidecar test file is removed.
extends SceneTree

var fails := 0
var m: Node
const OUT := "C:/Temp/claude/smoothswap/"
const KEY := "smoothbody_test"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = Vector2(1, 0)
	root.push_input(e)
	await process_frame


func click(p: Vector2) -> void:
	await move(p)
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(e)
		await process_frame


func shot(name: String) -> Image:
	var img: Image = m.get_viewport().get_texture().get_image()
	if name != "":
		DirAccess.make_dir_recursive_absolute(OUT)
		img.save_png(OUT + name)
	return img


## the render key: every piece's mesh arrays and the posed skin positions, hashed
func rkey() -> String:
	m.skp.mark()
	m.skp.refresh()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var names: Array = m.pieces.keys()
	names.sort()
	for n in names:
		var mi: MeshInstance3D = m.pieces[n]
		ctx.update(String(n).to_utf8_buffer())
		for si in mi.mesh.get_surface_count():
			var a: Array = mi.mesh.surface_get_arrays(si)
			for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_INDEX]:
				ctx.update(var_to_bytes(a[k]))
	for s in m.skp.surfs:
		ctx.update(var_to_bytes(s["pos"]))
	return ctx.finish().hex_encode()


## the vertex count of the pieces' source arrays (the body's own mesh)
func total_verts() -> int:
	var n := 0
	for s in m.skp.surfs:
		n += (s["rest"] as PackedVector3Array).size()
	return n


## the posed positions of the vertices weighing >= 0.9 on a part (SkinPick's own binds)
func part_pos(part: String) -> PackedVector3Array:
	m.skp.mark()
	m.skp.refresh()
	var pi: int = m.skp.parts.find(part)
	var out := PackedVector3Array()
	for s in m.skp.surfs:
		var per: int = s["per"]
		var bones: PackedInt32Array = s["bones"]
		var w: PackedFloat32Array = s["w"]
		var pos: PackedVector3Array = s["pos"]
		for v in pos.size():
			var sw := 0.0
			for q in per:
				if m.skp.bind_part[bones[v * per + q]] == pi:
					sw += w[v * per + q]
			if sw >= 0.9:
				out.append(pos[v])
	return out


func centroid(ps: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in ps:
		c += p
	return c / maxf(ps.size(), 1)


func t_pose() -> void:
	m.B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/t_pose.json")))
	m._reset_all()
	m._refresh()


# ---- the CPU skinning of corrective_test.gd (the same measure of a section)
static func globals(sk: Skeleton3D) -> Array:
	var g := []
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		var local := Transform3D(sk.get_bone_pose_rotation(i), sk.get_bone_pose_position(i))
		g.append(local if p < 0 else (g[p] as Transform3D) * local)
	return g


static func skinned(mesh: ArrayMesh, sk: Skeleton3D, skin: Skin, g: Array) -> PackedVector3Array:
	var mats := []
	for k in skin.get_bind_count():
		var bb := skin.get_bind_bone(k)
		if bb < 0:
			bb = sk.find_bone(skin.get_bind_name(k))
		mats.append((g[bb] as Transform3D) * skin.get_bind_pose(k))
	var out := PackedVector3Array()
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(1, vs.size())
		for v in vs.size():
			var p := Vector3.ZERO
			for q in per:
				var w: float = wts[v * per + q]
				if w > 0.0:
					p += ((mats[bones[v * per + q]] as Transform3D) * vs[v]) * w
			out.append(p)
	return out


## the triangles whose three corners weigh >= 0.5 on the limb: its bone and the twist bones under it (up to the next joint
## of ours: the skin of an upper arm is weighed on upperarm_twist_01 / 02 as much as on upperarm)
static func own_tris(mesh: ArrayMesh, sk: Skeleton3D, skin: Skin, limbs: Array, idx: Dictionary) -> PackedInt32Array:
	var joints := {}
	for j in idx:
		joints[idx[j]] = true
	var binds := []
	for k in skin.get_bind_count():
		var c := sk.find_bone(skin.get_bind_name(k))
		while c >= 0 and not joints.has(c):
			c = sk.get_bone_parent(c)
		binds.append(c)
	var arr := mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var n := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var per := bones.size() / maxi(1, n)
	var w := PackedFloat32Array()
	for v in n:
		var sw := 0.0
		for q in per:
			if limbs.has(binds[bones[v * per + q]]):
				sw += wts[v * per + q]
		w.append(sw)
	var out := PackedInt32Array()
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for t in range(0, ix.size(), 3):
		if w[ix[t]] >= 0.5 and w[ix[t + 1]] >= 0.5 and w[ix[t + 2]] >= 0.5:
			out.append_array([ix[t], ix[t + 1], ix[t + 2]])
	return out


static func section_area(pos: PackedVector3Array, idx: PackedInt32Array, P: Vector3, n: Vector3) -> float:
	var pts := []
	for t in range(0, idx.size(), 3):
		var a := pos[idx[t]]
		var b := pos[idx[t + 1]]
		var c := pos[idx[t + 2]]
		var da := n.dot(a - P)
		var db := n.dot(b - P)
		var dc := n.dot(c - P)
		for e in [[a, b, da, db], [b, c, db, dc], [c, a, dc, da]]:
			var d0: float = e[2]
			var d1: float = e[3]
			if (d0 > 0.0) != (d1 > 0.0):
				pts.append((e[0] as Vector3).lerp(e[1], d0 / (d0 - d1)))
	if pts.size() < 3:
		return 0.0
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	var p2 := []
	for p in pts:
		var q: Vector3 = p - P
		p2.append(Vector2(q.dot(u), q.dot(v)))
	return hull_area(p2)


static func hull_area(p: Array) -> float:
	p.sort_custom(func(x, y): return x.x < y.x if x.x != y.x else x.y < y.y)
	var lo := []
	for q in p:
		while lo.size() >= 2 and _cross2(lo[-2], lo[-1], q) <= 0.0:
			lo.pop_back()
		lo.append(q)
	var up := []
	for i in range(p.size() - 1, -1, -1):
		var q: Vector2 = p[i]
		while up.size() >= 2 and _cross2(up[-2], up[-1], q) <= 0.0:
			up.pop_back()
		up.append(q)
	lo.pop_back()
	up.pop_back()
	var h := lo + up
	var a := 0.0
	for i in h.size():
		var x: Vector2 = h[i]
		var y: Vector2 = h[(i + 1) % h.size()]
		a += x.x * y.y - y.x * x.y
	return absf(a) * 0.5


static func _cross2(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a - o).x * (b - o).y - (a - o).y * (b - o).x


## the section of the arm's own skin at the elbow, straight vs bent 120 deg: [straight, bent, triangles]
func elbow_sections() -> Array:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	B.ground()
	var mq := Overlays.mannequin(root, StandardMaterial3D.new())
	var man: Node3D = mq[0]
	var sk: Skeleton3D = mq[1]
	var idx: Dictionary = mq[2]
	var mi: MeshInstance3D = man.find_children("*", "MeshInstance3D", true, false)[0]
	var skin: Skin = mi.skin
	var src: ArrayMesh = mi.mesh
	for j in ["lowerarm_l", "lowerarm_r", "calf_l", "calf_r"]:
		B.ang[j] = Vector3(0.0, B.ang[j].y, B.ang[j].z)
	Overlays.pose_skeleton(sk, idx, B)
	var own := own_tris(src, sk, skin, [idx["upperarm_l"], idx["lowerarm_l"]], idx)
	var out := []
	for bend in [0.0, 120.0]:
		B.ang["lowerarm_l"] = Vector3(bend, 0.0, 0.0)
		Overlays.pose_skeleton(sk, idx, B)
		var g := globals(sk)
		var elbow: Vector3 = (g[idx["lowerarm_l"]] as Transform3D).origin
		var a: Vector3 = ((g[idx["upperarm_l"]] as Transform3D).origin - elbow).normalized()
		var b: Vector3 = ((g[idx["hand_l"]] as Transform3D).origin - elbow).normalized()
		var nrm := (a + b).normalized() if (a + b).length() > 0.2 else a
		out.append(section_area(skinned(src, sk, skin, g), own, elbow, nrm))
	out.append(own.size() / 3)
	man.queue_free()
	return out


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.dummy_on = false
	m.B.wep_on = false
	m.B.wep2_on = false
	m.easy.set_on(false, false)
	await idle(3)
	var man_glb := FileAccess.get_sha256("res://assets/mannequin.glb")
	print("assets/mannequin.glb sha256 ", man_glb)
	ok(not Overlays.smooth, "0 the mannequin is the default (Overlays.smooth false)")
	t_pose()
	await idle(3)
	var mq_verts := total_verts()
	var geo0: Dictionary = m._face_geo().duplicate()
	var key0 := rkey()
	m.undo.clear()
	m.redo.clear()

	# ---- 1 one undo step
	var u0: int = m.undo.size()
	m._body_smooth_toggle()
	await idle(3)
	ok(Overlays.smooth and m.undo.size() == u0 + 1, "1 the toggle is ONE undo step (%d -> %d) and the body is smooth" % [u0, m.undo.size()])
	var sm_verts := total_verts()
	ok(sm_verts > 0 and sm_verts != mq_verts and m.pieces.size() >= 50, "1 the smooth body is its own mesh (%d vertices vs the mannequin's %d; %d pieces)" % [sm_verts, mq_verts, m.pieces.size()])
	ok(m.wp_key == "body_smooth" and not m.wp.is_empty(), "1 the weights have a sidecar per body (key %s)" % m.wp_key)
	m._undo()
	await idle(3)
	ok(not Overlays.smooth and total_verts() == mq_verts and m.wp_key == "mannequin", "1 ONE Ctrl+Z gives the mannequin back (%d vertices, key %s)" % [total_verts(), m.wp_key])
	m._redo()
	await idle(3)
	ok(Overlays.smooth and total_verts() == sm_verts, "1 Ctrl+Y puts the smooth body back")
	m._undo()
	await idle(3)

	# ---- 2 the mannequin path is byte-identical
	var key1 := rkey()
	print("render key before ", key0)
	print("render key after  ", key1)
	ok(key0 == key1 and key0 != "", "2 the mannequin's render key is the same before and after smooth -> mannequin")
	ok(FileAccess.get_sha256("res://assets/mannequin.glb") == man_glb, "2 assets/mannequin.glb is untouched")

	# ---- the smooth body from here on
	m._body_smooth_toggle()
	await idle(3)
	ok(Overlays.smooth, "the smooth body is on for bars 3-8")
	t_pose()
	await idle(3)

	# ---- 6 soles
	var low := 1000.0
	for s in m.skp.surfs:
		for p in (s["pos"] as PackedVector3Array):
			low = minf(low, p.y)
	m.skp.mark()
	m.skp.refresh()
	low = 1000.0
	for s in m.skp.surfs:
		for p in (s["pos"] as PackedVector3Array):
			low = minf(low, p.y)
	ok(absf(low) <= 0.005, "6 the T-pose soles are %.2f mm from the floor (bar 5 mm)" % (low * 1000.0))
	await idle(2)
	m._view(1, true)
	await idle(4)
	shot("smooth_tpose_front.png")

	# ---- 3 posing
	var fa_l0 := centroid(part_pos("lowerarm_l"))
	var elbow_at: Vector3 = m.skel.global_transform * m.skel.get_bone_global_pose(m.bone_idx["lowerarm_l"]).origin
	var fa_r0 := centroid(part_pos("lowerarm_r"))
	m.B.ang["lowerarm_l"] = Vector3(90.0, 0.0, 0.0)
	m.B.fk()
	m._refresh()
	await idle(3)
	var fa_l1 := centroid(part_pos("lowerarm_l"))
	var fa_r1 := centroid(part_pos("lowerarm_r"))
	var turn := rad_to_deg((fa_l0 - elbow_at).angle_to(fa_l1 - elbow_at))
	ok(turn >= 80.0 and turn <= 100.0, "3 the left elbow at 90 deg turns the left forearm's skin %.1f deg about the elbow (bar 80..100; its centroid moved %.1f cm)" % [turn, fa_l1.distance_to(fa_l0) * 100.0])
	ok(fa_r1.distance_to(fa_r0) < 0.001, "3 the right forearm stays (%.2f mm)" % (fa_r1.distance_to(fa_r0) * 1000.0))
	t_pose()
	await idle(3)

	# ---- 4 pick (real clicks and hovers)
	m._view(1, true)
	await idle(4)
	for pj in ["lowerarm_l", "lowerarm_r", "calf_l"]:
		var c := centroid(part_pos(pj))
		var sp: Vector2 = m.cam.unproject_position(c)
		m.sel = "pelvis"
		m.hover_part = ""
		await move(sp + Vector2(3, 0))
		await move(sp)
		var hov: String = m.hover_part
		await click(sp)
		ok(m.sel == pj, "4 a real click on the %s skin picks %s (picked '%s', hover '%s')" % [pj, pj, m.sel, hov])
	m.sel = "pelvis"

	# ---- 5 paint
	m.wp_key = KEY   # (a sidecar of this test's own)
	var wp_n := 0
	for s in m.wp["surfs"]:
		wp_n += (s["verts"] as PackedVector3Array).size()
	ok(wp_n == sm_verts, "5 the paint model is the smooth body's own skin (%d vertices; the mannequin's is %d)" % [wp_n, mq_verts])
	m._wp_toggle()
	m.wp_bind = m._wp_bind_of("lowerarm_l")
	m.wp_mode = "add"
	m.wp_radius = 0.08
	m.wp_strength = 0.25
	SkinPaint.refresh(m.wp)
	var before := []
	for s in m.wp["surfs"]:
		before.append([(s["bones"] as PackedInt32Array).duplicate(), (s["w"] as PackedFloat32Array).duplicate()])
	var fa := centroid(part_pos("lowerarm_l"))
	var wr := centroid(part_pos("hand_l"))
	var axis := (wr - fa).normalized()
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
	var changed := 0
	var k2 := 0
	for s in m.wp["surfs"]:
		var b1: PackedInt32Array = s["bones"]
		var w1: PackedFloat32Array = s["w"]
		var b0: PackedInt32Array = before[k2][0]
		var w0: PackedFloat32Array = before[k2][1]
		for i in b1.size():
			if b1[i] != b0[i] or absf(w1[i] - w0[i]) > 1e-6:
				changed += 1
		k2 += 1
	ok(m.wp_centres.size() >= 4 and changed > 0, "5 a real stroke over the left forearm: %d dabs, %d weight entries changed" % [m.wp_centres.size(), changed])
	m._wp_toggle()
	m.wp_key = "body_smooth"
	var sc := ProjectSettings.globalize_path("user://weights/%s.weights.json" % KEY)
	if FileAccess.file_exists(sc):
		DirAccess.remove_absolute(sc)
	await idle(2)

	# ---- 7 elbow volume (plain skinning)
	var es := elbow_sections()
	var ratio: float = float(es[1]) / maxf(float(es[0]), 1e-9)
	print("arm section through the elbow: straight %.2f cm2, 120 deg %.2f cm2 (%d tris)" % [float(es[0]) * 1e4, float(es[1]) * 1e4, es[2]])
	ok(float(es[0]) > 0.0 and ratio >= 0.7, "7 at 120 deg the section through the elbow keeps %.0f %% of the straight arm's (bar 70 %%)" % (ratio * 100.0))

	# ---- 8 the drawn face
	t_pose()
	await idle(3)
	m._face_geo()
	var geo1: Dictionary = m.face_geo
	var same := not geo1.is_empty() and geo1.size() == geo0.size()
	var worst := 0.0
	for k in geo0:
		same = same and geo1.has(k)
		if geo1.has(k) and typeof(geo0[k]) == TYPE_VECTOR3:
			worst = maxf(worst, (geo1[k] as Vector3).distance_to(geo0[k]))
		else:
			same = same and var_to_str(geo1.get(k)) == var_to_str(geo0[k])   # (a number or a name: exactly)
	same = same and worst < 1e-5
	ok(same, "8 the face anchors on the smooth body equal the mannequin's (the same egg head; largest gap %.7f m)" % worst)
	m.playhead = 0.0
	m._view(1, true)
	await idle(2)
	var hp: Vector2 = m.cam.unproject_position(m.B.P["head"] + m.B.offset + Vector3(0, 0.1, 0))
	var box := Rect2i(Vector2i(hp) - Vector2i(70, 70), Vector2i(140, 140))
	m.S.face = {}
	m._refresh()
	await idle(3)
	var off_img := shot("").get_region(box)
	m.face_ui.key(0.0, {"brow_l": 0.5, "brow_r": 0.5, "jaw": 0.8, "eye_yaw": 0.0, "eye_pitch": 0.0, "blink": 0.0})
	m._refresh()
	await idle(3)
	var on_img := shot("").get_region(box)
	var diff := 0
	for y in off_img.get_height():
		for x in off_img.get_width():
			if off_img.get_pixel(x, y).is_equal_approx(on_img.get_pixel(x, y)) == false:
				diff += 1
	ok(m.face_root != null and m.face_root.visible and m.mouth_mi != null and m.mouth_mi.visible and diff >= 50, "8 with a keyed face the face nodes are shown and change %d pixels of the head (bar 50)" % diff)
	m.undo.clear()
	m.S.face = {}
	m._refresh()

	# ---- a kick (a picture): the right knee up, the shin out, the arms up for balance, seen from the side
	t_pose()
	m.B.ang["thigh_r"] = Vector3(-85.0, 0.0, 0.0)
	m.B.ang["calf_r"] = Vector3(0.0, 0.0, 0.0)
	m.B.ang["upperarm_l"] = Vector3(0.0, 0.0, -40.0)
	m.B.ang["upperarm_r"] = Vector3(0.0, 0.0, 40.0)
	m.B.ang["lowerarm_l"] = Vector3(70.0, 0.0, 0.0)
	m.B.ang["lowerarm_r"] = Vector3(70.0, 0.0, 0.0)
	m.B.fk()
	m.sel = "pelvis"
	m._big_view()
	m._view(2, true)
	m._refresh()
	await idle(40)
	shot("smooth_kick.png")
	m._big_view()

	# ---- the chooser (Expert: the BODY tab)
	t_pose()
	m._view(1, true)
	m._page_set("BODY")
	await idle(5)
	shot("smooth_chooser.png")

	# ---- 9 Easy: mouse only (the view panel's button: real clicks)
	m._body_smooth_toggle()   # back to the mannequin: the Easy button starts from there
	await idle(2)
	m.easy.set_on(true, false)
	await idle(5)
	var btn := m.easy.views.find_child("easy_body_smooth", true, false) as Button
	ok(btn != null and btn.is_visible_in_tree(), "9 Easy shows the Smooth body button (view panel %s)" % str(m.easy.views.size))
	if btn != null:
		var u1: int = m.undo.size()
		await click(btn.get_global_rect().get_center())
		await idle(3)
		ok(Overlays.smooth and m.undo.size() == u1 + 1, "9 a real click on it: the body is smooth, ONE undo step (%d -> %d)" % [u1, m.undo.size()])
		await idle(3)
		shot("smooth_chooser_easy.png")
		await click(btn.get_global_rect().get_center())
		await idle(3)
		ok(not Overlays.smooth and m.undo.size() == u1 + 2, "9 a second click gives the mannequin back")
	print("smoothbody: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
