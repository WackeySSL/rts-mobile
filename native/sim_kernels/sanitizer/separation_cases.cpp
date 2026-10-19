// The SEPARATION kernel's cases for the sanitizer harness (ADR 0013 section 10): core/separation.h's run, called the way
// bind/kernel_separation.cpp calls it, over states the harness owns as plain std::vector buffers, so that AddressSanitizer
// sees every array at its exact size. The states come from the seed-42 arena (the dumps of
// tests/sim/native/sanitizer/dump_states.gd, with the grid built afresh from the dumped positions) and from crafted
// scenes. Sanitizers judge memory and undefined behaviour, not answers: the pushes of the rules are the gdUnit4 suites'
// (test_separation*.gd, test_separation_kernel*.gd and the lockstep of P39n2), and only what needs no second
// implementation is checked here (no push past the cap, nothing written past the rows, a grid with no cells gives
// nothing). The build has no -fwrapv, so the ranges that core/separation.h records are run at their edges: positions of
// 10^9, the largest reach and the largest divisor of the data's radii. Plain C++17, no Godot header. MIT.
// Twin: bind/kernel_separation.cpp (call() below is the same separation::run, with the arrays of the World replaced by
// vectors). A change to that call edits call() in the same PR.
#include <algorithm>
#include <climits>
#include <iterator>
#include <string>
#include <vector>

#include "cases.h"
#include "separation.h"
#include "views.h"

