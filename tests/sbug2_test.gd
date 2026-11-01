## godot --path . -s tests/sbug2_test.gd     (needs a window; run it with APPDATA pointed at a temp dir, see below)
## SBUG2 (Nick 11-01): "the body starts dissolving while moving and leaving parts behind, stretched or distorted".
## CAUSE: the painted-skin-weights sidecar (user://weights/mannequin.weights.json) was applied unchecked (SkinPaint.load_into,
## called by main._wp_setup). Nick's file had the right forearm's weight added over the whole body (feet included). At rest the
## skin is the same, the moment that forearm moves in a clip the whole body is dragged after it (edge stretch x28-x40).
## Dragging a hand in the stand pose could not show it, a clean user dir never has the file.
## BARS (the stretch of a mesh edge = its skinned length in the pose / its length in the unbent rest mesh):
##   1. every frame of every scene in res://scenes (forward, backward scrub, jumps; walk with onion skin + motion trail too):
##      no piece edge stretches past BAR_STRETCH = x4.0. Derivation: the clean body's worst edge over all those frames is the
##      inner fold of a right elbow held bent near its 145 deg stop (x3.2 measured, 2 mm edges); x4.0 is 25 % over the worst
##      real anatomy, and 7-10 times under the broken file (x27-x40).
##   2. the stand pose and the rest skeleton: x1.05 (the mannequin at rest skins to x1.01)
##   3. the weights the body is using: no influence (weight >= 5 %) farther than SkinPaint.MAX_REACH (0.5 m) from its bone
##   4. PLANTED CONTROL: the cause re-introduced the way the old code applied it (a sidecar with lowerarm_r added over the whole
##      body, applied unchecked): bar 1 FAILS on it (stretch past the bar on the clips), bar 3 FAILS on it
##   5. the same sidecar through the real path (main._wp_setup): refused, set aside as .rejected, the body keeps its own weights,
##      bars 1 and 3 pass again, a sound painted sidecar (a real stroke) is still applied
## The test writes only its own key (sbug2_test) and refuses to run when the user dir already holds a mannequin sidecar
## (booting main would set it aside): `APPDATA=C:\Temp\x godot ... -s tests/sbug2_test.gd`.
extends SceneTree

const BAR_STRETCH := 4.0
const BAR_REST := 1.05
const KEY := "sbug2_test"

var fails := 0
var rows: Array = []


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## one body's edge list and the weights, read once: [{"v": rest verts, "bones", "w", "per", "e0": PackedInt32Array, "e1", "rest": PackedFloat32Array}]
func _prep(m: Node) -> Array:
	var rest: Dictionary = BaseBody.rest_meshes(m)
	var first: MeshInstance3D = m.pieces.values()[0]
	var out := []
	for si in first.mesh.get_surface_count():
		var arr: Array = (rest[first] as ArrayMesh).surface_get_arrays(si)
		var d := {"v": arr[Mesh.ARRAY_VERTEX], "bones": arr[Mesh.ARRAY_BONES], "w": arr[Mesh.ARRAY_WEIGHTS], "e0": PackedInt32Array(), "e1": PackedInt32Array(), "rest": PackedFloat32Array(), "si": si}
		d["per"] = (d["bones"] as PackedInt32Array).size() / (d["v"] as PackedVector3Array).size()
		out.append(d)
	for j in m.pieces:
		var mi: MeshInstance3D = m.pieces[j]
		var rm := rest[mi] as ArrayMesh
		for si in rm.get_surface_count():
			var ix = rm.surface_get_arrays(si)[Mesh.ARRAY_INDEX]
			if ix == null:
				continue
			var d: Dictionary = out[si]
			var v: PackedVector3Array = d["v"]
			var e0: PackedInt32Array = d["e0"]
			var e1: PackedInt32Array = d["e1"]
			var er: PackedFloat32Array = d["rest"]
			for t in range(0, ix.size() - 2, 3):
				for e in 3:
					var i0: int = ix[t + e]
					var i1: int = ix[t + (e + 1) % 3]
					var r := v[i0].distance_to(v[i1])
					if r > 0.002:
						e0.append(i0)
						e1.append(i1)
						er.append(r)
			d["e0"] = e0
			d["e1"] = e1
			d["rest"] = er
	return out


