class_name PageTour
extends Onboarding
## PAGE TOUR (docs/ROADMAP_400.md P01): the first time a page of the mesh side is opened (BODY, and the greyed MODEL /
## SCULPT / SURFACE), a 5-step tour points at that page's real controls, one callout and one arrow at a time. It is the
## first-launch guide's machinery (scripts/onboarding.gd: the callout beside its target, inside the window, never over
## it), moved on by Next instead of by an action: a page tour shows, it does not test. A greyed page's steps tell what
## already works for it, in P11's words (main.PAGE_SOON_WHY); its search step lists the commands of its prefix that exist.
## Seen = pagetour/<PAGE> = true in the settings file, written when the tour starts (a page is toured once); "Page tour"
## in the search box plays the tour of the page you are on (BODY when on a page without one) whenever asked.
## A test never gets one by itself: auto is false until main says this is a real launch (or the test sets it).

const SEC := "pagetour"
const TOURED := ["BODY", "MODEL", "SCULPT", "SURFACE"]
## per page: [title, text, target]; a target is a node name under the window (a | b = both, merged), or one of
## "page:<PAGE>" (that page's button on the page bar), "status" (the status line), "search" (the Search button), "undo"
const TOUR := {
	"BODY": [
		["Who you are posing", "The readout: this person's stature and mass, as ANSUR II percentiles.", "body_readout"],
		["Woman to man", "The survey sample the percentiles are read from: 0 = ANSUR II women, 100 = men.", "sl_blend"],
		["Seven proportions", "Stature, mass and the limbs, each a percentile. One drag = one undo step.", "sliders"],
		["Quick bodies", "5th, 50th or 95th: stature and mass at once; the proportions stay.", "quick_5|quick_95"],
		["Keep a character", "Name this person and Save: a character for any scene (never written into data).", "char_name|char_save"],
	],
	"MODEL": [
		["MODEL is coming", "Greyed, never dead: click it any time for what works and what is next.", "page:MODEL"],
		["Why it is greyed", "", "status"],
		["What works now", "", "search"],
		["The test cube", "Search, Model: edit a test cube: a cube on the stage. 1 / 2 / 3 vertex / edge / face, B box, L lasso, X x-ray.", "search"],
		["Mesh undo", "Every mesh step is one undo step, the same Undo as the body and the cards.", "undo"],
	],
	"SCULPT": [
		["SCULPT is coming", "Greyed, never dead: click it any time for what works and what is next.", "page:SCULPT"],
		["Why it is greyed", "", "status"],
		["What works now", "", "search"],
		["Shape the body now", "Until the brushes come, the BODY page shapes the person: ANSUR II sliders, no mesh needed.", "page:BODY"],
		["Then the mesh", "Sculpting comes after the MODEL tools: the mesh core is in, its brushes are next.", "page:MODEL"],
	],
	"SURFACE": [
		["SURFACE is coming", "Greyed, never dead: click it any time for what works and what is next.", "page:SURFACE"],
		["Why it is greyed", "", "status"],
		["What works now", "", "search"],
		["Edit the mesh first", "UVs and materials need a mesh you can edit: the MODEL page comes first.", "page:MODEL"],
		["Out to a renderer", "Meanwhile DELIVER exports the animation (FBX, glTF) to a tool that paints and renders.", "page:DELIVER"],
	],
}

var page := ""        # the page being toured ("" = none)
var auto := false     # main: a real launch (a test turns it on itself)
var _next: Button
var _changing := false


static func seen(cf: ConfigFile, p: String) -> bool:
	return cf.get_value(SEC, p, false) == true


static func steps_of(p: String) -> Array:
	return TOUR.get(p, [])


func build(root: Control) -> void:
	super.build(root)
	card.name = "pagetour_card"
	arrow.name = "pagetour_arrow"
	var skip: Button = card.find_child("onboard_skip", true, false)
	skip.name = "pagetour_skip"
	skip.tooltip_text = "close this page's tour (Search: Page tour plays it again)"
	_next = Button.new()
	_next.name = "pagetour_next"
	_next.text = "Next"
	_next.focus_mode = Control.FOCUS_NONE
	_next.pressed.connect(next)
	skip.get_parent().add_child(_next)
	skip.get_parent().move_child(_next, skip.get_index())


## main: a page was opened (a page switch, or a greyed page's button). The tour starts if it is due
func opened(p: String) -> void:
	if _changing:
		return
	if page != "" and p != page:
		finish(true, false)   # the user went on to another page: this tour is over (it is already marked seen)
	if not auto or page != "" or not TOURED.has(p) or not _clear():
		return
	var cf := ConfigFile.new()
	cf.load(m.settings)
	if not seen(cf, p):
		begin_page(p)


## nothing else is pointing at the window: the first-launch guide, the first-run tour, the Easy mode
func _clear() -> bool:
	return m.onboard.step < 0 and not m.onboard.pending and int(m.tour_step) < 0 and not (m.easy != null and m.easy.on)


## the search box's "Page tour": this page's tour (BODY when this page has none), seen or not
func replay() -> void:
	begin_page(m.cur_page if TOURED.has(m.cur_page) else "BODY")


