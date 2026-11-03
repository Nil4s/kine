## C17 MESH PRINT SAFETY (complaints #292, #358, #387). Three additions to the printing export; none changes an existing check or default.
##   1 INTERNAL SHELLS  a closed shell sitting inside another closed shell (what a slicer shows as a floating ring or a hidden inner wall)
##   2 REPAIR LIST      a repair that WRITES DOWN every change before it is made, works on a copy, and is one undo step. A shell that is a
##                      deliberate hollow (wound inward) is kept and said so. Nothing is deleted without a line in the list.
##   3 RELOAD CHECK    the written .stl / .3mf is read back from disk: shells, closed, manifold, internal shells, triangle count
## Bodies are the MeshExport kind: {"name", "v": PackedVector3Array (mm), "t": PackedInt32Array, "color"}.
class_name PrintSafety
extends RefCounted


## the connected shells of one indexed mesh: [{"tris": PackedInt32Array of triangle numbers, "verts": Dictionary}]
static func shells_of(b: Dictionary) -> Array:
	var t: PackedInt32Array = b["t"]
	var n := t.size() / 3
	var parent := {}
	for i in t:
		parent[i] = i
	for i in range(0, t.size(), 3):
		_union(parent, t[i], t[i + 1])
		_union(parent, t[i + 1], t[i + 2])
	var by := {}
	for i in n:
		var r := _find(parent, t[i * 3])
		if not by.has(r):
			by[r] = []
		(by[r] as Array).append(i)
	var out := []
	for r in by:
		out.append({"tris": PackedInt32Array(by[r])})
	return out


static func _find(p: Dictionary, a: int) -> int:
	while int(p[a]) != a:
		p[a] = p[int(p[a])]
		a = int(p[a])
	return a


static func _union(p: Dictionary, a: int, b: int) -> void:
	var ra := _find(p, a)
	var rb := _find(p, b)
	if ra != rb:
		p[ra] = rb


## the sub-mesh of one shell as its own indexed mesh (same vertex array, only its triangles)
static func sub(b: Dictionary, tris: PackedInt32Array) -> Dictionary:
	var t: PackedInt32Array = b["t"]
	var o := PackedInt32Array()
	for k in tris:
		o.append(t[k * 3])
		o.append(t[k * 3 + 1])
		o.append(t[k * 3 + 2])
	return {"v": b["v"], "t": o}


static func _box(b: Dictionary) -> AABB:
	var v: PackedVector3Array = b["v"]
	var t: PackedInt32Array = b["t"]
	var bb := AABB(v[t[0]], Vector3.ZERO)
	for i in t:
		bb = bb.expand(v[i])
	return bb


## does the ray from p along +x cross the mesh an odd number of times (p inside)? Moller-Trumbore, ray direction (1, 0, 0.0001...) slanted so it
## misses edges
static func inside(b: Dictionary, p: Vector3) -> bool:
	var v: PackedVector3Array = b["v"]
	var t: PackedInt32Array = b["t"]
	var d := Vector3(1.0, 0.000137, 0.000291)
	var hits := 0
	for i in range(0, t.size(), 3):
		var a := v[t[i]]
		var e1 := v[t[i + 1]] - a
		var e2 := v[t[i + 2]] - a
		var h := d.cross(e2)
		var det := e1.dot(h)
		if absf(det) < 1e-12:
			continue
		var f := 1.0 / det
		var s := p - a
		var u := f * s.dot(h)
		if u < 0.0 or u > 1.0:
			continue
		var q := s.cross(e1)
		var w := f * d.dot(q)
		if w < 0.0 or u + w > 1.0:
			continue
		if f * e2.dot(q) > 1e-9:
			hits += 1
	return hits % 2 == 1


