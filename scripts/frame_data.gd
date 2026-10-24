## frame_data.gd - FIGHTING-GAME FRAME DATA (ROADMAP 12). Terms as the community uses them: docs/research/FRAME_DATA.md.
##
## Frames run 0 .. n-1 at `fps` (60 by default; the scene's own 30 fps is only its card timing). Frame f is the pose at t = f / fps.
##   STARTUP   = the frames before the first ACTIVE frame (frame 0 is the scene's first card, the "input").
##   ACTIVE    = first active frame .. last active frame (the count includes any inactive gap; `gaps` says how many).
##   RECOVERY  = the frames after the last active frame up to the scene's end.
##   startup + active + recovery = n.
## A frame is ACTIVE when the striking part's tip (the bat's tip; with no weapon, the striking hand or foot whose tip
## moves fastest in the scene) is moving faster than TIP_SPEED m/s AND toward the target side, OR (with a dummy /
## second fighter placed) the weapon is in the opponent's body (Dummy.touch). "Toward" = along dir: +Z (the hero faces
## +Z) or, with a dummy, the horizontal direction from the hero to it.
## HITBOXES (active frames only): the weapon's two capsules (Body.cap bat_handle / bat_barrel, radii B.rad), or with no
## weapon the striker's two limb capsules. HURTBOXES (every frame): the body capsules (Body.BODY + Body.WIDE).
## HIT / HURT BOXES (ROADMAP 36, hit_boxes.gd): the scene's boxes are added on the frames they cover. A hit box the user
## drew is in "hitboxes" with src "box" whether or not the frame is active (the active frames stay the auto-detected
## ones); the hurtboxes are the body's capsules with the edits applied (off = left out, scale = the radius times).
## Units: metres, +Y up (the body's own space).
class_name FrameData
extends RefCounted

const TIP_SPEED := 8.0      # m/s: the tip must move faster than this (a real bat strike is 10-20 m/s; combo3 peaks above it)
const FPS := 60             # the game's frame rate (a setting in the UI)
const STRIKERS := ["hand_r", "hand_l", "foot_r", "foot_l"]
const STRIKE_CAPS := {"hand_r": ["lowerarm_r", "hand_r"], "hand_l": ["lowerarm_l", "hand_l"],
	"foot_r": ["calf_r", "foot_r"], "foot_l": ["calf_l", "foot_l"]}


## the frame data of scene S played on body B (at `fps`). `dummy` = the opponent placed where it stands (or null).
## Leaves B posed at the scene's last frame. Returns {} for an empty scene.
static func analyze(S: Scene, B: Body, fps := FPS, dummy: Dummy = null) -> Dictionary:
	var N := int(round(S.length() * float(fps)))
	if N < 1 or S.cards.is_empty():
		return {}
	var raw := []
	for f in N:
		S.apply(B, float(f) / float(fps))
		var s := _sample(B, dummy)
		s["hurt"] = HitBoxes.hurt_list(B, S.boxes, f)   # the body's capsules, with the scene's hurt edits (none = as before)
		s["authored"] = HitBoxes.hit_list(B, S.boxes, f)   # the hit boxes the user drew on this frame
		raw.append(s)
	# the key: the weapon when one is held in the scene, else the striking limb with the fastest tip
	var key := "weapon"
	var any_wep := false
	for s in raw:
		if s["wep"]:
			any_wep = true
			break
	if not any_wep:
		var best := -1.0
		key = STRIKERS[0]
		for st in STRIKERS:
			var peak := 0.0
			for f in N - 1:
				peak = maxf(peak, ((raw[f + 1]["tips"][st] as Vector3) - (raw[f]["tips"][st] as Vector3)).length() * fps)
			if peak > best:
				best = peak
				key = st
	var dir := Vector3(0, 0, 1)
	if dummy != null:
		var hero_root: Vector3 = B.P["pelvis"]
		var foe_root: Vector3 = dummy.xf * (dummy.D.P["pelvis"] as Vector3)
		dir = foe_root - hero_root
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 1e-6 else Vector3(0, 0, 1)
	var frames := []
	var first := -1
	var last := -1
	var nact := 0
	for f in N:
		var tip = _tip(raw[f], key)   # null when the weapon is not held on this frame: no speed, not active
		var v := Vector3.ZERO
		if N > 1 and tip != null:
			if f < N - 1:
				var nxt = _tip(raw[f + 1], key)
				if nxt != null:
					v = (nxt - tip) * float(fps)
			else:
				var prv = _tip(raw[f - 1], key)
				if prv != null:
					v = (tip - prv) * float(fps)
		var speed := v.length()
		var act: bool = (speed > TIP_SPEED and v.dot(dir) > 0.0) or bool(raw[f]["touch"])
		var hit := []
		if act:
			nact += 1
			if first < 0:
				first = f
			last = f
			hit = _hitboxes(raw[f], key)
		hit.append_array(raw[f]["authored"])
		frames.append({"f": f, "t": float(f) / float(fps), "active": act, "speed": speed,
			"hitboxes": hit, "hurtboxes": raw[f]["hurt"]})
	var startup := N
	var active := 0
	var recovery := 0
	if first >= 0:
		startup = first
		active = last - first + 1
		recovery = N - last - 1
	var out := {"fps": fps, "n": N, "striker": key, "dir": dir, "startup": startup, "active": active,
		"recovery": recovery, "first": first, "last": last, "gaps": active - nact, "frames": frames}
	if not S.boxes.is_empty():
		out["boxes"] = HitBoxes.to_file(S.boxes)   # the scene's own boxes (absent when there are none: the export is as before)
	return out


