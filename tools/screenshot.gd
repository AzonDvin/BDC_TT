extends SceneTree
# Opens a scene in a window, optionally advances a battle with the bot, saves a screenshot, quits.
# Usage: godot --path . --script res://tools/screenshot.gd -- <scene> <out.png> [bot_steps]
var frames := 0
var out := ""
var steps := 0
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[1]
	steps = int(a[2]) if a.size() > 2 else 0
	change_scene_to_file(a[0])
func _process(_d: float) -> bool:
	frames += 1
	if frames == 5 and steps > 0:
		var view = current_scene
		if view and view.get("b") != null:
			var n := 0
			while n < steps and SimpleBot.step(view.b):
				n += 1
			view._refresh()
	if frames == 25:
		get_root().get_viewport().get_texture().get_image().save_png(out)
		return true
	return false
