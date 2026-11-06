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
	var adir := {}
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
				adir[id] = u
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
		var radii := [14.0, 20.0, 26.0, 34.0, 44.0, 56.0, 70.0, 88.0, 110.0]
		for rad: float in radii:
			var steps := 16
			for si in steps:
				var ang := TAU * float(si) / float(steps)
				var dirv := Vector2(cos(ang), sin(ang))
				if adir.has(id) and dirv.dot(adir[id] as Vector2) > 0.5:
					continue   # never cover the arrow shaft
				var cpos := anchor + dirv * rad
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
		"yellow arrow: where the part is in %s s at its present velocity" % String.num(arrow_t, 2),
		"white dots: its 3 earlier positions, %s s apart (dot nearest the part = latest)" % String.num(h, 2),
		"dashed cyan box: part hidden behind others (< 25% visible)",
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


# ================================================================ ZOOM: levels 0-3, delta, characters, held (L1 AI-COST, docs/LOOK4D_ZOOM.md)
## An agent looks at a scene in steps, each dearer than the last:
##   level 0  one line (~30 tokens): moving count, fastest part, contacts, near misses, hidden, held
##   level 1  today's D made cheaper: moving parts [id, pos, vel, speed], spin only where it exists, static parts as NAMES, hidden pairs, touching pairs, held pairs
##   level 2  one part: size, shape, rotation, spin, acceleration, joint (value, limits, distance to the nearest limit), mass, material, contacts (point, normal, penetration),
##            the nearest gaps with time to collision, support, visible share, last 3 / next 3 positions
##   level 3  track: a time series for named parts over [t0, t1]
##   delta    only the fields that changed since a given time (applying it to frame n gives frame n+1 exactly)
##   character  per-bone data, foot contacts, balance (CoM against the support polygon)
## Optional scene keys used here: joint: Callable(id, t) -> {type, value, unit, lo, hi}; material: {id: String}; gap: Callable(a, b) -> mm (exact);
## groups: {name: [ids]} (a holder is reported by its group name); holdable: [ids] that can be held; char: bool; skeleton: {bone: parent}.
const FLOOR_P := 0.0001           # m: a position under this prints as 0
const FLOOR_V := 0.001            # m/s
const FLOOR_W := 0.01             # rad/s
const TOUCH_MM := 0.1
const HELD_MM := 1.0
const NEAR_MM := 2.0
const RIGID_M := 0.0005           # m: held = the offset between two parts stays within this over +-HELD_WIN
const HELD_WIN := 0.1             # s
const MOVED_M := 0.0005           # m: a part moved if its centre travelled this far over the window
const TTC_HORIZON := 0.5
const TTC_STEP := 0.025
const FOOT_DOWN_M := 0.015        # a foot capsule whose lowest point is under this is on the ground


static func _q(x: float, fl := 0.0) -> float:
	if not is_finite(x):
		return 0.0
	if absf(x) < fl:
		return 0.0
	return round_sig(x)


static func _qv(v: Vector3, fl := 0.0) -> Array:
	return [_q(v.x, fl), _q(v.y, fl), _q(v.z, fl)]


static func _num(x: float) -> String:
	if not is_finite(x):
		return "null"
	if x == 0.0:
		return "0"
	if x == floorf(x) and absf(x) < 1.0e9:
		return str(int(x))
	var e := int(floor(log(absf(x)) / log(10.0)))
	var s := String.num(x, clampi(SIG - 1 - e, 0, 12))
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s


## compact JSON text: no spaces, numbers printed shortest
static func txt(v: Variant) -> String:
	if v == null:
		return "null"
	if v is bool:
		return "true" if v else "false"
	if v is int:
		return str(v)
	if v is float:
		return _num(v)
	if v is String or v is StringName:
		return JSON.stringify(String(v))
	if v is Vector3:
		return txt([v.x, v.y, v.z])
	if v is Array:
		var parts: Array = []
		for e in v:
			parts.append(txt(e))
		return "[" + ",".join(parts) + "]"
	if v is Dictionary:
		var parts2: Array = []
		for k in v:
			parts2.append(JSON.stringify(String(k)) + ":" + txt(v[k]))
		return "{" + ",".join(parts2) + "}"
	return JSON.stringify(str(v))


static func tokens(v: Variant) -> int:
	return int(ceil(txt(v).length() / 4.0))