## one frame's raw measurements (the body as posed now)
static func _sample(B: Body, dummy: Dummy) -> Dictionary:
	var hurt := []
	for part in Body.BODY + Body.WIDE.keys():
		hurt.append(_cap(B, part))
	var s := {"wep": B.wep_on, "hurt": hurt, "tips": {}, "caps": {}, "touch": false}
	if B.wep_on:
		s["tip"] = B.wep_point(B.wep_len)
		s["wcaps"] = [_cap(B, "bat_handle"), _cap(B, "bat_barrel")]
	for st in STRIKERS:
		s["tips"][st] = B.E[st]
		var caps := []
		for part in STRIKE_CAPS[st]:
			caps.append(_cap(B, part))
		s["caps"][st] = caps
	if dummy != null and B.wep_on:
		s["touch"] = not dummy.touch(B).is_empty()
	return s


static func _cap(B: Body, part: String) -> Dictionary:
	var c: Array = B.cap(part)
	return {"a": c[0], "b": c[1], "r": float(B.rad[part])}


## the striking point of key on this frame; null for the weapon on a frame where no weapon is held (no tip to read)
static func _tip(s: Dictionary, key: String) -> Variant:
	if key == "weapon":
		return s.get("tip")
	return s["tips"][key]


static func _hitboxes(s: Dictionary, key: String) -> Array:
	if key == "weapon":
		return (s.get("wcaps", []) as Array).duplicate()
	return (s["caps"][key] as Array).duplicate()


## the spans to draw on the timeline strip: [{"kind": "startup"/"active"/"recovery", "f0", "f1" (first, one past last)}]
static func spans(fd: Dictionary) -> Array:
	if fd.is_empty():
		return []
	var out := []
	var s: int = fd["startup"]
	var a: int = fd["active"]
	if s > 0:
		out.append({"kind": "startup", "f0": 0, "f1": s})
	if a > 0:
		out.append({"kind": "active", "f0": s, "f1": s + a})
	if int(fd["recovery"]) > 0:
		out.append({"kind": "recovery", "f0": s + a, "f1": int(fd["n"])})
	return out


## the frame at scene time t (clamped to the data)
static func frame_at(fd: Dictionary, t: float) -> Dictionary:
	if fd.is_empty():
		return {}
	var f := clampi(int(floor(t * float(fd["fps"]) + 1e-6)), 0, int(fd["n"]) - 1)
	return fd["frames"][f]


# ---------------------------------------------------------------- export (metres, Y up)

static func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 1e-6), snappedf(v.y, 1e-6), snappedf(v.z, 1e-6)]


static func _caps_json(caps: Array) -> Array:
	var out := []
	for c in caps:
		var o := {"a": _v3(c["a"]), "b": _v3(c["b"]), "r": snappedf(float(c["r"]), 1e-6)}
		if c.has("src"):   # a hit box the user drew (hit_boxes.gd): its part, damage and hitstun ride with it
			o["src"] = c["src"]
			o["part"] = c["part"]
			o["damage"] = snappedf(float(c["damage"]), 1e-3)
			o["hitstun"] = int(c["hitstun"])
		out.append(o)
	return out


## the JSON-ready dictionary: {fps, startup, active, recovery, frames: [{f, active, hitboxes, hurtboxes}], boxes (when the scene has any)}
static func to_json(fd: Dictionary) -> Dictionary:
	var frames := []
	for fr in fd["frames"]:
		frames.append({"f": fr["f"], "active": fr["active"], "hitboxes": _caps_json(fr["hitboxes"]),
			"hurtboxes": _caps_json(fr["hurtboxes"])})
	var out := {"fps": fd["fps"], "startup": fd["startup"], "active": fd["active"], "recovery": fd["recovery"], "frames": frames}
	if fd.has("boxes"):
		out["boxes"] = fd["boxes"]   # the scene's boxes (hit_boxes.gd), as the scene file keeps them
	if fd.has("exchange"):
		out["exchange"] = fd["exchange"]   # N080: hitstun, blockstun, advantage (frame_advantage.gd); only with a second fighter
	return out


## writes the JSON to `path` (a user's chosen file). Returns an Error.
static func write_json(fd: Dictionary, path: String) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_json(fd), "\t"))
	f.close()
	return OK


## the capsules of one frame as wire lines (ImmediateMesh, PRIMITIVE_LINES): axis + two end rings per capsule
static func wire(frames_caps: Array) -> ImmediateMesh:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for g in frames_caps:   # [[caps, Color], ...]
		for c in g[0]:
			_wire_capsule(im, c["a"], c["b"], float(c["r"]), g[1])
	im.surface_end()
	return im


static func _wire_capsule(im: ImmediateMesh, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := b - a
	var n := d.normalized() if d.length() > 1e-9 else Vector3.UP
	var u := n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.UP).normalized()
	var w := n.cross(u)
	im.surface_set_color(col)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	for end in [a, b]:
		var prev: Vector3 = end + u * r
		for k in range(1, 17):
			var ang := TAU * float(k) / 16.0
			var p: Vector3 = end + (u * cos(ang) + w * sin(ang)) * r
			im.surface_set_color(col)
			im.surface_add_vertex(prev)
			im.surface_add_vertex(p)
			prev = p
