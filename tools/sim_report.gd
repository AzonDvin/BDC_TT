extends SceneTree
# Plays bot-vs-bot battles and prints a summary per scenario. Usage: godot --headless --path . --script res://tools/sim_report.gd
func _initialize() -> void:
	var facs := Catalog.FACTION_IDS
	var i := 0
	for sc in Scenario.ORDER:
		var b := Battle.new()
		b.setup(Samples.roster(facs[i % 4]), Samples.roster(facs[(i + 1) % 4]), sc, -1, 1000 + i)
		i += 1
		var steps := 0
		while steps < 4000 and SimpleBot.step(b) and b.round_no <= 15:
			steps += 1
		var downs := [0, 0]
		for f in b.fighters:
			if f.where == "down":
				downs[f.player] += 1
		print("%-22s %-30s rounds=%2d steps=%4d down=%s phase=%s pending=%s | %s" % [Scenario.display_name(sc), "%s v %s" % [b.player_names[0].left(14), b.player_names[1].left(14)], b.round_no, steps, downs, b.phase, b.pending.get("type", "-"), b.result_text])
	quit()
