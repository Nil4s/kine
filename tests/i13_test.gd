## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/i13_test.gd     (ROADMAP I13; a window)
## IMPACT FRAMES FROM THE HIT (scripts/impact_frames.gd, impact_frames_ui.gd, the commands "Add impact frames" / "Remove impact frames").
## Hero: 5 cards, a shot camera keyed; fighter 2 stands in front. Three hits (rows as Dummy.fighter_hits gives them, impulse by I2's
## HitPhysics.measure): a light jab (hand on the head, J ~ 5), a body punch (J ~ 15), a bat to the head (J ~ 27). Bars, before measuring:
##   1 FRAMES: the jab gets 2 frames of hit-stop, the bat 6, the punch between (3..5); J, frames, shake peak rise monotone over the 3 hits
##     and the squash scale falls monotone (0.92 -> 0.85, the other axes 1/sqrt(s): volume kept).
##   2 SHAKE: the jab's camera shake peaks at 0.5-1.2 cm, the bat's at 3.5-4.6 cm (ShotFx.shake_at sampled at 1/240 s); the shake lives on
##     the shot camera (shots[0].fx.shake, name 'Impact frames'), one per hit at the contact's time.
##   3 TIMES: after the edit every card boundary, part key, marker and camera key that was after a hit moved by exactly the holds before
##     it (1e-6 s); the contacts' spacing grew by exactly the earlier hold; BOTH fighters' scenes are as long as before + the 3 holds.
##   4 HOLD: during each stop (at the middle of the hold) both fighters' bodies are where they were at the contact (1 mm), and the pose at
##     the stop's start equals the old scene's pose at the contact (2 mm: the card was split there).
##   5 PREVIEW: Preview and 20 ticks of it leave both fighters' scenes (JSON) and the shots unchanged; the preview scenes are longer.
##   6 ACCEPT: one undo step; Ctrl+Z restores both scenes exactly (JSON), redo puts the edit back exactly.
##   7 REMOVE: 'Remove impact frames' (one undo step) restores both scenes exactly (JSON); its undo puts the frames back.
##   8 SQUASH: the struck part's squash is 0.97 / ~0.93 / 0.90 at the three contacts (Body.squash), 1 three frames after each stop, its direction
##     within 3 degrees of the blow's; in the app the head bone of fighter 2 is scaled along that direction at the bat's contact, and the
##     picture shows the stop marked on the timeline (hit-stop markers drawn, inside the window).
##  10 SAVED TAGS (I13 step 2): accept, save to user://i13b_<pid>.json, reload, 'Remove impact frames' -> JSON-equal to the original, 3 stops removed.
##  11 PREVIEW SHAKE: during the preview the viewport camera is shaken at a contact (its transform differs from the unshaken one by the
##     shake's size, within 25 % of the event's offset) and back exactly after; the scenes stay untouched.
##  12 VISIBLE SQUASH: at the bat's contact the head bone is scaled 0.85 +-0.03 along the blow, the other axes > 1.03 (volume within 6 %),
##     and the head is inside the window in the closer framing used for the picture.
##   9 REAL CONTACT: combo3 against a standing fighter 2: 'Add impact frames' finds the contact, Accept adds >= 1 hit-stop of 2..6 frames, one undo.
extends SceneTree

var fails := 0
var m: Node
const D0 := 1.2
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i13b.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func pose_of(arm: float) -> Dictionary:
	var b := body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.set_ang("upperarm_r", Vector3(0, 0, arm))
	b.ground()
	return b.to_dict()


func hero_scene() -> Scene:
	var s := Scene.new()
	s.from_dict({"scene": "zz_i13", "fps": 30, "cards": [
		{"name": "a", "pose": pose_of(0), "move": -1.0, "hold": 0.5},
		{"name": "b", "pose": pose_of(80), "move": 0.6, "hold": 0.4},
		{"name": "c", "pose": pose_of(0), "move": 0.6, "hold": 0.5},
		{"name": "d", "pose": pose_of(80), "move": 0.6, "hold": 0.4},
		{"name": "e", "pose": pose_of(0), "move": 0.6, "hold": 0.5}]})
	s.shots = [{"t": 0.0, "name": "Shot 1", "keys": [], "fx": {}}]
	ShotCam.put(s.shots[0]["keys"], {"t": 0.0, "pos": Vector3(2.6, 1.4, -1.0), "aim": Vector3(0, 1.1, 0.6), "f": 40.0})
	ShotCam.put(s.shots[0]["keys"], {"t": 4.0, "pos": Vector3(2.2, 1.4, -0.4), "aim": Vector3(0, 1.1, 0.6), "f": 40.0})
	PartKeys.put(s.part_keys, "head", 3.4, Vector3(10, 0, 0))
	PartKeys.put(s.part_keys, "head", 4.0, Vector3(0, 0, 0))
	Markers.add(s.markers, 1.2, "mid", "note")
	return s


