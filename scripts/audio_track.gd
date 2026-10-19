## AUDIO TRACK (GAP_ANALYSIS row 23): one sound on the timeline, like Blender's and Maya's audio strip.
## The scene keeps {"path", "offset", "gain_db"} (Scene.audio, only when there is a sound); main.gd plays it in step with
## the playhead and plays a short slice on a scrub; the timeline draws the peak envelope this file computes ONCE on load.
## Pure helpers: no node, no scene. WAV is decoded for the envelope (8 and 16 bit PCM, mono / stereo); ogg and mp3 play
## but are not decoded (Godot gives no PCM for them): the timeline shows a flat bar with the file name and says so.
class_name AudioTrack
extends RefCounted

const BUCKET := 0.01        # s: one envelope bucket (10 ms)
const EXTS := ["wav", "ogg", "mp3"]
const MAX_PER_BUCKET := 128   # samples read per bucket at most (a long song stays fast; a short test file is exact)


static func clean(a: Dictionary) -> Dictionary:
	return {"path": String(a.get("path", "")), "offset": snappedf(float(a.get("offset", 0.0)), 0.001), "gain_db": snappedf(float(a.get("gain_db", 0.0)), 0.01)}


## the stream for a path, or null (no file, unknown kind, undecodable)
static func load_stream(path: String) -> AudioStream:
	if path == "" or not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"wav":
			return AudioStreamWAV.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			var s := AudioStreamMP3.new()
			s.data = FileAccess.get_file_as_bytes(path)
			return s if s.data.size() > 0 else null
	return null


## {"ok": envelope was decoded, "name", "length", "dt", "mx": PackedFloat32Array (the loudest sample per bucket, 0..1)}
## "ok" false = a flat bar (ogg / mp3 / ADPCM); "length" is still known when the stream says it
static func envelope(stream: AudioStream, path: String) -> Dictionary:
	var out := {"ok": false, "name": path.get_file(), "length": 0.0, "dt": BUCKET, "mx": PackedFloat32Array(), "mn": PackedFloat32Array()}
	if stream == null:
		return out
	out["length"] = stream.get_length()
	if not (stream is AudioStreamWAV):
		return out
	var w := stream as AudioStreamWAV
	var bytes := 1
	if w.format == AudioStreamWAV.FORMAT_16_BITS:
		bytes = 2
	elif w.format != AudioStreamWAV.FORMAT_8_BITS:
		return out   # IMA ADPCM / QOA: packed, not read here
	var ch := 2 if w.stereo else 1
	var data := w.data
	var frames := data.size() / (bytes * ch)
	if frames <= 0 or w.mix_rate <= 0:
		return out
	var per := maxi(1, int(round(BUCKET * w.mix_rate)))
	var stride := maxi(1, per / MAX_PER_BUCKET)
	var nb := int(ceil(float(frames) / per))
	var mx := PackedFloat32Array()
	var mn := PackedFloat32Array()
	mx.resize(nb)
	mn.resize(nb)
	var scale := 1.0 / (32768.0 if bytes == 2 else 128.0)
	for b in nb:
		var hi := -1.0
		var lo := 1.0
		var f := b * per
		var fe := mini(f + per, frames)
		while f < fe:
			var base := f * ch * bytes
			var v := 0.0
			for c in ch:   # stereo: the louder side
				var o := base + c * bytes
				var s := float(data.decode_s16(o)) if bytes == 2 else float(data.decode_s8(o))
				if absf(s) > absf(v):
					v = s
			v *= scale
			hi = maxf(hi, v)
			lo = minf(lo, v)
			f += stride
		mx[b] = hi
		mn[b] = lo
	out["ok"] = true
	out["length"] = float(frames) / w.mix_rate
	out["mx"] = mx
	out["mn"] = mn
	return out


## the loudest absolute value (0..1) in sound time t0..t1 (the timeline's column), 0 when outside
static func peak(env: Dictionary, t0: float, t1: float) -> float:
	var mx: PackedFloat32Array = env.get("mx", PackedFloat32Array())
	if mx.is_empty():
		return 0.0
	var mn: PackedFloat32Array = env["mn"]
	var dt: float = env["dt"]
	var a := clampi(int(floor(t0 / dt)), 0, mx.size() - 1)
	var b := clampi(int(floor(t1 / dt)), a, mx.size() - 1)
	if t1 < 0.0 or t0 > mx.size() * dt:
		return 0.0
	var p := 0.0
	for i in range(a, b + 1):
		p = maxf(p, maxf(absf(mx[i]), absf(mn[i])))
	return p


## a 1 kHz-style test tone: 16-bit mono PCM bytes with a silent gap (the test writes it as a WAV)
static func sine_wav_bytes(rate: int, seconds: float, hz: float, amp: float, gap_a: float, gap_b: float) -> PackedByteArray:
	var n := int(seconds * rate)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var v := 0.0 if (t >= gap_a and t < gap_b) else amp * sin(TAU * hz * t)
		pcm.encode_s16(i * 2, int(round(v * 32767.0)))
	var h := PackedByteArray()
	h.resize(44)
	h.encode_u32(0, 0x46464952)   # RIFF
	h.encode_u32(4, 36 + pcm.size())
	h.encode_u32(8, 0x45564157)   # WAVE
	h.encode_u32(12, 0x20746d66)  # fmt
	h.encode_u32(16, 16)
	h.encode_u16(20, 1)
	h.encode_u16(22, 1)
	h.encode_u32(24, rate)
	h.encode_u32(28, rate * 2)
	h.encode_u16(32, 2)
	h.encode_u16(34, 16)
	h.encode_u32(36, 0x61746164)  # data
	h.encode_u32(40, pcm.size())
	h.append_array(pcm)
	return h
