extends GdUnitTestSuite
## SelectionModel: a sorted, unique selection, one `changed` per real change, and groups 1-3.

var _model: SelectionModel
var _changes: int = 0


func before_test() -> void:
	_model = SelectionModel.new()
	_changes = 0
	_model.changed.connect(func() -> void: _changes += 1)


func test_set_ids_sorts_removes_duplicates_and_leaves_the_callers_array_alone() -> void:
	var given: PackedInt32Array = PackedInt32Array([7, 3, 3, 12, 1, 7])
	_model.set_ids(given)
	assert_array(_model.selected).is_equal([1, 3, 7, 12])
	assert_array(given).is_equal([7, 3, 3, 12, 1, 7])
	var found: Array[bool] = []
	for id: int in [0, 1, 2, 3, 7, 12, 13]:
		found.append(_model.is_selected(id))
	assert_array(found).is_equal([false, true, false, true, true, true, false])


func test_changed_fires_once_per_real_change_of_the_selection() -> void:
	_model.set_ids(PackedInt32Array([2, 1]))
	assert_int(_changes).is_equal(1)
	_model.set_ids(PackedInt32Array([1, 2, 2]))  # The same selection.
	_model.assign_group(1)  # A group change leaves the selection alone.
	assert_int(_changes).is_equal(1)
	_model.set_ids(PackedInt32Array([1, 2, 3]))
	assert_int(_changes).is_equal(2)
	_model.clear()
	_model.clear()  # Already empty.
	assert_int(_changes).is_equal(3)


func test_groups_keep_a_copy_of_the_selection_and_recall_it() -> void:
	assert_int(SelectionModel.GROUP_COUNT).is_equal(3)
	_model.set_ids(PackedInt32Array([5, 6, 7]))
	_model.assign_group(1)
	_model.selected.append(8)  # Neither an edit in place nor a later selection edits the group.
	_model.set_ids(PackedInt32Array([9]))
	_model.assign_group(3)
	_model.clear()
	assert_array(_model.group(1)).is_equal([5, 6, 7])
	assert_array(_model.group(2)).is_empty()
	assert_array(_model.group(3)).is_equal([9])
	_model.group(1).append(99)  # The returned array is a copy.
	assert_array(_model.group(1)).is_equal([5, 6, 7])
	_changes = 0
	assert_bool(_model.recall_group(1)).is_true()
	assert_array(_model.selected).is_equal([5, 6, 7])
	assert_bool(_model.recall_group(3)).is_true()
	assert_array(_model.selected).is_equal([9])
	assert_bool(_model.recall_group(3)).is_true()  # Already selected: true, no new change.
	assert_int(_changes).is_equal(2)


func test_an_empty_or_unknown_group_does_not_change_the_selection() -> void:
	_model.set_ids(PackedInt32Array([4, 8]))
	_changes = 0
	assert_bool(_model.recall_group(2)).is_false()  # Empty.
	for slot: int in [0, 4]:  # These slots do not exist.
		_model.assign_group(slot)
		assert_array(_model.group(slot)).is_empty()
		assert_bool(_model.recall_group(slot)).is_false()
	assert_array(_model.selected).is_equal([4, 8])
	assert_int(_changes).is_equal(0)
	_model.assign_group(2)
	_model.clear()
	_model.assign_group(2)  # An empty selection empties the group.
	assert_bool(_model.recall_group(2)).is_false()
