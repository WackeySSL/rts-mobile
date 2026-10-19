// The INTEGRATE kernel's cases for the sanitizer harness (ADR 0013 section 10): core/integrate.h's run, with
// core/flow.h's best_neighbour and acquire and core/fixed_math.h's isqrt, called the way bind/kernel_integrate.cpp
// calls them, over states the harness owns as plain std::vector buffers, so that AddressSanitizer sees every array at its
// exact size. The states come from the seed-42 arena (the dumps of tests/sim/native/sanitizer/dump_states.gd) and from
// crafted scenes. Sanitizers judge memory and undefined behaviour, not answers: the values of best_neighbour, acquire and
// the pass are the gdUnit4 suites' (test_integrate_kernel.gd and the movement suites), and only isqrt, whose range is the
// whole of int64, is also checked here. Plain C++17, no Godot header. MIT.
// Twin: bind/kernel_integrate.cpp (call() below is the same integrate::run, with the slot objects replaced by SlotData).
// A change to that call edits call() in the same PR.
#include <algorithm>
#include <climits>
#include <iterator>
#include <limits>
#include <string>
#include <utility>
#include <vector>

#include "cases.h"
#include "fixed_math.h"
#include "integrate.h"
#include "views.h"

namespace {

constexpr int64_t BIG = 1000000000; // a budget that finishes any field of a map this harness builds
constexpr int64_t BUCKET_COUNT = flow::BUCKETS;
constexpr int64_t NAV_DIRECT = 1, NAV_FIELD = 2; // World.NavMode
constexpr int64_t ORDER_ATTACK_MOVE = 1, ORDER_MOVE = 2, ORDER_ATTACK = 3; // World.Order
// The slots the pass keeps an answer for: the value bits of an int64_t, a slot's bit being a shift by 0 to 62. It is
// written here and not read from integrate::MEMO_SLOTS, so that a smaller MEMO_SLOTS is a Finding: the rows on the slots
// between would pay an Object::get of `complete` each (the data/rules.tres cache has 8 slots).
constexpr int64_t MEMOISED = std::numeric_limits<int64_t>::digits;

// One FlowField as INTEGRATE sees it: the served cost and what indexes it.
struct SlotData {
	std::vector<int32_t> cost;
	int64_t grid_cols = 0, cell_count = 0, stride = 0;
	bool complete = false;
};

// The World and FlowCache members that SimKernels::integrate reads and writes.
struct State {
	integrate::Rules rules;
	std::vector<int32_t> unit_id, type_index, push_x, push_y, pos_x, pos_y, goal_x, goal_y, group_cell, order, nav_mode, nav_cell, field, nav_next, best_dist, stall, intent_x, intent_y;
	std::vector<int32_t> type_speed, type_spacing, type_move_class;
	std::vector<uint8_t> move_cost;
	std::vector<int32_t> key_goal, key_class, key_version, last_used, ref_count, requested, status;
	int64_t cols = 0, rows = 0, classes = 0, requests = 0;
	std::vector<SlotData> slots;
};

// The slots of the state as the pass reaches them (bind/kernel_integrate.cpp's BoundSlots). The bind layer pays an
// Object::get for each ask of `complete`, which ADR 0013 section 2 forbids per row, so a slot below MEMOISED
// may be asked once, and again only after its recycle: a second ask is a Finding (the pass lost its memo).
class VectorSlots final : public integrate::Slots {
public:
	explicit VectorSlots(std::vector<SlotData> &slots) :
			slots_(slots), asked_(slots.size(), false) {}

