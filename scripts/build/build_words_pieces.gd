class_name BuildWordsPieces
extends RefCounted
## build_words_pieces.gd - WORDS learns PIECES: "stairs in the corner", "L stairs to the second floor", "a table and 2 benches in the middle",
## "a crate by the door", "4 pillars around the room", "a fence along the back wall", "a ramp to the platform" (docs/BUILD_PLAN.md 1e + 1f).
## A sentence gives SPECS (plain data, the chips of a plan card): {"kind", "n", "at", "walls": [], "wall", "to", "to_floor", "storey"}.
##   at: "" (the kind's own default, DEFAULT_AT) | "corner" | "middle" | "wall" (by it) | "along" (a fence's length = the free wall) | "door" | "around"
## place(b, specs) puts them on the building record, ONE piece at a time, DETERMINISTICALLY: the middle of a piece is on the 0.5 m grid, inside
## the interior of the room of its floor, clear of every door (the door's width + 0.1 m each side, 0.9 m deep inward = the swing), clear of every other
## piece (and of the stairs that arrive on this floor), and never half in: a piece that has no clear place is LEFT OUT and the reason is said plainly.
## Candidates are tried in a fixed order (corners: the one farthest from the doors first; walls: back, left, right, front; "middle": the nearest cell
## to the centre first), so the same words on the same house always give the same pieces. Nothing here touches the scene (the UI takes the undo step).

const G := 0.5
const KEEP := 0.9        # m: the clear space in front of a door
const SIDE := 0.1        # m: the clear space each side of a door
const EPS := 1e-4
const MAX_N := 12
const WORDS := {"stairs": "stairs", "stair": "stairs", "staircase": "stairs", "staircases": "stairs", "table": "table", "tables": "table",
	"bench": "bench", "benches": "bench", "crate": "crate", "crates": "crate", "box": "crate", "boxes": "crate", "pillar": "pillar",
	"pillars": "pillar", "column": "pillar", "columns": "pillar", "fence": "fence", "fences": "fence", "ramp": "ramp", "ramps": "ramp",
	"platform": "platform", "platforms": "platform", "stage": "platform"}
const PLURAL := ["tables", "benches", "crates", "boxes", "pillars", "columns", "fences", "ramps", "platforms", "staircases"]
const NAMES := {"stairs": ["stairs", "stairs"], "stairs_l": ["L stairs", "L stairs"], "table": ["table", "tables"], "bench": ["bench", "benches"],
	"crate": ["crate", "crates"], "pillar": ["pillar", "pillars"], "fence": ["fence", "fences"], "ramp": ["ramp", "ramps"], "platform": ["platform", "platforms"]}
const DEFAULT_AT := {"stairs": "corner", "stairs_l": "corner", "table": "middle", "bench": "wall", "crate": "corner", "pillar": "around",
	"fence": "along", "ramp": "wall", "platform": "middle"}
