## validate.gd - a scene or pose file against docs/scene.schema.json (round 13, GATES T1). The validator READS the
## schema; it does not restate it. It knows the JSON Schema 2020-12 keywords that file uses, and a keyword it does not
## know is an error in itself (so the schema cannot grow a rule this code silently skips). Paths are written the way
## python's jsonschema writes them ($.cards[3].pose.joints.head.bend), so the two can be compared (tests/schema_test.gd).
##   Validate.file("res://scenes/combo3.json") -> [] or [{"path": "$.cards[3].hold", "msg": "-1 is less than the minimum of 0"}]
class_name Validate
extends RefCounted

const SCHEMA := "res://docs/scene.schema.json"
const NOTES := ["$schema", "$id", "title", "description", "$defs"]
const KNOWN := ["$ref", "if", "then", "else", "type", "required", "properties", "additionalProperties", "propertyNames",
	"items", "minItems", "maxItems", "uniqueItems", "enum", "minimum", "maximum", "exclusiveMinimum", "dependentRequired"]


static func schema() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SCHEMA))


## a file: unreadable / not JSON are errors too, at "$"
static func file(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return [{"path": "$", "msg": "no such file: " + path}]
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK:
		return [{"path": "$", "msg": "not JSON: line %d: %s" % [j.get_error_line(), j.get_error_message()]}]
	return data(j.data)


static func data(d: Variant) -> Array:
	var s := schema()
	var out := []
	_check(d, s, s, "$", out)
	return out


static func _check(v: Variant, sc: Dictionary, root: Dictionary, path: String, out: Array) -> void:
	for k in sc:
		if not (k in KNOWN or k in NOTES):
			out.append({"path": path, "msg": "the schema uses '%s', which tools/validate.gd does not know" % k})
	if sc.has("$ref"):
		var r: String = sc["$ref"]
		if not r.begins_with("#/$defs/"):
			out.append({"path": path, "msg": "only local $refs (#/$defs/...): " + r})
			return
		_check(v, root["$defs"][r.substr(8)], root, path, out)
	if sc.has("if"):
		var probe := []
		_check(v, sc["if"], root, path, probe)
		var branch := "then" if probe.is_empty() else "else"
		if sc.has(branch):
			_check(v, sc[branch], root, path, out)
	if sc.has("type") and not _is(v, sc["type"]):
		out.append({"path": path, "msg": "%s is not of type '%s'" % [_show(v), sc["type"]]})
		return   # the rest assumes the type
	if sc.has("enum") and not _in(v, sc["enum"]):
		out.append({"path": path, "msg": "%s is not one of %s" % [_show(v), JSON.stringify(sc["enum"])]})
	if v is float or v is int:
		if sc.has("minimum") and v < sc["minimum"]:
			out.append({"path": path, "msg": "%s is less than the minimum of %s" % [_show(v), _show(sc["minimum"])]})
		if sc.has("maximum") and v > sc["maximum"]:
			out.append({"path": path, "msg": "%s is greater than the maximum of %s" % [_show(v), _show(sc["maximum"])]})
		if sc.has("exclusiveMinimum") and v <= sc["exclusiveMinimum"]:
			out.append({"path": path, "msg": "%s is less than or equal to the minimum of %s" % [_show(v), _show(sc["exclusiveMinimum"])]})
	if v is Array:
		if sc.has("minItems") and v.size() < sc["minItems"]:
			out.append({"path": path, "msg": "%s should have at least %d items" % [_show(v), int(sc["minItems"])]})
		if sc.has("maxItems") and v.size() > sc["maxItems"]:
			out.append({"path": path, "msg": "%s should have at most %d items" % [_show(v), int(sc["maxItems"])]})
		if sc.get("uniqueItems", false):
			var seen := {}
			for x in v:
				if seen.has(JSON.stringify(x)):
					out.append({"path": path, "msg": "%s has non-unique elements" % _show(v)})
					break
				seen[JSON.stringify(x)] = true
		if sc.has("items"):
			for i in v.size():
				_check(v[i], sc["items"], root, "%s[%d]" % [path, i], out)
	if v is Dictionary:
		for r in sc.get("required", []):
			if not v.has(r):
				out.append({"path": path, "msg": "'%s' is a required property" % r})
		for r in sc.get("dependentRequired", {}):
			if v.has(r):
				for need in sc["dependentRequired"][r]:
					if not v.has(need):
						out.append({"path": path, "msg": "'%s' is a dependency of '%s'" % [need, r]})
		var props: Dictionary = sc.get("properties", {})
		for k in v:
			var kp := "%s.%s" % [path, k]
			if sc.has("propertyNames"):
				var pn := []
				_check(k, sc["propertyNames"], root, kp, pn)
				if not pn.is_empty():
					var names: Array = sc["propertyNames"].get("enum", [])
					out.append({"path": kp, "msg": "'%s' is not one of the %d names here%s" % [k, names.size(), (" (closest: '%s')" % _closest(k, names)) if not names.is_empty() else ""]})
					continue
			if props.has(k):
				_check(v[k], props[k], root, kp, out)
			elif sc.has("additionalProperties"):
				var ap: Variant = sc["additionalProperties"]
				if ap is bool:
					if not ap:
						out.append({"path": kp, "msg": "'%s' is not a property this file can have (a typo?)" % k})
				else:
					_check(v[k], ap, root, kp, out)


static func _is(v: Variant, t: String) -> bool:
	match t:
		"object": return v is Dictionary
		"array": return v is Array
		"string": return v is String
		"boolean": return v is bool
		"null": return v == null
		"number": return (v is float or v is int)
		"integer": return (v is int) or (v is float and is_finite(v) and v == floorf(v))
	return false


## JSON has one number type: 1 == 1.0 here, a bool is never a number
static func _in(v: Variant, opts: Array) -> bool:
	for o in opts:
		if typeof(o) == typeof(v) and o == v:
			return true
		if (o is float or o is int) and (v is float or v is int) and float(o) == float(v):
			return true
	return false


## the name sharing the longest start with k (a typo is usually at the end: lowerarm_rr, uperarm_r is caught too)
static func _closest(k: String, names: Array) -> String:
	var best := ""
	var bs := -1.0
	for n: String in names:
		var pre := 0
		while pre < mini(k.length(), n.length()) and k[pre] == n[pre]:
			pre += 1
		var sc := pre + k.similarity(n)
		if sc > bs:
			bs = sc
			best = n
	return best


static func _show(v: Variant) -> String:
	var s := JSON.stringify(v)
	return s if s.length() <= 60 else s.left(57) + "..."
