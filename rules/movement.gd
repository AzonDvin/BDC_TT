class_name Movement
extends RefCounted
## Moves (pp.20-22): Normal, Run, Charge, Disengage. A move is declared first (Run/Charge roll their extra d6,
## Disengage takes its Initiative test), then committed with a path of waypoints.
## Waypoints are floor-plan points (inches) with a level each (0 = battlefield floor, else a platform/roof height).
## Between waypoints a fighter walks on its level, jumps gaps (<= 3" through the air), climbs a ladder (-1"),
## climbs a wall (vertical distance counts), jumps down (impact damage from 3"), or flies (Fly keyword).

const TOKEN_RADIUS := 0.5


## Declares a move for the active fighter. Returns "" or an error.
static func declare(b: Battle, kind: String) -> String:
	var f := b.active_fighter()
	if f == null:
		return "No fighter is activating."
	if not b.move_plan.is_empty():
		return "A move is already declared."
	if not b.can_still_move(f):
		return "%s cannot make a move now." % f.name
	var engaged := Effects.is_engaged(b, f)
	var extra := 0
	var rolled_2d6 := 0
	var notes: PackedStringArray = []
	match kind:
		"normal":
			if engaged:
				return "Engaged fighters can only Disengage."
		"run", "charge":
			if engaged:
				return "Engaged fighters can only Disengage."
			if f.acted:
				return "A %s move must come before any action." % kind.capitalize()
			if b.move_or_action_only(f) and kind == "charge" and b.cfg.get("bloodied_strict", true):
				notes.append("only a move OR an action this activation, so no attack after the charge")
		"disengage":
			if not engaged:
				return "Only engaged fighters can Disengage."
		_:
			return "Unknown move %s" % kind
	if not b.harried_check(f, "move"):
		return ""
	if kind == "disengage":
		var t := b.dice.test(int(f.stats["initiative"]))
		b.mark_dice_rolled()
		if not t["pass"]:
			f.moved = true
			f.move_kind = "disengage"
			b.log_line("%s fails to disengage (rolled %d vs Initiative %d); the move is used." % [f.name, t["roll"], f.stats["initiative"]])
			b.changed.emit()
			return ""
		b.log_line("%s disengages (rolled %d vs Initiative %d): up to 3\"." % [f.name, t["roll"], f.stats["initiative"]])
		b.move_plan = {"uid": f.uid, "kind": kind, "allowance": 3.0}
		b.changed.emit()
		return ""
	if kind in ["run", "charge"]:
		extra = b.dice.d6()
		notes.append("+%d\" (d6)" % extra)
	if str(f.stats["move"]) == "2d6":
		rolled_2d6 = b.dice.d6() + b.dice.d6()
		notes.insert(0, "Move 2d6 = %d\"" % rolled_2d6)
	var allowance := Effects.move_value(b, f, rolled_2d6) + extra
	if f.has_rule("impetuous") and not "impetuous" in f.once_per_battle:
		var imp := b.dice.d6()
		f.once_per_battle.append("impetuous")
		allowance += imp
		notes.append("Impetuous +%d\"" % imp)
	if extra > 0 or rolled_2d6 > 0 or "impetuous" in f.once_per_battle:
		b.mark_dice_rolled()
	b.move_plan = {"uid": f.uid, "kind": kind, "allowance": allowance}
	b.log_line("%s declares a %s move: up to %.1f\"%s." % [f.name, kind.capitalize(), allowance, (" (" + ", ".join(notes) + ")") if not notes.is_empty() else ""])
	b.changed.emit()
	return ""


## A Normal move declared but not yet made can be withdrawn (nothing was rolled).
static func cancel(b: Battle) -> String:
	if b.move_plan.is_empty():
		return "No move declared."
	if b.move_plan["kind"] != "normal":
		return "Dice were rolled for this move; it can't be withdrawn."
	b.move_plan = {}
	b.changed.emit()
	return ""


static func can_climb(f: FighterState) -> bool:
	return f.category != "beast" and not f.has_rule("large_and_heavy")


static func _climbs_like_ladder(f: FighterState) -> bool:
	return f.has_item("grappling_hook") or f.has_rule("wall_scrambler")


