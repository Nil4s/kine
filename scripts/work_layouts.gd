class_name WorkLayouts
extends RefCounted
## WORKSPACE LAYOUTS (lane L20, GAP_AUDIT_1106 #4; Expert / Engineering only). A layout says, per page (Part, Assembly, Engineering, Animate),
## which panels are open, which dock each sits on (left, right, bottom, or float), the dock sizes (left / right column width, bottom height) and the
## tool rail's width. Named layouts are kept in one JSON file (user://kine_layouts.json) with a schema version:
##   {"schema": 1, "active": "<name or ''>", "current": <layout>, "layouts": {"<name>": <layout>, ...}}
## A file that cannot be read, is the wrong shape, or has another schema falls back to the factory default (`fallback` is true; nothing crashes).
## The geometry (solve) is pure: it places the open panels of a page in a clear area so that nothing overlaps, nothing leaves the area, every panel keeps
## its minimum size and the 3D view keeps at least MIN_VIEW (60 %) of the window; when a saved layout cannot satisfy that on a smaller window the dock
## sizes shrink toward the minimums, then the last panels are closed (reported in "closed"). `check` measures a set of rects against the same limits
## (the L2 screen limits of docs/UIEXP_DESIGN.md). The live placement is scripts/uiexp_shell.gd (dock_apply); the dialog is scripts/work_layouts_ui.gd.

const SCHEMA := 1
const FACTORY := "Factory"
const PAGES := ["part", "assembly", "engineering", "animate"]
const DOCKS := ["left", "right", "bottom", "float"]
const DETACHABLE := ["timeline", "graph", "view2"]   # L37: panels that can live in their own OS window; "detached" holds id -> [x, y, w, h]
const MIN_VIEW := 0.60
const GAP := 8.0
const TOP := 81.0          # the ribbon bar
const PAGEBAR := 34.0
const RAIL_MIN := 96
const RAIL_MAX := 200
const RAIL_H_EST := 640.0  # the rail's usual height (Part: four groups)
const SPLIT_MIN := 100
const SPLIT_MAX := 1200
const CUBE_COL := 132.0 + 24.0
const CENTER_MIN := Vector2(240, 160)   # the free middle (the 3D view) never gets narrower / lower than this

## per page: panel id -> {title, dock, order, min, want (size when the app places it itself), open}
const PANEL_DEFS := {
	"part": {
		"browser": {"title": "Part browser", "dock": "left", "order": 0, "min": Vector2(196, 120), "want": Vector2(196, 300), "open": true},
		"inspector": {"title": "Inspector (dialogs)", "dock": "right", "order": 0, "min": Vector2(300, 160), "want": Vector2(300, 420), "open": true},
		"timeline": {"title": "Timeline", "dock": "bottom", "order": 0, "min": Vector2(400, 84), "want": Vector2(1000, 84), "open": true},
	},
	"assembly": {
		"parts": {"title": "Add part list", "dock": "left", "order": 0, "min": Vector2(250, 160), "want": Vector2(250, 420), "open": true},
		"inspector": {"title": "Assembly panel", "dock": "right", "order": 0, "min": Vector2(300, 200), "want": Vector2(300, 560), "open": true},
	},
	"engineering": {
		"parts": {"title": "Add part list", "dock": "left", "order": 0, "min": Vector2(250, 160), "want": Vector2(250, 420), "open": true},
		"inspector": {"title": "Assembly panel", "dock": "right", "order": 0, "min": Vector2(300, 200), "want": Vector2(300, 560), "open": true},
		"fits": {"title": "Fits and stack-up", "dock": "left", "order": 1, "min": Vector2(250, 160), "want": Vector2(300, 420), "open": true},
	},
	"animate": {
		"browser": {"title": "Browser", "dock": "left", "order": 0, "min": Vector2(200, 160), "want": Vector2(240, 500), "open": true},
		"inspector": {"title": "Inspector", "dock": "right", "order": 0, "min": Vector2(240, 160), "want": Vector2(290, 500), "open": true},
		"timeline": {"title": "Timeline", "dock": "bottom", "order": 0, "min": Vector2(400, 160), "want": Vector2(1000, 248), "open": true},
	},
}
const SPLIT_OF := {
	"part": {"left": 196, "right": 300, "bottom": 84},
	"assembly": {"left": 250, "right": 300, "bottom": 160},
	"engineering": {"left": 300, "right": 300, "bottom": 160},
	"animate": {"left": 240, "right": 290, "bottom": 248},
}

