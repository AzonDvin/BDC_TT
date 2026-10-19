class_name AI
extends RefCounted
## The computer player. battle.cfg["ai"] = [controller for player 0, controller for player 1]:
##   ""       a human plays
##   "easy"   SimpleBot (moves straight at the enemy, takes whatever action is to hand)
##   "normal" this planner: pathfinding, objectives, cover, charge odds, target choice, sensible melee and magic.
## It only uses the public rules API (Options, Movement, Combat, Magic, respond), so it can't break the rules.
## It never rolls the battle's dice for its own choices, so it can't change the luck of the game.


## The last move the AI made: {"uid", "path"} (for the view to animate). Not part of the battle state.
static var last_move := {}


## Commits a move and remembers its path (and the level of each waypoint).
static func _commit(b: Battle, path: PackedVector2Array, pickup := false, levels := PackedFloat32Array()) -> bool:
	var uid := b.active
	if Movement.commit(b, path, pickup, levels) != "":
		return false
	last_move = {"uid": uid, "path": path, "levels": levels}
	return true


static func controller(b: Battle, p: int) -> String:
	var ai: Array = b.cfg.get("ai", ["", ""])
	return str(ai[p]) if p >= 0 and p < ai.size() else ""


static func is_ai(b: Battle, p: int) -> bool:
	return controller(b, p) != ""


## Which player must act now, or -1.
static func decider(b: Battle) -> int:
	if b.is_over():
		return -1
	if not b.pending.is_empty():
		return int(b.pending.get("player", -1))
	if b.phase == "activation":
		return b.turn
	return -1


static func should_act(b: Battle) -> bool:
	var p := decider(b)
	return p >= 0 and is_ai(b, p)


## Does one thing for the computer player (answer a decision, pick a fighter, or one part of an activation).
## Returns false if there was nothing for it to do.
static func step(b: Battle) -> bool:
	var p := decider(b)
	if p < 0 or not is_ai(b, p):
		return false
	if controller(b, p) == "easy":
		return SimpleBot.step(b)
	if not b.pending.is_empty():
		return _answer(b) == ""
	if b.active < 0:
		var pick := _choose_fighter(b, p)
		if pick == null:
			return false
		b.scen["ai_tried"] = {}
		b.scen["ai_steps"] = 0
		return b.activate(pick.uid) == ""
	var f := b.active_fighter()
	if f == null or f.player != p:
		return false
	return _act(b, f)


static func _rng(b: Battle) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([b.dice.rng.seed, b.round_no, b.active, b.history.size()])
	return r


# =============================================================================================
# Decisions

static func _answer(b: Battle) -> String:
	var p := b.pending
	var me: int = p.get("player", 0)
	match p.get("type", ""):
		"choose_first":
			return b.respond({"player": me})
		"surge_or_pass":
			var best: FighterState = null
			var best_s := -INF
			for f in b.can_surge(me):
				var s := _activation_score(b, f)
				if s > best_s:
					best_s = s
					best = f
			return b.respond({"pass": true} if best == null else {"uid": best.uid})
		"flee_test":
			return b.respond({"voluntary": false})
		"deploy", "place":
			return b.respond({"auto": true})
		"pick_entry":
			return b.respond({"corner": _rng(b).randi_range(0, 3)})
		"pick_reserve_group":
			var best_g: int = p["groups"][0]
			var best_n := -1
			for g in p["groups"]:
				var n := 0
				for f in b.fighters:
					if f.player == me and f.where == "reserve" and f.battle_group == g:
						n += 1
				if n > best_n:
					best_n = n
					best_g = g
			return b.respond({"group": best_g})
		"melee_weapons":
			var d := b.fighter(p["uid"])
			var dw := Combat.default_weapons(d)
			return b.respond({"weapons": Combat.weapon_ids(d, dw[0], dw[1]), "net": d.has_item("net"), "stand_ground": d.has_rule("stand_ground")})
		"duel_turn":
			return b.respond(_duel_choice(b))
		"volley":
			return b.respond({"targets": []})
		"pick_quarter":
			var bestq := 0
			var best_lead := -INF
			for q in 4:
				var lead := 0.0
				for f in b.on_board():
					if Scenario.quarter_of(b, f) == q:
						lead += 1.0 if f.player != me else -1.0
				if lead > best_lead:
					best_lead = lead
					bestq = q
			return b.respond({"quarter": bestq})
		"pick_fighter":
			var bu: int = p["candidates"][0]
			var bv := -INF
			for uid in p["candidates"]:
				var v := _fighter_value(b.fighter(uid))
				if v > bv:
					bv = v
					bu = uid
			return b.respond({"uid": bu})
	return "unknown decision"


static func _fighter_value(f: FighterState) -> float:
	var v := float(Catalog.fighter_def(f.faction, f.def_id).get("cost", 50))
	if f.has_kw("Leader"):
		v += 80
	if "hit" in f.marks:
		v += 200
	if f.treasure > 0:
		v += 60
	return v


## Melee duel: parry dangerous blows (crits, or anything that would take us down), otherwise strike.
static func _duel_choice(b: Battle) -> Dictionary:
	var opts := Combat.duel_options(b)
	if opts.is_empty():
		return {}
	var me_uid: int = b.duel["turn"]
	var foe_uid: int = b.duel["def"] if me_uid == b.duel["att"] else b.duel["att"]
	var me := b.fighter(me_uid)
	var foe := b.fighter(foe_uid)
	var theirs: Array = b.duel["rolls"][str(foe_uid)]
	var mine: Array = b.duel["rolls"][str(me_uid)]
	var best_parry := {}
	var best_threat := 0.0
	for o in opts:
		if o["choice"]["action"] != "parry":
			continue
		var t: Dictionary = theirs[int(o["choice"]["target"])]
		var threat := _die_damage(foe, t)
		if threat > best_threat:
			best_threat = threat
			best_parry = o["choice"]
	var best_attack := {}
	var best_dmg := -1.0
	for o in opts:
		if o["choice"]["action"] != "attack":
			continue
		var d := _die_damage(me, mine[int(o["choice"]["die"])])
		if d > best_dmg:
			best_dmg = d
			best_attack = o["choice"]
	if not best_parry.is_empty() and (best_threat >= me.life or best_threat >= 2.5) and not (not best_attack.is_empty() and best_dmg >= foe.life):
		return best_parry
	if not best_attack.is_empty():
		return best_attack
	return best_parry if not best_parry.is_empty() else opts[0]["choice"]


