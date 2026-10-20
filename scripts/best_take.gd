## best_take.gd - MY BEST TAKE (ROADMAP I38). Nick stars a clip; Kine measures what the starred clip does differently from his OTHER clips of
## the same kind and says it in plain words, ranked by how big the difference is; "make this one more like my best" nudges the open clip.
## KIND of a clip: "strike" when it has a strike card (StylePrint.kind_of), else "other"; only clips of the starred one's kind are the peers.
## FEATURES (one number per clip; a feature a clip cannot have, e.g. no wind-up, is left out for that clip):
##   windup_hold   s     mean hold of the wind-up cards                         lever: the wind-up holds
##   anticipation  x     wind-up move time / strike move time (the animator's anticipation ratio, TimingCoach.ANTIC_RATIO)  lever: the wind-up moves
##   strike_move   s     mean move time of the strike cards                     lever: the strike moves (inside BeatFight.strike_range, the cited human range)
##   follow        %     recover move / (strike move + recover move): the follow-through share   lever: the recover moves
##   guard_h       cm    guard hands over the chin (StylePrint._guard_stance)   lever: the upper-arm bend on the guard cards
##   stance        x     feet apart / hip width (StylePrint._guard_stance)      lever: the thigh abduction on the guard cards
##   peak_hand     m/s   fastest hand in the clip (StyleDial.hand_stats)        no lever of its own: it follows the strike time
## All timing features are ratios or means of MOVES and HOLDS, so a change to one lever does not move another feature's number.
## RANK by effect size = (starred - peers' median) / spread, the spread being the peers' standard deviation but never below FLOOR (ours: the
## smallest difference worth a sentence, so two peers that happen to agree do not make a hair's breadth look infinite). The top TOP are shown.
## NUDGE: each of the shown features that has a lever is moved toward the starred value on a COPY of the open clip (Preview plays the copy,
## Accept replaces the cards in ONE undo step). Nothing here writes under scenes/; the stars are one file under user:// (a test passes its own).
class_name BestTake
extends RefCounted

const STARS := "user://best_take_stars.json"
const MIN_PEERS := 2
const TOP := 5
const FEATS := ["windup_hold", "anticipation", "strike_move", "follow", "guard_h", "stance", "peak_hand"]
const FLOOR := {"windup_hold": 0.03, "anticipation": 0.25, "strike_move": 0.02, "follow": 5.0, "guard_h": 2.0, "stance": 0.08, "peak_hand": 0.4}
const LEVER := ["windup_hold", "anticipation", "strike_move", "follow", "guard_h", "stance"]
const NAME := {"windup_hold": "wind-up hold", "anticipation": "wind-up length", "strike_move": "strike time", "follow": "follow-through",
	"guard_h": "guard height", "stance": "stance width", "peak_hand": "peak hand speed"}
const PROBE_DEG := 6.0
const ARM_MAX := 45.0


# ---------------------------------------------------------------- the stars (user://, per scene path)

static func load_stars(path := STARS) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (d.get("stars", []) as Array).duplicate() if d is Dictionary else []


static func save_stars(stars: Array, path := STARS) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"stars": stars}, " "))
	f.close()
	return true


## star / unstar a scene path; returns whether it is starred now. The newest star is last.
static func toggle(scene_path: String, path := STARS) -> bool:
	var s := load_stars(path)
	var on := not s.has(scene_path)
	if on:
		s.append(scene_path)
	else:
		s.erase(scene_path)
	save_stars(s, path)
	return on


# ---------------------------------------------------------------- measuring

static func _mean(v: Array) -> float:
	var s := 0.0
	for x in v:
		s += float(x)
	return s / float(maxi(v.size(), 1))


static func _median(v: Array) -> float:
	var a := v.duplicate()
	a.sort()
	var n := a.size()
	if n == 0:
		return 0.0
	return float(a[n / 2]) if n % 2 == 1 else 0.5 * (float(a[n / 2 - 1]) + float(a[n / 2]))


static func _std(v: Array) -> float:
	if v.size() < 2:
		return 0.0
	var m := _mean(v)
	var s := 0.0
	for x in v:
		s += (float(x) - m) * (float(x) - m)
	return sqrt(s / float(v.size() - 1))


static func cards_of(S: Scene, kind: String) -> Array:
	var out := []
	for i in range(1, S.cards.size()):
		if StylePrint.kind_of(S, i) == kind:
			out.append(i)
	return out


static func guard_cards(S: Scene) -> Array:
	var out := []
	for i in S.cards.size():
		if StylePrint.kind_of(S, i) == "guard":
			out.append(i)
	return out


static func family(S: Scene) -> String:
	return "strike" if not cards_of(S, "strike").is_empty() else "other"


