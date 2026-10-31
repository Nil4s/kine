class_name PartTemplates
extends RefCounted
## EASY PART: templates = parametric feature lists in scripts/build/part.gd's terms (sword, axe, shield, chair, crate).
## A template makes the SAME record Expert edits, from a few named numbers (mm): rec["easy"] = {"t": "sword", "p": {"blade_length": 760, ...}, "n": features it owns}.
## The template owns the first n features (ids f1..fn, always the same ids); retemplate() rewrites exactly those when a number changes, and
## whatever the user added after them (Draw shape, Pull it up ...) stays. Expert sees plain features: "Exact sizes? Use Expert" needs no conversion.
## params: k (the name), label, lo / hi / def / step (mm), words (the two ends of its slider). dot_of() says which number an amber dot drags.

const MM := 0.001
const ARCH_GAP := 40.0   # mm: a car's wheel arch top sits this far above the tyre's top (the arch is the wheel radius + 40 mm)
const CAB_W := 0.88     # the glasshouse is this share of the body's width (narrower than the lower body, so the cabin reads as a cabin)
const ORDER :=["sword", "axe", "shield", "chair", "gear", "rack", "slothole", "phone", "shelf", "lidbox", "crate"]   # NGEAR: Gear sits before Crate (Crate stays the last chip). P066: Rack after Gear (its pinion); its numbers are not cm: "raw". P096: the three recipes before Crate
const START := ["box", "cylinder", "sphere", "tube", "plate"]   # FREESTART: the neutral "Start from" row on Easy Part's panel (simple shapes, no weapon)
const T := {
	"box": {"title": "Box", "params": [
		{"k": "width", "label": "Width", "lo": 50.0, "hi": 1000.0, "def": 300.0, "step": 10.0, "words": ["Narrower", "Wider"]},
		{"k": "height", "label": "Height", "lo": 50.0, "hi": 1000.0, "def": 300.0, "step": 10.0, "words": ["Lower", "Taller"]},
		{"k": "depth", "label": "Depth", "lo": 50.0, "hi": 1000.0, "def": 300.0, "step": 10.0, "words": ["Shallower", "Deeper"]}]},
	"cylinder": {"title": "Cylinder", "params": [
		{"k": "diameter", "label": "Width across", "lo": 50.0, "hi": 800.0, "def": 300.0, "step": 10.0, "words": ["Narrower", "Wider"]},
		{"k": "height", "label": "Height", "lo": 50.0, "hi": 1000.0, "def": 400.0, "step": 10.0, "words": ["Shorter", "Taller"]}]},
	"sphere": {"title": "Sphere", "params": [
		{"k": "diameter", "label": "Width across", "lo": 50.0, "hi": 800.0, "def": 300.0, "step": 10.0, "words": ["Smaller", "Bigger"]}]},
	"tube": {"title": "Tube", "params": [
		{"k": "diameter", "label": "Width across", "lo": 50.0, "hi": 800.0, "def": 300.0, "step": 10.0, "words": ["Narrower", "Wider"]},
		{"k": "wall", "label": "Wall", "lo": 5.0, "hi": 100.0, "def": 30.0, "step": 5.0, "words": ["Thinner", "Thicker"]},
		{"k": "height", "label": "Length", "lo": 50.0, "hi": 1000.0, "def": 400.0, "step": 10.0, "words": ["Shorter", "Longer"]}]},
	"plate": {"title": "Plate", "params": [
		{"k": "width", "label": "Width", "lo": 50.0, "hi": 1000.0, "def": 400.0, "step": 10.0, "words": ["Narrower", "Wider"]},
		{"k": "length", "label": "Length", "lo": 50.0, "hi": 1000.0, "def": 300.0, "step": 10.0, "words": ["Shorter", "Longer"]},
		{"k": "thickness", "label": "Thickness", "lo": 2.0, "hi": 50.0, "def": 10.0, "step": 1.0, "words": ["Thinner", "Thicker"]}]},
	"sword": {"title": "Sword", "params": [
		{"k": "blade_length", "label": "Blade length", "lo": 300.0, "hi": 1200.0, "def": 760.0, "step": 10.0, "words": ["Shorter", "Longer"]},
		{"k": "width", "label": "Width", "lo": 30.0, "hi": 120.0, "def": 68.0, "step": 2.0, "words": ["Thinner", "Wider"]},
		{"k": "guard_size", "label": "Guard size", "lo": 80.0, "hi": 240.0, "def": 130.0, "step": 10.0, "words": ["Smaller", "Bigger"]},
		{"k": "thickness", "label": "Thickness", "lo": 4.0, "hi": 16.0, "def": 7.0, "step": 1.0, "words": ["Thinner", "Thicker"]}]},
	"axe": {"title": "Axe", "params": [
		{"k": "handle_length", "label": "Handle length", "lo": 300.0, "hi": 1000.0, "def": 700.0, "step": 10.0, "words": ["Shorter", "Longer"]},
		{"k": "head_width", "label": "Blade width", "lo": 80.0, "hi": 300.0, "def": 160.0, "step": 10.0, "words": ["Narrower", "Wider"]},
		{"k": "head_thickness", "label": "Head thickness", "lo": 10.0, "hi": 50.0, "def": 24.0, "step": 2.0, "words": ["Thinner", "Thicker"]},
		{"k": "handle_thickness", "label": "Handle thickness", "lo": 20.0, "hi": 50.0, "def": 30.0, "step": 2.0, "words": ["Thinner", "Thicker"]}]},
	"shield": {"title": "Shield", "params": [
		{"k": "radius", "label": "Size", "lo": 150.0, "hi": 450.0, "def": 300.0, "step": 10.0, "words": ["Smaller", "Bigger"]},
		{"k": "thickness", "label": "Thickness", "lo": 6.0, "hi": 30.0, "def": 14.0, "step": 1.0, "words": ["Thinner", "Thicker"]},
		{"k": "boss", "label": "Middle bump", "lo": 20.0, "hi": 120.0, "def": 60.0, "step": 5.0, "words": ["Smaller", "Bigger"]}]},
	"chair": {"title": "Chair", "params": [
		{"k": "seat_height", "label": "Seat height", "lo": 300.0, "hi": 700.0, "def": 450.0, "step": 10.0, "words": ["Lower", "Higher"]},
		{"k": "seat_width", "label": "Seat width", "lo": 300.0, "hi": 600.0, "def": 420.0, "step": 10.0, "words": ["Narrower", "Wider"]},
		{"k": "seat_depth", "label": "Seat depth", "lo": 300.0, "hi": 600.0, "def": 420.0, "step": 10.0, "words": ["Shallower", "Deeper"]},
		{"k": "back_height", "label": "Back height", "lo": 200.0, "hi": 800.0, "def": 450.0, "step": 10.0, "words": ["Lower", "Taller"]}]},
	"crate": {"title": "Crate", "params": [
		{"k": "width", "label": "Width", "lo": 200.0, "hi": 900.0, "def": 500.0, "step": 10.0, "words": ["Narrower", "Wider"]},
		{"k": "height", "label": "Height", "lo": 200.0, "hi": 800.0, "def": 400.0, "step": 10.0, "words": ["Lower", "Taller"]},
		{"k": "depth", "label": "Depth", "lo": 200.0, "hi": 800.0, "def": 400.0, "step": 10.0, "words": ["Shallower", "Deeper"]},
		{"k": "lid", "label": "Lid overhang", "lo": 0.0, "hi": 60.0, "def": 20.0, "step": 5.0, "words": ["None", "More"]}]},
	# P096 RECIPES (Friday 96): three starters in What to build > Template. Raw mm sliders; each is the same record Expert edits, and its sliders rewrite only its own steps.
	# phone = a wedge (the phone leans on its slope): width across, depth = the base, height = the back. shelf = an L (a shelf leg, an upright). lidbox = a box with its lid lying beside it, 10 mm apart.
	"phone": {"title": "Phone stand", "params": [
		{"k": "width", "label": "Width", "lo": 40.0, "hi": 200.0, "def": 90.0, "step": 10.0, "words": ["Narrower", "Wider"], "raw": true, "unit": "mm"},
		{"k": "depth", "label": "Depth", "lo": 60.0, "hi": 200.0, "def": 100.0, "step": 10.0, "words": ["Shallower", "Deeper"], "raw": true, "unit": "mm"},
		{"k": "height", "label": "Height", "lo": 60.0, "hi": 200.0, "def": 100.0, "step": 10.0, "words": ["Lower", "Taller"], "raw": true, "unit": "mm"}]},
	"shelf": {"title": "Shelf bracket", "params": [
		{"k": "leg", "label": "Shelf leg", "lo": 100.0, "hi": 400.0, "def": 200.0, "step": 10.0, "words": ["Shorter", "Longer"], "raw": true, "unit": "mm"},
		{"k": "upright", "label": "Upright", "lo": 80.0, "hi": 300.0, "def": 150.0, "step": 10.0, "words": ["Lower", "Taller"], "raw": true, "unit": "mm"},
		{"k": "thickness", "label": "Thickness", "lo": 4.0, "hi": 20.0, "def": 8.0, "step": 1.0, "words": ["Thinner", "Thicker"], "raw": true, "unit": "mm"},
		{"k": "width", "label": "Width", "lo": 20.0, "hi": 80.0, "def": 40.0, "step": 5.0, "words": ["Narrower", "Wider"], "raw": true, "unit": "mm"}]},
	"lidbox": {"title": "Box with lid", "params": [
		{"k": "width", "label": "Width", "lo": 100.0, "hi": 600.0, "def": 300.0, "step": 10.0, "words": ["Narrower", "Wider"], "raw": true, "unit": "mm"},
		{"k": "height", "label": "Height", "lo": 50.0, "hi": 400.0, "def": 150.0, "step": 10.0, "words": ["Lower", "Taller"], "raw": true, "unit": "mm"},
		{"k": "depth", "label": "Depth", "lo": 100.0, "hi": 600.0, "def": 200.0, "step": 10.0, "words": ["Shallower", "Deeper"], "raw": true, "unit": "mm"},
		{"k": "lid", "label": "Lid thickness", "lo": 5.0, "hi": 30.0, "def": 10.0, "step": 1.0, "words": ["Thinner", "Thicker"], "raw": true, "unit": "mm"}]},
	# NGEAR: a spur gear with a centre hole. Real pitch diameter = teeth x module: tip = module x (teeth + 2), root = module x (teeth - 2.5). Default 30 teeth: a 64 mm gear reads in the 3/4 view.
	# raw: the slider's own numbers (a tooth count, a size step 1 = Small / Medium / Big teeth = module 1 / 2 / 3, a thickness in mm), not cm
	"gear": {"title": "Gear", "params": [
		{"k": "teeth", "label": "Teeth", "lo": 8.0, "hi": 60.0, "def": 30.0, "step": 1.0, "words": ["Fewer", "More"], "raw": true, "unit": "teeth"},
		{"k": "module", "label": "Teeth size", "lo": 1.0, "hi": 3.0, "def": 2.0, "step": 1.0, "words": ["Small teeth", "Big teeth"], "raw": true, "unit": "size"},
		{"k": "thickness", "label": "Thickness", "lo": 3.0, "hi": 30.0, "def": 10.0, "step": 1.0, "words": ["Thinner", "Thicker"], "raw": true, "unit": "mm"}]},
	# P066: a straight rack, the Gear's partner: a bar of teeth. Length = teeth x pitch, pitch = pi x module (the Gear's pitch, so they mesh). Its numbers are raw too.
	"rack": {"title": "Rack", "params": [
		{"k": "teeth", "label": "Length", "lo": 4.0, "hi": 40.0, "def": 12.0, "step": 1.0, "words": ["Shorter", "Longer"], "raw": true, "unit": "teeth"},
		{"k": "module", "label": "Teeth size", "lo": 1.0, "hi": 3.0, "def": 2.0, "step": 1.0, "words": ["Small teeth", "Big teeth"], "raw": true, "unit": "size"},
		{"k": "thickness", "label": "Thickness", "lo": 3.0, "hi": 30.0, "def": 10.0, "step": 1.0, "words": ["Thinner", "Thicker"], "raw": true, "unit": "mm"}]},
	# p067hinges: a hinge from the Hinge chip (not in ORDER: its own button beside Parts). Sized to the door: the door's height (mm) sets the
	# leaves (butt and living: door / 21 rounded to 5 mm, so 100 mm at 2100) or the strip (piano: the full door height). kind: 1 Butt, 2 Piano, 3 Living.
	"hinge": {"title": "Hinge", "params": [
		{"k": "door", "label": "Door height", "lo": 1800.0, "hi": 2400.0, "def": 2100.0, "step": 100.0, "words": ["Shorter door", "Taller door"], "raw": true, "unit": "mm"},
		{"k": "kind", "label": "Kind", "lo": 1.0, "hi": 3.0, "def": 1.0, "step": 1.0, "words": ["Butt", "Living"], "raw": true, "unit": "kind"}]},
	# p070: a compression spring: turns (coils, 3..12), wire (mm, 1..4) and coil size (the mean coil width, mm, 20..60) on raw sliders. Coils 0.8 x wire apart.
	"spring": {"title": "Spring", "params": [
		{"k": "turns", "label": "Turns", "lo": 3.0, "hi": 12.0, "def": 6.0, "step": 1.0, "words": ["Fewer", "More"], "raw": true, "unit": "turns"},
		{"k": "wire", "label": "Wire", "lo": 1.0, "hi": 4.0, "def": 2.0, "step": 1.0, "words": ["Thinner", "Thicker"], "raw": true, "unit": "mm"},
		{"k": "size", "label": "Coil size", "lo": 20.0, "hi": 60.0, "def": 40.0, "step": 5.0, "words": ["Smaller", "Bigger"], "raw": true, "unit": "mm"}]},
	# P032: a plate with a long rounded hole (a slot) cut right through it. Length and Width are the hole's own size (the round ends
	# are Width / 2 across); the plate is 20 mm wider than the hole on each side. Width is at most 40, so Length (at least 60) stays longer.
	"slothole": {"title": "Slot", "params": [
		{"k": "length", "label": "Length", "lo": 60.0, "hi": 300.0, "def": 120.0, "step": 10.0, "words": ["Shorter", "Longer"]},
		{"k": "width", "label": "Width", "lo": 10.0, "hi": 40.0, "def": 20.0, "step": 2.0, "words": ["Narrower", "Wider"]},
		{"k": "thickness", "label": "Thickness", "lo": 3.0, "hi": 30.0, "def": 8.0, "step": 1.0, "words": ["Thinner", "Thicker"]}]},
	# VEHICLE PARTS (B3, scripts/vehicle.gd): not in ORDER, so no Easy chip: a car body and one wheel
	"car": {"title": "Car body", "params": [
		{"k": "body_length", "label": "Length", "lo": 1500.0, "hi": 5000.0, "def": 4000.0, "step": 50.0, "words": ["Shorter", "Longer"]},
		{"k": "body_width", "label": "Width", "lo": 1000.0, "hi": 2200.0, "def": 1750.0, "step": 20.0, "words": ["Narrower", "Wider"]},
		{"k": "body_height", "label": "Height", "lo": 900.0, "hi": 1800.0, "def": 1450.0, "step": 10.0, "words": ["Lower", "Taller"]},
		{"k": "wheelbase", "label": "Wheelbase", "lo": 1000.0, "hi": 3000.0, "def": 2500.0, "step": 20.0, "words": ["Shorter", "Longer"]},
		# the wheel's radius, copied in by Vehicle.make_set and the Easy screen (the arches follow it); no slider of its own on the car
		{"k": "wheel_r", "label": "Wheel size", "lo": 100.0, "hi": 600.0, "def": 320.0, "step": 10.0, "words": ["Smaller", "Bigger"]}]},
	# P072 (Parts > Wheels): a wheel with an axle hole, not in ORDER (no template chip): the Wheel and Castor chips (easy_part.gd) make it.
	# radius / width / hole in mm; the hole runs along the axle (world X) through the middle. Its sliders are hidden there ("parts": true).
	"axwheel": {"title": "Wheel", "parts": true, "params": [
		{"k": "radius", "label": "Size", "lo": 20.0, "hi": 150.0, "def": 40.0, "step": 5.0, "words": ["Smaller", "Bigger"]},
		{"k": "width", "label": "Width", "lo": 6.0, "hi": 60.0, "def": 20.0, "step": 2.0, "words": ["Thinner", "Wider"]},
		{"k": "hole", "label": "Axle hole", "lo": 4.0, "hi": 16.0, "def": 8.0, "step": 1.0, "words": ["Smaller", "Bigger"]}]},
	"castor": {"title": "Castor", "parts": true, "params": [
		{"k": "radius", "label": "Size", "lo": 20.0, "hi": 150.0, "def": 25.0, "step": 5.0, "words": ["Smaller", "Bigger"]},
		{"k": "width", "label": "Width", "lo": 6.0, "hi": 60.0, "def": 16.0, "step": 2.0, "words": ["Thinner", "Wider"]},
		{"k": "hole", "label": "Axle hole", "lo": 4.0, "hi": 16.0, "def": 6.0, "step": 1.0, "words": ["Smaller", "Bigger"]}]},
	"wheel": {"title": "Wheel", "params": [
		{"k": "radius", "label": "Radius", "lo": 100.0, "hi": 600.0, "def": 320.0, "step": 10.0, "words": ["Smaller", "Bigger"]},
		{"k": "width", "label": "Width", "lo": 50.0, "hi": 400.0, "def": 200.0, "step": 10.0, "words": ["Thinner", "Wider"]}]},
	# P075: Clips and feet (Parts library, not in ORDER: no template chip). Sizes in mm (raw sliders). Each is one solid on the floor.
	# foot = a disc, d across, h tall. clip = a ring (d across, w tall, 2.5 mm wall) with a 3 mm opening cut through its wall.
	# slot = a plate (slot length + 12 mm, 10 mm wide, t thick) with a 2.5 mm wide slot of length L cut through it (a zip tie's strap).
	"foot": {"title": "Rubber foot", "params": [
		{"k": "d", "label": "Width", "lo": 8.0, "hi": 30.0, "def": 16.0, "step": 2.0, "words": ["Smaller", "Bigger"], "raw": true, "unit": "mm"},
		{"k": "h", "label": "Height", "lo": 2.0, "hi": 10.0, "def": 4.0, "step": 1.0, "words": ["Thinner", "Thicker"], "raw": true, "unit": "mm"}]},
	"clip": {"title": "Cable clip", "params": [
		{"k": "d", "label": "Width", "lo": 8.0, "hi": 30.0, "def": 14.0, "step": 2.0, "words": ["Smaller", "Bigger"], "raw": true, "unit": "mm"},
		{"k": "w", "label": "Height", "lo": 4.0, "hi": 15.0, "def": 8.0, "step": 1.0, "words": ["Lower", "Taller"], "raw": true, "unit": "mm"}]},
	"slot": {"title": "Zip-tie slot", "params": [
		{"k": "L", "label": "Slot length", "lo": 6.0, "hi": 30.0, "def": 14.0, "step": 2.0, "words": ["Shorter", "Longer"], "raw": true, "unit": "mm"},
		{"k": "t", "label": "Thickness", "lo": 2.0, "hi": 6.0, "def": 3.0, "step": 1.0, "words": ["Thinner", "Thicker"], "raw": true, "unit": "mm"}]},
	# NSCREW2: a screw from the Parts category (not in ORDER: no template chip). d = the nominal size (M3..M6, mm), L = the length under the head (mm).
	# Its numbers are picked by the Parts chips (easy_part.gd), so its sliders are hidden there ("parts": true).
	# FRIDAY 73: a bracket from the Parts page's Brackets: kind 1 = L, 2 = T, 3 = corner brace (raw: the chip's own number). Its numbers are not sliders (parts: true)
	"bracket": {"title": "Bracket", "parts": true, "params": [
		{"k": "kind", "label": "Shape", "lo": 1.0, "hi": 3.0, "def": 1.0, "step": 1.0, "words": ["L", "Corner brace"], "raw": true, "unit": "kind"},
		{"k": "leg", "label": "Leg", "lo": 40.0, "hi": 200.0, "def": 80.0, "step": 10.0, "words": ["Shorter", "Longer"], "raw": true, "unit": "mm"},
		{"k": "width", "label": "Width", "lo": 10.0, "hi": 80.0, "def": 30.0, "step": 5.0, "words": ["Narrower", "Wider"], "raw": true, "unit": "mm"},
		{"k": "thickness", "label": "Thickness", "lo": 3.0, "hi": 10.0, "def": 5.0, "step": 1.0, "words": ["Thinner", "Thicker"], "raw": true, "unit": "mm"}]},
	"screw": {"title": "Screw", "parts": true, "params": [
		{"k": "d", "label": "Size", "lo": 3.0, "hi": 6.0, "def": 4.0, "step": 1.0, "words": ["Smaller", "Bigger"]},
		{"k": "L", "label": "Length", "lo": 10.0, "hi": 30.0, "def": 16.0, "step": 1.0, "words": ["Shorter", "Longer"]}]},
	# P069 BEARINGS: a deep groove ball bearing from the Parts chips (608, 625, 688). kind = 0 / 1 / 2 (BEARING_SIZE). Its numbers are the chips, so no sliders.
	"bearing": {"title": "Bearing", "parts": true, "params": [
		{"k": "kind", "label": "Bearing", "lo": 0.0, "hi": 2.0, "def": 0.0, "step": 1.0, "words": ["Smaller", "Bigger"], "raw": true, "unit": "size"}]},
	# P069 BEARINGS: the seat for the bearing on the floor: a holder block with a pocket for it, and the bearing beside it (same kind)
	"seat": {"title": "Seat", "parts": true, "params": [
		{"k": "kind", "label": "Bearing", "lo": 0.0, "hi": 2.0, "def": 0.0, "step": 1.0, "words": ["Smaller", "Bigger"], "raw": true, "unit": "size"}]},
	# P071 HANDLES: from the Parts library's Handles page (easy_part.gd), not in ORDER (no template chip). Sized by the chips (96 / 128 / 160 mm,
	# 24 / 32 / 40 mm); the sliders then move the same handle. Holes: a drawer pull has two 4.5 mm holes (an M4 screw of the Parts page goes through).
	"drawer_pull": {"title": "Drawer pull", "params": [
		{"k": "spacing", "label": "Hole spacing", "lo": 64.0, "hi": 192.0, "def": 128.0, "step": 32.0, "words": ["Closer", "Further"], "unit": "mm"},
		{"k": "thickness", "label": "Thickness", "lo": 6.0, "hi": 20.0, "def": 10.0, "step": 2.0, "words": ["Thinner", "Thicker"], "unit": "mm"}]},
	"knob": {"title": "Knob", "params": [
		{"k": "diameter", "label": "Width", "lo": 16.0, "hi": 60.0, "def": 32.0, "step": 4.0, "words": ["Smaller", "Bigger"], "unit": "mm"},
		{"k": "height", "label": "Height", "lo": 10.0, "hi": 40.0, "def": 18.0, "step": 2.0, "words": ["Lower", "Taller"], "unit": "mm"}]},
	"d_handle": {"title": "D-handle", "params": [
		{"k": "width", "label": "Width", "lo": 64.0, "hi": 220.0, "def": 128.0, "step": 16.0, "words": ["Narrower", "Wider"], "unit": "mm"},
		{"k": "thickness", "label": "Thickness", "lo": 6.0, "hi": 20.0, "def": 10.0, "step": 2.0, "words": ["Thinner", "Thicker"], "unit": "mm"}]},
	# p078makeacasef: a case for a board (Parts > Boards). "board" picks the board (1 Raspberry Pi, 2 Arduino Uno): its numbers are the
	# Boards chips (easy_part.gd), so its slider is hidden there ("parts": true). Its features are the same count for both boards.
	"case": {"title": "Board case", "parts": true, "params": [
		{"k": "board", "label": "Board", "lo": 1.0, "hi": 2.0, "def": 1.0, "step": 1.0, "words": ["Raspberry Pi", "Arduino Uno"], "raw": true, "unit": "board"}]},
	# P080 WOOD BOARDS: a flat wood board, mm (Parts > Wood boards): width across X, thickness up Y, length along Z. Its sliders are the board's sizes
	"board": {"title": "Wood board", "params": [
		{"k": "width", "label": "Width", "lo": 10.0, "hi": 1300.0, "def": 89.0, "step": 1.0, "words": ["Narrower", "Wider"]},
		{"k": "thickness", "label": "Thickness", "lo": 3.0, "hi": 50.0, "def": 38.0, "step": 1.0, "words": ["Thinner", "Thicker"]},
		{"k": "length", "label": "Length", "lo": 100.0, "hi": 2500.0, "def": 2438.0, "step": 10.0, "words": ["Shorter", "Longer"]}]},
}

