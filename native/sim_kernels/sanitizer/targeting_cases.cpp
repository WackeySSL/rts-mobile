// The TARGETING kernel's cases for the sanitizer harness (ADR 0013 section 10): core/targeting.h's run, with
// core/fixed_math.h's line_clear, called the way bind/kernel_targeting.cpp calls it, over states the harness owns as plain
// std::vector buffers, so that AddressSanitizer sees every array at its exact size. The states come from the seed-42
// arena (the dumps of tests/sim/native/sanitizer/dump_states.gd, with the grid built afresh from the dumped positions) and
// from crafted scenes. Sanitizers judge memory and undefined behaviour, not answers: the targets and modes of the rules
// are the gdUnit4 suites' (test_targeting*.gd and test_engagement*.gd under both implementations,
// test_targeting_kernel*.gd), and only what needs no second implementation is checked here (a MOVE row ends with no
// target, no count past the rows, a grid with no cells finds nobody). The build has no -fwrapv, so the range that
// core/targeting.h records is run at its edges: positions of 10^9 and reaches of 2 * 10^9. Plain C++17, no Godot header. MIT.
// Twin: bind/kernel_targeting.cpp (call() below is the same targeting::run, with the arrays of the World replaced by
// vectors). A change to that call edits call() in the same PR.
#include <algorithm>
#include <climits>
#include <iterator>
#include <string>
#include <vector>

#include "cases.h"
#include "targeting.h"
#include "views.h"

