class_name Battle
extends RefCounted
## The live battle: all state plus the round/activation flow (Chapter 2). Rules details are delegated to
## Movement, Combat, Magic and Scenario. The view never mutates state directly: it calls the public methods
## below, which validate, change state, log, and emit `changed`.
##
## Decisions that belong to a specific player (who goes first, melee choices, flee tests, placing
## reinforcements...) are stored in `pending` and answered with respond(). State, not await, so it can be
## saved and undone.

signal changed
signal logged(text: String)

var cfg := {
	"flame_end_radius": 1.25,      # half-width of the flame template's round end (diagram missing in v1.03)
	"bloodied_strict": true,       # bloodied: a Charge counts as the move, so no melee attack after it (p.12)
	"auto_place_reserves": false,
}

var board_size := Vector2(36, 36)
var terrain: Array = []
var fighters: Array = []
var rosters: Array = [{}, {}]
var player_names: Array = ["Player 1", "Player 2"]
var underdog := 0
var round_no := 0
var priority := 0
var turn := 0
var active := -1
var active_is_surge := false
var phase := "setup"            # setup, deploy, priority, start_of_round, activation, end_of_round, flee, over
var pending := {}
var duel := {}
var move_plan := {}
var scen := {}
var winner := -1
var result_text := ""
var dice := Dice.new()
var history: Array = []
var tokens: Array = []          # treasure etc: [{"type": "treasure", "pos": Vector2, "value": ...}]
var _undo: Array = []
var _next_uid := 1


# ---------------------------------------------------------------------------------------------
# Setup

func setup(r0: Roster, r1: Roster, scenario_id: String, twist := -1, seed_value := -1, layout: Dictionary = {}) -> void:
	if seed_value < 0:
		# A fresh, unpredictable seed from the operating system's cryptographic random source.
		seed_value = Crypto.new().generate_random_bytes(8).decode_s64(0) & 0x7FFFFFFFFFFFFFFF
	dice = Dice.new(seed_value)
	log_line("Dice seed: %d (enter it on the New Battle screen to replay these exact dice)." % seed_value)
	rosters = [r0.to_dict(), r1.to_dict()]
	player_names = [r0.name, r1.name]
	fighters.clear()
	for p in 2:
		var r: Roster = [r0, r1][p]
		for m in r.members:
			var f := FighterState.from_member(r, m, p, _next_uid)
			_next_uid += 1
			fighters.append(f)
	var ra := r0.rating()
	var rb := r1.rating()
	if ra == rb:
		underdog = dice.roll_off()
		log_line("Warband ratings are tied (%d); %s wins the roll-off and is the underdog." % [ra, player_names[underdog]])
	else:
		underdog = 0 if ra < rb else 1
		log_line("Underdog: %s (rating %d vs %d)." % [player_names[underdog], mini(ra, rb), maxi(ra, rb)])
	Magic.prepare_spells(self)
	for f in fighters:
		if f.has_rule("mad_engineering"):
			f.statuses["engineering"] = dice.d3()
	Scenario.setup(self, scenario_id, twist, layout)


func new_uid() -> int:
	_next_uid += 1
	return _next_uid - 1


# ---------------------------------------------------------------------------------------------
# Queries

func fighter(uid: int) -> FighterState:
	for f in fighters:
		if f.uid == uid:
			return f
	return null


func on_board(player := -1) -> Array:
	var out: Array = []
	for f in fighters:
		if f.on_board() and (player < 0 or f.player == player):
			out.append(f)
	return out


func other(p: int) -> int:
	return 1 - p


func can_activate_normally(player: int) -> Array:
	var out: Array = []
	for f in on_board(player):
		if not f.activated:
			out.append(f)
	return out


func can_surge(player: int) -> Array:
	var out: Array = []
	for f in on_board(player):
		if f.activated and not f.surged:
			out.append(f)
	return out


func active_fighter() -> FighterState:
	return fighter(active)


func log_line(text: String) -> void:
	history.append(text)
	logged.emit(text)


func is_over() -> bool:
	return phase == "over"


# ---------------------------------------------------------------------------------------------
# Round sequence (p.18)

