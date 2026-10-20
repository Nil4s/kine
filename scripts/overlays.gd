## overlays.gd - what animators ask for and the poser lacked (10-14, Nick: "what 3D animators complain they don't have")
##   MOTION TRAIL (T): the weapon tip's path over the whole scene (the bat hand's wrist when there is no weapon). One dot
##     per frame, so SPACING shows: dots far apart = fast, bunched = slow. Colour = speed against the scene's peak (blue
##     slow -> yellow -> red fast, as animBot's trail). The cards' moments are big white dots; the peak is labelled.
##     Built once per scene change (the scene sampled at its fps on a body of its own), never per frame.
##   ONION SKIN (O): the card BEFORE the playhead (orange) and the card AFTER it (green) as see-through bodies: the same
##     mannequin, posed by the same Body math as the main one (sampled from the scene, not approximated).
## Both draw on their own Body (GB), so the pose being edited is never touched.
class_name Overlays
extends Node3D

const SLOW := Color(0.2, 0.5, 1.0)
const MID := Color(1.0, 0.85, 0.2)
const FAST := Color(1.0, 0.2, 0.15)
const BEFORE := Color(1.0, 0.55, 0.15, 0.28)
const AFTER := Color(0.25, 0.95, 0.45, 0.28)
const FIXED := Color(0.15, 0.65, 1.0, 0.6)   # the fix preview ghost: what a Fix button would make of this moment
## ONION FADES (round 23, GATES DD1, UPGRADES #43): two ghosts each side; the farther one fainter, and its hue pushed on
## away from the other side's (past: orange -> red, future: green -> cyan), so near/far and past/future read at a glance
const PAST_FAR := Color(1.0, 0.25, 0.2, 0.13)
const FUTURE_FAR := Color(0.2, 0.85, 1.0, 0.13)
## COMPARE WITH (ROADMAP 28): the older version laid over the open scene; magenta, so it is never mistaken for the onion
const TAKE := Color(1.0, 0.62, 0.15, 0.40)   # I14: the real take, laid over the clip (orange, grown like the version ghost so it shows on the body)
const VERSION_GROW := 0.004   # m: the version ghost is inflated along its normals by this (the body is not moved)
const VERSION := Color(0.85, 0.3, 0.95, 0.35)   # COMPARE WITH / Show both: translucent, depth write off, grown 4 mm (VERSION_GROW) so it never z-fights the body
## ghost slots: [past near, future near, fix preview, past far, future far, version]; onion's [side][distance] -> slot
const ONION_SLOT := [[0, 3], [1, 4]]

var trail_on := false
var auto_pin := ""  # the part whose trail is on only while it is picked and T is on (main.gd _auto_pin_sync); Shift+T keeps it
var pins := []      # body parts with a trail of their own (Shift+T on the selected part): the END of the part (forearm =
                    # the wrist, thigh = the knee, foot = the toes' base), the pelvis = the hips' centre
