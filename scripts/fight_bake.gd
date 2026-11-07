## fight_bake.gd - L76: the fight maths of L72 / L74 BAKED onto a real two-body clip (Scene with Scene.actors). Pure functions on Scenes; the app wraps each call in ONE undo step
## (main.gd _fight_*; the agent tools in fight_bake_serve.gd).
##   contacts(S)               the hero's strike that lands on a partner: frame, t, striker, region (RegionReact.pick), struck side, impulse, flags
##   bake_reaction(S, c, o)    RegionReact.react's joint deltas become ONE card on the partner, arriving at contact + max(drop_delay, MIN_RISE)
##   fix_impact(S)             ImpactAlign's fix pose is written into the card(s) that bracket the contact frame
##   bake_momentum(S, c, o)    BodyCollide's post-hit velocities become root-offset cards on BOTH bodies (the change against the no-hit slide)
## A card is spliced in by SPLICE: when the body HOLDS a pose at the contact the hold is cut at the contact and the new cards follow (every earlier frame is exactly the same);
## when the body is MOVING at the contact a card with the sampled pose is put at the contact first (the move into it is re-timed: not exact, reported as "exact": false).
## Assumptions (ours): the striking mass M_EFF (punch 3 kg, kick 6 kg) times the tip speed is the impulse; the region comes from the fist's height on the partner.
class_name FightBake
extends RefCounted

const FPS := 60
const REACH := 0.25        # m: the fist within this of the partner's SKIN (nearest body capsule surface) at the contact frame is a contact (the frame is the fastest one, just before the hit lands)
const MIN_RISE := 0.08     # s: the soonest a reaction card can arrive (a drop_delay of 0 still needs time to move)
const HOLD_END := 0.25     # s: the last baked card is held this long
const M_EFF := {"punch": 3.0, "kick": 6.0}
const EPS := 1e-4


static func new_body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b


## fist height (fraction of the partner's height) and lateral side -> an anatomy tag
static func tag_of(yf: float, lx: float) -> Dictionary:
	var right := lx < 0.0   # the partner's right is -x in his own space
	if yf >= 0.85:
		return {"tag": "face", "y": yf, "head_y": clampf((yf - 0.85) / 0.15, 0.0, 1.0)}
	if yf >= 0.6:
		return {"tag": "abdominals", "y": yf, "head_y": 0.5}
	if yf >= 0.45:
		return {"tag": "obliques_r" if right else "obliques_l", "y": yf, "head_y": 0.5}
	return {"tag": "quadriceps_r" if right else "quadriceps_l", "y": yf, "head_y": 0.5}


static func contacts(S: Scene, fps := FPS) -> Array:
	if S.actors.is_empty() or S.cards.size() < 2:
		return []
	var r := ImpactAlign.scene_check(S, fps)
	if not bool(r.get("ok", false)) or int(r.get("frame", -1)) < 0:
		return []
	var f := int(r["frame"])
	var t := float(f) / float(fps)
	var key: String = r["striker"]
	if key == "weapon":   # a held weapon is not a hand / foot strike: not baked (limit)
		return []
	var b := new_body()
	S.apply(b, t)
	var tip: Vector3 = b.E[key]
	S.apply(b, t + 1.0 / float(fps))
	var tip2: Vector3 = b.E[key]
	var speed := (tip2 - tip).length() * float(fps)
	if speed < 1.0:   # the last frame: look back
		S.apply(b, maxf(t - 1.0 / float(fps), 0.0))
		speed = (tip - (b.E[key] as Vector3)).length() * float(fps)
	var best := -1
	var best_d := INF
	var best_tag := {}
	for k in S.actors.size():
		var Sx: Scene = S.actors[k]["scene"]
		var pb := new_body()
		Sx.apply(pb, t)
		var xf := Constraints.actor_xf(S.actors[k]["xf"])
		var lt: Vector3 = xf.affine_inverse() * tip
		var root: Vector3 = pb.P["pelvis"]
		var H: float = (pb.P["head"] as Vector3).y + 0.12
		var d := skin_distance(pb, lt)
		if d <= REACH and d < best_d:
			best = k
			best_d = d
			best_tag = tag_of(clampf(lt.y / H, 0.0, 1.0), lt.x - root.x)
	if best < 0:
		return []
	var kind := String(r["striker"]).begins_with("foot")
	var kd := "kick" if kind else "punch"
	var tg: String = best_tag["tag"]
	var rules := []
	for fl in r["flags"]:
		rules.append(fl["rule"])
	return [{"frame": f, "t": t, "striker": key, "kind": kd, "side": String(key).right(1), "speed": speed, "partner": best,
		"tag": tg, "y": best_tag["y"], "head_y": best_tag["head_y"], "region": RegionReact.pick(tg, best_tag["y"], best_tag["head_y"]),
		"struck": tg.right(1) if tg.ends_with("_l") or tg.ends_with("_r") else "r", "impulse": float(M_EFF[kd]) * speed, "skin_m": best_d, "flags": rules}]


