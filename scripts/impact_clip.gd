## impact_clip.gd - IMPACT FRAMES ON A STRIKE (Friday plan 137): a hand or weapon of the clip meets a PROP (a target box) and, at
## the first frame it touches it, the clip gets three things, all written into the clip (so a GLB / BVH / playblast of it carries them):
##   HIT-STOP   the pose holds for N frames (0..6, default 3) at the contact: the card under the contact is split there and holds, and
##              everything after shifts by N / fps (ImpactFrames' tags and shift: Remove, undo and the scene file work as I13's).
##   FLASH      the target's material is white (emission) on exactly FLASH_FRAMES = 2 frames from the contact frame (read from the stop's
##              marker: flash_props(); ImpactClipUI.sync() puts it on the prop's mesh each refresh, so playback and the playblast show it).
##   SHAKE      the shot camera shakes for SHAKE_DUR = 0.25 s from the contact (ShotFx event, name ImpactFrames.SHAKE_NAME): the offset peaks
##              at the contact frame and is zero at 0.25 s (ShotFx's envelope exp(-d u)(1 - u) ends at 0). Its size is the amplitude slider (cm).
## THE CONTACT is found on the clip as it is: every frame k / fps is posed with Scene.apply, and the first frame a striker's shape
## is inside a prop of the set (Props.depth > 0) after being outside is the contact. The shapes: each HAND is a sphere on the wrist
## joint with the hand's own radius (Body.rad), so "touching" = the wrist is nearer the prop's surface than the hand's radius; a held
## weapon is its two capsules (bat_handle / bat_barrel, wep2_handle / wep2_blade) at their radii.
## The edit is the I13 edit (marker "Hit-stop Nf" with note "i13:<hold> J=0.0 N s prop=<i> amp=<cm>"), so ImpactFrames.remove() takes it
## out exactly and ImpactFrames.record() / rehydrate() keep its tags in the scene file.
class_name ImpactClip
extends RefCounted

const FLASH_FRAMES := 2
const SHAKE_DUR := 0.25
const STOP_MAX := 6
const STOP_DEFAULT := 3
const AMP_DEFAULT := 2.0   # cm, the camera shake's strength (the length of its position offset at the contact is about 1.4 x this)
const AMP_MAX := 6.0
const CAM_NAME := "Impact cam"
const FLASH_COLOR := Color(1, 1, 1)


## the shapes that strike: [{"part", "a", "b", "r"}] in the pose B holds now
static func strikers(B: Body) -> Array:
	var out := []
	for h in ["hand_r", "hand_l"]:
		out.append({"part": h, "a": B.P[h], "b": B.P[h], "r": float(B.rad[h])})
	var wp := []
	if B.wep_on:
		wp += ["bat_handle", "bat_barrel"]
	if B.wep2_on:
		wp += ["wep2_handle", "wep2_blade"]
	for p in wp:
		var c := B.cap(p)
		out.append({"part": p, "a": c[0], "b": c[1], "r": float(B.rad[p])})
	return out


## the first contact of a striker with a prop of S: {"k" (frame), "t" (k / fps), "prop", "part"}; {} when none. B is put back as it was.
static func find_contact(S: Scene, B: Body) -> Dictionary:
	var fps := maxi(S.fps, 1)
	var carried := {}
	for cr in S.carries():
		carried[int(cr["prop"])] = true
	var keep := B.state()
	var n := int(floor(S.length() * float(fps) + 1e-6))
	var inside := {}
	var res := {}
	for k in n + 1:
		var t := float(k) / float(fps)
		S.apply(B, t)
		for pi in S.props.size():
			if carried.has(pi):
				continue
			for st in strikers(B):
				var key := "%s|%d" % [st["part"], pi]
				var inn := Props.depth(S.props[pi], st["a"], st["b"], st["r"]) > 1e-6
				if inn and k > 0 and not inside.get(key, false):
					res = {"k": k, "t": t, "prop": pi, "part": String(st["part"])}
					break
				inside[key] = inn
			if not res.is_empty():
				break
		if not res.is_empty():
			break
	B.set_state(keep)
	return res


static func hold_s(frames: int, fps: int) -> float:
	return float(frames) / float(maxi(fps, 1))


