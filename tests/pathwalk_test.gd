## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/pathwalk_test.gd     (ROADMAP 92; a window for the picture)
## PathWalk.build() turns a floor path into walk cards (walk_bat's steady steps, turned to the path). Bars, stated first:
##   1 straight 5 m path at 1.3 m/s: step length within 0.415 +- 2 SD of body height (Gait Posture 2009, PMID 19502061:
##     0.415 +- 0.038; bar [0.339, 0.491] of 1.70 m); cadence within 105.5 +- 2 SD (PMID 29775941: 105.5 +- 5.2; bar 95.1-115.9)
##   2 the app's own gait check (Rulebook GAIT) says nothing about it: no GAIT finding, and the sample reads as a walk
##   3 a standing foot slides less than 5 mm on its mark, every frame (walk_legs_test's bar)
##   4 swing knee peak 55-70 deg (Winter 2009 normative; the bar the walk legs test uses is 55-72)
##   5 90 deg turn path (2 m, the corner, 2.5 m): the facing (pelvis yaw) follows the path tangent within 10 deg, every frame
##   6 the same turn: no standing foot slides more than 1 cm on its mark
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## build a walk and load it: {"S": Scene, "B": Body, "r": build result}
func load_walk(pts: Array, speed: float) -> Dictionary:
	var r := PathWalk.build(pts, speed)
	if not r["ok"]:
		return {"ok": false, "why": r["why"]}
	var S := Scene.new()
	S.from_dict(r["scene"])
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return {"ok": true, "S": S, "B": B, "r": r}


## the largest slide of a standing foot on its mark over the whole walk, 120 Hz (walk_legs_test's measure)
func slide(S: Scene, B: Body) -> float:
	var fps := 120.0
	var ts := S.times()
	var t0: float = ts[0][0]
	var t1: float = ts[-1][1]
	var mark := {}
	var prev := {}
	var worst := 0.0
	for k in int((t1 - t0) * fps) + 1:
		S.apply(B, t0 + k / fps)
		for sd in ["_l", "_r"]:
			var ball: Vector3 = B.P["ball" + sd]
			var down := ball.y < 0.022
			var slow: bool = prev.has(sd) and Vector2(ball.x - prev[sd].x, ball.z - prev[sd].z).length() * fps < 0.2
			if down and slow:
				if not mark.has(sd):
					mark[sd] = ball
				worst = maxf(worst, Vector2(ball.x - mark[sd].x, ball.z - mark[sd].z).length())
			elif not down:
				mark.erase(sd)
			prev[sd] = ball
	return worst


## the largest calf (knee) bend while the foot is in the air, over the walk
func swing_knee(S: Scene, B: Body) -> float:
	var fps := 120.0
	var ts := S.times()
	var k_max := 0.0
	for k in int((float(ts[-1][1]) - float(ts[0][0])) * fps) + 1:
		S.apply(B, float(ts[0][0]) + k / fps)
		for sd in ["_l", "_r"]:
			if (B.P["ball" + sd] as Vector3).y >= 0.022:
				k_max = maxf(k_max, float(B.ang["calf" + sd].x))
	return k_max


## the pelvis's facing (yaw, rad, about +y) and the path's tangent at the hip's nearest point, every frame: the largest gap
func facing_gap(S: Scene, B: Body, c: Dictionary) -> float:
	var fps := 120.0
	var ts := S.times()
	var worst := 0.0
	for k in int((float(ts[-1][1]) - float(ts[0][0])) * fps) + 1:
		S.apply(B, float(ts[0][0]) + k / fps)
		var fwd: Vector3 = (B.G["pelvis"] as Quaternion) * Vector3(0, 0, 1)
		var face := atan2(fwd.x, fwd.z)
		var hip: Vector3 = B.offset
		var best := INF
		var s_best := 0.0
		var P: Array = c["p"]
		var S_arr: PackedFloat64Array = c["s"]
		for i in P.size():
			var d := Vector2(P[i].x - hip.x, P[i].z - hip.z).length()
			if d < best:
				best = d
				s_best = S_arr[i]
		# the walk's own hips sit HIP_BACK behind the feet: the nearest point is where the body is, so the tangent there
		var tan := PathWalk.heading(c, s_best)
		var gap := absf(wrapf(face - tan, -PI, PI))
		worst = maxf(worst, gap)
	return rad_to_deg(worst)


