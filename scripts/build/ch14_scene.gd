extends RefCounted
## CH14: the arm as a 3D scene (metres; parts in mm) for the animated build and the syringe-pair section.
## build(parent) -> sc; pose(sc, t) puts every joint, the five master plungers on the console and the six cans where the build sequence (ch14_anim.gd) has them at time t.
## Node chain: yaw (turntable, about y) -> shoulder at (0, hs) (upper arm, about z by th1) -> elbow at (L1, 0) (forearm, th2) -> wrist at (L2, 0) (gripper, psi; jaws slide in z).
const A := preload("res://scripts/build/ch14_arm.gd")
const N := preload("res://scripts/build/ch14_anim.gd")
const PT := preload("res://scripts/build/ch14_parts.gd")
const MM := 0.001
const AXES := ["ba", "sh", "el", "wr", "gr"]


static func _mi(parent: Node3D, rec: Dictionary, nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = Assembly.built(rec)["mesh"]
	mi.scale = Vector3.ONE   # parts are built in metres by the kernel already (Part records are mm, the replay answers metres)
	parent.add_child(mi)
	return mi


static func _node(parent: Node3D, nm: String) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	parent.add_child(n)
	return n


static func build(parent: Node) -> Dictionary:
	var d := A.design()
	var sc := {"d": d, "wp": N.waypoints(d), "cans": [], "plungers": {}}
	var root := Node3D.new()
	root.name = "Arm"
	parent.add_child(root)
	sc["root"] = root
	var table := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(1.0, 0.02, 0.9)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.86, 0.84, 0.80)
	tm.material = tmat
	table.mesh = tm
	table.position = Vector3(0.05, -0.028, 0.0)
	root.add_child(table)
	_mi(root, PT.baseboard(), "baseboard")
	_mi(root, PT.console(), "console")
	var stand := _mi(root, PT.stand(), "stand")
	stand.position = Vector3(0, 0, float(d["r_pick"])) * MM
	var yaw := _node(root, "yaw")
	_mi(yaw, PT.turntable(), "turntable")
	var sh := _node(yaw, "shoulder")
	sh.position = Vector3(0, float(d["hs"]), 0) * MM
	_mi(sh, PT.upper_arm(), "upper_arm")
	var el := _node(sh, "elbow")
	el.position = Vector3(float(d["L1"]), 0, 0) * MM
	_mi(el, PT.forearm(), "forearm")
	var wr := _node(el, "wrist")
	wr.position = Vector3(float(d["L2"]), 0, 0) * MM
	_mi(wr, PT.gripper_body(), "gripper")
	var jp := _mi(wr, PT.jaw(), "jaw_plus")
	var jm := _mi(wr, PT.jaw(), "jaw_minus")
	jm.scale = Vector3(1, 1, -1)
	sc["nodes"] = {"yaw": yaw, "sh": sh, "el": el, "wr": wr, "jp": jp, "jm": jm}
	# the three lever slaves ride on their carriers: shoulder on the turntable (a frame at the shoulder axis), elbow on the upper arm, wrist on the forearm
	var sh_base := _node(yaw, "shoulder_base")
	sh_base.position = Vector3(0, float(d["hs"]), 0) * MM
	sc["slaves"] = {}
	for j in ["sh", "el", "wr"]:
		var carrier: Node3D = {"sh": sh_base, "el": sh, "wr": el}[j]
		var sz: int = d["cyl"][j][1]
		var lay := A.slave_layout(d, j)
		var b := _mi(carrier, PT.syringe_barrel(sz), "slave_" + j)
		var p := _mi(carrier, PT.syringe_plunger(sz, float(lay["lrod"])), "slave_plunger_" + j)
		sc["slaves"][j] = {"barrel": b, "plunger": p, "lay": lay}
	# the five masters lie on the console, tips at x = -124 pointing +x (the barrel part's tip points -x: turned 180 deg about y)
	for k in AXES.size():
		var j: String = AXES[k]
		var sz: int = d["cyl"][j][0]
		var r: float = float(A.SYR[sz]["bore"]) / 2.0
		var y := 10.0 + r + 1.0
		var z := -80.0 + 40.0 * k
		var bar := _mi(root, PT.syringe_barrel(sz), "master_" + j)
		bar.rotation = Vector3(0, PI, 0)
		bar.position = Vector3(-134.0, y, z) * MM
		var pl := _mi(root, PT.syringe_plunger(sz, A.stroke(sz) + 15.0), "plunger_" + j)
		pl.rotation = Vector3(0, PI, 0)
		sc["plungers"][j] = {"node": pl, "y": y, "z": z}
	var can_rec := PT.can_rec()
	for k in 6:
		var c := _mi(root, can_rec, "can%d" % (k + 1))
		sc["cans"].append(c)
	var cam := Camera3D.new()
	cam.fov = 38.0
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0.95, 0.62, 0.30), Vector3(0.0, 0.17, -0.06), Vector3.UP)
	cam.current = true
	sc["cam"] = cam
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.look_at_from_position(Vector3(0.6, 1.0, 0.5), Vector3(0, 0, 0), Vector3.UP)
	sun.shadow_enabled = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.93, 0.94, 0.96)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	return sc


