## godot --headless --path . -s tests/breath_test.gd     (round 43, GATES YY6)
## BREATH against people (Massaroni et al. 2015: chest wall surface 1-8 mm in quiet breathing, 0.17-0.33 Hz = 10-20 a
## minute). Bars:
##   1 the front of the chest (the chest capsule's surface, straight ahead of its middle) moves 3-7 mm at full inhale
##     (people 1-8; aimed at 5), and back to where it was (1e-6 m) at full exhale.
##   2 the period: at 15 a minute the chest is fully in at 2 s and out at 4 s (one breath = 60 / rate s).
##   3 the head keeps its angle (the neck turns the chest's lean back): its world turn within 0.05 deg; the head moves
##     < 6 mm (printed), the feet do not move (1e-9 m).
##   4 off = nothing: breath 0 leaves every angle bit for bit.
##   5 files: every scene in scenes/ saves byte for byte as it loads (no "breath" key written while off); a scene with
##     breath on writes it and reads it back.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the front of the chest: the chest capsule's middle, pushed forward (+z at rest, turned with the chest) by its radius
func chest_front(B: Body) -> Vector3:
	var c: Array = B.cap("spine_03")
	var mid: Vector3 = (c[0] + c[1]) * 0.5
	return mid + (B.G["spine_03"] as Quaternion) * Vector3(0, 0, B.rad["spine_03"])


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var base: Dictionary = B.ang.duplicate()
	var f0 := chest_front(B)
	var h0: Vector3 = B.P["head"]
	var hq0: Quaternion = B.G["head"]
	var foot0: Vector3 = B.P["foot_r"]
	B.breathe(2.0, 15.0)   # 15 a minute: fully in at 2 s
	var mm := (chest_front(B) - f0).length() * 1000.0
	var head_mm := ((B.P["head"] as Vector3) - h0).length() * 1000.0
	var head_deg := rad_to_deg(hq0.angle_to(B.G["head"]))
	var feet := ((B.P["foot_r"] as Vector3) - foot0).length()
	for j in base:
		B.ang[j] = base[j]
	B.breathe(4.0, 15.0)   # fully out at 4 s
	var out_mm := (chest_front(B) - f0).length() * 1000.0
	ok(mm >= 3.0 and mm <= 7.0 and out_mm < 1e-3, "1 the front of the chest moves %.2f mm at full inhale (people 1-8, aimed at 5) and %.4f mm at full exhale" % [mm, out_mm])
	ok(absf(Body.breath_at(2.0, 15.0) - 1.0) < 1e-9 and Body.breath_at(4.0, 15.0) < 1e-9 and absf(Body.breath_at(2.0, 20.0) - Body.breath_at(5.0, 20.0)) < 1e-9,
		"2 the period: 15 a minute = in at 2 s, out at 4 s; 20 a minute repeats every 3 s")
	ok(head_deg < 0.05 and head_mm < 6.0 and feet < 1e-9, "3 the head keeps its angle (%.4f deg), moves %.2f mm; the feet %.9f m" % [head_deg, head_mm, feet])
	for j in base:
		B.ang[j] = base[j]
	B.breathe(2.0, 0.0)
	var same := true
	for j in base:
		same = same and B.ang[j] == base[j]
	ok(same, "4 off (0 a minute): every angle bit for bit")
	var bad := []
	var n := 0
	for f in DirAccess.get_files_at("res://scenes"):
		if not f.ends_with(".json"):
			continue
		var raw := FileAccess.get_file_as_string("res://scenes/" + f)
		var d = JSON.parse_string(raw)
		if not (d is Dictionary) or not d.has("cards"):
			continue
		var S := Scene.new()
		S.from_dict(d)
		n += 1
		if S.breath != 0.0 or d.has("breath"):
			bad.append(f)
	var S2 := Scene.new()
	S2.breath = 14.0
	var B2 := Body.new()
	B2.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B2.fk()
	S2.add("a", B2.to_dict())
	var dd := S2.to_dict(B2)
	var S3 := Scene.new()
	S3.from_dict(JSON.parse_string(JSON.stringify(dd)))
	var S4 := Scene.new()
	S4.add("a", B2.to_dict())
	ok(bad.is_empty() and n > 5 and dd.get("breath", 0.0) == 14.0 and S3.breath == 14.0 and not S4.to_dict(B2).has("breath"),
		"5 files: %d scenes load with breathing off and none holds the key %s; on writes \"breath\": 14 and reads it back; off writes nothing" % [n, bad])
	print("BREATH TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
