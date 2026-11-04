extends SceneTree
## CH12 3D film: the footbridge as a Kine Part (data/challenges/ch12_bridge.json) in 3D over a river with a city behind, Kine mannequins on a walk cycle (PathWalk + Crowd's pose table),
## the 300 s run played as a 15x time-lapse with a clock, then a split screen of the locked crowd, the random-phase control and the retrofit dampers.
## godot --position -30000,-30000 --audio-driver Dummy --resolution 1280x720 --path . -s tools/ch12_render3d.gd -- <outdir> [exaggeration=10] [n_over_nc=3] [part=AB|A|B] [max_frames=0]
## Writes <outdir>/frames/f%05d.png (A then B). Encode: ffmpeg -y -framerate 20 -i <outdir>/frames/f%05d.png -c:v libx264 -pix_fmt yuv420p <outdir>/ch12_3d.mp4
## WHAT IS SIMULATED AND WHAT IS A PICTURE (also printed on the film):
##   simulated: the deck's lateral motion (frame solver, C++), each walker's lateral phase theta_i (the crowd equation re-integrated from the recorded mid-span motion, checked against the solver's own end phases),
##   the walker's body sway d_i = A_s sin(theta_i) with A_s = F0 / (m omega^2) (F = m a at 70 kg), drawn with the same exaggeration as the deck.
##   a picture: the gait cycle (Kine PathWalk steps at 1.3 m/s, played at normal speed, not time-lapsed) and the step width (hips abducted up to 10 deg as the amplitude passes 100 mm, Dallard's
##   observation that people splay their feet on a swaying deck; the amount is illustrative, not fitted).
const BR := preload("res://scripts/build/ch12_bridge.gd")
const BODY_MASS := 70.0
const FPS := 20.0
const STEP_DT := 0.025
const SNAP_EVERY := 30          # 0.75 s per frame: 20 fps = 15x
const WALK_SPEED := 1.3

var S := 10.0
var part_json: Dictionary
var gait: Dictionary = {}
var splay_sign := 1.0


# ------------------------------------------------------------------------------------------------ gait table
func make_gait() -> void:
	var T: float = PathWalk.step_numbers(WALK_SPEED)["time"]
	var r := PathWalk.build([Vector3(0, 0, 0), Vector3(14, 0, 0)], WALK_SPEED)
	var sc := Scene.new()
	sc.from_dict(r["scene"])
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var t0: float = PathWalk.HOLD_START + 2.0 * T
	var stride := 2.0 * T
	var n := 64
	var angs := []
	var offs := []
	var hs := []
	for k in n + 1:
		sc.apply(B, t0 + stride * k / n)
		var a := PackedVector3Array()
		for j in Body.ORDER:
			a.append(B.ang[j])
		angs.append(a)
		offs.append(B.offset)
		hs.append(B.sole_low())
	var v: Vector3 = ((offs[n] as Vector3) - (offs[0] as Vector3)) / stride
	gait = {"n": n, "angs": angs, "offs": offs, "hs": hs, "stride": stride, "v": v}
	print("gait: step time %.3f s, stride %.3f s, clip speed %.2f m/s (x), offset drift z %.3f" % [T, stride, v.x, v.z])
	# which sign of thigh side-angle widens the stance
	var q0: PackedVector3Array = angs[0]
	var w0 := _stance(B, q0, 0.0)
	var w1 := _stance(B, q0, 10.0)
	splay_sign = 1.0 if w1 > w0 else -1.0
	print("stance width %.3f m, with +10 deg abduction %.3f m (sign %+.0f)" % [w0, w1, splay_sign])


func _stance(B: Body, a: PackedVector3Array, deg: float) -> float:
	for q in Body.ORDER.size():
		B.ang[Body.ORDER[q]] = a[q]
	B.ang["thigh_l"] = B.ang["thigh_l"] + Vector3(0, deg, 0)
	B.ang["thigh_r"] = B.ang["thigh_r"] + Vector3(0, -deg, 0)
	B.fk()
	var l: Vector3 = Proportions.heel(B, "_l")
	var r: Vector3 = Proportions.heel(B, "_r")
	return absf(l.x - r.x) + absf(l.z - r.z)


