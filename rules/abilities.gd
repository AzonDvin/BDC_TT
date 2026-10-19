class_name Abilities
extends RefCounted
## Bonus actions (any number per activation, p.19) and special actions from fighter scrolls, skills and items.
## list() tells the UI what the active fighter can use right now; use() performs it.
## needs: "none" | "enemy" | "friendly" | "point" | "spell"

static func list(b: Battle, f: FighterState) -> Array:
	var out: Array = []
	if f == null or f.uid != b.active or not f.on_board():
		return out
	var engaged := Effects.is_engaged(b, f)
	var can_act := b.can_still_act(f)
	var fresh := not f.moved and not f.acted
	var once := func(id): return not id in f.once_per_battle
	if f.has_rule("rallying_cry") and once.call("rallying_cry"):
		out.append({"id": "rallying_cry", "name": "Rallying Cry", "kind": "bonus", "needs": "none"})
	if f.has_rule("attack_attack") and once.call("attack_attack"):
		out.append({"id": "attack_attack", "name": "Attack! Attack!", "kind": "bonus", "needs": "none"})
	if f.has_rule("unholy_sermon") and once.call("unholy_sermon") and not engaged:
		out.append({"id": "unholy_sermon", "name": "Unholy Sermon", "kind": "bonus", "needs": "none"})
	if f.has_rule("death_march") and once.call("death_march"):
		out.append({"id": "death_march", "name": "Death March", "kind": "bonus", "needs": "none"})
	if f.has_rule("leech_blood") and once.call("leech_blood"):
		out.append({"id": "leech_blood", "name": "Leech Blood", "kind": "bonus", "needs": "none"})
	if f.has_rule("rite_of_contagion") and once.call("rite_of_contagion") and not engaged:
		out.append({"id": "rite_of_contagion", "name": "Rite of Contagion", "kind": "bonus", "needs": "none"})
	if f.has_rule("escape_artist") and once.call("escape_artist") and engaged:
		out.append({"id": "escape_artist", "name": "Escape Artist (2d6\")", "kind": "bonus", "needs": "point"})
	if f.has_item("smoke_bomb") and once.call("smoke_bomb") and engaged:
		out.append({"id": "smoke_bomb", "name": "Drop Smoke Bomb (6\")", "kind": "bonus", "needs": "point"})
	if f.has_rule("cloud_of_bats") and once.call("cloud_of_bats"):
		out.append({"id": "cloud_of_bats", "name": "Cloud of Bats (9\")", "kind": "bonus", "needs": "point"})
	if f.has_item("spirit_guardian") and once.call("spirit_guardian"):
		out.append({"id": "spirit_guardian", "name": "Invoke Ethereal Protection", "kind": "bonus", "needs": "none"})
	if f.has_item("winged_familiar") and once.call("winged_familiar"):
		out.append({"id": "winged_familiar", "name": "Winged Familiar: Harry", "kind": "bonus", "needs": "enemy"})
	if f.has_item("wooden_stakes") and once.call("wooden_stakes") and engaged:
		out.append({"id": "wooden_stakes", "name": "Drive the Stake", "kind": "bonus", "needs": "enemy"})
	if f.has_item("bomb_rat") and once.call("bomb_rat") and not engaged:
		out.append({"id": "bomb_rat", "name": "Set Up Bomb Rat", "kind": "bonus", "needs": "point"})
	if f.has_rule("mad_engineering") and int(f.statuses.get("engineering", 0)) > 0 and not engaged and not "engineer" in f.once_per_activation:
		out.append({"id": "engineer_patch", "name": "Engineer: Patch-up (%d pts)" % f.statuses["engineering"], "kind": "bonus", "needs": "friendly"})
		out.append({"id": "engineer_soup", "name": "Engineer: Soup-up (%d pts)" % f.statuses["engineering"], "kind": "bonus", "needs": "friendly"})
	if int(f.statuses.get("witchfire", 0)) > 0 and not "witchfire" in f.once_per_activation:
		out.append({"id": "witchfire", "name": "Witchfire Attack (%d)" % f.statuses["witchfire"], "kind": "bonus", "needs": "none"})
	if f.has_rule("bestial_transformation") and once.call("bestial_transformation") and fresh:
		out.append({"id": "transform", "name": "Bestial Transformation", "kind": "bonus", "needs": "none"})
	if can_act:
		if f.has_rule("recite_holy_litanies") and once.call("recite_holy_litanies"):
			out.append({"id": "recite_holy_litanies", "name": "Recite Holy Litanies", "kind": "action", "needs": "enemy"})
		if f.has_rule("patch_you_up"):
			out.append({"id": "patch_you_up", "name": "Patch You Up", "kind": "action", "needs": "friendly"})
		if f.has_item("cauldron"):
			out.append({"id": "cauldron", "name": "Use the Cauldron", "kind": "action", "needs": "spell"})
		if b.scen.get("twist_id", "") == "the_saints_sarcophagus" and not b.scen.get("lid_off", false) and not engaged and f.category != "beast":
			for t in b.terrain:
				if t.name == "Sarcophagus" and Geo.base_overlaps_polygon(f.pos, f.radius + 0.1, t.polygon):
					out.append({"id": "pry_lid", "name": "Pry off the Sarcophagus Lid", "kind": "action", "needs": "none"})
	return out


