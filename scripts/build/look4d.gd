class_name Look4D
extends RefCounted
## LOOK4D: a scene at time t as four formats an AI can read (docs/LOOK4D_DESIGN.md, docs/LOOK4D_WIRING.md).
##   A  plain screenshot, 768 x 432
##   B  a 4-frame filmstrip (t-3h .. t) tiled 2 x 2 into ONE 768 x 432 image (same pixel budget as A and C)
##   C  ONE annotated image: id + view-depth label per visible part, yellow arrow = the 3D velocity projected to the screen (tail at the part centre,
##      tip at centre + v * ARROW_T), 3 white ghost dots at t-h, t-2h, t-3h, hidden parts as a dashed cyan outline of their silhouette box. No colour encodes a number.
##   D  JSON, 3 significant figures: id, pos, vel, speed, angvel, mass, momentum, view depth, visible share, occluded (+ by), contacts, penetration.
## Reuses: LookFacts (id_color, decode_ids, the flat id material: the id pass), FrameFacts (focal, project: the pinhole and silhouette boxes),
## AssemblyAnim (the scenes' poses at t -/+ dt, in look4d_scenes.gd), RigidDrop.spin (angular velocity between two poses), KCad.distance / overlap_volume (contacts, in the scenes).
## NOT reused: LookFacts.id_pass / serve (they need the app's Part pipeline: m.bld.part) - the same primitives are used on the scene's own nodes.
##
## A scene is a Dictionary (see look4d_scenes.gd):
##   name, ids: [String], build: Callable(world: Node3D) (fills sc.nodes {id: MeshInstance3D} and sc.mass {id: kg}), set_time: Callable(t),
##   contacts: Callable() -> [{a, b, gap_mm, pen_mm3}] at the pose set last, shapes: Callable() -> {id: shape} (optional, for the truth data),
##   camera {pos, look, fov}, t0, h (ghost step, s), own_env (bool: build() adds its own light and environment)
## A context (open) holds the scene's SubViewport (shaded), and on demand an id pass and a solo pass.

const W := 768
const H := 432
const DT := 1.0 / 60.0            # half step of the central difference: v = (x(t + DT) - x(t - DT)) / (2 DT)
const ARROW_T := 0.25             # s: the arrow tip is where the part would be in ARROW_T at its present velocity
const HIDE_FRAC := 0.25           # visible share under this (and a silhouette in the picture) = occluded
const MOVE_MS := 0.001            # m/s: a part slower than this is static (no arrow, no ghosts, no velocity row in D)
const CS := 0.71875               # C: the picture is drawn at this scale (552 x 311) so a legend strip fits in 768 x 432
const IMG_W := 552
const IMG_H := 311
const LEG_W := 216
const YELLOW := Color(1.0, 0.85, 0.0)
const CYAN := Color(0.2, 0.9, 1.0)
const SIG := 3                    # D: significant figures
const GHOSTS := 3
const HORIZON := 0.5              # s, for the truth data
const TRUTH_STEP := 1.0 / 30.0


# ---------------------------------------------------------------- the context
static func open(host: Node, sc: Dictionary, size := Vector2i(W, H)) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	sc["nodes"] = {}
	sc["mass"] = {}
	if not bool(sc.get("own_env", false)):
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.93, 0.94, 0.96)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.8, 0.8, 0.85)
		env.ambient_light_energy = 0.6
		var we := WorldEnvironment.new()
		we.environment = env
		world.add_child(we)
		var sun := DirectionalLight3D.new()
		world.add_child(sun)
		sun.look_at_from_position(Vector3(0.5, 1.0, 1.0), Vector3.ZERO, Vector3.UP)
	(sc["build"] as Callable).call(world)
	var cam := Camera3D.new()
	cam.near = 0.01
	cam.far = 100.0
	world.add_child(cam)
	var cd: Dictionary = sc["camera"]
	cam.fov = float(cd.get("fov", 40.0))
	cam.look_at_from_position(cd["pos"], cd["look"], Vector3.UP)
	cam.current = true
	return {"sc": sc, "host": host, "vp": vp, "world": world, "cam": cam, "idvp": null, "solo": null, "id_nodes": {}}


static func close(ctx: Dictionary) -> void:
	for k in ["vp", "idvp", "solo"]:
		if ctx.get(k) != null and is_instance_valid(ctx[k]):
			(ctx[k] as Node).queue_free()


