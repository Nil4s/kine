## SELECTION SETS AND KEYING SETS (docs/GAP_ANALYSIS.md rows 9 and 6; docs/research/SETS.md).
## A scene can hold named groups of body parts:
##   selection sets: a name -> parts; clicking one selects exactly those parts (the first is the one the panel shows).
##   keying sets:    a name -> parts; with one ACTIVE, K keys every part in it at the playhead as ONE undo step.
##                   With none active, K keys the one picked part, as it always has.
## In the scene as Scene.sets = {"select": {name: [parts]}, "keying": {name: [parts]}, "active": name}; every sub-key
## is written only when it has something, and a scene with no set has no "sets" key at all (it saves as before).
## The data functions are static; the app's side (commands, the browser's menu, the rename box) is one PartSets per
## poser: PartSets.of(main).
class_name PartSets
extends RefCounted

const KINDS := ["select", "keying"]
const WORD := {"select": "selection set", "keying": "keying set"}

var m: Node
var cur := {}   # the picked set {"kind", "name"} (a view choice: never saved, never an undo step)
var _dlg: ConfirmationDialog
var _edit: LineEdit


# ---------------------------------------------------------------- data (static)

## the parts a set may hold: body parts and fingers (the weapon has its own controls)
static func part_ok(j: String) -> bool:
	return j in Body.BODY or j in Body.FINGERS


## a file's / a caller's sets made safe: unknown parts dropped, duplicates dropped, empty sets dropped, an active name
## that is not a keying set dropped. Returns {} when there is nothing (so the scene writes no "sets" key)
static func clean(d) -> Dictionary:
	var out := {}
	if not d is Dictionary:
		return out
	for k in KINDS:
		var src = d.get(k, {})
		if not src is Dictionary:
			continue
		var one := {}
		for n in src:
			var nm := String(n).strip_edges()
			if nm == "" or not src[n] is Array:
				continue
			var ps := []
			for j in src[n]:
				if part_ok(String(j)) and not ps.has(String(j)):
					ps.append(String(j))
			if not ps.is_empty():
				one[nm] = ps
		if not one.is_empty():
			out[k] = one
	var act := String(d.get("active", ""))
	if act != "" and out.get("keying", {}).has(act):
		out["active"] = act
	return out


static func to_file(s: Dictionary) -> Dictionary:
	return clean(s).duplicate(true)


static func from_file(d) -> Dictionary:
	return clean(d)


## a set's name on the other side: "arm_l" <-> "arm_r"; any other name is its own twin
static func twin_name(n: String) -> String:
	if n.ends_with("_l"):
		return n.left(n.length() - 2) + "_r"
	if n.ends_with("_r"):
		return n.left(n.length() - 2) + "_l"
	return n


## MIRROR (Scene.MIRROR_SCENE "sets"): every part to its twin (hand_l <-> hand_r, the middle stays), and a set named
## "_l" / "_r" takes its twin's name (the swap is one-to-one, so "arm_l" and "arm_r" trade places, never collide)
static func mirror_file(d) -> Dictionary:
	var s := clean(d)
	var out := {}
	for k in KINDS:
		if not s.has(k):
			continue
		var one := {}
		for n in s[k]:
			one[twin_name(n)] = (s[k][n] as Array).map(func(j): return Body.twin(j))
		out[k] = one
	if s.has("active"):
		out["active"] = twin_name(s["active"])
	return clean(out)


## a free name: "base", else "base 2", "base 3" ... (a suffix _l / _r stays last, so mirror still reads it)
static func free_name(s: Dictionary, kind: String, base: String) -> String:
	var have: Dictionary = s.get(kind, {})
	if not have.has(base):
		return base
	var side := ""
	var stem := base
	if base.ends_with("_l") or base.ends_with("_r"):
		side = base.right(2)
		stem = base.left(base.length() - 2)
	var k := 2
	while have.has("%s %d%s" % [stem, k, side]):
		k += 1
	return "%s %d%s" % [stem, k, side]


## the name a new set gets: "set 1" ("keys 1"), with "_l" / "_r" when every part is on that side (mirror reads it)
static func auto_name(s: Dictionary, kind: String, parts: Array) -> String:
	var base := "set" if kind == "select" else "keys"
	var n := 1
	while s.get(kind, {}).has("%s %d" % [base, n]) or s.get(kind, {}).has("%s %d_l" % [base, n]) or s.get(kind, {}).has("%s %d_r" % [base, n]):
		n += 1
	var side := ""
	if not parts.is_empty() and parts.all(func(j): return String(j).ends_with("_l")):
		side = "_l"
	elif not parts.is_empty() and parts.all(func(j): return String(j).ends_with("_r")):
		side = "_r"
	return "%s %d%s" % [base, n, side]