	int64_t count() override { return static_cast<int64_t>(slots_.size()); }
	bool complete(int64_t slot) override {
		if (known(slot) && slot < MEMOISED) {
			if (asked_[static_cast<size_t>(slot)]) {
				throw Finding("integrate: the pass asked slot " + std::to_string(slot) + " for `complete` twice with no recycle between: a get per row in the bind layer");
			}
			asked_[static_cast<size_t>(slot)] = true;
		}
		return known(slot) && at(slot).complete;
	}
	flow::Served served(int64_t slot) override {
		flow::Served found;
		if (known(slot)) {
			found.cost = cview(at(slot).cost);
			found.grid_cols = at(slot).grid_cols;
			found.cell_count = at(slot).cell_count;
			found.stride = at(slot).stride;
			found.complete = at(slot).complete;
		}
		return found;
	}
	void recycle(int64_t slot) override {
		if (known(slot)) {
			at(slot).complete = false;
			std::fill(at(slot).cost.begin(), at(slot).cost.end(), static_cast<int32_t>(flow::UNREACHED));
			asked_[static_cast<size_t>(slot)] = false;
		}
	}

private:
	bool known(int64_t slot) const { return slot >= 0 && slot < static_cast<int64_t>(slots_.size()); }
	SlotData &at(int64_t slot) { return slots_[static_cast<size_t>(slot)]; }

