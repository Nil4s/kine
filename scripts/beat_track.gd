## beat_track.gd - MUSIC BEATS (ROADMAP 32). Finds the beats of the scene's sound and snaps contact cards to them.
## DETECTION (Ellis 2007, "Beat tracking by dynamic programming", J. New Music Research 36(1)):
##   1. onsets: the sound decimated to 11.025 kHz (mean of 4 samples), 256-sample Hann frames (23 ms), hop 128 (11.6 ms);
##      spectral flux = the sum over bins of the positive rise of |X| from one frame to the next.
##   2. tempo: autocorrelation of the onset envelope at lags of 60..200 BPM; the shortest lag that is a local peak
##      within 10 % of the best (so a click track reads as its beat, not twice or half of it).
##   3. beats: Ellis's dynamic programme. C[t] = O[t] + max over earlier frames tau of (C[tau] - LAMBDA (log(dt / P))^2),
##      P = the period in frames. The best path is the beat sequence; each beat is then moved to the 50 % rise of the
##      sound's own waveform (within 25 ms), so the beat time is the onset, not the analysis frame.
##   4. downbeats: the beat phase (of 4) with the strongest onsets is the bar's first beat, but only when it is clearly
##      stronger (1.2 x the other three phases); otherwise no bar is claimed and every beat is plain.
## SNAP: each contact card (a card a "hit" marker sits on, Markers) moves its arrival onto the nearest beat by changing
## that card's move time. A move may change by at most SNAP_MAX of itself; a snap that needs more is refused whole.
## Beat times are in the SOUND's time (from the file's start); the scene time of a beat is t + Scene.audio.offset.
## Scenes hold them as "beats_audio": [{"t", "down"}] sorted by t, only when there are any (old scenes save as before).
## Pure helpers: no node. Only WAV can be read sample by sample (Godot gives no PCM for ogg or mp3).
class_name BeatTrack
extends RefCounted

const DEC := 4              # decimation: 44.1 kHz -> 11.025 kHz
const FFT_N := 256          # 23.2 ms at 11.025 kHz
const HOP := 128            # 11.6 ms
const BPM_MIN := 60.0
const BPM_MAX := 200.0
const LAMBDA := 100.0       # Ellis's transition penalty
const BAR_RATIO := 1.2      # the 4/4 phase must be this much stronger than the mean of the others
const REFINE := 0.025       # s: the onset is looked for this close to the analysis time
const SNAP_MAX := 0.25      # a snap may change a move by at most this fraction of its time


## mono samples in -1..1, decimated (mean of DEC frames): {"ok", "msg", "x", "rate"}. Only 8 and 16 bit PCM WAV.
static func mono(stream: AudioStream) -> Dictionary:
	var bad := {"ok": false, "msg": "", "x": PackedFloat32Array(), "rate": 0.0}
	if stream == null or not (stream is AudioStreamWAV):
		bad["msg"] = "beats need a wav: Godot cannot read ogg or mp3 samples here, so no beats can be found in that sound"
		return bad
	var w := stream as AudioStreamWAV
	var bytes := 1
	if w.format == AudioStreamWAV.FORMAT_16_BITS:
		bytes = 2
	elif w.format != AudioStreamWAV.FORMAT_8_BITS:
		bad["msg"] = "beats need 8 or 16 bit PCM wav: this file is compressed"
		return bad
	var ch := 2 if w.stereo else 1
	var frames := w.data.size() / (bytes * ch)
	if frames < FFT_N * DEC or w.mix_rate <= 0:
		bad["msg"] = "the sound is too short to find beats in"
		return bad
	var nd := frames / DEC
	var x := PackedFloat32Array()
	x.resize(nd)
	var scale := 1.0 / (32768.0 if bytes == 2 else 128.0) / ch
	var data := w.data
	for i in nd:
		var acc := 0.0
		for k in DEC:
			var base := ((i * DEC + k) * ch) * bytes
			for c in ch:
				var o := base + c * bytes
				acc += float(data.decode_s16(o)) if bytes == 2 else float(data.decode_s8(o))
		x[i] = acc * scale / DEC
	return {"ok": true, "msg": "", "x": x, "rate": float(w.mix_rate) / DEC}


