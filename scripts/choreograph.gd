## choreograph.gd - CHOREOGRAPH TO THE SONG (ROADMAP I22). Static, no UI (choreograph_ui.gd owns the panel, the preview and the file).
## With the music's beats found (beat_track.gd) it measures the ENERGY of the song and lays out a two-fighter fight skeleton on it:
##   ENERGY: the RMS loudness of the music's samples in each beat's window (beat to next beat), read from a PCM wav (the same
##     limit as the beat finder: ogg / mp3 samples cannot be read, and the panel says so). A BAR is 4 beats from the first downbeat;
##     its energy e is the mean beat RMS over the loudest bar (0..1).
##   EXCHANGES PER BAR follow e: below LEVELS[0] a pause (the guard is held, nobody strikes), then 1, 2 and 3 strikes. The strikes sit
##     on the bar's beats 0, 1, 2 (every 2nd beat, 0 and 2, when a beat is shorter than MIN_GAP: a fist cannot wind up and land
##     twice in 0.45 s), so every CONTACT lands on a beat (the cards are timed to it, then BeatFight.fit (I15) checks every one).
##   THE BIGGEST STRIKE is on the loudest DOWNBEAT: its move is the one of the bank that travels farthest, at the FASTEST time the
##     timing coach records for it (TimingCoach.peak_range). Every other strike is slower the quieter its beat: between 30 % and 100 %
##     of the way from the fastest to the slowest recorded time, so none is as hard as the biggest one. The impulse of a blow is
##     J = (1 + e) mu v (hit_physics.gd, I2): with the same striker and target mass, J follows the fist's speed, so the fastest is the biggest.
##   THE MOVES are Nick's own cards: a bank of (wind-up, strike, follow-through) triples read from his clips (a card the coach
##     calls a strike, StylePrint.kind_of_name, with the card before and the card after it). His style fingerprint (I17) sets the
##     wind-up time when it has one; the wind-up is never shorter than TimingCoach.ANTIC_RATIO x the strike, the follow-through never
##     shorter than SETTLE_RATIO x it. Where two strikes are too close for that (gap / 3 under the fastest time), the second is dropped.
##   THE ANSWERS are FightPhrase.plan (I11): the defender blocks or slips each strike; its cards are written in its own scene.
## plan() builds the scene (the attacker with a "hit" marker per contact, the defender in actors); nothing is written to a file.
class_name Choreograph
extends RefCounted

const BAR := 4                      # beats
const LEVELS := [0.25, 0.5, 0.75]   # bar energy below each: 0, 1, 2 strikes; above the last: 3 (ours)
const MIN_GAP := 0.45               # s between two contacts at the least (ours: ANTIC 2 + strike 1 parts of >= 0.11 s each + margin)
const SLOW_MIN := 0.3               # a non-peak strike is this far (of lo..hi) toward the slowest, at the loudest beat
const DEF_DIST := 1.8               # m: where the defender stands (the range manager of I11 steps in)
const WINDUP := 0.35                # s: the default wind-up when there is no style fingerprint
const BANK_MAX := 12


## per-beat RMS of the music: {"ok", "msg", "rms": [one per beat]}; the beat's window is [t, next t) (the last beat reuses the period before it)
static func energy(stream: AudioStream, beats: Array) -> Dictionary:
	var bad := {"ok": false, "msg": "", "rms": []}
	if stream == null or not (stream is AudioStreamWAV):
		bad["msg"] = "the energy needs the samples of a wav: add the song as a wav with the music role, then run Beats: find the beats"
		return bad
	var w := stream as AudioStreamWAV
	var bytes := 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else (1 if w.format == AudioStreamWAV.FORMAT_8_BITS else 0)
	if bytes == 0 or w.mix_rate <= 0:
		bad["msg"] = "the energy needs 8 or 16 bit PCM wav: this file is compressed"
		return bad
	var bs := BeatTrack.clean_list(beats)
	if bs.size() < 2:
		bad["msg"] = "no beats yet: run Beats: find the beats in the sound first"
		return bad
	var ch := 2 if w.stereo else 1
	var data := w.data
	var frames := data.size() / (bytes * ch)
	var scale := 1.0 / (32768.0 if bytes == 2 else 128.0)
	var out := []
	for k in bs.size():
		var t0 := float(bs[k]["t"])
		var t1 := float(bs[k + 1]["t"]) if k + 1 < bs.size() else t0 + (t0 - float(bs[k - 1]["t"]))
		var f0 := clampi(int(t0 * w.mix_rate), 0, frames)
		var f1 := clampi(int(t1 * w.mix_rate), f0, frames)
		var stride := maxi(1, (f1 - f0) / 4000)
		var acc := 0.0
		var n := 0
		var f := f0
		while f < f1:
			var v := 0.0
			for c in ch:
				var o := (f * ch + c) * bytes
				v += (float(data.decode_s16(o)) if bytes == 2 else float(data.decode_s8(o))) * scale
			v /= ch
			acc += v * v
			n += 1
			f += stride
		out.append(sqrt(acc / n) if n > 0 else 0.0)
	return {"ok": true, "msg": "", "rms": out}


