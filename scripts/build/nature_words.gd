class_name NatureWords
extends RefCounted
## nature_words.gd - FRIDAY 225: NATURE from WORDS. "2 golden ginkgo trees 6 m tall left and right", "a box hedge 0.8 m high along the path", "round shrubs by the stair",
## "grass", "scatter 12 rocks over 20 x 20 m". A sentence -> items for the building record's "nature" list (scripts/build/nature.gd), placed from the house that stands
## (its rooms, its door side, its stairs, a path) and said back in one line. The words that are not understood are LISTED, never guessed.
## parse(text, building) -> {"ok", "items": [...], "say", "ignored": [], "error"}; apply(building, text) does it to the record.

const NUMBERS := {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "twelve": 12, "twenty": 20, "a": 1, "an": 1}
const UNITS := {"m": 1.0, "metre": 1.0, "metres": 1.0, "meter": 1.0, "meters": 1.0, "cm": 0.01, "ft": 0.3048, "feet": 0.3048, "foot": 0.3048}
const TREEW := ["tree", "trees"]
const SPECIES := {"ginkgo": "ginkgo", "gingko": "ginkgo", "oak": "oak", "pine": "pine", "conifer": "pine", "fir": "pine", "spruce": "pine", "palm": "palm",
	"birch": "birch", "bare": "bare", "dead": "bare"}
const SEASONW := {"spring": "spring", "summer": "summer", "green": "summer", "autumn": "autumn", "fall": "autumn", "golden": "autumn", "gold": "autumn", "yellow": "autumn",
	"red": "red", "crimson": "red", "winter": "winter", "leafless": "winter"}
const NOUNS := ["tree", "trees", "hedge", "hedges", "shrub", "shrubs", "bush", "bushes", "grass", "lawn", "meadow", "flower", "flowers", "path", "paths", "rock", "rocks",
	"stone", "stones", "scatter"]
const KNOWN := ["a", "an", "the", "of", "and", "with", "some", "make", "add", "put", "plant", "build", "create", "me", "please", "in", "on", "at", "by", "to", "around", "near", "along",
	"over", "across", "beside", "next", "tall", "high", "long", "wide", "left", "right", "front", "back", "behind", "both", "sides", "side", "each", "either", "house", "building",
	"stair", "stairs", "staircase", "door", "round", "box", "boxy", "square", "cone", "conical", "dense", "thick", "sparse", "thin", "x", "by", "m", "all", "it", "its", "lining",
	"leaves", "leaf", "coloured", "colored", "seed", "yard", "garden", "courtyard", "ground", "full", "bed", "patch", "wild", "dry", "short", "low", "big", "small", "large", "tiny",
	"rows", "row", "edge", "edges", "along", "path", "up"]
const COLORW := ["white", "yellow", "pink", "blue", "purple", "orange", "red"]


static func looks_natural(text: String) -> bool:
	for w in _tokens(text):
		if NOUNS.has(String(w)):
			return true
	return false


static func _tokens(text: String) -> Array:
	var s := text.to_lower().replace("×", " x ").replace("*", " x ").replace("-", " ")
	for ch in [";", "!", "?", "\"", "(", ")", "/", "+"]:
		s = s.replace(ch, " ")
	s = s.replace(",", " , ")
	var re := RegEx.new()
	re.compile("(?<!\\d)\\.|\\.(?!\\d)")
	s = re.sub(s, " ", true)
	re.compile("(\\d)\\s*x\\s*(\\d)")
	s = re.sub(s, "$1 x $2", true)
	re.compile("(\\d)([a-z])")
	s = re.sub(s, "$1 $2", true)
	var out := []
	for w in s.split(" ", false):
		out.append(String(w))
	return out


static func _is_num(w: String) -> bool:
	return w.is_valid_float()


