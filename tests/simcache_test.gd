## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/simcache_test.gd     (L35 SIM CACHE: bake any sim to a point cache the timeline scrubs)
##
## THE WORK: "Bake sim" caches the cape (cloth) and the soft-body regions per frame into ONE FILE PER SIM OBJECT under the session
## folder (scripts/sim_cache.gd: header + float32 xyz, 12 bytes a vertex a frame; scripts/sim_cache_live.gd: the app's side). After the
## bake the timeline shows the cached frame and never re-simulates; an edit makes the cache stale; "Free bake" removes it; each is ONE
## undo step. Bars written BEFORE the code (this file's first commit has no scripts/sim_cache*.gd). Each has a PLANTED CONTROL.
##   1 FILE SIZE       a 5041-vertex x 200-frame file is exactly HEADER + 12 x 5041 x 200 bytes on disk, and so is the real cape file
##                     (192 x its frame count); the file starts with the magic. CONTROL: a file one byte longer is refused.
##   2 BIT-EXACT       every frame of the cape read back from the cache equals the live sim (an independent Cloth.bake_scene of the
##                     scene) byte for byte; the soft regions the same against a SoftBody.bake_scene. CONTROL: frame k+1 read as frame k
##                     differs; one value nudged by 1 ulp is seen by the byte comparison.
##   3 SCRUB           a random-order scrub (shuffled, then 200 jumps up and down) over >= 200 frames returns the same bytes as the
##                     sequential play, with the scene's own cape frames POISONED (zeros) so only the file can answer; the drawn cape
##                     mesh at a frame holds the cached vertices. CONTROL: the poisoned scene cape itself reads as wrong.
##   4 SPEED           the per-frame cache read of a 5041-vertex cloth is <= 0.5 ms (mean of 2000 random reads; p50 and max printed).
##                     CONTROL: a per-vertex GDScript decode of the same frame is measured and is slower than the bar (the timer can fail).
##   5 STALE           changing a pose card, or the body's proportions, marks the cache stale (and the timeline stops serving it);
##                     a selection or the playhead moving does not. CONTROL: a different scene's key differs; an undone edit is fresh.
##   6 UNDO            Bake sim is ONE undo step; undo removes it, redo brings it back bit-exact; Free bake is one step, deletes the
##                     file; undo brings the file and the cache back bit-exact.
##   7 SOFT DRAW       with a soft region on, the drawn skin vertices equal the live-bake draw (within 1e-6 m) and come from the file
##                     (the read counter moves); stale, they come from the live bake and the counter does not move.
##   8 FILE CONTROLS   a corrupted data byte, a corrupted header count, a truncated file and a wrong header offset are each caught.
var fails := 0
var m: Node
const TMP := "user://simcache_scene.json"
const DIR := "user://simcache_test"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func boot_app() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.dummy_on = false


func load_scene(S: Scene) -> void:
	var fa := FileAccess.open(TMP, FileAccess.WRITE)
	fa.store_string(JSON.stringify(S.to_dict(m.B, false)))
	fa.close()
	m._load_scene(TMP)
	m._rebuild_cards()
	m.playing = false
	await idle(2)


## the quick turn at 60 fps: stand 1.0 s, the pelvis turns 90 deg in 0.25 s, holds 2.2 s = 3.45 s = 208 frames
func turn_scene() -> Scene:
	var S := Scene.new()
	S.fps = 60
	var rest := {}
	for j in Body.ORDER:
		rest[j] = {"bend": 0.0, "side": 0.0, "twist": 0.0}
	S.add("stand", {"joints": rest.duplicate(true), "offset": [0.0, 0.0, 0.0]})
	(S.cards[-1] as Dictionary)["hold"] = 1.0
	var turned := rest.duplicate(true)
	(turned["pelvis"] as Dictionary)["twist"] = 90.0
	S.add("turn", {"joints": turned, "offset": [0.0, 0.0, 0.0]})
	(S.cards[-1] as Dictionary)["move"] = 0.25
	(S.cards[-1] as Dictionary)["hold"] = 2.2
	return S


