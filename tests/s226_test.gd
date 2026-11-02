extends SceneTree
## godot --path . --position 4000,4000 -s tests/s226_test.gd     (ITEM 226 ROOF FEATURE: scripts/build/part_roof.gd; needs the CAD DLL)
## Bars (numbers measured on the KERNEL's solid: its tessellation is ray-cast, the bounding box and the volume are the kernel's, never the generator's own variables):
##   1 TYPES     hip / gable / xieshan / pyramid / shed / flat: each ONE valid solid with volume > 0 and a closed mesh
##   2 RIDGE     the ridge top is the asked height +-1 mm (vertical ray through the ridge), the eave line stays at 0
##   3 OVERHANG  the box is plan + 2 x overhang exactly (+-0.5 mm) on both sides
##   4 LIFT      the eave corner point rises by the asked lift +-1 pct; the mid-eave points do not rise (< 1 pct of the lift); the ridge is untouched
##   5 SAG       mid-slope the surface is below the straight slope by the asked sag +-2 pct
##   6 THICK     the shell is the asked thickness measured square to the slope (a ray along the normal) +-0.5 mm, flat and sloped
##   7 VOLUME    kernel volume vs the analytic value (flat, gable) and vs a fine sampling of the surface (xieshan, lifted, sagged hip) +-1 pct
##   8 SKIRT     a roof with an open top: a ray through the opening hits nothing; the ring is one valid solid
##   9 TRIMS     ridge + hip ridges + eave edge asked: each its own valid solid body
##  10 RECORD    the JSON of the record replays to the same volume (save and reload); the agent call adds ONE undo step and Undo takes it back
##  11 UI        the Expert Roof tool: its dialog makes a roof from typed numbers with real clicks, one undo step; Easy chip puts a roof on the floor
## Shots: C:/Users/Nick/tools/kine_workers/out/226/sheet.png (all types), hall.png (double eave), expert.png, easy.png
const KCad := preload("res://scripts/kcad.gd")
var fails := 0
const SHOT := "C:/Users/Nick/tools/kine_workers/out/226"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the kernel solid's triangles (mm)
func tris_of(id: int) -> PackedVector3Array:
	var am: ArrayMesh = KCad.tessellate(id, 0.5, 0.3)
	var out := PackedVector3Array()
	for s in am.get_surface_count():
		var arr := am.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix = arr[Mesh.ARRAY_INDEX]
		if ix == null or (ix as PackedInt32Array).is_empty():
			for v in vs:
				out.append(v * 1000.0)
		else:
			for i in ix:
				out.append(vs[i] * 1000.0)
	return out


## sorted distances along the ray (Moller-Trumbore)
func ray(tris: PackedVector3Array, o: Vector3, d: Vector3) -> Array:
	var hits: Array = []
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var e1 := tris[i + 1] - a
		var e2 := tris[i + 2] - a
		var pv := d.cross(e2)
		var det := e1.dot(pv)
		if absf(det) < 1e-12:
			continue
		var inv := 1.0 / det
		var tv := o - a
		var u := tv.dot(pv) * inv
		if u < -1e-9 or u > 1.0 + 1e-9:
			continue
		var qv := tv.cross(e1)
		var v := d.dot(qv) * inv
		if v < -1e-9 or u + v > 1.0 + 1e-9:
			continue
		var t := e2.dot(qv) * inv
		if t > 0.0:
			hits.append(t)
	hits.sort()
	return hits


func top_y(tris: PackedVector3Array, x: float, z: float) -> float:
	var h := ray(tris, Vector3(x, 100000.0, z), Vector3.DOWN)
	return 100000.0 - float(h[0]) if not h.is_empty() else NAN


func rec_of(fields: Dictionary) -> Dictionary:
	var rec := Part.make("Roof test")
	(rec["features"] as Array).append(Part.new_feature(rec, "roof", fields))
	return rec


func build(fields: Dictionary) -> Dictionary:
	var rec := rec_of(fields)
	var res := Part.replay(rec)
	var id := -1
	var tess: Array = res.get("tess_ids", [])
	return {"rec": rec, "res": res, "err": (res["errors"] as Dictionary)}