const WALL_ORDER := ["back", "left", "right", "front"]
const CORNERS := [["left", "back"], ["right", "back"], ["left", "front"], ["right", "front"]]
## the order the "where" chip cycles through: [at, wall]
const AREAS := [["corner", ""], ["middle", ""], ["wall", ""], ["around", ""], ["door", ""], ["along", "back"], ["wall", "left"], ["wall", "right"], ["wall", "front"]]
const WALLW := {"front": "front", "back": "back", "rear": "back", "left": "left", "right": "right"}
const ORDW := {"first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5}
const NEAR := ["by", "against", "near", "beside", "next", "at"]
## the words the edit sentences may use besides the nouns
const KNOWN := ["l", "shaped", "around", "corner", "corners", "wall", "walls", "against", "beside", "near", "next", "by", "room", "rooms", "it", "them",
	"rotate", "place", "turn", "second", "third", "fourth", "fifth", "first", "upstairs", "rear", "along", "up", "stage"]


# ---------------------------------------------------------------- the words -> specs

static func _at(t: Array, i: int) -> String:
	return String(t[i]) if i >= 0 and i < t.size() else ""


static func _is_num(w: String) -> bool:
	return w != "" and w.is_valid_float() and not w.begins_with("-")


static func new_spec(kind: String, n: int) -> Dictionary:
	return {"kind": kind, "n": n, "at": "", "walls": [], "wall": "", "to": "", "to_floor": 0, "storey": -1}


## the piece noun at t[j] ("stairs", "L stairs", "l shaped stairs", "benches"): [kind, tokens used] or []
static func noun_at(t: Array, j: int) -> Array:
	var w := _at(t, j)
	if w == "l":
		var k := j + 1
		if _at(t, k) == "shaped":
			k += 1
		if WORDS.get(_at(t, k), "") == "stairs":
			return ["stairs_l", k - j + 1]
		return []
	if WORDS.has(w):
		return [String(WORDS[w]), 1]
	return []


## the word before t[i], leaving out a / an / the
static func _prev(t: Array, i: int) -> String:
	var k := i - 1
	while k >= 0 and ["a", "an", "the"].has(String(t[k])):
		k -= 1
	return _at(t, k)


static func has_noun(t: Array) -> bool:
	for i in t.size():
		if not noun_at(t, i).is_empty():
			return true
	return false


## one piece word of a sentence at t[i]; returns the tokens it used (0 = not a piece word here). st = {"specs": [], "run": [], "pend": ""};
## `on` = the words before were about a piece (so "corner", "by the door", a wall word belong to it); st["error"] is set on a refusal
static func feed(t: Array, i: int, st: Dictionary, on: bool) -> int:
	var w := String(t[i])
	var specs: Array = st["specs"]
	if _is_num(w):
		var nn := noun_at(t, i + 1)
		if nn.is_empty():
			return 0
		var v := float(w)
		if absf(v - roundf(v)) > 0.001 or v < 1.0:
			st["error"] = "%s %s: a piece count is a whole number, 1 to %d." % [w, _at(t, i + 1), MAX_N]
			return 1 + int(nn[1])
		if int(v) > MAX_N:
			st["error"] = "%d %s is too many in one go (up to %d)." % [int(v), _at(t, i + 1), MAX_N]
			return 1 + int(nn[1])
		_add(st, String(nn[0]), int(v))
		return 1 + int(nn[1])
	var nn2 := noun_at(t, i)
	if not nn2.is_empty():
		if String(nn2[0]) == "platform" and not specs.is_empty() and String(specs[specs.size() - 1]["kind"]) == "ramp" and _prev(t, i) == "to":
			specs[specs.size() - 1]["to"] = "platform"
			return 1
		_add(st, String(nn2[0]), 2 if PLURAL.has(_at(t, i + int(nn2[1]) - 1)) else 1)
		return int(nn2[1])
	if not on or specs.is_empty():
		return 0
	var cur: Dictionary = specs[specs.size() - 1]
	match w:
		"corner", "corners":
			_area(st, "corner")
			return 1
		"middle", "centre", "center":
			if String(cur["at"]) == "" or String(cur["at"]) == "by":
				_area(st, "middle")
			return 1
		"around":
			_area(st, "around")
			return 1
		"along":
			st["pend"] = "along"
			return 1
		"by", "against", "near", "beside", "next":
			if st["pend"] == "":
				st["pend"] = "by"
			return 1
		"wall", "walls":
			var at := String(cur["at"])
			if at == "" or at == "wall":
				_area(st, "along" if st["pend"] == "along" else "wall")
			return 1
		"door", "doorway":
			if NEAR.has(_prev(t, i)) or _prev(t, i) == "to":
				_area(st, "door")
				return 1
			return 0
	if WALLW.has(w):
		var wl := String(WALLW[w])
		if not (cur["walls"] as Array).has(wl):
			(cur["walls"] as Array).append(wl)
		if String(cur["wall"]) == "":
			cur["wall"] = wl
		for idx in st["grp"]:
			var gs: Dictionary = specs[int(idx)]
			if not (gs["walls"] as Array).has(wl):
				(gs["walls"] as Array).append(wl)
			if String(gs["wall"]) == "":
				gs["wall"] = wl
		if not ["door", "doorway", "window", "windows"].has(_at(t, i + 1)) and (String(cur["at"]) == "" or String(cur["at"]) == "wall" or String(cur["at"]) == "along"):
			_area(st, "along" if st["pend"] == "along" else "wall")
		return 1
	if ORDW.has(w) and _prev(t, i) == "to" and ["floor", "storey", "level"].has(_at(t, i + 1)):
		cur["to_floor"] = int(ORDW[w])
		return 1
	if w.begins_with("ord") and w.substr(3).is_valid_int() and _prev(t, i) == "to":
		cur["to_floor"] = int(w.substr(3))
		return 1
	return 0


static func _add(st: Dictionary, kind: String, n: int) -> void:
	(st["specs"] as Array).append(new_spec(kind, n))
	st["grp"] = []
	(st["run"] as Array).append((st["specs"] as Array).size() - 1)
	st["pend"] = ""


## an area word after pieces: it names where the run of pieces just listed ("a table and 2 benches in the middle") stands
static func _area(st: Dictionary, at: String) -> void:
	var specs: Array = st["specs"]
	var cur: Dictionary = specs[specs.size() - 1]
	cur["at"] = at
	for idx in st["run"] + st["grp"]:   # the pieces listed together take the place; a later word of the same phrase ("back left corner") may refine it
		var s: Dictionary = specs[int(idx)]
		s["at"] = at
		s["wall"] = cur["wall"]
		s["walls"] = (cur["walls"] as Array).duplicate()
	st["grp"] = st["run"] + st["grp"]
	st["run"] = []
	st["pend"] = ""


static func new_state() -> Dictionary:
	return {"specs": [], "run": [], "grp": [], "pend": ""}


# ---------------------------------------------------------------- the words for a spec

static func label(kind: String, n: int) -> String:
	return String(NAMES[kind][0 if n == 1 else 1])


static func eff_at(s: Dictionary) -> String:
	if String(s.get("to", "")) != "":
		return "to"
	return String(s["at"]) if String(s["at"]) != "" else String(DEFAULT_AT[String(s["kind"])])


static func area_text(s: Dictionary) -> String:
	var at := eff_at(s)
	var wl := String(s.get("wall", ""))
	var ws: Array = s.get("walls", [])
	match at:
		"corner":
			if ws.size() >= 2:
				return "in the %s %s corner" % [ws[0] if WALL_ORDER.has(ws[0]) and (ws[0] == "back" or ws[0] == "front") else ws[1], ws[1] if (ws[0] == "back" or ws[0] == "front") else ws[0]]
			return "in the %s corner" % wl if wl != "" else "in the corner"
		"middle":
			return "in the middle"
		"wall":
			return "by the %s wall" % wl if wl != "" else "by the wall"
		"along":
			return "along the %s wall" % wl if wl != "" else "along the wall"
		"door":
			return "by the %s door" % wl if wl != "" else "by the door"
		"around":
			return "around the room"
		"to":
			return "to the %s" % s["to"]
	return ""


## "4 pillars around the room", "L stairs in the corner to floor 2"
static func spec_text(s: Dictionary) -> String:
	var n := int(s["n"])
	var out := "%s %s" % [str(n) if n != 1 else "a", label(String(s["kind"]), n)]
	if n == 1 and String(s["kind"]) in ["stairs", "stairs_l"]:
		out = label(String(s["kind"]), 1)
	out += " " + area_text(s)
	if int(s.get("to_floor", 0)) > 0:
		out += " to floor %d" % int(s["to_floor"])
	return out.strip_edges()


static func specs_text(specs: Array) -> String:
	return ", ".join(specs.map(func(s): return spec_text(s)))


## a short list for the summary line: "4 pillars, a platform, a bench"
static func summary(specs: Array) -> String:
	return ", ".join(specs.map(func(s): return ("%d %s" % [int(s["n"]), label(String(s["kind"]), int(s["n"]))]) if int(s["n"]) != 1 else "a " + label(String(s["kind"]), 1)))


# ---------------------------------------------------------------- the cards

## a card for each spec: chips = [count, name, where]; tail = what the placement said ("" = it fits, else why not)
static func cards(specs: Array, res: Array) -> Array:
	var out := []
	for i in specs.size():
		var s: Dictionary = specs[i]
		var n := int(s["n"])
		var r: Dictionary = res[i] if i < res.size() and res[i] is Dictionary else {}
		var tail := ""
		if not r.is_empty() and int(r.get("placed", 0)) < n:
			tail = String(r.get("why", ""))
			if int(r.get("placed", 0)) > 0:
				tail = "%d of %d fit. %s" % [int(r["placed"]), n, tail]
			tail += " Left out."
		var chips := [{"key": "pc%d_n" % i, "text": str(n), "kind": "num", "value": float(n)}, {"text": label(String(s["kind"]), n), "kind": "text"},
			{"key": "pc%d_at" % i, "text": area_text(s), "kind": "cycle", "value": 0.0}]
		if int(s.get("to_floor", 0)) > 0:
			chips.append({"text": "to floor %d" % int(s["to_floor"]), "kind": "text"})
		var d: Dictionary = BuildPieces.DEFS[String(s["kind"])]
		out.append({"title": String(d["label"]), "tag": "default: " + area_text({"kind": s["kind"], "at": "", "wall": "", "walls": [], "to": ""}) if String(s["at"]) == "" and String(s.get("to", "")) == "" else "",
			"chips": chips, "tail": tail})
	return out


## a chip of a spec card: "pc2_n" (the count) typed in. "" = it took, else why not. A count of 0 takes the piece off the list
static func set_chip(specs: Array, key: String, v: float) -> String:
	var idx := _chip_index(key)
	if idx < 0 or idx >= specs.size() or not key.ends_with("_n"):
		return "no such number"
	if int(roundf(v)) < 0 or int(roundf(v)) > MAX_N:
		return "0 to %d of one piece." % MAX_N
	if int(roundf(v)) == 0:
		specs.remove_at(idx)
	else:
		specs[idx]["n"] = int(roundf(v))
	return ""


static func cycle(specs: Array, key: String) -> void:
	var idx := _chip_index(key)
	if idx < 0 or idx >= specs.size() or not key.ends_with("_at"):
		return
	var s: Dictionary = specs[idx]
	var cur := -1
	for k in AREAS.size():
		if String(AREAS[k][0]) == eff_at(s) and (String(AREAS[k][1]) == String(s.get("wall", "")) or (String(AREAS[k][1]) == "" and String(s.get("wall", "")) == "")):
			cur = k
			break
	var nx: Array = AREAS[(cur + 1) % AREAS.size()]
	s["at"] = String(nx[0])
	s["wall"] = String(nx[1])
	s["walls"] = [] if String(nx[1]) == "" else [String(nx[1])]
	s["to"] = ""


static func _chip_index(key: String) -> int:
	if not key.begins_with("pc"):
		return -1
	var body := key.substr(2)
	var us := body.find("_")
	if us < 1 or not body.substr(0, us).is_valid_int():
		return -1
	return int(body.substr(0, us))


static func value_of(specs: Array, key: String) -> float:
	var idx := _chip_index(key)
	return float(specs[idx]["n"]) if idx >= 0 and idx < specs.size() else 0.0


# ---------------------------------------------------------------- placing

static func _no(why: String) -> Dictionary:
	return {"ok": false, "why": why}


static func _room_on(b: Dictionary, storey: int) -> Dictionary:
	for r in b.get("rooms", []):
		if int(r.get("storey", 0)) == storey and String(r["id"]) != "garage":
			return r
	return {}


static func _overlap(a: Rect2, c: Rect2) -> bool:
	return a.position.x < c.end.x - EPS and a.end.x > c.position.x + EPS and a.position.y < c.end.y - EPS and a.end.y > c.position.y + EPS


## what a piece on this floor has to keep clear of: {"room", "inner": Rect2, "obs": [Rect2], "doors": [{"wall", "mid", "zone"}]}
static func context(b: Dictionary, room: Dictionary, storey: int, skip_id := "") -> Dictionary:
	var t := clampf(Building.num(b, room.get("thickness"), 0.2), 0.01, minf(float(room["w"]), float(room["d"])) * 0.5 - 0.01)
	var rx := float(room["x"])
	var rz := float(room["z"])
	var rw := float(room["w"])
	var rd := float(room["d"])
	var inner := Rect2(rx + t, rz + t, rw - 2.0 * t, rd - 2.0 * t)
	var obs := []
	for p in b.get("pieces", []):
		if String(p["id"]) == skip_id:
			continue
		var ps := int(p.get("storey", 0))
		if ps == storey or (ps == storey - 1 and BuildPieces.is_stairs(p)):
			obs.append(BuildPieces.footprint(b, p))
	var doors := []
	for o in b.get("openings", []):
		if String(o.get("room", "")) != String(room["id"]) or String(o.get("kind", "")) == "window" or not Building.WALLS.has(String(o.get("wall", ""))):
			continue
		var wall := String(o["wall"])
		var along_x := wall == "front" or wall == "back"
		var span := (rw if along_x else rd) - 2.0 * t
		var ow := clampf(Building.num(b, o.get("w"), 0.9), 0.05, maxf(span, 0.05))
		var mid := (rx + rw * 0.5 if along_x else rz + rd * 0.5) + clampf(Building.num(b, o.get("at"), 0.0), -(span - ow) * 0.5, (span - ow) * 0.5)
		var depth := maxf(KEEP, ow)
		var zone := Rect2()
		match wall:
			"front":
				zone = Rect2(mid - ow * 0.5 - SIDE, rz + t, ow + 2.0 * SIDE, depth)
			"back":
				zone = Rect2(mid - ow * 0.5 - SIDE, rz + rd - t - depth, ow + 2.0 * SIDE, depth)
			"left":
				zone = Rect2(rx + t, mid - ow * 0.5 - SIDE, depth, ow + 2.0 * SIDE)
			_:
				zone = Rect2(rx + rw - t - depth, mid - ow * 0.5 - SIDE, depth, ow + 2.0 * SIDE)
		obs.append(zone)
		doors.append({"wall": wall, "mid": mid, "zone": zone})
	return {"room": room, "inner": inner, "obs": obs, "doors": doors}


## the footprint of a piece record turned to yaw: {"yaw", "size": Vector2}
static func _info(b: Dictionary, p0: Dictionary, yaw: float) -> Dictionary:
	var q := p0.duplicate()
	q["yaw"] = yaw
	q["x"] = 0.0
	q["z"] = 0.0
	return {"yaw": yaw, "size": BuildPieces.footprint(b, q).size}


static func _infos(b: Dictionary, p0: Dictionary, first_yaw := 0.0) -> Array:
	var a := _info(b, p0, first_yaw)
	var c := _info(b, p0, fposmod(first_yaw + 90.0, 360.0))
	if (a["size"] as Vector2).is_equal_approx(c["size"]):
		return [a]
	return [a, c]


static func _lo(edge: float, half: float) -> float:
	return ceilf((edge + half - EPS) / G) * G


static func _hi(edge: float, half: float) -> float:
	return floorf((edge - half + EPS) / G) * G


static func _legal(cx: Dictionary, c: Vector2, size: Vector2) -> bool:
	var inner: Rect2 = cx["inner"]
	var r := Rect2(c - size * 0.5, size)
	if r.position.x < inner.position.x - EPS or r.position.y < inner.position.y - EPS or r.end.x > inner.end.x + EPS or r.end.y > inner.end.y + EPS:
		return false
	for o in cx["obs"]:
		if _overlap(r, o):
			return false
	return true


## the first legal candidate [Vector2 centre, info index] or null
static func _first(cx: Dictionary, infos: Array, cands: Array) -> Variant:
	for c in cands:
		if _legal(cx, c[0], infos[int(c[1])]["size"]):
			return c
	return null


## every grid cell where a piece of each yaw sits inside the room, nearest to the anchor first
static func _cells(cx: Dictionary, infos: Array, anchor: Vector2) -> Array:
	var inner: Rect2 = cx["inner"]
	var rows := []
	for yi in infos.size():
		var sz: Vector2 = infos[yi]["size"]
		var x := _lo(inner.position.x, sz.x * 0.5)
		var x1 := _hi(inner.end.x, sz.x * 0.5)
		var z0 := _lo(inner.position.y, sz.y * 0.5)
		var z1 := _hi(inner.end.y, sz.y * 0.5)
		while x <= x1 + EPS:
			var z := z0
			while z <= z1 + EPS:
				rows.append([Vector2(x, z).distance_squared_to(anchor), yi, x, z])
				z += G
			x += G
	rows.sort_custom(func(a, c):
		if absf(a[0] - c[0]) > 1e-6:
			return a[0] < c[0]
		if a[1] != c[1]:
			return a[1] < c[1]
		if a[2] != c[2]:
			return a[2] < c[2]
		return a[3] < c[3])
	return rows.map(func(r): return [Vector2(r[2], r[3]), r[1]])


## candidates flush against a wall, the ones nearest the target (m along the wall) first; the yaw that lays the long side along the wall first
static func _wall_cands(cx: Dictionary, infos: Array, wall: String, target: float) -> Array:
	var inner: Rect2 = cx["inner"]
	var along_x := wall == "front" or wall == "back"
	var order := range(infos.size())
	order.sort_custom(func(a, c):
		var sa: Vector2 = infos[a]["size"]
		var sc: Vector2 = infos[c]["size"]
		var la := (sa.x >= sa.y) if along_x else (sa.y >= sa.x)
		var lc := (sc.x >= sc.y) if along_x else (sc.y >= sc.x)
		if la != lc:
			return la
		return a < c)
	var out := []
	for yi in order:
		var sz: Vector2 = infos[yi]["size"]
		var rows := []
		if along_x:
			var zc := _lo(inner.position.y, sz.y * 0.5) if wall == "front" else _hi(inner.end.y, sz.y * 0.5)
			var x := _lo(inner.position.x, sz.x * 0.5)
			while x <= _hi(inner.end.x, sz.x * 0.5) + EPS:
				rows.append([absf(x - target), x, Vector2(x, zc)])
				x += G
		else:
			var xc := _lo(inner.position.x, sz.x * 0.5) if wall == "left" else _hi(inner.end.x, sz.x * 0.5)
			var z := _lo(inner.position.y, sz.y * 0.5)
			while z <= _hi(inner.end.y, sz.y * 0.5) + EPS:
				rows.append([absf(z - target), z, Vector2(xc, z)])
				z += G
		rows.sort_custom(func(a, c): return a[0] < c[0] - 1e-6 or (absf(a[0] - c[0]) <= 1e-6 and a[1] < c[1]))
		for r in rows:
			out.append([r[2], yi])
	return out


static func _wall_mid(cx: Dictionary, wall: String, slot: float) -> float:
	var inner: Rect2 = cx["inner"]
	if wall == "front" or wall == "back":
		return inner.position.x + slot * inner.size.x
	return inner.position.y + slot * inner.size.y


## the walls of an area word, in the order tried
static func _walls_for(s: Dictionary, k: int, stretch: bool) -> Array:
	var ws: Array = s.get("walls", [])
	if not ws.is_empty():
		return ws.duplicate()
	if String(s.get("wall", "")) != "":
		return [String(s["wall"])]
	if stretch:
		var o := WALL_ORDER.duplicate()
		var r := k % 4
		return o.slice(r) + o.slice(0, r)
	return WALL_ORDER.duplicate()


## the longest stretch of a wall that no door's space crosses: [start, end] along the wall (m, world)
static func _free_run(cx: Dictionary, wall: String) -> Array:
	var inner: Rect2 = cx["inner"]
	var along_x := wall == "front" or wall == "back"
	var lo := inner.position.x if along_x else inner.position.y
	var hi := inner.end.x if along_x else inner.end.y
	var cuts := []
	for d in cx["doors"]:
		if String(d["wall"]) == wall:
			var z: Rect2 = d["zone"]
			cuts.append([z.position.x if along_x else z.position.y, z.end.x if along_x else z.end.y])
	cuts.sort_custom(func(a, c): return a[0] < c[0])
	var best := [lo, lo]
	var at := lo
	for c in cuts:
		if float(c[0]) - at > best[1] - best[0]:
			best = [at, float(c[0])]
		at = maxf(at, float(c[1]))
	if hi - at > best[1] - best[0]:
		best = [at, hi]
	return best


## where one piece of the spec goes: {"ok": true, "x", "z", "yaw", "storey", "set": {numbers changed}} or {"ok": false, "why"}.
## k of n = which of the spec's pieces this is; tmpl = a piece being moved (its own numbers stay); skip_id = that piece (it is not in its own way)
static func find(b: Dictionary, s: Dictionary, k: int, n: int, skip_id := "", tmpl := {}) -> Dictionary:
	var kind := String(s["kind"])
	var is_st := kind == "stairs" or kind == "stairs_l"
	var storey := int(s.get("storey", -1))
	if storey < 0:
		storey = maxi(int(s.get("to_floor", 0)) - 2, 0) if is_st else 0
	var nf := Building.storey_count(b)
	var nm := label(kind, 1)
	if is_st and storey + 1 >= nf:
		return _no("The %s go up to a floor above: this house has %d floor%s. Say 'add a floor' first." % [nm, nf, "" if nf == 1 else "s"])
	var room := _room_on(b, storey)
	if room.is_empty():
		return _no("There is no floor %d to put the %s on." % [storey + 1, nm])
	if float(room.get("yaw", 0.0)) != 0.0:
		return _no("This room is turned: pieces go in straight rooms.")
	var cx := context(b, room, storey, skip_id)
	var inner: Rect2 = cx["inner"]
	var p0: Dictionary = tmpl.duplicate() if not tmpl.is_empty() else BuildPieces.make("p0", kind, 0.0, 0.0, 0.0, storey)
	p0["storey"] = storey
	var at := eff_at(s)
	var setd := {}
	var found: Variant = null
	var infos: Array = []
	var tried := false
	match at:
		"to":
			var plat := {}
			for p in b.get("pieces", []):
				if String(p["kind"]) == String(s["to"]) and int(p.get("storey", 0)) == storey and String(p["id"]) != skip_id:
					plat = p
					break
			if plat.is_empty():
				return _no("There is no %s to put the %s to: say 'a platform in the middle' too." % [s["to"], nm])
			p0["h"] = BuildPieces.value(plat, "h")
			setd["h"] = p0["h"]
			var pr := BuildPieces.footprint(b, plat)
			var yaws := [0.0, 90.0, 180.0, 270.0]
			var sides := []
			for yw in yaws:
				var info := _info(b, p0, yw)
				var sz: Vector2 = info["size"]
				var c := Vector2.ZERO
				match int(yw):
					0:
						c = Vector2(pr.get_center().x, pr.position.y - sz.y * 0.5)
					90:
						c = Vector2(pr.position.x - sz.x * 0.5, pr.get_center().y)
					180:
						c = Vector2(pr.get_center().x, pr.end.y + sz.y * 0.5)
					_:
						c = Vector2(pr.end.x + sz.x * 0.5, pr.get_center().y)
				sides.append([c.distance_squared_to(inner.get_center()), yw, c, sz])
			sides.sort_custom(func(a, c): return a[0] < c[0] - 1e-6 or (absf(a[0] - c[0]) <= 1e-6 and a[1] < c[1]))
			for sd in sides:
				var yw: float = sd[1]
				var along_x := int(yw) == 0 or int(yw) == 180
				var reach := (pr.size.x if along_x else pr.size.y) * 0.5
				var off := 0.0
				while off <= reach + EPS:
					for sg in ([1.0] if off == 0.0 else [1.0, -1.0]):
						var c: Vector2 = sd[2]
						c = Vector2(snappedf(c.x + (off * sg if along_x else 0.0), G), snappedf(c.y + (0.0 if along_x else off * sg), G))
						if _legal(cx, c, sd[3]):
							found = [c, yw]
							break
					if found != null:
						break
					off += G
				if found != null:
					break
			tried = true
			if found != null:
				return {"ok": true, "x": (found[0] as Vector2).x, "z": (found[0] as Vector2).y, "yaw": float(found[1]), "storey": storey, "set": setd}
			infos = [_info(b, p0, 0.0)]
		"corner":
			infos = _infos(b, p0)
			var order := range(4)
			var ws: Array = s.get("walls", [])
			var only := -1
			var zw := ""
			var xw := ""
			for w in ws:
				if w == "front" or w == "back":
					zw = String(w)
				else:
					xw = String(w)
			if zw != "" and xw != "":
				for ci in 4:
					if CORNERS[ci][0] == xw and CORNERS[ci][1] == zw:
						only = ci
			var far := func(ci: int) -> float:
				var cn := Vector2(inner.position.x if CORNERS[ci][0] == "left" else inner.end.x, inner.position.y if CORNERS[ci][1] == "front" else inner.end.y)
				var dmin := 1e9
				for d in cx["doors"]:
					dmin = minf(dmin, cn.distance_to((d["zone"] as Rect2).get_center()))
				return dmin
			order.sort_custom(func(a, c):
				var pa: bool = (zw == CORNERS[a][1] or xw == CORNERS[a][0]) and (zw != "" or xw != "")
				var pc: bool = (zw == CORNERS[c][1] or xw == CORNERS[c][0]) and (zw != "" or xw != "")
				if pa != pc:
					return pa
				var fa: float = far.call(a)
				var fc: float = far.call(c)
				if absf(fa - fc) > 1e-6:
					return fa > fc
				return a < c)
			var cands := []
			for ci in order:
				if only >= 0 and ci != only:
					continue
				for yi in infos.size():
					var sz: Vector2 = infos[yi]["size"]
					cands.append([Vector2(_lo(inner.position.x, sz.x * 0.5) if CORNERS[ci][0] == "left" else _hi(inner.end.x, sz.x * 0.5),
						_lo(inner.position.y, sz.y * 0.5) if CORNERS[ci][1] == "front" else _hi(inner.end.y, sz.y * 0.5)), yi])
			found = _first(cx, infos, cands)
			if found == null and not cands.is_empty():   # the corner's own place is taken: the nearest clear place within 3 m of it ("2 crates in the corner")
				var anchor: Vector2 = cands[0][0]
				for c in _cells(cx, infos, anchor):
					if (c[0] as Vector2).distance_to(anchor) > 3.0 + EPS:
						break
					if _legal(cx, c[0], infos[int(c[1])]["size"]):
						found = c
						break
		"middle":
			infos = _infos(b, p0)
			found = _first(cx, infos, _cells(cx, infos, inner.get_center()))
		"around":
			infos = _infos(b, p0)
			var sz0: Vector2 = infos[0]["size"]
			var cands := []
			var xl := _lo(inner.position.x, sz0.x * 0.5)
			var xh := _hi(inner.end.x, sz0.x * 0.5)
			var zl := _lo(inner.position.y, sz0.y * 0.5)
			var zh := _hi(inner.end.y, sz0.y * 0.5)
			var far2 := func(c: Vector2) -> float:
				var dmin := 1e9
				for d in cx["doors"]:
					dmin = minf(dmin, c.distance_to((d["zone"] as Rect2).get_center()))
				return dmin
			var corners := [Vector2(xl, zh), Vector2(xh, zh), Vector2(xl, zl), Vector2(xh, zl)]
			corners.sort_custom(func(a, c): return far2.call(a) > far2.call(c) + 1e-6)
			cands.append_array(corners.map(func(c): return [c, 0]))
			var xm := snappedf(inner.get_center().x, G)
			var zm := snappedf(inner.get_center().y, G)
			for c in [Vector2(xm, zh), Vector2(xm, zl), Vector2(xl, zm), Vector2(xh, zm)]:
				cands.append([c, 0])
			for c in [Vector2(snappedf(inner.position.x + inner.size.x * 0.25, G), zh), Vector2(snappedf(inner.position.x + inner.size.x * 0.75, G), zh),
					Vector2(snappedf(inner.position.x + inner.size.x * 0.25, G), zl), Vector2(snappedf(inner.position.x + inner.size.x * 0.75, G), zl),
					Vector2(xl, snappedf(inner.position.y + inner.size.y * 0.25, G)), Vector2(xl, snappedf(inner.position.y + inner.size.y * 0.75, G)),
					Vector2(xh, snappedf(inner.position.y + inner.size.y * 0.25, G)), Vector2(xh, snappedf(inner.position.y + inner.size.y * 0.75, G))]:
				cands.append([c, 0])
			found = _first(cx, infos, cands)
		"door":
			infos = _infos(b, p0)
			var cands := []
			for d in cx["doors"]:
				if String(s.get("wall", "")) != "" and String(d["wall"]) != String(s["wall"]):
					continue
				cands.append_array(_wall_cands(cx, infos, String(d["wall"]), float(d["mid"])))
			if cands.is_empty():
				return _no("There is no door %sto put the %s by." % ["on the %s wall " % s["wall"] if String(s.get("wall", "")) != "" else "", nm])
			found = _first(cx, infos, cands)
		_:   # "wall" / "along"
			var stretch := at == "along"
			for wl in _walls_for(s, k, stretch):
				var q := p0.duplicate()
				if stretch and kind == "fence" and tmpl.is_empty():
					var run := _free_run(cx, String(wl))
					var len := floorf((float(run[1]) - float(run[0]) + EPS) / G) * G
					if len >= 0.5:
						var def: Array = BuildPieces.DEFS["fence"]["params"]["w"]
						q["w"] = clampf(len, def[1], def[2])
				var inf := _infos(b, q)
				var target := _wall_mid(cx, String(wl), (float(k) + 0.5) / float(maxi(n, 1)))
				if stretch and kind == "fence" and tmpl.is_empty():
					var run2 := _free_run(cx, String(wl))
					target = (float(run2[0]) + float(run2[1])) * 0.5
				var f: Variant = _first(cx, inf, _wall_cands(cx, inf, String(wl), target))
				if f != null:
					found = f
					infos = inf
					if q.get("w") != p0.get("w"):
						setd["w"] = q["w"]
					break
				infos = inf
	if found == null:
		var fits := false
		for inf in (infos if not infos.is_empty() else _infos(b, p0)):
			var sz: Vector2 = inf["size"]
			if sz.x <= inner.size.x + EPS and sz.y <= inner.size.y + EPS:
				fits = true
		var sz0b: Vector2 = (infos if not infos.is_empty() else _infos(b, p0))[0]["size"]
		if not fits:
			return _no("Can't fit the %s: it is %s x %s m and this room is %s x %s m inside." % [nm, _n(sz0b.x), _n(sz0b.y), _n(inner.size.x), _n(inner.size.y)])
		return _no("Can't fit the %s %s: it is %s x %s m and nothing is clear there (the walls, %s m in front of each door, and the other pieces are in the way)." % [nm, area_text(s), _n(sz0b.x), _n(sz0b.y), _n(KEEP)])
	var info: Dictionary = infos[int(found[1])]
	return {"ok": true, "x": (found[0] as Vector2).x, "z": (found[0] as Vector2).y, "yaw": float(info["yaw"]), "storey": storey, "set": setd}


static func _n(v: float) -> String:
	var s := "%.2f" % v
	return s.rstrip("0").rstrip(".") if s.contains(".") else s


## put the specs on the record, in the sentence's order (a ramp to a platform after the platforms). Returns {"ids": [], "res": [{"placed", "ids", "why"}]
## per spec}; a piece that does not fit is left out and said
static func place(b: Dictionary, specs: Array) -> Dictionary:
	var order := range(specs.size())
	order.sort_custom(func(a, c):
		var ta := String(specs[a].get("to", "")) != ""
		var tc := String(specs[c].get("to", "")) != ""
		if ta != tc:
			return tc
		return a < c)
	var res := []
	res.resize(specs.size())
	var ids := []
	for i in order:
		var s: Dictionary = specs[i]
		var n := int(s.get("n", 1))
		var r := {"placed": 0, "ids": [], "why": ""}
		for k in n:
			var f := find(b, s, k, n)
			if not bool(f["ok"]):
				if String(r["why"]) == "":
					r["why"] = String(f["why"])
				continue
			var id := Building.add_piece(b, String(s["kind"]), float(f["x"]), float(f["z"]), float(f["yaw"]), int(f["storey"]))
			var pc := Building.piece_of(b, id)
			for key in f["set"]:
				pc[key] = f["set"][key]
			ids.append(id)
			(r["ids"] as Array).append(id)
			r["placed"] = int(r["placed"]) + 1
		res[i] = r
	return {"ids": ids, "res": res}


## what place() would say for these specs on this building, without touching it
static func report(b: Dictionary, specs: Array) -> Array:
	return place(b.duplicate(true), specs)["res"]


# ---------------------------------------------------------------- the edits

static func _matches(p: Dictionary, kind: String) -> bool:
	var pk := String(p["kind"])
	return pk == kind or (kind == "stairs" and pk == "stairs_l")


static func pieces_of(b: Dictionary, kind: String) -> Array:
	return b.get("pieces", []).filter(func(p): return _matches(p, kind))


## the one piece an edit means ("the crate"): {"p"} or {"error"}; several of a kind need "all" (or a plural)
static func _the_piece(b: Dictionary, e: Dictionary) -> Dictionary:
	var kind := String(e["kind"])
	var list := pieces_of(b, kind)
	var nm := label(kind, 1)
	if list.is_empty():
		return {"error": "There is no %s to %s." % [nm, String(e.get("verb", "change"))]}
	if list.size() > 1:
		return {"error": "Which %s? There are %d. Say '%s all the %s'." % [nm, list.size(), "remove" if String(e["op"]) == "remove_piece" else "turn", label(kind, 2)]}
	return {"p": list[0]}


static func apply(b: Dictionary, e: Dictionary) -> Dictionary:
	match String(e["op"]):
		"add_pieces":
			var specs: Array = e["specs"]
			if specs.is_empty():
				return {"ok": false, "error": "Add what? Say a piece: stairs, a table, a bench, a crate, pillars, a fence, a ramp or a platform."}
			var r := place(b, specs)
			if (r["ids"] as Array).is_empty():
				var whys := []
				for x in r["res"]:
					if String(x["why"]) != "" and not whys.has(String(x["why"])):
						whys.append(String(x["why"]))
				return {"ok": false, "error": " ".join(whys) + " Nothing was added."}
			var done := []
			var left := []
			for i in specs.size():
				var x: Dictionary = r["res"][i]
				if int(x["placed"]) > 0:
					done.append("%d %s" % [int(x["placed"]), label(String(specs[i]["kind"]), int(x["placed"]))] if int(x["placed"]) != 1 else "a " + label(String(specs[i]["kind"]), 1))
				if int(x["placed"]) < int(specs[i]["n"]):
					left.append("%d %s: %s" % [int(specs[i]["n"]) - int(x["placed"]), label(String(specs[i]["kind"]), int(specs[i]["n"]) - int(x["placed"])), x["why"]])
			var say := "Added %s" % ", ".join(done)
			if not left.is_empty():
				say += ". Left out: " + " ".join(left)
			return {"ok": true, "say": say}
		"remove_piece":
			var list := pieces_of(b, String(e["kind"]))
			if list.is_empty():
				return {"ok": false, "error": "There is no %s to remove." % label(String(e["kind"]), 1)}
			if list.size() > 1 and not bool(e.get("all", false)):
				return {"ok": false, "error": "Which %s? There are %d. Say 'remove all the %s'." % [label(String(e["kind"]), 1), list.size(), label(String(e["kind"]), 2)]}
			var was_stairs := false
			for p in list:
				was_stairs = was_stairs or BuildPieces.is_stairs(p)
				Building.remove_piece(b, String(p["id"]))
			return {"ok": true, "say": "Removed %d %s%s" % [list.size(), label(String(e["kind"]), list.size()), " (the floor above is whole again)" if was_stairs else ""]}
		"turn_piece":
			var tp := _the_piece(b, {"op": "turn_piece", "kind": e["kind"], "verb": "turn"})
			if tp.has("error"):
				return {"ok": false, "error": tp["error"]}
			var p: Dictionary = tp["p"]
			var yaw := fposmod(float(p.get("yaw", 0.0)) + 90.0, 360.0)
			var room := _room_on(b, int(p.get("storey", 0)))
			var cx := context(b, room, int(p.get("storey", 0)), String(p["id"]))
			var q := p.duplicate()
			q["yaw"] = yaw
			var fp := BuildPieces.footprint(b, q)
			if not _legal(cx, fp.get_center(), fp.size):
				return {"ok": false, "error": "The %s cannot turn here: turned, it would touch a wall, a door's space or another piece." % label(String(p["kind"]), 1)}
			p["yaw"] = yaw
			return {"ok": true, "say": "Turned the %s a quarter turn (now facing %d degrees)" % [label(String(p["kind"]), 1), int(yaw)]}
		"move_piece":
			var mp := _the_piece(b, {"op": "move_piece", "kind": e["kind"], "verb": "move"})
			if mp.has("error"):
				return {"ok": false, "error": mp["error"]}
			var p2: Dictionary = mp["p"]
			var s: Dictionary = new_spec(String(p2["kind"]), 1)
			s["at"] = String(e.get("at", ""))
			s["wall"] = String(e.get("wall", ""))
			s["walls"] = [] if String(s["wall"]) == "" else [String(s["wall"])]
			s["storey"] = int(p2.get("storey", 0))
			var f := find(b, s, 0, 1, String(p2["id"]), p2)
			if not bool(f["ok"]):
				return {"ok": false, "error": String(f["why"]) + " It stays where it is."}
			p2["x"] = float(f["x"])
			p2["z"] = float(f["z"])
			p2["yaw"] = float(f["yaw"])
			return {"ok": true, "say": "Moved the %s %s (now at %.1f, %.1f m)" % [label(String(p2["kind"]), 1), area_text(s), float(f["x"]), float(f["z"])]}
	return {"ok": false, "error": "Kine cannot do that with pieces yet."}


static func describe(e: Dictionary) -> String:
	match String(e["op"]):
		"add_pieces":
			return "Add " + specs_text(e["specs"])
		"remove_piece":
			return "Remove %s%s" % ["all the " + label(String(e["kind"]), 2) if bool(e.get("all", false)) else "the " + label(String(e["kind"]), 1), ""]
		"turn_piece":
			return "Turn the %s a quarter turn" % label(String(e["kind"]), 1)
		"move_piece":
			return "Move the %s %s" % [label(String(e["kind"]), 1), area_text({"kind": e["kind"], "at": e.get("at", ""), "wall": e.get("wall", ""), "walls": [] if String(e.get("wall", "")) == "" else [e["wall"]], "to": ""})]
	return ""