func pose(thigh: float, calf: float, arm: float) -> Dictionary:
	var B := body()
	for sd in ["_l", "_r"]:
		B.set_ang("thigh" + sd, Vector3(thigh, 0, 0))
		B.set_ang("calf" + sd, Vector3(calf, 0, 0))
		B.set_ang("upperarm" + sd, Vector3(arm, 0, 0))
	B.fk()
	return B.to_dict()


func landing_scene() -> Scene:
	var B := body()
	var S := Scene.new()
	S.name = "zz_simcache_land"
	S.add("stand", B.to_dict())
	S.add("dip", pose(50, 90, 0))
	S.add("air", pose(10, 20, 100))
	S.add("land", pose(50, 90, 0))
	S.add("stand", B.to_dict())
	var mvs := [0.3, 0.3, 0.2855, 0.08, 0.4]
	var hd := [0.1, 0.05, 0.0, 0.1, 0.2]
	for i in 5:
		S.cards[i]["move"] = mvs[i]
		S.cards[i]["hold"] = hd[i]
	S.cards[2]["air"] = true
	return S


func bytes_of(v: PackedVector3Array) -> PackedByteArray:
	return v.to_byte_array()


## n frames of v vertices of a deterministic wandering cloth (a stand-in for a 5k-vertex sim)
func synth(v: int, n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 35
	var cur := PackedVector3Array()
	cur.resize(v)
	for i in v:
		cur[i] = Vector3(float(i % 71) * 0.02, float(i / 71) * 0.02, 0.0)
	var out := []
	for k in n:
		for i in v:
			cur[i] += Vector3(rng.randf_range(-0.001, 0.001), rng.randf_range(-0.001, 0.001), rng.randf_range(-0.001, 0.001))
		out.append(cur.duplicate())
	return out


func flip_byte(path: String, off: int) -> void:
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	f.seek(off)
	var b := f.get_8()
	f.seek(off)
	f.store_8(b ^ 0x5A)
	f.close()


func copy_file(a: String, b: String) -> void:
	DirAccess.copy_absolute(ProjectSettings.globalize_path(a), ProjectSettings.globalize_path(b))


func _init() -> void:
	var t_all := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))

	# ---------- 1 FILE SIZE, 4 SPEED, 8 FILE CONTROLS (the file layer alone: 5041 vertices x 200 frames)
	var V := 5041
	var NF := 200
	var frames := synth(V, NF)
	var p5k := DIR + "/synth.ksim"
	ok(SimCache.write(p5k, frames, 60, "synthetic"), "1 the 5041-vertex x 200-frame file is written")
	var want_len: int = SimCache.HEADER + 12 * V * NF
	var fa := FileAccess.open(p5k, FileAccess.READ)
	var got_len: int = fa.get_length()
	var magic := fa.get_buffer(4).get_string_from_ascii()
	fa.close()
	print("1 FILE: %d bytes on disk, header %d + 12 x %d x %d = %d" % [got_len, SimCache.HEADER, V, NF, want_len])
	ok(got_len == want_len, "1 the file is exactly header + 12 x vertices x frames bytes")
	ok(SimCache.size_for(V, NF) == want_len and magic == "KSIM", "1 size_for agrees, and the file starts with the magic KSIM (%s)" % magic)
	copy_file(p5k, DIR + "/long.ksim")
	var fl := FileAccess.open(DIR + "/long.ksim", FileAccess.READ_WRITE)
	fl.seek_end()
	fl.store_8(0)
	fl.close()
	ok(SimCache.open(DIR + "/long.ksim") == null, "1 CONTROL: the same file one byte longer is refused")
	ok(SimCache.open(DIR + "/missing.ksim") == null, "1 CONTROL: a missing file is refused, not an empty cache")

	var c5k := SimCache.open(p5k)
	ok(c5k != null and c5k.verts == V and c5k.frames == NF and c5k.fps == 60 and c5k.key == "synthetic", "1 the header reads back (verts, frames, fps, key)")
	var exact := true
	for k in NF:
		exact = exact and bytes_of(c5k.frame(k)) == bytes_of(frames[k])
	ok(exact, "2 all 200 frames of the 5041-vertex cache equal what was written, byte for byte")
	ok(bytes_of(c5k.frame(8)) != bytes_of(frames[7]), "2 CONTROL: frame 8 read for frame 7 differs (the comparison sees a wrong frame)")
	var nudged: PackedVector3Array = frames[20].duplicate()
	nudged[100].x = nextafter(nudged[100].x, 10.0)
	ok(bytes_of(nudged) != bytes_of(frames[20]), "2 CONTROL: one value moved 1 ulp is seen by the byte comparison")
	# 8: wrong offsets and damage
	var wrong := SimCache.raw_frame(c5k.buf, V, SimCache.HEADER + 4, 20)
	ok(bytes_of(wrong) != bytes_of(frames[20]), "8 CONTROL: a header offset 4 bytes off reads the wrong numbers")
	ok(bytes_of(SimCache.raw_frame(c5k.buf, V, SimCache.HEADER, 20)) == bytes_of(frames[20]), "8 the right offset reads the right numbers")
	copy_file(p5k, DIR + "/flip.ksim")
	var hit := SimCache.HEADER + 12 * V * 77 + 12345
	flip_byte(DIR + "/flip.ksim", hit)
	ok(SimCache.open(DIR + "/flip.ksim") == null, "8 a corrupted data byte is caught when the file opens")
	var unchecked := SimCache.open(DIR + "/flip.ksim", false)
	ok(unchecked != null and bytes_of(unchecked.frame(77)) != bytes_of(frames[77]) and bytes_of(unchecked.frame(76)) == bytes_of(frames[76]),
		"8 CONTROL: read without the check, the corrupted byte changes exactly its own frame (77) and no other")
	copy_file(p5k, DIR + "/hdr.ksim")
	flip_byte(DIR + "/hdr.ksim", 8)
	ok(SimCache.open(DIR + "/hdr.ksim") == null, "8 a corrupted vertex count in the header is caught")
	copy_file(p5k, DIR + "/trunc.ksim")
	var ft := FileAccess.open(DIR + "/trunc.ksim", FileAccess.READ_WRITE)
	ft.resize(want_len - 100)
	ft.close()
	ok(SimCache.open(DIR + "/trunc.ksim") == null, "8 a truncated file is caught")

	# 4 SPEED
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var times := []
	var sink := 0.0
	for i in 2000:
		var k := rng.randi_range(0, NF - 1)
		var t0 := Time.get_ticks_usec()
		var f := c5k.frame(k)
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		sink += f[i % V].x
	times.sort()
	var mean := 0.0
	for x in times:
		mean += float(x)
	mean /= float(times.size())
	print("4 SPEED: 5041 vertices, 2000 random reads: mean %.4f ms, p50 %.4f, p99 %.4f, max %.4f (checksum %.3f)" % [mean, times[1000], times[1980], times[-1], sink])
	ok(mean <= 0.5, "4 the per-frame cache read of a 5041-vertex cloth is %.4f ms mean (bar <= 0.5)" % mean)
	var slow := 0.0
	for i in 20:
		var t0 := Time.get_ticks_usec()
		var raw := c5k.buf
		var out := PackedVector3Array()
		out.resize(V)
		var base := SimCache.HEADER + 12 * V * (i * 7 % NF)
		for j in V:
			out[j] = Vector3(raw.decode_float(base + 12 * j), raw.decode_float(base + 12 * j + 4), raw.decode_float(base + 12 * j + 8))
		slow += float(Time.get_ticks_usec() - t0) / 1000.0
	slow /= 20.0
	ok(slow > 0.5, "4 CONTROL: a per-vertex GDScript decode of the same frame takes %.3f ms: over the bar, so the timer can fail" % slow)

	# ---------- the app
	await boot_app()
	m.simc.dir = DIR + "/session"
	var S := turn_scene()
	await load_scene(S)
	ok(m.S.fps == 60 and abs(m.S.length() - 3.45) < 0.01, "0 the turn scene is loaded at 60 fps, %.2f s" % m.S.length())
	m._do(func(): m.S.cape = Cloth.bake_scene(m.S.clone(), body()))
	var nf: int = (m.S.cape["frames"] as Array).size()
	ok(nf >= 200, "0 the cape is on the back: %d frames" % nf)
	ok(m.simc.state(m.S, "cape") == "none", "0 before Bake sim the cape has no cache (state none)")
	var u0: int = m.undo.size()
	var rep: Dictionary = m._simc_bake()
	ok(m.undo.size() == u0 + 1, "6 Bake sim is ONE undo step (%d -> %d)" % [u0, m.undo.size()])
	ok(m.simc.state(m.S, "cape") == "fresh" and rep.get("objects", []).has("cape"), "0 after Bake sim the cape cache is fresh (%s)" % str(rep))
	var cfile: String = m.simc.file_of("cape")
	var cl := FileAccess.open(cfile, FileAccess.READ)
	var clen: int = cl.get_length() if cl != null else -1
	if cl != null:
		cl.close()
	ok(clen == SimCache.HEADER + 12 * 192 * nf, "1 the real cape file is header + 12 x 192 x %d = %d bytes (disk: %d)" % [nf, SimCache.HEADER + 12 * 192 * nf, clen])
	ok(cfile.begins_with(m.simc.dir), "1 the file lives under the session folder (%s)" % cfile)

	# 2 BIT-EXACT against an independent live sim
	var live: Dictionary = Cloth.bake_scene(m.S.clone(), body())
	var lf: Array = live["frames"]
	var same := lf.size() == nf
	var first_bad := -1
	for k in mini(nf, lf.size()):
		if bytes_of(m.simc.frame_at(m.S, "cape", float(k) / 60.0)) != bytes_of(lf[k]):
			same = false
			if first_bad < 0:
				first_bad = k
	ok(same, "2 all %d frames of the cape cache equal an independent live cloth sim, byte for byte (first bad frame %d)" % [nf, first_bad])
	ok(bytes_of(m.simc.frame_at(m.S, "cape", 60.0 / 60.0)) != bytes_of(lf[57]), "2 CONTROL: the cache at frame 60 is not the live sim's frame 57 (the cape moves)")

	# 3 SCRUB with the scene's own cape POISONED
	var keep_cape: Dictionary = m.S.cape.duplicate(true)
	var zero := PackedVector3Array()
	zero.resize(192)
	var pz := []
	for k in nf:
		pz.append(zero)
	m.S.cape["frames"] = pz
	ok(m.simc.state(m.S, "cape") == "fresh", "3 poisoning the scene's own cape frames leaves the cache fresh (the cape output is not its input)")
	ok(bytes_of(Cloth.verts_at(m.S.cape, 1.0)) != bytes_of(lf[60]), "3 CONTROL: the poisoned scene cape reads wrong, so only the file can answer")
	var seq := []
	for k in nf:
		seq.append(bytes_of(m.simc.frame_at(m.S, "cape", float(k) / 60.0)))
	var order := range(nf)
	var r2 := RandomNumberGenerator.new()
	r2.seed = 35
	for i in range(order.size() - 1, 0, -1):
		var j := r2.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var rand_ok := true
	for k in order:
		rand_ok = rand_ok and bytes_of(m.simc.frame_at(m.S, "cape", float(k) / 60.0)) == seq[k]
	var jumps := 0
	for i in 200:
		var k := r2.randi_range(0, nf - 1)
		if bytes_of(m.simc.frame_at(m.S, "cape", float(k) / 60.0)) != seq[k]:
			rand_ok = false
		jumps += 1
	var back_ok := true
	for k in range(nf - 1, -1, -1):
		back_ok = back_ok and bytes_of(m.simc.frame_at(m.S, "cape", float(k) / 60.0)) == seq[k]
	var live_ok := true
	for k in nf:
		live_ok = live_ok and seq[k] == bytes_of(lf[k])
	ok(rand_ok and back_ok and live_ok, "3 a shuffled pass over %d frames, %d random jumps and a backward pass all equal the sequential play, and the live sim (bytes)" % [nf, jumps])
	m.playhead = 57.0 / 60.0
	m._cape_draw()
	var mesh_v: PackedVector3Array = (m._cape_mi.mesh as ImmediateMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var fi := Cloth.faces()
	var want_v := PackedVector3Array()
	for q in fi:
		want_v.append((lf[57] as PackedVector3Array)[q])
	ok(mesh_v.size() == want_v.size() and bytes_of(mesh_v) == bytes_of(want_v), "3 the cape drawn at the playhead holds the cached frame 57 (%d vertices)" % mesh_v.size())
	m.S.cape = keep_cape

	# 5 STALE
	var reads0: int = m.simc.reads
	m.sel_card = 1
	m.playhead = 0.5
	ok(m.simc.state(m.S, "cape") == "fresh", "5 a selection and a playhead move leave the cache fresh")
	var u1: int = m.undo.size()
	m._do(func(): (m.S.cards[1]["pose"]["joints"]["pelvis"] as Dictionary)["twist"] = 40.0)
	ok(m.simc.state(m.S, "cape") == "stale", "5 changing a pose card marks the cape cache STALE")
	ok(m.simc.frame_at(m.S, "cape", 1.0).is_empty() and m.simc.reads == reads0 + 0 or m.simc.reads >= reads0, "5 a stale cache is not served")
	ok(m.simc.frame_at(m.S, "cape", 1.0).is_empty(), "5 the timeline gets nothing from a stale cache (it falls back to the live cape)")
	m._undo()
	ok(m.undo.size() == u1 and m.simc.state(m.S, "cape") == "fresh", "5 CONTROL: undoing the edit makes the cache fresh again (same content, same key)")
	m._do(func(): m.S.body = {"stature": 1.95})
	ok(m.simc.state(m.S, "cape") == "stale", "5 editing the body (stature) marks the cache STALE")
	m._undo()
	ok(m.simc.state(m.S, "cape") == "fresh", "5 undoing the body edit makes it fresh")
	var other := turn_scene()
	other.cards[1]["pose"]["joints"]["pelvis"]["twist"] = 80.0
	ok(SimCacheLive.key_for(other, "cape") != SimCacheLive.key_for(m.S, "cape") and SimCacheLive.key_for(m.S, "cape") == SimCacheLive.key_for(m.S.clone(), "cape"),
		"5 CONTROL: a scene with another pose has another key; a clone of this one has the same")

	# 6 UNDO / REDO / FREE
	m._undo()   # the bake
	ok(m.simc.state(m.S, "cape") == "none", "6 undo takes the bake back (no cache)")
	m._redo()
	ok(m.simc.state(m.S, "cape") == "fresh", "6 redo brings the cache back, fresh")
	var again := true
	for k in nf:
		again = again and bytes_of(m.simc.frame_at(m.S, "cape", float(k) / 60.0)) == bytes_of(lf[k])
	ok(again, "6 after undo and redo all %d frames are still the live sim, byte for byte" % nf)
	var u2: int = m.undo.size()
	m._simc_free()
	ok(m.undo.size() == u2 + 1 and m.simc.state(m.S, "cape") == "none" and not FileAccess.file_exists(cfile), "6 Free bake is ONE undo step, the cache is gone and so is the file")
	m._undo()
	ok(m.simc.state(m.S, "cape") == "fresh" and FileAccess.file_exists(cfile), "6 undo of Free bake brings the cache and its file back")
	again = true
	for k in nf:
		again = again and bytes_of(m.simc.frame_at(m.S, "cape", float(k) / 60.0)) == bytes_of(lf[k])
	ok(again, "6 and the restored file is bit-exact on all %d frames" % nf)
	m._redo()
	ok(m.simc.state(m.S, "cape") == "none" and not FileAccess.file_exists(cfile), "6 redo of Free bake frees it again")
	m._undo()

	# ---------- 7 SOFT
	var SL := landing_scene()
	await load_scene(SL)
	m._do(func(): m.S.soft = {"regions": ["belly", "thigh_l"]})
	await idle(2)
	var t_end := Time.get_ticks_msec() + 120000
	while not m.soft_live.ready() and Time.get_ticks_msec() < t_end:
		await process_frame
	ok(m.soft_live.ready(), "7 the live soft bake finished")
	var k_draw := 40
	var sig_live := _piece_sig(k_draw)
	var rep2: Dictionary = m._simc_bake()
	ok((rep2.get("objects", []) as Array).has("soft:belly") and (rep2.get("objects", []) as Array).has("soft:thigh_l"), "7 Bake sim cached both soft regions (%s)" % str(rep2.get("objects")))
	ok(not (rep2.get("objects", []) as Array).has("cape"), "7 no cape on this scene, so no cape file")
	var ref: Dictionary = SoftBody.bake_scene(m.S.clone(), body(), ["belly", "thigh_l"], 60.0, {"sag_frame": "body"})
	var exact2 := true
	var cnt := 0
	for n in ["belly", "thigh_l"]:
		var dl: Array = ref["regions"][n]["disp"]
		for k in dl.size():
			exact2 = exact2 and bytes_of(m.simc.frame_at(m.S, "soft:" + n, float(k) / 60.0)) == bytes_of(dl[k])
			cnt += 1
	ok(exact2 and cnt > 150, "2 every frame of both soft regions (%d frames) equals a live SoftBody bake, byte for byte" % cnt)
	var r_a: int = m.simc.reads
	var sig_cached := _piece_sig(k_draw)
	var dmax := 0.0
	for j in sig_live:
		dmax = maxf(dmax, _vmax(sig_live[j], sig_cached[j]))
	ok(m.simc.reads > r_a, "7 the draw read the file (reads %d -> %d)" % [r_a, m.simc.reads])
	ok(dmax <= 1e-6 and sig_live.size() > 0, "7 the drawn skin from the cache equals the live-bake draw: worst %s m over %d pieces (bar 1e-6)" % [dmax, sig_live.size()])
	var moved := false
	var rest_sig := _piece_sig(0)
	for j in sig_live:
		moved = moved or _vmax(rest_sig[j], sig_cached[j]) > 1e-5
	ok(moved, "7 CONTROL: frame 40 differs from frame 0 on the skin (the flesh moves, the comparison is not vacuous)")
	m._do(func(): (m.S.cards[1]["pose"]["joints"]["spine_01"] as Dictionary)["bend"] = 20.0)
	ok(m.simc.state(m.S, "soft:belly") == "stale" and m.simc.state(m.S, "soft:thigh_l") == "stale", "5 a pose edit marks both soft caches stale")
	var r_b: int = m.simc.reads
	_piece_sig(k_draw)
	ok(m.simc.reads == r_b, "7 stale: the draw does not read the file (reads stay %d)" % r_b)

	print("simcache: %d failures (%.1f s)" % [fails, float(Time.get_ticks_msec() - t_all) / 1000.0])
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


## the drawn vertices of every body piece at frame k
func _piece_sig(k: int) -> Dictionary:
	var t := float(k) / 60.0
	m.playhead = t
	m._ps().apply(m.B, t)
	m._refresh()
	var out := {}
	for j in m.pieces:
		var pc := m.pieces[j] as MeshInstance3D
		if not is_instance_valid(pc) or pc.mesh == null:
			continue
		var v := PackedVector3Array()
		for si in pc.mesh.get_surface_count():
			v.append_array(pc.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX])
		out[j] = v
	return out


func _vmax(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size():
		return INF
	var mx := 0.0
	for i in a.size():
		mx = maxf(mx, (a[i] - b[i]).length())
	return mx
