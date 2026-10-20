## hit_physics.gd - I2 (ROADMAP Innovations): THE HIT DECIDES THE REACTION. When the attacker's weapon or fist touches the other
## fighter (the contact the Check's CONTACT label and R16's picker already find: a row of Dummy.fighter_hits), Kine computes the blow
## itself and has the MuJoCo humanoid (tools/physics/react.py = sim.py's stance PD + balance + stepping) react to it:
##   WHERE   the struck body part (the row's "on"), mapped to the MuJoCo body that carries it;
##   DIRECTION the striking spot's velocity relative to the struck spot's own animated velocity, in the struck fighter's body space
##             (the push, as an angle in the floor plane: sim.Humanoid.hit's dir_deg, 0 = forward, 90 = his left);
##   IMPULSE J = (1 + e) x mu x v_rel, mu = m_eff M / (m_eff + M) the reduced mass of the striker (m_eff) and the struck part (M: the
##     head, the trunk, a limb's segments), e the restitution (RESTITUTION). m_eff:
##     a weapon: the effective mass of the bat + the arm that holds it, at the contact, from the striker's pose there (arm_mass; the strike point is the hit's u along the bat): the bat
##       (mass, COM, radius of gyration of Body.KINDS), hand, forearm and upper arm as rigid pieces on free joints (shoulder = the fixed
##       end, the trunk being 15+ times heavier; elbow and wrist free), m_eff = 1 / (j M^-1 j^T) for the strike point's velocity along the
##       blow (j its Jacobian, M the chain's mass matrix): the operational-space mass of Khatib 1987 (IEEE J Robotics & Automation 3:43).
##       With the arm taken away it is Cross's effective mass of a bat at the impact point, 1 / (1/m + d^2/I_cm) (Cross 1999, Am J Phys
##       67:692); the arm adds the more the straighter it lies along the blow, which is why a faster, more extended swing meets a heavier
##       bat (swing.py: J / v rises 0.80 -> 1.10 kg with the swing speed). Free joints: Nathan 2000 (Am J Phys 68:979) finds the hands
##       decoupled from a bat within about 1 ms of the impact. Nothing is fitted to swing.py; the test prints the 4-speed comparison;
##     a fist (hand or forearm): 2.9 kg effective striking mass of a boxer's punch (Walilko, Viano & Bir 2005, Br J Sports Med 39:710),
##       scaled by the striker's mass / 75 kg (their Olympic boxers); other limbs and the head: HitReaction's limb mass.
##   The impulse is the full 3D vector: react.py applies its vertical part too (an uppercut lifts, a chop pushes down) and starts the
##   fighter with the root yaw and lean (the pelvis's orientation) it has at the contact.
## The sim is started from the STRUCK fighter's pose at the contact and run for SECS; its BVH becomes key cards by R15's importer
## (PhysImport), the root travel kept and shifted to where the fighter stands, and the cards go onto the struck fighter from the
## contact by ReactionPicker.insert (R16's insertion). Strength is R16's label (ReactionPicker.describe: light / medium / hard, fell).
## Everything here runs on any thread (no node): the app calls work() on the R13 worker. Files: only user://i2/ (the job, the
## stance scene, the sim's BVH and report).
class_name HitPhysics
extends RefCounted

const SCRIPT := "res://tools/physics/react.py"
const DIR := "user://i2"
const SECS := 1.6
const SETTLE := 0.3
const FIST_KG := 2.9        # Walilko, Viano & Bir 2005 (Olympic boxers): effective striking mass of a punch, at 75 kg
const REF_KG := 75.0
const RESTITUTION := 0.16   # e of the blow: exp(-pi z / sqrt(1 - z^2)) at the damping ratio z = 0.5 of swing.py's contact (the sim this is checked against); soft tissue is in this range (assumed, not measured)
const AXIAL := 0.1          # a thin rod's spin about its own axis, as a share of its inertia across it: keeps the mass matrix invertible (moves no strike mass by more than a percent)


## the MuJoCo body that carries a struck part: its joint, a finger -> the hand, the toe -> the foot
static func sim_body(on: String) -> String:
	var j := HitReaction.joint_of(on)
	if j.begins_with("ball"):
		return "foot" + j.substr(4)
	for f in ["thumb", "index", "middle", "ring", "pinky"]:
		if j.begins_with(f):
			return "hand" + (j.substr(j.length() - 2) if j.ends_with("_l") or j.ends_with("_r") else "_r")
	return j


static func body_kg(Bs: Body) -> float:
	return float(Bs.body.get("mass", HumanLimits.REF_MASS))


