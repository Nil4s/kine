## style_print.gd - LEARN MY STYLE (ROADMAP I17). Reads Nick's own clips (scenes/*.json, READ ONLY) and computes a fingerprint:
##   per move kind (strike / wind-up / guard / recover / step; the kind comes from the card's name with the same word lists the
##   next-pose ghosts use (NextPose.PHASES) and the timing coach (TimingCoach.STRIKE_WORDS)):
##       his MEDIAN move time and hold (seconds),
##   on the guard cards: the guard hands' height relative to the chin (cm; the chin sits 0.23 m under the top of the head: the
##       menton-vertex height, 0.130 x stature, Winter 2009 Table 4.1 -> 0.2275 m at 1.75 m) and the stance width (feet apart
##       over hip width, both from the same pose),
##   and his most common card-to-card transitions (kind -> kind, counted over adjacent cards).
## Where it goes: user://style_print.json (a test passes its own path with the PID). Used by (1) new cards (Add card / Next poses)
## take his median for their kind instead of the fixed default, (2) "Use my style" retimes a clip toward the medians, never outside
## the timing coach's human range, (3) the like-Nick / neutral toggle.  A fingerprint from fewer than 3 clips is not enough to learn from.
## Read only: nothing here writes under scenes/, poses/ or data/; save() writes the one path it is given.
class_name StylePrint
extends RefCounted

const PATH := "user://style_print.json"
const MIN_CLIPS := 3      # fewer clips than this: not enough to learn a style from
const KINDS := ["strike", "windup", "guard", "recover", "step"]
const LABEL := {"strike": "strike", "windup": "wind-up", "guard": "guard", "recover": "recover", "step": "step"}
const STEP_WORDS := ["step", "walk", "advance", "retreat", "shuffle", "pivot", "lunge", "footwork"]
const CHIN_BELOW_TOP := 0.23   # m, see the header
const TOP_TRANSITIONS := 5


## the kind of a card named `nm`, or ""
static func kind_of_name(nm: String) -> String:
	var l := nm.to_lower()
	for w in STEP_WORDS:
		if l.contains(w):
			return "step"
	for w in TimingCoach.STRIKE_WORDS:
		if l.contains(w):
			return "strike"
	match NextPose.phase_of(nm):
		"contact":
			return "strike"
		"windup":
			return "windup"
		"ready":
			return "guard"
		"recover", "follow":
			return "recover"
	return ""


static func kind_of(S: Scene, i: int) -> String:
	var k := kind_of_name(String(S.cards[i]["name"]))
	if k == "" and i >= 1 and TimingCoach.is_strike(S, i):
		return "strike"
	return k


## Nick's clips: scenes/*.json at the top of `dir`, not a work-in-progress (_wip, zz_, a leading _) and not a test scene
static func clip_paths(dir := "res://scenes/") -> Array:
	var out := []
	for fn in DirAccess.get_files_at(dir):
		var l := fn.to_lower()
		if not l.ends_with(".json") or l.begins_with("zz_") or l.begins_with("_") or l.contains("_wip") or l.contains("test"):
			continue
		out.append(dir + fn)
	out.sort()
	return out


static func _median(v: Array) -> float:
	if v.is_empty():
		return 0.0
	var a := v.duplicate()
	a.sort()
	var n := a.size()
	return float(a[n / 2]) if n % 2 == 1 else 0.5 * (float(a[n / 2 - 1]) + float(a[n / 2]))


## guard height (m, hands over the chin) and stance (feet apart / hip width) of the body posed by S at time t
static func _guard_stance(S: Scene, B: Body, t: float) -> Array:
	S.apply(B, t)
	B.fk()
	var chin: float = (B.E["head"] as Vector3).y - CHIN_BELOW_TOP
	var h := 0.5 * (float((B.P["hand_l"] as Vector3).y) + float((B.P["hand_r"] as Vector3).y)) - chin
	var hip := (B.P["thigh_l"] as Vector3).distance_to(B.P["thigh_r"])
	var fl: Vector3 = B.P["foot_l"]
	var fr: Vector3 = B.P["foot_r"]
	var w := Vector2(fl.x - fr.x, fl.z - fr.z).length() / maxf(hip, 0.01)
	return [h, w]