func begin_round() -> void:
	round_no += 1
	for f in fighters:
		f.activated = false
		f.surged = false
	scen.erase("no_surge_0")
	scen.erase("no_surge_1")
	log_line("— Round %d —" % round_no)
	var a := dice.d6()
	var b := dice.d6()
	priority = underdog if a == b else (0 if a > b else 1)
	log_line("Priority roll: %s %d, %s %d → %s has priority%s." % [player_names[0], a, player_names[1], b, player_names[priority], " (underdog wins ties)" if a == b else ""])
	phase = "priority"
	pending = {"type": "choose_first", "player": priority}
	changed.emit()


func _start_of_round() -> void:
	phase = "start_of_round"
	Scenario.start_of_round(self)
	if pending.is_empty():
		_begin_activations()


func _begin_activations() -> void:
	phase = "activation"
	_check_turn()


## Called whenever an activation finishes: decide who acts next, or end the round (p.19).
func _check_turn() -> void:
	if is_over():
		return
	active = -1
	if scen.get("thunder", false):
		scen.erase("thunder")
		log_line("Thunder claps: time stops and the round ends immediately.")
		_end_of_round()
		return
	var mine := can_activate_normally(turn)
	var theirs := can_activate_normally(other(turn))
	if mine.is_empty() and theirs.is_empty():
		_end_of_round()
		return
	if mine.is_empty():
		if not can_surge(turn).is_empty() and not scen.get("no_surge_" + str(turn), false):
			pending = {"type": "surge_or_pass", "player": turn}
		else:
			turn = other(turn)
	changed.emit()


func _end_of_round() -> void:
	phase = "end_of_round"
	active = -1
	Scenario.end_of_round(self)
	for f in fighters:
		for i in range(f.effects.size() - 1, -1, -1):
			if f.effects[i].get("until", "") == "round":
				f.effects.remove_at(i)
	if is_over():
		changed.emit()
		return
	_flee_tests()


func _flee_tests() -> void:
	phase = "flee"
	var order := [underdog, other(underdog)]
	scen["flee_queue"] = []
	for p in order:
		if _flee_count(p) >= 5 and Scenario.must_take_flee_test(self, p):
			if scen.get("rallying_cry_" + str(p), false):
				log_line("%s: Rallying Cry — no Flee test this round." % player_names[p])
				continue
			scen["flee_queue"].append(p)
	scen.erase("rallying_cry_0")
	scen.erase("rallying_cry_1")
	_next_flee_test()


func _flee_count(p: int) -> int:
	var n := 0
	for f in fighters:
		if f.player == p and not f.summoned and (f.where == "down" or f.is_bloodied()):
			n += 1
	return n


func _next_flee_test() -> void:
	var q: Array = scen.get("flee_queue", [])
	if q.is_empty():
		begin_round()
		return
	var p: int = q.pop_front()
	pending = {"type": "flee_test", "player": p, "count": _flee_count(p)}
	changed.emit()


func _resolve_flee(p: int, voluntary: bool) -> void:
	var fled := voluntary
	if not voluntary:
		var r := dice.d6()
		var text := "%s takes a Flee test (%d fighters bloodied or down): rolled %d" % [player_names[p], _flee_count(p), r]
		if r == 1 and _has_banner(p):
			var r2 := dice.d6()
			text += ", re-rolled with the banner: %d" % r2
			r = r2
		fled = r == 1
		log_line(text + (" — the warband FLEES!" if fled else " — they hold."))
	else:
		log_line("%s chooses to flee." % player_names[p])
	if fled:
		Scenario.on_flee(self, p)
		end_battle(other(p), "%s fled the battle." % player_names[p])
		return
	_next_flee_test()


func _has_banner(p: int) -> bool:
	for f in on_board(p):
		for id in ["guild_banner", "clan_banner", "ancient_banner", "cloister_icon"]:
			if f.has_item(id):
				return true
	return false


