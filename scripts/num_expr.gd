class_name NumExpr
## W07: a safe arithmetic evaluator for number fields. Numbers, + - * / and parentheses only (unary - and + too);
## no Godot Expression, so user text never reaches an object. A number token may carry a unit suffix ("1.5in",
## "4 cm"): the suffix is passed through untouched (not converted here, W06 combines units).
## eval(text) -> {"ok": bool, "value": float, "err": String, "unit": String (first suffix seen, "" none),
##                "units": Array (distinct suffixes in order)}

static func eval(text: String) -> Dictionary:
	var p := {"s": text.strip_edges(), "i": 0, "units": []}
	if String(p["s"]) == "":
		return _fail("type a number or a sum such as 25*2+3")
	var r = _expr(p)
	if r == null:
		return _fail(String(p.get("err", "not a sum I can read")))
	_skip(p)
	if int(p["i"]) < String(p["s"]).length():
		return _fail("unexpected '%s' in the sum" % String(p["s"])[int(p["i"])])
	var v: float = r
	if is_nan(v) or is_inf(v):
		return _fail("that sum has no finite value")
	var us: Array = p["units"]
	return {"ok": true, "value": v, "err": "", "unit": "" if us.is_empty() else String(us[0]), "units": us}


## true when the text has an operator or bracket (past a leading sign or an exponent), i.e. is more than a plain number
static func is_expression(text: String) -> bool:
	var t := text.strip_edges()
	for i in t.length():
		var c := t[i]
		if c in ["*", "/", "(", ")"]:
			return true
		if c in ["+", "-"] and i > 0 and not (t[i - 1] in ["e", "E"]):
			return true
	return false


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "value": 0.0, "err": msg, "unit": "", "units": []}


static func _skip(p: Dictionary) -> void:
	var s: String = p["s"]
	while int(p["i"]) < s.length() and s[int(p["i"])] in [" ", "\t"]:
		p["i"] = int(p["i"]) + 1


static func _expr(p: Dictionary):
	var a = _term(p)
	if a == null:
		return null
	while true:
		_skip(p)
		var s: String = p["s"]
		var i: int = p["i"]
		if i >= s.length() or not (s[i] in ["+", "-"]):
			break
		p["i"] = i + 1
		var b = _term(p)
		if b == null:
			return null
		a = float(a) + float(b) if s[i] == "+" else float(a) - float(b)
	return a


static func _term(p: Dictionary):
	var a = _unary(p)
	if a == null:
		return null
	while true:
		_skip(p)
		var s: String = p["s"]
		var i: int = p["i"]
		if i >= s.length() or not (s[i] in ["*", "/"]):
			break
		p["i"] = i + 1
		var b = _unary(p)
		if b == null:
			return null
		if s[i] == "*":
			a = float(a) * float(b)
		else:
			if absf(float(b)) < 1e-12:
				p["err"] = "cannot divide by zero"
				return null
			a = float(a) / float(b)
	return a


static func _unary(p: Dictionary):
	_skip(p)
	var s: String = p["s"]
	var i: int = p["i"]
	if i < s.length() and s[i] in ["+", "-"]:
		p["i"] = i + 1
		var v = _unary(p)
		if v == null:
			return null
		return -float(v) if s[i] == "-" else float(v)
	return _atom(p)


static func _atom(p: Dictionary):
	_skip(p)
	var s: String = p["s"]
	var i: int = p["i"]
	if i >= s.length():
		p["err"] = "the sum ends early: a number is missing"
		return null
	if s[i] == "(":
		p["i"] = i + 1
		var v = _expr(p)
		if v == null:
			return null
		_skip(p)
		if int(p["i"]) >= s.length() or s[int(p["i"])] != ")":
			p["err"] = "a closing bracket is missing"
			return null
		p["i"] = int(p["i"]) + 1
		return v
	var j := i
	var digits := 0
	while j < s.length() and (s[j] >= "0" and s[j] <= "9"):
		j += 1
		digits += 1
	if j < s.length() and s[j] == ".":
		j += 1
		while j < s.length() and (s[j] >= "0" and s[j] <= "9"):
			j += 1
			digits += 1
	if digits == 0:
		p["err"] = "expected a number, found '%s'" % s[i]
		return null
	if j < s.length() and (s[j] == "e" or s[j] == "E") and j + 1 < s.length() and (s[j + 1] in ["+", "-"] or (s[j + 1] >= "0" and s[j + 1] <= "9")):
		var k := j + 1
		if s[k] in ["+", "-"]:
			k += 1
		if k < s.length() and s[k] >= "0" and s[k] <= "9":
			while k < s.length() and s[k] >= "0" and s[k] <= "9":
				k += 1
			j = k
	var num := s.substr(i, j - i)
	# an optional unit suffix (letters, " or '), carried through untouched
	var u := j
	while u < s.length() and s[u] == " ":
		u += 1
	var e := u
	while e < s.length() and ((s[e].to_lower() >= "a" and s[e].to_lower() <= "z") or s[e] in ["\"", "'", "°", "µ"]):
		e += 1
	if e > u:
		var unit := s.substr(u, e - u)
		var us: Array = p["units"]
		if not us.has(unit):
			us.append(unit)
		j = e
	p["i"] = j
	return float(num)