## the striking mass (kg) of this hit's striker, with the rule of the header. `dir` = the unit direction of the blow (hero space), used
## for a weapon (the arm's mass depends on how it lies along it); the striker Bs must be posed at the contact
static func strike_mass(hit: Dictionary, Bs: Body, dir := Vector3.ZERO) -> float:
	var part: String = hit["part"]
	if Body.is_wep(part):
		if dir.length() < 0.5 or Bs.wep_hand == "" or not Bs.wep_on:
			return HitReaction.strike_mass(hit, Bs)
		return arm_mass(Bs, Bs.wep_point(float(hit["u"])), dir.normalized())
	if part.begins_with("hand") or part.begins_with("lowerarm"):
		return FIST_KG * body_kg(Bs) / REF_KG
	return HitReaction.strike_mass(hit, Bs)


## the mass the struck part presents: the head, the trunk (any spine joint), or the limb's segments
static func struck_mass(on: String, B: Body) -> float:
	var mm := HitReaction.masses_kg(B)
	var j := HitReaction.joint_of(on)
	if j.begins_with("head") or j.begins_with("neck"):
		return float(mm["head"])
	if j.begins_with("spine") or j == "pelvis" or j.begins_with("clavicle"):
		return float(mm["trunk"])
	return HitReaction.strike_mass({"part": j, "u": 0.0}, B)


## velocity of a point p riding on link lk (0 upper arm, 1 forearm, 2 hand + bat) for a unit generalised velocity k (9: the shoulder's
## angular velocity, the elbow's and the wrist's relative to their parents)
static func _vel(k: int, p: Vector3, lk: int, S: Vector3, E: Vector3, W: Vector3) -> Vector3:
	var w := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var e := Vector3.ZERO
	e[k % 3] = 1.0
	w[k / 3] = e
	var w0: Vector3 = w[0]
	var w1: Vector3 = w0 + (w[1] as Vector3)
	var w2: Vector3 = w1 + (w[2] as Vector3)
	if lk == 0:
		return w0.cross(p - S)
	if lk == 1:
		return w0.cross(E - S) + w1.cross(p - E)
	return w0.cross(E - S) + w1.cross(W - E) + w2.cross(p - W)


static func _spin(k: int, lk: int) -> Vector3:
	var e := Vector3.ZERO
	if k / 3 <= lk:
		e[k % 3] = 1.0
	return e


