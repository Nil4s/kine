## pose_copy.gd - COPY A POSE BETWEEN FIGHTERS (ROADMAP 53). "Pose: copy to the other fighter" and "Pose: copy to the other
## fighter, mirrored" put the active fighter's pose at the playhead onto the other fighter's card at that same moment (a card
## is made there when the other fighter has none).
##   ANGLES: every joint's rotation is copied as it is. Each fighter keeps its own skeleton, so a taller fighter's leg is
##     reached by its own bones; the rotations are equal, the lengths are not.
##   HIPS: the other fighter keeps its own hips (its world placement is unchanged), unless "relative": then its offset from
##     its own first card moves by the same amount the source's did from its first card.
##   WEAPON AND GRIPS: the weapon (kind, length, hand, its place in the hand) and both hands' grips come along; a weapon is
##     made on the other fighter when it has none.
##   FEET: a foot the source has planted is re-planted on the other fighter at the same place relative to its hips (Body.plant);
##     with no planted foot the other fighter is put on the floor (Scene._ground, when its on_floor is set).
##   MIRRORED: the source is a scratch copy of the active body that the app's own Body.mirror_pose has reflected, so the
##     mirrored copy is the app's mirror of the pose exactly.
## Static only: main.gd calls copy(); the undo step is taken there (one step).
class_name PoseCopy
extends RefCounted

const EPS := 0.002     # s: a card this close to the playhead IS that moment (it is updated, not doubled)
const MOVE := 0.001    # s: the move of a card made at the playhead (it arrives at the playhead)
const HOLD := 0.3      # s: the hold of a card made here (Scene.add's default)
const NAME := "copied pose"


## the source as a scratch body: the active body's state (its proportions, weapon and grips) reflected by the app's own
## Body.mirror_pose when mirrored. The active body itself is not touched.
static func scratch(src: Body, mirrored: bool) -> Body:
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	M.set_state(src.state())
	if mirrored:
		M.mirror_pose()
	return M


## a fighter's own start: the hips' offset on its first card (where it stands before its moves); the fallback with no card
static func start_of(S: Scene, fallback: Vector3) -> Vector3:
	if S.cards.is_empty():
		return fallback
	var o: Array = S.cards[0]["pose"].get("offset", [0, 0, 0])
	return Vector3(o[0], o[1], o[2])


## the copy: the pose of src_B (posed by src_S at the playhead t) onto the other fighter (tgt_B, tgt_S) as a card at t.
## Returns the card's index. Nothing is undone here: the caller takes the undo step.
static func copy(src_B: Body, src_S: Scene, tgt_B: Body, tgt_S: Scene, t: float, mirrored: bool, rel: bool, name := NAME) -> int:
	if tgt_B.body != tgt_S.body:
		tgt_B.set_proportions(tgt_S.body)   # the other fighter's own proportions (its skeleton, not the source's)
	var M := scratch(src_B, mirrored)
	var ss := start_of(src_S, src_B.offset)
	if mirrored:
		ss.x = -ss.x   # the scratch's offset is reflected: its start is too
	var planted := paste(M, tgt_B, tgt_S, src_S, t, rel, ss, start_of(tgt_S, tgt_B.offset))
	# the card's feet: a planted foot is held as the source held it ("plant"); any other foot lands where the copy put it
	# ("steps" with no step: Scene._anchors reads it as "step", the card's own place), so the scene's auto-pin does not
	# move a copied leg back to the other fighter's own previous foot (the copy is the pose, not a pose plus a slide)
	var flags := {}
	if not planted.is_empty():
		flags["plant"] = planted.duplicate()
	var st := {}
	for sd in ["_l", "_r"]:
		if not sd in planted:
			st[sd] = [0.0, 0.0, 0.0]
	flags["steps"] = st
	return card_at(tgt_S, t, tgt_B.to_dict(), name, flags)