static func frames(n := 2) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


static func ids(ctx: Dictionary) -> Array:
	return ctx["sc"]["ids"]


## sets the scene to time t (the source nodes move)
static func at(ctx: Dictionary, t: float) -> void:
	(ctx["sc"]["set_time"] as Callable).call(t)


## the shaded picture of the scene at time t, at size (default 768 x 432)
static func shot(ctx: Dictionary, t: float, size := Vector2i(W, H)) -> Image:
	at(ctx, t)
	var vp: SubViewport = ctx["vp"]
	vp.size = size
	await frames(2)
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img


# ---------------------------------------------------------------- camera
static func cam_dict(ctx: Dictionary, size := Vector2i(W, H)) -> Dictionary:
	var cam: Camera3D = ctx["cam"]
	return {"xf": cam.global_transform, "fov": cam.fov, "keep_width": cam.keep_aspect == Camera3D.KEEP_WIDTH, "w": size.x, "h": size.y, "near": cam.near}


## a world point to picture pixels (y down) and the view depth in metres (> 0 in front of the camera); the FrameFacts pinhole
static func project_pt(ctx: Dictionary, p: Vector3, size := Vector2i(W, H)) -> Dictionary:
	var c := cam_dict(ctx, size)
	var f := FrameFacts.focal(c)
	var v: Vector3 = (c["xf"] as Transform3D).affine_inverse() * p
	var z := -v.z
	if z <= 1e-6:
		return {"px": Vector2(NAN, NAN), "z": z}
	return {"px": Vector2(size.x * 0.5 + v.x * f / z, size.y * 0.5 - v.y * f / z), "z": z}


# ---------------------------------------------------------------- the states (no render)
## {id: {c: Vector3 (the mesh box centre, world), b: Basis, vis: bool}} at time t
static func state(ctx: Dictionary, t: float) -> Dictionary:
	at(ctx, t)
	var out := {}
	var nodes: Dictionary = ctx["sc"]["nodes"]
	for id in nodes:
		var n := nodes[id] as MeshInstance3D
		var xf := n.global_transform
		var bb: AABB = n.mesh.get_aabb() if n.mesh != null else AABB()
		out[id] = {"c": xf * bb.get_center(), "b": xf.basis, "vis": n.is_visible_in_tree()}
	return out


## the central-difference kinematics at t: {id: {c, v (m/s), w (rad/s), speed}}; dt is the half step (a wrong dt is the test's planted fault)
static func kinematics(ctx: Dictionary, t: float, dt := DT) -> Dictionary:
	var a := state(ctx, t - dt)
	var m := state(ctx, t)
	var b := state(ctx, t + dt)
	var out := {}
	for id in m:
		var v: Vector3 = ((b[id]["c"] as Vector3) - (a[id]["c"] as Vector3)) / (2.0 * dt)
		var w: Vector3 = RigidDrop.spin(a[id]["b"], b[id]["b"], 2.0 * dt)
		out[id] = {"c": m[id]["c"], "v": v, "w": w, "speed": v.length(), "vis": m[id]["vis"]}
	at(ctx, t)
	return out


# ---------------------------------------------------------------- the id and solo passes
## the first n ids LookFacts.decode_ids can read back (it drops a colour whose three 4-bit levels sum to under 2)
static func codes(n: int) -> Array:
	var out: Array = []
	var v := 1
	while out.size() < n:
		if ((v >> 8) & 15) + ((v >> 4) & 15) + (v & 15) >= 2:
			out.append(v)
		v += 1
	return out


static func _clone_set(ctx: Dictionary, vp: SubViewport, colors: bool) -> Dictionary:
	var nodes: Dictionary = ctx["sc"]["nodes"]
	var ids_a: Array = ctx["sc"]["ids"]
	var out := {}
	var cd := codes(ids_a.size())
	for i in ids_a.size():
		var id: String = ids_a[i]
		var src := nodes[id] as MeshInstance3D
		var mi := MeshInstance3D.new()
		mi.mesh = src.mesh
		mi.material_override = LookFacts._flat(LookFacts.id_color(cd[i]) if colors else Color(1, 1, 1, 1))
		vp.add_child(mi)
		out[id] = mi
	return out