## the worst edge stretch of the body in its current pose: [stretch, "surface:vertex"]; the DRAWN vertices (the bent mesh the
## corrective made) skinned by the weights the pieces carry now
func _stretch(m: Node, prep: Array) -> Array:
	var first: MeshInstance3D = m.pieces.values()[0]
	var sk: Skeleton3D = m.skel
	var skin: Skin = first.skin
	var mats := []
	for k in skin.get_bind_count():
		mats.append(sk.get_bone_global_pose(SkinPaint.bind_bone(skin, sk, k)) * skin.get_bind_pose(k))
	var worst := 0.0
	var at := ""
	for d in prep:
		var arr: Array = first.mesh.surface_get_arrays(d["si"])
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wt: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per: int = d["per"]
		var pos := PackedVector3Array()
		pos.resize(v.size())
		for k in v.size():
			var acc := Vector3.ZERO
			for j in per:
				var w := wt[k * per + j]
				if w > 0.0:
					acc += w * ((mats[bo[k * per + j]] as Transform3D) * v[k])
			pos[k] = acc
		var e0: PackedInt32Array = d["e0"]
		var e1: PackedInt32Array = d["e1"]
		var er: PackedFloat32Array = d["rest"]
		for q in e0.size():
			var r := pos[e0[q]].distance_to(pos[e1[q]]) / er[q]
			if r > worst:
				worst = r
				at = "s%d v%d" % [d["si"], e0[q]]
	return [worst, at]


func _reach(m: Node) -> Dictionary:
	var got := []
	for s in m.wp["surfs"]:
		got.append([s["bones"], s["w"]])
	return SkinPaint.reach(m.wp, got)


func _frames(n: int, quick: bool) -> Array:
	var out := []
	var step := 1 if n <= 40 else 2
	if quick:
		step = 6
	for f in range(0, n + 1, step):
		out.append(f)
	for f in range(n, -1, -(4 if not quick else 12)):   # the scrub back
		out.append(f)
	for f in [0, n, n / 2, 1, maxi(n - 1, 0), n / 3, 0]:   # jumps
		out.append(f)
	return out


## play every frame of the scene in `frames`: the worst stretch [value, "where"]
func _play(m: Node, prep: Array, frames: Array) -> Array:
	var fps: float = m.S.fps
	var worst := [0.0, ""]
	for f in frames:
		m.playhead = float(f) / fps
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		await process_frame
		var r: Array = _stretch(m, prep)
		if r[0] > worst[0]:
			worst = [r[0], "%s f%d" % [r[1], f]]
	return worst


func _boot() -> Node:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 8:
		await process_frame
	return m


func _drop(m: Node) -> void:
	m.queue_free()
	for i in 4:
		await process_frame


func _scenes() -> Array:
	var out := []
	for f in DirAccess.get_files_at("res://scenes"):
		if f.ends_with(".json"):
			out.append("res://scenes/" + f)
	out.sort()
	return out


## the broken file: the right forearm's weight added over the whole body, differing from one vertex to the next (what Nick's
## sidecar had: neighbouring vertices of the foot at 0.50 and 0.08 on lowerarm_r), in `model`
func _plant(model: Dictionary, m: Node) -> void:
	var bind: int = m._wp_bind_of("lowerarm_r")
	for s in model["surfs"]:
		var per: int = s["per"]
		var nb: PackedInt32Array = s["bones"]
		var nw: PackedFloat32Array = s["w"]
		for i in (s["verts"] as PackedVector3Array).size():
			var infl: Dictionary = SkinPaint._infl(s, i)
			var h := fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
			infl[bind] = float(infl.get(bind, 0.0)) + 0.6 * h
			var fit: Dictionary = SkinPaint._fit(s, i, infl, bind)
			for q in per:
				nb[i * per + q] = fit["b"][q]
				nw[i * per + q] = fit["w"][q]
		s["bones"] = nb
		s["w"] = nw


