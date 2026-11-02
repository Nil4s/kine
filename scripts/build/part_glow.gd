class_name PartGlow
extends RefCounted
## ITEM 258 A LOOK THAT GLOWS (found by the temple video: lanterns and RGB strips could only be coloured, never lit). An appear step may carry
##   "emission": [r, g, b] (0..1, the colour of the light the surface gives off) and "emission_energy": strength (0..MAX_K; 0 or no field = no glow).
## Part.look_of copies them into the look as "glow" (Color) and "glow_k" (float), so they ride with the body through split / pattern / combine the way the
## colour does, are saved with the part (they are record fields of the appear step) and key the surface packing (s233) like any other look number.
## The two look-to-material builders (Part.paint: pictures, props, the nice render; PartUI._look_surfaces: the Part view and final_shot) call apply().
## A glowing surface is drawn by the renderer as emission: it is bright with no light on it, and the Environment's glow (bloom) spreads it when on.

const MAX_K := 16.0


## the appear step's emission fields into the look (no fields, a zero strength or a black colour: the look is left without glow)
static func read(f: Dictionary, look: Dictionary) -> void:
	var e: Variant = f.get("emission", null)
	var k := clampf(float(f.get("emission_energy", 0.0)), 0.0, MAX_K)
	if not (e is Array) or (e as Array).size() < 3 or k <= 0.0:
		return
	var c := Color(clampf(float(e[0]), 0.0, 1.0), clampf(float(e[1]), 0.0, 1.0), clampf(float(e[2]), 0.0, 1.0))
	if c.r + c.g + c.b <= 0.0:
		return
	look["glow"] = c
	look["glow_k"] = k


static func has(look: Dictionary) -> bool:
	return look.get("glow") is Color and float(look.get("glow_k", 0.0)) > 0.0


## the look's glow on a material (a look without glow leaves the material as it is)
static func apply(mt: BaseMaterial3D, look: Dictionary) -> void:
	if mt == null or not has(look):
		return
	mt.emission_enabled = true
	mt.emission = look["glow"]
	mt.emission_energy_multiplier = float(look["glow_k"])


## the record fields of a glow (for an appear step): {"emission": [r, g, b], "emission_energy": k}
static func fields(c: Color, k: float) -> Dictionary:
	return {"emission": [snappedf(c.r, 0.0001), snappedf(c.g, 0.0001), snappedf(c.b, 0.0001)], "emission_energy": clampf(k, 0.0, MAX_K)}


## one appear step on body bi that keeps the look the body has after the steps so far (its colour, roughness, metal, alpha, made material) and adds
## the glow; returns the new step's id ("" when the part has no body bi). k = 0 turns a glow off.
static func add_step(rec: Dictionary, bi: int, c: Color, k: float) -> String:
	var res := Part.replay(rec, -1, {"errors_only": true})
	var looks: Array = res.get("body_looks", [])
	if bi < 0 or bi >= int(res.get("bodies", 0)):
		return ""
	var l: Dictionary = looks[bi] if bi < looks.size() else Part.look_at([], bi)
	var lc: Color = l["c"]
	var f := {"name": "Glow%d" % (Part.count_of(rec, "appear") + 1), "body": bi, "preset": String(l.get("preset", "Custom")), "color": [lc.r, lc.g, lc.b],
		"rough": float(l.get("rough", 0.5)), "metal": float(l.get("metal", 0.15)), "alpha": float(l.get("alpha", 1.0))}
	if l.get("mat") is Dictionary and not (l["mat"] as Dictionary).is_empty():
		f["mat"] = (l["mat"] as Dictionary).duplicate(true)
	f.merge(fields(c, k), true)
	var nf := Part.new_feature(rec, "appear", f)
	(rec["features"] as Array).append(nf)
	return String(nf["id"])
