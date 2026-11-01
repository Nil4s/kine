## FRIDAY 99: Portuguese UI. The words of the app are English in the code; a translation (data/i18n/pt_BR.po, Brazilian Portuguese,
## plain everyday words) is added to Godot's TranslationServer, and every Button / Label / CheckBox / menu item whose text is one of
## its English msgids is drawn in Portuguese (Godot auto-translates Control text; the code never changes, so `button.text` stays English).
## The choice (English / Portugues) is in the start screen's Settings and is remembered in user://kine_lang.cfg.
## main.gd calls KineLang.apply_saved(testing) once at boot. A test never reads the real file (it would turn the English tests
## Portuguese): it gets English unless the env var KINE_LANG_FILE names a file.
class_name KineLang
extends RefCounted

const PO := "res://data/i18n/pt_BR.po"
const LANGS := [["en", "English"], ["pt_BR", "Português"]]   # a language's own name, the same in both
static var _tr: Translation = null
static var _added := false


static func file() -> String:
	var e := OS.get_environment("KINE_LANG_FILE")
	return e if e != "" else "user://kine_lang.cfg"


## "en" or "pt_BR": what the file remembers ("en" when there is none)
static func saved() -> String:
	var cf := ConfigFile.new()
	if cf.load(file()) != OK:
		return "en"
	var c := String(cf.get_value("lang", "code", "en"))
	return c if c == "pt_BR" else "en"


static func current() -> String:
	return "pt_BR" if TranslationServer.get_locale().begins_with("pt") else "en"


static func _load() -> void:
	if _tr == null:
		_tr = load(PO) as Translation
	if _tr != null and not _added:
		TranslationServer.add_translation(_tr)
		_added = true


## the language, now (no file written)
static func use(code: String) -> void:
	_load()
	TranslationServer.set_locale("pt_BR" if code == "pt_BR" else "en")


## the language, now, and remembered
static func set_lang(code: String) -> void:
	use(code)
	var cf := ConfigFile.new()
	cf.load(file())
	cf.set_value("lang", "code", "pt_BR" if code == "pt_BR" else "en")
	cf.save(file())


## at boot: the remembered language; a test gets English unless it names its own file
static func apply_saved(testing := false) -> void:
	if testing and OS.get_environment("KINE_LANG_FILE") == "":
		use("en")
		return
	use(saved())


## the text as drawn now: a control's own words through the translation (Control.text itself stays English)
static func shown(n: Node, english: String) -> String:
	return n.atr(english)
