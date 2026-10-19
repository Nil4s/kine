## lip_sync.gd - LIP-SYNC FROM AUDIO (ROADMAP 31, top-25 #21). Pure helpers: no node, no scene.
## The scene keeps Scene.lip = {"jaw": [{"t", "v": Vector3(open_deg, 0, 0)}], "mouth": [{"t", "s": "M"|"A"|"O"|"E"}]}
## (the key shape of Scene.part_keys, so PartKeys.at is the curve). "jaw" is a CHANNEL, not a Body joint: the mannequin
## has no jaw bone (data/skeleton.json is untouched). The mouth is drawn on the head from the channel (main.gd _lip_draw).
## Saved only when there is one (a scene without it writes no "lip" key, byte for byte as before).
##
## FROM THE AUDIO (WAV only: Godot does not decode ogg / mp3 for us, so they say so and bake nothing):
##   1. 10 ms windows (WIN): RMS, and ZCR = zero crossings per second (a crude brightness / voicing proxy).
##   2. Class per window: silent (RMS < GATE x loudest) = closed M; ZCR >= ZCR_FRIC = fricative S (teeth, jaw nearly shut);
##      ZCR < ZCR_DARK = rounded O/U; ZCR < ZCR_VOICED = open A; else wide E/I. A crude estimate, not a formant tracker:
##      a real vowel classifier would use F1/F2. M/B/P show as the closed shape M at the closures inside speech.
##   3. Mouth shape: majority vote over 13 windows (0.13 s), so no shape flips faster than ~8 Hz.
##   4. Jaw opening: JAW_MAX x class factor x RMS / loudest RMS (JAW_K), then a Gaussian smoother (sigma 25 ms):
##      its gain is ~0.73 at 5 Hz and ~0.02 at 20 Hz, so nothing faster than ~8 Hz survives (tests/lip_sync_test.gd).
##      The jaw range: 0-15 deg (conversational speech opens the jaw about 5-15 deg; the jaw's own limit is ~25 deg).
##   5. Baked at the scene's fps, shifted by the sound's offset. The syllable rate is 4-6 Hz (Greenberg et al. 2003, syllable
##      nuclei in conversational speech about 4-5 per second; Poeppel & Assaneo 2020 on the 4-8 Hz speech band).
class_name LipSync
extends RefCounted

const WIN := 0.01           # s: analysis window (10 ms)
const JAW_MAX := 15.0       # deg: the jaw at the loudest vowel
const GATE := 0.05          # silence = RMS below 5 % of the loudest window
const ZCR_FRIC := 3000.0    # crossings per s at or above: fricative (S, F, SH)
const ZCR_DARK := 300.0     # voiced and below: rounded (O / U)
const ZCR_VOICED := 1200.0  # voiced and below: open (A); above: wide (E / I)
const VOTE := 6             # windows either side in the mouth-shape vote (13 x 10 ms)
const SIGMA := 0.025        # s: Gaussian smoother for the jaw (gain 0.73 at 5 Hz, 0.02 at 20 Hz)
const JAW_K := {"A": 1.0, "O": 0.7, "E": 0.45, "S": 0.2, "M": 0.0}
## the mouth drawn on the head at rest: width and height (m) per shape; the jaw adds a gap (14 mm at full open)
const SHAPE_SIZE := {"M": Vector2(0.024, 0.002), "A": Vector2(0.026, 0.004), "O": Vector2(0.013, 0.004), "E": Vector2(0.032, 0.002)}


