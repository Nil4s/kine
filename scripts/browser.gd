## BROWSER (round 7, Fusion 360's browser tree): every part of the body by name, folded the way the body is built
## (torso, each arm with its fingers, each leg), the weapon, and the open scene's clips. Click a part = it is
## selected, the same as clicking it in the view (a finger joint is hard to hit in 3D; here it is one click). Click a
## clip = picked, the same as on the timeline. It follows the selection: click in the view and its row lights up.
class_name Browser
extends Tree

const GROUPS := [
	["Torso", ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head"]],
	["Right arm", ["clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"], "r"],
	["Left arm", ["clavicle_l", "upperarm_l", "lowerarm_l", "hand_l"], "l"],
	["Right leg", ["thigh_r", "calf_r", "foot_r", "ball_r"]],
	["Left leg", ["thigh_l", "calf_l", "foot_l", "ball_l"]],
]
const FINGER_NAMES := ["thumb", "index", "middle", "ring", "pinky"]

var m: Node
var rows := {}   # part -> its TreeItem
var _scene_root: TreeItem
var _set_root: TreeItem   # round 37 (SS5): the scene's props, one row each (shown only when there are any)
var _wep: TreeItem
var _bodies: TreeItem   # G07: the saved bodies (.kbody), a row each with its picture (shown only when there are any)
var _quiet := false
var folders := []   # [the folder row, its parts]: a limb's eye and lock act on all of them (KK1)
var _lit: TreeItem   # the row lit because the view's mouse is on its part (KK2)
var _hover_mine := false   # the hover came from the mouse on a row here
var _poses_root: TreeItem   # RR3: Poses > Library / Mine, rows from main's pose list
var _lib: TreeItem
var _down := false   # R8: the left button is down on the tree
var _pose_pending := -1   # R8: the pose row pressed, applied on release unless it became a drag
var _mine: TreeItem
var _dummy: TreeItem
var _psets := {}   # "select" / "keying" -> the folder of the scene's selection / keying sets (scripts/part_sets.gd)
var pose_cache_path := "user://pose_tags.json"   # R21: where the computed pose tags are cached (a test points it at a temp file)
var pose_query := ""   # R21: the words typed in the Poses search box
var pose_index: PoseTags.Index
var _pose_sig := ""   # the pose paths the index was built from
var _search: LineEdit   # sits over the first row under Poses
var _search_row: TreeItem
var _chips: Control   # the layer that draws the matching tags as chips on the rows
var _followed := ""   # the part whose row follow() last went to (a change of it is the only thing that scrolls the tree to it)
var _outl_root: TreeItem   # L36 OUTLINER (scripts/outliner.gd): the scene's objects as a tree by parent
var outl_kinds := {"body": true, "light": true, "cam": true, "cloth": true, "soft": true, "prop": true}   # the type filter toggles
var outl_query := ""   # the words typed in the Outliner's search box
var _ol_sig := ""   # what the Outliner rows were built from (a rebuild only when it changes: a rebuild mid-click drops the click)
var _ol_search: LineEdit
var _ol_search_row: TreeItem
var _ol_bar: HBoxContainer   # the filter toggles, drawn over their row
var _ol_bar_row: TreeItem
var _ol_closed := {}   # object id -> true for a row the user folded
var _pending := false   # a clip-row rebuild is queued for the next frame   # true while the tree follows the view (a selection made here must not loop back)


func _ready() -> void:
	hide_root = true
	focus_mode = Control.FOCUS_NONE
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_font_size_override("font_size", 13)   # RR3: rows of 22 px (Fusion's browser), was 15
	add_theme_constant_override("v_separation", 2)
	add_theme_constant_override("item_margin", 12)
	add_theme_constant_override("draw_guides", 0)
	item_selected.connect(_chosen)
	_search = LineEdit.new()   # R21: search the pose library by words (names and auto tags); filters as you type
	_search.name = "pose_search"
	_search.placeholder_text = "search poses: guard, tired, low kick..."
	_search.clear_button_enabled = true
	_search.add_theme_font_size_override("font_size", 12)
	_search.tooltip_text = "words over the pose names and their tags (crouch, guard, high, low, kick, lunge, one-leg, arms-up, seated, lying) and moods measured from the body (tired, proud, scared, happy, angry, sad, calm, excited; exhausted = tired); a typo is forgiven"
	_search.visible = false
	_search.text_changed.connect(set_pose_query)
	add_child(_search)
	_chips = ChipLayer.new()
	_chips.t = self
	_chips.name = "pose_chips"
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_chips)
	drop_mode_flags = Tree.DROP_MODE_ON_ITEM
	_ol_search = LineEdit.new()
	_ol_search.name = "outl_search"
	_ol_search.placeholder_text = "search the scene: chair, key light..."
	_ol_search.clear_button_enabled = true
	_ol_search.add_theme_font_size_override("font_size", 12)
	_ol_search.tooltip_text = "words over the names of the scene's objects (any case); with the type toggles below it, only those objects are listed"
	_ol_search.visible = false
	_ol_search.text_changed.connect(set_outl_query)
	add_child(_ol_search)
	_ol_bar = HBoxContainer.new()
	_ol_bar.name = "outl_filters"
	_ol_bar.add_theme_constant_override("separation", 1)
	_ol_bar.visible = false
	for k in Outliner.KINDS:
		var b := Button.new()
		b.name = "outl_f_" + k
		b.toggle_mode = true
		b.button_pressed = true
		b.text = {"body": "Body", "light": "Light", "cam": "Cam", "cloth": "Cloth", "soft": "Soft", "prop": "Prop"}[k]
		b.tooltip_text = "show / hide the %s in the list below" % Outliner.KIND_NAMES[k].to_lower()
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 10)
		b.custom_minimum_size = Vector2(10, 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggled.connect(func(on: bool): set_outl_filter(k, on))
		_ol_bar.add_child(b)
	add_child(_ol_bar)
	item_collapsed.connect(func(it: TreeItem):
		var md = it.get_metadata(0)
		if md is Dictionary and md.has("onode"):
			if it.collapsed:
				_ol_closed[md["onode"]] = true
			else:
				_ol_closed.erase(md["onode"])
		m._browser_fit.call_deferred())   # RR6: a folder opened or closed: the box follows
	gui_input.connect(_motion)
	mouse_exited.connect(_left)
	build()


func _part(parent: TreeItem, j: String, label := "") -> TreeItem:
	var it := create_item(parent)
	it.set_text(0, label if label != "" else m.nice(j))
	it.set_metadata(0, {"part": j})
	it.set_tooltip_text(0, it.get_text(0))   # the whole name, when the eye and lock leave it cut short
	rows[j] = it
	if not j in Body.WEAPON:   # the weapon has its own lock (L) and is never hidden from here
		it.add_button(0, Icons.small("eye"), 0)
		it.add_button(0, Icons.small("unlock"), 1)
	return it


## a folder's eye and lock, for every part under it
func _folder_buttons(it: TreeItem, js: Array) -> void:
	it.add_button(0, Icons.small("eye"), 0)
	it.add_button(0, Icons.small("unlock"), 1)
	folders.append([it, js])


func _folder(parent: TreeItem, t: String, folded := false) -> TreeItem:
	var it := create_item(parent)
	it.set_text(0, t)
	it.set_selectable(0, false)
	it.set_custom_color(0, Tok.c("heading"))
	it.collapsed = folded
	return it


func build() -> void:
	clear()
	rows = {}
	folders = []
	_lit = null
	var root := create_item()
	_scene_root = _folder(root, "Scene", true)   # RR6: folded (the clips are on the strip below); a row = a click away
	_poses_root = _folder(root, "Poses")
	_poses_root.set_metadata(0, {"menu": "poses"})
	_search_row = create_item(_poses_root)   # R21: the search box is drawn over this row
	_search_row.set_selectable(0, false)
	_search_row.set_custom_minimum_height(26)
	_lib = _folder(_poses_root, "Library", true)
	_mine = _folder(_poses_root, "Mine")
	var body := _folder(root, "Body")
	for g in GROUPS:
		var gi := _folder(body, g[0], true)   # RR6: folded; picking a part unfolds its group (_refresh_now)
		var all: Array = g[1].duplicate()
		for j in g[1]:
			_part(gi, j)
		if g.size() > 2:   # an arm: its fingers, folded, one row per joint
			var fi := _folder(gi, "fingers", true)
			var hand := []
			for f in FINGER_NAMES:
				var ff := _folder(fi, f, true)
				var one := []
				for k in 3:
					# "index, middle joint": a row must say which finger even when its folders have scrolled away
					var fj := "%s_0%d_%s" % [f, k + 1, g[2]]
					_part(ff, fj, "%s, %s joint" % [f, ["base", "middle", "tip"][k]])
					one.append(fj)
				_folder_buttons(ff, one)
				hand += one
			_folder_buttons(fi, hand)
			all += hand
		_folder_buttons(gi, all)
	var sets_root := _folder(root, "Sets")   # the user's named groups of parts (GAP_ANALYSIS rows 9, 6)
	sets_root.set_tooltip_text(0, "selection sets (a click selects their parts) and keying sets (K keys the active one's parts)")
	for k in PartSets.KINDS:
		_psets[k] = _folder(sets_root, k)
		_psets[k].set_metadata(0, {"menu": "psets_" + k})
		_psets[k].set_tooltip_text(0, "right-click: a new %s from the selected parts" % PartSets.WORD[k])
	_bodies = _folder(root, "Bodies", true)
	_wep = _folder(root, "Weapon")
	_part(_wep, "bat_handle", "handle (drag it to swing the weapon)")
	_outl_root = _folder(root, "Outliner", true)
	_outl_root.set_tooltip_text(0, "every object of the scene by parent: drag a row onto another to parent it (it stays where it is); the eye hides, the lock freezes")
	_ol_search_row = create_item(_outl_root)
	_ol_search_row.set_selectable(0, false)
	_ol_search_row.set_custom_minimum_height(26)
	_ol_bar_row = create_item(_outl_root)
	_ol_bar_row.set_selectable(0, false)
	_ol_bar_row.set_custom_minimum_height(24)
	_ol_sig = ""
	_set_root = _folder(root, "Set")
	_set_root.set_tooltip_text(0, "the scene's props: click one to pick it; SET adds, turns and deletes them")
	_dummy = _folder(root, "Target dummy")
	_dummy.set_metadata(0, {"menu": "dummy"})
	_dummy.set_tooltip_text(0, "right-click: on / off, closer, farther, solid")
	refresh()


## the parts of the tree that change: the weapon row (only with a weapon), the scene's clips, the selection.
## Always on the NEXT frame: a click on a clip row picks the card, which rebuilds the cards, which lands here; freeing
## that row while the Tree is still handling the click on it crashed Godot (illegal instruction, browser_test)
func refresh() -> void:
	if not _pending:
		_pending = true
		_refresh_now.call_deferred()


## every folder open but the finger folders and Library (as the tree was before RR6 folded Scene and the groups): a
## test that clicks deep rows opens the tree first, as a user opens a folder
func open_all() -> void:
	var it := get_root().get_first_child() if get_root() != null else null
	while it != null:
		if it.get_text(0) != "fingers" and not it.get_text(0).begins_with("Library") and it.get_parent() != null and it.get_parent().get_text(0) != "fingers":
			it.collapsed = false
		it = it.get_next_in_tree()
	m._browser_fit.call_deferred()


## RR6: the height the rows need (the box fits them, as Fusion's browser does): the shown rows (a folded folder's
## children are not shown) times a row's height, plus the tree's own margins
func content_h() -> float:
	var last: TreeItem = null
	var n := 0
	var it := get_root().get_first_child() if get_root() != null else null
	while it != null:
		if it.visible:
			last = it
			n += 1
		it = it.get_next_visible(false)
	var sb := get_theme_stylebox("panel")
	var pad := 6.0 + (sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM) if sb != null else 0.0)
	var r := get_item_area_rect(last) if last != null else Rect2()
	if r.size.y > 0.0:   # laid out: the last shown row's bottom, unscrolled
		return r.end.y + get_scroll().y + pad
	return n * 24.0 + pad   # not laid out yet (the first frame): a row's height, generously