## the 90 degree turn: straight +z to (0, 2), a quarter circle (centre (1.5, 2), r 1.5) to (1.5, 3.5) heading +x, straight on
func turn_path() -> Array:
	var out := []
	for i in 21:
		out.append(Vector3(0, 0, 2.0 * i / 20.0))
	for i in range(1, 24):
		var phi := (PI / 2.0) * i / 23.0
		out.append(Vector3(1.5 - 1.5 * cos(phi), 0, 2.0 + 1.5 * sin(phi)))
	for i in range(1, 26):
		out.append(Vector3(1.5 + 2.5 * i / 25.0, 0, 3.5))
	return out


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var st := PathWalk.step_numbers(1.3)
	print("numbers at 1.3 m/s: step %.3f m, cadence %.1f steps/min, %.3f s per step" % [st["step"], st["cadence"], st["time"]])
	# 1-4: a straight 5 m walk at 1.3 m/s, along +z like the donor
	var a := load_walk([Vector3(0, 0, 0), Vector3(0, 0, 5.0)], 1.3)
	if not a["ok"]:
		print("FAIL the straight walk did not build: %s" % a["why"])
		TestFiles.cleanup()
		quit(1)
		return
	var S: Scene = a["S"]
	var B: Body = a["B"]
	var r: Dictionary = a["r"]
	var h := 1.70
	var step: float = r["step"]
	ok(step / h >= 0.415 - 2 * 0.038 and step / h <= 0.415 + 2 * 0.038,
		"1 step length %.3f m = %.3f of height (people 0.415 +- 0.038; bar 0.339-0.491)" % [step, step / h])
	var cad: float = r["cadence"]
	ok(cad >= 105.5 - 2 * 5.2 and cad <= 105.5 + 2 * 5.2,
		"1 cadence %.1f steps/min at 1.3 m/s (people 105.5 +- 5.2; bar 95.1-115.9)" % cad)
	var sm := Rulebook.sample(S, B)
	var g := Rulebook.gait(sm)
	print("  the gait check reads: walk %s, step %.3f of height, cadence %.1f, steps %s" % [g["walk"], g.get("step", -1.0), g.get("cad", -1.0), g.get("steps", "?")])
	var gait_f := Rulebook.check(S, B, sm).filter(func(x): return x["rule"] == "GAIT")
	ok(g["walk"] and gait_f.is_empty(), "2 the app's gait check: %s, no GAIT finding (%d)" % ["a walk" if g["walk"] else "NOT a walk: " + str(g["why"]), gait_f.size()])
	var sl := slide(S, B)
	ok(sl < 0.005, "3 a standing foot slides %.2f mm on its mark (bar < 5 mm)" % (sl * 1000.0))
	var kn := swing_knee(S, B)
	ok(kn >= 55.0 and kn <= 70.0, "4 swing knee peak %.1f deg (Winter 2009 normative ~60-65; bar 55-70)" % kn)
	# 5-6: a 90 degree turn: 2 m straight, a quarter circle of radius 1.5 m, 2.5 m straight (points every 10 cm)
	var turn := turn_path()
	var b := load_walk(turn, 1.3)
	if not b["ok"]:
		print("FAIL the turn did not build: %s" % b["why"])
		TestFiles.cleanup()
		quit(1)
		return
	var SB: Scene = b["S"]
	var BB: Body = b["B"]
	var cb: Dictionary = PathWalk.curve(turn)
	var fg := facing_gap(SB, BB, cb)
	ok(fg <= 10.0, "5 facing follows the path tangent on the 90 deg turn: worst gap %.1f deg (bar 10)" % fg)
	var sl2 := slide(SB, BB)
	ok(sl2 < 0.01, "6 standing feet on the turn: worst slide %.1f mm (bar < 10 mm)" % (sl2 * 1000.0))
	# 8 a tight turn is refused, with the number and the next step
	var tight := []
	for i in 21:
		tight.append(Vector3(0, 0, 2.0 * i / 20.0))
	for i in range(1, 24):
		var phi := (PI / 2.0) * i / 23.0
		tight.append(Vector3(0.5 - 0.5 * cos(phi), 0, 2.0 + 0.5 * sin(phi)))
	for i in range(1, 26):
		tight.append(Vector3(0.5 + 2.5 * i / 25.0, 0, 2.5))
	var refused := PathWalk.build(tight, 1.3)
	ok(not refused["ok"] and String(refused["why"]).contains("radius"), "8 a 0.5 m bend is refused: %s" % refused.get("why", "built"))
	if DisplayServer.get_name() != "headless":
		await shot(turn, b["r"], SB, BB)
	# 7 placement: where each landing's ball really is when its card arrives, against the mark the walk was given
	var place := 0.0
	var ts_b := SB.times()
	var N := int(b["r"]["steps"]) - 1
	var Lb: float = b["r"]["step"]
	var landing_t := []
	for i in SB.cards.size():
		if String(SB.cards[i]["name"]).begins_with("step"):
			landing_t.append(ts_b[i][1])
	for k in range(1, N + 1):
		var sd := "_l" if k % 2 == 1 else "_r"
		SB.apply(BB, landing_t[k - 1])
		var mark := PathWalk.foot(cb, sd, Lb * 0.5 + (k - 1) * Lb)
		var ball: Vector3 = BB.P["ball" + sd]
		place = maxf(place, Vector2(ball.x - mark.x, ball.z - mark.z).length())
	ok(place < 0.02, "7 placement: every landing's ball is on its path mark, worst %.1f mm off (bar < 20 mm)" % (place * 1000.0))
	print("PATH WALK TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)


## the picture: the walk on the turn, the body whole, the path as a ribbon and each footprint where it landed
func shot(pts: Array, r: Dictionary, S: Scene, B: Body) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1100, 800)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	get_root().add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.93, 0.93, 0.91)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, 30, 0)
	key.light_energy = 1.0
	vp.add_child(key)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.6
	cam.near = 0.05
	cam.far = 40.0
	vp.add_child(cam)
	var at_pt := Vector3(2.0, 0.9, 1.75)
	cam.look_at_from_position(at_pt + Vector3(-5.0, 6.5, 7.0), at_pt)
	cam.current = true
	var skin := StandardMaterial3D.new()
	skin.albedo_color = PoseLibrary.SKIN
	skin.roughness = 0.55
	var mq := Overlays.mannequin(vp, skin)
	# the path: a ribbon along the smoothed centre line
	var c := PathWalk.curve(pts)
	var P: Array = c["p"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.35, 0.75)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	for i in range(P.size() - 1):
		var a: Vector3 = P[i] + Vector3(0, 0.005, 0)
		var b_: Vector3 = P[i + 1] + Vector3(0, 0.005, 0)
		var dir := (b_ - a).normalized()
		var side := Vector3(-dir.z, 0, dir.x) * 0.025
		st.add_vertex(a - side)
		st.add_vertex(a + side)
		st.add_vertex(b_ + side)
		st.add_vertex(a - side)
		st.add_vertex(b_ + side)
		st.add_vertex(b_ - side)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	vp.add_child(mi)
	# the footprints: one flat box per landing (the stance feet included), turned to the tangent there
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.85, 0.35, 0.2)
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# the marks come from the walk's own landings: foot(c, side, s) for each landing k, sides alternating from the left
	var landings := []
	var L: float = r["step"]
	var N: int = int(r["steps"]) - 1
	for k in range(1, N + 1):
		var sd := "_l" if k % 2 == 1 else "_r"
		landings.append([sd, PathWalk.foot(c, sd, L * 0.5 + (k - 1) * L)])
	for lm in landings:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.012, 0.26)
		box.mesh = bm
		box.material_override = fm
		var pos: Vector3 = lm[1]
		var yaw := PathWalk.heading(c, _s_of(c, pos))
		box.position = Vector3(pos.x, 0.006, pos.z)
		box.rotation = Vector3(0, yaw, 0)
		vp.add_child(box)
	# the body at a moment on the arc
	var ts := S.times()
	var k_mid := int(ts.size() * 0.6)
	S.apply(B, ts[k_mid][1])
	Overlays.pose_skeleton(mq[1], mq[2], B)
	# the camera on the body: the whole figure is about 1/3 of the frame's height
	var hip: Vector3 = B.offset + Vector3(0, 0.85, 0)
	cam.size = 4.6
	cam.look_at_from_position(hip + Vector3(-3.0, 4.2, 4.6), hip)
	await get_root().get_tree().process_frame
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var path := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/pathwalk.png"
	if img != null and not img.is_empty():
		img.save_png(path)
		print("picture saved: %s" % path)
	else:
		print("FAIL the picture did not render")
		fails += 1


## the arc length of the path point nearest to p (for the footprints' tangents)
func _s_of(c: Dictionary, p: Vector3) -> float:
	var best := INF
	var s_best := 0.0
	var P: Array = c["p"]
	var S_arr: PackedFloat64Array = c["s"]
	for i in P.size():
		var d := Vector2((P[i] as Vector3).x - p.x, (P[i] as Vector3).z - p.z).length()
		if d < best:
			best = d
			s_best = S_arr[i]
	return s_best
