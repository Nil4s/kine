class_name FbxMaterial
extends RefCounted
## FbxMaterial (C39, complaint M #4): the body's and each prop's material written into the FBX as Material objects (DiffuseColor =
## the base colour) and, for a prop with a photo material, a Texture object (the albedo map's file path) wired to DiffuseColor.
## Opt-in: FbxExport.write(..., mats) with [{"name", "color": Color, "tex": "path or empty", "solids", "xf", "scale"}]; [] writes nothing new (the old file).
## The skeleton has no mesh, and Blender / Unity only create a material that a mesh uses, so each material rides on a Mesh Model: a prop's is the
## prop's own solids (boxes, at the prop's place and size); the body's is a 1 cm swatch cube at the origin named Body_material (the body mesh is
## not in the file). The text goes into the finished ASCII tree, so the binary writer takes it too.
const ID0 := 1300000000
const FACES := [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]


## the materials of a scene: the body's, then one per prop (Props colour; a photo material adds its albedo path)
static func of_scene(S, body: Color) -> Array:
	var out := [{"name": "Body", "color": body, "tex": "", "solids": [[Vector3.ZERO, Vector3.ONE * 0.01]], "xf": Transform3D.IDENTITY, "scale": 1.0}]
	if S == null:
		return out
	for i in S.props.size():
		var p: Dictionary = S.props[i]
		var nm := "Prop_%s_%d" % [String(p.get("kind", "prop")), i]
		var tex := ""
		if p.has("mat"):
			var f := "user://materials/%s/albedo.png" % PhotoMaterial.clean_name(String(p["mat"]))
			if FileAccess.file_exists(f):
				tex = ProjectSettings.globalize_path(f)
		out.append({"name": nm, "color": Props.COLOURS[Props.colour_of(p)], "tex": tex, "solids": Props.kind_of(p["kind"]).get("solids", []),
			"xf": p["xf"], "scale": Props.scale_of(p)})
	return out


static func _bump(text: String, kind: String, by: int) -> String:
	var rx := RegEx.new()
	rx.compile("(ObjectType: \"" + kind + "\" [{]\n\t\tCount: )([0-9]+)")
	var m := rx.search(text)
	if m == null:
		return text
	return text.substr(0, m.get_start(2)) + str(int(m.get_string(2)) + by) + text.substr(m.get_end(2))