# ---------------------------------------------------------------- the snapshot
## visible share without a renderer (the MCP session is headless): rays from the camera to points on the part's camera-facing faces,
## blocked when they cross another part's box (in that part's own frame, so a turned box is a turned box). Same row layout as measure().
static func measure_ray(ctx: Dictionary) -> Dictionary:
	var sc: Dictionary = ctx["sc"]
	var nodes: Dictionary = sc["nodes"]
	var cam: Camera3D = ctx["cam"]
	var cp := cam.global_position
	var out := {}
	var nm_set := {}
	for id in named(ctx):
		nm_set[id] = true
	var inv := {}
	var loc := {}
	for id in sc["ids"]:
		var n0 := nodes[id] as MeshInstance3D
		inv[id] = n0.global_transform.affine_inverse()
		loc[id] = n0.mesh.get_aabb() if n0.mesh != null else AABB()
	for id in sc["ids"]:
		var n := nodes[id] as MeshInstance3D
		var row := {"solo_px": 0, "vis_px": 0, "frac": 0.0, "by": "", "bbox": [0, 0, 0, 0]}
		if n.is_visible_in_tree() and nm_set.has(id) and n.mesh != null:
			var bb: AABB = loc[id]
			var xf := n.global_transform
			var pts: Array = []
			var ctr := bb.get_center()
			var hs := bb.size * 0.5
			for ax in 3:
				for sg in [-1.0, 1.0]:
					var nl := Vector3.ZERO
					nl[ax] = sg
					var nw := (xf.basis * nl).normalized()
					var fc := xf * (ctr + nl * hs)
					if nw.dot(cp - fc) <= 0.0:
						continue
					var a1 := (ax + 1) % 3
					var a2 := (ax + 2) % 3
					for u in [-0.6, 0.0, 0.6]:
						for w in [-0.6, 0.0, 0.6]:
							var q := ctr + nl * hs
							q[a1] += u * hs[a1]
							q[a2] += w * hs[a2]
							pts.append(xf * q + nw * 1.0e-4)
			var free := 0
			var cover := {}
			for p in pts:
				var blocker := ""
				for oid in sc["ids"]:
					var on := nodes[oid] as MeshInstance3D
					if oid == id or on.mesh == null or not on.is_visible_in_tree():
						continue
					if _seg_hits_box(cp, p, inv[oid], loc[oid]):
						blocker = oid
						break
				if blocker == "":
					free += 1
				else:
					cover[blocker] = int(cover.get(blocker, 0)) + 1
			if pts.size() > 0:
				row["solo_px"] = 1
				row["frac"] = float(free) / float(pts.size())
				row["vis_px"] = free
				var best := 0
				for k in cover:
					if int(cover[k]) > best:
						best = int(cover[k])
						row["by"] = k
		out[id] = row
	return out


## does the segment a-b cross the box (local frame given by inv)
static func _seg_hits_box(a: Vector3, b: Vector3, inv: Transform3D, box: AABB) -> bool:
	var la := inv * a
	var lb := inv * b
	var d := lb - la
	var t0 := 0.0
	var t1 := 1.0
	for ax in 3:
		var lo := box.position[ax]
		var hi := box.end[ax]
		if absf(d[ax]) < 1e-12:
			if la[ax] < lo or la[ax] > hi:
				return false
		else:
			var ta := (lo - la[ax]) / d[ax]
			var tb := (hi - la[ax]) / d[ax]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				return false
	return true


static func _hasj(ctx: Dictionary, id: String, t: float) -> bool:
	var sc: Dictionary = ctx["sc"]
	if not sc.has("joint"):
		return false
	return not (sc["joint"] as Callable).call(id, t).is_empty()


## {id: [holder names]} for the named parts that move rigidly with a partner within HELD_MM, with no penetration needed.
## Rigid: over t -/+ HELD_WIN the offset between the two centres stays within RIGID_M in the world frame, or in either part's own frame (so a turning gripper and a tilting one both count).
## At least one of the two must have moved (two parts at rest are resting, not held). The held one is the one scene.holdable names, else the one without a joint, else the lighter.
## A holder inside a scene group is reported by the group's name.
static func held_map(ctx: Dictionary, t: float, contacts: Array) -> Dictionary:
	var sc: Dictionary = ctx["sc"]
	var nm: Array = named(ctx)
	var groups: Dictionary = sc.get("groups", {})
	var cand: Array = []
	for c in contacts:
		if nm.has(c["a"]) and nm.has(c["b"]) and (float(c.get("gap_mm", 0.0)) <= HELD_MM or float(c.get("pen_mm3", 0.0)) > 0.0):
			cand.append(c)
	var out := {}
	if cand.is_empty():
		return out
	var sa := state(ctx, t - HELD_WIN)
	var sm := state(ctx, t)
	var sb := state(ctx, t + HELD_WIN)
	at(ctx, t)
	var holdable: Variant = sc.get("holdable", null)
	for c in cand:
		var a: String = c["a"]
		var b: String = c["b"]
		var moved := false
		for id in [a, b]:
			moved = moved or ((sa[id]["c"] as Vector3).distance_to(sb[id]["c"]) > MOVED_M)
		if not moved:
			continue
		var dev_w := 0.0
		var dev_a := 0.0
		var dev_b := 0.0
		var w0: Vector3 = (sm[b]["c"] as Vector3) - (sm[a]["c"] as Vector3)
		var fa0: Vector3 = (sm[a]["b"] as Basis).inverse() * w0
		var fb0: Vector3 = (sm[b]["b"] as Basis).inverse() * (-w0)
		for s in [sa, sb]:
			var w1: Vector3 = (s[b]["c"] as Vector3) - (s[a]["c"] as Vector3)
			dev_w = maxf(dev_w, (w1 - w0).length())
			dev_a = maxf(dev_a, ((s[a]["b"] as Basis).inverse() * w1 - fa0).length())
			dev_b = maxf(dev_b, ((s[b]["b"] as Basis).inverse() * (-w1) - fb0).length())
		if minf(dev_w, minf(dev_a, dev_b)) > RIGID_M:
			continue
		var held := ""
		if holdable != null:
			var ha: bool = (holdable as Array).has(a)
			var hb: bool = (holdable as Array).has(b)
			if ha and not hb:
				held = a
			elif hb and not ha:
				held = b
			else:
				continue
		elif sc.has("joint"):
			var ja := _hasj(ctx, a, t)
			var jb := _hasj(ctx, b, t)
			if ja and not jb:
				held = b
			elif jb and not ja:
				held = a
			else:
				continue
		else:
			held = a if float(sc["mass"].get(a, 1.0)) <= float(sc["mass"].get(b, 1.0)) else b
		var holder := b if held == a else a
		var hn := holder
		for g in groups:
			if (groups[g] as Array).has(holder):
				hn = String(g)
		if not out.has(held):
			out[held] = []
		if not (out[held] as Array).has(hn):
			(out[held] as Array).append(hn)
	for k in out:
		(out[k] as Array).sort()
	return out


