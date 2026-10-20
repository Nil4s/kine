## MARKERS (round 41, GATES WW5, UPGRADES_300 #261 + the export half of UPGRADES_200 #106): named moments on the scene's
## timeline, the way an editor drops a cue: [{"t": seconds, "name": String, "kind": "hit"|"step"|"swoosh"|"note"}] sorted
## by t. The game that plays an export fires its own sound / spark / camera shake on them ("events" in the game JSON,
## t as a fraction of the length). They are written to the scene file only when there are any (old scenes save as before).
## ROADMAP 97: a marker may also carry "note" (free text, several lines; in the file only when not empty) and "color"
## (one of PALETTE: "red" | "green" | "blue" | "gold", the Tok tokens mk_*; absent = the colour of its kind). The .glb
## export puts them on its first animation as extras "poser_markers" (glTF extras are what engines read; BVH has no
## place for them, so BVH carries none). All static: the Scene holds the array (Scene.markers), main.gd owns the undo.
class_name Markers

const KINDS := ["hit", "step", "swoosh", "note", "sfx"]
const PALETTE := ["red", "green", "blue", "gold"]
const KIND_COLOR := {"hit": "red", "step": "green", "swoosh": "blue", "note": "gold", "sfx": "green"}
const NOTE_MAX := 2000   # characters kept of a marker's note


static func sorted(ms: Array) -> Array:
	var out := ms.duplicate(true)
	out.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	return out


## one marker, cleaned (a bad kind is a note, a missing name is "m<i+1>"; note and color only when set)
static func clean(d: Dictionary, i := 0) -> Dictionary:
	var k := String(d.get("kind", "note"))
	var out := {"t": maxf(0.0, float(d.get("t", 0.0))), "name": String(d.get("name", "m%d" % (i + 1))), "kind": k if k in KINDS else "note"}
	var note := String(d.get("note", ""))
	if note != "":
		out["note"] = note.left(NOTE_MAX)
	var c := String(d.get("color", ""))
	if c in PALETTE:
		out["color"] = c
	return out


## the Tok token a marker is drawn in: its own colour, else its kind's
static func token_of(mk: Dictionary) -> String:
	var c := String(mk.get("color", ""))
	if c in PALETTE:
		return "mk_" + c
	return "mk_" + String(KIND_COLOR.get(String(mk.get("kind", "note")), "gold"))


## the marker with its name, note and colour replaced (a blank name keeps the old one; a blank note removes it); a new dict
static func with(mk: Dictionary, name: String, note: String, color: String) -> Dictionary:
	var d := mk.duplicate(true)
	if name.strip_edges() != "":
		d["name"] = name.strip_edges()
	d.erase("note")
	if note != "":
		d["note"] = note
	d.erase("color")
	if color in PALETTE:
		d["color"] = color
	return clean(d)


## the file's list -> clean, sorted (anything not a dictionary with a t is dropped)
static func from_list(l) -> Array:
	var out := []
	if l is Array:
		for d in l:
			if d is Dictionary and d.has("t"):
				out.append(clean(d, out.size()))
	return sorted(out)


## the next free name "m<n>"
static func next_name(ms: Array) -> String:
	var n := ms.size() + 1
	var used := ms.map(func(x): return String(x["name"]))
	while ("m%d" % n) in used:
		n += 1
	return "m%d" % n


## adds one at t (the array stays sorted); -> the marker added
static func add(ms: Array, t: float, name := "", kind := "note") -> Dictionary:
	var mk := clean({"t": snappedf(t, 0.001), "name": name if name != "" else next_name(ms), "kind": kind})
	ms.append(mk)
	ms.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	return mk


## the time of a whole frame (ROADMAP 97: a dragged marker lands on frames): frame = round(t * fps)
static func frame_of(t: float, fps: int) -> int:
	return roundi(t * float(maxi(fps, 1)))


static func time_of_frame(f: int, fps: int) -> float:
	return snappedf(float(f) / float(maxi(fps, 1)), 1e-6)


## the index of the marker nearest to t within tol seconds, else -1
static func near(ms: Array, t: float, tol: float) -> int:
	var best := -1
	var bd := tol + 1e-9
	for i in ms.size():
		var d := absf(float(ms[i]["t"]) - t)
		if d <= bd:
			bd = d
			best = i
	return best


## the time of the first marker after t (by more than eps), else -1
static func next_t(ms: Array, t: float, eps := 1e-3) -> float:
	for x in ms:
		if float(x["t"]) > t + eps:
			return float(x["t"])
	return -1.0