## guard hands (cm over the chin) and stance (x hip width), mean over the guard cards at their arrival
static func guard_now(S: Scene, B: Body, idx: Array) -> Array:
	var ts := S.times()
	var h := []
	var w := []
	for i in idx:
		var gs := StylePrint._guard_stance(S, B, float(ts[i][1]))
		h.append(float(gs[0]) * 100.0)
		w.append(float(gs[1]))
	return [_mean(h), _mean(w)]


## the features of scene S (poses B on the way: the caller restores it)
static func features(S: Scene, B: Body, with_speed := true) -> Dictionary:
	var out := {}
	var wu := cards_of(S, "windup")
	var st := cards_of(S, "strike")
	var rc := cards_of(S, "recover")
	var smv := _mean(st.map(func(i): return S.move_time(i)))
	if not wu.is_empty():
		out["windup_hold"] = _mean(wu.map(func(i): return float(S.cards[i]["hold"])))
	if not wu.is_empty() and not st.is_empty() and smv > 1e-6:
		out["anticipation"] = _mean(wu.map(func(i): return S.move_time(i))) / smv
	if not st.is_empty():
		out["strike_move"] = smv
	if not st.is_empty() and not rc.is_empty():
		var rmv := _mean(rc.map(func(i): return S.move_time(i)))
		out["follow"] = 100.0 * rmv / maxf(smv + rmv, 1e-6)
	var g := guard_cards(S)
	if not g.is_empty():
		var gs := guard_now(S, B, g)
		out["guard_h"] = gs[0]
		out["stance"] = gs[1]
	if with_speed and S.cards.size() >= 2:
		out["peak_hand"] = float(StyleDial.hand_stats(S, B)["peak"])
	return out


static func features_of_file(path: String, B: Body) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or (d.get("cards", []) as Array).size() < 2:
		return {}
	var S := Scene.new()
	S.from_dict(d)
	var out := features(S, B)
	out["_family"] = family(S)
	return out


# ---------------------------------------------------------------- ranking

## rank the starred clip's features against the peers' ([feature dicts]): [{"feat", "star", "usual", "spread", "effect", "n"}] biggest |effect| first
static func rank(star: Dictionary, peers: Array) -> Array:
	var rows := []
	for f in FEATS:
		if not star.has(f):
			continue
		var vals := []
		for p in peers:
			if (p as Dictionary).has(f):
				vals.append(float(p[f]))
		if vals.size() < MIN_PEERS:
			continue
		var usual := _median(vals)
		var spread := maxf(_std(vals), float(FLOOR[f]))
		rows.append({"feat": f, "star": float(star[f]), "usual": usual, "spread": spread, "effect": (float(star[f]) - usual) / spread, "n": vals.size()})
	rows.sort_custom(func(a, b): return absf(float(a["effect"])) > absf(float(b["effect"])) or (absf(float(a["effect"])) == absf(float(b["effect"])) and String(a["feat"]) < String(b["feat"])))
	return rows


## a plain sentence for one row
static func words(r: Dictionary) -> String:
	var s: float = r["star"]
	var u: float = r["usual"]
	var d := s - u
	match String(r["feat"]):
		"windup_hold":
			return "your best take holds the wind-up %.2f s %s than your usual %.2f s" % [absf(d), "longer" if d > 0.0 else "shorter", u]
		"anticipation":
			return "your best take winds up for %.1f× the strike time, your usual is %.1f×" % [s, u]
		"strike_move":
			return "your best take strikes in %.2f s, %.2f s %s than your usual %.2f s" % [s, absf(d), "slower" if d > 0.0 else "faster", u]
		"follow":
			return "your best take gives the follow-through %.0f%% of strike plus recovery, your usual is %.0f%%" % [s, u]
		"guard_h":
			return "your best take keeps the guard hands %.0f cm %s than your usual, which is %.0f cm %s the chin" % [absf(d), "higher" if d > 0.0 else "lower", absf(u), "above" if u >= 0.0 else "below"]
		"stance":
			return "your best take stands %.2f× hip width %s than your usual %.2f× hip width" % [absf(d), "wider" if d > 0.0 else "narrower", u]
		"peak_hand":
			return "your best take's fastest hand peaks at %.1f m/s, %.1f m/s %s than your usual %.1f m/s" % [s, absf(d), "faster" if d > 0.0 else "slower", u]
	return ""


# ---------------------------------------------------------------- nudging

static func _edit_joint(c: Dictionary, j: String, axis: String, add: float) -> void:
	var jt: Dictionary = (c["pose"] as Dictionary)["joints"]
	if not jt.has(j):
		jt[j] = {"bend": 0.0, "side": 0.0, "twist": 0.0}
	jt[j][axis] = float(jt[j].get(axis, 0.0)) + add


