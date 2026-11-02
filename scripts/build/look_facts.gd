class_name LookFacts
extends RefCounted
## LOOK FACTS (item 242, AI EASE 2): numbers for what a picture LOOKS like, so an AI does not need a screenshot to catch "right in geometry, wrong in looks"
## (a lattice read as louvres because its bars were as dark as its back; pale lemon canopies; a fish-like beast; neon saturation).
## ONE render pair at a small size (default 480 x 270):
##   SHADED  TempleLight.final_shot(): the final light (sky, sun, haze, tone map), no UI, the given or the current camera
##   IDS     id_pass(): the same camera, flat UNLIT colour per piece (one of 4096 ids, 16 levels a channel), no AA, black = nothing: exact masks, no guessing by colour
##   SOLO    solo_pass(): per target, the target alone (transparent background): how much of it WOULD show, so visible vs hidden is a count, and who hides it
## Per target (a piece by name, a piece kind, a nature item or its canopy / trunk): px and share of the picture, bbox, mean hue / saturation / value and their spread,
## contrast against a ring of pixels just outside its mask, visible vs hidden (and by what), optional "vs" contrast against another target (a grid's bars vs its back),
## and plain-words verdict lines. The scene, the camera and the undo stack are not touched (the temple light is put back as it was).
##
## serve(m, p): p = {targets: [selector, ...] | piece | kind | nature, camera?: {pos, target, fov}, w?, h?, ring?}  (all optional: no target = every kind and nature item)
##   selector = {piece: "Column 3"} (name: exact, else contains; all matches are ONE target) | {kind: "column"} | {nature: "<item id or kind>", part?: "canopy"|"trunk"|"all"} |
##              {body: n}; each may carry {label: "..."} and {vs: <selector>} (contrast with that other target, not with the ring)

const ID_STEP := 17            # a channel is one of 16 levels, 0 .. 255 step 17: the decode rounds, so a +-8 error in the framebuffer still reads right
const MAX_SOLO := 24
const FLAT_BELOW := 0.15       # contrast under this reads as one flat panel
const BLEND_BELOW := 0.08      # ... and under this the piece is gone into its surroundings
const NEON_SAT := 0.85
const DEFAULT_W := 480
const DEFAULT_H := 270


## ---------------------------------------------------------------- the pieces of the scene
## unit = {name, kind, src: "part"|"nature", surf: int (part), node: Node (nature), item: id, sub: "canopy"|"trunk"|"body"|...}
static func units_of(m: Node) -> Array:
	var out := []
	var pu = m.bld.part
	if pu != null and pu.part_mesh != null and pu.part_mesh.mesh != null and pu.part_mesh.is_visible_in_tree():
		var res: Dictionary = pu.res
		var sb: Array = res.get("surf_body", [])
		var bl: Array = res.get("body_looks", [])
		var bk: Array = res.get("body_kinds", [])
		var ns: int = pu.part_mesh.mesh.get_surface_count()
		var merged: bool = ns < int(res.get("bodies", ns))
		for s in ns:
			var bi := int(sb[s]) if s < sb.size() else s
			var nm := ""
			if bi >= 0 and bi < bl.size():
				nm = String((bl[bi] as Dictionary).get("name", ""))
			if nm == "":
				nm = "Body%d" % (bi + 1)
			if merged:
				nm += " (+merged)"
			out.append({"name": nm, "kind": String(bk[bi]) if bi >= 0 and bi < bk.size() else "", "src": "part", "surf": s, "body": bi})
	var nv = m.bld.nature
	if nv != null and nv.is_visible_in_tree():
		var items: Array = m.S.building.get("nature", []) if not m.S.building.is_empty() else []
		for it in items:
			var id := String(it["id"])
			if not nv.nodes.has(id):
				continue
			var root: Node = nv.nodes[id]["node"]
			for ch in root.get_children():
				if not (ch is MeshInstance3D or ch is MultiMeshInstance3D):
					continue
				var sub := _sub_of(String(it["kind"]), String(ch.name))
				out.append({"name": "%s %s %s" % [String(it["kind"]).capitalize(), id, sub], "kind": String(it["kind"]) + " " + sub, "src": "nature", "node": ch, "item": id,
					"nkind": String(it["kind"]), "sub": sub})
	return out


