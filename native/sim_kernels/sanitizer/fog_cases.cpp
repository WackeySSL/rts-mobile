// The FOG kernel's cases for the sanitizer harness (ADR 0013 section 10): core/fog.h's run, and the stamp it is made of, called the
// way bind/kernel_fog.cpp calls it, over states the harness owns as plain std::vector buffers, so that AddressSanitizer sees every
// array at its exact size. The states come from the seed-42 arena (the dumps of tests/sim/native/sanitizer/dump_states.gd) and from
// crafted scenes. Sanitizers judge memory and undefined behaviour, not answers: the discs and flips of the rules are the gdUnit4
// suites' (test_fog*.gd under both implementations, test_fog_kernel.gd), and only what needs no second implementation is checked
// here (no dirty count past its block, a mark is 0 or 1, a row that moved stands on a cell of the map, the cells covered stay within
// what the stamps can reach). The build has no -fwrapv, so the range that core/fog.h records is run at its edges: positions and
// counts at the ends of int32, a tick near 2^62, the cadence at the ends of int64, and masks whose tables hold the ends of int32.
// Plain C++17, no Godot header. MIT.
// Twin: bind/kernel_fog.cpp (call() below is the same fog::run, with the arrays of the World replaced by vectors). A change to that
// call edits call() in the same PR.
#include <algorithm>
#include <string>
#include <vector>

#include "cases.h"
#include "fixed_math.h"
#include "fog.h"
#include "views.h"

