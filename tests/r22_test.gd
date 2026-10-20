## godot --path . -s tests/r22_test.gd     (ROUND 2 R22: face expressions on cards. Needs a window: run as :w)
## Bars written before the first run. Source: FACS (Ekman & Friesen 1978): pain AU4+6/7+9/10+43, effort AU4+7+24,
## anger AU4+5+7+23, surprise AU1+2+5+26 (the table is Face.EXPR_AU).
##  (1) FEATURES on the drawn head (brow node height above the neutral face, along the head's up): anger and pain brows are
##      lowered >= 6 mm, effort >= 3 mm, surprise raised >= 6 mm; the mouth node's height for surprise >= 2x the neutral
##      mouth's; anger's and effort's lips are pressed (mouth height <= neutral's); anger's eye is wider than the pain eye
##  (2) BLEND: card 1 anger after neutral card 0; at the middle of the move the brow value is strictly between the two and
##      within 0.03 of half of anger's; weights sum to 1; at card 1 the weight of anger is 1.
##  (3) SAVE/LOAD: to_dict -> JSON -> from_dict keeps every card's expr; neutral is not written
##  (4) OLD SCENES: combo3.json (no expr) has expr_at == {} and its to_dict has no "expr" key on any card; the face reads the
##      same as Face.pose with no expression
##  (5) UNDO: _set_expr is ONE undo step; undo restores the cards exactly (var_to_str); redo puts it back; a hit-labelled card
##      suggests pain (Face.suggest) and an ordinary one does not
##  (6) PLACEMENT (whole body, dist 4.6): for each of the 5 expressions every feature (brows, eyes, irises, mouth) projects inside
##      the head mesh's screen hull AND within the top 15 % of the body's screen height (head top to the floor)
##  (7) screenshot of the 5 expressions side by side when R22_SHOT is set
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the head piece's triangles, skinned by the skeleton's pose now: corner points in world space, three per triangle
func skinned_head(mm: Node) -> PackedVector3Array:
	var sk: Skeleton3D = mm.skel
	var pc: MeshInstance3D = mm.pieces["head"]
	var sn: Skin = pc.skin
	var out := PackedVector3Array()
	for si in pc.mesh.get_surface_count():
		var arr := pc.mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wt: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var per := bo.size() / vs.size()
		var cache := {}
		for i in ix:
			if not cache.has(i):
				var p := Vector3.ZERO
				for q in per:
					var w := wt[i * per + q]
					if w <= 0.0:
						continue
					var bi := bo[i * per + q]
					var bn: int = sn.get_bind_bone(bi) if sn.get_bind_bone(bi) >= 0 else bi
					p += w * ((sk.global_transform * sk.get_bone_global_pose(bn) * sn.get_bind_pose(bi)) * vs[i])
				cache[i] = p
			out.append(cache[i])
	return out


func feats() -> Dictionary:
	return {"brow_l": m.face_brow[0], "brow_r": m.face_brow[1], "eye_l": m.face_eye[0], "eye_r": m.face_eye[1],
		"iris_l": m.face_pupil[0], "iris_r": m.face_pupil[1], "mouth": m.mouth_mi}


