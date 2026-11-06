## lock_fixtures.gd - two-body lock clips for N041 (lock_truth.gd), built with the real tools like throw_fixtures.gd: Body poses from poses/stand.json,
## the partner's arm held out in front of him, the locker's hands put on that arm by Body.reach, a two-actor Scene (Scene.actors + xf).
## Layout: the locker (hero) stands at the origin facing +z; the partner stands DIST in front of him at yaw 180, facing him.
## The GEOMETRY of a clip is what Body can do (angles clamped to the limits); the DEMAND is the raw angle the partner's cards carry (set after the
## pose is made, so it may lie past his limit). Nothing is typed in as a verdict: the judge reads the demand and the touching.
## kinds: "armbar" (juji-gatame: the arm straight, one hand on the wrist, one at the elbow; the elbow is asked `elbow` deg, default -12 = hyperextended),
## "armbar_light" (the same grip, elbow asked 40), "wristlock" (kote-gaeshi: forearm up, the hand asked `wrist` deg of flexion, default 67),
## "kimura" (the bent arm, the upper arm asked to roll `roll` deg, default 85), "apart" (the armbar 3 m away), "sweep" (hands at the elbow, the elbow
## ask goes `from` -> `to`, default 45 -> -15). opts: "arm" "r" | "l" (the partner's arm), "dist".
class_name LockFixtures
extends RefCounted

const FPS := ThrowFixtures.FPS
const MOVE_T := 0.5
const HOLD_T := 0.3


static func _put(b: Body, j: String, bend: float, side := 0.0, twist := 0.0) -> void:
	b.ang[j] = b.clamp_ang(j, Vector3(bend, side, twist))


static func _reach(h: Body, tip: String, tgt: Vector3) -> float:
	h.reach(tip, tgt)
	return ((h.P[tip] as Vector3) - tgt).length()


static func _with(pose: Dictionary, joint: String, axis: String, v: float) -> Dictionary:
	var p: Dictionary = pose.duplicate(true)
	p["joints"][joint][axis] = v
	return p


static func build(kind: String, opts := {}) -> Scene:
	var sfx := "_" + String(opts.get("arm", "r"))
	var d: float = float(opts.get("dist", ThrowFixtures.DIST)) + (3.0 if kind == "apart" else 0.0)
	var el := "lowerarm" + sfx
	var ua := "upperarm" + sfx
	var hd := "hand" + sfx
	# the demand (raw) and the geometry (clamped) of the partner's arm
	var elbow_geo := 0.0
	var demand_joint := el
	var demand_axis := "bend"
	var from_v := 0.0
	var to_v := 0.0
	match kind:
		"armbar", "apart":
			to_v = float(opts.get("elbow", -12.0))
			from_v = to_v
			elbow_geo = maxf(to_v, 0.0)
		"armbar_light":
			to_v = float(opts.get("elbow", 40.0))
			from_v = to_v
			elbow_geo = to_v
		"wristlock":
			demand_joint = hd
			to_v = float(opts.get("wrist", 67.0))
			from_v = to_v
			elbow_geo = 90.0
		"kimura":
			demand_joint = ua
			demand_axis = "twist"
			to_v = float(opts.get("roll", 85.0))
			from_v = to_v
			elbow_geo = 90.0
		"sweep":
			from_v = float(opts.get("from", 45.0))
			to_v = float(opts.get("to", -15.0))
	var P := ThrowFixtures.stand()
	_put(P, ua, 90.0)
	_put(P, el, elbow_geo)
	if kind == "wristlock":
		_put(P, hd, to_v)
	if kind == "kimura":
		_put(P, ua, 90.0, 0.0, to_v)
	P.fk()
	var X := ThrowFixtures.xf_of(d)
	var wrist: Vector3 = X * (P.P[hd] as Vector3)
	var elbow: Vector3 = X * (P.P[el] as Vector3)
	var mid: Vector3 = X * (((P.P[ua] as Vector3) + (P.P[el] as Vector3)) * 0.5)
	var H := ThrowFixtures.stand()
	# the partner's right arm is the locker's left (+x): his left hand takes the wrist, the right the elbow; the left arm swaps them
	var ha := "hand_l" if sfx == "_r" else "hand_r"
	var hb := "hand_r" if sfx == "_r" else "hand_l"
	var miss := 0.0
	if kind == "sweep":
		miss = maxf(_reach(H, ha, mid), _reach(H, hb, elbow))
	else:
		miss = maxf(_reach(H, ha, wrist), _reach(H, hb, elbow))
	H.fk()
	var pose0: Dictionary = P.to_dict()
	var pose1: Dictionary = pose0
	var pa: Dictionary = _with(pose0, demand_joint, demand_axis, from_v)
	var pb: Dictionary = _with(pose0, demand_joint, demand_axis, to_v)
	var mv: float = 2.0 if kind == "sweep" else MOVE_T
	var hp: Dictionary = H.to_dict()
	var hero := ThrowFixtures.scene_of("n041_" + kind, [ThrowFixtures.card("grip", hp, -1.0, HOLD_T), ThrowFixtures.card("lock", hp, mv, HOLD_T)])
	var part := ThrowFixtures.scene_of("n041_" + kind + "_partner", [ThrowFixtures.card("grip", pa, -1.0, HOLD_T), ThrowFixtures.card("lock", pb, mv, HOLD_T)])
	hero["actors"] = [{"name": "partner", "xf": {"pos": [0.0, d], "yaw": 180.0}, "scene": part}]
	var S := Scene.new()
	S.from_dict(hero)
	S.set_meta("miss", miss)
	return S