## the house's footprint [lo, hi] as Vector2 corners; a default yard when there is none
static func bounds(bd: Dictionary) -> Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for r in bd.get("rooms", []):
		var yaw := deg_to_rad(float(r.get("yaw", 0.0)))
		for c in [Vector3(0, 0, 0), Vector3(float(r["w"]), 0, 0), Vector3(0, 0, float(r["d"])), Vector3(float(r["w"]), 0, float(r["d"]))]:
			var q: Vector3 = c.rotated(Vector3.UP, yaw)
			lo = Vector2(minf(lo.x, float(r["x"]) + q.x), minf(lo.y, float(r["z"]) + q.z))
			hi = Vector2(maxf(hi.x, float(r["x"]) + q.x), maxf(hi.y, float(r["z"]) + q.z))
	if lo.x == INF:
		return [Vector2(-3, -2), Vector2(3, 2), false]
	return [lo, hi, true]


static func offset_path(path: Array, off: float) -> Array:
	var st := Nature.stations(path, 1000.0)
	var out := []
	for s in st:
		var tn: Vector2 = s["tan"]
		var p: Vector2 = (s["pos"] as Vector2) + Vector2(-tn.y, tn.x) * off * float(s["miter"])
		out.append([p.x, p.y])
	return out


## split a sentence into clauses: at commas, "then", and at "and" when what follows starts a new thing
static func clauses(toks: Array) -> Array:
	var out: Array = []
	var cur: Array = []
	for i in toks.size():
		var w := String(toks[i])
		var split := false
		if w == "," or w == "then":
			split = true
		elif w == "and" and i + 1 < toks.size():
			var nx := String(toks[i + 1])
			if NUMBERS.has(nx) or _is_num(nx) or ["some", "the", "round", "box", "cone"].has(nx):
				split = cur.any(func(t): return NOUNS.has(String(t)))
		if split:
			if not cur.is_empty():
				out.append(cur)
			cur = []
		elif w != "," and not (w == "and" and cur.is_empty()):
			cur.append(w)
	if not cur.is_empty():
		out.append(cur)
	return out


static func parse(text: String, bd: Dictionary) -> Dictionary:
	var work := bd.duplicate(true) if not bd.is_empty() else Building.make("Untitled")
	var before: int = (work.get("nature", []) as Array).size()
	var ignored: Array = []
	var says: Array = []
	var seed_base := before * 13
	for cl in clauses(_tokens(text)):
		var r := _clause(cl, work, seed_base)
		seed_base += 100
		for w in r["ignored"]:
			if not ignored.has(w):
				ignored.append(w)
		for it in r["items"]:
			Nature.add(work, it)
		if r["say"] != "":
			says.append(r["say"])
	var items: Array = (work.get("nature", []) as Array).slice(before)
	if items.is_empty():
		var why := "Kine did not find a tree, hedge, shrub, grass, flowers, path or rocks in that sentence."
		if not ignored.is_empty():
			why += " It did not understand: %s." % ", ".join(ignored)
		return {"ok": false, "items": [], "say": "", "ignored": ignored, "error": why}
	return {"ok": true, "items": items, "say": ", ".join(says), "ignored": ignored, "error": "", "work": work}


## do the sentence to the record: the new items go in; returns the parse (with "ok" false and nothing changed when it did not understand)
static func apply(bd: Dictionary, text: String) -> Dictionary:
	var r := parse(text, bd)
	if bool(r["ok"]):
		bd["nature"] = (r["work"]["nature"] as Array).duplicate(true)
	return r


