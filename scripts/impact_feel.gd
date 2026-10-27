## impact_feel.gd - I3 IMPACT FEEL CURVES. Every blow of the fighters' report (ImpactFrames.blows: each one measured by HitPhysics.measure,
## impulse J in N s) becomes one rumble event for a game controller's haptic call: at t (the contact, the same time as the impact frames)
## play the motor at `strength` for `length` seconds.
##   STRENGTH  clamp(J / J_FULL, 0, 1): linear in the impulse, so a blow twice as big gives twice the motor strength; a blow of J_FULL
##             (25 N s, ImpactFrames' J_HI, the heaviest blow ImpactFrames scales for) or more is full strength.
##   LENGTH    the camera shake's length of the same blow (ImpactFrames.shake: 6 to 12 frames at 30 fps, 0.2 to 0.4 s), so the rumble
##             ends with the shake. No new number: the same scaling as the hit-stop and the shake.
## The file is <name>_impact_feel.json next to the .glb (EngineExport.export writes it for every engine export: "events" is empty when
## no blow lands on a body part, or when the scene has one fighter). Pure: no node, no scene is changed.
class_name ImpactFeel
extends RefCounted

const FORMAT := "kine-impact-feel-1"
const J_FULL := 25.0
const SUFFIX := "_impact_feel.json"


## the motor strength (0..1 of full) of a blow of impulse J (N s)
static func strength_of(J: float) -> float:
	return clampf(J / J_FULL, 0.0, 1.0)


## one event per blow, by time: blows as ImpactFrames.blows gives them ([{"t", "J", "victim"}])
static func events(blows: Array) -> Array:
	var out := []
	for e in blows:
		var J := float(e["J"])
		out.append({"t": snappedf(float(e["t"]), 1e-6), "victim": int(e["victim"]), "strength": snappedf(strength_of(J), 0.001),
			"length": snappedf(float(ImpactFrames.shake(0.0, J)["dur"]), 0.001), "J": snappedf(J, 0.01)})
	return out


static func sidecar(blows: Array, fps: int, scene_name: String) -> Dictionary:
	return {"format": FORMAT, "scene": scene_name, "fps": fps, "units": "strength 0..1 of full motor, length s, J N s",
		"note": "Each event: play the motor at strength for length seconds, starting at t (seconds from the clip's start). victim = the fighter index (0 = the first) whose controller it is. No events: no blow lands on a body part.",
		"events": events(blows)}


## the file beside the .glb: <name>_impact_feel.json
static func path_for(glb_path: String) -> String:
	return glb_path.get_basename() + SUFFIX


## writes data beside the .glb; returns the path, or "" when the file cannot be opened
static func write(glb_path: String, data: Dictionary) -> String:
	var path := path_for(glb_path)
	var abs_p := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	var f := FileAccess.open(abs_p, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return path
