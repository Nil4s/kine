class_name KMeshStats
extends RefCounted
## A14 (docs/ROADMAP_400.md): a KMesh's counts for the status line while it is edited (the Model page's readout, like
## Blender's statistics overlay). Pure: reads the mesh and the selection, changes nothing.
##   verts / edges / faces   the KMesh's own (an edge once, however many faces use it)
##   tris                    the triangles it draws as: a face of n corners is n - 2 (what the GPU and a game engine count)
##   tri_faces / quads / ngons   faces by corner count: 3, 4, 5 or more
##   poles                   interior verts whose valence (edges at the vert) is not 4: the places an edge loop stops.
##                           poles3 = valence 3 or less (a cube's corner), poles5 = 5 or more (a star). Boundary verts and
##                           loose verts are not poles (a boundary vert of valence 3 is the regular one there)
##   boundary / loose        verts on an open edge / in no face
##   sel, sel_mode           the selection's size in its live mode (KMeshSelect keeps only that set filled)
## The status line text is line(): short enough for the readout's half of the line.


static func of(m: KMesh, sel: KMeshSelect = null) -> Dictionary:
	var nv := m.verts.size()
	var val := PackedInt32Array()
	val.resize(nv)
	var es: Array = m.edges()
	for e in es:
		val[(e as Vector2i).x] += 1
		val[(e as Vector2i).y] += 1
	var on_rim := {}
	m._fresh()
	for h in m.he_twin.size():
		if m.he_twin[h] == -1:
			on_rim[m.he_vert[h]] = true
			on_rim[m.he_vert[m.he_next[h]]] = true
	var tris := 0
	var by := [0, 0, 0]   # 3, 4, 5+ corners
	for f in m.faces:
		var n: int = (f as PackedInt32Array).size()
		if n < 3:
			continue
		tris += n - 2
		by[mini(n, 5) - 3] += 1
	var p3 := 0
	var p5 := 0
	var loose := 0
	for v in nv:
		if val[v] == 0:
			loose += 1
		elif not on_rim.has(v) and val[v] != 4:
			if val[v] < 4:
				p3 += 1
			else:
				p5 += 1
	var r := {"verts": nv, "edges": es.size(), "faces": m.faces.size(), "tris": tris,
		"tri_faces": by[0], "quads": by[1], "ngons": by[2], "poles": p3 + p5, "poles3": p3, "poles5": p5,
		"boundary": on_rim.size(), "loose": loose, "sel": 0, "sel_mode": -1}
	if sel != null:
		r["sel"] = sel.count()
		r["sel_mode"] = sel.mode
	return r


## the readout: "98 verts  192 edges  96 faces  192 tris  ·  0 n-gons  ·  poles 8 / 0 (3 / 5+)  ·  4 / 98 picked"; under 504 px
## at the line's 12 px (the readout's half of a 1600 px window); a narrower window trims its end (picked, then poles)
static func line(s: Dictionary) -> String:
	var t := "%s verts  %s edges  %s faces  %s tris" % [ViewX._thousands(s["verts"]), ViewX._thousands(s["edges"]),
		ViewX._thousands(s["faces"]), ViewX._thousands(s["tris"])]
	t += "  ·  %d n-gon%s" % [s["ngons"], "" if s["ngons"] == 1 else "s"]
	t += "  ·  poles %d / %d (3 / 5+)" % [s["poles3"], s["poles5"]]
	var md: int = s["sel_mode"]
	if md >= 0:   # of the live mode's kind: the mode is on the say-line and the 1 / 2 / 3 keys
		t += "  ·  %d / %s picked" % [s["sel"], ViewX._thousands([s["verts"], s["edges"], s["faces"]][md])]
	return t