static func _die_damage(owner: FighterState, die: Dictionary) -> float:
	var w := owner.weapon_by_id(die.get("w", ""))
	if w.is_empty():
		return 1.0
	var expr = w.get("crit") if die.get("crit", false) and w.get("crit") != null else w.get("damage", "1")
	return Dice.average(str(expr))


# =============================================================================================
# Choosing who activates

static func _choose_fighter(b: Battle, p: int) -> FighterState:
	var best: FighterState = null
	var best_s := -INF
	for f in b.can_activate_normally(p):
		var s := _activation_score(b, f)
		if s > best_s:
			best_s = s
			best = f
	return best


static func _activation_score(b: Battle, f: FighterState) -> float:
	if Effects.is_engaged(b, f):
		return 10.0 + f.life * 0.1
	if f.treasure > 0:
		return 9.0
	var e := _nearest_enemy(b, f)
	if e == null:
		return 1.0
	var gap := Effects.dist(f, e)
	var crowd := 0
	for o in b.on_board(f.player):
		if o != f and Geo.signed_gap(f.pos, f.radius, o.pos, o.radius) < 0.4:
			crowd += 1
	if not _is_shooter(f) and gap <= _move_of(f) + 3.0:
		return 8.0
	for w in f.usable_ranged():
		if _could_shoot(f, w) and _any_legal_target(b, f, w):
			return 7.0
	if f.is_caster():
		return 6.0
	return 3.0 - gap * 0.02 - crowd * 0.5


## Rough check for a fighter that isn't activating yet (Combat.check_can_shoot needs the active fighter).
static func _could_shoot(f: FighterState, w: Dictionary) -> bool:
	return f.stats["bow"] != null and not w["id"] in f.lost_weapons and not w["id"] in f.needs_reload and not ("used:" + w["id"]) in f.once_per_battle


static func _move_of(f: FighterState) -> float:
	return 7.0 if str(f.stats["move"]) == "2d6" else float(f.stats["move"])


static func _is_shooter(f: FighterState) -> bool:
	if f.stats["bow"] == null or int(f.stats["bow"]) > 5:
		return false
	for w in f.usable_ranged():
		if str(w.get("range", "0")) == "flame" or float(w.get("range", 0)) >= 8.0:
			return true
	return false


static func _nearest_enemy(b: Battle, f: FighterState) -> FighterState:
	var best: FighterState = null
	for o in b.on_board(b.other(f.player)):
		if best == null or Effects.dist(f, o) < Effects.dist(f, best):
			best = o
	return best


static func _any_legal_target(b: Battle, f: FighterState, w: Dictionary) -> bool:
	if Effects.weapon_has(f, w, "Blast") or Effects.weapon_has(f, w, "Flame"):
		var e := _nearest_enemy(b, f)
		return e != null and Effects.dist(f, e) <= maxf(Effects.range_for(b, f, w), 7.0)
	for t in Combat.ranged_targets(b, f, w):
		if t["legal"]:
			return true
	return false


# =============================================================================================
# One activation, a step at a time

static func _tried(b: Battle, key: String) -> bool:
	return b.scen.get("ai_tried", {}).has(key)


static func _mark(b: Battle, key: String) -> void:
	var d: Dictionary = b.scen.get("ai_tried", {})
	d[key] = true
	b.scen["ai_tried"] = d


static func _act(b: Battle, f: FighterState) -> bool:
	# What this activation has tried so far (reset whenever a new activation starts, however it was started).
	var this_activation := [b.round_no, f.uid, b.active_is_surge]
	if b.scen.get("ai_for", []) != this_activation:
		b.scen["ai_for"] = this_activation
		b.scen["ai_tried"] = {}
		b.scen["ai_steps"] = 0
	b.scen["ai_steps"] = int(b.scen.get("ai_steps", 0)) + 1
	if int(b.scen["ai_steps"]) > 12:
		b.end_activation()
		return true
	var o := Options.for_active(b)
	var engaged := Effects.is_engaged(b, f)
	# Abilities worth using at once (Rallying Cry, auras that boost a fight, the Lycanfell's transformation...).
	if not _tried(b, "abilities"):
		_mark(b, "abilities")
		if _use_good_ability(b, f, engaged):
			return true
	if engaged:
		if o["actions"]["melee"] == "" and not _tried(b, "melee"):
			_mark(b, "melee")
			var t := _best_melee_target(b, f)
			if t != null and Combat.start_melee(b, t.uid, {}) == "":
				return true
		b.end_activation()
		return true
	# Not engaged: a caster with an attack spell blasts the enemy now if it can (then may still make a normal move).
	if not f.acted and _battle_mage(f) and not _tried(b, "spell_first"):
		_mark(b, "spell_first")
		var atk := _best_attack_spell(b, f)
		if not atk.is_empty() and Magic.cast(b, atk["name"], atk["params"]) == "":
			return true
	# Shoot or cast first when it is already worth it (and always with a Heavy weapon, which can't move first).
	if not f.acted and not _tried(b, "shoot_first"):
		_mark(b, "shoot_first")
		var shot := _best_shot(b, f)
		if not shot.is_empty() and (shot["heavy"] or shot["ev"] >= 0.5 or not _wants_to_move(b, f)):
			if _fire(b, f, shot):
				return true
		var sp := _best_spell(b, f)
		if not sp.is_empty() and sp["value"] >= 1.0:
			if Magic.cast(b, sp["name"], sp["params"]) == "":
				return true
	# Casters with attack spells fight with magic: they don't charge into melee.
	if not f.moved and o["moves"]["charge"] == "" and not _is_shooter(f) and not _battle_mage(f) and not _tried(b, "charge"):
		_mark(b, "charge")
		if _try_charge(b, f):
			return true
	# Long-range shooters make for high ground (roofs, upper floors) when no enemy is close.
	if not f.moved and o["moves"]["normal"] == "" and not _tried(b, "climb"):
		_mark(b, "climb")
		if _try_climb(b, f):
			return true
	if not f.moved and o["moves"]["normal"] == "" and not _tried(b, "pickup"):
		_mark(b, "pickup")
		if _try_pickup(b, f):
			return true
	if not f.moved and o["moves"]["normal"] == "" and not _tried(b, "move") and _wants_to_move(b, f):
		_mark(b, "move")
		if _do_move(b, f):
			return true
	# After moving: fight if the charge landed, else shoot, cast, hide or draw power.
	if Effects.is_engaged(b, f):
		return _act(b, f) if not _tried(b, "melee") else _end(b)
	o = Options.for_active(b)
	if not f.acted and not _tried(b, "action"):
		_mark(b, "action")
		var shot2 := _best_shot(b, f)
		if not shot2.is_empty() and _fire(b, f, shot2):
			return true
		# Casters: an attack spell first; then power up while no enemy is within 6"; then a clearly useful other spell.
		var atk2 := _best_attack_spell(b, f)
		if not atk2.is_empty() and Magic.cast(b, atk2["name"], atk2["params"]) == "":
			return true
		var sp2 := _best_spell(b, f)
		if not sp2.is_empty() and sp2["value"] >= 1.5 and Magic.cast(b, sp2["name"], sp2["params"]) == "":
			return true
		if _should_draw_power(b, f) and o["actions"].get("draw_power", "x") == "":
			if Magic.draw_power(b) == "":
				return true
		if not sp2.is_empty() and Magic.cast(b, sp2["name"], sp2["params"]) == "":
			return true
		if o["actions"].get("hide", "x") == "" and not _is_objective_runner(b, f):
			if Combat.hide(b) == "":
				return true
		if o["actions"].get("draw_power", "x") == "":
			if Magic.draw_power(b) == "":
				return true
		for wid in f.needs_reload:
			if Combat.reload_weapon(b, wid, "action") == "":
				return true
	return _end(b)


