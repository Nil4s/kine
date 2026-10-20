## combo_mine.gd - MY COMBOS (ROADMAP I23). Reads Nick's own clips (scenes/*.json, READ ONLY; StylePrint.clip_paths skips _wip / test /
## zz_ files) and finds the card sequences he repeats.
##   CLASSIFY each card (the first card, the start pose, is left out):
##     a STRIKE (FightRhythm.strike_cards = BeatFight.contacts + the cards named for a kind of strike, or StylePrint's "strike") -> its KIND
##     word (FightRhythm.KIND_WORDS of the name: jab / cross / hook ...; none: "kick" when a foot travels furthest, else "strike"), its LIMB
##     (hand / foot) and SIDE (l / r) from the end effector that travels furthest in the card's move (FightRhythm._limb, I19's idea);
##     any other card -> StylePrint.kind_of (wind-up / guard / recover / step), or a block word -> "block". Cards with no kind
##     ("fix (skin)") are skipped; at most MAX_SKIP of them may sit between two cards of one combo.
##   N-GRAMS n = 2..4 of consecutive classified cards with at least one strike. The key uses the strikes' side RELATIVE to the first
##     strike of the gram (same / opposite), so a jab-cross thrown left-first and right-first is the same combo, mirrored.
##     An occurrence may not overlap an earlier one of the same combo in the same clip (counted once). A combo is a combo at count >= 2
##     (in two clips, or twice in one). A shorter gram all of whose occurrences sit inside a longer combo is dropped (the longer one wins).
##   TIMING per card of the combo: the MEAN of his move and hold over the occurrences (Scene.move_time, so an auto move counts as the time it plays).
##   NAME in plain words: "wind-up-strike-recover, your 0.40/0.15/0.18 rhythm, used 3 times in 2 clips".
## The poses come from the first occurrence (his own cards, read again from the clip when inserted); mirrored (Scene.mirror_card) when the
## card the combo goes after is on the other side than the combo's first strike. Nothing here writes under scenes/; the cache is one file
## under user:// keyed by the clips' names and modification times.
class_name ComboMine
extends RefCounted

const CACHE := "user://combo_cache.json"
const MIN_N := 2
const MAX_N := 4
const MIN_COUNT := 2
const MAX_SKIP := 2
const WORD := {"windup": "wind-up", "guard": "guard", "recover": "recover", "step": "step", "block": "block"}


static func _side(limb: String) -> String:
	return limb.substr(limb.length() - 1)


## the classified cards of S: [{"i", "kind", "word", "strike", "limb": hand/foot, "side": l/r}]
static func classify(S: Scene, B: Body) -> Array:
	var out := []
	var sc := FightRhythm.strike_cards(S)
	for i in range(1, S.cards.size()):
		var nm := String(S.cards[i]["name"]).to_lower()
		if FightRhythm._is_feint(nm):
			continue
		var kw := FightRhythm._word(nm, FightRhythm.KIND_WORDS)
		var bw := FightRhythm._word(nm, FightRhythm.BLOCK_WORDS)
		var k := StylePrint.kind_of(S, i)
		var strike := (sc.has(i) or k == "strike") and not (bw != "" and kw == "")
		var e := {"i": i, "kind": "", "word": "", "strike": strike, "limb": "", "side": ""}
		if strike:
			var lm := FightRhythm._limb(S, B, i)
			var foot := String(lm[0]).begins_with("foot")
			e["kind"] = "strike"
			e["limb"] = "foot" if foot else "hand"
			e["side"] = _side(String(lm[0]))
			e["word"] = kw if kw != "" else ("kick" if foot else "strike")
		elif bw != "":
			e["kind"] = "block"
			e["word"] = "block"
		elif k != "":
			e["kind"] = k
			e["word"] = String(WORD.get(k, k))
		else:
			continue
		out.append(e)
	return out


## the side (l / r) of the limb that travels furthest in card i's move; "" for the first card
static func side_of(S: Scene, B: Body, i: int) -> String:
	if i < 1 or i >= S.cards.size():
		return ""
	return _side(String(FightRhythm._limb(S, B, i)[0]))


static func _key(win: Array) -> String:
	var lead := ""
	var parts := []
	for e in win:
		if bool(e["strike"]):
			if lead == "":
				lead = String(e["side"])
			parts.append("%s.%s.%s" % [e["word"], e["limb"], "same" if e["side"] == lead else "opp"])
		else:
			parts.append(String(e["word"]))
	return ">".join(parts)


static func clip_stamp(paths: Array) -> String:
	var parts := []
	for p in paths:
		parts.append("%s:%d" % [String(p).get_file(), FileAccess.get_modified_time(String(p))])
	return String("|".join(parts)).md5_text()


