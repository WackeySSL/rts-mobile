// Views over the harness's own std::vector buffers, for the case files (ADR 0013 section 10): ArrayView needs a pointer
// and a count, and AddressSanitizer sees every buffer at its exact size. Plain C++17, no Godot header. MIT.
#pragma once

#include <cstdint>
#include <vector>

#include "array_view.h"

template <typename T>
ArrayView<T> view(std::vector<T> &values) {
	return ArrayView<T>(values.data(), static_cast<int64_t>(values.size()));
}
template <typename T>
ArrayView<const T> cview(const std::vector<T> &values) {
	return ArrayView<const T>(values.data(), static_cast<int64_t>(values.size()));
}
