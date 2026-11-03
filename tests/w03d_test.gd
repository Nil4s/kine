extends SceneTree
const KCad := preload("res://scripts/kcad.gd")
## godot --headless --path . -s tests/w03d_test.gd     (W03d: fillet face pair for hole rims, corners, body keys; needs the CAD DLL)
## Bars (written before the first run):
##  1 DESCRIPTOR  a real hole's rim edge stores a cylinder half {"ty":"cylinder","r"} with r = 4.0 +- 0.01 mm (the radius of the hole)
##  2 RESIZE      step-1 width 40 -> 60 (the hole keeps its absolute place): the rim fillet lands within 0.5 mm of the rim centre (6,15,0)
##  3 SEAM        the cylinder half's stored normal is overwritten with a wrong one (an arbitrary seam reading): still within 0.5 mm.
##                CONTROL: the same wrong normal on a half WITHOUT "ty" (the W03b descriptor) is refused by the gate: it does not land within 0.5 mm
##  4 TWO HOLES   holes r4 at x=10 and r2 at x=30 (same face pair): each rim lands on its own hole within 0.5 mm after the resize
##  5 RADIUS      the r4 hole edited to r5: its rim fillet lands on the r5 rim (5,15,0) within 0.5 mm
##  6 CORNER      the plate's right-front vertical corner edge stays on the corner (within 0.5 mm of the corner at width 60).
##                CONTROL: a (+y,+y) pair does not land on the corner
##  7 BODY KEYS   a body-making step inserted at the front of a stamped record: the fillet on the second box still rounds that box (volume equal to
##                the volume before the insert, within 1e-12 m3; the fillet removes 2.1e-9 m3 from B). CONTROL: the unstamped record rounds another body or errors
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func rec_make(w: float, r1 := 4.0, two := false) -> Dictionary:
	var r := Part.make("w03d")
	var F: Array = r["features"]
	F.append({"t": "sketch", "id": "f1", "name": "S1", "plane": "front", "ents": [{"k": "rect", "a": [0, 0], "b": [w, 30]}], "dims": [{"id": "d1", "ent": 0, "kind": "w", "mm": w}]})
	F.append({"t": "extrude", "id": "f2", "name": "E1", "sketch": "f1", "dist": 20.0, "both": false, "op": "new"})
	var ents := [{"k": "circle", "c": [10, 15], "r": r1}]
	if two:
		ents.append({"k": "circle", "c": [30, 15], "r": 2.0})
	F.append({"t": "sketch", "id": "f3", "name": "S2", "plane": "front", "ents": ents, "dims": []})
	F.append({"t": "extrude", "id": "f4", "name": "Hole", "sketch": "f3", "dist": 20.0, "both": false, "op": "cut"})
	return r


func edge_near(res: Dictionary, p: Array, body := -1) -> Dictionary:
	var best := {}
	var bd := 1e9
	for e in res["edges"]:
		if body >= 0 and int(e["body"]) != body:
			continue
		var d: float = (e["c"] / Part.MM).distance_to(Vector3(p[0], p[1], p[2]))
		if d < bd:
			bd = d
			best = e
	return best


## where the picker lands (mm) for descriptor `want` on body bi just before step index i; null when it picks nothing
func landing(rec: Dictionary, i: int, want: Dictionary, bi := 0) -> Variant:
	var ids: Array = Part.replay(rec, i - 1, {"keep": true}).get("ids", [])
	var es: Array = KCad.edges(int(ids[bi]))
	var j := PartRefs.pick_edge(int(ids[bi]), es, Part._bbox(es), want)
	var out: Variant = null if j < 0 else (es[j]["center"] / Part.MM)
	Part.release_kept(ids)
	return out


func dist(v: Variant, p: Array) -> float:
	return (v as Vector3).distance_to(Vector3(p[0], p[1], p[2])) if v != null else 99.0


func widen(r: Dictionary, w: float) -> Dictionary:
	var r2 := r.duplicate(true)
	r2["features"][0]["ents"][0]["b"] = [w, 30]
	r2["features"][0]["dims"][0]["mm"] = w
	return r2


