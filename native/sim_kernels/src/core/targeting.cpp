// The TARGETING kernel's rules, a mirror of Targeting.run and Targeting._engage in game/sim/Targeting.gd: see targeting.h. MIT.
#include "targeting.h"

#include "fixed_math.h"
#include "flow.h"

namespace targeting {

namespace {

constexpr int64_t ATTACK_MOVE = 1; // Targeting.ATTACK_MOVE (World.Order.ATTACK_MOVE)
constexpr int64_t IDLE = 0; // Targeting.IDLE (World.Order.IDLE)
constexpr int64_t ATTACK = 3; // Targeting.ATTACK (World.Order.ATTACK)
constexpr int64_t NONE = 0; // Targeting.NONE (World.NavMode.NONE)
constexpr int64_t DIRECT = 1; // Targeting.DIRECT (World.NavMode.DIRECT)
constexpr int64_t HOLD = 3; // Targeting.HOLD (World.NavMode.HOLD)
constexpr int64_t CHASE = 4; // Targeting.CHASE (World.NavMode.CHASE)
constexpr int64_t ARMOUR_CLASSES = 4; // World.Armour.size()

// GDScript's clampi: the lower bound is tested first, as in Godot's CLAMP.
int64_t clamp(int64_t value, int64_t low, int64_t high) {
	return value < low ? low : (value > high ? high : value);
}

// PackedInt32Array.bsearch(value) with `before` at its default: the first index whose element is not below `value`, by the
// bisection of Godot's SearchArray, so that the answer is the engine's even for a column that is not sorted.
int64_t bsearch(const ArrayView<const int32_t> &values, int64_t value) {
	int64_t low = 0;
	int64_t high = values.size();
	while (low < high) {
		const int64_t middle = (low + high) >> 1;
		if (values.get(middle) < value) {
			low = middle + 1;
		} else {
			high = middle;
		}
	}
	return low;
}

// One call of Targeting.run: the World's columns, tables and rules.
class Pass {
public:
	Pass(const Rows &rows, const Types &types, const Weapons &weapons, const Grid &grid, const Map &map, const Rules &rules) :
			rows_(rows), types_(types), weapons_(weapons), grid_(grid), map_(map), rules_(rules) {}

	int64_t acquire();
	int64_t engage();

private:
	Rows rows_;
	Types types_;
	Weapons weapons_;
	Grid grid_;
	Map map_;
	Rules rules_;

