extends SceneTree
# Saves every synthesised sound effect as a .wav to audition outside the game.
# Usage: godot --headless --path . --script res://tools/sfx_preview.gd -- <output folder>
func _initialize() -> void:
	var dir: String = OS.get_cmdline_user_args()[0]
	var t := Time.get_ticks_msec()
	Sfx.build_streams()
	print("Built in %d ms" % (Time.get_ticks_msec() - t))
	for n in Sfx._streams:
		var w: AudioStreamWAV = Sfx._streams[n][0]
		w.save_to_wav(dir.path_join("bdc_%s.wav" % n))
		print("%s  %.2fs" % [n, w.get_length()])
	quit()