namespace {

constexpr int64_t TILE = 1000; // World.MILLI_PER_TILE
constexpr int64_t TICK_TOP = int64_t(1) << 61; // a tick near the top of the range that core/fog.h records

// The World members and the FogGrid that SimKernels::fog reads and writes.
struct State {
	fog::Rules rules;
	int64_t cols = 0, rows = 0, cells = 0, player_count = 0, dirty_capacity = 0;
	std::vector<int32_t> unit_id, owner, type_index, pos_x, pos_y, fog_cell;
	std::vector<int32_t> visible, version, dirty, dirty_count, dirty_full, mask_start, mask_radius, mask_half;
	std::vector<uint8_t> explored, listed;
};

int64_t units_of(const State &state) {
	return static_cast<int64_t>(state.unit_id.size());
}

// The grid of a state as the bind layer hands it to core/.
fog::Grid grid_of(State &state) {
	fog::Grid grid;
	grid.cols = state.cols;
	grid.rows = state.rows;
	grid.cells = state.cells;
	grid.player_count = state.player_count;
	grid.dirty_capacity = state.dirty_capacity;
	grid.visible = view(state.visible);
	grid.dirty = view(state.dirty);
	grid.dirty_count = view(state.dirty_count);
	grid.dirty_full = view(state.dirty_full);
	grid.version = view(state.version);
	grid.explored = view(state.explored);
	grid.listed = view(state.listed);
	grid.mask_start = cview(state.mask_start);
	grid.mask_radius = cview(state.mask_radius);
	grid.mask_half = cview(state.mask_half);
	return grid;
}

// One call of the FOG kernel: the cells the stamps cover, which it adds to stats.
int64_t call(State &state) {
	fog::Grid grid = grid_of(state);
	fog::Rows rows;
	rows.count = units_of(state);
	rows.owner = cview(state.owner);
	rows.type_index = cview(state.type_index);
	rows.pos_x = cview(state.pos_x);
	rows.pos_y = cview(state.pos_y);
	rows.fog_cell = view(state.fog_cell);
	return fog::run(grid, rows, state.rules);
}

// The answers that need no second implementation: a count of cells within what two stamps of a row can reach (unless the mask
// tables are not a mask's, whose half-widths the sum of covered cells takes as they are, like the twin), no dirty count below 0
// or past its block, no mark but 0 and 1, and a row that moved stands on a cell of the map.
void check(const State &state, const std::vector<int32_t> &before, int64_t covered, bool masks, const char *what) {
	const std::string where = std::string("fog: ") + what + ": ";
	if (masks && (covered < 0 || covered > 2 * units_of(state) * std::max<int64_t>(state.cells, 1))) {
		throw Finding(where + std::to_string(covered) + " cells covered");
	}
	for (const int32_t count : state.dirty_count) {
		if (count < 0 || count > state.dirty_capacity) {
			throw Finding(where + "a dirty count of " + std::to_string(count) + " in a block of " + std::to_string(state.dirty_capacity));
		}
	}
	for (const uint8_t mark : state.listed) {
		if (mark > 1) {
			throw Finding(where + "a listed mark of " + std::to_string(mark));
		}
	}
	for (size_t row = 0; row < state.fog_cell.size(); row++) {
		if (state.fog_cell[row] != before[row] && (state.fog_cell[row] < 0 || state.fog_cell[row] >= state.cells)) {
			throw Finding(where + "row " + std::to_string(row) + " moved to the cell " + std::to_string(state.fog_cell[row]));
		}
	}
}

// A call, checked and counted in the tally. `masks` is false for a state whose mask tables are corrupted on purpose: it counts as a
// run, and its cells covered are neither bounded nor part of the work.
void play(State &state, Tally &tally, const char *what, bool masks = true) {
	const std::vector<int32_t> before = state.fog_cell;
	const int64_t covered = call(state);
	check(state, before, covered, masks, what);
	tally.runs += 1;
	tally.work += masks ? covered : 0;
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
		{ "world.fog_cell", &State::fog_cell },
		{ "fog.visible", &State::visible },
		{ "fog.version", &State::version },
		{ "fog.dirty", &State::dirty },
		{ "fog.dirty_count", &State::dirty_count },
		{ "fog.dirty_full", &State::dirty_full },
		{ "fog.mask_start", &State::mask_start },
		{ "fog.mask_radius", &State::mask_radius },
		{ "fog.mask_half", &State::mask_half },
	};
	for (const auto &column : columns) {
		(state.*column.column) = dump.ints(column.name);
	}
	state.explored = dump.bytes("fog.explored");
	state.listed = dump.bytes("fog.listed");
	state.rules.tick = dump.scalar("world.tick");
	state.rules.fog_period_ticks = dump.scalar("world.fog_period_ticks");
	state.rules.pad_mask = static_cast<int64_t>(dump.ints("world.type_sight").size());
	state.cols = dump.scalar("fog.cols");
	state.rows = dump.scalar("fog.rows");
	state.cells = dump.scalar("fog.cells");
	state.player_count = dump.scalar("fog.player_count");
	state.dirty_capacity = dump.scalar("fog.dirty_capacity");
	const size_t units = state.unit_id.size();
	for (const std::vector<int32_t> *column : { &state.owner, &state.type_index, &state.pos_x, &state.pos_y, &state.fog_cell }) {
		if (column->size() != units) {
			throw std::runtime_error("a row column of the dump does not have one entry per unit");
		}
	}
	const size_t players = static_cast<size_t>(state.player_count);
	const size_t blocks = players * static_cast<size_t>(state.cells);
	if (state.visible.size() != blocks || state.explored.size() != blocks || state.listed.size() != blocks) {
		throw std::runtime_error("a fog array of the dump is not one block of the map's cells per player");
	}
	if (state.version.size() != players || state.dirty_count.size() != players || state.dirty_full.size() != players) {
		throw std::runtime_error("a fog count of the dump does not have one entry per player");
	}
	if (state.dirty.size() != players * static_cast<size_t>(state.dirty_capacity)) {
		throw std::runtime_error("the dirty lists of the dump are not one block of the capacity per player");
	}
	if (state.cols * state.rows != state.cells) {
		throw std::runtime_error("the sides of the fog grid of the dump do not make its cells");
	}
	return state;
}