## the shell picture of one body: {"shells": n, "list": [{"tris", "volume", "closed", "box"}], "internal": [{"inner": i, "outer": j, "cavity": bool}]}
## cavity = the inner shell winds inward (negative volume): a deliberate hollow, not a stray body
static func analyse_body(b: Dictionary) -> Dictionary:
	var sh := shells_of(b)
	var list := []
	for s in sh:
		var m := sub(b, s["tris"])
		list.append({"tris": (s["tris"] as PackedInt32Array).size(), "volume": MeshExport.signed_volume(m), "closed": bool(MeshExport.check(m)["closed"]), "box": _box(m), "mesh": m})
	var internal := []
	for i in list.size():
		for j in list.size():
			if i == j or not bool(list[i]["closed"]) or not bool(list[j]["closed"]):
				continue
			var bi: AABB = list[i]["box"]
			var bj: AABB = list[j]["box"]
			if not bj.grow(0.001).encloses(bi) or bi.size.length() >= bj.size.length():
				continue
			var mi: Dictionary = list[i]["mesh"]
			var vi: PackedVector3Array = mi["v"]
			var probe: Vector3 = vi[(mi["t"] as PackedInt32Array)[0]]
			# a vertex of the inner shell is never on the outer one; test the triangle's centre pulled slightly to be safe
			var ti: PackedInt32Array = mi["t"]
			probe = (vi[ti[0]] + vi[ti[1]] + vi[ti[2]]) / 3.0
			if inside(list[j]["mesh"], probe):
				internal.append({"inner": i, "outer": j, "cavity": float(list[i]["volume"]) < 0.0})
				break
	return {"shells": list.size(), "list": list, "internal": internal}


## the printing-safety lines for a part's bodies (each starts OK or WARN, like the other checklists)
static func lines(bodies: Array) -> Array:
	var out := []
	var shells := 0
	var stray := 0
	for bi in bodies.size():
		var a := analyse_body(bodies[bi])
		shells += int(a["shells"])
		for it in a["internal"]:
			if bool(it["cavity"]):
				out.append("OK    %s: shell %d is a hollow inside shell %d (wound inward): a deliberate cavity, kept" % [bodies[bi]["name"], int(it["inner"]) + 1, int(it["outer"]) + 1])
			else:
				stray += 1
				var l: Dictionary = a["list"][int(it["inner"])]
				out.append("WARN  %s: shell %d (%d triangles, %.1f mm3) is a closed solid INSIDE shell %d: a slicer shows it as a floating ring or a hidden inner wall. Open the repair list to see what removing it changes" % [bodies[bi]["name"], int(it["inner"]) + 1, int(l["tris"]), float(l["volume"]), int(it["outer"]) + 1])
	if stray == 0:
		out.insert(0, "OK    no closed shell sits inside another (%d shell%s)" % [shells, "" if shells == 1 else "s"])
	return out


## THE REPAIR: a plan that lists every change, applied to a COPY. {"changes": [text], "bodies": repaired copy, "before": the original bodies, "count": n}
## Only a stray inner solid is removed. A cavity, an open shell, anything not understood is left and listed under "kept".
static func repair(bodies: Array) -> Dictionary:
	var changes := []
	var fixed := []
	for bi in bodies.size():
		var b: Dictionary = bodies[bi]
		var a := analyse_body(b)
		var drop := {}
		for it in a["internal"]:
			var l: Dictionary = a["list"][int(it["inner"])]
			if bool(it["cavity"]):
				changes.append("KEPT    %s: shell %d is a deliberate hollow inside shell %d" % [b["name"], int(it["inner"]) + 1, int(it["outer"]) + 1])
			else:
				drop[int(it["inner"])] = true
				changes.append("REMOVE  %s: shell %d, %d triangles, %.1f mm3 (a closed solid inside shell %d). The outer wall stays" % [b["name"], int(it["inner"]) + 1, int(l["tris"]), float(l["volume"]), int(it["outer"]) + 1])
		for i in a["list"].size():
			if not bool(a["list"][i]["closed"]):
				changes.append("KEPT    %s: shell %d is open (not closed); repair does not touch it, press Fix it" % [b["name"], i + 1])
		var sh := shells_of(b)
		var t: PackedInt32Array = b["t"]
		var nt := PackedInt32Array()
		for si in sh.size():
			if drop.has(si):
				continue
			for k in (sh[si]["tris"] as PackedInt32Array):
				nt.append(t[k * 3])
				nt.append(t[k * 3 + 1])
				nt.append(t[k * 3 + 2])
		var c := b.duplicate()
		c["t"] = nt
		fixed.append(c)
	var removed := 0
	for c in changes:
		if String(c).begins_with("REMOVE"):
			removed += 1
	if removed == 0:
		changes.insert(0, "Nothing to repair: no stray inner shell was found")
	return {"changes": changes, "bodies": fixed, "before": bodies, "count": removed}


