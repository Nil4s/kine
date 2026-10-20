## sound_cues.gd - I35 SOUND CUES FROM PHYSICS. The animation already knows when the sound should happen, so Kine derives the cues:
##   WHOOSH  at each speed peak of a striking end-effector (the weapon's tip; for an unarmed fighter the hands and feet) above a
##           threshold. Strength from the peak speed, pitch from it too, length from the time the speed stays above half the peak.
##   HIT     at each contact the fighters' report finds (Dummy.fighter_hits rows). Strength from the blow's impulse J (HitPhysics.measure:
##           (1 + e) x reduced mass x relative speed, in N s); the struck part's name gives the kind: head, body, or weapon (a clash).
##   STEP    at each foot plant's start (Scene.plants t0); a scene with no plants gets the touchdowns found from the foot's height and speed.
## Cues are DERIVED (never stored in the scene): a list of {t, frame, kind, strength, source, [pitch, len]}, kind = whoosh | hit_head |
## hit_body | hit_weapon | step. Strength is 1 - exp(-x / k) of the physical quantity, so it is strictly increasing in it and never clips.
## The preview sounds are synthesized here (synth(): no audio file, nothing downloaded); SoundCuesUI plays them through an
## AudioStreamGenerator in step with playback. The cue sheet (CSV + JSON) is written by write_sheet() under a folder the caller names.
class_name SoundCues
extends RefCounted

const RATE := 22050
const WHOOSH_MIN := {"tip": 8.0, "hand": 5.0, "foot": 6.0}   # m/s: the peak must be this fast (the weapon's is WeaponTrail's ribbon threshold)
const V_K := 25.0     # m/s: whoosh strength = 1 - exp(-v / V_K)
const J_K := 30.0     # N s: hit strength = 1 - exp(-J / J_K) (a bat to the arm in combo3 is ~36 N s, a boxer's punch ~26)
const MERGE := 0.6    # two peaks of one source are ONE swing when the dip between them stays above this share of the lower peak
const TD_H := 0.05    # m: a foot is down when its height is within this of the lowest it reaches in the clip ...
const TD_V := 0.6     # ... and slower than this (m/s)
const STEP_V := 2.5   # m/s: the foot's speed in the two frames before a plant that reads as strength 1 - exp(-1)
const FORMAT := "kine-cue-sheet-1"
const KINDS := ["whoosh", "hit_head", "hit_body", "hit_weapon", "step"]


static func strength_whoosh(v: float) -> float:
	return clampf(1.0 - exp(-v / V_K), 0.02, 1.0)


static func strength_hit(j: float) -> float:
	return clampf(1.0 - exp(-j / J_K), 0.02, 1.0)


static func pitch_of(v: float) -> float:
	return 250.0 + 45.0 * v   # Hz, the band's centre at the peak: 8 m/s -> 610 Hz, 32 m/s -> 1690 Hz


static func frame_of(t: float, fps: float) -> int:
	return roundi(t * fps)


## ONE PASS over a scene at its fps: per frame the tip (armed), hands and feet. {"fps", "n", "tip": [Vector3], "armed": [bool], "hand_l"..: [Vector3]}
static func track(S: Scene, b: Body) -> Dictionary:
	var out := {"fps": float(S.fps), "n": 0, "tip": [], "armed": []}
	if S.cards.size() < 1:
		return out
	if b.body != S.body:
		b.set_proportions(S.body)
	var fps := float(S.fps)
	var n := int(ceil(S.length() * fps)) + 1
	for j in ["hand_l", "hand_r", "foot_l", "foot_r"]:
		out[j] = []
	for i in n:
		S.apply(b, minf(i / fps, S.length()))
		var on := b.wep_on
		(out["armed"] as Array).append(on)
		(out["tip"] as Array).append(b.wep_point(b.wep_len) if on else Vector3.ZERO)
		for j in ["hand_l", "hand_r", "foot_l", "foot_r"]:
			(out[j] as Array).append(b.P[j])
	out["n"] = n
	return out


