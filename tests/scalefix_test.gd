extends SceneTree
## godot --headless --path . -s tests/scalefix_test.gd   (CH15 gaps G27, G28, G29 in docs/CHALLENGE_FEEDBACK.md: Part at building scale)
## Bars (written before the first run):
##  1 MESH SCALE   a hand-sized part keeps the full detail deflection exactly (0.3 mm); a 28 m containment-like shell gets a size-scaled one
##                 (DEFL_PER_R x rms radius, about 1.4 cm), builds through Assembly.built in under 30 s with its volume within 0.5 pct of
##                 the closed form. CONTROL: the shell's rms radius read by fine_defl is the sphere's radius within 1 pct (the size
##                 estimate is real, not a constant).
##  2 SPLIT SCALE  a Split through the centre of a 56 m sphere gives two bodies of half the volume each (0.1 pct). CONTROL: the old
##                 fixed 20 m half-space box, used the same way, does NOT give halves (it bit a hole).
##  3 CUT FAILS    a cut the kernel refuses is the step's error with the body named, not a silent skip: _cut_failed_words names
##                 the bodies, and is empty when none failed; a real Part with a cut that cannot be made (a zero-size tool) reports an
##                 error on that step or leaves the body exactly as it was.
var fails := 0
const KCad := preload("res://scripts/kcad.gd")


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func sphere_rec(r_mm: float, cut_r := 0.0, split := false) -> Dictionary:
	var fs := [{"t": "prim", "id": "f1", "name": "P1", "kind": "sphere", "op": "new", "x": 0.0, "y": 0.0, "z": 0.0, "r": r_mm}]
	if cut_r > 0.0:
		fs.append({"t": "prim", "id": "f2", "name": "P2", "kind": "sphere", "op": "cut", "into": 0, "x": 0.0, "y": 0.0, "z": 0.0, "r": cut_r})
	if split:
		fs.append({"t": "split", "id": "f3", "name": "Split", "plane": "top", "at": 0.0, "keep": 0})
	var r := Part.make("scale")
	r["features"] = fs
	r["seq"] = fs.size()
	return r


func _init() -> void:
	if not Part.available():
		ok(false, "KineCAD is missing")
		quit(1)
		return
	# 1
	var small := Part.replay(sphere_rec(25.0), -1, {"keep": true})
	var sid := int((small["ids"] as Array)[0])
	ok(Part.fine_defl(sid) == Part.FINE_DEFL, "1 a 50 mm sphere keeps the full-detail deflection %.4f mm" % (Part.fine_defl(sid) * 1000.0))
	Part.release_kept(small["ids"])
	var shell_rec := sphere_rec(28000.0, 27962.0)
	var kept := Part.replay(shell_rec, -1, {"keep": true})
	var bid := int((kept["ids"] as Array)[0])
	var fd := Part.fine_defl(bid)
	var r_est := fd / Part.DEFL_PER_R
	ok(absf(r_est - 28.0) / 28.0 < 0.01 and fd > 0.01, "1 CONTROL the 28 m shell's size estimate is %.3f m (sphere 28 m), deflection %.1f mm" % [r_est, fd * 1000.0])
	Part.release_kept(kept["ids"])
	var t0 := Time.get_ticks_msec()
	var b := Assembly.built(shell_rec)
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	var want := 4.0 / 3.0 * PI * (pow(28.0, 3) - pow(27.962, 3))
	var vol: float = b["volume"]
	var nv := 0
	if b["mesh"] != null:
		nv = ((b["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	ok(b["mesh"] != null and secs < 30.0 and absf(vol - want) / want < 0.005, "1 the 28 m shell builds in %.1f s (%d verts), volume %.2f m3 vs %.2f" % [secs, nv, vol, want])
	# 2
	var sp := Part.replay(sphere_rec(28000.0, 0.0, true), -1, {"keep": true})
	var ids: Array = sp.get("ids", [])
	var half := 4.0 / 3.0 * PI * pow(28.0, 3) / 2.0
	var halves_ok := ids.size() == 2
	var vols := []
	for i in ids:
		var v := KCad.volume(int(i))
		vols.append(v)
		halves_ok = halves_ok and absf(v - half) / half < 0.001
	ok(halves_ok, "2 split of a 56 m sphere: %d bodies %s m3 (half %.1f)" % [ids.size(), str(vols), half])
	Part.release_kept(ids)
	var s := KCad.sphere(28.0)
	var old := Part._half(Vector3.ZERO, Vector3.UP, 20.0)
	var a := KCad.intersect(s, old)
	var va := KCad.volume(a) if a != 0 else 0.0
	ok(absf(va - half) / half > 0.01, "2 CONTROL the old 20 m half-space keeps %.1f m3 of the upper half %.1f (not a half)" % [va, half])
	for x in [s, old, a]:
		if x != 0:
			KCad.release(x)
	# 3
	ok(Part._cut_failed_words([]) == "" and Part._cut_failed_words(["Body2"]).contains("Body2"), "3 a refused cut names its body: '%s'" % Part._cut_failed_words(["Body2"]))
	var bad := sphere_rec(25.0)
	(bad["features"] as Array).append({"t": "prim", "id": "f2", "name": "P2", "kind": "box", "op": "cut", "into": 0, "x": 0.0, "y": 0.0, "z": 0.0, "w": 0.0, "h": 0.0, "d": 0.0})
	bad["seq"] = 2
	var rb := Part.replay(bad, -1, {})
	var errs: Dictionary = rb.get("errors", {})
	var v_full := 4.0 / 3.0 * PI * pow(0.025, 3)
	ok(errs.has("f2") or absf(float(rb.get("volume", 0.0)) - v_full) / v_full < 1e-3, "3 a zero-size cut tool: error %s or the body unchanged (%.3e vs %.3e m3)" % [str(errs.get("f2", "none")), float(rb.get("volume", 0.0)), v_full])
	print("scalefix: %d fail" % fails)
	quit(1 if fails > 0 else 0)
