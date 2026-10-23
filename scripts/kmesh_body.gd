class_name KMeshBody
extends Node
## BODY-AWARE MESH (ROADMAP_400 A18 ★): every vertex of a KMesh knows the character's bone nearest to it (UE5 name), how
## far it is from that bone, and the body region it is in, as three A09 vertex channels that are saved with the mesh:
##   "body_bone"   float: index into BONES (the UE5 name table; -1 = not labelled yet)
##   "body_cm"     float: the distance to that bone, in cm
##   "body_region" float: index into REGIONS (-1 = not labelled yet)
## NEAREST BONE = nearest bone SEGMENT, not the joint point: a bone runs from its own joint to the joint of its child along
## the limb (Body.CHILD; the hand to middle_01, a finger 03 to its 04 leaf, the ball to its leaf; the head, which has no
## child, runs on past its joint along the neck's direction for HEAD_K neck lengths). Every bone of BONES the skeleton has
## is one segment. Where two segments are exactly as near (a point past the end of both, round a joint), the one the point
## overshoots less wins, then the lower BONES index: the answer never depends on the order of anything.
## FAST: the verts are bucketed into CELL-sized cells; each cell keeps only the segments that can be nearest to some point
## of its box (d(centre) <= the cell's best d(centre) + the box's diagonal), so a vertex tests a few segments, not all.
## refresh() is the per-frame entry: the whole mesh again when the body (its segments, the mesh's placement) changed or the
## vertex count did, else only the verts that moved since the last labelling (a 1 mm edit relabels one vertex).
## The labels are the segments' world space: segs come from segments_from_skeleton (the skeleton as POSED now), xf takes
## the mesh's local space there (KMeshView.global_transform).
## A19 (anatomy tags) builds on this: its finer tags (deltoid, patella, knuckle ...) are painted once on the base body
## and carried by A09 (attr_remap) through every edit; REGIONS stays the coarse layer the tags sit inside, and region_of()
## the rule a tag falls back to where nothing was painted.
## As a Node this is the model preview's "colour by region" view (kmesh_edit_ui.gd, Shift+H): a tint layer on the
## mesh in each region's colour, a legend of the regions present (bottom right of the free view), and a hover readout
## at the mouse ("forearm_l, 1.8 cm from bone lowerarm_l").

const CH_BONE := "body_bone"
const CH_CM := "body_cm"
const CH_REGION := "body_region"
const CELL := 0.08        # m: the bucket size of compute()
const HEAD_K := 2.5       # the head bone runs this many neck lengths past its joint (the crown is inside it)
const OFF_TINT := 0.0015  # m: the region layer sits this far out along the vertex normal (as the selection tint does)
const LEGEND_PAD := 12.0

## the UE5 bone names a label can name. APPEND ONLY: a saved mesh stores indices into this table
const BONES := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head",
	"clavicle_l", "upperarm_r", "lowerarm_l", "hand_r", "clavicle_r", "upperarm_l", "lowerarm_r", "hand_l",
	"thigh_r", "calf_l", "foot_r", "ball_l", "thigh_l", "calf_r", "foot_l", "ball_r",
	"thumb_01_l", "thumb_02_l", "thumb_03_l", "index_01_l", "index_02_l",
	"index_03_l", "middle_01_l", "middle_02_l", "middle_03_l", "ring_01_l",
	"ring_02_l", "ring_03_l", "pinky_01_l", "pinky_02_l", "pinky_03_l",
	"thumb_01_r", "thumb_02_r", "thumb_03_r", "index_01_r", "index_02_r",
	"index_03_r", "middle_01_r", "middle_02_r", "middle_03_r", "ring_01_r",
	"ring_02_r", "ring_03_r", "pinky_01_r", "pinky_02_r", "pinky_03_r"]
## the body regions. APPEND ONLY (saved as indices)
const REGIONS := ["head", "neck", "chest", "abdomen", "pelvis",
	"upperarm_l", "forearm_l", "hand_l", "upperarm_r", "forearm_r", "hand_r",
	"thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"]
