## godot --headless --path . -s tools/make_templates.gd [-- walk run ...]   -> templates/<name>.json
## THE FIVE STARTING SCENES (ROADMAP 44): walk, run, jump, punch, sword swing. Each is written as a PLAN (clips that say only
## what changes, as tools/cook.gd does, minus the bat reach) and baked into a scene file the app copies into scenes/_wip.
## The numbers each one is built to, and the real data they come from, are in the comments at each plan and are CHECKED by
## tests/templates_test.gd (the build of each template, measured).
##   "set": {joint: [bend, side, twist]}  absolute angles     "hips": [x, 0, z]  where the body stands (m)
##   "steps": {"_l": [x, 0, z]}  that foot steps by that much  "heel_up": ["_r"], "heel_deg"   "lift"  the stepping foot's rise (m)
##   "air": true  the card is in the flight        "walk": true  the hips' travel is one curve through the run of cards
##   "fist": ["l"] / "open" / "relaxed": a hand's shape        "move", "hold": seconds
extends SceneTree

const LEGS := ["foot_l", "foot_r", "ball_l", "ball_r"]
const Plans := preload("res://tools/template_plans.gd")


static func _v(a) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## the plan of a template (see the plans below)
static func plan(nm: String) -> Dictionary:
	return Plans.get_plan(nm)


## a plan baked: the scene file's dictionary, plus the report lines the tool prints
static func bake(p: Dictionary, report := []) -> Dictionary:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://" + String(p.get("base", "poses/stand.json")))))
	if B.wep_on:
		B.unlock_weapon()
	if p.has("weapon"):
		var w: Dictionary = p["weapon"]
		B.set_kind(String(w["kind"]))
		B.set_weapon_len(float(w["len"]))
		B.weapon_to_hand(String(w["hand"]))
		B.elbow_low = float(p.get("elbow_low", 0.0))
	var S := Scene.new()
	S.name = p["name"]
	S.spline = bool(p.get("spline", false))
	S.floor_body = bool(p.get("floor_body", false))   # a fall: the whole body's lowest point is on the floor (the get-ups do the same)
	S.pin = bool(p.get("pin", true))                  # a fall: no planted feet (a planted leg holds the body up off the floor it lies on)
	var hips := Vector3.ZERO
	var marks := {}
	var last := {}
	if p.has("rise"):
		# the sit-down: scripts/rise.gd's keys played backwards, on a chair at the origin (the set is the scene's own props)
		S.props = [Props.make("chair", Props.xf_at(Vector3.ZERO, 0.0))]
		var r := Rise.sit_down(B, S.props[0])
		var i := 0
		for c in r["cards"]:
			S.add(c["name"], c["pose"])
			var cd: Dictionary = S.cards[-1]
			cd["move"] = float(p.get("move_of", {}).get(i, p["move"])) if i > 0 else -1.0   # "move_of": {card: s} slows one move
			cd["hold"] = float(p.get("hold0", 0.4)) if i == 0 else (0.6 if i == (r["cards"] as Array).size() - 1 else 0.0)
			cd["steps"] = {}
			cd["plant"] = c["plant"]
			if i >= int(p.get("flow_from", 99)) and i < (r["cards"] as Array).size() - 1:
				cd["flow"] = true   # a pass-through key from this card on: the speed carries on through it (no stop between two fast moves: HITCH)
			i += 1
		report.append("  Rise.sit_down: %d cards, seat-off margin %.1f cm, miss_max %.4f" % [i, float(r["report"]["margin_off"]) * 100.0, float(r["report"]["miss_max"])])
	for c in p["clips"]:
		for j in B.ang.keys():   # every clip is absolute: all body joints back to rest, the hands' fingers kept
			if not (String(j).begins_with("thumb") or String(j).begins_with("index") or String(j).begins_with("middle") or String(j).begins_with("ring") or String(j).begins_with("pinky")):
				B.ang[j] = Vector3.ZERO
		for j in c.get("set", {}):
			B.ang[j] = B.clamp_ang(j, _v(c["set"][j]))
		for j in c.get("add", {}):
			B.ang[j] = B.clamp_ang(j, B.ang[j] + _v(c["add"][j]))
		B.offset = Vector3.ZERO
		if c.has("hips"):
			hips = _v(c["hips"])
		B.offset = Vector3(hips.x, 0.0, hips.z)
		B.fk()
		for kind in ["fist", "open", "relaxed"]:
			for k in c.get(kind, []):
				B.hand_shape(k, kind)
		for sd in ["_l", "_r"]:
			if not sd in c.get("free_feet", []):   # a foot in the air keeps the ankle the card gives it
				B.flat_foot(sd)
		for sd in c.get("heel_up", []):
			B.set_ang("foot" + sd, B.ang["foot" + sd] + Vector3(-float(c.get("heel_deg", 25.0)), 0, 0))
			B.toes_flat(sd)
		for sd in c.get("toes_up", []):
			B.set_ang("foot" + sd, B.ang["foot" + sd] + Vector3(float(c.get("toes_deg", 20.0)), 0, 0))
		B.ground()
		if c.has("y"):
			B.offset.y = float(c["y"])   # the hips' height, absolute (offset.y: standing is -0.014)
			B.fk()
		if c.has("drop"):
			B.offset.y -= float(c["drop"])   # the hips lower (bent knees): the legs below are re-solved onto their marks
			B.fk()
		var plant: Dictionary = c.get("plant", {}).duplicate()
		if c.get("keep_feet", false):
			for sd in ["_l", "_r"]:
				plant[sd] = marks[sd]   # "keep_feet": both toe bases go back to where the first card stood
		if c.get("keep_now", false):
			for sd in ["_l", "_r"]:
				plant[sd] = last[sd]    # "keep_now": both toe bases stay where the card before left them (as the bake placed them)
		for sd in c.get("step", {}):
			var st: Array = c["step"][sd]   # "step": {"_r": [x, 0, z]}: that foot steps by this much from its first-card mark
			plant[sd] = [float(marks[sd][0]) + float(st[0]), float(marks[sd][1]) + float(st[2]), float(marks[sd][2])]
		for sd in plant:
			# "plant": {"_r": [x, z]}  that foot's toe base goes to this world mark (the leg alone is solved), heading 0
			var m: Array = plant[sd]
			var up: bool = sd in c.get("heel_up", [])
			B.plant(sd, Vector3(float(m[0]), (B.p0["ball" + sd] as Vector3).y, float(m[1])), float(m[2]) if m.size() > 2 else float(c.get("head", 0.0)), not up)
			if up:
				B.toes_flat(sd)
		for sd in ["_l", "_r"]:
			last[sd] = [(B.P["ball" + sd] as Vector3).x, (B.P["ball" + sd] as Vector3).z, B.foot_heading(sd)]   # where the feet stand after this card (keep_now)
		if B.wep_on:
			# the weapon hand reaches `hand` (metres in the chest's frame: from spine_03, +x his left, +y up, +z the way the
			# chest faces) with the blade along `aim` (tools/cook.gd's reach), the other hand follows onto the grip
			if c.has("hand") or c.has("aim"):
				var at := Vector3.ZERO
				if c.has("hand"):
					at = (B.P["spine_03"] as Vector3) + (B.G["spine_03"] as Quaternion) * _v(c["hand"])
				B.roll_free = S.cards.is_empty()
				B.sweep_bat_arm(at, _v(c.get("aim", [0, 1, 0])), c.has("hand"), c.has("aim"), float(c.get("aim_weight", p.get("aim_weight", 0.15))))
			B.apply_grip()
		if S.cards.is_empty():
			for sd in ["_l", "_r"]:
				marks[sd] = [(B.P["ball" + sd] as Vector3).x, (B.P["ball" + sd] as Vector3).z, B.foot_heading(sd)]
		var pose := B.to_dict()
		if c.has("store"):
			# spline scenes read the hips' offset Scene.LEAD * 5 ahead of the legs: the card holds the offset as it stood that much
			# earlier, so that at runtime the hips are where this clip's legs (solved above) expect them
			var keep := B.offset
			B.offset = Vector3(0.0, float(c["store"][1]), float(c["store"][0]))
			pose = B.to_dict()
			B.offset = keep
		S.add(c["name"], pose)
		S.cards[-1]["move"] = float(c.get("move", -1.0))
		S.cards[-1]["hold"] = float(c.get("hold", 0.0))
		S.cards[-1]["steps"] = c.get("steps", {})
		if c.has("lift"):
			S.cards[-1]["lift"] = float(c["lift"])
		if c.has("no_steps"):
			S.cards[-1].erase("steps")
		for k in ["walk", "air"]:
			if c.get(k, false):
				S.cards[-1][k] = true
		var cs: Array = B.contacts().map(func(x): return "%s/%s %.0fmm" % [x[0], x[1], x[2] * 1000])
		report.append("  %-18s hips %s y %.3f  R thigh %.0f knee %.0f ankle %.0f | L thigh %.0f knee %.0f  contacts %s" % [c["name"], str(hips), B.offset.y, B.ang["thigh_r"].x, B.ang["calf_r"].x, B.ang["foot_r"].x, B.ang["thigh_l"].x, B.ang["calf_l"].x, cs])
		report[-1] += "  ball_r z %.3f hips y %.3f" % [(B.P["ball_r"] as Vector3).z, B.offset.y]
	var pins := 0 if p.get("no_pin", false) else S.pin_cards(B)
	var added := 0   # no pass-by cards: each template's poses are meant to be clean as written (the report names any frame that is not)
	var d := S.to_dict(B)
	d["plan"] = "templates/%s (tools/make_templates.gd)" % p["name"]
	if p.has("note"):
		d["note"] = p["note"]
	for b in d["bad_frames"].slice(0, 6):
		report.append("  BAD FRAME %s" % str(b))
	report.append("%s: %d clips (+%d pass-by), %.2f s, legs re-planted %d, bad frames %d" % [p["name"], S.cards.size() - added, added, S.length(), pins, d["bad_frames"].size()])
	return d


