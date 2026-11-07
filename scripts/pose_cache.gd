class_name PoseCache
extends RefCounted
## POSE CACHE (ROADMAP 20, real-time playback). Caches the parts of Scene.apply that depend on nothing but the scene's
## own content, so a playing frame does not redo them. Output is bit-identical to the uncached path (tests/play_perf_test.gd).
##
## WHAT IS CACHED: the foot-plant references (FootPlant.refs). Each live plant's reference is the sole as the scene
## plays at the plant's t0: a full Scene.apply at t0 on every frame, though t0 never changes while the scene does not.
## That was ~6 ms of the ~17 ms one apply costs on a heavy scene (measured with tests/play_perf_test.gd).
##
## WHY NOT A POSE CACHE KEYED ON TIME: during forward playback the playhead moves by dt every frame, so an exact-time key
## never repeats within a pass (a hit needs the same float again: a second loop only). Quantising the key to the frame
## would make the displayed pose step at the scene's fps, which changes what plays; that is not done here.
##
## INVALIDATION (never stale, no hash):
##   The key is a DEEP COPY of every input the reference apply reads before it writes it (the scene's content, the
##   proportions, the weapon's kind and length; listed in _key). On each use the current inputs are built and compared with == (Godot compares arrays
##   and dictionaries by value, Vector3 and Quaternion exactly). A change of any input, however it was made (an undo, a
##   drag, a live slider, a file load, an in-place write into a card), changes the key, so the next frame recomputes.
##   A deep copy means an in-place write into the live arrays cannot alter the stored key too.
##   Not cached (always recomputed): a scene with a constraint whose target is another actor (its reference reads that
##   actor's scene, which is not in the key), or one whose target is the weapon (it reads the bat's last pose). Scenes
##   with no plants never reach this code.
##   The cache lives on the Scene instance (set_meta), so it dies with the scene and a clone starts empty.
##
## NOT IN THE KEY, ON PURPOSE: the bat's pose fields (wep_pos, wep_rot, wep_lpos, wep_lrot) and the second weapon's
## local fields. Scene.put writes them from the card sample at the frame's time, before anything reads them, so they are
## outputs of apply, not inputs; putting them in the key would make it change every frame of a held-bat playback.
##
## ASSUMPTION TESTED, NOT PROVEN: skipping the reference apply leaves the body in a different state than the apply did
## (the apply poses the body at t0; the caller poses it at t afterwards, as Scene.apply's own comment says). The next apply
## must not read that state. tests/play_perf_test.gd checks it on 300 frames of a two-fighter playback with a held bat,
## an edit and a plant edit: cached and uncached body states compare bit for bit, every frame, both fighters.

static var enabled := true   # the test switches it off to take the uncached reference
static var hits := 0         # counters for the test's report
static var misses := 0


## the reference of plant i at its t0: {"P", "G", "Gb", "pole"}, the same values FootPlant.refs read by applying the scene
static func plant_ref(S: Scene, B: Body, i: int) -> Dictionary:
	var p: Dictionary = S.plants[i]
	var foot := String(p["foot"])
	var ball := "ball" + foot.right(2)
	# R2 MEMO (inside a scope that holds the cards fixed, Scene.free_memo): the reference is read at ref_time(p) with the plants off,
	# so it depends on the scene's content and that time only, not on the plant list (which the scans change every step)
	if S.free_memo != null and S.baker == null and _plain_cons(S):
		var mk := [FootPlant.ref_time(p), foot]
		if S.free_memo.has(mk):
			return S.free_memo[mk]
		var rr := _compute(S, B, i, foot, ball, p)
		S.free_memo[mk] = rr
		return rr
	var key := _key(S, B)
	if not enabled or key.is_empty():
		return _compute(S, B, i, foot, ball, p)
	var store: Dictionary = S.get_meta("pose_cache_refs", {})
	if store.get("key", []) == key and store.has(i):
		hits += 1
		return store[i]
	misses += 1
	if store.get("key", []) != key:
		store = {"key": key.duplicate(true)}   # the stored key is a copy: later in-place edits cannot reach it
	var r := _compute(S, B, i, foot, ball, p)
	store[i] = r
	S.set_meta("pose_cache_refs", store)
	return r


## R2: no constraint reads another actor or the weapon (the cases _key refuses to cache)
static func _plain_cons(S: Scene) -> bool:
	for c in S.cons:
		var kind := String((c as Dictionary).get("target", {}).get("kind", ""))
		if kind == "actor" or kind == "weapon":
			return false
	return true


static func _compute(S: Scene, B: Body, i: int, foot: String, ball: String, p: Dictionary) -> Dictionary:
	S._plants_off = true
	S.apply(B, FootPlant.ref_time(p))
	S._plants_off = false
	# BP, BE: the ball's and the toe tip's points; h, rb, re: the ankle's, the ball's and the toe's rest heights (ROADMAP 93: the sole)
	return {"P": B.P[foot], "G": B.G[foot], "Gb": B.G[ball], "pole": LimbIK.pole_from_pose(B, foot),
		"BP": B.P[ball], "BE": B.E[ball], "h": (B.p0[foot] as Vector3).y, "rb": (B.p0[ball] as Vector3).y, "re": (B.e0[ball] as Vector3).y}


## every input the reference apply reads BEFORE it writes it. The bat and the second weapon's pose fields (wep_pos,
## wep_rot, wep_lpos, wep_lrot, wep_hand, wep_on, grip*, wep2_*) are NOT inputs: Scene.put writes them from the card sample
## at the frame's time before anything reads them, and a weapon-target constraint is the one reader that could see the old
## values (see below). An empty array means "do not cache": a constraint on another actor (its reference reads that
## actor's scene) or on the weapon (it reads the bat's last pose when the sample has no bat).
static func _key(S: Scene, B: Body) -> Array:
	for c in S.cons:
		var kind := String((c as Dictionary).get("target", {}).get("kind", ""))
		if kind == "actor" or kind == "weapon":
			return []
	return [S.cards, S.plants, S.ik, S.clips, S.cons, S.layer, S.layer_w, S.layers, S.breath, S.drivers, S.part_keys,
		S.props, S.body, S.fps, S.pin, S.on_floor, S.floor_body, S.free_limits, S.stepped, S.spline, S.loop, S.natural, S.moving_holds, S.sway, S.sway_seed,
		S.cons_me, B.body, B.wep_kind, B.wep_len, B.wep_handle, B.wep2_kind]