static func _end(b: Battle) -> bool:
	if b.active >= 0 and b.pending.is_empty():
		b.end_activation()
	return true


static func _wants_to_move(b: Battle, f: FighterState) -> bool:
	var e := _nearest_enemy(b, f)
	if e == null:
		return true
	# A long-range shooter on high ground holds it while there is an enemy in range.
	if f.elev >= HIGH_GROUND and _long_shooter(f) and Effects.dist(f, e) <= _best_range(b, f) + 2.0:
		return false
	return Effects.dist(f, e) > 1.5


static func _is_objective_runner(b: Battle, f: FighterState) -> bool:
	return f.treasure > 0 or "hit" in f.marks


static func _use_good_ability(b: Battle, f: FighterState, engaged: bool) -> bool:
	for a in Abilities.list(b, f):
		if a["needs"] != "none":
			continue
		var id: String = a["id"]
		var ok := false
		match id:
			"rallying_cry":
				ok = f.life < f.max_life() or b._flee_count(f.player) >= 4
			"attack_attack", "unholy_sermon":
				ok = engaged or _engaged_friends(b, f, 9.0) >= 1
			"transform":
				ok = engaged or Effects.dist(f, _nearest_enemy(b, f)) <= 9.0 if _nearest_enemy(b, f) else false
			"spirit_guardian":
				ok = engaged
			"tunnel", "witchfire":
				ok = true
			"leech_blood", "rite_of_contagion":
				ok = _enemies_within(b, f, 9.0 if id == "leech_blood" else 12.0) >= 2
		if ok and Abilities.use(b, id) == "":
			return true
	return false


static func _engaged_friends(b: Battle, f: FighterState, r: float) -> int:
	var n := 0
	for o in b.on_board(f.player):
		if o != f and Effects.near(f, o, r) and Effects.is_engaged(b, o):
			n += 1
	return n


static func _enemies_within(b: Battle, f: FighterState, r: float) -> int:
	var n := 0
	for o in b.on_board(b.other(f.player)):
		if Effects.near(f, o, r):
			n += 1
	return n


static func _best_melee_target(b: Battle, f: FighterState) -> FighterState:
	var best: FighterState = null
	var bs := -INF
	for e in Effects.engaged_enemies(b, f):
		var s: float = _fighter_value(e) * 0.01 - e.life
		if s > bs:
			bs = s
			best = e
	return best


# --- Shooting ---------------------------------------------------------------------------------------

## The best ranged attack available right now: {"w", "uid"|"point"|"dir", "ev", "heavy"} or {}.
static func _best_shot(b: Battle, f: FighterState) -> Dictionary:
	var best := {}
	for w in f.usable_ranged():
		if Combat.check_can_shoot(b, f, w) != "":
			continue
		var heavy := Effects.weapon_has(f, w, "Heavy")
		if Effects.weapon_has(f, w, "Flame"):
			for e in b.on_board(b.other(f.player)):
				if Effects.dist(f, e) > 7.5:
					continue
				var dir: Vector2 = e.pos - f.pos
				var v := _template_value(b, f, Combat.flame_hits(b, f, dir), w)
				if v > best.get("ev", 0.0):
					best = {"w": w, "dir": dir, "ev": v, "heavy": heavy}
			continue
		if Effects.weapon_has(f, w, "Blast"):
			var rng := Effects.range_for(b, f, w)
			for e in b.on_board(b.other(f.player)):
				if Effects.dist(f, e) > rng or not Combat.point_visible(b, f.pos, e.pos, [f, e], Effects.eye_height(f), e.elev + 0.3):
					continue
				var v2 := _template_value(b, f, Combat.blast_hits(b, e.pos, e.elev), w) * 0.6
				if v2 > best.get("ev", 0.0):
					best = {"w": w, "point": e.pos, "elev": e.elev, "ev": v2, "heavy": heavy}
			continue
		for t in Combat.ranged_targets(b, f, w):
			if not t["legal"]:
				continue
			var tgt := b.fighter(t["uid"])
			var ev := _expected_damage(b, f, w, tgt, t["obscured"]) * Dice.average(str(w.get("attacks", "1")))
			if tgt.life <= 2:
				ev *= 1.4
			if ev > best.get("ev", 0.0):
				best = {"w": w, "uid": tgt.uid, "ev": ev, "heavy": heavy}
	return best


