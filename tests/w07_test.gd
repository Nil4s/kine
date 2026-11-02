## godot --headless --path . -s tests/w07_test.gd   (W07: arithmetic in number fields)
## Bars (written first): '25*2+3' -> 53; '(10+5)/3' -> 5; '-2*-3' -> 6; '2+' refused with words; '10/0' refused;
## '1.5in+2' evaluates with unit 'in' carried; '2^3' and 'x' and '__import__' refused (no objects); a size field
## (PartUI.typed_mm) takes '25*2+3' as 53 mm and '2+', '10/0', '5-9' as -1 with words from _size_words;
## a refused entry leaves a real dimension at its old value. CONTROL: a plain evaluator that ignored precedence would give 56.
extends SceneTree

var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func v(t: String) -> float:
	var r := NumExpr.eval(t)
	return float(r["value"]) if r["ok"] else NAN


func _init() -> void:
	ok(absf(v("25*2+3") - 53.0) < 1e-9, "25*2+3 = 53")
	ok(absf(v("25*2+3") - 56.0) > 1.0, "control: left-to-right (56) is not what we give")
	ok(absf(v("(10+5)/3") - 5.0) < 1e-9, "(10+5)/3 = 5")
	ok(absf(v("-2*-3") - 6.0) < 1e-9, "-2*-3 = 6")
	ok(absf(v(" 1.5e1 + .5 ") - 15.5) < 1e-9, "1.5e1 + .5 = 15.5")
	var r := NumExpr.eval("2+")
	ok(not r["ok"] and String(r["err"]) != "", "2+ refused: " + String(r["err"]))
	r = NumExpr.eval("10/0")
	ok(not r["ok"] and "zero" in String(r["err"]), "10/0 refused: " + String(r["err"]))
	r = NumExpr.eval("(1+2")
	ok(not r["ok"], "(1+2 refused: " + String(r["err"]))
	for bad in ["2^3", "x", "__import__('os')", "1+OS.execute()", "", "3 3", "1..2"]:
		ok(not NumExpr.eval(bad)["ok"], "refused: '%s'" % bad)
	r = NumExpr.eval("1.5in+2")
	ok(r["ok"] and absf(float(r["value"]) - 3.5) < 1e-9 and r["unit"] == "in", "1.5in+2 = 3.5, unit 'in' carried")
	r = NumExpr.eval("4 cm * 2")
	ok(r["ok"] and r["unit"] == "cm" and absf(float(r["value"]) - 8.0) < 1e-9, "4 cm * 2 = 8 cm carried")
	ok(PartUI.typed_mm("25*2+3") == 53.0, "typed_mm 25*2+3 = 53")
	ok(PartUI.typed_mm("40") == 40.0 and PartUI.typed_mm("4 cm") == 40.0, "plain 40 and 4 cm unchanged")
	ok(PartUI.typed_mm("(2+2) cm") == 40.0 or PartUI.typed_mm("(2+2)*10") == 40.0, "bracket sum")
	ok(PartUI.typed_mm("2+") == -1.0 and PartUI.typed_mm("10/0") == -1.0 and PartUI.typed_mm("5-9") == -1.0, "bad sums give -1")
	# a real dimension keeps its old value on a refused entry
	if ClassDB.class_exists("Node"):
		var sk := {"ents": [{"k": "line", "a": [0.0, 0.0], "b": [10.0, 0.0]}]}
		Part.set_dim(sk, 0, "len", 10.0)
		var old: float = sk["dims"][0]["mm"]
		for t in ["2+", "10/0"]:
			var mm := PartUI.typed_mm(t)
			if mm > 0.0:
				Part.set_dim_held(sk, 0, "len", mm)
		ok(sk["dims"][0]["mm"] == old, "refused entries keep the old value (%s)" % old)
		var mm2 := PartUI.typed_mm("25*2+3")
		ok(mm2 > 0.0 and Part.set_dim_held(sk, 0, "len", mm2) == "" and absf(float(sk["dims"][0]["mm"]) - 53.0) < 1e-6, "accepted entry sets 53")
	print("W07 %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