var path := "user://kine_layouts.json"
var layouts := {}       # name -> layout
var cur := {}           # the working layout (what the screens show)
var active := ""        # the name cur was loaded from / saved as ("" = the factory default or unsaved)
var fallback := false   # the file was unreadable / wrong schema: the factory default is in use


func _init(p := "user://kine_layouts.json") -> void:
	path = p
	cur = factory()
	load_file()


# ---------------------------------------------------------------------------------------------------- the data

static func factory() -> Dictionary:
	var pages := {}
	for pg in PAGES:
		var panels := {}
		for id in PANEL_DEFS[pg]:
			var df: Dictionary = PANEL_DEFS[pg][id]
			panels[id] = {"open": bool(df["open"]), "dock": String(df["dock"]), "order": int(df["order"]), "float": [320, 220, int(df["want"].x), int(df["want"].y)]}
		pages[pg] = {"rail_w": RAIL_MIN, "splits": (SPLIT_OF[pg] as Dictionary).duplicate(), "panels": panels}
	return {"pages": pages, "detached": {}}


## the right shape (every page, every panel a dictionary)? A wrong shape is a corrupt file, a wrong value is repaired by sanitize
static func shaped(L: Variant) -> bool:
	if not (L is Dictionary) or not (L as Dictionary).has("pages") or not ((L as Dictionary)["pages"] is Dictionary):
		return false
	for pg in PAGES:
		var P: Variant = (L as Dictionary)["pages"].get(pg, null)
		if not (P is Dictionary) or not ((P as Dictionary).get("panels", null) is Dictionary) or not ((P as Dictionary).get("splits", null) is Dictionary):
			return false
		for id in (P as Dictionary)["panels"]:
			if not (((P as Dictionary)["panels"] as Dictionary)[id] is Dictionary):
				return false
	return true


## every field present, typed and clamped; unknown panels and keys dropped
static func sanitize(L: Dictionary) -> Dictionary:
	var out := factory()
	var src: Dictionary = L.get("pages", {}) if L.get("pages", {}) is Dictionary else {}
	for pg in PAGES:
		var P: Dictionary = src.get(pg, {}) if src.get(pg, {}) is Dictionary else {}
		var O: Dictionary = out["pages"][pg]
		O["rail_w"] = clampi(int(P.get("rail_w", RAIL_MIN)), RAIL_MIN, RAIL_MAX)
		var sp: Dictionary = P.get("splits", {}) if P.get("splits", {}) is Dictionary else {}
		for k in ["left", "right", "bottom"]:
			O["splits"][k] = clampi(int(sp.get(k, O["splits"][k])), SPLIT_MIN, SPLIT_MAX)
		var pn: Dictionary = P.get("panels", {}) if P.get("panels", {}) is Dictionary else {}
		for id in O["panels"]:
			var Q: Dictionary = pn.get(id, {}) if pn.get(id, {}) is Dictionary else {}
			var T: Dictionary = O["panels"][id]
			T["open"] = bool(Q.get("open", T["open"]))
			var dk := String(Q.get("dock", T["dock"]))
			T["dock"] = dk if DOCKS.has(dk) else String(PANEL_DEFS[pg][id]["dock"])
			T["order"] = clampi(int(Q.get("order", T["order"])), 0, 99)
			var fl: Variant = Q.get("float", T["float"])
			if fl is Array and (fl as Array).size() == 4:
				T["float"] = [clampi(int(fl[0]), 0, 4000), clampi(int(fl[1]), 0, 4000), clampi(int(fl[2]), 0, 4000), clampi(int(fl[3]), 0, 4000)]
	var dt: Dictionary = L.get("detached", {}) if L.get("detached", {}) is Dictionary else {}
	for id in DETACHABLE:
		var a: Variant = dt.get(id, null)
		if a is Array and (a as Array).size() == 4 and (a as Array).all(func(v): return v is int or v is float):
			out["detached"][id] = [clampi(int(a[0]), -16000, 16000), clampi(int(a[1]), -16000, 16000), clampi(int(a[2]), 160, 16000), clampi(int(a[3]), 100, 16000)]
	return out


