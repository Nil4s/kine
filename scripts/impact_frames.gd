## impact_frames.gd - I13 IMPACT FRAMES FROM THE HIT. Every contact the fighters' report finds (a Dummy.fighter_hits row on a body part)
## gets, scaled by its impulse J = m_eff x v_rel (HitPhysics.measure, I2's function: nothing is re-derived here):
##   HIT-STOP   both fighters freeze for round(lerp(2, 6, clamp((J - 5) / 20, 0, 1))) frames at 30 fps from the contact, and everything
##              after it (cards, part keys, IK, markers, the shot camera ...) shifts by exactly that hold. Game-feel practice: fighting
##              games hold a hit for a few frames, more for a heavier blow (Street Fighter II/IV: about 2-6 frames of hit-stop by
##              attack strength, Capcom's light / medium / heavy normals; Swink, "Game Feel", 2009, ch. 'Impact / hit pause').
##   SHAKE      the shot camera shakes (ShotFx event "Impact frames"): a damped oscillation, amplitude lerp(0.7, 3.0) cm x (0.6, 0.8, 1.0)
##              and lerp(0.5, 2.0) deg, 6 to 12 frames long, the decay heavier for a light blow (e-folds 5 -> 3), starting at the contact.
##   SQUASH     the struck part is scaled along the blow's direction, lerp(0.92, 0.85, u), the other two axes stretched by 1/sqrt(s) so the
##              volume stays (animation practice: a hit-stop squash is exaggerated for a few frames, 0.85-0.92 along the blow; Williams,
##              "The Animator's Survival Kit", squash and stretch keeps volume; Thomas & Johnston, "The Illusion of Life", ch. 3),
##              held through the stop and back over 3 frames:
##              an attribute "<part>.squash" (CustomAttr shape, keys x = scale, y/z = the direction's azimuth / elevation in the
##              struck fighter's body space), drawn by Overlays.pose_skeleton from Body.squash (Scene.apply sets it).
## The edit is tagged (cards "ihs" / "iho", camera keys "ih", the shake's name, the squash attribute's "ih", a marker "Hit-stop NF"
## whose note is "i13:<hold>"); remove() takes the tagged things out and shifts the rest back. The tags on cards and camera keys are
## not part of a card / key in the file, so the scene file carries a small "impact" record (record() / rehydrate(): the stops, the
## tagged cards by index, the tagged camera keys by shot and time, the shake's name, the squash attributes) and a reload puts the
## tags back: Remove works after save + load.
class_name ImpactFrames
extends RefCounted

const FPS := 30
const J_LO := 5.0
const J_HI := 25.0
const SHAKE_NAME := "Impact frames"
const MARK := "Hit-stop"
const TAG := "i13"
const SQUASH_FRAMES := 3


static func u_of(J: float) -> float:
	return clampf((J - J_LO) / (J_HI - J_LO), 0.0, 1.0)


static func stop_frames(J: float) -> int:
	return roundi(lerpf(2.0, 6.0, u_of(J)))


static func hold_s(frames: int) -> float:
	return snappedf(float(frames) / float(FPS), 0.001)


static func squash_scale(J: float) -> float:
	return lerpf(0.92, 0.85, u_of(J))


## the other two axes of a squash of s along the blow: 1/sqrt(s), the volume stays
static func stretch_of(s: float) -> float:
	return 1.0 / sqrt(maxf(s, 0.01))


## the camera shake of a blow of impulse J starting at t
static func shake(t: float, J: float, seed_n := 1) -> Dictionary:
	var u := u_of(J)
	var a := lerpf(0.7, 3.0, u)
	var b := lerpf(0.5, 2.0, u)
	return {"t": t, "dur": lerpf(6.0, 12.0, u) / float(FPS), "cm": Vector3(0.6, 0.8, 1.0) * a, "deg": Vector3(0.5, 0.3, 0.6) * b,
		"hz": 12.0, "decay": lerpf(5.0, 3.0, u), "seed": seed_n, "name": SHAKE_NAME}


## the largest camera offset (cm, length of the position vector) a shake event reaches, sampled at 1/240 s
static func shake_peak_cm(e: Dictionary) -> float:
	var best := 0.0
	var n := int(ceil(float(e["dur"]) * 240.0))
	for i in n + 1:
		var s := ShotFx.shake_at([e], float(e["t"]) + float(i) / 240.0)
		if not s.is_empty():
			best = maxf(best, (s["pos"] as Vector3).length() * 100.0)
	return best