## P069 BEARINGS: [bore, outside diameter, width] in mm of the bearings 608, 625, 688 (deep groove ball bearings, ISO 15 sizes)
const BEARING_SIZE := [[8.0, 22.0, 7.0], [5.0, 16.0, 5.0], [8.0, 16.0, 5.0]]
const SEAT_WALL := 6.0      # mm: the holder's wall beside the bearing, and the floor under its pocket
const SEAT_CLEAR := 0.2     # mm: the pocket is the outside diameter + this (the bearing drops in and turns)
const SEAT_BEAR_GAP := 15.0 # mm: the bearing stands this far beside the holder's edge (the two never touch)

## P071 HANDLES: the chip sizes (mm) by kind, in the Parts library's Handles grid: each row's three sizes, and the template number each one sets
const HANDLE_SIZES := {"drawer_pull": [96, 128, 160], "knob": [24, 32, 40], "d_handle": [96, 128, 160]}
const HANDLE_KEY := {"drawer_pull": "spacing", "knob": "diameter", "d_handle": "width"}
const HANDLE_NAME := {"drawer_pull": "Drawer pull", "knob": "Knob", "d_handle": "D-handle"}
const PULL_END := 14.0   # mm from a drawer pull's hole to its end: the bar is spacing + 2 x 14 mm long
const PULL_W := 12.0     # mm: a drawer pull's bar height (its width across the front)
const PULL_HOLE := 2.25  # mm radius: a 4.5 mm hole, for an M4 screw
const D_H := 36.0        # mm: a D-handle's height (outside), the loop's bar is D_BAR thick
const D_BAR := 9.0

