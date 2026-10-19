// The checked table of every World member that the native kernels get or set, and the checks over it
// (ADR 0013 section 2). The internal-pointer access also lives here (since FLOW, P30n; the event resize
// comes with FIRE, P42n). check() is pure: it returns a status and never logs. MIT.
// Twin: the World's shape lists and the helpers' HASHED/UNHASHED lists in game/sim; test:
// tests/sim/native/test_kernel_abi.gd, which also reads the X(...) lines below as its table.
#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/variant_internal.hpp>

#include <cstdint>

#include "core/array_view.h"
#include "core/flow.h"
#include "core/world_status.h"

namespace world_access {

using godot::Array;
using godot::Object;
using godot::PackedByteArray;
using godot::PackedInt32Array;
using godot::StringName;
using godot::Variant;
using godot::VariantInternal;

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
// Whether `phase` is one of the five that have a checked list, and so may have a kernel.
constexpr bool has_list(int64_t phase) {
	return phase >= 0 && phase <= SHIFT_MAX && ((PH_ALL >> phase) & 1) == 1;
}

// Mirrors of the twin's GDScript consts (the sizes that are structure, not balance).
constexpr int64_t STAT_COUNT = 7; // World.Stat.size()
constexpr int64_t ARMOUR_COUNT = 4; // World.Armour.size(), the percents per weapon
constexpr int64_t MOVE_CLASSES = 3; // World.MoveClass.size(), the cost lists of move_cost
constexpr int64_t PAD = flow::PAD; // FlowField's padded grid: one blocked ring, so cols + 2 and rows + 2
constexpr int64_t BUCKETS = flow::BUCKETS; // FlowField.BUCKETS

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
	S_COUNT,
};
// The length of a rule that has not been asked for yet (-1 stands for one that cannot be read).
constexpr int64_t LENGTH_UNKNOWN = -2;

struct Entry {
	const char *name;
	int64_t owner;
	int64_t kind;
	int64_t size;
	int64_t phases; // the bits of the phases whose kernel gets or sets it
};

// One line per name: X(owner, name, kind, length rule, phases). Table order is check order, so the
// ints that rules read come before the arrays they size, and `fields` before the slots.
// clang-format off
#define SIM_CHECKED_TABLE(X) \
	X(WORLD, max_rows, INT, NONE, PH_T | PH_S | PH_G) \
	X(WORLD, map_cols, INT, NONE, PH_T | PH_S | PH_I | PH_G) \
	X(WORLD, map_rows, INT, NONE, PH_T | PH_S | PH_I | PH_G) \
	X(WORLD, map_w, INT, NONE, PH_S | PH_I) \
	X(WORLD, map_h, INT, NONE, PH_S | PH_I) \
	X(WORLD, map_version, INT, NONE, PH_I) \
	X(WORLD, tick, INT, NONE, PH_T | PH_I | PH_G) \
	X(WORLD, flow_cache_size, INT, NONE, 0) \
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
	X(WORLD, group_cell, I32, ROWS, PH_I) \
	X(WORLD, order, I32, ROWS, PH_T | PH_I) \
	X(WORLD, hp, I32, ROWS, PH_T) \
	X(WORLD, order_target, I32, ROWS, PH_T) \
	X(WORLD, target, I32, ROWS, PH_T) \
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
	X(WORLD, stats, I32, STATS, PH_F | PH_T | PH_S | PH_G) \
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
#define SIM_ENTRY(owner, name, kind, size, phases) { #name, OWN_##owner, K_##kind, S_##size, phases },
	SIM_CHECKED_TABLE(SIM_ENTRY)
#undef SIM_ENTRY
};
static_assert(sizeof(TABLE) / sizeof(TABLE[0]) == ID_COUNT, "one entry per Id");

// A Packed array borrowed for one call: the Variant keeps it alive (a getter may hand out a fresh copy) and the view
// points into it. Never kept between calls (ADR 0013 section 2).
template <typename T>
struct Borrowed {
	Variant value;
	ArrayView<T> view;
};

// The names as StringNames, made once on the main thread by the constructor of SimKernels and only
// read afterwards (ADR 0013 section 6).
class WorldAccess {
	StringName names_[ID_COUNT];
	StringName owners_[OWN_COUNT];

	// What one check() has fetched, kept alive by the Variants: an Object * taken from a Variant that
	// is a temporary dangles when the Variant goes (a helper or a slot a getter makes fresh has no
	// other owner). It lives in one call, so nothing is kept between calls (ADR 0013 section 2).
	struct Held {
		Object *world;
		Variant helpers[OWN_COUNT]; // flow, fog, sep_grid and target_grid, fetched at first use
		bool fetched[OWN_COUNT] = {};
		Variant fields; // flow.fields: its Array keeps every slot alive
		bool fields_fetched = false;
		int64_t lengths[S_COUNT]; // each length rule, once

