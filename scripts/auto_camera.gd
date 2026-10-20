## AUTO CAMERA (ROADMAP I7). For the strike in the clip it suggests a shot camera for each beat, from film grammar, and NAMES the
## rule behind each one. Read only: compute() returns suggestions; add_shot() writes ONE shot into a shot list it is given.
##
## BEATS (read from the card names by the R27 phase reader, NextPose.phase_of, and the contact time from Check's own evidence):
##   the CONTACT card = the contact-phase card whose striking hand arrives fastest (none named: the fastest hand move in the clip);
##   WIND-UP = the last wind-up-phase card before it (none: the card just before); RECOVER = the first recover-phase card after it
##   (none: the last card). The contact TIME is a "hit" marker inside the contact card, else (two fighters) the first frame their
##   bodies touch (Body.cross_contacts, the test Check uses), else the card's arrival.
## THE RULES (film grammar; Mascelli, "The Five C's of Cinematography", 1965; Arijon, "Grammar of the Film Language", 1976;
## Katz, "Film Directing Shot by Shot", 1991):
##   180-DEGREE RULE   the action line is the line between the two fighters (one fighter: his facing). Every suggested camera stays
##                     on ONE side of it: the side of the striking hand, so the hand is not hidden behind the body.
##   LEAD ROOM         the subject sits on the 1/3 line OPPOSITE to the direction of motion (offset 1/6 of the frame width), so
##                     the frame has more room in front of the strike than behind it (rule of thirds; Katz, "headroom and lead room").
##   CLOSER ON CONTACT wind-up = medium wide (35 mm, the whole body of every fighter), contact = close-up (85 mm, head, chest and
##                     the striking hand), at least CLOSER x the wind-up's subject height: tension rises, the frame tightens.
##   LOW ANGLE         a heavy strike (the striking hand arrives at HEAVY_SPEED or more) is shot from below, LOW_DEG: the fist
##                     grows and the fighter looms (Mascelli: a low angle gives power). 4.0 m/s is the slow end of the recorded
##                     punch means: peak 7.1 m/s (MMA swing punch, Sensors 2025) to 11.95 m/s (lead hook, Stanley et al. 2018)
##                     over a minimum-jerk bell (peak = 1.875 x mean, Flash & Hogan 1985) = 3.8 .. 6.4 m/s (timing_coach.gd).
##   HOLD THE WIDE     the recover goes back to a wide (28 mm, margin 14 %) that holds the whole fight in frame until the next beat.
## The numbers THIRD, CLOSER, the lens and margin per beat are OURS (the books give the order, not a number).
## Cameras are in the HERO's space like every shot (shot_camera.gd); the others stand at their placement (actor xf).
class_name AutoCam
extends RefCounted

const FR := Rect2i(0, 0, 1280, 720)   # the frame the fit works in (16:9); the result does not depend on the pixel size
const THIRD := 1.0 / 6.0              # the subject's offset from the centre, in frame widths (the 1/3 line)
const CLOSER := 1.25                  # the contact's subject height is at least this many times the wind-up's
const HEAVY_SPEED := 4.0              # m/s, mean speed of the striking hand into contact: at or over = a heavy strike
const LOW_DEG := 12.0                 # deg: the low angle's pitch up
const SAMPLES := 7                    # times looked at inside a shot, to keep the fighters in frame throughout
const MIN_CAM_Y := 0.15               # m: a camera never goes under the floor
const NJ := 22                        # Body.ORDER[0:22] are the body's joints (the rest are fingers)

## beat -> [lens mm, deg off the action line, pitch up (deg; negative = looking down), margin (share of the frame), size word]
const SPEC := {
	"windup": [35.0, 58.0, -3.0, 0.06, "medium wide"],
	"contact": [85.0, 38.0, 0.0, 0.07, "close-up"],
	"recover": [28.0, 70.0, -5.0, 0.14, "wide"],
}
const BEAT_WORD := {"windup": "WIND-UP", "contact": "CONTACT", "recover": "RECOVER"}


