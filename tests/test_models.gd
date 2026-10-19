extends "res://tests/test_case.gd"
## Fighter figures from the KayKit Adventurers pack: who gets which character, weapons in hand, animations,
## the pill fallback, and the death animation on the board.

const H := preload("res://tests/helpers.gd")
const GM := "guild_mercenaries"


func _weapon_in(model: Node3D, side: String) -> String:
	for att in model.find_children("*", "BoneAttachment3D", true, false):
		if (att as BoneAttachment3D).bone_name == "handslot." + side and att.get_child_count() > 0:
			return String(att.get_child(0).name)
	return ""


func test_roles_pick_characters() -> void:
	var b := H.bare_battle()
	assert_eq(FighterModels.character_for(H.add(b, GM, "guild_wizard", 0, Vector2(5, 5), ["arcane_staff"])), "Mage")
	assert_eq(FighterModels.character_for(H.add(b, GM, "guild_captain", 0, Vector2(8, 5), ["sword"])), "Knight")
	assert_eq(FighterModels.character_for(H.add(b, GM, "guild_champion", 0, Vector2(11, 5), ["sword"])), "Barbarian")
	assert_eq(FighterModels.character_for(H.add(b, GM, "guild_mercenary", 0, Vector2(14, 5), ["sword", "crossbow"])), "Ranger")
	assert_true(FighterModels.character_for(H.add(b, GM, "guild_mercenary", 0, Vector2(17, 5), ["sword"])) in ["Rogue", "Rogue_Hooded"])
	assert_eq(FighterModels.character_for(H.add(b, GM, "hunting_dog", 0, Vector2(20, 5))), "Husky" if ResourceLoader.exists(FighterModels.ANIMALS + "Husky.gltf") else "")


func test_models_hold_their_weapons_and_idle() -> void:
	if not FighterModels.available():
		return
	var b := H.bare_battle()
	var knight := H.add(b, GM, "guild_captain", 0, Vector2(5, 5), ["sword", "shield"])
	var m := FighterModels.build(knight)
	assert_true(m != null)
	assert_true(_weapon_in(m, "r").begins_with("sword_1handed"), "sword in the right hand: %s" % _weapon_in(m, "r"))
	assert_true(_weapon_in(m, "l").begins_with("shield"), "shield in the left hand")
	var p: AnimationPlayer = m.get_node("Anim")
	assert_eq(String(p.current_animation), "Idle_A")
	assert_eq(p.get_animation("Walking_A").loop_mode, Animation.LOOP_LINEAR, "walking loops")
	assert_true(p.has_animation("Death_A") and p.has_animation("Hit_A"))
	assert_approx(m.scale.y, knight.height / FighterModels.MODEL_HEIGHT, 0.001, "scaled to the fighter's height")
	var archer := H.add(b, GM, "guild_mercenary", 0, Vector2(8, 5), ["sword", "long_bow"])
	var am := FighterModels.build(archer)
	assert_true(_weapon_in(am, "l").begins_with("bow"), "a bow is held in the left hand")
	assert_eq(_weapon_in(am, "r"), "", "and nothing else")
	m.free()
	am.free()


func test_board_uses_models_and_plays_death() -> void:
	if not FighterModels.available():
		return
	var b := H.bare_battle()
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(10, 10), ["sword"])
	var dog := H.add(b, GM, "hunting_dog", 0, Vector2(14, 10))
	var board := Board3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(board)
	board.build(b)
	board.sync()
	var n: Node3D = board.fighter_nodes[f.uid]
	assert_true(n.get_node_or_null("Model") != null, "the mercenary is a model")
	var dm: Node3D = board.fighter_nodes[dog.uid].get_node_or_null("Model")
	if FighterModels.character_for(dog) != "":
		assert_true(dm != null and FighterModels.player_of(dm) != null, "the dog is a creature with its own animations")
	f.where = "down"
	board.sync()
	assert_true(n.visible, "still shown while the death animation plays")
	assert_eq(String((n.get_node("Model/Anim") as AnimationPlayer).current_animation), "Death_A")
	board.queue_free()


