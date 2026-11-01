class_name EasyChallenge
extends PanelContainer
## S165 BUILD-ALONG CHALLENGES (Friday plan 165, Kine's own idea: a target to build toward, with a score from the measured geometry).
## A card in the clear view of Easy Part (bottom left; it never sits on the Make buttons, the hint or the panel): pick one of five challenges
## (Phone stand, L-bracket, Hook, Box with lid, Gear pair), see the target as a picture and its key sizes in words, build it by the usual steps,
## then press "How close am I?". The score is measured from the kernel, not guessed:
##   both parts are moved so their lowest corner is at 0, 0, 0 (where you built it does not matter), then
##   shared = the volume of (yours AND the target), by the kernel's intersect (every body of yours against every body of the target)
##   IoU    = shared / (yours + target - shared)                        (1 = the same solid, 0 = nothing in common)
##   fit    = 1 - min(1, (|dx| + |dy| + |dz|) / (target x + y + z))     (dx, dy, dz = how far each box size is off, mm)
##   score  = round(100 x IoU x fit)
## One plain-words hint comes with it, the most useful first: a size that is off ("your stand is 20 mm too tall"), else a part that is missing
## ("your stand has no slot"), else "spot on". The card changes no part and makes no undo step. The target is a Part record (the same steps Expert
## shows): Challenge.target_record(id), so the right answer can be loaded and scores 100.

const MM := 0.001
const KCad := preload("res://scripts/kcad.gd")
const PIC_W := 120
const PIC_H := 90
const SIZE_TOL := 1.5   # mm: a box size off by less than this is not worth a hint
const IDS := ["stand", "bracket", "hook", "lidbox", "gears"]
## per challenge: title, noun (your ...), what the target has (plain words), parts: [name, words, kind ("hole" = must be empty, "solid" = must be filled), fraction box of the target's size x0 y0 z0 x1 y1 z1]
const C := {
	"stand": {"title": "Phone stand", "noun": "stand", "has": "A block with a slot across the top for the phone: 14 mm wide, 30 mm deep, 10 mm from the front.",
		"parts": [["slot", "the slot for the phone", "hole", [0.1, 0.4, 0.2, 0.9, 0.9, 0.35]]]},
	"bracket": {"title": "L-bracket", "noun": "bracket", "has": "Two flat legs 5 mm thick joined at a corner, with a 6 mm round hole through the upright leg.",
		"parts": [["hole", "the round hole in the upright leg", "hole", [0.02, 0.66, 0.43, 0.08, 0.74, 0.57]]]},
	"hook": {"title": "Hook", "noun": "hook", "has": "A flat back plate 6 mm thick, an arm 6 mm thick out from the bottom, and a tip turned up at the end.",
		"parts": [["tip", "the tip turned up at the end", "solid", [0.87, 0.13, 0.1, 0.97, 0.3, 0.9]]]},
	"lidbox": {"title": "Box with lid", "noun": "box", "has": "A box 60 x 40 mm and 20 mm high, a lid 4 mm thick that overhangs 2 mm each side, and a small knob on the lid.",
		"parts": [["lid", "the lid on top", "solid", [0.1, 0.7, 0.1, 0.9, 0.77, 0.9]], ["knob", "the knob on the lid", "solid", [0.46, 0.85, 0.42, 0.54, 0.97, 0.58]]]},
	"gears": {"title": "Gear pair", "noun": "gear pair", "has": "Two gears side by side that mesh: a small one with 10 teeth and a big one with 20 teeth, each 10 mm thick.",
		"parts": [["big gear", "the big gear", "solid", [0.78, 0.45, 0.3, 0.94, 0.55, 0.7]], ["small gear", "the small gear", "solid", [0.06, 0.45, 0.3, 0.16, 0.55, 0.7]]]},
}