## move the guard cards' feature `kind` ("guard_h" / "stance") on S to `target` with a posture lever; returns the value reached
static func _guard_lever(S: Scene, B: Body, kind: String, target: float) -> float:
	var g := guard_cards(S)
	if g.is_empty():
		return NAN
	var which := 0 if kind == "guard_h" else 1
	var pats: Array = [[["upperarm_l", "bend", 1.0], ["upperarm_r", "bend", 1.0]]] if kind == "guard_h" else [
		[["thigh_l", "side", 1.0], ["thigh_r", "side", 1.0]], [["thigh_l", "side", 1.0], ["thigh_r", "side", -1.0]]]
	var cur := float(guard_now(S, B, g)[which])
	for _it in 3:
		var err := target - cur
		if absf(err) < (0.3 if which == 0 else 0.01):
			break
		# probe: a step of PROBE_DEG on a copy, keep the pattern whose effect is biggest
		var best := {"slope": 0.0, "pat": []}
		for pat in pats:
			var T := S.clone()
			for i in g:
				for e in pat:
					_edit_joint(T.cards[i], String(e[0]), String(e[1]), PROBE_DEG * float(e[2]))
			var sl := (float(guard_now(T, B, g)[which]) - cur) / PROBE_DEG
			if absf(sl) > absf(float(best["slope"])):
				best = {"slope": sl, "pat": pat}
		if absf(float(best["slope"])) < 1e-4:
			break
		var a := clampf(err / float(best["slope"]), -ARM_MAX, ARM_MAX)
		for i in g:
			for e in best["pat"]:
				_edit_joint(S.cards[i], String(e[0]), String(e[1]), a * float(e[2]))
		cur = float(guard_now(S, B, g)[which])
	return cur


static func _scale_moves(S: Scene, idx: Array, k: float, lo := TimingCoach.MIN_MOVE, hi := INF) -> void:
	for i in idx:
		var mv := S.move_time(i)
		S.cards[i]["move"] = snappedf(clampf(mv * k, lo, hi), 0.001)


## the nudge of S toward the starred features, for the features in `feats` (rows' names): {"scene": copy, "changes": [{"feat", "from", "to", "got"}]}
static func nudge(S: Scene, B: Body, star: Dictionary, feats: Array) -> Dictionary:
	var T := S.clone()
	var ch := []
	var now := features(T, B, false)
	for f in ["guard_h", "stance"]:   # posture first: it does not touch the timing features
		if feats.has(f) and now.has(f) and star.has(f):
			var got := _guard_lever(T, B, f, float(star[f]))
			ch.append({"feat": f, "from": float(now[f]), "to": float(star[f]), "got": got})
	var st := cards_of(T, "strike")
	if feats.has("strike_move") and now.has("strike_move") and star.has("strike_move") and not st.is_empty():
		var k := float(star["strike_move"]) / maxf(float(now["strike_move"]), 1e-6)
		for i in st:
			var rg := BeatFight.strike_range(T, B, i)
			_scale_moves(T, [i], k, maxf(TimingCoach.MIN_MOVE, float(rg[0])), maxf(float(rg[1]), T.move_time(i)))
		ch.append({"feat": "strike_move", "from": float(now["strike_move"]), "to": float(star["strike_move"]), "got": float(features(T, B, false)["strike_move"])})
	var wu := cards_of(T, "windup")
	if feats.has("windup_hold") and now.has("windup_hold") and star.has("windup_hold"):
		var dh := float(star["windup_hold"]) - float(now["windup_hold"])
		for i in wu:
			T.cards[i]["hold"] = snappedf(maxf(0.0, float(T.cards[i]["hold"]) + dh), 0.001)
		ch.append({"feat": "windup_hold", "from": float(now["windup_hold"]), "to": float(star["windup_hold"]), "got": float(features(T, B, false)["windup_hold"])})
	if feats.has("anticipation") and now.has("anticipation") and star.has("anticipation") and not wu.is_empty():
		var smv := _mean(st.map(func(i): return T.move_time(i)))
		var cur := _mean(wu.map(func(i): return T.move_time(i)))
		_scale_moves(T, wu, float(star["anticipation"]) * smv / maxf(cur, 1e-6))
		ch.append({"feat": "anticipation", "from": float(now["anticipation"]), "to": float(star["anticipation"]), "got": float(features(T, B, false)["anticipation"])})
	var rc := cards_of(T, "recover")
	if feats.has("follow") and now.has("follow") and star.has("follow") and not rc.is_empty() and not st.is_empty():
		var smv := _mean(st.map(func(i): return T.move_time(i)))
		var cur := _mean(rc.map(func(i): return T.move_time(i)))
		var sh := clampf(float(star["follow"]) / 100.0, 0.05, 0.95)
		_scale_moves(T, rc, sh * smv / (1.0 - sh) / maxf(cur, 1e-6))
		ch.append({"feat": "follow", "from": float(now["follow"]), "to": float(star["follow"]), "got": float(features(T, B, false)["follow"])})
	return {"scene": T, "changes": ch}
