## FPS CONVERT (L92, ROADMAP_400 L19): change a scene's frame rate and keep every moment where it was.
## Kine stores time in SECONDS (cards' move / hold, part keys "t", markers "t"), so a conversion never retimes anything: the new rate
## only changes where the frame grid falls, and a key that sits between two frames of the new rate is a SUB-FRAME KEY, kept exactly.
## What does count frames is the frame-indexed data (review notes "frame", hit / hurt boxes "f0" / "f1"): those follow the rate,
## frame * new / old, ties to the even frame (so 24 -> 30 -> 24 gives every frame back).
## SNAP (opt-in): each part key moves to the nearest whole frame of the new rate (at most half a frame). A key whose frame is
## already taken by the key before it (or would pass the key after it) stays where it is and is counted in "kept". Every move is reported.
## Pure: no node. The caller (fps_wave.gd) owns the undo step.
class_name FpsConvert
extends RefCounted

const MIN_FPS := 1
const MAX_FPS := 240


## frame * new / old with a tie going to the even frame
static func frame_of(f: int, old: int, new_fps: int) -> int:
	var x := float(f) * float(new_fps) / float(old)
	var fl := floorf(x)
	var d := x - fl
	if absf(d - 0.5) < 1e-9:
		return int(fl) if int(fl) % 2 == 0 else int(fl) + 1
	return int(roundf(x))


## {"ok", "from", "to", "snap", "moves": [{"what", "joint", "i", "from", "to", "dt"}], "kept", "max_move", "keys"}; ok false + "error" = nothing changed
static func convert(S: Scene, new_fps: int, snap := false) -> Dictionary:
	var old := S.fps
	if new_fps < MIN_FPS or new_fps > MAX_FPS:
		return {"ok": false, "error": "fps must be %d..%d" % [MIN_FPS, MAX_FPS], "moves": [], "kept": 0}
	if new_fps == old:
		return {"ok": false, "error": "the scene is already at %d fps" % old, "moves": [], "kept": 0}
	var moves := []
	var kept := 0
	var keys := 0
	var mx := 0.0
	if snap:
		var g := float(new_fps)
		for j in S.part_keys:
			var ks: Array = S.part_keys[j]
			for i in ks.size():
				keys += 1
				var t := float(ks[i]["t"])
				var s := roundf(t * g) / g
				var ok_prev: bool = i == 0 or s > float(ks[i - 1]["t"]) + 1e-9
				var ok_next: bool = i == ks.size() - 1 or s < float(ks[i + 1]["t"]) - 1e-9
				if absf(s - t) <= 1e-12:
					continue
				if not (ok_prev and ok_next):
					kept += 1
					continue
				ks[i]["t"] = s
				moves.append({"what": "part_key", "joint": j, "i": i, "from": t, "to": s, "dt": s - t})
				mx = maxf(mx, absf(s - t))
	else:
		for j in S.part_keys:
			keys += (S.part_keys[j] as Array).size()
	for n in S.notes:
		n["frame"] = frame_of(int(n["frame"]), old, new_fps)
	for b in S.boxes:
		for k in ["f0", "f1"]:
			if b.has(k):
				b[k] = frame_of(int(b[k]), old, new_fps)
	S.fps = new_fps
	return {"ok": true, "from": old, "to": new_fps, "snap": snap, "moves": moves, "kept": kept, "max_move": mx, "keys": keys}
