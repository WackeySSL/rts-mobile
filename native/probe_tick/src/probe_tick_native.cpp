// P26n spike: a plain C++ port of game/ui/PerfProbeTick.gd, function for function. Read the two
// side by side: every statement has its GDScript twin in the same order, so the results are
// bit-identical (tests/perf/test_probe_tick_native.gd compares them tick by tick).
//
// What the port keeps from GDScript, on purpose:
// - ints are int64_t; the state arrays are int32_t, so a store truncates exactly where the
//   PackedInt32Array store does;
// - division truncates toward zero and % takes the sign of the dividend, in both languages;
// - the evaluation order of the LCG draws is spelled out (C++ leaves operand order open);
// - no floats anywhere, and nothing but the ported code inside the timed part of step() and
//   flow_slice(): no allocation and no Godot call. Each of the two makes one
//   OS.get_thread_caller_id() call per job, before its timer starts, for the thread tests.

#include "probe_tick_native.h"

#include <algorithm>
#include <chrono>
#include <cstring>

#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

#ifndef PROBE_TICK_PLATFORM
#define PROBE_TICK_PLATFORM "unknown"
#define PROBE_TICK_TARGET "unknown"
#define PROBE_TICK_ARCH "unknown"
#define PROBE_TICK_OPT "unknown"
#endif

using namespace godot;

namespace {

constexpr int64_t UNITS = ProbeTickNative::UNITS;
constexpr int64_t SIDE = ProbeTickNative::SIDE;
constexpr int64_t COLS = ProbeTickNative::COLS;
constexpr int64_t PAD = ProbeTickNative::PAD;
constexpr int64_t UNREACHED = ProbeTickNative::UNREACHED;

// Flow neighbours and their costs (per 10 of terrain cost, x14 / 10 on a diagonal).
constexpr int64_t STEPS[8] = { -67, -66, -65, -1, 1, 65, 66, 67 };
constexpr int64_t COSTS[8] = { 14, 10, 14, 10, 10, 14, 10, 14 };
// The two orthogonal cells a diagonal step passes between; both are the cell itself for an
// orthogonal step, so every step runs the same corner check.
constexpr int64_t SIDE_X[8] = { -1, 0, 1, 0, 0, -1, 0, 1 };
constexpr int64_t SIDE_Y[8] = { -66, 0, -66, 0, 0, 66, 0, 66 };

inline int64_t maxi(int64_t a, int64_t b) { return a > b ? a : b; }
inline int64_t mini(int64_t a, int64_t b) { return a < b ? a : b; }
inline int64_t clampi(int64_t v, int64_t lo, int64_t hi) { return v < lo ? lo : (v > hi ? hi : v); }

// game/sim/FixedMath.gd isqrt: the floor of the square root of n, digit by digit.
int64_t isqrt(int64_t n) {
	if (n <= 0) {
		return 0;
	}
	int64_t rest = n;
	int64_t root = 0;
	int64_t bit = int64_t(1) << 62;
	while (bit > rest) {
		bit >>= 2;
	}
	while (bit != 0) {
		if (rest >= root + bit) {
			rest -= root + bit;
			root = (root >> 1) + bit;
		} else {
			root >>= 1;
		}
		bit >>= 2;
	}
	return root;
}

inline int64_t now_usec() {
	using namespace std::chrono;
	return duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
}

} // namespace

ProbeTickNative::ProbeTickNative() {
	// The var initialisers of PerfProbeTick.gd, in the same sizes and fill values.
	x_.assign(UNITS, 0);
	y_.assign(UNITS, 0);
	target_.assign(UNITS, -1);
	seen_.assign(2 * COLS * COLS, 0);
	dirty_.assign(COLS * COLS, 0);
	flow_cost_.assign(PAD * PAD, int32_t(UNREACHED));
	goal_x_.assign(UNITS, 0);
	goal_y_.assign(UNITS, 0);
	stamped_.assign(UNITS, -1);
	sep_head_.assign(COLS * COLS, -1);
	sep_next_.assign(UNITS, -1);
	tgt_head_.assign(16 * 16, -1);
	tgt_next_.assign(UNITS, -1);
	terrain_.assign(PAD * PAD, 0);
	bucket_.assign(16 * PAD * PAD, 0);
	bucket_n_.assign(16, 0);

	// PerfProbeTick._init().
	for (int64_t ty = 0; ty < COLS; ty++) { // A ridge at columns 31-32 with three gaps inside rows 25-39.
		for (int64_t tx = 0; tx < COLS; tx++) {
			bool gap = ty >= 25 && ty <= 39 && (ty - 25) % 5 < 2;
			terrain_[(ty + 1) * PAD + tx + 1] = ((tx == 31 || tx == 32) && !gap) ? 0 : 10;
		}
	}
	for (int64_t i = 0; i < UNITS; i++) {
		int64_t draw_x = next(12000);
		x_[i] = int32_t(19000 + (i / SIDE) * 14000 + draw_x);
		int64_t draw_y = next(15000);
		y_[i] = int32_t(24500 + draw_y);
		new_goal(i);
	}
	for (int warm = 0; warm < 3; warm++) { // Both players get their first stamp.
		step();
	}
}