## p078makeacasef: the boards a case fits. L x W = the board in mm (x along the board's long side, z its width); holes = the mounting holes
## from the board's corner (mm, x and z); ports = the two port openings on the +x wall, as z ranges from the board's corner (mm).
const CASE_BOARDS := {
	1: {"name": "Raspberry Pi", "L": 85.0, "W": 56.0, "holes": [[3.5, 3.5], [61.5, 3.5], [3.5, 52.5], [61.5, 52.5]], "ports": [[8.0, 20.0], [26.0, 44.0]]},
	2: {"name": "Arduino Uno", "L": 68.6, "W": 53.3, "holes": [[14.0, 2.5], [15.3, 50.7], [66.1, 7.6], [66.1, 35.5]], "ports": [[6.0, 16.0], [30.0, 42.0]]},
}
const CASE_WALL := 3.0        # mm: every wall and the floor
const CASE_CLEAR := 1.0       # mm: the gap between the board's edge and the inside wall
const CASE_H := 26.0          # mm: the box's height (open at the top)
const CASE_STAND := 9.0       # mm: a standoff's top, above the box's outside floor
const CASE_STAND_R := 2.5     # mm: a standoff's outside radius (5 mm across)
const CASE_HOLE_R := 1.2      # mm: the screw hole through a standoff and the floor (and the lid)
const CASE_LID := 3.0         # mm: the lid's thickness; it lies beside the box, not on it
const CASE_GAP := 10.0        # mm: the gap between the box and the lid
const CASE_PORT_Y := [11.0, 21.0]   # mm: the port openings' height on the wall

