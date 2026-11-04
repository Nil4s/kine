#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "kine_cad.h"
#include <OSD_ThreadPool.hxx>
#include <cstdlib>

using namespace godot;

void kine_cad_initialize(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_ABSTRACT_CLASS(KineCAD);
}

void kine_cad_terminate(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	// c77: with KINE_PAR_MESH the OCCT default pool has live workers that keep Godot from exiting on Windows;
	// Init(1) joins and drops them (a pool of 1 = the calling thread only).
	if (std::getenv("KINE_PAR_MESH") != nullptr) {
		OSD_ThreadPool::DefaultPool()->Init(1);
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT kine_cad_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(kine_cad_initialize);
	init_obj.register_terminator(kine_cad_terminate);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
