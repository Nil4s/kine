## reaction_picker.gd - HIT REACTION PICKER (ROADMAP R16), a panel on the STAGE page. It lists the reaction clips found in
## a folder (scenes/reactions/, scenes/_wip/reactions/, user://reactions/, and the physics importer's output in
## scenes/_wip whose name says react / hit / fall), each with an ANIMATED THUMBNAIL (three frames: the start, the middle
## and the end of the clip, cycled) and a LABEL read from the clip itself: where it hits, how hard, whether the fighter
## fell. Drag one onto the struck fighter in a two-fighter scene: its cards go onto THAT fighter's scene starting at the
## attacker's CONTACT time (the first row of the fighters' report that lands on that fighter: the same time the Check's
## CONTACT label and the dummy's red dot show), as ONE undo step. The attacker is never touched.
## A reaction clip is an ordinary scene file (cards): the first card is the moment of impact, the rest is the response.
## Not here: turning a MuJoCo / Isaac export into a scene (R15's "Import physics reaction": its output is what this lists).
## HOW THE CARDS ARE PUT IN (insert): the struck fighter keeps its cards that arrive before the contact; the reaction's
## cards follow, the first one's MOVE STARTING at the contact time (the card before it keeps its hold only up to the contact), the body begins to react when it is hit;
## its cards that arrive after the reaction ends come back after it (so a longer fight still follows).
## The label's numbers are measured on the clip (Body angles, 30 per second), not typed: WHERE = the region (head, torso,
## arm, leg) whose joints turn most from the first card's pose (a limb only when it turns 1.5 x more than the trunk and head: limbs swing passively); STRENGTH = that largest single-joint turn (light < 25 deg,
## medium < 50, hard above; the bands are ours); FELL = the hips end under 60 % of their starting height.
class_name ReactionPicker
extends PanelContainer

const DIRS := ["res://scenes/reactions", "res://scenes/_wip/reactions", "user://reactions"]
const WIP := "res://scenes/_wip"
const WIP_WORDS := ["react", "hit", "fall", "physics", "knock"]
const SAMPLE_DIR := "res://scenes/_wip/reactions"
const HZ := 30.0
const LIGHT_DEG := 25.0
const HARD_DEG := 50.0
const FELL_RATIO := 0.6
const LIMB_OVER := 1.5
const MIN_GAP := 0.04     # s: the least move into the card that follows the reaction
const LEAD_MOVE := 0.12   # s: the move into the first reaction card, when there is room for it
const FRAME_S := 0.4      # s a thumbnail frame is shown
const ROW_H := 76.0

var m: Node                      # main.gd
var clips := []                  # [{"path", "name", "S": Scene, "info": describe(), "row": Control, "pic": TextureRect}]
var _box: VBoxContainer
var _note: Label
var _tick := 0.0
var _frame := 0
var _drag := {}                  # {"i", "from", "ghost"}: a row being dragged


# ------------------------------------------------------------------------------------------------ the files

## every reaction clip file at hand: the folders above, plus the physics import's output in scenes/_wip (named for it)
static func scan() -> Array:
	var out := []
	for base in DIRS:
		for dir in UserPaths.dirs(base):   # the bundled folder, and the user's copy in an exported build
			var d := DirAccess.open(dir)
			if d == null:
				continue
			var fs := Array(d.get_files())
			fs.sort()
			for f in fs:
				if String(f).ends_with(".json"):
					out.append(dir + "/" + f)
	for wip in UserPaths.dirs(WIP):
		var w := DirAccess.open(wip)
		if w == null:
			continue
		var fs2 := Array(w.get_files())
		fs2.sort()
		for f in fs2:
			var low := String(f).to_lower()
			if low.ends_with(".json") and WIP_WORDS.any(func(x): return low.contains(x)):
				out.append(wip + "/" + f)
	return out.filter(func(p): return _is_clip(p))


static func _is_clip(path: String) -> bool:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d is Dictionary and (d as Dictionary).get("cards") is Array and ((d as Dictionary)["cards"] as Array).size() >= 2