func test_attack_clips_follow_the_weapon() -> void:
	var b := H.bare_battle()
	var sw := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 5), ["sword"])
	var zw := H.add(b, GM, "guild_mercenary", 0, Vector2(8, 5), ["zweihander"])
	var dual := H.add(b, GM, "guild_mercenary", 0, Vector2(11, 5), ["dagger", "dagger"])
	var bow := H.add(b, GM, "guild_mercenary", 0, Vector2(14, 5), ["sword", "long_bow"])
	var xb := H.add(b, GM, "guild_mercenary", 0, Vector2(17, 5), ["sword", "crossbow"])
	var pistol := H.add(b, GM, "guild_mercenary", 0, Vector2(20, 5), ["sword", "blackpowder_pistol"])
	var sling := H.add(b, "verminkin", "verminkin_warrior", 0, Vector2(23, 5), ["sword", "sling"])
	assert_eq(FighterModels.clip_group(sw, "melee", "Sword"), "melee_1h")
	assert_eq(FighterModels.clip_group(zw, "melee", "Zweihander"), "melee_2h")
	assert_eq(FighterModels.clip_group(dual, "melee", "Dagger"), "melee_dual")
	assert_eq(FighterModels.clip_group(bow, "shoot", "Long Bow"), "shoot_bow")
	assert_eq(FighterModels.clip_group(xb, "shoot", "Crossbow"), "shoot_2h")
	assert_eq(FighterModels.clip_group(xb, "reload"), "reload_2h")
	assert_eq(FighterModels.clip_group(pistol, "shoot", "Blackpowder Pistol"), "shoot_1h")
	assert_eq(FighterModels.clip_group(sling, "shoot", "Sling"), "throw")
	assert_eq(FighterModels.run_clip(bow), "Running_HoldingBow" if FighterModels.library().has_animation("Running_HoldingBow") else "Running_A")


func test_animation_pack_clips_are_loaded_when_present() -> void:
	if not DirAccess.dir_exists_absolute(FighterModels.EXTRA_ANIMS):
		return
	var lib := FighterModels.library()
	for group in FighterModels.CLIPS:
		for nm in FighterModels.CLIPS[group]:
			assert_true(lib.has_animation(nm), "%s (%s)" % [nm, group])
	assert_false(lib.has_animation("Fishing_Cast"), "tool and leisure clips aren't loaded")


const DC := "death_covens"