## dress card `i` with `ex`, put the playhead on it, draw; returns the readings
func wear(i: int, ex: String) -> Dictionary:
	m.S.set_expr(i, ex)
	m.sel_card = i
	m.playhead = m.S.times()[i][1]
	m._face_draw()
	await idle(2)
	var up: Vector3 = (m.B.G["head"] as Quaternion) * Vector3(0, 1, 0)
	var f := feats()
	return {"brow": ((f["brow_l"] as Node3D).global_position.dot(up) + (f["brow_r"] as Node3D).global_position.dot(up)) * 0.5,
		"mouth_y": (f["mouth"] as Node3D).global_transform.basis.get_scale().y,
		"eye_h": (f["eye_l"] as Node3D).global_transform.basis.get_scale().y}


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	m._commands()
	var S: Scene = m.S

	# (4) old scene first: nothing set
	var d0: Dictionary = S.to_dict(m.B, false)
	var any_expr := false
	for c in d0["cards"]:
		if c.has("expr"):
			any_expr = true
	var pn := Face.pose({}, {}, 0.0)
	var pe := Face.at(S.face, S.lip, 0.0, S.expr_at(0.0))
	ok(S.expr_at(0.5).is_empty() and not any_expr and var_to_str(pn["brow_l"]) == var_to_str(pe["brow_l"]) and pn["mouth"] == pe["mouth"],
		"4 old scene (combo3, %d cards): expr_at is empty, no card writes expr, the face reads as without expressions" % S.cards.size())
	var base_cards := var_to_str(S.cards)

	# (1) features
	m.S.face = {}
	var last := S.cards.size() - 1
	S.set_expr(last, "effort")   # a scene with no expression draws no face at all (old scenes); one card with one turns it on
	var r := {}
	for ex in Face.EXPRESSIONS:
		r[ex] = await wear(0, ex)
	for ex in Face.EXPRESSIONS:
		print("   %-9s brow %+.1f mm  mouth_h %.2f mm  eye_h %.2f mm" % [ex, (float(r[ex]["brow"]) - float(r["neutral"]["brow"])) * 1000.0, float(r[ex]["mouth_y"]) * 1000.0, float(r[ex]["eye_h"]) * 1000.0])
	var nb := float(r["neutral"]["brow"])
	ok(nb - float(r["anger"]["brow"]) >= 0.006 and nb - float(r["pain"]["brow"]) >= 0.006 and nb - float(r["effort"]["brow"]) >= 0.003,
		"1 brows lowered: anger %.1f, pain %.1f, effort %.1f mm (bars 6, 6, 3)" % [(nb - float(r["anger"]["brow"])) * 1000.0, (nb - float(r["pain"]["brow"])) * 1000.0, (nb - float(r["effort"]["brow"])) * 1000.0])
	ok(float(r["surprise"]["brow"]) - nb >= 0.006, "1 surprise brows raised %.1f mm (bar 6)" % ((float(r["surprise"]["brow"]) - nb) * 1000.0))
	ok(float(r["surprise"]["mouth_y"]) >= 2.0 * float(r["neutral"]["mouth_y"]), "1 surprise opens the mouth: %.2f mm vs neutral %.2f (bar 2x)" % [float(r["surprise"]["mouth_y"]) * 1000.0, float(r["neutral"]["mouth_y"]) * 1000.0])
	ok(float(r["anger"]["mouth_y"]) <= float(r["neutral"]["mouth_y"]) + 1e-6 and float(r["effort"]["mouth_y"]) <= float(r["neutral"]["mouth_y"]) + 1e-6,
		"1 anger and effort press the lips (mouth height <= neutral)")
	ok(float(r["anger"]["eye_h"]) > float(r["pain"]["eye_h"]), "1 anger eyes wider (AU5) than pain (AU6/7+43): %.2f vs %.2f mm" % [float(r["anger"]["eye_h"]) * 1000.0, float(r["pain"]["eye_h"]) * 1000.0])

	# (2) blend between card 0 (neutral) and card 1 (anger)
	S.set_expr(0, "neutral")
	S.set_expr(1, "anger")
	var ts := S.times()
	var tm := (float(ts[0][2]) + float(ts[1][1])) * 0.5
	var w := S.expr_at(tm)
	var full := Face.at(S.face, S.lip, ts[1][1], S.expr_at(ts[1][1]))
	var mid := Face.at(S.face, S.lip, tm, w)
	var bm := float(mid["brow_l"])
	var bf := float(full["brow_l"])
	var wsum := 0.0
	for k in w:
		wsum += float(w[k])
	ok(float(ts[1][1]) > float(ts[0][2]) and bm < 0.0 and bm > bf and absf(bm - 0.5 * bf) <= 0.03 and absf(wsum - 1.0) < 1e-6 and absf(float(S.expr_at(ts[1][1])["anger"]) - 1.0) < 1e-6,
		"2 blend: brow at mid-move %.3f is between neutral 0 and anger %.3f (half is %.3f), weights sum %.3f" % [bm, bf, 0.5 * bf, wsum])

	# (3) save / load
	var k2 := 2 if S.cards.size() > 2 else 1
	S.set_expr(k2, "pain")
	var dd: Dictionary = S.to_dict(m.B, false)
	var back: Dictionary = JSON.parse_string(JSON.stringify(dd))
	var S2 := Scene.new()
	S2.from_dict(back)
	var same := S2.cards.size() == S.cards.size()
	for i in S.cards.size():
		if same and String(S.cards[i].get("expr", "neutral")) != String(S2.cards[i].get("expr", "neutral")):
			same = false
	ok(same and String(dd["cards"][k2]["expr"]) == "pain" and not dd["cards"][0].has("expr"), "3 round trip keeps every card's expression; neutral card 0 writes no key")

	# (5) undo
	S.set_expr(1, "neutral")
	S.set_expr(k2, "neutral")
	S.set_expr(last, "neutral")
	m.sel_card = 1
	var before := var_to_str(S.cards)
	ok(before == base_cards, "5 cards back to the loaded state before the undo test")
	var u0: int = m.undo.size()
	m._set_expr(1, "surprise")
	await idle(2)
	var changed: bool = String(m.S.cards[1].get("expr", "")) == "surprise"
	ok(changed and m.undo.size() == u0 + 1, "5 _set_expr is one undo step (%d)" % (m.undo.size() - u0))
	m._undo()
	await idle(2)
	ok(var_to_str(m.S.cards) == before, "5 undo restores the cards exactly")
	m._redo()
	await idle(2)
	ok(String(m.S.cards[1].get("expr", "")) == "surprise", "5 redo puts it back")
	m._undo()
	await idle(2)
	ok(Face.suggest("hit 1") == "pain" and Face.suggest("hit at") == "pain" and Face.suggest("flinch") == "pain" and Face.suggest("guard") == "" and Face.suggest("whitehall") == "",
		"5 hit / reaction cards suggest pain, others do not")
	S = m.S

	# (6) placement, whole body
	if m.dummy_on:
		m._dummy_toggle()
	if m.ui_toast != null:
		m.ui_toast.visible = false
	m._turn_to(0.0, -5.0, 4.6, Vector3(0, 0.95, 0), false)
	await idle(3)
	S.set_expr(last, "effort")
	var worst_frac := 0.0
	var in_hull := 0
	var total := 0
	for ex in Face.EXPRESSIONS:
		await wear(0, ex)
		await idle(2)
		var skin := skinned_head(m)
		var pts := PackedVector2Array()
		var top := -INF
		for v in skin:
			pts.append(m.cam.unproject_position(v))
			top = maxf(top, v.y)
		var hull := Geometry2D.convex_hull(pts)
		var y_top: float = m.cam.unproject_position(Vector3(0, top, 0)).y
		var y_floor: float = m.cam.unproject_position(Vector3(0, 0, 0)).y
		var body_px := y_floor - y_top
		var f := feats()
		for k in f:
			var sp: Vector2 = m.cam.unproject_position((f[k] as Node3D).global_position)
			total += 1
			if Geometry2D.is_point_in_polygon(sp, hull):
				in_hull += 1
			worst_frac = maxf(worst_frac, (sp.y - y_top) / body_px)
	S.set_expr(0, "neutral")
	ok(in_hull == total and worst_frac <= 0.15, "6 placement: %d of %d features inside the head's screen hull; lowest feature is %.1f %% of body height below the head top (bar 15 %%)" % [in_hull, total, worst_frac * 100.0])

	# (7) the shot
	var shot := OS.get_environment("R22_SHOT")
	if shot != "":
		var hc: Vector3 = m.face_at(m.face_geo["eye_l"]) * 0.5 + m.face_at(m.face_geo["eye_r"]) * 0.5 - Vector3(0, 0.03, 0)
		m._turn_to(0.0, -5.0, 0.7, hc, false)
		await idle(3)
		var tiles := []
		for ex in Face.EXPRESSIONS:
			await wear(0, ex)
			await idle(2)
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			var sp: Vector2 = m.cam.unproject_position(hc)
			var rr := Rect2i(int(sp.x) - 150, int(sp.y) - 150, 300, 300).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			var tile := img.get_region(rr)
			tile.convert(Image.FORMAT_RGBA8)
			tiles.append(tile)
		var sheet := Image.create(300 * tiles.size(), 300, false, Image.FORMAT_RGBA8)
		for i in tiles.size():
			sheet.blit_rect(tiles[i], Rect2i(Vector2i.ZERO, tiles[i].get_size()), Vector2i(300 * i, 0))
		sheet.save_png(shot)
		ok(FileAccess.file_exists(shot), "7 five expressions saved to %s" % shot)
	print("R22 TEST %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	quit(fails)