var onion_on := false
## PER-PART ONION (ROADMAP 70): with "picked parts only" on, the ghosts are only the picked parts (the whole body is not
## drawn), onion_before frames before the playhead and onion_after after it, onion_step frames apart (at the scene's fps).
## Each ghost frame is one rig: a mannequin split into its parts (split_parts), with only the picked pieces shown. The
## alpha falls with the time distance (the nearest frame strongest), and past and future take Tok's onion_past / onion_future.
var onion_parts_on := false
var onion_picks := []       # body part names (Body.ORDER), in the order they were picked
var onion_before := 2       # frames before the playhead (0..ONION_MAX)
var onion_after := 2        # frames after it
var onion_step := 1         # frames between two ghosts (1..ONION_STEP_MAX)
const ONION_MAX := 5
const ONION_STEP_MAX := 10
const ONION_ALPHA_NEAR := 0.5
const ONION_ALPHA_FAR := 0.12
var _rigs := []             # [{node, sk, idx, pieces, mat}] one per ghost frame, pooled while the frame count stays
## SPACING GHOSTS (10-14, animators: "I can't see my spacing"): every SPACE_DT seconds around the playhead, the parts
## that TRAVEL: the weapon shaft + both forearms (unarmed: arms and legs), orange behind, green ahead, fading with
## distance. Bunched = slow, a wide fan = fast: the spacing chart, in 3D. (A whole stick body was tried first: a swing
## turns in place, so ten bodies stacked into a tangle.) Built in the trail's one pass (never per frame).
var spacing_on := false
const SPACE_DT := 0.1
const SPACE_SPAN := 0.5   # s each way
var _space := []          # [[t, [Vector3 a, Vector3 b, ...] line pairs], ...]
var _space_mesh: MeshInstance3D
## SPEED GRAPH data (the same pass): seconds and m/s of the weapon tip (the wrist without one), the hips, the head
var graph_on := false
var curves := {}
## REACH MARKER: while a hand / foot is pulled past where it can go, where the mouse wants it (a cross) and a line from
## the limb to it. Without it the hand just stops and nothing says why (round 6)
var _reach_mesh: MeshInstance3D
var reach_gap := 0.0   # m: how far the limb is from the mouse's point now (0 = none shown)
var GB := Body.new()
var _dirty := true
var _line: MeshInstance3D
var _peak: Label3D
var _pin_nodes := {}   # part -> [MeshInstance3D, Label3D]
var _ghosts := []   # [[skeleton, bone_idx, weapon line mesh], x2]
var info := ""      # what the trail measured, for the status line
var builds := 0     # how many times the trail was built (tests: once per scene change, never per frame)


func setup() -> void:
	GB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	_line = MeshInstance3D.new()
	_line.mesh = ImmediateMesh.new()
	add_child(_line)
	_peak = Label3D.new()
	_peak.pixel_size = 0.0008
	_peak.fixed_size = true
	_peak.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_peak.no_depth_test = true
	_peak.outline_size = 8
	_peak.font_size = 26
	_peak.modulate = FAST.lightened(0.3)
	add_child(_peak)
	_reach_mesh = MeshInstance3D.new()
	_reach_mesh.mesh = ImmediateMesh.new()
	add_child(_reach_mesh)
	_space_mesh = MeshInstance3D.new()
	_space_mesh.mesh = ImmediateMesh.new()
	add_child(_space_mesh)
	for col in [BEFORE, AFTER, FIXED, PAST_FAR, FUTURE_FAR, VERSION, TAKE]:
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_BACK
		if col == VERSION or col == TAKE:   # the diff ghost sits on the body's own surfaces (same pose): no depth write, grown outward so it never fights the skin
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			m.grow = true
			m.grow_amount = VERSION_GROW
		var mq := mannequin(self, m)
		var man: Node3D = mq[0]
		var sk: Skeleton3D = mq[1]
		var idx: Dictionary = mq[2]
		var wl := MeshInstance3D.new()
		wl.mesh = ImmediateMesh.new()
		add_child(wl)
		man.visible = false
		_ghosts.append([man, sk, idx, wl, col])
	_hide()


## ONE mannequin from assets/mannequin.glb under parent, its animation player gone, every mesh in material m:
## [node, skeleton, {joint: bone index}]. The main body, the dummy and the ghosts are all made by this.
static func mannequin(parent: Node, m: Material) -> Array:
	var man: Node3D = (load("res://assets/mannequin.glb") as PackedScene).instantiate()
	parent.add_child(man)
	for ap in man.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()
		ap.queue_free()
	for mi in man.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = m
	var sk: Skeleton3D = man.find_children("*", "Skeleton3D", true, false)[0]
	var idx := {}
	for j in Body.ORDER:
		idx[j] = sk.find_bone("Head" if j == "head" else j)
	return [man, sk, idx]


