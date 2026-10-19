class_name Twists
extends RefCounted
## Scenario twists (Chapter 3) and lingering spell effects (Eldritch Barrier, Umbral Vortex, Plague Pit).
## Scenario calls these hooks; state lives in battle.scen. Twists that need a player's choice at the start of a
## round use pending decisions ("pick_quarter", "pick_fighter") answered through Battle.respond().


# --- Set-up ----------------------------------------------------------------------------------------

static func setup_extra(b: Battle) -> void:
	var tw: String = b.scen.get("twist_id", "")
	var c := Scenario.center(b)
	match tw:
		"the_chest":
			# The underdog places the chest wholly within 6" of an entry point nobody picked: placed once entries are known.
			b.scen["chest_pending"] = true
		"saint_tricksters_game":
			for i in range(b.tokens.size() - 1, -1, -1):
				if b.tokens[i]["type"] == "treasure":
					b.tokens.remove_at(i)
			b.tokens.append({"type": "treasure", "pos": c + b.dice.direction() * b.dice.rng.randf_range(0.0, 2.5), "elev": 0.0, "trickster": true})
			b.scen["trickster_left"] = 4
		"hidden_tunnel":
			var a := _open_spot(b, func(p): return p.y < 14.5 or p.y > 21.5)
			var other := Vector2.INF
			for k in 200:
				var q := a + b.dice.direction() * b.dice.rng.randf_range(3.0, 6.0)
				if (q.y < 14.5 or q.y > 21.5) and q.x > 1 and q.y > 1 and q.x < b.board_size.x - 1 and q.y < b.board_size.y - 1 and Height.supports(b, q, 0.0):
					other = q
					break
			if a != Vector2.INF and other != Vector2.INF:
				b.tokens.append({"type": "tunnel", "pos": a, "elev": 0.0})
				b.tokens.append({"type": "tunnel", "pos": other, "elev": 0.0})
				b.log_line("Two hidden tunnel entrances are marked (only the Hit can use them).")
		"barricaded_holdout":
			var n := b.dice.d3()
			var edges := [[Vector2(c.x, c.y - 4), 0.0], [Vector2(c.x + 4, c.y), PI / 2], [Vector2(c.x, c.y + 4), 0.0], [Vector2(c.x - 4, c.y), PI / 2]]
			for i in n:
				var e: Array = edges[i]
				b.terrain.append(TerrainPiece.make("Barricade", "high", Geo.rect_polygon(e[0], Vector2(4.5, 0.25), e[1]), 2.0))
			b.log_line("The Defender raises %d barricade wall(s) around the holding." % n)
		"drunk_as_an_eel":
			for f in b.fighters:
				if "hit" in f.marks and not (f.has_kw("Demon") or f.has_kw("Undead")):
					f.statuses["drunk"] = true


## Called once entry points are known (after pick_entry).
static func after_entries(b: Battle) -> void:
	if b.scen.get("chest_pending", false):
		b.scen.erase("chest_pending")
		var taken: Array = b.scen["entry"]
		for i in 4:
			if not i in taken:
				var corner: Vector2 = Scenario.corners(b)[i]
				var p := corner + (Scenario.center(b) - corner).normalized() * 4.0
				b.tokens.append({"type": "chest", "pos": p, "elev": 0.0})
				b.log_line("The underdog places the chest near an unclaimed entry point.")
				break


static func _open_spot(b: Battle, ok: Callable) -> Vector2:
	for k in 300:
		var p := Vector2(b.dice.rng.randf_range(3, b.board_size.x - 3), b.dice.rng.randf_range(3, b.board_size.y - 3))
		if ok.call(p) and _clear_floor(b, p):
			return p
	return Vector2.INF


static func _clear_floor(b: Battle, p: Vector2) -> bool:
	for t in b.terrain:
		if t.blocks_movement() and Geo.base_overlaps_polygon(p, 0.8, t.polygon):
			return false
	return true


# --- Start of round --------------------------------------------------------------------------------