static func t_end(sc: Dictionary) -> float:
	var wp: Array = sc["wp"]
	return float(wp[wp.size() - 1]["t"])


## the arm and the cans at time t; answers the state
static func pose(sc: Dictionary, t: float) -> Dictionary:
	var d: Dictionary = sc["d"]
	var st := N.state(d, sc["wp"], t)
	var nd: Dictionary = sc["nodes"]
	(nd["yaw"] as Node3D).rotation = Vector3(0, deg_to_rad(st["yaw"]), 0)
	if st.has("th1"):
		(nd["sh"] as Node3D).rotation = Vector3(0, 0, deg_to_rad(st["th1"]))
		(nd["el"] as Node3D).rotation = Vector3(0, 0, deg_to_rad(st["th2"]))
		(nd["wr"] as Node3D).rotation = Vector3(0, 0, deg_to_rad(st["psi"]))
	var inner := 41.1 - float(st["g"])
	(nd["jp"] as Node3D).position = Vector3(0, 0, inner + 2.0) * MM
	(nd["jm"] as Node3D).position = Vector3(0, 0, -(inner + 2.0)) * MM
	if st.has("th1"):
		# slaves: barrel tip at P + u t0 pointing at the pin, the plunger's thumb disc on the pin Q (slave_layout: the stopper then sits lmin..lmax - lmin + 4 inside)
		var ang := {"sh": float(st["th1"]), "el": float(st["th2"]), "wr": float(st["psi"])}
		for j in ["sh", "el", "wr"]:
			var sv: Dictionary = sc["slaves"][j]
			var sl := A.slave_line(d, j, ang[j])
			var P: Vector2 = sl["P"]
			var Q: Vector2 = sl["Q"]
			var u := (Q - P).normalized()
			var bs := Basis(Vector3(0, 0, 1), atan2(u.y, u.x))
			var tip := P + u * float(sv["lay"]["t0"])
			var disc := Q - u * (8.0 + float(sv["lay"]["lrod"]))
			(sv["barrel"] as Node3D).transform = Transform3D(bs, Vector3(tip.x, tip.y, 26.0) * MM)
			(sv["plunger"] as Node3D).transform = Transform3D(bs, Vector3(disc.x, disc.y, 26.0) * MM)
		var sk := N.strokes(d, st)
		for j in AXES:
			var p: Dictionary = sc["plungers"][j]
			(p["node"] as Node3D).position = Vector3(-134.0 - float(sk["master_out"][j]), float(p["y"]), float(p["z"])) * MM
	# cans: placed ones on the pyramid, the held one in the jaws, the next one on the stand, the rest hidden
	var placed := N.placed_at(d, sc["wp"], t)
	if int(st["held"]) < 0 and String(st["label"]).ends_with("released") and placed.size() < 6:
		placed.append(placed.size())   # the jaws are opening on it: it already stands on the stack
	var ps := A.poses(d)
	var held: int = st["held"]
	var nxt := placed.size() if held < 0 else held
	for k in 6:
		var c: MeshInstance3D = sc["cans"][k]
		c.visible = true
		if placed.has(k):
			var tp: Dictionary = ps[k + 1]
			c.global_transform = Transform3D(Basis(), (N.rad_dir(90.0) * float(tp["r"]) + Vector3(0, float(tp["z"]) - A.CAN_H / 2.0, 0)) * MM)
		elif k == held:
			var wpos: Vector3 = (nd["wr"] as Node3D).global_position
			c.global_transform = Transform3D(Basis(), wpos + Vector3(0, -(float(d["dg"]) + A.CAN_H / 2.0), 0) * MM)
		elif k == nxt:
			c.global_transform = Transform3D(Basis(), Vector3(0, 0, float(d["r_pick"])) * MM)
		else:
			c.visible = false
	return st


## the syringe pair section alone, seen square on to the cut face
static func build_section(parent: Node) -> Dictionary:
	var root := Node3D.new()
	root.name = "PairSection"
	parent.add_child(root)
	var mi := _mi(root, PT.pair_section(), "pair")
	var bb: AABB = (mi.mesh as ArrayMesh).get_aabb()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = bb.size.x * 1.05
	root.add_child(cam)
	var c := bb.get_center()
	cam.look_at_from_position(c + Vector3(0, 0, 0.5), c, Vector3.UP)
	cam.current = true
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.look_at_from_position(Vector3(0.3, 0.6, 1.0), Vector3.ZERO, Vector3.UP)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(1, 1, 1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 0.9)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	return {"root": root, "cam": cam}