static func use(b: Battle, id: String, params := {}) -> String:
	var f := b.active_fighter()
	var avail := false
	var entry := {}
	for a in list(b, f):
		if a["id"] == id:
			avail = true
			entry = a
	if not avail:
		return "That ability isn't available now."
	var target: FighterState = b.fighter(int(params.get("target", -1))) if params.has("target") else null
	if entry["needs"] in ["enemy", "friendly"] and target == null:
		return "Pick a target."
	if entry["needs"] == "point" and not params.has("point"):
		return "Pick a point."
	if entry["kind"] == "action":
		f.acted = true
	b.mark_dice_rolled()
	match id:
		"rallying_cry":
			f.once_per_battle.append(id)
			b.heal(f, 1, "Rallying Cry")
			b.scen["rallying_cry_" + str(f.player)] = true
			b.log_line("%s's Rallying Cry: no Flee test for %s this round if they remain on the battlefield." % [f.name, b.player_names[f.player]])
		"attack_attack", "unholy_sermon", "death_march":
			f.once_per_battle.append(id)
			var radius: float = {"attack_attack": 9.0, "unholy_sermon": 6.0, "death_march": 9.0}[id]
			f.add_effect({"id": "aura_" + id, "until": "round", "radius": radius})
			b.log_line("%s uses %s (%.0f\" aura until the end of the round)." % [f.name, entry["name"], radius])
		"leech_blood":
			f.once_per_battle.append(id)
			for o in b.on_board(b.other(f.player)):
				if Geo.within(f.pos, f.radius, o.pos, o.radius, 9.0) and not b.dice.test(int(o.stats["willpower"]))["pass"]:
					Combat.apply_damage(b, o, 1, f, "Leech Blood")
					b.heal(f, 1, "Leech Blood")
		"rite_of_contagion":
			f.once_per_battle.append(id)
			for o in b.on_board(b.other(f.player)):
				if Geo.within(f.pos, f.radius, o.pos, o.radius, 12.0) and not b.dice.test(int(o.stats["willpower"]))["pass"]:
					Combat.apply_damage(b, o, 1, f, "Rite of Contagion")
					if o.on_board() and o.can_be_poisoned():
						o.statuses["poisoned"] = true
					b.log_line("%s is struck by the Rite of Contagion." % o.name)
		"escape_artist", "smoke_bomb", "cloud_of_bats":
			var reach := 6.0 if id == "smoke_bomb" else (9.0 if id == "cloud_of_bats" else float(b.dice.d6() + b.dice.d6()))
			var pt: Vector2 = params["point"]
			if f.pos.distance_to(pt) + f.radius > reach + f.radius + Geo.EPS:
				return "Must be set up wholly within %.0f\"." % reach
			var probe_err := Magic._placement_ok(b, f, pt)
			if probe_err != "":
				return probe_err
			f.once_per_battle.append(id)
			f.pos = pt
			b.log_line("%s uses %s and reappears elsewhere%s." % [f.name, entry["name"], (" (rolled %.0f\")" % reach) if id == "escape_artist" else ""])
		"spirit_guardian":
			f.once_per_battle.append(id)
			f.add_effect({"id": "spirit_guardian", "until": "round"})
			b.log_line("%s is shielded by ethereal protection (ignores Rend this round)." % f.name)
		"winged_familiar":
			if target.player == f.player or not Geo.within(f.pos, f.radius, target.pos, target.radius, 24.0) or not Effects.visibility(b, f, target)["visible"]:
				return "Pick a visible enemy within 24\"."
			f.once_per_battle.append(id)
			target.add_effect({"id": "harried", "until": "round"})
			b.log_line("%s is harried by a winged familiar (Willpower test for each Move or Action — resolve on the table)." % target.name)
		"wooden_stakes":
			if not target in Effects.engaged_enemies(b, f) or not (target.has_kw("Demon") or target.has_kw("Undead")) or not target.is_bloodied():
				return "The target must be an engaged, bloodied Demon or Undead."
			f.once_per_battle.append(id)
			var r := b.dice.d6()
			b.log_line("%s drives a stake at %s (rolled %d)." % [f.name, target.name, r])
			if r >= 2:
				Combat.take_down(b, target, f, "Wooden Stake")
		"bomb_rat":
			var pt2: Vector2 = params["point"]
			if not Geo.within(f.pos, f.radius, pt2, 0.5, 3.0):
				return "The Bomb Rat must be set up within 3\"."
			var rat := Magic.summon(b, f, "giant_rat", pt2)
			if rat == null:
				return "No room for the Bomb Rat."
			f.once_per_battle.append(id)
			rat.name = "Bomb Rat"
			rat.statuses["fuse"] = clampi(int(params.get("fuse", 3)), 1, 6)
			rat.activated = false
			b.log_line("%s releases a Bomb Rat with a fuse of %d." % [f.name, rat.statuses["fuse"]])
		"engineer_patch", "engineer_soup":
			if target.player != f.player or not Geo.within(f.pos, f.radius, target.pos, target.radius, 1.0) or Effects.is_engaged(b, target):
				return "Pick a friendly fighter within 1\" that isn't engaged."
			f.statuses["engineering"] = int(f.statuses["engineering"]) - 1
			f.once_per_activation.append("engineer")
			if id == "engineer_patch":
				if target.has_kw("Contraption"):
					b.heal(target, b.dice.d3(), "Patch-up")
			else:
				var rw := target.usable_ranged()
				if rw.is_empty():
					return "That fighter has no ranged weapon."
				target.add_effect({"id": "souped_up", "until": "round", "weapon": rw[0]["id"]})
				b.log_line("%s's %s is souped-up (Rend +1, misfires backfire)." % [target.name, rw[0]["name"]])
		"witchfire":
			return Magic.witchfire_attack(b)
		"transform":
			f.once_per_battle.append("bestial_transformation")
			transform(b, f, true)
		"recite_holy_litanies":
			if target.player == f.player or not (target.is_caster() or target.has_kw("Demon") or target.has_kw("Undead")):
				return "Target a Wizard, Priest, Demon or Undead enemy."
			if not Geo.within(f.pos, f.radius, target.pos, target.radius, 12.0) or not Effects.visibility(b, f, target)["visible"]:
				return "The target must be visible and within 12\"."
			f.once_per_battle.append(id)
			var ra := b.dice.d6() + int(f.stats["willpower"])
			var rd := b.dice.d6() + int(target.stats["willpower"])
			b.log_line("%s recites holy litanies at %s: %d vs %d." % [f.name, target.name, ra, rd])
			if ra >= rd:
				Combat.apply_damage(b, target, b.dice.d3(), f, "Holy Litanies")
		"patch_you_up":
			if target.player != f.player or not Geo.within(f.pos, f.radius, target.pos, target.radius, 1.0):
				return "Pick a friendly fighter within 1\"."
			var t := b.dice.test(int(f.stats["willpower"]))
			if t["pass"]:
				b.heal(target, 1, "Patch You Up")
			else:
				b.log_line("%s fumbles the bandages (rolled %d)." % [f.name, t["roll"]])
		"cauldron":
			var t2 := b.dice.test(int(f.stats["willpower"]))
			if not t2["pass"]:
				b.log_line("The cauldron's brew fails (rolled %d)." % t2["roll"])
			else:
				var wanted: String = params.get("spell", "")
				for lore_id in f.lores:
					for s in Catalog.lore(f.faction, lore_id)["spells"]:
						if s["name"] == wanted:
							var names: PackedStringArray = []
							Magic._add_prepared(f, s, lore_id, names)
							b.log_line("%s prepares %s from the cauldron." % [f.name, wanted])
		"pry_lid":
			var tries: int = b.scen.get("lid_tries_round", {}).get(str(b.round_no) + ":" + str(f.player), 0)
			var r2 := b.dice.d6() + tries
			var key := str(b.round_no) + ":" + str(f.player)
			var lt: Dictionary = b.scen.get("lid_tries_round", {})
			lt[key] = tries + 1
			b.scen["lid_tries_round"] = lt
			if r2 >= 6:
				b.scen["lid_off"] = true
				var res := b.dice.d6()
				b.log_line("%s pries off the lid (rolled %d)! Contents (%d): %s" % [f.name, r2, res, ["", "Unholy Curse", "Rotten Black Mulch", "Rotten Black Mulch", "Rotten Black Mulch", "Coin Purse", "Heirloom"][res]])
				if res == 1:
					if not (f.has_kw("Demon") or f.has_kw("Undead")):
						Combat.apply_damage(b, f, b.dice.d6(), null, "Unholy Curse")
					for o in b.on_board():
						if o != f and Scenario.in_chapel(b, o.pos) and not (o.has_kw("Demon") or o.has_kw("Undead")) and not b.dice.test(int(o.stats["willpower"]))["pass"]:
							Combat.apply_damage(b, o, b.dice.d6(), null, "Unholy Curse")
				elif res == 5 and f.on_board():
					if f.treasure > 0:
						Scenario.drop_treasure(b, f)
					f.treasure = 1
			else:
				b.log_line("%s fails to pry off the lid (rolled %d)." % [f.name, r2])
	b.changed.emit()
	return ""