static func _pass_vp(ctx: Dictionary, transparent: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.own_world_3d = true
	vp.transparent_bg = transparent
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_debanding = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 1)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var src: Camera3D = ctx["cam"]
	var cam := Camera3D.new()
	cam.transform = src.global_transform
	cam.fov = src.fov
	cam.near = src.near
	cam.far = src.far
	vp.add_child(cam)
	(ctx["host"] as Node).add_child(vp)
	cam.current = true
	return vp


static func _sync(ctx: Dictionary, clones: Dictionary, only := "") -> void:
	var nodes: Dictionary = ctx["sc"]["nodes"]
	for id in clones:
		var mi := clones[id] as MeshInstance3D
		var src := nodes[id] as MeshInstance3D
		mi.global_transform = src.global_transform
		mi.visible = src.is_visible_in_tree() and (only == "" or only == id)


## per id at the pose set now: {solo_px (the part alone), vis_px (its colour in the full id pass), frac, by (the id covering most of its silhouette), bbox [x0, y0, x1, y1] of the silhouette}
## ids come from LookFacts.id_color (1-based index of the scene's id list); an id with solo_px 0 is fully outside the picture (or behind the camera)
static func measure(ctx: Dictionary) -> Dictionary:
	if ctx["idvp"] == null:
		ctx["idvp"] = _pass_vp(ctx, false)
		ctx["id_nodes"] = _clone_set(ctx, ctx["idvp"], true)
		ctx["solo"] = _pass_vp(ctx, true)
		ctx["solo_nodes"] = _clone_set(ctx, ctx["solo"], false)
	var ids_a: Array = ctx["sc"]["ids"]
	var cd := codes(ids_a.size())
	var idx := {}
	for i in cd.size():
		idx[int(cd[i])] = i
	_sync(ctx, ctx["id_nodes"])
	await frames(2)
	var idimg: Image = (ctx["idvp"] as SubViewport).get_texture().get_image()
	idimg.convert(Image.FORMAT_RGB8)
	var map := LookFacts.decode_ids(idimg)
	var vis := {}
	for p in map.size():
		var k := map[p]
		if k > 0:
			vis[k] = int(vis.get(k, 0)) + 1
	var out := {}
	var nm_set := {}
	for id in named(ctx):
		nm_set[id] = true
	for i in ids_a.size():
		var id: String = ids_a[i]
		var node := (ctx["sc"]["nodes"][id] as MeshInstance3D)
		var row := {"solo_px": 0, "vis_px": int(vis.get(cd[i], 0)), "frac": 0.0, "by": "", "bbox": [0, 0, 0, 0]}
		if node.is_visible_in_tree() and nm_set.has(id):
			_sync(ctx, ctx["solo_nodes"], id)
			await frames(2)
			var si: Image = (ctx["solo"] as SubViewport).get_texture().get_image()
			si.convert(Image.FORMAT_RGBA8)
			var d := si.get_data()
			var n := 0
			var cover := {}
			var x0 := W
			var y0 := H
			var x1 := -1
			var y1 := -1
			for p in W * H:
				if d[p * 4 + 3] > 127:
					n += 1
					var x := p % W
					var y := p / W
					if x < x0: x0 = x
					if x > x1: x1 = x
					if y < y0: y0 = y
					if y > y1: y1 = y
					var k := map[p]
					if k != cd[i] and k > 0:
						cover[k] = int(cover.get(k, 0)) + 1
			row["solo_px"] = n
			if n > 0:
				row["bbox"] = [x0, y0, x1, y1]
				row["frac"] = minf(1.0, float(row["vis_px"]) / float(n))
				var best := 0
				for k in cover:
					if int(cover[k]) > best:
						best = int(cover[k])
						row["by"] = String(ids_a[int(idx.get(int(k), 0))])
		out[id] = row
	return out


static func occluded(row: Dictionary) -> bool:
	return int(row["solo_px"]) > 0 and float(row["frac"]) < HIDE_FRAC


# ---------------------------------------------------------------- D
static func round_sig(x: float, n := SIG) -> float:
	if x == 0.0 or not is_finite(x):
		return x
	var e := int(floor(log(absf(x)) / log(10.0)))
	var s := pow(10.0, n - 1 - e)
	return roundf(x * s) / s


