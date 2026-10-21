// What a kernel's case file hands the harness (ADR 0013 section 10). Plain C++17, no Godot header. MIT.
//
// A later kernel (P42n FIRE and PROJECTILES; FLOW, SEPARATION, INTEGRATE, TARGETING and FOG have theirs) adds one file here, say
// fire_cases.cpp, with its two functions below and one KernelCases constant, plus the `extern` line of that
// constant at the end of this file, one pointer in KERNELS (main.cpp) and the records it reads in
// tests/sim/native/sanitizer/dump_states.gd. Nothing else changes: the dump reader, the driver and the build script
// (which compiles every *.cpp of this folder) stay as they are.
#pragma once

#include <cstdint>
#include <stdexcept>

#include "dump.h"

// What a case file counts, so that the harness can tell a clean run from a run that did nothing.
struct Tally {
	int64_t runs = 0; // calls of the core/ functions that the kernel's bind layer makes
	int64_t work = 0; // what they did, in the kernel's unit (FLOW: cells settled; SEPARATION: units looked at; INTEGRATE: rows changed; TARGETING: units looked at and lines tested; FOG: cells covered)
};

// A result that is wrong for a reason a sanitizer cannot see (a run that never finished, a case that did nothing):
// the harness exits 1. A sanitizer report aborts the process with its own exit code before this is thrown.
struct Finding : std::runtime_error {
	using std::runtime_error::runtime_error;
};

struct KernelCases {
	const char *name;
	// The kernel's core/ functions over the state of one dump, with the inputs the bind layer would pass.
	void (*on_dump)(const Dump &dump, Tally &tally);
	// The crafted cases: states no match is sure to reach.
	void (*crafted)(Tally &tally);
};

extern const KernelCases FLOW_CASES;
extern const KernelCases SEPARATION_CASES;
extern const KernelCases INTEGRATE_CASES;
extern const KernelCases TARGETING_CASES;
extern const KernelCases FOG_CASES;