// Plays one tick and returns its wall time in microseconds.
int64_t ProbeTickNative::step() {
	last_step_thread_ = OS::get_singleton()->get_thread_caller_id(); // Before the timer starts.
	int64_t started = now_usec();
	tick_ += 1;
	rebuild(sep_head_, sep_next_, 1000, COLS);
	rebuild(tgt_head_, tgt_next_, 4000, 16);
	move_units();
	acquire();
	tile_events();
	return now_usec() - started;
}

// Settles up to `budget` flow cells and returns the wall time in microseconds. A finished field is
// replaced by the next goal at the start of the following call.
int64_t ProbeTickNative::flow_slice(int64_t p_budget) {
	last_slice_thread_ = OS::get_singleton()->get_thread_caller_id(); // Before the timer starts.
	int64_t started = now_usec();
	int32_t *cost = flow_cost_.data();
	const int32_t *terrain = terrain_.data();
	int32_t *count = bucket_n_.data();
	int32_t *bucket = bucket_.data();
	if (pending_ == 0) {
		int64_t row = next(COLS); // GDScript draws the row first, then the column.
		int64_t col = next(30);
		int64_t goal = (1 + row) * PAD + 1 + col;
		std::fill(flow_cost_.begin(), flow_cost_.end(), int32_t(UNREACHED));
		std::fill(bucket_n_.begin(), bucket_n_.end(), 0);
		cost[goal] = 0;
		bucket[0] = int32_t(goal);
		count[0] = 1;
		dist_ = 0;
		pending_ = 1;
	}
	int64_t settled = 0;
	while (settled < p_budget && pending_ > 0) {
		int64_t ring = dist_ % 16;
		if (count[ring] == 0) {
			dist_ += 1;
			continue;
		}
		count[ring] -= 1;
		int64_t cell = bucket[ring * PAD * PAD + count[ring]];
		pending_ -= 1;
		if (cost[cell] != dist_) {
			continue; // Stale: a shorter way came after this entry.
		}
		settled += 1;
		for (int k = 0; k < 8; k++) {
			int64_t nxt = cell + STEPS[k];
			int64_t enter = terrain[nxt]; // Cost of the cell stepped onto.
			if (enter == 0 || terrain[cell + SIDE_X[k]] == 0 || terrain[cell + SIDE_Y[k]] == 0) {
				continue; // Blocked, or a diagonal that would cut a corner.
			}
			int64_t next_cost = dist_ + enter * COSTS[k] / 10;
			if (next_cost < cost[nxt]) {
				int64_t next_ring = next_cost % 16;
				cost[nxt] = int32_t(next_cost);
				bucket[next_ring * PAD * PAD + count[next_ring]] = int32_t(nxt);
				count[next_ring] += 1;
				pending_ += 1;
			}
		}
	}
	slice_cells_ = settled;
	return now_usec() - started;
}

int64_t ProbeTickNative::next(int64_t p_n) {
	lcg_ = (lcg_ * 1103515245 + 12345) & 0x7FFFFFFF;
	return (lcg_ >> 8) % p_n;
}

// The other half of the arena, so the armies keep crossing and crowding in the middle.
void ProbeTickNative::new_goal(int64_t p_i) {
	int64_t draw_x = next(10000);
	goal_x_[p_i] = int32_t((x_[p_i] < 32000 ? 34000 : 20000) + draw_x);
	int64_t draw_y = next(14000);
	goal_y_[p_i] = int32_t(25000 + draw_y);
}

// Resets the grid, then inserts the rows in descending order (cells list ascending rows).
void ProbeTickNative::rebuild(std::vector<int32_t> &r_head, std::vector<int32_t> &r_link, int64_t p_size, int64_t p_cols) {
	int32_t *head = r_head.data();
	int32_t *link = r_link.data();
	const int32_t *px = x_.data();
	const int32_t *py = y_.data();
	std::fill(r_head.begin(), r_head.end(), -1);
	for (int64_t i = UNITS - 1; i >= 0; i--) {
		int64_t cell = (py[i] / p_size) * p_cols + px[i] / p_size;
		link[i] = head[cell];
		head[cell] = int32_t(i);
	}
}