## everything the levels read, at time t (kinematics, visible share, contacts, held). render false = rays, no renderer and no await (the headless MCP session).
static func snap_ray(ctx: Dictionary, t: float) -> Dictionary:
	var key := "%s|ray" % t
	var cc := _snap_cache(ctx)
	if cc.has(key):
		at(ctx, t)
		return cc[key]
	var kin := kinematics(ctx, t)
	return _snap_store(ctx, key, t, kin, measure_ray(ctx), false)


static func snap(ctx: Dictionary, t: float, render := true) -> Dictionary:
	if not render:
		return snap_ray(ctx, t)
	var key := "%s|render" % t
	var cc := _snap_cache(ctx)
	if cc.has(key):
		at(ctx, t)
		return cc[key]
	var kin := kinematics(ctx, t)
	var meas := await measure(ctx)
	return _snap_store(ctx, key, t, kin, meas, true)


static func _snap_cache(ctx: Dictionary) -> Dictionary:
	if not ctx.has("snaps"):
		ctx["snaps"] = {}
	var cc: Dictionary = ctx["snaps"]
	if cc.size() > 8:
		cc.clear()
	return cc


static func _snap_store(ctx: Dictionary, key: String, t: float, kin: Dictionary, meas: Dictionary, render: bool) -> Dictionary:
	var sc: Dictionary = ctx["sc"]
	at(ctx, t)
	var contacts: Array = (sc["contacts"] as Callable).call() if sc.has("contacts") else []
	var S := {"t": t, "kin": kin, "meas": meas, "contacts": contacts, "render": render}
	S["held"] = held_map(ctx, t, contacts)
	(ctx["snaps"] as Dictionary)[key] = S
	return S


## touching (gap <= 0.1 mm or overlapping) pairs among the named parts
static func touching(ctx: Dictionary, S: Dictionary) -> Array:
	var nm: Array = named(ctx)
	var out: Array = []
	for c in S["contacts"]:
		if nm.has(c["a"]) and nm.has(c["b"]) and (float(c.get("gap_mm", 0.0)) <= TOUCH_MM or float(c.get("pen_mm3", 0.0)) > 1.0):
			out.append(c)
	return out


static func near_miss(ctx: Dictionary, S: Dictionary) -> Array:
	var nm: Array = named(ctx)
	var out: Array = []
	for c in S["contacts"]:
		var g := float(c.get("gap_mm", 0.0))
		if nm.has(c["a"]) and nm.has(c["b"]) and g > TOUCH_MM and g <= NEAR_MM and float(c.get("pen_mm3", 0.0)) <= 1.0:
			out.append(c)
	return out


# ---------------------------------------------------------------- level 0 and 1
static func level0(ctx: Dictionary, S: Dictionary) -> Dictionary:
	var nm: Array = named(ctx)
	var mv := 0
	var fast := ""
	var fs := 0.0
	var hid := 0
	for id in nm:
		var k: Dictionary = S["kin"][id]
		if _moving(k):
			mv += 1
		if float(k["speed"]) > fs:
			fs = float(k["speed"])
			fast = id
		if occluded(S["meas"][id]):
			hid += 1
	return {"scene": ctx["sc"]["name"], "t": _q(float(S["t"])), "moving": mv, "fastest": [fast, _q(fs)] if fast != "" else null,
		"contacts": touching(ctx, S).size(), "near": near_miss(ctx, S).size(), "hidden": hid, "held": (S["held"] as Dictionary).size()}