static func actor_xf(xf: Dictionary) -> Transform3D:
	var p: Array = xf.get("pos", [0.0, 0.0])
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(xf.get("yaw", 0.0)))), Vector3(float(p[0]), 0.0, float(p[1])))


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## the y component of a x b: the SIDE of line direction a that b lies on (+ or -)
static func side_of(a: Vector3, b: Vector3) -> float:
	return a.z * b.x - a.x * b.z


static func new_body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return b


## every fighter posed at t: [{"all": [Vector3] (the joints, the head top, the soles), "pel", "chest", "head", "hl", "hr", "face"}]
## in the hero's space. bodies[k] belongs to fighter k (0 = the hero); S.actors[k-1] is fighter k's scene and placement
static func fighters(S: Scene, bodies: Array, t: float) -> Array:
	var out := []
	for k in bodies.size():
		var sc: Scene = S if k == 0 else S.actors[k - 1]["scene"]
		var X := Transform3D.IDENTITY if k == 0 else actor_xf(S.actors[k - 1]["xf"])
		var B: Body = bodies[k]
		sc.apply(B, t)
		B.fk()
		var all := []
		for j in Body.ORDER.slice(0, NJ):
			all.append(X * (B.P[j] as Vector3))
		var top: Vector3 = X * (B.P["head"] as Vector3) + Vector3(0, 0.13, 0)
		all.append(top)
		for sd in ["l", "r"]:
			all.append(X * (B.P["ball_" + sd] as Vector3) + Vector3(0, -0.03, 0))
			all.append(X * (B.P["foot_" + sd] as Vector3) + Vector3(0, -0.07, 0))
		var face := _flat(X.basis * ((B.P["thigh_l"] as Vector3) - (B.P["thigh_r"] as Vector3)).cross(Vector3.UP))
		out.append({"all": all, "pel": X * (B.P["pelvis"] as Vector3), "chest": X * (B.P["spine_03"] as Vector3), "head": top,
			"hl": X * (B.P["hand_l"] as Vector3), "hr": X * (B.P["hand_r"] as Vector3),
			"face": face.normalized() if face.length() > 1e-6 else Vector3(0, 0, 1)})
	return out


static func bodies_for(S: Scene) -> Array:
	var bs := [new_body()]
	for a in S.actors:
		bs.append(new_body())
	return bs


## the strike: {"card", "hand": "l"|"r", "dist", "speed" (m/s mean into contact), "dir" (flat unit, the hand's travel), "named": bool}
static func find_strike(S: Scene, bodies: Array) -> Dictionary:
	var ts := S.times()
	var best := {}
	for pass_named in [true, false]:
		for i in range(1, S.cards.size()):
			var named := NextPose.phase_of(String(S.cards[i]["name"])) == "contact"
			if pass_named and not named:
				continue
			var a: Dictionary = fighters(S, bodies, float(ts[i][0]))[0]
			var b: Dictionary = fighters(S, bodies, float(ts[i][1]))[0]
			var dl: float = (a["hl"] as Vector3).distance_to(b["hl"])
			var dr: float = (a["hr"] as Vector3).distance_to(b["hr"])
			var sd := "l" if dl >= dr else "r"
			var dist := maxf(dl, dr)
			var dur := maxf(float(ts[i][1]) - float(ts[i][0]), 0.04)
			var mv: Vector3 = _flat((b["h" + sd] as Vector3) - (a["h" + sd] as Vector3))
			if dist < 0.1:
				continue
			if best.is_empty() or dist / dur > float(best["speed"]):
				best = {"card": i, "hand": sd, "dist": dist, "speed": dist / dur, "dir": mv.normalized() if mv.length() > 0.05 else Vector3.ZERO, "named": named}
		if not best.is_empty():
			break
	return best


