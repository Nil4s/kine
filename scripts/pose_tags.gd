## POSE TAGS (round 2, R21): the pose library searched by words. A pose's tags are COMPUTED from the pose itself (the
## joint positions in its file, read only; nothing under poses/ is ever written), and the search matches a typed word
## against the pose's name AND its tags, forgiving a one-letter typo the way the command search does (CommandSearch.typo1).
##
## The rules (metres, the standing figure of poses/stand.json: hips 0.9167, head top 1.74, knee 0.53, shoulders 0.38 apart):
##   crouch   hips below 80 % of the standing hip height (0.733), not seated, not lying
##   guard    BOTH hands within 0.45 m of the face/chest point and at least 0.12 m in front of the chest
##   high     the weapon's tip, or a hand, more than 0.10 m / 0 m above the top of the head
##   low      the weapon's tip more than 0.10 m below the hips, or a hand below knee height (0.55)
##   kick     a foot (ankle) above the other leg's knee height, and at least 0.35 m off the floor
##   lunge    feet apart (on the floor plane) by more than 1.2 shoulder widths and the front knee bent past 30 degrees
##   one-leg  one ankle at least 0.12 m above the other
##   arms-up  both hands above the top of the head
##   seated   hips 0.38..0.58 m up (a chair seat is ~0.45 m, ISO 7250 / ANSI chair heights), thighs within 20 degrees of
##            horizontal, shins within 30 degrees of vertical. (A deep squat with hips that high is the same shape: it is
##            tagged seated; a squat lower than 0.38 m is a crouch.)
##   lying    hips below 0.45 m and the spine (hips to head) within 30 degrees of horizontal
## plus "bat" / "weapon" when the pose holds one. Positions are the world ones in the file; the figure faces the way
## (left shoulder - right shoulder) x up points.
class_name PoseTags
extends RefCounted

const VERSION := 1   # bump when a rule changes: every cached tag list is recomputed
const STAND_HIP := 0.9167
const ALL := ["crouch", "guard", "high", "low", "kick", "lunge", "one-leg", "arms-up", "seated", "lying"]
## words people type for a tag; the typed word is read as the tag (like CommandSearch.SYNONYMS)
const SYN := {"squat": "crouch", "duck": "crouch", "crouching": "crouch", "block": "guard", "defend": "guard", "defence": "guard",
	"defense": "guard", "overhead": "high", "sit": "seated", "sitting": "seated", "lie": "lying", "prone": "lying",
	"supine": "lying", "stance": "lunge", "single-leg": "one-leg", "onelegged": "one-leg", "hands-up": "arms-up", "kicking": "kick",
	"balance": "one-leg"}
const OPTIONAL := ["up", "the", "a", "with", "in", "and", "pose", "of"]   # a word that only helps when it matches


static func _p(j: Dictionary, n: String) -> Vector3:
	var a = j.get(n, {}).get("pos", null)
	return Vector3(a[0], a[1], a[2]) if a is Array and a.size() >= 3 else Vector3.ZERO


static func _e(j: Dictionary, n: String) -> Vector3:
	var a = j.get(n, {}).get("end", null)
	return Vector3(a[0], a[1], a[2]) if a is Array and a.size() >= 3 else _p(j, n)


