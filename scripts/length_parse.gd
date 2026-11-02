class_name LengthParse
extends RefCounted
## W06: typed lengths with units. parse_length("1.5in", "mm") -> {ok, mm, error}.
## Units: mm, cm, m, in (or "), ft (or '). A bare number uses the project unit. "1,5" reads as 1.5 (Brazil).
## W07 (arithmetic) can replace number_of() below: it gets the text with the unit already cut off.
const MM_PER := {"mm": 1.0, "cm": 10.0, "m": 1000.0, "in": 25.4, "ft": 304.8}
const UNITS := ["mm", "cm", "in"]   # the project units offered
const SUFFIXES := [["mm", "mm"], ["cm", "cm"], ["in", "in"], ["ft", "ft"], ["\"", "in"], ["'", "ft"], ["m", "m"]]   # longest first: "mm" before "m"


## the number in a text (unit already cut off); NAN when it is not one
static func number_of(t: String) -> float:
	var v := t.strip_edges().replace(",", ".")
	if v.is_valid_float():
		return float(v)
	if NumExpr.is_expression(v):   # W07: a sum (25*2+3); the unit was cut off before this
		var r := NumExpr.eval(v)
		if bool(r["ok"]) and String(r["unit"]) == "":
			return float(r["value"])
	return NAN


## the unit a text ends with ("" when none) and the text before it
static func split_unit(text: String) -> Array:
	var t := text.strip_edges().to_lower()
	for s in SUFFIXES:
		if t.ends_with(String(s[0])):
			return [String(s[1]), t.trim_suffix(String(s[0])).strip_edges()]
	return ["", t]


static func parse_length(text: String, project_unit: String = "mm") -> Dictionary:
	var sp := split_unit(text)
	var unit: String = sp[0] if sp[0] != "" else project_unit
	if not MM_PER.has(unit):
		unit = "mm"
	var n := number_of(String(sp[1]))
	if is_nan(n):
		return {"ok": false, "mm": 0.0, "error": "type a length like 40, 4 cm or 1.5 in"}
	return {"ok": true, "mm": n * float(MM_PER[unit]), "error": ""}


## mm shown in the project unit: "38.1 mm" or, with dual on, "38.1 mm (1.50 in)" (the other unit is inches, or mm for an inch project)
static func label(mm: float, project_unit: String = "mm", dual := false) -> String:
	var main := "%s %s" % [_n(mm / float(MM_PER.get(project_unit, 1.0))), project_unit]
	if not dual:
		return main
	if project_unit == "in":
		return "%s (%s mm)" % [main, _n(mm)]
	return "%s (%.2f in)" % [main, mm / 25.4]


static func _n(v: float) -> String:
	return str(snappedf(v, 0.001))
