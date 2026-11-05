extends SceneTree
## godot --path . -s tests/g7time_test.gd     (G7TIME: Assembly drives keyed on a timeline, played through the loop solver, and filmed by the shared
## render helper; gaps G7 and G11 of docs/CHALLENGE_FEEDBACK.md; scripts/build/assembly_anim.gd, assembly_render.gd, the timeline strip in
## assembly_motion_ui.gd). Bars committed before the first run; every bar has a planted control (a "CONTROL" line that must be caught):
##   a INTERP     keys [[0, 10, linear], [1, 30, smooth], [3, -10, constant], [4, 50, linear]], put in shuffled order: the value at 9 times equals
##                the hand value to 1e-9 (linear 15 at 0.25; smooth u = 0.25 / 0.5 / 0.75 -> 30 - 40 s(u), s = u^2 (3 - 2u): 23.75 / 10 / -3.75;
##                held -10 at 3.5; 50 at 4 and 5; 10 at -1; 30 at 1); 2 s at 30 fps is 61 frames, the last at 2.0 s.
##                CONTROL: the same keys with the 1 s key put at 1.1 s miss the hand values by more than 1e-9
##   b ENGINE     the CH13 engine (ch13_parts.loop_assembly) keyed 0 -> 720 deg (linear) over 2 s at 30 fps: at every one of the 61 frames the
##                drive is at 12 k deg (1e-9), the piston pin centre is at y = R cos t + sqrt(L^2 - (R sin t)^2) on the bore axis and the crank
##                pin at (R sin t, R cos t) (1e-6 mm, doubles: AssemblyLoop.world_mm on the frame's states). The piston alone can't see a
##                reversed track (y(-t) = y(t)), so the crank pin is checked with it. CONTROL: the reversed track (720 -> 0) misses by > 1 mm
##   c CLASH/TIME the g1motion hinge with the 5 mm longer lid, keyed 0 -> 70 deg over 2 s: AssemblyAnim.check lists Lid x Ceiling only, first at
##                a time within one frame (1/30 s) after the hand onset t = 2 x 64.73 / 70 s (and not before it); the same with a smooth key
##                (onset where 70 s(t/2) = 64.73 deg, by bisection). CONTROL: keyed 0 -> 60 deg (below the onset) no clash is listed
##   d RENDER     AssemblyRender.render on the engine keyed 0 -> 720 deg at 6 fps over 2 s, 320 x 240: 13 PNG frames of 320 x 240; the sheet is
##                4 x 4 tiles of 256 x 192 and tile i is frame i shrunk (byte equal), the 3 spare tiles are the fill; each pair of consecutive
##                frames differs in >= 100 pixels where the piston is (its own frames: "only" p4); the head's pixels (eroded 3 px, >= 500 px)
##                are byte equal in all 13 frames; the .mp4 is written when ffmpeg is found (said either way).
##                CONTROL: a frozen track (0 -> 0) gives 13 byte-identical frames
##   e UI         the engine record in the Assembly screen, Check motion open: with no keys the timeline doesn't move the piston (CONTROL);
##                Key at 0 s (Smooth), then drive slider 360 at 2 s + Key: 2 keys, 2 undo steps; time 0.5 s puts the crank at 360 s(0.25) =
##                56.25 deg and the piston mesh at the closed form - 34 mm (1e-4 mm, float32); Play runs to 2.0 s and stops, the piston at TDC;
##                the Export Video path films 61 frames + a sheet; Run sweeps the 61 frames: no clash; Delete key at 2 s: 1 key; three Ctrl+Z give
##                back the identical record (no "anim"). Shot C:/Temp/claude/g7time/timeline.png
##   f OLD        tests/assets/g1motion/old_assembly.json, tests/assets/g2loop/drive_199.json (#199) and tests/assets/g7time/joint_204.json (written
##                by the #204 code before this branch) open in the screen, the timeline moved, and save back equal.
##                CONTROL: the #204 record with one key does not compare equal
##   g PAYOFF     the CH13 contact sheet (13 frames over 2 revolutions, ch13's camera) and section view (SectionLook cut at z = ZC, 40 deg)
##                re-made with the helper: 13 tiles; the cut shows >= 800 cap-colour pixels (ch13 bar i), the uncut view none (CONTROL); the
##                payoff code's line count is printed against CH13's own scene + grab code
const AM := preload("res://scripts/build/assembly_motion.gd")
const AL := preload("res://scripts/build/assembly_loop.gd")
const AN := preload("res://scripts/build/assembly_anim.gd")
const AR := preload("res://scripts/build/assembly_render.gd")
const P := preload("res://scripts/build/ch13_parts.gd")
const OUT := "C:/Temp/claude/g7time"
const OLD := "res://tests/assets/g1motion/old_assembly.json"
const D199 := "res://tests/assets/g2loop/drive_199.json"
const J204 := "res://tests/assets/g7time/joint_204.json"
var fails := 0
var m: Node
var A: AssemblyUI


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func ctl(c: bool, w: String) -> void:
	ok(c, "CONTROL " + w)


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func sci(x: float) -> String:
	return String.num_scientific(x)


