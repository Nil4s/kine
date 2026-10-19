## godot --headless --path . -s tests/cross_contact_test.gd     (GATES.md Round 50 TC2)
## BODY-VS-BODY CONTACT: Body.cross_contacts(other, xf). Bars written before measuring:
##  (1) two standing bodies 1.5 m apart facing: 0 contacts; at 0.2 m: torso pairs sink > 1 cm, listed "touch".
##  (2) a staff thrust into the other's chest: a "hit" on the chest; Dummy.touch on the same geometry names the same
##      part and zone.
##  (3) 300 random pose pairs + placements (within 1.2 m): the culled result = brute force (same contact set, same kind,
##      depths within 1 mm); worst printed.
##  (4) mean time per call < 1 ms when apart (> 2 m); mean printed when close; the bodies unchanged (state() equal).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func stand() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b


func rnd_pose(b: Body, rng: RandomNumberGenerator) -> void:
	for j in b.ang.keys():
		if not b.lim.has(j) or j in Body.FINGERS:
			continue
		var L: Dictionary = b.lim[j]
		b.ang[j] = Vector3(rng.randf_range(L["bend"].x, L["bend"].y), rng.randf_range(L["side"].x, L["side"].y),
			rng.randf_range(L["twist"].x, L["twist"].y)) * 0.8
	b.fk()
	b.wep_on = false
	b.wep2_on = false
	var r := rng.randf()
	if r < 0.5:
		var kinds: Array = Body.KINDS.keys()
		kinds.erase("dagger")
		b.set_kind(kinds[rng.randi() % kinds.size()])
		b.wep_on = true
		b.wep_hand = ""
		b.wep_pos = (b.P["pelvis"] as Vector3) + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.0, 0.9), rng.randf_range(-0.6, 0.6))
		b.wep_rot = Quaternion(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf_range(0, TAU))
	if rng.randf() < 0.3:
		b.wep2_on = true
		b.wep2_kind = "dagger"
		b.wep2_hand = "hand_l"
		b.wep2_lpos = Vector3.ZERO
		b.wep2_lrot = Quaternion(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf_range(0, TAU))


## the all-pairs result, no culling at all: {"mine|theirs": depth}
func brute(a: Body, b: Body, xf: Transform3D) -> Dictionary:
	var out := {}
	for pa in a.cross_parts():
		var ca: Array = a.cap(pa)
		for pb in b.cross_parts():
			var cb: Array = b.cap(pb)
			var d: float = float(a.rad[pa]) + float(b.rad[pb]) - Body.seg_seg(ca[0], ca[1], xf * (cb[0] as Vector3), xf * (cb[1] as Vector3))
			if d > Body.CROSS_MIN:
				out[pa + "|" + pb] = d
	return out


func by_key(cs: Array) -> Dictionary:
	var out := {}
	for c in cs:
		out[str(c[0]) + "|" + str(c[1])] = float(c[2])
	return out


func place(d: float, yaw := PI, rng: RandomNumberGenerator = null) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(0, 0, d))


