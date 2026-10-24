## godot --path . -s tests/cardstrip_test.gd     (the scene strip's rework; needs a window)
## THE SCENE STRIP AS PICTURES. BARS (written before measuring):
##  1 at 1600 x 900 with combo3 (12 cards) the strip shows every card; with 20 cards at least 16 are FULLY visible (the old
##    strip: 8); the strip is not taller than before (card row <= 112 px, the bottom panel == BOTTOM_H)
##  2 the header is the name box + ONE Scene menu + Fold, all icons, no long caption: <= 4 visible header controls
##  3 each card's picture is its own pose: a fresh render of the pose (a second renderer, no cache) differs from the card's
##    picture by a mean pixel difference <= 0.02 (of 1.0), while pictures of two DIFFERENT poses differ by >= 0.01
##  4 rename / retime / reorder (drag-drop) / delete are each ONE undo step, and the undo restores the scene's JSON exactly
##  5 the selected card has Tok card_sel; the card at the playhead has the Tok card_play frame; they follow the playhead
##  7 each walk-template thumb (8 cards, the body walks forward) frames its own body: inside the thumb with a 2 px margin, centre
##    within 25 % of the width from the thumb centre (measured by scanning the thumb image for pixels off the backdrop colour)
##  6 playing combo3 from 0: after the first frame the card at the playhead is inside the strip's viewport on >= 95 % of the
##    frames, and the strip scrolled when the card was past the edge (with the window narrowed to 700 px so it must)
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func scene_json() -> String:
	return JSON.stringify(m.S.to_dict(m.B), "", true)


func visible_cards() -> int:
	var sc: ScrollContainer = m.ui_card_row
	var n := 0
	var x0 := sc.get_global_rect().position.x
	var x1 := sc.get_global_rect().end.x
	for pc in m.ui_cards.get_children():
		var r: Rect2 = (pc as Control).get_global_rect()
		if r.position.x >= x0 - 1.0 and r.end.x <= x1 + 1.0:
			n += 1
	return n


## [pictures, visible cards with a picture, visible cards, cards] of the strip now
func card_icons() -> Array:
	var sc: ScrollContainer = m.ui_card_row
	var x0 := sc.get_global_rect().position.x
	var x1 := sc.get_global_rect().end.x
	var all := 0
	var vis := 0
	var vtot := 0
	var n := 0
	for pc in m.ui_cards.get_children():
		if not String(pc.name).begins_with("card_"):
			continue
		n += 1
		var nb := (pc as Node).find_child("b_pick", true, false) as Button
		var has := nb != null and nb.icon != null
		if has:
			all += 1
		var r := (pc as Control).get_global_rect()
		if r.position.x >= x0 - 1.0 and r.end.x <= x1 + 1.0:
			vtot += 1
			if has:
				vis += 1
	return [all, vis, vtot, n]