## one undo step: the bodies as they were before the repair
static func undo(rep: Dictionary) -> Array:
	return rep["before"]


## the repaired copy written beside the original as <name>_repaired.<fmt>; the original file and the part are not touched.
## Answers {"ok", "path", "reload": reload_check of the written copy, "changes"}
static func export_repaired(rec: Dictionary, fmt: String, dir: String) -> Dictionary:
	var bo := MeshExport.bodies_of(rec)
	if (bo["bodies"] as Array).is_empty():
		return {"ok": false, "path": "", "changes": [String(bo["why"])], "reload": {}}
	var rp := repair(bo["bodies"])
	var gdir := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(gdir)
	var name := String(rec.get("name", "Part"))
	var path := "%s/%s_repaired.%s" % [gdir, MeshExport.stem(name), fmt]
	var e := MeshExport.write_stl(path, rp["bodies"]) if fmt == "stl" else MeshExport.write_3mf(path, rp["bodies"], name)
	if e != OK:
		return {"ok": false, "path": path, "changes": rp["changes"], "reload": {}}
	return {"ok": true, "path": path, "changes": rp["changes"], "reload": reload_check(path)}


## the part's normal export, then the file read back: MeshExport.export_part's answer plus "reload" (see reload_check). The text is unchanged.
static func export_checked(rec: Dictionary, fmt: String, dir: String, budget := 0, quality := {}) -> Dictionary:
	var r := MeshExport.export_part(rec, fmt, dir, budget, quality)
	r["reload"] = reload_check(String(r["path"])) if bool(r["ok"]) else {}
	return r


## READ A WRITTEN FILE BACK: {"ok", "format", "objects", "shells", "tris", "open", "bad", "closed", "internal" (stray), "lines"}
static func reload_check(path: String) -> Dictionary:
	var bodies := read_file_bodies(path)
	if bodies.is_empty():
		return {"ok": false, "format": path.get_extension(), "objects": 0, "shells": 0, "tris": 0, "open": 0, "bad": 0, "closed": false, "internal": 0,
			"lines": ["WARN  the file could not be read back: " + path.get_file()]}
	var open := 0
	var bad := 0
	var tris := 0
	var shells := 0
	var stray := 0
	for b in bodies:
		var c := MeshExport.check(b)
		open += int(c["open"])
		bad += int(c["bad"])
		tris += int(c["tris"])
		var a := analyse_body(b)
		shells += int(a["shells"])
		for it in a["internal"]:
			if not bool(it["cavity"]):
				stray += 1
	var closed := open == 0 and bad == 0
	var ln := ["%s    read back %s: %d triangles, %d shell%s in %d object%s" % ["OK" if closed and stray == 0 else "WARN", path.get_file(), tris, shells, "" if shells == 1 else "s", bodies.size(), "" if bodies.size() == 1 else "s"]]
	ln.append("%s    %s" % ["OK  " if closed else "WARN", "closed and manifold: every edge joins exactly two faces" if closed else "%d open edge%s, %d badly joined" % [open, "" if open == 1 else "s", bad]])
	if stray > 0:
		ln.append("WARN  %d stray inner shell%s: the repair list shows them" % [stray, "" if stray == 1 else "s"])
	return {"ok": true, "format": path.get_extension(), "objects": bodies.size(), "shells": shells, "tris": tris, "open": open, "bad": bad, "closed": closed, "internal": stray, "lines": ln}