## pose a walker B at gait phase u (0..1) with extra hip abduction splay (deg)
func pose_walker(B: Body, u: float, splay: float) -> void:
	var n: int = gait["n"]
	var f := fposmod(u, 1.0) * n
	var i0 := int(floorf(f)) % n
	var i1 := (i0 + 1) % n
	var w: float = f - floorf(f)
	var A: PackedVector3Array = gait["angs"][i0]
	var A1: PackedVector3Array = gait["angs"][i1]
	for q in Body.ORDER.size():
		var j: String = Body.ORDER[q]
		B.ang[j] = A[q].lerp(A1[q], w)
	if splay != 0.0:
		B.ang["thigh_l"] = B.ang["thigh_l"] + Vector3(0, splay_sign * splay, 0)
		B.ang["thigh_r"] = B.ang["thigh_r"] + Vector3(0, -splay_sign * splay, 0)
	var v: Vector3 = gait["v"]
	var stride: float = gait["stride"]
	var o0: Vector3 = gait["offs"][0]
	var o: Vector3 = (gait["offs"][i0] as Vector3).lerp(gait["offs"][i1], w)
	var t := f / n * stride
	B.offset = Vector3(o.x - o0.x - v.x * t, o.y, o.z - o0.z - v.z * t) + Vector3(o0.x, 0, o0.z)
	B.fk()
	var h := lerpf(float(gait["hs"][i0]), float(gait["hs"][i1]), w)
	B.offset.y += h - B.sole_low()
	B.fk()


# ------------------------------------------------------------------------------------------------ one world
class W:
	extends RefCounted
	var root: Node3D
	var segs: Array = []         # [mesh_instance, kind, side]
	var crosses: Array = []
	var men: Array = []          # {node, sk, idx, B, i (walker index), x0, dir, ph, lane}
	var deck_y := 8.0
	var tool


