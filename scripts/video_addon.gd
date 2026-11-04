class_name VideoAddon
extends RefCounted
## C78: the installed Kine (an exported build) ships WITHOUT Python. Every feature that shells out to a Python tool (video import,
## several cameras, webcam puppet, reference image, Make it physical, hit simulation, QR pictures, generated moves) asks gate() first and
## says its sentence instead of failing on a missing interpreter. Run from source / the editor, gate() is always "" (nothing changes).
## The add-on is a folder beside Kine.exe: addon/python/python.exe (+ its wheels) and tools/*.py. See docs/C78_INSTALLER.md.

const NOTE := "needs the video add-on (Python with mediapipe and opencv), which this install does not include: install the Kine video add-on, or run Kine from the source folder"


static func exported() -> bool:
	return OS.has_feature("template") and not OS.has_feature("editor")


static func addon_dir() -> String:
	return OS.get_executable_path().get_base_dir().path_join("addon")


## is the add-on beside Kine.exe? (always true when not an exported build)
static func installed() -> bool:
	if not exported():
		return true
	return FileAccess.file_exists(addon_dir().path_join("python/python.exe"))


## "" when the Python features can run; else the sentence to say. feature = what the user was doing ("tracking a video")
static func gate(feature: String) -> String:
	if installed():
		return ""
	return "%s %s" % [feature, NOTE]