	void reset_row(int64_t row, int64_t mode);
};

// Movement.reset_row: the navigation state combat gives a unit when it changes the unit's mode.
void Pass::reset_row(int64_t row, int64_t mode) {
	rows_.nav_mode.set(row, mode);
	rows_.nav_cell.set(row, -1);
	rows_.field.set(row, -1);
	rows_.nav_next.set(row, -1);
	rows_.best_dist.set(row, flow::UNREACHED);
	rows_.stall.set(row, 0);
}

// Targeting.run before its call of _engage: returns the rows the scans looked at.
int64_t Pass::acquire() {
	const ArrayView<const int32_t> ids = rows_.unit_id;
	const ArrayView<const int32_t> owners = rows_.owner;
	const ArrayView<const int32_t> types = rows_.type_index;
	const ArrayView<const int32_t> pos_x = rows_.pos_x;
	const ArrayView<const int32_t> pos_y = rows_.pos_y;
	ArrayView<int32_t> goal_x = rows_.goal_x;
	ArrayView<int32_t> goal_y = rows_.goal_y;
	ArrayView<int32_t> orders = rows_.order;
	ArrayView<int32_t> order_targets = rows_.order_target;
	ArrayView<int32_t> targets = rows_.target;
	const ArrayView<const int32_t> type_armour = types_.armour;
	const ArrayView<const int32_t> type_acquire = types_.acquire;
	const ArrayView<const int32_t> type_weapon = types_.weapon;
	const ArrayView<const int32_t> weapon_range = weapons_.range;
	const ArrayView<const int32_t> weapon_min_range = weapons_.min_range;
	const ArrayView<const int32_t> weapon_vs = weapons_.vs_armour;
	const ArrayView<const int32_t> heads = grid_.head;
	const ArrayView<const int32_t> links = grid_.next;
	const int64_t cols = grid_.cols;
	const int64_t lines = grid_.rows;
	const int64_t side = grid_.cell_milli;
	// No cells (an empty map), no rows of them or a cell side below 1 (SpatialGrid.configure keeps it at 1 or more): nobody
	// is found, and C++ could not divide by the side.
	const bool cells = cols >= 1 && lines >= 1 && side >= 1;
	const int64_t weapons = weapon_range.size();
	const int64_t tick = rules_.tick;
	const int64_t period = rules_.retarget_period_ticks > 1 ? rules_.retarget_period_ticks : 1;
	const int64_t count = ids.size();
	int64_t looked = 0;
	for (int64_t row = 0; row < count; row++) {
		int64_t order = orders.get(row);
		if (order == ATTACK) {
			const int64_t locked = order_targets.get(row);
			const int64_t at = bsearch(ids, locked);
			if (at < count && ids.get(at) == locked && owners.get(at) != owners.get(row) && owners.get(at) != 0) {
				targets.set(row, locked);
				goal_x.set(row, pos_x.get(at));
				goal_y.set(row, pos_y.get(at));
				continue;
			}
			orders.set(row, ATTACK_MOVE);
			order_targets.set(row, 0);
			targets.set(row, 0);
			order = ATTACK_MOVE;
		}
		if (order != ATTACK_MOVE && order != IDLE) {
			targets.set(row, 0);
			continue;
		}
		if ((tick + ids.get(row)) % period != 0) {
			continue;
		}
		const int64_t type = types.get(row);
		const int64_t weapon = type_weapon.get(type);
		if (weapon < 0 || weapon >= weapons) {
			continue;
		}
		const int64_t reach = order == ATTACK_MOVE ? type_acquire.get(type) : weapon_range.get(weapon);
		const int64_t reach2 = reach * reach;
		const int64_t min2 = weapon_min_range.get(weapon) * weapon_min_range.get(weapon);
		const int64_t vs_base = weapon * ARMOUR_CLASSES;
		const int64_t own = owners.get(row);
		const int64_t x = pos_x.get(row);
		const int64_t y = pos_y.get(row);
		const int64_t held = targets.get(row);
		if (held != 0) {
			const int64_t at = bsearch(ids, held);
			if (at < count && ids.get(at) == held && owners.get(at) != own && owners.get(at) != 0) {
				const int64_t held_x = pos_x.get(at) - x;
				const int64_t held_y = pos_y.get(at) - y;
				const int64_t held_d2 = held_x * held_x + held_y * held_y;
				if (held_d2 <= reach2 && held_d2 >= min2 && weapon_vs.get(vs_base + type_armour.get(types.get(at))) > 0) {
					continue;
				}
			}
		}
		if (!cells) {
			targets.set(row, 0); // An empty map: no cells, so no candidate and no target.
			continue;
		}
		int64_t best = -1;
		int64_t best_percent = 0;
		int64_t best_d2 = 0;
		// Clamped, so a point the grid put in an edge cell (outside the map) still finds that cell.
		const int64_t first_column = clamp((x - reach) / side, 0, cols - 1);
		const int64_t last_column = clamp((x + reach) / side, 0, cols - 1);
		const int64_t first_line = clamp((y - reach) / side, 0, lines - 1);
		const int64_t last_line = clamp((y + reach) / side, 0, lines - 1);
		for (int64_t line = first_line; line <= last_line; line++) {
			for (int64_t column = first_column; column <= last_column; column++) {
				int64_t next = heads.get(line * cols + column);
				while (next != -1) {
					const int64_t other = next;
					next = links.get(other);
					if (other == row) {
						continue;
					}
					looked += 1;
					const int64_t other_owner = owners.get(other);
					if (other_owner == own || other_owner == 0) {
						continue;
					}
					const int64_t dx = pos_x.get(other) - x;
					const int64_t dy = pos_y.get(other) - y;
					const int64_t d2 = dx * dx + dy * dy;
					if (d2 > reach2 || d2 < min2) {
						continue;
					}
					const int64_t percent = weapon_vs.get(vs_base + type_armour.get(types.get(other)));
					if (percent <= 0) {
						continue;
					}
					if (percent > best_percent || (percent == best_percent && (d2 < best_d2 || (d2 == best_d2 && other < best)))) {
						best = other;
						best_percent = percent;
						best_d2 = d2;
					}
				}
			}
		}
		targets.set(row, best >= 0 ? ids.get(best) : 0);
	}
	return looked;
}

// Targeting._engage: returns the line checks it ran.
int64_t Pass::engage() {
	const ArrayView<const int32_t> ids = rows_.unit_id;
	const ArrayView<int32_t> orders = rows_.order;
	const ArrayView<int32_t> modes = rows_.nav_mode;
	const ArrayView<int32_t> targets = rows_.target;
	const ArrayView<int32_t> checked = rows_.nav_cell;
	const ArrayView<const int32_t> types = rows_.type_index;
	const ArrayView<const int32_t> classes = types_.move_class;
	const ArrayView<const int32_t> pos_x = rows_.pos_x;
	const ArrayView<const int32_t> pos_y = rows_.pos_y;
	const ArrayView<const int32_t> type_acquire = types_.acquire;
	const ArrayView<const int32_t> type_weapon = types_.weapon;
	const ArrayView<const int32_t> weapon_range = weapons_.range;
	const ArrayView<const int32_t> weapon_min_range = weapons_.min_range;
	const int64_t weapons = weapon_range.size();
	const int64_t count = ids.size();
	const int64_t tick = rules_.tick;
	const int64_t period = rules_.line_check_period_ticks > 1 ? rules_.line_check_period_ticks : 1;
	int64_t checks = 0;
	for (int64_t row = 0; row < count; row++) {
		int64_t mode = modes.get(row);
		const int64_t order = orders.get(row);
		const int64_t held = targets.get(row);
		int64_t at = -1;
		if (held != 0) {
			at = bsearch(ids, held);
			if (at >= count || ids.get(at) != held) {
				at = -1;
			}
		}
		if (at < 0) {
			if (mode == HOLD || mode == CHASE) {
				reset_row(row, order == IDLE ? NONE : DIRECT);
			}
			continue;
		}
		const int64_t type = types.get(row);
		const int64_t weapon = type_weapon.get(type);
		if (weapon < 0 || weapon >= weapons) {
			continue;
		}
		const int64_t x = pos_x.get(row);
		const int64_t y = pos_y.get(row);
		const int64_t dx = pos_x.get(at) - x;
		const int64_t dy = pos_y.get(at) - y;
		const int64_t d2 = dx * dx + dy * dy;
		const int64_t reach = weapon_range.get(weapon);
		const int64_t min_range = weapon_min_range.get(weapon);
		if (d2 <= reach * reach && d2 >= min_range * min_range) {
			if (mode != HOLD) {
				reset_row(row, HOLD);
			}
			continue;
		}
		if (mode == HOLD) {
			mode = order == IDLE ? NONE : DIRECT;
			reset_row(row, mode);
		}
		if ((order != ATTACK_MOVE && order != ATTACK) || (tick + ids.get(row)) % period != 0) {
			continue;
		}
		if (order == ATTACK) {
			if (mode == DIRECT && checked.get(row) >= 0) {
				checks += 1;
				if (!fixed_math::line_clear(map_.move_cost, map_.cols, map_.rows, x, y, pos_x.get(at), pos_y.get(at), classes.get(type))) {
					reset_row(row, DIRECT);
				}
			}
			continue;
		}
		bool clear = false;
		const int64_t acquire_range = type_acquire.get(type);
		if (d2 <= acquire_range * acquire_range) {
			checks += 1;
			clear = fixed_math::line_clear(map_.move_cost, map_.cols, map_.rows, x, y, pos_x.get(at), pos_y.get(at), classes.get(type));
		}
		if (clear && mode != CHASE) {
			reset_row(row, CHASE);
		} else if (!clear && mode == CHASE) {
			reset_row(row, DIRECT);
		}
	}
	return checks;
}

} // namespace

Counts run(const Rows &rows, const Types &types, const Weapons &weapons, const Grid &grid, const Map &map, const Rules &rules) {
	Pass pass(rows, types, weapons, grid, map, rules);
	Counts counts;
	counts.candidates = pass.acquire();
	counts.line_checks = pass.engage();
	return counts;
}

} // namespace targeting
