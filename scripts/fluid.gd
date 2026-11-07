class_name Fluid
extends RefCounted
## CH8: the liquid solver factory. The C++ KineFluidNative when the DLL has it, else the GDScript twin FluidSim (small grids only).


static func native() -> bool:
	return NativeExt.ensure("kine_native", "KineFluidNative")


static func make(force_gd := false) -> Object:
	if not force_gd and native():
		return ClassDB.instantiate("KineFluidNative")
	return FluidSim.new()