## the onset envelope: spectral flux per hop. Returns {"env": PackedFloat32Array, "fr": frames per second}
static func onsets(x: PackedFloat32Array, rate: float) -> Dictionary:
	var tb := _tables()
	var rev: PackedInt32Array = tb[0]
	var cs: PackedFloat32Array = tb[1]
	var sn: PackedFloat32Array = tb[2]
	var win := PackedFloat32Array()
	win.resize(FFT_N)
	for i in FFT_N:
		win[i] = 0.5 - 0.5 * cos(TAU * i / FFT_N)
	var nf := maxi(0, (x.size() - FFT_N) / HOP + 1)
	var env := PackedFloat32Array()
	env.resize(nf)
	var re := PackedFloat32Array()
	re.resize(FFT_N)
	var im := PackedFloat32Array()
	im.resize(FFT_N)
	var mag := PackedFloat32Array()
	mag.resize(FFT_N / 2 + 1)
	var prev := PackedFloat32Array()
	prev.resize(FFT_N / 2 + 1)
	for f in nf:
		var s := f * HOP
		for i in FFT_N:
			re[rev[i]] = x[s + i] * win[i]
			im[rev[i]] = 0.0
		var size := 2
		while size <= FFT_N:
			var half := size >> 1
			var step := FFT_N / size
			var st := 0
			while st < FFT_N:
				for j in half:
					var wr := cs[j * step]
					var wi := sn[j * step]
					var a := st + j
					var b := a + half
					var tr := re[b] * wr - im[b] * wi
					var ti := re[b] * wi + im[b] * wr
					re[b] = re[a] - tr
					im[b] = im[a] - ti
					re[a] += tr
					im[a] += ti
				st += size
			size <<= 1
		var flux := 0.0
		for k in FFT_N / 2 + 1:
			var v := sqrt(re[k] * re[k] + im[k] * im[k]) / FFT_N   # linear: a loud onset counts in proportion to its level
			var d := v - prev[k]
			if d > 0.0:
				flux += d
			prev[k] = v
		env[f] = flux
	return {"env": env, "fr": rate / HOP}


## the bit-reversal table and the twiddles of a FFT_N point FFT: [rev, cos, sin] (sin is negated: forward transform)
static func _tables() -> Array:
	var bits := int(round(log(FFT_N) / log(2.0)))
	var rev := PackedInt32Array()
	rev.resize(FFT_N)
	for i in FFT_N:
		var r := 0
		for b in bits:
			if i & (1 << b):
				r |= 1 << (bits - 1 - b)
		rev[i] = r
	var cs := PackedFloat32Array()
	var sn := PackedFloat32Array()
	cs.resize(FFT_N / 2)
	sn.resize(FFT_N / 2)
	for k in FFT_N / 2:
		cs[k] = cos(TAU * k / FFT_N)
		sn[k] = -sin(TAU * k / FFT_N)
	return [rev, cs, sn]


## the tempo in BPM from the envelope's autocorrelation over 60..200 BPM (0 when the envelope is flat or too short)
static func tempo(env: PackedFloat32Array, fr: float) -> float:
	var n := env.size()
	var lo := maxi(1, int(floor(fr * 60.0 / BPM_MAX)))
	var hi := mini(int(ceil(fr * 60.0 / BPM_MIN)), n / 2)
	if hi <= lo + 2:
		return 0.0
	var mean := 0.0
	for v in env:
		mean += v
	mean /= maxf(n, 1)
	var e := PackedFloat32Array()
	e.resize(n)
	for i in n:
		e[i] = env[i] - mean
	var ac := PackedFloat32Array()
	ac.resize(hi + 2)
	var best := 0.0
	for lag in range(lo - 1, hi + 2):
		var s := 0.0
		for i in n - lag:
			s += e[i] * e[i + lag]
		ac[lag] = s / (n - lag)
		if lag >= lo and lag <= hi:
			best = maxf(best, ac[lag])
	if best <= 0.0:
		return 0.0
	for lag in range(lo, hi + 1):
		if ac[lag] >= 0.9 * best and ac[lag] >= ac[lag - 1] and ac[lag] >= ac[lag + 1]:
			var a := ac[lag - 1]
			var b := ac[lag]
			var c := ac[lag + 1]
			var den := a - 2.0 * b + c
			var off := 0.5 * (a - c) / den if absf(den) > 1e-12 else 0.0
			return 60.0 * fr / (lag + clampf(off, -0.5, 0.5))
	return 0.0


