## godot --headless --path . -s tests/lift_form_test.gd     (GATES WW9, #229; headless is fine)
## LIFTING FORM, against real people. The rule: the hands below the knees, the trunk (hips to neck) flexed past 60 deg and
## the knees bent under 30 deg = a stoop to the floor: WARN LIFT FORM naming both angles. REAL PEOPLE: lifters who squat
## bend the knees 86-115 deg at the lowest point of a floor lift (Saraceni et al. 2021, PMID 34288926: knee flexion 91.5 /
## 115.1 deg at the first lift of a no-LBP / LBP group, 85.9 / 95.5 at the 95th); the lifting studies define a stoop as
## knees 0-30 deg (Int J Sports Med 2025, PMID 40368419); the multifidus quiets between 45 and 60 deg of torso flexion
## (Shu et al. 2007, PMID 18089925); stoop lifts load the spine more than squat ones (Bazrgari et al. 2007, PMID 17103232).
## Checked: a squat reach to the floor says nothing, a stoop WARNs with the angles, hands at the waist say nothing, a
## shipped scene has no LIFT FORM, a series broken on purpose fires and a good one does not.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


## a pose: the pelvis tipped forward by `hinge` with the thighs turned back by `hip` (hinge == hip keeps the legs
## upright: a hip hinge), the knees bent `knee`, the spine `spine`; then both hands reached to `hands`
func pose(hinge: float, hip: float, knee: float, spine: float, hands: Vector3) -> Dictionary:
	var B := body()
	B.set_ang("pelvis", Vector3(hinge, 0, 0))
	for sd in ["_l", "_r"]:
		B.set_ang("thigh" + sd, Vector3(hip, 0, 0))
		B.set_ang("calf" + sd, Vector3(knee, 0, 0))
	for n in ["spine_01", "spine_02", "spine_03"]:
		B.set_ang(n, Vector3(spine / 3.0, 0, 0))
	B.fk()
	B.ground()
	B.reach("hand_l", hands + Vector3(0.15, 0, 0))
	B.reach("hand_r", hands - Vector3(0.15, 0, 0))
	B.fk()
	return B.to_dict()


func scene(d: Dictionary) -> Scene:
	var S := Scene.new()
	S.name = "zz_lift"
	S.add("stand", body().to_dict())
	S.add("lift", d)
	S.cards[1]["move"] = 0.5
	S.cards[1]["hold"] = 0.6
	return S


func lift_findings(S: Scene) -> Array:
	return Rulebook.check(S, body()).filter(func(f): return f["rule"] == "LIFT FORM")


## the rule's own measurement at the end of the scene
func read(S: Scene) -> Dictionary:
	var B := body()
	S.apply(B, S.length())
	return Rulebook.lift_form(B)


func _init() -> void:
	var floor_reach := Vector3(0.0, 0.15, 0.35)
	# a squat to the floor: knees deep, the trunk moderately flexed
	var Sq := scene(pose(0, 100, 110, 60, floor_reach))
	var q := read(Sq)
	print("SQUAT: hands %.2f m, knees %.2f m | trunk %.0f deg (bar over %.0f), knees %.0f deg (people 86-115; stoop under %.0f)" % [q["hand"], q["knee"], q["trunk"], Rulebook.LIFT_TRUNK, q["bend"], Rulebook.LIFT_KNEE])
	ok(q["hand"] < q["knee"] and q["bend"] > 86.0 and q["bend"] < 120.0 and q["trunk"] < 60.0, "the squat reach is a floor reach with people's knee bend and a moderate trunk")
	var f := lift_findings(Sq)
	ok(f.is_empty(), "  Check: no LIFT FORM on the squat %s" % [f.map(func(x): return x["msg"])])
	# a stoop to the floor: legs straight (a little bend), back flexed
	var St := scene(pose(75, 75, 6, 0, floor_reach))
	var s := read(St)
	print("STOOP: hands %.2f m, knees %.2f m | trunk %.0f deg (bar over %.0f), knees %.0f deg (bar under %.0f)" % [s["hand"], s["knee"], s["trunk"], Rulebook.LIFT_TRUNK, s["bend"], Rulebook.LIFT_KNEE])
	ok(s["hand"] < s["knee"] and s["trunk"] > 70.0 and s["bend"] < 15.0, "the stoop: hands below the knees, trunk over 70 deg, knees under 15")
	f = lift_findings(St)
	ok(f.size() == 1 and f[0]["sev"] == "WARN", "  Check: one WARN LIFT FORM on the stoop (%d)" % f.size())
	if f.size() == 1:
		var m: String = f[0]["msg"]
		print("   ", m)
		var tr := int(round(float(f[0]["v"])))
		ok(m.contains("the back bent ") and m.contains("the knees only ") and m.contains("lift with the legs") and tr > 70, "  the message names both angles and the advice (trunk %d deg)" % tr)
		ok(m.contains("86-115"), "  and the people number")
	# standing with the hands at the waist
	var Sw := scene(pose(0, 0, 0, 0, Vector3(0.0, 1.0, 0.25)))
	var w := read(Sw)
	print("WAIST: hands %.2f m, knees %.2f m | trunk %.0f deg, knees %.0f deg" % [w["hand"], w["knee"], w["trunk"], w["bend"]])
	ok(w["hand"] > w["knee"], "the hands at the waist are above the knees")
	ok(lift_findings(Sw).is_empty(), "  Check: no LIFT FORM at the waist")
	# a stoop with the hands ABOVE the knees (bending to a table) is not this rule's business
	var Sh := scene(pose(40, 40, 0, 0, Vector3(0.0, 0.9, 0.3)))
	var h := read(Sh)
	print("TABLE: hands %.2f m, knees %.2f m | trunk %.0f deg, knees %.0f deg" % [h["hand"], h["knee"], h["trunk"], h["bend"]])
	ok(h["hand"] > h["knee"] and lift_findings(Sh).is_empty(), "a bend to a table (hands above the knees): no LIFT FORM")
	# series broken on purpose, and a good one
	var t := []
	var bad := []
	var good := []
	for i in 30:
		t.append(i / 60.0)
		bad.append({"hand": 0.3, "knee": 0.5, "trunk": 80.0, "bend": 10.0})
		good.append({"hand": 0.3, "knee": 0.5, "trunk": 80.0, "bend": 100.0})
	ok(Rulebook.rule_lift_form({"t": t, "lift_form": bad}).size() == 1, "a stoop series fires once")
	ok(Rulebook.rule_lift_form({"t": t, "lift_form": good}).is_empty(), "the same trunk with the knees at 100 deg does not")
	ok(Rulebook.rule_lift_form({"t": t.slice(0, 4), "lift_form": bad.slice(0, 4)}).is_empty(), "a stoop shorter than 0.1 s does not (a pass through)")
	ok(Rulebook.rule_lift_form({"t": t}).is_empty(), "a sample without the series: nothing")
	# the shipped scenes: no LIFT FORM, nothing else changed in kind
	var n := 0
	for fn in ["combo3.json", "bo_spin.json", "dodge_side.json"]:
		var Sc := Scene.new()
		Sc.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + fn)))
		n += lift_findings(Sc).size()
	ok(n == 0, "shipped scenes combo3, bo_spin, dodge_side: %d LIFT FORM findings" % n)
	ok(Rulebook.SRC.has("LIFT FORM") and Rulebook.WHY.has("LIFT FORM") and Rulebook.URL.has("LIFT FORM"), "LIFT FORM has its SRC, WHY and URL")
	print("LIFT FORM TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