## the region colours: the middle in greens / yellows, the left in reds, the right in blues (as Kine's side colours go: main.SIDE_L red, SIDE_R blue)
const COLORS := {"head": Color(0.95, 0.85, 0.35), "neck": Color(0.75, 0.62, 0.25), "chest": Color(0.35, 0.72, 0.42),
	"abdomen": Color(0.55, 0.85, 0.55), "pelvis": Color(0.22, 0.5, 0.32),
	"upperarm_r": Color(0.25, 0.45, 0.95), "forearm_r": Color(0.35, 0.75, 0.98), "hand_r": Color(0.6, 0.45, 0.95),
	"thigh_r": Color(0.15, 0.3, 0.7), "shin_r": Color(0.3, 0.9, 0.9), "foot_r": Color(0.55, 0.65, 0.85),
	"upperarm_l": Color(0.92, 0.3, 0.25), "forearm_l": Color(0.98, 0.6, 0.3), "hand_l": Color(0.95, 0.4, 0.7),
	"thigh_l": Color(0.65, 0.15, 0.15), "shin_l": Color(0.95, 0.75, 0.45), "foot_l": Color(0.85, 0.55, 0.55)}


## the region a bone's flesh belongs to ("" for a name that is not one of BONES)
static func region_of(bone: String) -> String:
	if not BONES.has(bone):
		return ""
	var s := bone.right(2) if bone.ends_with("_l") or bone.ends_with("_r") else ""
	var stem := bone.trim_suffix(s)
	match stem:
		"head":
			return "head"
		"neck_01":
			return "neck"
		"spine_03", "clavicle":
			return "chest"
		"spine_01", "spine_02":
			return "abdomen"
		"pelvis":
			return "pelvis"
		"upperarm":
			return "upperarm" + s
		"lowerarm":
			return "forearm" + s
		"thigh":
			return "thigh" + s
		"calf":
			return "shin" + s
		"foot", "ball":
			return "foot" + s
	return "hand" + s   # the hand and every finger bone


static var _region_ix := PackedInt32Array()   # BONES index -> REGIONS index (built once)


static func _bone_region_ix() -> PackedInt32Array:
	if _region_ix.is_empty():
		for b in BONES:
			_region_ix.append(REGIONS.find(region_of(b)))
	return _region_ix


## the skeleton's bones as segments in world space: [{"bone" (UE5 name), "bi" (BONES index), "a", "b"}], in BONES
## order. posed: the pose it holds now; else its rest. A bone the skeleton lacks is left out.
static func segments_from_skeleton(sk: Skeleton3D, posed := true) -> Array:
	var gx := sk.global_transform if sk.is_inside_tree() else sk.transform
	var at := func(b: int) -> Vector3: return gx * (sk.get_bone_global_pose(b) if posed else sk.get_bone_global_rest(b)).origin
	var ix := {}   # lower-case name -> skeleton bone ("Head" in the mannequin's glb)
	for b in sk.get_bone_count():
		ix[sk.get_bone_name(b).to_lower()] = b
	var out := []
	for bi in BONES.size():
		var nm: String = BONES[bi]
		if not ix.has(nm):
			continue
		var b: int = ix[nm]
		var a: Vector3 = at.call(b)
		var e := a
		var kids := sk.get_bone_children(b)
		var to: String = Body.CHILD.get(nm, "")
		if to != "" and ix.has(to):
			e = at.call(ix[to])
		elif ix.has("middle_01" + nm.right(2)) and nm.begins_with("hand_"):
			e = at.call(ix["middle_01" + nm.right(2)])
		elif kids.size() == 1:
			e = at.call(kids[0])
		elif kids.size() > 1:
			e = Vector3.ZERO
			for k in kids:
				e += at.call(k)
			e /= kids.size()
		elif sk.get_bone_parent(b) >= 0:   # a leaf (the head): on along its parent's direction
			var pa: Vector3 = at.call(sk.get_bone_parent(b))
			e = a + (a - pa) * HEAD_K
		out.append({"bone": nm, "bi": bi, "a": a, "b": e})
	return out


## make sure the three channels are there (labels -1 until computed)
static func ensure(mesh: KMesh) -> void:
	if not mesh.has_attr(CH_BONE):
		mesh.add_attr(CH_BONE, KMesh.AD_VERT, TYPE_FLOAT, -1.0)
	if not mesh.has_attr(CH_CM):
		mesh.add_attr(CH_CM, KMesh.AD_VERT, TYPE_FLOAT, 0.0)
	if not mesh.has_attr(CH_REGION):
		mesh.add_attr(CH_REGION, KMesh.AD_VERT, TYPE_FLOAT, -1.0)


