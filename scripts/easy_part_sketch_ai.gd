class_name EasyPartSketchAI
extends RefCounted
## FRIDAY 191 SKETCH WITH SIZES (AI): in the Trace box (Easy Part > Draw shape > Trace) a photo of a hand sketch with the sizes written on it
## ("80" along a side, "hole 10") goes to the model the Ask AI box is set to (scripts/llm_client.gd: the same four backends, the same key row,
## the key kept in memory only). The model answers a JSON list of Easy steps in the app's OWN words; this file checks every step against the
## schema below BEFORE anything is built (an unknown step, a missing size, a hole off the part: refused in words, nothing built, no undo
## step), then applies the steps one at a time through the same records the Draw shape / Pull it up / Cut a hole / Round the edges buttons
## make: each its own undo step, each with its slider (click its row in Your steps).
## No key / no network: the words say so and the local Trace (Trace it, the photo's outline at the width you set) is offered.
## TESTS never use the network: `fixture_path` names a recorded model reply (a file in the shape the backend answers), read instead of a send.

const STEPS := ["Draw shape", "Pull it up", "Cut a hole", "Round the edges"]
const MAX_STEPS := 12
const MAX_HOLES := 8
const SIZE_MIN := 1.0
const SIZE_MAX := 1000.0
const MAX_IMAGE_PX := 1280
const DEFAULT_MODEL := {"anthropic": "claude-sonnet-5-5", "openai": "gpt-4o", "gemini": "gemini-2.0-flash"}

const SYSTEM := "You read photos of hand-drawn sketches of small parts and answer with JSON only: no words before or after it."

const PROMPT := """This is a photo of a rough hand sketch of ONE small part for 3D printing, seen from above. Sizes are written on the drawing in millimetres (for example "80" along a side, "hole 10" or "d10" beside a circle).

Reply with ONLY a JSON object {"steps": [ ... ]} that rebuilds the part in Kine's own Easy steps. Use exactly these steps and no others:
  {"step": "Draw shape", "shape": "rect", "width": 80, "height": 40}
  {"step": "Draw shape", "shape": "circle", "diameter": 60}
  {"step": "Draw shape", "shape": "polygon", "points": [[0, 0], [60, 0], [30, 40]]}
  {"step": "Pull it up", "mm": 10}
  {"step": "Cut a hole", "diameter": 10, "x": 0, "y": 0}
  {"step": "Round the edges", "mm": 2}

Rules:
- The first step is one Draw shape, the second is Pull it up (how thick the part is: use the thickness written on the sketch, or 10 if none is written).
- All numbers are millimetres. The outline is centred on (0, 0); x goes to the right of the page and y goes up the page. A polygon's points are in the same frame (they are centred for you).
- Cut a hole: diameter, and x / y = the hole's centre measured from the middle of the outline (0, 0 = the middle). Add one Cut a hole step per hole.
- Round the edges is optional and comes last; only add it if the sketch says the edges are rounded.
- Use only sizes you can read on the sketch; do not invent features. No other step names, no extra fields."""

# the test hooks
static var fixture_path := ""   # a recorded reply file (Anthropic message shape): read instead of sending
static var last_prompt := ""    # what was (or would be) sent: system, then the question
static var last_request := {}   # the request body of the last send, the picture cut down to its size
static var sends := 0           # real network sends made (a test asserts 0)

var trace          # the Trace box (easy_part_trace.gd)
var ep             # the Easy Part
var btn: Button
var busy := false
var last := {}     # {"ok", "why", "steps", "built"} of the last press

signal done


static func prompt_text() -> String:
	return "SYSTEM: %s\n\nUSER (with the photo attached): %s" % [SYSTEM, PROMPT]


# ---------------------------------------------------------------- the schema check (pure: no scene needed)

## the model's words -> the JSON inside them (a fenced block, or the first { .. } / [ .. ]); null when there is none
static func _parse(s: String) -> Variant:   # JSON.parse_string logs an engine error on prose; this stays quiet
	var j := JSON.new()
	return j.data if j.parse(s) == OK else null


