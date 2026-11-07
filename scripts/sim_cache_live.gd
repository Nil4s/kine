## sim_cache_live.gd - L35 SIM CACHE in the app: which sim objects have a point cache (scripts/sim_cache.gd), whether it is still true, and
## the frame to show.
##
## SIM OBJECTS: "cape" (the cloth, Cloth) and "soft:<region>" (one soft-body region's node displacements, SoftBody). One file each under
## `dir` (the session folder: user://session/simcache). "Bake sim" (Main._simc_bake) runs the sims on this thread, writes the files and
## records them in `meta`, all in one undo step; the timeline then asks frame_at() and gets the file's frame, never a re-simulation.
##
## STALE: meta[name]["key"] is the md5 of every scene input the sim reads (key_for). state() recomputes it from the scene as it is NOW,
## so any edit however it was made (a card, a part key, the body's proportions, an undo) is seen at once; a cache whose key no longer
## matches is "stale" and serves nothing (the live cape / live soft bake draws). The sim's own OUTPUT (S.cape, S.soft strength) is not in
## the key. An undo that restores the old content makes the same key again: fresh.
##
## UNDO: `meta` is part of the undo snapshot. The files follow meta (apply_meta): a file that leaves meta is kept in `trash` (bytes, by
## file + key) and deleted; one that returns is written back from there. So Free bake and its undo, and Bake sim and its undo / redo,
## are bit-exact. The cache belongs to the scene object it was baked on: another scene drops it.
class_name SimCacheLive
extends RefCounted

const SKEL := "res://data/skeleton.json"
const LIMS := "res://data/body_limits.json"
const HZ := 60.0

var dir := "user://session/simcache"
var meta := {}          # name -> {"file", "key", "verts", "frames", "fps"}
var reads := 0          # frames served from a file (tests read it)
var _loaded := {}       # name -> SimCache (opened and checked)
var _trash := {}        # "file|key" -> bytes
var _bound := 0         # instance id of the scene the meta belongs to
static var hashes := 0  # how many times a key was md5-hashed (tests count it)
var _kmemo := {}        # name -> key, valid for the current edit generation (edited() clears it)
var _kscene := 0        # the scene the memo belongs to


## L42: the scene was edited (an edit, an undo, a redo): the memoized keys are dropped. Between two edits a key is hashed once, not on every read.
func edited() -> void:
	_kmemo.clear()


func _key(S: Scene, name: String) -> String:
	var id := S.get_instance_id()
	if id != _kscene:
		_kmemo.clear()
		_kscene = id
	if _kmemo.has(name):
		return _kmemo[name]
	var k := key_for(S, name)
	_kmemo[name] = k
	return k


## the md5 of the scene inputs sim object `name` reads
static func key_for(S: Scene, name: String) -> String:
	hashes += 1
	var a := [name, S.cards, S.part_keys, S.ik, S.clips, S.plants, S.drivers, S.secondary, S.cons, S.layer, S.layer_w, S.layers, S.breath,
		S.fitness, S.spline, S.natural, S.on_floor, S.floor_body, S.free_limits, S.pin, S.fps, S.moving_holds, S.sway, S.sway_seed, S.stepped, S.loop, S.body,
		S.bones, S.spline_chains, S.props]
	if name == "cape":
		a.append(Cloth.self_collide)
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_MD5)
	hc.update(var_to_bytes(a))
	return hc.finish().hex_encode()


static func _safe(s: String) -> String:
	var out := ""
	for ch in s:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") else "_"
	return out


func file_of(name: String) -> String:
	return String((meta.get(name, {}) as Dictionary).get("file", ""))


func _bind(S: Scene) -> void:
	var id := S.get_instance_id()
	if _bound != id:
		if not meta.is_empty():
			apply_meta({})
		_bound = id


## "none" (no cache), "missing" (recorded but the file is gone or damaged), "stale" (the scene changed since), "fresh"
func state(S: Scene, name: String) -> String:
	if S == null or meta.is_empty():
		return "none"
	_bind(S)
	if not meta.has(name):
		return "none"
	if _load(name) == null:
		return "missing"
	return "fresh" if _key(S, name) == String(meta[name]["key"]) else "stale"


## POL1106b: the timeline badge. "cache: none" when nothing is baked, "cache: fresh" when every baked object is fresh, otherwise
## "cache: stale" (a stale object, or a recorded file that is gone: neither serves a frame, both need a new Bake sim).
func badge(S: Scene) -> String:
	if S == null or meta.is_empty():
		return "cache: none"
	var out := "fresh"
	for n in meta.keys():
		if state(S, n) != "fresh":
			out = "stale"
	return "cache: " + out


func _load(name: String) -> SimCache:
	if _loaded.has(name):
		return _loaded[name]
	var c := SimCache.open(file_of(name))
	if c != null and c.key != String(meta[name]["key"]):
		c = null
	if c != null:
		_loaded[name] = c
	return c


## the cached frame at time t, or an empty array when there is no fresh cache (the caller then draws the live sim)
func frame_at(S: Scene, name: String, t: float) -> PackedVector3Array:
	if state(S, name) != "fresh":
		return PackedVector3Array()
	var c := _load(name)
	reads += 1
	return c.frame(roundi(t * float(c.fps)))


## the progress and the cancel of a background bake (Cloth.simulate's ctl): the bar of the import panel reads VideoIQ.progress, its Cancel sets
## VideoIQ.cancel_flag. The cape's share of the bar is [lo, lo + span].
class Ctl:
	extends RefCounted
	var lo := 0.0
	var span := 1.0

	func report(f: float) -> void:
		VideoIQ.progress = lo + span * f

	func cancelled() -> bool:
		return bool(VideoIQ.cancel_flag[0])