static func load_clip(path: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return S


static func _body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


# ------------------------------------------------------------------------------------------------ the label

static func region_of(j: String) -> String:
	if j in ["head", "neck_01"]:
		return "head"
	if j.begins_with("clavicle") or j.begins_with("upperarm") or j.begins_with("lowerarm") or j.begins_with("hand"):
		return "arm"
	if j.begins_with("thigh") or j.begins_with("calf") or j.begins_with("foot") or j.begins_with("ball"):
		return "leg"
	return "torso"


static func _finger(j: String) -> bool:
	return j.begins_with("thumb") or j.begins_with("index") or j.begins_with("middle") or j.begins_with("ring") or j.begins_with("pinky")


## what the clip is: {"where", "strength" (word), "peak" (deg), "fell", "label", "poses" [3 card poses: start, middle, end],
## "length" (s)}. Read off the clip with its own body; nothing typed
static func describe(S: Scene) -> Dictionary:
	var B := _body()
	var L := S.length()
	S.apply(B, 0.0)
	var a0: Dictionary = B.ang.duplicate()
	var h0: float = (B.P["pelvis"] as Vector3).y
	var reg := {"head": 0.0, "torso": 0.0, "arm": 0.0, "leg": 0.0}
	var n := maxi(1, int(ceil(L * HZ)))
	var h_end := h0
	for k in n + 1:
		S.apply(B, minf(L, float(k) / HZ))
		for j in B.ang:
			if _finger(String(j)):
				continue
			var d: Vector3 = ((B.ang[j] as Vector3) - (a0[j] as Vector3)).abs()
			var r := region_of(String(j))
			reg[r] = maxf(reg[r], maxf(d.x, maxf(d.y, d.z)))
		h_end = (B.P["pelvis"] as Vector3).y
	# a limb swings passively when the trunk is hit, so a limb names the hit only when it turns LIMB_OVER x more than the trunk and head
	var where := "torso"
	var peak := maxf(reg["torso"], reg["head"])
	if reg["head"] > reg["torso"] + 1e-6:
		where = "head"
	for r in ["arm", "leg"]:
		if reg[r] > peak * LIMB_OVER:
			where = r
			peak = reg[r]
	peak = maxf(peak, maxf(reg["arm"], reg["leg"]) if where == "torso" or where == "head" else peak)
	var fell := h_end < FELL_RATIO * h0
	var word := "light" if peak < LIGHT_DEG else ("medium" if peak < HARD_DEG else "hard")
	var poses := []
	for t in [0.0, L * 0.5, L]:
		S.apply(B, t)
		poses.append(B.to_dict())
	return {"where": where, "strength": word, "peak": peak, "fell": fell, "length": L, "poses": poses,
		"label": "%s · %s %d° · %s" % [where, word, roundi(peak), "FELL" if fell else "stayed up"]}


# ------------------------------------------------------------------------------------------------ the contact

## the first moment a strike lands on fighter k (index in actors_rt; 0 = the hero) in the fighters' report, measured now
## on clones (Main._fighters_measure): {"t", "by" (the striker's index), "found"}. Not found: the playhead
static func contact(m_: Node, k: int) -> Dictionary:
	m_._actors_sync()
	var hs: Scene = (m_.actors_rt[0]["S"] as Scene).clone()
	var others := []
	for i in range(1, m_.actors_rt.size()):
		others.append({"name": m_.actors_rt[i]["name"], "S": (m_.actors_rt[i]["S"] as Scene).clone(), "xf": m_.actors_rt[i]["xf"]})
	var rows: Array = m_.call("_fighters_measure", hs, others)["hits"]
	for r in rows:   # sorted by time
		if r["kind"] != "hit" and r["kind"] != "struck":
			continue
		var victim: int = 0 if r["by"] == "other" else int(r["vs"])
		if victim == k and not Body.is_wep(String(r["on"])):
			return {"t": float(r["t"]), "by": (int(r["vs"]) if r["by"] == "other" else 0), "found": true}
	return {"t": m_.playhead, "by": -1, "found": false}


# ------------------------------------------------------------------------------------------------ the cards

## put the clip's cards onto `victim` starting at time t (see the header). The victim's other keys are untouched, except
## that a clip that FELL puts the victim on the floor rule a lying body needs (floor_body). Returns {"n" (cards put in),
## "kept", "tail"}
static func insert(victim: Scene, clip: Scene, t: float) -> Dictionary:
	var ts := victim.times()
	var keep := 0
	for i in victim.cards.size():
		if float(ts[i][1]) <= t + 1e-9:
			keep = i + 1
		else:
			break
	var end_t := t + LEAD_MOVE + clip.length()
	var tail := []
	var tail_arr := []
	for i in range(keep, victim.cards.size()):
		if float(ts[i][1]) >= end_t:
			tail.append((victim.cards[i] as Dictionary).duplicate(true))
			tail_arr.append(float(ts[i][1]))
	var out := []
	for i in keep:
		out.append((victim.cards[i] as Dictionary).duplicate(true))
	if keep > 0:   # the card before gives up hold so the first reaction card arrives exactly at t
		(out[keep - 1] as Dictionary)["hold"] = snappedf(maxf(0.0, t - float(ts[keep - 1][1])), 0.0001)
		out.append(_clip_card(clip, 0, LEAD_MOVE))
	else:
		out.append(_clip_card(clip, 0, -1.0))
	for i in range(1, clip.cards.size()):
		out.append(_clip_card(clip, i, -2.0))
	for i in tail.size():
		var c: Dictionary = tail[i]
		if i == 0:
			c["move"] = snappedf(maxf(MIN_GAP, float(tail_arr[0]) - end_t), 0.0001)
		out.append(c)
	var fell: bool = bool(describe(clip)["fell"])
	victim.cards = out
	if fell:
		victim.floor_body = true
	return {"n": clip.cards.size(), "kept": keep, "tail": tail.size()}


static func _clip_card(clip: Scene, i: int, move: float) -> Dictionary:
	var c: Dictionary = (clip.cards[i] as Dictionary).duplicate(true)
	if move >= 0.0:
		c["move"] = snappedf(move, 0.0001)
	elif move == -1.0:
		c["move"] = -1.0
	return c   # -2: the clip's own move


# ------------------------------------------------------------------------------------------------ the sample clips

## three sample clips written once under scenes/_wip/reactions/ (NEW files only; a folder that already holds clips is left
## as it is), made from poses already in the app: the bat hit of scenes/hit_react.json (read only) and the stand pose bent
## by hand into a head snap and a knock-down. Returns the paths
static func make_samples(dir0 := SAMPLE_DIR) -> Array:
	var dir := UserPaths.w(dir0)   # an exported build: the user's folder (res:// is read-only)
	var have := []
	var d0 := DirAccess.open(dir)
	if d0 != null:
		var fs := Array(d0.get_files())
		fs.sort()
		for f in fs:
			if String(f).ends_with(".json"):
				have.append(dir + "/" + f)
	if not have.is_empty():
		return have
	DirAccess.make_dir_recursive_absolute(dir)
	var out := []
	var B := _body()
	var stand: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json"))
	# 1 a bat to the torso: the HIT / catch / settle cards of hit_react.json, the bat taken out of the victim's hands
	var hr: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/hit_react.json"))
	var cards1 := []
	for i in range(1, 5):
		var c: Dictionary = (hr["cards"][i] as Dictionary).duplicate(true)
		(c["pose"] as Dictionary)["weapon"] = {}
		cards1.append(c)
	(cards1[0] as Dictionary)["move"] = -1.0
	out.append(_write(dir, "bat_to_torso", cards1, false))
	# 2 a head snap: the chin goes up and back, the shoulders follow, then it comes back
	var cards2 := []
	for st in [["hit", 0.0, {"neck_01": Vector3(-14, 0, 8), "head": Vector3(-10, 0, 6)}, 0.0],
			["snap", 0.14, {"neck_01": Vector3(-30, 0, 30), "head": Vector3(-25, 0, 20), "spine_03": Vector3(-6, 0, 5), "spine_01": Vector3(-5, 0, 0)}, 0.05],
			["recover", 0.3, {"neck_01": Vector3(-8, 0, 6), "head": Vector3(-5, 0, 4)}, 0.1],
			["back up", 0.4, {}, 0.2]]:
		cards2.append(_card(B, stand, st[0], st[1], st[2], st[3], false))
	out.append(_write(dir, "head_snap", cards2, false))
	# 3 a knock-down: tips back, knees go, lies on the floor
	var cards3 := []
	for st in [["hit", 0.0, {"pelvis": Vector3(-8, 0, 0), "spine_01": Vector3(-5, 0, 0), "neck_01": Vector3(-10, 0, 0)}, 0.0],
			["stagger", 0.25, {"pelvis": Vector3(-30, 0, 0), "thigh_l": Vector3(40, 0, 0), "calf_l": Vector3(55, 0, 0), "thigh_r": Vector3(20, 0, 0), "calf_r": Vector3(30, 0, 0), "upperarm_l": Vector3(40, 0, 0), "upperarm_r": Vector3(40, 0, 0)}, 0.0],
			["falling", 0.3, {"pelvis": Vector3(-62, 0, 0), "thigh_l": Vector3(60, 0, 0), "calf_l": Vector3(70, 0, 0), "thigh_r": Vector3(40, 0, 0), "calf_r": Vector3(60, 0, 0), "upperarm_l": Vector3(60, 25, 0), "upperarm_r": Vector3(60, 25, 0)}, 0.0],
			["down", 0.35, {"pelvis": Vector3(-82, 0, 0), "thigh_l": Vector3(20, 10, 0), "calf_l": Vector3(25, 0, 0), "thigh_r": Vector3(10, 0, 0), "calf_r": Vector3(10, 0, 0), "upperarm_l": Vector3(10, 0, 0), "upperarm_r": Vector3(10, 0, 0), "neck_01": Vector3(10, 0, 0)}, 0.8]]:
		cards3.append(_card(B, stand, st[0], st[1], st[2], st[3], true))
	out.append(_write(dir, "knock_down", cards3, true))
	return out


static func _card(B: Body, base: Dictionary, nm: String, move: float, delta: Dictionary, hold: float, lying: bool) -> Dictionary:
	B.from_dict(base)
	for j in delta:
		B.ang[j] = B.clamp_ang(j, (B.ang[j] as Vector3) + (delta[j] as Vector3))
	B.fk()
	if lying:
		B.ground_body()
	else:
		B.ground()
	var p := B.to_dict()
	p["weapon"] = {}
	return {"name": nm, "pose": p, "move": (-1.0 if move <= 0.0 else move), "hold": hold}


static func _write(dir: String, nm: String, cards: Array, floor_body: bool) -> String:
	var path := "%s/%s.json" % [dir, nm]
	var d := {"scene": nm, "fps": 30, "cards": cards, "natural": true, "on_floor": not floor_body, "floor_body": floor_body, "pin": false,
		"note": "a sample hit reaction (R16): made from the app's own poses; the first card is the moment of impact"}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d, " "))
		f.close()
	return path