static func _template_value(b: Battle, f: FighterState, hits: Array, w: Dictionary) -> float:
	var v := 0.0
	for h in hits:
		var dmg := Dice.average(str(w.get("damage", "1")))
		v += dmg * (1.0 if h.player != f.player else -1.5)
	return v


static func _expected_damage(b: Battle, f: FighterState, w: Dictionary, t: FighterState, cover: bool) -> float:
	var mod := Effects.attack_mod(b, f, w, t, true)
	var need := Effects.hit_value(f, true) - mod
	var crit_on := Effects.crit_threshold(b, f, w, true)
	var p_crit := (7.0 - crit_on) / 6.0
	var p_hit := clampf((7.0 - need) / 6.0, 0.0, 1.0)
	p_hit = maxf(p_hit, p_crit)
	var armour := Effects.armour_value(b, t, {"cover": cover})
	var rend := Effects.rend_for(b, f, w, t)
	var need_save := armour - rend if not Effects.ignores_rend(t) else armour
	var p_save := 0.0 if need_save > 6 else clampf((7.0 - need_save) / 6.0, 0.0, 1.0)
	var dmg := Dice.average(str(w.get("damage", "1")))
	var crit_dmg := Dice.average(str(w.get("crit"))) if w.get("crit") != null else dmg
	return ((p_hit - p_crit) * dmg + p_crit * crit_dmg) * (1.0 - p_save)


static func _fire(b: Battle, f: FighterState, shot: Dictionary) -> bool:
	var w: Dictionary = shot["w"]
	var err := ""
	if shot.has("dir"):
		err = Combat.shoot_flame(b, w["id"], shot["dir"])
	elif shot.has("point"):
		err = Combat.shoot_blast(b, w["id"], shot["point"], shot.get("elev", 0.0))
	else:
		err = Combat.shoot(b, w["id"], shot["uid"])
	return err == ""


# --- Magic -----------------------------------------------------------------------------------------

## Spells that damage enemies (Magic._resolve), with how far away they can reach a target.
const DAMAGE_SPELLS := {
	"Arcane Missile": 15.0, "Chain Lightning": 12.0, "Draw Blood": 9.0, "Erupting Sores": 9.0, "Rotten Insides": 9.0,
	"Torrent of Fire": 8.0, "Spray of Vomit": 8.0, "Balefire": 8.0, "Black Bile": 8.0, "Bat Scream": 8.0, "Sanguine Spear": 12.0,
	"Bouncing Blast": 15.0, "Plague Bomb": 12.0, "Death Blast": 12.0, "Rain of Filth": 12.0, "Plague Wind": 15.0,
}
## Casters keep this far from enemies when they can, and draw power when nobody is this close.
const CASTER_SAFE := 6.0


## A caster with an attack spell prepared: it fights with magic rather than charging into melee.
static func _battle_mage(f: FighterState) -> bool:
	return f.is_caster() and _damage_reach(f) > 0.0


## Longest reach of the fighter's prepared damaging spells (0 = none).
static func _damage_reach(f: FighterState) -> float:
	var r := 0.0
	for sp in f.prepared:
		r = maxf(r, float(DAMAGE_SPELLS.get(sp["name"], 0.0)))
	return r


static func _enemy_within(b: Battle, f: FighterState, inches: float) -> bool:
	for e in b.on_board(b.other(f.player)):
		if Effects.near(f, e, inches):
			return true
	return false


## Draws power (an extra casting die next activation) when no enemy is within 6". A caster that already holds power
## but had nothing to cast draws again: unused power is lost when this activation ends (p.33), and a fresh draw keeps it.
## Two casting dice don't add miscast risk: 1 die miscasts on a 1, 2 dice on a double, both 1 in 6.
static func _should_draw_power(b: Battle, f: FighterState) -> bool:
	return f.is_caster() and not f.prepared.is_empty() and not _enemy_within(b, f, CASTER_SAFE)


static func _cast_chance(f: FighterState, casting: int) -> float:
	var dice := 2 if f.statuses.get("drawn_power", false) else 1
	var wp := int(f.stats["willpower"])
	var ok := 0
	var total := 0
	if dice == 1:
		for a in range(1, 7):
			total += 1
			if a != 1 and a + wp >= casting:
				ok += 1
	else:
		for a in range(1, 7):
			for c in range(1, 7):
				total += 1
				if a != c and a + c + wp >= casting:
					ok += 1
	return float(ok) / total


## The most useful spell to cast now: {"name", "params", "value"} or {}.
static func _best_spell(b: Battle, f: FighterState, damaging_only := false) -> Dictionary:
	if Magic.can_use_arcane(b, f) != "":
		return {}
	var best := {}
	for sp in f.prepared:
		if damaging_only and not DAMAGE_SPELLS.has(sp["name"]):
			continue
		var chance := _cast_chance(f, int(sp["casting"]))
		var name: String = sp["name"]
		var damaging := DAMAGE_SPELLS.has(name)
		if chance < (0.3 if damaging else 0.4):
			continue
		var info := Magic.spell_info(name)
		var params := {}
		var value := 0.0
		match info["target"]:
			"closest":
				var ce := Magic._closest_enemy(b, f, float(info.get("range", 0.0)))
				if ce != null:
					value = 3.0 + (1.0 if ce.life <= 2 else 0.0)
			"enemy":
				for e in b.on_board(b.other(f.player)):
					if Magic._validate_target(b, f, name, {"target": e.uid}, false) == "":
						params = {"target": e.uid}
						value = 1.2 if name != "Silence" else (1.5 if e.is_caster() else 0.0)
						break
			"friendly":
				var ally := _best_ally_for(b, f, name)
				if ally != null:
					params = {"target": ally.uid}
					value = 1.2
			"none":
				value = _self_spell_value(b, f, name)
			"point":
				if name in ["Umbral Vortex", "Bouncing Blast", "Plague Bomb", "Death Blast", "Plague Wind", "Rain of Filth"]:
					for e in b.on_board(b.other(f.player)):
						var p := {"point": e.pos, "elev": e.elev}
						if Magic._validate_target(b, f, name, p, false) == "":
							var hits := Combat.blast_hits(b, e.pos, e.elev)
							var v := 0.0
							for h in hits:
								v += (2.5 if damaging else 1.0) if h.player != f.player else -2.5
							if v > value:
								value = v
								params = p
			"dir":
				for e in b.on_board(b.other(f.player)):
					if Effects.dist(f, e) <= (11.5 if name == "Sanguine Spear" else 7.5):
						var hits2 := _spear_hits(b, f, e.pos - f.pos) if name == "Sanguine Spear" else Combat.flame_hits(b, f, e.pos - f.pos)
						var v2 := 0.0
						for h in hits2:
							v2 += (2.5 if damaging else 1.0) if h.player != f.player else -2.5
						if v2 > value:
							value = v2
							params = {"dir": e.pos - f.pos}
			"summon":
				if Magic._summoned_count(b, f.player) < 3:
					var probe := FighterState.new()
					probe.radius = Geo.radius_from_mm(32.0)
					probe.player = f.player
					var spot := Scenario.find_spot(b, probe, f.pos, 2.5)
					if spot != Vector2.INF:
						params = {"point": spot}
						value = 1.5
		if value <= 0.0 or Magic._validate_target(b, f, name, params, false) != "":
			continue
		value *= chance
		if value > best.get("value", 0.0):
			best = {"name": name, "params": params, "value": value}
	return best


