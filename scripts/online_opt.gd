## online_opt.gd - L16: the two opt-in online settings (update check, crash upload) in user://online.cfg. Both OFF and EMPTY by default.
class_name OnlineOpt
extends RefCounted

const PATH := "user://online.cfg"


static func load_cfg(path: String = PATH) -> Dictionary:
	var out := {"update": UpdateCheck.default_cfg(), "crash": CrashUpload.default_cfg()}
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return out
	out["update"]["enabled"] = bool(cf.get_value("update", "enabled", false))
	out["update"]["feed_url"] = str(cf.get_value("update", "feed_url", ""))
	out["crash"]["enabled"] = bool(cf.get_value("crash", "enabled", false))
	out["crash"]["endpoint"] = str(cf.get_value("crash", "endpoint", ""))
	return out


static func save_cfg(path: String, c: Dictionary) -> void:
	var cf := ConfigFile.new()
	cf.set_value("update", "enabled", bool(c["update"]["enabled"]))
	cf.set_value("update", "feed_url", str(c["update"]["feed_url"]))
	cf.set_value("crash", "enabled", bool(c["crash"]["enabled"]))
	cf.set_value("crash", "endpoint", str(c["crash"]["endpoint"]))
	cf.save(path)
