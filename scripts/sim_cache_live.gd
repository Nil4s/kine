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


## the md5 of the scene inputs sim object `name` reads
static func key_for(S: Scene, name: String) -> String:
	var a := [name, S.cards, S.part_keys, S.ik, S.clips, S.plants, S.drivers, S.secondary, S.cons, S.layer, S.layer_w, S.layers, S.breath,
		S.fitness, S.spline, S.natural, S.on_floor, S.floor_body, S.free_limits, S.pin, S.fps, S.moving_holds, S.stepped, S.loop, S.body,
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
	return "fresh" if key_for(S, name) == String(meta[name]["key"]) else "stale"


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


## the sims of scene S run on this thread: {"objs": {name: {"frames": Array, "fps": int}}, "cape": the cape dict or {}}
static func compute(S: Scene) -> Dictionary:
	var objs := {}
	var cape := {}
	if not S.cape.is_empty():
		var B := Body.new()
		B.load_files(SKEL, LIMS)
		B.fk()
		cape = Cloth.bake_scene(S.clone(), B)
		objs["cape"] = {"frames": cape["frames"], "fps": int(cape.get("fps", S.fps))}
	var names: Array = SoftBody.regions_of(S)
	if not names.is_empty():
		SoftBody.native_door()
		var B2 := Body.new()
		B2.load_files(SKEL, LIMS)
		B2.fk()
		var bk := SoftBody.bake_scene(S.clone(), B2, names, HZ, {"sag_frame": "body"})
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
		var file := "%s/%s_%s.ksim" % [dir, _safe(S.name if S.name != "" else "scene"), _safe(name)]
		if meta.has(name):
			_stash(name)
		_loaded.erase(name)
		if SimCache.write(file, o["frames"], int(o["fps"]), key):
			var fr: Array = o["frames"]
			meta[name] = {"file": file, "key": key, "verts": (fr[0] as PackedVector3Array).size(), "frames": fr.size(), "fps": int(o["fps"])}
			done.append(name)
	return done


## Free bake: every cache (or the named one) goes, the files too
func free_all() -> void:
	apply_meta({})


## the meta becomes `nm`; files that leave it are kept in the trash and deleted, files that come back are written from there
func apply_meta(nm: Dictionary) -> void:
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