// A table filled with one value, for the states the bind layer cannot refuse (mask tables have no fixed length).
void fill_all(std::vector<int32_t> &table, int32_t value) {
	std::fill(table.begin(), table.end(), value);
}

// Each dump gets the update as dumped, at every residue of the ticks (the turn of a player is `(tick - player + 1) % period`)
// and at a tick near the top of the range, with the cadence across its guards, every row of each owner in turn, every row stamped
// nowhere, on a cell or off the map, every row at the ends of the position range and of each type, every block full, every
// count at the ends of int32, a mask table of the ends of int32, a grid that is not one, and every mark set.
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
	for (const int64_t tick : { int64_t(1) << 40, TICK_TOP, TICK_TOP + 1 }) {
		State state = base;
		state.rules.tick = tick;
		play(state, tally, "late tick");
	}
	for (const int64_t period : { INT64_MIN, int64_t(-1), int64_t(0), int64_t(1), int64_t(2), int64_t(3), int64_t(5), int64_t(1000), INT64_MAX }) {
		State state = base;
		state.rules.fog_period_ticks = period;
		play(state, tally, "periods");
	}
	// From here on every player has its turn on every tick, and every row is stamped nowhere or elsewhere, so each has work.
	State every = base;
	every.rules.fog_period_ticks = 1;
	for (const int32_t owner : { 0, 1, 2, 3, -1, INT32_MAX, INT32_MIN }) {
		State state = every;
		fill_all(state.owner, owner);
		fill_all(state.fog_cell, -1);
		play(state, tally, "owners");
	}
	for (const int32_t stamped : { -1, -5, 0, 1, INT32_MAX, INT32_MIN }) {
		State state = every;
		fill_all(state.fog_cell, stamped);
		play(state, tally, "stamped cells");
	}
	for (const int64_t beyond : { int64_t(0), int64_t(1), int64_t(3000000) }) {
		State state = every;
		fill_all(state.fog_cell, static_cast<int32_t>(base.cells + beyond));
		play(state, tally, "cells off the map");
	}
	for (const int32_t x : { INT32_MAX, INT32_MIN, 0, -1 }) {
		for (const int32_t y : { INT32_MAX, INT32_MIN, 0, -1 }) {
			State state = every;
			fill_all(state.pos_x, x);
			fill_all(state.pos_y, y);
			fill_all(state.fog_cell, -1);
			play(state, tally, "positions");
		}
	}
	for (const int32_t type : { -1, 0, 1, 2, 3, INT32_MAX, INT32_MIN }) {
		State state = every;
		fill_all(state.type_index, type);
		fill_all(state.fog_cell, -1);
		play(state, tally, "types");
	}
	for (const int32_t count : { 0, 1, 4, INT32_MAX }) {
		State state = every;
		fill_all(state.dirty_count, static_cast<int32_t>(std::clamp<int64_t>(count, 0, base.dirty_capacity)));
		fill_all(state.fog_cell, -1);
		play(state, tally, "full blocks");
	}
	for (const int32_t count : { INT32_MAX, INT32_MIN, 1, -1 }) {
		State state = every;
		fill_all(state.visible, count);
		play(state, tally, "counts");
	}
	{
		State state = every;
		std::fill(state.listed.begin(), state.listed.end(), 1);
		play(state, tally, "every cell listed");
	}
	for (const int32_t value : { INT32_MAX, INT32_MIN, -1, 0, 1 }) {
		State state = every;
		fill_all(state.mask_radius, value);
		fill_all(state.fog_cell, -1);
		play(state, tally, "mask radii", false);
		state = every;
		fill_all(state.mask_start, value);
		fill_all(state.fog_cell, -1);
		play(state, tally, "mask starts", false);
		state = every;
		fill_all(state.mask_half, value);
		fill_all(state.fog_cell, -1);
		play(state, tally, "mask half-widths", false);
	}
	for (const int64_t side : { int64_t(0), int64_t(-1), base.cols - 1, base.cols + 1, INT64_MAX, INT64_MIN }) {
		State state = every;
		state.cols = side;
		play(state, tally, "columns");
		state = every;
		state.rows = side;
		play(state, tally, "rows");
	}
	{
		State state = every;
		state.player_count = 0;
		play(state, tally, "no players");
		// More players than the arrays have blocks, and rows of the player past them: ArrayView reads 0 and writes nothing.
		state.player_count = INT64_MAX;
		fill_all(state.owner, INT32_MAX);
		fill_all(state.fog_cell, -1);
		play(state, tally, "players past the arrays");
	}
}