## the parts a keying set keys with K: body parts only (a part key holds a body joint's 3 angles; fingers have shapes)
static func keyable(parts: Array) -> Array:
	return parts.filter(func(j): return j in Body.BODY)


# ---------------------------------------------------------------- the app's side

static func of(main: Node) -> PartSets:
	if not main.has_meta("part_sets"):
		var p := PartSets.new()
		p.m = main
		main.set_meta("part_sets", p)
	return main.get_meta("part_sets")


func _sets() -> Dictionary:
	return m.S.sets


## the selected parts that can go in a set (the weapon left out), the shown one first
func picked_parts() -> Array:
	var out := []
	for j in m.group():
		if part_ok(j) and not out.has(j):
			out.append(j)
	return out


func cur_ok() -> bool:
	return not cur.is_empty() and _sets().get(cur["kind"], {}).has(cur["name"])


func parts_of(kind: String, nm: String) -> Array:
	return (_sets().get(kind, {}).get(nm, []) as Array).duplicate()


func active() -> String:
	return String(_sets().get("active", ""))


## every set edit: one undo step, the scene's sets cleaned after, the browser shown again
func _edit_sets(f: Callable) -> void:
	m._do(func():
		var s: Dictionary = m.S.sets.duplicate(true)
		f.call(s)
		m.S.sets = clean(s))
	if not cur_ok():
		cur = {}
	if m.ui_browser != null:
		m.ui_browser.refresh()


func commands(add: Callable) -> void:
	add.call("Selection set: new from the selected parts", "", make.bind("select"), "selection set group quick select save named bone collection maya blender",
		true, "a named selection set of the parts selected now (Ctrl+click adds parts); it is listed under Sets in the browser and saved with the scene")
	add.call("Keying set: new from the selected parts", "", make.bind("keying"), "keying set character set key together channels group blender maya",
		true, "a named keying set of the parts selected now, made the active one: K then keys all of them at the playhead in one go")
	add.call("Sets: select the picked set", "", select_cur, "selection set select group pick quick select",
		false, "select exactly the parts of the set picked in the browser's Sets list (a drag on any of them turns them all)")
	add.call("Sets: add the selected parts to the picked set", "", add_parts, "selection set keying set add assign include member",
		true, "the parts selected now join the set picked in the browser's Sets list")
	add.call("Sets: remove the selected parts from the picked set", "", remove_parts, "selection set keying set remove unassign exclude member",
		true, "the parts selected now leave the set picked in the browser's Sets list (an emptied set is deleted)")
	add.call("Sets: rename the picked set", "", ask_rename, "selection set keying set rename name label",
		false, "a box to type the picked set's new name (OK renames it: one undo step)")
	add.call("Sets: delete the picked set", "", delete_cur, "selection set keying set delete remove clear",
		true, "the set picked in the browser's Sets list is deleted (its parts are not touched)")
	add.call("Sets: mirror the picked set to the other side", "", mirror_cur, "selection set keying set mirror left right other side twin flip",
		true, "a twin of the picked set with every part on the other side; a set named \"_l\" gets the \"_r\" name (it replaces a set of that name)")
	add.call("Keying set: use the picked set for K", "", use_cur, "keying set active current key together character set",
		true, "the keying set picked in the browser becomes the active one: K keys every body part in it at the playhead")
	add.call("Keying set: none (K keys the one part)", "", use_none, "keying set active none off single one part",
		true, "no active keying set: K keys only the picked part, as before")


## a new set from the selection (a keying set becomes the active one, as Blender's Add Keying Set does)
func make(kind: String) -> void:
	var ps := picked_parts()
	if ps.is_empty():
		m._say("a %s holds body parts: click a part first (Ctrl+click adds more)" % WORD[kind])
		return
	var nm := auto_name(_sets(), kind, ps)
	_edit_sets(func(s):
		if not s.has(kind):
			s[kind] = {}
		s[kind][nm] = ps
		if kind == "keying":
			s["active"] = nm)
	cur = {"kind": kind, "name": nm}
	if m.ui_browser != null:
		m.ui_browser.refresh()
	m._say("%s '%s': %d part%s (%s)%s  (right-click it under Sets to rename; Ctrl+Z takes it back)" % [WORD[kind], nm, ps.size(), "" if ps.size() == 1 else "s",
		", ".join(ps.map(func(j): return m.nice(j))), "; K now keys all of them" if kind == "keying" else ""])


## a browser row was clicked: that set is picked and its parts selected
func pick(kind: String, nm: String) -> void:
	cur = {"kind": kind, "name": nm}
	select_cur()