## distance (m) from a point (the body's own space) to the nearest body capsule surface; 0 inside
static func skin_distance(pb: Body, pt: Vector3) -> float:
	var best := INF
	for part in Body.BODY + Body.WIDE.keys():
		var c: Array = pb.cap(part)
		var a: Vector3 = c[0]
		var ab: Vector3 = (c[1] as Vector3) - a
		var den := ab.length_squared()
		var u := clampf((pt - a).dot(ab) / den, 0.0, 1.0) if den > 1e-12 else 0.0
		best = minf(best, maxf((pt - (a + ab * u)).length() - float(pb.rad[part]), 0.0))
	return best


# ---------------------------------------------------------------- cards

## where time t falls in the scene's cards: {i, mode: hold | move | tail}
static func find(Sx: Scene, t: float) -> Dictionary:
	var ts := Sx.times()
	for i in ts.size():
		var tt: Array = ts[i]
		if t >= float(tt[1]) - EPS and t <= float(tt[2]) + EPS:
			return {"i": i, "mode": "hold"}
		if t > float(tt[0]) and t < float(tt[1]):
			return {"i": i, "mode": "move"}
	return {"i": ts.size() - 1, "mode": "tail"}


## a card pose that reads as the scene at time t (the template's other keys kept)
static func pose_at(Sx: Scene, t: float, template: Dictionary) -> Dictionary:
	var s := Sx.sample(t)
	var p: Dictionary = template.duplicate(true)
	var a: Dictionary = s["ang"]
	for j in a:
		var v: Vector3 = a[j]
		if not (p["joints"] as Dictionary).has(j):
			p["joints"][j] = {}
		p["joints"][j]["bend"] = v.x
		p["joints"][j]["side"] = v.y
		p["joints"][j]["twist"] = v.z
	var o: Vector3 = s["offset"]
	p["offset"] = [o.x, o.y, o.z]
	return p


static func limits() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/body_limits.json"))


## add (bend, side, twist) deg to a joint of a pose, clamped into body_limits; returns the delta really applied
static func add_joint(p: Dictionary, j: String, d: Vector3, lim: Dictionary) -> Vector3:
	if not (p["joints"] as Dictionary).has(j):
		p["joints"][j] = {"bend": 0.0, "side": 0.0, "twist": 0.0}
	var x: Dictionary = p["joints"][j]
	var old := Vector3(x["bend"], x["side"], x["twist"])
	var v := old + d
	var L: Dictionary = lim.get(j.replace("_l", "_r") if j.ends_with("_l") else j, {})
	if not L.is_empty():
		v.x = clampf(v.x, L["bend"][0], L["bend"][1])
		v.y = clampf(v.y, L["side"][0], L["side"][1])
		v.z = clampf(v.z, L["twist"][0], L["twist"][1])
	x["bend"] = v.x
	x["side"] = v.y
	x["twist"] = v.z
	return v - old