static func same(a: Variant, b: Variant) -> bool:
	return JSON.stringify(a, "\t", true) == JSON.stringify(b, "\t", true)


static func clean_name(n: String) -> String:
	var s := n.strip_edges()
	if s.length() < 1 or s.length() > 40 or s.to_lower() == FACTORY.to_lower():
		return ""
	for i in s.length():
		if s.unicode_at(i) < 32:
			return ""
	return s


# ---------------------------------------------------------------------------------------------------- the store

func names() -> Array:
	var a := layouts.keys()
	a.sort()
	return a


func is_factory() -> bool:   # detached windows do not count: they leave the docked panels where the app puts them
	var c := cur.duplicate()
	c["detached"] = {}
	return same(c, factory())


func serialize() -> String:
	return JSON.stringify({"schema": SCHEMA, "active": active, "current": cur, "layouts": layouts}, "\t", true)


func save_file() -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(serialize())
	f.close()
	return true


func _default() -> void:
	cur = factory()
	layouts = {}
	active = ""


func load_file() -> void:
	fallback = false
	_default()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		fallback = true
		return
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if txt.strip_edges() == "" or j.parse(txt) != OK or not (j.data is Dictionary):
		fallback = true
		return
	var D: Dictionary = j.data
	if not D.has("schema") or not (D["schema"] is float or D["schema"] is int) or int(D["schema"]) != SCHEMA or not (D.get("layouts", null) is Dictionary) or not shaped(D.get("current", null)):
		fallback = true
		return
	var ls := {}
	for n in D["layouts"]:
		if clean_name(String(n)) != String(n) or not shaped(D["layouts"][n]):
			fallback = true
			_default()
			return
		ls[String(n)] = sanitize(D["layouts"][n])
	layouts = ls
	cur = sanitize(D["current"])
	var a := String(D.get("active", ""))
	active = a if layouts.has(a) else ""


## the working layout stored under a name (an existing name is overwritten)
func save_as(name: String) -> bool:
	var n := clean_name(name)
	if n == "":
		return false
	layouts[n] = sanitize(cur.duplicate(true))
	active = n
	return save_file()


func load_named(name: String) -> bool:
	if not layouts.has(name):
		return false
	cur = sanitize((layouts[name] as Dictionary).duplicate(true))
	active = name
	save_file()
	return true


func rename(old: String, new: String) -> bool:
	var n := clean_name(new)
	if n == "" or not layouts.has(old) or layouts.has(n):
		return false
	layouts[n] = layouts[old]
	layouts.erase(old)
	if active == old:
		active = n
	return save_file()


func delete(name: String) -> bool:
	if not layouts.has(name):
		return false
	layouts.erase(name)
	if active == name:
		active = ""
	return save_file()


## back to the factory default (the saved layouts stay)
func reset() -> void:
	cur = factory()
	active = ""
	save_file()


func touch() -> void:
	cur = sanitize(cur)
	save_file()


func set_dock(page: String, id: String, dock: String) -> bool:
	if not cur["pages"].has(page) or not cur["pages"][page]["panels"].has(id) or not DOCKS.has(dock):
		return false
	var top := 0
	for k in cur["pages"][page]["panels"]:
		top = maxi(top, int(cur["pages"][page]["panels"][k]["order"]))
	var T: Dictionary = cur["pages"][page]["panels"][id]
	T["dock"] = dock
	T["order"] = mini(top + 1, 99)
	T["open"] = true
	touch()
	return true


func set_open(page: String, id: String, on: bool) -> void:
	if cur["pages"].has(page) and cur["pages"][page]["panels"].has(id):
		cur["pages"][page]["panels"][id]["open"] = on
		touch()


func set_split(page: String, dock: String, px: int) -> void:
	if cur["pages"].has(page) and cur["pages"][page]["splits"].has(dock):
		cur["pages"][page]["splits"][dock] = px
		touch()


