## godot --path . -s tests/fastsave_test.gd   (L56 FASTSAVE, 11-06)
## Save and USD export with a big set replayed every frame (Scene.check on save; Props.solid_cache rebuilt on every grounding call).
## Target (docs/PERF_SCOUT_1106.md row 1): save with 1000 props 8.8 s -> <= 300 ms; the saved file BYTE-IDENTICAL to before.
## BARS (written before the fix, never moved):
##   S1  warm save (nothing changed since the last save), median of 5: <= 300 ms at 256 AND at 1000 props
##   S2  cold save (first save after a prop edit), median of 3: <= 1500 ms at 1000 props
##   S3  USD text with props, median of 3: <= 1500 ms at 1000 props
##   E1  saved text == reference text built from the UNCACHED public Scene.check (key order kept) at 0 / 256 / 1000 props, combo3 (39 bad frames)
##   E2  after a prop edit, a card pose edit and a body-state change, the next save still equals its reference (the cache is invalidated)
##   E3  golden: sha256 of the save text and of the USD text equal the values recorded BEFORE the change (C:/Temp/claude/fastsave/gold.json;
##       FASTSAVE_GOLD=1 records them, a normal run compares)
##   U1  undo/redo exact: props+cards hash after undo == before the edit; the save after undo == the save before the edit
##   W1  a warm save makes 0 Scene.apply calls (Scene.apply_calls delta)
##   G1  grounding equality: a dense set AROUND the body (every built-in kind, yaws, scales, tilted ones; 400 props) changes the pose, and the
##       per-frame body state with the new grounding == with Body.legacy_ground (the pre-optimisation code), all frames; G2 control: the dense set
##       really moves the body (state hash differs from the no-props run)
##   P1..P3 planted-fail controls: (P1) the comparison flags a one-byte change; (P2) a stale answer (the pre-edit save text) is flagged against the
##          post-edit reference; (P3) the bad_frames list is non-empty so E1 is not comparing two empties
extends SceneTree

const GOLD := "C:/Temp/claude/fastsave/gold.json"
const KINDS4 := ["box", "crate", "table", "chair"]
var m: Node
var fails := 0
var passes := 0
var H := {}


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if c:
		passes += 1
	else:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func boot() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.easy.set_on(false, false)
	m._as_wait = -1e9
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.undo.clear()
	m.redo.clear()
	m.set_process(false)
	await idle(4)


func set_props(n: int) -> void:
	var side := int(ceil(sqrt(float(n))))
	var props := []
	for i in n:
		var pos := Vector3((i % side) * 1.5 - side * 0.75, 0, (i / side) * 1.5 - side * 0.75 + 4.0)
		props.append(Props.make(KINDS4[i % 4], Props.xf_at(pos, float(i * 37 % 360))))
	m.S.props = props