## Simulator ruling: a warband with nobody left in the battle (every fighter taken down or escaped, none in reserve
## and none about to Rise Again) loses at once, even if it never takes a flee test (Street of Death's Defender,
## Defiant Stand). Both wiped out together is a draw. Returns true if the battle ended.
func check_wipeout() -> bool:
	if is_over():
		return true
	var left := [0, 0]
	var down := [0, 0]
	for f in fighters:
		if f.where in ["board", "reserve"] or (f.where == "down" and f.statuses.has("rise_again_marker") and not "rise_again" in f.once_per_battle):
			left[f.player] += 1
		elif f.where == "down":
			down[f.player] += 1
	if left[0] > 0 and left[1] > 0:
		return false
	if left[0] == 0 and left[1] == 0:
		end_battle(-1, "Both warbands have been wiped out.")
		return true
	var p := 0 if left[0] == 0 else 1
	var how := "the whole warband has been taken down" if down[p] > 0 and down[p] == fighters.filter(func(x): return x.player == p).size() else "no fighters are left in the battle"
	end_battle(other(p), "%s is wiped out: %s." % [player_names[p], how])
	return true


func end_battle(win: int, text: String) -> void:
	winner = win
	result_text = text
	Twists.on_battle_end(self, win)
	phase = "over"
	pending = {}
	log_line("BATTLE OVER: " + text + (" %s wins." % player_names[win] if win >= 0 else " Draw."))
	changed.emit()


# ---------------------------------------------------------------------------------------------
# Pending decisions

## Answers the current pending decision. Returns "" or an error.
func respond(choice: Dictionary) -> String:
	if pending.is_empty():
		return "Nothing to answer."
	var p := pending.duplicate(true)
	match p["type"]:
		"choose_first":
			pending = {}
			turn = int(choice["player"])
			log_line("%s chooses %s to activate first." % [player_names[p["player"]], player_names[turn]])
			_start_of_round()
		"surge_or_pass":
			pending = {}
			if choice.get("pass", false):
				log_line("%s makes no surge activation." % player_names[turn])
				scen["no_surge_" + str(turn)] = true
				turn = other(turn)
				_check_turn()
			else:
				return activate(int(choice["uid"]), true)
		"flee_test":
			pending = {}
			_resolve_flee(p["player"], choice.get("voluntary", false))
		"deploy", "place":
			return Scenario.respond_placement(self, choice)
		"pick_reserve_group", "pick_entry", "scenario_choice", "pick_quarter", "pick_fighter":
			return Scenario.respond(self, choice)
		"melee_weapons", "duel_turn":
			return Combat.respond_duel(self, choice)
		"volley":
			return Combat.respond_volley(self, choice)
		_:
			return "Unknown decision %s" % p["type"]
	changed.emit()
	return ""


# ---------------------------------------------------------------------------------------------
# Activations (p.19)

func activate(uid: int, surge := false) -> String:
	if phase != "activation" or not pending.is_empty():
		return "Not the time to activate a fighter."
	if active >= 0:
		return "Finish the current activation first."
	var f := fighter(uid)
	if f == null or not f.on_board() or f.player != turn:
		return "That fighter can't activate now."
	if surge:
		if f.surged or not f.activated or not can_activate_normally(turn).is_empty():
			return "That fighter can't make a surge activation."
		if can_activate_normally(other(turn)).is_empty():
			return "Surge activations are only possible while the opponent still has fighters to activate."
	elif f.activated:
		return "Already activated this round."
	_snapshot()
	pending = {}
	active = uid
	active_is_surge = surge
	if surge:
		f.surged = true
	else:
		f.activated = true
	f.start_activation_reset()
	f.statuses["damaged_this_activation"] = false
	f.statuses["bloodied_at_start"] = f.is_bloodied()
	log_line("%s activates %s%s." % [player_names[f.player], f.name, " (surge activation: 1 move or 1 action)" if surge else ""])
	_start_of_activation(f)
	changed.emit()
	return ""