## cut the scene at T and insert cards after it. make(base_pose) -> [{dt, pose}] (each card arrives dt after the one before; the last is held HOLD_END)
static func splice(Sx: Scene, T: float, make: Callable) -> Dictionary:
	if Sx.cards.is_empty() or T < 0.0:
		return {"ok": false, "error": "no cards at that time"}
	var f := find(Sx, T)
	var ts := Sx.times()
	var i: int = f["i"]
	var mode: String = f["mode"]
	var base: Dictionary
	var at := i + 1
	if mode == "move":
		base = pose_at(Sx, T, Sx.cards[i]["pose"])
		Sx.cards.insert(i, {"name": "contact", "pose": base.duplicate(true), "move": T - float(ts[i][0]), "hold": 0.0})
		at = i + 1
	else:
		base = (Sx.cards[i]["pose"] as Dictionary).duplicate(true)
		Sx.cards[i]["hold"] = maxf(T - float(ts[i][1]), 0.0)
	var steps: Array = make.call(base)
	for k in steps.size():
		var st: Dictionary = steps[k]
		Sx.cards.insert(at + k, {"name": String(st.get("name", "hit")), "pose": st["pose"], "move": maxf(float(st["dt"]), 0.02), "hold": HOLD_END if k == steps.size() - 1 else 0.0})
	return {"ok": true, "mode": mode, "exact": mode != "move"}


# ---------------------------------------------------------------- reaction

static func bake_reaction(S: Scene, c: Dictionary, o := {}) -> Dictionary:
	var real := contacts(S, FPS)
	var hit := false
	for r in real:
		if int(r["frame"]) == int(c.get("frame", -1)):
			hit = true
	if not hit:
		return {"ok": false, "error": "no contact at that frame: there is nothing to bake a reaction onto"}
	var k := int(c.get("partner", 0))
	var Sx: Scene = S.actors[k]["scene"]
	var tag: String = String(o.get("tag", c.get("tag", "abdominals")))
	var region: String = String(o.get("region", ""))
	if region == "":
		region = RegionReact.pick(tag, float(o.get("y", c.get("y", 0.5))), float(o.get("head_y", c.get("head_y", 0.5))))
	var dflt := tag.right(1) if tag.ends_with("_l") or tag.ends_with("_r") else String(c.get("struck", "r"))
	var side: String = String(o.get("side", dflt))
	var J: float = float(o.get("impulse", c.get("impulse", 60.0)))
	var rr := RegionReact.react(region, J, side)
	if (rr["joints"] as Dictionary).is_empty():
		return {"ok": false, "error": "region '%s' has no reaction pattern (a hit there is not baked)" % region}
	var T: float = float(c["t"])
	var rise := maxf(float(rr["drop_delay_s"]), MIN_RISE)
	var lim := limits()
	var applied := {}
	var sp := splice(Sx, T, func(base: Dictionary):
		var p: Dictionary = base.duplicate(true)
		for j in rr["joints"]:
			applied[j] = add_joint(p, String(j), rr["joints"][j], lim)
		return [{"name": "hit " + region, "dt": rise, "pose": p}])
	if not bool(sp.get("ok", false)):
		return sp
	return {"ok": true, "region": region, "side": side, "impulse": J, "amp": rr["amp"], "t_contact": T, "t_arrive": T + rise, "drop_delay_s": rr["drop_delay_s"],
		"expected": applied, "exact": sp["exact"], "partner": k}


# ---------------------------------------------------------------- impact fix

static func fix_impact(S: Scene, fps := FPS) -> Dictionary:
	var r := ImpactAlign.scene_check(S, fps)
	if not bool(r.get("ok", false)) or int(r.get("frame", -1)) < 0:
		return {"ok": false, "error": "no strike in the scene: nothing to fix"}
	if (r["flags"] as Array).is_empty():
		return {"ok": false, "error": "the impact at frame %d is clean: nothing to fix" % int(r["frame"])}
	var T := float(int(r["frame"])) / float(fps)
	var f := find(S, T)
	var i: int = f["i"]
	var idx := [i]
	if f["mode"] == "move" and i >= 1:
		idx = [i - 1, i]
	var ts := S.times()
	var first_t: float = float(ts[idx[0]][0])
	var lim := limits()
	var rules := []
	for fl in r["flags"]:
		rules.append(fl["rule"])
		for j in fl["fix"]:
			var fv: Vector3 = fl["fix"][j]
			for ci in idx:
				var p: Dictionary = (S.cards[ci]["pose"] as Dictionary).duplicate(true)
				if not (p["joints"] as Dictionary).has(j):
					continue
				var x: Dictionary = p["joints"][j]
				if String(fl["rule"]).begins_with("WRIST"):
					x["bend"] = fv.x
					x["side"] = fv.y
				else:
					x["bend"] = maxf(float(x["bend"]), fv.x)
				var L: Dictionary = lim.get(String(j).replace("_l", "_r") if String(j).ends_with("_l") else String(j), {})
				if not L.is_empty():
					x["bend"] = clampf(float(x["bend"]), L["bend"][0], L["bend"][1])
					x["side"] = clampf(float(x["side"]), L["side"][0], L["side"][1])
				S.cards[ci]["pose"] = p
	return {"ok": true, "frame": int(r["frame"]), "t": T, "rules": rules, "cards": idx, "first_changed_t": first_t}