# ------------------------------------------------------------------ a
func smooth(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


## [t, hand value] pairs, worked by hand from the keys in the header
const HAND := [[0.25, 15.0], [1.5, 23.75], [2.0, 10.0], [2.5, -3.75], [3.5, -10.0], [4.0, 50.0], [5.0, 50.0], [-1.0, 10.0], [1.0, 30.0]]


func worst_vs_hand(asm: Dictionary) -> float:
	var w := 0.0
	for h in HAND:
		w = maxf(w, absf(AN.value_at(asm, "D", float(h[0])) - float(h[1])))
	return w


func keyed(keys: Array) -> Dictionary:
	var a := Assembly.make("interp")
	AM.set_drive(a, AM.make_drive("D", "p1", "rotate", Vector3.BACK, Vector3.ZERO, 0.0, 90.0))
	for k in keys:
		AN.set_key(a, "D", float(k[0]), float(k[1]), String(k[2]))
	return a


func bars_interp() -> void:
	var a := keyed([[3.0, -10.0, "constant"], [0.0, 10.0, "linear"], [4.0, 50.0, "linear"], [1.0, 30.0, "smooth"]])
	var ts: Array = AN.track_of(a, "D")["keys"].map(func(k): return float(k[0]))
	var w := worst_vs_hand(a)
	var got: Array = HAND.map(func(h): return snappedf(AN.value_at(a, "D", float(h[0])), 1e-6))
	ok(w <= 1e-9 and ts == [0.0, 1.0, 3.0, 4.0], "a 9 times vs hand values: worst %s (bar 1e-9); got %s; keys in order %s; smooth(0.25) = %s (hand 0.15625)" % [sci(w), str(got), str(ts), str(AN.ease_of("smooth", 0.25))])
	var b := Assembly.make("frames")
	AN.set_length(b, 2.0)
	var tt := AN.times(b)
	ok(AN.frame_count(b) == 61 and tt.size() == 61 and absf(float(tt[60]) - 2.0) < 1e-12 and absf(float(tt[1]) - 1.0 / 30.0) < 1e-12, "a 2 s at 30 fps: %d frames, the last at %s s" % [AN.frame_count(b), str(tt[60])])
	var wrong := keyed([[3.0, -10.0, "constant"], [0.0, 10.0, "linear"], [4.0, 50.0, "linear"], [1.1, 30.0, "smooth"]])
	var ww := worst_vs_hand(wrong)
	ctl(ww > 1e-9, "a the 1 s key put at 1.1 s misses the hand values by %s" % sci(ww))


# ------------------------------------------------------------------ b
func x_closed(t: float) -> float:
	return P.R * cos(t) + sqrt(P.L * P.L - (P.R * sin(t)) * (P.R * sin(t)))


func engine_keyed(v0: float, v1: float, fps := 30) -> Dictionary:
	var asm := P.loop_assembly()
	AN.set_key(asm, "Crank", 0.0, v0, "linear")
	AN.set_key(asm, "Crank", 2.0, v1, "linear")
	asm["anim"]["fps"] = fps
	return asm


## {"worst" mm, "worst_v", "at", "frames", "unsolved"} against th = 12 k deg
func engine_vs_closed(asm: Dictionary) -> Dictionary:
	var fr := AN.frames(asm)
	var worst := 0.0
	var worst_v := 0.0
	var at := ""
	var steps: Array = fr["steps"]
	for k in steps.size():
		var st: Dictionary = steps[k]
		var th_deg := 12.0 * k
		worst_v = maxf(worst_v, absf(float(st["values"].get("Crank", INF)) - th_deg))
		if not bool(st["ok"]):
			worst = INF
			continue
		var th := deg_to_rad(th_deg)
		var pp: Array = AL.world_mm(asm, st["states"], "p4", [0.0, 0.0, P.PIN_Z])
		var cp: Array = AL.world_mm(asm, st["states"], "p2", [0.0, P.R, 29.0])
		var e := maxf(maxf(absf(pp[0]), absf(pp[1] - x_closed(th))), maxf(absf(cp[0] - P.R * sin(th)), absf(cp[1] - P.R * cos(th))))
		if e > worst:
			worst = e
			at = "frame %d (%s deg): piston %s, crank pin %s" % [k, str(th_deg), str([snappedf(pp[0], 1e-6), snappedf(pp[1], 1e-6)]), str([snappedf(cp[0], 1e-6), snappedf(cp[1], 1e-6)])]
	return {"worst": worst, "worst_v": worst_v, "at": at, "frames": steps.size(), "unsolved": fr["unsolved"], "ms": fr["ms"]}


func bars_engine() -> void:
	var r := engine_vs_closed(engine_keyed(0.0, 720.0))
	ok(int(r["frames"]) == 61 and (r["unsolved"] as Array).is_empty() and float(r["worst_v"]) <= 1e-9 and float(r["worst"]) <= 1e-6, "b engine 0 -> 720 deg over 2 s at 30 fps: %d frames, drive vs 12 k deg worst %s, piston + crank pin vs the closed form worst %s mm (bar 1e-6; %s), %.1f ms" % [int(r["frames"]), sci(float(r["worst_v"])), sci(float(r["worst"])), r["at"], float(r["ms"])])
	var rc := engine_vs_closed(engine_keyed(720.0, 0.0))
	ctl(float(rc["worst"]) > 1.0, "b the reversed track (720 -> 0) is %.3f mm off (%s)" % [float(rc["worst"]), rc["at"]])


# ------------------------------------------------------------------ c
func box_rec(nm: String, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> Dictionary:
	var fs: Array = []
	var sk := "f1"
	fs.append({"t": "sketch", "id": sk, "name": "Sketch", "plane": "front", "ents": [{"k": "rect", "a": [x0, y0], "b": [x1, y1]}], "dims": []})
	fs.append({"t": "extrude", "id": "f2", "name": "Extrude", "sketch": sk, "dist": z1 - z0, "both": false, "op": "new"})
	var rec := Part.make(nm)
	rec["features"] = fs
	rec["seq"] = fs.size()
	return rec


## g1motion's hinge (lid_len 85 = the 5 mm longer lid)
func hinge(lid_len: float) -> Dictionary:
	var a := Assembly.make("Hinge %.0f" % lid_len)
	a["parts"] = [
		{"id": "p1", "name": "Base", "src": "", "rec": box_rec("Base", -10, -20, 0, 90, 0, 20), "pos": [0.0, 0.0, 0.0], "rot": [0.0, 0.0, 0.0]},
		{"id": "p2", "name": "Lid", "src": "", "rec": box_rec("Lid", 0, 0, 0, lid_len, 5, 20), "pos": [0.0, 0.0, 0.0], "rot": [0.0, 0.0, 0.0]},
		{"id": "p3", "name": "Ceiling", "src": "", "rec": box_rec("Ceiling", -20, 79, 0, 100, 89, 20), "pos": [0.0, 0.0, 0.0], "rot": [0.0, 0.0, 0.0]}]
	a["seq"] = 3
	AM.set_drive(a, AM.make_drive("Lid", "p2", "rotate", Vector3.BACK, Vector3.ZERO, 0.0, 70.0))
	return a


func lid_check(top: float, interp: String) -> Dictionary:
	var a := hinge(85.0)
	AN.set_key(a, "Lid", 0.0, 0.0, interp)
	AN.set_key(a, "Lid", 2.0, top, "linear")
	var r := AN.check(a)
	var first := INF
	var only := true
	for c in r["clashes"]:
		first = minf(first, float(c["t"]))
		var s := [String(c["a"]), String(c["b"])]
		s.sort()
		only = only and s == ["Ceiling", "Lid"]
	return {"r": r, "first": first, "only": only, "words": AN.words(a, r)}


func bars_clash_time() -> void:
	var th_hand := rad_to_deg(asin(79.0 / sqrt(85.0 * 85.0 + 25.0)) - atan2(5.0, 85.0))
	var t_lin := 2.0 * th_hand / 70.0
	var c := lid_check(70.0, "linear")
	ok(bool(c["r"]["ok"]) and c["only"] and float(c["first"]) >= t_lin and float(c["first"]) <= t_lin + 1.0 / 30.0, "c linear 0 -> 70 deg: first clash at %s s (hand onset %.4f s = %.2f deg; one frame %.4f s); %s; %d kernel calls, %d ms" % [str(c["first"]), t_lin, th_hand, 1.0 / 30.0, str(c["words"]), int(c["r"]["kernel_calls"]), int(c["r"]["ms"])])
	var lo := 0.0
	var hi := 1.0
	for i in 200:
		var mid := (lo + hi) * 0.5
		if smooth(mid) < th_hand / 70.0:
			lo = mid
		else:
			hi = mid
	var t_sm := 2.0 * hi
	var s := lid_check(70.0, "smooth")
	ok(bool(s["r"]["ok"]) and s["only"] and float(s["first"]) >= t_sm and float(s["first"]) <= t_sm + 1.0 / 30.0, "c smooth 0 -> 70 deg: first clash at %s s (hand onset %.4f s); %s" % [str(s["first"]), t_sm, str(s["words"])])
	var n := lid_check(60.0, "linear")
	ctl(bool(n["r"]["ok"]) and (n["r"]["clashes"] as Array).is_empty(), "c keyed 0 -> 60 deg (below the %.2f deg onset): %d clashes" % [th_hand, (n["r"]["clashes"] as Array).size()])


# ------------------------------------------------------------------ d
func load_png(p: String) -> Image:
	var im := Image.load_from_file(p)
	if im != null:
		im.convert(Image.FORMAT_RGB8)
	return im


## pixels of a that are not the background (a's corner)
func mask_of(a: Image) -> PackedByteArray:
	var w := a.get_width()
	var h := a.get_height()
	var bg := a.get_pixel(0, 0)
	var out := PackedByteArray()
	out.resize(w * h)
	for y in h:
		for x in w:
			out[y * w + x] = 1 if a.get_pixel(x, y) != bg else 0
	return out


func erode(mk: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	for y in h:
		for x in w:
			var keep := 1
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var xx := x + dx
					var yy := y + dy
					if xx < 0 or yy < 0 or xx >= w or yy >= h or mk[yy * w + xx] == 0:
						keep = 0
						break
				if keep == 0:
					break
			out[y * w + x] = keep
	return out


func count(mk: PackedByteArray) -> int:
	var n := 0
	for v in mk:
		n += v
	return n


## pixels inside mk where a and b differ
func diff_in(a: Image, b: Image, mk: PackedByteArray) -> int:
	var w := a.get_width()
	var da := a.get_data()
	var db := b.get_data()
	var n := 0
	for i in mk.size():
		if mk[i] == 1 and (da[i * 3] != db[i * 3] or da[i * 3 + 1] != db[i * 3 + 1] or da[i * 3 + 2] != db[i * 3 + 2]):
			n += 1
	return n


func bars_render() -> void:
	if DisplayServer.get_name() == "headless":
		ok(false, "d needs a screen (wtest runs windowed)")
		return
	var asm := engine_keyed(0.0, 720.0, 6)
	var base := {"width": 320, "height": 240}
	var o := base.duplicate()
	o["dir"] = OUT + "/d_full"
	var r: Dictionary = await AR.render(root, asm, o)
	var imgs: Array = []
	var sizes_ok := true
	for p in r.get("frames", []):
		var im := load_png(String(p))
		sizes_ok = sizes_ok and im != null and im.get_width() == 320 and im.get_height() == 240
		imgs.append(im)
	ok(bool(r["ok"]) and int(r["n"]) == 13 and imgs.size() == 13 and sizes_ok, "d %d frames written (want 13 = 2 s at 6 fps), each 320 x 240: %s; %d ms" % [int(r["n"]), str(sizes_ok), int(r["ms"])])
	var sh := load_png(String(r.get("sheet", "")))
	var tiles_ok := sh != null and int(r["tiles"]) == 13 and int(r["cols"]) == 4 and int(r["rows"]) == 4 and sh.get_width() == 4 * 256 and sh.get_height() == 4 * 192
	var bad_tiles: Array = []
	if tiles_ok:
		for i in 16:
			var reg := sh.get_region(Rect2i((i % 4) * 256, (i / 4) * 192, 256, 192))
			var want: Image
			if i < 13:
				want = AR.tile_of(imgs[i], 256, 192)
			else:
				want = Image.create(256, 192, false, Image.FORMAT_RGB8)
				want.fill(Color(0.2, 0.2, 0.22))
			if reg.get_data() != want.get_data():
				bad_tiles.append(i)
	ok(tiles_ok and bad_tiles.is_empty(), "d the sheet %s is %d x %d tiles (%s px), %d tiles; tiles not equal to their frame / the fill: %s" % [String(r.get("sheet", "")).get_file(), int(r["cols"]), int(r["rows"]), str(sh.get_size() if sh != null else Vector2i.ZERO), int(r["tiles"]), str(bad_tiles)])
	var op := base.duplicate()
	op["dir"] = OUT + "/d_piston"
	op["only"] = ["p4"]
	op["mp4"] = false
	op["sheet"] = false
	var rp: Dictionary = await AR.render(root, asm, op)
	var oh := base.duplicate()
	oh["dir"] = OUT + "/d_head"
	oh["only"] = ["p7"]
	oh["times"] = [0.0]
	oh["mp4"] = false
	oh["sheet"] = false
	var rh: Dictionary = await AR.render(root, asm, oh)
	var least := 1 << 30
	var mov: Array = []
	if imgs.size() == 13 and int(rp["n"]) == 13:
		var pm: Array = []
		for p in rp["frames"]:
			pm.append(mask_of(load_png(String(p))))
		for k in range(1, 13):
			var u := PackedByteArray()
			u.resize((pm[k] as PackedByteArray).size())
			for i in u.size():
				u[i] = 1 if (pm[k][i] == 1 or pm[k - 1][i] == 1) else 0
			var d := diff_in(imgs[k - 1], imgs[k], u)
			mov.append(d)
			least = mini(least, d)
	ok(mov.size() == 12 and least >= 100, "d consecutive frames differ where the piston is: %s pixels (least %d, bar 100)" % [str(mov), least])
	var head_n := 0
	var head_bad := -1
	if imgs.size() == 13 and int(rh["n"]) == 1:
		var hm := erode(mask_of(load_png(String(rh["frames"][0]))), 320, 240, 3)
		head_n = count(hm)
		head_bad = 0
		for k in range(1, 13):
			head_bad = maxi(head_bad, diff_in(imgs[0], imgs[k], hm))
	ok(head_n >= 500 and head_bad == 0, "d the head (static) covers %d pixels (eroded 3 px, bar 500); the most that differ from frame 0 in any frame: %d" % [head_n, head_bad])
	var ff := String(r.get("ffmpeg", ""))
	print("d  mp4: %s (ffmpeg %s)" % [String(r.get("mp4", "")) if String(r.get("mp4", "")) != "" else "none", ff if ff != "" else "not found: frames + sheet only"])
	ok(ff == "" or (String(r["mp4"]) != "" and FileAccess.get_file_as_bytes(String(r["mp4"])).size() > 1000), "d the .mp4 is written when ffmpeg is found: %s" % (String(r["mp4"]) if ff != "" else "no ffmpeg here"))
	var of := base.duplicate()
	of["dir"] = OUT + "/d_frozen"
	of["mp4"] = false
	var rf: Dictionary = await AR.render(root, engine_keyed(0.0, 0.0, 6), of)
	var same := int(rf["n"]) == 13
	var worst := 0
	if same:
		var f0 := load_png(String(rf["frames"][0]))
		var all1 := PackedByteArray()
		all1.resize(320 * 240)
		all1.fill(1)
		for k in range(1, 13):
			worst = maxi(worst, diff_in(f0, load_png(String(rf["frames"][k])), all1))
	ctl(same and worst == 0, "d a frozen track (0 -> 0): %d frames, the most pixels that differ from frame 0: %d" % [int(rf["n"]), worst])


# ------------------------------------------------------------------ e (the screen)
func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func key(code: int, uni := 0, ctrl := false) -> void:
	for dn in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = uni
		e.ctrl_pressed = ctrl
		e.pressed = dn
		root.push_input(e, true)
		await process_frame


func shot(nm: String) -> void:
	await idle(4)
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, nm])


func nd(nm: String) -> Node:
	return root.find_child(nm, true, false)


func piston_y_mm() -> float:
	return (A.meshes["p4"] as MeshInstance3D).transform.origin.y / Assembly.MM


func open_screen() -> void:
	var ss: StartScreen = m.start_screen
	ss.dirs_override = ["user://g7time_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(6)
	A = m.bld.asm
	m.build_choose.show_chooser()
	await idle(4)
	await click_ctl(nd("build_choose_assembly") as Button)
	await idle(4)


func bars_ui() -> void:
	await open_screen()
	A.open_record(P.loop_assembly())
	await idle(6)
	A.motion.open()
	await idle(4)
	var before := JSON.stringify(A.asm, "", true)
	var y_rec := piston_y_mm()
	var tsl := nd("asm_time_scrub") as HSlider
	var sl := nd("asm_motion_scrub") as HSlider
	tsl.value = 1.0
	await idle(3)
	ctl(absf(piston_y_mm() - y_rec) < 1e-9 and (nd("asm_time_play") as Button).disabled, "e with no keys the timeline at 1 s leaves the piston at %.4f mm (record %.4f); Play disabled: %s" % [piston_y_mm(), y_rec, str((nd("asm_time_play") as Button).disabled)])
	tsl.value = 0.0
	await idle(2)
	(nd("asm_time_interp") as OptionButton).select(1)
	await click_ctl(nd("asm_time_key") as Button)
	tsl.value = 2.0
	await idle(2)
	sl.value = 360.0
	await idle(2)
	(nd("asm_time_interp") as OptionButton).select(0)
	await click_ctl(nd("asm_time_key") as Button)
	var ks: Array = AN.track_of(A.asm, "Crank").get("keys", [])
	ok(ks == [[0.0, 0.0, "smooth"], [2.0, 360.0, "linear"]] and A.asm_undo.size() == 2, "e Key at 0 s (Smooth) and at 2 s (drive slider 360): keys %s, %d undo steps" % [str(ks), A.asm_undo.size()])
	tsl.value = 0.5
	await idle(3)
	var th := 360.0 * smooth(0.25)
	var wy := x_closed(deg_to_rad(th)) - P.PIN_Z
	var at_text := (nd("asm_motion_at") as Label).text
	ok(absf(piston_y_mm() - wy) <= 1e-4 and absf(A.motion.scrub.value - th) < 1e-6 and at_text.begins_with("0.5 s"), "e time 0.5 s: crank %s deg (hand 56.25), piston mesh %.5f mm (closed form - 34: %.5f, diff %s); '%s'" % [str(A.motion.scrub.value), piston_y_mm(), wy, sci(absf(piston_y_mm() - wy)), at_text])
	await shot("timeline")
	await click_ctl(nd("asm_time_play") as Button)
	var seen: Array = []
	var n := 0
	while A.motion.playing and n < 3000:
		await process_frame
		n += 1
		if n % 20 == 0:
			seen.append(snappedf(A.motion.time_t, 0.001))
	var rising := seen.size() >= 2
	for i in range(1, seen.size()):
		rising = rising and float(seen[i]) >= float(seen[i - 1])
	ok(not A.motion.playing and absf(A.motion.time_t - 2.0) < 1e-12 and absf(piston_y_mm() - y_rec) <= 1e-4 and rising, "e Play ran %d frames to %s s and stopped (times seen %s), piston %.5f mm (TDC %.5f)" % [n, str(A.motion.time_t), str(seen.slice(0, 6)), piston_y_mm(), y_rec])
	var vr: Dictionary = await A.export_video({"width": 320, "height": 180, "dir": OUT + "/e_video"})
	ok(int(vr.get("n", 0)) == 61 and String(vr.get("sheet", "")) != "" and A.last_export == vr, "e Export Video: %d frames (2 s at 30 fps), sheet %s, mp4 '%s'; '%s'" % [int(vr.get("n", 0)), String(vr.get("sheet", "")).get_file(), String(vr.get("mp4", "")).get_file(), A.status_text])
	await click_ctl(nd("asm_motion_run") as Button)
	await idle(3)
	var none := nd("asm_motion_none") as Label
	ok(none != null and none.text.contains("animation") and (A.motion.res.get("times", []) as Array).size() == 61 and nd("asm_motion_row_0") == null, "e Run along the timeline: %d frames, '%s'" % [(A.motion.res.get("times", []) as Array).size(), none.text if none != null else "(no line)"])
	tsl.value = 2.0
	await idle(2)
	await click_ctl(nd("asm_time_unkey") as Button)
	var ks2: Array = AN.track_of(A.asm, "Crank").get("keys", [])
	ok(ks2.size() == 1 and A.asm_undo.size() == 3, "e Delete key at 2 s: keys %s, %d undo steps" % [str(ks2), A.asm_undo.size()])
	m.get_viewport().gui_release_focus()
	for i in 3:
		await key(KEY_Z, 0, true)
		await idle(3)
	var after := JSON.stringify(A.asm, "", true)
	ok(after == before and not A.asm.has("anim") and absf(piston_y_mm() - y_rec) < 1e-6, "e three Ctrl+Z: the record is as before (%s), anim gone: %s, piston %.4f mm" % [str(after == before), str(not A.asm.has("anim")), piston_y_mm()])
	await shot("undone")


# ------------------------------------------------------------------ f
func sorted_json(path: String) -> String:
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	return JSON.stringify(j, "", true) if j != null else ""


func through_screen(path: String) -> String:
	var rec := Assembly.read(path)
	if rec.is_empty():
		return ""
	A.open_record(rec)
	await idle(4)
	A.motion.open()
	await idle(3)
	(nd("asm_time_scrub") as HSlider).value = 1.0
	await idle(2)
	A.motion.close()
	await idle(2)
	return Assembly.save(A.asm)   # no name: a name renames the record


func bars_old() -> void:
	var keep := Assembly.dir
	Assembly.dir = "user://g7time_old"
	var rows: Array = []
	var all_ok := true
	for p in [OLD, D199, J204]:
		var saved: String = await through_screen(p)
		var eq := saved != "" and sorted_json(saved) == sorted_json(p)
		all_ok = all_ok and eq
		rows.append("%s %s" % [String(p).get_file(), "equal" if eq else "DIFFERENT"])
	var j := Assembly.read(J204)
	ok(all_ok and not j.is_empty() and AL.has_joints(j) and not AN.has_anim(j), "f old records through the screen (timeline moved) save back: %s" % ", ".join(PackedStringArray(rows)))
	AN.set_key(j, "Crank", 0.0, 0.0)
	var pk := Assembly.save(j)
	ctl(sorted_json(pk) != sorted_json(J204), "f the #204 record with one key does not compare equal")
	Assembly.dir = keep


# ------------------------------------------------------------------ g
const CAM13 := {"pos": Vector3(0.21, 0.13, 0.40), "look": Vector3(0.0, 0.055, 0.039), "fov": 32.0}


func cap_px(img: Image) -> int:
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			for k in SectionLook.CAPS:
				if absf(c.r - k.r) < 0.03 and absf(c.g - k.g) < 0.03 and absf(c.b - k.b) < 0.03:
					n += 1
					break
	return n


func lines_between(path: String, a: String, b: String) -> int:
	var ls := FileAccess.get_file_as_string(path).split("\n")
	var i0 := -1
	for i in ls.size():
		if i0 < 0 and ls[i].contains(a):
			i0 = i
		elif i0 >= 0 and ls[i].contains(b):
			return i - i0 + 1
	return -1


func bars_payoff() -> void:
	# PAYOFF BEGIN
	var asm := P.loop_assembly()
	AN.set_key(asm, "Crank", 0.0, 0.0)
	AN.set_key(asm, "Crank", 2.0, 720.0)
	asm["anim"]["fps"] = 6
	var o := {"dir": OUT + "/g_sheet", "width": 512, "height": 720, "camera": CAM13, "sheet_cols": 6}
	var sheet: Dictionary = await AR.render(root, asm, o)
	var c := {"dir": OUT + "/g_section", "width": 512, "height": 720, "camera": CAM13, "times": [40.0 / 360.0], "mp4": false, "sheet": false}
	var whole: Dictionary = await AR.render(root, asm, c)
	c["dir"] = OUT + "/g_section_cut"
	c["cut"] = {"n": Vector3(0, 0, 1), "w": P.ZC * 0.001}
	var cut: Dictionary = await AR.render(root, asm, c)
	# PAYOFF END
	var cp := cap_px(load_png(String(cut["frames"][0]))) if int(cut.get("n", 0)) == 1 else -1
	var wp := cap_px(load_png(String(whole["frames"][0]))) if int(whole.get("n", 0)) == 1 else -1
	ok(bool(sheet["ok"]) and int(sheet["tiles"]) == 13 and int(sheet["cols"]) == 6 and cp >= 800, "g the CH13 sheet re-made: %d tiles (%d x %d) in %s; the section at 40 deg shows %d cap-colour pixels (ch13 bar i: >= 800)" % [int(sheet["tiles"]), int(sheet["cols"]), int(sheet["rows"]), String(sheet["sheet"]), cp])
	ctl(wp == 0, "g the uncut view has %d cap-colour pixels" % wp)
	var mine := lines_between("res://tests/g7time_test.gd", "# PAYOFF " + "BEGIN", "# PAYOFF " + "END") - 2
	var scene13 := FileAccess.get_file_as_string("res://scripts/build/ch13_scene.gd").split("\n").size()
	var grab13 := lines_between("res://tests/ch13_test.gd", "func grab() -> Image:", "print(\"sheet: ")
	print("g  PAYOFF: the helper call is %d lines; CH13 wrote ch13_scene.gd (%d lines) + grab / diff / cap / sheet in ch13_test.gd (%d lines) = %d" % [mine, scene13, grab13, scene13 + grab13])
	ok(mine > 0 and mine < scene13 + grab13, "g the helper call (%d lines) is shorter than CH13's own scene + grab code (%d lines)" % [mine, scene13 + grab13])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	if not Part.available() or not ClassDB.class_has_method("KineCAD", "overlap_volume"):
		ok(false, "the CAD DLL with overlap_volume is missing")
		print("g7time: %d fail" % fails)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	bars_interp()
	bars_engine()
	bars_clash_time()
	await bars_render()
	await bars_ui()
	await bars_old()
	await bars_payoff()
	print("g7time: %d fail" % fails)
	quit(1 if fails > 0 else 0)