## NSCREW2: ISO 4762 socket head screws: nominal size -> [head diameter, head height] (mm). The shank is the nominal size, plain (no thread).
const SCREW_HEAD := {3: [5.5, 3.0], 4: [7.0, 4.0], 5: [8.5, 5.0], 6: [10.0, 6.0]}
## NNUTWASHER: ISO 4032 nut [across flats, thickness] and ISO 7089 washer [inside, outside, thickness] (mm), by the nominal size M3..M6.
## They stand on the floor beside the screw: the washer's centre at X 18 mm, the nut's at X 40 mm (the screw's head is under 6 mm wide).
const NUT_ISO := {3: [5.5, 2.4], 4: [7.0, 3.2], 5: [8.0, 4.7], 6: [10.0, 5.2]}
const WASH_ISO := {3: [3.2, 7.0, 0.5], 4: [4.3, 9.0, 0.8], 5: [5.3, 10.0, 1.0], 6: [6.4, 12.0, 1.6]}
const NW_WASHER_X := 18.0
const NW_NUT_X := 40.0
const NW_N := 8   # the features the nut and washer take: a washer (a disc, a bore cut) and a nut (a hex, a bore cut)


## NNUTWASHER: the nut and washer features for size d, appended to fs (the screw's features, so the ids go on from them). Returns only the new ones.
## Both are sketched on the Top plane (sketch x = X, the normal is up Y), so they stand on the floor with their holes along Y.
static func nw_features(fs: Array, d: int) -> Array:
	var base := fs.size()
	var sd := clampi(int(roundf(float(d))), 3, 6)
	var w: Array = WASH_ISO[sd]
	var wc := [NW_WASHER_X, 0.0]
	_ex(fs, _sk(fs, "top", [{"k": "circle", "c": wc, "r": float(w[1]) * 0.5}]), "extrude", float(w[2]), "new")
	_ex(fs, _sk(fs, "top", [{"k": "circle", "c": wc, "r": float(w[0]) * 0.5}]), "extrude", float(w[2]) + 2.0, "cut")
	var n: Array = NUT_ISO[sd]
	var R: float = float(n[0]) / sqrt(3.0)   # a corner's radius: the corners point along X, the flats face Z
	var hex := []
	for k in 6:
		hex.append(Vector2(NW_NUT_X + R * cos(float(k) * PI / 3.0), R * sin(float(k) * PI / 3.0)))
	_ex(fs, _sk(fs, "top", _poly(hex)), "extrude", float(n[1]), "new")
	_ex(fs, _sk(fs, "top", [{"k": "circle", "c": [NW_NUT_X, 0.0], "r": float(sd) * 0.5}]), "extrude", float(n[1]) + 2.0, "cut")
	return fs.slice(base)


## NNUTWASHER: a screw on the floor takes its nut and washer: they go on the END of the record and the easy record remembers where ("nw" = their first index)
static func nw_add(rec: Dictionary, d: int) -> void:
	var feats: Array = rec["features"]
	var start := feats.size()
	feats.append_array(nw_features(feats.duplicate(), d))
	rec["seq"] = maxi(int(rec.get("seq", 0)), feats.size())
	(rec["easy"] as Dictionary)["nw"] = start


## NNUTWASHER: a size change rewrites the nut and washer too (same count for every size, so the features after them keep their ids). Does nothing without them.
static func nw_set(rec: Dictionary, d: int) -> void:
	var e: Dictionary = rec.get("easy", {})
	if e.is_empty() or int(e.get("nw", -1)) < 0:
		return
	var start := int(e["nw"])
	var feats: Array = rec["features"]
	var head: Array = feats.slice(0, start)
	var rest: Array = feats.slice(mini(start + NW_N, feats.size()))
	rec["features"] = head + nw_features(head.duplicate(), d) + rest


## FRIDAY 37 BOSS CHIP: a round post beside a screw, sized by it: outside = the screw's head + 4 mm, hole = the screw's size + 0.5 mm (the screw goes in),
## height = the screw's length L. It stands on the floor at X BO_X (the washer is at +18, the nut at +40). Four features: a sketch and its extrude for the post, then for its hole.
const BO_N := 4   # a sketch and its extrude, twice (the post, then its hole): four features
const BO_X := -18.0
static func bo_features(fs: Array, d: int, L: float) -> Array:
	var base := fs.size()
	var sd := clampi(int(roundf(float(d))), 3, 6)
	var outer: float = float(SCREW_HEAD[sd][0]) + 4.0
	_ex(fs, _sk(fs, "top", [{"k": "circle", "c": [BO_X, 0.0], "r": outer * 0.5}]), "extrude", L, "new")
	_ex(fs, _sk(fs, "top", [{"k": "circle", "c": [BO_X, 0.0], "r": (float(sd) + 0.5) * 0.5}]), "extrude", L + 2.0, "cut")
	return fs.slice(base)


## FRIDAY 37 BOSS CHIP: a screw on the floor takes its post: it goes on the END of the record ("bo" = its first index in the easy record)
static func bo_add(rec: Dictionary, d: int, L: int) -> void:
	var feats: Array = rec["features"]
	var start := feats.size()
	feats.append_array(bo_features(feats.duplicate(), d, float(L)))
	rec["seq"] = maxi(int(rec.get("seq", 0)), feats.size())
	(rec["easy"] as Dictionary)["bo"] = start


## FRIDAY 37 BOSS CHIP: a size change rewrites the post too (the same count for every size, so the features after it keep their ids). Does nothing without it.
static func bo_set(rec: Dictionary, d: int, L: int) -> void:
	var e: Dictionary = rec.get("easy", {})
	if e.is_empty() or int(e.get("bo", -1)) < 0:
		return
	var start := int(e["bo"])
	var feats: Array = rec["features"]
	var head: Array = feats.slice(0, start)
	var rest: Array = feats.slice(mini(start + BO_N, feats.size()))
	rec["features"] = head + bo_features(head.duplicate(), d, float(L)) + rest


## the default camera of a template: [yaw, pitch] degrees, a 3/4 view in which its main shape reads (the axe turns further so its blade face shows)
const VIEW := {"sword": [30.0, -22.0], "axe": [42.0, -20.0], "shield": [30.0, -18.0], "chair": [38.0, -22.0], "crate": [34.0, -24.0], "box": [34.0, -24.0], "cylinder": [34.0, -22.0], "sphere": [30.0, -20.0], "tube": [34.0, -22.0], "plate": [34.0, -28.0], "case": [32.0, -24.0], "slothole": [34.0, -30.0], "hinge": [35.0, -12.0], "phone": [34.0, -22.0], "shelf": [34.0, -24.0], "lidbox": [34.0, -24.0]}


static func view_of(t: String) -> Array:
	return VIEW.get(t, [30.0, -22.0])


static func defaults(t: String) -> Dictionary:
	var p := {}
	for d in T[t]["params"]:
		p[d["k"]] = d["def"]
	return p


static func param(t: String, k: String) -> Dictionary:
	for d in T[t]["params"]:
		if d["k"] == k:
			return d
	return {}


## a new record of template t (numbers p: missing ones are the defaults, all clamped to their range)
static func make(t: String, p := {}) -> Dictionary:
	var rec := Part.make(String(T[t]["title"]))
	var pp := defaults(t)
	for k in p:
		if pp.has(k):
			pp[k] = clampf(float(p[k]), float(param(t, k)["lo"]), float(param(t, k)["hi"]))
	var fs := features_of(t, pp)
	rec["features"] = fs
	rec["seq"] = fs.size()
	rec["easy"] = {"t": t, "p": pp, "n": fs.size()}
	return rec


## writes numbers into the record's template and rewrites the features it owns (the user's own later features stay)
static func retemplate(rec: Dictionary, p: Dictionary) -> void:
	var e: Dictionary = rec.get("easy", {})
	if e.is_empty():
		return
	var t := String(e["t"])
	for k in p:
		if (e["p"] as Dictionary).has(k):
			e["p"][k] = clampf(float(p[k]), float(param(t, k)["lo"]), float(param(t, k)["hi"]))
	var fs := features_of(t, e["p"])
	var feats: Array = rec["features"]
	for i in mini(fs.size(), feats.size()):
		feats[i] = fs[i]


## a round (fillet) that no longer replays after a size changed: its radius shrinks to the biggest of 0.5 / 0.3 / 0.2 / 0.1 mm (or 1 mm and
## less than the old one) that works; when none does, the edges that still take 0.1 mm are kept and the rest left out; a round with no edge
## left is taken off. Returns the words for the user ("" when every round replays). Only fillets with an error are touched.
static func fit_rounds(rec: Dictionary) -> String:
	if not rec.has("features"):   # no part at all (the {} record: Expert took its empty sketch out): no round to fit
		return ""
	var note := ""
	var i := 0
	while i < (rec["features"] as Array).size():
		var f: Dictionary = rec["features"][i]
		if String(f["t"]) != "fillet" or String(Part.replay(rec)["errors"].get(String(f["id"]), "")) == "":
			i += 1
			continue
		var r0 := float(f["r"])
		var cands := []
		for c in [r0 * 0.5, 1.0, 0.5, 0.3, 0.2, 0.1]:
			var cc := snappedf(float(c), 0.1)
			if cc < r0 - 1e-6 and cc >= 0.1 - 1e-6 and not cands.has(cc):
				cands.append(cc)
		cands.sort()
		cands.reverse()
		var done := false
		for c in cands:
			f["r"] = c
			if String(Part.replay(rec)["errors"].get(String(f["id"]), "")) == "":
				note = "The round is now %s mm: the part is too small for %s mm" % [str(c), str(r0)]
				done = true
				break
		if not done:
			var all_edges: Array = (f["edges"] as Array).duplicate(true)
			var good := []
			f["r"] = 0.1
			f["edges"] = []
			for e in all_edges:
				var trial := good.duplicate(true)
				trial.append(e)
				f["edges"] = trial
				if String(Part.replay(rec)["errors"].get(String(f["id"]), "")) == "":
					good = trial
			f["edges"] = good
			if good.is_empty():
				(rec["features"] as Array).remove_at(i)
				note = "Too thin to round now: the round was taken off"
				continue
			note = "Some edges are too small to round now: the others are rounded"
		i += 1
	return note