# ------------------------------------------------------------------------------------------------ the panel

func setup(m_: Node) -> void:
	m = m_
	name = "reaction_picker"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tok.c("float")
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	var h := Label.new()
	h.text = "HIT REACTIONS: drag one onto the struck fighter"
	h.add_theme_font_size_override("font_size", 13)
	h.add_theme_color_override("font_color", Tok.c("heading"))
	v.add_child(h)
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 11)
	_note.add_theme_color_override("font_color", Tok.of("ink:0.6"))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 320
	v.add_child(_note)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(330, 3.0 * ROW_H + 12.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_box)
	if m.thumbs != null:
		m.thumbs.made_pose.connect(_pic_ready)
	set_process_input(false)
	rebuild()


## list the folders again (the picker shows what is on disk now)
func rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	clips.clear()
	for p in scan():
		var S := load_clip(p)
		var info := describe(S)
		var row := _row(p, info, clips.size())
		_box.add_child(row["row"])
		clips.append({"path": p, "name": String(p.get_file().get_basename()), "S": S, "info": info, "row": row["row"], "pic": row["pic"]})
	_note.text = ("%d reactions found. The cards land on the struck fighter at the moment the other one hits it." % clips.size()) if not clips.is_empty() \
		else "no reaction clips yet: put scenes in scenes/reactions/ (or import a physics hit), or run 'Reactions: make 3 sample clips'"
	for c in clips:
		for p in (c["info"]["poses"] as Array):
			if m.thumbs != null:
				m.thumbs.request_pose(p)
	_show_frame()