## {"ok", "rate", "mono": PackedFloat32Array (channels averaged), "length", "why"} from a PCM WAV on disk (8 / 16 / 32 bit float)
static func read_wav(path: String) -> Dictionary:
	if path.get_extension().to_lower() != "wav":
		return {"ok": false, "why": "only a wav can be read here (Godot does not decode ogg or mp3 for analysis): add a wav"}
	if not FileAccess.file_exists(path):
		return {"ok": false, "why": "the sound file is missing: %s" % path.get_file()}
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 44 or b.decode_u32(0) != 0x46464952 or b.decode_u32(8) != 0x45564157:
		return {"ok": false, "why": "%s is not a RIFF wav" % path.get_file()}
	var pos := 12
	var fmt := 0
	var ch := 1
	var rate := 0
	var bits := 16
	var at := -1
	var n_data := 0
	while pos + 8 <= b.size():
		var id := b.decode_u32(pos)
		var n := b.decode_u32(pos + 4)
		if id == 0x20746d66 and pos + 24 <= b.size():   # "fmt "
			fmt = b.decode_u16(pos + 8)
			ch = maxi(1, b.decode_u16(pos + 10))
			rate = b.decode_u32(pos + 12)
			bits = b.decode_u16(pos + 22)
		elif id == 0x61746164:   # "data"
			at = pos + 8
			n_data = mini(n, b.size() - at)
			break
		pos += 8 + n + (n & 1)
	var bytes := bits / 8
	if at < 0 or rate <= 0 or not ((fmt == 1 and (bits == 8 or bits == 16)) or (fmt == 3 and bits == 32) or (fmt == 0xFFFE and bits == 16)):
		return {"ok": false, "why": "%s: only 8 or 16 bit PCM (or 32 bit float) wav can be analysed; save it as 16 bit" % path.get_file()}
	var frames := n_data / (bytes * ch)
	var mono := PackedFloat32Array()
	mono.resize(frames)
	var scale := 1.0 / (128.0 if bits == 8 else 32768.0)
	for f in frames:
		var acc := 0.0
		for c in ch:
			var o := at + (f * ch + c) * bytes
			if bits == 8:
				acc += (float(b.decode_u8(o)) - 128.0) * scale
			elif bits == 16:
				acc += float(b.decode_s16(o)) * scale
			else:
				acc += b.decode_float(o)
		mono[f] = acc / ch
	return {"ok": true, "rate": rate, "mono": mono, "length": float(frames) / rate, "why": ""}


## the 10 ms windows: {"rms": PackedFloat32Array, "zcr": PackedFloat32Array (zero crossings per second), "dt": WIN}
static func windows(mono: PackedFloat32Array, rate: int) -> Dictionary:
	var per := maxi(2, int(round(WIN * rate)))
	var nb := mono.size() / per
	var rms := PackedFloat32Array()
	var zcr := PackedFloat32Array()
	rms.resize(nb)
	zcr.resize(nb)
	for w in nb:
		var f0 := w * per
		var s := 0.0
		var cr := 0
		var prev := mono[f0] >= 0.0
		for f in range(f0, f0 + per):
			var v := mono[f]
			s += v * v
			if (v >= 0.0) != prev:
				cr += 1
			prev = v >= 0.0
		rms[w] = sqrt(s / per)
		zcr[w] = cr / (per / float(rate))
	return {"rms": rms, "zcr": zcr, "dt": WIN}


## the mouth class per window, before the vote: "M" silent, "S" fricative, "O", "A", "E"
static func classes(W: Dictionary) -> PackedStringArray:
	var rms: PackedFloat32Array = W["rms"]
	var zcr: PackedFloat32Array = W["zcr"]
	var peak := 0.0
	for v in rms:
		peak = maxf(peak, v)
	var gate := maxf(GATE * peak, 1e-5)
	var out := PackedStringArray()
	out.resize(rms.size())
	for i in rms.size():
		if rms[i] < gate:
			out[i] = "M"
		elif zcr[i] >= ZCR_FRIC:
			out[i] = "S"
		elif zcr[i] < ZCR_DARK:
			out[i] = "O"
		elif zcr[i] < ZCR_VOICED:
			out[i] = "A"
		else:
			out[i] = "E"
	return out


## per window: [mouth shape after the vote ("M", "A", "O", "E"; S shows as E), raw jaw deg]
static func analyse(W: Dictionary) -> Dictionary:
	var rms: PackedFloat32Array = W["rms"]
	var cls := classes(W)
	var nb := rms.size()
	var peak := 0.0
	for v in rms:
		peak = maxf(peak, v)
	# the vote: the most frequent class in a 13-window span (a run shorter than ~60 ms cannot flip the shape)
	var shape := PackedStringArray()
	shape.resize(nb)
	for i in nb:
		var cnt := {}
		for j in range(maxi(0, i - VOTE), mini(nb, i + VOTE + 1)):
			cnt[cls[j]] = int(cnt.get(cls[j], 0)) + 1
		var best := "M"
		var bn := -1
		for k in cnt:
			if cnt[k] > bn:
				bn = cnt[k]
				best = k
		shape[i] = "E" if best == "S" else best
	# the raw jaw: the class factor x loudness (the loudest window of the sound = the full factor)
	var raw := PackedFloat32Array()
	raw.resize(nb)
	for i in nb:
		var k: float = JAW_K.get(cls[i], 0.0)
		raw[i] = JAW_MAX * k * (rms[i] / peak if peak > 0.0 else 0.0)
	return {"shape": shape, "jaw": _gauss(raw, SIGMA / float(W["dt"]))}