## the speed (m/s) of a path sampled at fps; v[i] = |p[i] - p[i-1]| fps, v[0] = v[1]; frames where valid[i] or valid[i-1] is false are 0
static func speeds(p: Array, fps: float, valid: Array = []) -> Array:
	var v := []
	for i in p.size():
		if i == 0:
			v.append(0.0)
		elif not valid.is_empty() and not (valid[i] and valid[i - 1]):
			v.append(0.0)
		else:
			v.append(((p[i] as Vector3) - (p[i - 1] as Vector3)).length() * fps)
	if v.size() > 1:
		v[0] = v[1]
	return v


## the peaks of a speed curve above thr: [{"i", "v", "i0", "i1"}], i0..i1 the frames at or above half the peak. A peak is a local maximum
## (>= the frame before, > the frame after); two whose dip stays above MERGE of the lower one are one swing (the higher stays).
static func peaks(v: Array, thr: float) -> Array:
	var raw := []
	for i in v.size():
		var left: float = v[i - 1] if i > 0 else 0.0
		var right: float = v[i + 1] if i + 1 < v.size() else 0.0
		if v[i] >= thr and v[i] >= left and v[i] > right:
			raw.append(i)
	var kept := []
	for i in raw:
		if not kept.is_empty():
			var j: int = kept[-1]
			var dip := 1e9
			for k in range(j, i + 1):
				dip = minf(dip, v[k])
			if dip >= MERGE * minf(v[j], v[i]):
				if v[i] > v[j]:
					kept[-1] = i
				continue
		kept.append(i)
	var out := []
	for i in kept:
		var i0: int = i
		var i1: int = i
		while i0 > 0 and v[i0 - 1] >= 0.5 * v[i]:
			i0 -= 1
		while i1 + 1 < v.size() and v[i1 + 1] >= 0.5 * v[i]:
			i1 += 1
		out.append({"i": i, "v": v[i], "i0": i0, "i1": i1})
	return out


static func whooshes(tr: Dictionary, source: String) -> Array:
	var out := []
	var fps: float = tr["fps"]
	var any_armed: bool = (tr["armed"] as Array).any(func(a): return a)
	var paths := []   # [source, speeds, threshold]
	if any_armed:
		paths.append([source + " weapon tip", speeds(tr["tip"], fps, tr["armed"]), WHOOSH_MIN["tip"]])
	else:
		for j in ["hand_l", "hand_r"]:
			paths.append(["%s %s" % [source, j], speeds(tr[j], fps), WHOOSH_MIN["hand"]])
		for j in ["foot_l", "foot_r"]:
			paths.append(["%s %s" % [source, j], speeds(tr[j], fps), WHOOSH_MIN["foot"]])
	for p in paths:
		for pk in peaks(p[1], p[2]):
			var len_s := float(pk["i1"] - pk["i0"] + 1) / fps
			out.append({"t": snappedf(float(pk["i"]) / fps, 0.0001), "frame": int(pk["i"]), "kind": "whoosh", "strength": strength_whoosh(pk["v"]),
				"source": p[0], "pitch": pitch_of(pk["v"]), "len": len_s, "speed": pk["v"]})
	return out


## footsteps: a plant's t0 each; with no plants, the touchdowns (a foot comes within TD_H of its lowest height and slows under TD_V,
## after at least 3 frames up). The first frame is not a touchdown (the clip starts standing).
static func steps(S: Scene, tr: Dictionary, source: String) -> Array:
	var out := []
	var fps: float = tr["fps"]
	var feet := ["foot_l", "foot_r"]
	if not S.plants.is_empty():
		for pl in S.plants:
			var t0 := float(pl["t0"])
			var f := clampi(frame_of(t0, fps), 0, maxi(0, int(tr["n"]) - 1))
			var s := 0.5
			if tr.has(String(pl["foot"])) and f >= 2:
				var path: Array = tr[String(pl["foot"])]
				s = clampf(1.0 - exp(-((path[f - 2] as Vector3) - (path[f] as Vector3)).length() * fps * 0.5 / STEP_V), 0.1, 1.0)
			out.append({"t": snappedf(t0, 0.0001), "frame": frame_of(t0, fps), "kind": "step", "strength": s, "source": "%s %s plant" % [source, String(pl["foot"])]})
		return out
	var low := 1e9
	for j in feet:
		for p in tr[j]:
			low = minf(low, (p as Vector3).y)
	for j in feet:
		var path: Array = tr[j]
		var v := speeds(path, fps)
		var up := 0
		for i in path.size():
			var down: bool = (path[i] as Vector3).y - low < TD_H and v[i] < TD_V
			if down and up >= 3:
				var vin: float = ((path[maxi(0, i - 2)] as Vector3) - (path[i] as Vector3)).length() * fps * 0.5
				out.append({"t": snappedf(float(i) / fps, 0.0001), "frame": i, "kind": "step", "strength": clampf(1.0 - exp(-vin / STEP_V), 0.1, 1.0), "source": "%s %s touchdown" % [source, j]})
			up = 0 if down else up + 1
	return out


