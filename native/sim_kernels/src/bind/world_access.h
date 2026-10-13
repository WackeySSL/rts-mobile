// The checked table of every World member that the native kernels get or set, and the checks over it
// (ADR 0013 section 2). The only file with the internal-pointer access (a kernel's fetch lands here with
// the first kernel, P30n); check() is pure: it returns a status and never logs. MIT.
// Twin: the World's shape lists and the helpers' HASHED/UNHASHED lists in game/sim; test:
// tests/sim/native/test_kernel_abi.gd (every name exists with its type, each check fails as expected).
#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstdint>

#include "core/world_status.h"

namespace world_access {

using godot::Array;
using godot::Object;
using godot::PackedByteArray;
using godot::PackedInt32Array;
using godot::StringName;
using godot::Variant;

// SimProbe.Phase ids (game/sim/SimProbe.gd, fixed): the five phases that get a kernel (ADR 0013 section 1).
constexpr int64_t PHASE_FLOW = 1;
constexpr int64_t PHASE_TARGETING = 3;
constexpr int64_t PHASE_SEPARATION = 5;
constexpr int64_t PHASE_INTEGRATE = 6;
constexpr int64_t PHASE_FOG = 10;
constexpr int64_t PH_F = int64_t(1) << PHASE_FLOW;
constexpr int64_t PH_T = int64_t(1) << PHASE_TARGETING;
constexpr int64_t PH_S = int64_t(1) << PHASE_SEPARATION;
constexpr int64_t PH_I = int64_t(1) << PHASE_INTEGRATE;
constexpr int64_t PH_G = int64_t(1) << PHASE_FOG;
constexpr int64_t PH_ALL = PH_F | PH_T | PH_S | PH_I | PH_G;
// The largest shift of a non-negative value (ADR 0013 section 4).
constexpr int64_t SHIFT_MAX = 62;

// Mirrors of the twin's GDScript consts (the sizes that are structure, not balance).
constexpr int64_t STAT_COUNT = 7; // World.Stat.size()
constexpr int64_t ARMOUR_COUNT = 4; // World.Armour.size(), the percents per weapon
constexpr int64_t MOVE_CLASSES = 3; // World.MoveClass.size(), the cost lists of move_cost
constexpr int64_t PAD = 2; // FlowField's padded grid: one blocked ring, so cols + 2 and rows + 2
constexpr int64_t BUCKETS = 512; // FlowField.BUCKETS

// Who holds a name: the World, a helper reached through it by member name, or each slot of flow.fields.
enum Owner : int64_t {
	OWN_WORLD,
	OWN_FLOW,
	OWN_SLOT,
	OWN_FOG,
	OWN_SEP,
	OWN_TARGET,
	OWN_COUNT,
};
inline constexpr const char *OWNER_MEMBER[OWN_COUNT] = { "", "flow", "", "fog", "sep_grid", "target_grid" };
// The Variant type a name has.
enum Kind : int64_t {
	K_INT,
	K_BOOL,
	K_I32, // PackedInt32Array
	K_BYTES, // PackedByteArray
	K_ARRAY, // an Array (flow.fields, the typed Array of slots)
};
// The length rule of an array.
enum Size : int64_t {
	S_NONE, // a scalar
	S_ANY, // an array with no fixed length (an anchor of the rules below, or the fog masks)
	S_ROWS_CAP, // at most max_rows: unit_id, the row count
	S_ROWS, // as many as unit_id
	S_MAX_ROWS, // max_rows
	S_STATS, // one per World.Stat
	S_TYPES, // as many as type_speed, the type tables' anchor
	S_WEAPONS, // as many as weapon_range, the weapon tables' anchor
	S_ARMOURS, // four per weapon
	S_COSTS, // one list of cells per move class
	S_SLOTS, // flow_cache_size
	S_PADDED, // a slot's padded grid
	S_BUCKETS,
	S_SEP_GRID, // the cells of the separation grid
	S_TARGET_GRID,
	S_FOG_CELLS, // a block of cells per player
	S_FOG_PLAYERS, // one per player
	S_FOG_DIRTY, // a dirty block per player
};

struct Entry {
	const char *name;
	int64_t owner;
	int64_t kind;
	int64_t size;
	int64_t phases; // the bits of the phases whose kernel gets or sets it
	const char *text; // "OWNER name KIND SIZE", for SimKernels.checked_names()
};

// One line per name: X(owner, name, kind, length rule, phases). Table order is check order, so the
// ints that rules read come before the arrays they size, and `fields` before the slots.
// clang-format off
#define SIM_CHECKED_TABLE(X) \
	X(WORLD, max_rows, INT, NONE, PH_ALL) \
	X(WORLD, map_cols, INT, NONE, PH_ALL) \
	X(WORLD, map_rows, INT, NONE, PH_ALL) \
	X(WORLD, map_w, INT, NONE, PH_S | PH_I) \
	X(WORLD, map_h, INT, NONE, PH_S | PH_I) \
	X(WORLD, map_version, INT, NONE, PH_I) \
	X(WORLD, tick, INT, NONE, PH_T | PH_I | PH_G) \
	X(WORLD, flow_cache_size, INT, NONE, PH_F | PH_I) \
	X(WORLD, retarget_period_ticks, INT, NONE, PH_T) \
	X(WORLD, fog_period_ticks, INT, NONE, PH_G) \
	X(WORLD, line_check_period_ticks, INT, NONE, PH_I) \
	X(WORLD, stall_ticks, INT, NONE, PH_I) \
	X(WORLD, stall_range_spacings, INT, NONE, PH_I) \
	X(WORLD, attack_rekey_milli, INT, NONE, PH_I) \
	X(WORLD, separation_neighbours, INT, NONE, PH_S) \
	X(WORLD, separation_scan, INT, NONE, PH_S) \
	X(WORLD, separation_idle_share, INT, NONE, PH_S) \
	X(WORLD, separation_push_max, INT, NONE, PH_S) \
	X(WORLD, separation_coincident_divisor, INT, NONE, PH_S) \
	X(WORLD, unit_id, I32, ROWS_CAP, PH_ALL) \
	X(WORLD, owner, I32, ROWS, PH_T | PH_G) \
	X(WORLD, type_index, I32, ROWS, PH_T | PH_S | PH_I | PH_G) \
	X(WORLD, pos_x, I32, ROWS, PH_T | PH_S | PH_I | PH_G) \
	X(WORLD, pos_y, I32, ROWS, PH_T | PH_S | PH_I | PH_G) \
	X(WORLD, goal_x, I32, ROWS, PH_T | PH_I) \
	X(WORLD, goal_y, I32, ROWS, PH_T | PH_I) \
	X(WORLD, order, I32, ROWS, PH_T | PH_I) \
	X(WORLD, hp, I32, ROWS, PH_T) \
	X(WORLD, order_target, I32, ROWS, PH_T | PH_I) \
	X(WORLD, target, I32, ROWS, PH_T | PH_I) \
	X(WORLD, nav_mode, I32, ROWS, PH_T | PH_I) \
	X(WORLD, field, I32, ROWS, PH_F | PH_I) \
	X(WORLD, nav_cell, I32, ROWS, PH_I) \
	X(WORLD, nav_next, I32, ROWS, PH_I) \
	X(WORLD, best_dist, I32, ROWS, PH_I) \
	X(WORLD, stall, I32, ROWS, PH_I) \
	X(WORLD, fog_cell, I32, ROWS, PH_G) \
	X(WORLD, intent_x, I32, MAX_ROWS, PH_S | PH_I) \
	X(WORLD, intent_y, I32, MAX_ROWS, PH_S | PH_I) \
	X(WORLD, push_x, I32, MAX_ROWS, PH_S | PH_I) \
	X(WORLD, push_y, I32, MAX_ROWS, PH_S | PH_I) \
	X(WORLD, stats, I32, STATS, PH_ALL) \
	X(WORLD, events, I32, ANY, 0) \
	X(WORLD, move_cost, BYTES, COSTS, PH_F | PH_T | PH_S | PH_I) \
	X(WORLD, type_speed, I32, ANY, PH_T | PH_S | PH_I | PH_G) \
	X(WORLD, type_radius, I32, TYPES, PH_S) \
	X(WORLD, type_spacing, I32, TYPES, PH_I) \
	X(WORLD, type_armour, I32, TYPES, PH_T) \
	X(WORLD, type_move_class, I32, TYPES, PH_T | PH_S | PH_I) \
	X(WORLD, type_sight, I32, TYPES, PH_G) \
	X(WORLD, type_acquire, I32, TYPES, PH_T) \
	X(WORLD, type_weapon, I32, TYPES, PH_T) \
	X(WORLD, weapon_range, I32, ANY, PH_T) \
	X(WORLD, weapon_min_range, I32, WEAPONS, PH_T) \
	X(WORLD, weapon_vs_armour, I32, ARMOURS, PH_T) \
	X(FLOW, cols, INT, NONE, PH_F | PH_I) \
	X(FLOW, rows, INT, NONE, PH_F | PH_I) \
	X(FLOW, classes, INT, NONE, PH_I) \
	X(FLOW, requests, INT, NONE, PH_I) \
	X(FLOW, key_goal, I32, SLOTS, PH_F | PH_I) \
	X(FLOW, key_class, I32, SLOTS, PH_F | PH_I) \
	X(FLOW, key_version, I32, SLOTS, PH_I) \
	X(FLOW, last_used, I32, SLOTS, PH_I) \
	X(FLOW, ref_count, I32, SLOTS, PH_F | PH_I) \
	X(FLOW, requested, I32, SLOTS, PH_F | PH_I) \
	X(FLOW, status, I32, SLOTS, PH_F | PH_I) \
	X(FLOW, fields, ARRAY, SLOTS, PH_F | PH_I) \
	X(SLOT, goal_cell, INT, NONE, PH_F) \
	X(SLOT, move_class, INT, NONE, PH_F) \
	X(SLOT, grid_cols, INT, NONE, PH_F | PH_I) \
	X(SLOT, cell_count, INT, NONE, PH_F | PH_I) \
	X(SLOT, stride, INT, NONE, PH_F | PH_I) \
	X(SLOT, level, INT, NONE, PH_F) \
	X(SLOT, pending, INT, NONE, PH_F) \
	X(SLOT, complete, BOOL, NONE, PH_F | PH_I) \
	X(SLOT, cost, I32, PADDED, PH_F | PH_I) \
	X(SLOT, next, I32, PADDED, PH_F) \
	X(SLOT, pad_cost, BYTES, PADDED, PH_F) \
	X(SLOT, bucket_head, I32, BUCKETS, PH_F) \
	X(SLOT, link_next, I32, PADDED, PH_F) \
	X(SLOT, link_prev, I32, PADDED, PH_F) \
	X(SEP, cols, INT, NONE, PH_S) \
	X(SEP, rows, INT, NONE, PH_S) \
	X(SEP, cell_milli, INT, NONE, PH_S) \
	X(SEP, head, I32, SEP_GRID, PH_S) \
	X(SEP, next, I32, MAX_ROWS, PH_S) \
	X(TARGET, cols, INT, NONE, PH_T) \
	X(TARGET, rows, INT, NONE, PH_T) \
	X(TARGET, cell_milli, INT, NONE, PH_T) \
	X(TARGET, head, I32, TARGET_GRID, PH_T) \
	X(TARGET, next, I32, MAX_ROWS, PH_T) \
	X(FOG, cols, INT, NONE, PH_G) \
	X(FOG, rows, INT, NONE, PH_G) \
	X(FOG, cells, INT, NONE, PH_G) \
	X(FOG, player_count, INT, NONE, PH_G) \
	X(FOG, dirty_capacity, INT, NONE, PH_G) \
	X(FOG, visible, I32, FOG_CELLS, PH_G) \
	X(FOG, explored, BYTES, FOG_CELLS, PH_G) \
	X(FOG, listed, BYTES, FOG_CELLS, PH_G) \
	X(FOG, version, I32, FOG_PLAYERS, PH_G) \
	X(FOG, dirty_count, I32, FOG_PLAYERS, PH_G) \
	X(FOG, dirty_full, I32, FOG_PLAYERS, PH_G) \
	X(FOG, dirty, I32, FOG_DIRTY, PH_G) \
	X(FOG, mask_start, I32, ANY, PH_G) \
	X(FOG, mask_radius, I32, ANY, PH_G) \
	X(FOG, mask_half, I32, ANY, PH_G)

#define SIM_ID(owner, name, kind, size, phases) ID_##owner##_##name,
enum Id : int64_t {
	SIM_CHECKED_TABLE(SIM_ID)
	ID_COUNT,
};
#undef SIM_ID
// clang-format on

inline constexpr Entry TABLE[] = {
#define SIM_ENTRY(owner, name, kind, size, phases) { #name, OWN_##owner, K_##kind, S_##size, phases, #owner " " #name " " #kind " " #size },
	SIM_CHECKED_TABLE(SIM_ENTRY)
#undef SIM_ENTRY
};
static_assert(sizeof(TABLE) / sizeof(TABLE[0]) == ID_COUNT, "one entry per Id");

// The names as StringNames, made once on the main thread by the constructor of SimKernels and only
// read afterwards (ADR 0013 section 6).
class WorldAccess {
	StringName names_[ID_COUNT];
	StringName owners_[OWN_COUNT];