## the shake of strength amp (cm) from t: ImpactFrames' damped oscillation, SHAKE_DUR long, peak at t
static func shake(t: float, amp: float, seed_n := 1) -> Dictionary:
	var e := ImpactFrames.shake(t, 15.0, seed_n)
	e["dur"] = SHAKE_DUR
	e["cm"] = Vector3(0.6, 0.8, 1.0) * amp
	e["deg"] = Vector3(0.5, 0.3, 0.6) * amp * 0.5
	e["decay"] = 3.0
	return e


## the clip with its impact frames at contact c (find_contact's result): frames of hit-stop, amp cm of shake, the flash on the prop.
## The caller has taken the undo step.
static func apply(S: Scene, B: Body, c: Dictionary, frames: int, amp: float) -> void:
	var fps := maxi(S.fps, 1)
	frames = clampi(frames, 0, STOP_MAX)
	var tc: float = c["t"]
	var h := hold_s(frames, fps)
	var keep := B.state()
	if frames > 0:
		_hold(S, B, tc, h)
	B.set_state(keep)
	var mk := Markers.add(S.markers, tc, "%s %df" % [ImpactFrames.MARK, frames], "hit")
	mk["t"] = tc   # Markers.add rounds to the millisecond; the stop starts at the frame's time
	mk["note"] = "%s:%s J=0.0 N s prop=%d amp=%s" % [ImpactFrames.TAG, str(h), int(c["prop"]), str(amp)]
	if amp > 0.0:
		var si := _shot_for(S, tc, c)
		if not S.shots[si].has("fx"):
			S.shots[si]["fx"] = {}
		ShotFx.list(S.shots[si]["fx"], "shake").append(shake(tc, amp, 1))


## the shot the shake goes on: the shot at tc if it has camera keys, else a key is put in it (a shot is made if the clip has none):
## a side view of the target, tagged "ih" so Remove takes it out
static func _shot_for(S: Scene, tc: float, c: Dictionary) -> int:
	var tgt: Vector3 = (S.props[int(c["prop"])]["xf"] as Transform3D).origin + Vector3(0, 0.9, 0)
	var key := {"t": 0.0, "pos": tgt + Vector3(2.6, 0.4, 0.0), "aim": tgt - Vector3(0, 0.1, 0.4), "f": 50.0, "ih": true}
	if S.shots.is_empty():
		S.shots = [{"t": 0.0, "name": CAM_NAME, "keys": [], "fx": {}}]
	var si := ShotCam.shot_index(S.shots, tc)
	if (S.shots[si]["keys"] as Array).is_empty():
		key["t"] = float(S.shots[si]["t"])
		ShotCam.put(S.shots[si]["keys"], key)
	return si


## ImpactFrames.remove for this edit; the shot it made (named CAM_NAME, keyless once its tagged key is out) goes with it
static func remove(S: Scene) -> int:
	for i in range(S.cards.size() - 1, -1, -1):   # the sampled frame cards of a mid-move stop go, the card gets its own move back
		if S.cards[i].has("ihb"):
			S.cards.remove_at(i)
		elif S.cards[i].has("ihm"):
			S.cards[i]["move"] = S.cards[i]["ihm"]
			S.cards[i].erase("ihm")
	var n := ImpactFrames.remove([S])
	for i in range(S.shots.size() - 1, -1, -1):
		var sh: Dictionary = S.shots[i]
		if String(sh.get("name", "")) == CAM_NAME and (sh["keys"] as Array).is_empty() and _fx_empty(sh.get("fx", {})):
			S.shots.remove_at(i)
	return n


## a shot's fx with nothing in it (a reloaded file's fx holds empty "shake" / "focus" lists)
static func _fx_empty(fx: Dictionary) -> bool:
	for k in fx:
		if fx[k] is Array and not (fx[k] as Array).is_empty():
			return false
		if not (fx[k] is Array):
			return false
	return true


static func _is_ours(mk: Dictionary) -> bool:
	var note := String(mk.get("note", ""))
	return String(mk.get("name", "")).begins_with(ImpactFrames.MARK) and note.begins_with(ImpactFrames.TAG + ":") and note.contains("prop=")


