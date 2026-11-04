extends SceneTree
## godot --path . -s tests/c55_test.gd   (C55: one SVG parser. sketch_import.gd now holds C15's scale-checked import; svg_import.gd is a name facade.)
## BARS (expected hashes recorded from origin BEFORE the merge of the two parsers; copied from out/c55/before.txt):
##  1 each of 16 outputs (11 C15 SvgImport inputs, 3 C53 SketchImport fixtures, 2 C53 SVG files through SvgImport) hashes to its recorded value.
##  CONTROL: a planted one-character change in one expected hash, and a planted 0.0001 nudge of one output coordinate, are both caught.
## WATCHDOG: the run quits with failure after 60 s.

const EXPECT := {"c15_r1": "24d316ba28111716", "c15_r2": "b9530384704119d4", "c15_r3": "7cc3e9c75e0c6306", "c15_r4": "5b7b35bc509d641b", "c15_r5": "133fb4ef7df305f8", "c15_r6": "c2d7ecdfea98367f", "c15_r7": "ee243a50b942ce5b", "c15_poly": "1883d304f7b25274", "c15_circ": "87550c9d79a70275", "c15_curve": "54fad9d502345622", "c15_novb": "dea4a94ea1ff46d8", "c53_px.svg": "cb7102201ed3f7f9", "c53_shapes.svg": "08475f9932afb312", "c53_shapes.dxf": "52b75817dd4fa752", "c15on_px.svg": "8bea36ecf5eaf16a", "c15on_shapes.svg": "0dd6b5137a5f3dca"}
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func svg(w: String, h: String, vb: String, body: String) -> String:
	return '<svg xmlns="http://www.w3.org/2000/svg"%s%s%s>%s</svg>' % [(' width="%s"' % w) if w != "" else "", (' height="%s"' % h) if h != "" else "", (' viewBox="%s"' % vb) if vb != "" else "", body]
func h(rep) -> String:
	return var_to_str(rep).sha256_text().substr(0, 16)


func _init() -> void:
	create_timer(60.0).timeout.connect(func():
		print("FAIL watchdog: 60 s")
		quit(2))
	var R := "res://tests/fixtures/c53/"
	var c15 := {
		"c15_r1": [svg("100mm","50mm","0 0 100 50",'<rect x="10" y="5" width="80" height="40"/>'), {}],
		"c15_r2": [svg("400","200","0 0 400 200",'<rect x="0" y="0" width="400" height="200"/>'), {}],
		"c15_r3": [svg("100mm","100mm","0 0 100 50",'<rect x="0" y="0" width="100" height="50"/>'), {}],
		"c15_r4": [svg("2in","1in","0 0 2 1",'<path d="M0 0 H2 V1 H0 Z"/>'), {}],
		"c15_r5": [svg("100mm","50mm","0 0 100 50",'<rect x="10" y="5" width="80" height="40"/>'), {"width_mm":60.0}],
		"c15_r6": ["hello", {}],
		"c15_r7": [svg("100mm","50mm","0 0 100 50",'<rect x="-80" y="0" width="300" height="50"/>'), {}],
		"c15_poly": [svg("50mm","50mm","0 0 50 50",'<polygon points="5,5 45,5 25,40"/><line x1="0" y1="0" x2="50" y2="50"/><polyline points="1,1 2,9 7,3"/>'), {}],
		"c15_circ": [svg("50mm","50mm","0 0 50 50",'<circle cx="25" cy="25" r="10"/>'), {}],
		"c15_curve": [svg("50mm","50mm","0 0 50 50",'<path d="M5 5 C 10 40 30 40 45 5 Q 25 0 5 5 Z"/>'), {}],
		"c15_novb": [svg("30mm","20mm","",'<rect x="1" y="1" width="10" height="5"/>'), {}],
	}
	var got := {}
	for k in c15:
		got[k] = h(SvgImport.parse(c15[k][0], c15[k][1]))
	var first = null
	for f in ["px.svg", "shapes.svg", "shapes.dxf"]:
		got["c53_" + f] = h(preload("res://scripts/build/sketch_import.gd").parse(f.get_extension(), FileAccess.get_file_as_string(R + f)))
	for f in ["px.svg", "shapes.svg"]:
		got["c15on_" + f] = h(SvgImport.parse(FileAccess.get_file_as_string(R + f)))
	ok(got.size() == EXPECT.size(), "16 outputs hashed (%d)" % got.size())
	for k in EXPECT:
		ok(got.get(k, "") == EXPECT[k], "1 %s output hash unchanged (%s)" % [k, got.get(k, "?")])
	# CONTROLS
	var bad: String = EXPECT["c15_r1"]
	bad = ("0" if bad[0] != "0" else "1") + bad.substr(1)
	ok(got["c15_r1"] != bad, "CONTROL one planted character in an expected hash is caught")
	var rep: Dictionary = SvgImport.parse(c15["c15_r1"][0], c15["c15_r1"][1])
	rep["ents"][0]["a"][0] = float(rep["ents"][0]["a"][0]) + 0.0001
	ok(h(rep) != EXPECT["c15_r1"], "CONTROL a 0.0001 nudge of one output coordinate changes the hash")
	print("c55: %d fail" % fails)
	quit(1 if fails > 0 else 0)