## the effective mass (kg) at the world point `at` along unit `n` of the bat + the arm that holds it (see the header); Bs posed at the contact
static func arm_mass(Bs: Body, at: Vector3, n: Vector3) -> float:
	var sd := String(Bs.wep_hand).right(2)   # "_r" / "_l"
	var mm := HitReaction.masses_kg(Bs)
	var S: Vector3 = Bs.P["upperarm" + sd]
	var E: Vector3 = Bs.P["lowerarm" + sd]
	var W: Vector3 = Bs.P[Bs.wep_hand]
	var xw := Bs.wep_xform()
	var ax: Vector3 = (xw[1] as Quaternion) * Vector3(0, 1, 0)
	var kd: Dictionary = Body.KINDS[Bs.wep_kind]
	var Lw: float = Bs.wep_len
	var m_b: float = float(HitReaction.WEAPON_KG.get(Bs.wep_kind, 0.9))
	var Cb: Vector3 = (xw[0] as Vector3) + ax * (float(kd["com"]) * Lw)
	var kb: float = float(kd["k"]) * Lw
	# rigid pieces: [mass, COM, rod axis, inertia across the rod about its COM, link]
	var pcs := []
	var t_ua: float = float((Proportions.DE_LEVA[String(Bs.body.get("sex", "male"))] as Dictionary)["upper_arm"][1])
	var t_fa: float = float((Proportions.DE_LEVA[String(Bs.body.get("sex", "male"))] as Dictionary)["forearm"][1])
	var sx := String(Bs.body.get("sex", "male"))
	for r in [[float(mm["upper_arm"]) / 2.0, S, E, 0, t_ua, "upper_arm"], [float(mm["forearm"]) / 2.0, E, W, 1, t_fa, "forearm"]]:
		var a0: Vector3 = r[1]
		var a1: Vector3 = r[2]
		var L := a1.distance_to(a0)
		var m: float = r[0]
		pcs.append([m, a0.lerp(a1, float(r[4])), (a1 - a0) / maxf(L, 1e-6), m * pow(Proportions.kperp(sx, String(r[5])) * L, 2.0), int(r[3])])
	var mh: float = float(mm["hand"]) / 2.0
	var Lh: float = ((Bs.E["hand" + sd] as Vector3) - W).length()   # de Leva: radius across the hand x its length (wrist -> 3rd metacarpale)
	pcs.append([mh, W, ax, mh * pow(Proportions.kperp(sx, "hand") * Lh, 2.0), 2])
	pcs.append([m_b, Cb, ax, m_b * kb * kb, 2])
	var M: Array = []
	for a in 9:
		M.append(PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0]))
	for pc in pcs:
		var lk: int = pc[4]
		var u: Vector3 = pc[2]
		var Ip: float = pc[3]
		for a in 9:
			var va := _vel(a, pc[1], lk, S, E, W)
			for b in 9:
				var vb := _vel(b, pc[1], lk, S, E, W)
				var wb := _spin(b, lk)
				var Iw: Vector3 = (wb - u * u.dot(wb)) * Ip + u * u.dot(wb) * (AXIAL * Ip)
				M[a][b] += float(pc[0]) * va.dot(vb) + _spin(a, lk).dot(Iw)
	var A: Array = []
	for a in 9:
		var row := PackedFloat64Array(M[a])
		row.append(n.dot(_vel(a, at, 2, S, E, W)))
		A.append(row)
	var jv := PackedFloat64Array()
	for a in 9:
		jv.append(A[a][9])
	for c in 9:
		var piv := c
		for r in range(c + 1, 9):
			if absf(A[r][c]) > absf(A[piv][c]):
				piv = r
		var tmp: PackedFloat64Array = A[c]
		A[c] = A[piv]
		A[piv] = tmp
		var d: float = A[c][c]
		if absf(d) < 1e-12:
			return HitReaction.strike_mass({"part": "bat_barrel", "u": 0.6}, Bs)
		for r in range(c + 1, 9):
			var f: float = A[r][c] / d
			for q in range(c, 10):
				A[r][q] -= f * A[c][q]
	var x := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
	for r in range(8, -1, -1):
		var sm: float = A[r][9]
		for q in range(r + 1, 9):
			sm -= A[r][q] * x[q]
		x[r] = sm / A[r][r]
	var jx := 0.0
	for a in 9:
		jx += jv[a] * x[a]
	return 1.0 / maxf(jx, 1e-9)


## the blow, in the struck fighter's body space. S = its scene, B its body (posed by the scene; put back), xf its place in the hero's
## space, hit = a Dummy.fighter_hits row, Bs = the striker's body. {"ok", "why", "J" (Vector3 N s, body space), "m_eff", "v_rel" (m/s,
## the speed along the push), "body" (MuJoCo), "dir_deg", "J_h" (the floor-plane part, N s), "t", "pose" (the struck fighter's pose
## dict at the contact), "offset" (its pelvis offset there), "M_struck" and "mu" (kg), "J_v" (the vertical part, N s, + up).
## Ss = the striker's scene: given, its body Bs is posed at the contact for the arm's mass (put back); the striker's space is the hero's.
static func measure(S: Scene, B: Body, xf: Transform3D, hit: Dictionary, Bs: Body, Ss: Scene = null) -> Dictionary:
	var keep := B.state()
	var on: String = hit["on"]
	if Body.is_wep(on) or not B.parent.has(HitReaction.joint_of(on)):
		return {"ok": false, "why": "the struck part %s is not a body part" % on}
	var jh := HitReaction.joint_of(on)
	var t_hit: float = hit["t"]
	S.apply(B, t_hit)
	var P0: Dictionary = B.P.duplicate()
	var G0: Dictionary = B.G.duplicate()
	var pose := B.to_dict()
	var off := Vector3(B.offset)
	var pv: Vector3 = xf.affine_inverse() * (hit["at"] as Vector3)
	var lp: Vector3 = (G0[jh] as Quaternion).inverse() * (pv - (P0[jh] as Vector3))
	var h1 := 1.0 / HitReaction.SIM_HZ
	S.apply(B, maxf(0.0, t_hit - h1))
	var before: Vector3 = (B.P[jh] as Vector3) + (B.G[jh] as Quaternion) * lp
	var now: Vector3 = (P0[jh] as Vector3) + (G0[jh] as Quaternion) * lp
	var v_struck: Vector3 = (now - before) / h1
	var v_rel: Vector3 = (hit["vec"] as Vector3) - xf.basis * v_struck
	var keep_s := {}
	if Ss != null and Body.is_wep(String(hit["part"])):
		keep_s = Bs.state()
		Ss.apply(Bs, t_hit)
	var m_eff := strike_mass(hit, Bs, v_rel)
	if not keep_s.is_empty():
		Bs.set_state(keep_s)
	var M_t := struck_mass(on, B)
	var mu := m_eff * M_t / (m_eff + M_t)
	var J: Vector3 = xf.basis.inverse() * (v_rel * ((1.0 + RESTITUTION) * mu))
	B.set_state(keep)
	var Jh := Vector2(J.x, J.z)
	return {"ok": true, "why": "", "J": J, "m_eff": m_eff, "v_rel": v_rel.length(), "body": sim_body(on), "dir_deg": rad_to_deg(atan2(J.x, J.z)),
		"J_h": Jh.length(), "J_v": J.y, "M_struck": M_t, "mu": mu, "m_blow": (1.0 + RESTITUTION) * mu, "t": t_hit, "pose": pose, "offset": off}


