## custom_attr.gd - CUSTOM ATTRIBUTES on parts (ROADMAP 82). Pure helpers: no node, no scene.
##
## A part (a Body joint such as hand_r) may carry named float attributes: "grip" with a min, a max and a default. The
## values are keyed per card, at the playhead, the way a joint's angle is, and read between keys by the SAME curve a
## part key uses (PartKeys.value_at). So the value between card 1 and card 3 is the curve a joint angle keyed at those
## two cards gets, to the bit (tests/customattr_test.gd checks it against PartKeys on hand_r).
##
##   Scene.attrs = {"<part>.<name>": {"min": f, "max": f, "default": f, "keys": [{"t": s, "v": Vector3(x, 0, 0)}]}}
##
## The keys share PartKeys' key shape (x is the value; y and z stay 0), so PartKeys.put / at / value_at carry them.
## No keys = the default at every time. Before the first key and after the last the curve holds the end values.
## In the FILE: "attrs": {"<part>.<name>": {"min", "max", "default", "keys": [{"t", "v": float}]}}, written only when
## there is one (a scene without it saves and plays byte for byte as before).
## EXPORT: scripts/gltf_export.gd puts them on the part's node in the .glb as extras "poser_attrs" (see add_glb_extras).
## MIRROR: an attribute's id moves to its twin part (hand_r.grip -> hand_l.grip, Body.twin); values and keys are free.
## Mirror side (M / N, the pose's R->L and L->R): copy_side gives the other side the same attribute, same keys.
class_name CustomAttr
extends RefCounted

const SEP := "."
const MAX_NAME := 24
const DEFAULT_RANGE := Vector2(0.0, 1.0)


static func id_of(part: String, aname: String) -> String:
	return part + SEP + aname


static func part_of(id: String) -> String:
	return id.get_slice(SEP, 0)


static func name_of(id: String) -> String:
	return id.get_slice(SEP, 1)


## "" when the name is usable, else the words that say what to type
static func check_name(aname: String) -> String:
	var n := aname.strip_edges().to_lower()
	if n.is_empty():
		return "type a name first (grip, fist_hold ...)"
	var re := RegEx.create_from_string("^[a-z][a-z0-9_]{0,%d}$" % (MAX_NAME - 1))
	if re.search(n) == null:
		return "type a name of 1 to %d letters, digits or _, starting with a letter (grip, fist_hold)" % MAX_NAME
	return ""


## "" when the range is usable, else what to change
static func check_range(mn: float, mx: float, def: float) -> String:
	if not (mn < mx):
		return "type a min below the max (the slider runs from min to max)"
	if def < mn or def > mx:
		return "type a default between min and max (%s .. %s)" % [mn, mx]
	return ""


## adds the attribute to the part; "" or the error (nothing is changed on an error)
static func define(attrs: Dictionary, part: String, aname: String, mn: float, mx: float, def: float) -> String:
	if not part in Body.ORDER:
		return "pick a BODY part first: the attribute goes on a joint (hand_r, upperarm_l ...)"
	var e := check_name(aname)
	if e != "":
		return e
	e = check_range(mn, mx, def)
	if e != "":
		return e
	var id := id_of(part, aname.strip_edges().to_lower())
	if attrs.has(id):
		return "%s already has %s: pick it to key its value, or name the new one differently" % [part, name_of(id)]
	attrs[id] = {"min": mn, "max": mx, "default": def, "keys": []}
	return ""


## the attribute's value at time t: the default with no keys, else the part-key curve, held inside its range
static func value_at(attrs: Dictionary, id: String, t: float) -> float:
	if not attrs.has(id):
		return 0.0
	var a: Dictionary = attrs[id]
	var ks: Array = a.get("keys", [])
	if ks.is_empty():
		return float(a["default"])
	return clampf(PartKeys.value_at(ks, t).x, float(a["min"]), float(a["max"]))


## keys the value v at time t (a key at the same time is replaced; v is held inside min..max). false if no such attribute
static func key(attrs: Dictionary, id: String, t: float, v: float) -> bool:
	if not attrs.has(id):
		return false
	var a: Dictionary = attrs[id]
	var pk := {id: a.get("keys", [])}
	PartKeys.put(pk, id, t, Vector3(clampf(v, float(a["min"]), float(a["max"])), 0.0, 0.0))
	a["keys"] = pk[id]
	return true


## deletes the attribute and its keys; false if there is no such attribute
static func remove(attrs: Dictionary, id: String) -> bool:
	return attrs.erase(id)


## the attribute names on one part, sorted
static func names_on(attrs: Dictionary, part: String) -> Array:
	var out := []
	for id in attrs:
		if part_of(id) == part:
			out.append(name_of(id))
	out.sort()
	return out


## a copy of the list of ids, sorted (the order the inspector and the file use)
static func ids(attrs: Dictionary) -> Array:
	var out := attrs.keys()
	out.sort()
	return out