static func start_of_round_auto(b: Battle) -> void:
	var tw: String = b.scen.get("twist_id", "")
	match tw:
		"rolling_fog":
			if not b.scen.get("fog_lifted", false):
				var fog: Array = []
				var rolls: PackedStringArray = []
				for q in 4:
					var r := b.dice.d6()
					rolls.append(str(r))
					if r >= 4:
						fog.append(q)
				if fog.is_empty():
					b.scen["fog_lifted"] = true
					b.scen.erase("fog")
					b.log_line("Rolling Fog (%s): the fog lifts for good." % ", ".join(rolls))
				else:
					b.scen["fog"] = fog
					b.log_line("Rolling Fog (%s): fog masks quarter(s) %s — no sight beyond 6\" there." % [", ".join(rolls), ", ".join(fog.map(func(q): return str(q + 1)))])
		"the_critical_quarter":
			if b.round_no >= 3:
				b.scen["critical_quarter"] = b.dice.rng.randi_range(0, 3)
				b.log_line("The critical quarter this round is quarter %d (+1 domination)." % (b.scen["critical_quarter"] + 1))
		"on_fire":
			var stage: int = b.scen.get("fire", 0)
			if stage < 2:
				var r2 := b.dice.d6()
				if r2 >= 4:
					b.scen["fire"] = stage + 1
					b.log_line("The fire in the holding grows (rolled %d): %s!" % [r2, "a BLAZE" if stage == 0 else "an INFERNO"])


## Choices some twists offer at the start of a round, asked one at a time: [pending dicts].
static func start_of_round_choices(b: Battle) -> Array:
	var tw: String = b.scen.get("twist_id", "")
	var out: Array = []
	if tw == "the_forsaken_quarter" and b.round_no >= 4:
		var m: Array = b.scen["marks"]
		if m[0] != m[1]:
			out.append({"type": "pick_quarter", "player": 0 if m[0] < m[1] else 1, "purpose": "forsaken"})
	if tw == "condemned":
		var vp: Array = b.scen["vp"]
		if vp[0] != vp[1]:
			var p := 0 if vp[0] < vp[1] else 1
			var cands: Array = []
			for f in b.on_board(b.other(p)):
				cands.append(f.uid)
			if not cands.is_empty():
				out.append({"type": "pick_fighter", "player": p, "purpose": "condemned", "candidates": cands})
	return out


static func respond(b: Battle, choice: Dictionary) -> String:
	var p := b.pending
	match p.get("purpose", ""):
		"forsaken":
			var q := int(choice.get("quarter", -1))
			if q >= 0:
				b.scen["forsaken_quarter"] = q
				b.log_line("%s declares quarter %d forsaken: it can't be controlled this round." % [b.player_names[p["player"]], q + 1])
		"condemned":
			var uid := int(choice.get("uid", -1))
			if uid >= 0 and not uid in p["candidates"]:
				return "Pick one of the enemy fighters."
			if uid >= 0:
				b.scen["condemned"] = uid
				b.log_line("%s condemns %s: taking them down this round is worth +1 VP." % [b.player_names[p["player"]], b.fighter(uid).name])
	b.pending = {}
	Scenario.continue_start_of_round(b)
	return ""


# --- Activations and moves ---------------------------------------------------------------------------

## Returns false if the activation ends immediately.
static func start_of_activation(b: Battle, f: FighterState) -> bool:
	if f.statuses.get("drunk", false):
		if f.statuses.get("damaged_ever", false) or Effects.is_engaged(b, f):
			f.statuses.erase("drunk")
			b.log_line("%s sobers up." % f.name)
		else:
			var r := b.dice.d6()
			if r == 6:
				f.statuses.erase("drunk")
				b.log_line("%s sobers up (rolled 6)." % f.name)
			else:
				b.log_line("%s is drunk as an eel (rolled %d): they stagger about and their activation ends." % [f.name, r])
				Movement.scatter(b, f, b.dice.d6())
				return false
	for bar in b.scen.get("barriers", []):
		if _barrier_live(b, bar) and absf(f.elev - float(bar["elev"])) < 1.5 and Geometry2D.get_closest_point_to_segment(f.pos, bar["a"], bar["b"]).distance_to(f.pos) <= f.radius + 0.1:
			var d := b.dice.d3()
			b.log_line("%s is caught in the Eldritch Barrier: %d damage." % [f.name, d])
			Combat.apply_damage(b, f, d, null, "Eldritch Barrier")
	var v: Dictionary = b.scen.get("vortex", {})
	if not v.is_empty() and absf(f.elev - float(v["elev"])) < 3.0 and f.pos.distance_to(v["c"]) - f.radius <= float(v["r"]):
		b.log_line("%s starts in the Umbral Vortex." % f.name)
		_vortex_hit(b, f)
	return f.on_board()


