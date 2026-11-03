class_name StickyKeys
extends RefCounted
## C11 (complaint #830): sticky modifier keys, an accessibility setting. OFF by default. When on, tapping Shift / Ctrl / Alt on its own
## (pressed and released with no other key or click between) LATCHES it: the next key press or mouse press gets that modifier, then the
## latch clears. Tapping a latched modifier again unlatches it. Holding a modifier while pressing something works as always.
## The choice is in user://kine_sticky.cfg (KINE_STICKY_FILE names another; a test never touches the real file).
const MODS := {KEY_SHIFT: "shift", KEY_CTRL: "ctrl", KEY_ALT: "alt"}
static var current: StickyKeys = null   # the app's live one; held() reads it
var on := false
var _applied := {}   # modifiers a press just took: still 'held' for that press's handlers until the next press
var latched := {}   # "shift"/"ctrl"/"alt" -> true
var _down := {}     # modifier name -> still a clean tap


static func file() -> String:
	var e := OS.get_environment("KINE_STICKY_FILE")
	return e if e != "" else "user://kine_sticky.cfg"


static func saved() -> bool:
	var cf := ConfigFile.new()
	return cf.load(file()) == OK and bool(cf.get_value("sticky", "on", false))


static func save(v: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(file())
	cf.set_value("sticky", "on", v)
	cf.save(file())


## the one place the app asks 'is Shift / Ctrl / Alt down': the real key state OR a sticky latch. Sticky off (or none) = is_key_pressed exactly.
static func held(k: int) -> bool:
	var real := Input.is_key_pressed(k)
	var s := current
	if s == null or not s.on or not MODS.has(k):
		return real
	var nm: String = MODS[k]
	return real or s.latched.has(nm) or s._applied.has(nm)


func set_on(v: bool) -> void:
	on = v
	_applied.clear()
	if not v:
		latched.clear()
		_down.clear()


## the modifiers waiting for the next key, e.g. "Shift+Ctrl" ("" when none): for a status line
func label() -> String:
	var parts := []
	for k in ["shift", "ctrl", "alt"]:
		if latched.has(k):
			parts.append(k.capitalize())
	return "+".join(parts)


## call with every input event, first. Edits the event in place (adds the latched modifiers); true when the event was only a
## modifier tap-in-progress (callers may ignore it).
func filter(ev: InputEvent) -> void:
	if not on:
		return
	if (ev is InputEventKey and (ev as InputEventKey).pressed and not MODS.has((ev as InputEventKey).keycode)) or (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed):
		_applied.clear()   # a new press: the last press's modifiers are spent
	if ev is InputEventKey:
		var k := ev as InputEventKey
		if MODS.has(k.keycode):
			var nm: String = MODS[k.keycode]
			if k.echo:
				return
			if k.pressed:
				_down[nm] = true
			else:
				if _down.get(nm, false):
					if latched.has(nm):
						latched.erase(nm)
					else:
						latched[nm] = true
				_down.erase(nm)
			return
		if k.pressed:
			_apply(k)
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		_apply(ev as InputEventWithModifiers)


func _apply(e: InputEventWithModifiers) -> void:
	for nm in _down.keys():
		_down[nm] = false   # a modifier held across another press is a chord, not a tap
	if latched.is_empty():
		return
	e.shift_pressed = e.shift_pressed or latched.has("shift")
	e.ctrl_pressed = e.ctrl_pressed or latched.has("ctrl")
	e.alt_pressed = e.alt_pressed or latched.has("alt")
	for nm in latched:
		_applied[nm] = true
	latched.clear()