## Label verts (all, or only the ids in `only`) by the nearest segment. xf: the mesh's local space -> the segments' space.
## Returns {"ms", "n" (verts labelled), "tests" (segment distance tests run)}.
static func compute(mesh: KMesh, segs: Array, xf := Transform3D.IDENTITY, only := PackedInt32Array(), all := true) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	ensure(mesh)
	var ns := segs.size()
	var sa := PackedVector3Array()
	var sd := PackedVector3Array()   # b - a
	var sl2 := PackedFloat32Array()  # |b - a|^2
	var sbi := PackedInt32Array()
	for s in segs:
		sa.append(s["a"])
		sd.append(s["b"] - s["a"])
		sl2.append((s["b"] - s["a"]).length_squared())
		sbi.append(s["bi"])
	var rix := _bone_region_ix()
	var ch_b: PackedFloat32Array = mesh.attr_data(CH_BONE)
	var ch_d: PackedFloat32Array = mesh.attr_data(CH_CM)
	var ch_r: PackedFloat32Array = mesh.attr_data(CH_REGION)
	var ids := only
	if all:
		ids = PackedInt32Array()
		ids.resize(mesh.verts.size())
		for i in ids.size():
			ids[i] = i
	# bucket the verts (world space) into cells
	var wp := PackedVector3Array()
	wp.resize(ids.size())
	var cells := {}
	var inv := 1.0 / CELL
	for k in ids.size():
		var p: Vector3 = xf * mesh.verts[ids[k]]
		wp[k] = p
		var key := Vector3i(floori(p.x * inv), floori(p.y * inv), floori(p.z * inv))
		if cells.has(key):
			(cells[key] as Array).append(k)
		else:
			cells[key] = [k]
	var tests := 0
	var cand := PackedInt32Array()
	var dc := PackedFloat32Array()
	dc.resize(ns)
	for key in cells:
		var ks: Array = cells[key]
		var lo: Vector3 = wp[ks[0]]
		var hi := lo
		for k in ks:
			lo = lo.min(wp[k])
			hi = hi.max(wp[k])
		var c := (lo + hi) * 0.5
		var h := (hi - lo).length() * 0.5
		var best := INF
		for s in ns:
			var q := c - sa[s]
			var t := 0.0 if sl2[s] < 1e-12 else clampf(q.dot(sd[s]) / sl2[s], 0.0, 1.0)
			var d := (q - sd[s] * t).length()
			dc[s] = d
			best = minf(best, d)
		tests += ns
		cand.clear()
		for s in ns:
			if dc[s] <= best + 2.0 * h + 1e-6:
				cand.append(s)
		for k in ks:
			var p: Vector3 = wp[k]
			var bs := -1
			var bd2 := INF
			var bover := INF
			for s in cand:
				var q := p - sa[s]
				var l2 := sl2[s]
				var t := 0.0 if l2 < 1e-12 else q.dot(sd[s]) / l2
				var over := 0.0
				var cp: Vector3
				if t <= 0.0:
					over = -t
					cp = sa[s]
				elif t >= 1.0:
					over = t - 1.0
					cp = sa[s] + sd[s]
				else:
					cp = sa[s] + sd[s] * t
				over *= sqrt(l2)
				var d2 := p.distance_squared_to(cp)
				if d2 < bd2 or (d2 == bd2 and (over < bover or (over == bover and sbi[s] < sbi[bs]))):
					bd2 = d2
					bs = s
					bover = over
			tests += cand.size()
			var v: int = ids[k]
			ch_b[v] = sbi[bs]
			ch_d[v] = sqrt(bd2) * 100.0
			ch_r[v] = rix[sbi[bs]]
	mesh.set_attr_data(CH_BONE, ch_b)
	mesh.set_attr_data(CH_CM, ch_d)
	mesh.set_attr_data(CH_REGION, ch_r)
	return {"ms": (Time.get_ticks_usec() - t0) / 1000.0, "n": ids.size(), "tests": tests}


static func _body_sig(segs: Array, xf: Transform3D) -> int:
	var pv := PackedVector3Array([xf.origin, xf.basis.x, xf.basis.y, xf.basis.z])
	var bi := PackedInt32Array()
	for s in segs:
		pv.append(s["a"])
		pv.append(s["b"])
		bi.append(s["bi"])
	return hash([pv, bi])