func _refresh_now() -> void:
	_pending = false
	m._browser_fit.call_deferred()
	if m == null or _scene_root == null:
		return
	for c in _scene_root.get_children():
		c.free()
	_scene_root.set_text(0, "Scene: %s  (%d clips)" % [m.S.name if m.S.name != "" else "unsaved", m.S.cards.size()])
	for i in m.S.cards.size():
		var it := create_item(_scene_root)
		it.set_text(0, "%d  %s" % [i + 1, m.S.cards[i]["name"]])
		it.set_metadata(0, {"card": i})
	# the set (SS5): one row per prop, the picked one in the accent colour
	for c in _set_root.get_children():
		c.free()
	_set_root.visible = not m.S.props.is_empty()
	_set_root.set_text(0, "Set  (%d)" % m.S.props.size())
	for i in m.S.props.size():
		var pr := create_item(_set_root)
		pr.set_text(0, m._prop_name(i))
		pr.set_metadata(0, {"prop": i})
		if i == m.sel_prop:
			pr.set_custom_color(0, Tok.c("accent"))
	for k in _psets:   # the scene's selection / keying sets, a row each
		for c in _psets[k].get_children():
			c.free()
		PartSets.of(m).fill(self, _psets[k], k)
	_fill_poses()
	_fill_outl()
	BodyFile.fill_browser(m, self, _bodies)   # G07 (scripts/body_file.gd)
	if m.ui_dummy != null:
		_dummy.set_text(0, "Target dummy: " + (m.ui_dummy.text.get_slice("\n", 0) if m.dummy_on else "off"))
	# TC5: with 2+ fighters the dummy's report is between them: the row says it, a row under it per contact (click: there)
	for c in _dummy.get_children():
		c.free()
	if m.ui_dummy != null and m._fighters_on():
		var ls: PackedStringArray = m.ui_dummy.text.split("\n")
		_dummy.set_text(0, "Hits: " + ls[0])
		for i in range(1, ls.size()):
			var hr := create_item(_dummy)
			hr.set_text(0, ls[i])
			if i - 1 < m.fighter_hits.size():
				hr.set_metadata(0, {"hit": i - 1})
				hr.set_tooltip_text(0, "click: the playhead to this contact")
	follow()


