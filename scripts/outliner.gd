## OUTLINER MODEL (lane L36, GAP_AUDIT_1106 UI/UX item 3). The scene's objects (the body, props, the three stage lights, the shot
## cameras, the cape, the soft-body regions) by id ("prop:3", "light:key", "cam:0", "cloth:cape", "soft:belly", "body:hero"), and a
## parent / hide / lock record on the Scene (Scene.outl, in the file as "outliner" only when it holds something):
##   {"parent": {id: parent id}, "local": {id: Transform3D, relative to the parent}, "hide": {id: true}, "lock": {id: true},
##    "xf": {id: Transform3D, the world place of an object that is not a prop}}
## A prop's world transform is its own S.props[i]["xf"]. A reparent KEEPS the world transform (local = inverse(parent world) x world);
## moving a parent carries its descendants (child world = parent world x local). Pure functions on a Scene; main.gd wraps them in
## one undo step each (_outl_reparent, _outl_hide, _outl_lock).
class_name Outliner
extends RefCounted

const KINDS := ["body", "light", "cam", "cloth", "soft", "prop"]
const KIND_NAMES := {"body": "Bodies", "light": "Lights", "cam": "Cameras", "cloth": "Cloth", "soft": "Soft", "prop": "Props"}
const LIGHTS := ["key", "fill", "rim"]


static func _d(S: Scene, k: String) -> Dictionary:
	if not S.outl.has(k):
		S.outl[k] = {}
	return S.outl[k]


static func prop_name(S: Scene, i: int) -> String:
	var k := String(S.props[i]["kind"])
	if k.begins_with("part:"):
		return PartScene.name_of(k)
	return k.trim_prefix("piece:").replace("_", " ")


## every object: [{"id", "kind", "name"}] in a fixed order
static func objects(S: Scene) -> Array:
	var out := [{"id": "body:hero", "kind": "body", "name": "body"}]
	for l in LIGHTS:
		out.append({"id": "light:" + l, "kind": "light", "name": l + " light"})
	for i in S.shots.size():
		var nm := String((S.shots[i] as Dictionary).get("name", ""))
		out.append({"id": "cam:%d" % i, "kind": "cam", "name": nm if nm != "" else "camera %d" % (i + 1)})
	if not S.cape.is_empty():
		out.append({"id": "cloth:cape", "kind": "cloth", "name": "cape"})
	for r in S.soft.get("regions", []):
		out.append({"id": "soft:" + String(r), "kind": "soft", "name": "soft " + String(r).replace("_", " ")})
	for i in S.props.size():
		out.append({"id": "prop:%d" % i, "kind": "prop", "name": prop_name(S, i)})
	return out


static func has(S: Scene, id: String) -> bool:
	for o in objects(S):
		if o["id"] == id:
			return true
	return false


static func kind_of(id: String) -> String:
	return id.get_slice(":", 0)


static func prop_index(id: String) -> int:
	return int(id.get_slice(":", 1)) if id.begins_with("prop:") else -1


## the ids a filter (kinds that are on) and a search (any case, a part of the name) leave
static func rows(S: Scene, kinds: Array, query: String) -> Array:
	var q := query.strip_edges()
	var out := []
	for o in objects(S):
		if o["kind"] in kinds and (q == "" or String(o["name"]).containsn(q)):
			out.append(o["id"])
	return out


static func parent_of(S: Scene, id: String) -> String:
	return String(S.outl.get("parent", {}).get(id, ""))


static func children_of(S: Scene, id: String) -> Array:
	var out := []
	for c in S.outl.get("parent", {}):
		if S.outl["parent"][c] == id:
			out.append(c)
	return out


static func is_inside(S: Scene, id: String, anc: String) -> bool:
	var p := parent_of(S, id)
	var n := 0
	while p != "" and n < 10000:
		if p == anc:
			return true
		p = parent_of(S, p)
		n += 1
	return false


static func world(S: Scene, id: String) -> Transform3D:
	var i := prop_index(id)
	if i >= 0:
		return S.props[i]["xf"] if i < S.props.size() else Transform3D.IDENTITY
	return S.outl.get("xf", {}).get(id, Transform3D.IDENTITY)


static func _set_raw(S: Scene, id: String, xf: Transform3D) -> void:
	var i := prop_index(id)
	if i >= 0:
		if i < S.props.size():
			S.props[i]["xf"] = xf
	else:
		_d(S, "xf")[id] = xf


static func local(S: Scene, id: String) -> Transform3D:
	if parent_of(S, id) == "":
		return world(S, id)
	return S.outl.get("local", {}).get(id, Transform3D.IDENTITY)


## the world place from the parent's world and the stored local one (a root: its own world)
static func world_from_local(S: Scene, id: String) -> Transform3D:
	var p := parent_of(S, id)
	if p == "":
		return world(S, id)
	return world(S, p) * local(S, id)


static func _name(S: Scene, id: String) -> String:
	for o in objects(S):
		if o["id"] == id:
			return String(o["name"])
	return id


## "" when child can go under parent (parent "" = the top level), else why not
static func can_reparent(S: Scene, child: String, parent: String) -> String:
	if not has(S, child):
		return "there is no object %s" % child
	if parent != "" and not has(S, parent):
		return "there is no object %s to drop it on" % parent
	var cn := _name(S, child)
	if parent == child:
		return "%s cannot be its own parent: it was dropped on itself" % cn
	if parent != "" and is_inside(S, parent, child):
		return "%s cannot go under %s: that one is inside it (a parent cannot sit inside its own child)" % [cn, _name(S, parent)]
	if parent_of(S, child) == parent:
		return "%s is already %s" % [cn, ("under " + _name(S, parent)) if parent != "" else "at the top level"]
	return ""


