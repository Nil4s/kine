class_name GpuNotice
extends RefCounted
## W14: which GPU Kine draws with, and a warning (with the Windows Graphics settings steps) when it is an integrated one
## while the PC has another. Quality.gd already drops integrated parts to Low; this tells the user why and how to switch.

const STEPS := "To use the faster GPU: Windows Settings > System > Display > Graphics > Browse, add Kine's .exe, click Options, choose High performance, Save, then restart Kine."


static func is_integrated(name: String) -> bool:
	var r := RegEx.new()
	r.compile(r"intel|uhd|hd graphics|iris|radeon\(tm\) graphics|vega")
	return r.search(name.to_lower()) != null


## adapters: every GPU name on the PC (may be just the active one); active: the one in use. Single GPU: no warning.
static func line(adapters: Array, active: String) -> String:
	var other := ""
	for a in adapters:
		if String(a) != active and not is_integrated(String(a)):
			other = String(a)
			break
	if is_integrated(active) and other != "":
		return "Graphics card in use: %s (integrated). This PC also has %s, so Kine is running slower than it could and drops to Low quality. %s" % [active, other, STEPS]
	return "Graphics card in use: %s" % active


## every GPU name Windows knows (only when the active one is integrated: costs a moment). Empty elsewhere.
static func list_windows() -> Array:
	if OS.get_name() != "Windows":
		return []
	var out := []
	OS.execute("powershell", ["-NoProfile", "-Command", "(Get-CimInstance Win32_VideoController).Name"], out, true)
	var res := []
	for s in String("".join(out)).split("\n", false):
		if s.strip_edges() != "":
			res.append(s.strip_edges())
	return res