## light the selected part's row (unfold what holds it, scroll to it)
func follow() -> void:
	# follow() runs on every refresh (a hover, an edit, each playing frame): only a CHANGE of the picked part scrolls the
	# tree to its row. Scrolling to it on every refresh pushed a tree the user had scrolled down back up, again and again
	var picked_now: bool = m.sel != _followed
	_followed = m.sel
	_wep.visible = m.B.wep_on
	var wh: TreeItem = rows.get("bat_handle")   # the weapon's row: a Part weapon names itself (the other kinds keep "handle")
	if wh != null:
		var want := "handle (drag it to swing the weapon)"
		if PartWeapon.is_part(m.B.wep_kind):
			want = "%s: handle (drag it to swing the weapon)" % PartWeapon.name_of(m.B.wep_kind)
		if wh.get_text(0) != want:
			wh.set_text(0, want)
			wh.set_tooltip_text(0, want)
	_sync_buttons()
	_light(rows.get(m.hover_part) if m.hover_part != m.sel else null)
	var oid := _outl_selected_id()
	var orw := _outl_find(oid) if oid != "" else null
	if orw != null:   # L36: a prop or object picked: its Outliner row lights up (the view and the tree stay one selection)
		var q := orw.get_parent()
		while q != null:
			q.collapsed = false
			q = q.get_parent()
		if get_selected() != orw:
			_quiet = true
			orw.select(0)
			_quiet = false
		if picked_now or _followed_obj != oid:
			_scroll_if_hidden_o.call_deferred(orw)
		_followed_obj = oid
		return
	_followed_obj = ""
	var it: TreeItem = rows.get(m.sel)
	if it == null:   # nothing picked, or a part with no row
		deselect_all()
		return
	var p := it.get_parent()
	while p != null:
		p.collapsed = false
		p = p.get_parent()
	if get_selected() != it:
		_quiet = true
		it.select(0)
		_quiet = false
	# only when the row is OUT of sight (round 20, GATES AA2: follow runs on every refresh, every drag, and re-centred
	# the row each time, so the tree jumped back whenever the user had scrolled); then in the middle, so the folders
	# above it stay in sight. Deferred: a just-unfolded tree has no layout yet this frame
	if picked_now:
		_scroll_if_hidden.call_deferred(it)


