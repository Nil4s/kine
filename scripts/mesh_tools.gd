class_name MeshTools
extends RefCounted
## THE MESH TOOLS, ONE LIST (ROADMAP_400 P02: search finds mesh tools too, with hotkeys shown). Every modeling tool is
## ONE line of TOOLS; the S box (scripts/command_search.gd) reads it, so a new op (extrude, dissolve, subdivide ...) adds
## a line here and is found by its words, its hotkey and its page with nothing else to change.
## A line: {"id", "label" (the row's name), "page" (where it works: "MODEL" = the model preview, kmesh_edit_ui.gd; a
## page name; "" = every page), "keys" (Kine's own key there), "bl" (the key with the Blender-style layer on, bl_keys.gd;
## "" = the same), "do", "also" (the other words it answers to), "desc"}. "do" is what a pick runs:
##   "cmd:<id>"  a command of main's registry (main._commands()): the S box's row for it gets the page and the words
##               here; no second row (the line names a tool that is already a command)
##   "key:<K>"   a key of the model preview, sent the way a real key comes (main._unhandled_input)
##   "bl:<K>"    a key of the Blender-style layer (G / R / S on the selected vertices): greyed while the layer is off
##   "op:<name>" an op of this file on the model preview's mesh (op())
##   ""          not built yet: the row shows greyed with "soon", a pick says so (the line is there so the search finds
##               it and the key is reserved; the agent who builds it fills "do")
## Picking a MODEL tool on another page opens the model preview first (the MODEL page is greyed in the page bar until
## B01; the test cube is its first step) and says so; then the tool runs.

const PAGE_ANY := "every page"
const SOON := "soon"