## moving parts [id, pos, vel, speed]; spin [id, angvel] for the parts that turn; still = names; hid = [id, by]; touch = [a, b, gap_mm, overlap_mm3]; held = [id, holders...]
static func level1(ctx: Dictionary, S: Dictionary) -> Dictionary:
	var sc: Dictionary = ctx["sc"]
	var cam: Camera3D = ctx["cam"]
	var mov: Array = []
	var spin: Array = []
	var still: Array = []
	var hid: Array = []
	for id in named(ctx):
		var k: Dictionary = S["kin"][id]
		var m: Dictionary = S["meas"][id]
		if _moving(k):
			mov.append([id, _qv(k["c"], FLOOR_P), _qv(k["v"], FLOOR_V), _q(float(k["speed"]), FLOOR_V)])
			if (k["w"] as Vector3).length() > FLOOR_W:
				spin.append([id, _qv(k["w"], FLOOR_W)])
		else:
			still.append(id)
		if occluded(m):
			hid.append([id, String(m["by"]) if named(ctx).has(m["by"]) else "other"])
	var touch: Array = []
	for c in touching(ctx, S):
		touch.append([c["a"], c["b"], _q(float(c.get("gap_mm", 0.0))), _q(float(c.get("pen_mm3", 0.0)))])
	var held: Array = []
	var hk: Array = (S["held"] as Dictionary).keys()
	hk.sort()
	for h in hk:
		held.append([h] + S["held"][h])
	var out := {"scene": sc["name"], "t": _q(float(S["t"])), "u": "m, m/s, rad/s, mm, mm3; pos = part centre; hid = visible share < 0.25",
		"cam": {"pos": _qv(cam.global_position, FLOOR_P), "dir": _qv(-cam.global_transform.basis.z, 0.001), "fov": _q(cam.fov)},
		"mov": mov, "spin": spin, "still": still}
	if not hid.is_empty():
		out["hid"] = hid
	if not touch.is_empty():
		out["touch"] = touch
	if not held.is_empty():
		out["held"] = held
	return out


# ---------------------------------------------------------------- shapes and gaps (level 2)
static func _scn_gap_m(sa: Dictionary, sb: Dictionary) -> float:
	var scn: Script = load("res://scripts/build/look4d_scenes.gd")
	return float(scn.shape_gap(sa, sb))


## the gap between two parts at the pose set now, mm (negative = overlap of the boxes). scene.gap (exact solids) when it has one, else the shapes
static func gap_mm(ctx: Dictionary, a: String, b: String, shapes: Dictionary = {}) -> float:
	var sc: Dictionary = ctx["sc"]
	if sc.has("gap"):
		return float((sc["gap"] as Callable).call(a, b))
	var sh: Dictionary = shapes if not shapes.is_empty() else shapes_now(ctx)
	return _scn_gap_m(sh[a], sh[b]) * 1000.0


## the gap between the two parts' world boxes, mm (negative = the boxes overlap)
static func box_gap_mm(ctx: Dictionary, a: String, b: String) -> float:
	var sh := {}
	for id in [a, b]:
		var n := ctx["sc"]["nodes"][id] as MeshInstance3D
		var bb: AABB = n.global_transform * n.mesh.get_aabb()
		sh[id] = {"k": "aabb", "min": _r2(bb.position), "max": _r2(bb.end)}
	return _scn_gap_m(sh[a], sh[b]) * 1000.0


static func _shape_kind(mesh: Mesh) -> String:
	if mesh is BoxMesh:
		return "box"
	if mesh is CapsuleMesh:
		return "capsule"
	if mesh is SphereMesh:
		return "sphere"
	if mesh is CylinderMesh:
		return "cylinder"
	return "mesh"


## the closest points of two shapes {k: aabb|sphere|capsule} -> {pa, pb, d (m, negative = inside), n (from a to b)}; the aabb pair reports its least penetration
static func closest(sa: Dictionary, sb: Dictionary) -> Dictionary:
	var ka := String(sa["k"])
	var kb := String(sb["k"])
	if ka == "aabb" and kb == "aabb":
		var la := _v3(sa["min"])
		var ha := _v3(sa["max"])
		var lb := _v3(sb["min"])
		var hb := _v3(sb["max"])
		var gap := Vector3.ZERO
		var inside := true
		var pen := INF
		var pax := 0
		var pdir := 1.0
		for ax in 3:
			var lo := maxf(la[ax], lb[ax])
			var hi := minf(ha[ax], hb[ax])
			if lo > hi:
				gap[ax] = lo - hi
				inside = false
			elif hi - lo < pen:
				pen = hi - lo
				pax = ax
				pdir = 1.0 if (la[ax] + ha[ax]) <= (lb[ax] + hb[ax]) else -1.0
		if inside:
			var n := Vector3.ZERO
			n[pax] = pdir
			var c := (la.max(lb) + ha.min(hb)) * 0.5
			c[pax] = minf(ha[pax], hb[pax]) if pdir > 0.0 else maxf(la[pax], lb[pax])
			return {"pa": c, "pb": c, "d": -pen, "n": n}
		var pa := Vector3.ZERO
		var pb := Vector3.ZERO
		for ax in 3:
			if gap[ax] > 0.0:
				var sgn := 1.0 if (la[ax] + ha[ax]) <= (lb[ax] + hb[ax]) else -1.0
				pa[ax] = ha[ax] if sgn > 0.0 else la[ax]
				pb[ax] = lb[ax] if sgn > 0.0 else hb[ax]
			else:
				var m := (maxf(la[ax], lb[ax]) + minf(ha[ax], hb[ax])) * 0.5
				pa[ax] = m
				pb[ax] = m
		return {"pa": pa, "pb": pb, "d": gap.length(), "n": (pb - pa).normalized()}
	var g := _scn_gap_m(sa, sb)
	# one of them round: closest points by sampling the round one's axis (good to a few mm, labelled bbox/approx)
	var best := INF
	var bp: Array = [Vector3.ZERO, Vector3.ZERO]
	for p in _axis_pts(sa):
		for q in _axis_pts(sb):
			var pp: Vector3 = p
			var qq: Vector3 = q
			if ka == "aabb":
				pp = _clamp_box(qq, sa)
			if kb == "aabb":
				qq = _clamp_box(pp, sb)
			var d := pp.distance_to(qq)
			if d < best:
				best = d
				bp = [pp, qq]
	var pa2: Vector3 = bp[0]
	var pb2: Vector3 = bp[1]
	var nn := (pb2 - pa2).normalized() if pa2.distance_to(pb2) > 1e-9 else Vector3.UP
	if ka != "aabb":
		pa2 += nn * float(sa["r"])
	if kb != "aabb":
		pb2 -= nn * float(sb["r"])
	return {"pa": pa2, "pb": pb2, "d": g, "n": nn}