static func _r(x: Variant) -> Variant:
	if x is float:
		return round_sig(x)
	if x is Vector3:
		return [round_sig(x.x), round_sig(x.y), round_sig(x.z)]
	if x is Array:
		return (x as Array).map(func(e): return _r(e))
	if x is Dictionary:
		var o := {}
		for k in x:
			o[k] = _r(x[k])
		return o
	return x


## the parts a reader is told about (D rows, C marks, questions); the others are still in every picture and in the id pass
static func named(ctx: Dictionary) -> Array:
	return ctx["sc"].get("named", ctx["sc"]["ids"])


static func _moving(k: Dictionary) -> bool:
	return float(k["speed"]) > MOVE_MS or (k["w"] as Vector3).length() > 0.01


## D v2 (compact): header row of field names, one array row per part. Moving parts carry pos, vel, speed, angvel, mass, momentum, depth, visible share, occluder;
## static parts (speed <= 1 mm/s, no spin) only pos, mass, depth, visible share, occluder (vel = 0 is implied). Contacts: only pairs that touch (gap <= 0.1 mm) or overlap (> 1 mm3).
## occluded = visible share under 0.25 (stated in "units"). Parts outside the picture have depth/vis as they are (vis 0), nothing else flags them.
static func digest(ctx: Dictionary, t: float, kin: Dictionary, meas: Dictionary, contacts: Array) -> Dictionary:
	var sc: Dictionary = ctx["sc"]
	var cam: Camera3D = ctx["cam"]
	var nm: Array = named(ctx)
	var mov: Array = []
	var sta: Array = []
	for id in nm:
		var k: Dictionary = kin[id]
		var m: Dictionary = meas[id]
		var mass := float(sc["mass"].get(id, 1.0))
		var pr := project_pt(ctx, k["c"])
		var by := ""
		if occluded(m):
			by = String(m["by"]) if nm.has(m["by"]) else "other"
		if _moving(k):
			mov.append([id, k["c"], k["v"], k["speed"], k["w"], mass, (k["v"] as Vector3) * mass, pr["z"], m["frac"], by])
		else:
			sta.append([id, k["c"], mass, pr["z"], m["frac"], by])
	var cons: Array = []
	for c in contacts:
		if nm.has(c["a"]) and nm.has(c["b"]) and (float(c.get("gap_mm", 0.0)) <= 0.1 or float(c.get("pen_mm3", 0.0)) > 1.0):
			cons.append([c["a"], c["b"], c.get("gap_mm", 0.0), c.get("pen_mm3", 0.0)])
	return _r({
		"scene": sc["name"], "t_s": t,
		"units": "world m, y up; vel m/s; angvel rad/s; momentum kg m/s; mass kg NOMINAL; depth m along the camera axis; vis = visible share of the part's silhouette, occluded if < 0.25; occluded_by = covering part ('other' = unlisted); static parts have vel 0",
		"camera": {"pos": cam.global_position, "look_dir": -cam.global_transform.basis.z, "up": cam.global_transform.basis.y, "fov_deg_vertical": cam.fov, "image_px": [W, H]},
		"moving_cols": ["id", "pos", "vel", "speed", "angvel", "mass", "momentum", "depth", "vis", "occluded_by"], "moving": mov,
		"static_cols": ["id", "pos", "mass", "depth", "vis", "occluded_by"], "static": sta,
		"touching_or_overlapping": cons, "touching_cols": ["a", "b", "gap_mm", "overlap_mm3"]})


## the digest as {id: {pos, vel, speed, angvel, mass, momentum, depth, vis, by}} (static rows get zero velocities)
static func rows(dg: Dictionary) -> Dictionary:
	var out := {}
	for r in dg["moving"]:
		out[r[0]] = {"pos": _v3(r[1]), "vel": _v3(r[2]), "speed": float(r[3]), "angvel": _v3(r[4]), "mass": float(r[5]), "momentum": _v3(r[6]), "depth": float(r[7]), "vis": float(r[8]), "by": String(r[9])}
	for r in dg["static"]:
		out[r[0]] = {"pos": _v3(r[1]), "vel": Vector3.ZERO, "speed": 0.0, "angvel": Vector3.ZERO, "mass": float(r[2]), "momentum": Vector3.ZERO, "depth": float(r[3]), "vis": float(r[4]), "by": String(r[5])}
	return out