var ep: Node                      # the Easy Part screen (words go to its status line; its record is the part being built)
var cur := ""                     # the challenge open ("" = none)
var chips := {}                   # id -> Button
var pic: TextureRect
var words: Label
var has_l: Label
var check_btn: Button
var score_l: Label
var hint_l: Label
var detail_l: Label
var close_btn: Button
var last := {}                    # the last check's numbers (the test reads them)
static var _pics := {}            # id -> ImageTexture (drawn once)
static var _cache := {}           # id -> {"size": Vector3 mm, "vol": mm3}


# ---------------------------------------------------------------- the targets (Part records, mm)

static func target_record(id: String) -> Dictionary:
	var fs: Array = []
	var T := PartTemplates
	match id:
		"stand":   # block 80 wide (x) x 40 tall (y) x 60 deep (z); a slot across the whole width, 14 wide at z 10..24, from y 10 up
			T._step(fs, "Block", "front", [T._rect(Vector2(0, 0), Vector2(80, 40))], 60.0, "new")
			T._step(fs, "Slot", "right", [T._rect(Vector2(-24, 10), Vector2(-10, 45))], 90.0, "cut")
		"bracket":   # two legs 50 x 50 x 30 wide, 5 thick; a 6 mm hole through the upright leg
			T._step(fs, "L shape", "front", T._poly([Vector2(0, 0), Vector2(50, 0), Vector2(50, 5), Vector2(5, 5), Vector2(5, 50), Vector2(0, 50)]), 30.0, "new")
			T._step(fs, "Hole", "right", [{"k": "circle", "c": [-15.0, 35.0], "r": 3.0}], 10.0, "cut")
		"hook":   # 40 x 60 x 12
			T._step(fs, "Hook", "front", T._poly([Vector2(0, 0), Vector2(40, 0), Vector2(40, 20), Vector2(34, 20), Vector2(34, 6), Vector2(6, 6), Vector2(6, 60), Vector2(0, 60)]), 12.0, "new")
		"lidbox":   # box 60 x 20 x 40, lid 64 x 4 x 40 over it, knob 10 x 10 x 6
			T._step(fs, "Box", "front", [T._rect(Vector2(0, 0), Vector2(60, 20))], 40.0, "new")
			T._step(fs, "Lid", "front", [T._rect(Vector2(-2, 20), Vector2(62, 24))], 40.0, "join")
			T._step(fs, "Knob", "top", [T._rect(Vector2(25, -25), Vector2(35, -15))], 30.0, "join")
		"gears":
			return PartTemplates.make("gearpair", {"teeth": 10.0, "ratio": 2.0, "module": 2.0, "thickness": 10.0})
	var rec := Part.make(String(C[id]["title"]))
	rec["features"] = fs
	rec["seq"] = fs.size()
	return rec


# ---------------------------------------------------------------- measuring (kernel)

## the bodies of a record, kept (the caller releases), moved so the lowest corner is at 0: {"ids": [...], "size": Vector3 mm, "vol": mm3, "ok": bool}
static func _solids(rec: Dictionary) -> Dictionary:
	var res := Part.replay(rec, -1, {"keep": true})
	var ids: Array = res.get("ids", [])
	var out := {"ids": [], "size": Vector3.ZERO, "vol": 0.0, "bodies": ids.size(), "errors": res.get("errors", {})}
	if ids.is_empty():
		return out
	var bb: AABB = res["aabb"]
	var moved: Array = []
	var vol := 0.0
	for b in ids:
		var t := KCad.translate(int(b), -bb.position)
		KCad.release(int(b))
		if t != 0:
			moved.append(t)
			vol += KCad.volume(t)
	out["ids"] = moved
	out["size"] = bb.size / MM
	out["vol"] = vol * 1e9
	return out


static func _release(ids: Array) -> void:
	for b in ids:
		KCad.release(int(b))


