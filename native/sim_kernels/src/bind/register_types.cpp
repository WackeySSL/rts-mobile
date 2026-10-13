// Registration of the native sim kernels. P53's skeleton (exception 7); gameplay-dev owns it from P54. MIT.
#include <gdextension_interface.h>

#include <godot_cpp/godot.hpp>

#include "sim_kernels.h"

using namespace godot;

static void initialize_sim_kernels_module(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		GDREGISTER_CLASS(SimKernels);
	}
}

static void uninitialize_sim_kernels_module(ModuleInitializationLevel) {}

extern "C" {
GDExtensionBool GDE_EXPORT sim_kernels_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_sim_kernels_module);
	init_obj.register_terminator(uninitialize_sim_kernels_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