static func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


# ---------------------------------------------------------------- C (Set-of-Mark style)
## C is 768 x 432: the picture at CS scale in the top-left (IMG_W x IMG_H), a legend strip at the right (LEG_W), a key under the picture. Equal pixel count with A and B.
## One numbered mark per named part that is in the picture; marks are placed greedily so no two boxes overlap, a leader line joins a moved mark to its part;
## arrows (yellow) and ghost dots (white, 3 earlier positions h apart) only for parts faster than 1 mm/s; hidden parts (vis < 0.25) get a dashed cyan box.
## plan() is pure data: {scene: [items in picture coordinates], marks: [{n, id, rect, anchor}], legend: [items in canvas coordinates]}
static func plan(ctx: Dictionary, kin: Dictionary, meas: Dictionary, past: Array) -> Dictionary:
	var sc: Dictionary = ctx["sc"]
	var arrow_t := float(sc.get("arrow_t", ARROW_T))
	var h := float(sc["h"])
	var cz := (ctx["cam"] as Camera3D).global_transform
	var inview: Array = []
	for id in named(ctx):
		if int(meas[id]["solo_px"]) > 0:
			inview.append(id)
	var number := {}
	for i in inview.size():
		number[inview[i]] = i + 1
	var order: Array = inview.duplicate()
	order.sort_custom(func(a, b):
		var sa := float(kin[a]["speed"])
		var sb := float(kin[b]["speed"])
		if absf(sa - sb) > 1e-9:
			return sa > sb
		return int(meas[a]["solo_px"]) > int(meas[b]["solo_px"]))
	var scene_items: Array = []
	var marks: Array = []
	var placed: Array = []
	var area := Rect2(0, 0, IMG_W, IMG_H)
	for id in order:
		var k: Dictionary = kin[id]
		var m: Dictionary = meas[id]
		var bb: Array = m["bbox"]
		if occluded(m):
			scene_items.append({"k": "dash", "c": CYAN, "r": Rect2(Vector2(bb[0], bb[1]) * CS, Vector2(bb[2] - bb[0], bb[3] - bb[1]) * CS)})
		if float(k["speed"]) > MOVE_MS:
			for g in past:
				var gp := project_pt(ctx, g[id])
				if is_finite((gp["px"] as Vector2).x):
					scene_items.append({"k": "dot", "p": (gp["px"] as Vector2) * CS})
			var pc := project_pt(ctx, k["c"])
			var tip := project_pt(ctx, (k["c"] as Vector3) + (k["v"] as Vector3) * arrow_t)
			var a: Vector2 = (pc["px"] as Vector2) * CS
			var b: Vector2 = (tip["px"] as Vector2) * CS
			if is_finite(a.x) and is_finite(b.x):
				var u := (b - a) / maxf((b - a).length(), 1e-6)
				var nrm := Vector2(-u.y, u.x)
				var hl := minf(10.0, (b - a).length() * 0.4)
				scene_items.append({"k": "arrow", "c": YELLOW, "a": a, "b": b, "h1": b - u * hl + nrm * hl * 0.5, "h2": b - u * hl - nrm * hl * 0.5})
	# marks: greedy, nearest free spot to the silhouette centre
	for id in order:
		var bb: Array = meas[id]["bbox"]
		var anchor := Vector2((bb[0] + bb[2]) * 0.5, (bb[1] + bb[3]) * 0.5) * CS
		var txt := str(number[id])
		var sz := Vector2(8.0 * txt.length() + 6.0, 15.0)
		var best := Rect2()
		var found := false
		var radii := [0.0, 10.0, 18.0, 26.0, 34.0, 44.0, 56.0, 70.0, 88.0, 110.0]
		for rad: float in radii:
			var steps := 1 if rad == 0.0 else 12
			for si in steps:
				var ang := TAU * float(si) / float(steps)
				var cpos := anchor + Vector2(cos(ang), sin(ang)) * rad
				var r := Rect2(cpos - sz * 0.5, sz)
				if not area.encloses(r):
					continue
				var clash := false
				for q in placed:
					if (q as Rect2).grow(1.0).intersects(r):
						clash = true
						break
				if not clash:
					best = r
					found = true
					break
			if found:
				break
		if not found:   # a last resort: scan the picture for any free box
			var y := 0.0
			while y + sz.y <= IMG_H and not found:
				var x := 0.0
				while x + sz.x <= IMG_W and not found:
					var r2 := Rect2(Vector2(x, y), sz)
					var clash2 := false
					for q in placed:
						if (q as Rect2).grow(1.0).intersects(r2):
							clash2 = true
							break
					if not clash2:
						best = r2
						found = true
					x += 4.0
				y += 4.0
		placed.append(best)
		marks.append({"n": int(number[id]), "id": id, "rect": best, "anchor": anchor})
		if (best.get_center() - anchor).length() > 7.0:
			scene_items.append({"k": "leader", "a": best.get_center(), "b": anchor})
	for mk in marks:
		scene_items.append({"k": "mark", "r": mk["rect"], "s": str(mk["n"])})
	marks.sort_custom(func(a, b): return int(a["n"]) < int(b["n"]))
	# the legend strip and the key
	var legend: Array = []
	legend.append({"k": "text", "p": Vector2(IMG_W + 8, 14), "s": "# part  depth m  speed m/s", "c": Color(0.7, 0.8, 1.0), "fs": 11})
	var yy := 31.0
	for mk in marks:
		var id: String = mk["id"]
		var k: Dictionary = kin[id]
		var pr := project_pt(ctx, k["c"])
		var spd := ""
		if float(k["speed"]) > MOVE_MS:
			var vz := (cz.affine_inverse().basis * (k["v"] as Vector3)).z
			spd = "%.2f" % float(k["speed"])
			if absf(vz) > 0.1 * float(k["speed"]):
				spd += " away" if vz < 0.0 else " toward"
		else:
			spd = "static"
		var nm := String(id)
		if nm.length() > 14:
			nm = nm.substr(0, 14)
		legend.append({"k": "text", "p": Vector2(IMG_W + 8, yy), "s": "%d %s %.1f %s" % [int(mk["n"]), nm, float(pr["z"]), spd], "c": Color(1, 1, 1), "fs": 11})
		yy += 16.0
	var key: Array = [
		"yellow arrow: where the part is in %.2g s at its present velocity" % arrow_t,
		"white dots: its 3 earlier positions, %.2g s apart (dot nearest the part = latest)" % h,
		"dashed cyan box: part hidden behind others (< 25 %% visible)",
		"numbers: marks, one per listed part in the picture; see the list at the right"]
	for i in key.size():
		legend.append({"k": "text", "p": Vector2(8, IMG_H + 20 + 20 * i), "s": key[i], "c": Color(0.85, 0.85, 0.85), "fs": 12})
	return {"scene": scene_items, "marks": marks, "legend": legend}