## volume (mm3) of the body with key `key` after replay up to step `upto` (-1 = all)
func vol_of_key(rec: Dictionary, key: String, upto := -1) -> float:
	var rp := Part.replay(rec, upto, {"effects": true, "errors_only": true})
	var ks: Array = rp.get("body_keys", [])
	var at := ks.find(key)
	return float(rp["volumes"][at]) if at >= 0 else -1.0


func _init() -> void:
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	# ---- 1, 2, 3
	var r := rec_make(40.0)
	var res := Part.replay(r, -1, {"edges": true})
	var rim := edge_near(res, [6, 15, 0])
	var d := Part.describe(rim)
	print("rim fp ", d["fp"])
	var cyl: Dictionary = {}
	for h in d["fp"]:
		if String(h.get("ty", "")) == "cylinder":
			cyl = h
	ok(not cyl.is_empty() and absf(float(cyl.get("r", 0.0)) - 4.0) < 0.01, "1 the rim stores a cylinder half with r = %s (bar 4.0 +- 0.01)" % str(cyl.get("r")))
	var F: Array = r["features"]
	F.append({"t": "fillet", "id": "f5", "name": "RimFillet", "body": 0, "r": 0.8, "edges": [d]})
	var r2 := widen(r, 60.0)
	var rr := Part.replay(r2, -1, {})
	ok(rr["errors"].is_empty(), "2 replay errors 0 at width 60 (%s)" % str(rr["errors"]))
	var l2 = landing(r2, 4, r2["features"][4]["edges"][0])
	ok(dist(l2, [6, 15, 0]) < 0.5, "2 rim fillet lands on the hole rim after the resize: %.3f mm" % dist(l2, [6, 15, 0]))
	var w3: Dictionary = (r2["features"][4]["edges"][0] as Dictionary).duplicate(true)
	for h in w3["fp"]:
		if String(h.get("ty", "")) == "cylinder":
			h["n"] = [0.0, 1.0, 0.0]   # a wrong, arbitrary seam reading
	var l3 = landing(r2, 4, w3)
	ok(dist(l3, [6, 15, 0]) < 0.5, "3 a wrong cylinder normal no longer matters: %.3f mm" % dist(l3, [6, 15, 0]))
	var w3c: Dictionary = w3.duplicate(true)
	for h in w3c["fp"]:
		h.erase("ty")
	var l3c = landing(r2, 4, w3c)
	print("control wrong normal without ty: ", l3c)
	ok(dist(l3c, [6, 15, 0]) >= 0.5, "3 CONTROL the W03b descriptor with that wrong normal does not land (%.2f mm)" % dist(l3c, [6, 15, 0]))
	# ---- 4 two holes
	var rt := rec_make(40.0, 4.0, true)
	var rest := Part.replay(rt, -1, {"edges": true})
	var ra := Part.describe(edge_near(rest, [6, 15, 0]))
	var rb := Part.describe(edge_near(rest, [28, 15, 0]))
	var rt2 := widen(rt, 60.0)
	var la = landing(rt2, 4, ra)
	var lb = landing(rt2, 4, rb)
	ok(dist(la, [6, 15, 0]) < 0.5 and dist(lb, [28, 15, 0]) < 0.5, "4 each rim lands on its own hole: %.3f and %.3f mm" % [dist(la, [6, 15, 0]), dist(lb, [28, 15, 0])])
	# ---- 5 radius edit
	var rt3 := rec_make(40.0, 5.0, true)
	var l5 = landing(rt3, 4, ra)
	ok(dist(l5, [5, 15, 0]) < 0.5, "5 the r4 rim fillet follows the hole edited to r5: %.3f mm from (5,15,0); the r2 rim is %.1f mm away" % [dist(l5, [5, 15, 0]), dist(l5, [28, 15, 0])])
	# ---- 6 corner: plate + boss on the right edge
	var rc := Part.make("w03d_c")
	var C: Array = rc["features"]
	C.append({"t": "sketch", "id": "f1", "name": "S1", "plane": "front", "ents": [{"k": "rect", "a": [0, 0], "b": [40, 30]}], "dims": [{"id": "d1", "ent": 0, "kind": "w", "mm": 40.0}]})
	C.append({"t": "extrude", "id": "f2", "name": "E1", "sketch": "f1", "dist": 20.0, "both": false, "op": "new"})
	C.append({"t": "sketch", "id": "f3", "name": "S2", "plane": "front", "ents": [{"k": "rect", "a": [34, 30], "b": [40, 40]}], "dims": []})
	C.append({"t": "extrude", "id": "f4", "name": "Boss", "sketch": "f3", "dist": 20.0, "both": false, "op": "join"})
	var resc := Part.replay(rc, -1, {"edges": true})
	var cor := edge_near(resc, [40, 15, 0])
	var cd := Part.describe(cor)
	print("corner edge ", cor["c"] / Part.MM, " fp ", cd["fp"])
	var rc2 := widen(rc, 60.0)
	var resc2 := Part.replay(rc2, -1, {"edges": true})
	var wc: Vector3 = edge_near(resc2, [60, 15, 0])["c"] / Part.MM
	var lc = landing(rc2, 4, cd)
	var dc: float = (lc as Vector3).distance_to(wc) if lc != null else 99.0
	ok(dc < 0.5, "6 the plate's right-front corner edge stays on the corner: %.3f mm" % dc)
	var cw := cd.duplicate(true)   # a pair that fits no edge, and a box position far from the corner: the picker falls back to the position score and lands elsewhere
	cw["fp"][0]["n"] = [0.0, 1.0, 0.0]
	cw["fp"][1]["n"] = [0.0, 1.0, 0.0]
	cw["q"] = [0.0, 0.0, 0.0]
	cw.erase("p")
	var lcw = landing(rc2, 4, cw)
	var dcw: float = (lcw as Vector3).distance_to(wc) if lcw != null else 99.0
	ok(dcw >= 0.5, "6 CONTROL a (+y,+y) pair does not land on the corner (%.2f mm)" % dcw)
	# ---- 7 body keys
	var rk := Part.make("w03d_k")
	var K: Array = rk["features"]
	K.append({"t": "prim", "id": "f1", "name": "A", "kind": "box", "op": "new", "x": 0.0, "w": 20.0, "h": 20.0, "d": 20.0})
	K.append({"t": "prim", "id": "f2", "name": "B", "kind": "box", "op": "new", "x": 60.0, "w": 10.0, "h": 10.0, "d": 10.0})
	var resk := Part.replay(rk, -1, {"edges": true})
	var cb: Vector3 = Vector3.ZERO
	for e in resk["edges"]:
		if int(e["body"]) == 1:
			cb += e["c"] / Part.MM
	cb /= 12.0
	var eb := edge_near(resk, [cb.x, cb.y + 5.0, cb.z + 5.0], 1)
	print("B centre ", cb, " edge ", eb.get("c", Vector3.ZERO) / Part.MM, " body ", eb.get("body"))
	K.append({"t": "fillet", "id": "f3", "name": "FB", "body": 1, "r": 1.0, "edges": [Part.describe(eb)]})
	var n0 := PartBKeys.stamp(rk)
	print("stamped ", n0, " fillet ", rk["features"][2])
	var vol_before := vol_of_key(rk, "f2#0")
	var vb_nofillet := vol_of_key(rk, "f2#0", 1)
	ok(vol_before > 0.0 and vol_before < vb_nofillet - 1e-9, "7 setup: the fillet removes volume from B (%s -> %s m3)" % [vb_nofillet, vol_before])
	var ins := Part.new_feature(rk, "prim", {"kind": "box", "op": "new", "x": 120.0, "w": 5.0, "h": 5.0, "d": 5.0, "name": "Ins"})
	var stamped := rk.duplicate(true)
	(stamped["features"] as Array).insert(0, ins)
	var unst := rk.duplicate(true)
	for f in unst["features"]:
		for k in ["bkey", "body_i"]:
			(f as Dictionary).erase(k)
	(unst["features"] as Array).insert(0, ins.duplicate(true))
	var vs := vol_of_key(stamped, "f2#0")
	ok(absf(vs - vol_before) < 1e-12, "7 stamped record: B keeps the fillet after the insert (%s vs %s m3)" % [vs, vol_before])
	var ue: Dictionary = Part.replay(unst, -1, {"errors_only": true}).get("errors", {})
	var vu := vol_of_key(unst, "f2#0")
	print("control unstamped B volume ", vu, " errors ", ue)
	ok(absf(vu - vol_before) > 1e-9 or not ue.is_empty(), "7 CONTROL the unstamped record loses the fillet on B or errors")
	print("FAILS ", fails)
	quit(1 if fails > 0 else 0)