static func _clause(cl: Array, bd: Dictionary, seed_base: int) -> Dictionary:
	var noun := ""
	var ni := -1
	for i in cl.size():
		if NOUNS.has(String(cl[i])):
			noun = String(cl[i])
			ni = i
			break
	var ign: Array = []
	for w in cl:
		var ws := String(w)
		if not (NOUNS.has(ws) or KNOWN.has(ws) or NUMBERS.has(ws) or _is_num(ws) or SPECIES.has(ws) or SEASONW.has(ws) or UNITS.has(ws) or COLORW.has(ws) or ws == "scatter"):
			ign.append(ws)
	if noun == "":
		return {"items": [], "say": "", "ignored": ign}
	var bb := bounds(bd)
	var lo: Vector2 = bb[0]
	var hi: Vector2 = bb[1]
	# numbers: a count (before the noun, no unit after), measures (number + unit [+ tall / high / long / wide]), "N x M" sizes
	var count := -1
	var height := -1.0
	var length := -1.0
	var wide := -1.0
	var area := Vector2.ZERO
	var i := 0
	while i < cl.size():
		var w := String(cl[i])
		if (_is_num(w) or (NUMBERS.has(w) and w != "a" and w != "an")) and i != cl.size():
			var v: float = w.to_float() if _is_num(w) else float(NUMBERS[w])
			var nx := String(cl[i + 1]) if i + 1 < cl.size() else ""
			if nx == "x" and i + 2 < cl.size() and _is_num(String(cl[i + 2])):
				area = Vector2(v, String(cl[i + 2]).to_float())
				i += 3
				if i < cl.size() and UNITS.has(String(cl[i])):
					i += 1
				continue
			if UNITS.has(nx):
				var mv: float = v * float(UNITS[nx])
				var after := String(cl[i + 2]) if i + 2 < cl.size() else ""
				if after == "long":
					length = mv
				elif after == "wide":
					wide = mv
				else:
					height = mv
				i += 2
				continue
			if count < 0 and (i < ni or noun == "scatter"):
				count = int(v)
		i += 1
	if count < 0 and cl.size() > 0 and (String(cl[0]) == "a" or String(cl[0]) == "an"):
		count = 1
	var species := ""
	var season := ""
	var color := ""
	var shape := ""
	var dens := -1
	for w in cl:
		var ws := String(w)
		if SPECIES.has(ws):
			species = String(SPECIES[ws])
		if SEASONW.has(ws) and not (ws == "red" and noun in ["flower", "flowers"]):
			season = String(SEASONW[ws])
		if COLORW.has(ws) and noun in ["flower", "flowers"]:
			color = ws
		if ws in ["round"]:
			shape = "round"
		if ws in ["box", "boxy", "square"]:
			shape = "box"
		if ws in ["cone", "conical"]:
			shape = "cone"
		if ws in ["dense", "thick", "full"]:
			dens = 9
		if ws in ["sparse", "thin"]:
			dens = 2
	var sides: Array = []
	for w in cl:
		if ["left", "right", "front", "back", "behind"].has(String(w)):
			sides.append("back" if String(w) == "behind" else String(w))
	var along_path := cl.has("path") and noun != "path"
	var plural: bool = noun.ends_with("s") or noun == "bushes" or noun == "grass" and false
	var items: Array = []
	var say := ""
	var sd := 1 + seed_base
	match noun:
		"tree", "trees":
			var n: int = count if count > 0 else (2 if plural else 1)
			n = clampi(n, 1, 60)
			var pos := _spread(n, sides, lo, hi, 3.0, 4.0)
			for k in n:
				var it := {"kind": "tree", "species": species if species != "" else "oak", "x": pos[k].x, "z": pos[k].y, "height": height if height > 0 else 6.0,
					"season": season if season != "" else "summer", "density": dens if dens > 0 else 5, "seed": sd + k * 3}
				if it["species"] == "bare":
					it["season"] = "winter"
				items.append(it)
			say = "%d %s tree%s%s" % [n, (species if species != "" else "oak"), "" if n == 1 else "s", " (%s)" % season if season != "" else ""]
		"hedge", "hedges":
			var shp: String = "round" if shape == "round" else "box"
			var hh: float = height if height > 0 else 0.9
			var paths: Array = []
			for it in bd.get("nature", []):
				if String(it["kind"]) == "path":
					paths.append(it)
			var lines: Array = []
			if along_path or (cl.has("path") and not paths.is_empty()):
				if paths.is_empty():
					var door := _door_path(lo, hi, 8.0)
					items.append({"kind": "path", "path": door, "width": 1.2})
					paths.append({"path": door, "width": 1.2})
				var pth: Dictionary = paths[paths.size() - 1]
				var off := float(pth["width"]) * 0.5 + 0.3 + 0.3
				var both: bool = cl.has("both") or cl.has("each") or cl.has("either") or cl.has("lining") or cl.has("sides")
				lines.append(offset_path(pth["path"], off))
				if both:
					lines.append(offset_path(pth["path"], -off))
			else:
				var ln: float = length if length > 0 else (hi.x - lo.x if bb[2] else 6.0)
				var side := String(sides[0]) if not sides.is_empty() else "front"
				match side:
					"back":
						lines.append([[lo.x, hi.y + 1.5], [lo.x + ln, hi.y + 1.5]])
					"left":
						lines.append([[lo.x - 1.5, lo.y], [lo.x - 1.5, lo.y + ln]])
					"right":
						lines.append([[hi.x + 1.5, lo.y], [hi.x + 1.5, lo.y + ln]])
					_:
						lines.append([[lo.x, lo.y - 1.5], [lo.x + ln, lo.y - 1.5]])
			for k in lines.size():
				items.append({"kind": "hedge", "path": lines[k], "shape": shp, "height": hh, "width": wide if wide > 0 else 0.6, "seed": sd + k})
			say = "%d %s hedge%s %.1f m high" % [lines.size(), shp, "" if lines.size() == 1 else "s", hh]
		"shrub", "shrubs", "bush", "bushes":
			var n2: int = count if count > 0 else (2 if plural else 1)
			n2 = clampi(n2, 1, 60)
			var at: Array = []
			if cl.has("stair") or cl.has("stairs") or cl.has("staircase"):
				var st := Vector2(INF, INF)
				for pc in bd.get("pieces", []):
					if String(pc.get("kind", "")).begins_with("stairs"):
						st = Vector2(float(pc["x"]), float(pc["z"]))
						break
				if st.x == INF:
					st = Vector2((lo.x + hi.x) * 0.5, lo.y)
				for k in n2:
					var side_x := (-1.0 if k % 2 == 0 else 1.0) * (1.4 + 0.9 * float(k / 2))
					at.append(Vector2(st.x + side_x, st.y - 0.8))
			elif cl.has("door"):
				for k in n2:
					at.append(Vector2((lo.x + hi.x) * 0.5 + (-1.0 if k % 2 == 0 else 1.0) * (1.6 + 0.9 * float(k / 2)), lo.y - 0.8))
			else:
				at = _spread(n2, sides, lo, hi, 1.2, 1.2)
			for k in n2:
				items.append({"kind": "shrub", "shape": "cone" if shape == "cone" else "round", "x": at[k].x, "z": at[k].y, "size": height if height > 0 else (wide if wide > 0 else 1.2),
					"season": season if season != "" else "summer", "seed": sd + k})
			say = "%d %s shrub%s" % [n2, "cone" if shape == "cone" else "round", "" if n2 == 1 else "s"]
		"grass", "lawn", "meadow":
			var m := 8.0
			var x0 := lo.x - m
			var z0 := lo.y - m
			var w := (hi.x - lo.x) + 2.0 * m
			var d := (hi.y - lo.y) + 2.0 * m
			if area.x > 0.0:
				w = area.x
				d = area.y
				x0 = (lo.x + hi.x) * 0.5 - w * 0.5
				z0 = (lo.y + hi.y) * 0.5 - d * 0.5
			items.append({"kind": "grass", "x": x0, "z": z0, "w": w, "d": d, "tone": "meadow" if (noun == "meadow" or cl.has("wild")) else ("dry" if cl.has("dry") else "lawn"),
				"blade": 0.22, "density": 30.0 if dens < 0 else float(dens) * 8.0, "seed": sd})
			say = "grass %.0f x %.0f m, off the house and paths" % [w, d]
		"flower", "flowers":
			var n3: int = count if count > 0 else 40
			var cx := (lo.x + hi.x) * 0.5
			var cz := lo.y - 2.5
			if sides.has("left"):
				cx = lo.x - 2.5
				cz = (lo.y + hi.y) * 0.5
			elif sides.has("right"):
				cx = hi.x + 2.5
				cz = (lo.y + hi.y) * 0.5
			items.append({"kind": "flowers", "x": cx - 1.0, "z": cz - 0.6, "w": 2.0, "d": 1.2, "n": n3, "color": color if color != "" else "yellow", "seed": sd})
			say = "%d %s flowers" % [n3, color if color != "" else "yellow"]
		"path", "paths":
			var ln2: float = length if length > 0 else 8.0
			items.append({"kind": "path", "path": _door_path(lo, hi, ln2), "width": wide if wide > 0 else 1.2})
			say = "a path %.1f m long" % ln2
		"rock", "rocks", "stone", "stones", "scatter":
			var of := "rock"
			for w in cl:
				var ws := String(w)
				if ws in ["shrub", "shrubs", "bush", "bushes"]:
					of = "shrub"
				elif ws in ["flower", "flowers"]:
					of = "flowers"
				elif ws in ["tree", "trees"]:
					of = "tree:" + (species if species != "" else "oak")
			var n4: int = count if count > 0 else 10
			var ar := {"shape": "rect", "x": lo.x - 6.0, "z": lo.y - 6.0, "w": hi.x - lo.x + 12.0, "d": hi.y - lo.y + 12.0}
			if area.x > 0.0:
				ar = {"shape": "rect", "x": (lo.x + hi.x) * 0.5 - area.x * 0.5, "z": (lo.y + hi.y) * 0.5 - area.y * 0.5, "w": area.x, "d": area.y}
			if cl.has("path"):
				for it in bd.get("nature", []):
					if String(it["kind"]) == "path":
						ar = {"shape": "line", "path": it["path"], "width": float(it["width"]) + 4.0}
			items.append({"kind": "scatter", "of": of, "n": n4, "spacing": 1.0 if of != "rock" else 0.8, "size": height if height > 0 else (0.6 if of == "rock" else 1.0),
				"jitter": 0.7, "seed": sd, "area": ar})
			say = "%d %s scattered" % [n4, of.replace("tree:", "")]
	return {"items": items, "say": say, "ignored": ign}