## the tags of one pose (a parsed pose file), in the order of ALL, then "bat" / "weapon"
static func tags_of(d: Dictionary) -> Array:
	var j: Dictionary = d.get("joints", {})
	if j.is_empty():
		return []
	var pel := _p(j, "pelvis")
	var head := _p(j, "head")
	var top := _e(j, "head").y
	var hr := _p(j, "hand_r")
	var hl := _p(j, "hand_l")
	var ar := _p(j, "foot_r")
	var al := _p(j, "foot_l")
	var kr := _p(j, "calf_r")
	var kl := _p(j, "calf_l")
	var sr := _p(j, "upperarm_r")
	var sl := _p(j, "upperarm_l")
	var s3 := _p(j, "spine_03")
	var wep: Dictionary = d.get("weapon", {})
	var tip = wep.get("tip", null)
	var has_tip: bool = tip is Array and tip.size() >= 3
	var tipv := Vector3(tip[0], tip[1], tip[2]) if has_tip else Vector3.ZERO
	var sh_w := maxf(0.1, Vector2(sr.x - sl.x, sr.z - sl.z).length())
	var fwd := (sl - sr).cross(Vector3.UP)
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3.BACK
	var out := []
	# seated / lying first: crouch yields to them
	var thigh_flat := true
	var shin_up := true
	for side in [["thigh_r", "calf_r", "foot_r"], ["thigh_l", "calf_l", "foot_l"]]:
		var th := _p(j, side[1]) - _p(j, side[0])
		var sn := _p(j, side[2]) - _p(j, side[1])
		if th.length() < 0.01 or sn.length() < 0.01:
			thigh_flat = false
			continue
		thigh_flat = thigh_flat and rad_to_deg(asin(clampf(absf(th.y) / th.length(), 0.0, 1.0))) < 20.0
		shin_up = shin_up and rad_to_deg(acos(clampf(absf(sn.y) / sn.length(), 0.0, 1.0))) < 30.0
	var seated: bool = pel.y >= 0.38 and pel.y <= 0.58 and thigh_flat and shin_up
	var spine := head - pel
	var lying: bool = pel.y < 0.45 and spine.length() > 0.1 and rad_to_deg(asin(clampf(absf(spine.y) / spine.length(), 0.0, 1.0))) < 30.0
	if seated and lying:
		seated = false
	if pel.y < 0.8 * STAND_HIP and not seated and not lying:
		out.append("crouch")
	# guard: both fists at the face / chest, in front of it
	var face := (head + s3) * 0.5
	if hr.distance_to(face) < 0.45 and hl.distance_to(face) < 0.45 and (hr - s3).dot(fwd) > 0.12 and (hl - s3).dot(fwd) > 0.12:
		out.append("guard")
	if (has_tip and tipv.y > top + 0.10) or hr.y > top or hl.y > top:
		out.append("high")
	if (has_tip and tipv.y < pel.y - 0.10) or hr.y < 0.55 or hl.y < 0.55:
		out.append("low")
	var kick := false
	if ar.y > 0.35 and ar.y > kl.y:
		kick = true
	if al.y > 0.35 and al.y > kr.y:
		kick = true
	if kick:
		out.append("kick")
	var sep := Vector2(ar.x - al.x, ar.z - al.z)
	if sep.length() > 1.2 * sh_w:
		var front_r := (ar - al).dot(fwd) > 0.0
		var th2 := _p(j, "thigh_r" if front_r else "thigh_l")
		var kn := kr if front_r else kl
		var an := ar if front_r else al
		var a1 := th2 - kn
		var a2 := an - kn
		if a1.length() > 0.01 and a2.length() > 0.01 and rad_to_deg(a1.angle_to(a2)) < 150.0:
			out.append("lunge")
	if absf(ar.y - al.y) >= 0.12:
		out.append("one-leg")
	if hr.y > top and hl.y > top:
		out.append("arms-up")
	if seated:
		out.append("seated")
	if lying:
		out.append("lying")
	if not wep.is_empty():
		if String(wep.get("kind", "")).contains("bat"):
			out.append("bat")
		out.append("weapon")
	return out