## the blows of a list of fighters-report rows: [{"t", "J" (N s), "m_eff", "v_rel", "on", "victim" (actor index), "dir" (unit, the struck
## fighter's body space)}] by time. actors = actors_rt-like [{"S", "B", "xf"}]; a row that lands on a weapon or not on a body part is skipped.
## Two blows within 1.5 frames are one: the harder stays.
static func blows(actors: Array, rows: Array) -> Array:
	var out := []
	for r in rows:
		if not (r["kind"] == "hit" or r["kind"] == "struck") or Body.is_wep(String(r["on"])):
			continue
		var vk: int = 0 if r["by"] == "other" else int(r["vs"])
		var sk: int = int(r["vs"]) if r["by"] == "other" else 0
		var bl := HitPhysics.measure(actors[vk]["S"], actors[vk]["B"], actors[vk]["xf"], r, actors[sk]["B"])
		if not bl["ok"]:
			continue
		var Jv: Vector3 = bl["J"]
		var e := {"t": float(r["t"]), "J": float(bl["m_eff"]) * float(bl["v_rel"]), "m_eff": float(bl["m_eff"]), "v_rel": float(bl["v_rel"]),
			"on": String(r["on"]), "victim": vk, "dir": Jv.normalized() if Jv.length() > 1e-6 else Vector3(0, 0, 1)}
		out.append(e)
	out.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	var kept := []
	for e in out:
		if not kept.is_empty() and float(e["t"]) - float(kept[-1]["t"]) < 1.5 / float(FPS):
			if float(e["J"]) > float(kept[-1]["J"]):
				kept[-1] = e
			continue
		kept.append(e)
	return kept


## the plan: each blow with its frames, hold, and the time its contact has AFTER the earlier stops ("tf")
static func plan(bl: Array) -> Array:
	var out := []
	var acc := 0.0
	for e in bl:
		var p: Dictionary = e.duplicate()
		p["frames"] = stop_frames(float(e["J"]))
		p["hold"] = hold_s(int(p["frames"]))
		p["tf"] = float(e["t"]) + acc
		p["shift_before"] = acc
		p["squash"] = squash_scale(float(e["J"]))
		acc += float(p["hold"])
		out.append(p)
	return out


static func already(hero: Scene) -> bool:
	for mk in hero.markers:
		if String(mk.get("name", "")).begins_with(MARK) and String(mk.get("note", "")).begins_with(TAG):
			return true
	return false


## ---- the edit -------------------------------------------------------------------------------------------------------------

## scenes[0] is the hero (the markers and shots live there); bodies[k] poses scenes[k] (their state is put back)
static func apply(scenes: Array, bodies: Array, pl: Array) -> void:
	var acc := 0.0
	for p in pl:
		var tc: float = float(p["t"]) + acc
		var h: float = p["hold"]
		for k in scenes.size():
			var keep: Dictionary = (bodies[k] as Body).state()
			_hold(scenes[k], bodies[k], tc, h)
			(bodies[k] as Body).set_state(keep)
		acc += h
	var hero: Scene = scenes[0]
	var n := 0
	for p in pl:
		n += 1
		var tf: float = p["tf"]
		var h: float = p["hold"]
		var mk := Markers.add(hero.markers, tf, "%s %df" % [MARK, int(p["frames"])], "hit")
		mk["note"] = "%s:%s J=%.1f N s" % [TAG, str(h), float(p["J"])]
		var si := ShotCam.shot_index(hero.shots, tf)
		if si >= 0 and not (hero.shots[si]["keys"] as Array).is_empty():
			ShotFx.list(_fx(hero.shots[si]), "shake").append(shake(tf, float(p["J"]), n))
		_squash(scenes[int(p["victim"])], p, tf, h)


static func _fx(shot: Dictionary) -> Dictionary:
	if not shot.has("fx"):
		shot["fx"] = {}
	return shot["fx"]


