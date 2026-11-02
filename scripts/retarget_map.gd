## RETARGET BONE-MAP SCREEN (W04). AnimImport.map_bones guesses source bone -> Kine joint; this shows the guess as pairs
## (Kine joint | source bone | name / structure / manual / saved), lets the animator fix any pair with a drop-down, and saves the
## map per RIG (key = the sorted bone names), so a second file from the same rig loads it with no screen.
## Logic is static (testable alone); the screen is RetargetMap.Screen. AnimImport._import_file calls RetargetMap.resolve.
class_name RetargetMap
extends RefCounted

const DIR := "user://bone_maps"
const NONE := "(none)"


## the rig's identity: the same bone names (any order) are the same rig
static func rig_key(src: Dictionary) -> String:
	var n: Array = (src["names"] as Array).duplicate()
	n.sort()
	return str("|".join(PackedStringArray(n)).hash())


static func _path(key: String) -> String:
	return "%s/%s.json" % [DIR, key]


static func has_saved(src: Dictionary) -> bool:
	return FileAccess.file_exists(_path(rig_key(src)))


## rows: [{kine, bone (name), idx, how}] for every mapped Kine joint, in body order
static func pairs(src: Dictionary, m: Dictionary) -> Array:
	var out := []
	for j in Body.ORDER:
		if m["map"].has(j):
			out.append({"kine": j, "bone": String(src["names"][m["map"][j]]), "idx": int(m["map"][j]), "how": String(m["how"].get(j, "name"))})
	return out


## point Kine joint `kine` at source bone `idx` (-1 = none). A bone already used by another joint swaps: that joint takes this one's old bone.
static func set_pair(m: Dictionary, kine: String, idx: int) -> void:
	var old: int = int(m["map"][kine]) if m["map"].has(kine) else -1
	if idx >= 0:
		for j in m["map"].keys():
			if j != kine and int(m["map"][j]) == idx:
				if old >= 0:
					m["map"][j] = old
					m["how"][j] = "manual"
				else:
					m["map"].erase(j)
					m["how"].erase(j)
	if idx < 0:
		m["map"].erase(kine)
		m["how"].erase(kine)
	else:
		m["map"][kine] = idx
		m["how"][kine] = "manual"
	refresh(m)


## unmapped / missing / main recomputed from m["map"] (needs m["_names"])
static func refresh(m: Dictionary) -> void:
	var names: Array = m["_names"]
	var used := {}
	for j in m["map"]:
		used[int(m["map"][j])] = true
	var un := []
	for i in names.size():
		if not used.has(i):
			un.append(names[i])
	var miss := []
	var main := 0
	for j in Body.ORDER:
		if m["map"].has(j):
			main += 1 if j in AnimImport.MAIN else 0
		else:
			miss.append(j)
	m["unmapped"] = un
	m["missing"] = miss
	m["main"] = main


static func guess(src: Dictionary) -> Dictionary:
	var m := AnimImport.map_bones(src)
	m["_names"] = src["names"]
	return m


static func save(src: Dictionary, m: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var pr := {}
	for j in m["map"]:
		pr[j] = String(src["names"][m["map"][j]])
	var f := FileAccess.open(_path(rig_key(src)), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"rig": rig_key(src), "bones": (src["names"] as Array).size(), "pairs": pr}))
	return true


## the saved map for this rig applied (how = "saved"), else the guess. Never raises: a bad file falls back to the guess.
static func resolve(src: Dictionary) -> Dictionary:
	var m := guess(src)
	if not has_saved(src):
		return m
	var d = JSON.parse_string(FileAccess.get_file_as_string(_path(rig_key(src))))
	if not (d is Dictionary) or not (d.get("pairs") is Dictionary):
		return m
	var at := {}
	for i in (src["names"] as Array).size():
		at[String(src["names"][i])] = i
	m["map"] = {}
	m["how"] = {}
	for j in d["pairs"]:
		var b := String(d["pairs"][j])
		if Body.ORDER.has(j) and at.has(b):
			m["map"][j] = at[b]
			m["how"][j] = "saved"
	refresh(m)
	return m


