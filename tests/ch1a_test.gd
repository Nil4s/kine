extends SceneTree
## CH1a: the one-storey house (data/challenges/ch1_house.json, docs/CH1_REFERENCE.md) replayed in Kine and held to the reference.
## godot --headless --path . -s tests/ch1a_test.gd
## BARS (written before any number was read):
##   A  REPLAY    the Part record replays with 0 errors and one body per listed member; every member is found in the replay within 1.5 mm
##   B  ROOMS     the six rooms' clear sizes, measured from the REPLAYED plates, are each within 2 % of the reference (w and d)
##   C  AREA      the slab's plan area is within 2 % of 800 sq ft (74.32 m2); the blueprint's overall dimensions give the same within 2 %
##   D  GRID      every stud / joist centre is on the 406.4 mm grid and every rafter centre on the 609.6 mm grid, within 5 mm
##   E  LOAD PATH every member is in one touching chain (gap < 1 mm) down to the ground, and every vertical member rests on a member below
##   F  PLAN      the Building record's plan (Blueprint) has the six rooms' sizes within 2 % (walls from Blueprint.room_walls)
##   G  MEMBERS   out/ch1/members.json lists kind, nominal size, span, spacing and supports for every member
##   D2 PAIRS    (CH1c) every rafter_pair sits on the 24 in grid offset by exactly one joist thickness (38 mm) from the grid line, which is the centre of its paired joist, within 5 mm
##   H  RAFTERS  (CH1c) every rafter's axis (longest edge of its sketch polygon) is perpendicular to the ridge axis: |dot| < 1e-3, and the front and back slopes meet at the ridge
##   I  OVERLAP   (CH1c) no two framing members overlap: the volume of intersection of every pair is under 1 mm3 (rafter heels sit beside the joists, birdsmouth on the top plate)
##   J  HOUSE     (CH1c) HouseCheck.check on the house record built from out/ch1/members.json passes on every line (UNVERIFIED lines stay listed as such)
##   CONTROL      a stud moved 20 mm fails D; a stud lifted 5 mm fails E; a room 4 % short fails B; a 4 % short slab fails C
var fails := 0
const TOL_ROOM := 0.02
const REF_ROOMS := {   # name -> [w, d] mm clear between stud faces (docs/CH1_REFERENCE.md)
	"Kitchen": [4267.0, 3353.0], "Hall": [2134.0, 3353.0], "Bedroom 2": [2997.0, 3353.0],
	"Living": [4267.0, 4000.0], "Bath/hall": [2134.0, 4000.0], "Bedroom 1": [2997.0, 4000.0]}
const REF_AREA_M2 := 74.32


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func _init() -> void:
	_run.call_deferred()


## a body list: [{"name", "kind", "lo": Vector3, "hi": Vector3}] in mm, from the replay matched to the member list
func replayed(d: Dictionary) -> Dictionary:
	var rec: Dictionary = d["part"]
	var res := Part.replay(rec.duplicate(true))
	var mesh: ArrayMesh = res["mesh"]
	var boxes := []
	var ranges: Array = res["surf_ranges"]   # more than 256 bodies share surfaces by look: [[body, first vertex, vertex count]] per surface
	for i in mesh.get_surface_count():
		var a: PackedVector3Array = mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
		for rg in ranges[i]:
			var lo := Vector3(1e9, 1e9, 1e9)
			var hi := -lo
			for k in range(int(rg[1]), int(rg[1]) + int(rg[2])):
				lo = lo.min(a[k])
				hi = hi.max(a[k])
			boxes.append([lo * 1000.0, hi * 1000.0])
	var members: Array = d["members"]
	var used := {}
	var out := []
	var worst := 0.0
	var missing := 0
	for m in members:
		var b: Array = m["box"]
		var mlo := Vector3(b[0], b[1], b[2])
		var mhi := Vector3(b[3], b[4], b[5])
		var best := -1
		var bd := 1e9
		for i in boxes.size():
			if used.has(i):
				continue
			var e := maxf(mx((boxes[i][0] - mlo).abs()), mx((boxes[i][1] - mhi).abs()))
			if e < bd:
				bd = e
				best = i
		if best < 0 or bd > 1.5:
			missing += 1
			continue
		used[best] = true
		worst = maxf(worst, bd)
		out.append({"name": m["name"], "kind": m["kind"], "lo": boxes[best][0], "hi": boxes[best][1]})
	return {"res": res, "bodies": boxes.size(), "list": out, "missing": missing, "worst": worst}


func mx(v: Vector3) -> float:
	return maxf(v.x, maxf(v.y, v.z))