var _followed_obj := ""


func _outl_selected_id() -> String:
	if m.sel_prop >= 0:
		return "prop:%d" % m.sel_prop
	if m.sel_obj != "" and not m.sel_obj.begins_with("prop:") and m.sel_obj_part == m.sel:
		return m.sel_obj
	return ""


func _outl_find(id: String) -> TreeItem:
	if _outl_root == null or not is_instance_valid(_outl_root):
		return null
	var stack: Array = [_outl_root]
	while not stack.is_empty():
		var it: TreeItem = stack.pop_back()
		var md = it.get_metadata(0)
		if md is Dictionary and md.get("onode", "") == id:
			return it
		for c in it.get_children():
			stack.append(c)
	return null


func _scroll_if_hidden_o(it: TreeItem) -> void:
	if it == null or not is_instance_valid(it):
		return
	var r := get_item_area_rect(it)
	if r.position.y < 0.0 or r.end.y > size.y or r.size.y <= 0.0:
		scroll_to_item(it, true)


## ---- OUTLINER (L36): filter toggles, search, rows by parent, an eye and a lock per row, drag a row onto another to parent it
func set_outl_filter(kind: String, on: bool) -> void:
	outl_kinds[kind] = on
	var b := _ol_bar.get_node_or_null("outl_f_" + kind) as Button if _ol_bar != null else null
	if b != null and b.button_pressed != on:
		b.set_pressed_no_signal(on)
	_fill_outl()


