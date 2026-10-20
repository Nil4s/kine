## sell_hit.gd - I21 SELL THE HIT. Stunt choreography fakes hits: the strike MISSES by a safe margin in 3D, and the camera is placed so it READS
## as a hit (the "cheat angle"). For each strike of the attacker (BeatFight.contacts, the spans of DistanceKeeper) this measures, at the instant of
## the strike's closest approach, the 3D miss AND the 2D gap as the shot camera sees it (the pinhole model of ShotCam.project), and classes it:
##   UNSAFE    the 3D miss (tip to the nearest body capsule of the target, DistanceKeeper.gap) is under SAFE = 10 cm: a real contact (miss <= 0) or
##             too near to be pulled with certainty. SAFETY flag, red. SAFE is a stunt-practice RULE OF THUMB (a pulled punch stops a hand's
##             breadth short of the face; a fist is ~9 cm wide) and a HEURISTIC, not a measured standard: no paper sets it; change SAFE to taste.
##   SOLD      3D miss >= SAFE and, on screen, the tip's disc overlaps or touches one of the target's projected capsules (a stadium of discs).
##   NOT SOLD  3D miss >= SAFE and a visible gap on screen: reported in px (of a 1280 x 720 frame) and in cm at the target's depth.
## THE TIP is a disc of TIP_R (fist 4.5 cm, boot 5 cm, blade 2 cm: heuristics, the visible size of the striking surface); the target's capsules
## carry their own radii.
## FIX 1, MOVE THE CAMERA along the line of action: the shot's camera (all of its keys, so a camera move keeps its shape) turns about the vertical
## through its aim point by the smallest angle (1 deg steps, up to MAX_ARC = 75 deg either way) that makes the tip overlap the target. Distance,
## aim point and lens stay, so the framing stays; the 3D miss is not touched (no body moves).
## FIX 2, OFFSET THE AIM: the tip's arrival pose is moved (IK on the striking arm, Body.reach) onto the camera ray through the nearest point of the
## target, SAFE + 1 cm in front of its surface, so the 3D margin holds and the tip covers the target on screen; measured again, up to 4 rounds.
class_name SellHit
extends RefCounted

const SAFE := 0.10
const TIP_R := {"hand": 0.045, "foot": 0.05, "weapon": 0.02}
const FRAME := Rect2i(0, 0, 1280, 720)
const MAX_ARC := 75.0
const OVERLAP_PX := 3.0       # a SOLD strike overlaps by at least this much (a touch is not stable under a 1 px jitter)
const AIM_MARGIN := 0.01


static func _tip_r(key: String) -> float:
	return float(TIP_R["weapon"] if key == "weapon" else (TIP_R["foot"] if key.begins_with("foot") else TIP_R["hand"]))


## the shot camera at t in the attacker's space: {"pos", "aim", "f"}; {} = the scene has no shot. ctf takes the hero's space to the attacker's
static func cam_at(shots: Array, t: float, ctf: Transform3D) -> Dictionary:
	var s := ShotCam.at(shots, t)
	if s.is_empty():
		return {}
	return {"pos": ctf * (s["pos"] as Vector3), "aim": ctf * (s["aim"] as Vector3), "f": float(s["f"])}


## how the camera sees the tip (a disc of radius tr at tip) against the target's capsules: {"gap_px" (< 0 = overlap), "gap_cm" at the target's depth,
## "depth" (m), "tip2": the tip's pixel}. A capsule is 17 discs along its axis.
static func screen(cam: Dictionary, tip: Vector3, tr: float, caps: Array) -> Dictionary:
	var X := ShotCam.xf(cam["pos"], cam["aim"]).affine_inverse()
	var k := FRAME.size.y * 0.5 / tan(deg_to_rad(ShotCam.fov_v(float(cam["f"]))) * 0.5)
	var qt: Vector3 = X * tip
	if -qt.z < 0.05:
		return {"gap_px": INF, "gap_cm": INF, "depth": 0.0, "tip2": Vector2.ZERO}
	var c2 := Vector2(qt.x, -qt.y) / -qt.z * k
	var rp := tr * k / -qt.z
	var best := INF
	var zb := 1.0
	for c in caps:
		if Body.is_wep(String(c[0])):
			continue
		for s in 17:
			var q: Vector3 = X * (c[1] as Vector3).lerp(c[2], float(s) / 16.0)
			if -q.z < 0.05:
				continue
			var g := c2.distance_to(Vector2(q.x, -q.y) / -q.z * k) - float(c[3]) * k / -q.z - rp
			if g < best:
				best = g
				zb = -q.z
	return {"gap_px": best, "gap_cm": best * zb / k * 100.0, "depth": zb, "tip2": c2 + Vector2(FRAME.size) * 0.5}