func begin_page(p: String) -> void:
	if not TOURED.has(p):
		return
	if m.easy != null and m.easy.on:
		m.easy.set_on(false, false)   # the tour points at the pages: Expert for this run (the saved mode is untouched)
	if p == "BODY" and m.cur_page != "BODY":
		_changing = true
		m._page_set("BODY", false)
		_changing = false
	page = p
	var cf := ConfigFile.new()
	cf.load(m.settings)
	cf.set_value(SEC, p, true)
	cf.save(m.settings)
	_go(0)


func next() -> void:
	_go(step + 1)


func _go(k: int) -> void:
	var st: Array = steps_of(page)
	if k >= st.size():
		finish(false)
		return
	step = k
	var s: Array = st[k]
	_title.text = "%s %d of %d:  %s" % [page, k + 1, st.size(), s[0]]
	_text.text = step_text(page, k)
	_next.text = "Done" if k == st.size() - 1 else "Next"
	if String(s[2]) == "status":
		m._say(m._page_soon_why(page))   # the line the step points at says it
	_reveal(String(s[2]))
	card.visible = true
	arrow.visible = true
	card.reset_size()
	set_process(true)
	_place()


## a step's sentence; the greyed pages' "why" and "works now" come from P11's own words and the command registry
func step_text(p: String, k: int) -> String:
	var s: Array = steps_of(p)[k]
	if String(s[1]) != "":
		return s[1]
	var w: Array = m.PAGE_SOON_WHY.get(p, ["", "coming"])
	if String(s[2]) == "status":
		return "Not built yet: %s." % w[1]
	var have := []
	for c in m._commands():
		if String(w[0]) != "" and String(c["name"]).begins_with(String(w[0])):
			have.append(String(c["name"]))
	if have.is_empty():
		return "Nothing to click for %s yet. Search (S) and type \"%s\": its commands show there as they arrive." % [p, String(w[0]).trim_suffix(":").to_lower()]
	return "Search (S), type \"%s\": %s." % [String(w[0]).trim_suffix(":").to_lower(), ", ".join(have.slice(0, 3))]


func finish(skipped: bool, save := true) -> void:
	var was := page
	page = ""
	step = -1
	pending = false
	set_process(false)
	if card != null:
		card.visible = false
		arrow.visible = false
	if save and m != null and was != "":
		m._say(("%s tour closed. Search: Page tour plays it again." if skipped else "%s tour done. Search: Page tour plays it again.") % was)


# ---------------------------------------------------------------- what each step points at

func _node(nm: String) -> Control:
	var n: Node = m.ui_root.find_child(nm, true, false)
	return n as Control


## the control the step names, in window coordinates, cut to what its scroll box shows
func target_rect() -> Rect2:
	if page == "" or step < 0:
		return Rect2()
	return _rect_of(String(steps_of(page)[step][2]))


func _rect_of(t: String) -> Rect2:
	var cs := _controls(t)
	if cs.is_empty():
		return Rect2()
	var r: Rect2 = cs[0].get_global_rect()
	for c in cs:
		r = r.merge(c.get_global_rect())
	var sc := _scroll_of(cs[0])
	if sc != null:
		r = r.intersection(sc.get_global_rect())
	return r


func _controls(t: String) -> Array:
	var out := []
	if t.begins_with("page:"):
		var p := t.trim_prefix("page:")
		out.append(m.ui_page_btns[p] if m.ui_page_btns.has(p) else _node("page_" + p.to_lower()))
	elif t == "status":
		out.append(m.ui_status)
	elif t == "undo":
		out.append(m.ui_undo_btn)
	elif t == "search":
		for b in m.ui_root.find_children("*", "Button", true, false):
			if m.label_of(b) == "Search (S)" and (b as Button).is_visible_in_tree():
				out.append(b)
				break
	elif t == "sliders":
		var ks: Array = BodyModel.KEYS
		out.append(m.ui_body.sliders[ks[0]])
		out.append(m.ui_body.sliders[ks[-1]])
	else:
		for nm in t.split("|"):
			var c := _node(nm)
			if c != null:
				out.append(c)
	return out.filter(func(c): return c is Control)


func _scroll_of(c: Node) -> ScrollContainer:
	var n := c.get_parent()
	while n != null and n != m.ui_root:
		if n is ScrollContainer:
			return n
		n = n.get_parent()
	return null


## the body panel scrolls: bring a step's control into its view before pointing at it
func _reveal(t: String) -> void:
	var cs := _controls(t)
	if cs.is_empty():
		return
	var sc := _scroll_of(cs[-1])
	if sc != null:
		sc.ensure_control_visible(cs[-1])


func _sides() -> Array:
	var t := String(steps_of(page)[step][2]) if page != "" and step >= 0 else ""
	if t.begins_with("page:") or t == "status":
		return ["above", "right", "left", "below"]   # the page bar and the status line are low in the window
	if t == "search" or t == "undo":
		return ["below", "left", "right", "above"]   # the top strip
	return ["right", "below", "above", "left"]       # the body panel is on the left


func _process(_dt: float) -> void:
	if page == "" or m == null:
		set_process(false)
		return
	if not target_rect().has_area():
		_reveal(String(steps_of(page)[step][2]))   # a page just opened: its panel was laid out after the step began
	_place()