func _box(parent: Node3D, size: Vector3, col: Color, rough := 0.7, metal := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = size
	mi.mesh = bx
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = rough
	mat.metallic = metal
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func build_world(parent: Node, size: Vector2i, own: bool, n_men: int, n_walkers: int, cam_mode: String) -> W:
	var w := W.new()
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = own
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(vp)
	var wr := Node3D.new()
	vp.add_child(wr)
	w.root = wr
	w.set_meta("vp", vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.36, 0.52, 0.78)
	psm.sky_horizon_color = Color(0.78, 0.84, 0.92)
	psm.ground_horizon_color = Color(0.70, 0.74, 0.78)
	psm.ground_bottom_color = Color(0.30, 0.34, 0.38)
	sky.sky_material = psm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.74, 0.80, 0.88)
	e.fog_density = 0.0016
	env.environment = e
	wr.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -55, 0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	wr.add_child(sun)
	# river and banks
	var river := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	river.mesh = pm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.16, 0.30, 0.40)
	rm.roughness = 0.15
	rm.metallic = 0.3
	river.material_override = rm
	river.position = Vector3(72, -w.deck_y - 0.0, 0)
	wr.add_child(river)
	# the Part: read its boxes (mm)
	var feats: Array = part_json["part"]["features"]
	var parts := {}
	for f in feats:
		if f["t"] == "prim":
			parts[f["name"]] = f
	var g: Dictionary = parts["girder.S"]
	var d: Dictionary = parts["deck"]
	var seg_len := BR.L / BR.NSEG
	for side in [-1, 1]:
		for s in BR.NSEG:
			var mi := _box(wr, Vector3(seg_len + 0.05, float(g["h"]) * 0.001, float(g["d"]) * 0.001), Color(0.36, 0.38, 0.42), 0.35, 0.8)
			w.segs.append([mi, "girder", side, s, float(g["y"]) * 0.001 + float(g["h"]) * 0.0005])
	for s in BR.NSEG:
		var mi := _box(wr, Vector3(seg_len + 0.05, float(d["h"]) * 0.001, float(d["d"]) * 0.001), Color(0.64, 0.58, 0.48), 0.85)
		w.segs.append([mi, "deck", 0, s, float(d["y"]) * 0.001 + float(d["h"]) * 0.0005])
	for f in feats:
		if f["t"] == "prim" and str(f["name"]).begins_with("cross."):
			var st := int(str(f["name"]).split(".")[1])
			var mi := _box(wr, Vector3(float(f["w"]) * 0.001, float(f["h"]) * 0.001, float(f["d"]) * 0.001), Color(0.30, 0.32, 0.36), 0.5, 0.6)
			w.crosses.append([mi, st, float(f["y"]) * 0.001 + float(f["h"]) * 0.0005])
	for nm in ["abutment.W", "abutment.E"]:
		var f: Dictionary = parts[nm]
		var top := float(f["y"]) * 0.001 + float(f["h"]) * 0.001
		var hh := w.deck_y + top + 0.0
		var mi := _box(wr, Vector3(float(f["w"]) * 0.001 + 6.0, hh + 0.0, float(f["d"]) * 0.001 + 4.0), Color(0.60, 0.57, 0.52), 0.9)
		mi.position = Vector3((float(f["x"]) + float(f["w"]) * 0.5) * 0.001, top - hh * 0.5, 0)
	# river banks and the city behind the far end and the far side
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var bank := _box(wr, Vector3(200, 3.0, 900), Color(0.38, 0.40, 0.36), 0.95)
	bank.position = Vector3(-100 - 3.0, -w.deck_y + 1.5, 0)
	var bank2 := _box(wr, Vector3(200, 3.0, 900), Color(0.38, 0.40, 0.36), 0.95)
	bank2.position = Vector3(BR.L + 100 + 3.0, -w.deck_y + 1.5, 0)
	var bank3 := _box(wr, Vector3(900, 3.0, 200), Color(0.38, 0.40, 0.36), 0.95)
	bank3.position = Vector3(72, -w.deck_y + 1.5, -130)
	for q in 70:
		var x := rng.randf_range(-60, BR.L + 150)
		var z := rng.randf_range(-260, -150)
		var h := rng.randf_range(12, 70) if rng.randf() < 0.9 else rng.randf_range(80, 140)
		var c := Color(0.55, 0.55, 0.57).lerp(Color(0.62, 0.50, 0.40), rng.randf() * 0.7) * rng.randf_range(0.8, 1.1)
		var b := _box(wr, Vector3(rng.randf_range(14, 34), h, rng.randf_range(14, 30)), Color(c.r, c.g, c.b), 0.85)
		b.position = Vector3(x, -w.deck_y + 3.0 + h * 0.5, z)
	for q in 40:
		var x := rng.randf_range(BR.L + 20, BR.L + 220)
		var z := rng.randf_range(-120, 140)
		var h := rng.randf_range(10, 60)
		var c := Color(0.52, 0.52, 0.55).lerp(Color(0.60, 0.46, 0.38), rng.randf() * 0.7)
		var b := _box(wr, Vector3(rng.randf_range(14, 32), h, rng.randf_range(14, 30)), Color(c.r, c.g, c.b), 0.85)
		b.position = Vector3(x, -w.deck_y + 3.0 + h * 0.5, z)
	# camera
	var cam := Camera3D.new()
	cam.fov = 48.0 if cam_mode == "A" else 38.0
	wr.add_child(cam)
	if cam_mode == "A":
		cam.look_at_from_position(Vector3(-16, 7.5, 15), Vector3(62, -1.0, 0), Vector3.UP)
	else:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 13.0
		cam.look_at_from_position(Vector3(72, 60, 0), Vector3(72, 0, 0), Vector3(0, 0, -1))
	# the walkers
	var step := float(n_walkers) / float(n_men)
	for k in n_men:
		var i := int(floor(k * step))
		var man := Node3D.new()
		wr.add_child(man)
		var skin := StandardMaterial3D.new()
		skin.albedo_color = [Color(0.86, 0.50, 0.26), Color(0.30, 0.55, 0.78), Color(0.78, 0.74, 0.34), Color(0.55, 0.35, 0.65), Color(0.32, 0.66, 0.48)][k % 5]
		skin.roughness = 0.6
		var mq := Overlays.mannequin(man, skin)
		var B := Body.new()
		B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		var seed_f := fposmod(k * 0.6180339887 + 0.17, 1.0)
		w.men.append({"node": man, "sk": mq[1], "idx": mq[2], "B": B, "i": i, "x0": (k + 0.5) / n_men * BR.L, "dir": 1.0 if k % 2 == 0 else -1.0, "ph": seed_f, "lane": (float((k * 7) % 5) - 2.0) * 0.36, "sc": 0.94 + 0.12 * fposmod(k * 0.7548776662, 1.0)})
	w.tool = self
	return w


