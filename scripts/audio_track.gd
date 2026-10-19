## AUDIO TRACKS (GAP_ANALYSIS row 23; ROADMAP 77): the sounds on the timeline, one lane per track, like Blender's and Maya's audio strips.
## The scene keeps Scene.audio_tracks: a list of {"path", "offset" s, "gain_db", "role" ("music" | "voice" | "sfx"), "mute", "solo"}.
## In the file the list is written as the old single "audio" dictionary when it is ONE plain track (path, offset, gain_db: an
## old scene saves back byte-identical), otherwise as an array of those dictionaries. Music beats read the music track, lip sync
## the voice track (the first track when none is tagged voice, so an old scene still lip-syncs). main.gd plays each track
## in step with the playhead; the timeline draws the peak envelope this file computes ONCE on load.
## Pure helpers: no node, no scene. WAV is decoded for the envelope (8 and 16 bit PCM, mono / stereo); ogg and mp3 play
## but are not decoded (Godot gives no PCM for them): the timeline shows a flat bar with the file name and says so.
class_name AudioTrack
extends RefCounted

const BUCKET := 0.01        # s: one envelope bucket (10 ms)
const EXTS := ["wav", "ogg", "mp3"]
const MAX_PER_BUCKET := 128   # samples read per bucket at most (a long song stays fast; a short test file is exact)
const ROLES := ["music", "voice", "sfx"]
const MIX_CHUNK := 4096       # frames read from a stream per call when the premix is built


static func clean(a: Dictionary) -> Dictionary:
	var out := {"path": String(a.get("path", "")), "offset": snappedf(float(a.get("offset", 0.0)), 0.001), "gain_db": snappedf(float(a.get("gain_db", 0.0)), 0.01)}
	var role := String(a.get("role", "music"))
	if role != "music":
		out["role"] = role if ROLES.has(role) else "sfx"
	if bool(a.get("mute", false)):
		out["mute"] = true
	if bool(a.get("solo", false)):
		out["solo"] = true
	return out


## the tracks that have a file, cleaned (a track with no path is dropped)
static func clean_list(a: Array) -> Array:
	var out := []
	for t in a:
		if t is Dictionary and String((t as Dictionary).get("path", "")) != "":
			out.append(clean(t))
	return out


## the scene file's "audio" value: the old dictionary for ONE plain track (path, offset, gain_db only), else an array; null = none
static func to_file(tracks: Array) -> Variant:
	var list := clean_list(tracks)
	if list.is_empty():
		return null
	if list.size() == 1 and (list[0] as Dictionary).size() == 3:
		return list[0]
	return list


## the tracks from the file's "audio" value: a dictionary (the old single sound) or an array; anything else = none
static func from_file(v: Variant) -> Array:
	if v is Dictionary:
		return clean_list([v])
	if v is Array:
		return clean_list(v)
	return []


## the index of the first track with this role; "voice" falls back to the first track (an old scene's one sound); -1 = none
static func index_of_role(tracks: Array, role: String) -> int:
	for i in tracks.size():
		if String(tracks[i].get("role", "music")) == role:
			return i
	return 0 if role == "voice" and not tracks.is_empty() else -1


## which tracks sound: not muted, and when any track is soloed only the soloed ones (one bool per track)
static func audible(tracks: Array) -> Array:
	var any_solo := false
	for t in tracks:
		any_solo = any_solo or bool(t.get("solo", false))
	var out := []
	for t in tracks:
		out.append(not bool(t.get("mute", false)) and (not any_solo or bool(t.get("solo", false))))
	return out


## the tracks that sound (for the playblast's mix)
static func audible_list(tracks: Array) -> Array:
	var on := audible(tracks)
	var out := []
	for i in tracks.size():
		if on[i]:
			out.append(tracks[i])
	return out


## the lane's name: the file name, the role when it is not music, MUTED / SOLO
static func label(t: Dictionary) -> String:
	var role := String(t.get("role", "music"))
	var s := String(t.get("path", "")).get_file()
	if role != "music":
		s += "  [%s]" % role
	if bool(t.get("mute", false)):
		s += "  MUTED"
	if bool(t.get("solo", false)):
		s += "  SOLO"
	return s


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