func mean_diff(a: Image, b: Image) -> float:
	var w := mini(a.get_width(), b.get_width())
	var h := mini(a.get_height(), b.get_height())
	var s := 0.0
	for y in h:
		for x in w:
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			s += (absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)) / 3.0
	return s / float(w * h)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(2)
	root.get_window().size = Vector2i(1600, 900)
	await idle(6)
	var src := "res://scenes/combo3.json"
	var file0 := FileAccess.get_file_as_string(src)
	m._load_scene(src)
	m._page_set("ANIMATE", false)
	await idle(3)
	m._rebuild_cards()
	await m.thumbs.settle()
	await idle(3)

	# 1 how many cards, how tall
	var n12 := visible_cards()
	ok(m.S.cards.size() == 12 and n12 == 12, "combo3: all %d of 12 cards are in the strip at 1600 x 900" % n12)
	var cards0: Array = m.S.cards.duplicate(true)
	for k in 8:
		m.S.cards.append(cards0[k].duplicate(true))
	m._rebuild_cards()
	await idle(3)
	var n20 := visible_cards()
	ok(n20 >= 16, "20 cards: %d fully visible (bar >= 16; the old strip showed 8)" % n20)
	print("     card row %.0f px, card %.0f x %.0f, panel %.0f" % [m.ui_card_row.size.y, (m.ui_cards.get_child(0) as Control).size.x, (m.ui_cards.get_child(0) as Control).size.y, m.ui_bp.size.y])
	ok(m.ui_card_row.size.y <= 112.0 and m.bottom_h <= m.BOTTOM_H + int(m.ui_timeline.clip_px() + m._tl_under_ruler() + m.ui_timeline.audio_h()),
		"the strip is not taller than before: card row %.0f px (<= 112), panel %d" % [m.ui_card_row.size.y, m.bottom_h])
	m.S.cards.resize(12)
	m._rebuild_cards()
	await m.thumbs.settle()
	await idle(3)

	# 2 the header
	var hdr := 0
	var words := 0
	for c in m.ui_bh.get_children():
		if c.is_visible_in_tree() and not (c is Control and (c as Control).size_flags_horizontal & Control.SIZE_EXPAND and c.get_class() == "Control"):
			hdr += 1
			if c is Button and (c as Button).text != "" and not (c is MenuButton):
				words += 1
	ok(hdr <= 4 and words == 0 and m.ui_scene_btn.icon != null and m.ui_fold_btn["bottom"].icon != null,
		"header: %d visible controls (heading, name box, Scene menu, Fold), %d text buttons, icons on Scene and Fold" % [hdr, words])
	var sm: PopupMenu = m.ui_scene_btn.get_popup()
	var items := []
	for i in sm.item_count:
		items.append(sm.get_item_text(i))
	ok(items == ["Save scene", "Open scene", "Versions", "New empty scene", "New from template...", "Delete scene"],
		"the Scene menu holds %s" % [items])

	# 3 the pictures
	var pic_ok := true
	var worst := 0.0
	var fresh := SceneThumbs.new()
	fresh.name = "fresh_renderer"
	root.add_child(fresh)
	await idle(2)
	var first_img: Image = null
	var second_img: Image = null
	var checked := 0
	for i in [0, 3, 7, 11]:
		var nb: Button = m.ui_cards.get_node("card_%d" % (i + 1)).find_child("b_pick", true, false)
		if nb.icon == null:
			pic_ok = false
			continue
		var card_img: Image = nb.icon.get_image()
		var own: Image = await fresh.draw_pose(m.S.cards[i]["pose"])
		var d := mean_diff(card_img, own)
		worst = maxf(worst, d)
		checked += 1
		if i == 3:
			first_img = own
		if i == 7:
			second_img = own
	var other := mean_diff(first_img, second_img) if first_img != null and second_img != null else 0.0
	ok(pic_ok and checked == 4 and worst <= 0.02, "each card's picture vs the pose rendered alone: worst mean pixel difference %.4f (bar <= 0.02) over %d cards" % [worst, checked])
	ok(other >= 0.01, "two different poses (cards 4 and 8) differ by %.4f (bar >= 0.01): the pictures are not all the same" % other)
	# placement: the picture is drawn inside its card, above the number and name
	var pc4: Control = m.ui_cards.get_node("card_4")
	var nb4: Button = m.ui_cards.get_node("card_4").find_child("b_pick", true, false)
	ok(nb4.icon != null and nb4.get_global_rect().size.y >= 70.0 and pc4.get_global_rect().encloses(nb4.get_global_rect()) and nb4.text.begins_with("4 "),
		"card 4: picture and '%s' are inside the card (%.0f x %.0f px)" % [nb4.text, pc4.size.x, pc4.size.y])

	# 3b the walk's thumbs frame their own body: the template's 8 cards (the body walks forward, root z from -3.9 to 0), each
	# drawn alone by the same renderer; the body's pixels (any pixel off the stage's backdrop colour, measured on the
	# thumb image itself) lie inside the thumb with a 2 px margin, and their centre is within 25 % of the width from the middle
	var wcards: Array = (Templates.read("walk") as Dictionary).get("cards", [])
	var tw := SceneThumbs.SIZE.x
	var th := SceneThumbs.SIZE.y
	var frame_bad: Array = []
	var frame_worst := 0.0
	for i in wcards.size():
		var wimg: Image = await fresh.draw_pose((wcards[i] as Dictionary)["pose"])
		var lo := Vector2i(tw, th)
		var hi := Vector2i(-1, -1)
		for y in th:
			for x in tw:
				var px := wimg.get_pixel(x, y)
				var bgc := PoseLibrary.BG
				if absf(px.r - bgc.r) + absf(px.g - bgc.g) + absf(px.b - bgc.b) > 0.06:
					lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
					hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
		if hi.x < 0:
			frame_bad.append("%d: no body" % i)
			continue
		var cen := (lo.x + hi.x + 1) / 2.0
		var off := absf(cen - tw / 2.0) / float(tw)
		frame_worst = maxf(frame_worst, off)
		var inside := lo.x >= 2 and lo.y >= 2 and hi.x <= tw - 3 and hi.y <= th - 3
		if not inside or off > 0.25:
			frame_bad.append("%d: x %d..%d y %d..%d centre off %.2f" % [i, lo.x, hi.x, lo.y, hi.y, off])
	ok(wcards.size() == 8 and frame_bad.is_empty(), "walk thumbs: %d cards, each body inside its thumb with a 2 px margin and centred (worst centre offset %.2f of the width, bar <= 0.25) %s" % [wcards.size(), frame_worst, str(frame_bad)])

	# 4 edits: one undo step each, exactly restored
	var before := scene_json()
	var u0: int = m.undo.size()
	m._card_rename(2, "zz new name")
	ok(m.undo.size() == u0 + 1 and m.S.cards[2]["name"] == "zz new name", "rename: one undo step (%d -> %d)" % [u0, m.undo.size()])
	m._undo()
	ok(scene_json() == before, "  undo restores the scene exactly")
	before = scene_json()
	u0 = m.undo.size()
	var hs: SpinBox = m.ui_cards.get_node("card_5").find_child("spin_hold", true, false)
	var h0: float = hs.value
	hs.value = h0 + 0.25
	ok(m.undo.size() == u0 + 1 and absf(float(m.S.cards[4]["hold"]) - (h0 + 0.25)) < 1e-6, "retime (hold on card 5): one undo step")
	var tt: String = m.ui_cards.get_node("card_5").find_child("b_timing", true, false).text
	ok(tt.contains("hold %s" % String.num(h0 + 0.25, 2)), "  the timing text reads '%s'" % tt)
	m._undo()
	ok(scene_json() == before, "  undo restores the scene exactly")
	before = scene_json()
	u0 = m.undo.size()
	var name0: String = m.S.cards[1]["name"]
	var data: Variant = {"kine_card": 1}   # what _card_drag hands over (a real drag needs the mouse)
	ok(m._card_can_drop(Vector2.ZERO, data, 6) and not m._card_can_drop(Vector2.ZERO, data, 1), "reorder: dropping card 2 on card 7 is allowed, on itself is not")
	m._card_drop(Vector2.ZERO, data, 6)
	ok(m.undo.size() == u0 + 1 and m.S.cards[6]["name"] == name0 and m.sel_card == 6, "  card 2 is now place 7, one undo step")
	m._undo()
	ok(scene_json() == before, "  undo restores the scene exactly")
	before = scene_json()
	u0 = m.undo.size()
	m._card_del(3)
	ok(m.undo.size() == u0 + 1 and m.S.cards.size() == 11, "delete: one undo step")
	m._undo()
	ok(scene_json() == before and m.S.cards.size() == 12, "  undo restores the scene exactly")
	# the right-click menu and the hover icons run the same functions
	m._card_menu(2, Vector2(300, 600))
	await idle(2)
	ok(m.ui_card_menu != null and m.ui_card_menu.item_count == 7 and m.ui_card_menu.visible, "right-click menu: %d items, open" % m.ui_card_menu.item_count)
	m.ui_card_menu.hide()
	var bu: Button = m.ui_cards.get_node("card_3").find_child("b_update", true, false)
	var bd: Button = m.ui_cards.get_node("card_3").find_child("b_delete", true, false)
	ok(bu != null and bd != null and bu.icon != null and bd.icon != null, "hover icons Update and Delete have icons")
	await idle(2)

	# 5 selected + playhead marks
	m.playing = false
	m._card_pick(4)
	await idle(2)
	var st_sel := (m.ui_cards.get_node("card_5") as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	var st_pl := (m.ui_cards.get_node("card_5") as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	ok(st_sel.bg_color == Tok.c("card_sel") and st_pl.border_color == Tok.c("card_play"), "picked card 5: card_sel ground, and the playhead frame (it sits at its time)")
	m.playhead = m.S.times()[8][1] + 0.01
	await idle(3)
	var st8 := (m.ui_cards.get_node("card_9") as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	var st5 := (m.ui_cards.get_node("card_5") as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	ok(st8.border_color == Tok.c("card_play") and st5.border_color.a == 0.0 and st5.bg_color == Tok.c("card_sel"), "playhead on card 9: it wears the frame; card 5 is still picked, frame gone")

	await idle(3)
	var shot_dir := "C:/Users/Nick/.claude/jobs/9afc22db/tmp"
	if DirAccess.dir_exists_absolute(shot_dir):
		root.get_texture().get_image().save_png(shot_dir + "/strip.png")

	# 6 playing keeps the playhead card in view (24 cards: they cannot all fit)
	for k in 12:
		m.S.cards.append(m.S.cards[k].duplicate(true))
	m.sel_card = -1
	m.playhead = 0.0
	m._rebuild_cards()
	await idle(3)
	var sc: ScrollContainer = m.ui_card_row
	ok(sc.get_h_scroll_bar().max_value > sc.size.x + 10.0, "24 cards need scrolling (%.0f > %.0f px)" % [sc.get_h_scroll_bar().max_value, sc.size.x])
	m.playing = true
	var frames := 0
	var seen := 0
	var max_scroll := 0
	var t_end: float = m._ps().length()
	while m.playing and m.playhead < t_end - 0.05 and frames < 4000:
		await process_frame
		frames += 1
		if frames < 3:
			continue
		var idx: int = m._play_card_idx()
		if idx < 0:
			continue
		var pc := m.ui_cards.get_child(idx) as Control
		var x0 := pc.get_global_rect().position.x
		var x1 := pc.get_global_rect().end.x
		var r := sc.get_global_rect()
		if x0 >= r.position.x - 1.0 and x1 <= r.end.x + 1.0:
			seen += 1
		max_scroll = maxi(max_scroll, sc.scroll_horizontal)
	var frac := float(seen) / float(maxi(1, frames - 2))
	ok(frames > 60 and frac >= 0.95 and max_scroll > 100, "playing combo3 (%d frames, playhead %.2f of %.2f s): the playhead card was in view on %.1f %% of the frames, the strip scrolled to %d px" % [frames, m.playhead, t_end, frac * 100.0, max_scroll])
	m.playing = false
	sc.scroll_horizontal = 0
	m._timeline_pick(22)   # a click on the timeline's block 23: the strip scrolls to the card
	await idle(4)
	var pc23 := m.ui_cards.get_child(22) as Control
	ok(sc.scroll_horizontal > 0 and pc23.get_global_rect().position.x >= sc.get_global_rect().position.x - 1.0 and pc23.get_global_rect().end.x <= sc.get_global_rect().end.x + 1.0,
		"a click on the timeline's block 23: the strip scrolled to %d px and card 23 is whole in view" % sc.scroll_horizontal)
	ok(FileAccess.get_file_as_string(src) == file0, "combo3.json byte-identical (nothing was saved)")

	# 8 EASY'S RUN: a beginner clicks Run (37 cards): the strip's pictures come fast. The pose pictures on disk are removed first
	# (a cold start: the draws are measured, not the cache). Frames are counted from the click; the frame gap is the time
	# between two process frames. Every frame that renders a picture costs ~2 display refreshes here (the old one-per-frame code: 49.7 ms), so the bar is "no visible stall": no frame over 100 ms while the pictures are drawn
	var da := DirAccess.open("user://thumbs")
	if da != null:
		for f in da.get_files():
			if f.begins_with("p_"):
				da.remove(f)
	m._new_scene()
	await idle(3)
	m.easy.set_on(true, false)
	await idle(6)
	var t_click := Time.get_ticks_usec()
	m.easy.home.card(1)   # Run
	var n_run: int = m.S.cards.size()
	var vis_ok_at := -1
	var all_at := -1
	var worst_gap := 0.0
	var last := Time.get_ticks_usec()
	for f in range(1, 41):
		await process_frame
		var now := Time.get_ticks_usec()
		if f > 1:
			worst_gap = maxf(worst_gap, (now - last) / 1000.0)
		last = now
		var st := card_icons()
		if vis_ok_at < 0 and st[1] == st[2]:
			vis_ok_at = f
		if all_at < 0 and st[0] == st[3]:
			all_at = f
			break
	print("     Run: %d cards; visible cards all have icons at frame %d, all cards at frame %d (%.0f ms from the click); worst frame gap %.1f ms" % [n_run, vis_ok_at, all_at, (Time.get_ticks_usec() - t_click) / 1000.0, worst_gap])
	ok(n_run == 37 and vis_ok_at > 0 and vis_ok_at <= 10, "Run: every visible strip card has its picture within 10 frames (frame %d; bar <= 10)" % vis_ok_at)
	ok(all_at > 0 and all_at <= 40, "Run: all %d cards have their picture within 40 frames (frame %d; bar <= 40)" % [n_run, all_at])
	ok(worst_gap <= 100.0, "Run: no frame over 100 ms while the pictures are drawn (worst %.1f ms; bar <= 100, the old code 49.7 but 2 s of blank cards)" % worst_gap)
	m.easy.set_on(false, false)
	print("CARDSTRIP %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