## put the world in the state of one frame: snap (6n deck displacements), per walker sin(theta) and the amplitude, the video clock for the gait
func update_world(w: W, snap: PackedFloat64Array, sin_th: PackedFloat64Array, amp: float, vt: float) -> void:
	var seg_len := BR.L / BR.NSEG
	var uz := func(st: int, k: int) -> float: return snap[(st * 3 + k) * 6 + 2] * S
	var uy := func(st: int, k: int) -> float: return snap[(st * 3 + k) * 6 + 1] * S
	for sg in w.segs:
		var mi: MeshInstance3D = sg[0]
		var s: int = sg[3]
		var k: int = 1 if sg[1] == "deck" else (0 if sg[2] < 0 else 2)
		var z0: float = uz.call(s, k) + (k - 1) * BR.ZG
		var z1: float = uz.call(s + 1, k) + (k - 1) * BR.ZG
		var y: float = sg[4] + w.deck_y - w.deck_y
		var a := Vector3(s * seg_len, y, z0)
		var b := Vector3((s + 1) * seg_len, y, z1)
		var dir := b - a
		mi.position = (a + b) * 0.5
		mi.rotation = Vector3(0, -atan2(dir.z, dir.x), 0)
	for cr in w.crosses:
		var mi2: MeshInstance3D = cr[0]
		var st: int = cr[1]
		mi2.position = Vector3(st * seg_len, cr[2], uz.call(st, 1))
	var T2: float = gait["stride"]
	for q in w.men.size():
		var m: Dictionary = w.men[q]
		var dir: float = m["dir"]
		var x: float = fposmod(m["x0"] + dir * WALK_SPEED * vt, BR.L)
		var st2 := mini(int(x / seg_len), BR.NSEG - 1)
		var fr := x / seg_len - st2
		var dz: float = (1.0 - fr) * uz.call(st2, 1) + fr * uz.call(st2 + 1, 1)
		var sway := (BR.F0_PED / (BODY_MASS * pow(float(_omega), 2.0))) * sin_th[q] * S
		var splay := 10.0 * clampf((amp - 0.0) / 0.1, 0.0, 1.0)
		var u := fposmod(vt / T2 + m["ph"], 1.0)
		pose_walker(m["B"], u if dir > 0.0 else u, splay)
		Overlays.pose_skeleton(m["sk"], m["idx"], m["B"])
		var node: Node3D = m["node"]
		var yaw := 0.0 if dir > 0.0 else PI
		node.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * m["sc"]), Vector3(x, 0.0, m["lane"] + dz + sway))


var _omega := 3.0