static func _axis_pts(s: Dictionary) -> Array:
	match String(s["k"]):
		"aabb":
			return [(_v3(s["min"]) + _v3(s["max"])) * 0.5]
		"sphere":
			return [_v3(s["c"])]
		_:
			var out: Array = []
			for i in 21:
				out.append(_v3(s["a"]).lerp(_v3(s["b"]), i / 20.0))
			return out


static func _clamp_box(p: Vector3, s: Dictionary) -> Vector3:
	return p.clamp(_v3(s["min"]), _v3(s["max"]))


# ---------------------------------------------------------------- level 2
## one part in full. S = snap at the same t. Lengths in m, angles in deg, rates in rad/s, gaps in mm.
static func level2(ctx: Dictionary, S: Dictionary, id: String) -> Dictionary:
	var sc: Dictionary = ctx["sc"]
	var t := float(S["t"])
	var nodes: Dictionary = sc["nodes"]
	if not nodes.has(id):
		return {"error": "no part '%s'" % id}
	var n := nodes[id] as MeshInstance3D
	var k: Dictionary = S["kin"][id]
	var m: Dictionary = S["meas"][id]
	var out := {"id": id, "t": _q(t)}
	var bb: AABB = n.mesh.get_aabb() if n.mesh != null else AABB()
	var sc3 := n.global_transform.basis.get_scale()
	out["shape"] = _shape_kind(n.mesh)
	out["size_m"] = _qv(bb.size * sc3, 0.0)
	var e := n.global_transform.basis.orthonormalized().get_euler()
	out["rot_deg"] = [_q(rad_to_deg(e.x), 0.01), _q(rad_to_deg(e.y), 0.01), _q(rad_to_deg(e.z), 0.01)]
	out["pos"] = _qv(k["c"], FLOOR_P)
	out["vel"] = _qv(k["v"], FLOOR_V)
	out["angvel"] = _qv(k["w"], FLOOR_W)
	out["acc"] = _qv(acceleration(ctx, id, t), 0.01)
	if sc.has("joint"):
		var j: Dictionary = (sc["joint"] as Callable).call(id, t)
		at(ctx, t)
		if not j.is_empty():
			var jj := {"type": j["type"], "value": _q(float(j["value"]), 1e-9), "unit": j.get("unit", "")}
			if j.has("lo") and j.has("hi"):
				jj["lo"] = j["lo"]
				jj["hi"] = j["hi"]
				jj["to_limit"] = _q(minf(float(j["value"]) - float(j["lo"]), float(j["hi"]) - float(j["value"])), 1e-9)
				jj["near"] = "lo" if float(j["value"]) - float(j["lo"]) < float(j["hi"]) - float(j["value"]) else "hi"
			out["joint"] = jj
	out["mass_kg"] = _q(float(sc["mass"].get(id, 1.0)))
	out["mass_note"] = "nominal"
	out["material"] = String(sc.get("material", {}).get(id, "unspecified"))
	var shapes := shapes_now(ctx)
	var cons: Array = []
	var nm: Array = named(ctx)
	for c in S["contacts"]:
		var o := ""
		if c["a"] == id:
			o = c["b"]
		elif c["b"] == id:
			o = c["a"]
		if o == "" or not nodes.has(o):
			continue
		if float(c.get("gap_mm", 0.0)) <= TOUCH_MM or float(c.get("pen_mm3", 0.0)) > 1.0:
			var cl := closest(shapes[id], shapes[o])
			var nrm: Vector3 = cl["n"]
			cons.append({"with": o, "pt": _qv((cl["pa"] as Vector3).lerp(cl["pb"], 0.5), FLOOR_P), "n": _qv(nrm, 0.001), "pen_mm": _q(maxf(0.0, -float(cl["d"]) * 1000.0), 0.001), "src": "bbox"})
	out["contacts"] = cons
	# nearest gaps: the 4 nearest by shape, refined by scene.gap when it exists
	var cands: Array = []
	for o in nm:
		if o == id or not (nodes[o] as MeshInstance3D).is_visible_in_tree():
			continue
		cands.append([o, _scn_gap_m(shapes[id], shapes[o]) * 1000.0])
	cands.sort_custom(func(x, y): return float(x[1]) < float(y[1]))
	var topn: Array = cands.slice(0, 4)
	if sc.has("gap"):
		for r in topn:
			r[1] = gap_mm(ctx, id, String(r[0]))
		topn.sort_custom(func(x, y): return float(x[1]) < float(y[1]))
	var gaps: Array = []
	for r in topn.slice(0, 3):
		var o2 := String(r[0])
		gaps.append({"id": o2, "gap_mm": _q(float(r[1]), 0.001), "ttc_s": ttc(ctx, id, o2, t)})
	out["gaps"] = gaps
	# support: resting on = a part whose top face is under this one's bottom face (within 1 mm, boxes overlapping in plan); held_by from the held map
	var holders: Array = (S["held"].get(id, []) as Array).duplicate()
	var on: Array = []
	var mine: AABB = n.global_transform * bb
	for o in nodes:
		var on_n := nodes[o] as MeshInstance3D
		if o == id or on_n.mesh == null or not on_n.is_visible_in_tree():
			continue
		var ob: AABB = on_n.global_transform * on_n.mesh.get_aabb()
		if absf(mine.position.y - ob.end.y) <= 0.001 and mine.position.x < ob.end.x and mine.end.x > ob.position.x and mine.position.z < ob.end.z and mine.end.z > ob.position.z \
				and ob.end.y <= mine.get_center().y and holders.is_empty():
			on.append(o)
	on.sort()
	out["support"] = {"on": on, "held_by": holders}
	out["vis"] = {"share": _q(float(m["frac"])), "by": String(m["by"]), "src": "render" if bool(S.get("render", true)) else "ray"}
	var h := float(sc.get("h", 0.1))
	var prev: Array = []
	var nxt: Array = []
	for i in range(3, 0, -1):
		prev.append(_qv(state(ctx, t - i * h)[id]["c"], FLOOR_P))
	for i in range(1, 4):
		nxt.append(_qv(state(ctx, t + i * h)[id]["c"], FLOOR_P))
	at(ctx, t)
	out["prev"] = prev
	out["next"] = nxt
	out["step_s"] = _q(h)
	return out