func set_rail(page: String, px: int) -> void:
	if cur["pages"].has(page):
		cur["pages"][page]["rail_w"] = px
		touch()


# ---------------------------------------------------------------------------------------------------- the geometry

## the clear area for the panels of a window of this size (the app's nav_clear_rect without the native side panels)
static func area_for(window: Vector2, rail_w: int) -> Rect2:
	var x0 := float(rail_w) + 8.0
	var y0 := TOP
	return Rect2(x0, y0, window.x - CUBE_COL - x0, window.y - 128.0 - y0)


## the pixels of the window that fixed chrome takes (ribbon bar, page bar, the rail), so the view's share can be told from the panels' rects
static func chrome_px(window: Vector2, rail_w: int) -> float:
	return (TOP + PAGEBAR) * window.x + float(rail_w) * minf(RAIL_H_EST, window.y - TOP)


static func share_of(rects: Dictionary, window: Vector2, chrome: float) -> float:
	var a := chrome
	for id in rects:
		a += (rects[id] as Rect2).get_area()
	return 1.0 - a / (window.x * window.y)


## measures: overlaps [[a, b]], outside [ids] (outside the window or the clear area), small [ids] (under their minimum), view_share
static func check(rects: Dictionary, page: String, window: Vector2, area: Rect2, chrome: float) -> Dictionary:
	var ids := rects.keys()
	var ov := []
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if (rects[ids[i]] as Rect2).intersection(rects[ids[j]]).get_area() >= 4.0:
				ov.append([ids[i], ids[j]])
	var out := []
	var small := []
	var win := Rect2(Vector2.ZERO, window)
	var ar := area.grow(1.0)
	for id in ids:
		var r: Rect2 = rects[id]
		if not win.encloses(r) or not ar.encloses(r):
			out.append(id)
		var df: Dictionary = PANEL_DEFS[page].get(id, {})
		if not df.is_empty() and (r.size.x < (df["min"] as Vector2).x - 0.5 or r.size.y < (df["min"] as Vector2).y - 0.5):
			small.append(id)
	return {"overlaps": ov, "outside": out, "small": small, "view_share": share_of(rects, window, chrome)}


## place the open panels of one page. only: ids that exist now (live: the visible panels); mins / wants override the defaults per id.
## Returns {"rects": {id: Rect2}, "closed": [ids closed to fit the limits], "dock": {id: dock}}
static func solve(P: Dictionary, page: String, window: Vector2, area: Rect2, chrome: float, only := [], mins := {}, wants := {}) -> Dictionary:
	var defs: Dictionary = PANEL_DEFS[page]
	var ids := []
	for id in defs:
		if P["panels"].has(id) and bool(P["panels"][id]["open"]) and (only.is_empty() or only.has(id)):
			ids.append(id)
	var mn := {}
	var wn := {}
	for id in defs:
		mn[id] = mins.get(id, defs[id]["min"])
		wn[id] = Vector2(maxf(wants.get(id, defs[id]["want"]).x, mn[id].x), maxf(wants.get(id, defs[id]["want"]).y, mn[id].y))
	var closed := []
	while true:
		var best := {}
		var t := 1.0
		while t >= -0.001:
			var r: Variant = _build(P, ids, mn, wn, area, maxf(t, 0.0))
			if r != null and share_of(r, window, chrome) >= MIN_VIEW:
				best = r
				break
			t -= 0.05
		if not best.is_empty() or ids.is_empty():
			var dk := {}
			for id in best:
				dk[id] = String(P["panels"][id]["dock"])
			return {"rects": best, "closed": closed, "dock": dk}
		# nothing fits at the minimum sizes: close one (floats first, then the last of the bottom, right, left docks)
		var victim := ""
		for dkn in ["float", "bottom", "right", "left"]:
			var hit := ids.filter(func(i): return String(P["panels"][i]["dock"]) == dkn)
			if not hit.is_empty():
				hit.sort_custom(func(a, b): return int(P["panels"][a]["order"]) > int(P["panels"][b]["order"]))
				victim = hit[0]
				break
		ids.erase(victim)
		closed.append(victim)
	return {}