static func _sk(fs: Array, plane_name: String, ents: Array) -> String:
	var id := "f%d" % (fs.size() + 1)
	var n := fs.filter(func(f): return f["t"] == "sketch").size() + 1
	fs.append({"t": "sketch", "id": id, "name": "Sketch%d" % n, "plane": plane_name, "ents": ents, "dims": []})
	return id


static func _ex(fs: Array, sketch_id: String, t: String, dist: float, op: String, both := false) -> void:
	var id := "f%d" % (fs.size() + 1)
	var n := fs.filter(func(g): return g["t"] == t).size() + 1
	var f := {"t": t, "id": id, "name": "%s%d" % [t.capitalize(), n], "sketch": sketch_id, "op": op}
	if t == "extrude":
		f["dist"] = dist
		f["both"] = both
	else:
		f["axis"] = "x"
		f["deg"] = 360.0
	fs.append(f)


static func _rect(a: Vector2, b: Vector2) -> Dictionary:
	return {"k": "rect", "a": Part.arr2(a), "b": Part.arr2(b)}


## a closed outline given in the Right plane's (Y, Z) as Vector2(y, z): the plane's sketch x runs along -Z, its y is Y
static func _yz(pts: Array) -> Array:
	var sk := []
	for p in pts:
		sk.append(Vector2(-(p as Vector2).y, (p as Vector2).x))
	return _poly(sk)


## a closed outline given as Vector2(y, z) points (the car's side profile) with each corner rounded to its radius (mm, 0 = sharp):
## lines and arcs in the Right plane's sketch (x = -Z, y = Y). A corner's arc runs between the two tangent points.
static func _rounded(yz: Array, radii: Array) -> Array:
	var n := yz.size()
	var pts := []
	for p in yz:
		pts.append(Vector2(-(p as Vector2).y, (p as Vector2).x))
	var tp := []   # per corner: [tangent 1, arc middle, tangent 2] (a sharp corner: the corner three times)
	for i in n:
		var P: Vector2 = pts[i]
		var r: float = radii[i]
		if r <= 0.0:
			tp.append([P, P, P])
			continue
		var u1: Vector2 = (pts[(i - 1 + n) % n] - P).normalized()
		var u2: Vector2 = (pts[(i + 1) % n] - P).normalized()
		var th := acos(clampf(u1.dot(u2), -1.0, 1.0)) * 0.5   # half the corner's angle
		var bis := (u1 + u2).normalized()
		var c := P + bis * (r / sin(th))
		tp.append([P + u1 * (r / tan(th)), c - bis * r, P + u2 * (r / tan(th))])
	var out := []
	for i in n:
		var cur: Array = tp[i]
		if float(radii[i]) > 0.0:
			out.append({"k": "arc", "a": Part.arr2(cur[0]), "m": Part.arr2(cur[1]), "b": Part.arr2(cur[2])})
		var nx: Vector2 = tp[(i + 1) % n][0]
		if (cur[2] as Vector2).distance_to(nx) > 1e-3:
			out.append({"k": "line", "a": Part.arr2(cur[2]), "b": Part.arr2(nx)})
	return out


static func _poly(pts: Array) -> Array:
	var out := []
	for i in pts.size():
		out.append({"k": "line", "a": Part.arr2(pts[i]), "b": Part.arr2(pts[(i + 1) % pts.size()])})
	return out


