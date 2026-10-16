## names.gd - EVERY WIDGET BY NAME (round 14, GATES U2, item 99). Godot calls a node added without a name "@Button@123",
## and that number changes from run to run, so neither a test nor an agent can find it again. main hooks the tree's
## node_added: every control it builds is named from what it SAYS, once, when it is made:
##   its text, else its placeholder, else the first line of its tooltip, else (a number box, a slider) the label just
##   before it in its row, else what it is.
## A kind prefix keeps a button and the box beside it apart: b_ (button), spin_, opt_, edit_, text_, check_, slider_,
## menu_. Names say what a control DOES, so a later relabel ("Trail (T)" turning to "Trail: on") never renames it.
## Repeated rows are named scopes (card_3, finding_2): find_child("card_3").find_child("b_update").
class_name Names
extends RefCounted

const PREFIX := {"Button": "b_", "CheckBox": "check_", "CheckButton": "check_", "MenuButton": "menu_", "OptionButton": "opt_",
	"SpinBox": "spin_", "LineEdit": "edit_", "TextEdit": "text_", "HSlider": "slider_", "VSlider": "slider_"}
const SIGNS := {"<": " lt ", ">": " gt ", "+": " plus ", "-": " minus ", "?": " help ", "&": " and "}


static func wants(n: Node) -> bool:
	return PREFIX.has(n.get_class()) and String(n.name).begins_with("@")


## the engine's own parts (a menu's search box, a tree's editor) are not the window's to name
static func internal(n: Node) -> bool:
	var p := n.get_parent()
	return p != null and not p.get_children(false).has(n)


## "Mirror pose (Shift+M)" -> "mirror_pose"; "< " -> "lt"; "X" -> "x"
static func slug(s: String) -> String:
	s = s.get_slice("\n", 0).to_lower()
	var cut := s.find(" (")
	if cut > 0:
		s = s.left(cut)   # the key hint is not the name: "trail (t)" -> "trail"
	if SIGNS.has(s.strip_edges()):
		s = SIGNS[s.strip_edges()]   # a button that IS a sign: "<" -> "lt"
	for k in range(s.length()):   # a label's value is not its name: "swing 0 deg" -> "swing", "hips up/down 0.00 m" -> "hips up/down"
		if (s[k] >= "0" and s[k] <= "9") and k > 0 and s[k - 1] == " ":
			s = s.left(k)
			break
	var out := ""
	for ch in s:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	while out.length() > 28 and out.contains("_"):   # long (a tooltip): its first words
		out = out.left(out.rfind("_"))
	return out


## what the control says, for its name
static func said(n: Node) -> String:
	for k in ["text", "placeholder_text"]:
		if k == "text" and n is OptionButton:
			continue   # its text is its CHOICE ("smooth"): a name from it would change with the value
		if k in n and slug(String(n.get(k))) != "":
			return slug(String(n.get(k)))
	var p := n.get_parent()
	if p != null and n is Range:   # a number box or slider: the label just before it ("move [0.3]")
		for k in range(n.get_index() - 1, -1, -1):
			var s := p.get_child(k)
			if s is Label and slug(s.text) != "":
				return slug(s.text)
	if "tooltip_text" in n and slug(String(n.tooltip_text)) != "":
		return slug(String(n.tooltip_text))
	return ""


static func name_of(n: Node) -> String:
	var s := said(n)
	return PREFIX[n.get_class()] + (s if s != "" else n.get_class().to_lower())


## name n (deferred by the caller: its text is set right after it is added). A clash with a sibling gets _2, _3
static func give(n: Node) -> void:
	if not is_instance_valid(n) or not wants(n) or internal(n):
		return
	var base := name_of(n)
	var nm := base
	var p := n.get_parent()
	var k := 2
	while p != null and p.has_node(NodePath(nm)) and p.get_node(NodePath(nm)) != n:
		nm = "%s_%d" % [base, k]
		k += 1
	n.name = nm
