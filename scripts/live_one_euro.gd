## ONE EURO FILTER (Casiez, Roussel & Vogel, CHI 2012) for one coordinate of the live webcam puppet (scripts/live_puppet.gd).
## A low cutoff while the value is still (the tracker's jitter goes), and a cutoff that rises with its speed (a fast move
## is not smeared). Its own file and class name, so the other filters in the app do not clash with it.
class_name LiveOneEuro
extends RefCounted

var mincut: float   # Hz: the cutoff while still
var beta: float     # Hz per unit/s of speed: how fast the cutoff rises with a move
var dcut: float     # Hz: the smoothing of the speed estimate itself
var _x := 0.0
var _dx := 0.0
var _on := false


func _init(m: float, b: float, d: float) -> void:
	mincut = m
	beta = b
	dcut = d


static func _alpha(cut: float, dt: float) -> float:
	return 1.0 / (1.0 + (1.0 / (TAU * cut)) / dt)


## the value at this sample (dt: seconds since the last one)
func step(x: float, dt: float) -> float:
	if not _on:
		_on = true
		_x = x
		_dx = 0.0
		return x
	dt = maxf(dt, 0.001)
	var ad := _alpha(dcut, dt)
	_dx = ad * ((x - _x) / dt) + (1.0 - ad) * _dx
	var a := _alpha(mincut + beta * absf(_dx), dt)
	_x = a * x + (1.0 - a) * _x
	return _x