## the second difference of the centre over the half step DT: (x(t+DT) - 2 x(t) + x(t-DT)) / DT^2, m/s2
static func acceleration(ctx: Dictionary, id: String, t: float) -> Vector3:
	var a: Vector3 = state(ctx, t - DT)[id]["c"]
	var b: Vector3 = state(ctx, t)[id]["c"]
	var c: Vector3 = state(ctx, t + DT)[id]["c"]
	at(ctx, t)
	return (c - 2.0 * b + a) / (DT * DT)


## seconds until the boxes of a and b first come within 0.1 mm, scanning TTC_HORIZON ahead (boxes, for speed); 0 = touching now; null = not within the horizon
static func ttc(ctx: Dictionary, a: String, b: String, t: float) -> Variant:
	at(ctx, t)
	var g0 := box_gap_mm(ctx, a, b)
	if g0 <= TOUCH_MM:
		return 0.0
	var prev_g := g0
	var prev_t := 0.0
	var tau := TTC_STEP
	while tau <= TTC_HORIZON + 1e-9:
		at(ctx, t + tau)
		var g := box_gap_mm(ctx, a, b)
		if g <= TOUCH_MM:
			at(ctx, t)
			var f := (prev_g - TOUCH_MM) / maxf(prev_g - g, 1e-9)
			return _q(prev_t + f * (tau - prev_t))
		prev_g = g
		prev_t = tau
		tau += TTC_STEP
	at(ctx, t)
	return null


# ---------------------------------------------------------------- level 3, frame, delta
## a time series for named parts over [t0, t1]: pos (m) and speed (m/s) per sample
static func track(ctx: Dictionary, part_ids: Array, t0: float, t1: float, step: float) -> Dictionary:
	var n := clampi(int(floor((t1 - t0) / maxf(step, 1e-6) + 1e-9)) + 1, 1, 200)
	var ts: Array = []
	var pos := {}
	var spd := {}
	for id in part_ids:
		pos[id] = []
		spd[id] = []
	for i in n:
		var t := t0 + i * step
		ts.append(_q(t))
		var kin := kinematics(ctx, t)
		for id in part_ids:
			if not kin.has(id):
				continue
			(pos[id] as Array).append(_qv(kin[id]["c"], FLOOR_P))
			(spd[id] as Array).append(_q(float(kin[id]["speed"]), FLOOR_V))
	return {"scene": ctx["sc"]["name"], "t": ts, "pos": pos, "speed": spd}


