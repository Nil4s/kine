extends RefCounted
## CH16 power and signal model. Sony's published battery/CIPA values are SEEN; every rail/load/efficiency/duty value is ASSUMED in
## docs/CH16_REFERENCE.md section 4. Removing a regulator never removes its loads: the planted control must become unsupplied.
const VBAT := 7.2
const AH := 1.020
const CIPA := 340.0
const EFF := 0.90
const DUTY_S := 12.0
const BUDGET_W := 8.0


static func rails() -> Array:
	return [
		{"id": "buck_core", "reg": "BUCK CORE", "v": 1.1, "w": 1.10, "loads": ["BIONZ X"]},
		{"id": "buck_sensor", "reg": "BUCK SENSOR", "v": 1.8, "w": 0.85, "loads": ["CMOS SENSOR"]},
		{"id": "buck_io", "reg": "BUCK I/O", "v": 3.3, "w": 1.20, "loads": ["DRAM", "SD CARD", "USB", "HDMI", "WI-FI/NFC"]},
		{"id": "boost_display", "reg": "BOOST DISPLAY", "v": 5.0, "w": 0.65, "loads": ["OLED EVF", "LCD"]},
		{"id": "direct_motor", "reg": "DIRECT MOTOR", "v": 7.2, "w": 0.80, "loads": ["SHUTTER DRIVER"]}
	]


static func ics() -> Array:
	return [
		{"id": "BIONZ X", "rail": "buck_core", "signal": "sensor MIPI/LVDS in; DRAM, SD, EVF, LCD, HDMI, USB, Wi-Fi data; shutter/sensor control"},
		{"id": "CMOS SENSOR", "rail": "buck_sensor", "signal": "MIPI/LVDS image data to BIONZ X; timing control in"},
		{"id": "DRAM", "rail": "buck_io", "signal": "parallel image buffer bus to BIONZ X"},
		{"id": "SD CARD", "rail": "buck_io", "signal": "SD command/data to BIONZ X"},
		{"id": "USB", "rail": "buck_io", "signal": "USB D+/D- to BIONZ X"},
		{"id": "HDMI", "rail": "buck_io", "signal": "HDMI TMDS from BIONZ X"},
		{"id": "WI-FI/NFC", "rail": "buck_io", "signal": "SDIO/control to BIONZ X; RF to antenna"},
		{"id": "OLED EVF", "rail": "boost_display", "signal": "LVDS video from BIONZ X"},
		{"id": "LCD", "rail": "boost_display", "signal": "RGB/SPI video and control from BIONZ X"},
		{"id": "SHUTTER DRIVER", "rail": "direct_motor", "signal": "H-bridge gate/control from BIONZ X; motor outputs"},
		{"id": "PMIC", "rail": "input", "signal": "enable/status I2C to BIONZ X; all regulator outputs"},
		{"id": "PROTECTION", "rail": "input", "signal": "battery ID/thermistor and fault status to PMIC"}
	]


static func model(opts := {}) -> Dictionary:
	var omit := String(opts.get("omit_reg", ""))
	var rr := rails()
	var load_sum := 0.0
	for r in rr:
		load_sum += float(r["w"])                         # deliberately includes a load whose regulator is omitted
	var input_w := load_sum / EFF
	var energy := VBAT * AH
	var shot_wh := energy / CIPA
	var shot_j := shot_wh * 3600.0
	var duty_j := input_w * DUTY_S
	var present := {}
	for r in rr:
		if String(r["id"]) != omit:
			present[String(r["id"])] = true
	present["input"] = true
	var missing: Array = []
	for ic in ics():
		var id := String(ic["id"])
		var rail := String(ic["rail"])
		var power_ok := present.has(rail)
		var signal_ok := String(ic["signal"]).strip_edges() != ""
		if not power_ok:
			missing.append(id + ": no power (" + rail + " regulator omitted)")
		if not signal_ok:
			missing.append(id + ": no signal")
	var budget_ok := omit == "" and input_w <= BUDGET_W and duty_j <= shot_j and missing.is_empty()
	return {"rails": rr, "ics": ics(), "energy_Wh": energy, "shot_Wh": shot_wh, "shot_J": shot_j, "rail_W": load_sum,
		"input_W": input_w, "budget_W": BUDGET_W, "duty_J": duty_j, "budget_ok": budget_ok, "missing_connections": missing, "omit_reg": omit}