## Ellis's beat sequence at tempo bpm: frame indices of the beats, ascending
static func track(env: PackedFloat32Array, fr: float, bpm: float) -> PackedInt32Array:
	var n := env.size()
	var out := PackedInt32Array()
	if n == 0 or bpm <= 0.0:
		return out
	var mean := 0.0
	for v in env:
		mean += v
	mean /= n
	var sd := 0.0
	for v in env:
		sd += (v - mean) * (v - mean)
	sd = sqrt(sd / n)
	if sd <= 0.0:
		return out
	var P := fr * 60.0 / bpm
	var dlo := maxi(1, int(round(P / 2.0)))
	var dhi := int(round(2.0 * P))
	var C := PackedFloat32Array()
	C.resize(n)
	var back := PackedInt32Array()
	back.resize(n)
	for t in n:
		var z := (env[t] - mean) / sd
		var best := -INF
		var bi := -1
		for d in range(dlo, dhi + 1):
			var tau := t - d
			if tau < 0:
				break
			var r := log(float(d) / P)
			var v := C[tau] - LAMBDA * r * r
			if v > best:
				best = v
				bi = tau
		if bi >= 0:
			C[t] = z + best
			back[t] = bi
		else:
			C[t] = z
			back[t] = -1
	var t_end := n - 1
	for t in range(maxi(0, n - dhi), n):
		if C[t] > C[t_end]:
			t_end = t
	var path := []
	var cur := t_end
	while cur >= 0:
		path.append(cur)
		cur = back[cur]
	path.reverse()
	for f in path:
		out.append(f)
	return out


## the onset time near analysis time t (s): the first sample within REFINE of t whose |value| reaches half the
## window's peak (the start of the sound, not the middle of the analysis frame)
static func refine(x: PackedFloat32Array, rate: float, t: float) -> float:
	var a := clampi(int(floor((t - REFINE) * rate)), 0, x.size() - 1)
	var b := clampi(int(ceil((t + REFINE) * rate)), a, x.size() - 1)
	var pk := 0.0
	for i in range(a, b + 1):
		pk = maxf(pk, absf(x[i]))
	if pk <= 0.0:
		return t
	for i in range(a, b + 1):
		if absf(x[i]) >= 0.5 * pk:
			return float(i) / rate
	return t


## the beats of a sound stream: {"ok", "msg", "bpm", "beats": [{"t", "down"}]} (t in the sound's own time)
static func analyze(stream: AudioStream) -> Dictionary:
	var m := mono(stream)
	if not m["ok"]:
		return {"ok": false, "msg": m["msg"], "bpm": 0.0, "beats": []}
	var x: PackedFloat32Array = m["x"]
	var rate: float = m["rate"]
	var on := onsets(x, rate)
	var env: PackedFloat32Array = on["env"]
	var fr: float = on["fr"]
	var bpm := tempo(env, fr)
	if bpm <= 0.0:
		return {"ok": false, "msg": "no steady beat found in this sound (no tempo between 60 and 200 BPM)", "bpm": 0.0, "beats": []}
	var frames := track(env, fr, bpm)
	# the path starts at the first frame, so leading beats before the sound starts are dropped (onset strength below the mean)
	var emean := 0.0
	for v in env:
		emean += v
	emean /= maxi(env.size(), 1)
	var k0 := 0
	while k0 < frames.size() - 2 and env[frames[k0]] < emean:
		k0 += 1
	frames = frames.slice(k0)
	if frames.size() < 2:
		return {"ok": false, "msg": "no beats found in this sound", "bpm": bpm, "beats": []}
	var times := PackedFloat32Array()
	for f in frames:
		# the analysis frame's centre, then the onset next to it
		times.append(refine(x, rate, (f * HOP + FFT_N / 2) / rate))
	# the tempo from the beats themselves (least squares on the beat index): sharper than the lag grid
	var n := times.size()
	var mi := (n - 1) * 0.5
	var mt := 0.0
	for v in times:
		mt += v
	mt /= n
	var sxy := 0.0
	var sxx := 0.0
	for i in n:
		sxy += (i - mi) * (times[i] - mt)
		sxx += (i - mi) * (i - mi)
	var period := sxy / sxx if sxx > 0.0 else 60.0 / bpm
	if absf(60.0 / period - bpm) < 3.0:
		bpm = 60.0 / period
	# downbeats: the phase of 4 with the strongest onsets, only when clearly stronger than the other three
	var phase_sum := [0.0, 0.0, 0.0, 0.0]
	var phase_n := [0, 0, 0, 0]
	for i in n:
		var p := i % 4
		phase_sum[p] += env[frames[i]]
		phase_n[p] += 1
	var means := []
	for p in 4:
		means.append(phase_sum[p] / maxi(phase_n[p], 1))
	var bestp := 0
	for p in 4:
		if means[p] > means[bestp]:
			bestp = p
	var others := 0.0
	for p in 4:
		if p != bestp:
			others += means[p] / 3.0
	var bar: bool = others > 0.0 and float(means[bestp]) >= BAR_RATIO * others and n >= 8
	var beats := []
	for i in n:
		beats.append({"t": snappedf(times[i], 0.001), "down": bar and i % 4 == bestp})
	return {"ok": true, "msg": "", "bpm": snappedf(bpm, 0.1), "beats": beats}


