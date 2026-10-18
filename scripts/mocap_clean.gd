## MOCAP FOOT LOCK + CLEANUP REPORT (round 42, GATES XX7; UPGRADES_300 #299, #305).
## A scene imported from a .bvh (BvhImport) has a card per frame. Raw mocap has two faults an animator fixes by hand:
##   FOOT LOCK: a foot that is on the floor but creeps (the capture's drift, the hips' noise). Contacts are found per foot
##     from the sole's height and the ball's speed; each contact is PLANTED with the scene's own planted-feet mechanism
##     (a card's "plant" list, Scene._planted / Body.plant: the foot stays where it stood in the first card of the contact).
##   CLEANUP REPORT: per frame, per joint: POPs (a one-frame spike that comes straight back), FLIPs (a ~360 deg Euler jump or a
##     quaternion sign flip in the file, or in the scene a number that jumps over 180 deg for nearly the same rotation, which
##     makes the blend between the two cards go the long way round), and LIMBS THROUGH THE BODY (Body.contacts, the same
##     parts-inside-each-other test Check and the Fix use). Each finding: frame, joint, size, suggested fix.
## The thresholds are ours (stated at each constant), not a published standard; the FOOT SLIDE bar itself is Rulebook's
## (Karunratanakul et al. 2023, 2.5 cm), measured before and after.
class_name MocapClean
extends RefCounted

const CONTACT_H := 0.03     # m: the lowest sole point this close to the floor = the foot is down (ours; Check's FOOT_DOWN is 5 cm)
const CONTACT_V := 0.2      # m/s: and the ball moves this slowly along the floor = meant to stand (ours; Check's FOOT_STILL is 0.3 m/s)
const MIN_RUN := 3          # frames: a shorter contact is a tap, not worth a lock
const POP_SPEED := 1500.0   # deg/s: a joint that turns this fast INTO a frame and straight back out (the frame is an outlier)
const POP_BACK := 0.5       # ...and the two neighbours are less than this fraction of that step apart
const FLIP_DEG := 180.0     # deg: a rotation number that jumps more than this between frames while the rotation hardly changes
const FLIP_ROT := 90.0      # deg: "hardly changes" = the real rotation moved less than this
const TRIM := 4            # frames cut off the end of a contact (see contacts())
const HELD := 0.01         # m: a locked foot that still creeps more than this is reported as not held
const THROUGH_MM := 5.0     # mm: parts inside each other deeper than this are a finding (Body.contacts already ignores under 1 mm)


## every card's joint rotations, the feet and the parts-inside-each-other, from the scene as it plays at the card times
static func frames(S: Scene, B: Body, want_through := true) -> Dictionary:
	var ts := S.times()
	var n := S.cards.size()
	var out := {"n": n, "t": [], "q": [], "ang": [], "ball_l": [], "ball_r": [], "sole_l": [], "sole_r": [], "bh_l": [], "bh_r": [], "hh_l": [], "hh_r": [], "through": []}
	for i in n:
		var t: float = ts[i][1]
		S.apply(B, t)
		out["t"].append(t)
		var q := {}
		var an := {}
		for j in Body.ORDER:
			q[j] = B.compose(j, B.ang[j])
			an[j] = B.ang[j]
		out["q"].append(q)
		out["ang"].append(an)
		out["ball_l"].append(B.P["ball_l"])
		out["ball_r"].append(B.P["ball_r"])
		for sd in ["_l", "_r"]:
			out["sole" + sd].append(_sole(B, sd))
			out["hh" + sd].append((B.P["foot" + sd] as Vector3).y - (B.p0["foot" + sd] as Vector3).y)
			out["bh" + sd].append((B.P["ball" + sd] as Vector3).y - (B.p0["ball" + sd] as Vector3).y)
		var th := []
		if want_through:
			for c in B.contacts():
				if float(c[2]) * 1000.0 > THROUGH_MM:
					th.append(c)
		out["through"].append(th)
	return out


## one foot's lowest sole point above where it rests (heel, ball, toe tip): Body.sole_low for one side
static func _sole(B: Body, sd: String) -> float:
	var low: float = (B.P["foot" + sd] as Vector3).y - (B.p0["foot" + sd] as Vector3).y
	low = minf(low, (B.E["ball" + sd] as Vector3).y - (B.e0["ball" + sd] as Vector3).y)
	return minf(low, (B.P["ball" + sd] as Vector3).y - (B.p0["ball" + sd] as Vector3).y)