## the volume (mm3) the bodies share with a box (mm: lo, hi)
static func _share_box(ids: Array, lo: Vector3, hi: Vector3) -> float:
	var bx := KCad.box((hi.x - lo.x) * MM, (hi.y - lo.y) * MM, (hi.z - lo.z) * MM)
	var bt := KCad.translate(bx, (lo + hi) * 0.5 * MM)
	KCad.release(bx)
	var v := 0.0
	for b in ids:
		var c := KCad.intersect(int(b), bt)
		if c != 0:
			v += KCad.volume(c)
			KCad.release(c)
	KCad.release(bt)
	return v * 1e9


## the target's size (mm) and volume (mm3), measured once
static func target_info(id: String) -> Dictionary:
	if not _cache.has(id):
		var s := _solids(target_record(id))
		_release(s["ids"])
		_cache[id] = {"size": s["size"], "vol": s["vol"]}
	return _cache[id]


## the target's key sizes in plain words, from the measured target
static func size_words(id: String) -> String:
	var sz: Vector3 = target_info(id)["size"]
	return "%d mm wide, %d mm tall, %d mm deep" % [roundi(sz.x), roundi(sz.y), roundi(sz.z)]


## Scores a part record against challenge id. Answers {"score" 0-100, "shared" mm3, "built" mm3, "target" mm3, "iou", "fit", "size" (yours mm),
## "tsize" (target mm), "hint", "formula", "missing": [part names], "nothing": bool}
static func score_of(rec: Dictionary, id: String) -> Dictionary:
	var out := {"score": 0, "shared": 0.0, "built": 0.0, "target": 0.0, "iou": 0.0, "fit": 0.0, "size": Vector3.ZERO, "tsize": Vector3.ZERO, "hint": "", "formula": "", "missing": [], "nothing": false}
	var noun := String(C[id]["noun"])
	var tgt := _solids(target_record(id))
	var tsz: Vector3 = tgt["size"]
	out["tsize"] = tsz
	out["target"] = tgt["vol"]
	var got := _solids(rec)
	if (got["ids"] as Array).is_empty():
		_release(tgt["ids"])
		out["nothing"] = true
		out["hint"] = "Nothing built yet: press Draw shape, draw on the grid, then Pull it up. Then press How close am I? again"
		return out
	var sz: Vector3 = got["size"]
	out["size"] = sz
	out["built"] = got["vol"]
	var shared := 0.0
	for a in got["ids"]:
		for b in tgt["ids"]:
			var c := KCad.intersect(int(a), int(b))
			if c != 0:
				shared += KCad.volume(c)
				KCad.release(c)
	shared *= 1e9
	var uni := float(got["vol"]) + float(tgt["vol"]) - shared
	var iou := clampf(shared / uni, 0.0, 1.0) if uni > 1e-9 else 0.0
	var dsum := absf(sz.x - tsz.x) + absf(sz.y - tsz.y) + absf(sz.z - tsz.z)
	var fit := 1.0 - minf(1.0, dsum / (tsz.x + tsz.y + tsz.z))
	var score := clampi(roundi(100.0 * iou * fit), 0, 100)
	out["shared"] = shared
	out["iou"] = iou
	out["fit"] = fit
	out["score"] = score
	out["formula"] = "shared %.0f mm3 (yours %.0f, target %.0f): overlap = %.0f / (%.0f + %.0f - %.0f) = %.1f percent; size fit = 1 - %.1f / %.0f = %.1f percent; score = 100 x %.3f x %.3f = %d" % [
		shared, got["vol"], tgt["vol"], shared, got["vol"], tgt["vol"], shared, iou * 100.0, dsum, tsz.x + tsz.y + tsz.z, fit * 100.0, iou, fit, score]
	# the missing parts (a hole that is filled, a solid that is empty), read in the target's frame
	var missing: Array = []
	for pt in C[id]["parts"]:
		var f: Array = pt[3]
		var lo := Vector3(f[0] * tsz.x, f[1] * tsz.y, f[2] * tsz.z)
		var hi := Vector3(f[3] * tsz.x, f[4] * tsz.y, f[5] * tsz.z)
		var vb := (hi - lo).x * (hi - lo).y * (hi - lo).z
		var fill := _share_box(got["ids"], lo, hi) / vb
		if (String(pt[2]) == "hole" and fill > 0.5) or (String(pt[2]) == "solid" and fill < 0.5):
			missing.append(pt)
	out["missing"] = missing.map(func(p): return String(p[0]))
	_release(got["ids"])
	_release(tgt["ids"])
	# the one hint: the biggest size that is off, else a missing part, else how near it is
	var diffs := [sz.x - tsz.x, sz.y - tsz.y, sz.z - tsz.z]
	var wd := [["too wide", "too narrow", "wide"], ["too tall", "too short", "tall"], ["too deep", "too shallow", "deep"]]
	var worst := 0
	for i in 3:
		if absf(float(diffs[i])) > absf(float(diffs[worst])):
			worst = i
	var hint := ""
	if absf(float(diffs[worst])) >= SIZE_TOL:
		var d: float = diffs[worst]
		hint = "Your %s is %d mm %s (yours %d mm, the target %d mm): change that size and press How close am I? again" % [noun, roundi(absf(d)), String(wd[worst][0] if d > 0.0 else wd[worst][1]), roundi([sz.x, sz.y, sz.z][worst]), roundi([tsz.x, tsz.y, tsz.z][worst])]
	elif not missing.is_empty():
		var pt: Array = missing[0]
		hint = "Your %s is the right size but %s %s: %s" % [noun, "has no" if String(pt[2]) == "hole" else "is missing", String(pt[1]).trim_prefix("the "), "cut it away" if String(pt[2]) == "hole" else "add it"]
	elif score >= 98:
		hint = "Spot on: your %s matches the target" % noun
	else:
		hint = "Very close: your %s differs from the target by %d mm3. Check the small sizes against the words" % [noun, roundi(uni - shared)]
	out["hint"] = hint
	return out


