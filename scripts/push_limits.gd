## push_limits.gd - R24: what a push does, read from numbers MEASURED by the MuJoCo humanoid (tools/physics/push_limits.py ->
## data/push_limits.json), not from a hand-written rule. From the fighting stance (scenes/hit_react.json) the sim was pushed with one
## impulse (5..60 N s, 8 directions, bisected to 1 N s) on the chest, stomach, head and shoulder; per direction the table holds
##   absorb_max  the largest impulse it takes in place (no step),
##   step_max    the largest it recovers from with a step,
##   fall_at     the smallest that knocks it down.
## label(): J <= absorb_max -> "absorbs", J < fall_at -> "steps", else "falls". Between two measured directions the LOWER number of
## the two neighbours is used (the cautious reading; the table is 45 degrees apart). The CHECK panel's hit rows use this
## (main.gd _push_rows), J from HitPhysics.measure (I2: effective mass x relative speed).
## The hand-written balance (Balance.read's support polygon, human_limits TIPPING, MARGIN_RES 2 cm) is CHECKED AGAINST the table,
## not replaced: it answers a still pose ("is the COM over the feet"), the table answers a blow, and the two are different
## questions. balance_equiv() turns the polygon's forward margin into the impulse a point mass of this mass would need to put its
## XCoM (Hof 2005: x + v / w0, w0 = sqrt(g / l)) on the edge, to set beside the sim's absorb_max / step_max.
class_name PushLimits
extends RefCounted

const PATH := "res://data/push_limits.json"
static var _t := {}


static func table() -> Dictionary:
	if _t.is_empty() and FileAccess.file_exists(PATH):
		_t = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _t


## the table's body key for a MuJoCo body name ("" = the table has no row for it)
static func key_of(sim_body: String) -> String:
	if sim_body == "spine_03":
		return "chest"
	if sim_body in ["pelvis", "spine_01", "spine_02"]:
		return "stomach"
	if sim_body in ["head", "neck_01"]:
		return "head"
	if sim_body.begins_with("clavicle") or sim_body.begins_with("upperarm"):
		return "shoulder"
	return ""


## {"absorb", "step", "fall"} (N s) for a body key and a push direction (deg, 0 = forward, 90 = his left); {} when there is no row
static func limits(key: String, dir_deg: float) -> Dictionary:
	var tb: Dictionary = table().get("table", {})
	if not tb.has(key):
		return {}
	var d := fposmod(dir_deg, 360.0)
	var a := int(floor(d / 45.0)) * 45
	var b := a if d - a < 0.001 else (a + 45) % 360
	var ra: Dictionary = tb[key][str(a)]
	var rb: Dictionary = tb[key][str(b)]
	return {"absorb": minf(ra["absorb_max"], rb["absorb_max"]), "step": minf(ra["step_max"], rb["step_max"]), "fall": minf(ra["fall_at"], rb["fall_at"])}


## "absorbs" / "steps" / "falls" ("" = no row for this body)
static func label(key: String, J: float, dir_deg: float) -> String:
	var l := limits(key, dir_deg)
	if l.is_empty():
		return ""
	if J <= float(l["absorb"]):
		return "absorbs"
	return "steps" if J < float(l["fall"]) else "falls"


static func words(key: String, J: float, dir_deg: float) -> String:
	var l := limits(key, dir_deg)
	if l.is_empty():
		return "no push-limit row for this part (the table has chest, stomach, head, shoulder)"
	return "%s  (J %.1f N s, %.0f deg; this fighter absorbs up to %.0f, steps up to %.0f, falls from %.0f N s)" % [label(key, J, dir_deg), J, dir_deg, l["absorb"], l["step"], l["fall"]]


## the hand-written balance against the table, forward: the impulse that would carry the XCoM of a body of mass_kg, COM height com_y,
## through the support polygon's forward margin (m, Balance.read) = margin x M x w0 (Hof 2005). N s.
static func balance_equiv(margin_m: float, mass_kg: float, com_y: float) -> float:
	return maxf(0.0, margin_m) * mass_kg * sqrt(9.81 / maxf(com_y, 0.3))
