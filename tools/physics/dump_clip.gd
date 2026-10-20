## godot --headless --path . -s tools/physics/dump_clip.gd -- scenes/<name>.json out.json [fps]
## Resolves a scene's cards to per-frame joint rotations (read only): ang[j] = (bend, side, twist) deg, pelvis position, and the
## weapon's world knob position + rotation with the holding hand's world frame, sampled the way tools/export_bvh.gd does.
extends SceneTree


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(a[0])))
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var fps := int(a[2]) if a.size() > 2 else 60
	var n := int(ceil(S.length() * fps - 1e-6)) + 1
	var frames := []
	var times: Array = S.times()
	for i in n:
		var t := minf(float(i) / fps, S.length())
		S.apply(B, t)
		B.fk()
		var ang := {}
		for j in Body.ORDER:
			var v: Vector3 = B.ang[j]
			ang[j] = [v.x, v.y, v.z]
		var pp: Vector3 = B.P["pelvis"]
		var f := {"t": t, "pelvis": [pp.x, pp.y, pp.z], "ang": ang, "wep_on": B.wep_on}
		if B.wep_on:
			var x: Array = B.wep_xform()
			var kn: Vector3 = x[0]
			var hand: String = B.wep_hand if B.wep_hand != "" else "hand_r"
			var q: Quaternion = x[1]
			var gh: Quaternion = B.G[hand]
			var ph: Vector3 = B.P[hand]
			f["wep"] = {"kind": B.wep_kind, "len": B.wep_len, "hand": hand, "knob": [kn.x, kn.y, kn.z], "rot": [q.x, q.y, q.z, q.w],
				"hand_P": [ph.x, ph.y, ph.z], "hand_G": [gh.x, gh.y, gh.z, gh.w]}
		frames.append(f)
	var cards := []
	for i in S.cards.size():
		cards.append({"name": S.cards[i]["name"], "t": times[i][1]})
	var fa := FileAccess.open(a[1], FileAccess.WRITE)
	fa.store_string(JSON.stringify({"fps": fps, "scene": a[0], "cards": cards, "frames": frames}))
	fa.close()
	print("%s: %d frames at %d fps, weapon on in %d" % [a[0], n, fps, frames.filter(func(f): return f["wep_on"]).size()])
	quit(0)
