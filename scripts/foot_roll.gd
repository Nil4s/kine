## foot_roll.gd - ONE control value per foot (round 42, GATES XX5, UPGRADES #270). The reverse-foot rig of Maya and
## Blender, on this skeleton: roll in degrees, 0 = the pose as it is.
##   roll < 0   the HEEL is the pivot: the foot rocks back, toes up (heel strike)
##   0 < roll <= BREAK   the BALL (the toe joint) is the pivot: the heel rises, the toes stay flat on the floor, so the
##              toe joint extends by exactly the roll (push-off)
##   roll > BREAK   the toe TIP is the pivot: past the break angle the toes lift and the foot goes up onto the tip
## The pivot point stays where it is in the world (1 mm bar): the pelvis does not move, the hip and knee follow
## (Body.reach puts the ankle where the turned foot needs it), so the leg must have a bent knee to give: a straight leg
## cannot lift its ankle (the miss is reported, never hidden). Ankle and toe go through the joint limits (ankle -45
## .. 25, toe -30 .. 60); a clamped joint cannot turn the whole way, so the pivot is held by moving the ankle instead.
## The skeleton HAS a toe joint ("ball_l/r", the toe base, with the toe tip as its end point), so the toe extends.
## The heel point is the sole under the ankle joint (ankle height at rest, straight down in the foot's own frame): the
## body's own measure of the heel (Body.sole_low).
## roll 0 returns before touching anything, so the pose is the same bit for bit.
class_name FootRoll
extends RefCounted

const BREAK := 55.0   # deg of roll where the toes leave the floor: the toe extension stops here and the tip takes over
                      # (real push-off: first MTP extension about 44 +- 5 walking (Miana 2021), 65 needed (Hopson 1995))


## the world axis about which a positive turn is "toes up" (the ankle's bend axis in the world), and the angle sign
static func _up_axis(B: Body, sd: String) -> Vector3:
	var q: Quaternion = B.compose("foot" + sd, Vector3(1, 0, 0))
	var gp: Quaternion = B.G[B.parent["foot" + sd]]
	return (gp * q.get_axis()).normalized() if q.get_angle() > 0.0 else Vector3.RIGHT


## the heel point (sole under the ankle) and the pivot a roll value names
static func heel_point(B: Body, sd: String) -> Vector3:
	return (B.P["foot" + sd] as Vector3) + (B.G["foot" + sd] as Quaternion) * Vector3(0, -(B.p0["foot" + sd] as Vector3).y, 0)


static func pivot_of(B: Body, sd: String, roll: float) -> Vector3:
	if roll < 0.0:
		return heel_point(B, sd)
	if roll <= BREAK:
		return B.P["ball" + sd]
	return B.E["ball" + sd]


## set the foot, ankle and toe for `roll` on side sd ("_l" / "_r"). Returns {"pivot": the point (Vector3), "err": how far
## it moved (m), "ankle": bend, "toe": bend, "miss": the ankle's reach miss (m)}; {} for roll 0 (nothing touched).
static func apply(B: Body, sd: String, roll: float) -> Dictionary:
	if roll == 0.0:
		return {}
	var foot := "foot" + sd
	var ball := "ball" + sd
	var ax := _up_axis(B, sd)
	var pv := pivot_of(B, sd, roll)
	var A: Vector3 = B.P[foot]
	var gf: Quaternion = B.G[foot]
	var gb: Quaternion = B.G[ball]
	var gf_t: Quaternion
	var gb_t: Quaternion
	var a_t: Vector3
	if roll < 0.0:
		var r := Quaternion(ax, deg_to_rad(-roll))
		a_t = pv + r * (A - pv)
		gf_t = r * gf
		gb_t = r * gb
	else:
		var r1 := Quaternion(ax, -deg_to_rad(minf(roll, BREAK)))
		a_t = pv + r1 * (A - pv)
		gf_t = r1 * gf
		gb_t = gb
		if roll > BREAK:
			var r2 := Quaternion(ax, -deg_to_rad(roll - BREAK))
			a_t = pv + r2 * (a_t - pv)
			gf_t = r2 * gf_t
			gb_t = r2 * gb_t
	var fast0 := B.fast
	B.fast = true
	var miss := 0.0
	for it in 10:
		miss = B.reach(foot, a_t)
		var gc: Quaternion = B.G[B.parent[foot]]
		B.ang[foot] = B.clamp_ang(foot, B.decompose(foot, (gc.inverse() * gf_t).normalized()))
		B.fk_sub(foot)
		B.ang[ball] = B.clamp_ang(ball, B.decompose(ball, ((B.G[foot] as Quaternion).inverse() * gb_t).normalized()))
		B.fk_sub(ball)
		var now := pivot_of(B, sd, roll)
		var e: Vector3 = now - pv
		if e.length() < 2e-5:
			break
		a_t = (B.P[foot] as Vector3) - e   # slide the ankle target by what the pivot is off
	B.fast = fast0
	B.fk()
	var end := pivot_of(B, sd, roll)
	return {"pivot": pv, "err": (end - pv).length(), "ankle": (B.ang[foot] as Vector3).x, "toe": (B.ang[ball] as Vector3).x, "miss": miss}