## the combos of the clips at `paths`, best first. B is posed on (the caller puts it back)
static func mine(paths: Array, B: Body) -> Array:
	var groups := {}
	for p in paths:
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(p)))
		if not (d is Dictionary) or (d.get("cards", []) as Array).size() < 2:
			continue
		var S := Scene.new()
		S.from_dict(d)
		var cl := classify(S, B)
		var seen := {}   # key -> last card index used in this clip
		for n in range(MIN_N, MAX_N + 1):
			for s in range(0, cl.size() - n + 1):
				var win := cl.slice(s, s + n)
				var ok := false
				for k in n:
					ok = ok or bool(win[k]["strike"])
					if k > 0 and int(win[k]["i"]) - int(win[k - 1]["i"]) > MAX_SKIP + 1:
						ok = false
						break
				if not ok:
					continue
				var key := _key(win)
				if int(win[0]["i"]) <= int(seen.get(key, 0)):
					continue   # overlaps an occurrence of this combo already counted in this clip
				seen[key] = int(win[n - 1]["i"])
				var lead := ""
				for e in win:
					if bool(e["strike"]):
						lead = String(e["side"])
						break
				var mv := []
				var hd := []
				var cs := []
				var words := []
				var sk := []
				for e in win:
					var i := int(e["i"])
					cs.append(i)
					mv.append(S.move_time(i))
					hd.append(float(S.cards[i]["hold"]))
					words.append(String(e["word"]))
					if bool(e["strike"]):
						sk.append(cs.size() - 1)
				if not groups.has(key):
					groups[key] = {"key": key, "n": n, "words": words, "occ": []}
				groups[key]["occ"].append({"file": String(p), "cards": cs, "lead": lead, "mv": mv, "hd": hd, "sk": sk})
	# keep count >= 2, then drop a gram whose every occurrence lies inside a longer combo
	var kept := []
	for key in groups:
		if (groups[key]["occ"] as Array).size() >= MIN_COUNT:
			kept.append(groups[key])
	var cover := {}
	for g in kept:
		var n := int(g["n"])
		for o in g["occ"]:
			var cs: Array = o["cards"]
			for m in range(MIN_N, n):
				for s in range(0, n - m + 1):
					cover[String(o["file"]) + ":" + ",".join(cs.slice(s, s + m).map(func(x): return str(int(x))))] = true
	var out := []
	for g in kept:
		var all := true
		for o in g["occ"]:
			all = all and cover.has(String(o["file"]) + ":" + ",".join((o["cards"] as Array).map(func(x): return str(int(x)))))
		if all:
			continue
		var n := int(g["n"])
		var occ: Array = g["occ"]
		var mv := []
		var hd := []
		for k in n:
			var sm := 0.0
			var sh := 0.0
			for o in occ:
				sm += float(o["mv"][k])
				sh += float(o["hd"][k])
			mv.append(sm / occ.size())
			hd.append(sh / occ.size())
		var files := {}
		for o in occ:
			files[String(o["file"]).get_file().get_basename()] = true
		var c := {"key": g["key"], "n": n, "words": g["words"], "count": occ.size(), "clips": files.size(), "files": files.keys(),
			"moves": mv, "holds": hd, "lead": String((occ[0] as Dictionary)["lead"]), "strikes": (occ[0] as Dictionary)["sk"], "src": {"file": occ[0]["file"], "cards": occ[0]["cards"]}}
		c["name"] = "-".join(g["words"])
		c["rhythm"] = "/".join(mv.map(func(x): return "%.2f" % float(x)))
		c["text"] = "%s, your %s rhythm, used %d time%s in %d clip%s" % [c["name"], c["rhythm"], occ.size(), "" if occ.size() == 1 else "s", files.size(), "" if files.size() == 1 else "s"]
		out.append(c)
	out.sort_custom(func(a, b):
		if int(a["n"]) * int(a["count"]) != int(b["n"]) * int(b["count"]):
			return int(a["n"]) * int(a["count"]) > int(b["n"]) * int(b["count"])
		return String(a["key"]) < String(b["key"]))
	return out


## the mined result for the clips in `dirs`, from the cache when no clip changed: {"combos", "clips", "cached", "ms"}
static func mined(dirs: Array, B: Body, cache := CACHE) -> Dictionary:
	var paths := []
	for d in dirs:
		paths.append_array(StylePrint.clip_paths(String(d)))
	var stamp := clip_stamp(paths)
	var t0 := Time.get_ticks_usec()
	if FileAccess.file_exists(cache):
		var c: Variant = JSON.parse_string(FileAccess.get_file_as_string(cache))
		if c is Dictionary and String(c.get("stamp", "")) == stamp:
			return {"combos": c["combos"], "clips": paths.size(), "cached": true, "ms": float(Time.get_ticks_usec() - t0) / 1000.0}
	var combos := mine(paths, B)
	var f := FileAccess.open(cache, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"stamp": stamp, "combos": combos}))
		f.close()
	return {"combos": combos, "clips": paths.size(), "cached": false, "ms": float(Time.get_ticks_usec() - t0) / 1000.0}


## his own cards for combo c, read from the clip they came from, timed with the mined means; mirrored when `side` (l / r) is not the combo's lead
static func cards_for(c: Dictionary, side := "") -> Array:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(c["src"]["file"])))
	if not (d is Dictionary):
		return []
	var S := Scene.new()
	S.from_dict(d)
	var M := DistanceKeeper.new_body()
	var flip := side != "" and String(c["lead"]) != "" and side != String(c["lead"])
	var out := []
	for k in (c["src"]["cards"] as Array).size():
		var i := int(c["src"]["cards"][k])
		if i >= S.cards.size():
			return []
		var card: Dictionary = (S.cards[i] as Dictionary).duplicate(true)
		if flip:
			card = Scene.mirror_card(card, M)
		card["move"] = float(c["moves"][k])
		card["hold"] = float(c["holds"][k])
		card.erase("usual")
		out.append(card)
	return out


## S with the combo's cards inserted after card `after` (a clone; S is not changed)
static func with_inserted(S: Scene, after: int, cards: Array) -> Scene:
	var c := S.clone()
	insert(c, after, cards)
	return c


static func insert(S: Scene, after: int, cards: Array) -> void:
	for k in cards.size():
		S.cards.insert(after + 1 + k, (cards[k] as Dictionary).duplicate(true))
