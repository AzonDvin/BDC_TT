extends SceneTree
# Prints the battle log of one computer-vs-computer game. Usage: --script res://tools/ai_log.gd -- scenario seed normal_side [easy|normal]
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var facs := Catalog.FACTION_IDS
	var sc: String = a[0]
	var i := int(a[1])
	var side := int(a[2])
	var other: String = a[3] if a.size() > 3 else "easy"
	var b := Battle.new()
	b.setup(Samples.roster(facs[i % 4]), Samples.roster(facs[(i + 1 + i / 4) % 4]), sc, -1, 2000 + i)   # same pairing as ai_report (pair index i)
	b.cfg["ai"] = ["normal", other] if side == 0 else [other, "normal"]
	var steps := 0
	while steps < 6000 and AI.step(b) and b.round_no <= 15:
		steps += 1
	for h in b.history:
		print(h)
	quit()