		explicit Held(Object *world_) :
				world(world_) {
			for (int64_t rule = 0; rule < S_COUNT; rule++) {
				lengths[rule] = LENGTH_UNKNOWN;
			}
		}
	};

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

	// The object that holds the names of `owner`, or null: no World, no such member, no object (a slot
	// is reached by slot_object).
	Object *owner_object(Held &held, int64_t owner) const {
		if (owner == OWN_WORLD || held.world == nullptr) {
			return held.world;
		}
		if (owner == OWN_SLOT) {
			return nullptr;
		}
		if (!held.fetched[owner]) {
			held.helpers[owner] = held.world->get(owners_[owner]);
			held.fetched[owner] = true;
		}
		if (held.helpers[owner].get_type() != Variant::OBJECT) {
			return nullptr;
		}
		Object *object = held.helpers[owner];
		return object;
	}

	// Slot `index` of flow.fields (the typed Array of FlowField), or null. The Array is fetched once.
	Object *slot_object(Held &held, int64_t index) const {
		if (!held.fields_fetched) {
			Object *flow = owner_object(held, OWN_FLOW);
			held.fields = flow == nullptr ? Variant() : flow->get(names_[ID_FLOW_fields]);
			held.fields_fetched = true;
		}
		if (held.fields.get_type() != Variant::ARRAY) {
			return nullptr;
		}
		const Array slots = held.fields;
		return slot_in(slots, index);
	}

	// An int member of its owner, or -1.
	int64_t int_of(Held &held, int64_t id) const {
		Object *object = owner_object(held, TABLE[id].owner);
		if (object == nullptr) {
			return -1;
		}
		const Variant value = object->get(names_[id]);
		return value.get_type() == Variant::INT ? static_cast<int64_t>(value) : -1;
	}

	// The length of an array member of the World or of a helper, or -1.
	int64_t length_at(Held &held, int64_t id) const {
		Object *object = owner_object(held, TABLE[id].owner);
		return object == nullptr ? -1 : length_of(object->get(names_[id]), TABLE[id].kind);
	}

	// The length that rule `size` asks for, or -1 when a number it is made of cannot be read.
	int64_t compute_length(Held &held, int64_t size) const {
		switch (size) {
			case S_ROWS:
				return length_at(held, ID_WORLD_unit_id);
			case S_MAX_ROWS:
				return int_of(held, ID_WORLD_max_rows);
			case S_STATS:
				return STAT_COUNT;
			case S_TYPES:
				return length_at(held, ID_WORLD_type_speed);
			case S_WEAPONS:
				return length_at(held, ID_WORLD_weapon_range);
			case S_ARMOURS:
				return mul(ARMOUR_COUNT, length_at(held, ID_WORLD_weapon_range));
			case S_COSTS:
				return mul(MOVE_CLASSES, mul(int_of(held, ID_WORLD_map_cols), int_of(held, ID_WORLD_map_rows)));
			case S_SLOTS:
				return int_of(held, ID_WORLD_flow_cache_size);
			case S_PADDED:
				return mul(add(int_of(held, ID_FLOW_cols), PAD), add(int_of(held, ID_FLOW_rows), PAD));
			case S_BUCKETS:
				return BUCKETS;
			case S_SEP_GRID:
				return mul(int_of(held, ID_SEP_cols), int_of(held, ID_SEP_rows));
			case S_TARGET_GRID:
				return mul(int_of(held, ID_TARGET_cols), int_of(held, ID_TARGET_rows));
			case S_FOG_CELLS:
				return mul(int_of(held, ID_FOG_player_count), int_of(held, ID_FOG_cells));
			case S_FOG_PLAYERS:
				return int_of(held, ID_FOG_player_count);
			case S_FOG_DIRTY:
				return mul(int_of(held, ID_FOG_player_count), int_of(held, ID_FOG_dirty_capacity));
			default:
				return -1;
		}
	}

	int64_t length_for(Held &held, int64_t size) const {
		if (held.lengths[size] == LENGTH_UNKNOWN) {
			held.lengths[size] = compute_length(held, size);
		}
		return held.lengths[size];
	}

