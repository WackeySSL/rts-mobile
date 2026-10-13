// A window over one of the World's arrays, for core/ (ADR 0013 section 2). The raw pointer lives here and
// nowhere else: an element is widened to int64_t on the way out and narrowed with an explicit cast on the way
// in (section 4). An index outside the window reads 0 and writes nothing, so the contents of a queue that
// check_world cannot vouch for never reach memory outside the array. MIT.
// Test: tests/sim/native/test_flow_lockstep.gd.
#pragma once

#include <cstdint>

template <typename T>
struct ArrayView {
	T *ptr = nullptr;
	int64_t size = 0;

	int64_t get(int64_t index) const {
		return index >= 0 && index < size ? ptr[index] : 0;
	}
	void set(int64_t index, int64_t value) {
		if (index >= 0 && index < size) {
			ptr[index] = static_cast<T>(value);
		}
	}
	void fill(int64_t value) {
		for (int64_t index = 0; index < size; index++) {
			ptr[index] = static_cast<T>(value);
		}
	}
};