## the sims of scene S run on this thread: {"objs": {name: {"frames": Array, "fps": int}}, "cape": the cape dict or {}}.
## bg (the background bake): progress is reported and the cancel flag is honoured ({} returned when cancelled); the numbers are the same.
static func compute(S: Scene, bg := false) -> Dictionary:
	var objs := {}
	var cape := {}
	var soft_names: Array = SoftBody.regions_of(S)
	if not S.cape.is_empty():
		var B := Body.new()
		B.load_files(SKEL, LIMS)
		B.fk()
		var ctl: Ctl = null
		if bg:
			ctl = Ctl.new()
			ctl.span = 0.5 if not soft_names.is_empty() else 1.0
		cape = Cloth.bake_scene(S.clone(), B, -1, ctl)
		if cape.is_empty():
			return {}
		objs["cape"] = {"frames": cape["frames"], "fps": int(cape.get("fps", S.fps))}
	var names: Array = SoftBody.regions_of(S)
	if not names.is_empty():
		SoftBody.native_door()
		var B2 := Body.new()
		B2.load_files(SKEL, LIMS)
		B2.fk()
		var so := {"sag_frame": "body"}
		if bg:
			VideoIQ.progress = 0.5 if not S.cape.is_empty() else 0.0
			so["cancel"] = VideoIQ.cancel_flag
		var bk := SoftBody.bake_scene(S.clone(), B2, names, HZ, so)
		if bk.is_empty():
			return {}
		for n in names:
			objs["soft:" + String(n)] = {"frames": bk["regions"][n]["disp"], "fps": int(HZ)}
	return {"objs": objs, "cape": cape}


## writes one file per object and records it. Called inside the undo step.
func commit(S: Scene, objs: Dictionary) -> Array:
	_bind(S)
	var done := []
	for name in objs:
		var o: Dictionary = objs[name]
		var key := key_for(S, name)
		var file := file_for(dir, S.name, name)
		if meta.has(name):
			_stash(name)
		_loaded.erase(name)
		if SimCache.write(file, o["frames"], int(o["fps"]), key):
			var fr: Array = o["frames"]
			meta[name] = {"file": file, "key": key, "verts": (fr[0] as PackedVector3Array).size(), "frames": fr.size(), "fps": int(o["fps"])}
			done.append(name)
	return done


static func file_for(d: String, scene_name: String, name: String) -> String:
	return "%s/%s_%s.ksim" % [d, _safe(scene_name if scene_name != "" else "scene"), _safe(name)]


## L42, ON THE WORKER: one file per object written next to its final place as <file>.pending (SimCache.write itself goes through a temp file and a
## rename). Nothing is recorded and no final file is touched: {} when the bake was cancelled or a write failed (what was written is removed).
static func write_pending(d: String, scene_name: String, objs: Dictionary, keys: Dictionary) -> Dictionary:
	var out := {}
	for name in objs:
		var o: Dictionary = objs[name]
		var final := file_for(d, scene_name, name)
		var ok_w := not bool(VideoIQ.cancel_flag[0]) and SimCache.write(final + ".pending", o["frames"], int(o["fps"]), String(keys[name]))
		if not ok_w:
			clear_pending(d, scene_name, objs.keys())
			return {}
		var fr: Array = o["frames"]
		out[name] = {"file": final, "key": String(keys[name]), "verts": (fr[0] as PackedVector3Array).size(), "frames": fr.size(), "fps": int(o["fps"])}
	return out


## removes any <file>.pending (and its temp) of these objects
static func clear_pending(d: String, scene_name: String, names: Array) -> void:
	for name in names:
		var p := file_for(d, scene_name, name) + ".pending"
		for q in [p, p + ".tmp"]:
			if FileAccess.file_exists(q):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(q))


## on the main thread, inside the undo step: the pending files become the cache files (a rename each) and are recorded
func commit_pending(S: Scene, pend: Dictionary) -> Array:
	_bind(S)
	var done := []
	for name in pend:
		var e: Dictionary = pend[name]
		var file := String(e["file"])
		if meta.has(name):
			_stash(name)
		_loaded.erase(name)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(file + ".pending"), ProjectSettings.globalize_path(file)) == OK:
			meta[name] = e.duplicate()
			done.append(name)
	_kmemo.clear()
	return done


## Free bake: every cache (or the named one) goes, the files too
func free_all() -> void:
	apply_meta({})


## the meta becomes `nm`; files that leave it are kept in the trash and deleted, files that come back are written from there
func apply_meta(nm: Dictionary) -> void:
	_kmemo.clear()
	for n in meta.keys():
		if not nm.has(n) or String(nm[n]["key"]) != String(meta[n]["key"]):
			_stash(n)
		if not nm.has(n):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(String(meta[n]["file"])))
	meta = nm.duplicate(true)
	_loaded.clear()
	for n in meta:
		var f := String(meta[n]["file"])
		var c := SimCache.open(f, false)
		if c == null or c.key != String(meta[n]["key"]):
			var tk := f + "|" + String(meta[n]["key"])
			if _trash.has(tk):
				var fa := FileAccess.open(f, FileAccess.WRITE)
				if fa != null:
					fa.store_buffer(_trash[tk])
					fa.close()


func _stash(n: String) -> void:
	var f := String(meta[n]["file"])
	if not FileAccess.file_exists(f):
		return
	var b := FileAccess.get_file_as_bytes(f)
	var tk := f + "|" + String(meta[n]["key"])
	_trash[tk] = b
