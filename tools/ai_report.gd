extends SceneTree
# Plays computer-vs-computer battles in every scenario and prints who won, so the AI levels can be compared.
# Usage: godot --headless --path . --script res://tools/ai_report.gd [-- games_per_scenario]
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 2
	var facs := Catalog.FACTION_IDS
	var tally := {"normal": 0, "easy": 0, "draw": 0}
	var i := 0
	var t0 := Time.get_ticks_msec()
	for sc in Scenario.ORDER:
		for g in games:
			var normal_side := g % 2
			var b := Battle.new()
			var m := i / 2   # each pair of games: same factions and dice seed, sides swapped
			b.setup(Samples.roster(facs[m % 4]), Samples.roster(facs[(m + 1 + m / 4) % 4]), sc, -1, 2000 + m)
			b.cfg["ai"] = ["normal", "easy"] if normal_side == 0 else ["easy", "normal"]
			i += 1
			var steps := 0
			var ts := Time.get_ticks_msec()
			var slowest := 0
			while steps < 6000 and b.round_no <= 15:
				var t1 := Time.get_ticks_msec()
				if not AI.step(b):
					break
				slowest = maxi(slowest, Time.get_ticks_msec() - t1)
				steps += 1
			var downs := [0, 0]
			for f in b.fighters:
				if f.where == "down":
					downs[f.player] += 1
			var who := "draw"
			if b.winner >= 0:
				who = "normal" if b.winner == normal_side else "easy"
			tally[who] += 1
			print("%-22s normal=P%d rounds=%2d steps=%4d down=%s %5dms (slowest step %dms) phase=%s pending=%s winner=%s | %s" % [Scenario.display_name(sc), normal_side + 1, b.round_no, steps, downs, Time.get_ticks_msec() - ts, slowest, b.phase, b.pending.get("type", "-"), who, b.result_text])
	print("Totals: %s in %ds" % [tally, (Time.get_ticks_msec() - t0) / 1000])
	quit()