## the old layout (labels "name d=..m" at the projected centre, no declutter): used only as the test's planted control. Returns the label boxes in A's pixels
static func naive_boxes(ctx: Dictionary, kin: Dictionary, meas: Dictionary) -> Array:
	var out: Array = []
	for id in named(ctx):
		if int(meas[id]["solo_px"]) <= 0:
			continue
		var pc := project_pt(ctx, kin[id]["c"])
		var c: Vector2 = pc["px"]
		if not is_finite(c.x):
			continue
		var label := "%s d=%.1fm" % [id, float(pc["z"])]
		out.append(Rect2(c + Vector2(-20, -12), Vector2(7.0 * label.length(), 15)))
	return out


static func boxes_intersect(rs: Array) -> int:
	var n := 0
	for i in rs.size():
		for j in range(i + 1, rs.size()):
			if (rs[i] as Rect2).intersects(rs[j] as Rect2):
				n += 1
	return n


# ---------------------------------------------------------------- the whole production
static func tile(imgs: Array) -> Image:
	var out := Image.create(W, H, false, Image.FORMAT_RGB8)
	for i in 4:
		var im := imgs[i] as Image
		if im.get_width() != W / 2 or im.get_height() != H / 2:
			im.resize(W / 2, H / 2, Image.INTERPOLATE_BILINEAR)
		out.blit_rect(im, Rect2i(0, 0, W / 2, H / 2), Vector2i((i % 2) * (W / 2), (i / 2) * (H / 2)))
	return out


static func save(img: Image, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)


