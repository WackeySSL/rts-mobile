// SimKernels: see sim_kernels.h. MIT licence, like the rest of rts-mobile.
#include "sim_kernels.h"

#include <godot_cpp/variant/packed_string_array.hpp>

#include "kernel_list.h"

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

int64_t SimKernels::phases() const {
	int64_t mask = 0;
#define SIM_KERNEL_BIT(method, phase) mask |= int64_t(1) << (phase);
	SIM_KERNEL_LIST(SIM_KERNEL_BIT)
#undef SIM_KERNEL_BIT
	return mask;
}

PackedStringArray SimKernels::checked_names() const {
	PackedStringArray lines;
	for (const world_access::Entry &entry : world_access::TABLE) {
		lines.append(String(entry.text) + " " + String::num_int64(entry.phases));
	}
	return lines;
}

void SimKernels::_bind_methods() {
	ClassDB::bind_method(D_METHOD("abi_version"), &SimKernels::abi_version);
	ClassDB::bind_method(D_METHOD("phases"), &SimKernels::phases);
	ClassDB::bind_method(D_METHOD("build_info"), &SimKernels::build_info);
	ClassDB::bind_method(D_METHOD("check_world", "world", "phase"), &SimKernels::check_world);
	ClassDB::bind_method(D_METHOD("checked_names"), &SimKernels::checked_names);
}
