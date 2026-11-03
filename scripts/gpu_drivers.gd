class_name GpuDrivers
extends RefCounted
## C11 (complaint #19): a known-bad GPU driver list (data/gpu_bad_drivers.json) and a ONE-LINE warning at start. The list is data
## (add a row, no code); a match only warns, it never blocks. Row: {"vendor": regex on the adapter name, "versions": [prefixes of the
## driver version string], "note": what goes wrong, "fix": what to do}.
const FILE := "res://data/gpu_bad_drivers.json"


static func rows(path := FILE) -> Array:
	var t := FileAccess.get_file_as_string(path)
	var j = JSON.parse_string(t) if t != "" else null
	return (j.get("bad", []) as Array) if j is Dictionary else []


## the first matching row, {} when the driver is not on the list
static func match_row(adapter: String, version: String, list: Array) -> Dictionary:
	for r in list:
		if not (r is Dictionary):
			continue
		var re := RegEx.new()
		if re.compile("(?i)" + String(r.get("vendor", "(?!)"))) != OK or re.search(adapter) == null:
			continue
		for p in r.get("versions", []):
			if version.begins_with(String(p)):
				return r
	return {}


## "" when fine, else one line
static func warning(adapter: String, version: String, list: Array) -> String:
	var r := match_row(adapter, version, list)
	if r.is_empty():
		return ""
	return "Warning: %s driver %s is known to cause problems (%s). %s" % [adapter, version, r.get("note", "see the list"), r.get("fix", "Update or roll back the driver.")]


static func warning_now() -> String:
	return warning(RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(), rows())
