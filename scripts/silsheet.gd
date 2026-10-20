## SILHOUETTE SHEET (ROADMAP_400 K26): animators judge readability by looking at the key poses as pure black shapes. Command
## "Check: silhouette sheet of the key poses": every card of the open scene is drawn from the CURRENT camera's direction as a flat
## black shape (body and held weapon, unshaded, nothing else) on white, tiled into one picture, saved as
## user://silhouettes/<scene>_sheet.png (never in scenes/) and shown in a popup, with a readability line per pose.
## DRAWING: a SubViewport that shares the app's 3D world, its camera a copy of the main camera (same direction, same field of view,
## centred on the figure's pelvis), seeing only render layer Shading.SIL_LAYER; the figure's pieces take a flat black material and
## that layer for the length of the draw, then get back exactly what they had. The playhead is moved to each card and put back.
## NUMBERS per pose (from the tile's pixels): FILL = black area / bounding-box area (a blob fills its box: low readability);
## NEGATIVE SPACE = white regions INSIDE THE FIGURE'S CONVEX HULL (the rubber band round the shape) that hold a square DISC of the figure's
## height wide: the air between limbs and body, under an arm, between the legs (a standing figure's box is mostly air at the
## corners, which says nothing, so the hull and not the box bounds it); HOLES = those regions closed on every side by the shape. FLAG "arms inside the torso": every elbow and wrist falls inside the
## torso's outline (shoulders and hips, widened by half the shoulder span, projected by the tile camera): the arms vanish into
## the body, the classic unreadable pose (the animator's rule: keep the action's limbs off the torso, Williams, The Animator's
## Survival Kit, "staging / silhouette"; Lasseter 1987 principle 'staging').
class_name SilSheet
extends RefCounted

const TILE := Vector2i(240, 320)
const DIR := "user://silhouettes"
const DISC := 0.03   # a pocket of air counts as negative space when it holds a square this share of the figure's height wide (room for a limb: 5 cm at 1.8 m)
const LOW_FILL := 0.62      # a pose that fills more than this share of its box is a blob
const GUTTER := 4
const FIT_DIST := 3.8   # metres back from the pelvis column: the whole body and a weapon's reach in a 3:4 tile at a 40 degree field

const LIMB_JOINTS := ["lowerarm_l", "hand_l", "lowerarm_r", "hand_r"]


## the sheet's file for a scene name: user://silhouettes/<name>_sheet.png
static func sheet_path(scene_name: String) -> String:
	var nm := scene_name.get_file().get_basename()
	if nm == "":
		nm = "scene"
	return "%s/%s_sheet.png" % [DIR, nm]


## black mask of a picture: 1 where the pixel is dark (the figure), 0 white
static func mask_of(img: Image) -> PackedByteArray:
	var im := img.duplicate() as Image
	im.convert(Image.FORMAT_L8)
	var d := im.get_data()
	var out := PackedByteArray()
	out.resize(d.size())
	for i in d.size():
		out[i] = 1 if d[i] < 128 else 0
	return out


