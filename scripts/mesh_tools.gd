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
	{"id": "mesh_body_edit", "label": "", "page": "MODEL", "keys": "", "bl": "", "do": "cmd:model_edit_the_body_mesh", "also": "body skin fighter character base mesh", "desc": ""},
	{"id": "mesh_body_apply", "label": "", "page": "MODEL", "keys": "", "bl": "", "do": "cmd:model_apply_the_body_mesh_to_the_fighter", "also": "body skin fighter apply write back", "desc": ""},
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
	{"id": "mesh_body", "label": "Model: colour by body region", "page": "MODEL", "keys": "Shift+H", "bl": "", "do": "op:body_regions", "also": "body region bone nearest anatomy limb arm leg hand head colour color skin aware label", "desc": "every vertex coloured by its body region (nearest UE5 bone), a legend, and the bone + distance under the mouse (A18)"},
	{"id": "mesh_anatomy", "label": "Model: colour by anatomy (tags)", "page": "MODEL", "keys": "Alt+H", "bl": "", "do": "op:anatomy", "also": "anatomy tag tags muscle deltoid biceps triceps patella kneecap knuckle elbow olecranon pectoral glutes calf shin palm sole skull face colour color paint brush", "desc": "every vertex coloured by its anatomy tag (deltoid, patella, knuckles ...), a legend, the tag under the mouse; Alt+drag paints the brush tag (A19)"},
	{"id": "mesh_anatomy_seed", "label": "Model: anatomy tags from the bones again", "page": "MODEL", "keys": "", "bl": "", "do": "op:anatomy_seed", "also": "anatomy tags reset reseed seed rule bones again clear paint", "desc": "every vertex's anatomy tag back to the rule (nearest bone, along it, round it); one undo step (A19)"},
	{"id": "mesh_model_checks", "label": "Model: model checks (grade for animation)", "page": "MODEL", "keys": "", "bl": "", "do": "op:model_checks", "also": "grade score animation ready rig deform bend joint joints poles ngon ngons triangles thin loops elbow knee quality topology", "desc": "B30: one button grades the mesh 0-100 for animation; problems worst first, each with Show me and a next step (scripts/model_checks.gd)"},
	{"id": "mesh_repair", "label": "Model: repair the mesh", "page": "MODEL", "keys": "", "bl": "", "do": "op:repair", "also": "repair fix clean merge distance doubles holes fill flip normals consistent cleanup", "desc": "fixes every problem that can be fixed alone (one undo step)"},
	{"id": "mesh_vpaint", "label": "Model: vertex paint on / off", "page": "MODEL", "keys": "", "bl": "", "do": "op:vpaint", "also": "vertex paint colour color brush blend mix add multiply blur eyedropper symmetry pressure", "desc": "drag on the mesh to paint its corner colours (E04, scripts/kmesh_vpaint_ui.gd): [ ] radius, N blend, X symmetry, F fill, Ctrl+click eyedropper, Esc leaves"},
	{"id": "mesh_vpaint_fill", "label": "Model: vertex paint: fill the selection", "page": "MODEL", "keys": "", "bl": "", "do": "op:vpaint_fill", "also": "vertex paint fill colour color selection faces flood", "desc": "the selected faces (or verts) take the paint colour, one undo step"},
	{"id": "mesh_grab", "label": "Model: grab the selected vertices", "page": "MODEL", "keys": "", "bl": "G", "do": "bl:G", "also": "grab move translate drag vertices", "desc": "the selection follows the mouse; X / Y / Z an axis, a number metres; Enter keeps"},
	{"id": "mesh_rotate", "label": "Model: rotate the selected vertices", "page": "MODEL", "keys": "", "bl": "R", "do": "bl:R", "also": "rotate turn spin vertices", "desc": "turn the selection round its centre; X / Y / Z an axis, a number degrees; Enter keeps"},
	{"id": "mesh_scale", "label": "Model: scale the selected vertices", "page": "MODEL", "keys": "", "bl": "S", "do": "bl:S", "also": "scale size grow shrink resize vertices", "desc": "scale the selection about its centre; a number = the factor; Enter keeps"},
	{"id": "mesh_snap_target", "label": "Model: snap target (vertex, edge, face, grid, body)", "page": "MODEL", "keys": "Shift+Tab", "bl": "", "do": "op:snap_target", "also": "snap snapping target vertex edge midpoint face surface grid increment body skin ctrl magnet", "desc": "the next thing G snaps onto while Ctrl is held (B08)"},
	{"id": "mesh_snap_toggle", "label": "Model: snapping always on / off", "page": "MODEL", "keys": "", "bl": "", "do": "op:snap_toggle", "also": "snap snapping toggle always magnet ctrl", "desc": "snap without holding Ctrl (then Ctrl lets go)"},
	{"id": "mesh_pivot", "label": "Model: pivot for rotate / scale (median, active, cursor, individual)", "page": "MODEL", "keys": ".", "bl": "", "do": "op:pivot", "also": "pivot point origin centre center median active cursor individual origins rotate scale", "desc": "what R / S turn and scale about (B14)"},
	{"id": "mesh_extrude", "label": "Model: extrude", "page": "MODEL", "keys": "E", "bl": "", "do": "", "also": "extrude pull push out grow faces", "desc": "pull the selected faces out along their normal, new side faces between"},
	{"id": "mesh_inset", "label": "Model: inset faces", "page": "MODEL", "keys": "I", "bl": "", "do": "", "also": "inset inside border shrink faces", "desc": "a smaller face inside each selected face, ringed by new faces"},
	{"id": "mesh_proportional", "label": "Model: proportional editing on / off", "page": "MODEL", "keys": "O", "bl": "", "do": "key:O", "also": "proportional falloff soft selection magnet radius smooth sphere root linear sharp constant connected", "desc": "G / R / S also pull the unselected verts within a radius, by a falloff (Shift+O falloff, Alt+O connected only, the wheel sizes it)"},
	{"id": "mesh_bevel", "label": "Model: bevel", "page": "MODEL", "keys": "Ctrl+B", "bl": "", "do": "op:bevel", "also": "bevel chamfer round fillet edges corner", "desc": "cut the selected edges into a chamfer of 1 or more segments"},
	{"id": "mesh_loopcut", "label": "Model: loop cut", "page": "MODEL", "keys": "Ctrl+R", "bl": "", "do": "key:Ctrl+R", "also": "loop cut ring split edge loop slice", "desc": "a new edge loop across a ring of quads"},
	{"id": "mesh_knife", "label": "Model: knife", "page": "MODEL", "keys": "Shift+K", "bl": "", "do": "key:Shift+K", "also": "knife cut slice draw edges", "desc": "draw a cut across faces"},
	{"id": "mesh_edge_split", "label": "Model: edge split", "page": "MODEL", "keys": "V", "bl": "", "do": "key:V", "also": "edge split rip separate disconnect seam tear apart edges", "desc": "split the selected edges: the faces either side get their own verts"},
	{"id": "mesh_dissolve", "label": "Model: dissolve", "page": "MODEL", "keys": "Ctrl+X", "bl": "", "do": "", "also": "dissolve delete remove merge faces edges vertices clean", "desc": "remove the selected elements, the faces round them joined"},
	{"id": "mesh_delete", "label": "Model: delete", "page": "MODEL", "keys": "Del", "bl": "", "do": "", "also": "delete remove erase vertices edges faces", "desc": "delete the selected elements"},
	{"id": "mesh_merge", "label": "Model: merge vertices", "page": "MODEL", "keys": "M", "bl": "", "do": "", "also": "merge weld collapse join center vertices", "desc": "the selected vertices become one"},
	{"id": "mesh_fill", "label": "Model: fill (make a face)", "page": "MODEL", "keys": "F", "bl": "", "do": "key:F", "also": "fill face make new close hole bridge grid", "desc": "a face on the selected vertices or across a hole"},
	{"id": "mesh_subdiv", "label": "Model: subdivide", "page": "MODEL", "keys": "", "bl": "", "do": "", "also": "subdivide subdivision catmull clark smooth split more faces", "desc": "every selected face split in four (Catmull-Clark: A12)"},
	{"id": "mesh_modifiers", "label": "Model: modifier stack (mirror, subdivide, solidify, array, displace)", "page": "MODEL", "keys": "", "bl": "", "do": "op:modifiers", "also": "modifier modifiers stack non-destructive mirror symmetry subdivide subdivision solidify thickness shell array repeat copies displace noise bump apply bake", "desc": "a live stack on the mesh, shown in the view; edits stay on the base (A11, the panel on the right)"},
	{"id": "mesh_shrinkwrap", "label": "Model: shrinkwrap onto the body (+4 mm)", "page": "MODEL", "keys": "", "bl": "", "do": "op:shrinkwrap", "also": "shrinkwrap shrink wrap project snap conform fit onto body skin surface armour armor plate offset nearest", "desc": "the selected verts (all when none) go to the nearest point of the fighter's skin at its current pose, 4 mm out (B13, one undo step)"},
	{"id": "mesh_shrinkwrap_view", "label": "Model: project onto the body along the view", "page": "MODEL", "keys": "", "bl": "", "do": "op:shrinkwrap_view", "also": "shrinkwrap project projection along view camera direction ray cast onto body skin armour armor decal", "desc": "the selected verts cast along the view direction (both ways) onto the skin, 4 mm out (B13, one undo step)"},
	{"id": "mesh_shrinkwrap_tgt", "label": "Model: shrinkwrap target = this mesh", "page": "MODEL", "keys": "", "bl": "", "do": "op:shrinkwrap_target", "also": "shrinkwrap target other mesh set use wrap onto", "desc": "this mesh becomes the other target (B13): open another and wrap it onto this one"},
	{"id": "mesh_shrinkwrap_other", "label": "Model: shrinkwrap onto the other target", "page": "MODEL", "keys": "", "bl": "", "do": "op:shrinkwrap_other", "also": "shrinkwrap shrink wrap onto other target mesh project conform", "desc": "the selected verts to the nearest point of the other target, 4 mm out (B13, one undo step)"},
	{"id": "mesh_loop_relax", "label": "Model: relax the selected edge loops", "page": "MODEL", "keys": "", "bl": "", "do": "op:edgeflow_relax", "also": "relax loop edge loops flow smooth even out wiggle jitter round circle laplacian looptools", "desc": "B18: the selected loops smoothed along themselves (10 passes), kept on the surface, a round loop keeps its size (one undo step)"},
	{"id": "mesh_loop_straighten", "label": "Model: straighten the selected edge run", "page": "MODEL", "keys": "", "bl": "", "do": "op:edgeflow_straighten", "also": "straighten straight line loop edge run align collinear even", "desc": "B18: the run's verts on the straight line between its ends, evenly spaced (one undo step)"},
	{"id": "mesh_loop_straighten_s", "label": "Model: straighten the selected edge run on the surface", "page": "MODEL", "keys": "", "bl": "", "do": "op:edgeflow_straighten_surface", "also": "straighten surface arc great circle geodesic loop edge run curved", "desc": "B18: the run's verts on the surface curve between its ends (a great-circle arc on a sphere), evenly spaced (one undo step)"},
	{"id": "mesh_loop_flow", "label": "Model: set edge flow on the selected loops", "page": "MODEL", "keys": "", "bl": "", "do": "op:edgeflow_flow", "also": "set flow edge flow maya curve curvature loop ring smooth bulge dent restore", "desc": "B18: each loop vert onto the smooth curve through its ring neighbours (Maya's Edge Flow; one undo step)"},
	{"id": "mesh_loop_space", "label": "Model: even spacing along the selected loops", "page": "MODEL", "keys": "", "bl": "", "do": "op:edgeflow_space", "also": "even spacing space distribute equal arc length loop edge verts", "desc": "B18: the loop's verts spread out to equal arc length along it (one undo step)"},
	{"id": "mesh_uv_editor", "label": "Model: UV editor panel on / off", "page": "MODEL", "keys": "Shift+U", "bl": "", "do": "op:uv_editor", "also": "uv uvs editor unwrap texture island islands layout 2d move rotate scale", "desc": "the mesh's UVs in 2D: select verts or islands, G / R / S move / rotate / scale them (one undo step each)"},
	{"id": "mesh_decimate", "label": "Model: decimate to half (quadric collapse)", "page": "MODEL", "keys": "", "bl": "", "do": "op:decimate", "also": "decimate reduce simplify collapse polycount fewer faces triangles optimize lower poly", "desc": "half the triangles, borders and UV seams kept, nothing flipped (one undo step; F03)"},
	{"id": "mesh_decimate_q", "label": "Model: decimate to a quarter (quadric collapse)", "page": "MODEL", "keys": "", "bl": "", "do": "op:decimate_quarter", "also": "decimate reduce simplify collapse polycount 25 percent quarter low poly", "desc": "a quarter of the triangles, borders and UV seams kept (one undo step; F03)"},
	{"id": "mesh_decimate_planar", "label": "Model: planar decimate (join flat faces)", "page": "MODEL", "keys": "", "bl": "", "do": "op:decimate_planar", "also": "planar decimate limited dissolve flat coplanar merge faces clean simplify", "desc": "faces in one plane (within 5 deg) become one, seams and borders kept (one undo step; F03)"},
	{"id": "mesh_rigretopo", "label": "Model: rig-aware retopo (loops at elbows, knees, shoulders, hips)", "page": "MODEL", "keys": "", "bl": "", "do": "op:rigretopo", "also": "retopo retopology remesh quad quads rig aware edge loops joints elbow knee shoulder hip deform bend topology limbs animation", "desc": "the body's arms and legs rebuilt as quad tubes with loops placed from the skeleton: 5 across each elbow / knee, radial rings round the shoulders / hips; weights from the skin (one undo step; F10)"},
	{"id": "mesh_lods", "label": "Model: make LODs (100 / 50 / 25 / 12 %)", "page": "MODEL", "keys": "", "bl": "", "do": "op:lods", "also": "lod lods level of detail levels game engine distance decimate", "desc": "4 levels kept with the mesh, each with its error (F04)"},
	{"id": "mesh_lod_next", "label": "Model: next LOD (preview)", "page": "MODEL", "keys": "", "bl": "", "do": "op:lod_next", "also": "lod next preview cycle level of detail show", "desc": "shows LOD0 -> 1 -> 2 -> 3 -> 0 (F04)"},
	{"id": "mesh_lod_export", "label": "Model: export the LODs (.glb)", "page": "MODEL", "keys": "", "bl": "", "do": "op:lod_export", "also": "lod export glb gltf unreal godot engine levels of detail save", "desc": "one .glb with model_LOD0 .. model_LOD3 (F04)"},
	{"id": "mesh_bool_union", "label": "Model: boolean union (join two parts)", "page": "MODEL", "keys": "", "bl": "", "do": "op:boolean_union", "also": "boolean booleans union join merge add combine csg solid parts objects", "desc": "B10: the selected part (nothing selected: the part added last) and the rest become one closed surface (one undo step)"},
	{"id": "mesh_bool_difference", "label": "Model: boolean difference (cut a part away)", "page": "MODEL", "keys": "", "bl": "", "do": "op:boolean_difference", "also": "boolean booleans difference subtract minus cut carve hole remove csg solid parts objects", "desc": "B10: the selected part (nothing selected: the part added last) cut out of the rest (one undo step)"},
	{"id": "mesh_bool_intersect", "label": "Model: boolean intersect (keep the overlap)", "page": "MODEL", "keys": "", "bl": "", "do": "op:boolean_intersect", "also": "boolean booleans intersect intersection overlap common csg solid parts objects", "desc": "B10: only where the selected part (nothing selected: the part added last) and the rest overlap is kept (one undo step)"},
	{"id": "mesh_separate", "label": "Model: separate the selection (a part of its own)", "page": "MODEL", "keys": "", "bl": "", "do": "op:separate", "also": "separate split detach break off apart selection part parts object objects", "desc": "B17: the selected faces become their own part, the border verts doubled (one undo step)"},
	{"id": "mesh_separate_loose", "label": "Model: separate by loose parts", "page": "MODEL", "keys": "", "bl": "", "do": "op:separate_loose", "also": "separate loose parts split apart islands pieces components objects", "desc": "B17: every connected piece its own part (one undo step)"},
	{"id": "mesh_join", "label": "Model: join parts", "page": "MODEL", "keys": "", "bl": "", "do": "op:join", "also": "join combine merge parts objects one together", "desc": "B17: the parts holding the selection (nothing selected: all) become one part; nothing moves (one undo step)"},
	{"id": "mesh_join_weld", "label": "Model: join parts, welding touching border verts", "page": "MODEL", "keys": "", "bl": "", "do": "op:join_weld", "also": "join combine merge weld stitch parts objects border open edges touching", "desc": "B17: join, and border verts of different parts within 0.1 mm become one (one undo step)"},
	{"id": "mesh_origin_geometry", "label": "Model: set origin to the geometry centre", "page": "MODEL", "keys": "", "bl": "", "do": "op:origin_geometry", "also": "origin set centre center geometry bounds pivot object", "desc": "B17: the mesh's origin to the centre of its box; the mesh does not move (one undo step)"},
	{"id": "mesh_origin_cursor", "label": "Model: set origin to the 3D cursor", "page": "MODEL", "keys": "", "bl": "", "do": "op:origin_cursor", "also": "origin set 3d cursor pivot object", "desc": "B17: the mesh's origin to the 3D cursor (Shift+right-click places it); the mesh does not move (one undo step)"},
	{"id": "mesh_origin_bottom", "label": "Model: set origin to the bottom centre", "page": "MODEL", "keys": "", "bl": "", "do": "op:origin_bottom", "also": "origin set bottom base floor feet centre center pivot object", "desc": "B17: the mesh's origin to the middle of its base (lowest y); the mesh does not move (one undo step)"},
	{"id": "mesh_curves", "label": "Model: spin / lathe / curves panel", "page": "MODEL", "keys": "", "bl": "", "do": "op:curves", "also": "spin screw lathe revolve curve curves bezier panel", "desc": "B11 / B12: lathe a profile, make and edit bezier curves"},
	{"id": "mesh_lathe", "label": "Model: spin / lathe the selected edges", "page": "MODEL", "keys": "", "bl": "", "do": "op:lathe", "also": "spin screw lathe revolve turn profile around axis vase bottle cup column ring thread helix", "desc": "B11: revolve the selected edge chain around an axis through the 3D cursor (angle, steps, screw); one undo step, live"},
	{"id": "mesh_lathe_typed", "label": "Model: lathe a typed profile", "page": "MODEL", "keys": "", "bl": "", "do": "op:lathe_typed", "also": "spin lathe revolve typed profile numbers r y radius height", "desc": "B11: revolve the r,y pairs typed in the panel (cm)"},
	{"id": "mesh_curve_add", "label": "Model: new curve (bezier: belt, strap, cable)", "page": "MODEL", "keys": "", "bl": "", "do": "op:curve_add", "also": "curve bezier spline path belt strap cable rope tube pipe sweep bevel taper", "desc": "B12: a bezier curve swept into a tube or strap; drag its points and handles"},
	{"id": "mesh_curve_circle", "label": "Model: new closed curve (circle)", "page": "MODEL", "keys": "", "bl": "", "do": "op:curve_circle", "also": "curve bezier circle closed loop ring belt", "desc": "B12: a closed bezier circle"},
	{"id": "mesh_curve_wrap", "label": "Model: shrinkwrap the curve onto the body", "page": "MODEL", "keys": "", "bl": "", "do": "op:curve_wrap", "also": "curve belt strap shrinkwrap wrap body waist skin fit", "desc": "B12 + B13: the curve onto the skin, 3 mm off"},
	{"id": "mesh_curve_to_mesh", "label": "Model: convert the curve to mesh", "page": "MODEL", "keys": "", "bl": "", "do": "op:curve_to_mesh", "also": "curve convert bake mesh apply sweep", "desc": "B12: the swept curve becomes mesh (one undo step)"},
	{"id": "mesh_add", "label": "Model: add a primitive (cube, sphere, cylinder...)", "page": "MODEL", "keys": "Shift+A", "bl": "", "do": "", "also": "add new primitive cube sphere cylinder plane cone torus shape create", "desc": "a new shape on the stage to model from"},
	{"id": "mesh_uv_export", "label": "Model: export UV layout", "page": "MODEL", "keys": "", "bl": "", "do": "cmd:model_export_uv_layout", "also": "uv layout export png svg texture template", "desc": ""},
	{"id": "mesh_uvpack", "label": "Model: pack UV islands", "page": "MODEL", "keys": "Ctrl+P", "bl": "", "do": "op:uv_pack", "also": "pack uv islands packing layout margin texel density rotate atlas", "desc": "D04: islands packed into 0..1 (MaxRects), 4 px margin at 1024, equal texel density, each island turned to its smallest box"},
	{"id": "mesh_uvgame2k", "label": "Model: game ready UVs (1 x 2k)", "page": "MODEL", "keys": "", "bl": "", "do": "op:uv_game_2k", "also": "game ready uv unwrap pack density budget 2k 2048 texture one click auto", "desc": "D15: seams, unwrap, pack and equal density for one 2048 texture; says the px/cm"},
	{"id": "mesh_uvgame4k", "label": "Model: game ready UVs (4 x 1k)", "page": "MODEL", "keys": "", "bl": "", "do": "op:uv_game_4k", "also": "game ready uv unwrap pack density budget 4k 1k 1024 tiles udim one click auto", "desc": "D15: seams, unwrap, pack into four 1024 tiles split by body region (UDIM 1001-1004), equal density; says the px/cm"},
	{"id": "mesh_autoweights", "label": "", "page": "MODEL", "keys": "", "bl": "", "do": "cmd:model_bind_to_the_skeleton_auto_weights", "also": "skin weights bind bones heat", "desc": ""},
	{"id": "mesh_mat_assign", "label": "Model: assign the material to the selected faces", "page": "MODEL", "keys": "", "bl": "", "do": "op:mat_assign", "also": "material materials pbr assign apply paint slot surface metal rough", "desc": "the Materials panel's picked slot goes on the selected faces (E01, one undo step)"},
	{"id": "mesh_mat_select", "label": "Model: select the faces of a material", "page": "MODEL", "keys": "", "bl": "", "do": "op:mat_select", "also": "material materials pbr slot by which faces", "desc": "the faces wearing the Materials panel's picked slot become the selection"},
	{"id": "mesh_romclash", "label": "Model: armour clash, range of motion (ROM test)", "page": "MODEL", "keys": "", "bl": "", "do": "op:romclash", "also": "armour armor clash range of motion rom test sweep cuts into body penetration clearance 1 cm heat map clothes safe plate", "desc": "B24 / B25: the armour on the fighter against the body over a sweep of every joint that moves it, to its limits: the worst poses listed, the offending verts lit red, the clearance per part (heat map)"},
	{"id": "mesh_armour", "label": "Model: armour from the body (plate over anatomy tags)", "page": "MODEL", "keys": "", "bl": "", "do": "op:armour", "also": "armour armor plate shell vambrace pauldron greave breastplate bracer guard offset thickness solidify bevel skinned tags region deltoid forearm pectoral", "desc": "B23: a plate shell over the picked anatomy tags / regions, 4 mm off the skin, 3 mm thick, edges bevelled, skinned, added to the fighter (one undo step)"},
	{"id": "mesh_wpaint", "label": "Model: weight paint (skin weights)", "page": "MODEL", "keys": "", "bl": "", "do": "op:wpaint", "also": "weight paint skin weights bone brush smooth normalise normalize mirror lock influence skinning", "desc": "H02: paint the active bone's skin weights (heat blue -> red): add / subtract / set / smooth, X mirror, lock bones (on / off)"},
	{"id": "mesh_fset_from_sel", "label": "Model: face set from the selection", "page": "MODEL", "keys": "", "bl": "", "do": "op:fset_from_sel", "also": "face set sets group polygroup selection selected new", "desc": "the selected faces become a new face set (C09; one undo step)"},
	{"id": "mesh_fset_anatomy", "label": "Model: face sets from the anatomy tags", "page": "MODEL", "keys": "", "bl": "", "do": "op:fset_anatomy", "also": "face set sets group polygroup anatomy tag tags muscle", "desc": "one face set per A19 anatomy tag, face for face (C09)"},
	{"id": "mesh_fset_regions", "label": "Model: face sets from the body regions", "page": "MODEL", "keys": "", "bl": "", "do": "op:fset_regions", "also": "face set sets group polygroup body region regions bone", "desc": "one face set per A18 body region (C09)"},
	{"id": "mesh_fset_materials", "label": "Model: face sets from the material slots", "page": "MODEL", "keys": "", "bl": "", "do": "op:fset_materials", "also": "face set sets group polygroup material materials slot", "desc": "one face set per material slot (C09)"},
	{"id": "mesh_fset_uv", "label": "Model: face sets from the UV islands", "page": "MODEL", "keys": "", "bl": "", "do": "op:fset_uv", "also": "face set sets group polygroup uv island islands", "desc": "one face set per UV island (C09)"},
	{"id": "mesh_sculpt_pose", "label": "Model: sculpt the body in pose", "page": "", "keys": "", "bl": "", "do": "op:sculpt_pose", "also": "sculpt pose posed frame animation bent elbow knee rest inverse skinning brush stroke body", "desc": "the open body skinned at this frame; every sculpt brush works on it and each stroke lands in the rest mesh, one undo step (C19, scripts/sculpt_pose_ui.gd)"},
	{"id": "mesh_sculpt_pose_corr", "label": "Model: sculpt in pose as a corrective (on / off)", "page": "", "keys": "", "bl": "", "do": "op:sculpt_pose_corr", "also": "corrective shape key pose space deformation psd elbow knee bend sculpt", "desc": "pose-sculpt strokes go into a corrective shape tied to the bent joint instead of the rest mesh (C19)"},
	{"id": "mesh_fset_hide", "label": "Model: hide the face sets of the selection", "page": "MODEL", "keys": "", "bl": "", "do": "op:fset_hide", "also": "face set sets hide hidden polygroup", "desc": "the sets of the selected faces are not drawn and not sculpted (C09)"},
	{"id": "mesh_fset_isolate", "label": "Model: isolate the face set of the selection", "page": "MODEL", "keys": "", "bl": "", "do": "op:fset_isolate", "also": "face set sets isolate solo only polygroup", "desc": "every other face set hidden (C09)"},
	{"id": "mesh_fset_show_all", "label": "Model: show every face set", "page": "MODEL", "keys": "", "bl": "", "do": "op:fset_show_all", "also": "face set sets show unhide reveal all polygroup", "desc": "every hidden face set drawn again (C09)"},
	{"id": "mesh_fset_grow", "label": "Model: grow the face sets of the selection", "page": "MODEL", "keys": "", "bl": "", "do": "op:fset_grow", "also": "face set sets grow expand ring polygroup", "desc": "each set of the selected faces takes one more ring of faces (C09)"},
	{"id": "mesh_fset_shrink", "label": "Model: shrink the face sets of the selection", "page": "MODEL", "keys": "", "bl": "", "do": "op:fset_shrink", "also": "face set sets shrink contract ring polygroup", "desc": "each set of the selected faces gives up its outer ring (C09)"},
	{"id": "mesh_fset_colors", "label": "Model: face-set colours on / off", "page": "MODEL", "keys": "", "bl": "", "do": "op:fset_colors", "also": "face set sets colour color overlay tint polygroup show", "desc": "each face set tinted in its own colour (C09)"},
	{"id": "mesh_realsize", "label": "Model: real-size check", "page": "MODEL", "keys": "", "bl": "", "do": "op:realsize", "also": "real size scale units dimensions sanity check too big small long sword helmet glove boot body proportions cm mm", "desc": "B27: the model's box against the fighter (a sword vs the arm, a helmet vs the head), with a readout beside it"},
	{"id": "mesh_realsize_fix", "label": "Model: real-size rescale (units fix)", "page": "MODEL", "keys": "", "bl": "", "do": "op:realsize_fix", "also": "real size rescale units cm mm fix scale 100 1000 import", "desc": "B27: a model made in cm or mm scaled back to metres, one undo step"},
	{"id": "mesh_refplane_add", "label": "Model: add a reference image (front / side / top plane)", "page": "MODEL", "keys": "", "bl": "", "do": "op:refplane_add", "also": "reference image picture photo blueprint plane background front side top opacity trace drop", "desc": "a picture on a plane behind the mesh, with opacity, offset, real height, two-point scale, flip, lock (B21; or drop a picture on the window)"},
	{"id": "mesh_refplane_two", "label": "Model: reference image: scale by two points", "page": "MODEL", "keys": "", "bl": "", "do": "op:refplane_two", "also": "reference image picture blueprint scale two points distance calibrate size real", "desc": "click two points on the picture, then type their real distance (B21)"},
	{"id": "mesh_mirror_edit", "label": "Model: edit mirror on / off (G R S and sculpt move the partner)", "page": "MODEL", "keys": "", "bl": "", "do": "op:mirror_edit", "also": "mirror symmetry symmetric x-mirror x mirror edit partner both sides topology topological", "desc": "B22: each moved vert's partner moves mirrored, in the same undo step; partners found by connectivity, so a posed or drifted mesh still mirrors"},
	{"id": "mesh_mirror_axis", "label": "Model: mirror axis X / Y / Z", "page": "MODEL", "keys": "", "bl": "", "do": "op:mirror_axis", "also": "mirror symmetry axis x y z plane", "desc": "B22: the next mirror axis"},
	{"id": "mesh_mirror_space", "label": "Model: mirror plane local / world", "page": "MODEL", "keys": "", "bl": "", "do": "op:mirror_space", "also": "mirror symmetry plane local world origin space", "desc": "B22: the plane through the mesh's origin or the world's"},
	{"id": "mesh_mirror_topo", "label": "Model: mirror partners by topology / by position", "page": "MODEL", "keys": "", "bl": "", "do": "op:mirror_topo", "also": "mirror symmetry topology topological connectivity position positional partners", "desc": "B22: partners by connectivity (default) or by position only"},
	{"id": "mesh_mirror_map", "label": "Model: mirror map (partnered %, select the unpaired)", "page": "MODEL", "keys": "", "bl": "", "do": "op:mirror_map", "also": "mirror symmetry map partners unpaired lonely topology report", "desc": "B22: how many verts have a mirror partner; the ones without are selected"},
	{"id": "mesh_symmetrize", "label": "Model: symmetrize (+ side onto - side)", "page": "MODEL", "keys": "", "bl": "", "do": "op:symmetrize", "also": "symmetrize symmetrise symmetry mirror copy side plus minus make symmetric", "desc": "B22: the - side becomes the mirror image of the + side, through the topological map (one undo step)"},
	{"id": "mesh_symmetrize_minus", "label": "Model: symmetrize (- side onto + side)", "page": "MODEL", "keys": "", "bl": "", "do": "op:symmetrize_minus", "also": "symmetrize symmetrise symmetry mirror copy side minus plus make symmetric", "desc": "B22: the + side becomes the mirror image of the - side (one undo step)"},
	{"id": "mesh_mirror_asym", "label": "Model: find asymmetry", "page": "MODEL", "keys": "", "bl": "", "do": "op:mirror_asym", "also": "asymmetry asymmetric symmetry check deviation drift mirror lopsided uneven", "desc": "B22: selects the verts whose partner is not at their mirror image and says the largest deviation in mm"},
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
		"snap_target":
			said = "Model: snap to " + KMeshSnap.NAMES[ui.snap.cycle()]
		"snap_toggle":
			ui.snap.toggle()
		"pivot":
			said = "Model: pivot " + KMeshPivot.NAMES[ui.pivot.cycle()]
		"vpaint", "vpaint_fill":   # E04
			return KMeshVPaintUI.toggle(m) if name == "vpaint" else KMeshVPaintUI.fill_op(m)
		"armour":   # B23 (scripts/armour_from_body.gd, armour_ui.gd)
			return ArmourUI.toggle(m)
		"romclash":   # B24 / B25 (scripts/rom_clash.gd, rom_clash_ui.gd)
			if m.clash_ui == null:
				m.clash_ui = RomClashUI.new(m)
			return m.clash_ui.run_said("rom")
		"wpaint":
			said = KMeshWPaintUI.toggle(m)
		"bevel":
			said = KMeshBevel.run(ui)
			return said   # run() said it
		"anatomy":   # A19 (scripts/kmesh_anatomy.gd)
			ui.anat.toggle()
			return String(m.ui_status.text) if m.get("ui_status") != null else ""
		"anatomy_seed":
			if m.skel == null:
				return "Model: no fighter to take the anatomy tags from"
			ui.undo.begin(ui.mesh)
			KMeshAnatomy.seed_tags(ui.mesh, m.skel, ui.view.global_transform)
			ui.undo.commit("anatomy tags from the bones")
			if ui.anat.on:
				ui.anat._rebuild()
			said = "Model: anatomy tags from the bones again (%d tags; one undo step)" % KMeshAnatomy.counts(ui.mesh).size()
		"body_regions":   # A18 (scripts/kmesh_body.gd)
			ui.body.toggle()
			return String(m.ui_status.text) if m.get("ui_status") != null else ""
		"model_checks":   # B30 (scripts/model_checks_ui.gd): the panel says what it found
			return ModelChecksUI.toggle(m)
		"modifiers":
			said = ui.mods.say_stack()
		"shrinkwrap", "shrinkwrap_view", "shrinkwrap_other", "shrinkwrap_target":   # B13 (scripts/kmesh_shrinkwrap.gd)
			said = KMeshShrinkwrap.op(name, m)
		"uv_pack", "uv_game_2k", "uv_game_4k":   # D04 / D15 (KMeshUVPack): one undo step, says the px/cm
			return KMeshUVPack.run_ui(ui, {"uv_pack": "pack", "uv_game_2k": "2k", "uv_game_4k": "4k"}[name])
		"uv_editor":
			ui.toggle_uv_editor()
		"mat_assign", "mat_select":   # E01: the Materials panel says what it did
			var _n: int = ui.mat_panel.assign_selection() if name == "mat_assign" else ui.mat_panel.select_by(ui.mat_panel.cur)
		"realsize":   # B27 (scripts/real_size.gd): the readout says it
			return RealSizeUI.toggle(m)
		"realsize_fix":
			return RealSizeUI.fix_op(m)
		"wire":
			ui.view.show_wire = not ui.view.show_wire
			ui.view.mark_dirty()
			said = "Model: wire %s" % ("on: every edge drawn over the surface" if ui.view.show_wire else "off: the surface alone")
		_:
			if name.begins_with("decimate"):
				said = KMeshDecimate.op(name, m)   # F03
			elif name.begins_with("lod"):
				said = KMeshLOD.op(name, m)   # F04
			elif name == "rigretopo":
				said = KMeshRigRetopo.op(m)   # F10
			elif name.begins_with("refplane"):   # B21 (scripts/kmesh_refplanes_ui.gd): it says what it did
				return ui.refp.open_dialog() if name == "refplane_add" else ui.refp.arm_two_points()
			elif name.begins_with("fset_"):
				said = KMeshFaceSetsUI.op(name, m)   # C09
			elif name.begins_with("sculpt_pose"):
				return SculptPoseUI.op(name, m)   # C19 (scripts/sculpt_pose_ui.gd): it says what it did
			elif name.begins_with("boolean_"):
				said = KMeshBoolean.op(name, m)   # B10
			elif name.begins_with("curve") or name.begins_with("lathe"):
				return KMeshCurvesUI.op(name, m)   # B11 / B12 (scripts/kmesh_curves_ui.gd): it says what it did
			elif name.begins_with("edgeflow_"):
				said = KMeshEdgeFlow.op(name, m)   # B18
			elif name.begins_with("mirror_") or name.begins_with("symmetrize"):
				said = KMeshTopoMirror.op(name, m)   # B22
			elif name.begins_with("separate") or name.begins_with("join") or name.begins_with("origin_"):
				said = KMeshSepJoin.op(name, m)   # B17
	if said != "":
		m._say(said)
	return said
