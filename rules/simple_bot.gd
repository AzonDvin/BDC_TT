class_name SimpleBot
extends RefCounted
## A very simple automatic player: answers decisions sensibly and plays activations by moving toward,
## charging, shooting and fighting the nearest enemy. Used by tests to play whole battles headlessly,
## and by the UI's "Auto" buttons. It only ever uses the public Battle API, so it can't break the rules.


static func answer(b: Battle) -> String:
	var p := b.pending
	match p.get("type", ""):
		"choose_first":
			return b.respond({"player": p["player"]})
		"surge_or_pass":
			var s := b.can_surge(p["player"])
			if s.is_empty():
				return b.respond({"pass": true})
			return b.respond({"uid": s[0].uid})
		"flee_test":
			return b.respond({"voluntary": false})
		"deploy", "place":
			return b.respond({"auto": true})
		"pick_entry":
			return b.respond({"corner": 0})
		"pick_reserve_group":
			return b.respond({"group": p["groups"][0]})
		"melee_weapons":
			var f := b.fighter(p["uid"])
			var dw := Combat.default_weapons(f)
			return b.respond({"weapons": Combat.weapon_ids(f, dw[0], dw[1])})
		"duel_turn":
			var opts := Combat.duel_options(b)
			if opts.is_empty():
				return "no duel options"
			return b.respond(opts[0]["choice"])
		"volley":
			return b.respond({"targets": []})
		"pick_quarter":
			return b.respond({"quarter": 0})
		"pick_fighter":
			return b.respond({"uid": p["candidates"][0]})
	return "unknown pending %s" % p.get("type", "")


static func nearest_enemy(b: Battle, f: FighterState) -> FighterState:
	var best: FighterState = null
	for o in b.on_board(b.other(f.player)):
		if best == null or f.pos.distance_to(o.pos) < f.pos.distance_to(best.pos):
			best = o
	return best


## Plays the active fighter's whole activation.
static func play_activation(b: Battle) -> void:
	var f := b.active_fighter()
	if f == null:
		return
	var e := nearest_enemy(b, f)
	if e != null and Effects.is_engaged(b, f) and b.can_still_act(f):
		var t: FighterState = Effects.engaged_enemies(b, f)[0]
		Combat.start_melee(b, t.uid, {})
		var guard := 0
		while not b.pending.is_empty() and guard < 60:
			guard += 1
			answer(b)
		if b.active != f.uid:
			return
	elif e != null and b.can_still_move(f) and not Effects.is_engaged(b, f):
		var gap := Effects.dist(f, e)
		var shooter := not f.usable_ranged().is_empty() and f.stats["bow"] != null
		if gap < 9.0 and not f.acted and not shooter:
			if Movement.declare(b, "charge") == "" and not b.move_plan.is_empty():
				var dir := (e.pos - f.pos).normalized()
				var dist := f.pos.distance_to(e.pos) - f.radius - e.radius - 0.4
				var path := PackedVector2Array([f.pos, f.pos + dir * dist])
				if Movement.commit(b, path) != "":
					Movement.fail_charge(b)
					return
		elif Movement.declare(b, "normal") == "":
			var dir2 := (e.pos - f.pos).normalized()
			var allowance: float = b.move_plan["allowance"]
			var want := minf(allowance - 0.2, f.pos.distance_to(e.pos) - f.radius - e.radius - 1.3)
			var moved := false
			for k in 6:
				var ang: float = [0.0, 0.5, -0.5, 1.0, -1.0, 1.6][k]
				var path2 := PackedVector2Array([f.pos, f.pos + dir2.rotated(ang) * maxf(want, 0.5)])
				if Movement.commit(b, path2) == "":
					moved = true
					break
			if not moved:
				Movement.cancel(b)
	if b.active != f.uid:
		return
	if b.can_still_act(f) and not Effects.is_engaged(b, f):
		for w in f.usable_ranged():
			if Combat.check_can_shoot(b, f, w) != "":
				continue
			if Effects.weapon_has(f, w, "Flame"):
				var en := nearest_enemy(b, f)
				if en and f.pos.distance_to(en.pos) < 8.0:
					Combat.shoot_flame(b, w["id"], en.pos - f.pos)
				break
			if Effects.weapon_has(f, w, "Blast"):
				var en2 := nearest_enemy(b, f)
				if en2 and f.pos.distance_to(en2.pos) - f.radius <= Effects.range_for(b, f, w) and Combat.point_visible(b, f.pos, en2.pos, [f, en2]):
					Combat.shoot_blast(b, w["id"], en2.pos)
				break
			for t2 in Combat.ranged_targets(b, f, w):
				if t2["legal"]:
					Combat.shoot(b, w["id"], t2["uid"])
					break
			break
		while b.pending.get("type", "") == "volley":
			answer(b)
	if b.active == f.uid and b.can_still_act(f) and f.is_caster() and not f.prepared.is_empty():
		var en3 := nearest_enemy(b, f)
		for s in f.prepared:
			var info := Magic.spell_info(s["name"])
			var params := {}
			match info["target"]:
				"closest", "none":
					pass
				"dir":
					if en3:
						params["dir"] = en3.pos - f.pos
				"point":
					if en3:
						params["point"] = en3.pos
				_:
					continue
			if Magic.cast(b, s["name"], params) == "":
				break
	if b.active == f.uid and b.pending.is_empty():
		b.end_activation()


## Advances the battle by one decision or activation. Returns false when nothing more can happen.
static func step(b: Battle) -> bool:
	if b.is_over():
		return false
	if not b.pending.is_empty():
		var err := answer(b)
		return err == ""
	if b.phase != "activation":
		return false
	if b.active >= 0:
		play_activation(b)
		return true
	var cands := b.can_activate_normally(b.turn)
	if cands.is_empty():
		return false
	if b.activate(cands[0].uid) != "":
		return false
	return true