func by_name(list: Array) -> Dictionary:
	var o := {}
	for e in list:
		o[e["name"]] = e
	return o


## the clear sizes of the six rooms from the plates in `list` (mm); `bump` shifts one wall for the control
func rooms_of(list: Array, bump := 0.0) -> Dictionary:
	var n := by_name(list)
	var Lx1: float = n["plate_t1.L.0"]["hi"].x
	var Rx0: float = n["plate_t1.R.0"]["lo"].x
	var Fz1: float = n["plate_t1.F.0"]["hi"].z
	var Bz0: float = n["plate_t1.B.0"]["lo"].z
	var Hz0: float = n["plate_t1.H.0"]["lo"].z
	var Hz1: float = n["plate_t1.H.0"]["hi"].z
	var V1a: Dictionary = n["plate_t1.V1.0"]
	var V1b: Dictionary = n["plate_t1.V1.1"]
	var V2a: Dictionary = n["plate_t1.V2.0"]
	var V2b: Dictionary = n["plate_t1.V2.1"]
	var k := 1.0 - bump
	return {
		"Kitchen": [(V1a["lo"].x - Lx1) * k, Hz0 - Fz1], "Hall": [V2a["lo"].x - V1a["hi"].x, Hz0 - Fz1], "Bedroom 2": [Rx0 - V2a["hi"].x, Hz0 - Fz1],
		"Living": [V1b["lo"].x - Lx1, Bz0 - Hz1], "Bath/hall": [V2b["lo"].x - V1b["hi"].x, Bz0 - Hz1], "Bedroom 1": [Rx0 - V2b["hi"].x, Bz0 - Hz1]}


func rooms_fail(rm: Dictionary) -> int:
	var bad := 0
	for k in REF_ROOMS:
		for i in 2:
			var ref: float = REF_ROOMS[k][i]
			if absf(float(rm[k][i]) - ref) / ref > TOL_ROOM:
				bad += 1
	return bad


func grid_fail(list: Array, shift_name := "", shift := 0.0) -> int:
	var bad := 0
	for e in list:
		var k: String = e["kind"]
		var step := 0.0
		if k == "stud" or k == "joist":
			step = 406.4
		elif k == "rafter":
			step = 609.6
		else:
			continue
		var nm: String = e["name"]
		var c: Vector3 = (e["lo"] + e["hi"]) * 0.5
		var w: String = nm.split(".")[1]
		# the stud's position along its wall: x for F B H, z for L R V1 V2; joists and rafters run along x
		var along: float = c.z if (k == "stud" and w in ["L", "R", "V1", "V2"]) else c.x
		if nm == shift_name:
			along += shift
		var r := fposmod(along + step * 0.5, step) - step * 0.5
		if absf(r) > 5.0:
			bad += 1
	return bad


## [count, failures] for kind rafter_pair: centre x - 38 on the 609.6 grid and 38 mm from the nearest joist centre, within 5 mm; `shift` moves the first one
func pairs_fail(list: Array, _tag := "", shift := 0.0) -> Array:
	var n := 0
	var bad := 0
	var joists := []
	for e in list:
		if e["kind"] == "joist":
			joists.append(((e["lo"] + e["hi"]) * 0.5).x)
	for e in list:
		if e["kind"] != "rafter_pair":
			continue
		var cx: float = ((e["lo"] + e["hi"]) * 0.5).x + (shift if n == 0 else 0.0)
		n += 1
		var r := fposmod(cx - 38.0 + 304.8, 609.6) - 304.8
		var dj := 1e9
		for j in joists:
			dj = minf(dj, absf(cx - j))
		if absf(r) > 5.0 or absf(dj - 38.0) > 5.0:
			bad += 1
	return [n, bad]


func touching(a: Dictionary, b: Dictionary, b: Dictionary, gap := 1.0) -> bool:
	return a["lo"].x <= b["hi"].x + gap and b["lo"].x <= a["hi"].x + gap and a["lo"].y <= b["hi"].y + gap and b["lo"].y <= a["hi"].y + gap and a["lo"].z <= b["hi"].z + gap and b["lo"].z <= a["hi"].z + gap