## what the old SkinPaint.load_into did with a sidecar: its weights straight onto the meshes, no check
func _apply_unchecked(m: Node, key: String) -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(SkinPaint.path(key)))
	for k in d["surfaces"].size():
		var e: Dictionary = d["surfaces"][k]
		m.wp["surfs"][k]["bones"] = Marshalls.base64_to_raw(String(e["bones"])).to_int32_array()
		m.wp["surfs"][k]["w"] = Marshalls.base64_to_raw(String(e["w"])).to_float32_array()
	SkinPaint.apply(m.wp)
	m.corr.attach(m.pieces.values(), m.skel)   # as at boot: the corrective keeps the rest mesh it is given, so it must see these weights
	m.dq_skin_pass.attach(m.pieces.values(), m.skel)


func _init() -> void:
	var real := ProjectSettings.globalize_path(SkinPaint.path("mannequin"))
	if FileAccess.file_exists(real):
		print("sbug2: user dir has a mannequin sidecar (%s): booting main would set it aside. Run with APPDATA on a temp dir." % real)
		print("sbug2: 1 fail")
		quit(1)
		return
	var scenes: Array = _scenes()
	# ---- A: the clean body, every scene, every frame
	var m: Node = await _boot()
	var prep: Array = _prep(m)
	var r0: Array = _stretch(m, prep)
	ok(float(r0[0]) < BAR_REST, "stand: no edge past x%.2f at rest (worst x%.3f %s)" % [BAR_REST, float(r0[0]), r0[1]])
	var rest: int = m.skel.get_bone_count()
	ok(rest > 0, "a skeleton to measure")
	var reach0: Dictionary = _reach(m)
	ok(float(reach0["worst"]) < SkinPaint.MAX_REACH and int(reach0["far"]) == 0, "the body's own weights: farthest influence %.3f m from its bone (bar < %.2f)" % [float(reach0["worst"]), SkinPaint.MAX_REACH])
	var clean := {}
	for sc in scenes:
		m._open_example(sc)
		for i in 3:
			await process_frame
		var n: int = int(ceil(m._ps().length() * float(m.S.fps)))
		if m.S.cards.is_empty() or n < 2:
			print("     (%s: no clip to play, skipped)" % sc.get_file())
			continue
		var w: Array = await _play(m, prep, _frames(n, false))
		clean[sc] = w[0]
		print("     CLEAN  %-22s %3d frames  worst x%.2f  (%s)" % [sc.get_file(), n + 1, float(w[0]), w[1]])
		ok(float(w[0]) < BAR_STRETCH, "%s: every frame under x%.1f (worst x%.2f)" % [sc.get_file(), BAR_STRETCH, float(w[0])])
	ok(clean.size() >= 8, "at least 8 clips were played (%d)" % clean.size())
	# walk with the onion skin and the motion trail on
	m._open_example("res://scenes/walk_bat.json")
	m.ov.onion_on = true
	m.ov.trail_on = true
	for i in 4:
		await process_frame
	var wn: int = int(ceil(m._ps().length() * float(m.S.fps)))
	var wo: Array = await _play(m, prep, _frames(wn, false))
	print("     CLEAN  %-22s %3d frames  worst x%.2f  (%s)" % ["walk+onion+trail", wn + 1, float(wo[0]), wo[1]])
	ok(float(wo[0]) < BAR_STRETCH, "walk with onion skin + motion trail: under x%.1f (worst x%.2f)" % [BAR_STRETCH, float(wo[0])])
	# a sound painted sidecar: a real stroke near the hand, applied through the real path
	m.ov.onion_on = false
	m.ov.trail_on = false
	await _drop(m)

	# ---- B: the planted control, the old unchecked apply
	m = await _boot()
	prep = _prep(m)
	m.wp_key = KEY
	_plant(m.wp, m)
	ok(SkinPaint.save(m.wp, KEY), "the planted sidecar was written (%s)" % KEY)
	var reach_planted: Dictionary = _reach(m)
	_apply_unchecked(m, KEY)
	reach_planted = _reach(m)
	ok(float(reach_planted["worst"]) > SkinPaint.MAX_REACH and int(reach_planted["far"]) > 100, "CONTROL: bar 3 FAILS on the planted body (worst influence %.2f m, %d past the bar)" % [float(reach_planted["worst"]), int(reach_planted["far"])])
	var broke := 0
	var before := {}
	for sc in scenes:
		if not clean.has(sc):
			continue
		m._open_example(sc)
		for i in 3:
			await process_frame
		var n: int = int(ceil(m._ps().length() * float(m.S.fps)))
		var w: Array = await _play(m, prep, _frames(n, true))
		before[sc] = w[0]
		if float(w[0]) >= BAR_STRETCH:
			broke += 1
		print("     PLANTED %-22s worst x%.2f  (%s)" % [sc.get_file(), float(w[0]), w[1]])
	ok(broke >= 8, "CONTROL: bar 1 FAILS on the planted body in %d of %d clips (bar: at least 8)" % [broke, before.size()])
	await _drop(m)

	# ---- C: the same file through the real path
	m = await _boot()
	prep = _prep(m)
	m.wp_key = KEY
	m._wp_setup()
	var mover := ProjectSettings.globalize_path(SkinPaint.path(KEY)) + ".rejected"
	ok(m.wp_notice != "" and m.wp_notice.contains("broken"), "the broken sidecar is refused with a reason: '%s'" % m.wp_notice.left(150))
	ok(not FileAccess.file_exists(ProjectSettings.globalize_path(SkinPaint.path(KEY))) and FileAccess.file_exists(mover), "it is set aside (%s), not deleted" % mover.get_file())
	var reach_fixed: Dictionary = _reach(m)
	ok(float(reach_fixed["worst"]) < SkinPaint.MAX_REACH and int(reach_fixed["far"]) == 0, "bar 3: the body keeps its own weights (farthest influence %.3f m)" % float(reach_fixed["worst"]))
	var after := {}
	for sc in scenes:
		if not clean.has(sc):
			continue
		m._open_example(sc)
		for i in 3:
			await process_frame
		var n: int = int(ceil(m._ps().length() * float(m.S.fps)))
		var w: Array = await _play(m, prep, _frames(n, true))
		after[sc] = w[0]
		ok(float(w[0]) < BAR_STRETCH, "AFTER the fix, %s with the broken sidecar present: worst x%.2f (was x%.2f), bar x%.1f" % [sc.get_file(), float(w[0]), float(before[sc]), BAR_STRETCH])
	DirAccess.remove_absolute(mover)
	# a sound sidecar (a real stroke at the hand) is still applied
	m.wp_key = KEY + "2"
	m._wp_setup()
	var bind: int = m._wp_bind_of("hand_r")
	SkinPaint.refresh(m.wp)
	var hp: Vector3 = m.B.P["hand_r"]
	for s in m.wp["surfs"]:
		SkinPaint.paint(s, s["pos"], hp, 0.08, bind, 0.25, "add")
	SkinPaint.save(m.wp, KEY + "2")
	var keep: Dictionary = _reach(m)
	m._wp_setup()
	ok(m.wp_notice == m.wp_notice and FileAccess.file_exists(ProjectSettings.globalize_path(SkinPaint.path(KEY + "2"))), "a sound painted sidecar (a stroke at the hand) is not refused (farthest influence %.3f m)" % float(keep["worst"]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SkinPaint.path(KEY + "2")))
	await _drop(m)

	print("     ---- per clip: worst edge stretch  clean | planted old code | fixed, with the broken file present")
	for sc in scenes:
		if clean.has(sc):
			print("     %-22s x%5.2f | x%6.2f | x%5.2f" % [sc.get_file(), float(clean[sc]), float(before[sc]), float(after[sc])])
	print("sbug2: %d fail" % fails)
	quit(fails)