// Sqrt-free pair pushes over the 3x3 cells (16 looked at, 8 used), one isqrt step to the goal.
void ProbeTickNative::move_units() {
	int32_t *px = x_.data();
	int32_t *py = y_.data();
	const int32_t *sep_head = sep_head_.data();
	const int32_t *sep_next = sep_next_.data();
	const int32_t *goal_x = goal_x_.data();
	const int32_t *goal_y = goal_y_.data();
	const int64_t square = 800 * 800;
	for (int64_t i = 0; i < UNITS; i++) {
		int64_t push_x = 0;
		int64_t push_y = 0;
		int64_t looked = 0;
		int64_t hits = 0;
		int64_t gy_end = mini(py[i] / 1000 + 2, COLS);
		for (int64_t gy = maxi(py[i] / 1000 - 1, 0); gy < gy_end; gy++) {
			int64_t gx_end = mini(px[i] / 1000 + 2, COLS);
			for (int64_t gx = maxi(px[i] / 1000 - 1, 0); gx < gx_end; gx++) {
				int64_t j = sep_head[gy * COLS + gx];
				while (j != -1 && looked < 16 && hits < 8) {
					int64_t dx = px[i] - px[j];
					int64_t dy = py[i] - py[j];
					int64_t d2 = dx * dx + dy * dy;
					if (j != i) {
						looked += 1;
						if (d2 < square) {
							hits += 1;
							push_x += dx * (square - d2) / (2 * square);
							push_y += dy * (square - d2) / (2 * square);
						}
					}
					j = sep_next[j];
				}
			}
		}
		int64_t to_x = goal_x[i] - px[i];
		int64_t to_y = goal_y[i] - py[i];
		int64_t to_d2 = to_x * to_x + to_y * to_y;
		if (to_d2 > 120 * 120) {
			int64_t d = isqrt(to_d2);
			px[i] = int32_t(px[i] + to_x * 120 / d);
			py[i] = int32_t(py[i] + to_y * 120 / d);
		} else {
			px[i] = goal_x[i];
			py[i] = goal_y[i];
			new_goal(i);
		}
		px[i] = int32_t(clampi(px[i] + clampi(push_x, -60, 60), 0, COLS * 1000 - 1));
		py[i] = int32_t(clampi(py[i] + clampi(push_y, -60, 60), 0, COLS * 1000 - 1));
	}
}

// A fifth of the units scan the 5x5 targeting cells around them for the nearest enemy.
void ProbeTickNative::acquire() {
	const int32_t *px = x_.data();
	const int32_t *py = y_.data();
	const int32_t *tgt_head = tgt_head_.data();
	const int32_t *tgt_next = tgt_next_.data();
	int32_t *target = target_.data();
	for (int64_t i = tick_ % 5; i < UNITS; i += 5) {
		int64_t best = -1;
		int64_t best_d2 = 5500 * 5500;
		int64_t gy_end = mini(py[i] / 4000 + 3, 16);
		for (int64_t gy = maxi(py[i] / 4000 - 2, 0); gy < gy_end; gy++) {
			int64_t gx_end = mini(px[i] / 4000 + 3, 16);
			for (int64_t gx = maxi(px[i] / 4000 - 2, 0); gx < gx_end; gx++) {
				int64_t j = tgt_head[gy * 16 + gx];
				while (j != -1) {
					int64_t dx = px[i] - px[j];
					int64_t dy = py[i] - py[j];
					if (j / SIDE != i / SIDE && dx * dx + dy * dy < best_d2) {
						best = j;
						best_d2 = dx * dx + dy * dy;
					}
					j = tgt_next[j];
				}
			}
		}
		target[i] = int32_t(best);
	}
}

// Player 0 on ticks 0 and player 1 on ticks 1 of every 3: units that changed tile look up their
// lowest-cost flow neighbour and move their fog stamp.
void ProbeTickNative::tile_events() {
	int64_t player = tick_ % 3;
	if (player > 1) {
		return;
	}
	const int32_t *px = x_.data();
	const int32_t *py = y_.data();
	const int32_t *flow = flow_cost_.data();
	int32_t *stamped = stamped_.data();
	for (int64_t i = player * SIDE; i < (player + 1) * SIDE; i++) {
		int64_t cell = (py[i] / 1000) * COLS + px[i] / 1000;
		if (cell == stamped[i]) {
			continue;
		}
		int64_t at = cell + PAD + 1 + 2 * (py[i] / 1000); // The same tile in the padded flow grid.
		int64_t best = flow[at];
		for (int k = 0; k < 8; k++) {
			best = mini(best, flow[at + STEPS[k]]);
		}
		flow_lookup_sink_ = best;
		stamp(player, stamped[i], -1);
		stamp(player, cell, 1);
		stamped[i] = int32_t(cell);
	}
}