## the file's list -> clean, sorted [{"t", "down"}] (anything without a t is dropped)
static func clean_list(l) -> Array:
	var out := []
	if l is Array:
		for d in l:
			if d is Dictionary and d.has("t"):
				out.append({"t": snappedf(float(d["t"]), 0.001), "down": bool(d.get("down", false))})
	out.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	return out


## the nearest beat time to t (scene time = sound time + offset); -1 when there are none
static func nearest(beats: Array, t: float, off: float) -> float:
	var best := INF
	var bt := -1.0
	for b in beats:
		var bs: float = float(b["t"]) + off
		if absf(bs - t) < absf(best - t):
			best = bs
			bt = bs
	return bt


## SNAP. Moves each contact card's arrival onto the nearest beat, in time order, on scene S (pass a clone first).
## A contact card = the card nearest to a "hit" marker (Markers kind hit). Returns
## {"ok", "msg", "moves": [[card index, change s]], "contacts": n}. When any change is more than SNAP_MAX of its move, ok is
## false: S is then part-changed, so the caller runs this on a clone and copies the cards over only when ok.
static func snap(S: Scene, beats: Array, off: float) -> Dictionary:
	var res := {"ok": false, "msg": "", "moves": [], "contacts": 0}
	var hits := []
	for mk in S.markers:
		if String(mk["kind"]) == "hit":
			hits.append(float(mk["t"]))
	if hits.is_empty():
		res["msg"] = "no contacts to snap: put a hit marker (kind hit) on each strike card first"
		return res
	if beats.is_empty():
		res["msg"] = "no beats to snap to: find the beats in the sound first"
		return res
	hits.sort()
	var done := {}
	for t in hits:
		var ts := S.times()
		var best := -1
		for i in range(1, S.cards.size()):
			if best < 0 or absf(float(ts[i][1]) - t) < absf(float(ts[best][1]) - t):
				best = i
		if best < 0 or done.has(best):
			continue
		done[best] = true
		var arrive := float(ts[best][1])
		var target := nearest(beats, arrive, off)
		var d := target - arrive
		var mv := S.move_time(best)
		if absf(d) > SNAP_MAX * mv + 1e-6:
			res["msg"] = "refused: contact card %d (%s) lands %.0f ms from the nearest beat, which would retime its %.0f ms move by %.0f%% (the most allowed is %.0f%%). Nothing changed" % [
				best + 1, S.cards[best]["name"], absf(d) * 1000.0, mv * 1000.0, absf(d) / mv * 100.0, SNAP_MAX * 100.0]
			res["moves"] = []
			return res
		var nm := mv + d
		if nm < 0.05:
			res["msg"] = "refused: contact card %d (%s) would have a move of %.0f ms" % [best + 1, S.cards[best]["name"], nm * 1000.0]
			res["moves"] = []
			return res
		S.cards[best]["move"] = snappedf(nm, 0.001)
		res["moves"].append([best, snappedf(d, 0.001)])
	res["ok"] = not res["moves"].is_empty()
	res["contacts"] = res["moves"].size()
	if not res["ok"]:
		res["msg"] = "no contact card needs a change: they already sit on beats"
	return res