func _grab_frame(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


# ------------------------------------------------------------------------------------------------ simulation + phases
func phases(br: Dictionary, lat: Dictionary, n: int, kind: String, u_mid: PackedFloat64Array, dt: float, n_frames: int) -> Dictionary:
	var cr := BR.crowd(br, n, lat["omega"], kind)
	var om: PackedFloat64Array = cr["omega"]
	var th: PackedFloat64Array = cr["theta0"].duplicate()
	var cp: float = cr["cp"]
	var n1: PackedInt32Array = cr["n1"]
	var cw: PackedFloat64Array = cr["w"]
	var xs := PackedFloat64Array()
	for i in n:
		xs.append((i + 0.5) / n * BR.L)
	var phi := PackedFloat64Array()
	for i in n:
		phi.append(sin(PI * xs[i] / BR.L))
	var out: Array = []
	var ns := u_mid.size() - 1
	for s in range(0, ns + 1):
		if s % SNAP_EVERY == 0:
			var sn := PackedFloat64Array()
			sn.resize(n)
			for i in n:
				sn[i] = sin(th[i])
			out.append(sn)
		if s == ns:
			break
		var vmid := (u_mid[mini(s + 1, ns)] - u_mid[maxi(s - 1, 0)]) / (dt * (mini(s + 1, ns) - maxi(s - 1, 0)))
		for i in n:
			var vi := phi[i] * vmid
			var g1 := om[i] + cp * vi * cos(th[i])
			var tm := th[i] + 0.5 * dt * g1
			th[i] += dt * (om[i] + cp * vi * cos(tm))
	return {"sin": out, "theta_end": th}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var outdir: String = args[0] if args.size() > 0 else "C:/Users/Nick/tools/kine_workers/out/ch12_3d"
	if args.size() > 1:
		S = float(args[1])
	var fac := float(args[2]) if args.size() > 2 else 3.0
	var parts_sel: String = args[3] if args.size() > 3 else "AB"
	var max_frames := int(args[4]) if args.size() > 4 else 0
	var skip := int(args[5]) if args.size() > 5 else 1
	DirAccess.make_dir_recursive_absolute(outdir + "/frames")
	part_json = JSON.parse_string(FileAccess.get_file_as_string("res://data/challenges/ch12_bridge.json"))
	make_gait()
	var br := BR.build()
	var lat := BR.mode(br, "lat")
	_omega = lat["omega"]
	var nc := BR.n_paper(BR.ZETA, lat["f"], lat["mgen"])
	var n := int(round(fac * nc))
	var T := 300.0
	var base := {"T": T, "dt": STEP_DT, "amp0": 0.006, "n": n}
	var runs: Array = []
	for spec in [["locked", false, "LOCKED crowd"], ["random", false, "RANDOM-phase crowd (control)"], ["locked", true, "RETROFIT: dampers, 5 % damping"]]:
		var o := base.duplicate()
		o["kind"] = spec[0]
		o["retrofit"] = spec[1]
		o["snap_every"] = SNAP_EVERY
		var r := BR.run(br, lat, o)
		var u: PackedFloat64Array = r["rec_u"].slice(0, int(r["ns"]) + 1)
		var ph := phases(br, lat, n, spec[0], u, STEP_DT, 0)
		# check the re-integration against the solver's own end phases (mod 2 pi)
		var th_c: PackedFloat64Array = r["crowd_theta"]
		var worst := 0.0
		for i in n:
			worst = maxf(worst, absf(wrapf(th_c[i] - ph["theta_end"][i], -PI, PI)))
		print("%s: %d snaps, peak mid-span %.1f mm, end %.1f mm; re-integrated theta vs solver, worst end difference %.3f rad" % [spec[2], r["snaps"].size(), 1000.0 * u_peak(u), 1000.0 * u_peak(u.slice(u.size() - 100)), worst])
		# per-frame amplitude: max |u| over the 2 s up to the frame
		var amps := PackedFloat64Array()
		for f in r["snaps"].size():
			var s1 := mini(f * SNAP_EVERY, u.size() - 1)
			amps.append(u_peak(u.slice(maxi(0, s1 - 84), s1 + 1)))
		runs.append({"name": spec[2], "snaps": r["snaps"], "sin": ph["sin"], "amp": amps, "u": u})
	var n_frames: int = runs[0]["snaps"].size()
	print("N_c %.1f, N %d, frames per part %d" % [nc, n, n_frames])
	var root := get_root()
	root.size = Vector2i(1280, 720)
	var cl := CanvasLayer.new()
	root.add_child(cl)
	# worlds
	var wa: W = null
	var wb: Array = []
	var holder := Node.new()
	root.add_child(holder)
	if parts_sel.contains("A"):
		wa = build_world(holder, Vector2i(1280, 720), true, 60, n, "A")
	if parts_sel.contains("B"):
		for r in 3:
			wb.append(build_world(holder, Vector2i(1280, 224), true, 28, n, "B"))
	var views: Array = []
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	title.position = Vector2(14, 8)
	var clock := Label.new()
	clock.add_theme_font_size_override("font_size", 30)
	clock.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	clock.add_theme_constant_override("shadow_offset_x", 2)
	clock.add_theme_constant_override("shadow_offset_y", 2)
	clock.position = Vector2(14, 44)
	var note := Label.new()
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	note.add_theme_constant_override("shadow_offset_x", 1)
	note.add_theme_constant_override("shadow_offset_y", 1)
	note.position = Vector2(14, 676)
	note.text = "deck and walker sway drawn x%d   |   sway is a 15x time-lapse, walkers walk at normal speed   |   step width: illustrative splay (up to 10 deg at 100 mm), not simulated" % int(S)
	var capl: Array = []
	var ampl: Array = []
	var cont_a: SubViewportContainer = null
	var cont_b: Array = []
	if wa != null:
		cont_a = SubViewportContainer.new()
		cont_a.stretch = false
		cont_a.position = Vector2.ZERO
		cl.add_child(cont_a)
		(wa.get_meta("vp") as SubViewport).reparent(cont_a)
	for q in wb.size():
		var c := SubViewportContainer.new()
		c.position = Vector2(0, 0 + q * 224)
		cl.add_child(c)
		(wb[q].get_meta("vp") as SubViewport).reparent(c)
		cont_b.append(c)
		var cap := Label.new()
		cap.add_theme_font_size_override("font_size", 18)
		cap.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		cap.add_theme_constant_override("shadow_offset_x", 1)
		cap.add_theme_constant_override("shadow_offset_y", 1)
		cap.position = Vector2(14, q * 224 + 4)
		capl.append(cap)
	for q in capl.size():
		cl.add_child(capl[q])
	cl.add_child(title)
	cl.add_child(clock)
	cl.add_child(note)
	await process_frame
	await process_frame
	var fi := 0
	var total := 0
	# Part A: the locked run, full screen
	var seqs: Array = []
	if wa != null:
		seqs.append("A")
	if wb.size() > 0:
		seqs.append("B")
	for part in seqs:
		for q in cont_b.size():
			cont_b[q].visible = part == "B"
			capl[q].visible = part == "B"
		if cont_a != null:
			cont_a.visible = part == "A"
		var lim := n_frames if max_frames == 0 else mini(n_frames, max_frames)
		for k in range(0, lim, skip):
			var vt := (k + (n_frames if part == "B" else 0)) / FPS
			var tt := k * SNAP_EVERY * STEP_DT
			if part == "A":
				var r0: Dictionary = runs[0]
				(wa.get_meta("vp") as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
				update_world(wa, r0["snaps"][k], r0["sin"][k], r0["amp"][k], vt)
				title.text = "CH12: a footbridge that sways: 144 m span, lateral f1 = %.2f Hz, %d walkers = %.0f x the critical number (Dallard et al. 2001)" % [lat["f"], n, fac]
				clock.text = "t = %5.1f s   (x15 time-lapse)     mid-span amplitude %5.1f mm real" % [tt, 1000.0 * r0["amp"][k]]
			else:
				for q in 3:
					var rq: Dictionary = runs[q]
					(wb[q].get_meta("vp") as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
					update_world(wb[q], rq["snaps"][k], rq["sin"][k], rq["amp"][k], vt)
					capl[q].text = "%s   N = %d   amplitude %5.1f mm" % [rq["name"], n, 1000.0 * rq["amp"][k]]
				title.text = ""
				note.text = "SPLIT SCREEN, plan view: the same 300 s, the same N = %d, three bridges   |   drawn x%d   |   walkers walk at normal speed" % [n, int(S)]
				clock.text = "t = %5.1f s   (x15 time-lapse)" % tt
				clock.position = Vector2(840, 2)
				clock.add_theme_font_size_override("font_size", 24)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/frames/f%05d.png" % [outdir, fi])
			fi += 1
		if part == "A" and wa != null:
			(wa.get_meta("vp") as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
		for q in wb.size():
			(wb[q].get_meta("vp") as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	print("frames done: ", fi)
	quit(0)


func u_peak(a: PackedFloat64Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, absf(v))
	return m