## ONE PIECE PER PART (round 30, GATES KK1, UPGRADES #24): the mannequin is one skinned mesh, so a part could not be
## hidden on its own. Split it once: each triangle goes to the part whose bones weigh most on its three corners (a
## bone below no part of ours, the root, counts as the pelvis; a finger's extra bones as their finger joint). Every
## piece keeps ALL the vertex data and only its own triangles, the same skin and skeleton and material, so with
## nothing hidden the body renders the same. The original is hidden, not freed. -> part -> its MeshInstance3D
static func split_parts(man: Node3D, sk: Skeleton3D, idx: Dictionary) -> Dictionary:
	var part_of := {}   # bone -> part: the bone itself if it is one of ours, else its nearest ancestor that is
	var ours := {}
	for j in idx:
		if idx[j] >= 0:
			ours[idx[j]] = j
	for b in sk.get_bone_count():
		var c := b
		while c >= 0 and not ours.has(c):
			c = sk.get_bone_parent(c)
		part_of[b] = ours[c] if c >= 0 else "pelvis"
	var out := {}
	for mi in man.find_children("*", "MeshInstance3D", true, false):
		var src := mi as MeshInstance3D
		var tris := {}   # part -> [surface -> PackedInt32Array]
		var mesh := src.mesh
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var nv: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var per := bones.size() / nv   # 4 or 8 influences
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(nv))
			for t in range(0, ix.size(), 3):
				var w := {}
				for k in 3:
					var v: int = ix[t + k]
					for q in per:
						var pj: String = part_of.get(bones[v * per + q], "pelvis")
						w[pj] = w.get(pj, 0.0) + wts[v * per + q]
				var best := ""
				for pj in w:
					if best == "" or w[pj] > w[best]:
						best = pj
				if not tris.has(best):
					tris[best] = {}
				if not tris[best].has(si):
					tris[best][si] = PackedInt32Array()
				tris[best][si].append_array(ix.slice(t, t + 3))
		for pj in tris:
			var am := ArrayMesh.new()
			for si in tris[pj]:
				var arr := mesh.surface_get_arrays(si)
				arr[Mesh.ARRAY_INDEX] = tris[pj][si]
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, mesh.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
			var piece := MeshInstance3D.new()
			piece.name = "piece_" + pj
			piece.mesh = am
			piece.skin = src.skin
			piece.material_override = src.material_override
			src.get_parent().add_child(piece)
			piece.transform = src.transform
			piece.skeleton = piece.get_path_to(src.get_node(src.skeleton))
			out[pj] = piece
		src.visible = false
	return out


## write a body's pose into a mannequin's skeleton (glTF local rotations, the pelvis's position)
static func pose_skeleton(sk: Skeleton3D, idx: Dictionary, b: Body) -> void:
	Proportions.scale_skeleton(sk, idx, b)   # PR1: the mesh takes the body's proportions (nothing for the default body)
	for j in Body.ORDER:
		if idx[j] >= 0:
			sk.set_bone_pose_rotation(idx[j], b.gltf_local(j))
	if idx["pelvis"] >= 0:
		sk.set_bone_pose_position(idx["pelvis"], b.gltf_pelvis_pos())
	_squash_skel(sk, idx, b)


## I13: a struck part squashed along the blow (Body.squash): the bone's scale along that direction (in the bone's own axes), put back next call
static func _squash_skel(sk: Skeleton3D, idx: Dictionary, b: Body) -> void:
	if sk.has_meta("sq"):
		var old: Dictionary = sk.get_meta("sq")
		for i in old:
			sk.set_bone_pose_scale(int(i), old[i])
		sk.remove_meta("sq")
	if b.squash.is_empty():
		return
	var keep := {}
	var want := {}
	for j in b.squash:
		if not idx.has(j) or int(idx[j]) < 0:
			continue
		var i: int = idx[j]
		var rot := sk.get_bone_global_pose(i).basis.orthonormalized()
		var dl: Vector3 = rot.inverse() * (b.squash[j]["dir"] as Vector3)
		var s: float = b.squash[j]["s"]
		keep[i] = sk.get_bone_pose_scale(i)
		want[i] = (keep[i] as Vector3) * Vector3(1.0 + (s - 1.0) * dl.x * dl.x, 1.0 + (s - 1.0) * dl.y * dl.y, 1.0 + (s - 1.0) * dl.z * dl.z)
	for i in want:
		sk.set_bone_pose_scale(int(i), want[i])
	sk.set_meta("sq", keep)