static func _sub_of(nkind: String, child: String) -> String:
	match child:
		"leaves":
			return "canopy"
		"wood":
			return "trunk"
	return child


## selector -> {label, idx: [unit index], vs: selector or null}
static func resolve(units: Array, sel: Dictionary) -> Dictionary:
	var idx := []
	var label := String(sel.get("label", ""))
	if sel.has("piece"):
		var want := String(sel["piece"]).to_lower()
		for i in units.size():
			if units[i]["src"] == "part" and String(units[i]["name"]).to_lower().replace(" (+merged)", "") == want:
				idx.append(i)
		if idx.is_empty():
			for i in units.size():
				if units[i]["src"] == "part" and String(units[i]["name"]).to_lower().contains(want):
					idx.append(i)
		if label == "":
			label = String(sel["piece"])
	elif sel.has("kind"):
		var want2 := String(sel["kind"]).to_lower()
		for i in units.size():
			if String(units[i]["kind"]).to_lower() == want2 or (units[i]["src"] == "nature" and String(units[i]["sub"]) == want2):
				idx.append(i)
		if label == "":
			label = want2
	elif sel.has("nature"):
		var want3 := String(sel["nature"]).to_lower()
		var part := String(sel.get("part", "all")).to_lower()
		for i in units.size():
			var u: Dictionary = units[i]
			if u["src"] != "nature":
				continue
			if String(u["item"]).to_lower() == want3 or String(u["nkind"]).to_lower() == want3:
				if part == "all" or String(u["sub"]) == part:
					idx.append(i)
		if label == "":
			label = "%s%s" % [String(sel["nature"]), "" if part == "all" else " " + part]
	elif sel.has("body"):
		for i in units.size():
			if units[i]["src"] == "part" and int(units[i]["body"]) == int(sel["body"]):
				idx.append(i)
		if label == "":
			label = "body %d" % int(sel["body"])
	return {"label": label, "idx": idx, "vs": sel.get("vs", null), "sel": sel}


## the targets asked for in p; none asked = every part kind (named pieces of no kind one each, up to the cap) and every nature item
static func targets_of(units: Array, p: Dictionary) -> Array:
	var sels := []
	if p.get("targets") is Array:
		for s in p["targets"]:
			if s is Dictionary:
				sels.append(s)
			elif s is String:
				sels.append({"piece": s})
	for k in ["piece", "kind", "nature", "body"]:
		if p.has(k):
			var s2 := {k: p[k]}
			if p.has("part"):
				s2["part"] = p["part"]
			if p.has("vs"):
				s2["vs"] = p["vs"]
			sels.append(s2)
	var out := []
	if not sels.is_empty():
		for s3 in sels:
			out.append(resolve(units, s3))
		return out
	var kinds := {}
	for i in units.size():
		var u: Dictionary = units[i]
		var key := String(u["kind"]) if String(u["kind"]) != "" else String(u["name"])
		if u["src"] == "nature":
			key = String(u["name"])
		if not kinds.has(key):
			kinds[key] = []
		kinds[key].append(i)
	for key in kinds:
		out.append({"label": key, "idx": kinds[key], "vs": null, "sel": {}})
	return out


## ---------------------------------------------------------------- the ID / mask pass (own small function: a silhouette tool may reuse it)
## id -> Color (sRGB, 16 levels a channel). 0 is nothing (black).
static func id_color(id: int) -> Color:
	return Color8(((id >> 8) & 15) * ID_STEP, ((id >> 4) & 15) * ID_STEP, (id & 15) * ID_STEP)