static func features_of(t: String, p: Dictionary) -> Array:
	var fs: Array = []
	match t:
		"box":
			_ex(fs, _sk(fs, "front", [_rect(Vector2(0, 0), Vector2(p["width"], p["height"]))]), "extrude", p["depth"], "new")
		"cylinder":
			_ex(fs, _sk(fs, "front", [{"k": "circle", "c": [0.0, 0.0], "r": float(p["diameter"]) * 0.5}]), "extrude", p["height"], "new")
		"sphere":
			# a half disc about the sketch's x axis (the same as the wheel's turn): the arc from -R over the top to +R, back along the axis
			var R: float = float(p["diameter"]) * 0.5
			_ex(fs, _sk(fs, "front", [{"k": "arc", "a": Part.arr2(Vector2(-R, 0)), "m": Part.arr2(Vector2(0, R)), "b": Part.arr2(Vector2(R, 0))}, {"k": "line", "a": Part.arr2(Vector2(R, 0)), "b": Part.arr2(Vector2(-R, 0))}]), "revolve", 0.0, "new")
		"tube":
			var Ro: float = float(p["diameter"]) * 0.5
			var h: float = p["height"]
			_ex(fs, _sk(fs, "front", [{"k": "circle", "c": [0.0, 0.0], "r": Ro}]), "extrude", h, "new")
			_ex(fs, _sk(fs, "front", [{"k": "circle", "c": [0.0, 0.0], "r": maxf(Ro - float(p["wall"]), 1.0)}]), "extrude", 2.0 * h + 20.0, "cut", true)
		"plate":
			_ex(fs, _sk(fs, "front", [_rect(Vector2(0, 0), Vector2(p["width"], p["length"]))]), "extrude", p["thickness"], "new")
		"screw":
			# NSCREW2: one lathe profile (x = radius, y = height, mm) spun round the up axis (Y), from the floor: the shank, then the head on top
			var sd := clampi(int(roundf(float(p["d"]))), 3, 6)
			var hd: Array = SCREW_HEAD[sd]
			var sl: float = float(p["L"])
			var r := float(sd) * 0.5
			var R: float = float(hd[0]) * 0.5
			var hk: float = float(hd[1])
			var prof := [Vector2(0, 0), Vector2(r, 0), Vector2(r, sl), Vector2(R, sl), Vector2(R, sl + hk), Vector2(0, sl + hk)]
			var sid := _sk(fs, "front", _poly(prof))
			_ex(fs, sid, "revolve", 0.0, "new")
			fs[fs.size() - 1]["axis"] = "y"
		"bearing":
			# P069: the ring on the floor (its bore and outside diameter from the top face, up Y), the same two steps as a washer
			var b: Array = BEARING_SIZE[clampi(int(roundf(float(p["kind"]))), 0, 2)]
			_ex(fs, _sk(fs, "top", [{"k": "circle", "c": [0.0, 0.0], "r": float(b[1]) * 0.5}]), "extrude", float(b[2]), "new")
			_ex(fs, _sk(fs, "top", [{"k": "circle", "c": [0.0, 0.0], "r": float(b[0]) * 0.5}]), "extrude", float(b[2]) + 2.0, "cut")
		"seat":
			# P069: a holder block standing on the floor (its top face at Y 0, down to -(width + wall)), a pocket cut down from the top
			# face: the bearing's outside diameter + 0.2 mm, as deep as the bearing is wide. The bearing stands on the floor beside it.
			var b: Array = BEARING_SIZE[clampi(int(roundf(float(p["kind"]))), 0, 2)]
			var h: float = float(b[1]) * 0.5 + SEAT_WALL
			_ex(fs, _sk(fs, "top", [_rect(Vector2(-h, -h), Vector2(h, h))]), "extrude", -(float(b[2]) + SEAT_WALL), "new")
			_ex(fs, _sk(fs, "top", [{"k": "circle", "c": [0.0, 0.0], "r": float(b[1]) * 0.5 + SEAT_CLEAR * 0.5}]), "extrude", -float(b[2]), "cut")
			var cx: float = h + SEAT_BEAR_GAP + float(b[1]) * 0.5
			_ex(fs, _sk(fs, "top", [{"k": "circle", "c": [cx, 0.0], "r": float(b[1]) * 0.5}]), "extrude", float(b[2]), "new")
			_ex(fs, _sk(fs, "top", [{"k": "circle", "c": [cx, 0.0], "r": float(b[0]) * 0.5}]), "extrude", float(b[2]) + 2.0, "cut")
		"sword":
			var L: float = p["blade_length"]
			var w: float = p["width"]
			var g: float = p["guard_size"]
			var th: float = p["thickness"]
			var tip := minf(w * 1.6, L * 0.3)
			var hw := w * 0.5
			# the blade tapers from the guard to 40 % of its width at the shoulder, then comes to a point
			_ex(fs, _sk(fs, "front", _poly([Vector2(0, -hw), Vector2(L - tip, -hw * 0.4), Vector2(L, 0), Vector2(L - tip, hw * 0.4), Vector2(0, hw)])), "extrude", th, "new", true)
			# a diamond section: the spine is th, the edges 6 % of it: the two shoulders come off each face, cut along the whole blade
			var e := th * 0.06
			for sg in [1.0, -1.0]:
				var m := 2.0
				var cut := [Vector2(-hw - m, sg * e), Vector2(-hw, sg * e), Vector2(0, sg * th * 0.5), Vector2(hw, sg * e), Vector2(hw + m, sg * e),
					Vector2(hw + m, sg * (th * 0.5 + m)), Vector2(-hw - m, sg * (th * 0.5 + m))]
				_ex(fs, _sk(fs, "right", _yz(cut)), "extrude", 2.0 * L + 20.0, "cut", true)
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-6, -g * 0.5), Vector2(4, g * 0.5))]), "extrude", 8.0, "join", true)
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-106, 0), Vector2(-2, 11))]), "revolve", 0.0, "join")
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-124, 0), Vector2(-104, 15))]), "revolve", 0.0, "join")
		"axe":
			var H: float = p["handle_length"]
			var hw: float = p["head_width"]
			var ht: float = p["head_thickness"]
			var r: float = float(p["handle_thickness"]) * 0.5
			_ex(fs, _sk(fs, "front", [_rect(Vector2(0, 0), Vector2(H + 10, r))]), "revolve", 0.0, "new")
			var ey := maxf(r + 4.0, 18.0)
			# a bearded wedge: the poll and eye round the handle, then the blade flares to the edge (its lower corner hangs a little back: the beard)
			_ex(fs, _sk(fs, "front", _poly([Vector2(H - 40, -ey), Vector2(H + 10, -ey), Vector2(H + 85, -hw * 0.5), Vector2(H + 110, hw * 0.5), Vector2(H + 10, ey), Vector2(H - 40, ey)])), "extrude", ht, "join", true)
			# the edge is thinner than the eye: two thin wedges come off the faces, side-on (Top plane: sketch y runs along -Z)
			var edge := minf(4.0, ht * 0.3)
			var x0 := H + 10.0
			var x1 := H + 112.0
			var hz := ht * 0.5
			for sg in [1.0, -1.0]:   # one closed wire per sketch: one wedge off each face
				_ex(fs, _sk(fs, "top", _poly([Vector2(x0, sg * hz), Vector2(x1, sg * edge * 0.5), Vector2(x1, sg * (hz + 1.0)), Vector2(x0, sg * (hz + 1.0))])), "extrude", hw + 80.0, "cut", true)
		"shield":
			var R: float = p["radius"]
			var th: float = p["thickness"]
			var bo: float = p["boss"]
			_ex(fs, _sk(fs, "front", [{"k": "circle", "c": [0.0, 0.0], "r": R}]), "extrude", th, "new")
			_ex(fs, _sk(fs, "front", [{"k": "circle", "c": [0.0, 0.0], "r": bo}]), "extrude", th + bo * 0.4, "join")
		"crate":
			var w: float = p["width"]
			var h: float = p["height"]
			var d: float = p["depth"]
			var o: float = p["lid"]
			_ex(fs, _sk(fs, "front", [_rect(Vector2(0, 0), Vector2(w, h))]), "extrude", d, "new")
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-o, h - 20), Vector2(w + o, h + 30))]), "extrude", d, "join")
		"slothole":
			# P032: the plate (Length + 40 by Width + 40, standing on the floor) and the hole: a stadium of Length x Width drawn
			# with two straight sides and two round ends (three-point arcs), cut through the plate's thickness from the floor
			var L: float = p["length"]
			var w: float = p["width"]
			var th: float = p["thickness"]
			var pl := Vector2(L + 40.0, w + 40.0)
			_ex(fs, _sk(fs, "top", [_rect(Vector2(0, 0), pl)]), "extrude", th, "new")
			var c := pl * 0.5
			var a := (L - w) * 0.5   # half the distance between the two round ends' centres
			var r := w * 0.5
			var hole := [
				{"k": "line", "a": Part.arr2(Vector2(c.x - a, c.y + r)), "b": Part.arr2(Vector2(c.x + a, c.y + r))},
				{"k": "arc", "a": Part.arr2(Vector2(c.x + a, c.y + r)), "m": Part.arr2(Vector2(c.x + a + r, c.y)), "b": Part.arr2(Vector2(c.x + a, c.y - r))},
				{"k": "line", "a": Part.arr2(Vector2(c.x + a, c.y - r)), "b": Part.arr2(Vector2(c.x - a, c.y - r))},
				{"k": "arc", "a": Part.arr2(Vector2(c.x - a, c.y - r)), "m": Part.arr2(Vector2(c.x - a - r, c.y)), "b": Part.arr2(Vector2(c.x - a, c.y + r))},
			]
			_ex(fs, _sk(fs, "top", hole), "extrude", th + 2.0, "cut")
		"phone":
			# P096: the wedge in the front plane (x across the base, y up), extruded by the width
			var pd: float = p["depth"]
			var ph: float = p["height"]
			_ex(fs, _sk(fs, "front", _poly([Vector2(0, 0), Vector2(pd, 0), Vector2(0, ph)])), "extrude", p["width"], "new")
		"shelf":
			# P096: an L in the front plane: the shelf leg along the bottom, the upright on the left, both thickness t, extruded by the width
			var sl: float = p["leg"]
			var su: float = p["upright"]
			var st: float = p["thickness"]
			_ex(fs, _sk(fs, "front", _poly([Vector2(0, 0), Vector2(sl, 0), Vector2(sl, st), Vector2(st, st), Vector2(st, su), Vector2(0, su)])), "extrude", p["width"], "new")
		"lidbox":
			# P096: the box, and its lid lying beside it on the floor (the Board case's rule: a 10 mm gap, its own solid)
			var bw: float = p["width"]
			var bh: float = p["height"]
			var bd: float = p["depth"]
			var bl: float = p["lid"]
			_ex(fs, _sk(fs, "front", [_rect(Vector2(0, 0), Vector2(bw, bh))]), "extrude", bd, "new")
			_ex(fs, _sk(fs, "front", [_rect(Vector2(bw + 10.0, 0), Vector2(2.0 * bw + 10.0, bl))]), "extrude", bd, "new")
		"chair":
			var sh: float = p["seat_height"]
			var w: float = p["seat_width"]
			var d: float = p["seat_depth"]
			var bh: float = p["back_height"]
			var st := 30.0
			var lt := 40.0
			_ex(fs, _sk(fs, "front", _poly([Vector2(0, sh), Vector2(w, sh), Vector2(w, 0), Vector2(w - lt, 0), Vector2(w - lt, sh - st), Vector2(lt, sh - st), Vector2(lt, 0), Vector2(0, 0)])), "extrude", d, "new")
			_ex(fs, _sk(fs, "front", [_rect(Vector2(0, sh - st), Vector2(w, sh + bh))]), "extrude", 30.0, "join")
			_ex(fs, _sk(fs, "right", [_rect(Vector2(-(d - lt), 0), Vector2(-lt, sh - st))]), "extrude", w, "cut")
		"car":
			# a car in side profile (the Right plane: sketch x = -Z, the car drives along +Z; sketch y = Y), extruded across the width.
			# The lower body (sills at the wheel centre's height, the belt at 55 % of the height, nose and tail rounded) is one extrusion
			# across the full width; each wheel arch is a circle of the wheel radius + 40 mm cut through it at its axle; the glasshouse
			# (windscreen 30 deg from horizontal, roof, rear hatch) is a narrower extrusion on the belt.
			var g := car_geom(p)
			var S: float = g["S"]
			var yb: float = g["yb"]
			var zn: float = g["zn"]
			var zt: float = g["zt"]
			var lower := [Vector2(S, zt), Vector2(yb, zt), Vector2(yb, g["zwb"]), Vector2(g["yn"], zn), Vector2(S, zn)]
			_ex(fs, _sk(fs, "right", _rounded(lower, [60.0, 80.0, 0.0, 120.0, 60.0])), "extrude", g["W"], "new", true)
			for zc in [float(p["wheelbase"]) * 0.5, -float(p["wheelbase"]) * 0.5]:
				_ex(fs, _sk(fs, "right", [{"k": "circle", "c": [-zc, S], "r": g["A"]}]), "extrude", 2.0 * g["W"], "cut", true)
			var cabin := [Vector2(yb, g["zwb"]), Vector2(g["H"], g["zrf"]), Vector2(g["H"], g["zrr"]), Vector2(yb, g["zrh"])]
			_ex(fs, _sk(fs, "right", _rounded(cabin, [0.0, 150.0, 150.0, 0.0])), "extrude", g["wc"], "join", true)
		"bracket":
			# FRIDAY 73: a bent bracket in the front plane (sketch x = along the foot, y = up), extruded 'width' both ways from the middle, then two
			# 6 mm screw holes cut through the legs (3 features per hole: a sketch and a cut). L: a foot and an upright; corner brace: the L with a
			# 0.4 leg gusset in the corner; T: a bar on top of a stem (the holes: one through the bar, one through the stem)
			var kind := int(roundf(float(p["kind"])))
			var S: float = p["leg"]
			var th: float = p["thickness"]
			var prof := []
			if kind == 2:
				var sx := S * 0.5 - th * 0.5
				prof = [Vector2(sx, 0), Vector2(sx + th, 0), Vector2(sx + th, S - th), Vector2(S, S - th), Vector2(S, S), Vector2(0, S), Vector2(0, S - th), Vector2(sx, S - th)]
			elif kind == 3:
				var g := S * 0.4
				prof = [Vector2(0, 0), Vector2(S, 0), Vector2(S, th), Vector2(th + g, th), Vector2(th, th + g), Vector2(th, S), Vector2(0, S)]
			else:
				prof = [Vector2(0, 0), Vector2(S, 0), Vector2(S, th), Vector2(th, th), Vector2(th, S), Vector2(0, S)]
			_ex(fs, _sk(fs, "front", _poly(prof)), "extrude", float(p["width"]), "new", true)
			var hr := 3.0   # the screw hole's radius (6 mm)
			if kind == 2:
				_ex(fs, _sk(fs, "top", [{"k": "circle", "c": [S * 0.2, 0.0], "r": hr}]), "extrude", 300.0, "cut", true)
				_ex(fs, _sk(fs, "right", [{"k": "circle", "c": [0.0, S * 0.3], "r": hr}]), "extrude", 300.0, "cut", true)
			else:
				_ex(fs, _sk(fs, "top", [{"k": "circle", "c": [S * 0.6, 0.0], "r": hr}]), "extrude", 300.0, "cut", true)
				_ex(fs, _sk(fs, "right", [{"k": "circle", "c": [0.0, S * 0.6], "r": hr}]), "extrude", 300.0, "cut", true)
		"gear":
			# NGEAR: a spur gear in the front plane: a tooth outline of N teeth (the flanks cross the pitch circle at half a tooth pitch, so
			# the tooth is as wide as the space there), extruded 5 mm x module, with the centre hole (0.12 x pitch diameter) cut through
			var N := int(roundf(float(p["teeth"])))
			var md := float(int(roundf(float(p["module"]))))
			var th: float = p["thickness"]
			_ex(fs, _sk(fs, "front", gear_outline(N, md)), "extrude", th, "new")
			_ex(fs, _sk(fs, "front", [{"k": "circle", "c": [0.0, 0.0], "r": 0.12 * N * md}]), "extrude", th, "cut", true)
		"foot":
			# P075: a rubber foot, a disc d across and h tall, standing on the floor (Top plane: the disc lies flat, Y up)
			_ex(fs, _sk(fs, "top", [{"k": "circle", "c": [0.0, 0.0], "r": float(p["d"]) * 0.5}]), "extrude", float(p["h"]), "new")
		"clip":
			# P075: a ring d across, w tall, 2.5 mm wall; a 3 mm opening cut through the wall on the +X side (the cable snaps in there)
			var d: float = p["d"]
			var w: float = p["w"]
			_ex(fs, _sk(fs, "top", [{"k": "circle", "c": [0.0, 0.0], "r": d * 0.5}]), "extrude", w, "new")
			_ex(fs, _sk(fs, "top", [{"k": "circle", "c": [0.0, 0.0], "r": d * 0.5 - 2.5}]), "extrude", 2.0 * w, "cut", true)
			_ex(fs, _sk(fs, "top", [_rect(Vector2(0.0, -1.5), Vector2(d, 1.5))]), "extrude", 2.0 * w, "cut", true)
		"slot":
			# P075: a plate (L + 12 mm long, 10 mm wide, t thick) with a 2.5 mm wide slot L long cut through it, 6 mm in from the start
			var L: float = p["L"]
			var th: float = p["t"]
			_ex(fs, _sk(fs, "top", [_rect(Vector2(0.0, 0.0), Vector2(L + 12.0, 10.0))]), "extrude", th, "new")
			_ex(fs, _sk(fs, "top", [_rect(Vector2(6.0, 3.75), Vector2(6.0 + L, 6.25))]), "extrude", 2.0 * th, "cut", true)
		"drawer_pull":
			# P071: a flat bar in the front plane, spacing + 28 mm long, 12 mm high, extruded by the thickness; two 4.5 mm holes at the
			# spacing cut through (both sides), so an M4 screw from the Parts page goes in
			var sp: float = p["spacing"]
			var pth: float = p["thickness"]
			var bl := sp * 0.5 + PULL_END
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-bl, -PULL_W * 0.5), Vector2(bl, PULL_W * 0.5))]), "extrude", pth, "new")
			for hx in [-sp * 0.5, sp * 0.5]:   # one sketch per hole: a sketch with two circles cut only one of them
				_ex(fs, _sk(fs, "front", [{"k": "circle", "c": [hx, 0.0], "r": PULL_HOLE}]), "extrude", 2.0 * pth, "cut", true)   # both ways: the cut is 2 x the thickness, or only half of each hole goes
		"knob":
			# P071: a plain round knob, turned about the up axis (like the screw): width across, height up from the floor
			var kr: float = float(p["diameter"]) * 0.5
			var kh: float = p["height"]
			var kprof := [Vector2(0, 0), Vector2(kr, 0), Vector2(kr, kh), Vector2(0, kh)]
			_ex(fs, _sk(fs, "front", _poly(kprof)), "revolve", 0.0, "new")
			fs[fs.size() - 1]["axis"] = "y"
		"d_handle":
			# P071: a loop: a 36 mm high block of the width, with a window cut through it (the bar is 9 mm all round)
			var dw: float = p["width"]
			var dth: float = p["thickness"]
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-dw * 0.5, -D_H * 0.5), Vector2(dw * 0.5, D_H * 0.5))]), "extrude", dth, "new")
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-dw * 0.5 + D_BAR, -D_H * 0.5 + D_BAR), Vector2(dw * 0.5 - D_BAR, D_H * 0.5 - D_BAR))]), "extrude", 2.0 * dth, "cut", true)   # both ways (see the drawer pull)
		"axwheel", "castor":
			# P072: a tyre (the profile turned about the sketch's x axis = world X, the axle), with a round axle hole of 'hole' mm cut
			# through its middle along X (a circle on the Right plane, extruded both ways past the tyre)
			var AR: float = p["radius"]
			var aw: float = p["width"]
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-aw * 0.5, 0.0), Vector2(aw * 0.5, AR))]), "revolve", 0.0, "new")
			_ex(fs, _sk(fs, "right", [{"k": "circle", "c": [0.0, 0.0], "r": float(p["hole"]) * 0.5}]), "extrude", 2.0 * aw, "cut", true)
		"rack":
			# P066: a rack in the front plane: n teeth along a bar 3 x module tall, extruded thickness
			var NR := int(roundf(float(p["teeth"])))
			var mr := float(int(roundf(float(p["module"]))))
			_ex(fs, _sk(fs, "front", rack_outline(NR, mr)), "extrude", float(p["thickness"]), "new")
		"board":
			return _board_features(p)   # P080: the wood board (end of this file)
		"case":
			# p078makeacasef: a box for a board, open at the top: a 3 mm wall and floor, the standoffs (5 mm across, 9 mm up from the floor) at the
			# board's holes with a screw hole through each, two port openings cut through the +x wall (an offset plane 1.5 mm inside the wall, so the
			# cut reaches only that wall), and the lid as its own flat plate beside the box (3 mm, the same footprint, the same four holes)
			var b: Dictionary = CASE_BOARDS[clampi(int(roundf(float(p["board"]))), 1, 2)]
			var inset := CASE_CLEAR + CASE_WALL
			var lo: float = float(b["L"]) + 2.0 * inset
			var zo: float = float(b["W"]) + 2.0 * inset
			_ex(fs, _sk(fs, "front", [_rect(Vector2(0, 0), Vector2(lo, CASE_H))]), "extrude", zo, "new")
			fs.append({"t": "shell", "id": "f%d" % (fs.size() + 1), "name": "Shell1", "body": 0, "thick": CASE_WALL, "open": "+y"})
			var st := []
			var hs := []
			for h in b["holes"]:
				var hc := [inset + float(h[0]), -(inset + float(h[1]))]   # the top plane's y runs toward -Z
				st.append({"k": "circle", "c": hc, "r": CASE_STAND_R})
				hs.append({"k": "circle", "c": hc, "r": CASE_HOLE_R})
			_ex(fs, _sk(fs, "top", st), "extrude", CASE_STAND, "join")
			_ex(fs, _sk(fs, "top", hs), "extrude", CASE_STAND + 1.0, "cut")
			var pid := "f%d" % (fs.size() + 1)
			fs.append({"t": "plane", "id": pid, "name": "Plane1", "from": "right", "mm": lo - CASE_WALL * 0.5})
			var ports := []
			for pr in b["ports"]:
				var z0: float = float(pr[0]) + inset
				var z1: float = float(pr[1]) + inset
				ports.append(_rect(Vector2(-z1, CASE_PORT_Y[0]), Vector2(-z0, CASE_PORT_Y[1])))   # the right plane's x runs along -Z
			_ex(fs, _sk(fs, pid, ports), "extrude", CASE_WALL + 2.0, "cut", true)
			var lx := lo + CASE_GAP
			_ex(fs, _sk(fs, "top", [_rect(Vector2(lx, 0), Vector2(lx + lo, -zo))]), "extrude", CASE_LID, "new")
			var lh := []
			for h in b["holes"]:
				lh.append({"k": "circle", "c": [lx + inset + float(h[0]), -(inset + float(h[1]))], "r": CASE_HOLE_R})
			_ex(fs, _sk(fs, "top", lh), "extrude", CASE_LID + 1.0, "cut")
		"hinge":
			# p067hinges: in the front plane (x across, y up the door). Butt: a 60 mm plate, 2.5 mm thick, leaf length L. Piano: a 30 mm strip
			# the full door height, 1.5 mm. Living: the whole 60 mm strip 0.8 mm thick (a thin flexible strip; a web with thicker leaves did not build on the kernel).
			var door: float = p["door"]
			var L := clampf(roundf(door / 21.0 / 5.0) * 5.0, 60.0, 150.0)
			var kd := int(roundf(float(p["kind"])))
			if kd == 2:
				_ex(fs, _sk(fs, "front", [_rect(Vector2(-15.0, 0.0), Vector2(15.0, door))]), "extrude", 1.5, "new")
			elif kd == 3:
				_ex(fs, _sk(fs, "front", [_rect(Vector2(-30.0, 0.0), Vector2(30.0, L))]), "extrude", 0.8, "new")
			else:
				_ex(fs, _sk(fs, "front", [_rect(Vector2(-30.0, 0.0), Vector2(30.0, L))]), "extrude", 2.5, "new")
		"spring":
			# p070: one sketch loop (the outline of the coils' union in the front plane) turned about the up axis: one solid, two features
			# whatever the turns (so a Turns change keeps the ids of the steps after it)
			var prof := spring_profile(int(clampi(int(roundf(float(p["turns"]))), 3, 12)), float(p["wire"]), float(p["size"]))
			var sid := _sk(fs, "front", _poly(prof))
			_ex(fs, sid, "revolve", 0.0, "new")
			fs[fs.size() - 1]["axis"] = "y"
		"wheel":
			# a tyre: the profile (width x radius) turned about the sketch's x axis = world X, the axle (side to side)
			var R: float = p["radius"]
			var w: float = p["width"]
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-w * 0.5, 0.0), Vector2(w * 0.5, R))]), "revolve", 0.0, "new")
	return fs


