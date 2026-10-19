class_name Roster
extends RefCounted
## A warband roster (Chapter 4, pp.49-51): faction, origin, fighters and their wargear.
## Each member: {"uid", "def", "name", "equipment": [ids], "skills": [ids], "signature_spells": [names], "option": id, "xp": int}

const STARTING_SILVER := 1000
const SAVE_DIR := "user://warbands/"

var name := "New Warband"
var faction := "guild_mercenaries"
var origin := ""
var members: Array = []
var _next_uid := 1


func add_member(def_id: String) -> Dictionary:
	var def := Catalog.fighter_def(faction, def_id)
	var m := {"uid": _next_uid, "def": def_id, "name": def.get("name", def_id), "equipment": [], "skills": [],
		"signature_spells": [], "option": "", "xp": 0}
	for s in def.get("starting_skills", []):
		m["skills"].append(s)
	_next_uid += 1
	members.append(m)
	return m


func remove_member(uid: int) -> void:
	for i in members.size():
		if members[i]["uid"] == uid:
			members.remove_at(i)
			return


func member(uid: int) -> Dictionary:
	for m in members:
		if m["uid"] == uid:
			return m
	return {}


func def_of(m: Dictionary) -> Dictionary:
	return Catalog.fighter_def(faction, m["def"])


func origin_def() -> Dictionary:
	return Catalog.origin(faction, origin)


## Silver spent on one fighter: recruit cost + mutation option + bought wargear (fixed wargear is included in the cost).
func member_cost(m: Dictionary) -> int:
	var def := def_of(m)
	var total: int = def.get("cost", 0)
	for o in def.get("options", []):
		if o["id"] == m.get("option", ""):
			total += int(o["cost"])
	for id in m["equipment"]:
		total += int(Catalog.wargear(faction, id).get("cost", 0))
	return total


func total_cost() -> int:
	var t := 0
	for m in members:
		t += member_cost(m)
	return t


func silver_left() -> int:
	return STARTING_SILVER - total_cost()


func rating() -> int:
	var t := total_cost()
	for m in members:
		t += int(m.get("xp", 0))
	return t


## Wargear the member may buy, by kind, from its wargear lists (p.50).
func allowed_wargear(m: Dictionary) -> Dictionary:
	var def := def_of(m)
	var out := {"melee": [], "ranged": [], "armour": [], "items": []}
	if def.get("exclusive_wargear", false):
		return out
	var lists: Dictionary = Catalog.faction(faction)["wargear_lists"]
	for ln in def.get("wargear_lists", []):
		for kind in out:
			for id in lists[ln][kind]:
				if not id in out[kind]:
					out[kind].append(id)
	return out


## All wargear the fighter carries: fixed + bought.
func carried(m: Dictionary) -> Array:
	var out: Array = []
	for id in def_of(m).get("fixed_wargear", []):
		out.append(id)
	out.append_array(m["equipment"])
	return out


func limit_for(def_id: String) -> int:
	var def := Catalog.fighter_def(faction, def_id)
	var lim = def.get("limit", null)
	var od := origin_def()
	for p in od.get("perks", []):
		if p.has("limit_override") and p["limit_override"].has(def_id):
			lim = p["limit_override"][def_id]
	return -1 if lim == null else int(lim)


func _category_exempt(def_id: String) -> bool:
	for p in origin_def().get("perks", []):
		if p.has("category_exempt") and p["category_exempt"].has(def_id):
			return true
	return false


## Every rule violation, as readable messages. Empty means the warband is legal.
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	if origin == "":
		errs.append("Pick an origin.")
	var od := origin_def()
	var counts := {"leader": 0, "champion": 0, "henchman": 0, "brute": 0, "beast": 0}
	var per_def := {}
	for m in members:
		var def := def_of(m)
		if def.is_empty():
			errs.append("Unknown fighter %s." % m["def"])
			continue
		if def.get("not_recruitable", false):
			errs.append("%s cannot be recruited." % def["name"])
		if not _category_exempt(m["def"]):
			counts[def["category"]] += 1
		per_def[m["def"]] = per_def.get(m["def"], 0) + 1
		errs.append_array(validate_member(m))
	var core: Dictionary = Catalog.core()["recruitment"]
	if counts["leader"] != 1:
		errs.append("A warband must have exactly 1 Leader (has %d)." % counts["leader"])
	if not od.is_empty():
		var leader_ok := false
		for m in members:
			if m["def"] == od["leader"]:
				leader_ok = true
		if not leader_ok:
			errs.append("The %s origin requires a %s as Leader." % [od["name"], Catalog.fighter_def(faction, od["leader"]).get("name", od["leader"])])
	if counts["champion"] > core["champions"][1]:
		errs.append("At most %d Champions (has %d)." % [core["champions"][1], counts["champion"]])
	if counts["henchman"] < core["henchmen_min"]:
		errs.append("At least %d Henchmen (has %d)." % [core["henchmen_min"], counts["henchman"]])
	if counts["brute"] > core["brutes"][1]:
		errs.append("At most %d Brutes (has %d)." % [core["brutes"][1], counts["brute"]])
	if counts["beast"] > core["beasts"][1]:
		errs.append("At most %d Beasts (has %d)." % [core["beasts"][1], counts["beast"]])
	if members.size() > core["max_fighters"]:
		errs.append("At most %d fighters (has %d)." % [core["max_fighters"], members.size()])
	for def_id in per_def:
		var lim := limit_for(def_id)
		if lim >= 0 and per_def[def_id] > lim:
			errs.append("At most %d %s (has %d)." % [lim, Catalog.fighter_def(faction, def_id)["name"], per_def[def_id]])
	# Rare wargear across the warband (p.30) and no duplicate skills (p.51).
	var rare_counts := {}
	var skill_owner := {}
	for m in members:
		for id in m["equipment"]:
			rare_counts[id] = rare_counts.get(id, 0) + 1
		for s in m["skills"]:
			if skill_owner.has(s):
				errs.append("Skill %s is on more than one fighter." % Catalog.skill(faction, s).get("name", s))
			skill_owner[s] = true
	for id in rare_counts:
		var lim := rare_limit(id)
		if lim >= 0 and rare_counts[id] > lim:
			errs.append("%s is Rare 0-%d (%d carried)." % [Catalog.wargear(faction, id).get("name", id), lim, rare_counts[id]])
	if silver_left() < 0:
		errs.append("Over budget by %d silver." % -silver_left())
	return errs


