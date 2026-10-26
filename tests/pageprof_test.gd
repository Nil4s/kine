## godot --path . -s tests/pageprof_test.gd     (needs a window; a PROFILER, prints the page-switch cost per page pair and its top parts)
extends SceneTree

var m: Node


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	var pages: Array = m.PAGES
	var rows := []
	m.page_prof_on = true
	for rep in 2:
		for a in pages:
			for b in pages:
				if a == b:
					continue
				m._page_set(a)
				await idle(8)
				m.page_prof = {}
				var t0 := Time.get_ticks_usec()
				m._page_set(b)
				var ms := (Time.get_ticks_usec() - t0) / 1000.0
				if rep == 0:
					continue   # the first lap warms the caches (first-use builds); the second is the steady switch
				var top: Array = m.page_prof.keys()
				top.sort_custom(func(x, y): return m.page_prof[x] > m.page_prof[y])
				var s: String = ""
				for i in mini(3, top.size()):
					s += " %s=%.1f" % [top[i], m.page_prof[top[i]] / 1000.0]
				rows.append([ms, "%s->%s" % [a, b], s])
	var worst := 0.0
	for r in rows:
		worst = maxf(worst, r[0])
		print("PP %-18s %7.1f ms |%s" % [r[1], r[0], s_of(r)])
	print("PP worst %.1f ms of %d pairs" % [worst, rows.size()])
	quit(0)


func s_of(r) -> String:
	return r[2]