## the kernel ids of a replay (the first body)
func body_ids(rec: Dictionary) -> Array:
	var bodies: Array = []
	var feats: Array = rec["features"]
	for f in feats:
		var e := PartRoof.add(bodies, f)
		if e != "":
			print("add error: ", e)
	return bodies


func box_of(id: int) -> AABB:
	var t := tris_of(id)
	var lo := Vector3(1e12, 1e12, 1e12)
	var hi := -lo
	for v in t:
		lo = lo.min(v)
		hi = hi.max(v)
	return AABB(lo, hi - lo)


## a fine sampling of the shell: the integral of top - bottom over the eave rectangle (minus the opening)
func fine_volume(f: Dictionary) -> float:
	var P := PartRoof.norm(f)
	var G := PartRoof.geometry(P)
	var a: float = G["a"]
	var b: float = G["b"]
	var nx := 480
	var nz := 360
	var s := 0.0
	for i in nx:
		var x := -a + (float(i) + 0.5) * 2.0 * a / float(nx)
		for j in nz:
			var z := -b + (float(j) + 0.5) * 2.0 * b / float(nz)
			if float(G["hx"]) > 0.0 and absf(x) < float(G["hx"]) and absf(z) < float(G["hz"]):
				continue
			var tp := float((PartRoof.top(G, x, z, 0) as Array)[0])
			var bt := PartRoof.bottom(G, x, z, 0)
			s += tp - bt
	return s * (2.0 * a / float(nx)) * (2.0 * b / float(nz))


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	if not Part.available() or not KCad.has_mesh_solid():
		print("FAIL the part library has no mesh solid")
		print("s226: 1 fail")
		quit()
		return
	var W := 8000.0
	var D := 6000.0
	var O := 600.0
	var HH := 2500.0
	var T := 60.0
	# ---- 1 TYPES, 2 RIDGE, 3 OVERHANG
	var ridge_want := {"hip": HH, "gable": HH, "xieshan": HH, "pyramid": HH, "shed": HH, "flat": 0.0}
	var vols := {}
	for ty in PartRoof.TYPES:
		var f := {"type": ty, "w": W, "d": D, "overhang": O, "height": HH, "thick": T}
		var t0 := Time.get_ticks_msec()
		var rec := rec_of(f)
		var res := Part.replay(rec)
		var errs: Dictionary = res["errors"]
		var ms := PartRoof.meshes(f)
		var open := PartRoof.open_edges((ms[0]["t"] as PackedInt32Array))
		ok(errs.is_empty() and int(res["bodies"]) == 1 and float(res["volume"]) > 0.0 and open == 0, "1 TYPES %s: %d solid, %.0f cm3, %d open edges, %d tris, %d ms %s" % [ty, int(res["bodies"]), float(res["volume"]) * 1e6, open, (ms[0]["t"] as PackedInt32Array).size() / 3, Time.get_ticks_msec() - t0, str(errs)])
		vols[ty] = float(res["volume"]) * 1e9
		var bodies := body_ids(rec)
		if bodies.is_empty():
			ok(false, "2 RIDGE %s: no body" % ty)
			continue
		var tr := tris_of(int(bodies[0]))
		var bx := box_of(int(bodies[0]))
		var topv := bx.position.y + bx.size.y
		var hv: float = ridge_want[ty]
		var rz := top_y(tr, 0.0, 0.0) if ty != "shed" else top_y(tr, 0.0, D * 0.5 + O - 0.5)
		ok(absf(rz - hv) <= 1.0, "2 RIDGE %s: ridge top %.2f mm (asked %.1f), box top %.2f" % [ty, rz, hv, topv])
		var gx := W + 2.0 * O
		var gz := D + 2.0 * O
		ok(absf(bx.size.x - gx) <= 0.5 and absf(bx.size.z - gz) <= 0.5, "3 OVERHANG %s: box %.2f x %.2f mm (plan + 2 x %.0f = %.0f x %.0f)" % [ty, bx.size.x, bx.size.z, O, gx, gz])
		for id in bodies:
			KCad.release(int(id))
	# ---- 7 VOLUME (analytic: the shell is t square to the slope, so a plane roof is t x sqrt(1+k^2) x plan area)
	var A := (W + 2.0 * O) * (D + 2.0 * O)
	var k := HH / (D * 0.5 + O)
	ok(absf(vols["flat"] - A * T) <= 0.01 * A * T, "7 VOLUME flat: %.0f mm3 vs analytic %.0f" % [vols["flat"], A * T])
	var gv := A * T * sqrt(1.0 + k * k)
	ok(absf(vols["gable"] - gv) <= 0.01 * gv, "7 VOLUME gable: %.0f mm3 vs analytic %.0f" % [vols["gable"], gv])
	var hv2 := A * T * sqrt(1.0 + k * k)
	ok(absf(vols["hip"] - hv2) <= 0.01 * hv2, "7 VOLUME hip: %.0f mm3 vs analytic %.0f" % [vols["hip"], hv2])
	for fv in [
		{"type": "xieshan", "w": W, "d": D, "overhang": O, "height": HH, "thick": T, "sag": 300.0, "lift": 400.0, "lift_len": 1800.0},
		{"type": "hip", "w": W, "d": D, "overhang": O, "height": HH, "thick": T, "sag": 350.0, "lift": 500.0, "lift_len": 2000.0},
		{"type": "xieshan", "w": W, "d": D, "overhang": O, "height": HH, "thick": T}]:
		var rec := rec_of(fv)
		var res := Part.replay(rec)
		var want := fine_volume(fv)
		var have := float(res["volume"]) * 1e9
		var oe := PartRoof.open_edges(PartRoof.meshes(fv)[0]["t"])
		ok(absf(have - want) <= 0.01 * want and (res["errors"] as Dictionary).is_empty(), "7 VOLUME %s sag %.0f lift %.0f: kernel %.0f mm3 vs fine sampling %.0f (%.2f pct), %d open edges, errors %s" % [fv["type"], float(fv.get("sag", 0)), float(fv.get("lift", 0)), have, want, 100.0 * (have - want) / want, oe, str(res["errors"])])
	# ---- 4 LIFT
	var lf := {"type": "hip", "w": W, "d": D, "overhang": O, "height": HH, "thick": T, "lift": 400.0, "lift_len": 2000.0}
	var l0 := {"type": "hip", "w": W, "d": D, "overhang": O, "height": HH, "thick": T}
	var bl := body_ids(rec_of(lf))
	var b0 := body_ids(rec_of(l0))
	var tl := tris_of(int(bl[0]))
	var t0s := tris_of(int(b0[0]))
	var ax := W * 0.5 + O
	var bz := D * 0.5 + O
	var dx := 0.5
	var cor := top_y(tl, ax - dx, bz - dx) - top_y(t0s, ax - dx, bz - dx)
	ok(absf(cor - 400.0) <= 4.0, "4 LIFT corner: rises %.2f mm (asked 400, +-1 pct = 4)" % cor)
	var mid1 := top_y(tl, 0.0, bz - dx) - top_y(t0s, 0.0, bz - dx)
	var mid2 := top_y(tl, ax - dx, 0.0) - top_y(t0s, ax - dx, 0.0)
	ok(absf(mid1) < 4.0 and absf(mid2) < 4.0, "4 LIFT mid-eave long side %.3f mm, short side %.3f mm (< 4)" % [mid1, mid2])
	var rid := top_y(tl, 0.0, 0.0) - top_y(t0s, 0.0, 0.0)
	ok(absf(rid) < 1.0, "4 LIFT ridge unchanged: %.3f mm" % rid)
	# the ask: lift L = 400 at the eave corner, over a length of 2000. So along the hip line and along the eave edge the rise (lifted top minus the unlifted top at the same plan point) must be L at the corner, fall without rising again, be 0 where the length ends, and bend smoothly (no kink)
	var LL := 400.0
	var LEN := 2000.0
	var step := 200.0
	for line in ["hip line", "eave edge"]:
		var rise: Array = []
		for q in 11:
			var sd := dx + float(q) * step if q > 0 else dx
			if q == 10:
				sd = LEN + dx
			var px := ax - sd
			var pz := bz - sd if line == "hip line" else bz - dx
			rise.append(top_y(tl, px, pz) - top_y(t0s, px, pz))
		var mono := true
		for q in 10:
			mono = mono and float(rise[q + 1]) <= float(rise[q]) + 0.004 * LL
		var kink := 0.0
		for q in range(1, 10):
			kink = maxf(kink, absf(float(rise[q - 1]) - 2.0 * float(rise[q]) + float(rise[q + 1])))
		var dt := step / LEN
		ok(absf(float(rise[0]) - LL) <= 0.01 * LL, "4 LIFT %s: rise %.2f mm at the corner (asked %.0f +-1 pct)" % [line, float(rise[0]), LL])
		ok(absf(float(rise[10])) < 0.01 * LL, "4 LIFT %s: rise %.3f mm where the lift length ends (asked 0, < 1 pct of L)" % [line, float(rise[10])])
		ok(float(rise[5]) > 0.01 * LL and float(rise[5]) < 0.99 * LL, "4 LIFT %s: rise %.1f mm at half the length (strictly between 0 and %.0f)" % [line, float(rise[5]), LL])
		ok(mono, "4 LIFT %s: the rise never grows going away from the corner (%s)" % [line, str(rise.map(func(r): return snappedf(float(r), 0.1)))])
		ok(kink <= 12.5 * LL * dt * dt, "4 LIFT %s: largest second difference %.2f mm (a smooth bump of L over the length bends at most 12 L (step/len)^2 = %.1f)" % [line, kink, 12.5 * LL * dt * dt])
	for id in bl + b0:
		KCad.release(int(id))
	# ---- 5 SAG (a gable: the slope is a plane, so the straight height at mid-slope is H/2)
	var sg := {"type": "gable", "w": W, "d": D, "overhang": O, "height": HH, "thick": T, "sag": 400.0}
	var bs := body_ids(rec_of(sg))
	var ts := tris_of(int(bs[0]))
	var mid := top_y(ts, 0.0, bz * 0.5)
	var strait := HH * 0.5
	ok(absf((strait - mid) - 400.0) <= 8.0, "5 SAG mid-slope: surface %.2f, straight %.2f, sag %.2f mm (asked 400, +-2 pct = 8)" % [mid, strait, strait - mid])
	ok(absf(top_y(ts, 0.0, 0.0) - HH) <= 1.0 and absf(top_y(ts, 0.0, bz - 0.01)) <= 1.0, "5 SAG ridge %.2f and eave line %.2f stay put" % [top_y(ts, 0.0, 0.0), top_y(ts, 0.0, bz - 0.01)])
	# ---- 6 THICK
	var kk := HH / bz
	var nrm := Vector3(0, 1, kk).normalized()
	var z0 := bz * 0.5
	var p0 := Vector3(0, HH - kk * z0, z0)
	var hs := ray(tris_of(int(bs[0])), p0 + nrm * 5.0, -nrm)   # the sagged one: the normal differs, so use the plain gable below
	for id in bs:
		KCad.release(int(id))
	var bg := body_ids(rec_of({"type": "gable", "w": W, "d": D, "overhang": O, "height": HH, "thick": T}))
	var tg := tris_of(int(bg[0]))
	hs = ray(tg, p0 + nrm * 5.0, -nrm)
	ok(hs.size() >= 2 and absf((float(hs[1]) - float(hs[0])) - T) <= 0.5, "6 THICK sloped: %.3f mm along the normal (asked %.0f)" % [float(hs[1]) - float(hs[0]) if hs.size() >= 2 else -1.0, T])
	for id in bg:
		KCad.release(int(id))
	var bf := body_ids(rec_of({"type": "flat", "w": W, "d": D, "overhang": O, "thick": 45.0}))
	var hf := ray(tris_of(int(bf[0])), Vector3(137.0, 1000, 311.0), Vector3.DOWN)
	ok(hf.size() >= 2 and absf((float(hf[1]) - float(hf[0])) - 45.0) <= 0.5, "6 THICK flat: %.3f mm (asked 45)" % [float(hf[1]) - float(hf[0]) if hf.size() >= 2 else -1.0])
	for id in bf:
		KCad.release(int(id))
	# ---- 8 SKIRT
	var sk := {"type": "hip", "w": W, "d": D, "overhang": O, "height": 1500.0, "thick": T, "hole": [5000.0, 3000.0], "sag": 200.0, "lift": 350.0, "lift_len": 1800.0}
	var rs := rec_of(sk)
	var rr := Part.replay(rs)
	var skb := body_ids(rs)
	var tsk := tris_of(int(skb[0]))
	var through := ray(tsk, Vector3(0, 100000, 0), Vector3.DOWN)
	var onring := ray(tsk, Vector3(0, 100000, 2000), Vector3.DOWN)
	ok((rr["errors"] as Dictionary).is_empty() and int(rr["bodies"]) == 1 and through.is_empty() and onring.size() >= 2, "8 SKIRT: ring is %d solid, the opening is empty (%d hits), the ring is there (%d hits), %.0f cm3" % [int(rr["bodies"]), through.size(), onring.size(), float(rr["volume"]) * 1e6])
	var hole_open := PartRoof.open_edges(PartRoof.meshes(sk)[0]["t"])
	ok(hole_open == 0, "8 SKIRT mesh closed: %d open edges" % hole_open)
	for id in skb:
		KCad.release(int(id))
	# ---- 9 TRIMS
	var tf := {"type": "hip", "w": W, "d": D, "overhang": O, "height": HH, "thick": T, "sag": 300.0, "lift": 400.0, "ridge": true, "hips": true, "eave": true}
	var rt := rec_of(tf)
	var rtr := Part.replay(rt)
	ok((rtr["errors"] as Dictionary).is_empty() and int(rtr["bodies"]) == 1 + 1 + 4 + 1, "9 TRIMS: %d bodies (shell + ridge + 4 hips + eave edge = 7) %s" % [int(rtr["bodies"]), str(rtr["errors"])])
	var allv := true
	for v in rtr["volumes"]:
		allv = allv and float(v) > 0.0
	ok(allv and (rtr["volumes"] as Array).size() == 7, "9 TRIMS every body has volume: %s" % str(rtr["volumes"]))
	# ---- 10 RECORD
	var js := JSON.stringify(rt)
	var back: Dictionary = JSON.parse_string(js)
	var rb := Part.replay(back)
	ok(absf(float(rb["volume"]) - float(rtr["volume"])) <= 1e-9 and int(rb["bodies"]) == int(rtr["bodies"]), "10 RECORD: saved and reloaded, %d bodies, volume %.1f vs %.1f cm3" % [int(rb["bodies"]), float(rb["volume"]) * 1e6, float(rtr["volume"]) * 1e6])
	var n0 := PartRoof.builds
	Part.replay(back)
	ok(PartRoof.builds - n0 <= 1, "10 RECORD: the replay of the same record builds %d meshes (the sewn solids are cached)" % [PartRoof.builds - n0])
	await ui_part()
	print("s226: %d fail" % fails)
	quit()




