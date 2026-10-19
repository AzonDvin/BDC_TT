# Minimal headless test runner for Godot 4.5+ (verified on 4.7.2).
#
# Copy this file and test_case.gd into the project's res://tests/ folder, then:
#   godot --headless --path <project> --import            # once, or after adding class_name scripts
#   godot --headless --path <project> --script res://tests/run_tests.gd
#   godot --headless --path <project> --script res://tests/run_tests.gd -- dice   # only tests whose id contains "dice"
#
# Discovers every res://tests/**/test_*.gd, instantiates it, and runs each method named test_*.
# A test fails if an assertion fails OR if a script error is raised while it runs (caught via Logger),
# so a crash in rules code is never mistaken for a pass. Exit code is 0 only when everything passes.
# Tests run on the first frame (not in _initialize), so scenes added to the tree get _ready() and can be tested too.
extends SceneTree

const TEST_ROOT := "res://tests"


class ErrorCatcher extends Logger:
	var messages: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		var text := rationale if rationale != "" else code
		messages.append("%s (%s:%d in %s)" % [text, file, line, function])


var _ran := false


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run_all()
	return false


func _run_all() -> void:
	var args := OS.get_cmdline_user_args()
	var filter: String = args[0] if args.size() > 0 else ""
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)

	var passed := 0
	var failed: Array[String] = []
	for path in _find_test_files(TEST_ROOT):
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			failed.append("%s: could not load (parse error?)" % path)
			continue
		for method in script.get_script_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			var id := "%s::%s" % [path.get_file().get_basename(), name]
			if filter != "" and not id.contains(filter):
				continue
			catcher.messages.clear()
			var test: Object = script.new()
			if test.has_method("before_each"):
				test.call("before_each")
			test.call(name)
			var problems: Array[String] = []
			if "failures" in test:
				problems.append_array(test.failures)
			problems.append_array(catcher.messages)
			if problems.is_empty():
				passed += 1
				print("  ok    ", id)
			else:
				failed.append("%s\n        %s" % [id, "\n        ".join(problems)])
				print("  FAIL  ", id)
			if test is Node:
				test.free()

	print("")
	for f in failed:
		printerr("FAIL ", f)
	print("%d passed, %d failed" % [passed, failed.size()])
	quit(0 if failed.is_empty() and passed > 0 else 1)


func _find_test_files(dir_path: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for sub in dir.get_directories():
		found.append_array(_find_test_files(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
	found.sort()
	return found