// Adds `delta` to the sight counts of the 13x13 square around `cell`, clipped to the map.
void ProbeTickNative::stamp(int64_t p_player, int64_t p_cell, int64_t p_delta) {
	if (p_cell < 0) {
		return;
	}
	int32_t *counts = seen_.data();
	int32_t *dirty = dirty_.data();
	int64_t row_end = mini(p_cell / COLS + 7, COLS);
	for (int64_t row = maxi(p_cell / COLS - 6, 0); row < row_end; row++) {
		int64_t col_end = mini(p_cell % COLS + 7, COLS);
		for (int64_t col = maxi(p_cell % COLS - 6, 0); col < col_end; col++) {
			int64_t at = p_player * COLS * COLS + row * COLS + col;
			counts[at] = int32_t(counts[at] + p_delta);
			if ((counts[at] == 0 || counts[at] == p_delta) && p_player == 0 && dirty_count_ < 4096) {
				dirty[dirty_count_] = int32_t(row * COLS + col);
				dirty_count_ += 1;
			}
		}
	}
}

PackedInt32Array ProbeTickNative::to_packed(const std::vector<int32_t> &p_values) {
	PackedInt32Array out;
	out.resize(int64_t(p_values.size()));
	std::memcpy(out.ptrw(), p_values.data(), p_values.size() * sizeof(int32_t));
	return out;
}

void ProbeTickNative::assign(std::vector<int32_t> &r_to, const PackedInt32Array &p_from, const char *p_name) {
	ERR_FAIL_COND_MSG(p_from.size() != int64_t(r_to.size()), String("ProbeTickNative: ") + p_name + " needs exactly " + String::num_int64(int64_t(r_to.size())) + " entries");
	std::memcpy(r_to.data(), p_from.ptr(), r_to.size() * sizeof(int32_t));
}

String ProbeTickNative::get_build_info() const {
	return String(PROBE_TICK_PLATFORM " " PROBE_TICK_TARGET " " PROBE_TICK_ARCH " " PROBE_TICK_OPT);
}

void ProbeTickNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("step"), &ProbeTickNative::step);
	ClassDB::bind_method(D_METHOD("flow_slice", "budget"), &ProbeTickNative::flow_slice);
	ClassDB::bind_method(D_METHOD("get_build_info"), &ProbeTickNative::get_build_info);

#define BIND_PROPERTY(m_type, m_name) \
	ClassDB::bind_method(D_METHOD("get_" #m_name), &ProbeTickNative::get_##m_name); \
	ClassDB::bind_method(D_METHOD("set_" #m_name, "value"), &ProbeTickNative::set_##m_name); \
	ADD_PROPERTY(PropertyInfo(m_type, #m_name), "set_" #m_name, "get_" #m_name)

	BIND_PROPERTY(Variant::INT, tick);
	BIND_PROPERTY(Variant::PACKED_INT32_ARRAY, x);
	BIND_PROPERTY(Variant::PACKED_INT32_ARRAY, y);
	BIND_PROPERTY(Variant::PACKED_INT32_ARRAY, target);
	BIND_PROPERTY(Variant::PACKED_INT32_ARRAY, seen);
	BIND_PROPERTY(Variant::PACKED_INT32_ARRAY, dirty);
	BIND_PROPERTY(Variant::INT, dirty_count);
	BIND_PROPERTY(Variant::PACKED_INT32_ARRAY, flow_cost);
	BIND_PROPERTY(Variant::INT, slice_cells);
#undef BIND_PROPERTY

	// The thread ids (OS.get_thread_caller_id()) the last jobs ran on; the probe's tests compare them
	// with the main thread's.
	ClassDB::bind_method(D_METHOD("get_last_step_thread"), &ProbeTickNative::get_last_step_thread);
	ClassDB::bind_method(D_METHOD("get_last_slice_thread"), &ProbeTickNative::get_last_slice_thread);

	BIND_CONSTANT(UNITS);
	BIND_CONSTANT(SIDE);
	BIND_CONSTANT(COLS);
	BIND_CONSTANT(PAD);
	BIND_CONSTANT(UNREACHED);
}