func _start_of_activation(f: FighterState) -> void:
	# Hidden ends at the start of the fighter's next activation (p.27).
	f.statuses.erase("hidden")
	if not Abilities.start_of_activation(self, f):
		end_activation()
		return
	if f.statuses.get("poisoned", false):
		log_line("%s suffers 1 damage from poison." % f.name)
		Combat.apply_damage(self, f, 1, null, "poison")
		if not f.on_board():
			end_activation()
			return
	if f.has_rule("infested_with_maggots") and f.life < f.max_life():
		var r := dice.d6()
		if r >= 4:
			heal(f, 1, "Infested with Maggots (%d)" % r)
	if f.has_rule("tough_bastard") and f.is_bloodied():
		var t := dice.test(int(f.stats["willpower"]))
		if t["pass"]:
			heal(f, 1, "Tough Bastard (rolled %d)" % t["roll"])
	if f.has_effect("entwined"):
		var t2 := dice.test(int(f.stats["initiative"]))
		if t2["pass"]:
			f.remove_effect("entwined")
			log_line("%s escapes the net (rolled %d)." % [f.name, t2["roll"]])
	for e in Effects.engaged_enemies(self, f):
		if e.has_rule("toxic_miasma"):
			var tm := dice.test(int(f.stats["willpower"]))
			if not tm["pass"]:
				log_line("%s chokes on the Toxic Miasma (rolled %d)." % [f.name, tm["roll"]])
				Combat.apply_damage(self, f, 1, e, "toxic miasma")
				if not f.on_board():
					end_activation()
					return
	# Fear (Rot Demons, Dread Aura): engaged with a fear-causer → Willpower test or the activation ends.
	if not f.causes_fear() and not f.is_unshakeable():
		for e in Effects.engaged_enemies(self, f):
			if e.causes_fear():
				var t3 := dice.test(int(f.stats["willpower"]))
				log_line("%s must face %s's fear: rolled %d vs Willpower %d — %s." % [f.name, e.name, t3["roll"], f.stats["willpower"], "passed" if t3["pass"] else "FAILED, activation ends"])
				if not t3["pass"]:
					end_activation()
					return
				break
	if not Scenario.start_of_activation(self, f):
		end_activation()


## Surge activations and bloodied fighters get a move OR an action (pp.12, 19); healing lifts the bloodied limit.
func move_or_action_only(f: FighterState) -> bool:
	return active_is_surge or (f.statuses.get("bloodied_at_start", false) and f.is_bloodied())


## Whether the active fighter may still make a Move / an Action this activation.
func can_still_move(f: FighterState) -> bool:
	if f.moved or f.has_effect("heavy_fired"):
		return false
	return not (move_or_action_only(f) and f.acted)


func can_still_act(f: FighterState) -> bool:
	if f.acted or f.move_kind == "run":
		return false
	return not (move_or_action_only(f) and f.moved)


func end_activation() -> String:
	var f := active_fighter()
	if f == null:
		return "No fighter is activating."
	if not duel.is_empty() or pending.get("type", "") in ["duel_turn", "melee_weapons", "volley", "place"]:
		return "Resolve the current decision first."
	move_plan = {}
	f.remove_effect("heavy_fired")
	if f.on_board():
		# Drawn power is lost if not used on the activation after it was drawn.
		if f.statuses.get("drawn_power_used_window", false):
			f.statuses.erase("drawn_power")
			f.statuses.erase("drawn_power_used_window")
		elif f.statuses.get("drawn_power", false):
			f.statuses["drawn_power_used_window"] = true
		# Treasure carriers who took damage may drop it (p.36).
		if f.treasure > 0 and f.statuses.get("damaged_this_activation", false):
			var r := dice.d6()
			if r == 1:
				log_line("%s drops the treasure (rolled 1)." % f.name)
				Scenario.drop_treasure(self, f)
		Abilities.end_of_activation(self, f)
		Scenario.end_of_activation(self, f)
	for o in fighters:
		if o.statuses.get("damaged_this_activation", false) and o != f and o.treasure > 0 and o.on_board():
			var r2 := dice.d6()
			if r2 == 1:
				log_line("%s drops the treasure (rolled 1)." % o.name)
				Scenario.drop_treasure(self, o)
		o.statuses["damaged_this_activation"] = false
	log_line("%s's activation ends." % f.name)
	active = -1
	active_is_surge = false
	_undo.clear()
	if is_over():
		changed.emit()
		return ""
	turn = other(turn)
	_check_turn()
	return ""