# ---------------------------------------------------------------- the picture

## a small shaded picture of the target from the front, right and above (z-buffer, flat light): drawn once per challenge
static func picture(id: String) -> ImageTexture:
	if _pics.has(id):
		return _pics[id]
	var img := Image.create(PIC_W, PIC_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.07, 0.08, 0.1, 1.0))
	var tris := PackedVector3Array()
	for t in Part.body_faces(target_record(id)):
		tris.append_array(t as PackedVector3Array)
	if tris.size() >= 3:
		var basis := Basis(Vector3.RIGHT, deg_to_rad(-28.0)) * Basis(Vector3.UP, deg_to_rad(-35.0))
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		var pts := PackedVector3Array()
		for p in tris:
			var q := basis * p
			pts.append(q)
			lo = lo.min(q)
			hi = hi.max(q)
		var sc := minf((PIC_W - 12.0) / maxf(hi.x - lo.x, 1e-6), (PIC_H - 12.0) / maxf(hi.y - lo.y, 1e-6))
		var off := Vector2(PIC_W, PIC_H) * 0.5 - Vector2(lo.x + hi.x, -(lo.y + hi.y)) * 0.5 * sc
		var zb := PackedFloat32Array()
		zb.resize(PIC_W * PIC_H)
		zb.fill(-1e9)
		var light := Vector3(0.35, 0.8, 0.5).normalized()
		for i in range(0, pts.size() - 2, 3):
			var a := pts[i]
			var b := pts[i + 1]
			var c := pts[i + 2]
			var n := (b - a).cross(c - a)
			if n.length() < 1e-14:
				continue
			n = n.normalized()
			if n.z < 0.0:
				n = -n   # the faces are viewed from the camera side whichever way the triangle winds
			var shade := 0.35 + 0.65 * clampf(n.dot(light), 0.0, 1.0)
			var col := Color(0.62 * shade + 0.1, 0.72 * shade + 0.1, 0.9 * shade + 0.05, 1.0)
			var pa := Vector2(a.x, -a.y) * sc + off
			var pb := Vector2(b.x, -b.y) * sc + off
			var pc := Vector2(c.x, -c.y) * sc + off
			var x0 := maxi(0, floori(minf(pa.x, minf(pb.x, pc.x))))
			var x1 := mini(PIC_W - 1, ceili(maxf(pa.x, maxf(pb.x, pc.x))))
			var y0 := maxi(0, floori(minf(pa.y, minf(pb.y, pc.y))))
			var y1 := mini(PIC_H - 1, ceili(maxf(pa.y, maxf(pb.y, pc.y))))
			var den := (pb.y - pc.y) * (pa.x - pc.x) + (pc.x - pb.x) * (pa.y - pc.y)
			if absf(den) < 1e-9:
				continue
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					var px := float(x) + 0.5
					var py := float(y) + 0.5
					var w0 := ((pb.y - pc.y) * (px - pc.x) + (pc.x - pb.x) * (py - pc.y)) / den
					var w1 := ((pc.y - pa.y) * (px - pc.x) + (pa.x - pc.x) * (py - pc.y)) / den
					var w2 := 1.0 - w0 - w1
					if w0 < -0.02 or w1 < -0.02 or w2 < -0.02:
						continue
					var z := w0 * a.z + w1 * b.z + w2 * c.z
					if z > zb[y * PIC_W + x]:
						zb[y * PIC_W + x] = z
						img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_pics[id] = tex
	return tex


