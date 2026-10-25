class_name BootProfile
extends RefCounted
## BOOT PROFILE: the time from the engine's start to the first usable frame, block by block (main.gd _ready marks each
## block). Off unless env KINE_BOOT_PROFILE=1 or the user arg --boot-profile is given; when off, every call is a no-op.
## The table prints once, at the first usable frame: "BOOT <name> <ms>" rows, then "BOOT total <ms>".

static var on := false
static var _last_us := 0
static var rows: Array = []   # [name, ms this block took]
static var _t_engine_ms := 0  # Time.get_ticks_msec() when the first block started (the engine's own startup)


static func start() -> void:
	on = OS.get_environment("KINE_BOOT_PROFILE") == "1" or OS.get_cmdline_user_args().has("--boot-profile")
	if not on:
		return
	_t_engine_ms = Time.get_ticks_msec()
	rows.append(["engine start -> _ready", _t_engine_ms])
	_last_us = Time.get_ticks_usec()


## one block finished: its time since the last mark
static func mark(name: String) -> void:
	if not on:
		return
	var now := Time.get_ticks_usec()
	rows.append([name, (now - _last_us) / 1000.0])
	_last_us = now


## the first usable frame: the table and the total (engine start -> now)
static func usable(name: String) -> void:
	if not on:
		return
	mark(name)
	var total := Time.get_ticks_msec()
	print("BOOT usable_at_ms %d" % total)
	for r in rows:
		print("BOOT %-34s %8.1f" % [r[0], r[1]])
	print("BOOT total_ms %d" % total)
	on = false