static func prev_t(ms: Array, t: float, eps := 1e-3) -> float:
	for i in range(ms.size() - 1, -1, -1):
		if float(ms[i]["t"]) < t - eps:
			return float(ms[i]["t"])
	return -1.0


## RETIME: where a time t goes when the scene's timing changes from `old` to `new` (both Scene.times(): [start of move,
## arrival, end of hold] per card, same card count). Piecewise linear through those points, so a marker at a card's
## arrival stays at that card's arrival, and one inside a stretched move or hold is stretched with it; after the
## last point the end shifts.
static func remap_time(t: float, old: Array, new: Array) -> float:
	var xs := [0.0]
	var ys := [0.0]
	for i in old.size():
		for j in 3:
			var o := float(old[i][j])
			if o > xs[-1] + 1e-9:
				xs.append(o)
				ys.append(float(new[i][j]))
	if t <= 0.0 or xs.size() < 2:
		return t
	for k in range(1, xs.size()):
		if t <= xs[k] + 1e-9:
			var u: float = (t - float(xs[k - 1])) / (float(xs[k]) - float(xs[k - 1]))
			return ys[k - 1] + u * (ys[k] - ys[k - 1])
	return t + (ys[-1] - xs[-1])


## the list after a retime (a new array; the input is untouched)
static func remap(ms: Array, old: Array, new: Array) -> Array:
	if old.size() != new.size() or old.is_empty():
		return ms.duplicate(true)
	var out := ms.duplicate(true)
	for x in out:
		x["t"] = snappedf(remap_time(float(x["t"]), old, new), 0.001)
	return sorted(out)


## the game export's "events": t as a fraction of the length (4 decimals, like the table's keys)
static func events(ms: Array, length: float) -> Array:
	var out := []
	for x in ms:
		out.append({"t_frac": snappedf(clampf(float(x["t"]) / maxf(length, 1e-6), 0.0, 1.0), 0.0001), "name": x["name"], "kind": x["kind"]})
	return out


## the .glb's list: name, kind, t (seconds), frame, and note / color when the marker has them
static func glb_list(ms: Array, fps: int) -> Array:
	var out := []
	for x in ms:
		var d := {"name": String(x["name"]), "kind": String(x["kind"]), "t": snappedf(float(x["t"]), 1e-6), "frame": frame_of(float(x["t"]), fps)}
		if x.has("note"):
			d["note"] = String(x["note"])
		if x.has("color"):
			d["color"] = String(x["color"])
		out.append(d)
	return out


## THE GLB EXTRAS (ROADMAP 97): the markers as extras "poser_markers" on the file's first animation (glTF 2.0 lets
## every object carry extras). Rewrites the .glb's JSON chunk; the binary chunk is copied as it is. No markers, or a
## file with no animation, = the file untouched. OK or the error.
static func add_glb_extras(path: String, ms: Array, fps: int) -> Error:
	if ms.is_empty():
		return OK
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 20 or b.slice(0, 4).get_string_from_ascii() != "glTF":
		return ERR_FILE_CORRUPT
	var jlen := b.decode_u32(12)
	if b.slice(16, 20).get_string_from_ascii() != "JSON":
		return ERR_FILE_CORRUPT
	var doc: Variant = JSON.parse_string(b.slice(20, 20 + jlen).get_string_from_utf8())
	if not doc is Dictionary:
		return ERR_FILE_CORRUPT
	var anims: Array = (doc as Dictionary).get("animations", [])
	if anims.is_empty():
		return OK
	var ex: Dictionary = (anims[0] as Dictionary).get("extras", {})
	ex["poser_markers"] = glb_list(ms, fps)
	(anims[0] as Dictionary)["extras"] = ex
	var jb := JSON.stringify(doc, "", false).to_utf8_buffer()
	while jb.size() % 4 != 0:
		jb.append(0x20)   # the JSON chunk pads with spaces (glTF 2.0 section 3.6.1)
	var rest := b.slice(20 + jlen)
	var outb := PackedByteArray()
	outb.append_array("glTF".to_ascii_buffer())
	outb.append_array(_u32(2))
	outb.append_array(_u32(12 + 8 + jb.size() + rest.size()))
	outb.append_array(_u32(jb.size()))
	outb.append_array("JSON".to_ascii_buffer())
	outb.append_array(jb)
	outb.append_array(rest)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(outb)
	f.close()
	return OK


static func _u32(v: int) -> PackedByteArray:
	var a := PackedByteArray()
	a.resize(4)
	a.encode_u32(0, v)
	return a