static func extract_json(text: String) -> Variant:
	var s := text.strip_edges()
	var f := s.find("```")
	if f >= 0:
		var rest := s.substr(f + 3)
		if rest.begins_with("json"):
			rest = rest.substr(4)
		var e := rest.find("```")
		s = (rest.substr(0, e) if e >= 0 else rest).strip_edges()
	var v: Variant = _parse(s)
	if v != null:
		return v
	var a := s.find("{")
	var b := s.rfind("}")
	if a >= 0 and b > a:
		v = _parse(s.substr(a, b - a + 1))
		if v != null:
			return v
	a = s.find("[")
	b = s.rfind("]")
	if a >= 0 and b > a:
		return _parse(s.substr(a, b - a + 1))
	return null


## [value, why]: key k of d as a number in lo..hi
static func _num(d: Dictionary, k: String, lo: float, hi: float, ctx: String) -> Array:
	if not d.has(k):
		return [0.0, "%s needs a number called \"%s\" (mm)" % [ctx, k]]
	var v: Variant = d[k]
	if not (v is float or v is int):
		return [0.0, "%s: \"%s\" must be a number in mm, not %s" % [ctx, k, str(v)]]
	var x := float(v)
	if is_nan(x) or is_inf(x) or x < lo or x > hi:
		return [0.0, "%s: \"%s\" is %s mm, but it must be between %s and %s mm" % [ctx, k, str(snappedf(x, 0.01)), str(lo), str(hi)]]
	return [x, ""]


static func _only(d: Dictionary, allowed: Array, ctx: String) -> String:
	for k in d:
		if not (k in allowed):
			return "%s has a field \"%s\" that Easy steps do not have (it takes %s)" % [ctx, str(k), ", ".join(PackedStringArray(allowed.map(func(x): return "\"%s\"" % x)))]
	return ""