## Checks a path for the declared move without changing anything.
## levels: one per waypoint (defaults to the fighter's current level). descend: "auto" | "climb" | "jump".
## Returns {"ok", "error", "cost", "length", "allowance", "deadly", "pickup_token", "crossings", "drops": [inches], "end_level"}.
static func evaluate(b: Battle, path: PackedVector2Array, pickup := false, levels := PackedFloat32Array(), descend := "auto") -> Dictionary:
	var out := {"ok": false, "error": "", "cost": 0.0, "length": 0.0, "allowance": 0.0, "deadly": 0, "pickup_token": -1,
		"crossings": 0, "drops": [], "end_level": 0.0}
	if b.move_plan.is_empty():
		out["error"] = "Declare a move first."
		return out
	var f := b.fighter(b.move_plan["uid"])
	var kind: String = b.move_plan["kind"]
	out["allowance"] = b.move_plan["allowance"]
	if path.size() < 2:
		out["error"] = "Pick a destination."
		return out
	path[0] = f.pos
	if levels.size() != path.size():
		levels = PackedFloat32Array()
		for i in path.size():
			levels.append(f.elev)
	levels[0] = f.elev
	var flying := f.has_kw("Fly")
	var length := 0.0
	var cost := 0.0
	var methods: PackedStringArray = []
	for i in range(1, path.size()):
		var seg := _segment(b, f, path[i - 1], levels[i - 1], path[i], levels[i], descend)
		if not seg["ok"]:
			out["error"] = seg["error"]
			return out
		cost += seg["cost"]
		length += path[i - 1].distance_to(path[i])
		if seg["drop"] >= 3.0:
			out["drops"].append(seg["drop"])
		if seg["method"] != "walk":
			methods.append(seg["method"])
	out["methods"] = methods
	# Floor-level crossings: low terrain, doors, windows (-1" each), deadly terrain, closed doors.
	var crossings := 0
	var deadly := 0
	if not flying:
		for t in b.terrain:
			var crossed := false
			for i in range(1, path.size()):
				if levels[i - 1] <= Height.LEVEL_EPS and levels[i] <= Height.LEVEL_EPS and Geo.segment_crosses_polygon(path[i - 1], path[i], t.polygon):
					crossed = true
			if not crossed:
				continue
			if t.costs_crossing():
				crossings += 1
			if t.kind == "deadly":
				deadly += 1
			if t.kind == "door" and t.closed and (kind != "normal" or f.category == "beast"):
				out["error"] = "Only Normal moves can pass a closed door (and never Beasts)."
				return out
	var mire := 0
	var m: Dictionary = b.scen.get("black_mire", {})
	if not m.is_empty() and not f.has_kw("Cloister") and not flying:
		if Geo.path_min_gap(path, 0.0, m["point"], 0.0) <= float(m["radius"]):
			mire = 1
	for pit in b.scen.get("pits", []):
		for i in range(1, path.size()):
			if levels[i] <= Height.LEVEL_EPS and not flying and Geo.segment_hits_circle(path[i - 1], path[i], pit["c"], pit["r"]):
				out["error"] = "Fighters on the floor can't cross the plague pit."
				return out
	cost += crossings + 2.0 * mire
	if pickup:
		cost += 1.0
	out["length"] = length
	out["cost"] = cost
	out["deadly"] = deadly
	out["crossings"] = crossings
	out["end_level"] = levels[levels.size() - 1]
	if cost > float(b.move_plan["allowance"]) + Geo.EPS:
		out["error"] = "Too far: %.1f\" of %.1f\"%s." % [cost, b.move_plan["allowance"], (" (incl. %d\" for low terrain, doors or windows)" % crossings) if crossings > 0 else ""]
		return out
	for p in path:
		if not Geo.base_inside_board(p, f.radius, b.board_size):
			out["error"] = "No part of a fighter may cross the battlefield edge."
			return out
	var end := path[path.size() - 1]
	var end_level: float = levels[levels.size() - 1]
	if not Height.supports(b, end, end_level):
		out["error"] = "The move must end on the floor or on a platform."
		return out
	var blocker := Height.base_clear(b, end, f.radius, end_level)
	if blocker != "":
		out["error"] = "The fighter's base would end overlapping %s." % blocker
		return out
	if f.has_rule("large_and_heavy") and end_level > Height.LEVEL_EPS:
		out["error"] = "Large and Heavy: must finish each move on the battlefield floor."
		return out
	var near_enemy := false
	for o in b.on_board():
		if o == f:
			continue
		var min_gap := INF
		for i in range(1, path.size()):
			var seg_lo := minf(levels[i - 1], levels[i])
			var seg_hi := maxf(levels[i - 1], levels[i])
			var v := 0.0 if (o.elev >= seg_lo - Geo.EPS and o.elev <= seg_hi + Geo.EPS) else minf(absf(o.elev - seg_lo), absf(o.elev - seg_hi))
			var h := Geo.path_min_gap(PackedVector2Array([path[i - 1], path[i]]), f.radius, o.pos, o.radius)
			if v < minf(f.height, o.height) and h < -Geo.EPS and not flying:
				out["error"] = "Fighters can't move through %s." % o.name
				return out
			min_gap = minf(min_gap, sqrt(maxf(h, 0.0) ** 2 + v * v))
		var end_gap := Height.gap3(end, f.radius, end_level, o.pos, o.radius, o.elev)
		if flying and absf(end_level - o.elev) < minf(f.height, o.height) and Geo.signed_gap(end, f.radius, o.pos, o.radius) < -Geo.EPS:
			out["error"] = "Can't end a move on top of %s." % o.name
			return out
		if o.player != f.player:
			if end_gap <= 1.0 + Geo.EPS:
				near_enemy = true
			if kind in ["normal", "run"] and min_gap < 1.0 - Geo.EPS:
				out["error"] = "A %s move can't come within 1\" of an enemy (%s)." % [kind, o.name]
				return out
			if kind == "disengage" and end_gap <= 1.0 + Geo.EPS:
				out["error"] = "A Disengage must finish more than 1\" from all enemies."
				return out
	if kind == "charge" and not near_enemy:
		out["error"] = "A Charge must finish within 1\" of an enemy."
		return out
	if pickup:
		out["pickup_token"] = treasure_in_reach(b, f, end, end_level)
		if out["pickup_token"] < 0:
			out["error"] = "No treasure within 1/2\" of the destination."
			return out
	out["ok"] = true
	return out


