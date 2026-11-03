class_name MoveRule
## C25 (complaint 198): ONE Move rule in and out of sketch. The sketch grid (PartUI.snap, snap_mm, Alt = free) and the drag of a piece
## (EasyPartMove) both snap through snap(); a typed distance sets the slide's length. OPT-IN: unified is false by default, and then the
## piece drag keeps its fixed 1 mm grid exactly as before.

static var unified := false


## v (mm) on the grid of step_mm; free (Alt held) or a step <= 0 leaves it alone
static func snap(v: float, step_mm: float, free: bool) -> float:
	if free or step_mm <= 0.0:
		return v
	return snappedf(v, step_mm)


## the in-plane grid of a piece drag, in metres: the sketch's own step when unified, else the old 1 mm (<= 0 = free)
static func grid_m(step_mm: float, free: bool, old := 0.001) -> float:
	if not unified:
		return old
	return 0.0 if (free or step_mm <= 0.0) else step_mm * 0.001


## a slide vector (m) made exactly typed_mm long, same direction; unchanged when nothing is typed or it has no direction
static func typed_slide(slide: Vector3, typed_mm: float) -> Vector3:
	if typed_mm <= 0.0 or slide.length() < 1e-9:
		return slide
	return slide.normalized() * typed_mm * 0.001