## Enemies a Sanguine Spear cast in direction `dir` would hit (12" line, Magic._resolve).
static func _spear_hits(b: Battle, f: FighterState, dir: Vector2) -> Array:
	var out: Array = []
	var a := f.pos + dir.normalized() * f.radius
	var c := a + dir.normalized() * 12.0
	for o in b.on_board(b.other(f.player)):
		if Geometry2D.get_closest_point_to_segment(o.pos, a, c).distance_to(o.pos) <= o.radius + 0.5 and Effects.visibility(b, f, o)["visible"]:
			out.append(o)
	return out


## The best damaging spell castable now, or {}.
static func _best_attack_spell(b: Battle, f: FighterState) -> Dictionary:
	return _best_spell(b, f, true)


static func _best_ally_for(b: Battle, f: FighterState, spell: String) -> FighterState:
	var best: FighterState = null
	var bs := 0.0
	for o in b.on_board(f.player):
		var s := 0.0
		if spell in ["Healing Essence"]:
			s = o.max_life() - o.life
		elif spell in ["Swollen Form", "Will of the Saints", "Ethereal Armour", "Protective Shroud"]:
			s = 2.0 if Effects.is_engaged(b, o) else (1.0 if Effects.dist(o, _nearest_enemy(b, o) if _nearest_enemy(b, o) else o) < 8.0 else 0.0)
		else:
			s = 2.0 if Effects.is_engaged(b, o) or (not _is_shooter(o) and _nearest_enemy(b, o) != null and Effects.dist(o, _nearest_enemy(b, o)) < 8.0) else 0.0
		if s > bs and Magic._validate_target(b, f, spell, {"target": o.uid}, false) == "":
			bs = s
			best = o
	return best


static func _self_spell_value(b: Battle, f: FighterState, spell: String) -> float:
	match spell:
		"Witchfire":
			return 1.5
		"Dark Vitality":
			var wounded := 0
			for o in b.on_board(f.player):
				if Effects.near(f, o, 3.0) and o.life < o.max_life():
					wounded += 1
			return wounded * 0.8
		_:
			var near := 0
			for o in b.on_board(f.player):
				if o != f and Effects.near(f, o, 6.0):
					near += 1
			return 0.5 * near if near >= 2 else 0.0


# --- Moving ----------------------------------------------------------------------------------------

## Where this fighter wants to go: scenario objectives first, then the nearest enemy.
static func _goal(b: Battle, f: FighterState) -> Vector2:
	var id: String = b.scen.get("id", "")
	var c := Scenario.center(b)
	if f.treasure > 0:
		return _nearest_edge_point(b, f.pos)
	if id == "street_of_death":
		var escape_x: float = b.board_size.x if b.scen.get("escape_edge", "east") == "east" else 0.0
		if "hit" in f.marks:
			return Vector2(escape_x, clampf(f.pos.y, 16.5, 19.5))
		for o in b.on_board():
			if "hit" in o.marks:
				return o.pos
	if id in ["glimmers_in_the_dark", "the_find", "the_chapel"] and _can_carry(b, f):
		# Only the nearest able friend goes for each token, and only when it is close; the rest fight.
		var best := Vector2.INF
		for t in b.tokens:
			if t["type"] != "treasure" or float(t.get("elev", 0.0)) > 0.1:
				continue
			var d: float = f.pos.distance_to(t["pos"])
			if d > 2.0 * _move_of(f) + 4.0:
				continue
			var mine := true
			for o in b.on_board(f.player):
				if o != f and o.treasure == 0 and _can_carry(b, o) and o.pos.distance_to(t["pos"]) < d - 0.5:
					mine = false
					break
			if mine and (best == Vector2.INF or d < f.pos.distance_to(best)):
				best = t["pos"]
		if best != Vector2.INF:
			return best
	if id == "the_find" and f.player == b.scen.get("defender", -1):
		return c
	if id == "a_deadly_encounter" and f.uid % 2 == 0:
		return c
	if id == "no_quarter":
		var best_q := 0
		var best_s := -INF
		for q in 4:
			var s := 0.0
			for o in b.on_board():
				if Scenario.quarter_of(b, o) == q:
					s += 1.0 if o.player != f.player else -0.7
			if s > best_s:
				best_s = s
				best_q = q
		var qc: Vector2 = [Vector2(9, 9), Vector2(27, 9), Vector2(27, 27), Vector2(9, 27)][best_q]
		if f.uid % 2 == 0:
			return qc
	var e := _nearest_enemy(b, f)
	if e != null and _battle_mage(f):
		# Aim for a point at spell reach (but never closer than 6") along the line to the nearest enemy.
		var keep := maxf(CASTER_SAFE + 1.0, _damage_reach(f) - 2.0)
		var d := f.pos.distance_to(e.pos)
		if f.acted:
			keep = maxf(keep, CASTER_SAFE + 2.0)   # spell already cast: get clear
		var away := (f.pos - e.pos).normalized() if d > 0.01 else Vector2(1, 0)
		var spot := e.pos + away * keep
		return Vector2(clampf(spot.x, 1.0, b.board_size.x - 1.0), clampf(spot.y, 1.0, b.board_size.y - 1.0))
	return e.pos if e != null else c


