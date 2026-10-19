## godot --headless --path . -s tests/actors_file_test.gd     (TWO-CHARACTER G1: the scene FILE format)
## A scene file may hold "actors": [{"name", "xf": {"pos": [x, z], "yaw"}, "scene": {a full scene}}] (the top level is actor 0).
## Bars: 1 a two-actor file survives from_dict -> to_dict unchanged; 2 every scene file of Nick's loads and saves as it
## was (the new key changed nothing for one-actor files); 3 the schema accepts it and rejects a misspelled key inside an
## actor; 4 Mirror twice is the original, once negates actor 1's x and yaw; 5 clone() is deep.
extends SceneTree

var fails := 0
var B: Body
var one_way := false   # bar 2: keys to_dict adds with a default are not differences


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func read(p: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(p))


## JSON text as it would be on disk (sorted keys, floats as they print), so 0.1f and 0.1 compare as the file does
func norm(d: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(d, "", true))


## the first difference between two values, as a path ("" = none)
func first_diff(a: Variant, b: Variant, path := "$", tol := 0.0, skip := []) -> String:
	if a is Dictionary and b is Dictionary:
		for k in a:
			if k in skip:
				continue
			if not b.has(k):
				return "%s.%s only in A" % [path, k]
			var r := first_diff(a[k], b[k], path + "." + String(k), tol, skip)
			if r != "":
				return r
		for k in b:
			if not a.has(k) and not k in skip and not one_way:
				return "%s.%s only in B" % [path, k]
		return ""
	if a is Array and b is Array:
		if a.size() != b.size():
			return "%s size %d vs %d" % [path, a.size(), b.size()]
		for i in a.size():
			var r := first_diff(a[i], b[i], path + "[%d]" % i, tol, skip)
			if r != "":
				return r
		return ""
	if typeof(a) != typeof(b) and not (a is float or a is int) and not (b is float or b is int):
		return "%s type %s vs %s" % [path, typeof(a), typeof(b)]
	if (a is float or a is int) and (b is float or b is int):
		return "" if (absf(float(a) - float(b)) <= tol if tol > 0.0 else JSON.stringify(a) == JSON.stringify(b)) else "%s %s vs %s" % [path, a, b]
	return "" if a == b else "%s %s vs %s" % [path, a, b]


func rt(d: Dictionary) -> Dictionary:
	var S := Scene.new()
	S.from_dict(d)
	var keep := B.state()
	var out: Dictionary = norm(S.to_dict(B))
	B.set_state(keep)
	return out


