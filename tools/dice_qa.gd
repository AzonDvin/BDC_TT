extends SceneTree
# Statistical checks of the battle dice. Usage: godot --headless --path . --script res://tools/dice_qa.gd
func _initialize() -> void:
	var n := 600000
	var d := Dice.new(12345)
	var counts := [0, 0, 0, 0, 0, 0, 0]
	var same_as_last := 0
	var last := 0
	var pairs := {}
	var run := 0
	var longest := 0
	for i in n:
		var r := d.d6()
		counts[r] += 1
		if r == last:
			same_as_last += 1
			run += 1
			longest = maxi(longest, run + 1)
		else:
			run = 0
		if last > 0:
			var k := last * 10 + r
			pairs[k] = pairs.get(k, 0) + 1
		last = r
	var exp := n / 6.0
	var chi := 0.0
	for f in range(1, 7):
		chi += pow(counts[f] - exp, 2) / exp
	print("1. FACES over %d rolls: %s" % [n, str(counts.slice(1))])
	print("   chi-square = %.2f (5 dof; fair dice are under 11.07 95%% of the time)" % chi)
	var pchi := 0.0
	var pexp := (n - 1) / 36.0
	for a in range(1, 7):
		for c in range(1, 7):
			pchi += pow(pairs.get(a * 10 + c, 0) - pexp, 2) / pexp
	print("2. PAIRS (does one roll predict the next?) chi-square = %.2f (35 dof; under 49.8 is fine)" % pchi)
	print("3. REPEATS: same face twice in a row %.2f%% (fair: 16.67%%); longest streak %d" % [100.0 * same_as_last / (n - 1), longest])
	var twod := {}
	for i in 360000:
		var s := d.d6() + d.d6()
		twod[s] = twod.get(s, 0) + 1
	var line := ""
	for s in range(2, 13):
		line += "%d:%.1f%% " % [s, 100.0 * twod.get(s, 0) / 360000.0]
	print("4. 2d6 (miscast/priority sums): %s  (7 should be 16.7%%, 2 and 12 2.8%%)" % line)
	var d3 := [0, 0, 0, 0]
	for i in 300000:
		d3[d.d3()] += 1
	print("5. d3: %s (each should be ~100000)" % str(d3.slice(1)))
	# Seeds next to each other must not give similar games.
	var firsts := [0, 0, 0, 0, 0, 0, 0]
	var matches := 0
	for s in 60000:
		var a := Dice.new(s)
		var b := Dice.new(s + 1)
		var ra := a.d6()
		firsts[ra] += 1
		if ra == b.d6():
			matches += 1
	print("6. NEIGHBOUR SEEDS: first rolls of seeds 0..59999 %s; seed n and n+1 agree %.2f%% (fair 16.67%%)" % [str(firsts.slice(1)), 100.0 * matches / 60000.0])
	quit()
