## godot --headless --path . -s tools/detail.gd -- scenes/<name>.json [--cards 30]
##   -> scenes/_wip/<name>_detail.json   (Nick's scene is never written; his moves are his)
## DETAIL PASS (Nick 10-14: "30 clips per scene to detail really good what's going on if it is a combat scene"). Keeps
## every card of the scene where and when it was, switches it to a SPLINE scene (scene.gd: one smooth curve, stops only
## at holds) and adds named BREAKDOWN cards, each one an animation principle written as a pose:
##   ~overshoot  a stop after a FAST move: the upper body passes its place by OVERSHOOT of the move, then
##   ~settle     comes back to SETTLE of it (a stopping weapon passes its final place a little; ATTACK_RULES "Overshoot")
##   ~hold       a stop after a slow move: a MOVING HOLD, the upper body drifts on by DRIFT of the move (never frozen)
##   ~anticipate before a BIG, FAST move (> BIG deg, at least the median speed: a strike, never a slow recovery): the
##               upper body and hips go back against it by ANTIC of it
##   ~bd         in-betweens of the long moves, eased (smootherstep), the forearm and hand DRAG behind the trunk
##               (successive breaking of joints: the trunk leads, the ends trail and then whip through)
## A stop's hold time is shared by its ~ cards, so every original card keeps its arrival time and the strike its timing.
## The legs are never offset (the feet are planted again by pin_cards); fingers are never offset.
extends SceneTree

const OVERSHOOT := 0.08
const SETTLE := 0.02
const DRIFT := 0.03
const ANTIC := 0.10
const BIG := 45.0         # deg: a move this big gets an anticipation
const FAST := 1.3         # x the median move speed: a move this fast gets an overshoot
const MIN_HOLD := 0.08    # s: a hold shorter than this stays a plain stop
const ROOM := 0.2         # s: a hold shorter than this gets ONE ~ card, not a chain
const DRAG := {4: 0.07, 5: 0.12}   # level -> how far behind (in u) the breakdown's forearm / hand is


func _init() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var target := 30
	var i := args.find("--cards")
	if i >= 0:
		target = int(args[i + 1])
		args.remove_at(i + 1)
		args.remove_at(i)
	var src: String = args[0]
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://" + src)))
	var before := _report(B, S)
	var r := polish(B, S, target)
	var D: Scene = r[0]
	var passby: int = r[1]
	var after := _report(B, D)
	var out := "res://scenes/_wip/%s_detail.json" % src.get_file().get_basename()
	D.name = src.get_file().get_basename() + "_detail"
	var d := D.to_dict(B)
	d["plan"] = "tools/detail.gd from " + src
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(d, " "))
	print("%s: %d cards -> %d (%d pass-by)  length %.2f -> %.2f s" % [src.get_file(), S.cards.size(), D.cards.size(), passby, S.length(), D.length()])
	print("  bad frames %d -> %d   worst contact %.1f -> %.1f mm" % [before[0], after[0], before[1] * 1000.0, after[1] * 1000.0])
	var names := []
	for c in D.cards:
		names.append(c["name"])
	print("  " + " | ".join(names))
	print("  guard cut back %d cards: %s" % [softened.size(), ", ".join(softened)])
	print("  wrote " + out)
	quit()


## the whole pass as one call (the poser's Polish button uses it too): detail, feet pinned, pass-bys where a move goes
## through the body -> [the new scene, pass-by cards added]. S is not changed.
static func polish(B: Body, S: Scene, target := 30) -> Array:
	var D := detail(B, S, target)
	D.pin_cards(B)
	var passby := D.clear(B)
	return [D, passby]


## [bad frame count, worst depth m]
func _report(B: Body, S: Scene) -> Array:
	var bad := S.check(B)
	var worst := 0.0
	for f in bad:
		for c in f[2]:
			worst = maxf(worst, float(c[2]))
	return [bad.size(), worst]


static func _legs(j: String) -> bool:
	return j.begins_with("thigh") or j.begins_with("calf") or j.begins_with("foot") or j.begins_with("ball")


## the biggest upper-body angle change between two flat poses (deg)
static func _size(a: Dictionary, b: Dictionary) -> float:
	var big := 0.0
	for j in a["ang"]:
		if _legs(j) or Scene.level(j) >= 6 or not b["ang"].has(j):
			continue
		var d := Scene._d(a["ang"][j], b["ang"][j], j).abs()
		big = maxf(big, d[d.max_axis_index()])
	return big