func test_undead_get_skeleton_figures() -> void:
	if not FighterModels.skeletons_available():
		return
	var b := H.bare_battle()
	var lord := H.add(b, DC, "barrow_lord", 0, Vector2(5, 5), ["sword", "shield"])
	var zombie := H.add(b, DC, "zombie", 0, Vector2(8, 5))
	var ogre := H.add(b, DC, "zombie_ogre", 0, Vector2(11, 5), ["ogre_mace"])
	var necro := H.add(b, DC, "necromancer", 0, Vector2(14, 5), ["arcane_staff"])
	var gargoyle := H.add(b, DC, "gargoyle", 0, Vector2(17, 5))
	assert_eq(FighterModels.character_for(lord), "Skeleton_Warrior")
	assert_eq(FighterModels.character_for(zombie), "Skeleton_Minion")
	assert_true(FighterModels.look_for(zombie)["zombie"], "zombies shamble and are tinted green")
	assert_eq(FighterModels.character_for(ogre), "Giant" if ResourceLoader.exists(FighterModels.GIANT) else "Skeleton_Warrior", "the Zombie Ogre is a green Giant")
	assert_eq(FighterModels.character_for(necro), "Mage", "a human Necromancer stays a human Mage")
	for vamp in ["bloodcursed_noble", "bloodcursed_knight", "bloodcursed_courtesan", "misbegotten"]:
		assert_eq(FighterModels.character_for(H.add(b, DC, vamp, 0, Vector2(5, 20), ["cursed_blade"])), "Skeleton_Mage", vamp)
	var contraption := H.add(b, "verminkin", "rolling_contraption", 0, Vector2(5, 24))
	assert_eq(FighterModels.character_for(contraption), "Skeleton_Warrior", "brutes without a creature model are golem-like Skeleton Warriors")
	assert_eq(FighterModels.look_for(contraption)["tint"], FighterModels.STONE_TINT)
	assert_eq(FighterModels.look_for(ogre)["tint"], FighterModels.ZOMBIE_TINT, "the Zombie Ogre is zombie green")
	for vamp in ["bloodcursed_noble", "bloodcursed_knight", "bloodcursed_courtesan", "misbegotten"]:
		assert_eq(FighterModels.character_for(H.add(b, DC, vamp, 0, Vector2(5, 20), ["cursed_blade"])), "Skeleton_Mage", vamp)
	assert_eq(FighterModels.character_for(gargoyle), "Goleling_Evolved" if ResourceLoader.exists(FighterModels.MONSTERS + "Goleling_Evolved.glb") else "")
	for i in 4:
		var sk := H.add(b, DC, "skeleton_warrior", 0, Vector2(20 + i * 2, 5), ["sword"])
		assert_true(FighterModels.character_for(sk) in ["Skeleton_Warrior", "Skeleton_Minion"])
	var m := FighterModels.build(lord)
	assert_true(_weapon_in(m, "r").begins_with("Skeleton_Blade"), "skeletons carry bone weapons: %s" % _weapon_in(m, "r"))
	assert_true(_weapon_in(m, "l").begins_with("Skeleton_Shield"))
	assert_eq(String((m.get_node("Anim") as AnimationPlayer).current_animation), FighterModels.idle_clip(m))
	assert_eq(FighterModels.death_clip(m), "Skeletons_Death" if FighterModels.library().has_animation("Skeletons_Death") else "Death_A")
	m.free()


func test_lycanfell_figure_swaps_when_it_transforms() -> void:
	if not FighterModels.available():
		return
	var b := H.bare_battle()
	var noble := H.add(b, DC, "lycanfell_noble", 0, Vector2(10, 10), ["sword"])
	var board := Board3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(board)
	board.build(b)
	board.sync()
	var before: Node3D = board.fighter_nodes[noble.uid]
	assert_eq(FighterModels.character_for(noble), "Knight")
	Abilities.transform(b, noble, true)
	board.sync()
	assert_true(board.fighter_nodes[noble.uid] != before, "a new figure after the transformation")
	assert_eq(FighterModels.character_for(noble), "Barbarian", "the beast is the fur-tinted Barbarian")
	Abilities.transform(b, noble, false)
	board.sync()
	assert_eq(FighterModels.character_for(noble), "Knight", "and back to the noble")
	board.queue_free()



func test_creatures_use_their_own_animations() -> void:
	if not ResourceLoader.exists(FighterModels.MONSTERS + "Orc.glb"):
		return
	var b := H.bare_battle()
	var cases := [["blighted_cloister", "rot_demon", "Demon-LnfIziKv4o"], ["blighted_cloister", "bloat_fly", "Armabee"],
		["blighted_cloister", "demonic_rotspawn", "Green_Spiky_Blob"], ["guild_mercenaries", "mercenary_ogre", "Giant"], ["blighted_cloister", "darkcloven_beastman", "Orc"],
		["death_covens", "dire_wolf", "Wolf"], ["verminkin", "giant_rat", "Rat"]]
	for c in cases:
		var f := H.add(b, c[0], c[1], 0, Vector2(5, 5))
		assert_eq(FighterModels.character_for(f), c[2], c[1])
		var m := FighterModels.build(f)
		assert_true(m != null, c[1])
		var p := FighterModels.player_of(m)
		assert_true(p != null, "%s has an animation player" % c[1])
		for role in ["idle", "attack", "death"]:
			assert_true(FighterModels._creature_role(m, role) != "", "%s has a %s clip" % [c[1], role])
		assert_eq(String(p.current_animation), FighterModels.idle_clip(m), "%s idles" % c[1])
		assert_true(FighterModels.play_attack(m, f, "melee"), "%s attacks with its own clip" % c[1])
		m.free()