## the scene changed: the trail is rebuilt the next time it is drawn
func mark_dirty() -> void:
	_dirty = true


func _hide() -> void:
	_line.visible = trail_on
	_peak.visible = trail_on
	for g in _ghosts:
		g[0].visible = false
		g[3].visible = false


static func _mat(point := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true   # seen through the body: the path is the point
	m.render_priority = 2
	if point > 0.0:
		m.use_point_size = true
		m.point_size = point
	return m


## speed u in 0..1 of the peak -> blue, yellow, red
static func heat(u: float) -> Color:
	u = clampf(u, 0.0, 1.0)
	return SLOW.lerp(MID, u * 2.0) if u < 0.5 else MID.lerp(FAST, (u - 0.5) * 2.0)


## the tracked point: the weapon tip, else the bat hand's wrist
static func tracked(b: Body) -> Vector3:
	return b.wep_point(b.wep_len) if b.wep_on else b.P["hand_r"]


## where a pinned part's trail runs: its end, the hips' centre for the pelvis
static func part_point(b: Body, j: String) -> Vector3:
	return b.P[j] if j == "pelvis" else b.E[j]


func _label3d() -> Label3D:
	var l := Label3D.new()
	l.pixel_size = 0.0008
	l.fixed_size = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.outline_size = 8
	l.font_size = 22
	l.modulate = FAST.lightened(0.3)
	add_child(l)
	return l


## pin / unpin a trail on a body part; true = now pinned
func toggle_pin(j: String) -> bool:
	_dirty = true
	if j in pins:
		pins.erase(j)
		for n in _pin_nodes[j]:
			n.queue_free()
		_pin_nodes.erase(j)
		return false
	pins.append(j)
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	add_child(mi)
	_pin_nodes[j] = [mi, _label3d()]
	return true


func trail(S: Scene) -> void:
	var show := S.cards.size() >= 2
	_line.visible = trail_on and show
	_peak.visible = _line.visible
	for j in pins:
		for n in _pin_nodes[j]:
			n.visible = show
	if not show:
		_space = []   # nothing to space (round 19, GATES Z3: the last scene's ghosts stayed drawn at 1 card and at 0)
	if not show or not _dirty or (not trail_on and pins.is_empty() and not spacing_on and not graph_on):
		return
	_dirty = false
	builds += 1
	# one pass over the scene feeds every trail: [point, speed] per frame for each
	var fps := float(S.fps)
	var n := int(ceil(S.length() * fps)) + 1
	var keys := [""] + pins   # "" = the weapon tip (the bat hand's wrist without one)
	var pts := {}
	for k in keys:
		pts[k] = []
	_space = []
	curves = {"t": [], "tip": [], "hips": [], "head": [], "cards": [], "armed": false, "fps": S.fps}
	var every := maxi(1, int(round(SPACE_DT * fps)))
	var ph := Vector3.ZERO
	var hh := Vector3.ZERO
	for i in n:
		var t := minf(i / fps, S.length())
		S.apply(GB, t)
		for k in keys:
			var p: Vector3 = tracked(GB) if k == "" else part_point(GB, k)
			var arr: Array = pts[k]
			arr.append([p, (p - arr[-1][0]).length() * fps if i > 0 else 0.0])
		var hp: Vector3 = GB.P["pelvis"]
		var hd: Vector3 = GB.P["head"]
		curves["t"].append(t)
		curves["tip"].append(pts[""][-1][1])
		curves["hips"].append((hp - ph).length() * fps if i > 0 else 0.0)
		curves["head"].append((hd - hh).length() * fps if i > 0 else 0.0)
		curves["armed"] = curves["armed"] or GB.wep_on
		ph = hp
		hh = hd
		if i % every == 0:
			_space.append([t, fan(GB)])
	for k in ["tip", "hips", "head"]:
		if curves[k].size() > 1:
			curves[k][0] = curves[k][1]
	var cards := []
	for t in S.times():
		cards.append(int(round(float(t[1]) * fps)))
		curves["cards"].append(float(t[1]))
	var tip_peak := _draw(_line, _peak, pts[""], cards, "")
	for j in pins:
		_draw(_pin_nodes[j][0], _pin_nodes[j][1], pts[j], cards, j)
	info = "trail: %d frames, peak %.1f m/s (%s)%s" % [n, tip_peak, "weapon tip" if GB.wep_on else "right wrist",
		("  + pinned: " + ", ".join(pins)) if not pins.is_empty() else ""]


## one trail: line + a dot per frame coloured by speed against ITS peak, white dots on the cards, the peak labelled.
## A pinned part's path is short (a foot moves centimetres where the bat tip moves metres), so its dots are smaller
## and its label names the part.
func _draw(mi: MeshInstance3D, lbl: Label3D, pts: Array, cards: Array, part: String) -> float:
	var small := part != ""
	if pts.size() > 1:
		pts[0][1] = pts[1][1]
	var peak := 0.0
	var pk := 0
	for i in pts.size():
		if pts[i][1] > peak:
			peak = pts[i][1]
			pk = i
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _mat())
	for p in pts:
		im.surface_set_color(heat(p[1] / maxf(1e-6, peak)))
		im.surface_add_vertex(p[0])
	im.surface_end()
	im.surface_begin(Mesh.PRIMITIVE_POINTS, _mat(4.0 if small else 6.0))
	for p in pts:
		im.surface_set_color(heat(p[1] / maxf(1e-6, peak)))
		im.surface_add_vertex(p[0])
	im.surface_end()
	im.surface_begin(Mesh.PRIMITIVE_POINTS, _mat(7.0 if small else 13.0))
	for f in cards:
		im.surface_set_color(Color(1, 1, 1, 0.85))
		im.surface_add_vertex(pts[clampi(f, 0, pts.size() - 1)][0])
	im.surface_end()
	lbl.text = ("%s %.1f m/s" % [part.replace("_l", " L").replace("_r", " R"), peak]) if small else "%.1f m/s" % peak
	lbl.font_size = 18 if small else 26
	lbl.position = pts[pk][0] + Vector3(0, 0.05 if small else 0.07, 0)
	return peak


