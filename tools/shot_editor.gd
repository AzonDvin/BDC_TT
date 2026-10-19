extends SceneTree
# Screenshot of the terrain editor with a random layout and a selected ruin.
var frames := 0
func _process(_d: float) -> bool:
	frames += 1
	if frames == 1:
		change_scene_to_file("res://view/terrain_editor.tscn")
	if frames == 5:
		var v = current_scene
		v._random_layout()
		for t in v.b.terrain:
			if t.kind == "platform":
				v._select(t)
				break
		v.board.dist = 30
		v.board.zoom(1.0)
		v._refresh()
	if frames == 25:
		get_root().get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		return true
	return false