const TOOLS := [
	{"id": "mesh_model", "label": "", "page": "MODEL", "keys": "", "bl": "", "do": "cmd:model_edit_a_test_cube_preview", "also": "model page modeling mesh open start enter", "desc": ""},
	{"id": "mesh_vert", "label": "Model: vertex select mode", "page": "MODEL", "keys": "1", "bl": "", "do": "key:1", "also": "vertex vert verts point points component select mode", "desc": "select vertices (the selection converts)"},
	{"id": "mesh_edge", "label": "Model: edge select mode", "page": "MODEL", "keys": "2", "bl": "", "do": "key:2", "also": "edge edges line component select mode", "desc": "select edges (the selection converts)"},
	{"id": "mesh_face", "label": "Model: face select mode", "page": "MODEL", "keys": "3", "bl": "", "do": "key:3", "also": "face faces polygon poly component select mode", "desc": "select faces (the selection converts)"},
	{"id": "mesh_box", "label": "Model: box select", "page": "MODEL", "keys": "B", "bl": "", "do": "key:B", "also": "box rectangle marquee drag select area", "desc": "drag a rectangle: what is inside is selected (Shift adds)"},
	{"id": "mesh_lasso", "label": "Model: lasso select", "page": "MODEL", "keys": "L", "bl": "", "do": "key:L", "also": "lasso loop freehand draw select area", "desc": "drag a loop: what is inside is selected (Shift adds)"},
	{"id": "mesh_xray", "label": "Model: x-ray select through", "page": "MODEL", "keys": "X", "bl": "", "do": "key:X", "also": "xray x-ray through see transparent hidden back far side occluded", "desc": "box and lasso take the far side too, not only what you see"},
	{"id": "mesh_all", "label": "Model: select all", "page": "MODEL", "keys": "A", "bl": "", "do": "key:A", "also": "all everything select whole", "desc": "every element of the mode"},
	{"id": "mesh_leave", "label": "Model: leave the test cube", "page": "MODEL", "keys": "Esc", "bl": "", "do": "key:Escape", "also": "leave exit close quit stop done", "desc": "drop the test cube (nothing is saved)"},
	{"id": "mesh_wire", "label": "Model: wire over the surface on / off", "page": "MODEL", "keys": "", "bl": "", "do": "op:wire", "also": "wire wireframe edges lines overlay show hide", "desc": "the edges drawn over the shaded surface, or the surface alone"},
	{"id": "mesh_validate", "label": "Model: check the mesh (validate)", "page": "MODEL", "keys": "", "bl": "", "do": "op:validate", "also": "validate check problems errors non-manifold holes doubled loose flipped inside out clean health", "desc": "lists what is wrong with the mesh, each with its next step (scripts/kmesh_validate.gd)"},
	{"id": "mesh_repair", "label": "Model: repair the mesh", "page": "MODEL", "keys": "", "bl": "", "do": "op:repair", "also": "repair fix clean merge distance doubles holes fill flip normals consistent cleanup", "desc": "fixes every problem that can be fixed alone (one undo step)"},
	{"id": "mesh_grab", "label": "Model: grab the selected vertices", "page": "MODEL", "keys": "", "bl": "G", "do": "bl:G", "also": "grab move translate drag vertices", "desc": "the selection follows the mouse; X / Y / Z an axis, a number metres; Enter keeps"},
	{"id": "mesh_rotate", "label": "Model: rotate the selected vertices", "page": "MODEL", "keys": "", "bl": "R", "do": "bl:R", "also": "rotate turn spin vertices", "desc": "turn the selection round its centre; X / Y / Z an axis, a number degrees; Enter keeps"},
	{"id": "mesh_scale", "label": "Model: scale the selected vertices", "page": "MODEL", "keys": "", "bl": "S", "do": "bl:S", "also": "scale size grow shrink resize vertices", "desc": "scale the selection about its centre; a number = the factor; Enter keeps"},
	{"id": "mesh_extrude", "label": "Model: extrude", "page": "MODEL", "keys": "E", "bl": "", "do": "", "also": "extrude pull push out grow faces", "desc": "pull the selected faces out along their normal, new side faces between"},
	{"id": "mesh_inset", "label": "Model: inset faces", "page": "MODEL", "keys": "I", "bl": "", "do": "", "also": "inset inside border shrink faces", "desc": "a smaller face inside each selected face, ringed by new faces"},
	{"id": "mesh_proportional", "label": "Model: proportional editing on / off", "page": "MODEL", "keys": "O", "bl": "", "do": "key:O", "also": "proportional falloff soft selection magnet radius smooth sphere root linear sharp constant connected", "desc": "G / R / S also pull the unselected verts within a radius, by a falloff (Shift+O falloff, Alt+O connected only, the wheel sizes it)"},
	{"id": "mesh_bevel", "label": "Model: bevel", "page": "MODEL", "keys": "Ctrl+B", "bl": "", "do": "", "also": "bevel chamfer round fillet edges corner", "desc": "cut the selected edges into a chamfer of 1 or more segments"},
	{"id": "mesh_loopcut", "label": "Model: loop cut", "page": "MODEL", "keys": "Ctrl+R", "bl": "", "do": "", "also": "loop cut ring split edge loop slice", "desc": "a new edge loop across a ring of quads"},
	{"id": "mesh_knife", "label": "Model: knife", "page": "MODEL", "keys": "K", "bl": "", "do": "", "also": "knife cut slice draw edges", "desc": "draw a cut across faces"},
	{"id": "mesh_dissolve", "label": "Model: dissolve", "page": "MODEL", "keys": "Ctrl+X", "bl": "", "do": "", "also": "dissolve delete remove merge faces edges vertices clean", "desc": "remove the selected elements, the faces round them joined"},
	{"id": "mesh_delete", "label": "Model: delete", "page": "MODEL", "keys": "Del", "bl": "", "do": "", "also": "delete remove erase vertices edges faces", "desc": "delete the selected elements"},
	{"id": "mesh_merge", "label": "Model: merge vertices", "page": "MODEL", "keys": "M", "bl": "", "do": "", "also": "merge weld collapse join center vertices", "desc": "the selected vertices become one"},
	{"id": "mesh_fill", "label": "Model: fill (make a face)", "page": "MODEL", "keys": "F", "bl": "", "do": "", "also": "fill face make new close hole bridge", "desc": "a face on the selected vertices or across a hole"},
	{"id": "mesh_subdiv", "label": "Model: subdivide", "page": "MODEL", "keys": "", "bl": "", "do": "", "also": "subdivide subdivision catmull clark smooth split more faces", "desc": "every selected face split in four (Catmull-Clark: A12)"},
	{"id": "mesh_add", "label": "Model: add a primitive (cube, sphere, cylinder...)", "page": "MODEL", "keys": "Shift+A", "bl": "", "do": "", "also": "add new primitive cube sphere cylinder plane cone torus shape create", "desc": "a new shape on the stage to model from"},
	{"id": "mesh_quad", "label": "", "page": "", "keys": "", "bl": "", "do": "cmd:view_quad_view_on_off", "also": "mesh model four views", "desc": ""},
	{"id": "mesh_local", "label": "", "page": "", "keys": "", "bl": "", "do": "cmd:view_isolate_the_selected_part", "also": "mesh model local view", "desc": ""},
	{"id": "mesh_frame", "label": "", "page": "", "keys": "", "bl": "", "do": "cmd:view_frame_the_selected_part", "also": "mesh model frame selected", "desc": ""},
	{"id": "mesh_section", "label": "", "page": "", "keys": "", "bl": "", "do": "cmd:view_section_plane", "also": "mesh model", "desc": ""},
	{"id": "mesh_normals", "label": "", "page": "", "keys": "", "bl": "", "do": "cmd:view_show_normals", "also": "mesh model overlay", "desc": ""},
	{"id": "mesh_shade_wire", "label": "", "page": "", "keys": "", "bl": "", "do": "cmd:view_shading_wireframe", "also": "mesh model overlay", "desc": ""},
	{"id": "mesh_shade_xray", "label": "", "page": "", "keys": "", "bl": "", "do": "cmd:view_shading_x-ray", "also": "mesh model", "desc": ""},
	{"id": "mesh_obj_in", "label": "", "page": "STAGE", "keys": "", "bl": "", "do": "cmd:stage_import_an_obj_as_a_prop", "also": "mesh model", "desc": ""},
	{"id": "mesh_obj_out", "label": "", "page": "DELIVER", "keys": "", "bl": "", "do": "cmd:deliver_export_the_posed_body_as_obj", "also": "mesh model", "desc": ""},
	{"id": "mesh_blkeys", "label": "", "page": "", "keys": "", "bl": "", "do": "cmd:keys_blender-style_g_r_s_on_off", "also": "mesh model vertices", "desc": ""},
]