## the attribute's id moved to its twin part, same definition and keys (scene mirror: hand_r.grip -> hand_l.grip)
static func mirror_file(attrs: Dictionary) -> Dictionary:
	var out := {}
	for id in attrs:
		var nid := id_of(Body.twin(part_of(id)), name_of(id))
		out[nid] = (attrs[id] as Dictionary).duplicate(true)
	return out


## Mirror Pose (M = right to left, N = left to right): every attribute on the source side is copied to its twin part,
## the same definition and keys. Attributes on the other side that the source does not have stay. Returns attrs.
static func copy_side(attrs: Dictionary, from_side: String) -> Dictionary:
	for id in attrs.keys():
		var p := part_of(id)
		if p.ends_with(from_side):
			attrs[id_of(Body.twin(p), name_of(id))] = (attrs[id] as Dictionary).duplicate(true)
	return attrs


static func to_file(attrs: Dictionary) -> Dictionary:
	var out := {}
	for id in ids(attrs):
		var a: Dictionary = attrs[id]
		var ks := []
		for k in a.get("keys", []):
			ks.append({"t": float(k["t"]), "v": (k["v"] as Vector3).x})   # exact: a reload plays the same curve to the bit
		out[id] = {"min": float(a["min"]), "max": float(a["max"]), "default": float(a["default"]), "keys": ks}
	return out


## the file's attrs back to memory. Broken entries (min not below max, unknown part, bad name) are dropped, not guessed
static func from_file(d: Variant) -> Dictionary:
	var out := {}
	if not (d is Dictionary):
		return out
	for id in (d as Dictionary):
		var e: Variant = d[id]
		if not (e is Dictionary) or not (part_of(id) in Body.ORDER) or check_name(name_of(id)) != "":
			continue
		var mn := float(e.get("min", 0.0))
		var mx := float(e.get("max", 1.0))
		var df := float(e.get("default", mn))
		if check_range(mn, mx, df) != "":
			continue
		var a := {"min": mn, "max": mx, "default": df, "keys": []}
		out[id] = a
		var pk := {id: []}
		for k in e.get("keys", []):
			PartKeys.put(pk, id, float(k["t"]), Vector3(clampf(float(k["v"]), mn, mx), 0.0, 0.0))
		a["keys"] = pk[id]
	return out


## THE GLB EXTRAS (ROADMAP 82): every attribute on a node named after its part gets
##   extras.poser_attrs = {"<name>": {"min", "max", "default", "keys": [[t, v], ...]}}
## so an engine reads the value curve with no animation track. Rewrites the .glb's JSON chunk in place (the binary
## chunk is copied as it is). Returns {"err": OK or an error, "missing": parts that have no node in the file}. Nodes that
## no attribute names are not touched.
static func add_glb_extras(path: String, attrs: Dictionary) -> Dictionary:
	var out := {"err": ERR_FILE_CORRUPT, "missing": []}
	if attrs.is_empty():
		out["err"] = OK
		return out
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 20 or b.slice(0, 4).get_string_from_ascii() != "glTF":
		return out
	var jlen := b.decode_u32(12)
	if b.slice(16, 20).get_string_from_ascii() != "JSON":
		return out
	var json_txt := b.slice(20, 20 + jlen).get_string_from_utf8()
	var doc: Variant = JSON.parse_string(json_txt)
	if not doc is Dictionary:
		return out
	var by_part := {}
	for id in attrs:
		var p := part_of(id)
		if not by_part.has(p):
			by_part[p] = {}
		var a: Dictionary = attrs[id]
		var ks := []
		for k in a.get("keys", []):
			ks.append([float(k["t"]), (k["v"] as Vector3).x])
		by_part[p][name_of(id)] = {"min": float(a["min"]), "max": float(a["max"]), "default": float(a["default"]), "keys": ks}
	var found := {}
	var nodes: Array = (doc as Dictionary).get("nodes", [])
	for nd in nodes:
		var nm := String((nd as Dictionary).get("name", ""))
		if by_part.has(nm):
			(nd as Dictionary)["extras"] = {"poser_attrs": by_part[nm]}
			found[nm] = true
	for p in by_part:
		if not found.has(p):
			(out["missing"] as Array).append(p)
	var jb := JSON.stringify(doc, "", false).to_utf8_buffer()
	while jb.size() % 4 != 0:
		jb.append(0x20)   # the JSON chunk pads with spaces (glTF 2.0 section 3.6.1)
	var rest := b.slice(20 + jlen)
	var total := 12 + 8 + jb.size() + rest.size()
	var outb := PackedByteArray()
	outb.append_array("glTF".to_ascii_buffer())
	outb.append_array(_u32(2))
	outb.append_array(_u32(total))
	outb.append_array(_u32(jb.size()))
	outb.append_array("JSON".to_ascii_buffer())
	outb.append_array(jb)
	outb.append_array(rest)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		out["err"] = FileAccess.get_open_error()
		return out
	f.store_buffer(outb)
	f.close()
	out["err"] = OK
	return out


static func _u32(v: int) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(4)
	p.encode_u32(0, v)
	return p