func set_outl_filter_all(on: bool) -> void:
	for k in Outliner.KINDS:
		outl_kinds[k] = on
		var b := _ol_bar.get_node_or_null("outl_f_" + k) as Button if _ol_bar != null else null
		if b != null:
			b.set_pressed_no_signal(on)
	_fill_outl()


func set_outl_query(q: String) -> void:
	outl_query = q
	if _ol_search != null and _ol_search.text != q:
		_ol_search.text = q
	_fill_outl()


func _fill_outl() -> void:
	if _outl_root == null or not is_instance_valid(_outl_root) or m == null:
		return
	var S: Scene = m.S
	var on := []
	for k in outl_kinds:
		if outl_kinds[k]:
			on.append(k)
	var shown: Array = Outliner.rows(S, on, outl_query)
	var sig := var_to_str([Outliner.objects(S), S.outl, shown, _ol_closed.keys()])
	if sig == _ol_sig:
		return
	_ol_sig = sig
	var kids := _outl_root.get_children()
	for k in range(2, kids.size()):
		kids[k].free()
	var ctx := {"made": {}, "names": {}, "shown": shown, "S": S}
	for o in Outliner.objects(S):
		ctx["names"][o["id"]] = o["name"]
	for id in shown:
		_ol_make(id, ctx)
	for id in ctx["made"]:
		if _ol_closed.has(id):
			(ctx["made"][id] as TreeItem).collapsed = true
	_followed_obj = ""
	_outl_root.set_text(0, "Outliner  (%d)" % shown.size())
	follow()


func _ol_make(id: String, ctx: Dictionary) -> TreeItem:
	var made: Dictionary = ctx["made"]
	if made.has(id):
		return made[id]
	var S: Scene = ctx["S"]
	var par: TreeItem = _outl_root
	var a := Outliner.parent_of(S, id)
	var n := 0
	while a != "" and n < 1000:   # the nearest ancestor that is listed
		if a in ctx["shown"]:
			par = _ol_make(a, ctx)
			break
		a = Outliner.parent_of(S, a)
		n += 1
	var it := create_item(par)
	made[id] = it
	var nm: String = ctx["names"][id]
	it.set_text(0, nm)
	it.set_metadata(0, {"onode": id})
	var hid_own: bool = S.outl.get("hide", {}).has(id)
	var hid: bool = Outliner.hidden(S, id)
	var lk: bool = Outliner.locked(S, id)
	it.add_button(0, Icons.small("eye_off" if hid else "eye"), 10)
	it.add_button(0, Icons.small("lock" if lk else "unlock"), 11)
	it.set_button_tooltip_text(0, 0, ("hidden%s: click to show it again" % ("" if hid_own else " by what it is under")) if hid else "shown: click to hide it (it is not drawn and a click goes through it)")
	it.set_button_tooltip_text(0, 1, "locked: click to free it" if lk else "free: click to lock it (a drag does not move it)")
	it.set_button_color(0, 0, Tok.dim(0.4) if hid else Tok.c("text"))
	it.set_button_color(0, 1, Tok.c("say") if lk else Tok.dim(0.4))
	if hid:
		it.set_custom_color(0, Tok.dim(0.4))
	it.set_tooltip_text(0, "%s (%s): drag it onto another row to parent it" % [nm, Outliner.kind_of(id)])
	return it


func _outl_button(it: TreeItem, id: int) -> void:
	var oid: String = (it.get_metadata(0) as Dictionary)["onode"]
	if id == 10:
		m._outl_hide(oid, not (m.S.outl.get("hide", {}) as Dictionary).has(oid))
	else:
		m._outl_lock(oid, not Outliner.locked(m.S, oid))


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("kine_outl")


