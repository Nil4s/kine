## templates.gd - STARTING SCENES (ROADMAP 44): "New from template..." lists eight (walk, run, jump, punch, sword swing, sit down, wave, fall); picking
## one copies it to a NEW file scenes/_wip/<template>[_N].json (never over one) and the app opens that copy. The templates
## themselves are the files in templates/ (read only; tools/make_templates.gd writes them from tools/template_plans.gd, and
## tests/templates_test.gd measures each against the real human data cited in the plan).
class_name Templates
extends RefCounted

const DIR := "res://templates"
const WIP := "res://scenes/_wip"
const NAMES := ["walk", "run", "jump", "punch", "sword_swing", "sit_down", "wave", "fall"]
## baked files the picker does NOT list: name -> the words TextBlocking builds them from (tools/make_templates.gd bakes them).
## "roundhouse" is StrikeBlocking's generated kick: built live it took ~3.6 s on Easy's Kick card, so the file holds that build.
const BAKED := {"roundhouse": "roundhouse"}
## names built from another template's file, played backwards: "stand up" is "sit down" reversed (walk-through round 7: from the
## seat or the floor, Kine had no stand move). The reversed file is made in read(), never written to templates/.
const DERIVED := {"stand_up": "sit_down"}
## the picker's text: [title, what you get]
const INFO := {
	"walk": ["Walk", "A half step, five steps at 105 a minute, feet together; arms swing against the legs."],
	"run": ["Run", "A slow jog of seven strides at 170 steps a minute, a flight between the footfalls, arms against the legs."],
	"jump": ["Jump", "Stand, dip, push off, fly, land soft in a crouch and stand: a 0.40 m countermovement jump."],
	"punch": ["Punch", "A guard, a cross: the back foot turns, the hips and shoulders open, the fist reaches and returns."],
	"sword_swing": ["Sword swing", "A one-hand cut across the body: hips, then chest, then the arm, then the blade."],
	"sit_down": ["Sit down", "From standing onto a chair: the knees bend, the trunk leans forward and comes back up, feet planted."],
	"wave": ["Wave", "The right hand raised, the forearm swung side to side two and a half times, then lowered."],
	"fall": ["Fall", "A backward breakfall: off balance, one step back into a deep crouch, sit down close to the heel, roll onto the back, arms slapping the floor."],
}


## a path in WIP not taken yet: <name>.json, <name>_2.json, ... (a template never writes over a scene)
## FREE NAME FAST (2000+ Easy clips in scenes/_wip: every card click probed walk_2..walk_907 one file at a time): the last free
## number found for a dir + name is remembered and the probe starts there. The first free name at or after it, as before; a file
## deleted below it is skipped (a gap, harmless). `probes` counts file checks (tests)
static var _next_k := {}
static var probes := 0


static func new_path(nm: String, dir := WIP) -> String:
	var key := dir + "|" + nm
	var k: int = _next_k.get(key, 2)
	var path := "%s/%s.json" % [dir, nm]
	if k == 2:
		probes += 1
	if k > 2 or FileAccess.file_exists(path):
		path = "%s/%s_%d.json" % [dir, nm, k]
		probes += 1
		while FileAccess.file_exists(path):
			k += 1
			path = "%s/%s_%d.json" % [dir, nm, k]
			probes += 1
		_next_k[key] = k + 1
	return path


## a name with a file in templates/: the picker's seven, or a baked one
static func has_file(nm: String) -> bool:
	return nm in NAMES or BAKED.has(nm) or DERIVED.has(nm)


## the template's scene file as a dictionary ({} when the name has no file or the file is gone)
static func read(nm: String) -> Dictionary:
	if DERIVED.has(nm):
		var src := read(String(DERIVED[nm]))
		return backwards(src) if not src.is_empty() else {}
	if not has_file(nm):
		return {}
	var p := "%s/%s.json" % [DIR, nm]
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


## a template's cards played backwards (the last card first). A card keeps its own pose and hold; the time INTO each card in the
## new order is the time OUT of the card after it in the old one (its move). Flow flags are dropped: a pass-through key has no
## meaning played back. The chair and the other props stay where the file put them.
static func backwards(d: Dictionary) -> Dictionary:
	var cards: Array = d.get("cards", [])
	var n := cards.size()
	if n == 0:
		return {}
	var out: Array = []
	for k in n:
		var c: Dictionary = (cards[n - 1 - k] as Dictionary).duplicate(true)
		c["move"] = -1.0 if k == 0 else float((cards[n - k] as Dictionary)["move"])
		c.erase("flow")
		c.erase("arrive_s")
		c.erase("leave_s")
		out.append(c)
	var r := d.duplicate(true)
	r["cards"] = out
	r["note"] = "STAND UP: the sit_down template played backwards (templates.gd backwards())"
	r["plan"] = "templates/sit_down, reversed"
	return r


## a NEW scene from the template, written to dir (scenes/_wip); returns its path ("" = it could not be made)
static func create(nm: String, dir0 := WIP) -> String:
	var dir := UserPaths.w(dir0)   # an exported build: the user's folder (res:// is read-only)
	var d := read(nm)
	if d.is_empty():
		return ""
	var path := new_path(nm, dir)
	d["scene"] = path.get_file().get_basename()
	d["plan"] = "from the %s template" % String(INFO[nm][0]).to_lower()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(d, " "))
	f.close()
	return path
