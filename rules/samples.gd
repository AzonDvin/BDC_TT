class_name Samples
extends RefCounted
## Ready-made legal warbands (under 1000 silver) for quick battles and tests.

const LISTS := {
	"guild_mercenaries": {"name": "Hauptmann Wolfram's Company", "origin": "swords_for_hire", "members": [
		["guild_captain", "Wolfram", ["sword", "shield", "cuirass"], ["feint", "stand_ground"], []],
		["guild_champion", "Anton", ["zweihander", "cuirass"], ["duellist"], []],
		["guild_wizard", "Erasmus", ["arcane_staff"], [], ["Arcane Missile"]],
		["guild_mercenary", "Hans", ["sword", "crossbow"], [], []],
		["guild_mercenary", "Georg", ["sword", "crossbow"], [], []],
		["guild_mercenary", "Otto", ["spear", "shield"], [], []],
		["guild_mercenary", "Kaspar", ["spear", "shield"], [], []],
		["guild_recruit", "Jakob", ["dagger"], [], []],
		["guild_recruit", "Lorenz", ["dagger"], [], []],
		["hunting_dog", "Rex", [], [], []],
	]},
	"verminkin": {"name": "Clan Gnashrik", "origin": "merciless_tyrant", "members": [
		["ironfang_warlord", "Gnashrik", ["sword", "shield"], ["dirty_fighter", "ambush"], []],
		["verminkin_champion", "Skrott", ["halberd"], ["back_stabber"], []],
		["verminkin_warlock", "Vritch", ["arcane_staff"], [], ["Chain Lightning"]],
		["verminkin_warrior", "Snikk", ["sword", "sling"], [], []],
		["verminkin_warrior", "Pilfrik", ["sword", "sling"], [], []],
		["verminkin_warrior", "Kratzik", ["sword", "sling"], [], []],
		["verminkin_warrior", "Skrik", ["club", "dagger"], [], []],
		["verminkin_warrior", "Huzzik", ["club", "dagger"], [], []],
		["verminkin_warrior", "Tik-Tik", ["club", "dagger"], [], []],
		["giant_rat", "Gnaw", [], [], []],
		["giant_rat", "Nibble", [], [], []],
		["rat_mutant", "Bruzzik", [], [], []],
	]},
	"death_covens": {"name": "The Embalmer's Court", "origin": "rogue_necromancer", "members": [
		["necromancer", "Mausar", ["arcane_staff"], [], ["Death Blast", "Raise Zombie"]],
		["barrow_champion", "Ossrik", ["sword", "shield", "cuirass"], ["chill_touch"], []],
		["bloodcursed_knight", "Strigor", ["cursed_blade"], ["relentless_attacker"], []],
		["skeleton_warrior", "Bones I", ["spear", "shield", "cuirass"], [], []],
		["skeleton_warrior", "Bones II", ["spear", "shield", "cuirass"], [], []],
		["skeleton_warrior", "Bones III", ["sword", "shield"], [], []],
		["skeleton_warrior", "Bones IV", ["sword", "shield"], [], []],
		["zombie", "Shambler", [], [], []],
		["zombie", "Rotgut", [], [], []],
		["zombie", "Moaner", [], [], []],
		["dire_wolf", "Grey Maw", [], [], []],
	]},
	"blighted_cloister": {"name": "The Knights of the Ninth Sore", "origin": "knights_militant", "members": [
		["knight_abbot", "Pestor", ["great_demonic_rot_blade"], ["unholy_sermon", "infested_with_maggots"], []],
		["cloister_sorcerer", "Malach", ["arcane_staff"], [], ["Black Bile"]],
		["cloister_knight", "Severin", ["sword", "shield"], [], []],
		["cloister_knight", "Dismas", ["sword", "shield"], [], []],
		["dreg_cultist", "Pusian", ["club", "blowpipe"], [], []],
		["dreg_cultist", "Raban", ["club", "blowpipe"], [], []],
		["dreg_cultist", "Silvan", ["club", "blowpipe"], [], []],
		["dreg_cultist", "Tertius", ["club", "blowpipe"], [], []],
		["rotling", "Wretch", [], [], []],
	]},
}


static func roster(faction: String) -> Roster:
	var spec: Dictionary = LISTS[faction]
	var r := Roster.new()
	r.faction = faction
	r.name = spec["name"]
	r.origin = spec["origin"]
	for row in spec["members"]:
		var m := r.add_member(row[0])
		m["name"] = row[1]
		m["equipment"] = row[2].duplicate()
		for s in row[3]:
			if not s in m["skills"]:
				m["skills"].append(s)
		m["signature_spells"] = row[4].duplicate()
	return r