## p070: the outline (right side up, left side down, mm, the front plane: x = radius, y = height) of n coils of wire w, mean coil diameter dia: each coil is a disk of
## radius w / 2 at height k x 0.8 w + w / 2, the coils overlap, so the outline is their union. Sampled every 0.1 mm (the coil centres sit on
## the 0.1 mm grid, so the widest point and the top are exact). The coil centre line is at radius dia / 2.
static func spring_profile(n: int, w: float, dia: float) -> Array:
	var rc := dia * 0.5
	var h := w * 0.5
	var pitch := 0.8 * w
	var H := (n - 1) * pitch + w
	var right := []
	var left := []
	var steps := int(roundf(H / 0.1))
	for i in steps + 1:
		var y := float(i) * 0.1
		var best := -1.0
		for k in n:
			var d := y - (float(k) * pitch + h)
			if absf(d) <= h + 0.000001:   # the 0.1 mm grid is not exact in floats: the top and bottom points keep their place
				best = maxf(best, sqrt(maxf(0.0, h * h - d * d)))
		if best < 0.0:
			continue
		right.append(Vector2(rc + best, y))
		left.append(Vector2(rc - best, y))
	left.reverse()
	# the two ends are single points (the disk's bottom and top): one vertex each, not two
	var out := []
	for q in right + left:
		if out.is_empty() or (out[-1] as Vector2).distance_to(q) > 0.001:
			out.append(q)
	if out.size() > 1 and (out[0] as Vector2).distance_to(out[-1]) < 0.001:
		out.pop_back()
	return out