## the scratch M's pose onto tgt: angles, weapon and grips, the hips, then the feet (see the top)
static func paste(M: Body, tgt: Body, tgt_S: Scene, src_S: Scene, t: float, rel: bool, src_start: Vector3, tgt_start: Vector3) -> Array:
	var keep := tgt.offset
	if M.wep_on and not tgt.wep_on:
		tgt.set_kind(M.wep_kind)   # the other fighter takes the weapon too
		tgt.set_weapon_len(M.wep_len)
		tgt.wep_on = true
	tgt.pose_paste(M.pose_copy(), false)   # angles, hips (its own offset is set below), the weapon in its hand, the off-hand weapon
	if M.wep_on and tgt.wep_on:   # the grips: the two-hand grip and the second hand's lock (round 47)
		tgt.grip = M.grip
		tgt.grip_u = M.grip_u
		tgt.grip2 = M.grip2.duplicate(true)
	tgt.offset = (tgt_start + (M.offset - src_start)) if rel else keep
	tgt.fk()
	# FEET: the source's planted feet on the card it holds at t; the other fighter's foot goes where the source's foot is,
	# relative to its own hips, on the floor (Body.plant solves the leg alone; the hips are not moved)
	var planted: Array = []
	var c := src_S._held(t)
	if c >= 1:
		planted = src_S.cards[c].get("plant", [])
	var floor_it := tgt_S.on_floor
	for sd in planted:
		var st: Array = M.foot_state(sd)
		var ball: Vector3 = st[0]
		var at := Vector3(ball.x - M.offset.x + tgt.offset.x, 0.0, ball.z - M.offset.z + tgt.offset.z)
		tgt.plant(sd, at, float(st[1]), bool(st[3]))
		floor_it = false
	if floor_it:
		tgt_S._ground(tgt)   # the other fighter stands on the floor, as the scene plays it
	tgt.fk()
	return planted


## the flags of a card ("plant": feet held, "steps": feet landing where the card puts them) are set as given, or removed
## when flags lacks them. Returns the index of the card.
static func _flag(c: Dictionary, flags: Dictionary) -> void:
	for key in ["plant", "steps"]:
		if flags.has(key) and not (flags[key] is Array and (flags[key] as Array).is_empty()) and not (flags[key] is Dictionary and (flags[key] as Dictionary).is_empty()):
			c[key] = flags[key]
		else:
			c.erase(key)


## the pose on the card at time t of S: the card that arrives at t is updated; otherwise a card is made at t (the card before
## holds up to t, the card after keeps its arrival). Returns the index of the card.
static func card_at(S: Scene, t: float, pose: Dictionary, name := NAME, flags := {}) -> int:
	var ts := S.times()
	if S.cards.is_empty():
		S.add(name, pose)
		_flag(S.cards[0], flags)
		return 0
	for i in S.cards.size():
		if absf(float(ts[i][1]) - t) <= EPS:
			S.cards[i]["pose"] = pose
			_flag(S.cards[i], flags)
			return i
	var k := S.cards.size()
	for i in S.cards.size():
		if float(ts[i][1]) > t:
			k = i
			break
	k = maxi(k, 1)   # card 0 arrives at 0: a later playhead is always after it
	var p := k - 1
	var arr_p: float = ts[p][1]
	var old_arr: float = ts[k][1] if k < S.cards.size() else -1.0
	S.cards[p]["hold"] = maxf(0.0, t - MOVE - arr_p)   # the card before holds up to t - MOVE
	# the hold of the new card is at most HOLD, and shorter when the card after must still arrive on time (its move keeps
	# at least 0.04 s): then the card after keeps its arrival time
	var hold := HOLD
	if old_arr >= 0.0:
		hold = clampf(old_arr - t - 0.04, 0.0, HOLD)
	S.add(name, pose, k)
	S.cards[k]["move"] = MOVE
	S.cards[k]["hold"] = snappedf(hold, 0.001)
	_flag(S.cards[k], flags)
	var nx := k + 1
	if nx < S.cards.size() and old_arr >= 0.0:
		var m := old_arr - (t + hold)   # the card after keeps its arrival time
		if m >= 0.04:
			S.cards[nx]["move"] = snappedf(m, 0.001)
	return k