## the kind of a hit row: weapon on weapon, the head, or the body
static func hit_kind(row: Dictionary) -> String:
	if String(row["kind"]) == "clash" or Body.is_wep(String(row["on"])):
		return "hit_weapon"
	return "hit_head" if HitReaction.joint_of(String(row["on"])).begins_with("head") else "hit_body"


## the hit cues of the fighters' report. actors = [{"S", "B", "xf", "name"}] (main's actors_rt); rows = Dummy.fighter_hits rows with "vs".
## Strength from HitPhysics' impulse J when the struck part is a body part, else from the speed of the blow (a clash: J of a 2 kg bat at v).
static func hits(rows: Array, actors: Array) -> Array:
	var out := []
	for r in rows:
		var fps := float((actors[0]["S"] as Scene).fps)
		var vk: int = 0 if r["by"] == "other" else int(r["vs"])
		var sk: int = int(r["vs"]) if r["by"] == "other" else 0
		var kind := hit_kind(r)
		var j := 0.0
		if kind != "hit_weapon" and vk < actors.size() and sk < actors.size():
			var blow := HitPhysics.measure(actors[vk]["S"], actors[vk]["B"], actors[vk]["xf"], r, actors[sk]["B"], actors[sk]["S"])
			if blow["ok"]:
				j = (blow["J"] as Vector3).length()
		if j <= 0.0:
			j = (1.0 + HitPhysics.RESTITUTION) * 0.5 * 1.0 * float(r["speed"])   # a clash, or no J: two 2 kg bodies' reduced mass 1 kg
		var who: String = String(actors[sk]["name"]) if sk < actors.size() else "?"
		var on: String = String(actors[vk]["name"]) if vk < actors.size() else "?"
		out.append({"t": snappedf(float(r["t"]), 0.0001), "frame": frame_of(float(r["t"]), fps), "kind": kind, "strength": strength_hit(j),
			"source": "%s %s on %s %s" % [who, String(r["part"]) if not Body.is_wep(String(r["part"])) else "weapon", on, String(r["on"]) if not Body.is_wep(String(r["on"])) else "weapon"], "J": j})
	return out


static func sort_cues(c: Array) -> Array:
	c.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]) or (float(a["t"]) == float(b["t"]) and String(a["kind"]) < String(b["kind"])))
	return c


## EVERYTHING: whooshes + steps for every actor (each on a body of its own), the hit cues of rows. actors as in hits().
static func derive(actors: Array, rows: Array) -> Array:
	var out := []
	for a in actors:
		var b := Body.new()
		b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		var tr := track(a["S"], b)
		if int(tr["n"]) < 2:
			continue
		var nm := String(a["name"])
		out.append_array(whooshes(tr, nm))
		out.append_array(steps(a["S"], tr, nm))
	out.append_array(hits(rows, actors))
	return sort_cues(out)


# ------------------------------------------------------------------ the cue sheet

static func csv(cues: Array) -> String:
	var s := "time,frame,kind,strength,source\n"
	for c in cues:
		s += "%.3f,%d,%s,%.3f,%s\n" % [c["t"], c["frame"], c["kind"], c["strength"], String(c["source"]).replace(",", ";")]
	return s


static func json(cues: Array, fps: int, scene: String) -> String:
	var rows := []
	for c in cues:
		var d := {"time": snappedf(float(c["t"]), 0.001), "frame": int(c["frame"]), "kind": c["kind"], "strength": snappedf(float(c["strength"]), 0.001), "source": c["source"]}
		if c["kind"] == "whoosh":
			d["pitch_hz"] = roundi(float(c["pitch"]))
			d["length_s"] = snappedf(float(c["len"]), 0.001)
		rows.append(d)
	return JSON.stringify({"format": FORMAT, "scene": scene, "fps": fps, "cues": rows}, "\t")


