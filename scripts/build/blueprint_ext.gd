## blueprint_ext.gd - OPT-IN extras for drawing sheets (complaints #423, #432, #441). Nothing here changes a default: with the
## "Default" dimension preset, no custom paper and no callouts, every sheet is byte-for-byte what blueprint.gd drew before.
##  - DIM PRESETS (#432): named sets of {gap: extension line gap, over: extension overshoot, tgap: text gap, bg: text background}, all mm
##  - CUSTOM SHEETS (#441): any W x H mm paper at any scale, 1:1 included (the SVG is W x H mm and 1 m of building = 1000 mm on it)
##  - CALLOUTS (#423): a boxed detail letter (editable) whose leader starts ON THE EDGE of the text box and ends at the target
class_name BlueprintExt
extends RefCounted

const DIM_PRESETS := {
	"Default": {"gap": 1.5, "over": 1.5, "tgap": 0.8, "bg": false},
	"Tight": {"gap": 0.5, "over": 1.0, "tgap": 0.3, "bg": false},
	"Airy": {"gap": 3.0, "over": 2.5, "tgap": 1.6, "bg": false},
	"Boxed": {"gap": 1.5, "over": 1.5, "tgap": 0.8, "bg": true},
}
const MIN_MM := 100.0
const MAX_MM := 20000.0
const CALL_H := 3.5   # mm: callout letter height
static var active := "Default"
static var user_presets := {}   # name -> a preset dictionary (saved by the user)


static func preset_names() -> Array:
	var out: Array = DIM_PRESETS.keys()
	for k in user_presets:
		if not out.has(k):
			out.append(k)
	return out


static func dim_params() -> Dictionary:
	if user_presets.has(active):
		return user_presets[active]
	return DIM_PRESETS.get(active, DIM_PRESETS["Default"])


## selects a preset by name (false when unknown)
static func use_preset(nm: String) -> bool:
	if not (DIM_PRESETS.has(nm) or user_presets.has(nm)):
		return false
	active = nm
	return true


## saves a named set; values are clamped to 0..10 mm. false for an empty name
static func save_preset(nm: String, gap: float, over: float, tgap: float, bg: bool) -> bool:
	nm = nm.strip_edges()
	if nm == "" or DIM_PRESETS.has(nm):
		return false
	user_presets[nm] = {"gap": clampf(gap, 0.0, 10.0), "over": clampf(over, 0.0, 10.0), "tgap": clampf(tgap, 0.0, 10.0), "bg": bg}
	return true


## the white box behind a dimension's text (a poly in class dim-bg)
static func dim_bg(p: Vector2, txt: String, horiz: bool) -> Dictionary:
	var w := 0.55 * Blueprint.TXT * float(txt.length()) + 1.0
	var h := Blueprint.TXT + 0.6
	var r := Rect2(p.x - w * 0.5, p.y - Blueprint.TXT * 0.85, w, h) if horiz else Rect2(p.x - Blueprint.TXT * 0.85 - 0.3, p.y - w * 0.5, h, w)
	return {"t": "poly", "pts": PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), "cls": "dim-bg", "d": {}}


## registers a W x H mm paper at 1:denom and returns the pick for Blueprint.sheet ({} when the size is out of range)
static func custom_pick(w: float, h: float, denom: int = 1) -> Dictionary:
	if w < MIN_MM or h < MIN_MM or w > MAX_MM or h > MAX_MM or denom < 1:
		return {}
	var nm := "Custom %dx%d" % [roundi(w), roundi(h)]
	Blueprint.custom_papers[nm] = Vector2(roundf(w), roundf(h))
	return {"paper": nm, "denom": denom}


# ---------------------------------------------------------------- callouts

static func _box(p: Vector2, letter: String) -> Rect2:
	var w := maxf(CALL_H * 0.7 * float(letter.length()), CALL_H) + 2.0
	var h := CALL_H + 2.0
	return Rect2(p.x - w * 0.5, p.y - CALL_H * 0.5 - h * 0.5 + CALL_H * 0.15, w, h)


## where the ray from the box's centre toward t leaves the box
static func edge_point(r: Rect2, t: Vector2) -> Vector2:
	var c := r.get_center()
	var d := t - c
	if d.length() < 0.001:
		return c
	var sx := INF if absf(d.x) < 0.0001 else (r.size.x * 0.5) / absf(d.x)
	var sy := INF if absf(d.y) < 0.0001 else (r.size.y * 0.5) / absf(d.y)
	return c + d * minf(sx, sy)


static func clean_letter(s: String) -> String:
	s = s.strip_edges().to_upper().left(3)
	return s if s != "" else "A"


## the entities of one callout: box, letter, leader (from the box edge to target), a dot at the target
static func callout(letter: String, p: Vector2, target: Vector2) -> Array:
	letter = clean_letter(letter)
	var r := _box(p, letter)
	var d := {"letter": letter}
	return [
		{"t": "poly", "pts": PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), "cls": "callout", "d": d},
		{"t": "text", "p": Vector2(p.x, p.y + CALL_H * 0.35), "s": letter, "h": CALL_H, "anc": "m", "rot": 0.0, "cls": "callout-text", "d": d},
		{"t": "line", "a": edge_point(r, target), "b": target, "cls": "leader", "d": d},
		{"t": "arc", "c": target, "r": 0.6, "a0": 0.0, "a1": TAU, "cls": "leader", "d": d},
	]


## callouts = [{"letter", "p", "t"}]; appends their entities to the sheet (returns it)
static func apply_callouts(sh: Dictionary, callouts: Array) -> Dictionary:
	for c in callouts:
		sh["ents"].append_array(callout(String(c["letter"]), c["p"], c["t"]))
	return sh


## renames a callout in a list (the list is what the UI keeps); false when there is no such letter
static func rename_callout(callouts: Array, old: String, nu: String) -> bool:
	for c in callouts:
		if String(c["letter"]) == old:
			c["letter"] = clean_letter(nu)
			return true
	return false


## the next free letter A, B, C ...
static func next_letter(callouts: Array) -> String:
	var used := {}
	for c in callouts:
		used[String(c["letter"])] = true
	for i in 26:
		var l := char(65 + i)
		if not used.has(l):
			return l
	return "Z"
