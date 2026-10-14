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
var _wep: TreeItem
var _quiet := false
var _pending := false   # a clip-row rebuild is queued for the next frame   # true while the tree follows the view (a selection made here must not loop back)


func _ready() -> void:
	hide_root = true
	focus_mode = Control.FOCUS_NONE
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_font_size_override("font_size", 15)
	item_selected.connect(_chosen)
	build()


func _part(parent: TreeItem, j: String, label := "") -> TreeItem:
	var it := create_item(parent)
	it.set_text(0, label if label != "" else m.nice(j))
	it.set_metadata(0, {"part": j})
	rows[j] = it
	return it


func _folder(parent: TreeItem, t: String, folded := false) -> TreeItem:
	var it := create_item(parent)
	it.set_text(0, t)
	it.set_selectable(0, false)
	it.set_custom_color(0, Color(0.6, 0.78, 1.0))
	it.collapsed = folded
	return it


func build() -> void:
	clear()
	rows = {}
	var root := create_item()
	var body := _folder(root, "Body")
	for g in GROUPS:
		var gi := _folder(body, g[0])
		for j in g[1]:
			_part(gi, j)
		if g.size() > 2:   # an arm: its fingers, folded, one row per joint
			var fi := _folder(gi, "fingers", true)
			for f in FINGER_NAMES:
				var ff := _folder(fi, f, true)
				for k in 3:
					# "index, middle joint": a row must say which finger even when its folders have scrolled away
					_part(ff, "%s_0%d_%s" % [f, k + 1, g[2]], "%s, %s joint" % [f, ["base", "middle", "tip"][k]])
	_wep = _folder(root, "Weapon")
	_part(_wep, "bat_handle", "handle (drag it to swing the weapon)")
	_scene_root = _folder(root, "Scene")
	refresh()


## the parts of the tree that change: the weapon row (only with a weapon), the scene's clips, the selection.
## Always on the NEXT frame: a click on a clip row picks the card, which rebuilds the cards, which lands here; freeing
## that row while the Tree is still handling the click on it crashed Godot (illegal instruction, browser_test)
func refresh() -> void:
	if not _pending:
		_pending = true
		_refresh_now.call_deferred()


func _refresh_now() -> void:
	_pending = false
	if m == null or _scene_root == null:
		return
	for c in _scene_root.get_children():
		c.free()
	_scene_root.set_text(0, "Scene: %s  (%d clips)" % [m.S.name if m.S.name != "" else "unsaved", m.S.cards.size()])
	for i in m.S.cards.size():
		var it := create_item(_scene_root)
		it.set_text(0, "%d  %s" % [i + 1, m.S.cards[i]["name"]])
		it.set_metadata(0, {"card": i})
	follow()


## light the selected part's row (unfold what holds it, scroll to it)
func follow() -> void:
	_wep.visible = m.B.wep_on
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
	# in the middle, so the folders above it stay in sight; deferred: a just-unfolded tree has no layout yet this frame
	scroll_to_item.call_deferred(it, true)


func _chosen() -> void:
	if _quiet:
		return
	var md = get_selected().get_metadata(0)
	if md == null:
		return
	if md.has("part"):
		m.sel = md["part"]
		m.playing = false
		m._refresh()
		m._say("%s selected (from the browser).  Drag in the view, or use the sliders on the right" % m.nice(md["part"]))
	elif md.has("card"):
		m._timeline_pick(md["card"])