func _init() -> void:
	var A := stand()
	var Bd := stand()
	var dm := Dummy.new()

	# ---- (1)
	dm.place(1.5)
	var far := A.cross_contacts(Bd, dm.xf)
	ok(far.size() == 0, "1: 1.5 m apart, facing: %d contacts" % far.size())
	dm.place(0.2)
	var near := A.cross_contacts(Bd, dm.xf)
	var torso := ["pelvis", "spine_01", "spine_02", "spine_03", "chest_wide", "hips_wide"]
	var deep := 0.0
	var all_touch := true
	var n_torso := 0
	for c in near:
		if c[0] in torso and c[1] in torso:
			n_torso += 1
			deep = maxf(deep, float(c[2]))
			if c[3] != "touch":
				all_touch = false
	print("     at 0.2 m: %d contacts, %d torso pairs, deepest %.1f cm" % [near.size(), n_torso, deep * 100.0])
	ok(n_torso > 0 and deep > 0.01, "1: at 0.2 m torso pairs penetrate > 1 cm (%.1f cm)" % (deep * 100.0))
	ok(n_torso > 0 and all_touch, "1: those torso pairs are listed touch")

	# ---- (2) a staff thrust from A into B's chest
	A.set_kind("staff")
	A.wep_on = true
	A.wep_hand = ""
	dm.place(1.0)
	var chest_y: float = (dm.cap("spine_03")[0] as Vector3).y
	A.wep_rot = Quaternion(Vector3.RIGHT, PI * 0.5)       # the weapon's Y -> +z: thrust forward
	A.wep_pos = Vector3(0.0, chest_y, -0.3)
	var cc := A.cross_contacts(Bd, dm.xf)
	var hits := cc.filter(func(c): return c[3] == "hit")
	var tz: Dictionary = dm.touch(A)
	var best_dz: Array = []   # the deepest hit on a part the Dummy knows (the Dummy has no wide capsules)
	for h in hits:
		if Dummy.ZONES.has(h[1]):
			best_dz = h
			break
	print("     staff thrust: hits=%d, first %s; Dummy.touch: %s" % [hits.size(), str(hits[0]) if hits.size() > 0 else "none", str(tz.get("part", "none")) + "/" + str(tz.get("zone", ""))])
	ok(hits.size() > 0 and Dummy.ZONES.get(hits[0][1], Body.CROSS_WIDE_ZONE.get(hits[0][1], "")) == "CHEST", "2: the staff is a hit on the chest (%s)" % (str(hits[0][1]) if hits.size() > 0 else "none"))
	ok(not tz.is_empty() and not best_dz.is_empty() and best_dz[1] == tz["part"] and best_dz[4] == tz["zone"], "2: same part and zone as Dummy.touch (%s %s)" % [str(best_dz[1]) if not best_dz.is_empty() else "-", str(best_dz[4]) if not best_dz.is_empty() else "-"])
	var dd := absf(float(best_dz[2]) - float(tz["depth"])) if not best_dz.is_empty() and not tz.is_empty() else 1.0
	ok(dd < 0.0005, "2: same depth as Dummy.touch within 0.5 mm (%.4f mm apart)" % (dd * 1000.0))
	# a staff on a forearm is a hit with the arm zone; two staves crossing are a clash; forearm on forearm a block
	var Bw := stand()
	Bw.set_kind("staff")
	Bw.wep_on = true
	Bw.wep_hand = ""
	Bw.wep_rot = Quaternion(Vector3.RIGHT, PI * 0.5)
	Bw.wep_pos = Vector3(0, chest_y, 0.0)
	var kinds_seen := {}
	for c in A.cross_contacts(Bw, Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1.0))):
		kinds_seen[c[3]] = true
	ok(kinds_seen.has("clash"), "2: staff against staff is a clash (kinds %s)" % str(kinds_seen.keys()))
	A.wep_on = false

	# ---- (3) + (4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	var worst := 0.0
	var set_diff := 0
	var mism_kind := 0
	var total := 0
	var max_reach := 0.0
	var a_close := []
	var kinds_total := {}
	for i in 300:
		var a := stand()
		var b := stand()
		rnd_pose(a, rng)
		rnd_pose(b, rng)
		var rr := 1.2 * sqrt(rng.randf())
		var th := rng.randf() * TAU
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(rr * cos(th), 0, rr * sin(th)))
		var cut := a.cross_contacts(b, xf)
		var bf := brute(a, b, xf)
		var ck := by_key(cut)
		total += bf.size()
		for k in bf:
			if not ck.has(k):
				set_diff += 1
			else:
				worst = maxf(worst, absf(float(ck[k]) - float(bf[k])))
		for k in ck:
			if not bf.has(k):
				set_diff += 1
		for c in cut:
			kinds_total[c[3]] = int(kinds_total.get(c[3], 0)) + 1
			if c[3] != Body.cross_kind(c[0], c[1]):
				mism_kind += 1
		# the body sphere bound: the farthest capsule surface from the pelvis, both bodies
		for body in [a, b]:
			for cp in body.cross_caps():
				if not Body.is_wep(cp[0]):
					max_reach = maxf(max_reach, (cp[4] as Vector3).distance_to(body.P["pelvis"]) + float(cp[5]))
		a_close.append([a, b, xf])
	print("     contacts over 300 pairs: %d, kinds %s" % [total, str(kinds_total)])
	ok(total > 300, "3: the random pairs overlap often enough to mean something (%d brute-force contacts)" % total)
	ok(set_diff == 0, "3: culled contact set = brute force (%d differences)" % set_diff)
	ok(worst < 0.001, "3: depths within 1 mm of brute force (worst %.6f mm)" % (worst * 1000.0))
	ok(mism_kind == 0, "3: every contact's kind follows cross_kind (%d off)" % mism_kind)
	ok(max_reach < Body.CROSS_BODY_R, "3: the body sphere radius %.2f m covers the farthest capsule seen (%.3f m)" % [Body.CROSS_BODY_R, max_reach])

	# (4) speed + purity
	var unchanged := true
	var t_close := 0
	for e in a_close:
		var s0 := var_to_str([e[0].state(), e[1].state(), e[0].P, e[1].P])
		var t0 := Time.get_ticks_usec()
		e[0].cross_contacts(e[1], e[2])
		t_close += Time.get_ticks_usec() - t0
		if var_to_str([e[0].state(), e[1].state(), e[0].P, e[1].P]) != s0:
			unchanged = false
	var t_far := 0
	for e in a_close:
		var xf2: Transform3D = e[2]
		var dir := Vector3(xf2.origin.x, 0, xf2.origin.z)
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.RIGHT
		xf2.origin = Vector3(0, 0, 0) + dir * (4.0 + rng.randf() * 2.0)
		var t0 := Time.get_ticks_usec()
		var res: Array = (e[0] as Body).cross_contacts(e[1], xf2)
		t_far += Time.get_ticks_usec() - t0
		if res.size() != 0:
			unchanged = false
	var mean_close := float(t_close) / 300.0 / 1000.0
	var mean_far := float(t_far) / 300.0 / 1000.0
	print("     mean per call: apart (> 2 m) %.4f ms, close (< 1.2 m) %.3f ms" % [mean_far, mean_close])
	ok(mean_far < 1.0, "4: apart, the broad phase rejects in < 1 ms (%.4f ms)" % mean_far)
	ok(unchanged, "4: bodies unchanged after the calls (state() and P equal; 0 contacts when apart)")
	print("     (info) close mean %.3f ms, bar not set" % mean_close)

	print("cross_contact: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
