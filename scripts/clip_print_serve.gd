## clip_print_serve.gd - agent tool `clip_print` (L90: ROADMAP_400 L27 + L21). {op, src}:
##   fingerprint  {src}  the open scene against the scene file `src`: the numbers table and ONE distance (no edit, no undo step)
##   transfer     {src}  the timing statistics of `src` (clip A) on the open scene (clip B): B's key poses kept, B's moves, holds, eases
##                       retimed toward A's fingerprint (scripts/clip_restyle.gd); ONE undo step; nothing changes (and no undo step)
##                       when B is already A's
## Both reply with the distance before / after as numbers.
class_name ClipPrintServe
extends RefCounted


static func _err(s: String) -> Dictionary:
	return {"ok": false, "error": s}


static func _load(src: String) -> Variant:
	var path := AgentTools.res(src)
	if src == "" or not FileAccess.file_exists(path):
		return "no such scene file '%s'" % src
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return "'%s' is not a scene file" % src
	var S := Scene.new()
	S.from_dict(d)
	return S


static func serve(m: Node, p: Dictionary) -> Dictionary:
	var op := String(p.get("op", "fingerprint"))
	if not op in ["fingerprint", "transfer"]:
		return _err("clip_print op is fingerprint or transfer (got '%s')" % op)
	if not p.has("src"):
		return _err("clip_print needs {src}: the scene file of clip A, e.g. scenes/walk_bat.json")
	var a: Variant = _load(String(p["src"]))
	if a is String:
		return _err("clip_print: " + a)
	var SA: Scene = a
	var S: Scene = m.S
	var fpA := ClipPrint.measure(SA, true)
	if not bool(fpA.get("ok", false)):
		return _err("clip_print: clip A: " + String(fpA.get("error", "")))
	if op == "fingerprint":
		var fpB := ClipPrint.measure(S, true)
		if not bool(fpB.get("ok", false)):
			return _err("clip_print: the open scene: " + String(fpB.get("error", "")))
		var c := ClipPrint.compare(fpB, fpA)
		return {"ok": true, "result": {"distance": c["distance"], "terms": c["terms"], "table": ClipPrint.table(fpB, fpA, "open", "src"),
			"global_open": fpB["global"], "global_src": fpA["global"]}}
	var pl := ClipRestyle.plan(S, fpA)
	if not bool(pl.get("ok", false)):
		return _err("clip_print: " + String(pl.get("error", "")))
	if not bool(pl["changed"]):
		return {"ok": true, "result": {"changed": false, "distance_before": pl["before"], "distance_after": pl["after"], "note": "nothing to move toward: the open scene already fits that fingerprint"}}
	m._do(func(): ClipRestyle.apply_plan(S, pl))
	return {"ok": true, "result": {"changed": true, "distance_before": pl["before"], "distance_after": pl["after"], "move_scale": pl["move_scale"],
		"hold_scale": pl["hold_scale"], "ease": pl["ease"], "ease_bias": pl["ease_bias"], "natural": pl["natural"], "length_s": snappedf(S.length(), 0.001)}}
