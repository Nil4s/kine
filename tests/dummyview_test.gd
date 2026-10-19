## godot --path . -s tests/dummyview_test.gd     (needs a window; saves tmp/dummyview.png)
## (1) THE DUMMY NEVER HIDES THE HERO. The dummy stands out front (the weapon swings at it), so in the default front view
## it is between the camera and the hero. BAR (stated before measuring): in the default view and in each preset view
## (front 1, his right 2, top 3, back 4, his left 5, bottom 6) with the dummy on, >= 95 % of the hero's pixels are visible.
## Pixels: HERO MASK = pixels that change when the hero is hidden (dummy off); a mask pixel is VISIBLE when the dummy
## has pulled it less than half way to its own colour (count_visible). PLACEMENT: the dummy is still drawn where it
## stands (the front view's ghost is translucent, not gone: the test reads the dummy's pixels there; the far views solid). Control: with the ghost forced off the front view must FAIL the bar (the test can fail).
## (2) HEADER = PANEL. The strip's clip count and the panel's "No clips yet" agree for an empty scene, combo3 and a scene
## with 1 card, also when the cards change without a rebuild (the stale-panel bug seen with the 12-clip header).
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


func shot() -> Image:
	await idle(3)
	await RenderingServer.frame_post_draw
	return m.get_viewport().get_texture().get_image()


func hero_show(v: bool) -> void:
	for p in m.pieces.values():
		(p as Node3D).visible = v


