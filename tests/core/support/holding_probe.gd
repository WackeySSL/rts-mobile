extends SimProbe
## A SimProbe that holds whatever a test puts in `held`: a Node, or a Resource inside an Array or a
## Dictionary. test_tick_job.gd hangs it behind a TickJob's StepProbe, and its reachability walk
## must find what it holds. Not a test suite. It has its own file because an inner class may not
## extend a script, and it never names itself
## (tests/project/test_inner_classes_extend_engine_classes.gd).

var held: Variant = null