## One leg of a move between two waypoints. Returns {"ok", "error", "cost", "drop", "method"}.
static func _segment(b: Battle, f: FighterState, a: Vector2, la: float, c: Vector2, lc: float, descend: String) -> Dictionary:
	var h := a.distance_to(c)
	var r := f.radius
	if f.has_kw("Fly"):
		return {"ok": true, "cost": h, "drop": 0.0, "method": "fly"}
	if absf(la - lc) <= Height.LEVEL_EPS:
		if la <= Height.LEVEL_EPS:
			for t in b.terrain:
				if t.blocks_movement() and Geo.path_touches_polygon(PackedVector2Array([a, c]), r, t.polygon):
					return {"ok": false, "error": "The path runs into %s (climb it, or go round)." % t.name}
			return {"ok": true, "cost": h, "drop": 0.0, "method": "walk"}
		var air := _air_run(b, a, c, la)
		if air > Height.JUMP_MAX + Geo.EPS:
			return {"ok": false, "error": "Too far to jump across (%.1f\" through the air; max 3\")." % air}
		for t in b.terrain:
			if t.kind == "high" and t.height > la + 0.3 and Geo.path_touches_polygon(PackedVector2Array([a, c]), r * 0.5, t.polygon):
				return {"ok": false, "error": "A wall blocks the way on this level (%s)." % t.name}
		if air > 0.0 and f.has_rule("large_and_heavy"):
			return {"ok": false, "error": "Large and Heavy fighters can't jump."}
		return {"ok": true, "cost": h, "drop": 0.0, "method": "jump" if air > 0.0 else "walk"}
	var ladder := Height.ladder_between(b, a, la, c, lc, r)
	if ladder != null:
		return {"ok": true, "cost": 1.0, "drop": 0.0, "method": "ladder"}
	var climbable := can_climb(f)
	var faces := Height.climbable_near(b, a, r) if la < lc else Height.climbable_near(b, c, r)
	var top := c if la < lc else a
	var top_level := maxf(la, lc)
	var face_ok := false
	for t in faces:
		if t.height >= top_level - 0.3 and Geo.base_overlaps_polygon(top, r + 1.0, t.polygon):
			face_ok = true
	if lc > la:
		if lc - la <= Height.JUMP_UP_MAX + Geo.EPS and _air_run(b, a, c, la) <= Height.JUMP_MAX and not f.has_rule("large_and_heavy"):
			return {"ok": true, "cost": h, "drop": 0.0, "method": "jump"}
		if climbable and face_ok:
			return {"ok": true, "cost": 1.0 + h if _climbs_like_ladder(f) else (lc - la) + h, "drop": 0.0, "method": "climb"}
		return {"ok": false, "error": "Getting up there needs a ladder or a wall to climb%s." % ("" if climbable else " (this fighter can't climb)")}
	var drop := la - lc
	var can_jump := not f.has_rule("large_and_heavy")
	var air2 := _air_run(b, a, c, la)
	var jump := {"ok": true, "cost": h, "drop": drop, "method": "jump down"}
	var climb := {"ok": true, "cost": 1.0 + h if _climbs_like_ladder(f) else drop + h, "drop": 0.0, "method": "climb down"}
	var climb_ok := climbable and face_ok
	var jump_ok := can_jump and air2 <= Height.JUMP_MAX + Geo.EPS
	if descend == "climb":
		return climb if climb_ok else {"ok": false, "error": "Nothing to climb down here."}
	if descend == "jump":
		return jump if jump_ok else {"ok": false, "error": "Too far to jump (max 3\" through the air)."}
	if jump_ok and drop < 3.0:
		return jump
	if climb_ok:
		return climb
	if jump_ok:
		return jump
	return {"ok": false, "error": "Can't get down from here (jump at most 3\" out from the edge)."}


