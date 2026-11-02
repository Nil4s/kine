extends SceneTree
const KCad := preload("res://scripts/kcad.gd")
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
func rec_make(w: float) -> Dictionary:
	var r := Part.make("w03b")
	var F: Array = r["features"]
	F.append({"t":"sketch","id":"f1","name":"S1","plane":"front","ents":[{"k":"rect","a":[0,0],"b":[w,30]}],"dims":[{"id":"d1","ent":0,"kind":"w","mm":w}]})
	F.append({"t":"extrude","id":"f2","name":"E1","sketch":"f1","dist":20.0,"both":false,"op":"new"})
	F.append({"t":"sketch","id":"f3","name":"S2","plane":"front","ents":[{"k":"rect","a":[34,30],"b":[40,40]}],"dims":[]})
	F.append({"t":"extrude","id":"f4","name":"Boss","sketch":"f3","dist":20.0,"both":false,"op":"join"})
	return r
func edge_near(res: Dictionary, p: Array) -> Dictionary:
	var best := {}
	var bd := 1e9
	for e in res["edges"]:
		var d: float = (e["c"] / Part.MM).distance_to(Vector3(p[0], p[1], p[2]))
		if d < bd:
			bd = d
			best = e
	return best
## where the fillet's picked edge centre is (mm) after replaying to just before it, via the real picker; strip_fp = the old descriptor
func landing(rec: Dictionary, fid: String, strip_fp: bool) -> Variant:
	var i := Part.index_of(rec, fid)
	var ids: Array = Part.replay(rec, i - 1, {"keep": true}).get("ids", [])
	var want: Dictionary = (rec["features"][i]["edges"][0] as Dictionary).duplicate(true)
	if strip_fp:
		want.erase("fp")
	var es: Array = KCad.edges(int(ids[0]))
	var j := PartRefs.pick_edge(int(ids[0]), es, Part._bbox(es), want)
	var out: Variant = null if j < 0 else (es[j]["center"] / Part.MM)
	Part.release_kept(ids)
	return out
## godot --headless --path . -s tests/w03b_test.gd
## Bars (written first): the fillet on the top edge (of the front face's top at y=30) made on width 40, stored by faces, lands within 0.5 mm of the
## same edge's centre after width 60 (x=30 -> 30 here: the edge centre moves with the box; bar = centre of the top-front edge of the 60 box (30,30,0));
## the boss top-left edge fillet stays on the boss at (10,15,20) within 0.5 mm. CONTROL: the old descriptor (no fp) misses the hole rim by >= 0.5 mm or fails.
func _init() -> void:
	var r := rec_make(40.0)
	var res := Part.replay(r, -1, {"edges": true})
	var top := edge_near(res, [17, 30, 0])
	var rim := edge_near(res, [34, 40, 10])
	print("top edge fp ", top.get("fp"), " rim fp ", rim.get("fp"))
	ok((top.get("fp") as Array).size() == 2 and (rim.get("fp") as Array).size() == 2, "replay edges carry the face pair")
	(r["features"] as Array).append({"t":"fillet","id":"f5","name":"Fillet1","body":0,"r":1.0,"edges":[Part.describe(top)]})
	(r["features"] as Array).append({"t":"fillet","id":"f6","name":"Fillet2","body":0,"r":1.0,"edges":[Part.describe(rim)]})
	var r2 := r.duplicate(true)
	r2["features"][0]["ents"][0]["b"] = [60.0, 30]
	r2["features"][0]["dims"][0]["mm"] = 60.0
	var rr := Part.replay(r2, -1, {})
	ok(rr["errors"].is_empty(), "replay errors 0 at width 60 (%s)" % str(rr["errors"]))
	var res2 := Part.replay(r2, 3, {"edges": true})
	var want_top := edge_near(res2, [17, 30, 0])
	var wt: Vector3 = want_top["c"] / Part.MM
	var lt = landing(r2, "f5", false)
	var d1: float = (lt as Vector3).distance_to(wt) if lt != null else 99.0
	ok(d1 < 0.5, "top-edge fillet stays on the top edge: %.3f mm" % d1)
	var lr = landing(r2, "f6", false)
	var wr: Vector3 = edge_near(res2, [34, 40, 10])["c"] / Part.MM
	var d2: float = (lr as Vector3).distance_to(wr) if lr != null else 99.0
	ok(d2 < 0.5, "boss top-left edge fillet stays on the boss: %.3f mm" % d2)
	var c1 = landing(r2, "f6", true)
	var dc: float = (c1 as Vector3).distance_to(wr) if c1 != null else 99.0
	print("control old descriptor on rim: ", dc)
	ok(dc >= 0.5, "CONTROL: the old descriptor lands on another edge (%.2f mm) or fails" % dc)
	var c2 = landing(r2, "f5", true)
	print("old descriptor on top edge: ", c2)
	print("FAILS ", fails)
	quit(1 if fails > 0 else 0)
