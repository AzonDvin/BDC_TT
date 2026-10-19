extends SceneTree
# Screenshot of the hover tooltip over a fighter, mid-battle.
var frames := 0
func _process(_d: float) -> bool:
	frames += 1
	if frames == 1:
		change_scene_to_file("res://view/battle.tscn")
	if frames == 5:
		var v = current_scene
		var n := 0
		while n < 40 and SimpleBot.step(v.b):
			n += 1
		while v.b.active < 0 and v.b.pending.is_empty() and n < 80:
			SimpleBot.step(v.b)
			n += 1
		v._refresh()
	if frames == 12:
		var v = current_scene
		var me: FighterState = v.b.active_fighter()
		for f in v.b.on_board():
			if me != null and f.player != me.player:
				var sp: Vector2 = v.board.camera.unproject_position(Vector3(f.pos.x, f.elev + f.height * 0.5, f.pos.y))
				v._update_tip(sp)
				break
	if frames == 20:
		get_root().get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		return true
	return false