## writes A.png B.png C.png D.json truth_data.json timing.json into dir; returns {ms: {A, B, C, D}, files, digest, meas, kin}
static func produce(host: Node, sc: Dictionary, dir: String) -> Dictionary:
	var ctx := open(host, sc)
	var t0 := float(sc["t0"])
	var h := float(sc["h"])
	await frames(3)
	var ms := {}
	# A
	var u := Time.get_ticks_usec()
	var a := await shot(ctx, t0)
	ms["A"] = (Time.get_ticks_usec() - u) / 1000.0
	save(a, dir + "/A.png")
	# B
	u = Time.get_ticks_usec()
	var strip: Array = []
	for k in range(GHOSTS, -1, -1):
		strip.append(await shot(ctx, t0 - k * h, Vector2i(W / 2, H / 2)))
	(ctx["vp"] as SubViewport).size = Vector2i(W, H)
	var b := tile(strip)
	ms["B"] = (Time.get_ticks_usec() - u) / 1000.0
	save(b, dir + "/B.png")
	# the data both D and C need
	u = Time.get_ticks_usec()
	var kin := kinematics(ctx, t0)
	var ms_kin := (Time.get_ticks_usec() - u) / 1000.0
	u = Time.get_ticks_usec()
	var meas := await measure(ctx)
	var ms_meas := (Time.get_ticks_usec() - u) / 1000.0
	u = Time.get_ticks_usec()
	at(ctx, t0)
	var contacts: Array = (sc["contacts"] as Callable).call()
	var ms_con := (Time.get_ticks_usec() - u) / 1000.0
	u = Time.get_ticks_usec()
	var dg := digest(ctx, t0, kin, meas, contacts)
	var txt := JSON.stringify(dg)
	ms["D"] = ms_kin + ms_meas + ms_con + (Time.get_ticks_usec() - u) / 1000.0
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/D.json", FileAccess.WRITE)
	f.store_string(txt)
	f.close()
	# C
	u = Time.get_ticks_usec()
	var past: Array = []
	for k in range(1, GHOSTS + 1):
		var st := state(ctx, t0 - k * h)
		var d := {}
		for id in st:
			d[id] = st[id]["c"]
		past.append(d)
	at(ctx, t0)
	var c := await draw_c(ctx, a, kin, meas, past)
	ms["C"] = ms["A"] + ms_kin + ms_meas + (Time.get_ticks_usec() - u) / 1000.0
	save(c, dir + "/C.png")
	# the truth data for tools/look4d_truth.py
	var td := truth_data(ctx, t0, kin, meas, contacts)
	var f2 := FileAccess.open(dir + "/truth_data.json", FileAccess.WRITE)
	f2.store_string(JSON.stringify(td))
	f2.close()
	var f3 := FileAccess.open(dir + "/timing.json", FileAccess.WRITE)
	f3.store_string(JSON.stringify({"ms": ms, "d_bytes": txt.length(), "d_tokens_est": int(ceil(txt.length() / 4.0)), "image_tokens": int(round(W * H / 750.0)), "parts": {"kin": ms_kin, "measure": ms_meas, "contacts": ms_con}}))
	f3.close()
	var out := {"ms": ms, "digest": dg, "meas": meas, "kin": kin, "contacts": contacts, "plan": plan(ctx, kin, meas, past), "ctx": ctx, "A": a, "B": b, "C": c, "d_text": txt}
	return out


static func draw_c(ctx: Dictionary, base: Image, kin: Dictionary, meas: Dictionary, past: Array) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	(ctx["host"] as Node).add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.11)
	bg.size = Vector2(W, H)
	vp.add_child(bg)
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(base)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.size = Vector2(IMG_W, IMG_H)
	vp.add_child(tr)
	var pl := plan(ctx, kin, meas, past)
	var ov := Overlay.new()
	ov.size = Vector2(IMG_W, IMG_H)
	ov.clip_contents = true
	ov.items = pl["scene"]
	ov.font = ThemeDB.fallback_font
	vp.add_child(ov)
	var lg := Overlay.new()
	lg.size = Vector2(W, H)
	lg.items = pl["legend"]
	lg.font = ThemeDB.fallback_font
	vp.add_child(lg)
	await frames(3)
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	vp.queue_free()
	return img


