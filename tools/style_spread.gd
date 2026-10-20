## godot --headless --path . -s tools/style_spread.gd    prints StyleDial.SPREAD as measured on scenes/ + moves/ (paste it into scripts/style_dial.gd)
extends SceneTree


func _init() -> void:
	var db := MotionMatch.build()
	var res := StyleDial.measure_spreads(db)
	for c in res["clips"]:
		print("  %-22s speed %6.1f deg/s  still %.2f  sharp %.2f  range %5.1f deg  flex %5.1f  head %.3f m  com %.3f m  knee %5.1f" % [
			c["name"], c["speed"], c["still"], c["sharp"], c["range"], c["flex"], c["head_h"], c["com_h"], c["knee"]])
	print("basis ", res["basis"])
	var s: Dictionary = res["spread"]
	print("const SPREAD := {\"move\": %.4f, \"hold\": %.4f, \"amp\": %.4f, \"flex\": %.4f, \"head\": %.4f}" % [s["move"], s["hold"], s["amp"], s["flex"], s["head"]])
	var files := []
	for c in (db["clips"] as Array):
		if String(c["path"]).begins_with("res://scenes/"):
			files.append(String(c["path"]))
	files.sort()
	var rows := StyleDial.measure_rows(db, ["res://scenes/"], files)
	print("const SPREAD_CLIPS := {")
	for p in files:
		var r: Dictionary = rows[p]
		print("\t%s: {\"md5\": %s, \"mv\": %.6f, \"hd\": %.6f, \"range\": %.6f, \"flex\": %.6f, \"head\": %.6f}," % [JSON.stringify(p), JSON.stringify(r["md5"]), r["mv"], r["hd"], r["range"], r["flex"], r["head"]])
	print("}")
	quit()
