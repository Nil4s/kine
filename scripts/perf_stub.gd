class_name PerfStub
extends RefCounted
## ROADMAP 99 (tests/perf4_test.gd): the per-subsystem breakdown. A test sets PerfStub.off = {"<name>": true} and the named
## subsystem is skipped for that run only; the default (empty) runs everything. Nothing in the app sets it.
## The names: body (the pose evaluation of every fighter), skinning (the mannequins drawn from their bodies), ik_plants (the IK
## and foot-plant passes inside a pose), hits (the fighters' contact tests and tags), timeline (the timeline's redraw), ui (the
## panels and the bar).

static var off := {}


static func skip(k: String) -> bool:
	return off.has(k)