## A LIBRARY INDEX: the name, path and tags of each pose, tags cached in a file (the cache is user:// in the app, a temp
## file in tests; a pose file is read again only when its modified time or the rules' VERSION changed)
class Index extends RefCounted:
	var cache_path := "user://pose_tags.json"
	var entries := []   # {"name", "path", "tags", "_nw" (words of the name), "_tags"}
	var read_files := 0   # how many pose files were parsed by the last build (0 = all from the cache)

	func build(items: Array) -> void:   # items: [{"name": String, "path": String}]
		var cache := {}
		if FileAccess.file_exists(cache_path):
			var c = JSON.parse_string(FileAccess.get_file_as_string(cache_path))
			if c is Dictionary and int(c.get("version", 0)) == PoseTags.VERSION:
				cache = c.get("poses", {})
		entries = []
		read_files = 0
		var fresh := {}
		for it in items:
			var path: String = it["path"]
			var mt := FileAccess.get_modified_time(path)
			var hit = cache.get(path)
			var tags: Array
			if hit is Dictionary and int(hit.get("mt", -1)) == mt:
				tags = hit["tags"]
			else:
				var d = JSON.parse_string(FileAccess.get_file_as_string(path))
				tags = PoseTags.tags_of(d) if d is Dictionary else []
				read_files += 1
			fresh[path] = {"mt": mt, "tags": tags}
			var nm: String = it["name"]
			entries.append({"name": nm, "path": path, "tags": tags, "_nw": PoseTags._words(nm.to_lower())})
		if read_files > 0 or fresh.size() != cache.size():   # write the cache only when it changed (never under poses/)
			var f := FileAccess.open(cache_path, FileAccess.WRITE)
			if f != null:
				f.store_string(JSON.stringify({"version": PoseTags.VERSION, "poses": fresh}))

	## the entries matching q, best first: [{"i": the index in `entries`, "score": int, "chips": matching tags}]. Every
	## typed word (but the OPTIONAL ones) must match the name or a tag. In the name: whole word 12 > word start 8 >
	## typo 7 > inside 4; a tag: its word 10 > a synonym 9 > start 8 > typo 6. An OPTIONAL word adds when it matches.
	func search(q: String) -> Array:
		var qw := q.to_lower().split(" ", false)
		var res := []
		for i in entries.size():
			var e: Dictionary = entries[i]
			var s := 0
			var chips := []
			var ok := true
			for w in qw:
				var best := PoseTags._word_in_name(e["_nw"], e["name"].to_lower(), w)
				var tg := ""
				for t in e["tags"]:
					var ts := PoseTags._word_in_tag(t, w)
					if ts > 0:
						if not chips.has(t):
							chips.append(t)
						if ts > best:
							best = ts
							tg = t
				if best <= 0:
					if w in PoseTags.OPTIONAL:
						continue
					ok = false
					break
				s += best
			if ok and (s > 0 or qw.is_empty()):
				res.append({"i": i, "score": s, "chips": chips})
		res.sort_custom(func(a, b): return a["score"] > b["score"] or (a["score"] == b["score"] and a["i"] < b["i"]))
		return res


static func _words(t: String) -> PackedStringArray:
	return t.replace("(", " ").replace(")", " ").replace("/", " ").replace("-", " ").replace(":", " ").split(" ", false)


## a typo on a word of 3+ letters (the command search wants 4: pose names are short words, "kik" must find "kick")
static func _typo(w: String, word: String) -> bool:
	return w.length() >= 3 and (CommandSearch.typo1(w, word) or (word.length() > w.length() and CommandSearch.typo1(w, word, w.length())))


static func _word_in_name(words: PackedStringArray, text: String, w: String) -> int:
	if w in words:
		return 12
	for x in words:
		if x.begins_with(w):
			return 8
	for x in words:
		if _typo(w, x):
			return 7
	return 4 if w.length() >= 3 and text.contains(w) else 0


static func _word_in_tag(tag: String, w: String) -> int:
	var t := tag.replace("-", " ")
	var tw := w.replace("-", " ")
	if tw == t or w == tag:
		return 10
	if SYN.get(w, "x") == tag:
		return 9
	if w.length() >= 3 and tag.begins_with(w):
		return 8
	if _typo(w, tag):
		return 6
	return 0