func _row(path: String, info: Dictionary, i: int) -> Dictionary:
	var pc := PanelContainer.new()
	pc.name = "clip_%d" % (i + 1)
	pc.custom_minimum_size = Vector2(0, ROW_H)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.tooltip_text = "%s: %s.  Drag it onto the struck fighter in the view (cards start at the contact, one Ctrl+Z)." % [path.get_file(), info["label"]]
	var rb := StyleBoxFlat.new()
	rb.bg_color = Tok.c("card")
	rb.set_corner_radius_all(4)
	rb.set_content_margin_all(4)
	pc.add_theme_stylebox_override("panel", rb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_PASS
	pc.add_child(hb)
	var pic := TextureRect.new()
	pic.name = "pic"
	pic.custom_minimum_size = Vector2(96, 64)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(pic)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(vb)
	var t1 := Label.new()
	t1.text = path.get_file().get_basename().replace("_", " ")
	t1.add_theme_font_size_override("font_size", 14)
	t1.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_child(t1)
	var t2 := Label.new()
	t2.name = "label"
	t2.text = "hits: %s\n%s %d°\n%s · %.1f s" % [info["where"], info["strength"], roundi(info["peak"]), "fell" if info["fell"] else "stayed up", info["length"]]
	t2.add_theme_font_size_override("font_size", 11)
	t2.add_theme_color_override("font_color", Tok.c("warn") if info["fell"] else Tok.of("ink:0.75"))
	t2.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_child(t2)
	pc.gui_input.connect(_row_input.bind(i))
	return {"row": pc, "pic": pic}


func _pic_ready(_key: String) -> void:
	_show_frame()


func _process(dt: float) -> void:
	if not is_visible_in_tree() or clips.is_empty():
		return
	_tick += dt
	if _tick >= FRAME_S:
		_tick = 0.0
		_frame = (_frame + 1) % 4
		_show_frame()


## the thumbnails: frame 0, 1, 2, 1 of each clip's three poses, in turn
func _show_frame() -> void:
	if m == null or m.thumbs == null:
		return
	var k: int = [0, 1, 2, 1][_frame]
	for c in clips:
		var poses: Array = c["info"]["poses"]
		var tex: Texture2D = m.thumbs.pose_picture(poses[k])
		if tex == null:
			tex = m.thumbs.pose_picture(poses[0])
		if tex != null and is_instance_valid(c["pic"]):
			(c["pic"] as TextureRect).texture = tex


## how many thumbnails have a picture now (the test reads it)
func pictures() -> int:
	var n := 0
	for c in clips:
		if (c["pic"] as TextureRect).texture != null:
			n += 1
	return n


# ------------------------------------------------------------------------------------------------ the drag

func _row_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (ev as InputEventMouseButton).pressed:
		_drag = {"i": i, "from": (ev as InputEventMouseButton).global_position, "ghost": null}
		set_process_input(true)


func _input(ev: InputEvent) -> void:
	if _drag.is_empty():
		return
	if ev is InputEventMouseMotion:
		var at: Vector2 = (ev as InputEventMouseMotion).global_position
		if _drag["ghost"] == null and at.distance_to(_drag["from"]) > 6.0:
			var g := Label.new()
			g.text = "  " + String(clips[_drag["i"]]["name"]).replace("_", " ") + ": drop on the struck fighter  "
			g.add_theme_font_size_override("font_size", 13)
			var gs := StyleBoxFlat.new()
			gs.bg_color = Tok.c("accent")
			gs.set_corner_radius_all(4)
			g.add_theme_stylebox_override("normal", gs)
			g.mouse_filter = Control.MOUSE_FILTER_IGNORE
			m.ui_root.add_child(g)
			_drag["ghost"] = g
		if _drag["ghost"] != null:
			(_drag["ghost"] as Control).global_position = at + Vector2(14, 10)
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not (ev as InputEventMouseButton).pressed:
		var d := _drag
		_drag = {}
		set_process_input(false)
		if d["ghost"] != null:
			(d["ghost"] as Control).queue_free()
			var at2: Vector2 = (ev as InputEventMouseButton).global_position
			if not get_global_rect().has_point(at2):
				m._reaction_drop(String(clips[d["i"]]["path"]), at2)