## pose p pushed by k x (the move from -> to), upper body (with the hips' turn when hips) only
static func _push(p: Dictionary, from: Dictionary, to: Dictionary, k: float, hips := false) -> Dictionary:
	var ang := {}
	for j in p["ang"]:
		var v: Vector3 = p["ang"][j]
		if not _legs(j) and Scene.level(j) < 6 and (hips or j != "pelvis") and from["ang"].has(j) and to["ang"].has(j):
			v = v + Scene._d(from["ang"][j], to["ang"][j], j) * k
			if j == "pelvis":
				v.z = wrapf(v.z, -180.0, 180.0)
		ang[j] = v
	return {"offset": p["offset"], "ang": ang, "weapon": p["weapon"]}


## the same in-between with every joint together (no drag): what the guard falls back to
static func _between_plain(S: Scene, a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var e := u * u * u * (u * (6.0 * u - 15.0) + 10.0)
	return _mix(a, b, e).merged({"weapon": S.blend(a, b, u)["weapon"]}, true)


## an in-between at u of the move a -> b: smootherstep, the forearm and hand DRAG behind
static func _between(S: Scene, a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var e := u * u * u * (u * (6.0 * u - 15.0) + 10.0)
	var ang := {}
	for j in a["ang"]:
		var x := clampf(u - float(DRAG.get(Scene.level(j), 0.0)), 0.0, 1.0)
		var ej := x * x * x * (x * (6.0 * x - 15.0) + 10.0) if not _legs(j) else e
		var v: Vector3 = (a["ang"][j] as Vector3) + Scene._d(a["ang"][j], b["ang"].get(j, a["ang"][j]), j) * ej
		if j == "pelvis":
			v.z = wrapf(v.z, -180.0, 180.0)
		ang[j] = v
	var w: Dictionary = S.blend(a, b, u)["weapon"]
	return {"offset": (a["offset"] as Vector3).lerp(b["offset"], e), "ang": ang, "weapon": w}


static var softened := []   # [card name, the scale kept] for every card the guard cut back (printed)


static func _worst(B: Body) -> float:
	var w := 0.0
	for c in B.contacts():
		w = maxf(w, float(c[2]))
	return w


## the shared tween rule (Scene.mix_flat), keeping a's weapon place: plain and rich share it here
static func _mix(a: Dictionary, b: Dictionary, s: float) -> Dictionary:
	var m := Scene.mix_flat(a, b, s)
	m["weapon"] = a["weapon"]
	return m


## the principled pose RICH as a card, but never deeper in the body than REF (m, its source cards' worst): the push
## from PLAIN (the same moment without the principle) is halved until it is (1, 1/2, 1/4, 1/8, then plain)
static func _guarded(B: Body, S: Scene, name: String, plain: Dictionary, rich: Dictionary, ref: float) -> Dictionary:
	for s in [1.0, 0.5, 0.25, 0.125, 0.0]:
		var pose := _card(B, S, _mix(plain, rich, s))
		if _worst(B) <= ref + 0.001 or s == 0.0:
			if s < 1.0:
				softened.append("%s x%s" % [name, s])
			return pose
	return {}


## a flat pose -> a card pose (clamped to the limits, grounded, the second hand back on its grip)
static func _card(B: Body, S: Scene, p: Dictionary) -> Dictionary:
	Scene.put(B, p)
	if S.on_floor:
		S._ground(B)
	B.apply_grip()
	return B.to_dict()


static func detail(B: Body, S: Scene, target: int) -> Scene:
	var n := S.cards.size()
	var P := []
	for k in n:
		P.append(Moves._flat(S.cards[k]["pose"]))
	var ref := []   # each source card's own worst contact (m): a new card may sink no deeper than its neighbours
	for k in n:
		_card(B, S, P[k])
		ref.append(_worst(B))
	var mv := [0.0]
	var size := [0.0]
	var speeds := []
	for k in range(1, n):
		mv.append(S.move_time(k))
		size.append(_size(P[k - 1], P[k]))
		speeds.append(size[k] / maxf(1e-3, mv[k]))
	speeds.sort()
	var median: float = speeds[speeds.size() / 2] if not speeds.is_empty() else 0.0
	# 1. the stops' own breakdowns: per card k, the ~ cards that share its hold: [[name, flat pose, share of the hold]]
	var subs := []
	for k in n:
		var s := []
		var h := float(S.cards[k]["hold"])
		if k < n - 1 and h >= MIN_HOLD:
			var fast_in: bool = k > 0 and size[k] / maxf(1e-3, mv[k]) >= FAST * median
			var strike_out: bool = size[k + 1] >= BIG and size[k + 1] / maxf(1e-3, mv[k + 1]) >= median   # never before a slow recovery
			if h < ROOM:
				# a short hold has room for ONE principle (three in 80 ms jittered, combo3 2.9 s, 10-14): the strike to come
				# wins, else the stop's own weight
				if strike_out:
					s.append(["~anticipate", _push(P[k], P[k], P[k + 1], -ANTIC, true), 1.0])
				elif fast_in:
					s.append(["~overshoot", _push(P[k], P[k - 1], P[k], OVERSHOOT), 1.0])
				elif k > 0:
					s.append(["~hold", _push(P[k], P[k - 1], P[k], DRIFT), 1.0])
			else:
				if fast_in:
					s.append(["~overshoot", _push(P[k], P[k - 1], P[k], OVERSHOOT), 0.3])
					s.append(["~settle", _push(P[k], P[k - 1], P[k], SETTLE), 0.4])
				elif k > 0:
					s.append(["~hold", _push(P[k], P[k - 1], P[k], DRIFT), 0.6])
				if strike_out:
					var base: Dictionary = s[-1][1] if not s.is_empty() else P[k]
					s.append(["~anticipate", _push(base, P[k], P[k + 1], -ANTIC, true), 0.4])
		subs.append(s)
	var base_count := n
	for s in subs:
		base_count += s.size()
	# 2. breakdowns for the rest: one at a time to the move that goes furthest per piece, never denser than ON TWOS (a
	#    card every 2 frames: an animator's drawing rate; 15 cards in a 5-frame move is a bake, not keys, 10-14), and
	#    none into a STEP (the foot's own arc owns that move; cutting it bounces the foot)
	var free := maxi(0, target - base_count)
	var nb := [0]
	var cap := [0]
	for k in range(1, n):
		nb.append(0)
		cap.append(0 if not S._steps(k).is_empty() else maxi(0, int(floor(mv[k] * S.fps / 2.0)) - 1))
	while free > 0:
		var best := -1
		for k in range(1, n):
			if nb[k] < cap[k] and size[k] > 1.0 and (best < 0 or size[k] / (nb[k] + 1) > size[best] / (nb[best] + 1)):
				best = k
		if best < 0:
			break
		nb[best] += 1
		free -= 1
	if free > 0:
		print("  ON TWOS reached: %d cards short of %d (the scene is too short for more keys)" % [free, target])
	# 3. write it: card k, its ~ cards in its hold, then the move to k+1 cut into nb[k+1] + 1 pieces
	var D := Scene.new()
	D.name = S.name
	D.natural = S.natural
	D.on_floor = S.on_floor
	D.floor_body = S.floor_body
	D.pin = S.pin
	D.fps = S.fps
	D.spline = true
	for k in n:
		var c: Dictionary = S.cards[k]
		var h := float(c["hold"])
		var s: Array = subs[k]
		var share := 0.0
		for x in s:
			share += float(x[2])
		var keep := h if k == n - 1 or s.is_empty() else 0.0
		if k == 0 and not s.is_empty():   # the first card is a stop: it keeps part of its hold, the rest goes to its ~
			keep = h * 0.5
			h *= 0.5
		var last: Dictionary = P[k]
		var nb_k: int = nb[k] if k > 0 else 0
		var mv_k: float = mv[k] / float(nb_k + 1) if k > 0 else 0.0
		if k > 0:
			var from: Dictionary = P[k - 1] if subs[k - 1].is_empty() else subs[k - 1][-1][1]
			for b in nb_k:
				var u := float(b + 1) / float(nb_k + 1)
				var nm := "%s ~bd%d" % [c["name"], b + 1]
				var plain := _between_plain(S, from, P[k], u)
				var pose := _guarded(B, S, nm, plain, _between(S, from, P[k], u), maxf(ref[k - 1], ref[k]))
				D.cards.append({"name": nm, "pose": pose, "move": mv_k, "hold": 0.0})
		var card := {"name": c["name"], "pose": c["pose"], "move": mv_k if k > 0 else 0.0, "hold": keep}
		for key in ["steps", "lift"]:
			if c.has(key):
				card[key] = c[key]
		D.cards.append(card)
		for x in s:
			var nm2 := "%s %s" % [c["name"], x[0]]
			var r2: float = maxf(ref[k], ref[mini(k + 1, n - 1)])
			D.cards.append({"name": nm2, "pose": _guarded(B, S, nm2, P[k], x[1], r2), "move": h * float(x[2]) / share, "hold": 0.0})
			last = x[1]
	# the last ~ card of a stop is where the next move starts: make it hold for 0 s but keep it a real point on the curve
	return D