	std::vector<SlotData> &slots_;
	std::vector<bool> asked_;
};

// What a pass changed in the rows that matter, for the harness's tally of work.
struct Mark {
	std::vector<int32_t> pos_x, pos_y, order, field, nav_next, stall;
};
Mark mark_of(const State &state) {
	return { state.pos_x, state.pos_y, state.order, state.field, state.nav_next, state.stall };
}
int64_t changed(const Mark &before, const State &state) {
	int64_t rows = 0;
	for (size_t row = 0; row < state.pos_x.size(); row++) {
		if (before.pos_x[row] != state.pos_x[row] || before.pos_y[row] != state.pos_y[row] || before.order[row] != state.order[row] || before.field[row] != state.field[row] || before.nav_next[row] != state.nav_next[row] || before.stall[row] != state.stall[row]) {
			rows += 1;
		}
	}
	return rows;
}

// One call of the INTEGRATE kernel.
void call(State &state) {
	integrate::Rows rows;
	rows.unit_id = cview(state.unit_id);
	rows.type_index = cview(state.type_index);
	rows.push_x = cview(state.push_x);
	rows.push_y = cview(state.push_y);
	rows.pos_x = view(state.pos_x);
	rows.pos_y = view(state.pos_y);
	rows.goal_x = view(state.goal_x);
	rows.goal_y = view(state.goal_y);
	rows.group_cell = view(state.group_cell);
	rows.order = view(state.order);
	rows.nav_mode = view(state.nav_mode);
	rows.nav_cell = view(state.nav_cell);
	rows.field = view(state.field);
	rows.nav_next = view(state.nav_next);
	rows.best_dist = view(state.best_dist);
	rows.stall = view(state.stall);
	rows.intent_x = view(state.intent_x);
	rows.intent_y = view(state.intent_y);
	integrate::Types types;
	types.speed = cview(state.type_speed);
	types.spacing = cview(state.type_spacing);
	types.move_class = cview(state.type_move_class);
	flow::Keys keys;
	keys.key_goal = view(state.key_goal);
	keys.key_class = view(state.key_class);
	keys.key_version = view(state.key_version);
	keys.last_used = view(state.last_used);
	keys.ref_count = view(state.ref_count);
	keys.requested = view(state.requested);
	keys.status = view(state.status);
	keys.cols = state.cols;
	keys.rows = state.rows;
	keys.classes = state.classes;
	keys.requests = state.requests;
	VectorSlots slots(state.slots);
	integrate::run(rows, types, cview(state.move_cost), state.rules, keys, slots);
	state.requests = keys.requests;
}

// `passes` calls, a tick apart, counting in the tally the rows that each one changed.
void play(State &state, int64_t passes, Tally &tally) {
	for (int64_t pass = 0; pass < passes; pass++) {
		const Mark before = mark_of(state);
		call(state);
		state.rules.tick += 1;
		tally.runs += 1;
		tally.work += changed(before, state);
	}
}

// ---- The states of the arena dumps ----

// The state of a dump, read the way the bind layer's check_world would: a wrong length is refused.
State from_dump(const Dump &dump) {
	State state;
	const struct {
		const char *name;
		std::vector<int32_t> State::*column;
	} columns[] = {
		{ "world.unit_id", &State::unit_id },
		{ "world.type_index", &State::type_index },
		{ "world.push_x", &State::push_x },
		{ "world.push_y", &State::push_y },
		{ "world.pos_x", &State::pos_x },
		{ "world.pos_y", &State::pos_y },
		{ "world.goal_x", &State::goal_x },
		{ "world.goal_y", &State::goal_y },
		{ "world.group_cell", &State::group_cell },
		{ "world.order", &State::order },
		{ "world.nav_mode", &State::nav_mode },
		{ "world.nav_cell", &State::nav_cell },
		{ "world.field", &State::field },
		{ "world.nav_next", &State::nav_next },
		{ "world.best_dist", &State::best_dist },
		{ "world.stall", &State::stall },
		{ "world.intent_x", &State::intent_x },
		{ "world.intent_y", &State::intent_y },
		{ "world.type_speed", &State::type_speed },
		{ "world.type_spacing", &State::type_spacing },
		{ "world.type_move_class", &State::type_move_class },
		{ "flow.key_goal", &State::key_goal },
		{ "flow.key_class", &State::key_class },
		{ "flow.key_version", &State::key_version },
		{ "flow.last_used", &State::last_used },
		{ "flow.ref_count", &State::ref_count },
		{ "flow.requested", &State::requested },
		{ "flow.status", &State::status },
	};
	for (const auto &column : columns) {
		(state.*column.column) = dump.ints(column.name);
	}
	state.move_cost = dump.bytes("world.move_cost");
	integrate::Rules &rules = state.rules;
	rules.map_cols = dump.scalar("world.map_cols");
	rules.map_rows = dump.scalar("world.map_rows");
	rules.map_w = dump.scalar("world.map_w");
	rules.map_h = dump.scalar("world.map_h");
	rules.map_version = dump.scalar("world.map_version");
	rules.tick = dump.scalar("world.tick");
	rules.line_check_period_ticks = dump.scalar("world.line_check_period_ticks");
	rules.stall_ticks = dump.scalar("world.stall_ticks");
	rules.stall_range_spacings = dump.scalar("world.stall_range_spacings");
	rules.attack_rekey_milli = dump.scalar("world.attack_rekey_milli");
	state.cols = dump.scalar("flow.cols");
	state.rows = dump.scalar("flow.rows");
	state.classes = dump.scalar("flow.classes");
	state.requests = dump.scalar("flow.requests");
	const int64_t units = dump.scalar("world.unit_count");
	const int64_t slots = dump.scalar("flow.slots");
	const int64_t padded = (state.cols + flow::PAD) * (state.rows + flow::PAD);
	for (const std::vector<int32_t> *column : { &state.unit_id, &state.type_index, &state.pos_x, &state.pos_y, &state.goal_x, &state.goal_y, &state.group_cell, &state.order, &state.nav_mode, &state.nav_cell, &state.field, &state.nav_next, &state.best_dist, &state.stall }) {
		if (static_cast<int64_t>(column->size()) != units) {
			throw std::runtime_error("a row column of the dump does not have one entry per unit");
		}
	}
	for (const std::vector<int32_t> *column : { &state.push_x, &state.push_y, &state.intent_x, &state.intent_y }) {
		if (static_cast<int64_t>(column->size()) < units) {
			throw std::runtime_error("a scratch column of the dump is shorter than the rows");
		}
	}
	for (const std::vector<int32_t> *column : { &state.key_goal, &state.key_class, &state.key_version, &state.last_used, &state.ref_count, &state.requested, &state.status }) {
		if (static_cast<int64_t>(column->size()) != slots) {
			throw std::runtime_error("a column of the flow cache does not have one entry per slot");
		}
	}
	for (int64_t index = 0; index < slots; index++) {
		const std::string prefix = "flow.slot." + std::to_string(index) + ".";
		SlotData data;
		data.cost = dump.ints(prefix + "cost");
		if (static_cast<int64_t>(data.cost.size()) != padded) {
			throw std::runtime_error(prefix + " has a cost that is not the padded size of the map");
		}
		data.grid_cols = dump.scalar(prefix + "grid_cols");
		data.cell_count = dump.scalar(prefix + "cell_count");
		data.stride = dump.scalar(prefix + "stride");
		data.complete = dump.scalar(prefix + "complete") != 0;
		state.slots.push_back(std::move(data));
	}
	return state;
}

// Pushes that are different for every row, in and out of the speed of a unit, for a pass that moves every row.
void push_everyone(State &state) {
	for (size_t row = 0; row < state.pos_x.size(); row++) {
		state.push_x[row] = static_cast<int32_t>(static_cast<int64_t>(row * 37) % 241 - 120);
		state.push_y[row] = static_cast<int32_t>(static_cast<int64_t>(row * 53) % 191 - 95);
	}
}

// Every unit follows a field: the fields of the dump as they stand, an ATTACK order on every third row, so that the
// look-ups, the re-key and the acquire of a unit's own field run on real caches.
void follow_fields(State &state) {
	const int64_t slots = static_cast<int64_t>(state.slots.size());
	for (size_t row = 0; row < state.pos_x.size(); row++) {
		const int64_t as = static_cast<int64_t>(row);
		state.order[row] = static_cast<int32_t>(as % 3 == 0 ? ORDER_ATTACK : (as % 3 == 1 ? ORDER_MOVE : ORDER_ATTACK_MOVE));
		state.nav_mode[row] = static_cast<int32_t>(NAV_FIELD);
		state.field[row] = static_cast<int32_t>(slots > 0 ? as % slots : -1);
		state.nav_next[row] = -1;
		state.goal_x[row] = static_cast<int32_t>((as * 7919) % std::max<int64_t>(state.rules.map_w, 1));
		state.goal_y[row] = static_cast<int32_t>((as * 6151) % std::max<int64_t>(state.rules.map_h, 1));
	}
}

// Each dump gets the pass as dumped, a pass with pushes on every row, a pass with steps at both ends of int32, and
// the fields followed by every row; each from a fresh copy and over many ticks, so that rows arrive, stall and re-key.
void on_dump(const Dump &dump, Tally &tally) {
	const State base = from_dump(dump);
	{
		State state = base;
		play(state, 40, tally);
	}
	{
		State state = base;
		push_everyone(state);
		play(state, 40, tally);
	}
	{
		State state = base;
		for (size_t row = 0; row < state.pos_x.size(); row++) {
			state.intent_x[row] = row % 2 == 0 ? INT32_MAX : INT32_MIN;
			state.intent_y[row] = row % 3 == 0 ? INT32_MAX : INT32_MIN;
			state.push_x[row] = row % 5 == 0 ? INT32_MAX : INT32_MIN;
			state.push_y[row] = row % 7 == 0 ? INT32_MAX : INT32_MIN;
		}
		play(state, 3, tally);
	}
	{
		State state = base;
		follow_fields(state);
		push_everyone(state);
		play(state, 60, tally);
	}
}

// ---- Crafted cases ----

// A deterministic stream for the crafted scenes (the harness only: the sim has no random numbers).
struct Stream {
	uint64_t seed;
	int64_t next(int64_t bound) {
		seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
		return static_cast<int64_t>((seed >> 33) % static_cast<uint64_t>(bound));
	}
};

// A scene: a map of `cols` x `rows` tiles with about one tile in `rock_in` blocked for some class, the three move
// classes with a type each, `slots` fields integrated to completion (every other one still pending) and `units` rows.
State make_scene(Stream &stream, int64_t cols, int64_t rows, int64_t slots, int64_t units, int64_t rock_in) {
	State state;
	state.cols = cols;
	state.rows = rows;
	state.classes = 3;
	const int64_t cells = cols * rows;
	state.rules.map_cols = cols;
	state.rules.map_rows = rows;
	state.rules.map_w = cols * 1000;
	state.rules.map_h = rows * 1000;
	state.rules.map_version = 2;
	state.rules.tick = 7;
	state.rules.line_check_period_ticks = 5;
	state.rules.stall_ticks = 6;
	state.rules.stall_range_spacings = 2;
	state.rules.attack_rekey_milli = 2500;
	for (int64_t cls = 0; cls < 3; cls++) {
		for (int64_t cell = 0; cell < cells; cell++) {
			state.move_cost.push_back(static_cast<uint8_t>(stream.next(rock_in) == 0 ? 0 : 10 + stream.next(4) * 10));
		}
	}
	state.type_speed = { 120, 61, 0 };
	state.type_spacing = { 1200, 1000, 900 };
	state.type_move_class = { 0, 1, 2 };
	const size_t padded = static_cast<size_t>((cols + flow::PAD) * (rows + flow::PAD));
	for (int64_t slot = 0; slot < slots; slot++) {
		const int64_t goal = stream.next(cells);
		const int64_t cls = stream.next(3);
		SlotData data;
		data.cost.assign(padded, static_cast<int32_t>(flow::UNREACHED));
		std::vector<int32_t> next(padded), bucket_head(BUCKET_COUNT), link_next(padded), link_prev(padded);
		std::vector<uint8_t> pad_cost(padded);
		flow::Slot field;
		field.cost = view(data.cost);
		field.next = view(next);
		field.bucket_head = view(bucket_head);
		field.link_next = view(link_next);
		field.link_prev = view(link_prev);
		field.pad_cost = view(pad_cost);
		flow::begin(field, goal, cls, cview(state.move_cost), cols, rows);
		if (slot % 2 == 0) {
			flow::advance(field, BIG);
		}
		if (field.swapped) {
			std::swap(data.cost, next);
		}
		data.complete = field.complete;
		data.grid_cols = field.grid_cols;
		data.cell_count = field.cell_count;
		data.stride = field.stride;
		state.slots.push_back(std::move(data));
		state.key_goal.push_back(static_cast<int32_t>(goal));
		state.key_class.push_back(static_cast<int32_t>(cls));
		state.key_version.push_back(static_cast<int32_t>(state.rules.map_version));
		state.last_used.push_back(static_cast<int32_t>(stream.next(9)));
		state.ref_count.push_back(static_cast<int32_t>(stream.next(3)));
		state.requested.push_back(static_cast<int32_t>(slot + 1));
		state.status.push_back(static_cast<int32_t>(slot % 2 == 0 ? flow::ACTIVE : flow::WAITING));
		state.requests = slot + 1;
	}
	const size_t scratch = static_cast<size_t>(units + 8);
	for (std::vector<int32_t> *column : { &state.push_x, &state.push_y, &state.intent_x, &state.intent_y }) {
		column->assign(scratch, 0);
	}
	for (int64_t row = 0; row < units; row++) {
		state.unit_id.push_back(static_cast<int32_t>(row + 1));
		state.type_index.push_back(static_cast<int32_t>(stream.next(3)));
		state.pos_x.push_back(static_cast<int32_t>(stream.next(cols * 1000)));
		state.pos_y.push_back(static_cast<int32_t>(stream.next(rows * 1000)));
		state.goal_x.push_back(static_cast<int32_t>(stream.next(cols * 1000)));
		state.goal_y.push_back(static_cast<int32_t>(stream.next(rows * 1000)));
		state.group_cell.push_back(static_cast<int32_t>(stream.next(4) == 0 ? stream.next(cells) : -1));
		state.order.push_back(static_cast<int32_t>(stream.next(4)));
		state.nav_mode.push_back(static_cast<int32_t>(stream.next(5)));
		state.nav_cell.push_back(static_cast<int32_t>(stream.next(3) == 0 ? -1 : stream.next(cells)));
		state.field.push_back(static_cast<int32_t>(stream.next(slots + 2) - 1));
		state.nav_next.push_back(static_cast<int32_t>(stream.next(4) == 0 ? -1 : stream.next(cells + 2) - 2));
		state.best_dist.push_back(static_cast<int32_t>(stream.next(2) == 0 ? flow::UNREACHED : stream.next(3000)));
		state.stall.push_back(static_cast<int32_t>(stream.next(6)));
		state.intent_x[static_cast<size_t>(row)] = static_cast<int32_t>(stream.next(241) - 120);
		state.intent_y[static_cast<size_t>(row)] = static_cast<int32_t>(stream.next(241) - 120);
	}
	return state;
}

// Maps of every shape the rules tell apart (one tile, a row, a column, wide, tall, square), rock of every density, with
// random orders, modes, fields and goals in range, over many ticks.
void random_scenes(Tally &tally) {
	const int64_t shapes[][2] = { { 1, 1 }, { 1, 9 }, { 9, 1 }, { 2, 2 }, { 24, 40 }, { 40, 24 }, { 64, 64 } };
	Stream stream = { 42 };
	for (const auto &shape : shapes) {
		for (const int64_t rock_in : { int64_t(2), int64_t(5), int64_t(40), BIG }) {
			for (const int64_t slots : { int64_t(1), int64_t(3), int64_t(8) }) {
				State state = make_scene(stream, shape[0], shape[1], slots, 60, rock_in);
				play(state, 50, tally);
			}
		}
	}
}

// More slots than the pass keeps an answer for (MEMOISED): the slots past them are asked on each use, and the ones
// below must not be mistaken for them (a shift past 62 is undefined).
void many_slots(Tally &tally) {
	Stream stream = { 11 };
	for (const int64_t slots : { MEMOISED - 1, MEMOISED, MEMOISED + 1, int64_t(2) * MEMOISED + 6 }) {
		State state = make_scene(stream, 16, 16, slots, 120, 9);
		play(state, 30, tally);
	}
}

// A World with no map (cols 0): nothing to slide on, and an upper bound of the largest int32.
void no_map(Tally &tally) {
	Stream stream = { 7 };
	State state = make_scene(stream, 1, 1, 1, 6, 1000);
	state.cols = state.rows = 0;
	state.slots.clear();
	state.key_goal.clear();
	state.key_class.clear();
	state.key_version.clear();
	state.last_used.clear();
	state.ref_count.clear();
	state.requested.clear();
	state.status.clear();
	state.move_cost.clear();
	state.rules.map_cols = state.rules.map_rows = state.rules.map_w = state.rules.map_h = 0;
	const int32_t at[] = { 0, 1, 90000, INT32_MAX - 100, INT32_MAX, 5 };
	for (size_t row = 0; row < state.pos_x.size(); row++) {
		state.pos_x[row] = at[row];
		state.pos_y[row] = at[(row + 2) % std::size(at)];
		state.goal_x[row] = at[(row + 1) % std::size(at)];
		state.goal_y[row] = at[(row + 4) % std::size(at)];
		state.nav_mode[row] = static_cast<int32_t>(NAV_DIRECT);
		state.nav_cell[row] = 0;
		state.field[row] = -1;
		state.order[row] = static_cast<int32_t>(ORDER_MOVE);
		state.intent_x[row] = 120;
		state.intent_y[row] = -99;
	}
	play(state, 5, tally);
}

// The rules at their edges: a period of 0 and 1, stall_ticks 0 and 1, no reach, no re-key distance, and rows of no
// units at all.
void rule_edges(Tally &tally) {
	Stream stream = { 99 };
	for (const int64_t value : { int64_t(0), int64_t(1), int64_t(2) }) {
		State state = make_scene(stream, 20, 12, 4, 60, 9);
		state.rules.line_check_period_ticks = value;
		state.rules.stall_ticks = value;
		state.rules.stall_range_spacings = value;
		state.rules.attack_rekey_milli = value * 600;
		play(state, 40, tally);
	}
	State empty = make_scene(stream, 5, 5, 2, 0, 3);
	play(empty, 3, tally);
	State alone = make_scene(stream, 5, 5, 0, 5, 3);
	for (size_t row = 0; row < alone.pos_x.size(); row++) {
		alone.nav_mode[row] = static_cast<int32_t>(NAV_FIELD);
		alone.field[row] = 0;
	}
	play(alone, 10, tally);
}

// Fields and tables that name no slot, no type, no class: -1, the slot count, and both ends of int32. The pass reads
// them through ArrayView (0 outside), so it finishes and AddressSanitizer stays quiet.
void hostile_references(Tally &tally) {
	Stream stream = { 5 };
	const int32_t hostile[] = { -1, 0, 1, 3, 4, 100, INT32_MAX, INT32_MIN, -2, 8 };
	for (size_t shift = 0; shift < std::size(hostile); shift++) {
		State state = make_scene(stream, 16, 16, 3, 40, 6);
		for (size_t row = 0; row < state.pos_x.size(); row++) {
			state.field[row] = hostile[(row + shift) % std::size(hostile)];
			state.type_index[row] = hostile[(2 * row + shift) % std::size(hostile)];
			state.nav_mode[row] = static_cast<int32_t>(NAV_FIELD);
			state.order[row] = static_cast<int32_t>(row % 4);
			state.nav_next[row] = hostile[(3 * row + shift) % std::size(hostile)];
		}
		for (size_t type = 0; type < state.type_move_class.size(); type++) {
			state.type_move_class[type] = hostile[(type + shift) % std::size(hostile)];
		}
		play(state, 6, tally);
	}
}

// isqrt against an exact check in 128 bits: the floor of the root for squares and their neighbours, every power of
// two, small numbers, the largest int64, and the numbers that are not positive.
void check_isqrt(int64_t n) {
	const int64_t root = fixed_math::isqrt(n);
	if (n <= 0) {
		if (root != 0) {
			throw Finding("isqrt of " + std::to_string(n) + " is " + std::to_string(root) + ", not 0");
		}
		return;
	}
	const __int128 low = static_cast<__int128>(root) * root;
	const __int128 high = static_cast<__int128>(root + 1) * (root + 1);
	if (low > n || high <= n) {
		throw Finding("isqrt of " + std::to_string(n) + " is " + std::to_string(root) + ", not its floor");
	}
}
void isqrt_cases(Tally &tally) {
	for (int64_t n = -3; n < 20000; n++) {
		check_isqrt(n);
		tally.runs += 1;
	}
	for (int64_t shift = 0; shift < 63; shift++) {
		const int64_t power = int64_t(1) << shift;
		for (const int64_t n : { power - 1, power, power + 1 }) {
			check_isqrt(n);
		}
	}
	for (int64_t root = 1; root < int64_t(3037000499); root = root * 3 + 1) {
		for (const int64_t n : { root * root - 1, root * root, root * root + 1 }) {
			check_isqrt(n);
		}
	}
	for (const int64_t n : { INT64_MAX, INT64_MAX - 1, int64_t(3037000499) * 3037000499, int64_t(3037000499) * 3037000499 - 1, INT64_MIN, int64_t(INT32_MIN), int64_t(INT32_MAX) }) {
		check_isqrt(n);
	}
	tally.work += 1;
}

void crafted(Tally &tally) {
	random_scenes(tally);
	many_slots(tally);
	no_map(tally);
	rule_edges(tally);
	hostile_references(tally);
	isqrt_cases(tally);
}

} // namespace

const KernelCases INTEGRATE_CASES = { "integrate", on_dump, crafted };