## the cards either side of the playhead: [before, after] (-1 = none). On a card exactly: the ones either side of it.
static func neighbours(S: Scene, t: float) -> Array:
	var ts := S.times()
	var before := -1
	var after := -1
	for i in S.cards.size():
		var at: float = ts[i][1]
		if at < t - 1e-3:
			before = i
		elif at > t + 1e-3 and after < 0:
			after = i
	return [before, after]


func onion(S: Scene, t: float) -> void:
	for side in ONION_SLOT:
		for k in side:
			_ghosts[k][0].visible = false
			_ghosts[k][3].visible = false
	if onion_on and onion_parts_on:
		_onion_rigs(S, t)
		return
	_free_rigs()
	if not onion_on or S.cards.size() < 2:
		return
	var nb := neighbours(S, t)
	var ts := S.times()
	for side in 2:
		if nb[side] < 0:
			continue
		for d in 2:   # the nearest card on this side, then the one past it
			var ci: int = nb[side] + (d if side == 1 else -d)
			if ci < 0 or ci >= S.cards.size():
				continue
			S.apply(GB, float(ts[ci][1]))
			_pose(_ghosts[ONION_SLOT[side][d]], GB)


## PER-PART ONION: the frames' times, nearest first: before (side -1) then after (side +1). Frames past either end are left out.
static func onion_times(t: float, length: float, fps: float, before: int, after: int, step: int) -> Array:
	var out := []
	for side in [-1, 1]:
		var n := before if side < 0 else after
		for k in range(1, n + 1):
			var tk: float = t + side * k * step / fps
			if tk >= -1e-6 and tk <= length + 1e-6:
				out.append([clampf(tk, 0.0, length), side, k, n])
	return out