## freeze scene S at t for h seconds: the card under t holds (or is split at t), and every timed thing after t shifts by h
static func _hold(S: Scene, B: Body, t: float, h: float) -> void:
	var ts: Array = S.times().duplicate(true)
	var i := -1
	for c in ts.size():
		if float(ts[c][2]) >= t - 1e-9:
			i = c
			break
	var cam := {}
	var cam_si := ShotCam.shot_index(S.shots, t)
	if cam_si >= 0:
		cam = ShotCam.sample(S.shots[cam_si]["keys"], t)
	if i < 0:
		i = S.cards.size() - 1
		S.cards[i]["iho"] = S.cards[i].get("iho", S.cards[i]["hold"])
		S.cards[i]["hold"] = float(S.cards[i]["hold"]) + h
	elif t >= float(ts[i][1]) - 1e-9 or i == 0:
		var c: Dictionary = S.cards[i]
		if not c.has("iho"):
			c["iho"] = c["hold"]
		c["hold"] = snappedf(float(c["hold"]) + h, 0.0001)
	else:
		S.apply(B, t)
		var x := {"name": "hit-stop", "pose": B.to_dict(), "move": t - float(ts[i][0]), "hold": h, "ease": "linear",
			"ihs": S.cards[i]["move"]}
		S.cards[i]["move"] = float(ts[i][1]) - t
		S.cards.insert(i, x)
	_shift(S, t, h)
	if not cam.is_empty():
		var keys: Array = S.shots[cam_si]["keys"]
		for tt in [t, t + h]:
			var n0 := keys.size()
			var kd := {"t": tt, "pos": cam["pos"], "aim": cam["aim"], "f": cam["f"]}
			var ex := ShotCam.key_near(keys, tt, 0.0005)
			if ex >= 0:
				continue   # a camera key of the user's is already there: it stays, untagged
			kd["ih"] = true
			ShotCam.put(keys, kd)
			if keys.size() == n0:
				continue


## every timed thing but the cards moves later by h where it is after t (the audio keeps its own clock)
static func _shift(S: Scene, t: float, h: float) -> void:
	var W := func(x: float) -> float: return x if x <= t + 1e-9 else x + h
	for j in S.part_keys:
		for key in S.part_keys[j]:
			key["t"] = W.call(float(key["t"]))
	for j in S.ik:
		for key in S.ik[j]:
			key["t"] = W.call(float(key["t"]))
	for L in S.layers:
		for kv in L.get("wk", []):
			kv[0] = W.call(float(kv[0]))
	for pr in S.props:
		for key in pr.get("keys", []):
			key["t"] = W.call(float(key["t"]))
	for arr in [S.markers, S.beats, S.lip.get("jaw", []), S.lip.get("mouth", [])]:
		for d in arr:
			d["t"] = W.call(float(d["t"]))
	for d in ShotCam.time_items(S.shots):
		if d.has("keys") and float(d["t"]) == 0.0:
			continue   # the first shot is cut at 0
		d["t"] = W.call(float(d["t"]))
	for n in S.notes:
		n["frame"] = roundi(W.call(float(n["frame"]) / float(maxi(S.fps, 1))) * float(maxi(S.fps, 1)))
	for j in S.secondary.get("keys", {}):
		for kv in S.secondary["keys"][j]:
			kv[0] = W.call(float(kv[0]))
	for c in S.clips:
		c["start"] = W.call(float(c["start"]))
	for pl in S.plants:
		pl["t0"] = W.call(float(pl["t0"]))
		pl["t1"] = W.call(float(pl["t1"]))
	for id in S.attrs:
		for key in S.attrs[id].get("keys", []):
			key["t"] = W.call(float(key["t"]))
	for j in S.face:
		if S.face[j] is Array:
			for key in S.face[j]:
				if key is Dictionary and key.has("t"):
					key["t"] = W.call(float(key["t"]))


static func _squash(Sv: Scene, p: Dictionary, tf: float, h: float) -> void:
	var part := HitReaction.joint_of(String(p["on"]))
	if not part in Body.ORDER:
		return
	var id := CustomAttr.id_of(part, "squash")
	if Sv.attrs.has(id) and not Sv.attrs[id].get("ih", false):
		return   # the user's own attribute of that name: left alone
	if not Sv.attrs.has(id):
		Sv.attrs[id] = {"min": 0.5, "max": 1.0, "default": 1.0, "keys": [], "ih": true}
	var d: Vector3 = p["dir"]
	var az := rad_to_deg(atan2(d.x, d.z))
	var el := rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
	var f := 1.0 / float(FPS)
	var pk := {id: Sv.attrs[id]["keys"]}
	for kv in [[tf - f, 1.0], [tf, float(p["squash"])], [tf + h, float(p["squash"])], [tf + h + float(SQUASH_FRAMES) * f, 1.0]]:
		if float(kv[0]) >= 0.0:
			PartKeys.put(pk, id, float(kv[0]), Vector3(float(kv[1]), az, el))
	Sv.attrs[id]["keys"] = pk[id]


