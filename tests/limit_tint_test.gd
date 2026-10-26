## godot --path . -s tests/limit_tint_test.gd     (the joint limit tint: yellow on the part whose joint is near its stop; needs a window for the screenshot)
## BARS (stated before the run):
##  (1) the fade is 0 until the last 10% of a joint's range, then rises linearly to 1 at the stop: head twist (range -35..35,
##      band = 7 deg) is 0 at 20 deg, 0.5 at 31.5 deg, 1 at 35 deg (clamped from 60);
##  (2) at a 60 deg head twist (clamped to the 35 deg stop) only head and neck_01 carry a limit look: no spine, no clavicle, no arm;
##  (3) the head's look is the limit colour at strength 0.28 x fade (1.0 at the stop), so it is visibly yellow and not a full patch;
##  (0) at rest (every angle zero) no joint is tinted;
##  (4) screenshot of the whole body with the head at 60 deg to C:/Users/Nick/.claude/jobs/9afc22db/tmp/polish_limit.png.
## Nothing is written to disk except that png (never scenes/, poses/, data/).
extends SceneTree

var fails := 0
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/polish_limit.png"
const CHEST := ["spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var B: Body = m.B

	# the rest pose first: the scene's own pose may already sit at a stop (an arm), which is not what this tests
	for j in Body.ORDER:
		B.set_ang(j, Vector3.ZERO)
	B.fk()
	m._refresh()
	var rest_tinted := []   # the LIMIT look only (a part touching another reads "touch", a separate red tint)
	for j in Body.ORDER:
		if m.part_look(j) == "limit":
			rest_tinted.append(j)
	ok(rest_tinted.is_empty(), "(0) at rest no joint is at its limit tint: %s" % str(rest_tinted))

	# (1) the ramp, on the head's twist (-35..35 deg, last 10% = 7 deg)
	var fades := {}
	for deg in [20.0, 31.5, 35.0, 60.0]:
		B.set_ang("head", Vector3(0, 0, deg))
		B.fk()
		fades[deg] = B.limit_fade("head")
	ok(absf(float(fades[20.0])) < 1e-9, "(1) the head at 20 deg: fade %.3f (want 0: not in the last 10%%)" % fades[20.0])
	ok(absf(float(fades[31.5]) - 0.5) < 1e-6, "(1) the head at 31.5 deg: fade %.3f (want 0.500)" % fades[31.5])
	ok(absf(float(fades[35.0]) - 1.0) < 1e-9 and absf(float(fades[60.0]) - 1.0) < 1e-9, "(1) the head at its 35 deg stop (and a 60 deg request, clamped): fade %.3f, %.3f (want 1)" % [fades[35.0], fades[60.0]])

	# (2) and (3) the 60 deg head twist as the body sees it: only head and neck_01 are limit looks
	B.set_ang("head", Vector3(0, 0, 60))
	B.fk()
	m._refresh()
	var tinted := []
	for j in Body.ORDER:
		if m.part_look(j) == "limit":
			tinted.append(j)
	ok(tinted.has("head") and tinted.all(func(j): return j == "head" or j == "neck_01"), "(2) at 60 deg head twist only head/neck_01 carry the limit tint: %s" % str(tinted))
	var chest_tinted := []
	for j in CHEST:
		if m.part_look(j) == "limit" or not m.skp.look_of(j).is_empty():
			chest_tinted.append(j)
	ok(chest_tinted.is_empty(), "(2) the chest (spine_01..03) and clavicles carry no limit tint and no look: %s" % str(chest_tinted))
	var hl: Array = m.skp.look_of("head")
	var want_a: float = 0.28 * 1.0
	ok(not hl.is_empty() and absf(float((hl[0] as Color).a) - want_a) < 1e-4, "(3) the head's tint strength is 0.28 at the stop: %s" % ("%.3f" % float((hl[0] as Color).a) if not hl.is_empty() else "none"))

	# (4) the picture: the whole body, head at 60 deg, as the person sees it
	m._refresh()
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(SHOT)
	ok(err == OK, "(4) screenshot saved to %s (%s)" % [SHOT.get_file(), error_string(err)])

	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
