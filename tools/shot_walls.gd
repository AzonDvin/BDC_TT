extends SceneTree
# Close-up of a ruin in the terrain editor to check wall rendering.
var frames := 0
func _process(_d: float) -> bool:
	frames += 1
	if frames == 1:
		change_scene_to_file("res://view/terrain_editor.tscn")
	if frames == 5:
		var v = current_scene
		v.b.dice = Dice.new(4)
		v._random_layout()
		for t in v.b.terrain:
			if t.kind == "platform":
				v.board.focus(Geo.rect_polygon(Vector2.ZERO, Vector2.ONE)[0] * 0 + v._centroid([t]))
				break
		v.board.dist = 14
		v.board.pitch = 0.6
		v.board.yaw = 0.8
		v.board.zoom(1.0)
		v._refresh()
	if frames == 30:
		get_root().get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		return true
	return false
