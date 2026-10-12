// P26n spike: a plain C++ port of game/ui/PerfProbeTick.gd (the P26s mock tick), never merged.
// MIT licence, like the rest of rts-mobile.
#pragma once

#include <cstdint>
#include <vector>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

// Same public surface as PerfProbeTick: the properties tick, x, y, target, seen, dirty,
// dirty_count, flow_cost and slice_cells, and step() and flow_slice(budget), which return their
// wall time in microseconds.
//
// Threading: step() and flow_slice() run on the probe's worker thread and touch only this
// object's own members: no allocation, and no Godot API apart from the one
// OS.get_thread_caller_id() call each makes before its timer starts. The Packed-array
// properties return copies and must be read by the main thread only between jobs, while the
// worker is asleep (the perf probe's mode 4 does the same with PerfProbeTick). Setters are for
// the main thread between jobs as well.
class ProbeTickNative : public RefCounted {
	GDCLASS(ProbeTickNative, RefCounted)

public:
	static constexpr int64_t UNITS = 150;
	static constexpr int64_t SIDE = UNITS / 2; // Rows 0-74 are player 0's, 75-149 player 1's.
	static constexpr int64_t COLS = 64;
	static constexpr int64_t PAD = 66; // The flow grid carries a blocked ring.
	static constexpr int64_t UNREACHED = 0x3FFFFFFF;

	ProbeTickNative();

	int64_t step();
	int64_t flow_slice(int64_t p_budget);

	int64_t get_tick() const { return tick_; }
	void set_tick(int64_t p_value) { tick_ = p_value; }
	int64_t get_dirty_count() const { return dirty_count_; }
	void set_dirty_count(int64_t p_value) { dirty_count_ = p_value; }
	int64_t get_slice_cells() const { return slice_cells_; }
	void set_slice_cells(int64_t p_value) { slice_cells_ = p_value; }

	PackedInt32Array get_x() const { return to_packed(x_); }
	void set_x(const PackedInt32Array &p_value) { assign(x_, p_value, "x"); }
	PackedInt32Array get_y() const { return to_packed(y_); }
	void set_y(const PackedInt32Array &p_value) { assign(y_, p_value, "y"); }
	PackedInt32Array get_target() const { return to_packed(target_); }
	void set_target(const PackedInt32Array &p_value) { assign(target_, p_value, "target"); }
	PackedInt32Array get_seen() const { return to_packed(seen_); }
	void set_seen(const PackedInt32Array &p_value) { assign(seen_, p_value, "seen"); }
	PackedInt32Array get_dirty() const { return to_packed(dirty_); }
	void set_dirty(const PackedInt32Array &p_value) { assign(dirty_, p_value, "dirty"); }
	PackedInt32Array get_flow_cost() const { return to_packed(flow_cost_); }
	void set_flow_cost(const PackedInt32Array &p_value) { assign(flow_cost_, p_value, "flow_cost"); }

	// Id (OS.get_thread_caller_id()) of the thread that ran the last step() / flow_slice().
	int64_t get_last_step_thread() const { return last_step_thread_; }
	int64_t get_last_slice_thread() const { return last_slice_thread_; }

	// Platform, target and -O level this library was built with, for the probe's report.
	String get_build_info() const;

protected:
	static void _bind_methods();

private:
	static PackedInt32Array to_packed(const std::vector<int32_t> &p_values);
	static void assign(std::vector<int32_t> &r_to, const PackedInt32Array &p_from, const char *p_name);

	int64_t next(int64_t p_n);
	void new_goal(int64_t p_i);
	void rebuild(std::vector<int32_t> &r_head, std::vector<int32_t> &r_link, int64_t p_size, int64_t p_cols);
	void move_units();
	void acquire();
	void tile_events();
	void stamp(int64_t p_player, int64_t p_cell, int64_t p_delta);

	// GDScript ints are int64; the Packed arrays are int32 and store (truncate) exactly as there.
	int64_t tick_ = 0;
	int64_t dirty_count_ = 0;
	int64_t slice_cells_ = 0;
	std::vector<int32_t> x_;
	std::vector<int32_t> y_;
	std::vector<int32_t> target_; // Nearest enemy row, -1 = none.
	std::vector<int32_t> seen_; // Sight squares on a cell, per player.
	std::vector<int32_t> dirty_; // Player 0 cells that flipped 0 <-> 1.
	std::vector<int32_t> flow_cost_;

	std::vector<int32_t> goal_x_;
	std::vector<int32_t> goal_y_;
	std::vector<int32_t> stamped_; // Tile of the last fog stamp.
	std::vector<int32_t> sep_head_;
	std::vector<int32_t> sep_next_;
	std::vector<int32_t> tgt_head_; // 4-tile cells.
	std::vector<int32_t> tgt_next_;
	std::vector<int32_t> terrain_; // Move cost per padded cell, 0 = blocked.
	std::vector<int32_t> bucket_; // 16 Dial buckets, one stack each.
	std::vector<int32_t> bucket_n_;
	int64_t dist_ = 0;
	int64_t pending_ = 0;
	int64_t lcg_ = 42;

	// Keeps the flow lookup of tile_events() alive: GDScript cannot drop an unused result, and the
	// real tick uses it, so the port must not let the compiler delete the eight loads.
	int64_t flow_lookup_sink_ = 0;
	int64_t last_step_thread_ = 0;
	int64_t last_slice_thread_ = 0;
};

} // namespace godot