## the beats: {"strike", "w", "c", "r" (card indexes; r == c = no recover), "cut_w", "cut_c", "cut_r", "tw", "tc", "tr"}; {} = none
static func beats(S: Scene, bodies: Array) -> Dictionary:
	if S.cards.size() < 2:
		return {}
	var st := find_strike(S, bodies)
	if st.is_empty():
		return {}
	var ts := S.times()
	var c: int = st["card"]
	var w := c - 1
	for i in range(c - 1, 0, -1):
		if NextPose.phase_of(String(S.cards[i]["name"])) == "windup":
			w = i
			break
	var r := c
	for i in range(c + 1, S.cards.size()):
		if NextPose.phase_of(String(S.cards[i]["name"])) == "recover":
			r = i
			break
	if r == c and c < S.cards.size() - 1:
		r = S.cards.size() - 1
	var tc := float(ts[c][1])
	var fps := float(maxi(S.fps, 1))
	var lo := float(ts[c][0])
	var hi := float(ts[c][2])
	var found := false
	for mk in S.markers:
		if String(mk["kind"]) == "hit" and float(mk["t"]) >= lo - 0.001 and float(mk["t"]) <= hi + 0.001:
			tc = float(mk["t"])
			found = true
			break
	if not found and not S.actors.is_empty():   # Check's cross-body test: the first frame the fighters touch
		var t := lo
		while t <= hi + 1e-6:
			fighters(S, bodies, t)
			if not (bodies[0] as Body).cross_contacts(bodies[1], actor_xf(S.actors[0]["xf"])).is_empty():
				tc = t
				break
			t += 1.0 / fps
	return {"strike": st, "w": w, "c": c, "r": r, "cut_w": float(ts[w][0]), "cut_c": float(ts[c][0]), "cut_r": float(ts[r][0]),
		"tw": float(ts[w][1]), "tc": tc, "tr": float(ts[r][1])}


# ---------------------------------------------------------------- the framing

static func _inside(key: Dictionary, pts: Array, m: float) -> bool:
	var f := float(key["f"])
	for p in pts:
		var q: Vector3 = ShotCam.xf(key["pos"], key["aim"]).affine_inverse() * (p as Vector3)
		if q.z > -0.05:
			return false
		var s := ShotCam.project(key["pos"], key["aim"], f, FR, p)
		if s.x < FR.size.x * m or s.x > FR.size.x * (1.0 - m) or s.y < FR.size.y * m or s.y > FR.size.y * (1.0 - m):
			return false
	return true


## the camera for distance d: aimed at `centre`, `dirv` (flat unit) the way from the aim to the camera, the lens f, the pitch (deg,
## camera below the aim for +), and the lead room: the subject point `pel` is moved along the camera's right until it sits
## `lead` frame widths from the centre (lead > 0: right of centre)
static func _place(centre: Vector3, dirv: Vector3, d: float, f: float, pitch: float, pel: Vector3, lead: float) -> Dictionary:
	var p := deg_to_rad(pitch)
	var aim := centre
	var pos := aim + dirv * d * cos(p) + Vector3(0, -d * sin(p), 0)
	pos.y = maxf(pos.y, MIN_CAM_Y)
	var right := (-dirv).cross(Vector3.UP).normalized()
	var k := FR.size.y * 0.5 / tan(deg_to_rad(ShotCam.fov_v(f)) * 0.5)
	var q: Vector3 = ShotCam.xf(pos, aim).affine_inverse() * pel
	var sx := ShotCam.project(pos, aim, f, FR, pel).x
	var err := sx - (FR.size.x * 0.5 + lead * FR.size.x)
	var shift := err * (-q.z) / k   # world metres along the right: moves the subject by -err px
	aim += right * shift
	pos += right * shift
	return {"pos": pos, "aim": aim, "f": f, "d": d}


## the smallest distance at which every point of `pts` is inside the frame's margin m (and `must` inside m_must), growing from 0.9 m
static func _fit(centre: Vector3, dirv: Vector3, f: float, pitch: float, pel: Vector3, lead: float, pts: Array, m: float) -> Dictionary:
	var d := 0.9
	var key := {}
	for i in 400:
		key = _place(centre, dirv, d, f, pitch, pel, lead)
		if _inside(key, pts, m):
			return key
		d *= 1.02
	return key


static func _bbox_centre(pts: Array) -> Vector3:
	var lo: Vector3 = pts[0]
	var hi: Vector3 = pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	return (lo + hi) * 0.5