## the model's reply text -> {"ok", "steps": [normalized step dicts], "why"}. Nothing is built here; a "why" names the step number and what is wrong
static func validate(text: String) -> Dictionary:
	var v: Variant = extract_json(text)
	if v == null:
		return {"ok": false, "steps": [], "why": "The AI's answer is not a list of steps (no JSON in it), so nothing was built"}
	var list: Variant = v.get("steps") if v is Dictionary else v
	if not (list is Array):
		return {"ok": false, "steps": [], "why": "The AI's answer has no \"steps\" list, so nothing was built"}
	var arr: Array = list
	if arr.is_empty():
		return {"ok": false, "steps": [], "why": "The AI found no steps in the sketch, so nothing was built"}
	if arr.size() > MAX_STEPS:
		return {"ok": false, "steps": [], "why": "The AI gave %d steps; a sketch part is at most %d, so nothing was built" % [arr.size(), MAX_STEPS]}
	var out := []
	var drawn := false
	var pulled := false
	var hw := 0.0
	var hh := 0.0
	var round_shape := false
	var thick := 0.0
	var holes := 0
	var rounded := false
	for i in arr.size():
		var ctx := "Step %d" % (i + 1)
		if not (arr[i] is Dictionary):
			return {"ok": false, "steps": [], "why": "%s is not a step (it must be an object with a \"step\" name), so nothing was built" % ctx}
		var st: Dictionary = arr[i]
		var nm := String(st.get("step", ""))
		if not (nm in STEPS):
			return {"ok": false, "steps": [], "why": "%s is \"%s\", which is not an Easy step. The steps are: %s. Nothing was built" % [ctx, nm if nm != "" else "(no name)", ", ".join(PackedStringArray(STEPS))]}
		ctx = "Step %d (%s)" % [i + 1, nm]
		var step := {"step": nm}
		var why := ""
		match nm:
			"Draw shape":
				if drawn:
					return {"ok": false, "steps": [], "why": "%s: a sketch part has ONE outline; the second Draw shape was refused, so nothing was built" % ctx}
				var shape := String(st.get("shape", ""))
				step["shape"] = shape
				match shape:
					"rect":
						why = _only(st, ["step", "shape", "width", "height", "note"], ctx)
						var w := _num(st, "width", SIZE_MIN, SIZE_MAX, ctx)
						var h := _num(st, "height", SIZE_MIN, SIZE_MAX, ctx)
						why = why if why != "" else (String(w[1]) if String(w[1]) != "" else String(h[1]))
						step["width"] = w[0]
						step["height"] = h[0]
						hw = float(w[0]) * 0.5
						hh = float(h[0]) * 0.5
					"circle":
						why = _only(st, ["step", "shape", "diameter", "note"], ctx)
						var d := _num(st, "diameter", SIZE_MIN, SIZE_MAX, ctx)
						why = why if why != "" else String(d[1])
						step["diameter"] = d[0]
						hw = float(d[0]) * 0.5
						hh = hw
						round_shape = true
					"polygon":
						why = _only(st, ["step", "shape", "points", "note"], ctx)
						var pts: Variant = st.get("points")
						if why == "" and not (pts is Array and (pts as Array).size() >= 3 and (pts as Array).size() <= 40):
							why = "%s needs \"points\": 3 to 40 corners as [x, y] in mm" % ctx
						if why == "":
							var clean := []
							var lo := Vector2(1e9, 1e9)
							var hi := Vector2(-1e9, -1e9)
							for p in pts:
								if not (p is Array and (p as Array).size() == 2 and (p[0] is float or p[0] is int) and (p[1] is float or p[1] is int)):
									why = "%s: every corner must be [x, y] in mm" % ctx
									break
								var q := Vector2(float(p[0]), float(p[1]))
								if absf(q.x) > SIZE_MAX or absf(q.y) > SIZE_MAX:
									why = "%s: a corner is more than %s mm from the middle" % [ctx, str(SIZE_MAX)]
									break
								clean.append([q.x, q.y])
								lo = lo.min(q)
								hi = hi.max(q)
							if why == "" and (hi.x - lo.x < SIZE_MIN or hi.y - lo.y < SIZE_MIN):
								why = "%s: the outline is under %s mm across" % [ctx, str(SIZE_MIN)]
							if why == "":
								step["points"] = clean
								hw = (hi.x - lo.x) * 0.5
								hh = (hi.y - lo.y) * 0.5
					_:
						why = "%s: the shape is \"%s\", but it must be rect, circle or polygon" % [ctx, shape]
				drawn = true
			"Pull it up":
				why = _only(st, ["step", "mm", "note"], ctx)
				if why == "" and not drawn:
					why = "%s comes before any Draw shape: draw the outline first" % ctx
				if why == "" and pulled:
					why = "%s: the part is pulled up once" % ctx
				var t := _num(st, "mm", 0.2, SIZE_MAX, ctx)
				why = why if why != "" else String(t[1])
				step["mm"] = t[0]
				thick = float(t[0])
				pulled = true
			"Cut a hole":
				why = _only(st, ["step", "diameter", "x", "y", "note"], ctx)
				if why == "" and not pulled:
					why = "%s comes before Pull it up: there is nothing solid to cut yet" % ctx
				var d2 := _num(st, "diameter", 0.5, SIZE_MAX, ctx)
				why = why if why != "" else String(d2[1])
				var px := 0.0
				var py := 0.0
				if why == "":
					for k in ["x", "y"]:
						if st.has(k):
							var c := _num(st, k, -SIZE_MAX, SIZE_MAX, ctx)
							if String(c[1]) != "":
								why = String(c[1])
								break
							if k == "x":
								px = c[0]
							else:
								py = c[0]
				step["diameter"] = d2[0]
				step["x"] = px
				step["y"] = py
				holes += 1
				if why == "" and holes > MAX_HOLES:
					why = "%s: more than %d holes" % [ctx, MAX_HOLES]
				if why == "":
					var r := float(d2[0]) * 0.5
					var fits := (Vector2(px, py).length() + r <= hw + 0.01) if round_shape else (absf(px) + r <= hw + 0.01 and absf(py) + r <= hh + 0.01)
					if not fits:
						why = "%s: a hole %s mm across at x %s, y %s does not fit inside the %s x %s mm outline" % [ctx, str(snappedf(float(d2[0]), 0.1)), str(snappedf(px, 0.1)), str(snappedf(py, 0.1)), str(snappedf(hw * 2.0, 0.1)), str(snappedf(hh * 2.0, 0.1))]
			"Round the edges":
				why = _only(st, ["step", "mm", "note"], ctx)
				if why == "" and not pulled:
					why = "%s comes before Pull it up: there is nothing solid to round yet" % ctx
				if why == "" and rounded:
					why = "%s: the edges are rounded once" % ctx
				var rr := _num(st, "mm", 0.1, 50.0, ctx)
				why = why if why != "" else String(rr[1])
				step["mm"] = rr[0]
				if why == "" and float(rr[0]) * 2.0 >= thick:
					why = "%s: a %s mm round does not fit a part %s mm thick (the round must be under half the thickness)" % [ctx, str(snappedf(float(rr[0]), 0.1)), str(snappedf(thick, 0.1))]
				rounded = true
		if why != "":
			return {"ok": false, "steps": [], "why": why + ", so nothing was built"}
		out.append(step)
	if not pulled:
		return {"ok": false, "steps": [], "why": "The AI never gave a Pull it up (how thick the part is), so nothing was built"}
	return {"ok": true, "steps": out, "why": ""}