## the numbers of one tile's mask: {black, box (Rect2i), fill, regions, holes}
static func measure(mask: PackedByteArray, w: int, h: int) -> Dictionary:
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	var black := 0
	for y in h:
		for x in w:
			if mask[y * w + x] == 1:
				black += 1
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if black == 0:
		return {"black": 0, "box": Rect2i(), "fill": 0.0, "regions": 0, "holes": 0, "black_share": 0.0}
	var box := Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
	# the figure's convex hull (from the row and column extremes of the black), and per row the span the hull covers
	var pts := PackedVector2Array()
	for y in range(y0, y1 + 1):
		var lo := -1
		var hi := -1
		for x in range(x0, x1 + 1):
			if mask[y * w + x] == 1:
				if lo < 0:
					lo = x
				hi = x
		if lo >= 0:
			pts.append(Vector2(lo, y))
			pts.append(Vector2(hi + 1, y))
			pts.append(Vector2(lo, y + 1))
			pts.append(Vector2(hi + 1, y + 1))
	for x in range(x0, x1 + 1):
		var tp := -1
		var bt := -1
		for y in range(y0, y1 + 1):
			if mask[y * w + x] == 1:
				if tp < 0:
					tp = y
				bt = y
		if tp >= 0:
			pts.append(Vector2(x, tp))
			pts.append(Vector2(x + 1, bt + 1))
	var hull := Geometry2D.convex_hull(pts)
	var span_lo := PackedInt32Array()
	var span_hi := PackedInt32Array()
	span_lo.resize(h)
	span_hi.resize(h)
	for y in h:
		span_lo[y] = w
		span_hi[y] = -1
		if y < y0 or y > y1:
			continue
		var yc := float(y) + 0.5
		var lo_f := 1e9
		var hi_f := -1e9
		for k in hull.size() - 1:
			var p := hull[k]
			var q := hull[k + 1]
			if (p.y <= yc and q.y > yc) or (q.y <= yc and p.y > yc):
				var xx := p.x + (yc - p.y) / (q.y - p.y) * (q.x - p.x)
				lo_f = minf(lo_f, xx)
				hi_f = maxf(hi_f, xx)
		if hi_f >= lo_f:
			span_lo[y] = int(ceil(lo_f - 0.5))
			span_hi[y] = int(floor(hi_f - 0.5))
	# AIR = white inside the hull. A pocket of air counts when it holds a square of side 2 r + 1 (r = DISC x the figure's height:
	# room for a limb), found with a prefix-sum erosion; the pockets are the 4-connected groups of such squares' centres
	var air := PackedByteArray()
	air.resize(w * h)
	var hull_px := 0
	for y in range(y0, y1 + 1):
		for x in range(span_lo[y], span_hi[y] + 1):
			hull_px += 1
			if mask[y * w + x] == 0:
				air[y * w + x] = 1
	# which air is closed: label the air's connected regions; a region touching the hull's edge is open to the outside
	var label := PackedInt32Array()
	label.resize(w * h)
	var closed := [true]   # label 0 unused
	for y in range(y0, y1 + 1):
		for x in range(span_lo[y], span_hi[y] + 1):
			var i := y * w + x
			if air[i] == 0 or label[i] != 0:
				continue
			var id := closed.size()
			closed.append(true)
			label[i] = id
			var stack := PackedInt32Array([i])
			while not stack.is_empty():
				var c: int = stack[stack.size() - 1]
				stack.resize(stack.size() - 1)
				var cx := c % w
				var cy := c / w
				for dd in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var nx: int = cx + dd[0]
					var ny: int = cy + dd[1]
					if ny < y0 or ny > y1 or nx < span_lo[ny] or nx > span_hi[ny]:
						closed[id] = false   # the hull's own edge: open to the outside
						continue
					var ni := ny * w + nx
					if air[ni] == 0 or label[ni] != 0:
						continue
					label[ni] = id
					stack.append(ni)
	var r := maxi(2, roundi(DISC * float(box.size.y)))
	var W1 := w + 1
	var pre := PackedInt32Array()   # pre[(y)*(w+1)+x] = number of non-air pixels in [0,x) x [0,y)
	pre.resize(W1 * (h + 1))
	for y in h:
		var run := 0
		for x in w:
			run += 1 - air[y * w + x]
			pre[(y + 1) * W1 + x + 1] = pre[y * W1 + x + 1] + run
	var surv := PackedByteArray()
	surv.resize(w * h)
	for y in range(y0 + r, y1 - r + 1):
		for x in range(x0 + r, x1 - r + 1):
			if air[y * w + x] == 0:
				continue
			var ax := x - r
			var ay := y - r
			var bx := x + r + 1
			var by := y + r + 1
			if pre[by * W1 + bx] - pre[ay * W1 + bx] - pre[by * W1 + ax] + pre[ay * W1 + ax] == 0:
				surv[y * w + x] = 1
	var regions := 0
	var holes := 0
	var done := PackedByteArray()
	done.resize(w * h)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := y * w + x
			if surv[i] == 0 or done[i] == 1:
				continue
			regions += 1
			if closed[label[i]]:
				holes += 1
			var stack := PackedInt32Array([i])
			done[i] = 1
			while not stack.is_empty():
				var c: int = stack[stack.size() - 1]
				stack.resize(stack.size() - 1)
				var cx := c % w
				var cy := c / w
				for dd in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var nx: int = cx + dd[0]
					var ny: int = cy + dd[1]
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var ni := ny * w + nx
					if surv[ni] == 1 and done[ni] == 0:
						done[ni] = 1
						stack.append(ni)
	return {"black": black, "box": box, "fill": float(black) / float(box.get_area()), "hull_fill": float(black) / float(maxi(1, hull_px)), "regions": regions, "holes": holes, "black_share": float(black) / float(w * h)}


## true when every elbow and wrist (screen points) is inside the torso outline (screen polygon)
static func arms_inside(torso: PackedVector2Array, limb_pts: Array) -> bool:
	if torso.size() < 3 or limb_pts.is_empty():
		return false
	for p in limb_pts:
		if not Geometry2D.is_point_in_polygon(p, torso):
			return false
	return true


## the one-line verdict for a pose's numbers
static func verdict(r: Dictionary) -> String:
	if r["arms_hidden"]:
		return "LOW: arms inside the torso (move an arm out from the body)"
	if r["fill"] > LOW_FILL:
		return "LOW: a blob (fills %d%% of its box; open the limbs)" % roundi(100.0 * r["fill"])
	if r["regions"] == 0:
		return "LOW: no air between the limbs (open one)"
	return "reads"


## the tiles tiled into one picture: columns x rows, a white gutter and a pale line round each tile
static func tile_sheet(tiles: Array, cols: int) -> Image:
	var rows := int(ceil(float(tiles.size()) / float(cols)))
	var w := cols * (TILE.x + GUTTER) + GUTTER
	var h := rows * (TILE.y + GUTTER) + GUTTER
	var sheet := Image.create(w, h, false, Image.FORMAT_RGB8)
	sheet.fill(Color.LIGHT_GRAY)
	for k in tiles.size():
		var ox := GUTTER + (k % cols) * (TILE.x + GUTTER)
		var oy := GUTTER + (k / cols) * (TILE.y + GUTTER)
		var t: Image = (tiles[k] as Image).duplicate()
		t.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(t, Rect2i(Vector2i.ZERO, TILE), Vector2i(ox, oy))
	return sheet


