#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "kine_sculpt_native.h"
#include "kine_cloth_native.h"
#include "kine_cloth_self_native.h"
#include "kine_meshcheck_native.h"
#include "kine_meshops_native.h"
#include "kine_parkour_native.h"
#include "kine_retopo_native.h"
#include "kine_solve_native.h"
#include "kine_skin_native.h"
#include "kine_clock_native.h"


#include "kine_field_native.h"
#include "kine_fluid_native.h"
#include "kine_frame_native.h"
#include "kine_seat_native.h"
#include "kine_wood_native.h"
#include "kine_fastener_native.h"

using namespace godot;

void kine_native_initialize(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_ABSTRACT_CLASS(KineSculptNative);
	GDREGISTER_ABSTRACT_CLASS(KineClothNative);
	GDREGISTER_CLASS(KineClothSelfNative);
	GDREGISTER_ABSTRACT_CLASS(KineMeshCheckNative);
	GDREGISTER_ABSTRACT_CLASS(KineMeshOpsNative);
	GDREGISTER_ABSTRACT_CLASS(KineParkourNative);
	GDREGISTER_CLASS(KineRetopoNative);
	GDREGISTER_ABSTRACT_CLASS(KineSolveNative);
	GDREGISTER_ABSTRACT_CLASS(KineSkinNative);
	GDREGISTER_ABSTRACT_CLASS(KineClockNative);


	GDREGISTER_ABSTRACT_CLASS(KineFieldNative);
	GDREGISTER_CLASS(KineFluidNative);
	GDREGISTER_ABSTRACT_CLASS(KineFrameNative);
	GDREGISTER_ABSTRACT_CLASS(KineSeatNative);
	GDREGISTER_ABSTRACT_CLASS(KineWoodNative);
	GDREGISTER_ABSTRACT_CLASS(KineFastenerNative);
}

void kine_native_terminate(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT kine_native_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(kine_native_initialize);
	init_obj.register_terminator(kine_native_terminate);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
