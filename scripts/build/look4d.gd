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
const LABEL_MIN_PX := 250         # a part with a smaller silhouette gets no label (the id list is in the header of every format)
const MAX_LABELS := 24
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
	for i in ids_a.size():
		var id: String = ids_a[i]
		var node := (ctx["sc"]["nodes"][id] as MeshInstance3D)
		var row := {"solo_px": 0, "vis_px": int(vis.get(cd[i], 0)), "frac": 0.0, "by": "", "bbox": [0, 0, 0, 0]}
		if node.is_visible_in_tree():
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


## the digest at time t: {scene, t, units, camera, objects: [...]}; kin and meas from kinematics() / measure(), contacts from the scene
static func digest(ctx: Dictionary, t: float, kin: Dictionary, meas: Dictionary, contacts: Array) -> Dictionary:
	var sc: Dictionary = ctx["sc"]
	var cam: Camera3D = ctx["cam"]
	var objs: Array = []
	for id in sc["ids"]:
		var k: Dictionary = kin[id]
		var m: Dictionary = meas[id]
		var mass := float(sc["mass"].get(id, 1.0))
		var pr := project_pt(ctx, k["c"])
		var cons: Array = []
		var pen := {}
		for c in contacts:
			if c["a"] == id or c["b"] == id:
				var other: String = c["b"] if c["a"] == id else c["a"]
				if float(c.get("gap_mm", 0.0)) <= 0.1 or float(c.get("pen_mm3", 0.0)) > 1.0:
					cons.append(other)
				if float(c.get("pen_mm3", 0.0)) > 1.0:
					pen[other] = c["pen_mm3"]
		objs.append({
			"id": id, "pos": k["c"], "vel": k["v"], "speed": k["speed"], "angvel": k["w"], "mass_kg": mass,
			"momentum": (k["v"] as Vector3) * mass, "depth_m": pr["z"], "visible_frac": m["frac"],
			"occluded": occluded(m), "occluded_by": m["by"] if occluded(m) else "", "contacts": cons, "penetration_mm3": pen})
	return _r({
		"scene": sc["name"], "t_s": t,
		"units": "world metres, y up; vel m/s; angvel rad/s (world axes); momentum kg m/s; depth_m = distance along the camera axis; mass_kg is NOMINAL",
		"camera": {"pos": cam.global_position, "look_dir": -cam.global_transform.basis.z, "up": cam.global_transform.basis.y, "fov_deg_vertical": cam.fov, "image_px": [W, H]},
		"objects": objs})