	static bool is_kind(Variant::Type type, int64_t kind) {
		switch (kind) {
			case K_INT:
				return type == Variant::INT;
			case K_BOOL:
				return type == Variant::BOOL;
			case K_I32:
				return type == Variant::PACKED_INT32_ARRAY;
			case K_BYTES:
				return type == Variant::PACKED_BYTE_ARRAY;
			default:
				return type == Variant::ARRAY;
		}
	}

	// The length of an array member, -1 for a scalar or another type.
	static int64_t length_of(const Variant &value, int64_t kind) {
		if (!is_kind(value.get_type(), kind)) {
			return -1;
		}
		switch (kind) {
			case K_I32: {
				PackedInt32Array array = value;
				return array.size();
			}
			case K_BYTES: {
				PackedByteArray array = value;
				return array.size();
			}
			case K_ARRAY: {
				Array array = value;
				return array.size();
			}
			default:
				return -1;
		}
	}

	// -1 stands for a size that cannot be read, so no length matches it.
	static int64_t add(int64_t a, int64_t b) { return a < 0 || b < 0 || a > INT64_MAX - b ? -1 : a + b; }
	static int64_t mul(int64_t a, int64_t b) { return a < 0 || b < 0 || (a != 0 && b > INT64_MAX / a) ? -1 : a * b; }