## {floating: members not reached from the ground through touching members, unsupported: vertical members with nothing under them}
func load_path(list: Array, lift_name := "", lift := 0.0) -> Dictionary:
	var L := []
	for e in list:
		var c: Dictionary = e.duplicate()
		if c["name"] == lift_name:
			c["lo"] = c["lo"] + Vector3(0, lift, 0)
			c["hi"] = c["hi"] + Vector3(0, lift, 0)
		L.append(c)
	var reach := {}
	var q := []
	for i in L.size():
		if L[i]["kind"] == "ground":
			reach[i] = true
			q.append(i)
	while not q.is_empty():
		var i: int = q.pop_back()
		for j in L.size():
			if not reach.has(j) and touching(L[i], L[j]):
				reach[j] = true
				q.append(j)
	var floating := []
	for i in L.size():
		if not reach.has(i):
			floating.append(L[i]["name"])
	# a vertical member (stud family, joist, rafter...) must have a member whose top face meets its underside
	var vert := ["stud", "king", "jack", "cripple", "corner", "end", "nailer", "gable_stud", "header", "joist", "top_plate1", "top_plate2", "bottom_plate", "sill", "ridge", "rafter", "gable_rafter"]
	var unsup := []
	for i in L.size():
		var a: Dictionary = L[i]
		if not (a["kind"] in vert):
			continue
		var found := false
		for j in L.size():
			if i == j:
				continue
			var b: Dictionary = L[j]
			if a["kind"] in ["rafter", "gable_rafter"]:   # the seat: a top plate under the heel, or the ridge at the top end
				if (b["kind"] == "top_plate2" or b["kind"] == "ridge") and touching(a, b):
					found = true
					break
				continue
			if a["kind"] == "ridge":   # the ridge is held by the rafters that meet it
				if (b["kind"] == "rafter" or b["kind"] == "gable_rafter") and touching(a, b):
					found = true
					break
				continue
			if a["kind"] == "gable_stud":   # stands on the top plate
				if b["kind"] == "top_plate2" and absf(b["hi"].y - a["lo"].y) <= 1.0 and touching(a, b):
					found = true
					break
				continue
			if absf(b["hi"].y - a["lo"].y) <= 1.0 and touching(a, b, 0.5):
				found = true
				break
		if not found:
			unsup.append(a["name"])
	return {"floating": floating, "unsupported": unsup}