## the settings the clip's impact marker carries: {"frames", "amp", "prop", "t"}; {} = the clip has none of this kind
static func settings(S: Scene) -> Dictionary:
	for mk in S.markers:
		if _is_ours(mk):
			var note := String(mk["note"])
			var frames := int(String(mk["name"]).get_slice(" ", 1).trim_suffix("f"))
			var pr := int(note.get_slice("prop=", 1).get_slice(" ", 0))
			var am := float(note.get_slice("amp=", 1).get_slice(" ", 0)) if note.contains("amp=") else AMP_DEFAULT
			return {"frames": frames, "amp": am, "prop": pr, "t": float(mk["t"])}
	return {}


## the props whose material is white at time t (the FLASH_FRAMES frames from the contact frame); [] otherwise
static func flash_props(S: Scene, t: float) -> Array:
	var out := []
	var tol := 0.0006   # a marker's time may differ from its frame's by a millisecond (file rounding)
	var fl := float(FLASH_FRAMES) / float(maxi(S.fps, 1))
	for mk in S.markers:
		if not _is_ours(mk):
			continue
		var d := t - float(mk["t"])
		if d >= -tol and d < fl - tol:
			out.append(int(String(mk["note"]).get_slice("prop=", 1).get_slice(" ", 0)))
	return out


## ImpactFrames._hold without the rounding of the hold (a stop of n frames must be n / fps long, not n / fps to 0.1 ms):
## the card under t holds for h more (or is split at t), and everything timed after t shifts by h
static func _hold(S: Scene, B: Body, t: float, h: float) -> void:
	var ts: Array = S.times().duplicate(true)
	var i := -1
	for c in ts.size():
		if float(ts[c][2]) >= t - 1e-9:
			i = c
			break
	var cam := {}
	var cam_si := ShotCam.shot_index(S.shots, t)
	if cam_si >= 0 and not (S.shots[cam_si]["keys"] as Array).is_empty():
		cam = ShotCam.sample(S.shots[cam_si]["keys"], t)
	if i < 0:
		i = S.cards.size() - 1
		if not S.cards[i].has("iho"):
			S.cards[i]["iho"] = S.cards[i]["hold"]
		S.cards[i]["hold"] = float(S.cards[i]["hold"]) + h
	elif t >= float(ts[i][1]) - 1e-9 or i == 0:
		var cd: Dictionary = S.cards[i]
		if not cd.has("iho"):
			cd["iho"] = cd["hold"]
		cd["hold"] = float(cd["hold"]) + h
	else:
		# MID-MOVE: the move under t is replaced by one card per FRAME of the ORIGINAL curve (sampled with Scene.apply before anything
		# is written, so the card's own ease, the natural lag and every layer are in the numbers): frames after the start up to the
		# contact (the contact card holds h), then the frames after the contact up to the card's end, then the card itself with
		# the rest of its move. At every frame the pose is the original's, before the contact and (shifted by the hold) after it.
		var fps := maxi(S.fps, 1)
		var a0 := float(ts[i][0])
		var b0 := float(ts[i][1])
		var kc := roundi(t * float(fps))
		var k0 := floori(a0 * float(fps) + 1e-6) + 1
		var kend := ceili(b0 * float(fps) - 1e-6) - 1
		var made := []
		var prev := a0
		for k in range(k0, maxi(kend, kc) + 1):
			var tk := float(k) / float(fps)
			S.apply(B, tk)
			made.append({"name": "hit-stop", "pose": B.to_dict(), "move": tk - prev, "hold": h if k == kc else 0.0, "ease": "linear", "ihb": true})
			prev = tk
		var oc: Dictionary = S.cards[i]
		oc["ihm"] = oc["move"]   # the card's own move, back on Remove
		oc["move"] = b0 - prev
		for n in made.size():
			S.cards.insert(i + n, made[n])
	ImpactFrames._shift(S, t, h)
	if not cam.is_empty():
		var keys: Array = S.shots[cam_si]["keys"]
		for tt in [t, t + h]:
			if ShotCam.key_near(keys, tt, 0.0005) >= 0:
				continue
			ShotCam.put(keys, {"t": tt, "pos": cam["pos"], "aim": cam["aim"], "f": cam["f"], "ih": true})