## the hero's height on screen, as a share of the frame height: head top to the lowest sole, at time t
static func subject_h(S: Scene, bodies: Array, key: Dictionary, t: float) -> float:
	var fs := fighters(S, bodies, t)
	var all: Array = fs[0]["all"]
	var lo := 1e9
	for p in all:
		lo = minf(lo, (p as Vector3).y)
	var top: Vector3 = fs[0]["head"]
	var a := ShotCam.project(key["pos"], key["aim"], float(key["f"]), FR, top)
	var feet: Vector3 = _flat(top) + Vector3(0, lo, 0)
	var b := ShotCam.project(key["pos"], key["aim"], float(key["f"]), FR, feet)
	return absf(b.y - a.y) / float(FR.size.y)


static func _times(a: float, b: float) -> Array:
	var out := []
	for i in SAMPLES:
		out.append(lerpf(a, b, float(i) / float(SAMPLES - 1)))
	return out


## THE SUGGESTIONS: {"sugs": [{"beat", "label", "size", "rules" [names], "rule" (the label's words), "why", "cut", "t", "key" {t, pos, aim, f},
## "lead" (+1/-1: which way the subject moves on screen), "heavy"}], "why": text when there are none, "line": {"a", "dir"}, "side": +1/-1,
## "motion": Vector3, "beats": the beats}. Read only: the scene is posed on private bodies
static func compute(S: Scene) -> Dictionary:
	var out := {"sugs": [], "why": ""}
	if S.cards.size() < 2:
		out["why"] = "Auto camera needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below"
		return out
	var bodies := bodies_for(S)
	var bt := beats(S, bodies)
	if bt.is_empty():
		out["why"] = "Auto camera found no striking move: no hand travels 10 cm into a card. Name a card 'contact' or 'strike', or make a hand move, then run it again"
		return out
	var st: Dictionary = bt["strike"]
	var tc := float(bt["tc"])
	var fc := fighters(S, bodies, tc)
	var hero: Dictionary = fc[0]
	var A: Vector3 = _flat(hero["pel"])
	var dir: Vector3 = hero["face"]
	var two := fc.size() > 1
	if two:
		var d2: Vector3 = _flat((fc[1]["pel"] as Vector3) - (hero["pel"] as Vector3))
		if d2.length() > 0.2:
			dir = d2.normalized()
	var hand: Vector3 = hero["h" + String(st["hand"])]
	var side := 1.0 if side_of(dir, _flat(hand - (hero["pel"] as Vector3))) >= 0.0 else -1.0
	var motion: Vector3 = st["dir"] if (st["dir"] as Vector3).length() > 0.5 else dir
	var heavy := float(st["speed"]) >= HEAVY_SPEED
	var spans := {
		"windup": [float(bt["cut_w"]), float(bt["cut_c"])],
		"contact": [float(bt["cut_c"]), float(bt["cut_r"]) if int(bt["r"]) != int(bt["c"]) else float(bt["tc"]) + 0.3],
		"recover": [float(bt["cut_r"]), S.length()],
	}
	var tbeat := {"windup": float(bt["tw"]), "contact": tc, "recover": float(bt["tr"])}
	var order := ["windup", "contact"]
	if int(bt["r"]) != int(bt["c"]) and float(bt["cut_r"]) > float(bt["cut_c"]) + 1e-6:
		order.append("recover")
	var hw := 0.0
	var hand_name := "h" + String(st["hand"])
	for beat in order:
		var sp: Array = SPEC[beat]
		var f := float(sp[0])
		var pitch := float(sp[2])
		if beat == "contact" and heavy:
			pitch = LOW_DEG
		var a: float = spans[beat][0]
		var b: float = spans[beat][1]
		var all := []
		var must := []
		for t in _times(a, maxf(b, a + 1e-3)):
			var fs := fighters(S, bodies, minf(t, S.length()))
			for q in fs.size():
				all.append_array(fs[q]["all"])
				must.append(fs[q]["head"])
				must.append(fs[q]["chest"])
			must.append(fs[0][hand_name])
		var pts: Array = must if beat == "contact" else all
		var centre := _bbox_centre(pts)
		var lead_dir := 1.0
		var theta := float(sp[1])
		var key := {}
		var dirv := Vector3.ZERO
		var s := 0.0
		for tries in 8:   # the angle opens until the camera is plainly on the chosen side and the motion has a screen direction
			dirv = Basis(Vector3.UP, -side * deg_to_rad(theta)) * (-dir)
			var right := (-dirv).cross(Vector3.UP).normalized()
			s = signf(motion.dot(right))
			if s == 0.0:
				s = 1.0
			key = _fit(centre, dirv, f, pitch, fc[0]["pel"], -s * THIRD, pts, float(sp[3]))
			if side_of(dir, (key["pos"] as Vector3) - A) * side > 0.1 and absf(motion.dot(right)) > 0.2:
				break
			theta += 6.0
		var tb: float = tbeat[beat]
		var hh := subject_h(S, bodies, key, tb)
		if beat == "windup":
			hw = hh
		elif beat == "contact":
			var d0 := float(key["d"])
			var sc := 1.0
			var nth := 0
			while hh < CLOSER * hw and nth < 10:   # closer: tighten while the head, chest and hand stay in frame
				sc *= 0.94
				var k2 := _place(centre, dirv, d0 * sc, f, pitch, fc[0]["pel"], -s * THIRD)
				if not _inside(k2, pts, 0.03):
					break
				key = k2
				hh = subject_h(S, bodies, key, tb)
				nth += 1
		var cut: float = float(bt["cut_" + {"windup": "w", "contact": "c", "recover": "r"}[beat]])
		var rules := []
		var label := ""
		match beat:
			"windup":
				rules = ["180-degree rule", "lead room"]
				label = "180-degree rule + lead room"
			"contact":
				rules = ["closer on contact", "180-degree rule", "lead room"]
				label = "closer on contact"
				if heavy:
					rules.append("low angle for power")
					label += " + low angle (power)"
			"recover":
				rules = ["hold the wide", "180-degree rule", "lead room"]
				label = "hold the wide"
		var why := "%s (%s, %.0f mm): %s. Camera %d deg off the action line on the striking hand's side (%s); the subject on the %s third, the strike moving %s." % [
			BEAT_WORD[beat], sp[4], f, " + ".join(rules), roundi(theta), "two fighters: the line between them" if two else "one fighter: his facing",
			"left" if s > 0 else "right", "right" if s > 0 else "left"]
		if beat == "contact":
			why += " Hand speed %.1f m/s%s." % [float(st["speed"]), " (heavy: from %.0f deg below)" % LOW_DEG if heavy else ""]
		var k3 := {"t": cut, "pos": key["pos"], "aim": key["aim"], "f": f}
		out["sugs"].append({"beat": beat, "label": "%s - %s" % [BEAT_WORD[beat], sp[4]], "size": sp[4], "rules": rules, "rule": label, "why": why,
			"cut": cut, "t": tb, "key": k3, "lead": s, "heavy": beat == "contact" and heavy, "subject_h": hh, "theta": theta})
	out["line"] = {"a": A, "dir": dir}
	out["side"] = side
	out["motion"] = motion
	out["beats"] = bt
	out["two"] = two
	return out


# ---------------------------------------------------------------- keeping

## the shot of a suggestion put into `shots` (the scene's list): cut on a whole frame; the first shot of an empty list starts at
## 0 s (a scene's first shot always does). false = a shot already starts on that frame (nothing written)
static func add_shot(shots: Array, sug: Dictionary, fps: int) -> bool:
	var fr := roundi(float(sug["cut"]) * fps)
	if shots.is_empty():
		fr = 0
	var t := float(fr) / float(fps)
	for sh in shots:
		if roundi(float(sh["t"]) * fps) == fr:
			return false
	var key: Dictionary = (sug["key"] as Dictionary).duplicate()
	key["t"] = t
	shots.insert(ShotCam.insert_index(shots, t), {"t": t, "name": "Auto: %s" % String(sug["label"]).to_lower(), "keys": [key]})
	return true
