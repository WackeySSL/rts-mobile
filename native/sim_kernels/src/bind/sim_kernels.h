// SimKernels, the one bound class of the native sim kernels (ADR 0013 section 2): stateless apart from
// the StringNames of the checked table, which the constructor makes on the main thread. P53's skeleton
// (exception 7), owned by gameplay-dev from P54 on. MIT.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <cstdint>

#include "world_access.h"

class SimKernels : public godot::RefCounted {
	GDCLASS(SimKernels, godot::RefCounted)

	world_access::WorldAccess access_;

public:
	// Equal to the constant in game/core/NativeKernels.gd (P54r); both change with the boundary.
	static constexpr int64_t ABI_VERSION = 1;

	int64_t abi_version() const { return ABI_VERSION; }
	int64_t phases() const; // One bit per SimProbe.Phase, from kernel_list.h.
	godot::String build_info() const; // Platform, target, arch, optimisation and compiler.
	// 0 if `world` has every name of `phase`'s list with its type and size; else world_access.h's status.
	// Pure: it logs nothing. `phase` is a SimProbe.Phase id; only the five ported phases have a list.
	int64_t check_world(godot::Object *world, int64_t phase) const { return access_.check(world, phase); }
	// The checked table, one line per name: "OWNER name KIND SIZE <phase bits>". The name test reads it.
	godot::PackedStringArray checked_names() const;

protected:
	static void _bind_methods();
};