## the fingerprint of the given scene files (read only). B is posed on the way.
static func compute(paths: Array, B: Body) -> Dictionary:
	var mv := {}
	var hd := {}
	var kclips := {}
	for k in KINDS:
		mv[k] = []
		hd[k] = []
		kclips[k] = {}
	var heights := []
	var widths := []
	var gclips := {}
	var trans := {}
	var used := {}
	for p in paths:
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(p)))
		if not (d is Dictionary) or (d.get("cards", []) as Array).size() < 2:
			continue
		var S := Scene.new()
		S.from_dict(d)
		var cname := String(p).get_file().get_basename()
		var ts := S.times()
		var prev := ""
		for i in S.cards.size():
			var k := kind_of(S, i)
			if k != "" and i >= 1 and float(S.cards[i]["move"]) > 0.0:   # a time he set himself, not the auto one
				(mv[k] as Array).append(float(S.cards[i]["move"]))
				(hd[k] as Array).append(float(S.cards[i]["hold"]))
				(kclips[k] as Dictionary)[cname] = true
				used[cname] = true
			if k == "guard":
				var gs := _guard_stance(S, B, float(ts[i][1]))
				heights.append(gs[0])
				widths.append(gs[1])
				gclips[cname] = true
				used[cname] = true
			if k != "" and prev != "":
				var key := prev + ">" + k
				trans[key] = int(trans.get(key, 0)) + 1
			prev = k
	var kinds := {}
	for k in KINDS:
		var a: Array = mv[k]
		if a.is_empty():
			continue
		kinds[k] = {"move": snappedf(_median(a), 0.001), "hold": snappedf(_median(hd[k]), 0.001), "n": a.size(), "clips": (kclips[k] as Dictionary).size()}
	var tl := []
	for key in trans:
		tl.append([key, int(trans[key])])
	tl.sort_custom(func(x, y): return int(x[1]) > int(y[1]) or (int(x[1]) == int(y[1]) and String(x[0]) < String(y[0])))
	var out := {"clips": used.size(), "kinds": kinds, "transitions": tl.slice(0, TOP_TRANSITIONS)}
	if not heights.is_empty():
		out["guard"] = {"hand_cm": snappedf(_median(heights) * 100.0, 0.1), "stance": snappedf(_median(widths), 0.01), "n": heights.size(), "clips": gclips.size()}
	out["enough"] = used.size() >= MIN_CLIPS
	return out


static func save(fp: Dictionary, path := PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(fp, " "))
	f.close()
	return true


static func load_print(path := PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


## his {"move", "hold"} for a kind, or {} (not enough clips, or he has none of this kind)
static func target(fp: Dictionary, kind: String) -> Dictionary:
	if not bool(fp.get("enough", false)):
		return {}
	var k: Variant = (fp.get("kinds", {}) as Dictionary).get(kind)
	return k if k is Dictionary else {}


## "from N clips" or the not-enough sentence
static func source_text(n: int) -> String:
	if n < MIN_CLIPS:
		return "not enough to learn from yet (%d clip%s; it needs %d)" % [n, "" if n == 1 else "s", MIN_CLIPS]
	return "from %d clips" % n


## the retime of scene S toward the fingerprint (read only): [{"card", "kind", "mv_from", "mv_to", "hd_from", "hd_to"}].
## A strike's move stays inside the timing coach's range (BeatFight.strike_range: the cited fist speeds); the wind-up before it keeps
## at least ANTIC_RATIO x the strike and the settle after it SETTLE_RATIO x, as the coach asks. A card never moves AWAY from his median.
static func plan(S: Scene, B: Body, fp: Dictionary) -> Array:
	var out := []
	if not bool(fp.get("enough", false)):
		return out
	var newmv := {}
	for i in range(1, S.cards.size()):
		var k := kind_of(S, i)
		var tg := target(fp, k)
		if tg.is_empty():
			continue
		var cur := S.move_time(i)
		var want := float(tg["move"])
		if k == "strike":
			var rg := BeatFight.strike_range(S, B, i)
			want = clampf(want, float(rg[0]), float(rg[1]))
		want = maxf(want, TimingCoach.MIN_MOVE)
		newmv[i] = want
	for i in newmv.keys():   # the coach's ratios around a strike
		if kind_of(S, i) != "strike":
			continue
		if newmv.has(i - 1) and i - 1 >= 1 and kind_of(S, i - 1) == "windup":
			newmv[i - 1] = maxf(float(newmv[i - 1]), TimingCoach.ANTIC_RATIO * float(newmv[i]))
		if newmv.has(i + 1) and kind_of(S, i + 1) == "recover":
			newmv[i + 1] = maxf(float(newmv[i + 1]), TimingCoach.SETTLE_RATIO * float(newmv[i]))
	for i in newmv.keys():
		var k := kind_of(S, i)
		var tg := target(fp, k)
		var cur := S.move_time(i)
		var med := float(tg["move"])
		var to := snappedf(float(newmv[i]), 0.001)
		if absf(to - med) > absf(cur - med) + 0.0005:
			to = snappedf(cur, 0.001)   # the human range or the coach's ratio keeps this card from his median: leave it
		var hcur := float(S.cards[i]["hold"])
		var hto := snappedf(float(tg["hold"]), 0.001)
		if absf(to - cur) < 0.0005 and absf(hto - hcur) < 0.0005:
			continue
		out.append({"card": i, "kind": k, "mv_from": snappedf(cur, 0.001), "mv_to": to, "hd_from": snappedf(hcur, 0.001), "hd_to": hto})
	out.sort_custom(func(x, y): return int(x["card"]) < int(y["card"]))
	return out


## write the plan on scene S (the caller makes the undo step)
static func apply_plan(S: Scene, pl: Array) -> void:
	for p in pl:
		var c: Dictionary = S.cards[int(p["card"])]
		c["move"] = float(p["mv_to"])
		c["hold"] = float(p["hd_to"])
		c.erase("usual")


static func with_applied(S: Scene, pl: Array) -> Scene:
	var c := S.clone()
	apply_plan(c, pl)
	return c