## the floor height this clip stands on: the 20th percentile of the lower foot's sole height over the clip (one foot is on
## the ground most of the time in a walk or a stand; the lowest single frame is no good, a noisy hips or a stray frame
## sinks it 2 cm and puts every real contact out of reach). A clip that is mostly airborne has no such floor: say so, not here.
static func floor_of(fr: Dictionary) -> float:
	var low := []
	for i in int(fr["n"]):
		low.append(minf(float(fr["sole_l"][i]), float(fr["sole_r"][i])))
	low.sort()
	return low[int(low.size() * 0.2)] if not low.is_empty() else 0.0


## contacts per foot: [{"foot": "_l", "a": first card, "b": last card}], from the sole's height above the clip's floor and the
## ball's speed along the floor (forward step, so the first frame of a stand is the one the foot arrives on)
static func contacts(fr: Dictionary) -> Array:
	var out := []
	var n: int = fr["n"]
	var fl := floor_of(fr)
	for sd in ["_l", "_r"]:
		var down := []
		for i in n:
			var j := mini(i, n - 2)
			var d: Vector3 = (fr["ball" + sd][j + 1] as Vector3) - (fr["ball" + sd][j] as Vector3)
			var dt: float = maxf(float(fr["t"][j + 1]) - float(fr["t"][j]), 1e-6)
			down.append(float(fr["sole" + sd][i]) - fl < CONTACT_H and float(fr["bh" + sd][i]) - fl < CONTACT_H and Vector2(d.x, d.z).length() / dt < CONTACT_V)
		var i := 0
		while i < n:
			if not down[i]:
				i += 1
				continue
			var a := i
			while i < n and down[i]:
				i += 1
			# the last TRIM frames are the toe-off: the foot is about to leave and the leg is at full stretch, where the planting
			# solver misses by up to 7 mm (measured on the clean walk), so they are left to the capture. 2 -> 4 in round 43:
			# the walk now pivots on the toes before it leaves (heel rise to toe-off ~0.13 s, as people), and planted flat
			# through those frames the lock slid 1.67 cm (bar 1)
			if i - 1 - TRIM - a + 1 >= MIN_RUN:
				out.append({"foot": sd, "a": a, "b": i - 1 - TRIM})
	out.sort_custom(func(x, y): return x["a"] < y["a"])
	return out


## plant each contact: cards a+1..b+1 get the foot in their "plant" list, so Scene._planted holds it where it stood in card a.
## (Scene._planted picks the card whose move starts at t, so the instant of card b belongs to card b+1: that card is planted
## too, and the foot is let go at card b+1, where the capture had it lift off.) Returns how many cards were marked.
static func lock(S: Scene, cons: Array) -> int:
	var n := 0
	for c in cons:
		for i in range(int(c["a"]) + 1, mini(int(c["b"]) + 2, S.cards.size())):
			var pl: Array = S.cards[i].get("plant", [])
			if not c["foot"] in pl:
				var np := pl.duplicate()
				np.append(c["foot"])
				S.cards[i]["plant"] = np
				n += 1
	return n


## the worst creep of each contact, in metres, measured on the scene as it plays (4 sub-frames per card): how far the ball
## gets from where it stood in the contact's first card, along the floor. [[contact, metres], ...]
static func contact_slide(S: Scene, B: Body, cons: Array, fr: Dictionary) -> Array:
	var out := []
	for c in cons:
		var key := "ball" + String(c["foot"])
		S.apply(B, fr["t"][c["a"]])
		var p0: Vector3 = B.P[key]
		var worst := 0.0
		var t0: float = fr["t"][c["a"]]
		var t1: float = fr["t"][c["b"]]
		var k := 0
		var steps: int = (int(c["b"]) - int(c["a"])) * 4
		while k <= steps:
			S.apply(B, lerpf(t0, t1, float(k) / maxf(steps, 1)))
			var d: Vector3 = (B.P[key] as Vector3) - p0
			worst = maxf(worst, Vector2(d.x, d.z).length())
			k += 1
		out.append([c, worst])
	return out


## Check's FOOT SLIDE rule on the scene: {"n": findings, "worst": metres of the worst, "list": [findings]}
static func slide_of(S: Scene, B: Body) -> Dictionary:
	var sm := Rulebook.sample(S, B)
	var list := Rulebook.rule_feet(sm)
	var worst := 0.0
	for f in list:
		worst = maxf(worst, float(f["size"]) if f.has("size") else float(f.get("v", 0.0)))
	return {"n": list.size(), "worst": worst, "list": list}


static func _step(fr: Dictionary, j: String, a: int, b: int) -> float:
	return Rulebook.ang_deg(fr["q"][a][j], fr["q"][b][j])


