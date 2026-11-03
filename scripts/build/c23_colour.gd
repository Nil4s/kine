## C23 (complaints #21, #38): colour in a 3D-print export. An STL holds no colour; a 3MF keeps each body's painted colour. This picks the format for the
## part: more than one distinct painted colour -> 3MF, and says why in one plain sentence. Opt-in: the dialog's third print format "Best for my part"
## (run "auto"); the STL and 3MF formats it already had are untouched.
class_name C23Colour
extends RefCounted


## the distinct painted colours (as #RRGGBB) of the bodies, in order of first use
static func colours_of(bodies: Array) -> Array:
	var out := []
	for b in bodies:
		if (b as Dictionary).get("color") != null:
			var h := MeshExport._hex(b["color"])
			if not out.has(h):
				out.append(h)
	return out


## {"fmt": "stl" | "3mf", "why": plain words, "colours": n}. wanted = what the maker asked for ("auto" lets the part decide)
static func pick_bodies(bodies: Array, wanted := "auto") -> Dictionary:
	var cs := colours_of(bodies)
	var n := cs.size()
	if wanted == "stl" or wanted == "3mf":
		return {"fmt": wanted, "why": "", "colours": n}
	if n > 1:
		return {"fmt": "3mf", "why": "3MF chosen: this part has %d colours and an STL holds none; the 3MF keeps each piece's colour" % n, "colours": n}
	if n == 1:
		return {"fmt": "3mf", "why": "3MF chosen: this part is painted and an STL would lose the colour", "colours": n}
	if bodies.size() > 1:
		return {"fmt": "3mf", "why": "3MF chosen: it is unpainted but has %d separate pieces, and the 3MF keeps each as its own object" % bodies.size(), "colours": 0}
	return {"fmt": "stl", "why": "STL chosen: one unpainted piece, so the plain shape is all there is to keep", "colours": 0}


static func pick(rec: Dictionary, quality := {}, wanted := "auto") -> Dictionary:
	var bo := MeshExport.bodies_of(rec, quality)
	return pick_bodies(bo["bodies"], wanted)


## the dialog's checklist line for the format on screen; "" when the part has fewer than two colours (nothing new to say)
static func dialog_line(rec: Dictionary, run: String, quality := {}) -> String:
	if rec.is_empty() or not Part.available():
		return ""
	var n := colours_of(MeshExport.bodies_of(rec, quality)["bodies"]).size()
	if n < 2:
		return ""
	if run == "stl":
		return "WARN  this part has %d colours and an STL holds none: pick 3MF (or Best for my part) to keep them" % n
	return "OK    %d colours: the 3MF keeps each piece's colour" % n
