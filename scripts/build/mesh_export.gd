## STL AND 3MF EXPORT of a built Part (3D printing). Reads the kernel's solids of the part record (Part.replay keep), tessellates each body
## fine (0.1 mm), welds the vertices, checks the shape is closed, and writes:
##   .stl  binary STL: an 80 byte header ("Kine ..."), a triangle count, then 50 bytes a triangle. STL has no units: the numbers are millimetres.
##   .3mf  a 3MF package (ZIPPacker): [Content_Types].xml, _rels/.rels, 3D/3dmodel.model with unit="millimeter", indexed triangles, one <object> per
##         separate body, and a <basematerials> colour for a body the maker painted.
## Both are Z up (the slicers' way): the part's floor (Kine's Y up) becomes the bed, z = 0. Dimensions are the part's own millimetres.
## The writers take bodies = [{"name", "v": PackedVector3Array (mm, welded), "t": PackedInt32Array (3 per triangle), "color": Color or null}].
class_name MeshExport
extends RefCounted

const KCad := preload("res://scripts/kcad.gd")
const PartInstances := preload("res://scripts/build/part_instances.gd")   # s261
const DEFLECT_M := 0.0001   # tessellation: at most 0.1 mm off the true surface
const ANGLE := 0.2
const WELD := 1000.0   # vertices closer than 1/1000 mm are one vertex


## Kine (x right, y up, z toward the viewer; metres) -> printer (x, y, z up; mm). A turn, so the winding stays outward.
static func to_print(p: Vector3) -> Vector3:
	return Vector3(p.x, -p.z, p.y) * 1000.0


## the bodies of a part record, ready to write: {"bodies": [...], "why": ""}; why is the words to say when there is nothing to write
static func bodies_of(rec: Dictionary, quality := {}) -> Dictionary:
	if rec.is_empty() or not Part.available():
		return {"bodies": [], "why": "Nothing to export: " + ("make a part first" if Part.available() else Part.why_not())}
	var res := Part.replay(rec, -1, {"keep": true})
	var ids: Array = res.get("ids", [])
	var looks: Array = res.get("body_looks", [])
	var names: Array = res.get("body_names", [])
	var out := []
	var base := String(rec.get("name", "Part"))
	var defl := DEFLECT_M if quality.is_empty() else float(quality["defl_mm"]) / 1000.0   # W05: the chosen mesh quality (Normal = the old numbers)
	var ang := ANGLE if quality.is_empty() else float(quality["angle"])
	for i in ids.size():
		var soup := PackedVector3Array()
		var tm := KCad.tessellate(int(ids[i]), defl, ang)
		if tm != null:
			for s in tm.get_surface_count():
				var arr := tm.surface_get_arrays(s)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var idx = arr[Mesh.ARRAY_INDEX]
				if idx == null:
					soup.append_array(vs)
				else:
					for k in (idx as PackedInt32Array):
						soup.append(vs[k])
		KCad.release(int(ids[i]))
		var b := weld(soup)
		b["name"] = base if ids.size() == 1 else "%s %d" % [base, i + 1]
		if i < names.size() and String(names[i]) != "Body%d" % (i + 1):   # s212: a body the maker named is called that in the file
			b["name"] = String(names[i])
		var look: Dictionary = looks[i] if i < looks.size() else {}
		# a colour only for a body the maker painted (a look named Default is the palette's guess, not a choice)
		b["color"] = look["c"] if not look.is_empty() and String(look.get("preset", "Default")) != "Default" else null
		out.append(b)
	PartInstances.bake_into(out, res.get("instances", []), base)   # s261: instanced copies become real triangles
	if out.is_empty() or int(out.map(func(b): return (b["t"] as PackedInt32Array).size()).max()) == 0:
		return {"bodies": [], "why": "Nothing to export: this part has no solid yet"}
	return {"bodies": out, "why": ""}