## the flat frame the delta works on: "id.field" -> value, "touch.a|b" -> [gap, overlap], over the same rounding as level 1 (static parts included, with their positions)
static func frame(ctx: Dictionary, S: Dictionary) -> Dictionary:
	var f := {}
	for id in named(ctx):
		var k: Dictionary = S["kin"][id]
		f[id + ".pos"] = _qv(k["c"], FLOOR_P)
		f[id + ".vel"] = _qv(k["v"], FLOOR_V)
		f[id + ".spin"] = _qv(k["w"], FLOOR_W)
		var m: Dictionary = S["meas"][id]
		f[id + ".hid"] = String(m["by"]) if occluded(m) else ""
		f[id + ".held"] = ",".join((S["held"].get(id, []) as Array))
	for c in touching(ctx, S):
		f["touch." + String(c["a"]) + "|" + String(c["b"])] = [_q(float(c.get("gap_mm", 0.0))), _q(float(c.get("pen_mm3", 0.0)))]
	return f


## {chg: {key: new value}, gone: [keys no longer in b]}; applying it to a gives b
static func delta(fa: Dictionary, fb: Dictionary) -> Dictionary:
	var chg := {}
	for k in fb:
		if not fa.has(k) or str(fa[k]) != str(fb[k]):
			chg[k] = fb[k]
	var gone: Array = []
	for k in fa:
		if not fb.has(k):
			gone.append(k)
	gone.sort()
	return {"chg": chg, "gone": gone}


static func apply_delta(fa: Dictionary, d: Dictionary) -> Dictionary:
	var out := fa.duplicate(true)
	for k in d["chg"]:
		out[k] = d["chg"][k]
	for k in d["gone"]:
		out.erase(k)
	return out


## the delta as text-ready data grouped by part: {since, t, chg: {id: {field: value}}, touch: {...}, gone: [...]}
static func delta_view(ctx: Dictionary, Sa: Dictionary, Sb: Dictionary) -> Dictionary:
	var d := delta(frame(ctx, Sa), frame(ctx, Sb))
	var by := {}
	var touch := {}
	for k in d["chg"]:
		var ks := String(k)
		if ks.begins_with("touch."):
			touch[ks.substr(6)] = d["chg"][k]
			continue
		var p := ks.rfind(".")
		var id := ks.substr(0, p)
		if not by.has(id):
			by[id] = {}
		by[id][ks.substr(p + 1)] = d["chg"][k]
	var out := {"scene": ctx["sc"]["name"], "since": _q(float(Sa["t"])), "t": _q(float(Sb["t"])), "chg": by}
	if not touch.is_empty():
		out["touch"] = touch
	if not (d["gone"] as Array).is_empty():
		out["gone"] = d["gone"]
	return out


# ---------------------------------------------------------------- characters
## foot contacts, balance, per-bone data. Needs capsule shapes. Support polygon = the convex hull (in x, z) of a circle of the capsule radius around both ends of every
## foot/ball capsule that is on the ground (lowest point under FOOT_DOWN_M); CoM = the mass-weighted centre of the bone centres (floor and bat left out).
static func character(ctx: Dictionary, S: Dictionary) -> Dictionary:
	var sc: Dictionary = ctx["sc"]
	var t := float(S["t"])
	at(ctx, t)
	var shapes := shapes_now(ctx)
	var feet := {}
	var pts: Array = []
	for id in named(ctx):
		var s: Dictionary = shapes[id]
		if String(s["k"]) != "capsule" or not (id.begins_with("foot") or id.begins_with("ball")):
			continue
		var a := _v3(s["a"])
		var b := _v3(s["b"])
		var r := float(s["r"])
		var low := minf(a.y, b.y) - r
		var down := low <= FOOT_DOWN_M
		feet[id] = {"down": down, "h_mm": _q(maxf(low, 0.0) * 1000.0, 0.01), "speed": _q(float(S["kin"][id]["speed"]), FLOOR_V)}
		if down:
			for e in [a, b]:
				for i in 8:
					var ang := TAU * i / 8.0
					pts.append(Vector2(e.x + r * cos(ang), e.z + r * sin(ang)))
	var hull := convex_hull(pts)
	var msum := 0.0
	var com := Vector3.ZERO
	for id in named(ctx):
		if id == "floor" or id == "bat_barrel":
			continue
		var mass := float(sc["mass"].get(id, 1.0))
		msum += mass
		com += (S["kin"][id]["c"] as Vector3) * mass
	com /= maxf(msum, 1e-9)
	var margin := 0.0
	var inside := false
	if hull.size() >= 3:
		margin = INF
		for i in hull.size():
			var p: Vector2 = hull[i]
			var q: Vector2 = hull[(i + 1) % hull.size()]
			var e2 := q - p
			var nrm := Vector2(-e2.y, e2.x).normalized()   # counter-clockwise hull: the inside is on the left
			margin = minf(margin, nrm.dot(Vector2(com.x, com.z) - p))
		inside = margin >= 0.0
	var bones: Array = []
	for id in named(ctx):
		if id == "floor" or id == "bat_barrel":
			continue
		var s2: Dictionary = shapes[id]
		var k: Dictionary = S["kin"][id]
		var row := {"id": id, "pos": _qv(k["c"], FLOOR_P), "vel": _qv(k["v"], FLOOR_V), "angvel": _qv(k["w"], FLOOR_W)}
		if String(s2["k"]) == "capsule":
			row["axis"] = _qv((_v3(s2["b"]) - _v3(s2["a"])).normalized(), 0.001)
		if sc.has("joint"):
			var j: Dictionary = (sc["joint"] as Callable).call(id, t)
			at(ctx, t)
			if not j.is_empty():
				row["joint"] = {"type": j["type"], "deg": _q(float(j["value"]), 0.01)}
				if j.has("lo"):
					row["joint"]["to_limit"] = _q(minf(float(j["value"]) - float(j["lo"]), float(j["hi"]) - float(j["value"])), 0.01)
		bones.append(row)
	var poly: Array = []
	for p2 in hull:
		poly.append([_q(p2.x, FLOOR_P), _q(p2.y, FLOOR_P)])
	return {"scene": sc["name"], "t": _q(t), "feet": feet, "com": _qv(com, FLOOR_P), "poly_xz": poly, "airborne": hull.size() < 3,
		"balanced": inside, "margin_mm": _q(margin * 1000.0, 0.01) if hull.size() >= 3 else null, "bones": bones}