## n positions: along the named sides of the house (left / right / front / back), or across the front
static func _spread(n: int, sides: Array, lo: Vector2, hi: Vector2, gap_side: float, gap_fb: float) -> Array:
	var out: Array = []
	var ss: Array = sides if not sides.is_empty() else ["front"]
	var per: Array = []
	for s in ss:
		per.append(0)
	for k in n:
		per[k % ss.size()] += 1
	var slot: Array = []
	for s in ss:
		slot.append(0)
	for k in n:
		var si := k % ss.size()
		var cnt: int = per[si]
		var j: int = slot[si]
		slot[si] += 1
		var f := (float(j) + 0.5) / float(cnt)
		match String(ss[si]):
			"left":
				out.append(Vector2(lo.x - gap_side, lo.y - gap_fb * 0.4 if cnt == 1 else lerpf(lo.y, hi.y, f)))
			"right":
				out.append(Vector2(hi.x + gap_side, lo.y - gap_fb * 0.4 if cnt == 1 else lerpf(lo.y, hi.y, f)))
			"back":
				out.append(Vector2(lerpf(lo.x, hi.x, f), hi.y + gap_fb))
			_:
				out.append(Vector2(lerpf(lo.x, hi.x, f), lo.y - gap_fb))
	return out


## a straight path from the front of the house outward
static func _door_path(lo: Vector2, hi: Vector2, ln: float) -> Array:
	var cx := (lo.x + hi.x) * 0.5
	return [[cx, lo.y - 0.2], [cx, lo.y - 0.2 - ln]]