## run the sim for a measured blow. Blocking (a few seconds): call it on a worker. {"ok", "why", "bvh", "report" (react.py's)}
static func simulate(blow: Dictionary, tag := "hit") -> Dictionary:
	DirAccess.make_dir_recursive_absolute(DIR)
	var base := ProjectSettings.globalize_path(DIR) + "/" + tag
	var job := {"pose": blow["pose"], "body": blow["body"], "J": snappedf(float(blow["J_h"]), 0.0001), "J_v": snappedf(float(blow["J_v"]), 0.0001), "dir_deg": snappedf(float(blow["dir_deg"]), 0.01),
		"secs": SECS, "settle": SETTLE, "out_bvh": base + ".bvh", "out_report": base + "_report.json", "scene_path": base + "_pose.json"}
	var jp := base + "_job.json"
	var f := FileAccess.open(jp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "why": "cannot write %s" % jp}
	f.store_string(JSON.stringify(job))
	f.close()
	DirAccess.remove_absolute(job["out_report"])
	var out := []
	var code := OS.execute("python", [ProjectSettings.globalize_path(SCRIPT), jp], out, true)
	if code != 0 or not FileAccess.file_exists(job["out_report"]):
		return {"ok": false, "why": "python tools/physics/react.py failed (exit %d): %s" % [code, String(out[0] if not out.is_empty() else "").strip_edges().right(300)]}
	var rep: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(job["out_report"]))
	return {"ok": true, "why": "", "bvh": job["out_bvh"], "report": rep}


## the sim's BVH as a clip (R15's importer) with the root put where the struck fighter stands. Bw is the worker's own Body.
## {"ok", "why", "clip": Scene, "text"}
static func clip_of(sim_out: Dictionary, blow: Dictionary, Bw: Body, name := "i2_hit") -> Dictionary:
	var r := PhysImport.import_file(String(sim_out["bvh"]), Bw, name)
	if not r["ok"]:
		return {"ok": false, "why": String(r["why"])}
	var clip: Scene = r["scene"]
	var o0: Array = clip.cards[0]["pose"]["offset"]
	var off: Vector3 = blow["offset"]
	var dx: float = off.x - float(o0[0])
	var dz: float = off.z - float(o0[2])
	for c in clip.cards:
		var o: Array = c["pose"]["offset"]
		c["pose"]["offset"] = [float(o[0]) + dx, float(o[1]), float(o[2]) + dz]
	return {"ok": true, "why": "", "clip": clip, "text": String(r["text"])}


## the whole job for the worker: sim, import. {"ok", "why", "clip", "blow", "report", "info" (ReactionPicker.describe), "text"}
static func work(blow: Dictionary, Bw: Body, tag := "hit") -> Dictionary:
	var s := simulate(blow, tag)
	if not s["ok"]:
		return s
	var c := clip_of(s, blow, Bw)
	if not c["ok"]:
		return c
	var info := ReactionPicker.describe(c["clip"])
	return {"ok": true, "why": "", "clip": c["clip"], "blow": blow, "report": s["report"], "info": info, "text": c["text"]}


## the label for the view / status line
static func label(res: Dictionary) -> String:
	var b: Dictionary = res["blow"]
	var inf: Dictionary = res["info"]
	return "J %.1f N s = %.2f kg x %.1f m/s · %s · %s %d° · %s" % [float(b["J_h"]), float(b["m_blow"]), float(b["v_rel"]), String(b["body"]).replace("_", " "),
		inf["strength"], roundi(float(inf["peak"])), "FELL" if inf["fell"] else "stayed up"]