func still() -> Scene:
	var p := pose_of(0)
	var s := Scene.new()
	s.from_dict({"scene": "zz_still", "fps": 30, "cards": [{"name": "a", "pose": p, "move": -1.0, "hold": 2.0}, {"name": "b", "pose": p, "move": 0.5, "hold": 3.0}]})
	return s


func sj(s: Scene) -> String:
	var d := s.to_dict(body())
	d.erase("actors")
	return JSON.stringify(d) + var_to_str(s.shots) + var_to_str(s.attrs)


func all_json() -> String:
	return sj(m.actors_rt[0]["S"]) + "|" + sj(m.actors_rt[1]["S"])


## a hit row as Dummy.fighter_hits gives it, in the hero's space: the striker's part moves along the victim's -z (toward it) at v
func row(Bv: Body, xf: Transform3D, part: String, on: String, v: float, t: float) -> Dictionary:
	var a: Array = Bv.cap(on)
	var mid := ((a[0] as Vector3) + (a[1] as Vector3)) * 0.5
	return {"t": t, "kind": "hit", "zone": "X", "part": part, "on": on, "by": "hero", "vs": 1, "u": 0.6, "depth": 0.01, "speed": v,
		"at": xf * (mid + Vector3(0, 0, float(Bv.rad[on]))), "vec": xf.basis * Vector3(0, 0, -v)}


func J_of(r: Dictionary) -> float:
	var bl := HitPhysics.measure(m.actors_rt[1]["S"], m.actors_rt[1]["B"], m.actors_rt[1]["xf"], r, m.actors_rt[0]["B"])
	return float(bl["m_eff"]) * float(bl["v_rel"])


func norm_fx() -> void:
	for a in m.actors_rt:
		for sh in (a["S"] as Scene).shots:
			sh["fx"] = ShotFx.clean(sh.get("fx", {}))
			if String(sh.get("light", "")) == "":
				sh.erase("light")   # a file load writes "light": "" for none