## ---- the screen --------------------------------------------------------------------------------------------------------
class Screen extends PanelContainer:
	signal done(m: Dictionary)   # Import pressed: the (possibly fixed) map, already saved for the rig
	signal cancelled
	var src: Dictionary
	var m: Dictionary
	var rows: Array = []   # [{kine, label, tag, opt}]
	var grid: GridContainer
	var info: Label
	var import_btn: Button
	var cancel_btn: Button

	func setup(source: Dictionary, mapping: Dictionary) -> void:
		src = source
		m = mapping
		name = "BoneMapScreen"
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.11, 0.12, 0.14, 1.0)   # opaque: the app behind must not show through the rows
		sb.border_color = Color(1, 1, 1, 0.25)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(14)
		add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		add_child(v)
		var t := Label.new()
		t.text = "Check how this rig's bones were matched to Kine's"
		t.add_theme_font_size_override("font_size", 18)
		v.add_child(t)
		info = Label.new()
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size.x = 300
		v.add_child(info)
		var sc := ScrollContainer.new()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.custom_minimum_size = Vector2(300, 120)
		v.add_child(sc)
		grid = GridContainer.new()
		grid.columns = 3
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 12)
		sc.add_child(grid)
		var hb := HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_END
		v.add_child(hb)
		cancel_btn = Button.new()
		cancel_btn.text = "Cancel"
		cancel_btn.pressed.connect(func(): cancelled.emit())
		hb.add_child(cancel_btn)
		import_btn = Button.new()
		import_btn.text = "Import with this map"
		import_btn.pressed.connect(_ok)
		hb.add_child(import_btn)
		_fill()

	func _fill() -> void:
		rows = []
		var names: Array = src["names"]
		for h in ["Kine joint", "Source bone (tap to change)", "Matched by"]:
			var l := Label.new()
			l.text = h
			l.modulate = Color(1, 1, 1, 0.6)
			grid.add_child(l)
		# the main 22 first (a missing one still gets a row so it can be fixed), then the other mapped joints
		var order: Array = AnimImport.MAIN.duplicate()
		for p in RetargetMap.pairs(src, m):
			if not order.has(p["kine"]):
				order.append(p["kine"])
		for j in order:
			var idx: int = int(m["map"][j]) if m["map"].has(j) else -1
			var jl := Label.new()
			jl.text = j
			grid.add_child(jl)
			var opt := OptionButton.new()
			opt.name = "opt_" + j
			opt.fit_to_longest_item = false
			opt.clip_text = true
			opt.custom_minimum_size.x = 220
			opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			opt.add_item(RetargetMap.NONE, 0)
			for i in names.size():
				opt.add_item(String(names[i]), i + 1)
			opt.select(idx + 1)
			opt.item_selected.connect(func(k: int): _picked(j, opt.get_item_id(k) - 1))
			grid.add_child(opt)
			var tg := Label.new()
			tg.text = String(m["how"].get(j, "-")) if idx >= 0 else "not matched"
			grid.add_child(tg)
			rows.append({"kine": j, "label": jl, "tag": tg, "opt": opt})
		_info()

	func _info() -> void:
		info.text = "%d of %d main joints matched. Pick another bone for any row; a bone used twice swaps. The map is remembered for this rig." % [m["main"], AnimImport.MAIN.size()]

	func _picked(kine: String, idx: int) -> void:
		RetargetMap.set_pair(m, kine, idx)
		for r in rows:
			var j: String = r["kine"]
			var ix: int = int(m["map"][j]) if m["map"].has(j) else -1
			(r["opt"] as OptionButton).select(ix + 1)
			(r["tag"] as Label).text = String(m["how"].get(j, "-")) if ix >= 0 else "not matched"
		_info()

	func _ok() -> void:
		RetargetMap.save(src, m)
		done.emit(m)

	## the pairs as shown: [[kine, bone text, tag text]] for rows with a bone
	func shown_pairs() -> Array:
		var out := []
		for r in rows:
			var o: OptionButton = r["opt"]
			if o.selected > 0:
				out.append([r["kine"], o.get_item_text(o.selected), (r["tag"] as Label).text])
		return out


## import `path` with the screen when the rig has no saved map, silently with it when it has. `host` is main (has _import_anim).
static func import_with_screen(host: Node, path: String) -> void:
	var src := AnimImport.load_source(path)
	if not src["ok"] or has_saved(src):
		host._import_anim(path)
		return
	var layer := CanvasLayer.new()
	layer.layer = 90
	layer.name = "BoneMapLayer"
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var cen := CenterContainer.new()
	cen.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(cen)
	var sc := Screen.new()
	var vp := Vector2(1024, 600)
	if host.is_inside_tree() and host.get_viewport() != null:
		vp = host.get_viewport().get_visible_rect().size
	sc.custom_minimum_size = Vector2(minf(760.0, vp.x - 32.0), minf(620.0, vp.y - 32.0))
	cen.add_child(sc)
	sc.setup(src, guess(src))
	sc.done.connect(func(_m): layer.queue_free(); host._import_anim(path))
	sc.cancelled.connect(layer.queue_free)
	host.add_child(layer)