## a triangle soup (Kine metres, 3 vertices a triangle) -> {"v": mm Z-up welded vertices, "t": indices}; triangles that collapse are dropped;
## the winding is turned if needed so the solid's signed volume is positive (outward normals)
static func weld(soup: PackedVector3Array) -> Dictionary:
	var verts := PackedVector3Array()
	var tris := PackedInt32Array()
	var seen := {}
	for i in range(0, soup.size() - 2, 3):
		var ix := [0, 0, 0]
		for k in 3:
			var p := to_print(soup[i + k])
			var key := Vector3i(roundi(p.x * WELD), roundi(p.y * WELD), roundi(p.z * WELD))
			if not seen.has(key):
				seen[key] = verts.size()
				verts.append(p)
			ix[k] = int(seen[key])
		if ix[0] == ix[1] or ix[1] == ix[2] or ix[0] == ix[2]:
			continue
		tris.append_array(PackedInt32Array(ix))
	var out := {"v": verts, "t": tris}
	if signed_volume(out) < 0.0:
		for i in range(0, tris.size(), 3):
			var t := tris[i + 1]
			tris[i + 1] = tris[i + 2]
			tris[i + 2] = t
		out["t"] = tris
	return out


## the signed volume (mm3) of an indexed mesh: positive when the triangles wind counter-clockwise seen from outside
static func signed_volume(b: Dictionary) -> float:
	var v: PackedVector3Array = b["v"]
	var t: PackedInt32Array = b["t"]
	var door = MeshCheckDoor.door()
	if door != null:
		return door.signed_volume(v, t)
	var s := 0.0
	for i in range(0, t.size(), 3):
		s += v[t[i]].dot(v[t[i + 1]].cross(v[t[i + 2]]))
	return s / 6.0


## the printability of one indexed mesh: {"tris", "open" (edges with one triangle), "bad" (edges with more than two triangles, or two the same way
## round), "closed" (open == 0 and bad == 0)}
static func check(b: Dictionary) -> Dictionary:
	var t: PackedInt32Array = b["t"]
	var door = MeshCheckDoor.door()
	if door != null:
		var nr: Dictionary = door.edge_check(t)
		var no := int(nr["open"])
		var nb := int(nr["bad"])
		return {"tris": t.size() / 3, "open": no, "bad": nb, "closed": no == 0 and nb == 0}
	var cnt := {}
	var dirs := {}
	for i in range(0, t.size(), 3):
		for k in 3:
			var a := t[i + k]
			var c := t[i + (k + 1) % 3]
			var key := (mini(a, c) << 32) | maxi(a, c)
			cnt[key] = int(cnt.get(key, 0)) + 1
			var d := 1 if a < c else -1
			dirs[key] = int(dirs.get(key, 0)) + d
	var open := 0
	var bad := 0
	for key in cnt:
		var n: int = cnt[key]
		if n == 1:
			open += 1
		elif n > 2 or int(dirs[key]) != 0:
			bad += 1
	return {"tris": t.size() / 3, "open": open, "bad": bad, "closed": open == 0 and bad == 0}


## the whole part's check, plain words: {"lines": ["OK    ..." / "WARN  ..."], "open": n, "bad": n, "tris": n, "size": Vector3 (mm), "closed": bool}
static func report(bodies: Array) -> Dictionary:
	var open := 0
	var bad := 0
	var tris := 0
	var box := AABB()
	var first := true
	for b in bodies:
		var c := check(b)
		open += int(c["open"])
		bad += int(c["bad"])
		tris += int(c["tris"])
		var bdoor = MeshCheckDoor.door()
		if bdoor != null:
			var bb: PackedVector3Array = bdoor.bounds(b["v"])
			for p in bb:
				if first:
					box = AABB(p, Vector3.ZERO)
					first = false
				else:
					box = box.expand(p)
			continue
		for p in (b["v"] as PackedVector3Array):
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	var lines := []
	if open == 0 and bad == 0:
		lines.append("OK    closed: every edge joins exactly two faces, so a slicer reads it as a solid (%d triangles)" % tris)
	else:
		if open > 0:
			lines.append("WARN  This part has %d open edge%s: press Fix it first. You can still export it" % [open, "" if open == 1 else "s"])
		if bad > 0:
			lines.append("WARN  This part has %d edge%s where faces meet badly (more than two faces, or turned the wrong way): press Fix it first. You can still export it" % [bad, "" if bad == 1 else "s"])
	lines.append("OK    size: %.1f x %.1f x %.1f mm (width x depth x height); the files hold millimetres" % [box.size.x, box.size.y, box.size.z])
	lines.append("OK    %d separate piece%s; the STL joins them in one file, the 3MF keeps each as its own object" % [bodies.size(), "" if bodies.size() == 1 else "s"])
	return {"lines": lines, "open": open, "bad": bad, "tris": tris, "size": box.size, "closed": open == 0 and bad == 0}