static func columns_for(n: int) -> int:
	return clampi(int(ceil(sqrt(float(n) * 1.6))), 1, 6)


## THE SHEET of the open scene (m = main). Returns {"image", "tiles", "results", "path"} ({} when there is nothing to draw)
static func make(m: Node, save := true) -> Dictionary:
	var S: Scene = m.S
	if S.cards.is_empty():
		return {}
	var shading_was: String = m.shading.mode
	if shading_was != "solid":
		m.shading.set_mode(m, "solid")
	var playhead_was: float = m.playhead
	var vp := SubViewport.new()
	vp.name = "silsheet_stage"
	vp.size = TILE
	vp.world_3d = m.get_viewport().world_3d
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	m.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.WHITE
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	var cam := Camera3D.new()
	cam.environment = env
	cam.cull_mask = Shading.SIL_LAYER
	cam.fov = m.cam.fov
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	vp.add_child(cam)
	cam.current = true
	var flat := StandardMaterial3D.new()
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flat.albedo_color = Color.BLACK
	var orig := {}
	var lay := {}
	var over := {}   # the highlight pass (selection, hover, warnings) is a material_overlay: off for the draw
	for mi in Shading.bodies(m):
		orig[mi] = mi.material_override
		lay[mi] = mi.layers
		over[mi] = mi.material_overlay
		mi.material_override = flat
		mi.material_overlay = null
		mi.layers = Shading.SIL_LAYER
	var times: Array = S.times()
	var tiles := []
	var results := []
	for i in S.cards.size():
		var t: float = (times[i] as Array)[1]
		m.playhead = t
		var ps: Scene = m._ps()
		ps.apply(m.B, ps.play_t(t))
		m._refresh()
		for mi in orig:   # _refresh puts the skin looks back on the pieces: the flat black goes on again, after it
			mi.material_override = flat
			mi.material_overlay = null
			mi.layers = Shading.SIL_LAYER
		# the camera: the main camera's direction, looking at the figure's pelvis column, far enough back to hold the whole body
		var pel: Vector3 = m.B.P["pelvis"]
		var at := Vector3(pel.x, m.target.y, pel.z)
		var basis: Basis = m.cam.global_transform.basis
		var back := FIT_DIST
		# sideways: centred on the span of the joints and the weapon's tip along the camera's right axis, so a long reach is not cut
		var rt: Vector3 = basis.x
		var lo := INF
		var hi := -INF
		var span_pts := []
		for j in m.B.P:
			span_pts.append(m.B.P[j])
		if m.B.wep_on:
			span_pts.append(m.B.wep_point(0.0))
			span_pts.append(m.B.wep_point(m.B.wep_len))
		for q in span_pts:
			lo = minf(lo, (q as Vector3).dot(rt))
			hi = maxf(hi, (q as Vector3).dot(rt))
		at += rt * (0.5 * (lo + hi) - at.dot(rt))
		cam.global_transform = Transform3D(basis, at + basis * Vector3(0, 0, back))
		await m.get_tree().process_frame
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var mk := mask_of(img)
		var r := measure(mk, img.get_width(), img.get_height())
		# the arms-in-torso test with the tile camera's own projection
		var sh_l := cam.unproject_position(m.B.P["upperarm_l"])
		var sh_r := cam.unproject_position(m.B.P["upperarm_r"])
		var hp_l := cam.unproject_position(m.B.P["thigh_l"])
		var hp_r := cam.unproject_position(m.B.P["thigh_r"])
		var poly := PackedVector2Array([sh_l, sh_r, hp_r, hp_l])
		var grown := Geometry2D.offset_polygon(poly, 0.5 * sh_l.distance_to(sh_r))
		var torso := poly
		if not grown.is_empty():
			torso = grown[0]
		var pts := []
		for j in LIMB_JOINTS:
			pts.append(cam.unproject_position(m.B.P[j]))
		r["arms_hidden"] = arms_inside(torso, pts)
		r["name"] = String((S.cards[i] as Dictionary).get("name", "card %d" % (i + 1)))
		r["verdict"] = verdict(r)
		tiles.append(img)
		results.append(r)
	# put everything back exactly as it was
	for mi in orig:
		if is_instance_valid(mi):
			mi.material_override = orig[mi]
			mi.material_overlay = over[mi]
			mi.layers = lay[mi]
	vp.queue_free()
	m.playhead = playhead_was
	var ps2: Scene = m._ps()
	ps2.apply(m.B, ps2.play_t(playhead_was))
	m._refresh()
	if shading_was != "solid":
		m.shading.set_mode(m, shading_was)
	var sheet := tile_sheet(tiles, columns_for(tiles.size()))
	var path := sheet_path(String(S.name))
	if save:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
		sheet.save_png(ProjectSettings.globalize_path(path))
	return {"image": sheet, "tiles": tiles, "results": results, "path": path, "cols": columns_for(tiles.size())}