static func _can_carry(b: Battle, f: FighterState) -> bool:
	return f.category != "beast" and not f.has_kw("Thrall") and f.treasure == 0 and Scenario.can_pick_up(b, f)


static func _nearest_edge_point(b: Battle, p: Vector2) -> Vector2:
	var cands := [Vector2(p.x, 0), Vector2(p.x, b.board_size.y), Vector2(0, p.y), Vector2(b.board_size.x, p.y)]
	var best: Vector2 = cands[0]
	for q in cands:
		if p.distance_to(q) < p.distance_to(best):
			best = q
	return best


static func _try_charge(b: Battle, f: FighterState) -> bool:
	var mv := _move_of(f)
	var nav := AINav.build(b, f, "charge", mv + 6.0)
	var best_c := Vector2i(-1, -1)
	var best_cost := INF
	var best_target: FighterState = null
	for e in b.on_board(b.other(f.player)):
		if absf(e.elev - f.elev) > 0.5 or e.elev > 0.1:
			continue
		var ec := nav.cell_of(e.pos)
		var reach := int(ceil((e.radius + f.radius + 1.0) / AINav.CELL)) + 1
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var c := Vector2i(ec.x + dx, ec.y + dy)
				if c.x < 0 or c.y < 0 or c.x >= nav.w or c.y >= nav.h or not nav.reachable(c):
					continue
				var p := nav.center(c)
				var gap := Geo.signed_gap(p, f.radius, e.pos, e.radius)
				if gap < 0.05 or gap > 0.9:
					continue
				var cst: float = nav.cost[nav.idx(c)] - _fighter_value(e) * 0.002
				if cst < best_cost:
					best_cost = cst
					best_c = c
					best_target = e
	if best_target == null or best_cost > mv + 3.0:
		return false
	if Movement.declare(b, "charge") != "" or b.move_plan.is_empty():
		return false
	var allowance: float = b.move_plan["allowance"]
	var raw := nav.path_to(best_c)
	for path in [nav.simplify(raw), raw]:
		if Movement.evaluate(b, path)["ok"] and _commit(b, path):
			return true
	# Not far enough this time: look for any contact point within the rolled distance.
	if Geo.path_length(raw) > allowance:
		Movement.fail_charge(b)
		return true
	Movement.fail_charge(b)
	return true


static func _do_move(b: Battle, f: FighterState) -> bool:
	if f.elev > Height.LEVEL_EPS:
		return _try_descend(b, f)
	var goal := _goal(b, f)
	var shooter := _is_shooter(f)
	var far := f.pos.distance_to(goal) > _move_of(f) + 4.0
	var kind := "run" if far and not shooter and not f.acted and not f.is_caster() and Options.for_active(b)["moves"]["run"] == "" else "normal"
	# A normal move's distance is known before declaring it, so plan first and stay put quietly if there's nowhere better.
	var known := kind == "normal" and str(f.stats["move"]) != "2d6"
	var allow := 0.0
	if known:
		allow = Effects.move_value(b, f, 0)
	else:
		if Movement.declare(b, kind) != "" or b.move_plan.is_empty():
			return false
		allow = b.move_plan["allowance"]
	var nav := AINav.build(b, f, kind, allow)
	var scored := _score_cells(b, f, nav, allow, goal, shooter)
	var here := nav.cell_of(f.pos)
	for k in mini(4, scored.size()):
		var cell: Vector2i = scored[k][1]
		if cell == here:
			break
		var raw := nav.path_to(cell)
		var pickup := kind == "normal" and Movement.treasure_in_reach(b, f, nav.center(cell), 0.0) >= 0 and nav.cost[nav.idx(cell)] <= allow - 1.0
		for path in [nav.simplify(raw), raw]:
			if path.size() < 2:
				continue
			if b.move_plan.is_empty():
				if Movement.declare(b, kind) != "" or b.move_plan.is_empty():
					return f.moved
			var ev := Movement.evaluate(b, path, pickup)
			if ev["ok"] and _commit(b, path, pickup):
				return true
	if b.move_plan.is_empty():
		return false
	return _give_up_move(b)


## Picks up treasure with a normal move when a token is within reach this activation (it costs 1", p.36).
static func _try_pickup(b: Battle, f: FighterState) -> bool:
	if f.treasure > 0 or f.elev > 0.1 or Movement.treasure_in_reach(b, f, f.pos, 0.0) < 0 and not _token_within(b, f, _move_of(f) + 1.0):
		return false
	if str(f.stats["move"]) == "2d6":
		return false
	var allow := Effects.move_value(b, f, 0)
	var nav := AINav.build(b, f, "normal", allow)
	var paths: Array = []
	if Movement.treasure_in_reach(b, f, f.pos, 0.0) >= 0:
		paths.append(PackedVector2Array([f.pos, f.pos + Vector2(0.01, 0.0)]))
	var best := Vector2i(-1, -1)
	for c in nav.reachable_cells(allow - 1.05, 1):
		if Movement.treasure_in_reach(b, f, nav.center(c), 0.0) >= 0 and (best.x < 0 or nav.cost[nav.idx(c)] < nav.cost[nav.idx(best)]):
			best = c
	if best.x >= 0:
		var raw := nav.path_to(best)
		paths.append(nav.simplify(raw))
		paths.append(raw)
	if paths.is_empty():
		return false
	if Movement.declare(b, "normal") != "" or b.move_plan.is_empty():
		return f.moved
	for path in paths:
		if path.size() >= 2 and Movement.evaluate(b, path, true)["ok"] and _commit(b, path, true):
			return true
	Movement.cancel(b)
	return false


static func _token_within(b: Battle, f: FighterState, r: float) -> bool:
	for t in b.tokens:
		if t["type"] == "treasure" and f.pos.distance_to(t["pos"]) <= r + f.radius:
			return true
	return false


