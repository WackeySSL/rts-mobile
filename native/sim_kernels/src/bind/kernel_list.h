// One line per kernel: X(method, phase id), the id being SimProbe.Phase's (world_access.h names the five).
// SimKernels.phases() is the mask of these lines, so tests/sim/support/sim_impls.gd's EXPECTED_PHASES must
// list the same phases. A port PR adds its line here, its method to sim_kernels.h/.cpp and its
// kernel_<phase>.cpp. P54 has none. The file's existence turns on scripts/ci/check-native-tests.sh's floor.
// MIT.
#pragma once

#define SIM_KERNEL_LIST(X)