## the bodies of a .stl (binary) or .3mf on disk, welded the way the writers weld
static func read_file_bodies(path: String) -> Array:
	var ext := path.get_extension().to_lower()
	if ext == "stl":
		var b := FileAccess.get_file_as_bytes(path)
		if b.size() < 84:
			return []
		var n := b.decode_u32(80)
		if b.size() != 84 + 50 * n or n == 0:
			return []
		var soup := PackedVector3Array()
		for i in n:
			for k in 3:
				var q := 84 + 50 * i + 12 + 12 * k
				soup.append(Vector3(b.decode_float(q), b.decode_float(q + 4), b.decode_float(q + 8)))
		return [_weld_mm(soup, "stl")]
	if ext == "3mf":
		var z := ZIPReader.new()
		if z.open(path) != OK:
			return []
		var model := z.read_file("3D/3dmodel.model")
		z.close()
		var xp := XMLParser.new()
		xp.open_buffer(model)
		var out := []
		var v := PackedVector3Array()
		var t := PackedInt32Array()
		var inobj := false
		var nm := ""
		while xp.read() != ERR_FILE_EOF:
			var ty := xp.get_node_type()
			if ty == XMLParser.NODE_ELEMENT:
				match xp.get_node_name():
					"object":
						inobj = true
						v = PackedVector3Array()
						t = PackedInt32Array()
						nm = xp.get_named_attribute_value_safe("name")
					"vertex":
						v.append(Vector3(float(xp.get_named_attribute_value_safe("x")), float(xp.get_named_attribute_value_safe("y")), float(xp.get_named_attribute_value_safe("z"))))
					"triangle":
						t.append(int(xp.get_named_attribute_value_safe("v1")))
						t.append(int(xp.get_named_attribute_value_safe("v2")))
						t.append(int(xp.get_named_attribute_value_safe("v3")))
			elif ty == XMLParser.NODE_ELEMENT_END and xp.get_node_name() == "object" and inobj:
				inobj = false
				out.append({"name": nm, "v": v, "t": t, "color": null})
		return out
	return []


## STL corners (mm) -> indexed mesh, vertices equal to 1/1000 mm joined
static func _weld_mm(soup: PackedVector3Array, nm: String) -> Dictionary:
	var verts := PackedVector3Array()
	var tris := PackedInt32Array()
	var seen := {}
	for p in soup:
		var key := Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))
		if not seen.has(key):
			seen[key] = verts.size()
			verts.append(p)
		tris.append(int(seen[key]))
	return {"name": nm, "v": verts, "t": tris, "color": null}


## the dialog's row: a button that lists the safety lines, one that shows the repair list and one that saves the repaired copy. Hidden until 3D printing.
static func build_row(ex) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "export_safety_box"
	box.visible = false
	var row := HBoxContainer.new()
	var b1 := Button.new()
	b1.name = "btn_safety_check"
	b1.text = "Print safety check"
	b1.tooltip_text = "Looks for a closed shell inside another (a floating ring in the slicer). Nothing changes"
	var b2 := Button.new()
	b2.name = "btn_safety_repair"
	b2.text = "Repair list"
	b2.tooltip_text = "Lists every change a repair would make. Saves a _repaired copy beside the export; the part and the first file are not touched"
	var b3 := Button.new()
	b3.name = "btn_safety_undo"
	b3.text = "Undo repair"
	b3.disabled = true
	row.add_child(b1)
	row.add_child(b2)
	row.add_child(b3)
	box.add_child(row)
	var say := Label.new()
	say.name = "export_safety_text"
	say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	say.custom_minimum_size = Vector2(600, 0)
	box.add_child(say)
	b1.pressed.connect(func():
		var bo := MeshExport.bodies_of(ex.m.S.part)
		say.text = "\n".join(lines(bo["bodies"])) if not (bo["bodies"] as Array).is_empty() else String(bo["why"]))
	b2.pressed.connect(func():
		var fmt := "stl" if ex.ui_format.selected == 1 else "3mf"
		var r := export_repaired(ex.m.S.part, fmt, "res://exports")
		say.text = "Repair list\n" + "\n".join(r["changes"]) + ("\nSaved " + String(r["path"]).get_file() + ". " + "\n".join((r["reload"] as Dictionary).get("lines", [])) if bool(r["ok"]) else "")
		box.set_meta("repaired_path", String(r["path"]) if bool(r["ok"]) else "")
		b3.disabled = not bool(r["ok"]))
	b3.pressed.connect(func():
		var p := String(box.get_meta("repaired_path", ""))
		if p != "" and FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
		say.text = "Repair undone: the repaired copy was removed. The part and the first file were never changed."
		b3.disabled = true)
	return box