func _onion_rigs(S: Scene, t: float) -> void:
	var fr := onion_times(t, S.length(), float(S.fps), onion_before, onion_after, onion_step)
	while _rigs.size() > fr.size():
		var dead: Dictionary = _rigs.pop_back()
		dead.node.visible = false
		dead.node.queue_free()
	while _rigs.size() < fr.size():
		_rigs.append(_new_rig())
	for i in fr.size():
		var f: Array = fr[i]
		var r: Dictionary = _rigs[i]
		r.t = float(f[0])
		S.apply(GB, float(f[0]))
		pose_skeleton(r.sk, r.idx, GB)
		var col: Color = Tok.c("onion_past" if f[1] < 0 else "onion_future")
		var fade := float(f[2] - 1) / float(maxi(1, int(f[3]) - 1))   # 0 at the nearest frame, 1 at the farthest
		col.a = lerpf(ONION_ALPHA_NEAR, ONION_ALPHA_FAR, fade)
		(r.mat as StandardMaterial3D).albedo_color = col
		r.node.visible = true
		for pj in r.pieces:
			(r.pieces[pj] as MeshInstance3D).visible = onion_picks.has(pj)


## one ghost rig: a mannequin in the ghost material, split into its parts; nothing shown until _onion_rigs picks them
func _new_rig() -> Dictionary:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	var mq := mannequin(self, m)
	var pieces := split_parts(mq[0], mq[1], mq[2])
	return {"node": mq[0], "sk": mq[1], "idx": mq[2], "pieces": pieces, "mat": m, "t": 0.0}


func _free_rigs() -> void:
	for r in _rigs:
		r.node.visible = false
		r.node.queue_free()
	_rigs.clear()


func has_rigs() -> bool:
	return not _rigs.is_empty()


## how many ghost meshes are on screen: the picked parts' pieces, on every ghost frame (0 once it is off)
func onion_mesh_count() -> int:
	var n := 0
	for r in _rigs:
		for pj in r.pieces:
			if (r.pieces[pj] as MeshInstance3D).visible:
				n += 1
	return n



## NEXT-POSE GHOSTS (ROADMAP R27, scripts/next_pose.gd): up to three smaller translucent mannequins in a row at the body's side
## (the camera's right), each in its source's colour with a label above its head. items: [{"body": Body (the pose), "col":
## Color, "text": String, "sel": bool}]. `at` = the current body's pelvis; `right` = the horizontal direction a ghost steps
## towards; each ghost is drawn at `scale` of the body, the first `first` m from `at`, the next ones `step` m apart (main.gd
## fits them between the body and the right panel). Nothing of the scene changes: these are display nodes only.
var _sg := []              # [{node, sk, idx, mat, label}]


func _sg_make() -> Dictionary:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	var mq := mannequin(self, m)
	var lb := Label3D.new()
	lb.pixel_size = 0.0008
	lb.fixed_size = true
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.outline_size = 8
	lb.font_size = 13
	add_child(lb)
	return {"node": mq[0], "sk": mq[1], "idx": mq[2], "mat": m, "label": lb}