	// What is wrong with name `id` on `object`, FAULT_NONE if nothing.
	int64_t fault_of(Held &held, Object *object, int64_t id) const {
		const Entry &entry = TABLE[id];
		const Variant value = object->get(names_[id]);
		if (!is_kind(value.get_type(), entry.kind)) {
			return FAULT_TYPE;
		}
		if (entry.size == S_NONE || entry.size == S_ANY) {
			return FAULT_NONE;
		}
		const int64_t length = length_of(value, entry.kind);
		if (entry.size == S_ROWS_CAP) {
			return length <= length_for(held, S_MAX_ROWS) ? FAULT_NONE : FAULT_SIZE;
		}
		return length == length_for(held, entry.size) ? FAULT_NONE : FAULT_SIZE;
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

	// What a kernel fetches once check() has found the names of its phase right (ADR 0013 section 2): by table id,
	// from the World, a helper (OWN_FLOW and the like) or a slot of flow.fields.
	Variant helper(Object *world, int64_t owner) const { return world->get(owners_[owner]); }
	Variant get(Object *object, int64_t id) const { return object->get(names_[id]); }
	void set(Object *object, int64_t id, const Variant &value) const { object->set(names_[id], value); }
	// The Object a Variant holds, null for any other type. The Variant keeps it alive.
	static Object *object_in(const Variant &value) {
		Object *object = nullptr;
		if (value.get_type() == Variant::OBJECT) {
			object = value;
		}
		return object;
	}
	// Slot `index` of the typed Array flow.fields (the Array keeps it alive), or null outside it or for a non-Object.
	static Object *slot_in(const Array &slots, int64_t index) {
		if (index < 0 || index >= slots.size()) {
			return nullptr;
		}
		const Variant &slot = slots[index];
		return object_in(slot);
	}
	// An int or bool member of `object`, 0 or false for a null Object or another type.
	int64_t int_in(Object *object, int64_t id) const {
		if (object == nullptr) {
			return 0;
		}
		const Variant value = get(object, id);
		return value.get_type() == Variant::INT ? static_cast<int64_t>(value) : 0;
	}
	bool bool_in(Object *object, int64_t id) const {
		if (object == nullptr) {
			return false;
		}
		const Variant value = get(object, id);
		return value.get_type() == Variant::BOOL && static_cast<bool>(value);
	}
	// The in-place access to a member: ptr() for a read (it never forks), ptrw() for a write (it forks once when
	// another copy of the array is held, and the copy keeps the old values). The engine logs an error for the
	// pointer of an empty array, so an empty array, and a Variant of the wrong type (the internal getter's
	// undefined behaviour), give an empty view.
	Borrowed<const int32_t> read_i32(Object *object, int64_t id) const {
		Borrowed<const int32_t> found = { get(object, id), {} };
		if (found.value.get_type() == Variant::PACKED_INT32_ARRAY) {
			const PackedInt32Array *array = VariantInternal::get_int32_array(&found.value);
			found.view = { array->size() > 0 ? array->ptr() : nullptr, array->size() };
		}
		return found;
	}
	Borrowed<int32_t> write_i32(Object *object, int64_t id) const {
		Borrowed<int32_t> found = { get(object, id), {} };
		if (found.value.get_type() == Variant::PACKED_INT32_ARRAY) {
			PackedInt32Array *array = VariantInternal::get_int32_array(&found.value);
			found.view = { array->size() > 0 ? array->ptrw() : nullptr, array->size() };
		}
		return found;
	}
	Borrowed<const uint8_t> read_bytes(Object *object, int64_t id) const {
		Borrowed<const uint8_t> found = { get(object, id), {} };
		if (found.value.get_type() == Variant::PACKED_BYTE_ARRAY) {
			const PackedByteArray *array = VariantInternal::get_byte_array(&found.value);
			found.view = { array->size() > 0 ? array->ptr() : nullptr, array->size() };
		}
		return found;
	}
	Borrowed<uint8_t> write_bytes(Object *object, int64_t id) const {
		Borrowed<uint8_t> found = { get(object, id), {} };
		if (found.value.get_type() == Variant::PACKED_BYTE_ARRAY) {
			PackedByteArray *array = VariantInternal::get_byte_array(&found.value);
			found.view = { array->size() > 0 ? array->ptrw() : nullptr, array->size() };
		}
		return found;
	}

	// Pure: the status of the first name of `phase`'s list that is wrong (status_of), 0 if all are right.
	// `world` is the World (an Object); a slot name is checked on every slot of flow.fields. Each helper,
	// the slot Array and each length rule is fetched once per call.
	int64_t check(Object *world, int64_t phase) const {
		if (!has_list(phase)) {
			return status_of(0, FAULT_PHASE);
		}
		Held held(world);
		for (int64_t id = 0; id < ID_COUNT; id++) {
			const Entry &entry = TABLE[id];
			if (((entry.phases >> phase) & 1) == 0) {
				continue;
			}
			int64_t fault = FAULT_NONE;
			if (entry.owner == OWN_SLOT) {
				const int64_t slots = length_for(held, S_SLOTS);
				fault = slots < 0 ? FAULT_OWNER : FAULT_NONE;
				for (int64_t slot = 0; slot < slots && fault == FAULT_NONE; slot++) {
					Object *object = slot_object(held, slot);
					fault = object == nullptr ? FAULT_OWNER : fault_of(held, object, id);
				}
			} else {
				Object *object = owner_object(held, entry.owner);
				fault = object == nullptr ? FAULT_OWNER : fault_of(held, object, id);
			}
			if (fault != FAULT_NONE) {
				return status_of(id, fault);
			}
		}
		return 0;
	}
};

} // namespace world_access