func med(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return b[b.size() / 2]


func ms_of(c: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	c.call()
	return (Time.get_ticks_usec() - t0) / 1000.0


func save_text() -> String:
	return JSON.stringify(m.S.to_dict(m.B))


## what the file must be: to_dict without the scan, plus the UNCACHED public check, "bad_frames" right after "cards" (where the literal has it)
func reference_text() -> String:
	var keep: Dictionary = m.B.state()
	var d: Dictionary = m.S.to_dict(m.B, false)
	var was: bool = m.S.stepped
	m.S.stepped = false
	var bad: Array = m.S.check(m.B)
	m.S.stepped = was
	var out := {}
	for k in d:
		out[k] = d[k]
		if k == "cards":
			out["bad_frames"] = bad
	m.B.set_state(keep)
	return JSON.stringify(out)


func snap_hash() -> int:
	return hash([m.S.props.map(func(p): return Props.to_dict(p)), m.S.cards.duplicate(true)])


func gold_get() -> Dictionary:
	if not FileAccess.file_exists(GOLD):
		return {}
	return JSON.parse_string(FileAccess.get_file_as_string(GOLD))


func frame_hashes() -> Array:
	var out := []
	var n := int(ceil(m.S.length() * m.S.fps))
	for f in n + 1:
		m.S.apply(m.B, float(f) / m.S.fps)
		var st: Dictionary = m.B.state()
		out.append(hash([st["ang"], st["offset"], m.B.P["foot_l"], m.B.P["foot_r"]]))
	return out


func ground_equality() -> void:
	var keys: Array = Props.KINDS.keys()
	var props := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 56
	for i in 400:
		var pos := Vector3(rng.randf_range(-2.0, 2.0), 0.0, rng.randf_range(-2.0, 2.0))
		var pr := Props.make(keys[i % keys.size()], Props.xf_at(pos, rng.randf_range(0, 360)))
		if i % 5 == 0:
			pr["scale"] = rng.randf_range(0.5, 1.5)
		if i % 9 == 0:
			pr["xf"] = Transform3D(Basis(Vector3(1, 0, 0), rng.randf_range(-0.4, 0.4)) * (pr["xf"] as Transform3D).basis, (pr["xf"] as Transform3D).origin)
		props.append(pr)
	m.S.props = []
	var h0 := frame_hashes()
	m.S.props = props
	Body.legacy_ground = true
	var hl := frame_hashes()
	Body.legacy_ground = false
	var hn := frame_hashes()
	var diff := 0
	for i in hn.size():
		if hn[i] != hl[i]:
			diff += 1
	var moved := 0
	for i in hn.size():
		if hn[i] != h0[i]:
			moved += 1
	ok(diff == 0, "G1 grounding: new == legacy on %d frames of a dense set (%d differ)" % [hn.size(), diff])
	ok(moved > 0, "G2 control: the dense set moves the body on %d of %d frames" % [moved, hn.size()])
	m.S.props = []


func _init() -> void:
	await boot()
	var gold: Dictionary = gold_get()
	var rec: bool = OS.get_environment("FASTSAVE_GOLD") == "1"
	var newgold := {}
	m.S.stepped = false
	for n in [0, 256, 1000]:
		set_props(n)
		m._props_show()
		await idle(2)
		var t1 := save_text()
		if rec:   # golden mode (run on the UNFIXED code, where every save costs seconds): only the hashes
			newgold["save_%d" % n] = t1.sha256_text()
			if n > 0:
				newgold["usd_%d" % n] = String(UsdExport.text(m.S, m.B)[0]).sha256_text()
			continue
		var ref := reference_text()
		ok(t1 == ref, "E1 %d props: save == reference (%d bytes)" % [n, t1.length()])
		if n == 0:
			var parsed = JSON.parse_string(t1)
			ok((parsed["bad_frames"] as Array).size() > 0, "P3 combo3 has bad frames (%d), E1 compares real content" % (parsed["bad_frames"] as Array).size())
			var alt := t1.substr(0, t1.length() / 2) + "X" + t1.substr(t1.length() / 2 + 1)
			ok(alt != ref, "P1 planted one-byte change is flagged")
		newgold["save_%d" % n] = t1.sha256_text()
		if n == 0:
			continue
		# S1 warm saves
		var warm := []
		for i in 5:
			warm.append(ms_of(func(): H["t"] = save_text()))
		print("ROW|save warm|%d|%.1f" % [n, med(warm)])
		ok(med(warm) <= 300.0, "S1 warm save %d props median %.0f ms <= 300" % [n, med(warm)])
		if n == 1000:
			var a1: int = Scene.apply_calls
			save_text()
			ok(Scene.apply_calls - a1 == 0, "W1 warm save made %d apply calls (want 0)" % (Scene.apply_calls - a1))
		# S2 cold saves: a prop edit before each
		var cold := []
		for i in 3:
			m.S.props[0]["xf"] = Props.xf_at(Vector3(0.1 * i, 0, 4.0), float(i))
			cold.append(ms_of(func(): H["t"] = save_text()))
		print("ROW|save cold|%d|%.1f" % [n, med(cold)])
		if n == 1000:
			ok(med(cold) <= 1500.0, "S2 cold save %d props median %.0f ms <= 1500" % [n, med(cold)])
		# S3 USD
		var us := []
		for i in 3:
			us.append(ms_of(func(): H["usd"] = UsdExport.text(m.S, m.B)))
		print("ROW|usd text|%d|%.1f" % [n, med(us)])
		if n == 1000:
			ok(med(us) <= 1500.0, "S3 USD text %d props median %.0f ms <= 1500" % [n, med(us)])
		newgold["usd_%d" % n] = String(H["usd"][0]).sha256_text()
		# back to the golden state
		set_props(n)
		m._props_show()
		await idle(1)
		var before_edit := save_text()
		newgold["save_%d" % n] = before_edit.sha256_text()
		# E2 invalidation: prop edit, card edit, body-state change
		var h0 := snap_hash()
		m.undo.clear()
		m._step_hint = "fastsave"
		m._push_undo()
		m.S.props[1]["xf"] = Props.xf_at(Vector3(0.0, 0.0, 0.0), 10.0)
		var after_prop := save_text()
		ok(after_prop == reference_text(), "E2 %d: save after a prop edit == reference" % n)
		ok(after_prop != before_edit, "P2 %d: the pre-edit text is stale against the post-edit reference (flagged)" % n)
		var card_j: Dictionary = (m.S.cards[1]["pose"] as Dictionary)["joints"]["upperarm_r"]
		var card_pose: Dictionary = card_j
		var jn := "bend"
		var old = card_pose[jn]
		card_pose[jn] = float(old) + 40.0
		ok(save_text() == reference_text(), "E2 %d: save after a card pose edit == reference" % n)
		card_pose[jn] = old
		ok(save_text() == reference_text(), "E2 %d: save after the card edit is reverted == reference" % n)
		m.B.wep_on = not m.B.wep_on
		ok(save_text() == reference_text(), "E2 %d: save after a weapon toggle == reference" % n)
		m.B.wep_on = not m.B.wep_on
		# U1 undo exact
		m._undo()
		ok(snap_hash() == h0, "U1 %d: undo restores props+cards exactly" % n)
		ok(save_text() == before_edit, "U1 %d: the save after undo == the save before the edit" % n)
		m._redo()
		ok(save_text() == reference_text(), "U1 %d: the save after redo == reference" % n)
		m._undo()
	if not rec:
		await ground_equality()
	if rec:
		DirAccess.make_dir_recursive_absolute("C:/Temp/claude/fastsave")
		var f := FileAccess.open(GOLD, FileAccess.WRITE)
		f.store_string(JSON.stringify(newgold))
		f.close()
		print("INFO|golden recorded: %s" % JSON.stringify(newgold))
	else:
		ok(not gold.is_empty(), "E3 golden file exists")
		for k in newgold:
			ok(gold.get(k, "") == newgold[k], "E3 golden %s equal" % k)
	print("fastsave: %d ok, %d fail" % [passes, fails])
	quit(0)