func dsum(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


## a = dummy off; e = dummy off, hero hidden; f = dummy on, hero hidden; d = dummy on. A hero pixel (a != e) is VISIBLE
## when d is within half of the dummy's own pull on it (|d-a| <= 0.5 |f-a|, floor 0.04; f = the dummy forced OPAQUE): under an opaque dummy d == f so
## the pull is whole (hidden); through the 22 % ghost d is 22 % of the way (visible); hero in front of the dummy: d == a.
func count_visible(a: Image, e: Image, f: Image, d: Image) -> Array:
	var n := 0
	var vis := 0
	var dpx := 0
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	for y in range(int(m.TOP_H), int(vs.y - m.bottom_h - m.LINE_H), 2):
		for x in range(int(m.lw()), int(vs.x - m.rw()), 2):
			if dsum(f.get_pixel(x, y), e.get_pixel(x, y)) > 0.02:
				dpx += 1   # the dummy's own pixels (dummy on vs off, hero hidden)
			if dsum(a.get_pixel(x, y), e.get_pixel(x, y)) < 0.08:
				continue
			n += 1
			if dsum(d.get_pixel(x, y), a.get_pixel(x, y)) <= maxf(0.04, 0.5 * dsum(f.get_pixel(x, y), a.get_pixel(x, y))):
				vis += 1
	return [n, vis, dpx]


## {"mask": n hero pixels, "vis": n of them visible, "on": the dummy-on image}
func measure(view: int) -> Dictionary:
	m._view(view)
	m.dummy_on = false
	m.clean = true
	m._refresh()
	hero_show(true)
	var a := await shot()
	hero_show(false)
	var e := await shot()
	m.dummy_on = true
	m._refresh()
	hero_show(false)   # (after the refresh: it puts the pieces back)
	var ghost_a: float = m.dummy_mat.albedo_color.a
	m.dummy_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED   # f: the dummy OPAQUE: the reference for "how far it pulls"
	m.dummy_mat.albedo_color.a = 1.0
	var f := await shot()
	m.dummy_mat.albedo_color.a = ghost_a
	m._refresh()   # the app's own choice again (ghost or solid)
	hero_show(true)
	var d := await shot()
	var cnt := count_visible(a, e, f, d)
	var n: int = cnt[0]
	var vis: int = cnt[1]
	return {"mask": n, "vis": vis, "dpx": cnt[2], "img": d}


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m.B.wep_on = false
	var names := {1: "front (default)", 2: "his right", 3: "top", 4: "back", 5: "his left", 6: "bottom"}
	var front_img: Image = null
	for v in [1, 2, 3, 4, 5, 6]:
		var r := await measure(v)
		var frac: float = float(r["vis"]) / maxf(1.0, float(r["mask"]))
		print("     view %s: hero pixels %d, visible with the dummy on %d = %.1f %%, ghost %s" % [names[v], r["mask"], r["vis"], frac * 100.0, m.dummy_ghost])
		ok(r["mask"] > 200 and frac >= 0.95, "%s: >= 95 %% of the hero's pixels visible (%.1f %%)" % [names[v], frac * 100.0])
		if v == 1:
			front_img = r["img"]
			ok(r["dpx"] > 3000, "  PLACEMENT front: the dummy is still drawn where it stands (%d of its pixels differ from the empty floor)" % r["dpx"])
			ok(m.dummy_ghost, "  front: the dummy is in the way, so it is the ghost (alpha %.2f)" % m.dummy_mat.albedo_color.a)
		if v == 4:
			ok(not m.dummy_ghost and m.dummy_mat.albedo_color.a == 1.0, "  back: nothing is behind the dummy, it stays solid")
	# control: forced solid in the front view must fail the bar
	m._view(1)
	m.clean = true
	hero_show(true)
	m.dummy_on = false
	m._refresh()
	var a := await shot()
	hero_show(false)
	var e := await shot()
	m.dummy_on = true
	m._refresh()
	m.dummy_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	m.dummy_mat.albedo_color.a = 1.0
	hero_show(false)
	var f := await shot()
	hero_show(true)
	m.dummy_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	m.dummy_mat.albedo_color.a = 1.0
	var d := await shot()
	var cnt := count_visible(a, e, f, d)
	var n: int = cnt[0]
	var vis: int = cnt[1]
	print("     CONTROL front, dummy forced opaque: %d / %d = %.1f %%" % [vis, n, 100.0 * vis / maxf(1.0, n)])
	ok(float(vis) / maxf(1.0, n) < 0.5, "control: an opaque dummy in the front view hides most of the hero (the measure can fail)")

	# the screenshot: default view, dummy on, as the user sees it (chrome back on)
	m.clean = false
	m._view(1)
	m._refresh()
	await idle(4)
	var img := await shot()
	img.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/dummyview.png")

	# (2) header = panel
	m.dummy_on = false
	var cases := []
	m._load_scene("res://scenes/combo3.json")
	await idle(2)
	cases.append(["combo3", m.S.cards.size()])
	var empty_ok := true
	for tag in ["combo3", "1 card", "empty", "stale: cards set without a rebuild", "stale: emptied without a rebuild"]:
		match tag:
			"1 card":
				m.S.cards = [m.S.cards[0]]
				m._rebuild_cards()
			"empty":
				m.S.cards = []
				m._rebuild_cards()
			"stale: cards set without a rebuild":
				m._load_scene("res://scenes/combo3.json")
				m.S.cards = m.S.cards.slice(0, 12)
				m._card_add()
				m.S.cards = m.S.cards.slice(0, 3)   # no rebuild
			"stale: emptied without a rebuild":
				m.S.cards = []
		await create_timer(0.6).timeout
		await idle(3)
		var hdr: String = m.ui_doc.text
		var n_cards: int = m.S.cards.size()
		var panel_empty: bool = (m.ui_cards.get_child(0) is Label and String(m.ui_cards.get_child(0).text).begins_with("No clips yet"))
		var hdr_empty := hdr.contains("no clips yet")
		var hdr_n := -1
		if not hdr_empty:
			hdr_n = int(hdr.split("·")[1].strip_edges().split(" ")[0])
		print("     %s: header \"%s\", panel %s, scene has %d" % [tag, hdr, "EMPTY STATE" if panel_empty else "cards", n_cards])
		ok(panel_empty == (n_cards == 0) and hdr_empty == (n_cards == 0) and (hdr_empty or hdr_n == n_cards) and m.ui_cards.get_child_count() >= (7 if n_cards == 0 else 1),
			"%s: header count and panel agree (%d)" % [tag, n_cards])
	print("RESULT dummyview: %d failed" % fails)
	quit(1 if fails > 0 else 0)