var m: Node
var pu: PartUI
var ep


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> Image:
	await idle(4)
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [SHOT, nm])
	return img


## the part rebuilds in the background (the first sewing of a roof takes seconds): wait for a result with a solid, 60 s at most
func wait_res() -> void:
	for i in 1800:
		if int(pu.res.get("bodies", 0)) >= 1 or not (pu.res.get("errors", {}) as Dictionary).is_empty():
			break
		await idle(2)
	await idle(3)


## the Parts panel scrolls: bring a control into view the way the user's wheel would
func reveal(c: Control) -> void:
	var n: Node = c.get_parent()
	while n != null and not (n is ScrollContainer):
		n = n.get_parent()
	if n != null:
		(n as ScrollContainer).ensure_control_visible(c)
	await idle(3)


## draw triangle soups (mm) in a SubViewport of their own: one grey solid lit from the side, framed by its box. yaw / pitch in degrees
func render_tris(lists: Array, size: Vector2i, yaw: float, pitch: float) -> Image:
	var svp := SubViewport.new()
	svp.size = size
	svp.own_world_3d = true
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(svp)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var tint := [Color(0.78, 0.8, 0.84), Color(0.86, 0.55, 0.45)]
	var n := 0
	for tl in lists:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in (tl as PackedVector3Array):
			st.add_vertex(v * 0.001)
			lo = lo.min(v * 0.001)
			hi = hi.max(v * 0.001)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint[n % 2]
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		svp.add_child(mi)
		n += 1
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	floor_mi.position = Vector3(0, lo.y - 0.02, 0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.18, 0.2, 0.22)
	floor_mi.material_override = fm
	svp.add_child(floor_mi)
	var ctr := (lo + hi) * 0.5
	var rad := (hi - lo).length() * 0.5
	var cam := Camera3D.new()
	cam.fov = 35.0
	svp.add_child(cam)
	var dir := Vector3(0, 0, 1).rotated(Vector3.RIGHT, -deg_to_rad(pitch)).rotated(Vector3.UP, deg_to_rad(yaw))
	cam.position = ctr + dir * (rad / sin(deg_to_rad(17.5)) * 0.95)
	cam.look_at(ctr, Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	svp.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.environment = e
	svp.add_child(env)
	await idle(6)
	var img := svp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	svp.queue_free()
	return img


func vol_mm3() -> float:
	return float(pu.res.get("volume", 0.0)) * 1e9


func ui_part() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://s226_test"))
	ss.dirs_override = ["user://s226_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	pu = m.bld.part
	# --- the agent call: ONE undo step
	var tools := AgentTools.new(m)
	var u0: int = m.undo.size()
	var rq: Dictionary = await tools.request(1, "part_roof", {"type": "hip", "w": 6000, "d": 4000, "overhang": 500, "height": 1800, "thick": 50, "sag": 200, "lift": 300})
	var rs: Dictionary = rq.get("result", {})
	ok(bool(rs.get("ok", false)) and m.undo.size() == u0 + 1 and int(rs.get("bodies", 0)) == 1 and float(rs.get("volume_mm3", 0.0)) > 1e6, "11 AGENT part_roof: ok %s, %d bodies, %.0f cm3, one undo step (%d -> %d) %s" % [str(rs.get("ok", false)), int(rs.get("bodies", 0)), float(rs.get("volume_mm3", 0.0)) / 1000.0, u0, m.undo.size(), str(rq.get("error", ""))])
	m._undo()
	await idle(3)
	ok(m.S.part.is_empty() or (m.S.part.get("features", []) as Array).is_empty(), "11 AGENT Undo takes the roof back")
	# --- Expert: the Roof tool with real clicks, typed numbers
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	await click_ctl(pu.ep.expert_btn)   # Easy Part's own button to Expert
	await idle(12)
	m._fit_top()
	await idle(6)
	var rb := root.find_child("part_tool_roof_shell", true, false) as Button
	var cap: MenuButton = null
	for lst in m.ui_caps.values():
		for pair in lst:
			var has := false
			for b in pair[1]:
				if (b as Node).name == "part_tool_roof_shell":
					has = true
			if has and (pair[0] as Control).is_visible_in_tree():
				cap = pair[0]
	var ri := -1
	if cap != null:
		await click_ctl(cap)
		await idle(4)
		for q in cap.get_popup().item_count:
			if cap.get_popup().get_item_text(q) == "Roof shell":
				ri = q
		await shot("expert_menu")
	var cr := cap.get_global_rect() if cap != null else Rect2()
	ok(cap != null and ri >= 0 and root.get_visible_rect().encloses(cr), "11 EXPERT the CREATE caption's menu lists Roof (caption on screen %s, item %d)" % [str(cr), ri])
	if ri < 0:
		return
	cap.get_popup().id_pressed.emit(cap.get_popup().get_item_id(ri))
	cap.get_popup().hide()
	await idle(6)
	var typ := root.find_child("part_roof_type", true, false) as OptionButton
	ok(typ != null, "11 EXPERT the dialog shows the roof type pick and its number rows")
	if typ == null:
		return
	typ.select(PartRoof.TYPES.find("xieshan"))
	typ.item_selected.emit(typ.selected)
	var typed := {"w": "9000", "d": "6000", "overhang": "700", "height": "2800", "thick": "70", "sag": "350", "lift": "450", "lift_len": "2200", "y": "3000"}
	for kv in typed:
		var le := root.find_child("part_roof_" + kv, true, false) as LineEdit
		le.text = typed[kv]
		le.text_changed.emit(le.text)
	await idle(4)
	var u1: int = m.undo.size()
	await shot("expert")
	pu.res = {}
	await click_ctl(pu.ok_btn)
	await wait_res()
	var fs: Array = m.S.part.get("features", [])
	var bx := pu.res.get("aabb", AABB()) as AABB
	ok(fs.size() == 1 and String(fs[0].get("type", "")) == "xieshan" and m.undo.size() == u1 + 1 and int(pu.res.get("bodies", 0)) == 1, "11 EXPERT OK made one roof step, one undo step (%d -> %d), %d solid, volume %.0f cm3" % [u1, m.undo.size(), int(pu.res.get("bodies", 0)), vol_mm3() / 1000.0])
	ok(absf(bx.size.x * 1000.0 - (9000.0 + 1400.0)) <= 1.0 and absf(bx.end.y * 1000.0 - (3000.0 + 2800.0)) <= 1.0, "11 EXPERT the built roof is %.1f x %.1f mm in plan and its ridge top is at %.1f mm (asked 10400 x 7400, 5800)" % [bx.size.x * 1000.0, bx.size.z * 1000.0, bx.end.y * 1000.0])
	var js := JSON.stringify(m.S.part)
	var back: Dictionary = JSON.parse_string(js)
	var rb2 := Part.replay(back)
	ok(absf(float(rb2["volume"]) * 1e9 - vol_mm3()) <= 1.0 and int(rb2["bodies"]) == 1, "11 SAVED the part JSON replays to the same volume (%.0f vs %.0f mm3)" % [float(rb2["volume"]) * 1e9, vol_mm3()])
	m._undo()
	await idle(4)
	ok((m.S.part.get("features", []) as Array).is_empty(), "11 EXPERT Undo takes the roof step off")
	# --- Easy: the Roofs page
	m.S.part = {}
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var pbtn := root.find_child("easypart_chip_parts", true, false) as Button
	await click_ctl(pbtn)
	await open_group_of(root.find_child("easypart_lib_Roofs", true, false))   # 239: Roofs is in the Building group
	var cat := root.find_child("easypart_lib_Roofs", true, false) as Button
	ok(cat != null and cat.is_visible_in_tree() and root.get_visible_rect().encloses(cat.get_global_rect()), "11 EASY the Roofs category is on the Parts page and on screen")
	if cat == null:
		return
	await click_ctl(cat)
	var u2: int = m.undo.size()
	var ntype := 0
	for t in ["hip", "gable", "xieshan", "pyramid", "shed", "flat"]:
		var chip := root.find_child("easypart_roof_" + t, true, false) as Button
		if chip == null or not chip.is_visible_in_tree():
			ok(false, "11 EASY chip %s missing" % t)
			continue
		await reveal(chip)
		pu.res = {}
		await click_ctl(chip)
		await wait_res()
		var bb := pu.res.get("aabb", AABB()) as AABB
		var good: bool = int(pu.res.get("bodies", 0)) == 1 and (pu.res.get("errors", {}) as Dictionary).is_empty() and absf(bb.position.y * 1000.0) <= 0.6 and absf(bb.size.x * 1000.0 - 4800.0) <= 1.0 and absf(bb.size.z * 1000.0 - 3800.0) <= 1.0
		ok(good, "11 EASY %s: one solid on the floor (lowest %.2f mm), %.1f x %.1f mm plan (4800 x 3800), %.0f cm3" % [t, bb.position.y * 1000.0, bb.size.x * 1000.0, bb.size.z * 1000.0, vol_mm3() / 1000.0])
		ntype += 1
		await shot("easy_" + t)
	ok(m.undo.size() == u2 + ntype, "11 EASY six chips: one undo step each (%d -> %d)" % [u2, m.undo.size()])
	var cur := root.find_child("easypart_roof_curved", true, false) as Button
	var xs := root.find_child("easypart_roof_xieshan", true, false) as Button   # a flat roof cannot sag: the Chinese hip first, then Curved
	await reveal(xs)
	pu.res = {}
	await click_ctl(xs)
	await wait_res()
	await reveal(cur)
	pu.res = {}
	await click_ctl(cur)
	await wait_res()
	var fcur: Dictionary = (m.S.part.get("features", []) as Array)[0]
	ok(float(fcur.get("sag", 0.0)) > 0.0 and float(fcur.get("lift", 0.0)) > 0.0 and int(pu.res.get("bodies", 0)) == 1, "11 EASY Curved: the roof on the floor now has sag %.0f and corner lift %.0f mm, still one solid" % [float(fcur.get("sag", 0.0)), float(fcur.get("lift", 0.0))])
	await shot("easy")
	# --- the contact sheet of all types (curved where it can be) and the hall's double eave, drawn from the KERNEL's triangles in a view of their own (the app view is full of panels)
	var sheet := Image.create(1200, 800, false, Image.FORMAT_RGB8)
	var kk := 0
	for t in ["hip", "gable", "xieshan", "pyramid", "shed", "flat"]:
		var fl := {"type": t, "w": 6000, "d": 4400, "overhang": 600, "height": 1500, "thick": 60}
		if t != "flat":
			fl["sag"] = 220.0
			fl["lift"] = 320.0 if t != "shed" else 0.0
			fl["lift_len"] = 1500.0
		var sb := body_ids(rec_of(fl))
		var tt: Array = []
		for sid in sb:
			tt.append(tris_of(int(sid)))
			KCad.release(int(sid))
		var cell := await render_tris(tt, Vector2i(400, 400), -30.0, 28.0)
		sheet.blit_rect(cell, Rect2i(0, 0, 400, 400), Vector2i((kk % 3) * 400, (kk / 3) * 400))
		kk += 1
	sheet.save_png(SHOT + "/sheet.png")
	var rec := Part.make("Hall roofs")
	var low := {"type": "hip", "w": 9000, "d": 6000, "overhang": 1200, "height": 1500, "thick": 70, "sag": 250, "lift": 500, "lift_len": 2400, "hole": [8200, 5200], "at": [0, 0, 0]}
	var up := {"type": "xieshan", "w": 7000, "d": 4400, "overhang": 1500, "height": 2600, "thick": 70, "sag": 450, "lift": 650, "lift_len": 2400, "at": [0, 1700, 0]}
	(rec["features"] as Array).append(Part.new_feature(rec, "roof", low))
	(rec["features"] as Array).append(Part.new_feature(rec, "roof", up))
	var hr := Part.replay(rec)
	ok((hr["errors"] as Dictionary).is_empty() and int(hr["bodies"]) == 2 and float(hr["volume"]) > 0.0, "11 HALL double eave: skirt + hip-and-gable, %d solids, %.0f cm3, %s" % [int(hr["bodies"]), float(hr["volume"]) * 1e6, str(hr["errors"])])
	var hb := body_ids(rec)
	var ht: Array = []
	for hid in hb:
		ht.append(tris_of(int(hid)))
		KCad.release(int(hid))
	var hall := await render_tris(ht, Vector2i(1000, 640), -28.0, 22.0)
	hall.save_png(SHOT + "/hall.png")


## 239 (a28b6389): the library chips sit in groups; a user opens a chip's group tab (a real click) before pressing the chip
func open_group_of(c: Control) -> void:
	if c == null or c.is_visible_in_tree():
		return
	for g in root.find_children("easypart_libgroup_*", "Button", true, false):
		var fl := root.find_child("easypart_libchips_" + (g as Button).text, true, false)
		if fl != null and fl.is_ancestor_of(c):
			await click_ctl(g)
			return
