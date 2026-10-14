extends FlowField
## A FlowField that counts its best_neighbour() calls, to show that Movement asks at event cadence
## (P37b). It goes into a World's `flow.fields` in place of a slot. It has a script base, so it
## never names itself at run time and the test constructs it. A test sets `counted` to false for
## its own lookups. Not a test suite.

var lookups: int = 0
var counted: bool = true


func best_neighbour(cell: int) -> int:
	if counted:
		lookups += 1
	return super(cell)