# ---------------------------------------------------------------- the card

func _init() -> void:
	name = "easypart_challenge_card"
	visible = false
	z_index = 20   # above the status words that run along the bottom of the clear view
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14, 0.98)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	pic = TextureRect.new()
	pic.name = "easypart_challenge_pic"
	pic.custom_minimum_size = Vector2(PIC_W, PIC_H)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(pic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 3)
	fl.add_theme_constant_override("v_separation", 3)
	col.add_child(fl)
	for id in IDS:
		var b := Button.new()
		b.name = "easypart_challenge_" + id
		b.text = String(C[id]["title"])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size = Vector2(0, 26)
		b.pressed.connect(pick.bind(id))
		fl.add_child(b)
		chips[id] = b
	close_btn = Button.new()
	close_btn.name = "easypart_challenge_close"
	close_btn.text = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.custom_minimum_size = Vector2(0, 26)
	close_btn.pressed.connect(close)
	fl.add_child(close_btn)
	words = Label.new()
	words.name = "easypart_challenge_words"
	words.add_theme_font_size_override("font_size", 12)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.custom_minimum_size.x = 215.0
	col.add_child(words)
	has_l = Label.new()   # what the target has: shown as the words' tooltip and as a short line
	has_l.name = "easypart_challenge_has"
	has_l.add_theme_font_size_override("font_size", 11)
	has_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	has_l.custom_minimum_size.x = 200.0
	has_l.visible = false
	col.add_child(has_l)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	v.add_child(row2)
	check_btn = Button.new()
	check_btn.name = "easypart_challenge_check"
	check_btn.text = "How close am I?"
	check_btn.tooltip_text = "Scores your part against the target, out of 100, from the real shapes"
	check_btn.focus_mode = Control.FOCUS_NONE
	check_btn.custom_minimum_size = Vector2(150, 32)
	check_btn.add_theme_font_size_override("font_size", 14)
	check_btn.pressed.connect(check)
	row2.add_child(check_btn)
	score_l = Label.new()
	score_l.name = "easypart_challenge_score"
	score_l.add_theme_font_size_override("font_size", 16)
	row2.add_child(score_l)
	hint_l = Label.new()
	hint_l.name = "easypart_challenge_hint"
	hint_l.add_theme_font_size_override("font_size", 13)
	hint_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_l.custom_minimum_size.x = 340.0
	v.add_child(hint_l)
	detail_l = Label.new()
	detail_l.name = "easypart_challenge_detail"
	detail_l.add_theme_font_size_override("font_size", 10)
	detail_l.modulate = Color(1, 1, 1, 0.65)
	detail_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_l.custom_minimum_size.x = 340.0
	detail_l.visible = false   # the numbers are the score line's tooltip (and printed to the console): the card stays short
	v.add_child(detail_l)
	_fill()