## reparent keeping the world transform; "" or why not (nothing changed then)
static func reparent(S: Scene, child: String, parent: String) -> String:
	var why := can_reparent(S, child, parent)
	if why != "":
		return why
	var w := world(S, child)
	if parent == "":
		_d(S, "parent").erase(child)
		_d(S, "local").erase(child)
	else:
		_d(S, "parent")[child] = parent
		_d(S, "local")[child] = world(S, parent).affine_inverse() * w
	_trim(S)
	return ""


static func cascade(S: Scene, id: String) -> void:
	for c in children_of(S, id):
		_set_raw(S, c, world(S, id) * local(S, c))
		cascade(S, c)


## the object's world place set (refused when it is locked); its descendants come with it
static func set_world(S: Scene, id: String, xf: Transform3D) -> String:
	if locked(S, id):
		return "%s is locked: unlock it first" % _name(S, id)
	_set_raw(S, id, xf)
	moved(S, id)
	return ""


## the object was moved by something else (a drag): its local place is read again, its descendants follow
static func moved(S: Scene, id: String) -> void:
	var p := parent_of(S, id)
	if p != "":
		_d(S, "local")[id] = world(S, p).affine_inverse() * world(S, id)
	cascade(S, id)


static func hidden(S: Scene, id: String) -> bool:
	if S.outl.get("hide", {}).has(id):
		return true
	var p := parent_of(S, id)
	var n := 0
	while p != "" and n < 10000:
		if S.outl.get("hide", {}).has(p):
			return true
		p = parent_of(S, p)
		n += 1
	return false


static func locked(S: Scene, id: String) -> bool:
	return S.outl.get("lock", {}).has(id)


static func set_hidden(S: Scene, id: String, on: bool) -> void:
	if on:
		_d(S, "hide")[id] = true
	else:
		_d(S, "hide").erase(id)
	_trim(S)


static func set_locked(S: Scene, id: String, on: bool) -> void:
	if on:
		_d(S, "lock")[id] = true
	else:
		_d(S, "lock").erase(id)
	_trim(S)


static func _trim(S: Scene) -> void:
	for k in S.outl.keys():
		if (S.outl[k] as Dictionary).is_empty():
			S.outl.erase(k)


## prop i was deleted: its record goes, the higher props are renumbered, its children become top-level (worlds are stored, so they stay)
static func prop_removed(S: Scene, i: int) -> void:
	if S.outl.is_empty():
		return
	var fix := func(id: String) -> String:
		var j := prop_index(id)
		if j == i:
			return ""
		return "prop:%d" % (j - 1) if j > i else id
	var out := {}
	for k in S.outl:
		var d: Dictionary = S.outl[k]
		var nd := {}
		for id in d:
			var nid: String = fix.call(id)
			if nid == "":
				continue
			var v = d[id]
			if k == "parent":
				v = fix.call(String(v))
				if v == "":
					continue
			nd[nid] = v
		out[k] = nd
	S.outl = out
	for id in S.outl.get("local", {}).keys():
		if not S.outl.get("parent", {}).has(id):
			S.outl["local"].erase(id)
	_trim(S)


## a number that changes when anything the outliner owns, or any prop place, changes
static func state_hash(S: Scene) -> int:
	return hash(var_to_str([S.props.map(func(p): return p["xf"]), S.outl]))


static func _x(t: Transform3D) -> Array:
	var b := t.basis
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, t.origin.x, t.origin.y, t.origin.z]


static func _t(a: Array) -> Transform3D:
	var f: Array = a.map(func(v): return float(v))
	return Transform3D(Basis(Vector3(f[0], f[1], f[2]), Vector3(f[3], f[4], f[5]), Vector3(f[6], f[7], f[8])), Vector3(f[9], f[10], f[11]))


static func to_file(S: Scene) -> Dictionary:
	var out := {}
	if not S.outl.get("parent", {}).is_empty():
		out["parent"] = S.outl["parent"].duplicate()
		out["local"] = {}
		for id in S.outl["parent"]:
			out["local"][id] = _x(local(S, id))
	for k in ["hide", "lock"]:
		if not S.outl.get(k, {}).is_empty():
			out[k] = S.outl[k].keys()
	if not S.outl.get("xf", {}).is_empty():
		out["xf"] = {}
		for id in S.outl["xf"]:
			out["xf"][id] = _x(S.outl["xf"][id])
	return out


static func from_file(d: Variant) -> Dictionary:
	var o := {}
	if not (d is Dictionary):
		return o
	if d.get("parent") is Dictionary and d.get("local") is Dictionary:
		o["parent"] = {}
		o["local"] = {}
		for id in d["parent"]:
			if d["local"].get(id) is Array and (d["local"][id] as Array).size() == 12:
				o["parent"][String(id)] = String(d["parent"][id])
				o["local"][String(id)] = _t(d["local"][id])
	for k in ["hide", "lock"]:
		if d.get(k) is Array and not (d[k] as Array).is_empty():
			o[k] = {}
			for id in d[k]:
				o[k][String(id)] = true
	if d.get("xf") is Dictionary:
		o["xf"] = {}
		for id in d["xf"]:
			if d["xf"][id] is Array and (d["xf"][id] as Array).size() == 12:
				o["xf"][String(id)] = _t(d["xf"][id])
	for k in o.keys():
		if (o[k] as Dictionary).is_empty():
			o.erase(k)
	return o