## NGEAR: the closed tooth outline of a spur gear with n teeth of module m (mm), as lines. Angles in units of q = pi / (2 n): a tooth is
## 4 q wide at its pitch circle; its tip spans 0.6 q each side of its middle, its root 1.5 q each side (the flank is straight, and it
## is 1.0 q each side where it crosses the pitch circle r = m n / 2). Tips at m (n + 2) / 2, roots at m (n - 2.5) / 2.
static func gear_outline(n: int, m: float) -> Array:
	var ra := m * (n + 2) * 0.5
	var rf := m * (n - 2.5) * 0.5
	var q := PI / (2.0 * n)
	var pts := []
	for k in n:
		var t := TAU * k / n
		pts.append(Vector2.from_angle(t - 0.6 * q) * ra)
		pts.append(Vector2.from_angle(t + 0.6 * q) * ra)
		pts.append(Vector2.from_angle(t + 1.5 * q) * rf)
		pts.append(Vector2.from_angle(t + 4.0 * q - 1.5 * q) * rf)
	return _poly(pts)


## P066: the closed outline of a straight rack with n teeth of module m (mm), as lines: a bar 3 m tall whose top is a row of n teeth on the
## root line y = 0. The pitch is pi m (the spur gear's pitch on its pitch circle, so a gear of module m meshes); each tooth is a trapezoid
## m tall with its tip 0.4 of the pitch wide, so the tip sits 1 m above the root and the rack is 4 m tall.
static func rack_outline(n: int, m: float) -> Array:
	var pitch := PI * m
	var pts := [Vector2(0.0, -3.0 * m), Vector2(n * pitch, -3.0 * m), Vector2(n * pitch, 0.0)]
	for k in range(n - 1, -1, -1):
		var x0 := k * pitch
		pts.append(Vector2(x0 + 0.7 * pitch, m))
		pts.append(Vector2(x0 + 0.3 * pitch, m))
		pts.append(Vector2(x0, 0.0))
	return _poly(pts)


## the car body's side-profile numbers (mm, the body's own frame: Y up from the ground, Z forward; the car's wheel radius is p.wheel_r):
## S the sill (the wheel centre's height), A the arch radius (the wheel + ARCH_GAP), yb the belt (55 % of H), yn the nose top, zn / zt the nose
## and tail, zrf / zrr the roof's front and rear edges, zrh the hatch's foot on the belt, zwb the windscreen's foot (30 deg from horizontal)
static func car_geom(p: Dictionary) -> Dictionary:
	var L: float = p["body_length"]
	var W: float = p["body_width"]
	var H: float = p["body_height"]
	var R: float = p.get("wheel_r", 320.0)
	var yb := H * 0.55
	var zrr := -0.375 * L
	return {"L": L, "W": W, "H": H, "S": R, "A": R + ARCH_GAP, "yb": yb, "yn": 0.48 * H, "zn": L * 0.5, "zt": -L * 0.5,
		"zrf": 0.0, "zrr": zrr, "zrh": zrr - 0.075 * L, "zwb": (H - yb) * sqrt(3.0), "wc": W * CAB_W}


## a handle in another material than the Part's: [material, last steel feature], or [] when all of it is one material. The sword's
## pommel and grip (the features after its guard, index 7) are wood; its blade and guard are steel
static func handle_mat(rec: Dictionary) -> Array:
	if String(rec.get("easy", {}).get("t", "")) == "sword":
		return ["wood", 7]
	return []


## the handle's centre in the Part's own frame (m): the grip a hand holds (PartWeapon). A sword's grip is the revolve x -106..-2 mm; an axe's
## haft runs 0..H+10 mm. Other templates, and a Part with no template, hold at its origin.
static func handle_of(rec: Dictionary) -> Vector3:
	var g: Array = rec.get("grip", [])   # p131grippoint: the spot Hold here picked (mm, the Part's own frame) wins over the template's
	if g.size() == 3:
		return Vector3(float(g[0]), float(g[1]), float(g[2])) * MM
	var e: Dictionary = rec.get("easy", {})
	match String(e.get("t", "")):
		"sword":
			return Vector3(-54.0 * MM, 0.0, 0.0)
		"axe":
			return Vector3(0.5 * (float(e["p"]["handle_length"]) + 10.0) * MM, 0.0, 0.0)
	return Vector3.ZERO


## the amber drag dot of a template number: {"at": Vector3 (m), "axis": Vector3 (the way the number grows), "gain": mm of number per mm the dot moves}, or {}
static func dot_of(t: String, k: String, p: Dictionary) -> Dictionary:
	var s := MM
	match t + "." + k:
		"sword.blade_length":
			return {"at": Vector3(float(p["blade_length"]) * s, 0, 0), "axis": Vector3.RIGHT, "gain": 1.0}
		"sword.width":
			return {"at": Vector3(float(p["blade_length"]) * 0.45 * s, float(p["width"]) * 0.5 * s, 0), "axis": Vector3.UP, "gain": 2.0}
		"sword.guard_size":
			return {"at": Vector3(-1.0 * s, float(p["guard_size"]) * 0.5 * s, 0), "axis": Vector3.UP, "gain": 2.0}
		"axe.handle_length":
			return {"at": Vector3((float(p["handle_length"]) + 110.0) * s, 0, 0), "axis": Vector3.RIGHT, "gain": 1.0}
		"axe.head_width":
			return {"at": Vector3((float(p["handle_length"]) + 110.0) * s, float(p["head_width"]) * 0.5 * s, 0), "axis": Vector3.UP, "gain": 2.0}
		"shield.radius":
			return {"at": Vector3(float(p["radius"]) * s, 0, 0), "axis": Vector3.RIGHT, "gain": 1.0}
		"shield.boss":
			return {"at": Vector3(0, float(p["boss"]) * s, (float(p["thickness"]) + float(p["boss"]) * 0.4) * s), "axis": Vector3.UP, "gain": 1.0}
		"crate.width":
			return {"at": Vector3(float(p["width"]) * s, float(p["height"]) * 0.5 * s, 0), "axis": Vector3.RIGHT, "gain": 1.0}
		"crate.height":
			return {"at": Vector3(float(p["width"]) * 0.5 * s, float(p["height"]) * s, 0), "axis": Vector3.UP, "gain": 1.0}
		"chair.seat_height":
			return {"at": Vector3(float(p["seat_width"]) * s, float(p["seat_height"]) * s, float(p["seat_depth"]) * s), "axis": Vector3.UP, "gain": 1.0}
		"chair.back_height":
			return {"at": Vector3(float(p["seat_width"]) * 0.5 * s, (float(p["seat_height"]) + float(p["back_height"])) * s, 0), "axis": Vector3.UP, "gain": 1.0}
	return {}


## P080 WOOD BOARDS: the real sizes of the two Parts > Wood boards chips, mm. 2x4 = 38 x 89 mm (1.5 x 3.5 in) in 8 ft (2438 mm) lengths;
## an MDF sheet is 1220 x 2440 mm and 15 mm thick. The name is the chip's words.
const WOOD_BOARDS := {"2x4": {"name": "2x4 board", "width": 89.0, "thickness": 38.0, "length": 2438.0}, "mdf": {"name": "MDF sheet 15 mm", "width": 1220.0, "thickness": 15.0, "length": 2440.0}}


## P080: one box of wood, its cross-section (width x thickness) on the front sketch, pulled along Z by the length: it lies flat on the floor
static func _board_features(p: Dictionary) -> Array:
	var fs: Array = []
	_ex(fs, _sk(fs, "front", [_rect(Vector2(0, 0), Vector2(p["width"], p["thickness"]))]), "extrude", p["length"], "new")
	return fs