func _init() -> void:
	B = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")

	# a two-actor file: actor 0 = combo3, actor 1 = a mirrored copy of swing_back (read only), at (1.5, 0) facing back
	var hero := rt(read("res://scenes/combo3.json"))
	var other := rt(read("res://scenes/swing_back.json"))
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var mir: Dictionary = norm(Scene.mirror_file(other, M))
	var two: Dictionary = hero.duplicate(true)
	two["actors"] = [{"name": "B", "xf": {"pos": [1.5, 0.0], "yaw": 180.0}, "scene": mir}]

	# 1 round trip
	var back := rt(two)
	var d1 := first_diff(two, back)
	ok(d1 == "" and back.has("actors") and back["actors"].size() == 1 and back["actors"][0]["xf"]["yaw"] == 180.0 and back["actors"][0]["scene"]["scene"] == "swing_back_mirrored",
		"1 two-actor dict: from_dict -> to_dict identical (%d chars of JSON; first difference: %s)" % [JSON.stringify(two).length(), d1 if d1 != "" else "none"])

	# 2 every file of Nick's, one actor, saves as it was
	var files := []
	for dir in ["res://scenes/", "res://scenes/_wip/", "res://scenes/_archive/"]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				files.append(dir + f)
	var differ := []
	for p in files:
		var orig := read(p)
		# the files predate this round: "plan" is provenance to_dict never writes, bad_frames is recomputed by the current
		# collision code, and a key an old file lacks (floor_body) is added by to_dict with its default. Neither is the
		# new key's doing: every OTHER key the file holds must come back equal, and no "actors" may appear
		one_way = true
		var back1 := rt(orig)
		var df := first_diff(norm(orig), back1, "$", 0.0, ["plan", "bad_frames", "length_s", "note", "arrive_s", "leave_s"])
		one_way = false
		if df == "" and back1.has("actors"):
			df = "an \"actors\" key appeared"
		if df != "":
			differ.append("%s: %s" % [p.get_file(), df])
	ok(files.size() > 10 and differ.is_empty(), "2 %d scene files (scenes/, _archive/): load -> to_dict equals the file on every key it holds (plan, note and the derived length_s, arrive_s, leave_s, bad_frames aside; keys an old file lacks are not compared); %d differ %s" % [files.size(), differ.size(), differ.slice(0, 4)])
	ok(not rt(read("res://scenes/combo3.json")).has("actors"), "2b a one-actor scene writes no \"actors\" key")

	# 3 schema
	var errs := Validate.data(two)
	ok(errs.is_empty(), "3 the two-actor file validates against docs/scene.schema.json (%d errors %s)" % [errs.size(), errs.slice(0, 2)])
	var bad: Dictionary = two.duplicate(true)
	bad["actors"][0]["xff"] = bad["actors"][0]["xf"]
	bad["actors"][0].erase("xf")
	var e2 := Validate.data(bad)
	ok(not e2.is_empty(), "3b a misspelled key inside an actor (\"xff\") is rejected (%d errors, first: %s)" % [e2.size(), e2[0] if e2.size() > 0 else "-"])
	var bad2: Dictionary = two.duplicate(true)
	bad2["actors"][0]["scene"]["cards"][0]["hold"] = -1.0
	var e3 := Validate.data(bad2)
	ok(not e3.is_empty() and "actors[0].scene.cards[0]" in String(e3[0]["path"]), "3c a bad card INSIDE an actor's scene is rejected at its path (%s)" % [e3[0]["path"] if e3.size() > 0 else "-"])

	# 4 mirror
	var m1: Dictionary = norm(Scene.mirror_file(two, M))
	var m2: Dictionary = norm(Scene.mirror_file(m1, M))
	var d4 := first_diff(norm(two), m2, "$", 0.011, ["contacts"])   # the poses go through float32 and a reflection: within 0.011 (mirror_list_test: 0.01 deg)
	ok(d4 == "", "4 mirrored twice: the two-actor scene is back, deep equal within 0.011 of a degree or a unit, the measured contacts aside (first difference: %s)" % [d4 if d4 != "" else "none"])
	var x0: float = two["actors"][0]["xf"]["pos"][0]
	var x1: float = m1["actors"][0]["xf"]["pos"][0]
	ok(is_equal_approx(x1, -x0) and is_equal_approx(m1["actors"][0]["xf"]["yaw"], -180.0) and m1["actors"][0]["xf"]["pos"][1] == two["actors"][0]["xf"]["pos"][1]
		and m1["actors"][0]["scene"]["scene"] == "swing_back", "4b mirrored once: actor 1's x %.2f -> %.2f, yaw %.0f -> %.0f, z kept, its scene mirrored (%s)" % [x0, x1, two["actors"][0]["xf"]["yaw"], m1["actors"][0]["xf"]["yaw"], m1["actors"][0]["scene"]["scene"]])

	# 5 clone
	var S := Scene.new()
	S.from_dict(two)
	var C := S.clone()
	C.actors[0]["scene"].cards[0]["name"] = "zz_edited"
	C.actors[0]["xf"]["pos"][0] = 9.0
	C.actors[0]["scene"].cards[0]["pose"] = {}
	ok(C.actors.size() == 1 and S.actors[0]["scene"].cards[0]["name"] != "zz_edited" and S.actors[0]["xf"]["pos"][0] == 1.5 and not S.actors[0]["scene"].cards[0]["pose"].is_empty(),
		"5 clone() is deep: editing the clone's actor 1 (card name, pose, xf) leaves the original (name %s, x %s)" % [S.actors[0]["scene"].cards[0]["name"], S.actors[0]["xf"]["pos"][0]])

	print("ACTORS FILE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