## Winged Familiar: a harried fighter must pass a Willpower test for each Move or Action, or lose it.
func harried_check(f: FighterState, what: String) -> bool:
	if not f.has_effect("harried"):
		return true
	var t := dice.test(int(f.stats["willpower"]))
	mark_dice_rolled()
	if t["pass"]:
		log_line("%s shrugs off the harrying (rolled %d)." % [f.name, t["roll"]])
		return true
	log_line("%s is harried and loses their %s (rolled %d)." % [f.name, what, t["roll"]])
	if what == "move":
		f.moved = true
	else:
		f.acted = true
	changed.emit()
	return false


## Things resolved after each move or action: fighters near open platform edges may fall (p.16).
func after_action() -> void:
	Height.fall_checks(self)


# ---------------------------------------------------------------------------------------------
# Life

func heal(f: FighterState, amount: int, why := "") -> void:
	var before := f.life
	f.life = mini(f.max_life(), f.life + amount)
	if f.life > before:
		f.statuses.erase("poisoned")
		log_line("%s heals %d%s." % [f.name, f.life - before, (" (%s)" % why) if why != "" else ""])


# ---------------------------------------------------------------------------------------------
# Undo: only before any dice have been rolled in the current activation.

func _snapshot() -> void:
	_undo = [to_dict()]


func can_undo() -> bool:
	return not _undo.is_empty()


func mark_dice_rolled() -> void:
	_undo.clear()


func undo() -> void:
	if _undo.is_empty():
		return
	var d: Dictionary = _undo.pop_back()
	_restore(d)
	log_line("(Undone.)")
	changed.emit()


func to_dict() -> Dictionary:
	var fs: Array = []
	for f in fighters:
		fs.append(f.to_dict())
	var ts: Array = []
	for t in terrain:
		ts.append(t.to_dict())
	return {"cfg": cfg.duplicate(true), "board_size": board_size, "terrain": ts, "fighters": fs, "rosters": rosters.duplicate(true),
		"player_names": player_names.duplicate(), "underdog": underdog, "round_no": round_no, "priority": priority, "turn": turn,
		"active": active, "active_is_surge": active_is_surge, "phase": phase, "pending": pending.duplicate(true),
		"duel": duel.duplicate(true), "move_plan": move_plan.duplicate(true), "scen": scen.duplicate(true), "winner": winner,
		"result_text": result_text, "rng_seed": dice.rng.seed, "rng_state": dice.rng.state, "history": history.duplicate(),
		"tokens": tokens.duplicate(true), "next_uid": _next_uid}


func _restore(d: Dictionary) -> void:
	cfg = d["cfg"].duplicate(true)
	board_size = d["board_size"]
	terrain = []
	for t in d["terrain"]:
		terrain.append(TerrainPiece.from_dict(t))
	fighters = []
	for f in d["fighters"]:
		fighters.append(FighterState.from_dict(f))
	rosters = d["rosters"].duplicate(true)
	player_names = d["player_names"].duplicate()
	underdog = d["underdog"]
	round_no = d["round_no"]
	priority = d["priority"]
	turn = d["turn"]
	active = d["active"]
	active_is_surge = d["active_is_surge"]
	phase = d["phase"]
	pending = d["pending"].duplicate(true)
	duel = d["duel"].duplicate(true)
	move_plan = d["move_plan"].duplicate(true)
	scen = d["scen"].duplicate(true)
	winner = d["winner"]
	result_text = d["result_text"]
	dice.rng.seed = d["rng_seed"]
	dice.rng.state = d["rng_state"]
	history = d["history"].duplicate()
	tokens = d["tokens"].duplicate(true)
	_next_uid = d["next_uid"]


static func from_dict(d: Dictionary) -> Battle:
	var b := Battle.new()
	b._restore(d)
	return b


func save_to(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(var_to_str(to_dict()))
	return OK


static func load_from(path: String) -> Battle:
	var d = str_to_var(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return null
	return from_dict(d)
