## hit_physics.gd - I2 (ROADMAP Innovations): THE HIT DECIDES THE REACTION. When the attacker's weapon or fist touches the other
## fighter (the contact the Check's CONTACT label and R16's picker already find: a row of Dummy.fighter_hits), Kine computes the blow
## itself and has the MuJoCo humanoid (tools/physics/react.py = sim.py's stance PD + balance + stepping) react to it:
##   WHERE   the struck body part (the row's "on"), mapped to the MuJoCo body that carries it;
##   DIRECTION the striking spot's velocity relative to the struck spot's own animated velocity, in the struck fighter's body space
##             (the push, as an angle in the floor plane: sim.Humanoid.hit's dir_deg, 0 = forward, 90 = his left);
##   IMPULSE J = m_eff x v_rel (kg m/s = N s). m_eff:
##     a weapon: the rod's effective mass at the contact about the grip (HitReaction.strike_mass: I_grip / d^2) plus a QUARTER of the two hands'
##       mass (the grip couples the hands for the impact; Nathan 2000, Am J Phys 68:979 finds the hands decoupled from a bat within about
##       1 ms, so the arms add little: a quarter is a guess between decoupled (0) and rigid (1)). At combo3's swing that is 0.71 kg: the
##       swing.py duel (tools/physics/measure_swing.py) measures impulse / speed = 0.80-1.10 kg on four bat swings (reported by the test);
##     a fist (hand or forearm): 2.9 kg effective striking mass of a boxer's punch (Walilko, Viano & Bir 2005, Br J Sports Med 39:710),
##       scaled by the striker's mass / 75 kg (their Olympic boxers); other limbs and the head: HitReaction's limb mass.
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
const HAND_SHARE := 0.25    # of the two hands' mass that rides with a weapon's impact (see the header). Measured by tests/i2_test.gd on combo3's swing: rod 0.29 + 0.25 hands = 0.71 kg, 11 % under swing.py's lowest J / v (0.80 kg); a share of ~0.36 would sit at its mean (0.9 kg): NOT tuned, the test's bar 2 reports the gap


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


## the striking mass (kg) of this hit's striker, with the rule of the header
static func strike_mass(hit: Dictionary, Bs: Body) -> float:
	var part: String = hit["part"]
	if Body.is_wep(part):
		return HitReaction.strike_mass(hit, Bs) + HAND_SHARE * float(HitReaction.masses_kg(Bs)["hand"])
	if part.begins_with("hand") or part.begins_with("lowerarm"):
		return FIST_KG * body_kg(Bs) / REF_KG
	return HitReaction.strike_mass(hit, Bs)


## the blow, in the struck fighter's body space. S = its scene, B its body (posed by the scene; put back), xf its place in the hero's
## space, hit = a Dummy.fighter_hits row, Bs = the striker's body. {"ok", "why", "J" (Vector3 N s, body space), "m_eff", "v_rel" (m/s,
## the speed along the push), "body" (MuJoCo), "dir_deg", "J_h" (the floor-plane part, N s), "t", "pose" (the struck fighter's pose
## dict at the contact), "offset" (its pelvis offset there)}
static func measure(S: Scene, B: Body, xf: Transform3D, hit: Dictionary, Bs: Body) -> Dictionary:
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
	var m_eff := strike_mass(hit, Bs)
	var J: Vector3 = xf.basis.inverse() * (v_rel * m_eff)
	B.set_state(keep)
	var Jh := Vector2(J.x, J.z)
	return {"ok": true, "why": "", "J": J, "m_eff": m_eff, "v_rel": v_rel.length(), "body": sim_body(on), "dir_deg": rad_to_deg(atan2(J.x, J.z)),
		"J_h": Jh.length(), "t": t_hit, "pose": pose, "offset": off}


## run the sim for a measured blow. Blocking (a few seconds): call it on a worker. {"ok", "why", "bvh", "report" (react.py's)}
static func simulate(blow: Dictionary, tag := "hit") -> Dictionary:
	DirAccess.make_dir_recursive_absolute(DIR)
	var base := ProjectSettings.globalize_path(DIR) + "/" + tag
	var job := {"pose": blow["pose"], "body": blow["body"], "J": snappedf(float(blow["J_h"]), 0.0001), "dir_deg": snappedf(float(blow["dir_deg"]), 0.01),
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
	return "J %.1f N s = %.2f kg x %.1f m/s · %s · %s %d° · %s" % [float(b["J_h"]), float(b["m_eff"]), float(b["v_rel"]), String(b["body"]).replace("_", " "),
		inf["strength"], roundi(float(inf["peak"])), "FELL" if inf["fell"] else "stayed up"]