func _say(t: String) -> void:
	if ep != null:
		ep._say(t)


## the Challenges chip: opens the card with the first challenge, or closes it
func toggle() -> void:
	if visible:
		close()
		return
	if not Part.available():
		_say("The part tools did not load: restart Kine first")
		return
	visible = true
	pick(cur if cur != "" else String(IDS[0]))


func close() -> void:
	visible = false
	if ep != null and ep.get("challenge_btn") != null:
		(ep.challenge_btn as Button).set_pressed_no_signal(false)


func pick(id: String) -> void:
	cur = id
	last = {}
	_fill()
	_say("Challenge %s: build it like the picture, then press How close am I?" % String(C[id]["title"]))


func _fill() -> void:
	for id in chips:
		(chips[id] as Button).set_pressed_no_signal(id == cur)
	check_btn.visible = cur != ""
	score_l.text = ""
	hint_l.text = ""
	detail_l.text = ""
	if cur == "" or not Part.available():
		words.text = "Pick a challenge"
		has_l.text = ""
		pic.texture = null
		return
	pic.texture = picture(cur)
	words.text = "%s: %s" % [String(C[cur]["title"]), size_words(cur)]
	has_l.text = String(C[cur]["has"])
	words.tooltip_text = has_l.text
	pic.tooltip_text = has_l.text
	score_l.tooltip_text = ""
	score_l.text = "Not checked yet"


## How close am I?: scores the part being built; no record change, no undo step
func check() -> void:
	if cur == "" or ep == null:
		return
	last = score_of(ep._rec(), cur)
	if bool(last["nothing"]):
		score_l.text = "Nothing built yet"
		hint_l.text = String(last["hint"])
		detail_l.text = ""
	else:
		var s := int(last["score"])
		score_l.text = "Score %d / 100: %s" % [s, "Spot on" if s >= 98 else ("Close" if s >= 80 else ("Getting there" if s >= 50 else "Far off"))]
		hint_l.text = String(last["hint"])
		detail_l.text = String(last["formula"])
		score_l.tooltip_text = String(last["formula"])
		score_l.mouse_filter = Control.MOUSE_FILTER_STOP
	print("S165 %s: %s | hint: %s" % [cur, String(last["formula"]), String(last["hint"])])
	_say(String(last["hint"]))


## the card sits at the bottom left of the clear view (below the Make buttons, the hint and the shape row, left of the panel)
func _process(_d: float) -> void:
	if ep == null:
		return
	var on: bool = ep.has_method("active") and ep.active()
	if not on:
		if visible and get_parent() != null:
			modulate.a = 0.0
		return
	modulate.a = 1.0
	if not visible:
		return
	var cl: Rect2 = ep._cl
	reset_size()
	size = get_combined_minimum_size()
	var vr := get_viewport().get_visible_rect()
	var bottom := minf(cl.end.y, vr.size.y) - 8.0
	var bb: Variant = ep.get("bulge_btn")   # the Pinch / Bulge chip sits low in this column when a solid is on the floor: stop above it
	if bb != null and (bb as Control).is_visible_in_tree():
		bottom = minf(bottom, (bb as Control).global_position.y - 6.0)
	var st: Variant = ep.get("status")   # bug5: the Tilt chips hide while the card is up (it stands where they are); it rests on the one-line status at the bottom left
	if st != null and (st as Control).is_visible_in_tree():
		bottom = minf(bottom, (st as Control).global_position.y - 6.0)
	position = Vector2(cl.position.x + 12.0, bottom - size.y)