## <dir>/<name>_cues.csv and .json; dir is made. -> {"ok", "csv", "json", "why"}
static func write_sheet(dir: String, name: String, cues: Array, fps: int) -> Dictionary:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir)) != OK:
		return {"ok": false, "why": "cannot make the folder %s: pick another folder, then export again" % dir}
	var res := {"ok": true, "csv": "%s/%s_cues.csv" % [dir, name], "json": "%s/%s_cues.json" % [dir, name], "why": ""}
	var f := FileAccess.open(res["csv"], FileAccess.WRITE)
	var g := FileAccess.open(res["json"], FileAccess.WRITE)
	if f == null or g == null:
		return {"ok": false, "why": "cannot write the cue sheet in %s: pick another folder, then export again" % dir}
	f.store_string(csv(cues))
	g.store_string(json(cues, fps, name))
	return res


# ------------------------------------------------------------------ the sounds

## a tiny deterministic noise (LCG) so every render of a cue is the same sound
class Lcg:
	var s := 12345

	func next() -> float:
		s = (s * 1103515245 + 12345) & 0x7fffffff
		return float(s) / 1073741823.5 - 1.0


## one cue as mono samples at RATE (-1..1)
static func synth(kind: String, strength: float, pitch := 900.0, len_s := 0.25) -> PackedFloat32Array:
	var nz := Lcg.new()
	var out := PackedFloat32Array()
	match kind:
		"whoosh":
			# band-passed noise (a state-variable filter), the centre sweeping up to the peak at the middle and back down
			var dur := clampf(len_s * 1.6, 0.14, 0.8)
			var n := int(dur * RATE)
			var lo := 0.0
			var bp := 0.0
			var amp := 0.25 + 0.75 * strength
			for i in n:
				var u := float(i) / float(n)
				var fc := pitch * (0.55 + 0.45 * sin(PI * u))   # sweeps 0.55 -> 1.0 -> 0.55 of the pitch
				var f := 2.0 * sin(PI * fc / float(RATE))
				var x := nz.next()
				var hp := x - lo - 0.35 * bp   # q ~ 2.9
				bp += f * hp
				lo += f * bp
				var env := sin(PI * u)
				out.append(clampf(bp * 2.2 * env * env * amp, -1.0, 1.0))
		"step":
			var n := int(0.07 * RATE)
			var lo := 0.0
			var amp := 0.15 + 0.5 * strength
			for i in n:
				var t := float(i) / RATE
				lo += 0.25 * (nz.next() - lo)   # low-passed click
				out.append(clampf((lo * 1.6 * exp(-t / 0.008) + 0.6 * sin(TAU * 170.0 * t) * exp(-t / 0.014)) * amp, -1.0, 1.0))
		_:   # hit_head / hit_body / hit_weapon
			var n := int(0.3 * RATE)
			var amp := 0.3 + 0.7 * strength
			var thump := 110.0 if kind == "hit_head" else 62.0
			for i in n:
				var t := float(i) / RATE
				var v := 0.0
				if kind == "hit_weapon":
					for k in [[920.0, 1.0], [1430.0, 0.7], [2210.0, 0.45], [3370.0, 0.25]]:
						v += k[1] * sin(TAU * k[0] * t) * exp(-t / 0.10)
					v = v * 0.35 + nz.next() * exp(-t / 0.004) * 0.5
				else:
					var f := thump * (1.0 + 0.6 * exp(-t / 0.03))   # the thump drops in pitch as it dies
					v = 0.9 * sin(TAU * f * t) * exp(-t / 0.07) + nz.next() * exp(-t / (0.012 if kind == "hit_body" else 0.02)) * 0.7
				out.append(clampf(v * amp, -1.0, 1.0))
	return out


static func rms(s: PackedFloat32Array) -> float:
	if s.is_empty():
		return 0.0
	var a := 0.0
	for x in s:
		a += x * x
	return sqrt(a / float(s.size()))
