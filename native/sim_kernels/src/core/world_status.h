// What a check of the World found (ADR 0013 section 2): plain C++17, no Godot header. MIT.
// Tests: tests/sim/native/test_kernel_abi.gd, which pins these numbers as literals.
#pragma once

#include <cstdint>

// What is wrong with one checked name.
enum Fault : int64_t {
	FAULT_NONE,
	FAULT_PHASE, // not one of the ported phases
	FAULT_OWNER, // the object that holds the name is missing
	FAULT_TYPE, // the member has another type
	FAULT_SIZE, // the array has another length
	FAULT_COUNT,
};

// 0 is ok; otherwise the table index of the first bad name, times FAULT_COUNT, plus the fault.
constexpr int64_t status_of(int64_t index, int64_t fault) {
	return fault == FAULT_NONE ? 0 : index * FAULT_COUNT + fault;
}
