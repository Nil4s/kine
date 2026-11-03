class_name FrameLight
extends RefCounted
## C06 PICTURE MATH FOR AN AGENT THAT CANNOT SEE: what frame_facts adds (keys only; every old key is untouched).
##   frame_facts {part?: record} -> "light": {brightest_piece, brightest_peak_luminance, touching_frame_edge: [names], touching_frame_edge_with_glow: [names],
##                                           pieces: {name: {emission, peak_luminance, glow_px, edge: {left,right,top,bottom}, edge_with_glow: {...}}}, note}
## Per piece (a body of the part, looked up by its body index in the replay's body_looks):
##   emission         = luminance(glow colour) x glow strength (0 = it does not glow). Luminance = 0.2126 R + 0.7152 G + 0.0722 B of the 0..1 colour.
##   peak_luminance   = emission + luminance(albedo): an UPPER bound of the brightest a pixel of it can be (emission plus a fully lit surface), so a white
##                      emitter outranks any lit paint. Ranking, not a render.
##   glow_px          = 0 without emission, else round(8 x log2(1 + emission) x width / 1280), at most 200: how far the bloom spreads past the silhouette.
##                      An ESTIMATE of the Environment glow (the measured bloom depends on the scene's glow settings); reflections are NOT modelled.
##   edge             = the silhouette box (the exact projected-corner box of frame_facts) reaches within 0.5 px of that side of the picture.
##   edge_with_glow   = the same with the box grown by glow_px on every side.
const TOL_PX := 0.5


static func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## a given part record ({part: {...}} in the request) as pieces, the way gather_part does for the part on screen
static func gather_given(m: Node, part: Dictionary) -> Dictionary:
	var rec := Part.from_file(part)
	var res := Part.replay(rec)
	if res.get("mesh") == null:
		return {"names": [], "verts": [], "aabb": []}
	var pm := MeshInstance3D.new()
	pm.mesh = res["mesh"]
	m.add_child(pm)
	var g := FrameFacts.gather_part(pm, res)
	m.remove_child(pm)
	pm.free()
	return g


static func block(g: Dictionary, cam: Dictionary) -> Dictionary:
	var names: Array = g["names"]
	var looks: Array = g.get("looks", [])
	var bidx: Array = g.get("body_idx", [])
	if looks.is_empty() or bidx.size() != names.size():
		return {"pieces": {}, "brightest_piece": "", "touching_frame_edge": [], "touching_frame_edge_with_glow": [], "note": "no per-piece looks here (pieces are not a part's bodies)"}
	var W := int(cam["w"])
	var H := int(cam["h"])
	var pcs := {}
	var best := -1.0
	var best_name := ""
	var touch := []
	var touch_g := []
	for i in names.size():
		var bi := int(bidx[i])
		var lk: Dictionary = looks[bi] if bi >= 0 and bi < looks.size() and looks[bi] is Dictionary else {}
		var em := 0.0
		if lk.get("glow") is Color and float(lk.get("glow_k", 0.0)) > 0.0:
			em = lum(lk["glow"]) * float(lk["glow_k"])
		var al := lum(lk["c"]) if lk.get("c") is Color else 0.0
		var peak := em + al
		var gpx := 0.0 if em <= 0.0 else minf(roundf(8.0 * log(1.0 + em) / log(2.0) * W / 1280.0), 200.0)
		var sil: Dictionary = FrameFacts.measure(g, [i], cam)["sil"]
		var e := {"left": false, "right": false, "top": false, "bottom": false}
		var eg := e.duplicate()
		if int(sil["n"]) > 0:
			e = _edges(sil, W, H, 0.0)
			eg = _edges(sil, W, H, gpx)
		pcs[names[i]] = {"emission": snappedf(em, 0.0001), "peak_luminance": snappedf(peak, 0.0001), "glow_px": gpx, "edge": e, "edge_with_glow": eg}
		if int(sil["n"]) > 0 and peak > best:
			best = peak
			best_name = String(names[i])
		if e.values().has(true):
			touch.append(String(names[i]))
		if eg.values().has(true):
			touch_g.append(String(names[i]))
	return {"brightest_piece": best_name, "brightest_peak_luminance": snappedf(maxf(best, 0.0), 0.0001), "touching_frame_edge": touch, "touching_frame_edge_with_glow": touch_g,
		"pieces": pcs, "note": "peak_luminance is an upper bound (emission + lit albedo); glow_px is an estimate of the bloom; reflections are not modelled"}


static func _edges(sil: Dictionary, W: int, H: int, grow: float) -> Dictionary:
	return {"left": float(sil["x0"]) - grow <= TOL_PX, "right": float(sil["x1"]) + grow >= W - TOL_PX,
		"top": float(sil["y0"]) - grow <= TOL_PX, "bottom": float(sil["y1"]) + grow >= H - TOL_PX}
