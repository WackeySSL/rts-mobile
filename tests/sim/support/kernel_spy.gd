extends RefCounted
## A stand-in for the native kernels (ADR 0013 section 3): the same methods, each recording its
## call instead of running a rule. A World's `kernels` is an untyped Object, so a spy goes where
## the library would. Not a test suite.

## One "name" or "name:budget" per call, in call order.
var calls: Array[String] = []
## What phases() answers: a spy can set bits no library has, to test what sim_impls.gd reports.
var reported_phases: int = 0


func phases() -> int:
	return reported_phases


func flow(_world: Object, budget: int) -> void:
	calls.append("flow:%d" % budget)


func separation(_world: Object) -> void:
	calls.append("separation")


func integrate(_world: Object) -> void:
	calls.append("integrate")


func targeting(_world: Object) -> void:
	calls.append("targeting")


func fog(_world: Object) -> void:
	calls.append("fog")