static func _by_order(P: Dictionary, ids: Array, dock: String) -> Array:
	var a := ids.filter(func(i): return String(P["panels"][i]["dock"]) == dock)
	a.sort_custom(func(x, y): return int(P["panels"][x]["order"]) < int(P["panels"][y]["order"]) or (int(P["panels"][x]["order"]) == int(P["panels"][y]["order"]) and String(x) < String(y)))
	return a


## one try at size factor t (1 = the layout's own dock sizes, 0 = the panels' minimums); null when the minimums do not fit
static func _build(P: Dictionary, ids: Array, mn: Dictionary, wn: Dictionary, area: Rect2, t: float) -> Variant:
	var L := _by_order(P, ids, "left")
	var R := _by_order(P, ids, "right")
	var B := _by_order(P, ids, "bottom")
	var F := _by_order(P, ids, "float")
	var colw := {"left": 0.0, "right": 0.0}
	for pair in [["left", L], ["right", R]]:
		if not (pair[1] as Array).is_empty():
			var lo := 0.0
			for id in pair[1]:
				lo = maxf(lo, mn[id].x)
			var hi := clampf(float(P["splits"][pair[0]]), lo, maxf(lo, area.size.x * 0.45))
			colw[pair[0]] = lerpf(lo, hi, t)
	var bh := 0.0
	if not B.is_empty():
		var lo2 := 0.0
		for id in B:
			lo2 = maxf(lo2, mn[id].y)
		bh = lerpf(lo2, clampf(float(P["splits"]["bottom"]), lo2, maxf(lo2, area.size.y * 0.4)), t)
	var g := GAP
	var x0 := area.position.x + g
	var x1 := area.end.x - g
	var y0 := area.position.y + g
	var y1 := area.end.y - g - ((bh + g) if bh > 0.0 else 0.0)
	var cx0: float = x0 + (colw["left"] + g if colw["left"] > 0.0 else 0.0)
	var cx1: float = x1 - (colw["right"] + g if colw["right"] > 0.0 else 0.0)
	if cx1 - cx0 < CENTER_MIN.x or y1 - y0 < CENTER_MIN.y:
		return null
	var rects := {}
	for pair in [["left", L, x0], ["right", R, x1 - colw["right"]]]:
		var col: Array = pair[1]
		if col.is_empty():
			continue
		var avail: float = y1 - y0 - g * (col.size() - 1)
		var sw := 0.0
		var sm := 0.0
		for id in col:
			sw += wn[id].y
			sm += mn[id].y
		if sm > avail + 0.01:
			return null
		var f := 1.0 if sw <= avail else (avail - sm) / maxf(sw - sm, 0.001)
		var y: float = y0
		for id in col:
			var h: float = mn[id].y + (wn[id].y - mn[id].y) * f
			rects[id] = Rect2(pair[2], y, colw[pair[0]], h)
			y += h + g
	if not B.is_empty():
		var wtot := x1 - x0 - g * (B.size() - 1)
		var each := wtot / B.size()
		for id in B:
			if each < mn[id].x - 0.01:
				return null
		var x := x0
		for id in B:
			rects[id] = Rect2(x, y1 + g, each, bh)
			x += each + g
	var placed: Array = []
	for id in F:
		var fl: Array = P["panels"][id]["float"]
		var w := clampf(float(fl[2]), mn[id].x, cx1 - cx0)
		var h := clampf(float(fl[3]), mn[id].y, y1 - y0)
		if mn[id].x > cx1 - cx0 or mn[id].y > y1 - y0:
			return null
		var want := Vector2(clampf(float(fl[0]), cx0, cx1 - w), clampf(float(fl[1]), y0, y1 - h))
		var spot := Rect2(want, Vector2(w, h))
		var found := false
		var yy := y0
		var cand: Array = [spot]
		while yy <= y1 - h + 0.01:
			var xx := cx0
			while xx <= cx1 - w + 0.01:
				cand.append(Rect2(xx, yy, w, h))
				xx += 40.0
			yy += 40.0
		for c in cand:
			var clash := false
			for q in placed:
				if (q as Rect2).intersection(c).get_area() >= 1.0:
					clash = true
					break
			if not clash:
				spot = c
				found = true
				break
		if not found:
			return null
		placed.append(spot)
		rects[id] = spot
	return rects