## the S box's rows for the lines that are not commands already: {"name", "kind": "mesh", "keys": "" (the registry's
## keys stay the global ones: these keys work in the model preview only), "hot", "page", "also", "desc", "tool", "run"}
static func rows(m) -> Array:
	var out := []
	for t in TOOLS:
		if String(t["do"]).begins_with("cmd:"):
			continue
		var r := {"name": t["label"], "kind": "mesh", "icon": "page_model", "keys": "", "page": t["page"], "also": t["also"],
			"desc": t["desc"], "tool": t, "host": m}
		r["run"] = run.bind(t, m)
		out.append(r)
	return out


## the command rows a line names get its page and its words (in place; the rows are main's fresh _commands() each time)
static func decorate(commands: Array) -> Array:
	var by_id := {}
	for t in TOOLS:
		var d := String(t["do"])
		if d.begins_with("cmd:"):
			by_id[d.substr(4)] = t
	for c in commands:
		var t = by_id.get(String((c as Dictionary).get("id", "")))
		if t != null and not c.has("tool"):
			c["tool"] = t
			c["page"] = t["page"]
			c["also"] = (String(c.get("also", "")) + " " + String(t["also"])).strip_edges()
	return commands


static func _bl_on(m) -> bool:
	return m != null and m.get("blk") != null and m.blk.on


static func _model_on(m) -> bool:
	return m != null and m.get("kmed") != null and m.kmed.on


## the key a line shows now: the Blender-layer key while that layer is on (or the only key it has)
static func hot(t: Dictionary, bl_on: bool) -> String:
	var k := String(t["keys"])
	var b := String(t["bl"])
	if b != "" and (bl_on or k == ""):
		return b
	return k


## a mesh row with a key of its own that works now (built): it wins a tie in the S box like a command with a shortcut
static func keyed(c: Dictionary) -> bool:
	if c.get("kind", "") != "mesh":
		return false
	var t: Dictionary = c["tool"]
	return String(t["do"]) != "" and String(t["keys"]) != ""