	// The object that holds the names of `owner`, or null: no World, no such member, or no object.
	Object *owner_object(Object *world, int64_t owner) const {
		if (owner == OWN_WORLD || world == nullptr) {
			return world;
		}
		Variant helper = world->get(owners_[owner]);
		if (helper.get_type() != Variant::OBJECT) {
			return nullptr;
		}
		Object *object = helper;
		return object;
	}

	// Slot `index` of flow.fields (the typed Array of FlowField), or null.
	Object *slot_object(Object *world, int64_t index) const {
		Object *flow = owner_object(world, OWN_FLOW);
		if (flow == nullptr) {
			return nullptr;
		}
		Variant fields = flow->get(names_[ID_FLOW_fields]);
		if (fields.get_type() != Variant::ARRAY) {
			return nullptr;
		}
		const Array slots = fields;
		if (index < 0 || index >= slots.size()) {
			return nullptr;
		}
		Variant slot = slots[index];
		if (slot.get_type() != Variant::OBJECT) {
			return nullptr;
		}
		Object *object = slot;
		return object;
	}

	// An int member of its owner, or -1.
	int64_t int_of(Object *world, int64_t id) const {
		Object *object = owner_object(world, TABLE[id].owner);
		Variant value = object == nullptr ? Variant() : object->get(names_[id]);
		return value.get_type() == Variant::INT ? static_cast<int64_t>(value) : -1;
	}