func select_cur() -> void:
	if not cur_ok():
		m._say("pick a set first: click one under Sets in the browser (or make one from the selected parts)")
		return
	var ps := parts_of(cur["kind"], cur["name"])
	m._select_set(ps)
	if m.ui_browser != null:
		m.ui_browser.refresh()
	m._say_plain("%s '%s': %d part%s selected (%s); drag any of them to turn them all" % [WORD[cur["kind"]], cur["name"], ps.size(), "" if ps.size() == 1 else "s",
		", ".join(ps.map(func(j): return m.nice(j)))])


func add_parts() -> void:
	if not cur_ok():
		m._say("pick a set first: click one under Sets in the browser, then select the parts to add")
		return
	var have := parts_of(cur["kind"], cur["name"])
	var adds := picked_parts().filter(func(j): return not have.has(j))
	if adds.is_empty():
		m._say("every selected part is already in '%s': select other parts (Ctrl+click adds) and try again" % cur["name"])
		return
	var c := cur.duplicate()
	_edit_sets(func(s): s[c["kind"]][c["name"]] = have + adds)
	m._say("'%s' now holds %d parts (added %s)" % [c["name"], have.size() + adds.size(), ", ".join(adds.map(func(j): return m.nice(j)))])


func remove_parts() -> void:
	if not cur_ok():
		m._say("pick a set first: click one under Sets in the browser, then select the parts to take out")
		return
	var have := parts_of(cur["kind"], cur["name"])
	var out := picked_parts().filter(func(j): return have.has(j))
	if out.is_empty():
		m._say("none of the selected parts is in '%s': select one of its parts and try again" % cur["name"])
		return
	var c := cur.duplicate()
	var left := have.filter(func(j): return not out.has(j))
	_edit_sets(func(s): s[c["kind"]][c["name"]] = left)   # an emptied set is dropped by clean()
	m._say("'%s' now holds %d part%s (took out %s)" % [c["name"], left.size(), "" if left.size() == 1 else "s", ", ".join(out.map(func(j): return m.nice(j)))])


## rename: one undo step; the active keying set keeps being active under its new name
func rename(kind: String, old: String, nm: String) -> bool:
	nm = nm.strip_edges()
	if not _sets().get(kind, {}).has(old):
		m._say("there is no %s '%s': pick one under Sets in the browser" % [WORD[kind], old])
		return false
	if nm == "" or nm == old:
		m._say("type a new name for '%s' and press OK" % old)
		return false
	if _sets()[kind].has(nm):
		m._say("there is already a %s '%s': type another name" % [WORD[kind], nm])
		return false
	_edit_sets(func(s):
		var one := {}
		for k in s[kind]:   # the same place in the list
			one[nm if k == old else k] = s[kind][k]
		s[kind] = one
		if kind == "keying" and String(s.get("active", "")) == old:
			s["active"] = nm)
	cur = {"kind": kind, "name": nm}
	if m.ui_browser != null:
		m.ui_browser.refresh()
	m._say("renamed '%s' to '%s'" % [old, nm])
	return true


func ask_rename() -> void:
	if not cur_ok():
		m._say("pick a set first: click one under Sets in the browser, then rename it")
		return
	if _dlg == null:
		_dlg = ConfirmationDialog.new()
		_dlg.name = "sets_rename"
		_dlg.title = "Rename the set"
		_dlg.ok_button_text = "Rename"
		_edit = LineEdit.new()
		_edit.name = "sets_rename_name"
		_edit.custom_minimum_size = Vector2(260, 0)
		_dlg.add_child(_edit)
		_dlg.register_text_enter(_edit)
		_dlg.confirmed.connect(func(): rename(_dlg.get_meta("kind"), _dlg.get_meta("old"), _edit.text))
		m.add_child(_dlg)
	_dlg.set_meta("kind", cur["kind"])
	_dlg.set_meta("old", cur["name"])
	_edit.text = cur["name"]
	_dlg.popup_centered()
	_edit.grab_focus.call_deferred()
	_edit.select_all.call_deferred()


func delete_cur() -> void:
	if not cur_ok():
		m._say("pick a set first: click one under Sets in the browser, then delete it")
		return
	var c := cur.duplicate()
	_edit_sets(func(s):
		s[c["kind"]].erase(c["name"])
		if c["kind"] == "keying" and String(s.get("active", "")) == c["name"]:
			s.erase("active"))
	cur = {}
	m._say("deleted the %s '%s' (its parts are as they were; Ctrl+Z brings it back)" % [WORD[c["kind"]], c["name"]])