## After a committed move: crossing barriers, vortices and burning holdings.
static func after_path(b: Battle, f: FighterState, path: PackedVector2Array, levels: PackedFloat32Array) -> void:
	for bar in b.scen.get("barriers", []):
		if not _barrier_live(b, bar):
			continue
		for i in range(1, path.size()):
			if absf(levels[i] - float(bar["elev"])) < 1.5 and Geometry2D.segment_intersects_segment(path[i - 1], path[i], bar["a"], bar["b"]) != null:
				var d := b.dice.d3()
				b.log_line("%s moves across the Eldritch Barrier: %d damage." % [f.name, d])
				Combat.apply_damage(b, f, d, null, "Eldritch Barrier")
				break
	var v: Dictionary = b.scen.get("vortex", {})
	if not v.is_empty() and f.on_board():
		for i in range(1, path.size()):
			if absf(levels[i] - float(v["elev"])) < 3.0 and Geometry2D.get_closest_point_to_segment(v["c"], path[i - 1], path[i]).distance_to(v["c"]) <= float(v["r"]) + f.radius:
				b.log_line("%s moves across the Umbral Vortex." % f.name)
				_vortex_hit(b, f)
				break
	if b.scen.get("fire", 0) >= 1 and f.on_board():
		var hold := Rect2(Scenario.center(b) - Vector2(4, 4), Vector2(8, 8))
		for i in range(1, path.size()):
			if levels[i] <= Height.LEVEL_EPS and _segment_hits_rect(path[i - 1], path[i], hold):
				var d2 := b.dice.d3()
				b.log_line("%s passes through the burning holding: %d damage." % [f.name, d2])
				Combat.apply_damage(b, f, d2, null, "fire")
				break


static func _segment_hits_rect(a: Vector2, c: Vector2, r: Rect2) -> bool:
	return Geo.segment_crosses_polygon(a, c, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))


static func _barrier_live(b: Battle, bar: Dictionary) -> bool:
	var caster := b.fighter(int(bar.get("caster", -1)))
	return caster != null and caster.on_board()


static func _vortex_hit(b: Battle, f: FighterState) -> void:
	var v: Dictionary = b.scen["vortex"]
	var caster := b.fighter(int(v.get("caster", -1)))
	Combat.resolve_hit(b, caster, f, {"name": "Umbral Vortex", "rend": int(v["rend"]), "damage": str(v["damage"]), "crit": null, "traits": [], "kind": "spell"}, false, {"melee": false, "rend": int(v["rend"])})


## -1 to a ranged attack whose line crosses an Eldritch Barrier.
static func ranged_penalty(b: Battle, att: FighterState, tgt: FighterState) -> int:
	for bar in b.scen.get("barriers", []):
		if _barrier_live(b, bar) and Geometry2D.segment_intersects_segment(att.pos, tgt.pos, bar["a"], bar["b"]) != null:
			return -1
	return 0


# --- Treasure and taking down ------------------------------------------------------------------------

static func after_pick_up(b: Battle, token: Dictionary) -> void:
	if token.get("trickster", false) and int(b.scen.get("trickster_left", 0)) > 0:
		b.scen["trickster_left"] = int(b.scen["trickster_left"]) - 1
		var dist := b.dice.d6() + b.dice.d6() + b.dice.d6()
		var p := Combat.scatter_point(b, Scenario.center(b), float(dist))
		b.tokens.append({"type": "treasure", "pos": p, "elev": 0.0, "trickster": true})
		b.log_line("Saint Trickster laughs: another treasure appears %d\" from the centre." % dist)


static func on_taken_down(b: Battle, f: FighterState) -> void:
	if b.scen.get("condemned", -1) == f.uid:
		var opp := b.other(f.player)
		b.scen["vp"][opp] += 1
		b.log_line("%s was condemned: +1 more VP for %s." % [f.name, b.player_names[opp]])