## the squash the scene plays at t, for Body.squash: {joint: {"s", "dir" (body space)}} for the parts squashed more than 0.1 %
static func squash_at(S: Scene, t: float) -> Dictionary:
	var out := {}
	for id in S.attrs:
		if not String(id).ends_with(".squash"):
			continue
		var ks: Array = S.attrs[id].get("keys", [])
		if ks.is_empty():
			continue
		var v: Vector3 = PartKeys.value_at(ks, t)
		var s := clampf(v.x, 0.5, 1.0)
		if s > 0.999:
			continue
		var az := deg_to_rad(v.y)
		var el := deg_to_rad(v.z)
		out[CustomAttr.part_of(id)] = {"s": s, "dir": Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))}
	return out


## ---- the tags in the file ------------------------------------------------------------------------------------------------

## what Scene.to_dict writes as "impact" ({} = nothing tagged): {"stops": [{"t", "hold", "frames"}] (the hero's markers), "cards":
## [{"i", "tag" ("ihs" | "iho"), "v"}], "cam": [{"shot", "t"}], "shake": the name, "squash": [attribute ids]}
static func record(S: Scene) -> Dictionary:
	var cs := []
	for i in S.cards.size():
		var c: Dictionary = S.cards[i]
		if c.has("ihs"):
			cs.append({"i": i, "tag": "ihs", "v": float(c["ihs"])})
		elif c.has("iho"):
			cs.append({"i": i, "tag": "iho", "v": float(c["iho"])})
	var cam := []
	var shake := false
	for si in S.shots.size():
		for k in S.shots[si]["keys"]:
			if k.get("ih", false):
				cam.append({"shot": si, "t": float(k["t"])})
		for e in (S.shots[si].get("fx", {}) as Dictionary).get("shake", []):
			if String(e.get("name", "")) == SHAKE_NAME:
				shake = true
	var sq := []
	for id in S.attrs:
		if S.attrs[id].get("ih", false):
			sq.append(String(id))
	var stops := []
	for mk in S.markers:
		if String(mk.get("name", "")).begins_with(MARK) and String(mk.get("note", "")).begins_with(TAG + ":"):
			var fr := int(String(mk["name"]).get_slice(" ", 1).trim_suffix("f"))
			stops.append({"t": float(mk["t"]), "hold": float(String(mk["note"]).get_slice(":", 1).get_slice(" ", 0)), "frames": fr})
	if cs.is_empty() and cam.is_empty() and not shake and sq.is_empty() and stops.is_empty():
		return {}
	var out := {"stops": stops, "cards": cs, "cam": cam, "squash": sq}
	if shake:
		out["shake"] = SHAKE_NAME
	return out


## the file's "impact" record back onto the freshly loaded scene S: the card and camera-key tags (the others survive the file)
static func rehydrate(S: Scene, rec: Variant) -> void:
	if not (rec is Dictionary):
		return
	for e in rec.get("cards", []):
		var i := int(e.get("i", -1))
		if i < 0 or i >= S.cards.size():
			continue
		var tag := String(e.get("tag", ""))
		if tag == "ihs" and String(S.cards[i]["name"]) == "hit-stop":
			S.cards[i]["ihs"] = float(e["v"])
		elif tag == "iho":
			S.cards[i]["iho"] = float(e["v"])
	for e in rec.get("cam", []):
		var si := int(e.get("shot", -1))
		if si < 0 or si >= S.shots.size():
			continue
		var ks: Array = S.shots[si]["keys"]
		var ki := ShotCam.key_near(ks, float(e["t"]), 0.0005)
		if ki >= 0:
			ks[ki]["ih"] = true


## ---- remove by tag ------------------------------------------------------------------------------------------------------------