// ---- Crafted cases ----

// The grid FogGrid.configure builds: `cols` x `rows` cells, `players` players, every array zero and a quarter of the cells to a block.
void configure(State &state, int64_t cols, int64_t rows, int64_t players) {
	state.cols = cols;
	state.rows = rows;
	state.cells = cols * rows;
	state.player_count = players;
	state.dirty_capacity = state.cells / 4;
	const size_t blocks = static_cast<size_t>(players * state.cells);
	state.visible.assign(blocks, 0);
	state.explored.assign(blocks, 0);
	state.listed.assign(blocks, 0);
	state.version.assign(static_cast<size_t>(players), 0);
	state.dirty_count.assign(static_cast<size_t>(players), 0);
	state.dirty_full.assign(static_cast<size_t>(players), 0);
	state.dirty.assign(static_cast<size_t>(players * state.dirty_capacity), 0);
	state.mask_start.clear();
	state.mask_radius.clear();
	state.mask_half.clear();
}

// FogGrid.add_mask: the disc of `sight` milli-tiles, a half-width in tiles per row from dy = -radius down.
void add_mask(State &state, int64_t sight) {
	const int64_t radius = sight / TILE;
	state.mask_start.push_back(static_cast<int32_t>(state.mask_half.size()));
	state.mask_radius.push_back(static_cast<int32_t>(radius));
	for (int64_t dy = -radius; dy <= radius; dy++) {
		state.mask_half.push_back(static_cast<int32_t>(fixed_math::isqrt(sight * sight - dy * dy * TILE * TILE) / TILE));
	}
}

// A row of `owner` and `type` on the middle of tile (x, y), last stamped on `stamped`.
void add_row(State &state, int32_t owner, int32_t type, int64_t x, int64_t y, int32_t stamped) {
	state.unit_id.push_back(static_cast<int32_t>(state.unit_id.size() + 1));
	state.owner.push_back(owner);
	state.type_index.push_back(type);
	state.pos_x.push_back(static_cast<int32_t>(x * TILE + TILE / 2));
	state.pos_y.push_back(static_cast<int32_t>(y * TILE + TILE / 2));
	state.fog_cell.push_back(stamped);
}

// The masks of the scenes: a dot, a plus, the shipped sights 6000 and 7000 and a dot again for the pad (the last one).
void add_masks(State &state) {
	for (const int64_t sight : { int64_t(0), int64_t(1000), int64_t(1414), int64_t(6000), int64_t(6500), int64_t(7000), int64_t(0) }) {
		add_mask(state, sight);
	}
	state.rules.pad_mask = static_cast<int64_t>(state.mask_start.size()) - 1;
}

