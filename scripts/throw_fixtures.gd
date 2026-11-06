## throw_fixtures.gd - two-body throw clips for N040 (throw_truth.gd), built with the real tools: Body poses from poses/stand.json, a lean about the
## ankles (pelvis bend with both feet re-planted on their marks by Body.plant), arms put on the partner by Body.reach, and a two-actor Scene
## (Scene.actors + xf). Nothing is typed in as a result: the judge reads whatever these poses do.
## Layout: the thrower (hero) stands at the origin facing +z; the partner stands DIST in front of him at yaw 180, facing him.
class_name ThrowFixtures
extends RefCounted

const FPS := 30
const DIST := 0.80          # m between their feet marks
const PULL_BACK := -30.0    # deg: the partner tipped backward about his ankles (osoto-gari kuzushi)
const THROWER_LEAN := 15.0  # deg: the thrower leans in about his ankles
const OVER_LEAN := 30.0     # deg: the overcommitted thrower's lean ...
const OVER_SHIFT := 0.30    # ... with his feet this far behind his hips (m)
const STEP_IN := 0.20       # m: the thrower steps in as he pulls (his whole body, feet included)
const MOVE_T := 0.5         # s: the off-balancing move
const HOLD_T := 0.3


static func stand() -> Body:
	var b := ThrowTruth.new_body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b


## a lean about the ankles: the pelvis tips by `pel` (+ forward), the spine by `sp`, both feet re-planted `back` m behind their marks
static func lean(b: Body, pel: float, sp := 0.0, back := 0.0) -> void:
	var bl: Vector3 = b.P["ball_l"]
	var br: Vector3 = b.P["ball_r"]
	b.ang["pelvis"] = Vector3(pel, 0, 0)
	b.ang["spine_01"] = Vector3(sp, 0, 0)
	b.fk()
	var sh := Vector3(0, 0, -back)
	b.plant("_l", bl + sh, 0.0, true)
	b.plant("_r", br + sh, 0.0, true)
	b.fk()


## REFERENCE (peer reviewed): Imamura RT, Hreljac A, Escamilla RF, Edwards WB (2006) "A three-dimensional analysis of the center of mass for three
## different judo throwing techniques", J Sports Sci Med 5(CSSI):122-131, https://jssm.org/jssm-05-CSSI1-122.xml-Fulltext . Harai-goshi, uke's
## whole-body COM linear momentum, forward, kuzushi phase: 20.6 kg m/s (tsukuri 52.6, kake 4.6). Four black belts as tori.
## ASSUMPTION (stated): the table value is read as the MEAN momentum over the phase, and the partner's mass is the model's own (de Leva).
const IMAMURA_KUZUSHI := 20.6   # kg m/s


static func mass_of(b: Body) -> float:
	var m := 0.0
	for p in HitReaction.pieces(b):
		m += float(p["m"])
	return m


## the forward lean (deg, about the ankles, feet re-planted) whose COM travel in `t` seconds gives a mean momentum of IMAMURA_KUZUSHI
static func imamura_angle(t: float) -> float:
	var b0 := stand()
	var want := IMAMURA_KUZUSHI * t / mass_of(b0)
	var z0 := Balance.com(b0).z
	var lo := 0.0
	var hi := 60.0
	for i in 22:
		var mid := 0.5 * (lo + hi)
		var b := stand()
		lean(b, mid)
		if Balance.com(b).z - z0 < want:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


static func xf_of(d: float, yaw := 180.0) -> Transform3D:
	return Constraints.actor_xf({"pos": [0.0, d], "yaw": yaw})


## the partner's two lapel points (the chest's front, left and right of the breastbone) in the thrower's space
static func lapels(p: Body, d: float) -> Array:
	var X := xf_of(d)
	var c: Vector3 = p.P["spine_03"]
	var out := []
	for sx in [-1.0, 1.0]:
		out.append(X * (c + Vector3(0.11 * sx, 0.04, 0.20)))
	return out


## put both hands of the thrower on the partner's lapels; returns the larger miss (m)
static func grip(h: Body, targets: Array) -> float:
	var miss := 0.0
	for k in 2:
		var tip: String = "hand_l" if k == 0 else "hand_r"   # partner-local -x is the thrower's +x (his left): the yaw 180 mirrors them
		var tgt: Vector3 = targets[0] if k == 0 else targets[1]
		h.reach(tip, tgt)
		miss = maxf(miss, ((h.P[tip] as Vector3) - tgt).length())
	h.fk()
	return miss


static func card(name: String, pose: Dictionary, move: float, hold: float) -> Dictionary:
	return {"name": name, "pose": pose, "move": move, "hold": hold}


static func scene_of(name: String, cards: Array) -> Dictionary:
	return {"scene": name, "fps": FPS, "natural": false, "on_floor": false, "pin": false, "cards": cards}


## kinds: "osoto" (kuzushi works), "no_kuzushi" (same thrower, partner not pulled), "overcommit" (partner pulled, thrower throws himself),
## "apart" (the same clip with the partner 3 m further), "imamura" (partner pulled forward at the momentum Imamura et al. 2006 measured)
## opts: "dist" (m), "pull" (deg), "move" (s), "shift" (m, the overcommitted thrower's feet behind his hips)
static func build(kind: String, opts := {}) -> Scene:
	var d: float = opts.get("dist", DIST) + (3.0 if kind == "apart" else 0.0)
	var mv: float = opts.get("move", MOVE_T)
	var pull: float = opts.get("pull", PULL_BACK)
	# --- cards 0: both stand, hands on the lapels
	var P0 := stand()
	var H0 := stand()
	lean(H0, THROWER_LEAN)
	var miss0 := grip(H0, lapels(P0, d))
	# --- card 1: the off-balancing
	var P1 := stand()
	var H1 := stand()
	match kind:
		"no_kuzushi":
			pass
		"imamura":
			lean(P1, imamura_angle(mv))
		_:
			lean(P1, pull)
	match kind:
		"overcommit":
			H1.offset.z += STEP_IN
			H1.fk()
			lean(H1, OVER_LEAN, 0.0, float(opts.get("shift", OVER_SHIFT)))
		"imamura":
			lean(H1, -5.0)
		_:
			H1.offset.z += STEP_IN
			H1.fk()
			lean(H1, THROWER_LEAN)
	# the hands follow the lapels the partner's pose at card 1 puts them at (the A clip's hands, also in the no-kuzushi clip: the same thrower)
	var Pa := stand()
	if kind == "no_kuzushi":
		lean(Pa, pull)
	elif kind == "imamura":
		lean(Pa, imamura_angle(mv))
	else:
		lean(Pa, pull)
	var miss1 := grip(H1, lapels(Pa, d))
	var hero := scene_of("n040_" + kind, [card("grip", H0.to_dict(), -1.0, HOLD_T), card("off-balance", H1.to_dict(), mv, HOLD_T)])
	var part := scene_of("n040_" + kind + "_partner", [card("grip", P0.to_dict(), -1.0, HOLD_T), card("off-balance", P1.to_dict(), mv, HOLD_T)])
	hero["actors"] = [{"name": "partner", "xf": {"pos": [0.0, d], "yaw": 180.0}, "scene": part}]
	var S := Scene.new()
	S.from_dict(hero)
	S.set_meta("miss", [miss0, miss1])
	return S