## Horizontal distance along a-c (on level `lvl`) that isn't over a surface of that level.
static func _air_run(b: Battle, a: Vector2, c: Vector2, lvl: float) -> float:
	var n := maxi(1, int(ceil(a.distance_to(c) / 0.1)))
	var air := 0.0
	var step := a.distance_to(c) / n
	for i in n:
		var p := a.lerp(c, (i + 0.5) / n)
		if not Height.supports(b, p, lvl):
			air += step
	return air


static func treasure_in_reach(b: Battle, f: FighterState, at: Vector2, level := 0.0) -> int:
	if f.treasure > 0 or f.category == "beast" or f.has_kw("Thrall"):
		return -1
	if not Scenario.can_pick_up(b, f):
		return -1
	for i in b.tokens.size():
		var t: Dictionary = b.tokens[i]
		if t["type"] == "treasure" and absf(float(t.get("elev", 0.0)) - level) < 1.0 and Geo.base_gap(at, f.radius, t["pos"], TOKEN_RADIUS) <= 0.5 + Geo.EPS:
			return i
	return -1


static func commit(b: Battle, path: PackedVector2Array, pickup := false, levels := PackedFloat32Array(), descend := "auto") -> String:
	var ev := evaluate(b, path, pickup, levels, descend)
	if not ev["ok"]:
		return ev["error"]
	var f := b.fighter(b.move_plan["uid"])
	var kind: String = b.move_plan["kind"]
	if pickup and kind != "normal":
		return "Treasure can only be picked up during a Normal move."
	f.pos = path[path.size() - 1]
	f.elev = ev["end_level"]
	f.moved = true
	f.move_kind = kind
	if kind == "charge":
		f.charged = true
	b.move_plan = {}
	var methods: PackedStringArray = ev["methods"]
	b.log_line("%s makes a %s move: %.1f\" used%s." % [f.name, kind, ev["cost"], (" (" + ", ".join(methods) + ")") if not methods.is_empty() else ""])
	for drop in ev["drops"]:
		b.mark_dice_rolled()
		Height.impact(b, f, drop, "jumping down")
	for i in ev["deadly"]:
		var dmg := b.dice.d3()
		b.mark_dice_rolled()
		b.log_line("%s crosses deadly terrain and suffers %d damage." % [f.name, dmg])
		Combat.apply_damage(b, f, dmg, null, "deadly terrain")
	if not f.on_board():
		b.changed.emit()
		return ""
	if levels.size() != path.size():
		levels = PackedFloat32Array()
		for i in path.size():
			levels.append(f.elev)
	Twists.after_path(b, f, path, levels)
	if not f.on_board():
		b.changed.emit()
		return ""
	if pickup and ev["pickup_token"] >= 0:
		Scenario.pick_up(b, f, ev["pickup_token"])
	_update_hidden(b)
	if kind == "charge":
		Combat.after_charge(b, f)
	Scenario.after_move(b, f)
	b.after_action()
	b.changed.emit()
	return ""