## n03: the per-triangle packing in C++ (KineMeshOpsNative); KINE_NO_NATIVE=1 forces the GDScript loops
static func native_on() -> bool:
	return MeshOpsDoor.on()


## binary STL bytes of every body (all in one mesh). Normals are computed from the winding (unit, outward).
static func stl_bytes(bodies: Array) -> PackedByteArray:
	var n := 0
	for b in bodies:
		n += (b["t"] as PackedInt32Array).size() / 3
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	var head := "Kine STL (binary), millimetres, Z up".to_ascii_buffer()
	head.resize(80)   # padded with zeros; an STL header must not begin with "solid" (some readers then guess ASCII)
	buf.put_data(head)
	buf.put_u32(n)
	var nat := native_on()
	for b in bodies:
		var v: PackedVector3Array = b["v"]
		var t: PackedInt32Array = b["t"]
		if nat:
			buf.put_data(MeshOpsDoor.door().stl_records(v, t))
			continue
		for i in range(0, t.size(), 3):
			var p0 := v[t[i]]
			var p1 := v[t[i + 1]]
			var p2 := v[t[i + 2]]
			var nn := (p1 - p0).cross(p2 - p0).normalized()
			for c in [nn.x, nn.y, nn.z, p0.x, p0.y, p0.z, p1.x, p1.y, p1.z, p2.x, p2.y, p2.z]:
				buf.put_float(c)
			buf.put_u16(0)
	return buf.data_array


static func _hex(c: Color) -> String:
	return "#%02X%02X%02X" % [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)]


