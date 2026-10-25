## godot --headless --path . -s tests/body_cache_test.gd     (the body cache: scripts/body_cache.gd)
## Bars, stated before measuring:
##   1 the cached build is byte-identical to the computed one: the pieces' surface arrays (vertices, normals, bones,
##     weights, indices) and the corrective's weights and girth shapes, cold (computed, cache written) and warm (loaded)
##   2 a cold run misses (computes and writes) and a warm run hits every entry and computes nothing
##   3 a corrupt cache file falls back to compute: the result is still identical, and the corrupt file is counted
##   4 the cache lives in its own user:// test folder, which this test empties and removes at the end
##   5 the warm build is faster than the cold build (printed; not a bar, the speed is read by the boot bench)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## every surface of every piece, and the corrective's caches, as bytes: the comparison is byte equality
func fingerprint(pieces: Dictionary, corr: Corrective) -> String:
	var all := []
	var keys := pieces.keys()
	keys.sort()
	for j in keys:
		var mi := pieces[j] as MeshInstance3D
		var surfs := []
		for si in mi.mesh.get_surface_count():
			surfs.append(mi.mesh.surface_get_arrays(si))
		all.append([j, surfs])
	all.append(var_to_bytes(corr._wcache))
	all.append(var_to_bytes(corr._gcache))
	return BodyCache.md5(var_to_bytes(all))


## one body build from the mannequin file: split, then the corrective's weights (the same calls as main's _body)
func build() -> Array:
	var t0 := Time.get_ticks_usec()
	var mq := Overlays.mannequin(root, StandardMaterial3D.new())
	var pieces := Overlays.split_parts(mq[0], mq[1], mq[2])
	var corr := Corrective.new()
	corr.attach(pieces.values(), mq[1])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var f := fingerprint(pieces, corr)
	mq[0].queue_free()
	return [f, ms]


func stats_copy() -> Dictionary:
	return BodyCache.stats.duplicate()


func clear_dir(d: String) -> void:
	var da := DirAccess.open(d)
	if da == null:
		return
	for f in da.get_files():
		DirAccess.remove_absolute(d.path_join(f))


func _init() -> void:
	BodyCache.enabled = false
	var ref: String = build()[0]

	BodyCache.enabled = true
	BodyCache.dir = "user://cache_test_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BodyCache.dir))
	clear_dir(BodyCache.dir)

	BodyCache.stats = {"hit": 0, "miss": 0, "bad": 0}
	var cold := build()
	var s1 := stats_copy()
	ok(cold[0] == ref and s1["miss"] > 0 and s1["hit"] == 0, "1/2 cold build byte-identical to the computed one, and it misses (%s)" % str(s1))
	var n_files := DirAccess.get_files_at(BodyCache.dir).size()
	ok(n_files > 0, "1/4 the cache folder holds %d files" % n_files)

	BodyCache.stats = {"hit": 0, "miss": 0, "bad": 0}
	var warm := build()
	var s2 := stats_copy()
	ok(warm[0] == ref and s2["hit"] > 0 and s2["miss"] == 0 and s2["bad"] == 0, "1/2 warm build byte-identical, every entry hits, nothing computed (%s)" % str(s2))
	print("     cold %.0f ms, warm %.0f ms" % [cold[1], warm[1]])

	# 3: corrupt every cache file in place
	var d := BodyCache.dir
	for f in DirAccess.get_files_at(d):
		var w := FileAccess.open(d.path_join(f), FileAccess.WRITE)
		w.store_buffer(PackedByteArray([1, 2, 3, 4, 5]))
		w.close()
	BodyCache.stats = {"hit": 0, "miss": 0, "bad": 0}
	var bad := build()
	var s3 := stats_copy()
	ok(bad[0] == ref and s3["bad"] > 0 and s3["miss"] > 0 and s3["hit"] == 0, "3 corrupt cache files: identical result by computing (%s)" % str(s3))

	clear_dir(d)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(d))
	ok(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(d)), "4 the test folder is removed")

	print("body_cache_test: %d failed" % fails)
	quit(fails)