# ---------------------------------------------------------------- the picture, the model, the words

func _init(t) -> void:
	trace = t
	ep = t.ep


## the button and its row, inside the Trace box (a step's own panel: nothing new on the main Easy panel)
func attach(vb: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "easypart_sketch_ai_row"
	vb.add_child(row)
	btn = Button.new()
	btn.name = "easypart_sketch_ai"
	btn.text = "Sketch with sizes (AI)"
	btn.tooltip_text = "Send this photo of a hand sketch with sizes written on it to the AI (the model set in the Ask AI box): it becomes Draw shape, Pull it up, Cut a hole ... steps you can still change. Needs a key and the internet; Trace it works without"
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(210, 36)
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(go)
	row.add_child(btn)


## the model row the Ask AI box holds (or the saved one): backend, model, address, and the key typed there (memory only)
func settings() -> Dictionary:
	var cf := ConfigFile.new()
	cf.load(ep.m.settings)
	var out := {"backend": String(cf.get_value("ai", "backend", "ollama")), "model": String(cf.get_value("ai", "model", "glm-4.7-flash")),
		"url": String(cf.get_value("ai", "url", "")), "key": ""}
	var box = ep.m.ui_ai
	if box != null and is_instance_valid(box):
		out["backend"] = String(LlmClient.BACKENDS[box.ui_backend.selected])
		out["model"] = box.ui_model.text.strip_edges()
		out["url"] = box.ui_url.text.strip_edges()
		out["key"] = box.ui_key.text.strip_edges()
	var be := String(out["backend"])
	if be != "ollama" and String(out["model"]) in ["", "glm-4.7-flash"]:
		out["model"] = DEFAULT_MODEL.get(be, "")
	return out


func picture_b64() -> String:
	var im: Image = (trace.image as Image).duplicate()
	im.convert(Image.FORMAT_RGB8)
	var big := maxi(im.get_width(), im.get_height())
	if big > MAX_IMAGE_PX:
		var k := float(MAX_IMAGE_PX) / float(big)
		im.resize(maxi(1, int(im.get_width() * k)), maxi(1, int(im.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	return Marshalls.raw_to_base64(im.save_png_to_buffer())


## the offline words: what is missing, and the local Trace offered (the Trace it button lights up)
func _offline(why: String) -> void:
	var words := "Sketch with sizes did not run: %s. Offline, press Trace it: it traces the photo's outline at the width you set (it cannot read written sizes)" % why
	last = {"ok": false, "why": why, "steps": [], "built": 0, "offline": true}
	_say(words)
	if trace.go_btn != null:
		trace.go_btn.modulate = Color(1.0, 0.88, 0.45)


func _say(words: String) -> void:
	trace.info.text = words
	ep._say(words)


func go() -> void:
	if busy:
		return
	if trace.image == null:
		_say("Pick a photo first: press Trace, then choose your sketch")
		return
	if not Part.available():
		_say(Part.why_not())
		return
	busy = true
	if trace.go_btn != null:
		trace.go_btn.modulate = Color.WHITE
	_say("Asking the AI to read your sketch ...")
	btn.disabled = true
	var r := await ask()
	var shown := ""
	if not bool(r.get("ok", false)):
		if bool(r.get("offline", false)):
			_offline(String(r["why"]))
		else:
			_say(String(r["why"]))
	else:
		var v := validate(String(r["text"]))
		if not bool(v["ok"]):
			last = {"ok": false, "why": String(v["why"]), "steps": [], "built": 0}
			_say(String(v["why"]))
		else:
			var a := apply(v["steps"])
			last = {"ok": bool(a["ok"]), "why": String(a["why"]), "steps": v["steps"], "built": int(a["built"])}
			if bool(a["ok"]):
				shown = ", ".join(PackedStringArray((v["steps"] as Array).map(func(s): return String(s["step"]))))
				_say("Built from your sketch: %s. Each is its own step: click one in Your steps to change its number, Undo takes the last back%s" % [shown, String(a.get("note", ""))])
			else:
				_say(String(a["why"]))
	if btn != null and is_instance_valid(btn):
		btn.disabled = false
	busy = false
	done.emit()


## the model's reply for the photo: {"ok", "text", "why"}. The fixture hook replaces the send; no key = refused before anything is sent
func ask() -> Dictionary:
	var st := settings()
	var png := picture_b64()
	last_prompt = prompt_text()
	if fixture_path != "":
		var raw := FileAccess.get_file_as_string(fixture_path)
		var pr := LlmClient.parse("anthropic", 200, raw)
		return {"ok": bool(pr["ok"]), "text": String(pr.get("text", "")), "why": String(pr.get("why", "")), "offline": false}
	var be := String(st["backend"])
	var key := String(st["key"])
	var convo := [{"role": "user", "text": PROMPT, "image": png}]
	last_request = LlmClient.build(be, String(st["model"]), String(st["url"]), key, SYSTEM, convo, [])
	if be != "ollama" and key == "":
		return {"ok": false, "text": "", "offline": true, "why": "there is no AI key (type your %s key in the Ask AI box's key row)" % be}
	var cl := LlmClient.new()
	cl.name = "LlmClientSketch"
	trace.panel.add_child(cl)
	cl.backend = be
	cl.model = String(st["model"])
	cl.base_url = String(st["url"])
	cl.key = key
	sends += 1
	await cl.chat(SYSTEM, convo, [])
	var r: Dictionary = cl.last
	cl.queue_free()
	if not bool(r.get("ok", false)):
		return {"ok": false, "text": "", "offline": true, "why": String(r.get("why", "the AI did not answer"))}
	return {"ok": true, "text": String(r.get("text", "")), "why": "", "offline": false}


# ---------------------------------------------------------------- build the steps (each its own undo step)

## the validated steps -> the part: {"ok", "why", "built", "note"}. A step the kernel cannot make puts back EVERYTHING this press added (record and undo steps)
func apply(steps: Array) -> Dictionary:
	ep._flush_if_dirty()
	ep.armed = ""
	var before: Dictionary = ep._rec().duplicate(true)
	var n0: int = ep.m.undo.size()
	var notes := ""
	var built := 0
	for st in steps:
		var r := _one(st)
		if String(r["why"]) != "":
			ep.m.S.part = before
			while ep.m.undo.size() > n0:
				ep.m._drop_undo()
			ep._edit_n = -1
			ep.pu.upto = -1
			ep.pu.sync()
			ep._rows_sync()
			ep._values_sync()
			return {"ok": false, "why": "Step %d (%s) could not be built: %s. Nothing was kept" % [built + 1, String(st["step"]), String(r["why"])], "built": 0, "note": ""}
		notes += String(r.get("note", ""))
		built += 1
	return {"ok": true, "why": "", "built": built, "note": notes}


func _one(st: Dictionary) -> Dictionary:
	var label := String(st["step"])
	var snap: Dictionary = ep._rec().duplicate(true)
	ep._begin(label)
	var rec: Dictionary = ep.pu._ensure()
	var why := ""
	var note := ""
	match label:
		"Draw shape":
			why = _draw(rec, st)
		"Pull it up":
			why = _pull(rec, float(st["mm"]))
		"Cut a hole":
			why = _hole(rec, float(st["diameter"]), Vector2(float(st["x"]), float(st["y"])))
		"Round the edges":
			var r := _round(rec, float(st["mm"]))
			why = String(r["why"])
			note = String(r["note"])
	if why != "":
		ep.m.S.part = snap
		ep.m._drop_undo()
		ep._edit_n = -1
		return {"why": why}
	ep._end()
	ep.pu.upto = -1
	ep.pu.sync()
	ep._rows_sync()
	ep._values_sync()
	return {"why": "", "note": note}


func _draw(rec: Dictionary, st: Dictionary) -> String:
	var ents: Array = []
	match String(st["shape"]):
		"rect":
			var hw := float(st["width"]) * 0.5
			var hh := float(st["height"]) * 0.5
			ents = [{"k": "rect", "a": Part.arr2(Vector2(-hw, -hh)), "b": Part.arr2(Vector2(hw, hh))}]
		"circle":
			ents = [{"k": "circle", "c": Part.arr2(Vector2.ZERO), "r": float(st["diameter"]) * 0.5}]
		"polygon":
			var pts: Array = []
			var lo := Vector2(1e9, 1e9)
			var hi := Vector2(-1e9, -1e9)
			for p in st["points"]:
				var q := Vector2(float(p[0]), float(p[1]))
				pts.append(q)
				lo = lo.min(q)
				hi = hi.max(q)
			var mid := (lo + hi) * 0.5
			for i in pts.size():
				var a: Vector2 = pts[i] - mid
				var b: Vector2 = pts[(i + 1) % pts.size()] - mid
				ents.append({"k": "line", "a": Part.arr2(a), "b": Part.arr2(b)})
	rec["features"].append(Part.new_feature(rec, "sketch", {"plane": "top", "ents": ents, "dims": []}))
	ep.tweak = {}
	return ""


func _pull(rec: Dictionary, mm: float) -> String:
	var why: String = ep._pull(rec)   # the button's own rules (which op, the slider), then the sketch's number
	if why != "":
		return why
	var f: Dictionary = rec["features"][rec["features"].size() - 1]
	f["dist"] = (-mm if float(f.get("dist", 1.0)) < 0.0 else mm)
	var err: String = ep._last_error(rec, String(f["id"]))
	if err != "":
		return "the outline cannot be pulled up (%s)" % err
	return ""


func _hole(rec: Dictionary, d: float, at: Vector2) -> String:
	var before := Part.replay(rec)
	if int(before["bodies"]) == 0:
		return "nothing solid to cut a hole in"
	var bb: AABB = before["aabb"]
	var reach := maxf(absf(bb.position.y), absf(bb.end.y)) / Part.MM
	var s := Part.new_feature(rec, "sketch", {"plane": "top", "ents": [{"k": "circle", "c": Part.arr2(at), "r": snappedf(d * 0.5, 0.01)}], "dims": []})
	rec["features"].append(s)
	var f := Part.new_feature(rec, "extrude", {"sketch": s["id"], "dist": snappedf(2.0 * (reach + 10.0), 1.0), "both": true, "op": "cut"})
	rec["features"].append(f)
	var err: String = ep._last_error(rec, String(f["id"]))
	var after := float(ep.pu.replay_full(rec)["volume"])
	if err != "" or not (after < float(before["volume"]) - 1e-12 and after > 1e-9):
		return "the hole would miss the part or take it all away"
	ep.tweak = {"id": s["id"], "ent": 0, "field": "r", "label": "Hole size", "unit": "cm", "lo": 0.6, "hi": 16.0, "step": 0.1, "scale": 5.0, "words": ["Smaller", "Bigger"]}
	return ""


func _round(rec: Dictionary, mm: float) -> Dictionary:
	var mode: String = ep.round_mode
	ep.round_mode = "all"
	var why: String = ep._round(rec)
	ep.round_mode = mode
	if why != "":
		return {"why": why, "note": ""}
	var f: Dictionary = rec["features"][rec["features"].size() - 1]
	if String(f.get("t", "")) != "fillet":
		return {"why": "the edges could not be rounded", "note": ""}
	var old := float(f["r"])
	f["r"] = snappedf(mm, 0.1)
	if ep._last_error(rec, String(f["id"])) != "":
		f["r"] = old
		return {"why": "", "note": " (a %s mm round did not fit, so the edges got %s mm: the slider changes it)" % [str(snappedf(mm, 0.1)), str(old)]}
	return {"why": "", "note": ""}