## text = the finished ASCII FBX; returns it with the materials added. mats empty -> text unchanged.
static func inject(text: String, mats: Array) -> String:
	if mats.is_empty():
		return text
	var null_m := RegEx.create_from_string("\tModel: ([0-9]+), \"Model::[^\"]*\", \"Null\"").search(text)
	var parent := int(null_m.get_string(1)) if null_m != null else 0
	var rot := Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO) if FbxExport.up_z else Transform3D.IDENTITY
	var objs := PackedStringArray()
	var conns := PackedStringArray()
	var ntex := 0
	var id := ID0
	for m in mats:
		id += 1
		var mid := id
		id += 1
		var mdl := id
		id += 1
		var geo := id
		var c: Color = m["color"]
		var nm := FbxExport._esc(String(m["name"]))
		var col := "%s,%s,%s" % [FbxExport._f(c.r), FbxExport._f(c.g), FbxExport._f(c.b)]
		objs.append("\tMaterial: %d, \"Material::%s\", \"\" {\n\t\tVersion: 102\n\t\tShadingModel: \"phong\"\n\t\tMultiLayer: 0\n\t\tProperties70:  {\n\t\t\tP: \"DiffuseColor\", \"Color\", \"\", \"A\",%s\n\t\t\tP: \"DiffuseFactor\", \"Number\", \"\", \"A\",1.0\n\t\t\tP: \"AmbientColor\", \"Color\", \"\", \"A\",0.0,0.0,0.0\n\t\t\tP: \"SpecularColor\", \"Color\", \"\", \"A\",0.2,0.2,0.2\n\t\t\tP: \"Shininess\", \"Number\", \"\", \"A\",20.0\n\t\t\tP: \"Opacity\", \"double\", \"Number\", \"\",1.0\n\t\t}\n\t}" % [mid, nm, col])
		var verts := PackedStringArray()
		var idx := PackedStringArray()
		var nv := 0
		var sc := float(m.get("scale", 1.0))
		for sd in m.get("solids", []):
			var ctr: Vector3 = sd[0]
			var hs: Vector3 = (sd[1] as Vector3) * 0.5
			for k in 8:
				var q := ctr + Vector3(hs.x * (1 if k & 1 else -1), hs.y * (1 if k & 2 else -1), hs.z * (1 if k & 4 else -1))
				q *= sc * FbxExport.unit_mult
				verts.append(FbxExport._f(q.x))
				verts.append(FbxExport._f(q.y))
				verts.append(FbxExport._f(q.z))
			for f in FACES:
				idx.append(str(nv + f[0]))
				idx.append(str(nv + f[1]))
				idx.append(str(nv + f[2]))
				idx.append(str(-(nv + f[3]) - 1))
			nv += 8
		var mxf: Transform3D = rot * (m.get("xf", Transform3D.IDENTITY) as Transform3D)
		var mname := "Body_material" if String(m["name"]) == "Body" else nm + "_mesh"
		objs.append(FbxExport._model_block(mdl, mname, "Mesh", Transform3D(mxf.basis.orthonormalized(), mxf.origin)))
		objs.append("\tGeometry: %d, \"Geometry::%s\", \"Mesh\" {\n\t\tVertices: *%d {\n\t\t\ta: %s\n\t\t}\n\t\tPolygonVertexIndex: *%d {\n\t\t\ta: %s\n\t\t}\n\t\tGeometryVersion: 124\n\t}" % [geo, nm, verts.size(), ",".join(verts), idx.size(), ",".join(idx)])
		conns.append("\tC: \"OO\", %d, %d" % [mdl, parent])
		conns.append("\tC: \"OO\", %d, %d" % [geo, mdl])
		conns.append("\tC: \"OO\", %d, %d" % [mid, mdl])
		if String(m.get("tex", "")) != "":
			id += 1
			ntex += 1
			var fp := String(m["tex"]).replace("\\", "/")
			objs.append("\tTexture: %d, \"Texture::%s_tex\", \"\" {\n\t\tType: \"TextureVideoClip\"\n\t\tVersion: 202\n\t\tTextureName: \"Texture::%s_tex\"\n\t\tProperties70:  {\n\t\t\tP: \"UseMaterial\", \"bool\", \"\", \"\",1\n\t\t}\n\t\tMedia: \"Video::%s_tex\"\n\t\tFileName: \"%s\"\n\t\tRelativeFilename: \"%s\"\n\t}" % [id, nm, nm, nm, FbxExport._esc(fp), FbxExport._esc(fp.get_file())])
			conns.append("\tC: \"OP\", %d, %d, \"DiffuseColor\"" % [id, mid])
	var out := _bump(text, "Model", mats.size())
	var oi := out.find("\n}\nConnections:  {\n")
	out = out.substr(0, oi) + "\n" + "\n".join(objs) + out.substr(oi)
	var ci := out.rfind("\n}\n")
	out = out.substr(0, ci) + "\n" + "\n".join(conns) + out.substr(ci)
	var add := "\tObjectType: \"Geometry\" {\n\t\tCount: %d\n\t}\n\tObjectType: \"Material\" {\n\t\tCount: %d\n\t}\n" % [mats.size(), mats.size()]
	if ntex > 0:
		add += "\tObjectType: \"Texture\" {\n\t\tCount: %d\n\t}\n" % ntex
	var di := out.find("\n}\nObjects:")
	if di >= 0:
		out = out.substr(0, di + 1) + add + out.substr(di + 1)
	return out