## Keep the labels fresh: everything again when the body or the mesh's placement changed (or the vertex count, or the
## channels are missing), else only the verts that moved since last time. -> compute()'s result + "full"; n = 0 when
## nothing had to change. The last labelled positions live in the mesh's meta (not saved).
static func refresh(mesh: KMesh, segs: Array, xf := Transform3D.IDENTITY) -> Dictionary:
	var bsig := _body_sig(segs, xf)
	var c: Dictionary = mesh.get_meta("_kbody", {})
	var full: bool = c.is_empty() or c["body"] != bsig or (c["pos"] as PackedVector3Array).size() != mesh.verts.size() \
		or not (mesh.has_attr(CH_BONE) and mesh.has_attr(CH_CM) and mesh.has_attr(CH_REGION))
	var r: Dictionary
	if full:
		r = compute(mesh, segs, xf)
	else:
		if c["vhash"] == hash(mesh.verts):
			return {"ms": 0.0, "n": 0, "tests": 0, "full": false}
		var old: PackedVector3Array = c["pos"]
		var moved := PackedInt32Array()
		for i in old.size():
			if old[i] != mesh.verts[i]:
				moved.append(i)
		r = compute(mesh, segs, xf, moved, false)
	r["full"] = full
	mesh.set_meta("_kbody", {"body": bsig, "pos": mesh.verts.duplicate(), "vhash": hash(mesh.verts)})
	return r


## one vertex's label: {"bone", "region", "cm"} ("" / -1 when not labelled)
static func label(mesh: KMesh, v: int) -> Dictionary:
	if not mesh.has_attr(CH_BONE) or v < 0 or v >= mesh.verts.size():
		return {"bone": "", "region": "", "cm": -1.0}
	var b := int(mesh.get_attr(CH_BONE, v))
	var r := int(mesh.get_attr(CH_REGION, v))
	return {"bone": BONES[b] if b >= 0 and b < BONES.size() else "", "region": REGIONS[r] if r >= 0 and r < REGIONS.size() else "",
		"cm": float(mesh.get_attr(CH_CM, v))}


## the hover words: "forearm_l, 1.8 cm from bone lowerarm_l"
static func readout(mesh: KMesh, v: int) -> String:
	var l := label(mesh, v)
	if l["bone"] == "":
		return "not labelled yet"
	return "%s, %.1f cm from bone %s" % [l["region"], l["cm"], l["bone"]]


static func color_of(region: String) -> Color:
	return COLORS.get(region, Color(0.5, 0.5, 0.5))


## region -> vertex count, for the regions present
static func counts(mesh: KMesh) -> Dictionary:
	var out := {}
	if not mesh.has_attr(CH_REGION):
		return out
	for r in (mesh.attr_data(CH_REGION) as PackedFloat32Array):
		var nm: String = REGIONS[int(r)] if r >= 0.0 else "none"
		out[nm] = int(out.get(nm, 0)) + 1
	return out


## the region layer: every face, each corner in its vertex's region colour, OFF_TINT out along the vertex normal
static func layer_mesh(mesh: KMesh) -> ArrayMesh:
	var am := ArrayMesh.new()
	if not mesh.has_attr(CH_REGION) or mesh.faces.is_empty():
		return am
	var reg: PackedFloat32Array = mesh.attr_data(CH_REGION)
	var pal := PackedColorArray()
	for r in REGIONS:
		pal.append(color_of(r))
	var pos := PackedVector3Array()
	var cols := PackedColorArray()
	var nor := PackedVector3Array()
	for fi in mesh.face_count():
		var fp: PackedInt32Array = mesh.faces[fi]
		for i in range(1, fp.size() - 1):
			for c in [0, i + 1, i]:   # Godot's front face is clockwise; KMesh counter-clockwise
				var v: int = fp[c]
				var n := mesh.vert_normals[v]
				pos.append(mesh.verts[v] + n * OFF_TINT)
				nor.append(n)
				var r := int(reg[v])
				cols.append(pal[r] if r >= 0 else Color(0.5, 0.5, 0.5))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nor
	arr[Mesh.ARRAY_COLOR] = cols
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


# ---------------------------------------------------------------- the model preview's view (an instance per KMeshEditUI)

var ui: Node                  # the KMeshEditUI
var on := false               # "colour by region" shown
var layer: MeshInstance3D     # the tint, a child of the view
var legend: PanelContainer
var hover_text := ""
var hover_at := Vector2.ZERO
var last := {}                # the last refresh() that changed something
var _mat: StandardMaterial3D