func _drop_data(at: Vector2, data: Variant) -> void:
	if not (data is Dictionary) or not (data as Dictionary).has("kine_outl"):
		return
	var target := get_item_at_position(at)
	var parent := ""
	if target == null:
		return
	var md = target.get_metadata(0)
	if md is Dictionary and md.has("onode"):
		parent = md["onode"]
	elif target != _outl_root:
		return
	m._outl_reparent(String(data["kine_outl"]), parent)


func _scroll_if_hidden(it: TreeItem) -> void:
	if it == null or not rows.values().has(it):
		return
	var r := get_item_area_rect(it)   # already scrolled: in sight = inside 0..size.y
	if r.position.y < 0.0 or r.end.y > size.y or r.size.y <= 0.0:
		scroll_to_item(it, true)


## the theme changed: the folder rows take the new heading colour IN PLACE (round 20, GATES AA2: build() for this
## dropped the user's folds and scroll)
func recolor() -> void:
	var stack: Array = [get_root()]
	while stack.size() > 0:
		var it: TreeItem = stack.pop_back()
		if it == null:
			continue
		if it != get_root() and not it.is_selectable(0):
			it.set_custom_color(0, Tok.c("heading"))
		for c in it.get_children():
			stack.append(c)


## each eye / lock shows its state; a folder's: hidden / locked when ALL its parts are
func _sync_buttons() -> void:
	for j in rows:
		var it: TreeItem = rows[j]
		if it.get_button_count(0) == 2:
			_show_state(it, [j])
	for f in folders:
		_show_state(f[0], f[1])


func _show_state(it: TreeItem, js: Array) -> void:
	var hid: bool = js.all(func(j): return m.hidden_parts.has(j))
	var lk: bool = js.all(func(j): return m.locked_parts.has(j))
	var key := [hid, lk, Tok.c("text")]
	if it.has_meta("eye_lock") and it.get_meta("eye_lock") == key:
		return   # unchanged: re-setting a button mid-click made the Tree drop the click
	it.set_meta("eye_lock", key)
	var what: String = m.nice(js[0]) if js.size() == 1 else "all %d parts in %s" % [js.size(), it.get_text(0)]
	it.set_button(0, 0, Icons.small("eye_off" if hid else "eye"))
	it.set_button(0, 1, Icons.small("lock" if lk else "unlock"))
	it.set_button_tooltip_text(0, 0, ("hidden: click to show %s again" if hid else "shown: click to hide %s (a click in the view goes through it)") % what)
	it.set_button_tooltip_text(0, 1, ("locked: click to free %s" if lk else "free: click to lock %s (it keeps its pose)") % what)
	it.set_button_color(0, 0, Tok.dim(0.4) if hid else Tok.c("text"))   # off = dimmed toward the panel (readable floor)
	it.set_button_color(0, 1, Tok.c("say") if lk else Tok.dim(0.4))


func _parts_of(it: TreeItem) -> Array:
	var md = it.get_metadata(0)
	if md is Dictionary and md.has("part"):
		return [md["part"]]
	for f in folders:
		if f[0] == it:
			return f[1]
	return []


## the eye (id 0) or the lock (id 1) on a row: a folder's acts on every part under it. Taken from the press itself in
## _motion, not Tree's button_clicked: the Tree re-checks the press against the OS mouse, so a pushed click (every
## test) was dropped there; the press is accepted, so the Tree's own path never toggles it a second time
func _button(it: TreeItem, id: int) -> void:
	if id >= 10:
		_outl_button(it, id)
		return
	var js := _parts_of(it)
	if js.is_empty():
		return
	if id == 0:
		m._set_hidden(js, not js.all(func(j): return m.hidden_parts.has(j)))
	else:
		m._set_locked(js, not js.all(func(j): return m.locked_parts.has(j)))


## HOVER IN SYNC (round 30, GATES KK2, UPGRADES #35): the row of the part the view's mouse is on is lit; the mouse on
## a part's row lights that part in the view (main's hover_part) and names it on the bar. Leaving the Browser clears it
## (_left): onto the view its motion re-picks anyway, but straight onto the right panel nothing else would (main's
## _process clean-up only sees panels that stop the mouse; the right panel's body lets it pass)
func _light(it: TreeItem) -> void:
	if _lit == it:
		return
	if _lit != null and rows.values().has(_lit):
		_lit.clear_custom_bg_color(0)
	_lit = it
	if it != null:
		it.set_custom_bg_color(0, Tok.c("btn_hover"))