func pos_at(S: Scene, j: String, t: float) -> Vector3:
	var b := body()
	S.apply(b, t)
	return b.P[j]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var hero := hero_scene()
	m.S = hero
	m._rebuild_cards()
	hero.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, D0], "yaw": 180.0}, "scene": still()})
	m._actors_sync()
	m._page_set("STAGE", false)
	m._refresh()
	await idle(2)
	var xf: Transform3D = m.actors_rt[1]["xf"]
	var Bv: Body = m.actors_rt[1]["B"]
	var hs: Scene = m.actors_rt[0]["S"]
	var fs: Scene = m.actors_rt[1]["S"]
	# the three blows, their speeds chosen from the effective masses so the impulses land near 5 / 15 / 27 N s
	var fist_m := J_of(row(Bv, xf, "hand_r", "head", 1.0, 0.8))
	var bat_m := J_of(row(Bv, xf, "bat_barrel", "head", 1.0, 2.0))
	var rows := [row(Bv, xf, "hand_r", "head", 5.0 / fist_m, 0.8), row(Bv, xf, "hand_r", "spine_03", 15.0 / fist_m, 2.0), row(Bv, xf, "bat_barrel", "head", 27.0 / bat_m, 3.0)]
	var bl := ImpactFrames.blows(m.actors_rt, rows)
	var pl := ImpactFrames.plan(bl)
	ok(pl.size() == 3, "3 blows found; m_eff fist %.2f kg, bat %.2f kg" % [fist_m, bat_m])
	var Js: Array = pl.map(func(p): return snappedf(float(p["J"]), 0.1))
	var fr: Array = pl.map(func(p): return int(p["frames"]))
	var pk: Array = pl.map(func(p): return ImpactFrames.shake_peak_cm(ImpactFrames.shake(float(p["tf"]), float(p["J"]))))
	var sq: Array = pl.map(func(p): return float(p["squash"]))
	print("     J %s, frames %s, shake peak cm %s, squash %s" % [Js, fr, pk.map(func(x): return snappedf(x, 0.01)), sq.map(func(x): return snappedf(x, 0.001))])
	ok(fr[0] == 2 and fr[2] == 6 and fr[1] >= 3 and fr[1] <= 5, "1 frames: jab %d (bar 2), punch %d (3..5), bat %d (bar 6)" % [fr[0], fr[1], fr[2]])
	ok(Js[0] < Js[1] and Js[1] < Js[2] and fr[0] <= fr[1] and fr[1] <= fr[2] and pk[0] < pk[1] and pk[1] < pk[2] and sq[0] > sq[1] and sq[1] > sq[2], "1 monotone in J over the 3 hits: J, frames, shake peak rise, squash falls")
	ok(pk[0] >= 0.5 and pk[0] <= 1.2 and pk[2] >= 3.5 and pk[2] <= 4.6 and absf(sq[0] - 0.92) < 0.01 and absf(sq[2] - 0.85) < 0.005, "2 jab shake %.2f cm (0.5-1.2), bat shake %.2f cm (3.5-4.6); squash %.3f .. %.3f" % [pk[0], pk[2], sq[0], sq[2]])

	# 3 - 4, 6, 7: the edit
	var before := all_json()
	var len_h := hs.length()
	var len_f := fs.length()
	var ts_old: Array = hs.times().duplicate(true)
	var pk_old := float(hs.part_keys["head"][0]["t"])
	var mk_old := float(hs.markers[0]["t"])
	var cam_old := float(hs.shots[0]["keys"][1]["t"])
	var pose_old := [pos_at(hs, "hand_r", 0.8), pos_at(hs, "hand_r", 2.0), pos_at(hs, "hand_r", 3.0)]
	var pose_old_v := [pos_at(fs, "head", 0.8), pos_at(fs, "head", 2.0), pos_at(fs, "head", 3.0)]
	var steps0: int = m.undo.size()
	m.if_ui.commit(pl)
	await idle(2)
	var steps: int = m.undo.size() - steps0
	var after := all_json()
	var holds := pl.map(func(p): return float(p["hold"]))
	var total := 0.0
	for h in holds:
		total += h
	ok(absf(hs.length() - (len_h + total)) < 1e-6 and absf(fs.length() - (len_f + total)) < 1e-6, "3 both fighters grew by exactly the holds: hero %.4f -> %.4f, fighter 2 %.4f -> %.4f (holds %s = %.4f)" % [len_h, hs.length(), len_f, fs.length(), holds, total])
	var hs_ts: Array = hs.times()
	var worst := 0.0
	# card boundaries: the original card k's arrival (k = 2, 3, 4 after hits at 0.8, 2.0, 3.0): shifted by the holds of the hits before it
	var shift_at := func(t: float) -> float:
		var s := 0.0
		for p in pl:
			if float(p["t"]) < t - 1e-9:
				s += float(p["hold"])
		return s
	var by_name := {}
	for i in hs.cards.size():
		by_name[hs.cards[i]["name"]] = hs_ts[i]
	for k in ["a", "b", "c", "d", "e"]:
		var oi: int = ["a", "b", "c", "d", "e"].find(k)
		var want: float = float(ts_old[oi][1]) + float(shift_at.call(float(ts_old[oi][1])))
		worst = maxf(worst, absf(float(by_name[k][1]) - want))
	worst = maxf(worst, absf(float(hs.part_keys["head"][0]["t"]) - (pk_old + float(shift_at.call(pk_old)))))
	worst = maxf(worst, absf(float(hs.markers[hs.markers.size() - 1]["t"]) - (mk_old + float(shift_at.call(mk_old)))) if false else 0.0)
	var mk_new := -1.0
	for mk in hs.markers:
		if mk["name"] == "mid":
			mk_new = float(mk["t"])
	worst = maxf(worst, absf(mk_new - (mk_old + float(shift_at.call(mk_old)))))
	var cam_new := -1.0
	for kk in hs.shots[0]["keys"]:
		if absf(float(kk["t"]) - (cam_old + total)) < 1e-6:
			cam_new = float(kk["t"])
	worst = maxf(worst, absf(cam_new - (cam_old + total)))
	ok(worst < 1e-6, "3 every card arrival, part key, marker and camera key after a hit moved by exactly the holds before it: worst error %s s" % str(worst))
	ok(absf((float(pl[1]["tf"]) - float(pl[0]["tf"])) - ((float(pl[1]["t"]) - float(pl[0]["t"])) + holds[0])) < 1e-9 and absf((float(pl[2]["tf"]) - float(pl[1]["tf"])) - ((float(pl[2]["t"]) - float(pl[1]["t"])) + holds[1])) < 1e-9,
		"3 the contacts keep their spacing plus exactly the earlier hold")
	var frozen := true
	var kept := true
	var info := []
	for i in 3:
		var p: Dictionary = pl[i]
		var tf: float = p["tf"]
		var mid_t := tf + float(p["hold"]) * 0.5
		var d_h := pos_at(hs, "hand_r", mid_t).distance_to(pos_at(hs, "hand_r", tf))
		var d_f := pos_at(fs, "head", mid_t).distance_to(pos_at(fs, "head", tf))
		var d_old := pos_at(hs, "hand_r", tf).distance_to(pose_old[i])
		info.append("%.2f/%.2f/%.1f mm" % [d_h * 1000.0, d_f * 1000.0, d_old * 1000.0])
		frozen = frozen and d_h < 0.001 and d_f < 0.001
		kept = kept and d_old < 0.002
	ok(frozen, "4 both fighters are still mid-stop (hand / head drift, mm): %s" % ", ".join(info))
	ok(kept, "4 the pose at each stop's start is the old scene's pose at the contact (hand, mm in the list above)")
	var shakes: Array = hs.shots[0]["fx"].get("shake", [])
	var on_time := shakes.size() == 3
	for i in shakes.size():
		on_time = on_time and absf(float(shakes[i]["t"]) - float(pl[i]["tf"])) < 1e-9 and shakes[i]["name"] == "Impact frames"
	ok(on_time, "2 three shake events on the shot camera, each at its contact's time")
	ok(steps == 1, "6 one undo step (%d)" % steps)

	# 8 squash
	var vals := []
	var dirok := true
	for i in 3:
		var p: Dictionary = pl[i]
		var tf: float = p["tf"]
		var s_at: Dictionary = ImpactFrames.squash_at(fs, tf + 1e-4)
		var j := HitReaction.joint_of(String(p["on"]))
		vals.append(float(s_at[j]["s"]) if s_at.has(j) else -1.0)
		if s_at.has(j):
			dirok = dirok and rad_to_deg((s_at[j]["dir"] as Vector3).angle_to(p["dir"])) < 3.0
		var late := ImpactFrames.squash_at(fs, tf + float(p["hold"]) + 4.0 / 30.0)
		ok(not late.has(j) or float(late[j]["s"]) > 0.999, "8 squash of the %s is back to 1 four frames after the stop (%s)" % [j, str(late.get(j, "gone"))])
	ok(absf(vals[0] - 0.92) < 0.004 and absf(vals[2] - 0.85) < 0.004 and vals[1] < vals[0] and vals[1] > vals[2] and dirok, "8 squash at the contacts %s (0.92 / ~0.885 / 0.85), direction within 3 deg of the blow's: %s" % [vals.map(func(x): return snappedf(x, 0.001)), dirok])

	# the picture: the bat's contact, whole body, the stops marked on the timeline
	m.playhead = float(pl[2]["tf"]) + 0.02
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	await idle(3)
	var man: Dictionary = m.actor_men[1]
	var sk: Skeleton3D = man["skel"]
	var hi: int = man["idx"]["head"]
	var rot := sk.get_bone_global_pose(hi).basis
	var sc := sk.get_bone_pose_scale(hi)
	var smin := minf(sc.x, minf(sc.y, sc.z))
	var smax := maxf(sc.x, maxf(sc.y, sc.z))
	ok(smin < 0.88 and smin > 0.82 and smax > 1.03 and absf(sc.x * sc.y * sc.z - 1.0) < 0.06, "12 in the app the head bone of fighter 2 is squashed at the bat's contact: bone scale %s (min %.3f along the blow, max %.3f, volume %.3f)" % [sc, smin, smax, sc.x * sc.y * sc.z])
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var mks_ok := 0
	for mk in hs.markers:
		if String(mk["name"]).begins_with("Hit-stop"):
			mks_ok += 1
	ok(mks_ok == 3, "8 three 'Hit-stop' markers on the timeline (%s), the timeline in a %s window" % [hs.markers.filter(func(x): return String(x["name"]).begins_with("Hit-stop")).map(func(x): return "%s @ %.3f" % [x["name"], x["t"]]), vp])
	var head_px: Vector2 = m.cam.unproject_position(m._stage_xf() * (m.actors_rt[1]["xf"] as Transform3D) * ((m.actors_rt[1]["B"] as Body).P["head"] as Vector3))
	ok(Rect2(Vector2.ZERO, vp).has_point(head_px), "8 placement: the struck head is drawn inside the window at %s" % head_px)
	# the picture: closer on the struck head (the whole-body placement was checked above)
	m.target = m._stage_xf() * (m.actors_rt[1]["xf"] as Transform3D) * ((m.actors_rt[1]["B"] as Body).P["head"] as Vector3)
	m.dist = 2.2
	m.yaw = -90.0   # from the side: the blow runs along the view's horizontal, so the flattening shows in profile
	m.pitch = 8.0
	m._cam()
	await idle(3)
	var head_px2: Vector2 = m.cam.unproject_position(m._stage_xf() * (m.actors_rt[1]["xf"] as Transform3D) * ((m.actors_rt[1]["B"] as Body).P["head"] as Vector3))
	ok(Rect2(Vector2.ZERO, vp).grow(-80).has_point(head_px2), "12 the squashed head is well inside the window in the close picture: %s" % head_px2)
	# the same view 3 frames before the contact (no squash yet), for the picture's left half
	var t_stop: float = m.playhead
	m.playhead = float(pl[2]["tf"]) - 0.1
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	m._cam()
	await idle(3)
	await RenderingServer.frame_post_draw
	var img_b: Image = m.get_viewport().get_texture().get_image()
	m.playhead = t_stop
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	m._cam()
	await idle(3)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	var img_a: Image = m.get_viewport().get_texture().get_image()
	var box := Rect2i(Vector2i(int(head_px2.x) - 260, int(head_px2.y) - 330), Vector2i(520, 600))
	var img := Image.create(1040, 600, false, img_a.get_format())
	img.blit_rect(img_b, box, Vector2i(0, 0))
	img.blit_rect(img_a, box, Vector2i(520, 0))   # left: before the blow, right: at the hit-stop (head squashed)
	ok(img.save_png(SHOT) == OK, "picture saved: %s" % SHOT)

	# 6 undo / redo
	m._undo()
	await idle(2)
	ok(all_json() == before, "6 Ctrl+Z restores both scenes exactly (JSON)")
	m._redo()
	await idle(2)
	ok(all_json() == after, "6 redo puts the impact frames back exactly")

	# 7 remove
	var u1: int = m.undo.size()
	m.if_ui.remove()
	await idle(2)
	if all_json() != before:
		var a_ := all_json()
		var k_ := 0
		while k_ < a_.length() and k_ < before.length() and a_[k_] == before[k_]:
			k_ += 1
		print("     DIFF at %d: now ...%s | before ...%s" % [k_, a_.substr(maxi(0, k_ - 60), 160), before.substr(maxi(0, k_ - 60), 160)])
	ok(m.undo.size() - u1 == 1 and all_json() == before, "7 'Remove impact frames' is one step and restores both scenes exactly (JSON equal: %s, steps %d)" % [all_json() == before, m.undo.size() - u1])
	m._undo()
	await idle(2)
	ok(all_json() == after, "7 its undo puts the frames back exactly")
	m._undo()
	await idle(2)

	# 5 preview
	var b5 := all_json()
	m.if_ui.pl = pl
	m.if_ui.preview()
	var longer: bool = (m.if_ui.pv[0] as Scene).length() > hs.length() + 0.3
	for i in 20:
		m.if_ui.tick(0.05)
		await process_frame
	var mid_pv: bool = not m.if_ui.pv.is_empty()
	m.if_ui.halt()
	await idle(2)
	ok(longer and all_json() == b5, "5 preview: its scenes are longer (%s), both fighters' scenes and the shots are unchanged (JSON) after 20 ticks (still playing at tick 20: %s)" % [longer, mid_pv])

	# 11 preview shake: the viewport camera shakes at a contact, the scenes stay, the camera comes back exactly
	m.dist = 3.0
	m._cam()
	var base_xf: Transform3D = m.cam.transform
	var b11 := all_json()
	m.if_ui.pl = pl
	m.if_ui.preview()
	m.if_ui.pv_t = float(pl[2]["tf"]) + 0.03
	m.if_ui.tick(0.0)
	var shk: Dictionary = m.if_ui.shaking
	var moved: float = (m.cam.transform.origin - base_xf.origin).length() * 100.0
	var want_cm: float = (shk["pos"] as Vector3).length() * 100.0 if not shk.is_empty() else -1.0
	var turned := rad_to_deg((m.cam.transform.basis.get_rotation_quaternion()).angle_to(base_xf.basis.get_rotation_quaternion()))
	ok(not shk.is_empty() and moved > 0.2 and absf(moved - want_cm) < 0.03 * want_cm + 0.01 and turned > 0.05, "11 preview shake at the bat's contact: camera moved %.2f cm (shake %.2f cm), turned %.2f deg" % [moved, want_cm, turned])
	m.if_ui.halt()
	await idle(2)
	ok(m.cam.transform.origin.distance_to(base_xf.origin) < 1e-6 and m.cam.transform.basis.get_rotation_quaternion().angle_to(base_xf.basis.get_rotation_quaternion()) < 1e-6 and all_json() == b11, "11 after the preview the camera is back exactly and the scenes are untouched")

	# 10 saved tags: accept, save, reload, remove -> JSON-equal to the original
	norm_fx()
	var orig10 := all_json()
	m.if_ui.commit(pl)
	await idle(2)
	var path10 := "user://i13b_%d.json" % OS.get_process_id()
	var d10: Dictionary = (m.actors_rt[0]["S"] as Scene).to_dict(m.actors_rt[0]["B"])
	var f10 := FileAccess.open(path10, FileAccess.WRITE)
	f10.store_string(JSON.stringify(d10))
	f10.close()
	var im: Dictionary = d10.get("impact", {})
	ok(not im.is_empty() and (im["cards"] as Array).size() > 0 and (im["cam"] as Array).size() > 0 and (im["stops"] as Array).size() == 3, "10 the file carries an impact record: %s tagged cards, %s camera keys, %s stops, shake '%s', squash %s" % [im.get("cards", []).size(), im.get("cam", []).size(), im.get("stops", []).size(), im.get("shake", ""), im.get("squash", [])])
	m._load_scene(path10)
	m._rebuild_cards()
	await idle(2)
	m._actors_sync()
	m._refresh()
	await idle(2)
	var loaded: Scene = m.actors_rt[0]["S"]
	var tags := 0
	for c in loaded.cards:
		tags += 1 if (c.has("ihs") or c.has("iho")) else 0
	ok(tags > 0 and ImpactFrames.already(loaded), "10 after the reload the card tags are back (%d tagged cards) and the stops are found" % tags)
	var u10: int = m.undo.size()
	m.if_ui.remove()
	await idle(2)
	norm_fx()   # a file load writes an empty fx as {"focus": []}: the same thing (ShotFx.clean), not a tag
	var rem := all_json()
	if rem != orig10:
		var k10 := 0
		while k10 < rem.length() and k10 < orig10.length() and rem[k10] == orig10[k10]:
			k10 += 1
		print("     DIFF at %d: now ...%s | orig ...%s" % [k10, rem.substr(maxi(0, k10 - 60), 160), orig10.substr(maxi(0, k10 - 60), 160)])
	ok(rem == orig10 and m.undo.size() - u10 == 1, "10 save + reload + 'Remove impact frames': JSON-equal to the original (%s), one undo step" % [rem == orig10])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path10))

	# 9 real contact: combo3 against a standing fighter 2
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, D0], "yaw": 180.0}, "scene": still()})
	m._actors_sync()
	m._refresh()
	await idle()
	var b9 := all_json()
	var real: Array = m.if_ui.compute()
	var u9: int = m.undo.size()
	if not real.is_empty():
		m.if_ui.commit(real)
	await idle(2)
	var nstop := 0
	var okf := true
	for mk in m.actors_rt[0]["S"].markers:
		if String(mk["name"]).begins_with("Hit-stop"):
			nstop += 1
	for p in real:
		okf = okf and int(p["frames"]) >= 2 and int(p["frames"]) <= 6
	ok(not real.is_empty() and nstop == real.size() and okf and m.undo.size() - u9 == 1, "9 combo3 vs a standing fighter: %d contact(s) %s, %d hit-stop marker(s), one undo step" % [real.size(), real.map(func(p): return "%.2fs J %.1f -> %d f" % [p["t"], p["J"], p["frames"]]), nstop])
	m._undo()
	await idle(2)
	ok(all_json() == b9, "9 its undo restores both scenes exactly")
	print("I13 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(0 if fails == 0 else 1)
