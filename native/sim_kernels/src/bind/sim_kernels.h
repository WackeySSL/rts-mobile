// SimKernels, the one bound class of the native sim kernels (ADR 0013 section 2). P53's skeleton
// (exception 7): no kernel yet; gameplay-dev owns it from P54. MIT.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <cstdint>

class SimKernels : public godot::RefCounted {
	GDCLASS(SimKernels, godot::RefCounted)

public:
	// Equal to the constant in game/core/NativeKernels.gd (P54r); both change with the boundary.
	static constexpr int64_t ABI_VERSION = 1;

	int64_t abi_version() const { return ABI_VERSION; }
	int64_t phases() const { return 0; } // One bit per SimProbe.Phase (kernel_list.h, P54).
	godot::String build_info() const; // Platform, target, arch, optimisation and compiler.

protected:
	static void _bind_methods();
};
