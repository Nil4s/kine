extends SceneTree
## SEED THE GRIP BOOK (scripts/grip_book.gd) from the two hands Nick fitted himself, moved only by the moves that keep a
## hand exactly on a round shaft (slide, roll, end for end, mirror). Where each hand goes = the references below.
##   godot --headless --path . -s tools/grip_book_seed.gd
## The hands:
##   POWER  = Nick's metal bat grip (data/grips/metal_bat.json, 10-12): the shaft across the palm, the thumb toward the tip
##   BO_L   = the left hand of Nick's two-hand bo pose (data/grips/staff.json "second", from moves/bo_two_hand_nick.json):
##            the SECOND hand of every two-hand grip, thumb toward the tip like the first (not the first hand mirrored: a
##            mirrored hand holds a mirrored weapon, and it missed its place by 10-33 cm on the same one)
## A hand's spot u is its PALM centre: a hand is ~9 cm across the palm (ANSUR II hand breadth, 50th pct men 8.9 cm), so a
## hand against a guard or an end sits 4.5 cm from it.
const HALF := 0.045


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.set_kind("metal_bat")
	B.weapon_to_hand("hand_r")
	var cap := GripBook.capture(B, "x")
	var power: Dictionary = cap["hands"][0]

	var st: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/grips/staff.json"))
	var s2: Dictionary = st["second"]
	var bo_l := {"role": "other", "side": "_l", "u": s2["u"], "lpos": s2["lpos"], "lrot": s2["lrot"], "fingers": s2.get("fingers", {})}
	B.set_kind("staff")
	B.weapon_to_hand("hand_r")
	B.grip = false
	var bo_r: Dictionary = GripBook.capture(B, "x")["hands"][0]
	# the arms of Nick's bo pose: the one two-hand grip recorded WITH its arms so far
	var bp := Body.new()
	bp.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	bp.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://moves/bo_two_hand_nick.json")))
	var bo_arms := {}
	for sd in ["_l", "_r"]:
		for j in ["clavicle", "upperarm", "lowerarm", "hand"]:
			var v: Vector3 = bp.ang[j + sd]
			bo_arms[j + sd] = [snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1)]
	print("POWER at u %.3f, BO main at u %.3f, BO_L at u %.3f" % [power["u"], bo_r["u"], bo_l["u"]])

	# a grip whose LOWER hand is the left: the whole two-hand grip mirrored (a round shaft is its own mirror, so the
	# mirror of a held grip is a held grip), locked to the left hand
	var LM := func(u: float) -> Dictionary:
		var o := GripBook.moved(GripBook.mirrored(power, "_l"), u)
		o["role"] = "main"
		return o
	var RO := func(u: float) -> Dictionary:
		var o := GripBook.moved(GripBook.mirrored(bo_l, "_r"), u)
		o["role"] = "other"
		return o
	var M := func(hd: Dictionary, u: float, rev := false) -> Dictionary:
		var o := GripBook.moved(hd, u, 0.0, rev)
		o["role"] = "main"
		return o
	var O := func(hd: Dictionary, u: float, rev := false) -> Dictionary:
		var o := GripBook.moved(hd, u, 0.0, rev)
		o["role"] = "other"
		return o
	var book := {
		"metal_bat": [
			["one_hand", "one hand", "the bat's standard grip (Nick's)", [M.call(power, power["u"])]],
			["batting", "batting (two hands)", "a batter's hands touch, the bottom hand against the knob (knob 3 cm + half a hand), the top hand right above it",
				[LM.call(0.03 + HALF), RO.call(0.03 + HALF + 0.10)], "_l"],
			["choke_up", "choked up", "the batting grip slid 6 cm up the handle", [LM.call(0.03 + HALF + 0.06), RO.call(0.03 + HALF + 0.16)], "_l"],
		],
		"staff": [
			["nick_bo", "Nick's bo hold", "measured from Nick's pose moves/bo_two_hand_nick.json", [M.call(bo_r, bo_r["u"]), bo_l], "", bo_arms],
			["thirds", "in thirds", "the hands at a third and two thirds of the staff (60 cm apart, shoulder width): the common bo hold",
				[M.call(bo_r, 0.60), O.call(bo_l, 1.20)]],
			["long_reach", "long reach (from the end)", "both hands toward one end for reach: rear hand at the end, the front 45 cm up",
				[M.call(bo_r, HALF), O.call(bo_l, HALF + 0.45)]],
		],
		"long_hammer": [
			["sledge_spread", "sledge, hands apart", "the rear hand at the end of the haft, the lead hand up by the head (start of a sledge swing)",
				[M.call(power, HALF), O.call(bo_l, 0.55)]],
			["sledge_together", "sledge, hands together", "the lead hand slid down to the rear one (a sledge's impact: the hands meet at the end; 10 cm apart: a palm and a finger, the hands touching)",
				[M.call(power, HALF), O.call(bo_l, HALF + 0.10)]],
			["one_hand_choke", "one hand, choked", "one hand near the head for short controlled blows", [M.call(power, 0.80)]],
		],
		"long_axe": [
			["two_hand", "two hands", "a Dane axe: the rear hand at the end, the lead hand 40 cm up", [M.call(power, HALF), O.call(bo_l, 0.45)]],
			["together", "hands together", "the lead hand slid to the rear (the strike)", [M.call(power, HALF), O.call(bo_l, HALF + 0.10)]],
			["one_hand_choke", "one hand, choked", "one hand high on the haft", [M.call(power, 0.85)]],
		],
		"dagger": [
			["forward", "forward", "the blade out past the thumb", [M.call(power, 0.06)]],
			["reverse", "reverse (ice-pick)", "the same hand turned end for end: the blade out under the little finger", [M.call(power, 0.06, true)]],
		],
		"sword": [
			["one_hand", "one hand", "the grip between the pommel and the cross (4 to 15 cm): the hand against the cross", [M.call(power, 0.15 - HALF)]],
			["pommel_hand", "one hand + pommel", "the off hand on the pommel for a stronger cut (in the medieval manuals)", [LM.call(0.02), RO.call(0.15 - HALF)], "_l"],
			["reverse", "reverse", "the blade down past the little finger", [M.call(power, 0.15 - HALF, true)]],
		],
		"longsword": [
			["two_hand", "two hands", "the right hand at the cross, the left at the pommel (the German school's hold)", [LM.call(0.05 + HALF * 0.5), RO.call(0.29 - HALF)], "_l"],
			["one_hand", "one hand", "the right hand at the cross, the left let go", [M.call(power, 0.29 - HALF)]],
			["half_sword", "half-sword", "the left hand on the blade's middle for thrusts in close (half-swording)", [M.call(power, 0.29 - HALF), O.call(bo_l, 0.70)]],
		],
		"katana": [
			["two_hand", "two hands (kamae)", "kendo: the right hand just under the tsuba, the left at the end of the tsuka; about a fist between them",
				[LM.call(HALF), RO.call(0.26 - HALF)], "_l"],
			["one_hand", "one hand", "the right hand under the tsuba", [M.call(power, 0.26 - HALF)]],
		],
		"spear": [
			["two_hand", "two hands", "the rear hand a third of a metre from the butt, the front hand 60 cm ahead (a bit over shoulder width)",
				[M.call(power, 0.30), O.call(bo_l, 0.90)]],
			["close", "close quarters", "both hands slid up toward the head", [M.call(power, 0.90), O.call(bo_l, 1.45)]],
			["one_hand", "one hand at the balance", "one hand at the point of balance (56 % up: 1.1 m)", [M.call(power, 1.10)]],
		],
	}
	for kind in book:
		var out := []
		for e in book[kind]:
			var en := {"name": e[0], "label": e[1], "ref": e[2], "hands": e[3]}
			if e.size() > 4 and String(e[4]) != "":
				en["main_side"] = e[4]
			if e.size() > 5:
				en["arms"] = e[5]
			out.append(en)
		B.set_kind(kind)
		for g in out:
			for hd in g["hands"]:
				if not GripBook.holdable(kind, B.wep_len, float(hd["u"]), true):
					print("BAD %s %s: u %.3f not holdable" % [kind, g["name"], hd["u"]])
		var p := GripBook.path_of(kind)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GripBook.DIR))
		var keep := []
		for g in GripBook.grips(kind):   # grips recorded by hand (not seeded here) are kept
			if not String(g.get("ref", "")).begins_with("seed:"):
				var mine := false
				for o in out:
					mine = mine or o["name"] == g["name"]
				if not mine:
					keep.append(g)
		for g in out:
			g["ref"] = "seed: " + String(g["ref"])
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(JSON.stringify({"weapon": kind, "grips": out + keep}, " "))
		f.close()
		print("BOOK %s: %d grips" % [kind, out.size() + keep.size()])
	quit(0)