static func _xml(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


## the 3D/3dmodel.model text. Resource ids: 1 = basematerials (when any body is painted), objects from 2.
static func model_xml(bodies: Array, title: String) -> String:
	var mats := []   # the distinct painted colours, in order
	for b in bodies:
		if b["color"] != null and not mats.has(_hex(b["color"])):
			mats.append(_hex(b["color"]))
	var x := PackedStringArray()
	x.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
	x.append("<model unit=\"millimeter\" xml:lang=\"en-US\" xmlns=\"http://schemas.microsoft.com/3dmanufacturing/core/2015/02\">")
	x.append("<metadata name=\"Title\">%s</metadata>" % _xml(title))
	x.append("<metadata name=\"Application\">Kine</metadata>")
	x.append("<resources>")
	if not mats.is_empty():
		x.append("<basematerials id=\"1\">")
		for i in mats.size():
			x.append("<base name=\"Colour %d\" displaycolor=\"%s\"/>" % [i + 1, mats[i]])
		x.append("</basematerials>")
	for oi in bodies.size():
		var b: Dictionary = bodies[oi]
		var pid := ""
		if b["color"] != null:
			pid = " pid=\"1\" pindex=\"%d\"" % mats.find(_hex(b["color"]))
		x.append("<object id=\"%d\" name=\"%s\" type=\"model\"%s>" % [oi + 2, _xml(String(b["name"])), pid])
		x.append("<mesh>")
		x.append("<vertices>")
		var t: PackedInt32Array = b["t"]
		if native_on():
			if not (b["v"] as PackedVector3Array).is_empty():
				x.append(MeshOpsDoor.door().xml_vertices(b["v"]))
		else:
			for p in (b["v"] as PackedVector3Array):
				x.append("<vertex x=\"%.6f\" y=\"%.6f\" z=\"%.6f\"/>" % [p.x, p.y, p.z])
		x.append("</vertices>")
		x.append("<triangles>")
		if native_on():
			if t.size() >= 3:
				x.append(MeshOpsDoor.door().xml_triangles(t))
		else:
			for i in range(0, t.size(), 3):
				x.append("<triangle v1=\"%d\" v2=\"%d\" v3=\"%d\"/>" % [t[i], t[i + 1], t[i + 2]])
		x.append("</triangles>")
		x.append("</mesh>")
		x.append("</object>")
	x.append("</resources>")
	x.append("<build>")
	for oi in bodies.size():
		x.append("<item objectid=\"%d\"/>" % (oi + 2))
	x.append("</build>")
	x.append("</model>")
	return "\n".join(x)


const CONTENT_TYPES := "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">\n<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>\n<Default Extension=\"model\" ContentType=\"application/vnd.ms-package.3dmanufacturing-3dmodel+xml\"/>\n</Types>"
const RELS := "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\n<Relationship Target=\"/3D/3dmodel.model\" Id=\"rel0\" Type=\"http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel\"/>\n</Relationships>"


## writes the .3mf package; OK or an Error
static func write_3mf(path: String, bodies: Array, title: String) -> int:
	var z := ZIPPacker.new()
	var e := z.open(path)
	if e != OK:
		return e
	for en in [["[Content_Types].xml", CONTENT_TYPES], ["_rels/.rels", RELS], ["3D/3dmodel.model", model_xml(bodies, title)]]:
		z.start_file(en[0])
		z.write_file(String(en[1]).to_utf8_buffer())
		z.close_file()
	z.close()
	return OK


static func write_stl(path: String, bodies: Array) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(stl_bytes(bodies))
	f.close()
	return OK


## a file name from a part name
static func stem(name: String) -> String:
	var s := name.strip_edges()
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		s = s.replace(ch, "_")
	s = s.replace(" ", "_")
	return s if s != "" else "part"


## the Export dialog's road: the part record -> dir/<name>.stl or .3mf. fmt "stl" | "3mf". Answers
## {"ok", "path", "why", "report": the check (see report), "text": one plain sentence to say}
static func export_part(rec: Dictionary, fmt: String, dir: String, budget := 0, quality := {}) -> Dictionary:
	var bo := bodies_of(rec, quality)
	if (bo["bodies"] as Array).is_empty():
		return {"ok": false, "path": "", "why": String(bo["why"]), "report": {}, "text": "NOT DONE: " + String(bo["why"])}
	var bodies: Array = ExportBudget.apply_bodies(bo["bodies"], budget)   # plan 157: a triangle budget writes a decimated copy
	var rep := report(bodies)
	var gdir := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(gdir)
	var name := String(rec.get("name", "Part"))
	var path := "%s/%s.%s" % [gdir, stem(name), fmt]
	var e := write_stl(path, bodies) if fmt == "stl" else write_3mf(path, bodies, name)
	if e != OK:
		return {"ok": false, "path": path, "why": error_string(e), "report": rep, "text": "NOT DONE: the file could not be written (%s). Check that the folder is writable, then export again" % error_string(e)}
	var msg := "exported %s: %d triangles, %.1f x %.1f x %.1f mm" % [path.get_file(), int(rep["tris"]), rep["size"].x, rep["size"].y, rep["size"].z]
	if budget > 0:
		msg += ExportBudget.words()
	if not bool(rep["closed"]):
		msg += ". " + String((rep["lines"] as Array)[0]).substr(6)
	return {"ok": true, "path": path, "why": "", "report": rep, "text": msg}


## the dialog's checklist for the part on screen (lines start OK or WARN)
static func check_lines(rec: Dictionary, quality := {}, budget := 0) -> Array:
	var bo := bodies_of(rec, quality)
	if (bo["bodies"] as Array).is_empty():
		return ["WARN  " + String(bo["why"])]
	var lines: Array = (report(ExportBudget.apply_bodies(bo["bodies"], budget) if budget > 0 else bo["bodies"])["lines"] as Array).duplicate()
	lines.append_array(PrintCheck.lines_of(rec, bo["bodies"]))   # Friday plan 112: Ready to print? (thin walls, overhangs, floating pieces)
	for row in Part.thread_look_rows(rec, AABB()):   # s031: a threaded hole says how to make the thread
		lines.append("OK  " + Part.thread_look_words(int(row["M"]), float(row["pitch"])))
	return lines


## printer (x, y, z up; mm) -> Kine (x right, y up, z toward the viewer; metres): the way back from to_print (Friday plan 114, Split to fit)
static func to_print_inv(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, -p.y) / 1000.0
