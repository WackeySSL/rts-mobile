// The FLOW kernel's cases for the sanitizer harness (ADR 0013 section 10): core/flow.h's run, begin, advance and
// recount, called the way bind/kernel_flow.cpp calls them (call() below is the same flow::run, with the slot objects
// replaced by SlotData), over states the harness owns as plain std::vector buffers, so that AddressSanitizer sees
// every array at its exact size. Plain C++17, no Godot header. MIT.
// Twin: bind/kernel_flow.cpp. Dump records: tests/sim/native/sanitizer/dump_states.gd.
#include <algorithm>
#include <climits>
#include <iterator>
#include <string>
#include <utility>
#include <vector>

#include "cases.h"
#include "flow.h"
#include "views.h"

namespace {

constexpr int64_t BIG = 1000000000; // a budget that finishes any field of a map this harness builds
constexpr int64_t BUCKET_COUNT = flow::BUCKETS;

// One FlowField: the arrays at their padded size and the int and bool members the kernel loads and stores.
struct SlotData {
	std::vector<int32_t> cost, next, bucket_head, link_next, link_prev;
	std::vector<uint8_t> pad_cost;
	int64_t goal_cell = -1, move_class = 0, grid_cols = 0, cell_count = 0, stride = 0, level = 0, pending = 0;
	bool complete = false;
};

// The World and FlowCache members that SimKernels::flow reads and writes.
struct FlowState {
	int64_t cols = 0, rows = 0, units = 0, rule_budget = 512;
	int64_t requests = 0;
	std::vector<int32_t> field, key_goal, key_class, requested, ref_count, status;
	std::vector<uint8_t> move_cost;
	std::vector<SlotData> slots;
};

flow::Slot load_slot(SlotData &data) {
	flow::Slot slot;
	slot.cost = view(data.cost);
	slot.next = view(data.next);
	slot.bucket_head = view(data.bucket_head);
	slot.link_next = view(data.link_next);
	slot.link_prev = view(data.link_prev);
	slot.pad_cost = view(data.pad_cost);
	slot.goal_cell = data.goal_cell;
	slot.move_class = data.move_class;
	slot.grid_cols = data.grid_cols;
	slot.cell_count = data.cell_count;
	slot.stride = data.stride;
	slot.level = data.level;
	slot.pending = data.pending;
	slot.complete = data.complete;
	return slot;
}

// The exit of a turn, as store_turn in bind/kernel_flow.cpp: the scalars and, when the field completed, the swap of the two buffers.
void store_slot(SlotData &data, const flow::Slot &slot) {
	data.goal_cell = slot.goal_cell;
	data.move_class = slot.move_class;
	data.grid_cols = slot.grid_cols;
	data.cell_count = slot.cell_count;
	data.stride = slot.stride;
	data.level = slot.level;
	data.pending = slot.pending;
	data.complete = slot.complete;
	if (slot.swapped) {
		std::swap(data.cost, data.next);
	}
}

// The slots of the state as flow::run reaches them, one turn at a time (bind/kernel_flow.cpp's FlowTurns).
class VectorTurns final : public flow::Turns {
public:
	explicit VectorTurns(FlowState &state) :
			state_(state) {}

	int64_t pending_of(int64_t slot) override { return known(slot) ? state_.slots[static_cast<size_t>(slot)].pending : int64_t(0); }
	bool load(int64_t slot) override {
		if (!known(slot)) {
			return false;
		}
		current_ = &state_.slots[static_cast<size_t>(slot)];
		turn_ = load_slot(*current_);
		return true;
	}
	flow::Slot &slot() override { return turn_; }
	void store() override { store_slot(*current_, turn_); }

private:
	bool known(int64_t slot) const { return slot >= 0 && slot < static_cast<int64_t>(state_.slots.size()); }