## the drawing of a plan(): pure items in the Control's own coordinates
class Overlay extends Control:
	var items: Array = []
	var font: Font

	func _draw() -> void:
		for it in items:
			match String(it["k"]):
				"dot":
					draw_circle(it["p"], 4.0, Color(0, 0, 0))
					draw_circle(it["p"], 3.0, Color(1, 1, 1))
				"arrow":
					draw_line(it["a"], it["b"], it["c"], 3.0)
					draw_line(it["b"], it["h1"], it["c"], 3.0)
					draw_line(it["b"], it["h2"], it["c"], 3.0)
				"leader":
					draw_line(it["a"], it["b"], Color(1, 1, 1), 1.0)
				"dash":
					var r: Rect2 = it["r"]
					var ps := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
					for i in 4:
						draw_dashed_line(ps[i], ps[i + 1], it["c"], 2.0, 6.0)
				"mark":
					var rr: Rect2 = it["r"]
					draw_rect(rr, Color(0, 0, 0, 0.88))
					draw_rect(rr, Color(1, 1, 1), false, 1.0)
					draw_string(font, rr.position + Vector2(3, 12), it["s"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1))
				"text":
					draw_string(font, it["p"], it["s"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(it.get("fs", 14)), it["c"])


# ---------------------------------------------------------------- the truth data
## numbers for the truth generator only (never shown to a reader): per sample time the world centre, projected pixel, depth and shape of every id,
## plus the id list, names, silhouette counts, contacts at t0
static func truth_data(ctx: Dictionary, t0: float, kin: Dictionary, meas: Dictionary, contacts: Array) -> Dictionary:
	var sc: Dictionary = ctx["sc"]
	var samples: Array = []
	var k := -int(round(0.3 / TRUTH_STEP))
	while float(k) * TRUTH_STEP <= HORIZON + 1e-9:
		var t := t0 + float(k) * TRUTH_STEP
		var st := state(ctx, t)
		var shapes := shapes_now(ctx)
		var row := {}
		for id in named(ctx):
			var pr := project_pt(ctx, st[id]["c"])
			row[id] = {"c": _r2(st[id]["c"]), "px": [_fin(pr["px"].x), _fin(pr["px"].y)], "z": pr["z"], "shape": shapes[id], "vis": st[id]["vis"]}
		samples.append({"t": t, "k": k, "objs": row})
		k += 1
	at(ctx, t0)
	var kinout := {}
	for id in named(ctx):
		kinout[id] = {"c": _r2(kin[id]["c"]), "v": _r2(kin[id]["v"]), "w": _r2(kin[id]["w"]), "speed": kin[id]["speed"]}
	return {"scene": sc["name"], "t0": t0, "ids": named(ctx), "all_ids": sc["ids"], "arrow_t": float(sc.get("arrow_t", ARROW_T)), "h": float(sc["h"]), "dt": DT, "image": [W, H], "kin": kinout, "meas": _named_meas(ctx, meas), "contacts": contacts, "samples": samples, "mass": sc["mass"],
		"camera": {"pos": _r2(ctx["cam"].global_position), "look_dir": _r2(-ctx["cam"].global_transform.basis.z), "fov": ctx["cam"].fov}, "may_ask": sc.get("may_ask", []), "kind": sc.get("kind", "motion")}


static func _named_meas(ctx: Dictionary, meas: Dictionary) -> Dictionary:
	var o := {}
	for id in named(ctx):
		o[id] = meas[id]
	return o


static func _fin(x: float) -> Variant:
	return x if is_finite(x) else null


static func _r2(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


## the shape of every id at the pose set now: {"k": "aabb", "min", "max"} | {"k": "sphere", "c", "r"} | {"k": "capsule", "a", "b", "r"} (scene override via sc.shapes)
static func shapes_now(ctx: Dictionary) -> Dictionary:
	var sc: Dictionary = ctx["sc"]
	var over: Dictionary = (sc["shapes"] as Callable).call() if sc.has("shapes") else {}
	var out := {}
	for id in sc["ids"]:
		if over.has(id):
			out[id] = over[id]
			continue
		var n := sc["nodes"][id] as MeshInstance3D
		var bb: AABB = n.global_transform * n.mesh.get_aabb()
		out[id] = {"k": "aabb", "min": _r2(bb.position), "max": _r2(bb.end)}
	return out
