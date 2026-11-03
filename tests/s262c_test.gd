extends SceneTree
## godot --path . -s tests/s262c_test.gd   (s262c: the GPU card exploded view v2, scripts/build/gpu_explode_layout.gd + ExplodeKeys.layout_hook; needs the CAD DLL)
## Fixture: hall_compare/gpu/kine_explode/gpu_copy.json (the 338-feature card, a copy). Bars written before the first run:
##   1 SPRINGS  PER BODY INDEX (never per name; 4 springs share one name): each of the 4 "Spring" bodies starts leaving (TIMELINE key: last 0 mm key before its first
##              positive key) strictly before the "Backplate" body does. CONTROL: the same bar on the planner alone (3be3abc6 behaviour, layout_hook empty) FAILS.
##   2 PAIRS    each spring has the same joint keys as one spring screw (4 of 4). CONTROL: planner alone, 0 of 4.
##   3 GAPS     at the hold, per body index: Fan*/Ring glow +300 mm, Shroud/Shroud facet/RGB bar +220, Fins/Heat pipe/Base plate +130, Backplate 90 (down -Z), IO bracket 60 (-X),
##              every other board body 0 (0.01 mm); joint axes +Z / -Z / -X. CONTROL: planner alone moves >= 1 board body.
##   4 NAMES    8 distinct joint names for 4 springs + 4 spring screws
##   5 CLEAR    ExplodeView.check (IO bracket's Z sweep zeroed, it moves along X) finds 0 collisions, plan.stuck empty
var fails := 0
const FIX := "C:/Users/Nick/tools/kine_workers/hall_compare/gpu/kine_explode/gpu_copy.json"
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


## {start, keys} of a body from the prop's joint keys (mm); {} when it has no joint
func leave_of(p: Dictionary, jn: Array, bi: int) -> Dictionary:
	var ks: Array = (p.get("jkeys", {}) as Dictionary).get(String(jn[bi]), [])
	if ks.is_empty():
		return {}
	var start := -1.0
	var prev := 0.0
	for k in ks:
		if start < 0.0 and float(k["v"]) > 1e-6:
			start = prev
		if start < 0.0:
			prev = float(k["t"])
	return {"start": start, "keys": ks}


func _peak(jk: Dictionary, nm: String) -> float:
	var v := 0.0
	for k in jk.get(nm, []):
		v = maxf(v, float(k["v"]))
	return v


func names_idx(names: Array, nm: String) -> Array:
	var o: Array = []
	for i in names.size():
		if names[i] == nm:
			o.append(i)
	return o


func run_case(rec: Dictionary, hooked: bool) -> Dictionary:
	ExplodeKeys.layout_hook = Callable(GpuExplodeLayout, "layout") if hooked else Callable()
	var opts := {"axis": Vector3.BACK, "gap_mm": 10.0, "by_level": false, "anchor": "PCB"}
	var r := ExplodeKeys.send(m, rec, opts, 0.7, 0.12, 1.5)
	var p: Dictionary = m.S.props[int(r["prop"])]
	var kd: Dictionary = Props.kind_of(String(p["kind"]))
	var res := Part.replay(rec)
	var pl := ExplodeKeys.plan_of(res, opts)
	return {"p": p, "kd": kd, "names": pl["names"], "jn": ExplodeKeys._joint_names(pl["names"]), "plan": pl["plan"], "send": r}


func spring_bar(c: Dictionary) -> int:
	var names: Array = c["names"]
	var lb := leave_of(c["p"], c["jn"], int(names_idx(names, "Backplate")[0]))
	var good := 0
	for bi in names_idx(names, "Spring"):
		var ls := leave_of(c["p"], c["jn"], int(bi))
		if not ls.is_empty() and not lb.is_empty() and float(ls["start"]) < float(lb["start"]) - 1e-6:
			good += 1
	return good