## the baked files (Templates.BAKED): the words TextBlocking builds, exactly as the Easy home card builds them
## (godot --headless --path . -s tools/make_templates.gd -- roundhouse). The report is the bake's own check of the build.
static func bake_words(nm: String) -> Dictionary:
	var r: Dictionary = EasyHome.new()._words_dict(String(Templates.BAKED[nm]))
	if not r["ok"]:
		push_error("bake %s: %s" % [nm, r["error"]])
		return {}
	var d: Dictionary = r["dict"]
	d["plan"] = "templates/%s (tools/make_templates.gd: the words '%s', built by TextBlocking)" % [nm, Templates.BAKED[nm]]
	return d


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var names: Array = args if not args.is_empty() else Templates.NAMES
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://templates"))
	for nm in names:
		var rep := []
		var d: Dictionary
		if Templates.BAKED.has(nm):
			d = bake_words(nm)
			rep.append("  %s: baked from the words '%s' (%d cards)" % [nm, Templates.BAKED[nm], (d.get("cards", []) as Array).size()])
		else:
			d = bake(plan(nm), rep)
		var f := FileAccess.open("res://templates/%s.json" % nm, FileAccess.WRITE)
		f.store_string(JSON.stringify(d, " "))
		f.close()
		for r in rep:
			print(r)
	quit()