namespace {

constexpr int64_t EDGE = 1000000000; // the range of positions that core/targeting.h records
constexpr int64_t TOP = 2000000000; // a reach of 2 * EDGE, which still fits an int32 element
constexpr int64_t ORDER_IDLE = 0, ORDER_ATTACK_MOVE = 1, ORDER_MOVE = 2, ORDER_ATTACK = 3; // World.Order
constexpr int64_t NAV_COUNT = 5; // World.NavMode.size()
constexpr int64_t ARMOUR_COUNT = 4; // World.Armour.size()

// The World members and the targeting grid that SimKernels::targeting reads and writes.
struct State {
	targeting::Rules rules;
	int64_t map_cols = 0, map_rows = 0;
	int64_t cols = 0, rows = 0, cell_milli = 4000;
	std::vector<int32_t> unit_id, owner, type_index, pos_x, pos_y, goal_x, goal_y, order, order_target, target, nav_mode, nav_cell, field, nav_next, best_dist, stall;
	std::vector<int32_t> armour, acquire, weapon, move_class, range, min_range, vs_armour;
	std::vector<uint8_t> move_cost;
	std::vector<int32_t> head, next;
};

int64_t units_of(const State &state) {
	return static_cast<int64_t>(state.unit_id.size());
}

// SpatialGrid.rebuild: rows go in descending order, so each cell lists its rows in ascending order, and a point outside
// the map goes to the nearest edge cell. A grid with no cells, or a cell side below 1, lists nothing.
void rebuild(State &state) {
	std::fill(state.head.begin(), state.head.end(), -1);
	std::fill(state.next.begin(), state.next.end(), -1);
	if (state.cols < 1 || state.rows < 1 || state.cell_milli < 1) {
		return;
	}
	for (int64_t row = units_of(state) - 1; row >= 0; row--) {
		const size_t at = static_cast<size_t>(row);
		const int64_t column = std::clamp<int64_t>(state.pos_x[at] / state.cell_milli, 0, state.cols - 1);
		const int64_t line = std::clamp<int64_t>(state.pos_y[at] / state.cell_milli, 0, state.rows - 1);
		const size_t cell = static_cast<size_t>(line * state.cols + column);
		state.next[at] = state.head[cell];
		state.head[cell] = static_cast<int32_t>(row);
	}
}

// One call of the TARGETING kernel: the counts it adds to stats.
targeting::Counts call(State &state) {
	targeting::Rows rows;
	rows.unit_id = cview(state.unit_id);
	rows.owner = cview(state.owner);
	rows.type_index = cview(state.type_index);
	rows.pos_x = cview(state.pos_x);
	rows.pos_y = cview(state.pos_y);
	rows.goal_x = view(state.goal_x);
	rows.goal_y = view(state.goal_y);
	rows.order = view(state.order);
	rows.order_target = view(state.order_target);
	rows.target = view(state.target);
	rows.nav_mode = view(state.nav_mode);
	rows.nav_cell = view(state.nav_cell);
	rows.field = view(state.field);
	rows.nav_next = view(state.nav_next);
	rows.best_dist = view(state.best_dist);
	rows.stall = view(state.stall);
	targeting::Types types;
	types.armour = cview(state.armour);
	types.acquire = cview(state.acquire);
	types.weapon = cview(state.weapon);
	types.move_class = cview(state.move_class);
	targeting::Weapons weapons;
	weapons.range = cview(state.range);
	weapons.min_range = cview(state.min_range);
	weapons.vs_armour = cview(state.vs_armour);
	targeting::Grid grid;
	grid.cols = state.cols;
	grid.rows = state.rows;
	grid.cell_milli = state.cell_milli;
	grid.head = cview(state.head);
	grid.next = cview(state.next);
	targeting::Map map;
	map.cols = state.map_cols;
	map.rows = state.map_rows;
	map.move_cost = cview(state.move_cost);
	return targeting::run(rows, types, weapons, grid, map, state.rules);
}

// The answers that need no second implementation: no count past what the rows can make (a row looks at the others at most
// once per call, and checks its line at most once), a grid with no cells (or a cell side below 1) looks at nobody, and a
// MOVE row ends with no target, whatever it held.
void check(const State &state, const targeting::Counts &counts, const char *what) {
	const int64_t units = units_of(state);
	const bool empty = state.cols < 1 || state.rows < 1 || state.cell_milli < 1;
	const bool bad_candidates = counts.candidates < 0 || counts.candidates > units * units || (empty && counts.candidates != 0);
	if (bad_candidates || counts.line_checks < 0 || counts.line_checks > units) {
		throw Finding(std::string("targeting: ") + what + ": " + std::to_string(counts.candidates) + " candidates, " + std::to_string(counts.line_checks) + " line checks");
	}
	for (size_t row = 0; row < state.order.size(); row++) {
		if (state.order[row] == ORDER_MOVE && state.target[row] != 0) {
			throw Finding(std::string("targeting: ") + what + ": MOVE row " + std::to_string(row) + " keeps the target " + std::to_string(state.target[row]));
		}
	}
}

// A call on the grid as the tick would have it, rebuilt from the positions, counted in the tally.
void play(State &state, Tally &tally, const char *what) {
	rebuild(state);
	const targeting::Counts counts = call(state);
	check(state, counts, what);
	tally.runs += 1;
	tally.work += counts.candidates + counts.line_checks;
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
		{ "world.owner", &State::owner },
		{ "world.type_index", &State::type_index },
		{ "world.pos_x", &State::pos_x },
		{ "world.pos_y", &State::pos_y },
		{ "world.goal_x", &State::goal_x },
		{ "world.goal_y", &State::goal_y },
		{ "world.order", &State::order },
		{ "world.order_target", &State::order_target },
		{ "world.target", &State::target },
		{ "world.nav_mode", &State::nav_mode },
		{ "world.nav_cell", &State::nav_cell },
		{ "world.field", &State::field },
		{ "world.nav_next", &State::nav_next },
		{ "world.best_dist", &State::best_dist },
		{ "world.stall", &State::stall },
		{ "world.type_armour", &State::armour },
		{ "world.type_acquire", &State::acquire },
		{ "world.type_weapon", &State::weapon },
		{ "world.type_move_class", &State::move_class },
		{ "world.weapon_range", &State::range },
		{ "world.weapon_min_range", &State::min_range },
		{ "world.weapon_vs_armour", &State::vs_armour },
		{ "target.head", &State::head },
		{ "target.next", &State::next },
	};
	for (const auto &column : columns) {
		(state.*column.column) = dump.ints(column.name);
	}
	state.move_cost = dump.bytes("world.move_cost");
	state.map_cols = dump.scalar("world.map_cols");
	state.map_rows = dump.scalar("world.map_rows");
	state.cols = dump.scalar("target.cols");
	state.rows = dump.scalar("target.rows");
	state.cell_milli = dump.scalar("target.cell_milli");
	state.rules.tick = dump.scalar("world.tick");
	state.rules.retarget_period_ticks = dump.scalar("world.retarget_period_ticks");
	state.rules.line_check_period_ticks = dump.scalar("world.line_check_period_ticks");
	const size_t units = state.unit_id.size();
	for (const std::vector<int32_t> *column : { &state.owner, &state.type_index, &state.pos_x, &state.pos_y, &state.goal_x, &state.goal_y, &state.order, &state.order_target, &state.target, &state.nav_mode, &state.nav_cell, &state.field, &state.nav_next, &state.best_dist, &state.stall }) {
		if (column->size() != units) {
			throw std::runtime_error("a row column of the dump does not have one entry per unit");
		}
	}
	const size_t types = state.armour.size();
	if (state.acquire.size() != types || state.weapon.size() != types || state.move_class.size() != types) {
		throw std::runtime_error("a type table of the dump does not have one entry per type");
	}
	if (state.min_range.size() != state.range.size() || state.vs_armour.size() != state.range.size() * static_cast<size_t>(ARMOUR_COUNT)) {
		throw std::runtime_error("a weapon table of the dump does not have one entry per weapon (four percents each)");
	}
	if (static_cast<int64_t>(state.move_cost.size()) != 3 * state.map_cols * state.map_rows) {
		throw std::runtime_error("the move costs of the dump are not three lists of the map's cells");
	}
	if (static_cast<int64_t>(state.head.size()) != state.cols * state.rows || state.next.size() < units) {
		throw std::runtime_error("the targeting grid of the dump does not have the size of its cells and rows");
	}
	return state;
}

