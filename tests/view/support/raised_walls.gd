extends WallLayer
## A `WallLayer` with a crafted raised set, for the suites that only ask `is_wall` (P656d5). Not a
## test suite.

var raised: Dictionary[int, bool] = {}


func is_wall(cell: int) -> bool:
	return raised.has(cell)