## Scores every reachable cell for a move toward `goal`, best first: [[score, cell], ...].
static func _score_cells(b: Battle, f: FighterState, nav: AINav, allow: float, goal: Vector2, shooter: bool) -> Array:
	var cands := nav.reachable_cells(allow - 0.15, 1)
	var enemies := b.on_board(b.other(f.player))
	var brawler := not shooter and not f.is_caster() and not _is_objective_runner(b, f)
	var scored: Array = []
	for c in cands:
		var p := nav.center(c)
		var s := -p.distance_to(goal)
		if shooter or f.is_caster():
			var danger := 0
			for e in enemies:
				if e.pos.distance_to(p) < 6.0:
					danger += 1
			s -= danger * 1.5
			s += 1.0 if _near_terrain_point(b, p, f.radius) else 0.0
		elif f.treasure > 0:
			s *= 2.0
		if brawler:
			# Don't stop where an enemy that is still to activate can charge us first (the charger strikes first).
			for e in enemies:
				if not e.activated and Geo.base_gap(p, f.radius, e.pos, e.radius) < _move_of(e) + 4.0:
					s -= 4.0
					break
		scored.append([s, c])
	scored.sort_custom(func(x, y): return x[0] > y[0])
	if shooter:
		var top := scored.slice(0, 20)
		for item in top:
			if _shot_possible_from(b, f, nav.center(item[1])):
				item[0] += 6.0
		top.sort_custom(func(x, y): return x[0] > y[0])
		scored = top + scored.slice(20)
	elif _battle_mage(f) and not f.acted:
		var reach := _damage_reach(f)
		var top2 := scored.slice(0, 30)
		for item in top2:
			var p2 := nav.center(item[1])
			var near_e := INF
			for e in enemies:
				near_e = minf(near_e, Geo.base_gap(p2, f.radius, e.pos, e.radius))
			if near_e <= reach - 0.5:
				item[0] += 5.0 if _spell_target_visible_from(b, f, p2, reach) else 1.0
			if near_e > CASTER_SAFE:
				item[0] += 2.0
		top2.sort_custom(func(x, y): return x[0] > y[0])
		scored = top2 + scored.slice(30)
	return scored


static func _spell_target_visible_from(b: Battle, f: FighterState, p: Vector2, reach: float) -> bool:
	var probe := FighterState.new()
	probe.pos = p
	probe.player = f.player
	for e in b.on_board(b.other(f.player)):
		if Geo.base_gap(p, f.radius, e.pos, e.radius) <= reach and Effects.visibility_from_point(b, p, f.elev + f.height * 0.9, probe, e)["visible"]:
			return true
	return false


# --- High ground ------------------------------------------------------------------------------------

## Surfaces at least this high count as high ground; shooters with a weapon reaching further than LONG_RANGE use it.
const HIGH_GROUND := 1.5
const LONG_RANGE := 15.0


static func _long_shooter(f: FighterState) -> bool:
	if not _is_shooter(f):
		return false
	for w in f.usable_ranged():
		if str(w.get("range", "0")) != "flame" and float(w.get("range", 0)) > LONG_RANGE:
			return true
	return false


static func _best_range(b: Battle, f: FighterState) -> float:
	var r := 0.0
	for w in f.usable_ranged():
		r = maxf(r, Effects.range_for(b, f, w))
	return r


## Ways up onto a surface: [{"floor", "top", "elev", "climb"}], by ladder (1") or, for fighters that can climb,
## up a wall (vertical + horizontal distance, p.22). Every way is still checked by Movement.evaluate.
static func _ascents(b: Battle, f: FighterState, s: Dictionary) -> Array:
	var out: Array = []
	var elev: float = s["elev"]
	var poly: PackedVector2Array = s["poly"]
	var r := f.radius
	for l in b.terrain:
		if l.kind != "ladder" or absf(l.height - elev) > 0.5 or l.base > 0.5:
			continue
		var lc := (l.bounds() as Rect2).get_center()
		if not Geo.base_overlaps_polygon(lc, 1.5, poly):
			continue
		var top := Height.nearest_clear(b, lc, r, elev)
		if not Height.supports(b, top, elev) or Height.base_clear(b, top, r, elev) != "":
			continue
		var found := false
		for d in [r + 0.25, r + 0.5]:
			for k in 16:
				var fl: Vector2 = lc + Vector2.from_angle(TAU * k / 16.0) * d
				if Geo.base_inside_board(fl, r, b.board_size) and Height.supports(b, fl, 0.0) and Height.base_clear(b, fl, r, 0.0) == "" \
						and Height.ladder_between(b, fl, 0.0, top, elev, r) != null:
					out.append({"floor": fl, "top": top, "elev": elev, "climb": 1.0})
					found = true
					break
			if found:
				break
	if Movement.can_climb(f):
		for i in poly.size():
			var a := poly[i]
			var c := poly[(i + 1) % poly.size()]
			if a.distance_to(c) < 2.0 * r:
				continue
			var mid := (a + c) / 2.0
			var n := (c - a).orthogonal().normalized()
			if Geometry2D.is_point_in_polygon(mid + n * 0.05, poly):
				n = -n
			var top2 := mid - n * (r + 0.2)
			if not Height.supports(b, top2, elev) or Height.base_clear(b, top2, r, elev) != "":
				continue
			for d2 in [r + 0.15, r + 0.45]:
				var fl2: Vector2 = mid + n * d2
				if Geo.base_inside_board(fl2, r, b.board_size) and Height.supports(b, fl2, 0.0) and Height.base_clear(b, fl2, r, 0.0) == "":
					out.append({"floor": fl2, "top": top2, "elev": elev, "climb": elev + fl2.distance_to(top2)})
					break
	return out


static func _spot_free(b: Battle, f: FighterState, p: Vector2, elev: float) -> bool:
	for o in b.on_board():
		if o != f and absf(o.elev - elev) < 0.5 and Geo.signed_gap(p, f.radius, o.pos, o.radius) < 0.05:
			return false
	return true


## How many enemies within weapon range a fighter standing at (p, elev) could see.
static func _perch_view(b: Battle, f: FighterState, p: Vector2, elev: float, rng: float) -> int:
	var probe := FighterState.new()
	probe.pos = p
	probe.elev = elev
	probe.player = f.player
	probe.radius = f.radius
	probe.height = f.height
	var n := 0
	for e in b.on_board(b.other(f.player)):
		if Height.gap3(p, f.radius, elev, e.pos, e.radius, e.elev) > rng:
			continue
		if Effects.visibility_from_point(b, p, elev + f.height * 0.9, probe, e)["visible"]:
			n += 1
	return n