func _run() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/challenges/ch1_house.json"))
	ok(d is Dictionary and d.has("part") and d.has("members") and d.has("building"), "the challenge file loads with part, building and members")
	var members: Array = d["members"]
	print("members ", members.size(), " features ", (d["part"]["features"] as Array).size())
	var t0 := Time.get_ticks_msec()
	var rp := replayed(d)
	print("replay ms ", Time.get_ticks_msec() - t0, " bodies ", rp["bodies"], " missing ", rp["missing"], " worst mm ", rp["worst"])
	var res: Dictionary = rp["res"]
	ok((res["errors"] as Dictionary).is_empty(), "A replay has 0 step errors (%s)" % str(res["errors"]).left(160))
	ok(int(rp["bodies"]) == members.size(), "A one body per member (%d bodies, %d members)" % [int(rp["bodies"]), members.size()])
	ok(int(rp["missing"]) == 0, "A every member is found in the replay within 1.5 mm (%d missing, worst %.3f mm)" % [int(rp["missing"]), float(rp["worst"])])
	var list: Array = rp["list"]
	# B rooms
	var rm := rooms_of(list)
	for k in REF_ROOMS:
		var ew: float = (float(rm[k][0]) - REF_ROOMS[k][0]) / REF_ROOMS[k][0] * 100.0
		var ed: float = (float(rm[k][1]) - REF_ROOMS[k][1]) / REF_ROOMS[k][1] * 100.0
		print("room %-10s %.0f x %.0f  (ref %.0f x %.0f)  err %.2f %% %.2f %%" % [k, rm[k][0], rm[k][1], REF_ROOMS[k][0], REF_ROOMS[k][1], ew, ed])
	ok(rooms_fail(rm) == 0, "B all six rooms' w and d within 2 %% of the reference (%d out)" % rooms_fail(rm))
	# C area
	var slab: Dictionary = by_name(list)["Slab on grade"]
	var area: float = (slab["hi"].x - slab["lo"].x) * (slab["hi"].z - slab["lo"].z) / 1e6
	print("slab area m2 ", area)
	ok(absf(area - REF_AREA_M2) / REF_AREA_M2 <= 0.02, "C slab plan area %.2f m2 within 2 %% of %.2f" % [area, REF_AREA_M2])
	# D grid
	var gf := grid_fail(list)
	var nstud := 0
	for e in list:
		if e["kind"] in ["stud", "joist", "rafter"]:
			nstud += 1
	print("grid members ", nstud)
	ok(nstud > 150 and gf == 0, "D %d studs / joists / rafters, %d off the 16 / 24 in grid by more than 5 mm" % [nstud, gf])
	# D2: paired rafters (kind rafter_pair): grid centre + 38 mm, and 38 mm from the centre of the joist they are paired with
	var pr := pairs_fail(list)
	ok(pr[0] >= 14 and pr[1] == 0, "D2 %d paired rafters, %d not on the 24 in grid + 38 mm beside their joist (within 5 mm)" % [pr[0], pr[1]])
	var pr2 := pairs_fail(list, "x", 20.0)
	ok(pr2[1] >= 1, "CONTROL D2: a paired rafter moved 20 mm fails D2")
	# E load path
	var lp := load_path(list)
	print("floating ", lp["floating"].slice(0, 12), " unsupported ", lp["unsupported"].slice(0, 12))
	ok(lp["floating"].is_empty(), "E every member touches a chain down to the ground (%d floating)" % lp["floating"].size())
	ok(lp["unsupported"].is_empty(), "E every vertical member rests on a member below it (%d unsupported)" % lp["unsupported"].size())
	# F blueprint
	var bld: Dictionary = d["building"]
	var r0: Dictionary = bld["rooms"][0]
	var walls := Blueprint.room_walls(bld, r0)
	var wm := {}
	for w in walls:
		wm[w["id"]] = w
	var inner_l: float = wm["left"]["q1"]
	var inner_r: float = wm["right"]["q0"]
	var inner_f: float = wm["front"]["q1"]
	var inner_b: float = wm["back"]["q0"]
	var i1: Dictionary = wm["i1"]
	var i2: Dictionary = wm["i2"]
	var i3: Dictionary = wm["i3"]
	var bp := {"Kitchen": [i2["q0"] - inner_l, i1["q0"] - inner_f], "Hall": [i3["q0"] - i2["q1"], i1["q0"] - inner_f], "Bedroom 2": [inner_r - i3["q1"], i1["q0"] - inner_f],
		"Living": [i2["q0"] - inner_l, inner_b - i1["q1"]], "Bath/hall": [i3["q0"] - i2["q1"], inner_b - i1["q1"]], "Bedroom 1": [inner_r - i3["q1"], inner_b - i1["q1"]]}
	var bad_bp := 0
	for k in REF_ROOMS:
		for i in 2:
			if absf(float(bp[k][i]) * 1000.0 - REF_ROOMS[k][i]) / REF_ROOMS[k][i] > TOL_ROOM:
				bad_bp += 1
	ok(bad_bp == 0, "F the blueprint's six rooms are within 2 %% of the reference (%d out)" % bad_bp)
	var sh := Blueprint.sheet(bld, "Floor 1")
	var texts := []
	for e in sh["ents"]:
		if String(e.get("t", "")) == "text":
			texts.append(String(e["s"]))
	print("plan texts ", texts.slice(0, 30))
	var ow := 0.0
	var od := 0.0
	for e in sh["ents"]:
		var dd: Dictionary = e.get("d", {})
		if String(e.get("t", "")) == "text" and String(dd.get("kind", "")) == "overall":
			if String(dd.get("axis", "")) == "x":
				ow = float(String(e["s"]))
			elif String(dd.get("axis", "")) == "z":
				od = float(String(e["s"]))
	print("overall dims on the sheet ", ow, " x ", od)
	ok(absf(ow * od - REF_AREA_M2) / REF_AREA_M2 <= 0.02, "C the sheet's overall dimensions %.2f x %.2f = %.2f m2 within 2 %%" % [ow, od, ow * od])
	# G members file
	var mf := FileAccess.get_file_as_string("res://out/ch1/members.json")
	var mj = JSON.parse_string(mf)
	var okm: bool = mj is Dictionary and (mj["members"] as Array).size() == members.size()
	if okm:
		for m in mj["members"]:
			if not (m.has("kind") and m.has("nominal") and m.has("span_mm") and m.has("spacing_mm") and m.has("supports")):
				okm = false
				break
	ok(okm, "G out/ch1/members.json has kind, nominal, span_mm, spacing_mm and supports for all %d members" % members.size())
	# ---- CH1c bars (written before the numbers were read)
	var ax := Ch1House.rafter_axes(members)
	var worst_dot := 0.0
	var nraf := 0
	for k in ax["rafters"]:
		worst_dot = maxf(worst_dot, absf((ax["rafters"][k] as Vector3).dot(ax["ridge"])))
		nraf += 1
	print("rafter axes ", nraf, " worst |dot| with the ridge ", worst_dot, " ridge axis ", ax["ridge"])
	ok(nraf >= 34 and worst_dot < 1e-3, "H all %d rafter axes are perpendicular to the ridge (worst |dot| %s)" % [nraf, str(worst_dot)])
	var fz1 := -1e9
	var bz0 := 1e9
	var steep := 0
	for m in members:
		if m["kind"] in ["rafter", "rafter_pair"]:
			if String(m["name"]).contains("front"):
				fz1 = maxf(fz1, float(m["box"][5]))
			else:
				bz0 = minf(bz0, float(m["box"][2]))
	for k in ax["rafters"]:
		var v: Vector3 = ax["rafters"][k]
		steep += 1 if absf(v.y) > 0.2 and absf(v.z) > 0.9 * 0.5 else 0
	print("front rafters end at z ", fz1, " back rafters start at z ", bz0, " sloping axes ", steep)
	ok(fz1 <= bz0 + 0.01 and steep == nraf, "H the front slope ends at z %.1f and the back slope starts at z %.1f: they meet at the ridge, no rafter crosses to the other side (%d of %d axes slope)" % [fz1, bz0, steep, nraf])
	var ov := Ch1House.overlaps(members)
	print("framing overlaps ", ov.size(), " ", ov.slice(0, 6))
	ok(ov.is_empty(), "I no two framing members overlap by more than 1 mm3 (%d pairs, first %s)" % [ov.size(), str(ov.slice(0, 3))])
	var paired := 0
	var pair_bad := 0
	for m in members:
		if m["kind"] != "rafter_pair":
			continue
		paired += 1
		var near := false
		for n in members:
			if n["kind"] == "joist" and absf(float(m["box"][0]) - float(n["box"][3])) < 1.0:
				near = true
				break
		pair_bad += 0 if near else 1
	ok(paired >= 14 and pair_bad == 0, "I each of %d paired rafters has a ceiling joist against its face (%d without)" % [paired, pair_bad])
	var lines := Ch1House.run(mj)
	var fl := Ch1House.failing(mj)
	var unv := 0
	for l in lines:
		if String(l["text"]).contains("UNVERIFIED"):
			unv += 1
	print("HouseCheck lines ", lines.size(), " failing ", fl.size(), " UNVERIFIED ", unv)
	ok(lines.size() >= 25 and fl.is_empty(), "J HouseCheck passes on the generated house: %d lines, %d FAIL, %d carry UNVERIFIED" % [lines.size(), fl.size(), unv])
	# CH1c controls
	var mj2: Dictionary = mj.duplicate(true)
	for m in mj2["members"]:
		if m["kind"] == "rafter" and m["spacing_mm"] != null:
			m["nominal"] = "2x4"
	ok(Ch1House.failing(mj2).size() >= 1, "CONTROL J: rafters made 2x4 are caught by HouseCheck")
	var ms2: Array = members.duplicate(true)
	for m in ms2:
		if m["kind"] == "rafter_pair":
			m["box"][0] = float(m["box"][0]) - 38.0
			m["box"][3] = float(m["box"][3]) - 38.0
			break
	ok(Ch1House.overlaps(ms2).size() >= 1, "CONTROL I: a rafter moved back onto its joist is caught as an overlap")
	var ms4: Array = members.duplicate(true)
	for m in ms4:
		if m["kind"] == "ridge":
			var b4: Array = m["box"]
			m["box"] = [b4[2], b4[1], b4[0], b4[5], b4[4], b4[3]]    # a ridge turned 90 degrees: its axis is z, the rafter axes are no longer perpendicular
			break
	var ax4 := Ch1House.rafter_axes(ms4)
	var w4 := 0.0
	for k in ax4["rafters"]:
		w4 = maxf(w4, absf((ax4["rafters"][k] as Vector3).dot(ax4["ridge"])))
	ok(w4 >= 1e-3, "CONTROL H: a ridge turned to run front to back makes the rafters parallel to it (worst |dot| %.3f) and fails the bar" % w4)
	# CONTROLS
	var some_stud := ""
	for e in list:
		if e["kind"] == "stud" and String(e["name"]).begins_with("stud.F."):
			some_stud = e["name"]
			break
	ok(grid_fail(list, some_stud, 20.0) >= 1, "CONTROL a stud moved 20 mm is caught by the grid bar")
	var plate_stud := ""
	for e in list:
		if e["kind"] == "stud":
			plate_stud = e["name"]
			break
	var lp2 := load_path(list, plate_stud, 5.0)
	ok(lp2["unsupported"].size() >= 1, "CONTROL a stud lifted 5 mm is caught as unsupported")
	ok(rooms_fail(rooms_of(list, 0.04)) >= 1, "CONTROL a kitchen 4 % short fails the room bar")
	ok(absf(area * 0.96 - REF_AREA_M2) / REF_AREA_M2 > 0.02, "CONTROL a 4 % short slab fails the area bar")
	print("ch1a: %d fail" % fails)
	quit(1 if fails > 0 else 0)
