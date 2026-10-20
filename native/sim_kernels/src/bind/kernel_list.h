// One line per kernel, the only place that names it (ADR 0013 section 2): SimKernels' declaration of
// the method, its binding and its bit in phases() are all generated from these lines, so two port PRs
// touch disjoint files except this one line each (and EXPECTED_PHASES in tests/sim/support/sim_impls.gd).
//   K0(method, phase)            void method(Object *world) const
//   K1(method, phase, argument)  void method(Object *world, int64_t argument) const
// `phase` is world_access.h's PHASE_* of the kernel's SimProbe.Phase; it needs a checked list there.
// A port PR adds its line and defines the method in its kernel_<phase>.cpp: FLOW (P30n) is the first, INTEGRATE (P37n)
// the second, SEPARATION (P39n) the third, TARGETING (P41n) the fourth.
// The file's existence turns on scripts/ci/check-native-tests.sh's floor. MIT.
#pragma once

#define SIM_KERNEL_LIST(K0, K1)                    \
	K1(flow, world_access::PHASE_FLOW, budget)     \
	K0(separation, world_access::PHASE_SEPARATION) \
	K0(integrate, world_access::PHASE_INTEGRATE)   \
	K0(targeting, world_access::PHASE_TARGETING)