static func flee_autopass(b: Battle, p: int) -> bool:
	for t in b.tokens:
		if t["type"] == "chest":
			for f in b.on_board(p):
				if (f.has_kw("Leader") or f.has_kw("Champion")) and Geo.within(f.pos, f.radius, t["pos"], 0.5, 3.0):
					b.log_line("%s guards the chest: Flee test passed automatically." % b.player_names[p])
					return true
	return false


# --- End of round / battle ---------------------------------------------------------------------------

static func end_of_round(b: Battle) -> void:
	for t in b.tokens:
		if t["type"] == "chest":
			var near := [false, false]
			for f in b.on_board():
				if Geo.within(f.pos, f.radius, t["pos"], 0.5, 3.0):
					near[f.player] = true
			for p in 2:
				if near[p] and not near[1 - p]:
					b.scen["vp"][p] += 1
					b.log_line("%s holds the chest: +1 VP (%d)." % [b.player_names[p], b.scen["vp"][p]])
	if b.scen.get("fire", 0) >= 2:
		var hold := Rect2(Scenario.center(b) - Vector2(4, 4), Vector2(8, 8))
		for i in range(b.tokens.size() - 1, -1, -1):
			var tk: Dictionary = b.tokens[i]
			if tk["type"] == "treasure" and hold.has_point(tk["pos"]) and b.dice.d6() >= 4:
				b.tokens.remove_at(i)
				b.log_line("Treasure in the holding is consumed by the inferno.")



## Round-long effects end after the end-of-round scoring.
static func clear_round(b: Battle) -> void:
	for k in ["barriers", "vortex", "pits", "condemned", "critical_quarter", "forsaken_quarter"]:
		b.scen.erase(k)


static func on_battle_end(b: Battle, winner: int) -> void:
	if winner < 0:
		return
	for t in b.tokens:
		if t["type"] == "chest":
			var r := b.dice.d6()
			var txt := "Empty all along."
			if r >= 2 and r <= 5:
				txt = "A modest find: %d silver." % (b.dice.d6() * 10)
			elif r == 6:
				txt = "A stash of silver: %d silver." % ((b.dice.d6() + b.dice.d6() + b.dice.d6()) * 5)
			b.log_line("%s claims the chest (rolled %d): %s" % [b.player_names[winner], r, txt])
	if b.scen.get("twist_id", "") == "the_saints_sarcophagus" and not b.scen.get("lid_off", false):
		var r2 := b.dice.d6()
		b.log_line("%s pries off the sarcophagus lid after the battle (rolled %d): %s." % [b.player_names[winner], r2, ["", "Unholy Curse", "Rotten Black Mulch", "Rotten Black Mulch", "Rotten Black Mulch", "Coin Purse (3d6x5 silver)", "Heirloom (roll on the relic table)"][r2]])


# --- Hidden Tunnel (Street of Death) -------------------------------------------------------------

static func tunnel_index_near(b: Battle, f: FighterState) -> int:
	if not "hit" in f.marks or f.elev > Height.LEVEL_EPS or Effects.is_engaged(b, f) or not f.moved:
		return -1
	for i in b.tokens.size():
		if b.tokens[i]["type"] == "tunnel" and Geo.base_gap(f.pos, f.radius, b.tokens[i]["pos"], 0.4) <= 0.5 + Geo.EPS:
			return i
	return -1


static func use_tunnel(b: Battle, f: FighterState) -> String:
	var i := tunnel_index_near(b, f)
	if i < 0:
		return "The Hit must finish a move within 1/2\" of a tunnel entrance, not engaged."
	var other := -1
	for j in b.tokens.size():
		if j != i and b.tokens[j]["type"] == "tunnel":
			other = j
	if other < 0:
		return "No exit."
	var exit_pos: Vector2 = b.tokens[other]["pos"]
	var spot := Scenario.find_spot(b, f, exit_pos, 1.0)
	if spot == Vector2.INF:
		spot = exit_pos
	f.pos = spot
	f.elev = 0.0
	for j in [maxi(i, other), mini(i, other)]:
		b.tokens.remove_at(j)
	b.log_line("%s slips through the hidden tunnel!" % f.name)
	Scenario.after_move(b, f)
	b.changed.emit()
	return ""
