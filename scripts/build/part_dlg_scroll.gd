class_name PartDlgScroll
extends RefCounted
## C58: a Part side dialog's ROWS scroll when the panel would run under the timeline; OK / Cancel / info stay outside the scroll box, pinned under it.

const MIN_H := 60.0


## puts `rows` in a ScrollContainer as the first child of `box`; returns it
static func wrap(box: VBoxContainer, rows: VBoxContainer) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.name = "part_dialog_scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.mouse_filter = Control.MOUSE_FILTER_PASS   # row clicks go through to the rows
	box.add_child(sc)
	box.move_child(sc, 0)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(rows)
	return sc


## the scroll box is as tall as its rows, or shorter by what the side panel overflows `avail`
static func fit(sc: ScrollContainer, rows: Control, side: Control, avail: float) -> void:
	if sc == null or not sc.is_visible_in_tree():
		return
	var h := rows.get_combined_minimum_size().y
	sc.custom_minimum_size.y = h
	side.reset_size()
	var over := side.get_combined_minimum_size().y - avail
	if over > 0.0:
		sc.custom_minimum_size.y = maxf(MIN_H, h - over)
		side.reset_size()