func sugg_show(items: Array, at: Vector3, right: Vector3, scale: float, first: float, step: float) -> void:
	while _sg.size() < items.size():
		_sg.append(_sg_make())
	var flat := Vector3(right.x, 0.0, right.z)
	flat = flat.normalized() if flat.length() > 1e-4 else Vector3.RIGHT
	for i in _sg.size():
		var g: Dictionary = _sg[i]
		var on := i < items.size()
		(g.node as Node3D).visible = on
		(g.label as Label3D).visible = on
		if not on:
			continue
		var it: Dictionary = items[i]
		var b: Body = it["body"]
		pose_skeleton(g.sk, g.idx, b)
		var col: Color = it["col"]
		col.a = 0.62 if it.get("sel", false) else 0.38
		(g.mat as StandardMaterial3D).albedo_color = col
		var want := Vector3(at.x, 0.0, at.z) + flat * (first + step * i)
		var gp: Vector3 = b.P["pelvis"]
		(g.node as Node3D).scale = Vector3.ONE * scale
		(g.node as Node3D).position = Vector3(want.x - scale * gp.x, 0.0, want.z - scale * gp.z)
		var lb: Label3D = g.label
		lb.text = String(it["text"])
		lb.modulate = Color(col, 1.0).lightened(0.35)
		lb.outline_modulate = Color(0, 0, 0, 0.9)
		lb.position = Vector3(want.x, 1.95 * scale + 0.12, want.z)


func sugg_hide() -> void:
	for g in _sg:
		(g.node as Node3D).visible = false
		(g.label as Label3D).visible = false


## where ghost i's pelvis stands (the test checks the placement from this)
func sugg_spot(i: int) -> Vector3:
	if i >= _sg.size() or not (_sg[i].node as Node3D).visible:
		return Vector3.INF
	return (_sg[i].label as Label3D).position


## COMPARE WITH (ROADMAP 28): the older version V posed at t as the magenta ghost (slot 5). Null = hidden. Its pose is left
## in GB (the sampler), never in the edited body.
func version_ghost(V: Scene, t: float) -> void:
	var g: Array = _ghosts[5]
	g[0].visible = false
	g[3].visible = false
	if V == null or V.cards.is_empty():
		return
	V.apply(GB, t)
	_pose(g, GB)


## I14 REHEARSE: the take (a Scene) at ITS time t (the clip's playhead run through the DTW map), orange. null = hide it
func take_ghost(V: Scene, t: float) -> void:
	var g: Array = _ghosts[6]
	g[0].visible = false
	g[3].visible = false
	if V == null or V.cards.is_empty():
		return
	V.apply(GB, t)
	_pose(g, GB)


## FIX PREVIEW: the scene as the fix would leave it (`cards`, from Fixer.propose), posed at t, as a blue ghost. The
## scene's cards are swapped in for the one sample and put back (the same list object): nothing of it changes.
## Empty cards = hide it.
func fix_preview(S: Scene, cards: Array, t: float) -> void:
	var g: Array = _ghosts[2]
	g[0].transform = Transform3D.IDENTITY
	g[3].transform = Transform3D.IDENTITY
	_fg_on = false
	g[0].visible = false
	g[3].visible = false
	if cards.is_empty():
		return
	var orig := S.cards
	var baker := S.baker
	S.baker = null   # the pose bake holds the cards as they ARE: it would draw the unfixed pose as the "fixed" ghost
	S.cards = cards
	S.apply(GB, t)
	S.cards = orig
	S.baker = baker
	_pose(g, GB)


## I11 FIGHT PHRASE PREVIEW: the defender as the phrase would leave it (scene S posed at t), the blue ghost (slot 2) placed by
## xf (its space -> the hero's). Null = hide it (only when this ghost is what is showing)
var _fg_on := false


func fight_ghost(S: Scene, t: float, xf: Transform3D) -> void:
	var g: Array = _ghosts[2]
	if S == null:
		if _fg_on:
			g[0].visible = false
			g[3].visible = false
			g[0].transform = Transform3D.IDENTITY
			g[3].transform = Transform3D.IDENTITY
			_fg_on = false
		return
	S.apply(GB, t)
	_pose(g, GB)
	g[0].transform = xf
	g[3].transform = xf
	_fg_on = true


