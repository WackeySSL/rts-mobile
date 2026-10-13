// SimKernels: see sim_kernels.h. MIT licence, like the rest of rts-mobile.
#include "sim_kernels.h"

using namespace godot;

// Compiler family and plain version: __VERSION__ names no family under g++ and is long under clang.
#define SIM_KERNELS_STR_(x) #x
#define SIM_KERNELS_STR(x) SIM_KERNELS_STR_(x)
#if defined(__clang__) // asked first: clang defines __GNUC__ too
#define SIM_KERNELS_COMPILER "clang " SIM_KERNELS_STR(__clang_major__) "." SIM_KERNELS_STR(__clang_minor__) "." SIM_KERNELS_STR(__clang_patchlevel__)
#else
#define SIM_KERNELS_COMPILER "g++ " SIM_KERNELS_STR(__GNUC__) "." SIM_KERNELS_STR(__GNUC_MINOR__) "." SIM_KERNELS_STR(__GNUC_PATCHLEVEL__)
#endif

// SIM_KERNELS_PLATFORM, _TARGET, _ARCH and _OPT: plain tokens from native/sim_kernels/SConstruct.
String SimKernels::build_info() const {
	return String(SIM_KERNELS_PLATFORM " " SIM_KERNELS_TARGET " " SIM_KERNELS_ARCH " " SIM_KERNELS_OPT " " SIM_KERNELS_COMPILER);
}

void SimKernels::_bind_methods() {
	ClassDB::bind_method(D_METHOD("abi_version"), &SimKernels::abi_version);
	ClassDB::bind_method(D_METHOD("phases"), &SimKernels::phases);
	ClassDB::bind_method(D_METHOD("build_info"), &SimKernels::build_info);
}