	// The length of an array member of the World or of a helper, or -1.
	int64_t length_at(Object *world, int64_t id) const {
		Object *object = owner_object(world, TABLE[id].owner);
		return object == nullptr ? -1 : length_of(object->get(names_[id]), TABLE[id].kind);
	}

	// The length that rule `size` asks for, or -1 when a number it is made of cannot be read.
	int64_t length_for(Object *world, int64_t size) const {
		switch (size) {
			case S_ROWS:
				return length_at(world, ID_WORLD_unit_id);
			case S_MAX_ROWS:
				return int_of(world, ID_WORLD_max_rows);
			case S_STATS:
				return STAT_COUNT;
			case S_TYPES:
				return length_at(world, ID_WORLD_type_speed);
			case S_WEAPONS:
				return length_at(world, ID_WORLD_weapon_range);
			case S_ARMOURS:
				return mul(ARMOUR_COUNT, length_at(world, ID_WORLD_weapon_range));
			case S_COSTS:
				return mul(MOVE_CLASSES, mul(int_of(world, ID_WORLD_map_cols), int_of(world, ID_WORLD_map_rows)));
			case S_SLOTS:
				return int_of(world, ID_WORLD_flow_cache_size);
			case S_PADDED:
				return mul(add(int_of(world, ID_FLOW_cols), PAD), add(int_of(world, ID_FLOW_rows), PAD));
			case S_BUCKETS:
				return BUCKETS;
			case S_SEP_GRID:
				return mul(int_of(world, ID_SEP_cols), int_of(world, ID_SEP_rows));
			case S_TARGET_GRID:
				return mul(int_of(world, ID_TARGET_cols), int_of(world, ID_TARGET_rows));
			case S_FOG_CELLS:
				return mul(int_of(world, ID_FOG_player_count), int_of(world, ID_FOG_cells));
			case S_FOG_PLAYERS:
				return int_of(world, ID_FOG_player_count);
			case S_FOG_DIRTY:
				return mul(int_of(world, ID_FOG_player_count), int_of(world, ID_FOG_dirty_capacity));
			default:
				return -1;
		}
	}