## Lycanfell Noble <-> Lycanfell Beast. Damage carries over both ways.
static func transform(b: Battle, f: FighterState, to_beast: bool) -> void:
	if to_beast:
		f.statuses["noble_form"] = {"def_id": f.def_id, "name": f.name, "stats": f.stats.duplicate(), "keywords": f.keywords,
			"melee": f.melee.duplicate(true), "ranged": f.ranged.duplicate(true), "items": f.items, "skills": f.skills, "special": f.special, "armour_id": f.armour_id}
		var damage := f.max_life() - f.life
		var beast := Catalog.fighter_def(f.faction, "lycanfell_beast")
		f.def_id = "lycanfell_beast"
		f.name = f.name + " (Beast)"
		f.stats = beast["stats"].duplicate()
		f.keywords = PackedStringArray(beast["keywords"])
		f.melee = [Catalog.wargear(f.faction, "wulfen_claws")]
		f.ranged = []
		f.items = PackedStringArray()
		f.skills = PackedStringArray()
		f.armour_id = ""
		f.special = PackedStringArray(["temperamental_transformation", "vestiges_of_the_noble"])
		f.life = maxi(1, int(f.stats["life"]) - damage)
		f.effects = []
		b.log_line("%s transforms into the Lycanfell Beast!" % f.statuses["noble_form"]["name"])
	else:
		var nf: Dictionary = f.statuses["noble_form"]
		var damage2 := f.max_life() - f.life
		for k in ["def_id", "name", "stats", "keywords", "melee", "ranged", "items", "skills", "special", "armour_id"]:
			f.set(k, nf[k])
		f.statuses.erase("noble_form")
		f.life = int(f.stats["life"]) - damage2
		b.log_line("The transformation ends; %s returns to noble form." % f.name)
		if f.life <= 0:
			f.life = 1
			Combat.take_down(b, f, null, "the transformation")