static func _flat(c: Color) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.albedo_color = c
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	mt.disable_fog = true
	return mt


static func _clear() -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.albedo_color = Color(0, 0, 0, 0)
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mt


## a leaf-card shader made flat: the same alpha-tested leaf shape, unshaded, one colour
static func _leaf_flat(src: ShaderMaterial, c: Color) -> Material:
	var code := src.shader.code
	if code.contains("ALBEDO = vcol * shade * rib;") and code.contains("render_mode cull_disabled, skip_vertex_transform;"):
		code = code.replace("render_mode cull_disabled, skip_vertex_transform;", "render_mode cull_disabled, skip_vertex_transform, unshaded;\nuniform vec3 idcol : source_color = vec3(1.0);")
		code = code.replace("ALBEDO = vcol * shade * rib;", "ALBEDO = idcol;")
		var sh := Shader.new()
		sh.code = code
		var sm := ShaderMaterial.new()
		sm.shader = sh
		for pr in src.shader.get_shader_uniform_list():
			var nm := String(pr["name"])
			var v: Variant = src.get_shader_parameter(nm)
			if v != null:
				sm.set_shader_parameter(nm, v)
		sm.set_shader_parameter("idcol", c)
		return sm
	return _flat(c)


## a SubViewport of its own world with the units drawn flat. colors: unit index -> Color (units not in it are not drawn; a part surface not in it is clear).
## transparent: nothing = alpha 0 (the solo pass), else black. The caller adds it under a node, awaits frames, reads the image and frees it.
static func id_pass(m: Node, units: Array, colors: Dictionary, xf: Transform3D, fov: float, near: float, far: float, size: Vector2i, transparent: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
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
	var cam := Camera3D.new()
	cam.transform = xf
	cam.fov = fov
	cam.near = near
	cam.far = far
	vp.add_child(cam)
	var pmi = m.bld.part.part_mesh
	var surf_unit := {}
	for i in units.size():
		var u: Dictionary = units[i]
		if u["src"] == "part":
			surf_unit[int(u["surf"])] = i
		elif colors.has(i):
			var src: Node = u["node"]
			var nd: Node3D
			var c: Color = colors[i]
			if src is MeshInstance3D:
				var mi := MeshInstance3D.new()
				mi.mesh = (src as MeshInstance3D).mesh
				mi.material_override = _flat(c)
				nd = mi
			else:
				var mm := MultiMeshInstance3D.new()
				mm.multimesh = (src as MultiMeshInstance3D).multimesh
				var mo: Material = (src as GeometryInstance3D).material_override
				mm.material_override = _leaf_flat(mo, c) if mo is ShaderMaterial else _flat(c)
				nd = mm
			vp.add_child(nd)
			nd.global_transform = (src as Node3D).global_transform
	if not surf_unit.is_empty() and pmi != null:
		var pm := MeshInstance3D.new()
		pm.mesh = pmi.mesh
		var clear := _clear()
		var any := false
		for s in pmi.mesh.get_surface_count():
			if surf_unit.has(s) and colors.has(surf_unit[s]):
				pm.set_surface_override_material(s, _flat(colors[surf_unit[s]]))
				any = true
			else:
				pm.set_surface_override_material(s, clear)
		if any:
			vp.add_child(pm)
			pm.global_transform = pmi.global_transform
		else:
			pm.free()
	m.add_child(vp)
	cam.current = true
	return vp


## the id of every pixel (0 = nothing, -1 = a pixel whose colour is no id: an edge or a blend). img: RGB8
static func decode_ids(img: Image) -> PackedInt32Array:
	var d := img.get_data()
	var n := img.get_width() * img.get_height()
	var out := PackedInt32Array()
	out.resize(n)
	var q := float(ID_STEP)
	for p in n:
		var r := int(d[p * 3])
		var g := int(d[p * 3 + 1])
		var b := int(d[p * 3 + 2])
		if r + g + b < 24:
			continue
		var lr := int(roundf(r / q))
		var lg := int(roundf(g / q))
		var lb := int(roundf(b / q))
		if absi(r - lr * ID_STEP) > 7 or absi(g - lg * ID_STEP) > 7 or absi(b - lb * ID_STEP) > 7:
			out[p] = -1
		else:
			out[p] = (lr << 8) | (lg << 4) | lb
	return out


## ---------------------------------------------------------------- the numbers
static func hue_name(h_deg: float, s: float, v: float) -> String:
	if s < 0.12:
		return "white" if v > 0.8 else ("black" if v < 0.15 else "grey")
	var h := fposmod(h_deg, 360.0)
	if h < 15.0 or h >= 345.0:
		return "red"
	if h < 40.0:
		return "orange"
	if h < 70.0:
		return "yellow"
	if h < 90.0:
		return "lime"
	if h < 160.0:
		return "green"
	if h < 195.0:
		return "teal"
	if h < 255.0:
		return "blue"
	if h < 290.0:
		return "purple"
	return "pink"


static func _lum(r: float, g: float, b: float) -> float:
	return 0.2126 * r + 0.7152 * g + 0.0722 * b


## Michelson contrast of two luminances
static func michelson(a: float, b: float) -> float:
	return absf(a - b) / (a + b + 0.02)


## {n, rgb, lum, hue_deg, sat, val, spread:{hue_deg, sat, val, lum}} of the pixels listed
static func colour_of(rgb: PackedByteArray, pix: PackedInt32Array) -> Dictionary:
	var n := pix.size()
	if n == 0:
		return {"n": 0}
	var sr := 0.0
	var sg := 0.0
	var sb := 0.0
	var sl := 0.0
	var sl2 := 0.0
	var ss := 0.0
	var ss2 := 0.0
	var sv := 0.0
	var sv2 := 0.0
	var hs := 0.0
	var hc := 0.0
	var hn := 0
	for p in pix:
		var r := rgb[p * 3] / 255.0
		var g := rgb[p * 3 + 1] / 255.0
		var b := rgb[p * 3 + 2] / 255.0
		var mx := maxf(r, maxf(g, b))
		var mn := minf(r, minf(g, b))
		var d := mx - mn
		var s := 0.0 if mx <= 0.0 else d / mx
		var l := _lum(r, g, b)
		sr += r
		sg += g
		sb += b
		sl += l
		sl2 += l * l
		ss += s
		ss2 += s * s
		sv += mx
		sv2 += mx * mx
		if s > 0.10 and mx > 0.08:
			var h := 0.0
			if mx == r:
				h = fposmod((g - b) / d, 6.0)
			elif mx == g:
				h = (b - r) / d + 2.0
			else:
				h = (r - g) / d + 4.0
			h *= PI / 3.0
			hs += sin(h)
			hc += cos(h)
			hn += 1
	var fn := float(n)
	var hue := 0.0
	var hsd := 0.0
	if hn > 0:
		hue = fposmod(rad_to_deg(atan2(hs, hc)), 360.0)
		var rr := clampf(sqrt(hs * hs + hc * hc) / float(hn), 0.0001, 1.0)
		hsd = rad_to_deg(sqrt(-2.0 * log(rr)))
	return {"n": n, "rgb": Vector3(sr / fn, sg / fn, sb / fn), "lum": sl / fn, "hue_deg": hue, "sat": ss / fn, "val": sv / fn,
		"spread": {"hue_deg": hsd, "sat": sqrt(maxf(ss2 / fn - (ss / fn) ** 2, 0.0)), "val": sqrt(maxf(sv2 / fn - (sv / fn) ** 2, 0.0)), "lum": sqrt(maxf(sl2 / fn - (sl / fn) ** 2, 0.0))}}


## the pixels within r px (Chebyshev) of the mask but not in it. mask: byte per pixel of a w x h picture, rect: where to look (the mask's bbox)
static func ring_of(mask: PackedByteArray, w: int, h: int, rect: Rect2i, r: int) -> PackedInt32Array:
	var x0 := maxi(rect.position.x - r, 0)
	var y0 := maxi(rect.position.y - r, 0)
	var x1 := mini(rect.end.x + r, w)
	var y1 := mini(rect.end.y + r, h)
	var rw := x1 - x0
	var rh := y1 - y0
	var tmp := PackedByteArray()
	tmp.resize(rw * rh)
	# horizontal: any mask pixel within r of x (running count)
	for y in rh:
		var cnt := 0
		var row := (y + y0) * w + x0
		for x in range(-r, rw + r):
			if x + r < rw and x + r >= 0:
				cnt += mask[row + x + r]
			if x - r - 1 >= 0 and x - r - 1 < rw:
				cnt -= mask[row + x - r - 1]
			if x >= 0 and x < rw and cnt > 0:
				tmp[y * rw + x] = 1
	var out := PackedInt32Array()
	for x in rw:
		var cnt2 := 0
		for y in range(-r, rh + r):
			if y + r < rh and y + r >= 0:
				cnt2 += tmp[(y + r) * rw + x]
			if y - r - 1 >= 0 and y - r - 1 < rh:
				cnt2 -= tmp[(y - r - 1) * rw + x]
			if y >= 0 and y < rh and cnt2 > 0:
				var gp := (y + y0) * w + x + x0
				if mask[gp] == 0:
					out.append(gp)
	return out


## ---------------------------------------------------------------- the call
static func serve(m: Node, p: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var W := clampi(int(p.get("w", DEFAULT_W)), 64, 1920)
	var H := clampi(int(p.get("h", int(roundf(W * float(DEFAULT_H) / DEFAULT_W)))), 36, 1080)
	var size := Vector2i(W, H)
	var units := units_of(m)
	if units.is_empty():
		return {"ok": false, "error": "look_facts: nothing is drawn (no part view or nature items are showing)"}
	var targets := targets_of(units, p)
	if targets.is_empty():
		return {"ok": false, "error": "look_facts: no target; give {piece}, {kind}, {nature} or {targets: [...]}"}
	for t in targets:
		if (t["idx"] as Array).is_empty():
			return {"ok": false, "error": "look_facts: nothing matches %s (pieces: %s)" % [JSON.stringify(t["sel"]), _some_names(units)]}
	# the camera: the given one, else the live one
	var c: Camera3D = m.cam
	var pos: Vector3 = c.global_position
	var tgt: Vector3 = pos - c.global_transform.basis.z * 10.0
	var fov := c.fov
	if p.get("camera") is Dictionary:
		var cp: Dictionary = p["camera"]
		var a := TempleLight._v3(cp.get("pos"))
		var b := TempleLight._v3(cp.get("target"))
		if not a.is_finite() or not b.is_finite():
			return {"ok": false, "error": "camera needs {\"pos\": [x, y, z], \"target\": [x, y, z], \"fov\": 45}"}
		pos = a
		tgt = b
		fov = float(cp.get("fov", 45.0))
	var xf := Transform3D(Basis.looking_at((tgt - pos).normalized(), Vector3.UP), pos) if p.get("camera") is Dictionary else c.global_transform
	var far := maxf(c.far, 2500.0)
	# the passes: IDS and one SOLO per target (a target the user asked for; the default list is capped), all drawn in the frames final_shot waits for
	var all_cols := {}
	for i in units.size():
		all_cols[i] = id_color(i + 1)
	var vids := id_pass(m, units, all_cols, xf, fov, c.near, far, size, false)
	var solos := []
	for ti in mini(targets.size(), MAX_SOLO):
		var cols := {}
		for ui in targets[ti]["idx"]:
			cols[ui] = id_color(1)
		solos.append(id_pass(m, units, cols, xf, fov, c.near, far, size, true))
	var realistic_was: bool = Realistic.live_on
	var shot: Dictionary = await TempleLight.final_shot(m, OS.get_temp_dir().path_join("kine_look_facts.png"), size, {"pos": xf.origin, "target": xf.origin - xf.basis.z * 10.0, "fov": fov})
	if realistic_was and not Realistic.live_on:
		Realistic.set_live(m, true)   # final_shot switches it off for the temple light: put back
	await RenderingServer.frame_post_draw
	var id_img := vids.get_texture().get_image()
	var solo_imgs := []
	for sv in solos:
		solo_imgs.append((sv as SubViewport).get_texture().get_image())
	for v in [vids] + solos:
		m.remove_child(v)
		v.queue_free()
	if not bool(shot.get("ok", false)) or id_img == null or id_img.is_empty():
		return {"ok": false, "error": "look_facts: the picture could not be drawn: " + String(shot.get("text", ""))}
	var img: Image = shot["image"]
	img.convert(Image.FORMAT_RGB8)
	id_img.convert(Image.FORMAT_RGB8)
	var ids := decode_ids(id_img)
	if p.has("debug_dir"):   # the masks, to LOOK at: the shaded picture, the id picture, and the shaded picture with each id tinted over it
		var dd := String(p["debug_dir"])
		DirAccess.make_dir_recursive_absolute(dd)
		img.save_png(dd.path_join("shaded.png"))
		id_img.save_png(dd.path_join("ids.png"))
		var ov := img.duplicate() as Image
		for q in ids.size():
			if ids[q] > 0:
				var cc := ov.get_pixel(q % W, q / W)
				ov.set_pixel(q % W, q / W, cc.lerp(Color.from_hsv(fposmod(ids[q] * 0.381, 1.0), 1.0, 1.0), 0.6))
		ov.save_png(dd.path_join("overlay.png"))
	var rgb := img.get_data()
	var ring_r := int(p.get("ring", maxi(3, W / 100)))
	var out_t := []
	var verdicts := []
	var by_target := {}   # label -> {pix, rect}
	for ti in targets.size():
		var t: Dictionary = targets[ti]
		by_target[ti] = _pixels_of(ids, W, H, t["idx"])
	for ti in targets.size():
		var t2: Dictionary = targets[ti]
		var bt: Dictionary = by_target[ti]
		var pix: PackedInt32Array = bt["pix"]
		var f := {"label": t2["label"], "pieces": (t2["idx"] as Array).size(), "px": pix.size(), "share": snappedf(float(pix.size()) / float(W * H), 0.0001)}
		var names := []
		for ui in (t2["idx"] as Array).slice(0, 4):
			names.append(units[ui]["name"])
		f["names"] = names
		var rect: Rect2i = bt["rect"]
		if pix.size() > 0:
			f["bbox_px"] = [rect.position.x, rect.position.y, rect.end.x, rect.end.y]
			f["bbox"] = [snappedf(rect.position.x / float(W), 0.001), snappedf(rect.position.y / float(H), 0.001), snappedf(rect.end.x / float(W), 0.001), snappedf(rect.end.y / float(H), 0.001)]
			f["cut_by_edge"] = rect.position.x <= 0 or rect.position.y <= 0 or rect.end.x >= W or rect.end.y >= H
			var col := colour_of(rgb, pix)
			f["hue_deg"] = snappedf(col["hue_deg"], 0.1)
			f["hue_name"] = hue_name(col["hue_deg"], col["sat"], col["val"])
			f["sat"] = snappedf(col["sat"], 0.001)
			f["val"] = snappedf(col["val"], 0.001)
			f["lum"] = snappedf(col["lum"], 0.001)
			f["rgb"] = [snappedf(col["rgb"].x, 0.001), snappedf(col["rgb"].y, 0.001), snappedf(col["rgb"].z, 0.001)]
			f["spread"] = {"hue_deg": snappedf(col["spread"]["hue_deg"], 0.1), "sat": snappedf(col["spread"]["sat"], 0.001), "val": snappedf(col["spread"]["val"], 0.001)}
			# the ring just outside the mask
			var mask := PackedByteArray()
			mask.resize(W * H)
			for q in pix:
				mask[q] = 1
			var rp := ring_of(mask, W, H, rect, ring_r)
			if rp.size() > 8:
				var rc := colour_of(rgb, rp)
				f["around"] = {"lum": snappedf(rc["lum"], 0.001), "hue_name": hue_name(rc["hue_deg"], rc["sat"], rc["val"]), "px": rp.size()}
				f["contrast"] = snappedf(michelson(col["lum"], rc["lum"]), 0.001)
				f["color_diff"] = snappedf((col["rgb"] - rc["rgb"]).length() / sqrt(3.0), 0.001)
		# visible vs hidden: the solo mask counted against the id picture
		if ti < solos.size():
			var si: Image = solo_imgs[ti]
			var solo_n := 0
			var vis_n := 0
			var by := {}
			if si != null and not si.is_empty():
				si.convert(Image.FORMAT_RGBA8)
				var sr := si.get_used_rect()
				var sd := si.get_data()
				var tset := {}
				for ui in t2["idx"]:
					tset[ui + 1] = true
				for y in range(sr.position.y, sr.end.y):
					for x in range(sr.position.x, sr.end.x):
						var pp := y * W + x
						if sd[pp * 4 + 3] > 127:
							solo_n += 1
							var id := ids[pp]
							if tset.has(id):
								vis_n += 1
							elif id > 0:
								by[id] = int(by.get(id, 0)) + 1
			f["solo_px"] = solo_n
			f["visible"] = snappedf(float(vis_n) / float(solo_n), 0.001) if solo_n > 0 else 0.0
			f["hidden_px"] = solo_n - vis_n
			var hb := []
			var keys := by.keys()
			keys.sort_custom(func(a, b): return by[a] > by[b])
			for k in keys.slice(0, 3):
				hb.append({"by": units[int(k) - 1]["name"], "px": by[k]})
			f["hidden_by"] = hb
		# vs another target
		if t2["vs"] is Dictionary:
			var vt := resolve(units, t2["vs"])
			if not (vt["idx"] as Array).is_empty() and pix.size() > 0:
				var vp2 := _pixels_of(ids, W, H, vt["idx"])
				if (vp2["pix"] as PackedInt32Array).size() > 0:
					var vc := colour_of(rgb, vp2["pix"])
					var cc := colour_of(rgb, pix)
					f["vs"] = {"label": vt["label"], "px": (vp2["pix"] as PackedInt32Array).size(), "contrast": snappedf(michelson(cc["lum"], vc["lum"]), 0.001),
						"color_diff": snappedf((cc["rgb"] - vc["rgb"]).length() / sqrt(3.0), 0.001)}
		var vl := verdict_lines(f, W, H)
		f["verdict"] = vl
		verdicts.append_array(vl)
		out_t.append(f)
	return {"ok": true, "size": [W, H], "camera": {"pos": [xf.origin.x, xf.origin.y, xf.origin.z], "fov": fov}, "ms": Time.get_ticks_msec() - t0, "facts": out_t,
		"verdicts": verdicts, "ring_px": ring_r, "id_levels": 16, "shot_ms": shot.get("ms", 0)}


static func _some_names(units: Array) -> String:
	var n := []
	for u in units.slice(0, 12):
		n.append(String(u["name"]))
	return ", ".join(n) + (", ..." if units.size() > 12 else "")


## {pix: pixel indexes whose id is one of the units, rect: their bbox}
static func _pixels_of(ids: PackedInt32Array, w: int, h: int, idx: Array) -> Dictionary:
	var want := {}
	for ui in idx:
		want[int(ui) + 1] = true
	var pix := PackedInt32Array()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for p in ids.size():
		var id := ids[p]
		if id > 0 and want.has(id):
			pix.append(p)
			var x := p % w
			var y := p / w
			x0 = mini(x0, x)
			y0 = mini(y0, y)
			x1 = maxi(x1, x)
			y1 = maxi(y1, y)
	return {"pix": pix, "rect": Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1) if x1 >= 0 else Rect2i()}


## ---------------------------------------------------------------- plain words
static func verdict_lines(f: Dictionary, w: int, h: int) -> Array:
	var L: String = f["label"]
	var out := []
	if int(f["px"]) == 0:
		if f.has("solo_px") and int(f["solo_px"]) > 0:
			out.append("%s: not visible at all: all %d px it would cover are hidden%s" % [L, int(f["solo_px"]), _by_words(f)])
		elif f.has("solo_px"):
			out.append("%s: not in the picture from this camera" % L)
		else:
			out.append("%s: nothing of it shows from this camera" % L)
		return out
	var share: float = f["share"]
	var cov := "%s: covers %.1f%% of the picture (%d px at %d x %d)" % [L, share * 100.0, int(f["px"]), w, h]
	if share < 0.002:
		cov += "; tiny, it will not read as more than a speck"
	if bool(f.get("cut_by_edge", false)):
		cov += "; cut by the picture edge"
	out.append(cov)
	if f.has("visible") and float(f["visible"]) < 0.999:
		var vis: float = f["visible"]
		out.append("%s: %.0f%% visible%s%s" % [L, vis * 100.0, _by_words(f), "; mostly hidden" if vis < 0.3 else ""])
	var s: float = f["sat"]
	var v: float = f["val"]
	var col := "%s: reads %s (hue %.0f deg, saturation %.2f, brightness %.2f)" % [L, f["hue_name"], f["hue_deg"], s, v]
	if s >= NEON_SAT and v > 0.35:
		col += "; neon: saturation above %.2f reads as glowing, real paint and foliage stay under it" % NEON_SAT
	elif v >= 0.82 and s >= 0.15 and s < 0.55:
		col += "; pale and washed out: bright with weak colour (a pale %s)" % f["hue_name"]
	elif v < 0.12:
		col += "; near black: no detail will read"
	out.append(col)
	var sp: Dictionary = f["spread"]
	if float(sp["val"]) < 0.03 and float(sp["sat"]) < 0.03:
		out.append("%s: flat, almost no variation inside it (brightness spread %.3f): reads as a cut-out or one painted shape" % [L, sp["val"]])
	if f.has("vs"):
		var vs: Dictionary = f["vs"]
		var c: float = vs["contrast"]
		out.append("%s: contrast with its %s %.2f (%s)" % [L, vs["label"], c, _contrast_words(c, float(vs["color_diff"]), true)])
	elif f.has("contrast"):
		var c2: float = f["contrast"]
		out.append("%s: contrast with what is around it %.2f (%s)" % [L, c2, _contrast_words(c2, float(f["color_diff"]), false)])
	return out


static func _by_words(f: Dictionary) -> String:
	var hb: Array = f.get("hidden_by", [])
	if hb.is_empty():
		return ""
	var n := []
	for h in hb:
		n.append(String(h["by"]))
	return " (behind " + ", ".join(n) + ")"


static func _contrast_words(c: float, cd: float, vs: bool) -> String:
	if c < BLEND_BELOW:
		return ("reads as one flat panel below ~%.2f: the two cannot be told apart" if vs else "blends into its surroundings below ~%.2f") % FLAT_BELOW \
			+ ("; the colour differs (%.2f) but not the brightness" % cd if cd > 0.12 else "")
	if c < FLAT_BELOW:
		return "weak, a soft read; it needs about %.2f to stand out" % FLAT_BELOW
	if c < 0.35:
		return "clear"
	return "strong"