func setup(edit_ui: Node) -> void:
	ui = edit_ui
	name = "kmesh_body"


## the skeleton the labels follow: the active fighter's
func segs() -> Array:
	var sk: Skeleton3D = ui.m.skel
	return segments_from_skeleton(sk, true) if sk != null else []


## every frame while the preview is open (and once at its start): the labels follow the mesh and the body
func tick() -> void:
	if ui == null or not ui.on or ui.mesh == null or ui.view == null:
		return
	var r := refresh(ui.mesh, segs(), ui.view.global_transform)
	if int(r["n"]) > 0:
		last = r
		if on:
			_rebuild()
	elif on and (layer == null or layer.get_parent() != ui.view):
		_rebuild()


func toggle() -> void:
	on = not on
	tick()
	_rebuild()
	if on:
		var c := counts(ui.mesh)
		ui.m._say("Model: colour by body region on: %d regions on this mesh (%s). Hover a vertex for its bone. Shift+H turns it off" % [c.size(), ", ".join(c.keys())])
	else:
		hover_text = ""
		ui.m._say("Model: colour by body region off (Shift+H turns it on)")


## the preview closed: the layer goes with the view, the legend hides
func close() -> void:
	on = false
	hover_text = ""
	layer = null
	if legend != null:
		legend.visible = false


func _rebuild() -> void:
	if ui.view == null:
		return
	if layer == null or not is_instance_valid(layer) or layer.get_parent() != ui.view:
		layer = MeshInstance3D.new()
		layer.name = "body_regions"
		ui.view.add_child(layer)
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 0.8
	layer.visible = on
	layer.mesh = layer_mesh(ui.mesh) if on else null
	layer.material_override = _mat
	_legend_update()


func _legend_update() -> void:
	if legend == null:
		legend = PanelContainer.new()
		legend.name = "body_legend"
		legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.bg_color = Color(Tok.c("float"), 0.92)
		st.set_corner_radius_all(8)
		st.set_content_margin_all(8)
		legend.add_theme_stylebox_override("panel", st)
		var vb := VBoxContainer.new()
		vb.name = "rows"
		vb.add_theme_constant_override("separation", 3)
		legend.add_child(vb)
		vb.add_child(ui.m._label("Body regions (Shift+H)", 14, "text"))
		for r in REGIONS:
			var row := HBoxContainer.new()
			row.name = r
			row.add_theme_constant_override("separation", 6)
			var sw := ColorRect.new()
			sw.name = "swatch"
			sw.color = color_of(r)
			sw.custom_minimum_size = Vector2(14, 14)
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(sw)
			var lb: Label = ui.m._label("", 13, "text:0.8")
			lb.name = "words"
			row.add_child(lb)
			vb.add_child(row)
		ui.m.ui_root.add_child(legend)
	legend.visible = on and ui.on
	if not legend.visible:
		return
	var c := counts(ui.mesh)
	for r in REGIONS:
		var row: Control = legend.get_node("rows/" + r)
		row.visible = c.has(r)
		(row.get_node("words") as Label).text = "%s: %d verts" % [r, int(c.get(r, 0))]
	legend.reset_size()
	var cl: Rect2 = ui.m.nav_clear_rect()   # bottom right of the free view (the topology legend has the bottom left)
	var sz := legend.get_combined_minimum_size()
	legend.position = Vector2(cl.end.x - sz.x - LEGEND_PAD, cl.end.y - sz.y - LEGEND_PAD)


## the mouse moved over the view (no button down): the vertex under it, read out. -> the vertex or -1
func hover(p: Vector2) -> int:
	hover_text = ""
	if not on or ui.view == null:
		return -1
	var h: Dictionary = ui.view.pick(ui.m.cam, p, 1e6)   # the hit face's nearest corner, however far
	if h.is_empty() or int(h["vert"]) < 0:
		return -1
	hover_text = readout(ui.mesh, int(h["vert"]))
	hover_at = p
	return int(h["vert"])


func draw(ov: Control) -> void:
	if not on or hover_text == "":
		return
	var f := ov.get_theme_default_font()
	var fs := 14
	var sz := f.get_string_size(hover_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var at := hover_at + Vector2(16, -10)
	ov.draw_rect(Rect2(at - Vector2(6, sz.y - 2), sz + Vector2(12, 8)), Color(Tok.c("float"), 0.92), true)
	ov.draw_string(f, at, hover_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Tok.c("text"))