## Start-of-activation hooks for abilities: Bomb Rat fuses.
static func start_of_activation(b: Battle, f: FighterState) -> bool:
	if f.statuses.has("fuse"):
		var r := b.dice.d6()
		var fuse := int(f.statuses["fuse"])
		if r > fuse:
			b.log_line("The Bomb Rat's fuse burns out (rolled %d > %d): BOOM!" % [r, fuse])
			detonate_bomb_rat(b, f)
			return false
		f.statuses["fuse"] = maxi(1, fuse - 1)
		b.log_line("The Bomb Rat scurries on (rolled %d, fuse now %d)." % [r, f.statuses["fuse"]])
	return true


static func detonate_bomb_rat(b: Battle, rat: FighterState) -> void:
	var profile := {"name": "Bomb Rat", "rend": -2, "damage": "d3", "crit": null, "traits": [], "kind": "special"}
	for o in Combat.blast_hits(b, rat.pos):
		if o != rat:
			Combat.resolve_hit(b, rat, o, profile, false, {"melee": false, "rend": -2})
	rat.where = "down"
	rat.statuses.clear()


## End-of-activation hooks: the Lycanfell Beast must pass a Willpower test or revert.
static func end_of_activation(b: Battle, f: FighterState) -> void:
	if f.on_board() and f.statuses.has("noble_form"):
		var t := b.dice.test(int(f.stats["willpower"]))
		if not t["pass"]:
			b.log_line("The beast's rage subsides (rolled %d)." % t["roll"])
			transform(b, f, false)