## the bars: [{"i0" (first beat index), "t0", "t1", "e" 0..1, "n" strikes, "down" rms of the downbeat}] from the first downbeat
static func bars(beats: Array, off: float, rms: Array) -> Array:
	var bs := BeatTrack.clean_list(beats)
	var first := 0
	for i in bs.size():
		if bs[i]["down"]:
			first = i
			break
	var out := []
	var i := first
	while i + BAR <= bs.size():
		var m := 0.0
		for k in BAR:
			m += float(rms[i + k])
		m /= BAR
		var t1 := float(bs[i + BAR]["t"]) + off if i + BAR < bs.size() else float(bs[i + BAR - 1]["t"]) + off + (float(bs[i + BAR - 1]["t"]) - float(bs[i + BAR - 2]["t"]))
		out.append({"i0": i, "t0": float(bs[i]["t"]) + off, "t1": t1, "m": m, "down": float(rms[i]), "e": 0.0, "n": 0})
		i += BAR
	var top := 0.0
	for b in out:
		top = maxf(top, float(b["m"]))
	for b in out:
		var e := float(b["m"]) / top if top > 0.0 else 0.0
		b["e"] = e
		b["n"] = 0 if e < LEVELS[0] else (1 if e < LEVELS[1] else (2 if e < LEVELS[2] else 3))
	return out


## the bank of Nick's moves from scene files: [{"name", "src", "ready", "windup", "strike", "follow" (poses), "d" (m the hand travels), "lo", "hi" (s, the coach's range)}]
## sorted by d, the longest first. Poses that step away from the spot (hips offset over 0.1 m) are left out: the bank is chained.
static func bank(paths: Array, B: Body) -> Array:
	var out := []
	for p in paths:
		if not FileAccess.file_exists(p):
			continue
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if not (d is Dictionary):
			continue
		var S := Scene.new()
		S.from_dict(d)
		if S.cards.size() < 3 or not S.actors.is_empty():
			continue
		for i in range(2, S.cards.size()):
			if StylePrint.kind_of_name(String(S.cards[i]["name"])) != "strike":
				continue
			var po: Array = (S.cards[i]["pose"] as Dictionary).get("offset", [0, 0, 0])
			var pw: Array = (S.cards[i - 1]["pose"] as Dictionary).get("offset", [0, 0, 0])
			if Vector3(po[0], po[1], po[2]).length() > 0.1 or Vector3(pw[0], pw[1], pw[2]).length() > 0.1:
				continue
			var t := Scene.new()
			t.from_dict({"scene": "zz_bank", "fps": 30, "cards": [
				{"name": "a", "pose": S.cards[i - 1]["pose"], "move": -1.0, "hold": 0.2}, {"name": "STRIKE", "pose": S.cards[i]["pose"], "move": 0.15, "hold": 0.0}]})
			var rg := BeatFight.strike_range(t, B, 1)
			if not is_finite(float(rg[1])):
				continue   # the hand barely travels: not a strike
			var fol: Dictionary = S.cards[i + 1]["pose"] if i + 1 < S.cards.size() else S.cards[0]["pose"]
			out.append({"name": String(S.cards[i]["name"]), "src": String(p).get_file().get_basename(), "ready": S.cards[0]["pose"], "windup": S.cards[i - 1]["pose"],
				"strike": S.cards[i]["pose"], "follow": fol, "d": float(rg[2]), "lo": float(rg[0]), "hi": float(rg[1])})
	out.sort_custom(func(a, b): return float(a["d"]) > float(b["d"]))
	return out.slice(0, BANK_MAX)


static func _body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


static func _stand() -> Dictionary:
	var b := _body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b.to_dict()


## the strike beats of a bar: beat offsets inside it
static func slots(n: int, period: float) -> Array:
	var stride := 1 if period >= MIN_GAP else 2
	var out := []
	for k in n:
		if k * stride < BAR:
			out.append(k * stride)
	return out


