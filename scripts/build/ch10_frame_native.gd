extends RefCounted
## The only script that names KineFrameNative (native/src/kine_frame_native.cpp). Ch10Frame load()s it by path only when the class exists.


static func solve(model: Dictionary, job: Dictionary) -> Dictionary:
	return KineFrameNative.solve(model, job)