# ---------------------------------------------------------------- momentum

static func root_velocity(Sx: Scene, xf: Transform3D, t: float, fps := FPS) -> Vector3:
	var b := new_body()
	Sx.apply(b, t)
	var p0: Vector3 = b.P["pelvis"]
	Sx.apply(b, t + 1.0 / float(fps))
	var p1: Vector3 = b.P["pelvis"]
	var v: Vector3 = xf.basis * ((p1 - p0) * float(fps))
	v.y = 0.0
	return v


static func _offset_steps(deltas: Array) -> Callable:
	return func(base: Dictionary):
		var steps := []
		var prev := 0.0
		var o0: Array = base.get("offset", [0.0, 0.0, 0.0])
		for k in deltas:
			var p: Dictionary = base.duplicate(true)
			var d: Vector3 = k["d"]
			p["offset"] = [float(o0[0]) + d.x, float(o0[1]) + d.y, float(o0[2]) + d.z]
			steps.append({"name": "push", "dt": float(k["t"]) - prev, "pose": p})
			prev = float(k["t"])
		return steps


static func bake_momentum(S: Scene, c: Dictionary, o := {}) -> Dictionary:
	if S.actors.is_empty():
		return {"ok": false, "error": "bake_momentum needs a scene with a partner"}
	var k := int(c.get("partner", 0))
	var Sx: Scene = S.actors[k]["scene"]
	var xf := Constraints.actor_xf(S.actors[k]["xf"])
	var T: float = float(c["t"])
	var mass := ThrowFixtures.mass_of(new_body())
	var ma: float = float(o.get("m_a", mass))
	var mb: float = float(o.get("m_b", mass))
	var va: Vector3 = o.get("v_a", root_velocity(S, Transform3D.IDENTITY, T))
	var vb: Vector3 = o.get("v_b", root_velocity(Sx, xf, T))
	if (va - vb).length() < 0.05:
		return {"ok": false, "error": "no closing speed at the contact (%.2f m/s): nothing to share" % (va - vb).length()}
	var col := BodyCollide.charge(ma, va, mb, vb, String(o.get("sex", "male")), float(o.get("e", 0.1)))
	var k0a: Array = BodyCollide._keys(va)
	var k0b: Array = BodyCollide._keys(vb)
	var da := []
	var db := []
	for q in range(1, BodyCollide.KEY_T.size()):
		da.append({"t": BodyCollide.KEY_T[q], "d": (col["keys_a"][q]["pos"] as Vector3) - (k0a[q]["pos"] as Vector3)})
		db.append({"t": BodyCollide.KEY_T[q], "d": xf.basis.inverse() * ((col["keys_b"][q]["pos"] as Vector3) - (k0b[q]["pos"] as Vector3))})
	var sa := splice(S, T, _offset_steps(da))
	var sb := splice(Sx, T, _offset_steps(db))
	if not bool(sa.get("ok", false)) or not bool(sb.get("ok", false)):
		return {"ok": false, "error": "could not key the roots"}
	return {"ok": true, "t_contact": T, "t_end": T + float(BodyCollide.KEY_T[BodyCollide.KEY_T.size() - 1]), "p_before": col["p_before"], "p_after": col["p_after"],
		"dv_a": col["dv_a"], "dv_b": col["dv_b"], "exact": bool(sa["exact"]) and bool(sb["exact"]), "end_a": da.back()["d"], "end_b": db.back()["d"]}


static func to_json(v: Variant) -> Variant:
	if v is Vector3:
		return [v.x, v.y, v.z]
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = to_json(v[k])
		return o
	if v is Array:
		return v.map(func(x): return to_json(x))
	return v