// The same units on a grid of other cells: `side` milli-tiles, over the extent of the dumped grid.
State regridded(const State &base, int64_t side) {
	State state = base;
	const int64_t width = base.cols * base.cell_milli;
	const int64_t height = base.rows * base.cell_milli;
	state.cell_milli = side;
	state.cols = (width + side - 1) / side;
	state.rows = (height + side - 1) / side;
	state.head.assign(static_cast<size_t>(state.cols * state.rows), -1);
	return state;
}

// Each dump gets the pass as dumped, at every residue of the ticks (the turn of a row is `(tick + id) % period`), with the
// periods across their guards, with every row in each order and each navigation mode and a checked line or not, with
// every row unarmed in each of the ways a type can be (no weapon, a weapon past the tables), and on grids of other cells.
void on_dump(const Dump &dump, Tally &tally) {
	const State base = from_dump(dump);
	{
		State state = base;
		play(state, tally, "as dumped");
	}
	for (int64_t tick = 0; tick < 10; tick++) {
		State state = base;
		state.rules.tick = tick;
		play(state, tally, "tick");
	}
	for (const int64_t retarget : { INT64_MIN, int64_t(-1), int64_t(0), int64_t(1), int64_t(2), int64_t(5), int64_t(1000), INT64_MAX }) {
		for (const int64_t lines : { INT64_MIN, int64_t(-3), int64_t(0), int64_t(1), int64_t(3), int64_t(5), INT64_MAX }) {
			State state = base;
			state.rules.retarget_period_ticks = retarget;
			state.rules.line_check_period_ticks = lines;
			play(state, tally, "periods");
		}
	}
	// Every row due and on its turn, in each order, mode and checked-line state: the engagement pass meets all of them.
	for (const int64_t order : { ORDER_IDLE, ORDER_ATTACK_MOVE, ORDER_MOVE, ORDER_ATTACK }) {
		for (int64_t mode = 0; mode < NAV_COUNT; mode++) {
			for (const int32_t checked : { -1, 5 }) {
				State state = base;
				state.rules.retarget_period_ticks = 1;
				state.rules.line_check_period_ticks = 1;
				std::fill(state.order.begin(), state.order.end(), static_cast<int32_t>(order));
				std::fill(state.nav_mode.begin(), state.nav_mode.end(), static_cast<int32_t>(mode));
				std::fill(state.nav_cell.begin(), state.nav_cell.end(), checked);
				// An ATTACK row names the next unit (the last one names the first).
				for (size_t row = 0; row < state.unit_id.size(); row++) {
					state.order_target[row] = state.unit_id[(row + 1) % state.unit_id.size()];
				}
				play(state, tally, "orders");
			}
		}
	}
	// A target the row holds that is not a unit: gone, itself, the first unit, the ends of the int32 range.
	for (const int32_t held : { 0, 1, 99999, INT32_MAX, INT32_MIN, -1 }) {
		State state = base;
		state.rules.retarget_period_ticks = 1;
		state.rules.line_check_period_ticks = 1;
		std::fill(state.target.begin(), state.target.end(), held);
		std::fill(state.order_target.begin(), state.order_target.end(), held);
		play(state, tally, "held targets");
		std::fill(state.order.begin(), state.order.end(), static_cast<int32_t>(ORDER_ATTACK));
		play(state, tally, "locked targets");
	}
	for (const int32_t weapon : { -1, 0, 1, 3, INT32_MAX, INT32_MIN }) {
		State state = base;
		state.rules.retarget_period_ticks = 1;
		state.rules.line_check_period_ticks = 1;
		std::fill(state.weapon.begin(), state.weapon.end(), weapon);
		play(state, tally, "weapons");
	}
	for (const int64_t side : { int64_t(500), int64_t(3000), int64_t(7000), int64_t(64000) }) {
		State state = regridded(base, side);
		state.rules.retarget_period_ticks = 1;
		play(state, tally, "other cells");
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

// A scene: a map of `cols` x `rows` tiles with a quarter of the tiles rock for each of three movement classes, a grid of
// cells of 4000 over it, four unit types (the weapon indexes 0, 1 and 2, and one that names no weapon) and `units` rows
// scattered over the map and a margin of 3000 around it, with owners 0 to 2 and a random order, mode, target and line
// state each. The rules are the shipped ones (5 and 5).
State make_scene(Stream &stream, int64_t cols, int64_t rows, int64_t units) {
	State state;
	state.map_cols = cols;
	state.map_rows = rows;
	state.cols = (cols * 1000 + state.cell_milli - 1) / state.cell_milli;
	state.rows = (rows * 1000 + state.cell_milli - 1) / state.cell_milli;
	state.rules = { stream.next(40), 5, 5 };
	state.move_cost.assign(static_cast<size_t>(3 * cols * rows), 10);
	for (uint8_t &cost : state.move_cost) {
		cost = stream.next(4) == 0 ? 0 : 10;
	}
	state.armour = { 0, 1, 2, 3 };
	state.acquire = { 5000, 5500, 6000, 3000 };
	state.weapon = { 0, 1, 2, -1 };
	state.move_class = { 0, 1, 2, 0 };
	state.range = { 4000, 5000, 4500 };
	state.min_range = { 0, 1000, 2000 };
	state.vs_armour = { 100, 10, 0, 40, 20, 100, 50, 0, 70, 60, 80, 100 };
	state.head.assign(static_cast<size_t>(state.cols * state.rows), -1);
	const size_t slack = static_cast<size_t>(units + 8);
	state.next.assign(slack, -1);
	for (int64_t row = 0; row < units; row++) {
		state.unit_id.push_back(static_cast<int32_t>(row + 1));
		state.owner.push_back(static_cast<int32_t>(stream.next(3)));
		state.type_index.push_back(static_cast<int32_t>(stream.next(4)));
		// Every fifth unit stands on or a few milli from an earlier one (equal distances, equal cells).
		if (row > 0 && row % 5 == 0) {
			const size_t earlier = static_cast<size_t>(stream.next(row));
			state.pos_x.push_back(state.pos_x[earlier] + static_cast<int32_t>(stream.next(8) - 3));
			state.pos_y.push_back(state.pos_y[earlier] + static_cast<int32_t>(stream.next(8) - 3));
		} else {
			state.pos_x.push_back(static_cast<int32_t>(stream.next(cols * 1000 + 6000) - 3000));
			state.pos_y.push_back(static_cast<int32_t>(stream.next(rows * 1000 + 6000) - 3000));
		}
		state.goal_x.push_back(static_cast<int32_t>(stream.next(cols * 1000)));
		state.goal_y.push_back(static_cast<int32_t>(stream.next(rows * 1000)));
		state.order.push_back(static_cast<int32_t>(stream.next(4)));
		// A target that is a unit, a unit that is gone, or none.
		const int64_t kind = stream.next(4);
		const int32_t named = kind == 0 ? 0 : (kind == 1 ? static_cast<int32_t>(units + 1 + stream.next(3)) : static_cast<int32_t>(1 + stream.next(units)));
		state.order_target.push_back(named);
		state.target.push_back(static_cast<int32_t>(stream.next(2) == 0 ? 0 : 1 + stream.next(units)));
		state.nav_mode.push_back(static_cast<int32_t>(stream.next(NAV_COUNT)));
		state.nav_cell.push_back(static_cast<int32_t>(stream.next(3) - 1));
		state.field.push_back(static_cast<int32_t>(stream.next(4) - 1));
		state.nav_next.push_back(static_cast<int32_t>(stream.next(3) - 2));
		state.best_dist.push_back(static_cast<int32_t>(stream.next(100)));
		state.stall.push_back(static_cast<int32_t>(stream.next(5)));
	}
	return state;
}

// Maps of every shape (one tile, a row, a column, wide, tall), crowds of every size, random ticks and the periods around the
// shipped ones, and the work of a call run six times over the same scene as the units walk.
void random_scenes(Tally &tally) {
	const int64_t shapes[][2] = { { 1, 1 }, { 1, 9 }, { 9, 1 }, { 3, 2 }, { 20, 12 }, { 64, 64 } };
	Stream stream = { 41 };
	for (const auto &shape : shapes) {
		for (const int64_t units : { int64_t(0), int64_t(1), int64_t(2), int64_t(9), int64_t(40), int64_t(150) }) {
			State state = make_scene(stream, shape[0], shape[1], units);
			for (int64_t round = 0; round < 6; round++) {
				state.rules.tick = stream.next(60);
				state.rules.retarget_period_ticks = stream.next(8) - 2;
				state.rules.line_check_period_ticks = stream.next(8) - 2;
				play(state, tally, "random");
				for (size_t at = 0; at < state.pos_x.size(); at++) {
					state.pos_x[at] += static_cast<int32_t>(stream.next(1201) - 600);
					state.pos_y[at] += static_cast<int32_t>(stream.next(1201) - 600);
				}
			}
		}
	}
}

// A grid with no cells (an empty map, or no columns or no rows) and a cell side below 1: nobody is found, nothing is
// divided by the side and the view of a head that is empty is never indexed.
void no_cells(Tally &tally) {
	Stream stream = { 5 };
	const struct {
		int64_t cols, rows, side;
	} grids[] = { { 0, 0, 4000 }, { 0, 3, 4000 }, { 5, 0, 4000 }, { 5, 3, 0 }, { 5, 3, -4000 }, { 5, 3, INT64_MIN } };
	for (const auto &grid : grids) {
		State state = make_scene(stream, 20, 12, 40);
		state.rules.retarget_period_ticks = 1;
		state.cols = grid.cols;
		state.rows = grid.rows;
		state.cell_milli = grid.side;
		state.head.assign(static_cast<size_t>(grid.cols * grid.rows), -1);
		play(state, tally, "no cells");
	}
	// The map itself with no cells: line_clear reads no move cost, and a line is clear.
	State bare = make_scene(stream, 20, 12, 40);
	bare.map_cols = 0;
	bare.map_rows = 0;
	bare.move_cost.clear();
	bare.rules.retarget_period_ticks = 1;
	bare.rules.line_check_period_ticks = 1;
	play(bare, tally, "no map");
}

// The range that core/targeting.h records, at its edges, where the sanitizer build aborts on an overflow. Units at the
// corners and edge midpoints of the square of side 2 * EDGE and at the origin, in a map of one tile (every unit in the one
// cell), each with a reach of 2 * EDGE = 2 * 10^9 and a minimum range of 10^9: d2 reaches 8 * 10^18 and reach^2 4 * 10^18,
// both below 2^63. Then the largest values an int32 element can give a range (INT32_MAX squared, 4.6 * 10^18).
void range_edges(Tally &tally) {
	Stream stream = { 8 };
	State corners = make_scene(stream, 1, 1, 0);
	corners.armour = { 0 };
	corners.acquire = { static_cast<int32_t>(TOP) };
	corners.weapon = { 0 };
	corners.move_class = { 0 };
	corners.range = { static_cast<int32_t>(TOP) };
	corners.min_range = { static_cast<int32_t>(EDGE) };
	corners.vs_armour = { 100, 100, 100, 100 };
	corners.rules = { 0, 1, 1 };
	int64_t id = 1;
	for (const int64_t x : { -EDGE, int64_t(0), EDGE }) {
		for (const int64_t y : { -EDGE, int64_t(0), EDGE }) {
			corners.unit_id.push_back(static_cast<int32_t>(id));
			// Units 1 and 7, 2 and 8, 3 and 9 stand 2 * EDGE apart along x: the west and the middle column are player 1's, the
			// east column player 2's, so unit 1 has only unit 7 in reach (4 * 10^18 away, exactly its reach).
			corners.owner.push_back(static_cast<int32_t>(id <= 6 ? 1 : 2));
			corners.type_index.push_back(0);
			corners.pos_x.push_back(static_cast<int32_t>(x));
			corners.pos_y.push_back(static_cast<int32_t>(y));
			corners.goal_x.push_back(0);
			corners.goal_y.push_back(0);
			corners.order.push_back(static_cast<int32_t>(id % 4 == 3 ? ORDER_ATTACK : ORDER_ATTACK_MOVE));
			corners.order_target.push_back(static_cast<int32_t>(id % 9 + 1));
			// Held by hand: a unit across the square (6 further on), so that the kept-target distance is computed over the range.
			corners.target.push_back(static_cast<int32_t>((id + 6) % 9 + 1));
			corners.nav_mode.push_back(1);
			corners.nav_cell.push_back(static_cast<int32_t>(id % 2));
			corners.field.push_back(-1);
			corners.nav_next.push_back(-1);
			corners.best_dist.push_back(0);
			corners.stall.push_back(0);
			id += 1;
		}
	}
	corners.next.assign(corners.unit_id.size() + 8, -1);
	// The acquire range, the weapon range (1000: a unit with a target out of it tests the line, at its acquire range) and the
	// minimum range, each across the range, from a clean state every time.
	for (const int64_t reach : { TOP, int64_t(INT32_MAX), EDGE, int64_t(1) }) {
		for (const int64_t minimum : { int64_t(0), EDGE, int64_t(INT32_MAX) }) {
			for (const int64_t weapon_reach : { int64_t(1000), reach }) {
				State state = corners;
				state.acquire = { static_cast<int32_t>(reach) };
				state.range = { static_cast<int32_t>(weapon_reach) };
				state.min_range = { static_cast<int32_t>(minimum) };
				play(state, tally, "corners");
			}
		}
	}
}

// Type numbers, weapon indexes, armour classes and heads that name nothing: a type past the table, negative or at both ends
// of int32, a type table that names a weapon past the weapon tables, an armour class past the four, owners at both ends of
// int32, an order past the four and heads that name rows past the units (inside and outside the arrays). The pass reads
// them through ArrayView (0 outside), so it finishes and AddressSanitizer stays quiet. Only heads are made hostile: a
// hostile link could close a circle, and the scan, which has no cap, would never end (in the twin either; SpatialGrid never
// writes one).
void hostile_references(Tally &tally) {
	Stream stream = { 6 };
	const int32_t hostile[] = { -1, 0, 1, 3, 4, 100, INT32_MAX, INT32_MIN, -2, 8 };
	for (size_t shift = 0; shift < std::size(hostile); shift++) {
		State state = make_scene(stream, 12, 8, 40);
		state.rules.retarget_period_ticks = 1;
		state.rules.line_check_period_ticks = 1;
		for (size_t row = 0; row < state.type_index.size(); row++) {
			state.type_index[row] = hostile[(row + shift) % std::size(hostile)];
			state.owner[row] = hostile[(row + 3 * shift) % std::size(hostile)];
			state.order[row] = hostile[(row + 5 * shift) % std::size(hostile)];
		}
		for (size_t type = 0; type < state.weapon.size(); type++) {
			state.weapon[type] = hostile[(type + shift) % std::size(hostile)];
			state.armour[type] = hostile[(type + 2 * shift) % std::size(hostile)];
			state.move_class[type] = hostile[(type + 4 * shift) % std::size(hostile)];
		}
		rebuild(state);
		for (size_t cell = 0; cell < state.head.size(); cell += 3) {
			state.head[cell] = hostile[(cell + 2 * shift) % std::size(hostile)];
		}
		const targeting::Counts counts = call(state);
		check(state, counts, "hostile references");
		tally.runs += 1;
		tally.work += counts.candidates + counts.line_checks;
	}
}

void crafted(Tally &tally) {
	random_scenes(tally);
	no_cells(tally);
	range_edges(tally);
	hostile_references(tally);
}

} // namespace

const KernelCases TARGETING_CASES = { "targeting", on_dump, crafted };