## Gaussian smoothing over windows, sigma in windows; the ends are renormalised (no pull to zero at the edges)
static func _gauss(x: PackedFloat32Array, sig: float) -> PackedFloat32Array:
	var n := x.size()
	var half := maxi(1, int(ceil(3.0 * sig)))
	var k := PackedFloat32Array()
	k.resize(2 * half + 1)
	for i in k.size():
		var d := float(i - half)
		k[i] = exp(-0.5 * d * d / (sig * sig))
	var y := PackedFloat32Array()
	y.resize(n)
	for i in n:
		var s := 0.0
		var wsum := 0.0
		for j in range(maxi(0, i - half), mini(n, i + half + 1)):
			var wgt := k[j - i + half]
			s += x[j] * wgt
			wsum += wgt
		y[i] = s / wsum if wsum > 0.0 else 0.0
	return y


## the baked channel: one jaw key per frame (the sound's offset applied: the sound starts at offset on the timeline),
## a mouth key where the shape changes. Outside the sound: closed. total = the scene's length in s.
static func bake(A: Dictionary, rate_fps: int, offset: float, total: float) -> Dictionary:
	var jaw := []
	var mouth := []
	var n_frames := int(ceil(total * rate_fps)) + 1
	var nb: int = (A["shape"] as PackedStringArray).size()
	var last := ""
	for f in n_frames:
		var t := snappedf(float(f) / rate_fps, 0.0001)
		var ta := t - offset
		var wi := int(floor(ta / WIN))
		var jv := 0.0
		var sh := "M"
		if ta >= 0.0 and wi < nb:
			jv = float((A["jaw"] as PackedFloat32Array)[wi])
			sh = (A["shape"] as PackedStringArray)[wi]
		jaw.append({"t": t, "v": Vector3(snappedf(jv, 0.01), 0.0, 0.0)})
		if sh != last:
			mouth.append({"t": t, "s": sh})
			last = sh
	return {"jaw": jaw, "mouth": mouth}


## the jaw's opening (deg) at scene time t: the channel's own curve (PartKeys.at), 0 with no channel
static func jaw_at(lip: Dictionary, t: float) -> float:
	var k: Array = lip.get("jaw", [])
	if k.is_empty():
		return 0.0
	return PartKeys.at(k, t).x


## the mouth shape at scene time t: the last key at or before t ("M" with no channel)
static func shape_at(lip: Dictionary, t: float) -> String:
	var k: Array = lip.get("mouth", [])
	var s := "M"
	for e in k:
		if float(e["t"]) <= t:
			s = String(e["s"])
		else:
			break
	return s


## the mouth's size in metres for a shape and a jaw opening: [width, height, depth]
static func mouth_size(shape: String, jaw_deg: float) -> Vector3:
	var s: Vector2 = SHAPE_SIZE.get(shape, SHAPE_SIZE["M"])
	var gap := 0.014 * clampf(jaw_deg / JAW_MAX, 0.0, 1.0)
	if shape == "M":
		gap = 0.0
	elif shape == "E":
		gap *= 0.5
	return Vector3(s.x, s.y + gap, 0.004)


## the file form: [t, deg] and [t, shape] pairs (rounded as bake rounds them, so a save and a reload match)
static func to_file(lip: Dictionary) -> Dictionary:
	var jaw := []
	for k in lip.get("jaw", []):
		jaw.append([snappedf(float(k["t"]), 0.0001), snappedf((k["v"] as Vector3).x, 0.01)])
	var mouth := []
	for k in lip.get("mouth", []):
		mouth.append([snappedf(float(k["t"]), 0.0001), String(k["s"])])
	return {"jaw": jaw, "mouth": mouth}


static func from_file(d: Variant) -> Dictionary:
	if not d is Dictionary or (d as Dictionary).is_empty():
		return {}
	var jaw := []
	for e in d.get("jaw", []):
		jaw.append({"t": float(e[0]), "v": Vector3(float(e[1]), 0.0, 0.0)})
	var mouth := []
	for e in d.get("mouth", []):
		mouth.append({"t": float(e[0]), "s": String(e[1])})
	return {"jaw": jaw, "mouth": mouth}