// On maps of every shape (one tile, a row, a column, not square, the arena's) a row of each type and player on each corner, each
// middle of an edge and the centre, stamped, then moved to the opposite corner, then moved off the map's far edge and back.
void edge_scenes(Tally &tally) {
	const int64_t shapes[][2] = { { 30, 30 }, { 20, 14 }, { 1, 1 }, { 1, 9 }, { 9, 1 }, { 7, 5 }, { 64, 64 } };
	for (const auto &shape : shapes) {
		const int64_t cols = shape[0], rows = shape[1];
		State state;
		configure(state, cols, rows, 2);
		add_masks(state);
		state.rules.fog_period_ticks = 1;
		for (int32_t type = 0; type < 8; type++) {
			for (const int64_t x : { int64_t(0), cols / 2, cols - 1 }) {
				for (const int64_t y : { int64_t(0), rows / 2, rows - 1 }) {
					add_row(state, 1 + type % 2, type, x, y, -1);
				}
			}
		}
		play(state, tally, "stamped");
		for (size_t row = 0; row < state.pos_x.size(); row++) {
			state.pos_x[row] = static_cast<int32_t>((cols - 1 - state.pos_x[row] / TILE) * TILE + TILE / 2);
			state.pos_y[row] = static_cast<int32_t>((rows - 1 - state.pos_y[row] / TILE) * TILE + TILE / 2);
		}
		play(state, tally, "moved to the opposite corner");
		for (size_t row = 0; row < state.pos_x.size(); row++) {
			state.pos_x[row] = static_cast<int32_t>(cols * TILE + 7);
			state.pos_y[row] = -3;
		}
		play(state, tally, "off the edges");
		for (size_t row = 0; row < state.pos_x.size(); row++) {
			state.pos_x[row] = static_cast<int32_t>(TILE / 2);
			state.pos_y[row] = static_cast<int32_t>(TILE / 2);
		}
		play(state, tally, "and back");
		// The dirty lists emptied between the updates, as FogUpdate.begin does, and the rows scattered over the map.
		std::fill(state.listed.begin(), state.listed.end(), 0);
		fill_all(state.dirty_count, 0);
		fill_all(state.dirty_full, 0);
		for (size_t row = 0; row < state.pos_x.size(); row++) {
			state.pos_x[row] = static_cast<int32_t>(((row * 7) % static_cast<size_t>(cols)) * TILE);
			state.pos_y[row] = static_cast<int32_t>(((row * 3) % static_cast<size_t>(rows)) * TILE);
		}
		play(state, tally, "scattered");
	}
}

// Blocks that fill: a 7 x 5 map (35 cells, a block of 8) and a 2 x 2 (a block of 1) with many rows of overlapping discs, played
// without emptying the lists, so that a flip finds a full block and a cell that is listed already; a map of one tile has a block of 0.
void full_blocks(Tally &tally) {
	const int64_t shapes[][2] = { { 7, 5 }, { 2, 2 }, { 1, 1 }, { 3, 1 } };
	for (const auto &shape : shapes) {
		State state;
		configure(state, shape[0], shape[1], 3);
		add_masks(state);
		state.rules.fog_period_ticks = 1;
		for (int32_t row = 0; row < 24; row++) {
			add_row(state, 1 + row % 3, row % 6, (row * 5) % shape[0], (row * 3) % shape[1], -1);
		}
		for (int64_t step = 0; step < 6; step++) {
			state.rules.tick = step;
			for (size_t row = 0; row < state.pos_x.size(); row++) {
				const int64_t shift = static_cast<int64_t>(row) + step;
				state.pos_x[row] = static_cast<int32_t>((shift * 5 % shape[0]) * TILE + TILE / 2);
				state.pos_y[row] = static_cast<int32_t>((shift * 3 % shape[1]) * TILE + TILE / 2);
			}
			play(state, tally, "filling");
		}
	}
}