## the right-hand text of a row: its hotkey, then its page ("E   MODEL   soon"). A command row keeps its own keys
static func right_text(c: Dictionary) -> String:
	var t: Dictionary = c.get("tool", {})
	var k := String(c.get("keys", ""))
	if c.get("kind", "") == "mesh":
		k = hot(t, _bl_on(c.get("host")))
	var pg := String(c.get("page", ""))
	var parts := []
	if k != "":
		parts.append(k)
	parts.append(pg if pg != "" else PAGE_ANY)
	if String(t.get("do", "x")) == "":
		parts.append(SOON)
	return "   ".join(parts)


## why a row is greyed now ("" = it is not): not built yet, or a Blender-layer key while that layer is off
static func why(c: Dictionary) -> String:
	var t: Dictionary = c.get("tool", {})
	var d := String(t.get("do", "x"))
	if d == "":
		return "%s is not built yet (coming on the MODEL page%s). Works now: selection modes, box, lasso, x-ray, validate, repair" % [t["label"].trim_prefix("Model: "), (", key " + String(t["keys"])) if String(t["keys"]) != "" else ""]
	if d.begins_with("bl:") and not _bl_on(c.get("host")):
		return "%s is the Blender-style %s key: turn the layer on first (S, then \"Keys: Blender-style G R S on / off\")" % [t["label"].trim_prefix("Model: "), d.substr(3)]
	return ""


## pick a line: a MODEL tool on another page opens the model preview first; then its key / op runs
static func run(t: Dictionary, m) -> void:
	var d := String(t["do"])
	var r := {"tool": t, "host": m}
	var w := why(r)
	if w != "":
		m._say(w)
		return
	if d.begins_with("cmd:"):
		return   # its command row runs it
	var opened := false
	if t["page"] == "MODEL" and not _model_on(m):
		m._kmesh_edit_start()
		opened = true
		if d == "key:Escape":
			return   # nothing to leave: it was just opened
	if d.begins_with("key:") or d.begins_with("bl:"):
		var ev := InputEventKey.new()
		ev.keycode = OS.find_keycode_from_string(d.substr(d.find(":") + 1))
		ev.pressed = true
		m._unhandled_input(ev)   # the way a real key comes: the Blender layer first, then the model preview
	elif d.begins_with("op:"):
		op(d.substr(3), m)
	if opened and m.get("ui_status") != null:   # what the tool said, after why the page changed
		m._say("Model: opened the test cube first (%s works on the MODEL page). %s" % [t["label"].trim_prefix("Model: "), String(m.ui_status.text).trim_prefix("Model: ")])


## the ops on the model preview's mesh. validate: what is wrong, said; repair: one KMeshUndo step; wire: the edges on / off
static func op(name: String, m) -> String:
	var ui = m.kmed
	var said := ""
	match name:
		"validate":
			var rep := KMeshValidate.report(ui.mesh)
			if rep["ok"]:
				said = "Model: the mesh is clean (%d verts, %d faces): no doubled or loose verts, no holes, nothing flipped" % [ui.mesh.verts.size(), ui.mesh.faces.size()]
			else:
				said = "Model: %d problems: %s" % [rep["problems"].size(), "; ".join(rep["problems"].map(func(p): return p["fix"]))]
		"repair":
			ui.undo.begin(ui.mesh)
			var done := KMeshValidate.repair(ui.mesh)
			ui.undo.commit("Repair the mesh")
			ui.sel.clear()   # the repair renumbers verts and faces: the old selection would name others
			ui.view.mark_dirty()
			said = "Model: nothing to repair" if done.is_empty() else "Model: repaired %s (one mesh undo step)" % ", ".join(done.keys().map(func(k): return "%s %d" % [k, done[k]]))
		"wire":
			ui.view.show_wire = not ui.view.show_wire
			ui.view.mark_dirty()
			said = "Model: wire %s" % ("on: every edge drawn over the surface" if ui.view.show_wire else "off: the surface alone")
	if said != "":
		m._say(said)
	return said