## THE PLAN. beats = S.beats_audio, off = the music's offset, rms = energy()["rms"], bank = bank(), fp = the style fingerprint ({} = none).
## Returns {"ok", "msg", "bars", "strikes": [{t, bar, slot, e, peak, move, T, J}], "dropped", "scene" (hero; the defender in .actors),
## "peak_t", "fit" (BeatFight.fit's result on the attacker), "defence" (FightPhrase's), "length"}
static func plan(B: Body, beats: Array, off: float, rms: Array, bk: Array, fp := {}) -> Dictionary:
	var res := {"ok": false, "msg": "", "bars": [], "strikes": [], "dropped": 0}
	var bs := BeatTrack.clean_list(beats)
	if bs.size() < BAR + 1 or rms.size() < bs.size():
		res["msg"] = "no beats or energy yet: add the song as a wav with the music role, run Beats: find the beats, then Choreograph to the song"
		return res
	if bk.is_empty():
		res["msg"] = "no strike moves to choose from: name the strike cards of your clips (strike, punch, contact...) so the bank can find them"
		return res
	var period := (float(bs[bs.size() - 1]["t"]) - float(bs[0]["t"])) / float(bs.size() - 1)
	var bl := bars(bs, off, rms)
	res["bars"] = bl
	# the loudest beat overall (the strike's own energy is its beat's RMS against it) and the loudest DOWNBEAT
	var top_b := 0.0
	for v in rms:
		top_b = maxf(top_b, float(v))
	var peak_bar := -1
	for k in bl.size():
		if peak_bar < 0 or float(bl[k]["down"]) > float(bl[peak_bar]["down"]) + 1e-9:
			peak_bar = k
	if peak_bar < 0 or top_b <= 0.0:
		res["msg"] = "the music is silent or shorter than one bar: nothing to choreograph"
		return res
	if int(bl[peak_bar]["n"]) < 1:
		bl[peak_bar]["n"] = 1   # the loudest downbeat always gets its strike
	var windup_t: float = WINDUP
	var tg := StylePrint.target(fp, "windup")
	if not tg.is_empty():
		windup_t = float(tg["move"])
	# the contacts, in order
	var cs := []
	var peak_i := -1
	for k in bl.size():
		for sl in slots(int(bl[k]["n"]), period):
			var bi: int = int(bl[k]["i0"]) + int(sl)
			var e := float(rms[bi]) / top_b
			var rec := {"t": float(bs[bi]["t"]) + off, "bar": k, "slot": sl, "e": e, "peak": k == peak_bar and sl == 0}
			if rec["peak"]:
				peak_i = cs.size()
			cs.append(rec)
	# which bank move, and its time (the peak: the farthest-travelling move at the fastest recorded time)
	var strikes := []
	var rr := 1
	var dropped := 0
	var prev_t := -1.0
	for c in cs:
		var mv: Dictionary = bk[0]
		if not c["peak"] and bk.size() > 1:
			mv = bk[1 + rr % (bk.size() - 1)]   # the others take turns; the farthest-travelling move is the peak's
			rr += 1
		var lo := float(mv["lo"])
		var hi := float(mv["hi"])
		var T := snappedf(lo + 0.0005, 0.001) if c["peak"] else snappedf(lo + (hi - lo) * (SLOW_MIN + (1.0 - SLOW_MIN) * (1.0 - minf(1.0, float(c["e"])))), 0.001)
		T = clampf(T, snappedf(lo + 0.0005, 0.001), hi)
		if prev_t >= 0.0:
			var gap: float = float(c["t"]) - prev_t
			if gap < MIN_GAP - 1e-6 or T * (1.0 + TimingCoach.ANTIC_RATIO) > gap + 1e-6:
				if c["peak"]:
					# the peak never goes: the strike before it is dropped instead
					if not strikes.is_empty():
						strikes.pop_back()
						dropped += 1
				else:
					dropped += 1
					continue
		c["move"] = mv
		c["T"] = T
		strikes.append(c)
		prev_t = float(c["t"])
	res["strikes"] = strikes
	res["dropped"] = dropped
	# the cards of the attacker
	var A := Scene.new()
	var ready: Dictionary = (bk[0]["ready"] as Dictionary).duplicate(true)
	A.from_dict({"scene": "choreo_song", "fps": 30, "cards": [{"name": "ready", "pose": ready, "move": -1.0, "hold": 0.0}]})
	var cards := A.cards
	var arrive_prev := 0.0   # arrival time of the last card written
	var markers := []
	var n_strike := 0
	for k in strikes.size():
		var c: Dictionary = strikes[k]
		var mv: Dictionary = c["move"]
		var T: float = c["T"]
		var Tk: float = c["t"]
		var avail := Tk - T - arrive_prev
		var W := clampf(windup_t, maxf(TimingCoach.ANTIC_RATIO * T, 0.1), maxf(avail, 0.1))
		W = minf(W, avail)
		if W < TimingCoach.ANTIC_RATIO * T - 1e-6 or avail < 0.05:
			W = maxf(avail, 0.04)
		(cards[cards.size() - 1] as Dictionary)["hold"] = snappedf(maxf(0.0, avail - W), 0.001)
		cards.append({"name": "wind-up %d" % (k + 1), "pose": (mv["windup"] as Dictionary).duplicate(true), "move": snappedf(W, 0.001), "hold": 0.0})
		cards.append({"name": "STRIKE %d" % (k + 1), "pose": (mv["strike"] as Dictionary).duplicate(true), "move": T, "hold": 0.0})
		arrive_prev = Tk - T + 0.0 + T   # the strike lands at Tk by construction (hold + wind-up + strike sum to it)
		arrive_prev = Tk
		markers.append({"t": Tk, "name": "hit %d" % (k + 1), "kind": "hit"})
		n_strike += 1
		# the follow-through when the next wind-up still has room (>= 2 x the next strike or 0.2 s) after it
		var F := maxf(TimingCoach.SETTLE_RATIO * T, 0.25)
		var next_room := INF
		if k + 1 < strikes.size():
			next_room = float(strikes[k + 1]["t"]) - float(strikes[k + 1]["T"]) - (Tk + F)
		var need: float = maxf(TimingCoach.ANTIC_RATIO * (float(strikes[k + 1]["T"]) if k + 1 < strikes.size() else 0.0), 0.2)
		if next_room >= need:
			cards.append({"name": "follow-through %d" % (k + 1), "pose": (mv["follow"] as Dictionary).duplicate(true), "move": snappedf(F, 0.001), "hold": 0.0})
			arrive_prev = Tk + F
	# back to the guard at the end of the music
	var end_t := float(bl[bl.size() - 1]["t1"]) if not bl.is_empty() else arrive_prev + 0.5
	end_t = maxf(end_t, arrive_prev + 0.4)
	var rd := end_t - arrive_prev
	cards.append({"name": "ready (end)", "pose": ready.duplicate(true), "move": snappedf(minf(0.5, rd), 0.001), "hold": snappedf(maxf(0.0, rd - 0.5), 0.001)})
	A.markers = Markers.sorted(markers)
	A.beats_audio = bs.duplicate(true)
	# I15: every contact is checked against the beat grid and the coach's range (the cards already sit on it: nothing should move)
	var fit := BeatFight.fit(A, B, bs, off, "every", false)
	res["fit"] = fit
	# I11: the defender answers
	var D := Scene.new()
	var stand := _stand()
	D.from_dict({"scene": "zz_still", "fps": 30, "cards": [{"name": "guard", "pose": stand, "move": -1.0, "hold": maxf(1.0, A.length() - 0.5)},
		{"name": "guard (hold)", "pose": stand, "move": 0.5, "hold": 1.0}]})
	var xf := {"pos": [0.0, DEF_DIST], "yaw": 180.0}
	var rel := Transform3D(Basis(Vector3.UP, deg_to_rad(180.0)), Vector3(0.0, 0.0, DEF_DIST))
	var defence := {"ok": false, "why": "no strike was laid out"}
	if n_strike > 0:
		defence = FightPhrase.plan(A, D, rel)
		if defence.get("ok", false):
			FightPhrase.apply_plan(D, defence)
	res["defence"] = defence
	A.actors = [{"name": "fighter 2", "xf": xf, "scene": D}]
	res["scene"] = A
	res["peak_t"] = float(strikes[peak_i if peak_i < strikes.size() else 0]["t"]) if not strikes.is_empty() else -1.0
	for s in strikes:
		if s["peak"]:
			res["peak_t"] = float(s["t"])
	res["length"] = A.length()
	res["ok"] = n_strike > 0
	var per := []
	for b in bl:
		per.append(int(b["n"]))
	res["msg"] = "%d bars, %d strikes (per bar %s)%s; the biggest on the loudest downbeat at %.2f s" % [bl.size(), n_strike, str(per), (", %d dropped for room" % dropped) if dropped > 0 else "", float(res["peak_t"])]
	return res
