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
static func new_path(nm: String, dir := WIP) -> String:
	var path := "%s/%s.json" % [dir, nm]
	var k := 2
	while FileAccess.file_exists(path):
		path = "%s/%s_%d.json" % [dir, nm, k]
		k += 1
	return path


## a name with a file in templates/: the picker's seven, or a baked one
static func has_file(nm: String) -> bool:
	return nm in NAMES or BAKED.has(nm)


## the template's scene file as a dictionary ({} when the name has no file or the file is gone)
static func read(nm: String) -> Dictionary:
	if not has_file(nm):
		return {}
	var p := "%s/%s.json" % [DIR, nm]
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


## a NEW scene from the template, written to dir (scenes/_wip); returns its path ("" = it could not be made)
static func create(nm: String, dir := WIP) -> String:
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