# ---------------------------------------------------------------- C
## the drawing list of C: [{k: "dot", p}, {k: "arrow", a, b, h1, h2}, {k: "dash", r}, {k: "text", p, s, c}] in picture pixels. Pure data, so the test can read it
static func plan(ctx: Dictionary, kin: Dictionary, meas: Dictionary, past: Array) -> Array:
	var items: Array = []
	var cam: Camera3D = ctx["cam"]
	var cz := cam.global_transform
	var order: Array = []
	for id in ctx["sc"]["ids"]:
		if int(meas[id]["solo_px"]) > 0:
			order.append(id)
	order.sort_custom(func(a, b): return int(meas[a]["solo_px"]) > int(meas[b]["solo_px"]))
	var labelled: Array = []
	for id in order:
		if int(meas[id]["solo_px"]) >= LABEL_MIN_PX and labelled.size() < MAX_LABELS:
			labelled.append(id)
	var placed: Array = []
	for id in labelled:
		var k: Dictionary = kin[id]
		var m: Dictionary = meas[id]
		var pc := project_pt(ctx, k["c"])
		var c: Vector2 = pc["px"]
		var bb: Array = m["bbox"]
		var hid := occluded(m)
		if hid:
			items.append({"k": "dash", "c": CYAN, "r": Rect2(Vector2(bb[0], bb[1]), Vector2(bb[2] - bb[0], bb[3] - bb[1]))})
		for g in past:   # ghosts: positions at t - k h
			var gp := project_pt(ctx, g[id])
			if is_finite((gp["px"] as Vector2).x):
				items.append({"k": "dot", "p": gp["px"]})
		var v: Vector3 = k["v"]
		var label := "%s d=%.1fm" % [id, float(pc["z"])]
		if hid:
			label = "%s (hidden) d=%.1fm" % [id, float(pc["z"])]
		if v.length() >= 0.02 and is_finite(c.x):
			var tip := project_pt(ctx, (k["c"] as Vector3) + v * ARROW_T)
			var b: Vector2 = tip["px"]
			if is_finite(b.x):
				var dir := (b - c)
				var L := dir.length()
				var u := dir / maxf(L, 1e-6)
				var n := Vector2(-u.y, u.x)
				var hl := minf(10.0, L * 0.4)
				items.append({"k": "arrow", "c": YELLOW, "a": c, "b": b, "h1": b - u * hl + n * hl * 0.5, "h2": b - u * hl - n * hl * 0.5})
				var vz := (cz.affine_inverse().basis * v).z   # camera looks down -z: vz < 0 = away from the camera
				var dirword := ""
				if absf(vz) > 0.1 * v.length():
					dirword = " away" if vz < 0.0 else " toward"
				items.append({"k": "text", "p": b + Vector2(6, -4), "s": "%.1f m/s%s" % [v.length(), dirword], "c": Color(1.0, 0.95, 0.55)})
		# the id label, nudged so labels do not sit on each other
		var pos := c + Vector2(-20, 0)
		var tries := [Vector2(0, 0), Vector2(0, 15), Vector2(0, -15), Vector2(0, 30), Vector2(0, -30), Vector2(40, 0), Vector2(-40, 15)]
		for off in tries:
			var r := Rect2(pos + off + Vector2(0, -12), Vector2(7.0 * label.length(), 15))
			var clash := false
			for q in placed:
				if (q as Rect2).intersects(r):
					clash = true
					break
			if not clash:
				pos += off
				placed.append(r)
				break
		items.append({"k": "text", "p": pos, "s": label, "c": Color(1, 1, 1)})
	return items


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
	var txt := JSON.stringify(dg, "\t")
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
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(base)
	tr.size = Vector2(W, H)
	vp.add_child(tr)
	var ctl := Overlay.new()
	ctl.size = Vector2(W, H)
	ctl.items = plan(ctx, kin, meas, past)
	ctl.font = ThemeDB.fallback_font
	vp.add_child(ctl)
	await frames(3)
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	vp.queue_free()
	return img


## the drawing of a plan()
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
				"dash":
					var r: Rect2 = it["r"]
					var ps := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
					for i in 4:
						draw_dashed_line(ps[i], ps[i + 1], it["c"], 2.0, 6.0)
				"text":
					draw_string_outline(font, it["p"], it["s"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0))
					draw_string(font, it["p"], it["s"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, it["c"])


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
		for id in st:
			var pr := project_pt(ctx, st[id]["c"])
			row[id] = {"c": _r2(st[id]["c"]), "px": [_fin(pr["px"].x), _fin(pr["px"].y)], "z": pr["z"], "shape": shapes[id], "vis": st[id]["vis"]}
		samples.append({"t": t, "k": k, "objs": row})
		k += 1
	at(ctx, t0)
	var kinout := {}
	for id in kin:
		kinout[id] = {"c": _r2(kin[id]["c"]), "v": _r2(kin[id]["v"]), "w": _r2(kin[id]["w"]), "speed": kin[id]["speed"]}
	return {"scene": sc["name"], "t0": t0, "ids": sc["ids"], "names": sc.get("names", {}), "dt": DT, "image": [W, H], "kin": kinout, "meas": meas, "contacts": contacts, "samples": samples, "mass": sc["mass"],
		"camera": {"pos": _r2(ctx["cam"].global_position), "look_dir": _r2(-ctx["cam"].global_transform.basis.z), "fov": ctx["cam"].fov}, "may_ask": sc.get("may_ask", []), "kind": sc.get("kind", "motion")}


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
