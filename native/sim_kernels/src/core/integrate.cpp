// The INTEGRATE kernel's rules, a mirror of Movement.integrate in game/sim/Movement.gd: see integrate.h. MIT.
#include "integrate.h"

#include "fixed_math.h"

namespace integrate {

namespace {

constexpr int64_t MILLI_PER_TILE = 1000; // World.MILLI_PER_TILE
constexpr int64_t TILE_CENTRE = 500; // World.TILE_CENTRE
constexpr int64_t NO_BOUND = 0x7FFFFFFF; // Movement.NO_BOUND
constexpr int64_t NO_NEXT = -2; // Movement.NO_NEXT
constexpr int64_t MOVE_CLASSES = 3; // World.MoveClass.size()
constexpr int64_t ORDER_IDLE = 0; // World.Order.IDLE
constexpr int64_t ORDER_ATTACK = 3; // World.Order.ATTACK
constexpr int64_t NAV_NONE = 0; // World.NavMode.NONE
constexpr int64_t NAV_DIRECT = 1; // World.NavMode.DIRECT
constexpr int64_t NAV_FIELD = 2; // World.NavMode.FIELD
constexpr int64_t NAV_HOLD = 3; // World.NavMode.HOLD
constexpr int64_t NAV_CHASE = 4; // World.NavMode.CHASE

// GDScript's clampi: the lower bound is tested first, as in Godot's CLAMP.
int64_t clamp(int64_t value, int64_t low, int64_t high) {
	return value < low ? low : (value > high ? high : value);
}

// One call of Movement.integrate: the World's columns and rules, and the slots of the flow cache.
class Pass {
public:
	Pass(const Rows &rows, const Types &types, const ArrayView<const uint8_t> &move_cost, const Rules &rules, flow::Keys &keys, Slots &slots) :
			rows_(rows), types_(types), move_cost_(move_cost), rules_(rules), keys_(keys), slots_(slots) {}

	void run();

private:
	Rows rows_;
	Types types_;
	ArrayView<const uint8_t> move_cost_;
	Rules rules_;
	flow::Keys &keys_;
	Slots &slots_;