static func classify(miss3: float, gap_px: float) -> String:
	if miss3 < SAFE:
		return "unsafe"
	return "sold" if gap_px <= 0.0 else "notsold"


## strike card i against D: DistanceKeeper's span, then the 3D miss and the screen gap at its closest instant
## {"card", "t0", "t1", "t", "tip", "miss", "gap_px", "gap_cm", "cls", "contact", "cam"}
static func row(A: Scene, BA: Body, D: Scene, BD: Body, xf: Transform3D, i: int, fps: int, shots: Array, ctf: Transform3D) -> Dictionary:
	var sp := DistanceKeeper.span(A, BA, D, BD, xf, i, fps)
	var t: float = sp["t_min"]
	A.apply(BA, t)
	D.apply(BD, t)
	var key: String = sp["tip"]
	var tip: Vector3 = DistanceKeeper.tips(BA)[key]
	var caps := BD.cross_caps(xf)
	var miss := DistanceKeeper.gap(tip, caps)
	var cam := cam_at(shots, t, ctf)
	var sc := screen(cam, tip, _tip_r(key), caps) if not cam.is_empty() else {"gap_px": INF, "gap_cm": INF}
	return {"card": i, "t0": sp["t0"], "t1": sp["t1"], "t": t, "tip": key, "miss": miss, "gap_px": sc["gap_px"], "gap_cm": sc["gap_cm"],
		"cls": classify(miss, float(sc["gap_px"])), "contact": miss <= 0.0, "cam": cam}


## all the strikes. {"ok", "msg", "rows", "unsafe", "notsold", "sold"}; A, D are not touched (clones)
static func analyze(A: Scene, D: Scene, xf: Transform3D, shots: Array, ctf := Transform3D.IDENTITY, fps := 30) -> Dictionary:
	if shots.is_empty():
		return {"ok": false, "msg": "this scene has no shot camera: frame the view, then 'Camera: key the shot camera from the view'", "rows": [], "unsafe": 0, "notsold": 0, "sold": 0}
	var a := A.clone()
	var d := D.clone()
	var BA := DistanceKeeper.new_body()
	var BD := DistanceKeeper.new_body()
	var rows := []
	var n := {"unsafe": 0, "notsold": 0, "sold": 0}
	for i in BeatFight.contacts(a):
		var r := row(a, BA, d, BD, xf, i, fps, shots, ctf)
		rows.append(r)
		n[r["cls"]] += 1
	var msg := "no strikes in the attacker's scene" if rows.is_empty() else "%d strike%s: %d sold, %d not sold, %d unsafe" % [rows.size(), "" if rows.size() == 1 else "s", n["sold"], n["notsold"], n["unsafe"]]
	return {"ok": not rows.is_empty(), "msg": msg, "rows": rows, "unsafe": n["unsafe"], "notsold": n["notsold"], "sold": n["sold"]}


## the bodies of strike row r posed at its closest instant: {"tip", "caps"}
static func _at(A: Scene, D: Scene, xf: Transform3D, r: Dictionary) -> Dictionary:
	var BA := DistanceKeeper.new_body()
	var BD := DistanceKeeper.new_body()
	A.clone().apply(BA, float(r["t"]))
	D.clone().apply(BD, float(r["t"]))
	return {"tip": DistanceKeeper.tips(BA)[r["tip"]], "caps": BD.cross_caps(xf)}


static func _turn(shots: Array, t: float, c: Vector3, deg: float) -> Array:
	var out := shots.duplicate(true)
	var s: Dictionary = out[ShotCam.shot_index(out, t)]
	var R := Basis(Vector3.UP, deg_to_rad(deg))
	for key in s["keys"]:
		key["pos"] = c + R * ((key["pos"] as Vector3) - c)
		key["aim"] = c + R * ((key["aim"] as Vector3) - c)
	return out


static func _guard(rep: Dictionary, k: int) -> String:
	var rows: Array = rep.get("rows", [])
	if k < 0 or k >= rows.size():
		return "pick a strike in the list first"
	if rows[k]["cls"] == "unsafe":
		return "that strike is UNSAFE (%.0f cm, under the %.0f cm margin): fix the choreography first, the camera cannot make it safe" % [float(rows[k]["miss"]) * 100.0, SAFE * 100.0]
	if rows[k]["cls"] == "sold":
		return "that strike is sold already: nothing to move"
	return ""