func mirror_cur() -> void:
	if not cur_ok():
		m._say("pick a set first: click one under Sets in the browser, then mirror it")
		return
	var c := cur.duplicate()
	var ps := parts_of(c["kind"], c["name"])
	var tw := ps.map(func(j): return Body.twin(j))
	if tw == ps:
		m._say("'%s' has no side (every part is in the middle): pick a set with left or right parts" % c["name"])
		return
	var nm := twin_name(c["name"])
	if nm == c["name"]:
		nm = free_name(_sets(), c["kind"], c["name"] + " mirrored")
	_edit_sets(func(s): s[c["kind"]][nm] = tw)
	cur = {"kind": c["kind"], "name": nm}
	if m.ui_browser != null:
		m.ui_browser.refresh()
	m._say("'%s' made from '%s' with every part on the other side" % [nm, c["name"]])


func use_cur() -> void:
	if not cur_ok() or cur["kind"] != "keying":
		m._say("pick a keying set first: click one under Sets > Keying sets in the browser (or make one from the selected parts)")
		return
	var nm: String = cur["name"]
	if active() == nm:
		m._say("'%s' is already the active keying set: press K to key its parts" % nm)
		return
	_edit_sets(func(s): s["active"] = nm)
	m._say("K now keys the keying set '%s' (%d parts) at the playhead" % [nm, keyable(parts_of("keying", nm)).size()])


func use_none() -> void:
	if active() == "":
		m._say("no keying set is active already: K keys the picked part (use a keying set to key several)")
		return
	_edit_sets(func(s): s.erase("active"))
	m._say("no active keying set: K keys the picked part only")


## K with an active keying set: every body part in it keyed at the playhead (their 3 angles as the body shows them),
## ONE undo step. false = no active set (the caller keys the one part, as before)
func key_active() -> bool:
	var nm := active()
	if nm == "":
		return false
	var ps := keyable(parts_of("keying", nm))
	if m.S.cards.is_empty():
		m._say("K keys the keying set '%s' at the playhead: open a scene with cards first" % nm)
		return true
	if ps.is_empty():
		m._say("the keying set '%s' has no body part to key: add one to it (fingers are keyed by their shapes)" % nm)
		return true
	var t := clampf(float(m.playhead), 0.0, float(m.S.length()))
	m._do(func():
		for j in ps:
			PartKeys.put(m.S.part_keys, j, t, m.B.ang[j]))
	m._say("keyed the keying set '%s' at %.2f s: %d parts (%s)  (Ctrl+Z takes all of them back)" % [nm, t, ps.size(), ", ".join(ps.map(func(j): return m.nice(j)))])
	return true


## the browser row's right-click menu: [label, callable]
func menu(md: Dictionary) -> Array:
	if md.has("pset"):
		var kind: String = md["kind"]
		var nm: String = md["pset"]
		var items := [["Select its parts", pick.bind(kind, nm)],
			["Add the selected parts", func(): cur = {"kind": kind, "name": nm}; add_parts()],
			["Remove the selected parts", func(): cur = {"kind": kind, "name": nm}; remove_parts()],
			["Rename...", func(): cur = {"kind": kind, "name": nm}; ask_rename()],
			["Mirror (_l <-> _r)", func(): cur = {"kind": kind, "name": nm}; mirror_cur()],
			["Delete", func(): cur = {"kind": kind, "name": nm}; delete_cur()]]
		if kind == "keying":
			items.insert(1, ["Don't use for K" if active() == nm else "Use for K (active keying set)",
				use_none if active() == nm else func(): cur = {"kind": kind, "name": nm}; use_cur()])
		return items
	var k := "keying" if String(md.get("menu", "")) == "psets_keying" else "select"
	var out := [["New %s from the selected parts" % WORD[k], make.bind(k)]]
	if k == "keying" and active() != "":
		out.append(["None active (K keys the one part)", use_none])
	return out


## the browser's Sets rows (browser.gd builds the two folders; this fills them)
func fill(tree: Tree, folder: TreeItem, kind: String) -> void:
	var s: Dictionary = _sets().get(kind, {})
	folder.set_text(0, "%s  (%d)" % ["Selection sets" if kind == "select" else "Keying sets", s.size()])
	for nm in s:
		var it := tree.create_item(folder)
		var on: bool = kind == "keying" and active() == nm
		it.set_text(0, "%s%s  (%d)" % [nm, "   K" if on else "", (s[nm] as Array).size()])
		it.set_metadata(0, {"pset": nm, "kind": kind})
		it.set_tooltip_text(0, "%s: %s\nclick: select these parts; right-click: add / remove / rename / mirror / delete%s" % [nm,
			", ".join((s[nm] as Array).map(func(j): return m.nice(j))), ("\nK keys these (the active keying set)" if on else "\nright-click: Use for K") if kind == "keying" else ""])
		if not cur.is_empty() and cur["kind"] == kind and cur["name"] == nm:
			it.set_custom_color(0, Tok.c("accent"))
		elif on:
			it.set_custom_color(0, Tok.c("say"))
