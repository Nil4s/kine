extends SceneTree
## BAKE A SCENE FOR THE GAME (Nick 10-13: "those scenes don't run on our engine?"). Plays a scene at `fps` and writes,
## per frame, every body joint's turn A (Body.compose: the joint's rotation from rest, in rest axes, chained
## G[j] = G[parent] * A[j]) and the hips' offset (character space, m). The game rebuilds each bone's local rotation on
## ITS OWN skeleton:   local(j) = R_rest(parent)^-1 * A(j) * R_rest(j)     (R_rest = the bone's rest rotation in model
## space), so any UAL-rigged body plays it (MATH.md "Bake for the game"). Fingers are baked too (the grip).
##   godot --headless --path . -s tools/bake_scene.gd -- scenes/x.json out.json [fps=30] [--landed D]
## G per frame too (each joint's turn from rest in the world): the game's check compares its bones against it.
## --grounded: each frame the whole body drops (or rises) till its lowest point (any capsule, fingers aside) is on the
## floor; for moves that always touch it (the get-ups: between two keys the blend can lift the body off the street).
## --landed D: the solid-dummy version at D m (the impact + rebound), as the poser plays it with the dummy on.
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://" + a[0])))
	var fps := 30
	if a.size() > 2 and not String(a[2]).begins_with("--"):
		fps = int(a[2])
	var k := a.find("--landed")
	if k >= 0:
		var T := Dummy.new()
		T.place(float(a[k + 1]))
		S = T.landed(S, B)[0]
	var grounded := a.has("--grounded")
	var n := int(ceil(S.length() * fps)) + 1
	var frames := []
	for f in n:
		S.apply(B, minf(float(f) / fps, S.length()))
		if grounded:
			_ground(B)
		var js := {}
		var gs := {}
		for j in Body.ORDER:
			js[j] = Body._q(B.compose(j, B.ang[j]))
			gs[j] = Body._q(B.G[j])
		var fr := {"offset": Body._p(B.offset), "A": js, "G": gs}
		if B.wep_on:
			var x := B.wep_xform()
			fr["weapon"] = {"knob": Body._p(x[0]), "rot": Body._q(x[1])}
		frames.append(fr)
	var sk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/skeleton.json"))
	var out := {"name": S.name, "fps": fps, "length": S.length(), "source": a[0],
		"pelvis_rest_y": sk["joints"]["pelvis"]["pos"][1], "grounded": grounded,
		"_note": "poser bake (tools/bake_scene.gd): per frame A = each joint's turn from rest in rest axes (quaternion x,y,z,w), offset = the hips' move from rest (m, character space +Y up +Z forward +X his left). Game: local = R_rest(parent)^-1 * A * R_rest(j).",
		"frames": frames}
	# the weapon, rigid in its hand (Body.lock_weapon): its place in the hand's frame (lrot = G[h]^-1 * rot,
	# lpos = G[h]^-1 * (knob - P[h])), its kind and length; the game hangs a mesh on that hand bone
	S.apply(B, 0.0)
	if B.wep_on and B.wep_hand != "":
		out["weapon"] = {"kind": B.wep_kind, "length": B.wep_len, "hand": B.wep_hand, "lpos": Body._p(B.wep_lpos), "lrot": Body._q(B.wep_lrot)}
	FileAccess.open(a[1], FileAccess.WRITE).store_string(JSON.stringify(out))
	print("BAKED %s: %d frames at %d fps, %.2f s -> %s" % [S.name, n, fps, S.length(), a[1]])
	quit()


## the lowest point of the whole body on the floor (each capsule's ends minus its radius; fingers skipped)
func _ground(B: Body) -> void:
	B.fk()
	var low := INF
	for j in Body.ORDER:
		if j.begins_with("thumb") or j.begins_with("index") or j.begins_with("middle") or j.begins_with("ring") or j.begins_with("pinky"):
			continue
		var r: float = float(B.rad.get(j, 0.03))
		low = minf(low, minf((B.P[j] as Vector3).y, (B.E[j] as Vector3).y) - r)
	B.offset.y -= low
	B.fk()