## POPs: a joint turns POP_SPEED deg/s or faster into a frame and out of it again, and the frames either side of it are
## close together (the frame is the outlier). [{"kind": "POP", "frame", "joint", "size" (deg), "fix"}]
static func pops(fr: Dictionary) -> Array:
	var out := []
	var n: int = fr["n"]
	for i in range(1, n - 1):
		var dt: float = float(fr["t"][i + 1]) - float(fr["t"][i - 1])
		var dti: float = float(fr["t"][i]) - float(fr["t"][i - 1])
		var dto: float = float(fr["t"][i + 1]) - float(fr["t"][i])
		if dti <= 0.0 or dto <= 0.0 or dt <= 0.0:
			continue
		for j in Body.ORDER:
			var a_in := _step(fr, j, i - 1, i)
			var a_out := _step(fr, j, i, i + 1)
			var m := minf(a_in, a_out)
			if m / maxf(dti, dto) < POP_SPEED:
				continue
			if _step(fr, j, i - 1, i + 1) < POP_BACK * m:
				out.append({"kind": "POP", "frame": i, "joint": j, "size": m,
					"fix": "frame %d turns %s %.0f deg off its neighbours for one frame (%.0f deg/s in, back out): replace it with the middle of frames %d and %d (Clean up mocap does this)" % [i, j, m, m / dti, i - 1, i + 1]})
	return out


## FLIPs in the scene: a rotation number (bend, side or twist) that jumps over FLIP_DEG between two cards while the rotation
## itself moves under FLIP_ROT. The cards are fine one by one but the move between them swings the long way round.
static func scene_flips(S: Scene, B: Body) -> Array:
	var out := []
	var prev := {}
	for i in S.cards.size():
		var jd: Dictionary = S.cards[i]["pose"].get("joints", {})
		var now := {}
		for j in Body.ORDER:
			if not jd.has(j):
				continue
			var v := Vector3(float(jd[j].get("bend", 0.0)), float(jd[j].get("side", 0.0)), float(jd[j].get("twist", 0.0)))
			now[j] = [v, B.compose(j, v)]
			if not prev.has(j):
				continue
			var d: Vector3 = v - (prev[j][0] as Vector3)
			var big := maxf(absf(d.x), maxf(absf(d.y), absf(d.z)))
			var rot := Rulebook.ang_deg(prev[j][1], now[j][1])
			if big > FLIP_DEG and rot < FLIP_ROT:
				out.append({"kind": "FLIP", "frame": i, "joint": j, "size": big,
					"fix": "%s jumps %.0f deg in its numbers between frames %d and %d though the rotation barely changes (%.1f deg): the move between them swings the long way round; give frame %d the same rotation in the other turn (+-360 on that number)" % [j, big, i - 1, i, rot, i]})
		prev = now
	return out


## FLIPs in the file: a ~360 deg jump of an Euler channel between two rows, or a quaternion sign flip (the rotation read from
## the row is the negative of the row before while the rotation itself moved under FLIP_ROT). One finding per frame and joint.
## BvhImport turns every row into the nearest rotation, so a flip in the file is gone once imported: this reads the file.
static func file_flips(bvh: Dictionary, B: Body) -> Array:
	var out := []
	if not bvh.get("ok", false):
		return out
	var rows: Array = bvh["frames"]
	for j in bvh["joints"]:
		if not B.lim.has(j["name"]):
			continue
		var chs: Array = j["channels"]
		for i in range(1, rows.size()):
			var big := 0.0
			for k in chs.size():
				if String(chs[k]).ends_with("rotation"):
					big = maxf(big, absf(rows[i][int(j["start"]) + k] - rows[i - 1][int(j["start"]) + k]))
			var q0 := BvhImport.rotation(j, rows[i - 1])
			var q1 := BvhImport.rotation(j, rows[i])
			var sign_flip := q0.dot(q1) < 0.0
			var real := rad_to_deg(2.0 * acos(clampf(absf(q0.dot(q1)), 0.0, 1.0)))
			if real < FLIP_ROT and (big > FLIP_DEG or sign_flip):
				out.append({"kind": "FLIP", "frame": i, "joint": j["name"], "size": big if big > FLIP_DEG else 360.0,
					"fix": "%s: the file's rotation jumps %.0f deg in a channel between rows %d and %d though the pose moves %.1f deg (an Euler wrap / quaternion sign flip): unwrap the channel by 360 from row %d on (an importer turns it to the nearest rotation, so the imported scene is already right)" % [j["name"], big, i - 1, i, real, i]})
	return out