func _motion(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT and (ev as InputEventMouseButton).pressed:
		var r := get_item_at_position((ev as InputEventMouseButton).position)
		if r != null and r.get_metadata(0) is Dictionary:
			accept_event()
			m._row_menu(r.get_metadata(0), get_screen_transform() * (ev as InputEventMouseButton).position)
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var at := (ev as InputEventMouseButton).position
		var id := get_button_id_at_position(at)
		var row := get_item_at_position(at)
		# R8: a pose row takes the body on the RELEASE (a press that turns into a drag to the card strip must not pose the body)
		_down = (ev as InputEventMouseButton).pressed
		if not _down and _pose_pending >= 0:
			var pi := _pose_pending
			_pose_pending = -1
			m._pose_apply(pi)
		if id >= 0 and row != null:
			accept_event()
			if (ev as InputEventMouseButton).pressed:
				_button(row, id)
		return
	if not ev is InputEventMouseMotion:
		return
	var it := get_item_at_position((ev as InputEventMouseMotion).position)
	var md = it.get_metadata(0) if it != null else null
	var j: String = md["part"] if md is Dictionary and md.has("part") else ""
	if j != m.hover_part:
		_hover_mine = j != ""
		m.hover_part = j
		m._refresh()


## R8: a pose row can be dragged onto the card strip (main.gd _pose_drop)
func _get_drag_data(at: Vector2) -> Variant:
	_pose_pending = -1
	var it := get_item_at_position(at)
	if it != null and it.get_metadata(0) is Dictionary and (it.get_metadata(0) as Dictionary).has("onode"):
		var ol := Label.new()
		ol.text = "  " + it.get_text(0)
		ol.add_theme_font_size_override("font_size", 13)
		set_drag_preview(ol)
		return {"kine_outl": it.get_metadata(0)["onode"]}
	if it == null or m.ui_poses == null:
		return null
	var md = it.get_metadata(0)
	if not (md is Dictionary) or not md.has("pose"):
		return null
	var path: String = m.ui_poses.get_item_metadata(int(md["pose"]))
	var l := Label.new()
	l.text = "  " + it.get_text(0)
	l.add_theme_font_size_override("font_size", 13)
	set_drag_preview(l)
	return {"kine_pose": path, "name": it.get_text(0)}


func _left() -> void:
	if _hover_mine:
		_hover_mine = false
		m.hover_part = ""
		m._refresh()


func _chosen() -> void:
	if _quiet:
		return
	var md = get_selected().get_metadata(0)
	if md == null:
		return
	if md.has("onode"):
		m._outl_select(md["onode"])
		return
	if md.has("part"):
		m.sel = md["part"]
		m.playing = false
		m._refresh()
		m._say("%s selected (from the browser).  Drag in the view, or use the sliders on the right" % m.nice(md["part"]))
	elif md.has("card"):
		m._timeline_pick(md["card"])
	elif md.has("prop"):
		m._prop_select(md["prop"])
	elif md.has("pose"):
		if _down:
			_pose_pending = int(md["pose"])
		else:
			m._pose_apply(md["pose"])
	elif md.has("hit"):
		m._goto_hit(md["hit"])
	elif md.has("pset"):
		PartSets.of(m).pick(md["kind"], md["pset"])
	elif md.has("kbody"):
		BodyFile.open_cmd(m, md["kbody"])


## R21: the Poses rows. No words typed = every pose in the pose list's order. Words typed = only the poses whose name or
## auto tags match (PoseTags.Index.search), best first, with the matching tags as chips on the row; the folders open
func _fill_poses() -> void:
	for f in [_lib, _mine]:
		for c in f.get_children():
			c.free()
	if m.ui_poses == null:
		return
	var q := pose_query.strip_edges()
	var order := []   # [pose index, matching chips]
	if q == "":
		for i in m.ui_poses.item_count:
			order.append([i, []])
	else:
		var sig := ""
		var items := []
		for i in m.ui_poses.item_count:
			var path: String = m.ui_poses.get_item_metadata(i)
			sig += path + "|"
			items.append({"name": m.ui_poses.get_item_text(i).get_slice("   ", 0), "path": path})
		if pose_index == null or sig != _pose_sig:   # parsed once per library change; a keystroke only scores
			pose_index = PoseTags.Index.new()
			pose_index.cache_path = pose_cache_path
			pose_index.build(items)
			_pose_sig = sig
		for r in pose_index.search(q):
			order.append([r["i"], r["chips"]])
	for o in order:
		var i: int = o[0]
		var t: String = m.ui_poses.get_item_text(i)
		var it := create_item(_mine if t.ends_with("(yours)") else _lib)
		it.set_text(0, t.get_slice("   ", 0))
		it.set_tooltip_text(0, "click: the body takes this pose; right-click: CLIP / Rename / Delete")
		it.set_metadata(0, {"pose": i})
		if not o[1].is_empty():
			it.set_meta("chips", o[1])
			it.set_tooltip_text(0, "tags: " + ", ".join(o[1]) + "
click: the body takes this pose; right-click: CLIP / Rename / Delete")
	var tail := "" if q == "" else " matching"
	_lib.set_text(0, "Library  (%d%s)" % [_lib.get_child_count(), tail])
	_mine.set_text(0, "Mine  (%d%s)" % [_mine.get_child_count(), tail])
	if q != "":
		_lib.collapsed = false
		_mine.collapsed = false


## the words typed in the search box (live: every keystroke)
func set_pose_query(q: String) -> void:
	pose_query = q
	_fill_poses()
	m._browser_fit.call_deferred()


## the matching tags as small chips at the right end of each pose row. The Tree's own custom-draw hook never ran for these
## rows (measured: 0 calls), so a transparent layer over the Tree draws them from the rows' rectangles
class ChipLayer extends Control:
	var t: Browser

	func _draw() -> void:
		if t == null or t.pose_query.strip_edges() == "":
			return
		var font := get_theme_default_font()
		var fs := 10
		var bg := Tok.c("accent")
		bg.a = 0.45
		for f in [t._lib, t._mine]:
			if not f.is_visible_in_tree():
				continue
			for it in f.get_children():
				if not it.has_meta("chips"):
					continue
				var rect := t.get_item_area_rect(it, 0)
				if rect.size.y <= 0.0 or rect.position.y < 0.0 or rect.end.y > t.size.y:
					continue
				var chips: Array = it.get_meta("chips")
				var x := rect.end.x - 4.0
				for k in range(chips.size() - 1, -1, -1):
					var w := font.get_string_size(chips[k], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0
					x -= w
					var r := Rect2(x, rect.position.y + 3.0, w, rect.size.y - 6.0)
					draw_rect(r, bg)
					draw_string(font, Vector2(x + 4.0, r.position.y + r.size.y * 0.5 + fs * 0.36), chips[k], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Tok.c("text"))
					x -= 3.0


## a control rides on its row (shown only while that row is in sight)
func _overlay(c: Control, row: TreeItem, pad: Vector2) -> void:
	if c == null:
		return
	var show := row != null and is_instance_valid(row) and row.is_visible_in_tree()
	var r := get_item_area_rect(row, 0) if show else Rect2()
	show = show and r.size.y > 0.0 and r.position.y >= 0.0 and r.end.y <= size.y
	if c.visible != show:
		c.visible = show
	if show:
		var want := Rect2(r.position + pad, Vector2(maxf(40.0, r.size.x - 6.0), r.size.y - 2.0))
		if c.position != want.position or c.size != want.size:
			c.position = want.position
			c.size = want.size


## the search box rides on its row (shown only while that row is in sight)
func _process(_dt: float) -> void:
	_overlay(_ol_search, _ol_search_row, Vector2(2, 1))
	_overlay(_ol_bar, _ol_bar_row, Vector2(2, 1))
	if _search == null:
		return
	if pose_query != "":
		_chips.queue_redraw()   # the rows scroll and fold: the chips follow them every frame while a search is on
	var show := _search_row != null and is_instance_valid(_search_row) and _search_row.is_visible_in_tree()
	var r := get_item_area_rect(_search_row, 0) if show else Rect2()
	show = show and r.size.y > 0.0 and r.position.y >= 0.0 and r.end.y <= size.y
	if _search.visible != show:
		_search.visible = show
	if show:
		var want := Rect2(r.position + Vector2(2, 1), Vector2(maxf(40.0, r.size.x - 6.0), r.size.y - 2.0))
		if _search.position != want.position or _search.size != want.size:
			_search.position = want.position
			_search.size = want.size
