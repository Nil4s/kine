class_name PartOrnamentUI
extends RefCounted
## s227: the Expert Part "Ornament" dialog (CREATE group): kind, seed, the box it fills (mm), how many, and where: at a point, on both ends of the
## part's ridge, or spread along the ridge. The same record step as the Words and Easy chip make (scripts/build/part_ornament.gd).

const WHERE := ["At a point (x, y, z below)", "On both ends of the ridge", "Spread along the ridge"]


static func open(ui, f: Dictionary, edit: int) -> void:
	var o := {}
	var kind_o := OptionButton.new()
	kind_o.name = "part_ornament_kind"
	kind_o.focus_mode = Control.FOCUS_NONE
	for k in PartOrnament.ORDER:
		kind_o.add_item(String(PartOrnament.KINDS[k]["name"]))
	var cur := String(f.get("kind", "chiwen"))
	kind_o.select(maxi(PartOrnament.ORDER.find(cur), 0))
	o["kind"] = kind_o
	ui.dlg_rows.add_child(ui._pat_row("Ornament", kind_o, ""))
	var d: Vector3 = PartOrnament.vec(f["size"]) if f.has("size") else PartOrnament.default_size(cur)
	var places: Array = f.get("places", [])
	var at0: Vector3 = PartOrnament.vec(places[0]["at"]) if not places.is_empty() else Vector3.ZERO
	var fld := func(nm: String, txt: String) -> LineEdit:
		var le: LineEdit = ui._field("part_ornament_" + nm)
		le.text = txt
		o[nm] = le
		return le
	ui.dlg_rows.add_child(ui._pat_row("Seed", fld.call("seed", str(int(f.get("seed", 1)))), ""))
	ui.dlg_rows.add_child(ui._pat_row("Long (along the ridge)", fld.call("w", ui._fmt(d.x)), "mm"))
	ui.dlg_rows.add_child(ui._pat_row("Tall", fld.call("h", ui._fmt(d.y)), "mm"))
	ui.dlg_rows.add_child(ui._pat_row("Wide (across)", fld.call("d", ui._fmt(d.z)), "mm"))
	ui.dlg_rows.add_child(ui._pat_row("How many", fld.call("n", str(int((f.get("row", {}) as Dictionary).get("n", places.size() if places.size() > 0 else 1)))), ""))
	var where_o := OptionButton.new()
	where_o.name = "part_ornament_where"
	where_o.focus_mode = Control.FOCUS_NONE
	for w in WHERE:
		where_o.add_item(w)
	where_o.select(0)
	where_o.item_selected.connect(func(_i): ui._preview())
	o["where"] = where_o
	ui.dlg_rows.add_child(ui._pat_row("Where", where_o, ""))
	ui.dlg_rows.add_child(ui._pat_row("At x", fld.call("x", ui._fmt(at0.x)), "mm"))
	ui.dlg_rows.add_child(ui._pat_row("At y (up)", fld.call("y", ui._fmt(at0.y)), "mm"))
	ui.dlg_rows.add_child(ui._pat_row("At z", fld.call("z", ui._fmt(at0.z)), "mm"))
	var dir0 := PartOrnament.vec(places[0].get("dir", [1.0, 0.0, 0.0])) if not places.is_empty() else Vector3.RIGHT
	ui.dlg_rows.add_child(ui._pat_row("Turned about up", fld.call("yaw", ui._fmt(rad_to_deg(atan2(-dir0.z, dir0.x)))), "deg"))
	kind_o.item_selected.connect(func(i: int):
		var sz := PartOrnament.default_size(String(PartOrnament.ORDER[i]))
		(o["w"] as LineEdit).text = ui._fmt(sz.x)
		(o["h"] as LineEdit).text = ui._fmt(sz.y)
		(o["d"] as LineEdit).text = ui._fmt(sz.z)
		ui._preview())
	ui.set_meta("orn", o)


## the step the dialog describes now, or {} when a number does not read
static func feature(ui) -> Dictionary:
	if not ui.has_meta("orn"):
		return {}
	var o: Dictionary = ui.get_meta("orn")
	var kind := String(PartOrnament.ORDER[clampi((o["kind"] as OptionButton).selected, 0, PartOrnament.ORDER.size() - 1)])
	var nums := {}
	for k in ["seed", "w", "h", "d", "n", "x", "y", "z", "yaw"]:
		nums[k] = ui._num(o[k])
		if is_nan(float(nums[k])):
			return {}
	var size := Vector3(float(nums["w"]), float(nums["h"]), float(nums["d"]))
	if size.x < 5.0 or size.y < 5.0 or size.z < 5.0 or size.x > 20000.0 or size.y > 20000.0 or size.z > 20000.0:
		return {}
	var n := clampi(int(nums["n"]), 1, 40)
	var places: Array = []
	var where := (o["where"] as OptionButton).selected
	var ridge: Dictionary = PartOrnament.ridge_of(ui._rec()) if where > 0 else {}
	var row := {}
	var count := n
	if kind == "corner_row":
		row = {"n": n}
		count = 1
	if where > 0 and not ridge.is_empty():
		var inset := size.x * 0.5
		places = PartOrnament.ends_of(ridge["a"], ridge["b"], inset) if where == 1 and count == 2 else PartOrnament.spread_on(ridge["a"], ridge["b"], count, inset)
	else:
		var yaw := deg_to_rad(float(nums["yaw"]))
		var dir := Vector3(cos(yaw), 0.0, -sin(yaw))
		for i in count:
			places.append({"at": PartOrnament.arr(Vector3(float(nums["x"]), float(nums["y"]), float(nums["z"])) + dir * size.x * 1.3 * float(i)), "dir": PartOrnament.arr(dir)})
	return PartOrnament.fields(kind, int(nums["seed"]), places, size, row)