	// What is wrong with name `id` on `object`, FAULT_NONE if nothing.
	int64_t fault_of(Object *world, Object *object, int64_t id) const {
		const Entry &entry = TABLE[id];
		Variant value = object->get(names_[id]);
		if (!is_kind(value.get_type(), entry.kind)) {
			return FAULT_TYPE;
		}
		if (entry.size == S_NONE || entry.size == S_ANY) {
			return FAULT_NONE;
		}
		const int64_t length = length_of(value, entry.kind);
		if (entry.size == S_ROWS_CAP) {
			return length <= int_of(world, ID_WORLD_max_rows) ? FAULT_NONE : FAULT_SIZE;
		}
		return length == length_for(world, entry.size) ? FAULT_NONE : FAULT_SIZE;
	}

public:
	// Main thread only.
	WorldAccess() {
		for (int64_t id = 0; id < ID_COUNT; id++) {
			names_[id] = StringName(TABLE[id].name);
		}
		for (int64_t owner = 0; owner < OWN_COUNT; owner++) {
			owners_[owner] = StringName(OWNER_MEMBER[owner]);
		}
	}

	// Pure: the status of the first name of `phase`'s list that is wrong (status_of), 0 if all are right.
	// `world` is the World (an Object); a slot name is checked on every slot of flow.fields.
	int64_t check(Object *world, int64_t phase) const {
		if (phase < 0 || phase > SHIFT_MAX || ((PH_ALL >> phase) & 1) == 0) {
			return status_of(0, FAULT_PHASE);
		}
		for (int64_t id = 0; id < ID_COUNT; id++) {
			const Entry &entry = TABLE[id];
			if (((entry.phases >> phase) & 1) == 0) {
				continue;
			}
			int64_t fault = FAULT_NONE;
			if (entry.owner == OWN_SLOT) {
				const int64_t slots = int_of(world, ID_WORLD_flow_cache_size);
				fault = slots < 0 ? FAULT_OWNER : FAULT_NONE;
				for (int64_t slot = 0; slot < slots && fault == FAULT_NONE; slot++) {
					Object *object = slot_object(world, slot);
					fault = object == nullptr ? FAULT_OWNER : fault_of(world, object, id);
				}
			} else {
				Object *object = owner_object(world, entry.owner);
				fault = object == nullptr ? FAULT_OWNER : fault_of(world, object, id);
			}
			if (fault != FAULT_NONE) {
				return status_of(id, fault);
			}
		}
		return 0;
	}

	// The one resize a tick may make (ADR 0013 section 2): `events` grows by `ints` entries, once, after
	// a kernel's loop; the caller fetches every pointer again afterwards. First used by FIRE (P42n).
	void grow_events(Object *world, int64_t ints) const {
		PackedInt32Array events = world->get(names_[ID_WORLD_events]);
		events.resize(events.size() + ints);
		world->set(names_[ID_WORLD_events], events);
	}
};

} // namespace world_access