## takes the tagged impact frames out of the scenes (scenes[0] the hero) and shifts everything back. Returns how many stops went
static func remove(scenes: Array) -> int:
	var hero: Scene = scenes[0]
	var stops := []
	for mk in hero.markers:
		if String(mk.get("name", "")).begins_with(MARK) and String(mk.get("note", "")).begins_with(TAG + ":"):
			stops.append({"t": float(mk["t"]), "hold": float(String(mk["note"]).get_slice(":", 1).get_slice(" ", 0))})
	stops.sort_custom(func(a, b): return float(a["t"]) > float(b["t"]))
	for S in scenes:
		var sc: Scene = S
		for i in range(sc.cards.size() - 1, -1, -1):
			var c: Dictionary = sc.cards[i]
			if c.has("ihs"):
				sc.cards[i + 1]["move"] = c["ihs"]
				sc.cards.remove_at(i)
			elif c.has("iho"):
				c["hold"] = c["iho"]
				c.erase("iho")
		for id in sc.attrs.keys():
			if sc.attrs[id].get("ih", false):
				sc.attrs.erase(id)
		for sh in sc.shots:
			var fx: Dictionary = sh.get("fx", {})
			var sl: Array = fx.get("shake", [])
			for i in range(sl.size() - 1, -1, -1):
				if String(sl[i].get("name", "")) == SHAKE_NAME:
					sl.remove_at(i)
			if fx.has("shake") and sl.is_empty():
				fx.erase("shake")   # ShotFx.list made the key for our events
			var ks: Array = sh["keys"]
			for i in range(ks.size() - 1, -1, -1):
				if ks[i].get("ih", false):
					ks.remove_at(i)
	for st in stops:
		for S in scenes:
			_unshift(S, float(st["t"]), float(st["hold"]))
	for i in range(hero.markers.size() - 1, -1, -1):
		if String(hero.markers[i].get("name", "")).begins_with(MARK) and String(hero.markers[i].get("note", "")).begins_with(TAG + ":"):
			hero.markers.remove_at(i)
	return stops.size()


## undo of _shift: what is after t + h goes back by h (what is inside the stop goes to t)
static func _unshift(S: Scene, t: float, h: float) -> void:
	var W := func(x: float) -> float:
		var v := x
		if x > t + h - 1e-9:
			v = x - h
		elif x > t + 1e-9:
			v = t
		else:
			return x
		var g := snappedf(v, 0.001)
		return g if absf(g - v) < 1e-9 else v   # clean float dust on the millisecond grid
	for j in S.part_keys:
		for key in S.part_keys[j]:
			key["t"] = W.call(float(key["t"]))
	for j in S.ik:
		for key in S.ik[j]:
			key["t"] = W.call(float(key["t"]))
	for L in S.layers:
		for kv in L.get("wk", []):
			kv[0] = W.call(float(kv[0]))
	for pr in S.props:
		for key in pr.get("keys", []):
			key["t"] = W.call(float(key["t"]))
	for arr in [S.markers, S.beats, S.lip.get("jaw", []), S.lip.get("mouth", [])]:
		for d in arr:
			if String(d.get("name", "")).begins_with(MARK) and String(d.get("note", "")).begins_with(TAG + ":"):
				continue   # the stops' own markers go at the end
			d["t"] = W.call(float(d["t"]))
	for d in ShotCam.time_items(S.shots):
		if d.has("keys") and float(d["t"]) == 0.0:
			continue
		d["t"] = W.call(float(d["t"]))
	for n in S.notes:
		n["frame"] = roundi(W.call(float(n["frame"]) / float(maxi(S.fps, 1))) * float(maxi(S.fps, 1)))
	for j in S.secondary.get("keys", {}):
		for kv in S.secondary["keys"][j]:
			kv[0] = W.call(float(kv[0]))
	for c in S.clips:
		c["start"] = W.call(float(c["start"]))
	for pl in S.plants:
		pl["t0"] = W.call(float(pl["t0"]))
		pl["t1"] = W.call(float(pl["t1"]))
	for id in S.attrs:
		for key in S.attrs[id].get("keys", []):
			key["t"] = W.call(float(key["t"]))
	for j in S.face:
		if S.face[j] is Array:
			for key in S.face[j]:
				if key is Dictionary and key.has("t"):
					key["t"] = W.call(float(key["t"]))