namespace {

constexpr int64_t EDGE = 1000000000; // the range of positions that core/separation.h records
constexpr int64_t DATA_REACH = 1000; // two radii of 500, the largest of data/units
constexpr int64_t DATA_DIVISOR = 3037000; // the largest divisor for that reach: 1000 * 3037000 <= 3037000499
constexpr int64_t HUGE_REACH = 2000000; // two radii of 1,000,000 (reach^3 still fits)
constexpr int64_t HUGE_DIVISOR = 1518; // the largest divisor for that reach

// The World members and the separation grid that SimKernels::separation reads and writes.
struct State {
	separation::Rules rules;
	int64_t cols = 0, rows = 0, cell_milli = 1000;
	std::vector<int32_t> type_index, pos_x, pos_y, intent_x, intent_y, push_x, push_y, radius, head, next;
};

int64_t units_of(const State &state) {
	return static_cast<int64_t>(state.pos_x.size());
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

// One call of the SEPARATION kernel: the units looked at.
int64_t call(State &state) {
	separation::Rows rows;
	rows.count = units_of(state);
	rows.type_index = cview(state.type_index);
	rows.pos_x = cview(state.pos_x);
	rows.pos_y = cview(state.pos_y);
	rows.intent_x = cview(state.intent_x);
	rows.intent_y = cview(state.intent_y);
	rows.push_x = view(state.push_x);
	rows.push_y = view(state.push_y);
	separation::Types types;
	types.radius = cview(state.radius);
	separation::Grid grid;
	grid.cols = state.cols;
	grid.rows = state.rows;
	grid.cell_milli = state.cell_milli;
	grid.head = cview(state.head);
	grid.next = cview(state.next);
	return separation::run(rows, types, grid, state.rules);
}

// The answers that need no second implementation: no push past the cap, none written past the rows, and the pushes of a
// grid with no cells (or a cell side below 1) all 0 with no look.
void check(const State &state, int64_t looked, const char *what) {
	const int64_t cap = std::max<int64_t>(state.rules.push_max, 0);
	const bool empty = state.cols < 1 || state.rows < 1 || state.cell_milli < 1;
	if (looked < 0 || (empty && looked != 0)) {
		throw Finding(std::string("separation: ") + what + ": " + std::to_string(looked) + " looks");
	}
	for (size_t at = 0; at < state.push_x.size(); at++) {
		const int64_t x = state.push_x[at];
		const int64_t y = state.push_y[at];
		const bool past = static_cast<int64_t>(at) >= units_of(state);
		if (x > cap || x < -cap || y > cap || y < -cap || ((past || empty) && (x != 0 || y != 0))) {
			throw Finding(std::string("separation: ") + what + ": row " + std::to_string(at) + " is pushed (" + std::to_string(x) + ", " + std::to_string(y) + ")");
		}
	}
}

// A call from a clean slate of garbage pushes (every row must be written), counted in the tally.
void play(State &state, Tally &tally, const char *what) {
	rebuild(state);
	std::fill(state.push_x.begin(), state.push_x.end(), 99);
	std::fill(state.push_y.begin(), state.push_y.end(), -99);
	const int64_t looked = call(state);
	check(state, looked, what);
	tally.runs += 1;
	tally.work += looked;
}

// ---- The states of the arena dumps ----

// The state of a dump, read the way the bind layer's check_world would: a wrong length is refused.
State from_dump(const Dump &dump) {
	State state;
	const struct {
		const char *name;
		std::vector<int32_t> State::*column;
	} columns[] = {
		{ "world.type_index", &State::type_index },
		{ "world.pos_x", &State::pos_x },
		{ "world.pos_y", &State::pos_y },
		{ "world.intent_x", &State::intent_x },
		{ "world.intent_y", &State::intent_y },
		{ "world.push_x", &State::push_x },
		{ "world.push_y", &State::push_y },
		{ "world.type_radius", &State::radius },
		{ "sep.head", &State::head },
		{ "sep.next", &State::next },
	};
	for (const auto &column : columns) {
		(state.*column.column) = dump.ints(column.name);
	}
	state.rules.neighbours = dump.scalar("world.separation_neighbours");
	state.rules.scan = dump.scalar("world.separation_scan");
	state.rules.idle_share = dump.scalar("world.separation_idle_share");
	state.rules.push_max = dump.scalar("world.separation_push_max");
	state.rules.coincident_divisor = dump.scalar("world.separation_coincident_divisor");
	state.cols = dump.scalar("sep.cols");
	state.rows = dump.scalar("sep.rows");
	state.cell_milli = dump.scalar("sep.cell_milli");
	const int64_t units = dump.scalar("world.unit_count");
	if (units_of(state) != units || static_cast<int64_t>(state.type_index.size()) != units) {
		throw std::runtime_error("a row column of the dump does not have one entry per unit");
	}
	if (static_cast<int64_t>(state.intent_x.size()) < units || state.intent_y.size() != state.intent_x.size() || state.push_x.size() != state.intent_x.size() || state.push_y.size() != state.intent_x.size()) {
		throw std::runtime_error("a scratch column of the dump is shorter than the rows");
	}
	if (static_cast<int64_t>(state.head.size()) != state.cols * state.rows || state.next.size() != state.intent_x.size()) {
		throw std::runtime_error("the separation grid of the dump does not have the size of its cells and rows");
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

// Each dump gets the pass as dumped, the caps and the guards across their edges, every unit moving and none, and grids of
// other cells (a unit in the middle of a long list, the scan cut at the border of the grid).
void on_dump(const Dump &dump, Tally &tally) {
	const State base = from_dump(dump);
	{
		State state = base;
		play(state, tally, "as dumped");
	}
	for (const int64_t neighbours : { int64_t(-1), int64_t(0), int64_t(1), int64_t(3), int64_t(8), int64_t(1000) }) {
		for (const int64_t scan : { int64_t(-1), int64_t(0), int64_t(1), int64_t(5), int64_t(16), int64_t(1000) }) {
			State state = base;
			state.rules.neighbours = neighbours;
			state.rules.scan = scan;
			play(state, tally, "caps");
		}
	}
	for (const int64_t share : { int64_t(-1), int64_t(0), int64_t(50), int64_t(100), int64_t(101), INT64_MIN, INT64_MAX }) {
		State state = base;
		state.rules.idle_share = share;
		play(state, tally, "idle share");
	}
	for (const int64_t cap : { INT64_MIN, int64_t(-3), int64_t(0), int64_t(1), int64_t(60), int64_t(1000000000), INT64_MAX }) {
		State state = base;
		state.rules.push_max = cap;
		play(state, tally, "push cap");
	}
	// The dumped radii are at most 500, so every divisor up to DATA_DIVISOR is in the recorded range.
	for (const int64_t divisor : { INT64_MIN, int64_t(-1), int64_t(0), int64_t(1), int64_t(2), int64_t(4), int64_t(1000), DATA_DIVISOR }) {
		State state = base;
		state.rules.coincident_divisor = divisor;
		play(state, tally, "divisor");
	}
	for (const int32_t intent : { 0, 120, -7 }) {
		State state = base;
		std::fill(state.intent_x.begin(), state.intent_x.end(), intent);
		std::fill(state.intent_y.begin(), state.intent_y.end(), intent == 0 ? 0 : -intent);
		play(state, tally, "intents");
	}
	for (const int64_t side : { int64_t(500), int64_t(3000), int64_t(7000), int64_t(64000) }) {
		State state = regridded(base, side);
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

// A scene: a grid of `cols` x `rows` cells of 1000, four types of radius 0 to 500, and `units` rows scattered over the map
// and a margin of 3000 around it, every fifth on the point of an earlier row or a few milli from it, and every third moving.
State make_scene(Stream &stream, int64_t cols, int64_t rows, int64_t units) {
	State state;
	state.cols = cols;
	state.rows = rows;
	state.radius = { 400, 300, 0, 500 };
	state.rules = { 8, 16, 75, 60, 4 };
	state.head.assign(static_cast<size_t>(cols * rows), -1);
	const size_t scratch = static_cast<size_t>(units + 8);
	for (std::vector<int32_t> *column : { &state.push_x, &state.push_y, &state.intent_x, &state.intent_y, &state.next }) {
		column->assign(scratch, column == &state.next ? -1 : 0);
	}
	for (int64_t row = 0; row < units; row++) {
		const size_t at = static_cast<size_t>(row);
		state.type_index.push_back(static_cast<int32_t>(stream.next(4)));
		if (row > 0 && row % 5 == 0) {
			const size_t earlier = static_cast<size_t>(stream.next(row));
			state.pos_x.push_back(state.pos_x[earlier] + static_cast<int32_t>(stream.next(8) - 3));
			state.pos_y.push_back(state.pos_y[earlier] + static_cast<int32_t>(stream.next(8) - 3));
		} else {
			state.pos_x.push_back(static_cast<int32_t>(stream.next(cols * 1000 + 6000) - 3000));
			state.pos_y.push_back(static_cast<int32_t>(stream.next(rows * 1000 + 6000) - 3000));
		}
		if (row % 3 == 0) {
			state.intent_x[at] = static_cast<int32_t>(stream.next(241) - 120);
			state.intent_y[at] = static_cast<int32_t>(stream.next(241) - 120);
		}
	}
	return state;
}

// Maps of every shape the scan tells apart (one cell, a row, a column, wide, tall), crowds of every size, and random
// rules around the shipped ones and across their guards.
void random_scenes(Tally &tally) {
	const int64_t shapes[][2] = { { 1, 1 }, { 1, 9 }, { 9, 1 }, { 3, 2 }, { 20, 8 }, { 64, 64 } };
	Stream stream = { 39 };
	for (const auto &shape : shapes) {
		for (const int64_t units : { int64_t(0), int64_t(1), int64_t(2), int64_t(9), int64_t(40), int64_t(150) }) {
			State state = make_scene(stream, shape[0], shape[1], units);
			for (int64_t round = 0; round < 6; round++) {
				state.rules.neighbours = stream.next(20) - 2;
				state.rules.scan = stream.next(40) - 2;
				state.rules.idle_share = stream.next(130) - 15;
				state.rules.push_max = stream.next(210) - 10;
				state.rules.coincident_divisor = stream.next(14) - 3;
				play(state, tally, "random");
			}
		}
	}
}

// A grid with no cells (an empty map, or no columns or no rows) and a cell side below 1: every push 0 and no look. The
// view of a grid whose head is empty must never be indexed.
void no_cells(Tally &tally) {
	Stream stream = { 5 };
	const struct {
		int64_t cols, rows, side;
	} grids[] = { { 0, 0, 1000 }, { 0, 8, 1000 }, { 20, 0, 1000 }, { 20, 8, 0 }, { 20, 8, -1000 }, { 20, 8, INT64_MIN } };
	for (const auto &grid : grids) {
		State state = make_scene(stream, 20, 8, 30);
		state.cols = grid.cols;
		state.rows = grid.rows;
		state.cell_milli = grid.side;
		state.head.assign(static_cast<size_t>(grid.cols * grid.rows), -1);
		play(state, tally, "no cells");
	}
}

// The ranges that core/separation.h records, at their edges, where the sanitizer build aborts on an overflow. Positions at
// both ends of the range, in a map of one cell so that every unit scans every other; the data's largest reach with
// the largest divisor it allows, and the largest reach with the divisor it allows.
void range_edges(Tally &tally) {
	State corners;
	corners.cols = corners.rows = 1;
	corners.radius = { 500 };
	corners.rules = { 8, 16, 75, 60, 4 };
	corners.head.assign(1, -1);
	for (const int64_t x : { -EDGE, int64_t(0), EDGE }) {
		for (const int64_t y : { -EDGE, int64_t(0), EDGE }) {
			corners.type_index.push_back(0);
			corners.pos_x.push_back(static_cast<int32_t>(x));
			corners.pos_y.push_back(static_cast<int32_t>(y));
		}
	}
	for (const int64_t at : { -EDGE, EDGE }) {
		corners.type_index.push_back(0);
		corners.pos_x.push_back(static_cast<int32_t>(at));
		corners.pos_y.push_back(static_cast<int32_t>(at));
		corners.type_index.push_back(0);
		corners.pos_x.push_back(static_cast<int32_t>(at == EDGE ? at - 100 : at + 100));
		corners.pos_y.push_back(static_cast<int32_t>(at));
	}
	const size_t scratch = corners.pos_x.size() + 8;
	for (std::vector<int32_t> *column : { &corners.push_x, &corners.push_y, &corners.intent_x, &corners.intent_y, &corners.next }) {
		column->assign(scratch, column == &corners.next ? -1 : 0);
	}
	corners.intent_x[1] = 120;
	play(corners, tally, "corners");

	// A square of units 7 apart, so that the pairs take every distance from 0 to 999 milli (the farthest overlap of the
	// data's radii), with the divisor that makes d2 * divisor * divisor largest.
	Stream stream = { 8 };
	State square = make_scene(stream, 12, 12, 0);
	square.rules.coincident_divisor = DATA_DIVISOR;
	square.rules.push_max = 1000000;
	for (int64_t index = 0; index < 150; index++) {
		square.type_index.push_back(3);
		square.pos_x.push_back(static_cast<int32_t>(5000 + (index % 15) * 7 + (index / 100) * 999));
		square.pos_y.push_back(static_cast<int32_t>(5000 + (index / 15) * 7));
	}
	// The farthest overlap, alone in its cell: 999 apart, d2 = 998001, the largest product with that divisor.
	for (const int32_t x : { 9000, 9999 }) {
		square.type_index.push_back(3);
		square.pos_x.push_back(x);
		square.pos_y.push_back(9000);
	}
	for (std::vector<int32_t> *column : { &square.push_x, &square.push_y, &square.intent_x, &square.intent_y, &square.next }) {
		column->assign(square.pos_x.size() + 8, column == &square.next ? -1 : 0);
	}
	square.rules.neighbours = 1000;
	square.rules.scan = 1000;
	play(square, tally, "largest divisor of the data");
	if (square.rules.coincident_divisor * DATA_REACH > 3037000499) {
		throw Finding("separation: DATA_DIVISOR is past the recorded range");
	}

	// The largest reach: radii of 10^6 and units a few 10^6 apart, with the divisor that reach allows.
	State wide;
	wide.cols = wide.rows = 1;
	wide.radius = { 1000000 };
	wide.rules = { 1000, 1000, 75, 1000000000, HUGE_DIVISOR };
	wide.head.assign(1, -1);
	for (int64_t index = 0; index < 40; index++) {
		wide.type_index.push_back(0);
		wide.pos_x.push_back(static_cast<int32_t>((index % 8) * 520000));
		wide.pos_y.push_back(static_cast<int32_t>((index / 8) * 400000));
	}
	for (std::vector<int32_t> *column : { &wide.push_x, &wide.push_y, &wide.intent_x, &wide.intent_y, &wide.next }) {
		column->assign(wide.pos_x.size() + 8, column == &wide.next ? -1 : 0);
	}
	play(wide, tally, "largest reach");
	if (wide.rules.coincident_divisor * HUGE_REACH > 3037000499) {
		throw Finding("separation: HUGE_DIVISOR is past the recorded range");
	}
}

// Type numbers and list entries that name nothing: a type past the table, negative or at both ends of int32, and heads and
// links that name rows past the units (inside and outside the arrays). The pass reads them through ArrayView (0 outside),
// so it finishes and AddressSanitizer stays quiet. The caps are small, because a list of such links may run in a circle
// (a cycle that visits only the unit itself would not end, in the twin either; SpatialGrid never writes one).
void hostile_references(Tally &tally) {
	Stream stream = { 6 };
	const int32_t hostile[] = { -1, 0, 1, 3, 4, 100, INT32_MAX, INT32_MIN, -2, 8 };
	for (size_t shift = 0; shift < std::size(hostile); shift++) {
		State state = make_scene(stream, 12, 8, 40);
		state.rules.scan = 30;
		state.rules.neighbours = 12;
		for (size_t row = 0; row < state.type_index.size(); row++) {
			state.type_index[row] = hostile[(row + shift) % std::size(hostile)];
		}
		const size_t units = state.pos_x.size();
		rebuild(state);
		std::fill(state.push_x.begin(), state.push_x.end(), 99);
		std::fill(state.push_y.begin(), state.push_y.end(), -99);
		for (size_t cell = 0; cell < state.head.size(); cell += 3) {
			state.head[cell] = hostile[(cell + 2 * shift) % std::size(hostile)];
		}
		for (size_t at = units; at < state.next.size(); at++) {
			state.next[at] = hostile[(at + shift) % std::size(hostile)];
			if (state.next[at] == static_cast<int32_t>(at)) {
				state.next[at] = -1;
			}
		}
		for (size_t at = 0; at < units; at += 4) {
			state.next[at] = hostile[(3 * at + shift) % std::size(hostile)];
			if (state.next[at] == static_cast<int32_t>(at)) {
				state.next[at] = -1;
			}
		}
		const int64_t looked = call(state);
		check(state, looked, "hostile references");
		tally.runs += 1;
		tally.work += looked;
	}
}

void crafted(Tally &tally) {
	random_scenes(tally);
	no_cells(tally);
	range_edges(tally);
	hostile_references(tally);
}

} // namespace

const KernelCases SEPARATION_CASES = { "separation", on_dump, crafted };
