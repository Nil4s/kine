## godot --headless --path . -s tools/style_spread.gd    prints StyleDial.SPREAD as measured on scenes/ + moves/ (paste it into scripts/style_dial.gd)
extends SceneTree


func _init() -> void:
	var db := MotionMatch.build()
	var r := StyleDial.measure_spreads(db)
	for c in r["clips"]:
		print("  %-22s speed %6.1f deg/s  still %.2f  sharp %.2f  range %5.1f deg  flex %5.1f  head %.3f m  com %.3f m  knee %5.1f" % [
			c["name"], c["speed"], c["still"], c["sharp"], c["range"], c["flex"], c["head_h"], c["com_h"], c["knee"]])
	print("basis ", r["basis"])
	var s: Dictionary = r["spread"]
	print("const SPREAD := {\"move\": %.4f, \"hold\": %.4f, \"amp\": %.4f, \"flex\": %.4f, \"head\": %.4f}" % [s["move"], s["hold"], s["amp"], s["flex"], s["head"]])
	quit()