	FlowState &state_;
	SlotData *current_ = nullptr;
	flow::Slot turn_;
};

// One call of the FLOW kernel with `budget` cells; returns the cells it settled.
int64_t call(FlowState &state, int64_t budget) {
	flow::Call args;
	args.ref_count = view(state.ref_count);
	args.status = view(state.status);
	args.field = cview(state.field);
	args.requested = cview(state.requested);
	args.key_goal = cview(state.key_goal);
	args.key_class = cview(state.key_class);
	args.costs = cview(state.move_cost);
	args.units = state.units;
	args.cols = state.cols;
	args.rows = state.rows;
	VectorTurns turns(state);
	const flow::Run result = flow::run(args, budget, turns);
	// The bind loop ends because every pick starts a field or settles a cell; one that does neither repeats forever.
	if (result.stuck) {
		throw Finding("FLOW picked a slot and settled nothing: the kernel loop would never end");
	}
	return result.settled;
}

void count(Tally &tally, int64_t settled) {
	tally.runs += 1;
	tally.work += settled;
}

// Every slot is free, or active and finished: nothing is left to integrate.
void check_finished(const FlowState &state, const std::string &what) {
	for (size_t slot = 0; slot < state.slots.size(); slot++) {
		const bool free = state.status[slot] == 0;
		const bool done = state.status[slot] == flow::ACTIVE && state.slots[slot].pending == 0 && state.slots[slot].complete;
		if (!free && !done) {
			throw Finding(what + ": slot " + std::to_string(slot) + " is not finished after the last call");
		}
	}
}

// Calls with `budget` until a call settles nothing (the loop only ends early when the budget is spent, so a call
// that settles nothing found no work), then checks the result. Bounded, so a kernel that never finishes is a finding.
void drain(FlowState &state, int64_t budget, Tally &tally, const std::string &what) {
	int64_t cells = 0;
	for (const SlotData &slot : state.slots) {
		cells += static_cast<int64_t>(slot.cost.size());
	}
	const int64_t limit = cells / budget + 2 * static_cast<int64_t>(state.slots.size()) + 16;
	for (int64_t calls = 0; calls < limit; calls++) {
		const int64_t settled = call(state, budget);
		count(tally, settled);
		if (settled == 0) {
			check_finished(state, what);
			return;
		}
	}
	throw Finding(what + ": still integrating after " + std::to_string(limit) + " calls of " + std::to_string(budget) + " cells");
}

// The state of a dump, read the way the bind layer's check_world would: a wrong length is refused.
FlowState from_dump(const Dump &dump) {
	FlowState state;
	state.cols = dump.scalar("flow.cols");
	state.rows = dump.scalar("flow.rows");
	state.units = dump.scalar("world.unit_count");
	state.rule_budget = dump.scalar("world.flow_cells_per_tick");
	state.field = dump.ints("world.field");
	state.move_cost = dump.bytes("world.move_cost");
	state.key_goal = dump.ints("flow.key_goal");
	state.key_class = dump.ints("flow.key_class");
	state.requested = dump.ints("flow.requested");
	state.ref_count = dump.ints("flow.ref_count");
	state.status = dump.ints("flow.status");
	const int64_t slots = dump.scalar("flow.slots");
	const int64_t padded = (state.cols + flow::PAD) * (state.rows + flow::PAD);
	for (const std::vector<int32_t> *column : { &state.key_goal, &state.key_class, &state.requested, &state.ref_count, &state.status }) {
		if (static_cast<int64_t>(column->size()) != slots) {
			throw std::runtime_error("a column of the flow cache does not have one entry per slot");
		}
	}
	for (int64_t index = 0; index < slots; index++) {
		const std::string prefix = "flow.slot." + std::to_string(index) + ".";
		SlotData data;
		data.cost = dump.ints(prefix + "cost");
		data.next = dump.ints(prefix + "next");
		data.bucket_head = dump.ints(prefix + "bucket_head");
		data.link_next = dump.ints(prefix + "link_next");
		data.link_prev = dump.ints(prefix + "link_prev");
		data.pad_cost = dump.bytes(prefix + "pad_cost");
		for (const std::vector<int32_t> *array : { &data.cost, &data.next, &data.link_next, &data.link_prev }) {
			if (static_cast<int64_t>(array->size()) != padded) {
				throw std::runtime_error(prefix + " has an array that is not the padded size of the map");
			}
		}
		if (static_cast<int64_t>(data.pad_cost.size()) != padded || static_cast<int64_t>(data.bucket_head.size()) != BUCKET_COUNT) {
			throw std::runtime_error(prefix + " has a pad_cost or bucket_head of the wrong size");
		}
		data.goal_cell = dump.scalar(prefix + "goal_cell");
		data.move_class = dump.scalar(prefix + "move_class");
		data.grid_cols = dump.scalar(prefix + "grid_cols");
		data.cell_count = dump.scalar(prefix + "cell_count");
		data.stride = dump.scalar(prefix + "stride");
		data.level = dump.scalar(prefix + "level");
		data.pending = dump.scalar(prefix + "pending");
		data.complete = dump.scalar(prefix + "complete") != 0;
		state.slots.push_back(std::move(data));
	}
	return state;
}

// Each dump gets single calls with the budgets of a tick (none, one cell, an odd few, the rule's slice, all) and two
// runs to the end, each from a fresh copy of the dumped state.
void on_dump(const Dump &dump, Tally &tally) {
	const FlowState base = from_dump(dump);
	const std::string what = "tick " + std::to_string(dump.tick);
	for (const int64_t budget : { int64_t(0), int64_t(1), int64_t(7), base.rule_budget, BIG }) {
		FlowState state = base;
		count(tally, call(state, budget));
	}
	for (const int64_t budget : { int64_t(97), BIG }) {
		FlowState state = base;
		drain(state, budget, tally, what + ", budget " + std::to_string(budget));
	}
}

// ---- Crafted cases ----

// A map of `classes` cost layers as the World's move_cost holds them: entry class * cells + cell, 0 = blocked.
struct Map {
	int64_t cols = 0, rows = 0, classes = 3;
	std::vector<uint8_t> cost;
};

template <typename CostOf>
Map make_map(int64_t cols, int64_t rows, CostOf cost_of) {
	Map map;
	map.cols = cols;
	map.rows = rows;
	for (int64_t cls = 0; cls < map.classes; cls++) {
		for (int64_t y = 0; y < rows; y++) {
			for (int64_t x = 0; x < cols; x++) {
				map.cost.push_back(cost_of(cls, x, y));
			}
		}
	}
	return map;
}

uint8_t open_cost(int64_t, int64_t, int64_t) {
	return 10;
}
uint8_t all_slow(int64_t, int64_t, int64_t) {
	return 255;
}
uint8_t blocked(int64_t, int64_t, int64_t) {
	return 0;
}
// Grass, slow ground (41 and the 255 cap of the bucket ring), odd costs (12, 13) and about one cell in eleven blocked.
uint8_t mixed(int64_t cls, int64_t x, int64_t y) {
	static constexpr uint8_t COSTS[] = { 0, 41, 255, 12, 13, 10, 10, 10, 10, 10, 10 };
	return COSTS[(x * 7 + y * 13 + cls * 5) % 11];
}

// A cache of `slots` free slots over the map, as FlowCache.configure makes it, and `units` rows pointing nowhere.
FlowState make_state(const Map &map, int64_t slots, int64_t units) {
	FlowState state;
	state.cols = map.cols;
	state.rows = map.rows;
	state.units = units;
	state.move_cost = map.cost;
	state.field.assign(static_cast<size_t>(units), -1);
	for (std::vector<int32_t> *column : { &state.key_goal, &state.key_class, &state.requested, &state.ref_count, &state.status }) {
		column->assign(static_cast<size_t>(slots), 0);
	}
	const size_t padded = static_cast<size_t>((map.cols + flow::PAD) * (map.rows + flow::PAD));
	state.slots.resize(static_cast<size_t>(slots));
	for (SlotData &slot : state.slots) {
		slot.cost.assign(padded, 0);
		slot.next.assign(padded, 0);
		slot.link_next.assign(padded, 0);
		slot.link_prev.assign(padded, 0);
		slot.pad_cost.assign(padded, 0);
		slot.bucket_head.assign(static_cast<size_t>(BUCKET_COUNT), 0);
	}
	return state;
}

// FlowCache.acquire's new key: the slot waits for its integration and serves nothing until it is done.
void request(FlowState &state, int64_t slot, int64_t goal, int64_t cls) {
	const size_t at = static_cast<size_t>(slot);
	state.key_goal[at] = static_cast<int32_t>(goal);
	state.key_class[at] = static_cast<int32_t>(cls);
	state.requested[at] = static_cast<int32_t>(++state.requests);
	state.status[at] = flow::WAITING;
	state.slots[at].complete = false;
	std::fill(state.slots[at].cost.begin(), state.slots[at].cost.end(), static_cast<int32_t>(flow::UNREACHED));
}

// FlowCache.invalidate's re-integration: the slot waits again, and the same key keeps serving its old field.
void rerequest(FlowState &state, int64_t slot) {
	state.requested[static_cast<size_t>(slot)] = static_cast<int32_t>(++state.requests);
	state.status[static_cast<size_t>(slot)] = flow::WAITING;
}

std::string label(const char *what, const Map &map, int64_t budget) {
	return std::string(what) + " " + std::to_string(map.cols) + "x" + std::to_string(map.rows) + ", budget " + std::to_string(budget);
}

// Every cell of a small map as the goal of every class, run to the end a cell at a time, a few at a time and at
// once: the goal on every edge and corner, and a goal next to blocked cells.
void tiny_maps_every_goal(Tally &tally) {
	const int64_t sizes[][2] = { { 1, 1 }, { 1, 5 }, { 5, 1 }, { 2, 2 }, { 3, 3 }, { 6, 5 }, { 4, 7 } };
	for (const auto &size : sizes) {
		for (const int64_t budget : { int64_t(1), int64_t(3), BIG }) {
			for (const bool slow : { false, true }) {
				const Map map = make_map(size[0], size[1], slow ? mixed : open_cost);
				const int64_t cells = size[0] * size[1];
				FlowState state = make_state(map, cells * map.classes, cells);
				for (int64_t cell = 0; cell < cells; cell++) {
					for (int64_t cls = 0; cls < map.classes; cls++) {
						request(state, cell * map.classes + cls, cell, cls);
					}
					state.field[static_cast<size_t>(cell)] = static_cast<int32_t>(cell * map.classes);
				}
				drain(state, budget, tally, label("every goal", map, budget));
			}
		}
	}
}

// The four corners, the middle of each edge and the centre of maps up to the GDD's size, square and not, open and
// with slow and blocked cells, in slices of a few dozen cells, of the rule and at once.
void edges_and_corners(Tally &tally) {
	const int64_t sizes[][2] = { { 64, 64 }, { 17, 40 }, { 40, 17 } };
	for (const auto &size : sizes) {
		const int64_t cols = size[0], rows = size[1];
		const int64_t goals[] = { 0, cols / 2, cols - 1, (rows / 2) * cols, (rows / 2) * cols + cols / 2, (rows / 2) * cols + cols - 1, (rows - 1) * cols, (rows - 1) * cols + cols / 2, rows * cols - 1 };
		for (const int64_t budget : { int64_t(61), int64_t(512), BIG }) {
			for (const bool slow : { false, true }) {
				const Map map = make_map(cols, rows, slow ? mixed : open_cost);
				FlowState state = make_state(map, 9 * map.classes, 150);
				for (int64_t goal = 0; goal < 9; goal++) {
					for (int64_t cls = 0; cls < map.classes; cls++) {
						request(state, goal * map.classes + cls, goals[goal], cls);
					}
				}
				for (size_t row = 0; row < state.field.size(); row++) {
					state.field[row] = static_cast<int32_t>(row % 27);
				}
				drain(state, budget, tally, label("edges and corners", map, budget));
			}
		}
	}
}

// Nothing can be entered: the goal is still seeded, its neighbours are blocked and the field is the goal alone.
void blocked_maps(Tally &tally) {
	for (const int64_t side : { int64_t(1), int64_t(16) }) {
		const Map map = make_map(side, side, blocked);
		const int64_t goals[] = { 0, side - 1, side * side - 1, (side / 2) * side + side / 2 };
		FlowState state = make_state(map, 4, 4);
		for (int64_t goal = 0; goal < 4; goal++) {
			request(state, goal, goals[goal], goal % map.classes);
		}
		drain(state, BIG, tally, label("blocked", map, BIG));
	}
}

// The goal in one corner and in the opposite one, all three classes: the longest paths of the GDD's map.
void opposite_corners(Tally &tally) {
	const Map map = make_map(64, 64, open_cost);
	for (const int64_t budget : { int64_t(512), BIG }) {
		FlowState state = make_state(map, 6, 6);
		for (int64_t cls = 0; cls < map.classes; cls++) {
			request(state, cls * 2, 0, cls);
			request(state, cls * 2 + 1, 64 * 64 - 1, cls);
		}
		drain(state, budget, tally, label("opposite corners", map, budget));
	}
}

// The largest map: no limit is written down (the GDD plans 56 to 64 tiles), so the harness takes 1024 x 1024, 16 times the
// side. Its cell numbers (about 1.1 million) and distances (up to about 365 thousand on open ground, as many on
// all-255 ground, which also wraps the 512 buckets of the ring many times) are far above the GDD's map, and both
// stay well inside the int32 columns that hold them (they hold up to 46 thousand cells a side, and 1.7 thousand
// a side before a worst-case path reaches UNREACHED).
void largest_map(Tally &tally) {
	const int64_t side = 1024;
	const struct {
		uint8_t (*cost)(int64_t, int64_t, int64_t);
		int64_t goal;
		int64_t budget;
	} cases[] = { { open_cost, side * side - 1, BIG }, { all_slow, 0, 8192 }, { mixed, (side / 2) * side + side / 2, BIG } };
	for (const auto &one : cases) {
		const Map map = make_map(side, side, one.cost);
		FlowState state = make_state(map, 1, 1);
		request(state, 0, one.goal, 0);
		state.field[0] = 0;
		drain(state, one.budget, tally, label("largest map", map, one.budget));
	}
}

// A key the costs cannot integrate completes at once with everything UNREACHED, and the same call goes on.
void unusable_keys(Tally &tally) {
	const Map map = make_map(64, 64, open_cost);
	const int64_t cells = 64 * 64;
	const int64_t keys[][2] = { { cells, 0 }, { -1, 0 }, { INT32_MIN, 1 }, { INT32_MAX, 2 }, { 0, 3 }, { 0, -1 }, { 0, INT32_MAX }, { 0, INT32_MIN }, { cells - 1, 2 }, { 5, 1 } };
	FlowState state = make_state(map, 10, 10);
	for (int64_t slot = 0; slot < 10; slot++) {
		request(state, slot, keys[slot][0], keys[slot][1]);
		state.field[static_cast<size_t>(slot)] = static_cast<int32_t>(slot);
	}
	drain(state, 100, tally, label("unusable keys", map, 100));
}

// recount: a field column with no slot (-1), a number past the slots and at both ends of int32, more units than the
// column holds (the kernel counts the shorter) and none.
void recount_columns(Tally &tally) {
	const Map map = make_map(8, 8, open_cost);
	const int32_t entries[] = { -1, 0, 1, 2, 3, 99, INT32_MAX, INT32_MIN, 2, 2 };
	for (const int64_t units : { int64_t(0), int64_t(1), int64_t(10), int64_t(1000) }) {
		FlowState state = make_state(map, 4, 10);
		for (size_t row = 0; row < state.field.size(); row++) {
			state.field[row] = entries[row];
		}
		state.units = units;
		for (int64_t slot = 0; slot < 4; slot++) {
			request(state, slot, slot * 9, 0);
		}
		count(tally, call(state, 20));
		const int64_t seen = std::min<int64_t>(units, 10);
		int64_t want = 0;
		for (int64_t row = 0; row < seen; row++) {
			want += entries[row] >= 0 && entries[row] < 4 ? 1 : 0;
		}
		int64_t got = 0;
		for (const int32_t refs : state.ref_count) {
			got += refs;
		}
		if (got != want) {
			throw Finding("recount: " + std::to_string(got) + " references for " + std::to_string(units) + " units, expected " + std::to_string(want));
		}
	}
}

// Budgets at the ends of int64: none, negative and as much as there is.
void budget_extremes(Tally &tally) {
	const Map map = make_map(64, 64, mixed);
	for (const int64_t budget : { int64_t(0), int64_t(-1), INT64_MIN, INT64_MAX }) {
		FlowState state = make_state(map, 3, 3);
		for (int64_t slot = 0; slot < 3; slot++) {
			request(state, slot, slot * 1000 + 7, slot);
		}
		const int64_t settled = call(state, budget);
		count(tally, settled);
		if (budget > 0) {
			check_finished(state, label("budget extremes", map, budget));
		} else if (settled != 0) {
			throw Finding(label("budget extremes", map, budget) + ": a call without budget settled cells");
		}
	}
}

// A served field that waits again: the same key keeps serving while it re-integrates (also over repainted costs, as after
// set_terrain), another goal or class serves nothing, in slices and at once.
void reintegration(Tally &tally) {
	const Map map = make_map(64, 64, mixed);
	for (const int64_t budget : { int64_t(37), BIG }) {
		FlowState state = make_state(map, 3, 3);
		for (int64_t slot = 0; slot < 3; slot++) {
			request(state, slot, 100 + slot, slot);
			state.field[static_cast<size_t>(slot)] = static_cast<int32_t>(slot);
		}
		drain(state, BIG, tally, label("reintegration, first", map, BIG));
		for (size_t cell = 0; cell < state.move_cost.size(); cell += 5) {
			state.move_cost[cell] = static_cast<uint8_t>(state.move_cost[cell] == 0 ? 10 : 0);
		}
		rerequest(state, 0);
		rerequest(state, 1);
		state.key_goal[1] = 3000;
		request(state, 2, 4095, 2);
		count(tally, call(state, budget));
		drain(state, budget, tally, label("reintegration, second", map, budget));
	}
}

// A queue whose contents check_world cannot vouch for: heads and links that name no cell, in every spelling of "outside
// the array" (exactly its size, past it, below -1, both ends of int32), in a field caught mid-integration. ArrayView
// must turn each into a read of 0 and a skipped write, so the run only finishes and AddressSanitizer stays quiet;
// without the range check it reports the first such access. No -1 among them: that is the real "none", and the kernel
// only ends because every pop uses up one of the cells that `pending` counts (it is not meant to survive a wrong
// count), so a queue emptied by -1 links would leave advance() looking for a cell that is not there.
void corrupted_queue(Tally &tally) {
	const Map map = make_map(8, 8, open_cost);
	const int64_t stride = map.cols + flow::PAD;
	const int64_t padded = stride * (map.rows + flow::PAD);
	const int32_t hostile[] = { int32_t(padded), int32_t(padded + 1), int32_t(padded - 1), INT32_MIN, INT32_MAX, -2, -3, 0, 1, int32_t(stride),
		int32_t(padded - stride), int32_t(padded - 2), int32_t(stride + 1) };
	const size_t hostile_count = std::size(hostile);
	FlowState base = make_state(map, 1, 1);
	request(base, 0, 3 * stride + 3, 0);
	count(tally, call(base, 3));
	if (base.slots[0].pending <= 0) {
		throw Finding("corrupted queue: the field the case starts from is not half integrated");
	}
	for (size_t shift = 0; shift < hostile_count; shift++) {
		for (const int64_t budget : { int64_t(1), int64_t(5), BIG }) {
			FlowState state = base;
			SlotData &slot = state.slots[0];
			for (size_t at = 0; at < slot.bucket_head.size(); at++) {
				slot.bucket_head[at] = hostile[(at + shift) % hostile_count];
			}
			for (size_t at = 0; at < slot.link_next.size(); at++) {
				slot.link_next[at] = hostile[(at + shift) % hostile_count];
				slot.link_prev[at] = hostile[(2 * at + shift) % hostile_count];
			}
			count(tally, call(state, budget));
		}
	}
}

void crafted(Tally &tally) {
	tiny_maps_every_goal(tally);
	edges_and_corners(tally);
	blocked_maps(tally);
	opposite_corners(tally);
	largest_map(tally);
	unusable_keys(tally);
	recount_columns(tally);
	budget_extremes(tally);
	reintegration(tally);
	corrupted_queue(tally);
}

} // namespace

const KernelCases FLOW_CASES = { "flow", on_dump, crafted };
