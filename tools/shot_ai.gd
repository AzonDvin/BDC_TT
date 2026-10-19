extends SceneTree
# Screenshot of a one-player battle mid-way through the computer's turn (move trail and "Last step" panel).
# Usage: godot --path . --script res://tools/shot_ai.gd -- <out.png> [steps]
var frames := 0
var out := ""
var steps := 0
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	steps = int(a[1]) if a.size() > 1 else 60
	var app = get_root().get_node("App")
	app.battle_config = {"rosters": [Samples.roster("guild_mercenaries"), Samples.roster("verminkin")], "scenario": "no_quarter", "twist": 0, "seed": 11, "ai": ["", "normal"]}
	app.ai_speed = 3   # paused: the tool steps by hand
	change_scene_to_file("res://view/battle.tscn")
func _process(_d: float) -> bool:
	frames += 1
	var view = current_scene
	if frames == 5 and view and view.get("b") != null:
		var n := 0
		var last_ai_move := 0
		while n < steps and not view.b.is_over():
			n += 1
			if AI.should_act(view.b):
				view._ai_do_step()
				if not AI.last_move.is_empty():
					last_ai_move = n
			elif not SimpleBot.step(view.b):
				break
		# Finish on the computer's turn just after it moved, so the trail and panel show.
		var guard := 0
		while guard < 200 and (not AI.should_act(view.b) or AI.last_move.is_empty()):
			guard += 1
			if AI.should_act(view.b):
				view._ai_do_step()
			elif not SimpleBot.step(view.b):
				break
		view._refresh()
	if frames == 200:
		get_root().get_viewport().get_texture().get_image().save_png(out)
		return true
	return false