## THE PREMIX (ROADMAP 77). decode() reads a stream once through its own playback, at the mix rate, so any format Godot
## plays works; the playback is some frames late (playback_delay), and decode() takes that out so sample k of the result is
## stream time k / rate. mix_pcm() sums decoded tracks at their start samples with their gains and clips the sum to full scale,
## as one 16-bit stereo WAV: sample 0 is t = 0 of the timeline.
static var _delay := {}   # per mix rate: the frames a playback is late by (measured once)


## the frames a playback of a stream at this rate is late by (an impulse at frame 0 comes out at this frame)
static func playback_delay(rate: int) -> int:
	if _delay.has(rate):
		return _delay[rate]
	var probe := AudioStreamWAV.new()
	probe.format = AudioStreamWAV.FORMAT_16_BITS
	probe.mix_rate = rate
	probe.stereo = false
	var pcm := PackedByteArray()
	pcm.resize(64 * 2)
	pcm.encode_s16(0, 32767)
	probe.data = pcm
	var pb := probe.instantiate_playback()
	pb.start(0.0)
	var v: PackedVector2Array = pb.mix_audio(1.0, 64)
	var d := 0
	for j in v.size():
		if v[j].x > 0.5:
			d = j
			break
	_delay[rate] = d
	return d


## the stream as interleaved stereo float samples at rate, sample k = stream time k / rate (length = its length)
static func decode(stream: AudioStream, rate: int) -> PackedFloat32Array:
	var n := int(round(stream.get_length() * rate))
	var out := PackedFloat32Array()
	out.resize(n * 2)
	var d := playback_delay(rate)
	var pb := stream.instantiate_playback()
	pb.start(0.0)
	var got := 0   # playback frames read so far; playback frame j is stream frame j - d
	while got < n + d:
		var v: PackedVector2Array = pb.mix_audio(1.0, mini(MIX_CHUNK, n + d - got))
		if v.is_empty():
			break
		for j in v.size():
			var idx := got + j - d
			if idx >= 0 and idx < n:
				out[2 * idx] = v[j].x
				out[2 * idx + 1] = v[j].y
		got += v.size()
	return out


## the sum of decoded tracks: pcms[i] at start sample starts[i], scaled by gains[i] (linear), clipped to full scale, as 16-bit
## stereo PCM bytes. Pure arrays, no nodes, so it may run on a worker thread: its result goes to out[0].
static func mix_bytes(pcms: Array, starts: Array, gains: Array, out: Array) -> void:
	var frames := 0
	for i in pcms.size():
		frames = maxi(frames, int(starts[i]) + int(pcms[i].size() / 2))
	var buf := PackedFloat32Array()
	buf.resize(frames * 2)
	for i in pcms.size():
		var src: PackedFloat32Array = pcms[i]
		var s0: int = int(starts[i])
		var g: float = float(gains[i])
		var n := int(src.size() / 2)
		for k in n:
			var o := 2 * (s0 + k)
			buf[o] += src[2 * k] * g
			buf[o + 1] += src[2 * k + 1] * g
	var pcm := PackedByteArray()
	pcm.resize(frames * 4)
	for q in frames * 2:
		pcm.encode_s16(2 * q, int(round(clampf(buf[q], -1.0, 1.0) * 32767.0)))
	out[0] = pcm


## the 16-bit stereo WAV stream of mix_bytes' PCM at rate (main thread: the stream is a resource)
static func wav_of(pcm: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = true
	w.data = pcm
	return w


## the sum of decoded tracks as a stream (mix_bytes + wav_of, on this thread)
static func mix_pcm(pcms: Array, starts: Array, gains: Array, rate: int) -> AudioStreamWAV:
	var out := [null]
	mix_bytes(pcms, starts, gains, out)
	return wav_of(out[0], rate)


## decode every stream at its offset (s) with its gain (dB) and sum them: decode() + mix_pcm() in one call
static func mix(streams: Array, offsets: Array, gains_db: Array, rate: int) -> AudioStreamWAV:
	var pcms := []
	var starts := []
	var gains := []
	for i in streams.size():
		pcms.append(decode(streams[i], rate))
		starts.append(int(round(float(offsets[i]) * rate)))
		gains.append(db_to_linear(float(gains_db[i])))
	return mix_pcm(pcms, starts, gains, rate)


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
