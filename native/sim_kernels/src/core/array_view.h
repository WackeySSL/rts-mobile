// A window over one of the World's arrays, for core/ (ADR 0013 section 2): the per-array piece of the contract's
// WorldView, with flow::Slot as the aggregate. The raw pointer is private, so core/ reaches an element only through
// get() and set(): an element is widened to int64_t on the way out and narrowed with an explicit cast on the way in
// (section 4), and the compiler enforces that, whatever the element type. An index outside the window reads 0 and
// writes nothing, so the contents of a queue that check_world cannot vouch for never reach memory outside the
// array. Only bind/world_access.h builds a view from a pointer. MIT.
// Test: tests/sim/native/test_flow_lockstep.gd.
#pragma once

#include <cstdint>

template <typename T>
class ArrayView {
public:
	ArrayView() = default;
	ArrayView(T *data, int64_t count) :
			ptr_(data), size_(count) {}

	int64_t size() const {
		return size_;
	}
	int64_t get(int64_t index) const {
		return index >= 0 && index < size_ ? ptr_[index] : 0;
	}
	void set(int64_t index, int64_t value) {
		if (index >= 0 && index < size_) {
			ptr_[index] = static_cast<T>(value);
		}
	}
	void fill(int64_t value) {
		for (int64_t index = 0; index < size_; index++) {
			ptr_[index] = static_cast<T>(value);
		}
	}

private:
	T *ptr_ = nullptr;
	int64_t size_ = 0;
};