	int64_t cell_of(int64_t x, int64_t y) const;
	bool is_passable(int64_t cell, int64_t move_class) const;
	int64_t acquire(int64_t goal_cell, int64_t move_class);
	void end_order(int64_t row);
	bool take_own_field(int64_t row, int64_t slot, int64_t move_class);
	int64_t rekey(int64_t row, int64_t slot, int64_t move_class);
	void refresh_next(int64_t row, int64_t cell, int64_t move_class);
};

// World.cell_of: the cell holding the point, never outside the map; 0 with no map.
int64_t Pass::cell_of(int64_t x, int64_t y) const {
	if (rules_.map_cols == 0) {
		return 0;
	}
	const int64_t column = clamp(x / MILLI_PER_TILE, 0, rules_.map_cols - 1);
	const int64_t line = clamp(y / MILLI_PER_TILE, 0, rules_.map_rows - 1);
	return line * rules_.map_cols + column;
}

// World.is_passable: true with no map, false outside it and for a class that does not exist.
bool Pass::is_passable(int64_t cell, int64_t move_class) const {
	if (rules_.map_cols == 0) {
		return true;
	}
	const int64_t cells = rules_.map_cols * rules_.map_rows;
	if (cell < 0 || cell >= cells || move_class < 0 || move_class >= MOVE_CLASSES) {
		return false;
	}
	return move_cost_.get(move_class * cells + cell) > 0;
}

// FlowCache.acquire, with the clear of a recycled slot that the slot objects do.
int64_t Pass::acquire(int64_t goal_cell, int64_t move_class) {
	const flow::Acquired got = flow::acquire(keys_, goal_cell, move_class, rules_.map_version, rules_.tick);
	if (got.recycled) {
		slots_.recycle(got.slot);
	}
	return got.slot;
}

// Movement._end_order: IDLE where it stands, with its navigation state cleared.
void Pass::end_order(int64_t row) {
	rows_.order.set(row, ORDER_IDLE);
	rows_.group_cell.set(row, -1);
	rows_.nav_mode.set(row, NAV_NONE);
	rows_.nav_cell.set(row, -1);
	rows_.field.set(row, -1);
	rows_.nav_next.set(row, -1);
	rows_.best_dist.set(row, flow::UNREACHED);
	rows_.stall.set(row, 0);
}

// Movement._take_own_field: a unit whose complete field names no next tile, on a field keyed on a tile other than its
// goal's, takes the field of its goal's tile (a fresh best distance and stall count) and returns true.
bool Pass::take_own_field(int64_t row, int64_t slot, int64_t move_class) {
	const int64_t own = cell_of(rows_.goal_x.get(row), rows_.goal_y.get(row));
	if (keys_.key_goal.get(slot) == own) {
		return false;
	}
	const int64_t fresh = acquire(own, move_class);
	if (fresh < 0) {
		return false;
	}
	rows_.field.set(row, fresh);
	rows_.best_dist.set(row, flow::UNREACHED);
	rows_.stall.set(row, 0);
	return true;
}

// Movement._rekey: an ATTACK unit's goal follows its target; once the goal is more than attack_rekey_milli from the
// centre of the tile its field is keyed on, the unit takes the field of its goal's tile (the old one with no free slot).
int64_t Pass::rekey(int64_t row, int64_t slot, int64_t move_class) {
	const int64_t cols = rules_.map_cols;
	const int64_t key = keys_.key_goal.get(slot);
	const int64_t dx = rows_.goal_x.get(row) - (key % cols * MILLI_PER_TILE + TILE_CENTRE);
	const int64_t dy = rows_.goal_y.get(row) - (key / cols * MILLI_PER_TILE + TILE_CENTRE);
	const int64_t limit = rules_.attack_rekey_milli;
	if (dx * dx + dy * dy <= limit * limit) {
		return slot;
	}
	const int64_t goal = cell_of(rows_.goal_x.get(row), rows_.goal_y.get(row));
	const int64_t fresh = acquire(goal, move_class);
	if (fresh < 0) {
		return slot;
	}
	rows_.field.set(row, fresh);
	return fresh;
}

// Movement._refresh_next: sets nav_next of FIELD unit `row`, standing in `cell`, from its field: the neighbour tile the
// field names, NO_NEXT when the field is complete and names none, -1 while it is pending. The field's own key counts as
// none when its tile is blocked for the unit's class now.
void Pass::refresh_next(int64_t row, int64_t cell, int64_t move_class) {
	int64_t slot = rows_.field.get(row);
	if (rows_.order.get(row) == ORDER_ATTACK) {
		slot = rekey(row, slot, move_class);
	}
	const flow::Served field = slots_.served(slot);
	int64_t next = -1;
	if (field.complete) {
		next = flow::best_neighbour(field, cell);
		if (next == keys_.key_goal.get(slot) && !is_passable(next, move_class)) {
			next = -1;
		}
		if (next < 0) {
			next = NO_NEXT;
			if (take_own_field(row, slot, move_class)) {
				next = -1;
			}
		}
	}
	rows_.nav_next.set(row, next);
}

void Pass::run() {
	const int64_t count = rows_.unit_id.size();
	const int64_t slot_count = slots_.count();
	const int64_t cols = rules_.map_cols;
	const int64_t cells = cols * rules_.map_rows;
	const int64_t period = rules_.line_check_period_ticks > 1 ? rules_.line_check_period_ticks : 1;
	const int64_t tick = rules_.tick;
	int64_t max_x = NO_BOUND;
	int64_t max_y = NO_BOUND;
	if (cells > 0) {
		max_x = (rules_.map_w < cols * MILLI_PER_TILE ? rules_.map_w : cols * MILLI_PER_TILE) - 1;
		max_y = (rules_.map_h < rules_.map_rows * MILLI_PER_TILE ? rules_.map_h : rules_.map_rows * MILLI_PER_TILE) - 1;
	}
	for (int64_t row = 0; row < count; row++) {
		const int64_t order = rows_.order.get(row);
		int64_t step_x = rows_.intent_x.get(row) + rows_.push_x.get(row);
		int64_t step_y = rows_.intent_y.get(row) + rows_.push_y.get(row);
		if (order == ORDER_IDLE && step_x == 0 && step_y == 0) {
			continue;
		}
		const int64_t x = rows_.pos_x.get(row);
		const int64_t y = rows_.pos_y.get(row);
		int64_t mode = rows_.nav_mode.get(row);
		const int64_t type = rows_.type_index.get(row);
		const int64_t move_class = types_.move_class.get(type);
		// The cell of a FIELD unit with a slot; -1 for any other unit.
		int64_t cell = -1;
		if (mode == NAV_FIELD && order != ORDER_IDLE && cells > 0 && rows_.field.get(row) >= 0 && rows_.field.get(row) < slot_count) {
			cell = clamp(y, 0, max_y) / MILLI_PER_TILE * cols + clamp(x, 0, max_x) / MILLI_PER_TILE;
			if ((rows_.nav_next.get(row) == -1 || (tick + rows_.unit_id.get(row)) % period == 0) && slots_.complete(rows_.field.get(row))) {
				refresh_next(row, cell, move_class);
			}
		}
		if (order != ORDER_IDLE && order != ORDER_ATTACK && mode != NAV_HOLD && mode != NAV_CHASE) {
			const int64_t speed = types_.speed.get(type);
			const int64_t dx = rows_.goal_x.get(row) - x;
			const int64_t dy = rows_.goal_y.get(row) - y;
			const int64_t to_goal = dx * dx + dy * dy;
			if (to_goal <= speed * speed) {
				end_order(row);
				mode = NAV_NONE;
			} else if (speed > 0 && ((mode == NAV_DIRECT && rows_.nav_cell.get(row) >= 0) || (cell >= 0 && rows_.nav_next.get(row) == NO_NEXT))) {
				const int64_t span = types_.spacing.get(type) * rules_.stall_range_spacings;
				if (mode == NAV_FIELD || to_goal <= span * span) {
					const int64_t nearest = fixed_math::isqrt(to_goal);
					if (nearest < rows_.best_dist.get(row)) {
						rows_.best_dist.set(row, nearest);
						rows_.stall.set(row, 0);
					} else {
						rows_.stall.set(row, rows_.stall.get(row) + 1);
						if (rows_.stall.get(row) >= rules_.stall_ticks) {
							rows_.goal_x.set(row, x);
							rows_.goal_y.set(row, y);
							rows_.intent_x.set(row, 0);
							rows_.intent_y.set(row, 0);
							step_x = rows_.push_x.get(row);
							step_y = rows_.push_y.get(row);
							end_order(row);
							mode = NAV_NONE;
						}
					}
				}
			}
		}
		if (step_x == 0 && step_y == 0) {
			continue;
		}
		int64_t new_x = clamp(x + step_x, 0, max_x);
		int64_t new_y = clamp(y + step_y, 0, max_y);
		if (cells > 0) {
			const int64_t base = move_class * cells;
			if (move_cost_.get(base + (new_y / MILLI_PER_TILE) * cols + new_x / MILLI_PER_TILE) == 0) {
				const int64_t own_column = clamp(x, 0, max_x) / MILLI_PER_TILE;
				const int64_t own_line = clamp(y, 0, max_y) / MILLI_PER_TILE;
				if (move_cost_.get(base + own_line * cols + new_x / MILLI_PER_TILE) != 0) {
					new_y = y;
				} else if (move_cost_.get(base + (new_y / MILLI_PER_TILE) * cols + own_column) != 0) {
					new_x = x;
				} else {
					new_x = x;
					new_y = y;
				}
				if (new_x == x && new_y == y && mode == NAV_DIRECT) {
					rows_.nav_cell.set(row, -1);
				}
			}
		}
		rows_.pos_x.set(row, new_x);
		rows_.pos_y.set(row, new_y);
		if (cell >= 0 && mode == NAV_FIELD) {
			const int64_t entered = new_y / MILLI_PER_TILE * cols + new_x / MILLI_PER_TILE;
			if (entered != cell && slots_.complete(rows_.field.get(row))) {
				refresh_next(row, entered, move_class);
			}
		}
	}
}

} // namespace

void run(const Rows &rows, const Types &types, const ArrayView<const uint8_t> &move_cost, const Rules &rules, flow::Keys &keys, Slots &slots) {
	Pass pass(rows, types, move_cost, rules, keys, slots);
	pass.run();
}

} // namespace integrate
