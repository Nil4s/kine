class_name JumpOver
extends RefCounted
## JUMP OVER A BOX (ajump, Easy): a walk to a take-off point in front of a crate or box, then the jump template carried
## forward so he lands past the far face, and lifted so his feet clear the top. Built from the jump.json template and the
## walk (PathWalk), joined by EasyHome.place_after (the same join as "sit on the chair"). Returns {"cards": [...], "why": ""}.
## The lift is one bell over the flight (the template's feet reach 0.36 m; the box top + CLEAR is the target), the forward
## travel one ramp from take-off to touch-down (the template's own air frames), then the landing stays past the box.

const KINDS_OK := ["crate", "box"]
const CLEAR := 0.15          # m: the feet clear the box top by this much at the crossing
const FEET_APEX := 0.36      # m: the jump template's feet at the top of its flight (measured, tests/ajump_test.gd)
const TAKE_BEFORE := 0.30    # m: the take-off sits this far before the box's near face
const LAND_PAST := 0.30      # m: he lands this far past the box's far face
const WALK_MIN := 1.45       # m: the walk to the take-off needs at least two steps (PathWalk refuses a shorter path: 141 cm); a shorter run is a jump from where he stands
const HALF := {"crate": Vector2(0.3, 0.2), "box": Vector2(0.2, 0.2)}   # half sizes (x, z) of the box solids (props.gd KINDS)
## per jump card (templates/jump.json order: stand, dip, push, take-off, leave, air, touch-down, absorb, stand): the share of
## the travel done by the card: 0 until take-off, 1 from touch-down on
const RAMP := [0.0, 0.0, 0.0, 0.0, 0.175, 0.53, 1.0, 1.0, 1.0]


## the box p (a Props dict: kind, xf) to jump over, from the floor point start (the body's pelvis at the clip's end, or now)
static func build(p: Dictionary, start: Vector3, fwd: Vector3) -> Dictionary:
	var fail := {"cards": [], "why": ""}
	var kind := String(p.get("kind", ""))
	if not KINDS_OK.has(kind):
		fail["why"] = "Jump over needs a crate or a box in the scene (Library > Furniture > Crate)"
		return fail
	var xf: Transform3D = p["xf"]
	var pos := Vector3(xf.origin.x, 0.0, xf.origin.z)
	var to_box := pos - Vector3(start.x, 0.0, start.z)
	if to_box.length() < 0.5:
		fail["why"] = "The %s is too close to him: move it about a stride away, in front of him" % kind
		return fail
	var a := to_box.normalized()
	var bx := Vector3(xf.basis.x.x, 0.0, xf.basis.x.z).normalized()
	var bz := Vector3(xf.basis.z.x, 0.0, xf.basis.z.z).normalized()
	var h: Vector2 = HALF[kind]
	var ext := absf(a.dot(bx)) * h.x + absf(a.dot(bz)) * h.y   # the box's half-width along the run
	var mid := to_box.dot(a)
	var near := mid - ext
	var far := mid + ext
	if near < 0.15:
		fail["why"] = "The %s touches him: move it back a little, then type 'jump over the %s'" % [kind, kind]
		return fail
	var t_dist := maxf(0.0, near - TAKE_BEFORE)
	var walk: Array = []
	var pel_end := Vector3.ZERO
	var turn := 0.0   # rad: a no-walk jump turned to the box (from the template's facing)
	if t_dist >= WALK_MIN:
		var T0 := Vector3(start.x, 0.0, start.z) + a * t_dist
		var r: Dictionary = PathWalk.build([Vector3(start.x, 0.0, start.z) + a * PathWalk.HIP_BACK, T0], 1.3)
		if not bool(r["ok"]):
			fail["why"] = "the walk to the take-off is refused (%s)" % String(r["why"])
			return fail
		walk = (r["scene"] as Dictionary)["cards"]
		pel_end = EasyHome._pelvis_ang((walk[walk.size() - 1]["pose"] as Dictionary).get("joints", {}))
	else:
		# no walk: the take-off is where he stands, so the box must be in front of him, and he must face +Z (the template's facing)
		# he may face up to 60 deg off the box: the jump is turned to it at its start (a snap at the first frame, not a walk-turn)
		var zf := Vector3(0, 0, 1)
		if a.dot(fwd) < 0.5 or fwd.dot(zf) < 0.99:
			fail["why"] = "the %s is too far to his side for a jump from where he stands: move it a stride further in front, so he runs up to it" % kind
			return fail
		t_dist = 0.0
		turn = atan2(a.x, a.z) - atan2(fwd.x, fwd.z)
	var T := Vector3(start.x, 0.0, start.z) + a * t_dist
	var D := (far + LAND_PAST) - t_dist
	# the lift: the feet reach FEET_APEX in the template; the box top + CLEAR is the goal
	var lift := maxf(0.0, p_top(kind) + CLEAR - FEET_APEX)
	var jump: Dictionary = Templates.read("jump")
	var jc: Array = (jump["cards"] as Array).duplicate(true)
	if jc.size() != RAMP.size():
		fail["why"] = "the jump template changed (%d cards): JumpOver needs %d" % [jc.size(), RAMP.size()]
		return fail
	if walk.is_empty():   # no walk: the template's own facing, turned by "turn" (EasyHome.place_after turns by the pelvis heading)
		var pa0 := EasyHome._pelvis_ang((jc[0]["pose"] as Dictionary).get("joints", {}))
		var PB := EasyHome._pelvis_body()
		pel_end = PB.decompose("pelvis", (Quaternion(Vector3.UP, turn) * PB.compose("pelvis", pa0)).normalized())
	EasyHome.place_after(jc, T, pel_end)
	for i in jc.size():
		var c: Dictionary = jc[i]
		var o: Array = c["pose"].get("offset", [0, 0, 0])
		var k: float = RAMP[i]
		var bell := sin(PI * clampf(k, 0.0, 1.0)) if i >= 3 and i <= 6 else 0.0
		c["pose"]["offset"] = [float(o[0]) + a.x * D * k, float(o[1]) + lift * bell, float(o[2]) + a.z * D * k]
		c["name"] = "jump over the %s: %s" % [kind, String(c["name"])]
	var cards: Array = walk.duplicate()
	for c in jc:
		cards.append(c)
	return {"cards": cards, "why": ""}


static func p_top(kind: String) -> float:
	return float(Props.KINDS[kind]["supports"][0][0])