// The ends of the range that core/fog.h records, on a 5 x 5 map: positions at the ends of int32, a tick near 2^62 and the
// cadence at the ends of int64, counts and the version at the ends of int32.
void range_edges(Tally &tally) {
	State state;
	configure(state, 5, 5, 2);
	add_masks(state);
	state.rules.fog_period_ticks = 1;
	const int32_t ends[] = { INT32_MAX, INT32_MIN };
	for (const int32_t x : ends) {
		for (const int32_t y : ends) {
			add_row(state, 1, 3, 2, 2, -1);
			state.pos_x.back() = x;
			state.pos_y.back() = y;
			add_row(state, 2, 5, 2, 2, -1);
			state.pos_x.back() = y;
			state.pos_y.back() = x;
		}
	}
	play(state, tally, "positions at the ends of int32");
	for (const int64_t tick : { TICK_TOP, TICK_TOP + 1, TICK_TOP + 2 }) {
		for (const int64_t period : { int64_t(1), int64_t(3), INT64_MAX, INT64_MIN, TICK_TOP }) {
			State late = state;
			late.rules.tick = tick;
			late.rules.fog_period_ticks = period;
			fill_all(late.fog_cell, -1);
			play(late, tally, "late ticks");
		}
	}
	for (const int32_t value : { INT32_MAX, INT32_MIN }) {
		State counted = state;
		fill_all(counted.visible, value);
		fill_all(counted.version, value);
		fill_all(counted.fog_cell, -1);
		play(counted, tally, "counts and versions");
		// The same rows move on: the unstamp reads what the stamp wrapped.
		for (size_t row = 0; row < counted.pos_x.size(); row++) {
			counted.pos_x[row] = static_cast<int32_t>(TILE / 2);
			counted.pos_y[row] = static_cast<int32_t>(TILE / 2);
		}
		play(counted, tally, "counts that wrapped");
	}
}

// States the bind layer's check cannot refuse: mask tables are not sized by a rule, so a row whose type names a mask past them, or
// whose mask names rows past the half-widths, must read nothing outside them (ArrayView reads 0), and a World with no map, no
// player or sides of a grid that do not make its cells does nothing at all.
void hostile_tables(Tally &tally) {
	State state;
	configure(state, 9, 9, 2);
	add_masks(state);
	state.rules.fog_period_ticks = 1;
	for (int32_t row = 0; row < 12; row++) {
		add_row(state, 1 + row % 2, row, row % 9, (row * 2) % 9, -1);
	}
	// The pad mask past the tables, the half-widths cut short, the starts past the half-widths and negative.
	State past = state;
	past.rules.pad_mask = 40;
	play(past, tally, "pad mask past the tables", false);
	State short_half = state;
	short_half.mask_half.resize(5);
	play(short_half, tally, "half-widths cut short", false);
	State no_masks = state;
	no_masks.mask_start.clear();
	no_masks.mask_radius.clear();
	no_masks.mask_half.clear();
	play(no_masks, tally, "no masks", false);
	State no_map;
	configure(no_map, 0, 0, 0);
	add_masks(no_map);
	add_row(no_map, 1, 0, 0, 0, -1);
	play(no_map, tally, "no map");
	// The stamp itself, called out of its contract: no columns to divide by, a player, a cell and a mask that are none of the
	// grid's, and a delta that is none of +1 and -1. It writes nothing outside the arrays (ArrayView) and divides by nothing.
	fog::Grid empty = grid_of(no_map);
	fog::stamp(empty, 1, 0, 0, 1);
	fog::stamp(empty, 7, -3, 99, -1);
	fog::Grid grid = grid_of(state);
	for (const int64_t player : { int64_t(0), int64_t(1), int64_t(3), int64_t(-5), INT64_MAX / 4096 }) {
		for (const int64_t cell : { int64_t(-1), int64_t(0), int64_t(80), int64_t(81), int64_t(1) << 40, -(int64_t(1) << 40) }) {
			for (const int64_t mask : { int64_t(-1), int64_t(0), int64_t(6), int64_t(7), int64_t(1) << 40 }) {
				fog::stamp(grid, player, cell, mask, 1);
				fog::stamp(grid, player, cell, mask, -1);
				fog::stamp(grid, player, cell, mask, 3);
				tally.runs += 3;
			}
		}
	}
}

void crafted(Tally &tally) {
	edge_scenes(tally);
	full_blocks(tally);
	range_edges(tally);
	hostile_tables(tally);
}

} // namespace

const KernelCases FOG_CASES = { "fog", on_dump, crafted };
