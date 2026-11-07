extends RefCounted
## The only script that names KineBlendNative (native/src/kine_blend_native.cpp). BlendMatrix loads it by path only when the class exists.


static func run(rig: Dictionary, caps: Dictionary, clips: Array, blend_s: float) -> Array:
	return KineBlendNative.matrix(rig, caps, clips, blend_s)