## Andrew's monotone chain, counter-clockwise, points are Vector2
static func convex_hull(pts: Array) -> Array:
	var p: Array = pts.duplicate()
	if p.size() < 3:
		return p
	p.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	var lower: Array = []
	for q in p:
		while lower.size() >= 2 and _cross2(lower[lower.size() - 2], lower[lower.size() - 1], q) <= 0.0:
			lower.pop_back()
		lower.append(q)
	var upper: Array = []
	for i in range(p.size() - 1, -1, -1):
		var q2: Vector2 = p[i]
		while upper.size() >= 2 and _cross2(upper[upper.size() - 2], upper[upper.size() - 1], q2) <= 0.0:
			upper.pop_back()
		upper.append(q2)
	lower.pop_back()
	upper.pop_back()
	return lower + upper


static func _cross2(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


# ---------------------------------------------------------------- the one entry point (GDScript and MCP both call this)
## p: {level 0|1|2|3, part, t, since, t1, step, ids, render, character}. Returns {ok, result, text, tokens} or {ok: false, error}.
## view_sync = visible share by rays (no renderer needed, what the headless MCP session uses); view = by the id render pass (needs a renderer), awaited.
static func view_sync(ctx: Dictionary, p: Dictionary) -> Dictionary:
	var t := float(p.get("t", ctx["sc"].get("t0", 0.0)))
	var Sb: Dictionary = {}
	var Sa: Dictionary = {}
	if int(p.get("level", 0)) != 3 or p.has("since"):
		Sb = snap_ray(ctx, t)
		if p.has("since"):
			Sa = snap_ray(ctx, float(p["since"]))
	return resolve(ctx, p, Sa, Sb)


static func view(ctx: Dictionary, p: Dictionary) -> Dictionary:
	if not bool(p.get("render", true)):
		return view_sync(ctx, p)
	var t := float(p.get("t", ctx["sc"].get("t0", 0.0)))
	var Sb: Dictionary = {}
	var Sa: Dictionary = {}
	if int(p.get("level", 0)) != 3 or p.has("since"):
		Sb = await snap(ctx, t, true)
		if p.has("since"):
			Sa = await snap(ctx, float(p["since"]), true)
	return resolve(ctx, p, Sa, Sb)


static func resolve(ctx: Dictionary, p: Dictionary, Sa: Dictionary, Sb: Dictionary) -> Dictionary:
	var sc: Dictionary = ctx["sc"]
	var t := float(p.get("t", sc.get("t0", 0.0)))
	var level := int(p.get("level", 0))
	var r: Dictionary
	if p.has("since"):
		r = delta_view(ctx, Sa, Sb)
	elif bool(p.get("character", false)):
		r = character(ctx, Sb)
	elif level == 0:
		r = level0(ctx, Sb)
	elif level == 1:
		r = level1(ctx, Sb)
	elif level == 2:
		var id := String(p.get("part", ""))
		if id == "":
			return {"ok": false, "error": "level 2 needs part"}
		r = level2(ctx, Sb, id)
		if r.has("error"):
			return {"ok": false, "error": r["error"]}
	elif level == 3:
		var ids_a: Array = p.get("ids", [])
		if ids_a.is_empty() and p.has("part"):
			ids_a = [String(p["part"])]
		if ids_a.is_empty():
			return {"ok": false, "error": "level 3 needs ids (or part)"}
		var t1 := float(p.get("t1", t + 1.0))
		r = track(ctx, ids_a, t, t1, float(p.get("step", maxf((t1 - t) / 20.0, 0.01))))
	else:
		return {"ok": false, "error": "level is 0, 1, 2 or 3"}
	var s := txt(r)
	return {"ok": true, "result": r, "text": s, "tokens": int(ceil(s.length() / 4.0))}