func pairs_shared(c: Dictionary) -> int:
	var names: Array = c["names"]
	var used := {}
	var n := 0
	for sp in names_idx(names, "Spring"):
		var a := leave_of(c["p"], c["jn"], int(sp))
		for sc in names_idx(names, "Spring screw"):
			if used.has(sc):
				continue
			var b := leave_of(c["p"], c["jn"], int(sc))
			if not a.is_empty() and not b.is_empty() and JSON.stringify(a["keys"]) == JSON.stringify(b["keys"]):
				used[sc] = true
				n += 1
				break
	return n


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 8:
		await process_frame
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	var scene: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX))
	var rec := Part.from_file(scene["part"])
	var old := run_case(rec, false)
	var nw := run_case(rec, true)
	ExplodeKeys.layout_hook = Callable()
	var g_old := spring_bar(old)
	var g_new := spring_bar(nw)
	print("springs leaving before the backplate: planner alone %d of 4, s262c %d of 4" % [g_old, g_new])
	ok(g_new == 4, "1 SPRINGS: 4 of 4 springs (by body index) leave before the Backplate")
	ok(g_old < 4, "1 CONTROL: the same bar fails on the planner alone (%d of 4)" % g_old)
	var ps_new := pairs_shared(nw)
	var ps_old := pairs_shared(old)
	ok(ps_new == 4, "2 PAIRS: each spring shares its keys with its own screw (%d of 4)" % ps_new)
	ok(ps_old == 0, "2 CONTROL: planner alone, %d of 4 pairs share keys" % ps_old)
	var nm := {}
	for k in ["Spring", "Spring screw"]:
		for bi in names_idx(nw["names"], k):
			nm[String(nw["jn"][bi])] = true
	ok(nm.size() == 8, "4 NAMES: %d distinct joint names for 4 springs + 4 spring screws" % nm.size())
	var names: Array = nw["names"]
	var jn: Array = nw["jn"]
	var t_hold: float = float(nw["send"]["total"]) * 0.5
	var ang := PropJoints.angles_at(nw["p"], t_hold)
	var bad := 0
	var worst := ""
	for i in names.size():
		var g := GpuExplodeLayout.group_of(String(names[i]))
		var w := 0.0
		if g in ["fans", "shroud", "cooler", "backplate", "io"]:
			w = absf(float(GpuExplodeLayout.DIST[g])) * 1000.0
		elif g != "board":
			continue
		var got := float(ang.get(String(jn[i]), 0.0))
		if absf(got - w) > 0.01:
			bad += 1
			worst = "%s#%d got %.3f want %.3f" % [names[i], i, got, w]
	ok(bad == 0, "3 GAPS: %d bodies off their SPEC v2 gap at the hold %s" % [bad, worst])
	var ax_ok := true
	var nj := 0
	for j in nw["kd"]["pjoints"]:
		nj += 1
		var g := GpuExplodeLayout.group_of(String(names[int(j["piece"])]))
		var wantax := Vector3.ZERO
		if g in ["fans", "shroud", "cooler"]:
			wantax = Vector3.BACK
		elif g in ["backplate", "bpscrews", "xbracket", "spring"]:
			wantax = Vector3.FORWARD
		elif g == "io":
			wantax = Vector3.LEFT
		if wantax != Vector3.ZERO and (j["axis"] as Vector3).distance_to(wantax) > 1e-4:
			ax_ok = false
	ok(ax_ok and nj > 0, "3 AXES: fans/shroud/cooler slide +Z, backplate/screws/springs -Z, IO bracket -X (%d joints)" % nj)
	var moved_old := 0
	var jk0: Dictionary = old["p"].get("jkeys", {})
	for i in old["names"].size():
		if GpuExplodeLayout.group_of(String(old["names"][i])) == "board" and _peak(jk0, String(old["jn"][i])) > 0.01:
			moved_old += 1
	ok(moved_old >= 1, "3 CONTROL: the planner alone moves %d board bodies off the PCB" % moved_old)
	var plan: Dictionary = nw["plan"].duplicate(true)
	var ex: Dictionary = plan.get("extra_axis", {})
	for u in ex:
		plan["dist"][int(u)] = 0.0
		plan["ubox"][int(u)] = AABB(Vector3(1e3, 1e3, 1e3), Vector3.ZERO)   # it leaves along X, first of the two layers it blocks (the order shows io before shroud and cooler)
	var sc := ExplodeView.schedule(plan, 0.7, 0.12, 1.5)
	var ck := ExplodeView.check(plan, sc)
	print("collisions %d samples %d stuck %s" % [(ck["collisions"] as Array).size(), ck["samples"], str(plan["stuck"])])
	var labs: Array = plan.get("labels", [])
	for ci in mini(8, (ck["collisions"] as Array).size()):
		var c: Dictionary = ck["collisions"][ci]
		print("COL t %.2f %s#%d hits %s#%d" % [c["t"], labs[c["mover"]], c["mover"], labs[c["hit"]], c["hit"]])
	print("ORDER ", (plan["order"] as Array).map(func(u): return "%s%d" % [labs[u], u]), " signs ", plan["sign"], " dist ", plan["dist"])
	ok((ck["collisions"] as Array).size() == 0 and (plan["stuck"] as Array).is_empty(), "5 CLEAR: 0 collisions, no stuck layer")
	print("s262c: %d fail" % fails)
	quit(1 if fails > 0 else 0)