func rare_limit(id: String) -> int:
	var w := Catalog.wargear(faction, id)
	if w.get("rare", null) != null:
		return int(w["rare"])
	for t in w.get("traits", []):
		if (t as String).begins_with("Rare 0-"):
			return (t as String).trim_prefix("Rare 0-").to_int()
	return -1


## Carrying limits and list legality for one fighter (pp.13-15).
func validate_member(m: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var def := def_of(m)
	var nm: String = m.get("name", def.get("name", "?"))
	var allowed := allowed_wargear(m)
	var melee := 0
	var ranged := 0
	var armour := 0
	var items := 0
	var two_handed_melee := false
	var two_handed_ranged := false
	var held := false
	var full_plate := false
	var plate_forbidden := false
	for id in carried(m):
		var w := Catalog.wargear(faction, id)
		if w.is_empty():
			errs.append("%s: unknown wargear %s." % [nm, id])
			continue
		var traits: Array = w.get("traits", [])
		match w["kind"]:
			"melee":
				melee += 1
				if "Two-handed" in traits:
					two_handed_melee = true
			"ranged":
				ranged += 1
				if "Two-handed" in traits:
					two_handed_ranged = true
					plate_forbidden = plate_forbidden or id != "brace_of_pistols"
			"armour":
				armour += 1
				if id == "full_plate":
					full_plate = true
			"item":
				if w.get("held", false):
					melee += 1
					held = true
				else:
					items += 1
	for id in m["equipment"]:
		var w := Catalog.wargear(faction, id)
		var kind_key: String = {"melee": "melee", "ranged": "ranged", "armour": "armour", "item": "items"}.get(w.get("kind", ""), "")
		if kind_key != "" and not id in allowed[kind_key]:
			errs.append("%s cannot take %s." % [nm, w.get("name", id)])
		if w.has("requires") and not w["requires"] in carried(m):
			errs.append("%s: %s requires a %s." % [nm, w["name"], Catalog.wargear(faction, w["requires"]).get("name", w["requires"])])
	var lim: Dictionary = Catalog.core()["recruitment"]["carrying_limit"]
	if melee > lim["melee"]:
		errs.append("%s carries %d melee weapons/held items (max %d)." % [nm, melee, lim["melee"]])
	if ranged > lim["ranged"]:
		errs.append("%s carries %d ranged weapons (max 1)." % [nm, ranged])
	if armour > lim["armour"]:
		errs.append("%s wears %d sets of armour (max 1)." % [nm, armour])
	if items > lim["items"]:
		errs.append("%s carries %d items (max 2)." % [nm, items])
	var two_handed_count := 0
	for id in carried(m):
		var w := Catalog.wargear(faction, id)
		if w.get("kind", "") in ["melee", "ranged"] and "Two-handed" in w.get("traits", []):
			two_handed_count += 1
	if two_handed_count > 1:
		errs.append("%s carries more than one two-handed weapon." % nm)
	if held and two_handed_ranged:
		errs.append("%s cannot carry a held item with a two-handed ranged weapon." % nm)
	if full_plate and plate_forbidden:
		errs.append("%s in Full-Plate cannot carry two-handed ranged weapons (except a Brace of Pistols)." % nm)
	if m["skills"].size() > int(def.get("recruit_skills", 0)) + def.get("starting_skills", []).size():
		errs.append("%s has too many skills (%d allowed)." % [nm, int(def.get("recruit_skills", 0)) + def.get("starting_skills", []).size()])
	if m["signature_spells"].size() > int(def.get("signature_spells", 0)):
		errs.append("%s has too many signature spells." % nm)
	return errs


func to_dict() -> Dictionary:
	return {"version": 1, "name": name, "faction": faction, "origin": origin, "members": members.duplicate(true), "next_uid": _next_uid}


static func from_dict(d: Dictionary) -> Roster:
	var r := Roster.new()
	r.name = d.get("name", "Warband")
	r.faction = d["faction"]
	r.origin = d.get("origin", "")
	r.members = []
	for m in d["members"]:
		var mm: Dictionary = m.duplicate(true)
		mm["uid"] = int(mm["uid"])
		mm["xp"] = int(mm.get("xp", 0))
		r.members.append(mm)
	r._next_uid = int(d.get("next_uid", r.members.size() + 1))
	return r


func save() -> Error:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(SAVE_DIR + name.validate_filename() + ".json", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "  "))
	return OK


static func load_file(path: String) -> Roster:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return null
	return from_dict(data)


static func saved_paths() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(SAVE_DIR + f)
	return out
