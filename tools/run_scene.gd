extends SceneTree
# Loads a scene, lets it run N frames, quits. Usage: --script res://tools/run_scene.gd -- res://view/x.tscn 30
var frames := 0
var limit := 30
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	limit = int(args[1]) if args.size() > 1 else 30
	change_scene_to_file(args[0])
func _process(_d: float) -> bool:
	frames += 1
	return frames >= limit
