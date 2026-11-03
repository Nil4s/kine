class_name CharScale
extends RefCounted
## C21 (complaint #40, a Mixamo character arrives tiny): a character that comes in under 0.3 m or over 5 m tall gets a one-click
## "Scale to 1.75 m". verdict() says whether it is off and by how much; offer() puts the button on screen; fix() does it: the file
## is copied into the library like any prop and registered at the factor that makes it 1.75 m tall. The original file is never changed.

const MIN_H := 0.3
const MAX_H := 5.0
const TARGET_H := 1.75


## {"off": bool, "height": m, "factor": multiply by this, "text": plain words} from Importer.inspect's answer
static func verdict(info: Dictionary) -> Dictionary:
	var h := float((info.get("size", Vector3.ZERO) as Vector3).y)
	var out := {"off": false, "height": h, "factor": 1.0, "text": ""}
	if h <= 0.0 or (h >= MIN_H and h <= MAX_H):
		return out
	out["off"] = true
	out["factor"] = TARGET_H / h
	var tall := Importer._len(h)
	out["text"] = "This character is %s tall, %s. One click scales it to 1.75 m (x%s)." % [tall, "far too small to animate with" if h < MIN_H else "far too big to fit a set", Importer._round3(TARGET_H / h)]
	return out


## copy the file into the library as a prop at the 1.75 m factor and put it in the set. Returns {"ok", "kind", "height", "factor", "why"}
static func fix(main: Node, path: String, info: Dictionary) -> Dictionary:
	var v := verdict(info)
	var r := {"ok": false, "kind": "", "height": 0.0, "factor": float(v["factor"]), "why": ""}
	if not bool(v["off"]):
		r["why"] = "This character is already a believable height, so nothing was scaled."
		return r
	var a: Dictionary = Importer.accept(path, "prop", main.library)
	if not a["ok"]:
		r["why"] = String(a["why"])
		return r
	var kind := "my " + String(a["path"]).get_file().get_basename()
	Props.register(kind, info["aabb"], a["path"], float(v["factor"]))
	main._prop_add(kind)
	r["ok"] = true
	r["kind"] = kind
	r["height"] = float((info["size"] as Vector3).y) * float(v["factor"])
	return r


## the one-click button: a small panel at the bottom of the window. Returns the panel (null when the height is believable)
static func offer(main: Node, path: String, info: Dictionary) -> Control:
	var v := verdict(info)
	if not bool(v["off"]):
		return null
	var old := main.find_child("char_scale_offer", true, false)
	if old != null:
		old.queue_free()
	var pc := PanelContainer.new()
	pc.name = "char_scale_offer"
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	pc.add_child(hb)
	var lb := Label.new()
	lb.name = "char_scale_text"
	lb.text = String(v["text"])
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.custom_minimum_size = Vector2(420, 0)
	hb.add_child(lb)
	var go := Button.new()
	go.name = "char_scale_fix"
	go.text = "Scale to 1.75 m"
	go.pressed.connect(func():
		var r := fix(main, path, info)
		main._say(("%s scaled to 1.75 m and added to the set" % path.get_file()) if r["ok"] else String(r["why"]))
		pc.queue_free())
	hb.add_child(go)
	var no := Button.new()
	no.name = "char_scale_keep"
	no.text = "Keep it"
	no.pressed.connect(pc.queue_free)
	hb.add_child(no)
	main.add_child(pc)
	return pc