## limbs through the body: runs of cards in which two parts are inside each other deeper than THROUGH_MM. One finding per
## pair and run, at the deepest card. [{"kind": "THROUGH BODY", "frame", "joint" (the pair), "size" (mm), "frames": run length}]
static func through(fr: Dictionary) -> Array:
	var out := []
	var open := {}   # pair -> index into out
	for i in int(fr["n"]):
		var now := {}
		for c in fr["through"][i]:
			var key := "%s|%s" % [c[0], c[1]]
			now[key] = true
			var mm := float(c[2]) * 1000.0
			if open.has(key) and out[open[key]]["last"] == i - 1:
				var f: Dictionary = out[open[key]]
				f["last"] = i
				f["frames"] += 1
				if mm > f["size"]:
					f["size"] = mm
					f["frame"] = i
			else:
				open[key] = out.size()
				out.append({"kind": "THROUGH BODY", "frame": i, "joint": key.replace("|", " into "), "size": mm, "last": i, "frames": 1, "fix": ""})
	for f in out:
		f["fix"] = "%s are %.0f mm inside each other for %d frame(s) around frame %d: Check's Fix (clearance) adds a pass-by pose, or lift the limb out by hand" % [f["joint"], f["size"], f["frames"], f["frame"]]
	return out


## the report for a scene (and the BVH it came from, if you have it): {"pops", "flips", "through", "contacts", "text"}
static func analyse(S: Scene, B: Body, bvh := {}) -> Dictionary:
	var fr := frames(S, B)
	var cons := contacts(fr)
	var p := pops(fr)
	var fl := file_flips(bvh, B) if not bvh.is_empty() else []
	fl += scene_flips(S, B)
	var th := through(fr)
	return {"frames": fr, "contacts": cons, "pops": p, "flips": fl, "through": th, "text": summary(S.cards.size(), cons, p, fl, th)}


static func summary(n: int, cons: Array, p: Array, fl: Array, th: Array) -> String:
	var s := "%d frames: %d foot contacts, %d pops, %d flips, %d limbs through the body" % [n, cons.size(), p.size(), fl.size(), th.size()]
	var first := ""
	for list in [p, fl, th]:
		if not list.is_empty() and first == "":
			first = "; first: %s at frame %d (%s)" % [list[0]["kind"].to_lower(), list[0]["frame"], list[0]["joint"]]
	return s + first


## replace each popped frame's joint with the middle of its two neighbours (their rotation numbers; a pop is one frame,
## so the neighbours are close). Returns how many joints were repaired.
static func repair_pops(S: Scene, pp: Array) -> int:
	var n := 0
	for f in pp:
		var i: int = f["frame"]
		var j: String = f["joint"]
		var a: Dictionary = S.cards[i - 1]["pose"]["joints"]
		var b: Dictionary = S.cards[i + 1]["pose"]["joints"]
		if not (a.has(j) and b.has(j)):
			continue
		var m := {}
		for k in ["bend", "side", "twist"]:
			m[k] = (float(a[j].get(k, 0.0)) + float(b[j].get(k, 0.0))) * 0.5
		S.cards[i]["pose"]["joints"][j] = m
		n += 1
	return n


## the whole clean-up on a scene: report, repair the pops, lock the feet. Returns the report plus "slide0", "slide1" (Check's
## FOOT SLIDE before and after), "locked" (cards marked), "repaired" (joints), "release" (worst jump, m, when a foot is let go)
static func clean(S: Scene, B: Body, bvh := {}) -> Dictionary:
	var r := analyse(S, B, bvh)
	r["slide0"] = slide_of(S, B)
	r["repaired"] = repair_pops(S, r["pops"])
	r["locked"] = lock(S, r["contacts"])
	r["slide1"] = slide_of(S, B)
	r["release"] = release_jump(S, B, r["contacts"], r["frames"])
	# a straight leg cannot be held once the hips travel past its reach: those contacts are named, not hidden
	r["unheld"] = contact_slide(S, B, r["contacts"], r["frames"]).filter(func(e): return e[1] > HELD)
	r["text"] += "; foot lock: %d cards planted, FOOT SLIDE %d -> %d findings%s" % [r["locked"], r["slide0"]["n"], r["slide1"]["n"], "" if r["unheld"].is_empty() else ", %d contacts still creep over %.0f cm (the leg is straight: lower the hips)" % [r["unheld"].size(), HELD * 100.0]]
	return r


## when a planted foot is let go it is where the capture had it: how far the ball moves in the one step from the last
## planted instant (card b) to the next card (m). The lock moves the whole creep of a contact into this step.
static func release_jump(S: Scene, B: Body, cons: Array, fr: Dictionary) -> float:
	var worst := 0.0
	for c in cons:
		var b: int = c["b"]
		if b + 2 >= int(fr["n"]):
			continue
		var key := "ball" + String(c["foot"])
		S.apply(B, fr["t"][b])
		var p: Vector3 = B.P[key]
		S.apply(B, fr["t"][b + 2])
		var d: Vector3 = (B.P[key] as Vector3) - p
		worst = maxf(worst, Vector2(d.x, d.z).length())
	return worst
