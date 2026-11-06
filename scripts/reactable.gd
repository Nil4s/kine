## reactable.gd - REACTABLE OR NOT (INNOVATIONS N082). Fairness from the body: for each strike, how many frames does a viewer have
## between the moment the strike can be SEEN coming (the tell) and its first ACTIVE frame, against the frames a human needs to react?
##   TELL    = the start of the earliest frame of the striking-tip motion >= SEE_SPEED (0.5 m/s, a hand clearly moving) that leads into the
##             run's first active frame; a still stretch of up to GAP_F frames (an eased wind-up pausing at its top) is bridged,
##             a longer rest ends the tell, so a long hold before the wind-up is not counted.
##   NEED    = ceil((Counter.REACT + latency) * fps) frames. Counter.REACT is the project's wind-up-to-counter constant (I3/I31);
##             latency is an input (0 offline; an online game adds its netcode delay, a user assumption, not a measured number).
##   WINDOW  = first active - tell. REACTABLE <=> window >= need. margin_f = window - need.
## Input is a FrameData.analyze result (frames[].speed, frames[].active), so it works for any clip the frame data works for.
class_name Reactable
extends RefCounted

const SEE_SPEED := 0.5   # m/s: tip speed at which a motion counts as visible
const GAP_F := 6         # frames: a still stretch up to this long inside a wind-up does not end the tell


static func need_frames(latency_ms: float, fps: int) -> int:
	return int(ceil((Counter.REACT + latency_ms / 1000.0) * float(fps) - 1e-6))


## {"ok", "fps", "latency_ms", "need_f", "runs": [{n, readable, first_active, window_f, window_s, need_f, margin_f, status, text}], "msg"}
static func analyze(fd: Dictionary, latency_ms := 0.0) -> Dictionary:
	if fd.is_empty():
		return {"ok": false, "fps": 0, "latency_ms": latency_ms, "need_f": 0, "runs": [], "msg": "no frame data: the scene is empty"}
	var fps: int = fd["fps"]
	var need := need_frames(latency_ms, fps)
	var fr: Array = fd["frames"]
	var starts := []
	for i in fr.size():
		if bool(fr[i]["active"]) and (i == 0 or not bool(fr[i - 1]["active"])):
			starts.append(i)
	var runs := []
	var prev_end := 0
	for k in starts.size():
		var fa: int = starts[k]
		var t := fa
		var low := 0
		for g in range(fa - 1, prev_end - 1, -1):
			if float(fr[g]["speed"]) >= SEE_SPEED:
				t = g
				low = 0
			else:
				low += 1
				if low > GAP_F:
					break
		var w := fa - t
		var ok := w >= need
		var d := {"n": k + 1, "readable": t, "first_active": fa, "window_f": w, "window_s": float(w) / float(fps), "need_f": need,
			"margin_f": w - need, "status": "reactable" if ok else "not reactable"}
		d["text"] = ("strike %d: seen at f %d, active at f %d: %d f (%.2f s) to react, needs %d f: %s" % [k + 1, t, fa, w, d["window_s"], need,
			"reactable (%d f to spare)" % (w - need) if ok else "NOT reactable (%d f short)" % (need - w)])
		runs.append(d)
		# the next run's tell may not reach back into this run's active frames
		var j := fa
		while j < fr.size() and bool(fr[j]["active"]):
			j += 1
		prev_end = j
	var msg := "no strike in this clip: no active frames" if runs.is_empty() else "%d strike%s, %d not reactable" % [runs.size(), "" if runs.size() == 1 else "s",
		runs.filter(func(r): return r["status"] != "reactable").size()]
	return {"ok": not runs.is_empty(), "fps": fps, "latency_ms": latency_ms, "need_f": need, "runs": runs, "msg": msg}


static func of_scene(S: Scene, B: Body, fps := FrameData.FPS, latency_ms := 0.0) -> Dictionary:
	return analyze(FrameData.analyze(S, B, fps), latency_ms)


static func words(r: Dictionary) -> String:
	if not r.get("ok", false):
		return String(r.get("msg", ""))
	var lines := []
	for x in r["runs"]:
		lines.append(String(x["text"]))
	return "\n".join(lines)


static func to_json(r: Dictionary) -> Dictionary:
	return r.duplicate(true)