## FIX 1 for strike k: turn the shot camera about the vertical through its aim point. {"ok", "why", "shots" (hero space), "deg", "after" (the row again), "msg"}
static func camera_fix(A: Scene, D: Scene, xf: Transform3D, shots: Array, ctf: Transform3D, fps: int, k: int, rep: Dictionary) -> Dictionary:
	var why := _guard(rep, k)
	if why != "":
		return {"ok": false, "why": why}
	var r: Dictionary = rep["rows"][k]
	var cam: Dictionary = r["cam"]
	var at := _at(A, D, xf, r)
	var c: Vector3 = cam["aim"]
	var found := 0.0
	for d in range(1, int(MAX_ARC) + 1):
		for sg in [1.0, -1.0]:
			var R := Basis(Vector3.UP, deg_to_rad(float(d) * sg))
			var c2 := {"pos": c + R * ((cam["pos"] as Vector3) - c), "aim": cam["aim"], "f": cam["f"]}
			if float(screen(c2, at["tip"], _tip_r(r["tip"]), at["caps"])["gap_px"]) <= -OVERLAP_PX:
				found = float(d) * sg
				break
		if found != 0.0:
			break
	if found == 0.0:
		return {"ok": false, "why": "no camera angle within %.0f degrees hides the gap: use 'Offset the aim' instead" % MAX_ARC}
	var hc: Vector3 = ShotCam.at(shots, float(r["t"]))["aim"]   # hero space: a turn about a vertical is the same angle in both spaces
	var ns := _turn(shots, float(r["t"]), hc, found)
	var an := analyze(A, D, xf, ns, ctf, fps)
	var after: Dictionary = an["rows"][k] if an["ok"] and k < an["rows"].size() else {}
	return {"ok": true, "why": "", "kind": "camera", "shots": ns, "deg": found, "k": k, "after": after,
		"msg": "turn the shot camera %.0f degrees %s about its aim point at %.2f s (distance and lens kept)" % [absf(found), "left" if found > 0.0 else "right", float(r["t"])]}


## FIX 2 for strike k: move the tip's arrival pose onto the camera ray through the target. {"ok", "why", "scene" (the attacker with the new pose),
## "move" (m, tip travel), "after", "msg"}
static func aim_fix(A: Scene, D: Scene, xf: Transform3D, shots: Array, ctf: Transform3D, fps: int, k: int, rep: Dictionary) -> Dictionary:
	var why := _guard(rep, k)
	if why != "":
		return {"ok": false, "why": why}
	var r: Dictionary = rep["rows"][k]
	var cam: Dictionary = r["cam"]
	var sc := A.clone()
	var key: String = r["tip"]
	var i := int(r["card"])
	var cur := r
	var moved := 0.0
	for it in 4:
		var at := _at(sc, D, xf, cur)
		var tip: Vector3 = at["tip"]
		# the nearest point to the tip that is >= SAFE + margin clear of EVERY capsule and covers one on screen: a candidate sits on the camera
		# ray through a point of a capsule's axis, in front of its surface
		var best := INF
		var want := tip
		for c in at["caps"]:
			if Body.is_wep(String(c[0])):
				continue
			for si in 9:
				var q: Vector3 = (c[1] as Vector3).lerp(c[2], float(si) / 8.0)
				var ray: Vector3 = (q - (cam["pos"] as Vector3)).normalized()
				var cand: Vector3 = q - ray * (float(c[3]) + SAFE + AIM_MARGIN)
				if DistanceKeeper.gap(cand, at["caps"]) < SAFE + AIM_MARGIN * 0.5:
					continue
				if float(screen(cam, cand, _tip_r(key), at["caps"])["gap_px"]) > -OVERLAP_PX:
					continue
				if cand.distance_to(tip) < best:
					best = cand.distance_to(tip)
					want = cand
		var delta := want - tip
		moved += delta.length()
		var B := DistanceKeeper.new_body()
		B.from_dict(sc.cards[i]["pose"])
		var hand: String = (B.wep_hand if B.wep_hand != "" else "hand_r") if key == "weapon" else key
		B.reach(hand, (B.P[hand] as Vector3) + delta)
		sc.cards[i]["pose"] = B.to_dict()
		cur = row(sc.clone(), DistanceKeeper.new_body(), D.clone(), DistanceKeeper.new_body(), xf, i, fps, shots, ctf)
		if cur["cls"] == "sold":
			break
	if cur["cls"] != "sold":
		return {"ok": false, "why": "the striking arm cannot reach a point that is %.0f cm clear and covers the target on screen (it ends %s): use 'Move the camera' instead" % [SAFE * 100.0, cur["cls"]]}
	return {"ok": true, "why": "", "kind": "aim", "scene": sc, "move": moved, "k": k, "after": cur,
		"msg": "move the %s %.0f cm at %.2f s (IK on the striking arm), still %.0f cm clear" % [key.replace("_", " "), moved * 100.0, float(r["t"]), float(cur["miss"]) * 100.0]}