## a stick body: line pairs along every bone but the fingers, the head to its top, the weapon shaft
static func stick(b: Body) -> Array:
	var out := []
	for j in Body.ORDER:
		var pj: String = b.parent[j]
		if pj == "" or j.begins_with("thumb") or j.begins_with("index") or j.begins_with("middle") or j.begins_with("ring") or j.begins_with("pinky"):
			continue
		out.append(b.P[pj])
		out.append(b.P[j])
	out.append(b.P["head"])
	out.append(b.E["head"])
	if b.wep_on:
		out.append(b.wep_point(0.0))
		out.append(b.wep_point(b.wep_len))
	return out


## what a spacing ghost draws: the weapon shaft and the forearms; without a weapon, both arms and both legs
static func fan(b: Body) -> Array:
	var out := []
	var parts := ["lowerarm_l", "lowerarm_r"] if b.wep_on else ["upperarm_l", "lowerarm_l", "upperarm_r", "lowerarm_r", "thigh_l", "calf_l", "thigh_r", "calf_r"]
	for j in parts:
		out.append(b.P[j])
		out.append(b.E[j])
	if b.wep_on:
		out.append(b.wep_point(0.0))
		out.append(b.wep_point(b.wep_len))
	return out


## show the reach marker from the limb's end `at` to the mouse's point `want` (on = false hides it). Shown only past 2 cm
func reach_marker(at: Vector3, want: Vector3, on: bool) -> void:
	reach_gap = at.distance_to(want) if on else 0.0
	_reach_mesh.visible = reach_gap > 0.02
	if not _reach_mesh.visible:
		return
	var im := _reach_mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES, _mat())
	im.surface_set_color(Color(1.0, 0.9, 0.35))
	var n := int(ceil(reach_gap / 0.03))   # dashed: 3 cm on, 3 cm off
	for k in range(0, n, 2):
		im.surface_add_vertex(at.lerp(want, float(k) / n))
		im.surface_add_vertex(at.lerp(want, minf(1.0, float(k + 1) / n)))
	for ax in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:   # the cross where the mouse is
		im.surface_add_vertex(want - ax * 0.04)
		im.surface_add_vertex(want + ax * 0.04)
	im.surface_end()


## the spacing ghosts around time t (from the cached pass; nothing is re-played here)
func spacing(t: float) -> void:
	_space_mesh.visible = spacing_on and not _space.is_empty()
	if not _space_mesh.visible:
		return
	var im := _space_mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	var m := _mat()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, m)
	var drawn := 0
	for g in _space:
		var dt: float = g[0] - t
		if absf(dt) < SPACE_DT * 0.5 or absf(dt) > SPACE_SPAN + 1e-4:
			continue
		var c: Color = BEFORE if dt < 0.0 else AFTER
		c.a = lerpf(0.85, 0.2, absf(dt) / SPACE_SPAN)
		im.surface_set_color(c)
		for p in g[1]:
			im.surface_add_vertex(p)
		drawn += 1
	if drawn == 0:   # an empty surface is an error: one invisible point
		im.surface_set_color(Color(0, 0, 0, 0))
		im.surface_add_vertex(Vector3.ZERO)
		im.surface_add_vertex(Vector3.ZERO)
	im.surface_end()


## pose one ghost mannequin from a body: the same bone write as the main view (main.gd _refresh)
func _pose(g: Array, b: Body) -> void:
	pose_skeleton(g[1], g[2], b)
	g[0].visible = true
	var im := g[3].mesh as ImmediateMesh
	im.clear_surfaces()
	if b.wep_on:
		var m := _mat()
		m.no_depth_test = false
		im.surface_begin(Mesh.PRIMITIVE_LINES, m)
		var c: Color = g[4]
		im.surface_set_color(Color(c, 0.9))
		im.surface_add_vertex(b.wep_point(0.0))
		im.surface_add_vertex(b.wep_point(b.wep_len))
		im.surface_end()
		g[3].visible = true