## A charge with no legal path: the fighter doesn't move and its activation ends immediately (p.20).
static func fail_charge(b: Battle) -> String:
	if b.move_plan.get("kind", "") != "charge":
		return "No charge declared."
	var f := b.fighter(b.move_plan["uid"])
	b.move_plan = {}
	f.moved = true
	f.move_kind = "charge"
	b.log_line("%s's charge fails; the activation ends." % f.name)
	return b.end_activation()


## Hidden fighters stop being hidden when an enemy is within 3" or they're no longer touching terrain (p.27).
static func _update_hidden(b: Battle) -> void:
	for h in b.on_board():
		if not h.statuses.get("hidden", false):
			continue
		var lost := not Effects.touching_terrain(b, h)
		for o in b.on_board():
			if o.player != h.player and Effects.near(h, o, 3.0):
				lost = true
		if lost:
			h.statuses.erase("hidden")
			b.log_line("%s is no longer hidden." % h.name)


## Moves a fighter without rules (scatter, set-up, table tools). Keeps it on the board.
static func place(b: Battle, f: FighterState, at: Vector2, level := -1.0) -> void:
	at.x = clampf(at.x, f.radius, b.board_size.x - f.radius)
	at.y = clampf(at.y, f.radius, b.board_size.y - f.radius)
	f.pos = at
	if level >= 0.0:
		f.elev = level
	elif not Height.supports(b, at, f.elev):
		var lv := Height.levels_at(b, at)
		f.elev = lv[0] if not lv.is_empty() else 0.0
	_update_hidden(b)


## Scatter (p.22): random direction; stops at high terrain or another fighter; may fall off platforms.
static func scatter(b: Battle, f: FighterState, inches: float) -> void:
	if f.is_unshakeable():
		b.log_line("%s is Unshakeable and doesn't scatter." % f.name)
		return
	var dir := b.dice.direction()
	var step := 0.1
	var travelled := 0.0
	var pos := f.pos
	var low_paid: Array = []
	var budget := inches
	while travelled + step <= budget:
		var nxt := pos + dir * step
		var stop := false
		if not Geo.base_inside_board(nxt, f.radius, b.board_size):
			stop = true
		for t in b.terrain:
			if f.elev <= Height.LEVEL_EPS and t.blocks_movement() and Geo.base_overlaps_polygon(nxt, f.radius, t.polygon):
				stop = true
			elif t.kind == "high" and t.height > f.elev + 0.3 and Geo.base_overlaps_polygon(nxt, f.radius, t.polygon):
				stop = true
			elif t.costs_crossing() and not t in low_paid and f.elev <= Height.LEVEL_EPS and Geo.base_overlaps_polygon(nxt, f.radius, t.polygon):
				low_paid.append(t)
				budget -= 1.0
		for o in b.on_board():
			if o != f and absf(o.elev - f.elev) < 1.0 and Geo.signed_gap(nxt, f.radius, o.pos, o.radius) <= 0.0:
				stop = true
		if stop:
			break
		if f.elev > Height.LEVEL_EPS and not Height.supports(b, nxt, f.elev):
			var t2 := b.dice.test(int(f.stats["initiative"]))
			if t2["pass"]:
				b.log_line("%s stops at the platform edge (rolled %d)." % [f.name, t2["roll"]])
				break
			b.log_line("%s scatters off the edge (rolled %d)!" % [f.name, t2["roll"]])
			var from := f.elev
			pos = nxt + dir * f.radius
			f.pos = pos
			f.elev = Height.level_below(b, pos, from)
			Height.impact(b, f, from - f.elev)
			if not f.on_board():
				return
			continue
		pos = nxt
		travelled += step
	b.log_line("%s scatters %.1f\"." % [f.name, f.pos.distance_to(pos)])
	f.pos = pos
	_update_hidden(b)