## The best high ground within reach of a few moves: the ascent plus its floor cell, total cost and score, or {}.
static func _plan_climb(b: Battle, f: FighterState, nav: AINav) -> Dictionary:
	var rng := _best_range(b, f)
	var best := {}
	for s in Height.surfaces(b):
		if float(s["elev"]) < HIGH_GROUND:
			continue
		if (s["piece"].bounds() as Rect2).get_center().distance_to(f.pos) > 3.0 * _move_of(f) + 6.0:
			continue
		for a in _ascents(b, f, s):
			var cell := nav.cell_of(a["floor"])
			if not nav.reachable(cell) or not _spot_free(b, f, a["top"], a["elev"]) or not _spot_free(b, f, a["floor"], 0.0):
				continue
			var cost: float = nav.cost[nav.idx(cell)] + nav.center(cell).distance_to(a["floor"]) + float(a["climb"])
			var view := _perch_view(b, f, a["top"], a["elev"], rng)
			var score := view * 3.0 + float(a["elev"]) * 0.5 - cost * 0.25
			for e in b.on_board(b.other(f.player)):
				if (a["top"] as Vector2).distance_to(e.pos) < 4.0:
					score -= 5.0
			if score > float(best.get("score", -INF)):
				best = a.duplicate()
				best["cell"] = cell
				best["cost"] = cost
				best["score"] = score
	return best


## A long-range shooter on the floor climbs onto the best high ground it can reach, or walks toward the foot of it.
static func _try_climb(b: Battle, f: FighterState) -> bool:
	if not _long_shooter(f) or f.elev >= HIGH_GROUND or f.elev > Height.LEVEL_EPS or _is_objective_runner(b, f):
		return false
	if str(f.stats["move"]) == "2d6" or _enemy_within(b, f, CASTER_SAFE):
		return false
	var allow := Effects.move_value(b, f, 0)
	var nav := AINav.build(b, f, "normal", allow * 3.0 + 6.0)
	var plan := _plan_climb(b, f, nav)
	if plan.is_empty():
		return false
	var raw := nav.path_to(plan["cell"])
	# Grid costs run a little long (diagonal steps), so try the climb whenever it is close and let the rules decide.
	if float(plan["cost"]) <= allow * 1.15 + 0.6:
		for floor_path in [nav.simplify(raw), raw]:
			var path := PackedVector2Array(floor_path)
			path.append(plan["floor"])
			path.append(plan["top"])
			var levels := PackedFloat32Array()
			for i in path.size():
				levels.append(0.0)
			levels[levels.size() - 1] = plan["elev"]
			if b.move_plan.is_empty() and (Movement.declare(b, "normal") != "" or b.move_plan.is_empty()):
				return f.moved
			if Movement.evaluate(b, path, false, levels)["ok"] and _commit(b, path, false, levels):
				return true
	# Too far this activation: walk along the route toward the foot of the climb.
	var last := 0
	for i in range(1, raw.size()):
		if nav.cost[nav.idx(nav.cell_of(raw[i]))] <= allow - 0.15:
			last = i
	if last == 0:
		if not b.move_plan.is_empty():
			Movement.cancel(b)
		return false
	var to_foot := raw.slice(0, last + 1)
	if last == raw.size() - 1 and float(plan["cost"]) - float(plan["climb"]) <= allow:
		to_foot.append(plan["floor"])   # the whole way to the foot of the climb fits: stand right at it
	var walk := nav.simplify(to_foot)
	if b.move_plan.is_empty() and (Movement.declare(b, "normal") != "" or b.move_plan.is_empty()):
		return f.moved
	# Best first: the straightened whole route cut at exactly the allowance (uses the full move), then grid paths.
	var whole := nav.simplify(raw)
	whole.append(plan["floor"])
	var exact := Geo.truncate(whole, allow - 0.05)
	for path2 in [exact, walk, to_foot]:
		if Movement.evaluate(b, path2)["ok"] and _commit(b, path2):
			return true
	Movement.cancel(b)
	return false


## Gets an elevated fighter back down to the floor by the nearest ladder or wall (or a jump), so it can move on.
static func _try_descend(b: Battle, f: FighterState) -> bool:
	var s := Height.surface_at(b, f.pos, f.elev)
	if s.is_empty():
		return false
	var ways := _ascents(b, f, s)
	ways.sort_custom(func(x, y): return f.pos.distance_to(x["top"]) < f.pos.distance_to(y["top"]))
	if Movement.declare(b, "normal") != "" or b.move_plan.is_empty():
		return f.moved
	for w in ways.slice(0, 4):
		var path := PackedVector2Array([f.pos, w["top"], w["floor"]])
		var levels := PackedFloat32Array([f.elev, f.elev, 0.0])
		if Movement.evaluate(b, path, false, levels)["ok"] and _commit(b, path, false, levels):
			return true
	Movement.cancel(b)
	return false


static func _give_up_move(b: Battle) -> bool:
	if b.move_plan.get("kind", "") == "normal":
		Movement.cancel(b)
		return false
	# A run was rolled: stand still rather than wander.
	var f := b.active_fighter()
	if Movement.commit(b, PackedVector2Array([f.pos, f.pos + Vector2(0.01, 0)])) != "":
		b.move_plan = {}
		f.moved = true
	return true


static func _near_terrain_point(b: Battle, p: Vector2, r: float) -> bool:
	for t in b.terrain:
		if Geo.base_overlaps_polygon(p, r + 0.4, t.polygon):
			return true
	return false


static func _shot_possible_from(b: Battle, f: FighterState, p: Vector2) -> bool:
	var best_range := 0.0
	for w in f.usable_ranged():
		best_range = maxf(best_range, Effects.range_for(b, f, w))
	for e in b.on_board(b.other(f.player)):
		if p.distance_to(e.pos) - f.radius - e.radius > best_range:
			continue
		var probe := FighterState.new()
		probe.pos = p
		probe.player = f.player
		if Effects.visibility_from_point(b, p, f.elev + f.height * 0.9, probe, e)["visible"]:
			return true
	return false
