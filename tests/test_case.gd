# Base class for tests run by run_tests.gd. Test files: `extends "res://tests/test_case.gd"`.
# Assertions record failures instead of aborting, so one test can report several problems.
extends RefCounted

var failures: Array[String] = []


func assert_true(cond: bool, msg := "expected true") -> void:
	if not cond:
		failures.append(msg)


func assert_false(cond: bool, msg := "expected false") -> void:
	if cond:
		failures.append(msg)


func assert_eq(actual: Variant, expected: Variant, msg := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%sexpected %s, got %s" % [_prefix(msg), var_to_str(expected), var_to_str(actual)])


func assert_approx(actual: float, expected: float, tolerance := 0.0001, msg := "") -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%sexpected %s ± %s, got %s" % [_prefix(msg), expected, tolerance, actual])


func assert_between(actual: float, low: float, high: float, msg := "") -> void:
	if actual < low or actual > high:
		failures.append("%sexpected %s in [%s, %s]" % [_prefix(msg), actual, low, high])


func _prefix(msg: String) -> String:
	return msg + ": " if msg != "" else ""
