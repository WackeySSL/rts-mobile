// SimKernels: see sim_kernels.h. MIT licence, like the rest of rts-mobile.
#include "sim_kernels.h"

using namespace godot;

// Defined by native/sim_kernels/SConstruct as plain tokens: the build the library reports about itself.
String SimKernels::build_info() const {
	return String(SIM_KERNELS_PLATFORM " " SIM_KERNELS_TARGET " " SIM_KERNELS_ARCH " " SIM_KERNELS_OPT " " __VERSION__);
}

void SimKernels::_bind_methods() {
	ClassDB::bind_method(D_METHOD("abi_version"), &SimKernels::abi_version);
	ClassDB::bind_method(D_METHOD("phases"), &SimKernels::phases);
	ClassDB::bind_method(D_METHOD("build_info"), &SimKernels::build_info);
}
